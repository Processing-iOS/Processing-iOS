import Foundation

@objc enum BugType: Int {
    case referenceError, syntaxErrorVarUsage, unknownError, syntaxError, typeError, rangeError
}

@objc class DetectedBug: NSObject {
    @objc let bugType: BugType
    @objc let wrongCode: String
    @objc let message: String
    @objc private(set) var fileName: String?
    @objc private(set) var line = 0
    @objc private(set) var column = 0
    private var source: String?
    private var sourceRange = NSRange(location: NSNotFound, length: 0)

    init(bugType: BugType, message: String, wrongCode: String = "") {
        self.bugType = bugType
        self.message = message
        self.wrongCode = wrongCode
    }

    func locate(in file: SketchSource, range: NSRange) {
        let text = file.content as NSString
        guard range.location != NSNotFound, range.location <= text.length,
              range.length <= text.length - range.location else { return }
        fileName = file.name
        source = file.content
        sourceRange = range
        let prefix = text.substring(to: range.location)
        let lines = SketchSource.normalized(prefix).components(separatedBy: "\n")
        line = lines.count
        column = (lines.last! as NSString).length + 1
    }

    @objc var hasSourceLocation: Bool { fileName != nil }

    // Offsets belong to the exact source that ran. Never edit or underline stale text.
    @objc func range(inSource text: String) -> NSRange {
        guard source == text else { return NSRange(location: NSNotFound, length: 0) }
        return sourceRange
    }

    @objc var displayMessage: String {
        let location = fileName.map { "\($0):\(line)\(column > 0 ? ":\(column)" : "")\n\n" } ?? ""
        let advice: String
        switch bugType {
        case .referenceError: advice = "Check the spelling and make sure this variable or function is defined before it is used."
        case .syntaxErrorVarUsage: advice = "Processing uses typed declarations, such as int count = 0; use JavaScript declarations in a P5.js project."
        case .syntaxError: advice = "Check punctuation, quotes, brackets, and declarations near the error."
        case .typeError: advice = "Check that the value exists and supports the operation you are calling."
        case .rangeError: advice = "Check for infinite recursion or an invalid numeric range."
        case .unknownError: advice = ""
        }
        return location + message + (advice.isEmpty ? "" : "\n\n" + advice)
    }
}

@objc class CodeErrorDetectionEngine: NSObject {
    @objc static func bug(fromString string: String) -> DetectedBug? {
        let message = String(string.trimmingCharacters(in: .whitespacesAndNewlines).prefix(4000))
        guard !message.isEmpty else { return nil }
        let identifier = #"([\p{L}_$][\p{L}\p{N}_$]*)"#
        let patterns = [
            #"(?:ReferenceError:\s*)?Can't find variable:\s*"# + identifier,
            #"(?:ReferenceError:\s*)?"# + identifier + #" is not defined\b"#
        ]
        for pattern in patterns {
            if let token = capture(pattern, in: message) {
                return DetectedBug(bugType: .referenceError, message: message, wrongCode: token)
            }
        }
        if message.contains("Cannot use the keyword 'var' as a variable name") {
            return DetectedBug(bugType: .syntaxErrorVarUsage, message: message, wrongCode: "var")
        }
        let type: BugType
        if message.contains("SyntaxError") { type = .syntaxError }
        else if message.contains("ReferenceError") { type = .referenceError }
        else if message.contains("TypeError") { type = .typeError }
        else if message.contains("RangeError") { type = .rangeError }
        else { type = .unknownError }
        return DetectedBug(bugType: type, message: message)
    }

    static func capture(_ pattern: String, in text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range(at: 1), in: text) else { return nil }
        return String(text[range])
    }
}
