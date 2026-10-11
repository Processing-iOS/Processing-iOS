import Foundation

struct ProjectFileError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

/// All imports are copied and checked before any project becomes visible.
enum ProjectFiles {
    static let didChange = Notification.Name("ProjectFilesDidChange")

    private static func changed(_ folder: URL) {
        if Thread.isMainThread { NotificationCenter.default.post(name: didChange, object: folder) }
        else { DispatchQueue.main.async { NotificationCenter.default.post(name: didChange, object: folder) } }
    }

    /// Copy only a project's useful files; recovery history and generated runtimes
    /// belong to the original working copy, not to a duplicate or shared project.
    static func copyProject(_ source: URL, to destination: URL) throws {
        let fm = FileManager.default
        guard !fm.fileExists(atPath: destination.path) else {
            throw ProjectFileError(message: "The destination already exists. Choose another name.")
        }
        try validateTree(source)
        try fm.createDirectory(at: destination, withIntermediateDirectories: false)
        do {
            for item in try fm.contentsOfDirectory(at: source, includingPropertiesForKeys: nil)
            where item.lastPathComponent != ".processing-history" && !item.lastPathComponent.hasPrefix("__runtime_") {
                try fm.copyItem(at: item, to: destination.appendingPathComponent(item.lastPathComponent))
            }
        } catch {
            try? fm.removeItem(at: destination)
            throw error
        }
    }

    static func renameFile(_ source: URL, to name: String, projectFolder: URL) throws {
        try write(projectFolder, options: []) { _ in
            try renameFileCoordinated(source, to: name, projectFolder: projectFolder)
        }
    }

    private static func renameFileCoordinated(_ source: URL, to name: String, projectFolder: URL) throws {
        try validateName(name)
        guard name != source.lastPathComponent else { return }
        let fm = FileManager.default
        let destination = source.deletingLastPathComponent().appendingPathComponent(name)
        if ["pde", "js"].contains(source.pathExtension.lowercased()),
           destination.pathExtension.lowercased() != source.pathExtension.lowercased() {
            throw ProjectFileError(message: "Keep the .\(source.pathExtension) extension so the file remains part of this project.")
        }
        guard !fm.fileExists(atPath: destination.path) else {
            throw ProjectFileError(message: "“\(name)” already exists. Choose another name; no files were changed.")
        }
        let history = projectFolder.appendingPathComponent(".processing-history")
        let oldHistory = history.appendingPathComponent(source.lastPathComponent)
        let newHistory = history.appendingPathComponent(name)
        var copiedHistory: [URL] = []
        do {
            if source.deletingLastPathComponent().standardizedFileURL.path == projectFolder.standardizedFileURL.path,
               fm.fileExists(atPath: oldHistory.path) {
                try fm.createDirectory(at: newHistory, withIntermediateDirectories: true)
                for item in try fm.contentsOfDirectory(at: oldHistory, includingPropertiesForKeys: nil) {
                    let timestamp = (try? JSONDecoder().decode(SourceRevision.self, from: Data(contentsOf: item)))?.date.timeIntervalSince1970 ?? 0
                    let target = newHistory.appendingPathComponent("\(timestamp)-\(UUID().uuidString).json")
                    try fm.copyItem(at: item, to: target)
                    copiedHistory.append(target)
                }
            }
            try fm.moveItem(at: source, to: destination)
        } catch {
            for item in copiedHistory { try? fm.removeItem(at: item) }
            throw error
        }
        if !copiedHistory.isEmpty { try? fm.removeItem(at: oldHistory) }
        changed(projectFolder)
    }

    static func duplicateFile(_ source: URL, as name: String, projectFolder: URL) throws {
        try write(projectFolder, options: []) { _ in
            try duplicateFileCoordinated(source, as: name, projectFolder: projectFolder)
        }
    }

    private static func duplicateFileCoordinated(_ source: URL, as name: String, projectFolder: URL) throws {
        try validateName(name)
        let destination = source.deletingLastPathComponent().appendingPathComponent(name)
        if ["pde", "js"].contains(source.pathExtension.lowercased()), destination.pathExtension.lowercased() != source.pathExtension.lowercased() {
            throw ProjectFileError(message: "Keep the .\(source.pathExtension) extension for the copied source file.")
        }
        guard !FileManager.default.fileExists(atPath: destination.path) else {
            throw ProjectFileError(message: "“\(name)” already exists. Choose another name.")
        }
        let temporary = source.deletingLastPathComponent().appendingPathComponent(".copy-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: temporary) }
        try FileManager.default.copyItem(at: source, to: temporary)
        try FileManager.default.moveItem(at: temporary, to: destination)
        changed(projectFolder)
    }

    static func renameProject(_ project: SimpleTextProject, to name: String) throws {
        guard !project.isLinked else {
            throw ProjectFileError(message: "Rename this linked folder in Files. Its bookmark will follow the folder when the provider supports it.")
        }
        try validateName(name)
        guard name != project.name else { return }
        let fm = FileManager.default, original = project.folder
        let destination = original.deletingLastPathComponent().appendingPathComponent(name)
        guard !fm.fileExists(atPath: destination.path) else {
            throw ProjectFileError(message: "A project named “\(name)” already exists. Choose another name.")
        }
        // Move the complete folder first. If the main-file rename fails, put it
        // back before exposing the changed model to the project list.
        try fm.moveItem(at: original, to: destination)
        do {
            let oldMain = destination.appendingPathComponent("\(project.name).\(project.sourceCodeExtension)")
            if fm.fileExists(atPath: oldMain.path) {
                try renameFile(oldMain, to: "\(name).\(project.sourceCodeExtension)", projectFolder: destination)
            }
        } catch {
            do { try fm.moveItem(at: destination, to: original) }
            catch { throw ProjectFileError(message: "The project is safe in “\(name)”, but the rename could not finish. Reopen that folder from My Projects.") }
            throw error
        }
        project.name = name
    }

    static func duplicateProject(_ project: SimpleTextProject, as name: String) throws {
        try validateName(name)
        let root = URL(fileURLWithPath: SketchController.documentsDirectory()).appendingPathComponent("sketches", isDirectory: true)
        let destination = root.appendingPathComponent(name)
        let stage = root.appendingPathComponent(".duplicate-\(UUID().uuidString)")
        let fm = FileManager.default
        guard !fm.fileExists(atPath: destination.path) else {
            throw ProjectFileError(message: "A project named “\(name)” already exists. Choose another name.")
        }
        defer { try? fm.removeItem(at: stage) }
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        try read(project.folder) { try copyProject($0, to: stage) }
        let main = stage.appendingPathComponent(project.preferredMainFileName ?? "\(project.name).\(project.sourceCodeExtension)")
        if fm.fileExists(atPath: main.path) {
            try renameFile(main, to: "\(name).\(project.sourceCodeExtension)", projectFolder: stage)
        }
        try fm.moveItem(at: stage, to: destination)
    }

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

    static func write<T>(_ url: URL, options: NSFileCoordinator.WritingOptions = .forReplacing, _ body: (URL) throws -> T) throws -> T {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        var coordinationError: NSError?
        var result: Result<T, Error>?
        NSFileCoordinator().coordinate(writingItemAt: url, options: options, error: &coordinationError) { coordinatedURL in
            result = Result { try body(coordinatedURL) }
        }
        if let coordinationError { throw coordinationError }
        guard let result else { throw ProjectFileError(message: "This file is unavailable. Download it in Files and try again.") }
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
            try write(folder, options: []) { _ in
                for item in items {
                    guard !fm.fileExists(atPath: item.to.path) else { throw ProjectFileError(message: "A file with this name appeared while importing. Nothing was overwritten.") }
                    try fm.createDirectory(at: item.to.deletingLastPathComponent(), withIntermediateDirectories: true)
                    try fm.moveItem(at: item.from, to: item.to)
                    inserted.append(item.to)
                }
            }
        } catch {
            for url in inserted { try? fm.removeItem(at: url) }
            throw error
        }
        changed(folder)
    }
}
