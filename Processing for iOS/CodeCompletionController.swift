import UIKit

/// Keeps completion UI separate from syntax highlighting and compiler diagnostics.
@objc final class CodeCompletionController: NSObject {
    private weak var textView: UITextView?
    private let file: SourceCodeFile
    private let projectFiles: [SourceCodeFile]
    private let strip = CompletionStrip()
    private var request: CodeCompletionRequest?
    private var work: DispatchWorkItem?
    private var applying = false
    private var symbolCache: [String: (source: String, names: [String])] = [:]
    @objc var didComplete: (() -> Void)?

    @objc init(textView: UITextView, file: SourceCodeFile, projectFiles: [SourceCodeFile]) {
        self.textView = textView
        self.file = file
        self.projectFiles = projectFiles
        super.init()
        textView.inputAccessoryView = strip
        textView.autocapitalizationType = .none
        textView.autocorrectionType = .no
        textView.spellCheckingType = .no
        textView.smartQuotesType = .no
        textView.smartDashesType = .no
        textView.smartInsertDeleteType = .no
        strip.onDismiss = { [weak self] in
            self?.dismiss()
            self?.textView?.resignFirstResponder()
        }
        strip.onSelect = { [weak self] index in self?.accept(at: index) }
        strip.onInsert = { [weak self] text in
            guard let textView = self?.textView else { return }
            if textView.delegate?.textView?(textView, shouldChangeTextIn: textView.selectedRange, replacementText: text) != false {
                textView.insertText(text)
            }
            self?.didComplete?()
        }
    }

    @objc func scheduleUpdate() {
        guard !applying else { return }
        work?.cancel()
        let pending = DispatchWorkItem { [weak self] in self?.update(explicit: false) }
        work = pending
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08, execute: pending)
    }

    @objc func show() {
        work?.cancel()
        update(explicit: true)
    }

    @objc var hasSuggestions: Bool { request?.items.isEmpty == false }

    @objc func dismiss() {
        work?.cancel()
        request = nil
        strip.display([])
    }

    @objc func acceptFirst() {
        accept(at: 0)
    }

    private func update(explicit: Bool) {
        guard let textView = textView, textView.isFirstResponder, textView.markedTextRange == nil else {
            dismiss()
            return
        }
        var projectSymbols: [String] = []
        for other in projectFiles where other !== file {
            guard let content = other.content else { continue }
            if symbolCache[other.filePath]?.source != content {
                symbolCache[other.filePath] = (content, CodeCompletionEngine.symbols(in: content, language: file.fileExtension))
            }
            projectSymbols += symbolCache[other.filePath]?.names ?? []
        }
        request = CodeCompletionEngine.request(source: textView.text, selection: textView.selectedRange,
            language: file.fileExtension, projectSymbols: projectSymbols, explicit: explicit)
        strip.display(request?.items ?? [])
    }

    private func accept(at index: Int) {
        guard let textView = textView, textView.isFirstResponder, textView.markedTextRange == nil,
              let request = request, request.items.indices.contains(index),
              let edit = request.edit(for: request.items[index], source: textView.text, selection: textView.selectedRange) else {
            dismiss()
            return
        }
        applying = true
        work?.cancel()
        // UITextInput insertion preserves UIKit's normal undo and text-change behavior.
        textView.selectedRange = edit.range
        textView.insertText(edit.text)
        textView.selectedRange = NSRange(location: edit.caret, length: 0)
        didComplete?()
        applying = false
        dismiss()
    }
}

private final class CompletionStrip: UIInputView {
    var onSelect: ((Int) -> Void)?
    var onDismiss: (() -> Void)?
    var onInsert: ((String) -> Void)?
    private let scroll = UIScrollView()
    private let stack = UIStackView()
    private let hint = UILabel()
    private let dismissButton = UIButton(type: .system)

    init() {
        super.init(frame: CGRect(x: 0, y: 0, width: 320, height: 104), inputViewStyle: .keyboard)
        autoresizingMask = [.flexibleWidth]
        allowsSelfSizing = true
        backgroundColor = .secondarySystemBackground
        scroll.showsHorizontalScrollIndicator = false
        stack.axis = .horizontal
        stack.spacing = 6
        stack.alignment = .fill
        hint.text = "Type a name to see completions"
        hint.textColor = .secondaryLabel
        hint.font = .preferredFont(forTextStyle: .footnote)
        hint.adjustsFontSizeToFitWidth = true
        hint.minimumScaleFactor = 0.75
        dismissButton.setImage(UIImage(systemName: "keyboard.chevron.compact.down"), for: .normal)
        dismissButton.accessibilityLabel = "Hide keyboard"
        dismissButton.addAction(UIAction { [weak self] _ in self?.onDismiss?() }, for: .touchUpInside)
        [scroll, hint, dismissButton].forEach { $0.translatesAutoresizingMaskIntoConstraints = false; addSubview($0) }
        stack.translatesAutoresizingMaskIntoConstraints = false
        scroll.addSubview(stack)
        let symbols = UIScrollView()
        symbols.showsHorizontalScrollIndicator = false
        let symbolStack = UIStackView()
        symbolStack.axis = .horizontal
        symbolStack.spacing = 2
        for (title, insertion) in [("Tab", "   "), ("{", "{"), ("}", "}"), ("(", "("), (")", ")"), ("[", "["), ("]", "]"), (";", ";"), ("\"", "\"")] {
            let button = UIButton(type: .system)
            button.setTitle(title, for: .normal)
            button.titleLabel?.font = .monospacedSystemFont(ofSize: 18, weight: .medium)
            button.accessibilityLabel = title == "Tab" ? "Insert indentation" : "Insert \(title)"
            button.widthAnchor.constraint(greaterThanOrEqualToConstant: 42).isActive = true
            button.addAction(UIAction { [weak self] _ in
                self?.onInsert?(insertion)
            }, for: .touchUpInside)
            symbolStack.addArrangedSubview(button)
        }
        symbols.translatesAutoresizingMaskIntoConstraints = false
        symbolStack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(symbols)
        symbols.addSubview(symbolStack)
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 104),
            scroll.leadingAnchor.constraint(equalTo: safeAreaLayoutGuide.leadingAnchor, constant: 8),
            scroll.trailingAnchor.constraint(equalTo: dismissButton.leadingAnchor, constant: -4),
            scroll.topAnchor.constraint(equalTo: topAnchor, constant: 4),
            scroll.heightAnchor.constraint(equalToConstant: 52),
            dismissButton.trailingAnchor.constraint(equalTo: safeAreaLayoutGuide.trailingAnchor),
            dismissButton.centerYAnchor.constraint(equalTo: scroll.centerYAnchor),
            dismissButton.widthAnchor.constraint(equalToConstant: 44),
            dismissButton.heightAnchor.constraint(equalToConstant: 44),
            hint.leadingAnchor.constraint(equalTo: scroll.leadingAnchor, constant: 8),
            hint.trailingAnchor.constraint(equalTo: scroll.trailingAnchor),
            hint.centerYAnchor.constraint(equalTo: scroll.centerYAnchor),
            stack.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor),
            stack.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor),
            stack.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor),
            stack.heightAnchor.constraint(equalTo: scroll.frameLayoutGuide.heightAnchor),
            symbols.leadingAnchor.constraint(equalTo: safeAreaLayoutGuide.leadingAnchor, constant: 4),
            symbols.trailingAnchor.constraint(equalTo: safeAreaLayoutGuide.trailingAnchor, constant: -4),
            symbols.topAnchor.constraint(equalTo: topAnchor, constant: 60),
            symbols.bottomAnchor.constraint(equalTo: bottomAnchor),
            symbolStack.leadingAnchor.constraint(equalTo: symbols.contentLayoutGuide.leadingAnchor),
            symbolStack.trailingAnchor.constraint(equalTo: symbols.contentLayoutGuide.trailingAnchor),
            symbolStack.topAnchor.constraint(equalTo: symbols.contentLayoutGuide.topAnchor),
            symbolStack.bottomAnchor.constraint(equalTo: symbols.contentLayoutGuide.bottomAnchor),
            symbolStack.heightAnchor.constraint(equalTo: symbols.frameLayoutGuide.heightAnchor)
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func display(_ items: [CodeCompletion]) {
        stack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        hint.isHidden = !items.isEmpty
        scroll.isHidden = items.isEmpty
        scroll.setContentOffset(.zero, animated: false)
        for (index, item) in items.enumerated() {
            let button = UIButton(type: .system)
            var config = UIButton.Configuration.tinted()
            config.title = item.name
            config.subtitle = item.detail
            config.baseForegroundColor = .label
            config.baseBackgroundColor = .tertiarySystemFill
            config.cornerStyle = .medium
            config.contentInsets = NSDirectionalEdgeInsets(top: 4, leading: 12, bottom: 4, trailing: 12)
            config.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer {
                var attributes = $0
                attributes.font = .monospacedSystemFont(ofSize: 15, weight: .semibold)
                return attributes
            }
            config.subtitleTextAttributesTransformer = UIConfigurationTextAttributesTransformer {
                var attributes = $0
                attributes.font = .systemFont(ofSize: 11)
                attributes.foregroundColor = .secondaryLabel
                return attributes
            }
            button.configuration = config
            button.accessibilityLabel = "Complete " + item.name
            button.accessibilityHint = item.detail
            button.accessibilityIdentifier = "completion." + item.name
            button.addAction(UIAction { [weak self] _ in self?.onSelect?(index) }, for: .touchUpInside)
            stack.addArrangedSubview(button)
        }
    }
}
