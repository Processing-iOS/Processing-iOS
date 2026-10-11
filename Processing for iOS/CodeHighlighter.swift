import UIKit

/// Colors a source snapshot off the typing path, then changes attributes only.
/// Never replace UITextView.text/attributedText: doing so resets native editing state.
@objc final class CodeHighlighter: NSObject {
    private weak var textView: UITextView?
    private let language: String
    private var pending: DispatchWorkItem?
    private var generation = 0
    private static let queue = DispatchQueue(label: "Processing.syntax", qos: .userInitiated)
    private static let identifier = try! NSRegularExpression(pattern: #"[$_\p{L}][$_\p{L}\p{M}\p{N}]*"#)

    @objc init(textView: UITextView, language: String) {
        self.textView = textView
        self.language = language
    }

    @objc func schedule() {
        pending?.cancel()
        generation += 1
        guard let textView, textView.markedTextRange == nil else { return }
        let source = textView.text ?? "", language = language, version = generation
        let size = textView.font?.pointSize ?? 18
        let task = DispatchWorkItem { [weak self] in
            let colored = Self.render(source, language: language, size: size)
            DispatchQueue.main.async { [weak self] in
                guard let self, self.generation == version, self.textView?.text == source else { return }
                self.apply(colored)
            }
        }
        pending = task
        Self.queue.asyncAfter(deadline: .now() + 0.08, execute: task)
    }

    @objc func highlightNow() {
        pending?.cancel()
        generation += 1
        guard let textView, textView.markedTextRange == nil else { return }
        apply(Self.render(textView.text ?? "", language: language, size: textView.font?.pointSize ?? 18))
    }

    private static func baseAttributes(size: CGFloat) -> [NSAttributedString.Key: Any] {
        let paragraph = NSMutableParagraphStyle()
        paragraph.headIndent = 32
        return [.font: UIFont(name: "SourceCodePro-Regular", size: size) ?? UIFont.monospacedSystemFont(ofSize: size, weight: .regular),
                .foregroundColor: UIColor.label, .paragraphStyle: paragraph]
    }

    private static func render(_ source: String, language: String, size: CGFloat) -> NSAttributedString {
        let result = NSMutableAttributedString(string: source, attributes: baseAttributes(size: size))
        let lexical = CodeCompletionEngine.codeOnly(source, language: language)
        let code = lexical.text as NSString
        let types = Set((language == "js" ? "let const var class JSON" : "int String boolean bool float double char color byte long PImage PFont PVector StringList CameraView").split(separator: " ").map(String.init))
        let keywords = Set("new void function if else for while do switch case break continue return true false null undefined async await import public private final".split(separator: " ").map(String.init))
        let parameters = Set("mouseX mouseY pmouseX pmouseY movedX movedY winMouseX winMouseY pwinMouseX pwinMouseY mouseButton touches mousePressed screenHeight screenWidth windowWidth windowHeight CENTER CORNER CORNERS RADIUS RIGHT LEFT HALF_PI PI QUARTER_PI TAU TWO_PI DEGREES RADIANS".split(separator: " ").map(String.init))
        let orange = UIColor(red: 228/255, green: 102/255, blue: 0, alpha: 1)
        let green = UIColor(red: 45/255, green: 154/255, blue: 126/255, alpha: 1)
        let blue = UIColor(red: 0, green: 101/255, blue: 155/255, alpha: 1)
        let parameter = UIColor(red: 117/255, green: 143/255, blue: 102/255, alpha: 1)
        identifier.enumerateMatches(in: lexical.text, range: NSRange(location: 0, length: code.length)) { match, _, _ in
            guard let range = match?.range else { return }
            let word = code.substring(with: range)
            var next = NSMaxRange(range)
            while next < code.length, let scalar = UnicodeScalar(code.character(at: next)), CharacterSet.whitespaces.contains(scalar) { next += 1 }
            let color: UIColor?
            if types.contains(word) { color = orange }
            else if keywords.contains(word) { color = green }
            else if parameters.contains(word) { color = parameter }
            else if next < code.length && code.character(at: next) == 40 { color = blue }
            else { color = nil }
            if let color { result.addAttribute(.foregroundColor, value: color, range: range) }
        }
        for span in lexical.spans {
            result.addAttribute(.foregroundColor, value: span.comment ? UIColor.secondaryLabel : UIColor(red: 126/255, green: 68/255, blue: 149/255, alpha: 1), range: span.range)
        }
        return result
    }

    private func apply(_ colored: NSAttributedString) {
        guard let textView, textView.markedTextRange == nil, textView.text == colored.string else { return }
        let offset = textView.contentOffset, selection = textView.selectedRange
        let undo = textView.undoManager
        let registered = undo?.isUndoRegistrationEnabled == true
        if registered { undo?.disableUndoRegistration() }
        textView.textStorage.beginEditing()
        colored.enumerateAttributes(in: NSRange(location: 0, length: colored.length)) { attributes, range, _ in
            textView.textStorage.setAttributes(attributes, range: range)
        }
        textView.textStorage.endEditing()
        if registered { undo?.enableUndoRegistration() }
        if textView.selectedRange != selection { textView.selectedRange = selection }
        textView.typingAttributes = Self.baseAttributes(size: textView.font?.pointSize ?? 18)
        textView.setContentOffset(offset, animated: false)
    }
}
