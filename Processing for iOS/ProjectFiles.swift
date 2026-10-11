import Foundation

struct ProjectFileError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

/// All imports are copied and checked before any project becomes visible.
enum ProjectFiles {
    static let didChange = Notification.Name("ProjectFilesDidChange")

    static func validateName(_ name: String) throws {
        guard !name.isEmpty, name != ".", name != "..", !name.hasPrefix("."),
              !name.contains("/"), !name.contains("\\"), !name.contains(":"),
              !name.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) else {
            throw ProjectFileError(message: "Choose a nonempty name without path separators or a leading dot.")
        }
    }

    static func read<T>(_ url: URL, _ body: (URL) throws -> T) throws -> T {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        var coordinationError: NSError?
        var result: Result<T, Error>?
        NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: &coordinationError) { coordinatedURL in
            result = Result { try body(coordinatedURL) }
        }
        if let coordinationError { throw coordinationError }
        guard let result else { throw ProjectFileError(message: "The selected file is unavailable. Download it in Files and try again.") }
        return try result.get()
    }

    static func language(in urls: [URL]) throws -> String {
        var extensions = Set<String>()
        for url in urls {
            try read(url) { local in
                let files = local.isDirectory
                    ? try FileManager.default.contentsOfDirectory(at: local, includingPropertiesForKeys: [.isRegularFileKey], options: .skipsHiddenFiles)
                    : [local]
                for file in files where try file.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true {
                    extensions.insert(file.pathExtension.lowercased())
                }
            }
        }
        // A Processing project may contain JS helpers or a README.
        if extensions.contains("pde") { return "pde" }
        if extensions.contains("js") { return "js" }
        throw ProjectFileError(message: "Choose a folder containing .pde or .js source files at its top level, or select those files directly.")
    }

    static func importProject(_ urls: [URL], to destination: URL, language: String) throws {
        let fm = FileManager.default
        guard !urls.isEmpty else { throw ProjectFileError(message: "Select at least one source file.") }
        guard !fm.fileExists(atPath: destination.path) else {
            throw ProjectFileError(message: "A project named “\(destination.lastPathComponent)” already exists. Choose a different name.")
        }
        let parent = destination.deletingLastPathComponent()
        try fm.createDirectory(at: parent, withIntermediateDirectories: true)
        let stage = parent.appendingPathComponent(".import-\(UUID().uuidString)", isDirectory: true)
        defer { try? fm.removeItem(at: stage) }
        let importingFolder = try urls.count == 1 && read(urls[0], { $0.isDirectory })
        if importingFolder {
            try read(urls[0]) { try fm.copyItem(at: $0, to: stage) }
        } else {
            try fm.createDirectory(at: stage, withIntermediateDirectories: false)
            for url in urls {
                try read(url) { local in
                    guard !local.isDirectory else { throw ProjectFileError(message: "Import one project folder at a time.") }
                    try fm.copyItem(at: local, to: stage.appendingPathComponent(local.lastPathComponent))
                }
            }
        }
        try validateTree(stage)
        let sources = try fm.contentsOfDirectory(at: stage, includingPropertiesForKeys: [.isRegularFileKey])
            .filter { $0.pathExtension.lowercased() == language && !$0.isDirectory }
        guard !sources.isEmpty else { throw ProjectFileError(message: "This folder has no .\(language) source files at its top level.") }
        for file in sources { _ = try String(contentsOf: file, encoding: .utf8) }

        // Preserve the original main-file ordering when the imported project gets a new name.
        let originalName = importingFolder ? urls[0].lastPathComponent : urls[0].deletingPathExtension().lastPathComponent
        let candidates = ["\(originalName).\(language)", "sketch.\(language)"]
        let main = candidates.compactMap { name in sources.first { $0.lastPathComponent == name } }.first
            ?? (sources.count == 1 ? sources.first : nil)
        let newMain = stage.appendingPathComponent("\(destination.lastPathComponent).\(language)")
        if let main, main != newMain, !fm.fileExists(atPath: newMain.path) {
            try fm.moveItem(at: main, to: newMain)
        }
        // A move within Documents makes the complete project appear at once.
        try fm.moveItem(at: stage, to: destination)
    }

    static func validateTree(_ folder: URL) throws {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(at: folder, includingPropertiesForKeys: [.isSymbolicLinkKey]) else {
            throw ProjectFileError(message: "Cannot read the selected project folder.")
        }
        for case let file as URL in enumerator {
            if try file.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink == true {
                throw ProjectFileError(message: "“\(file.lastPathComponent)” is a symbolic link. Import the actual file instead.")
            }
        }
    }

    static func importFiles(_ urls: [URL], into folder: URL) throws {
        let fm = FileManager.default
        let projectLanguage = (try? language(in: [folder])) ?? (try? language(in: urls))
        let stage = fm.temporaryDirectory.appendingPathComponent("Processing-import-\(UUID().uuidString)")
        try fm.createDirectory(at: stage, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: stage) }
        var items: [(from: URL, to: URL)] = []
        for (index, url) in urls.enumerated() {
            try read(url) { local in
                let source = ["pde", "js"].contains(local.pathExtension.lowercased())
                if source, let projectLanguage, local.pathExtension.lowercased() != projectLanguage {
                    throw ProjectFileError(message: "This is a .\(projectLanguage) project. Import .\(local.pathExtension) code as a separate project.")
                }
                let targetFolder = source ? folder : folder.appendingPathComponent("data", isDirectory: true)
                let target = targetFolder.appendingPathComponent(local.lastPathComponent)
                guard !fm.fileExists(atPath: target.path), !items.contains(where: { $0.to == target }) else {
                    throw ProjectFileError(message: "“\(local.lastPathComponent)” already exists. Rename the incoming file or existing file first; nothing was imported.")
                }
                let copy = stage.appendingPathComponent(String(index), isDirectory: local.isDirectory)
                try fm.copyItem(at: local, to: copy)
                if local.isDirectory { try validateTree(copy) }
                else if try local.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink == true {
                    throw ProjectFileError(message: "Import the actual file instead of a symbolic link.")
                }
                if source { _ = try String(contentsOf: copy, encoding: .utf8) }
                items.append((copy, target))
            }
        }
        var inserted: [URL] = []
        do {
            for item in items {
                try fm.createDirectory(at: item.to.deletingLastPathComponent(), withIntermediateDirectories: true)
                try fm.moveItem(at: item.from, to: item.to)
                inserted.append(item.to)
            }
        } catch {
            for url in inserted { try? fm.removeItem(at: url) }
            throw error
        }
        NotificationCenter.default.post(name: didChange, object: folder)
    }
}
