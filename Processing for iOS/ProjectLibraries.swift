import Foundation

/// An ordered list of local classic-script bundles, kept with the project.
enum ProjectLibraries {
    private static let manifest = ".processing-libraries.json"
    private static let maximumBytes = 16_000_000

    private static func validate(_ paths: [String]) throws {
        guard paths.count <= 32, Set(paths).count == paths.count else {
            throw ProjectFileError(message: "Use at most 32 different JavaScript libraries in a project.")
        }
        for path in paths {
            let parts = path.split(separator: "/", omittingEmptySubsequences: false)
            guard parts.count == 2, parts[0] == "libraries",
                  (path as NSString).pathExtension.lowercased() == "js" else {
                throw ProjectFileError(message: "Invalid library path “\(path)”. Libraries must be .js files inside libraries/.")
            }
            try ProjectFiles.validateName(String(parts[1]))
        }
    }

    private static func pathsUncoordinated(in folder: URL) throws -> [String] {
        let url = folder.appendingPathComponent(manifest)
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        guard url.resolvingSymlinksInPath().path == folder.resolvingSymlinksInPath().appendingPathComponent(manifest).path else {
            throw ProjectFileError(message: "The library list must be inside this project.")
        }
        guard (try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0) <= 65_536 else {
            throw ProjectFileError(message: "The project's library list is too large. Use an array of at most 32 library paths.")
        }
        let paths: [String]
        do { paths = try JSONDecoder().decode([String].self, from: Data(contentsOf: url)) }
        catch { throw ProjectFileError(message: "Cannot read the project's library list. It must contain an ordered JSON array of library paths. \(error.localizedDescription)") }
        try validate(paths)
        return paths
    }

    static func paths(in project: SimpleTextProject) throws -> [String] {
        try ProjectFiles.read(project.folder) { try pathsUncoordinated(in: $0) }
    }

    private static func fileURL(_ path: String, in folder: URL) throws -> URL {
        try validate([path])
        let url = folder.appendingPathComponent(path)
        guard url.resolvingSymlinksInPath().path == folder.resolvingSymlinksInPath().appendingPathComponent(path).path else {
            throw ProjectFileError(message: "“\(path)” must be a file inside this project, not a symbolic link.")
        }
        return url
    }

    private static func code(at url: URL) throws -> String {
        let size = try url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
        guard size.isRegularFile == true, (size.fileSize ?? 0) <= maximumBytes else {
            throw ProjectFileError(message: "Choose a JavaScript file smaller than 16 MB.")
        }
        let data = try Data(contentsOf: url)
        guard data.count <= maximumBytes, let text = String(data: data, encoding: .utf8) else {
            throw ProjectFileError(message: "“\(url.lastPathComponent)” must be UTF-8 JavaScript smaller than 16 MB.")
        }
        return text
    }

    static func sources(in project: SimpleTextProject) throws -> [SketchSource] {
        guard project.sourceCodeExtension == "js" else { return [] }
        return try ProjectFiles.read(project.folder) { folder in
            var totalBytes = 0
            let sources = try pathsUncoordinated(in: folder).map { path -> SketchSource in
                do {
                    let text = try code(at: fileURL(path, in: folder))
                    totalBytes += text.utf8.count
                    guard totalBytes <= maximumBytes else {
                        throw ProjectFileError(message: "The project's JavaScript libraries exceed 16 MB. Exclude unused libraries.")
                    }
                    return SketchSource(name: path, content: text, firstLine: 1)
                } catch {
                    throw ProjectFileError(message: "Cannot load \(path). \(error.localizedDescription) Open Tools → JavaScript Libraries to fix the file or exclude it.")
                }
            }
            return sources
        }
    }

    static func source(_ path: String, in project: SimpleTextProject) throws -> String {
        try ProjectFiles.read(project.folder) { try code(at: fileURL(path, in: $0)) }
    }

    private static func save(_ paths: [String], folder: URL) throws {
        try validate(paths)
        try JSONEncoder().encode(paths).write(to: folder.appendingPathComponent(manifest), options: .atomic)
    }

    static func reorder(_ paths: [String], in project: SimpleTextProject) throws {
        try ProjectFiles.write(project.folder, options: []) { folder in
            let existing = try pathsUncoordinated(in: folder)
            guard Set(existing) == Set(paths), existing.count == paths.count else {
                throw ProjectFileError(message: "The library list changed elsewhere. Reopen it before changing the order.")
            }
            try save(paths, folder: folder)
        }
    }

    /// Excluding a library never deletes its source; it can be imported again.
    static func exclude(_ path: String, from project: SimpleTextProject) throws {
        try ProjectFiles.write(project.folder, options: []) { folder in
            try save(pathsUncoordinated(in: folder).filter { $0 != path }, folder: folder)
        }
    }

    static func add(_ urls: [URL], to project: SimpleTextProject) throws {
        guard project.sourceCodeExtension == "js" else {
            throw ProjectFileError(message: "JavaScript libraries require a p5.js project.")
        }
        guard urls.count <= 32 else { throw ProjectFileError(message: "Choose at most 32 JavaScript libraries.") }
        var incomingBytes = 0
        let incoming = try urls.map { url -> (path: String, text: String) in
            try ProjectFiles.read(url) { local in
                let path = "libraries/" + local.lastPathComponent
                try validate([path])
                let text = try code(at: local)
                incomingBytes += text.utf8.count
                guard incomingBytes <= maximumBytes else {
                    throw ProjectFileError(message: "Choose at most 16 MB of JavaScript libraries.")
                }
                return (path, text)
            }
        }
        try validate(incoming.map(\.path))
        try ProjectFiles.write(project.folder, options: []) { folder in
            var paths = try pathsUncoordinated(in: folder)
            let files = FileManager.default
            // Validate every collision before writing any file.
            var total = 0
            for path in paths {
                total += (try code(at: fileURL(path, in: folder))).utf8.count
            }
            for item in incoming {
                let destination = try fileURL(item.path, in: folder)
                if files.fileExists(atPath: destination.path), try code(at: destination) != item.text {
                    throw ProjectFileError(message: "“\(item.path)” already exists with different code. Rename the incoming file; nothing was overwritten.")
                }
                if !paths.contains(item.path) { paths.append(item.path); total += item.text.utf8.count }
            }
            try validate(paths)
            guard total <= maximumBytes else { throw ProjectFileError(message: "The project's JavaScript libraries would exceed 16 MB.") }
            var created: [URL] = []
            do {
                for item in incoming {
                    let destination = try fileURL(item.path, in: folder)
                    if !files.fileExists(atPath: destination.path) {
                        try files.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
                        try item.text.write(to: destination, atomically: true, encoding: .utf8)
                        created.append(destination)
                    }
                }
                try save(paths, folder: folder)
            } catch {
                for url in created { try? files.removeItem(at: url) }
                throw error
            }
        }
    }
}
