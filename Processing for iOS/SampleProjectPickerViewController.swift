import UIKit

final class SampleProjectPickerViewController: UITableViewController {
    private let fileNames = SketchController.bundledSampleFileNames()
    private var selectedFileNames = Set<String>()
    private let onImport: ([String]) -> Void
    private lazy var importButton = UIBarButtonItem(
        title: "Import", style: .done, target: self, action: #selector(importSelected)
    )

    init(onImport: @escaping ([String]) -> Void) {
        self.onImport = onImport
        super.init(style: .insetGrouped)
    }

    required init?(coder: NSCoder) {
        fatalError("Use init(onImport:)")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Sample Projects"
        preferredContentSize = CGSize(width: 540, height: 640)
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .cancel, target: self, action: #selector(cancel)
        )
        navigationItem.rightBarButtonItem = importButton
        updateImportButton()

        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "sample")
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 64
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        fileNames.count
    }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        "Choose samples to import"
    }

    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        "Existing projects are kept. Edited samples get a clean copy with a numbered name."
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "sample", for: indexPath)
        let fileName = fileNames[indexPath.row]
        let name = (fileName as NSString).deletingPathExtension
            .replacingOccurrences(of: "Example_", with: "")
            .replacingOccurrences(of: "FollowMe", with: "Follow Me")
            .replacingOccurrences(of: "Gyroscope_Accelerometer", with: "Gyroscope & Accelerometer")
        let language = fileName.hasSuffix(".js") ? "p5.js" : "Processing"
        var content = cell.defaultContentConfiguration()
        content.text = name
        content.secondaryText = language
        content.textProperties.numberOfLines = 0
        cell.contentConfiguration = content

        let selected = selectedFileNames.contains(fileName)
        cell.accessoryType = selected ? .checkmark : .none
        cell.accessibilityLabel = "\(name), \(language)"
        cell.accessibilityTraits = selected ? [.button, .selected] : [.button]
        cell.accessibilityHint = selected ? "Deselect sample" : "Select sample"
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        let fileName = fileNames[indexPath.row]
        if !selectedFileNames.insert(fileName).inserted {
            selectedFileNames.remove(fileName)
        }
        tableView.deselectRow(at: indexPath, animated: false)
        tableView.reloadRows(at: [indexPath], with: .none)
        updateImportButton()
    }

    private func updateImportButton() {
        let count = selectedFileNames.count
        importButton.title = count == 0 ? "Import" : "Import (\(count))"
        importButton.isEnabled = count > 0
    }

    @objc private func cancel() {
        dismiss(animated: true)
    }

    @objc private func importSelected() {
        let selected = fileNames.filter { selectedFileNames.contains($0) }
        guard !selected.isEmpty, importButton.isEnabled else { return }
        importButton.isEnabled = false
        dismiss(animated: true) { [onImport] in
            onImport(selected)
        }
    }
}
