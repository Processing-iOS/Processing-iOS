import UIKit
import UniformTypeIdentifiers

final class ProjectLibrariesViewController: UITableViewController, UIDocumentPickerDelegate {
    private let project: SimpleTextProject
    private var paths: [String] = []

    init(project: SimpleTextProject) {
        self.project = project
        super.init(style: .insetGrouped)
        title = "JavaScript Libraries"
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        navigationItem.leftBarButtonItem = UIBarButtonItem(barButtonSystemItem: .done, target: self, action: #selector(close))
        navigationItem.rightBarButtonItems = [
            UIBarButtonItem(barButtonSystemItem: .add, target: self, action: #selector(addLibrary)), editButtonItem
        ]
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 65
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        reloadLibraries()
    }

    private func reloadLibraries() {
        do { paths = try ProjectLibraries.paths(in: project); tableView.reloadData() }
        catch { showError(error) }
    }

    @objc private func close() { dismiss(animated: true) }

    @objc private func addLibrary() {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [UTType(filenameExtension: "js") ?? .sourceCode], asCopy: true)
        picker.allowsMultipleSelection = true
        picker.delegate = self
        present(picker, animated: true)
    }

    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        FileOperationProgress.perform(title: "Adding Libraries…", from: self, work: {
            try ProjectLibraries.add(urls, to: self.project)
        }) { error in
            if let error { self.showError(error) }
            else { self.reloadLibraries() }
        }
    }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        paths.isEmpty ? "No project libraries" : "Load order"
    }

    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        "Tap + to import browser-compatible .js bundles. Libraries run from top to bottom after p5.js 1.4.0 and before your sketch. Edit lets you drag to reorder. Tap a library to read its code; edit the file through Files.\n\nUse classic scripts or browser/UMD builds. Node.js, npm packages, ES modules, and Java .jar files do not run directly here. Exclude removes a library from the run but keeps its file."
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { paths.count }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "library") ?? UITableViewCell(style: .subtitle, reuseIdentifier: "library")
        cell.textLabel?.text = "\(indexPath.row + 1). " + (paths[indexPath.row] as NSString).lastPathComponent
        cell.textLabel?.font = .preferredFont(forTextStyle: .body)
        cell.textLabel?.numberOfLines = 0
        cell.detailTextLabel?.text = "Tap to read source"
        cell.detailTextLabel?.textColor = .secondaryLabel
        cell.accessoryType = .disclosureIndicator
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        do {
            let path = paths[indexPath.row]
            let code = try ProjectLibraries.source(path, in: project)
            navigationController?.pushViewController(LibrarySourceViewController(path: path, code: code), animated: true)
        } catch { showError(error) }
    }

    override func tableView(_ tableView: UITableView, editingStyleForRowAt indexPath: IndexPath) -> UITableViewCell.EditingStyle { .none }
    override func tableView(_ tableView: UITableView, canMoveRowAt indexPath: IndexPath) -> Bool { true }

    override func tableView(_ tableView: UITableView, moveRowAt sourceIndexPath: IndexPath, to destinationIndexPath: IndexPath) {
        var reordered = paths
        reordered.insert(reordered.remove(at: sourceIndexPath.row), at: destinationIndexPath.row)
        do { try ProjectLibraries.reorder(reordered, in: project); paths = reordered; tableView.reloadData() }
        catch { reloadLibraries(); showError(error) }
    }

    override func tableView(_ tableView: UITableView, trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration? {
        let path = paths[indexPath.row]
        let exclude = UIContextualAction(style: .normal, title: "Exclude") { [weak self] _, _, done in
            guard let self else { done(false); return }
            do { try ProjectLibraries.exclude(path, from: self.project); self.reloadLibraries(); done(true) }
            catch { self.showError(error); done(false) }
        }
        exclude.backgroundColor = .systemOrange
        let actions = UISwipeActionsConfiguration(actions: [exclude])
        actions.performsFirstActionWithFullSwipe = false
        return actions
    }

    private func showError(_ error: Error) {
        let alert = UIAlertController(title: "Library Error", message: error.localizedDescription, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }
}

final class LibrarySourceViewController: UIViewController {
    private let code: String
    private let bug: DetectedBug?
    private let source = UITextView()

    init(path: String, code: String, bug: DetectedBug? = nil) {
        self.code = code
        self.bug = bug
        super.init(nibName: nil, bundle: nil)
        title = (path as NSString).lastPathComponent
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        source.isEditable = false
        source.font = .monospacedSystemFont(ofSize: 15, weight: .regular)
        source.text = code
        source.textContainerInset = UIEdgeInsets(top: 16, left: 12, bottom: 20, right: 12)
        source.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(source)
        NSLayoutConstraint.activate([
            source.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            source.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
            source.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            source.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])
        navigationItem.rightBarButtonItem = UIBarButtonItem(title: "Copy", style: .plain, target: self, action: #selector(copyCode))
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        if let range = bug?.range(inSource: code), range.location != NSNotFound {
            source.selectedRange = range
            source.scrollRangeToVisible(range)
        }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setToolbarHidden(true, animated: animated)
    }

    @objc private func copyCode() { UIPasteboard.general.string = code; navigationItem.rightBarButtonItem?.title = "Copied" }
}
