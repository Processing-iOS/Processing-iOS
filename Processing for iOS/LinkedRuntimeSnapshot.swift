import Foundation

/// A linked project runs from a coordinated local snapshot. Provider folders
/// receive only deliberate source edits and exports, never generated runtime HTML.
@objc final class LinkedRuntimeSnapshot: NSObject {
    @objc let project: SimpleTextProject
    private let container: URL

    private init(original: SimpleTextProject, container: URL, folder: URL) {
        self.container = container
        project = SimpleTextProject(folder: folder, name: original.name, language: original.sourceCodeExtension)
        project.preferredMainFileName = original.preferredMainFileName
    }

    @objc static func prepare(_ original: SimpleTextProject) throws -> LinkedRuntimeSnapshot {
        if let error = original.initializationError { throw error }
        let container = FileManager.default.temporaryDirectory.appendingPathComponent("Processing-runtime-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: container, withIntermediateDirectories: true)
        let folder = container.appendingPathComponent(original.name, isDirectory: true)
        do {
            try ProjectFiles.read(original.folder) { try ProjectFiles.copyProject($0, to: folder) }
            return LinkedRuntimeSnapshot(original: original, container: container, folder: folder)
        } catch {
            try? FileManager.default.removeItem(at: container)
            throw error
        }
    }

    deinit { try? FileManager.default.removeItem(at: container) }
}
