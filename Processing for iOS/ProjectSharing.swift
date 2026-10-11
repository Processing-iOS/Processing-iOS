import UIKit

struct ProjectExport {
    let container: URL
    let url: URL

    func remove() { try? FileManager.default.removeItem(at: container) }

    static func prepare(folder: URL, name: String, zip: Bool) throws -> ProjectExport {
        try ProjectFiles.validateName(name)
        let fm = FileManager.default
        let container = fm.temporaryDirectory.appendingPathComponent("Processing-export-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: container, withIntermediateDirectories: true)
        do {
            let copied = container.appendingPathComponent(name, isDirectory: true)
            try ProjectFiles.read(folder) { try ProjectFiles.copyProject($0, to: copied) }
            guard zip else { return ProjectExport(container: container, url: copied) }
            let archive = container.appendingPathComponent(name + ".zip")
            var coordinationError: NSError?
            var copyError: Error?
            NSFileCoordinator().coordinate(readingItemAt: copied, options: .forUploading, error: &coordinationError) { snapshot in
                do { try fm.copyItem(at: snapshot, to: archive) }
                catch { copyError = error }
            }
            if let error = coordinationError ?? copyError as NSError? { throw error }
            guard fm.fileExists(atPath: archive.path) else { throw ProjectFileError(message: "Could not create the project archive.") }
            try fm.removeItem(at: copied)
            return ProjectExport(container: container, url: archive)
        } catch {
            try? fm.removeItem(at: container)
            throw error
        }
    }
}

final class ProjectSharing: NSObject, UIDocumentPickerDelegate {
    private weak var presenter: UIViewController?
    private let folder: URL
    private let name: String
    private var export: ProjectExport?

    init(folder: URL, name: String, presenter: UIViewController) {
        self.folder = folder
        self.name = name
        self.presenter = presenter
    }

    deinit { export?.remove() }

    func present(from sender: UIBarButtonItem) {
        guard let presenter else { return }
        let choices = UIAlertController(title: "Export \(name)", message: "Includes all source files, assets, and project libraries.", preferredStyle: .actionSheet)
        choices.addAction(UIAlertAction(title: "Share Project ZIP", style: .default) { [weak self] _ in self?.prepare(zip: true, sender: sender) })
        choices.addAction(UIAlertAction(title: "Save Project Folder to Files", style: .default) { [weak self] _ in self?.prepare(zip: false, sender: sender) })
        choices.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        choices.popoverPresentationController?.barButtonItem = sender
        presenter.present(choices, animated: true)
    }

    private func prepare(zip: Bool, sender: UIBarButtonItem) {
        guard let presenter else { return }
        var prepared: ProjectExport?
        FileOperationProgress.perform(title: "Preparing Export…", from: presenter, work: {
            prepared = try ProjectExport.prepare(folder: self.folder, name: self.name, zip: zip)
        }) { [weak self] error in
            guard let self else { prepared?.remove(); return }
            if let error {
                let alert = UIAlertController(title: "Cannot Export Project", message: error.localizedDescription, preferredStyle: .alert)
                alert.addAction(UIAlertAction(title: "OK", style: .default))
                presenter.present(alert, animated: true)
                return
            }
            guard let prepared else { return }
            self.export?.remove()
            self.export = prepared
            if zip {
                let share = UIActivityViewController(activityItems: [prepared.url], applicationActivities: nil)
                share.popoverPresentationController?.barButtonItem = sender
                share.completionWithItemsHandler = { [weak self] _, _, _, _ in self?.cleanup() }
                presenter.present(share, animated: true)
            } else {
                let picker = UIDocumentPickerViewController(forExporting: [prepared.url], asCopy: true)
                picker.delegate = self
                presenter.present(picker, animated: true)
            }
        }
    }

    private func cleanup() {
        export?.remove()
        export = nil
    }

    func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) { cleanup() }
    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) { cleanup() }
}
