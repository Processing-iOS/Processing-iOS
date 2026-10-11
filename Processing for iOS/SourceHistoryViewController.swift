import UIKit

final class SourceHistoryViewController: UITableViewController {
    private let file: SourceCodeFile
    private let didRestore: () -> Void
    private var revisions: [SourceRevision] = []

    init(file: SourceCodeFile, didRestore: @escaping () -> Void) {
        self.file = file
        self.didRestore = didRestore
        super.init(style: .insetGrouped)
        title = "Code History"
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        navigationItem.rightBarButtonItem = UIBarButtonItem(barButtonSystemItem: .done, target: self, action: #selector(done))
        do {
            revisions = try file.history()
            if revisions.isEmpty {
                let label = UILabel()
                label.text = "Previous versions of \(file.fileName) appear here after you make changes."
                label.numberOfLines = 0
                label.textAlignment = .center
                label.textColor = .secondaryLabel
                tableView.backgroundView = label
            }
        } catch { showError(error) }
    }
    @objc private func done() { dismiss(animated: true) }
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { revisions.count }
    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? { file.fileName }
    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        "Up to 100 versions are kept on this device, at most once every 30 seconds while editing. Restoring also saves a copy of your current code."
    }
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = UITableViewCell(style: .subtitle, reuseIdentifier: nil)
        let revision = revisions[indexPath.row]
        cell.textLabel?.text = DateFormatter.localizedString(from: revision.date, dateStyle: .medium, timeStyle: .medium)
        cell.detailTextLabel?.text = revision.content.isEmpty ? "Empty file" : String(revision.content.prefix(120)).replacingOccurrences(of: "\n", with: " ")
        cell.accessoryType = .disclosureIndicator
        return cell
    }
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        let revision = revisions[indexPath.row]
        let preview = UIViewController()
        preview.title = "Previous Version"
        let text = UITextView()
        text.isEditable = false
        text.font = .monospacedSystemFont(ofSize: 15, weight: .regular)
        text.text = revision.content
        text.backgroundColor = .systemBackground
        preview.view = text
        preview.navigationItem.rightBarButtonItem = UIBarButtonItem(title: "Restore", primaryAction: UIAction { [weak self, weak preview] _ in
            let alert = UIAlertController(title: "Restore this version?", message: "Your current code will remain available in History.", preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
            alert.addAction(UIAlertAction(title: "Restore", style: .default) { _ in
                guard let self else { return }
                do {
                    try self.file.restore(revision)
                    self.didRestore()
                    self.dismiss(animated: true)
                } catch { self.showError(error) }
            })
            preview?.present(alert, animated: true)
        })
        navigationController?.pushViewController(preview, animated: true)
    }
    private func showError(_ error: Error) {
        let alert = UIAlertController(title: "Cannot Access History", message: error.localizedDescription, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        (navigationController?.topViewController ?? self).present(alert, animated: true)
    }
}
