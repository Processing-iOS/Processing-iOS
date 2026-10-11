import UIKit

@objc final class CodeEditorTools: NSObject {
    private weak var textView: UITextView?
    private let language: String
    private var applying = false
    @objc var didChange: (() -> Void)?

    @objc init(textView: UITextView, language: String) {
        self.textView = textView
        self.language = language
        super.init()
        if #available(iOS 16.0, *) { textView.isFindInteractionEnabled = true }
    }

    @objc static var fontSize: CGFloat {
        let saved = UserDefaults.standard.double(forKey: "editorFontSize")
        return CGFloat(saved == 0 ? 18 : min(30, max(12, saved)))
    }

    @objc func changeFontSize(_ delta: CGFloat) {
        UserDefaults.standard.set(Double(min(30, max(12, Self.fontSize + delta))), forKey: "editorFontSize")
        textView?.font = UIFont(name: "SourceCodePro-Regular", size: Self.fontSize)
    }

    @objc func format() {
        guard let textView, textView.markedTextRange == nil else { return }
        let original = textView.text ?? ""
        let lexical = CodeCompletionEngine.codeOnly(original, language: language)
        let lines = original.components(separatedBy: "\n")
        let masked = lexical.text.components(separatedBy: "\n")
        var depth = 0, offset = 0
        var result: [String] = []
        var mappings: [(old: Int, new: Int, removed: Int, inserted: Int, length: Int)] = []
        var newOffset = 0
        for (index, line) in lines.enumerated() {
            let ns = line as NSString
            let leading = line.prefix { $0 == " " || $0 == "\t" }.utf16.count
            let code = masked[index].trimmingCharacters(in: .whitespaces)
            let closing = code.prefix { $0 == "}" || $0 == " " || $0 == "\t" }.filter { $0 == "}" }.count
            // A line beginning inside a multiline string/comment is literal content.
            // Leave its whitespace untouched, including its closing delimiter.
            let preserve = !lexical.codePositions[min(offset, lexical.codePositions.count - 1)]
            let indent = String(repeating: " ", count: min(100, max(0, depth - closing)) * 3)
            let formatted = preserve ? line : (line.isEmpty ? "" : indent + ns.substring(from: leading))
            result.append(formatted)
            mappings.append((offset, newOffset, preserve ? 0 : leading, preserve || line.isEmpty ? 0 : indent.utf16.count, ns.length))
            offset += ns.length + 1
            newOffset += formatted.utf16.count + 1
            depth = max(0, depth + masked[index].filter { $0 == "{" }.count - masked[index].filter { $0 == "}" }.count)
        }
        let formatted = result.joined(separator: "\n")
        guard formatted != original else { return }
        func moved(_ position: Int) -> Int {
            guard let line = mappings.last(where: { $0.old <= position }) else { return 0 }
            let column = min(line.length, max(0, position - line.old))
            return min(formatted.utf16.count, line.new + line.inserted + max(0, column - line.removed))
        }
        let selection = textView.selectedRange, offsetBefore = textView.contentOffset
        replace(NSRange(location: 0, length: original.utf16.count), with: formatted, action: "Format Code")
        let start = moved(selection.location), end = moved(NSMaxRange(selection))
        textView.selectedRange = NSRange(location: start, length: max(0, end - start))
        textView.setContentOffset(offsetBefore, animated: false)
    }

    /// Return true only when a custom insertion replaced UIKit's normal edit.
    @objc func handleChange(in range: NSRange, replacement: String) -> Bool {
        guard !applying, let textView, textView.markedTextRange == nil,
              range.length == 0, replacement == "\n" || replacement == "}" else { return false }
        let source = textView.text ?? "", ns = source as NSString
        guard range.location <= ns.length else { return false }
        let lexical = CodeCompletionEngine.codeOnly(source, language: language)
        guard lexical.codePositions[range.location] else { return false }
        let before = ns.substring(to: range.location)
        let line = before.components(separatedBy: "\n").last ?? ""
        let indent = String(line.prefix { $0 == " " || $0 == "\t" })
        if replacement == "}" {
            guard line == indent, !indent.isEmpty else { return false }
            let drop = indent.hasSuffix("\t") ? 1 : min(3, indent.count)
            replace(NSRange(location: range.location - drop, length: drop), with: "}", action: "Indent")
            return true
        }
        let maskedBefore = ((lexical.text as NSString).substring(to: range.location).components(separatedBy: "\n").last ?? "").trimmingCharacters(in: .whitespaces)
        let opens = maskedBefore.hasSuffix("{")
        var insertion = "\n" + indent + (opens ? "   " : "")
        let caret = range.location + insertion.utf16.count
        if opens, range.location < ns.length, ns.character(at: range.location) == 125 {
            insertion += "\n" + indent
        }
        replace(range, with: insertion, action: "Indent")
        textView.selectedRange = NSRange(location: caret, length: 0)
        return true
    }

    private func replace(_ range: NSRange, with text: String, action: String) {
        guard let textView else { return }
        applying = true
        textView.undoManager?.beginUndoGrouping()
        textView.selectedRange = range
        textView.insertText(text)
        textView.undoManager?.setActionName(action)
        textView.undoManager?.endUndoGrouping()
        applying = false
        didChange?()
    }

    @objc func find(from presenter: UIViewController) {
        guard let textView else { return }
        if #available(iOS 16.0, *) {
            textView.findInteraction?.presentFindNavigator(showingReplace: true)
        } else {
            // The native navigator is available on iOS 16+. Keep basic search and
            // replacement available on the app's oldest supported OS as well.
            let alert = UIAlertController(title: "Find and Replace", message: "Search this file (case sensitive).", preferredStyle: .alert)
            alert.addTextField { $0.placeholder = "Find"; $0.autocapitalizationType = .none; $0.autocorrectionType = .no }
            alert.addTextField { $0.placeholder = "Replace with"; $0.autocapitalizationType = .none; $0.autocorrectionType = .no }
            alert.addAction(UIAlertAction(title: "Find Next", style: .default) { _ in
                guard let query = alert.textFields?.first?.text, !query.isEmpty else { return }
                let text = textView.text as NSString
                let start = min(NSMaxRange(textView.selectedRange), text.length)
                var found = text.range(of: query, range: NSRange(location: start, length: text.length - start))
                if found.location == NSNotFound { found = text.range(of: query) }
                if found.location != NSNotFound {
                    textView.selectedRange = found
                    textView.scrollRangeToVisible(found)
                } else {
                    let missing = UIAlertController(title: "No Matches", message: query, preferredStyle: .alert)
                    missing.addAction(UIAlertAction(title: "OK", style: .default))
                    presenter.present(missing, animated: true)
                }
            })
            alert.addAction(UIAlertAction(title: "Replace All", style: .default) { [weak self] _ in
                guard let query = alert.textFields?.first?.text, !query.isEmpty else { return }
                let original = textView.text ?? ""
                let result = original.replacingOccurrences(of: query, with: alert.textFields?[1].text ?? "")
                if original != result { self?.replace(NSRange(location: 0, length: original.utf16.count), with: result, action: "Replace All") }
            })
            alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
            presenter.present(alert, animated: true)
        }
    }
}
