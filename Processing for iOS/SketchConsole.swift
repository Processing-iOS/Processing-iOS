import UIKit

/// Output survives the runner so errors and earlier prints remain available in the editor.
@objc final class SketchConsole: NSObject {
    static let didChange = Notification.Name("SketchConsole.didChange")
    @objc private(set) var text = ""
    private let limit = 60_000

    @objc func append(_ value: String, level: String = "log") {
        appendRecords([["text": value, "level": level, "newline": true]])
    }

    @objc func appendRecords(_ records: [Any]) {
        for item in records.prefix(200) {
            guard let record = item as? [String: Any] else { continue }
            guard let value = record["text"] as? String else { continue }
            let level = record["level"] as? String ?? "log"
            if level == "warn" || level == "error" { text += "[\(level.uppercased())] " }
            text += String(value.prefix(2_000))
            if record["newline"] as? Bool != false { text += "\n" }
        }
        if text.utf8.count > limit {
            text = "… Earlier output removed …\n" + String(text.suffix(14_000))
        }
        NotificationCenter.default.post(name: Self.didChange, object: self)
    }

    @objc func clear() {
        text = ""
        NotificationCenter.default.post(name: Self.didChange, object: self)
    }
}

@objc final class SketchConsoleViewController: UIViewController {
    private let console: SketchConsole
    private let output = UITextView()

    @objc init(console: SketchConsole) {
        self.console = console
        super.init(nibName: nil, bundle: nil)
        title = "Console"
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        output.isEditable = false
        output.alwaysBounceVertical = true
        output.font = .monospacedSystemFont(ofSize: 14, weight: .regular)
        output.textColor = .label
        output.backgroundColor = .systemBackground
        output.accessibilityLabel = "Sketch output"
        output.textContainerInset = UIEdgeInsets(top: 16, left: 12, bottom: 16, right: 12)
        output.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(output)
        NSLayoutConstraint.activate([
            output.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            output.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            output.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            output.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor)
        ])
        navigationItem.leftBarButtonItems = [
            UIBarButtonItem(title: "Copy", style: .plain, target: self, action: #selector(copyOutput)),
            UIBarButtonItem(title: "Clear", style: .plain, target: self, action: #selector(clearOutput))
        ]
        navigationItem.rightBarButtonItem = UIBarButtonItem(barButtonSystemItem: .done, target: self, action: #selector(close))
        NotificationCenter.default.addObserver(self, selector: #selector(refresh), name: SketchConsole.didChange, object: console)
        refresh()
    }

    @objc private func refresh() {
        // Keep a selection or an earlier scrolled position while output arrives.
        let follow = output.selectedRange.length == 0 &&
            output.contentOffset.y + output.bounds.height >= output.contentSize.height - 40
        let selection = output.selectedRange, offset = output.contentOffset
        output.text = console.text.isEmpty ? "No output yet. Use println() or console.log() in your sketch." : console.text
        if follow { output.scrollRangeToVisible(NSRange(location: (output.text as NSString).length, length: 0)) }
        else {
            let length = (output.text as NSString).length
            output.selectedRange = NSRange(location: min(selection.location, length), length: min(selection.length, max(0, length - selection.location)))
            output.setContentOffset(offset, animated: false)
        }
    }

    @objc private func copyOutput() { UIPasteboard.general.string = console.text }
    @objc private func clearOutput() { console.clear() }
    @objc private func close() { dismiss(animated: true) }

    @objc static func presentConsole(_ console: SketchConsole, from presenter: UIViewController) {
        let navigation = UINavigationController(rootViewController: SketchConsoleViewController(console: console))
        navigation.sheetPresentationController?.detents = [.medium(), .large()]
        navigation.sheetPresentationController?.prefersGrabberVisible = true
        presenter.present(navigation, animated: true)
    }
}
