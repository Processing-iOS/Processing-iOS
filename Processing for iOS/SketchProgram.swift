import Foundation

struct SketchSource {
    let name: String
    let content: String
    let firstLine: Int

    static func normalized(_ text: String) -> String {
        text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
    }

    var lineCount: Int { Self.normalized(content).components(separatedBy: "\n").count }

    func range(line: Int, column: Int = 0) -> NSRange? {
        guard line > 0, line <= lineCount else { return nil }
        let text = content as NSString
        var start = 0
        for _ in 1..<line {
            guard start < text.length else { return nil }
            start = NSMaxRange(text.lineRange(for: NSRange(location: start, length: 0)))
        }
        guard start <= text.length else { return nil }
        let lineRange = text.lineRange(for: NSRange(location: start, length: 0))
        if column > 0 {
            // WebKit columns and UIKit ranges both count UTF-16 code units.
            let offset = column - 1
            guard offset <= lineRange.length else { return nil }
            let location = start + offset
            return NSRange(location: location, length: location < text.length ? 1 : 0)
        }
        return lineRange
    }
}

/// An immutable snapshot: execution order, HTML and diagnostics use the same source.
@objc class SketchProgram: NSObject {
    let sources: [SketchSource]
    let language: String
    @objc let htmlPage: String
    @objc let preflightBug: DetectedBug?

    @objc init(project: SimpleTextProject) throws {
        language = project.sourceCodeExtension
        var nextLine = 1
        sources = try project.sourceFileURLs().map { url in
            let content: String
            do {
                content = try String(contentsOf: url, encoding: .utf8)
            } catch {
                throw Self.failure("Cannot read \(url.lastPathComponent). \(error.localizedDescription)")
            }
            let source = SketchSource(name: url.lastPathComponent, content: content, firstLine: nextLine)
            nextLine += source.lineCount
            return source
        }
        guard !sources.isEmpty else {
            throw Self.failure("This project contains no .\(language) source files.")
        }
        let code = sources.map { SketchSource.normalized($0.content) + "\n" }.joined()
        let scanned = language == "pde" ? ProcessingSourceScanner.scan(code) : nil
        if let issue = scanned?.issue ?? scanned.flatMap({ Self.unsupportedImport(in: $0.code) }) {
            let bug = DetectedBug(bugType: .syntaxError, message: issue.message)
            let prefix = (code as NSString).substring(to: issue.offset)
            let lines = prefix.components(separatedBy: "\n")
            if let file = sources.last(where: { $0.firstLine <= lines.count }),
               let range = file.range(line: lines.count - file.firstLine + 1,
                                      column: (lines.last! as NSString).length + 1) {
                bug.locate(in: file, range: range)
            }
            preflightBug = bug
        } else {
            preflightBug = nil
        }
        let libraryNames = language == "pde" ? ["processing.min", "ProcessingCompatibility"] : ["p5.min", "p5.sound.min"]
        let libraries = try libraryNames.map { ["name": $0 + ".js", "code": try Self.resource($0, extension: "js")] }
        let payload: [String: Any] = ["language": language, "code": code, "libraries": libraries]
        let data = try JSONSerialization.data(withJSONObject: payload)
        // JSON is data, never HTML. Escape script terminators and JavaScript line separators.
        let json = String(decoding: data, as: UTF8.self)
            .replacingOccurrences(of: "<", with: "\\u003c")
            .replacingOccurrences(of: "\u{2028}", with: "\\u2028")
            .replacingOccurrences(of: "\u{2029}", with: "\\u2029")
        let bridge = try Self.resource("SketchRuntime", extension: "js")
        let title = project.name.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
        htmlPage = """
        <!doctype html><html><head><meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <title>\(title)</title>
        <style>html,body{margin:0;width:100%;height:100%;overflow:hidden;}
        *{-webkit-touch-callout:none;-webkit-user-select:none;}</style></head><body>
        <script>\(bridge)</script>
        <script>SketchRuntime.start(\(json));</script>
        </body></html>
        """
        super.init()
    }

    @objc func bug(fromMessage body: Any) -> DetectedBug? {
        guard let payload = body as? [String: Any], let message = payload["message"] as? String,
              let bug = CodeErrorDetectionEngine.bug(fromString: message) else { return nil }
        // Only original JS source locations can be mapped directly. Processing.js transforms
        // PDE into JavaScript; its generated line numbers must never be presented as PDE lines.
        let url = payload["url"] as? String ?? ""
        let line = Self.positiveInteger(payload["line"])
        let column = Self.positiveInteger(payload["column"])
        if language == "js", url == "sketch-source.js", line > 0,
           let file = sources.last(where: { $0.firstLine <= line }),
           let range = file.range(line: line - file.firstLine + 1, column: column) {
            bug.locate(in: file, range: tokenRange(bug.wrongCode, in: file, near: range) ?? range)
        } else if language == "pde", !bug.wrongCode.isEmpty {
            // Without a source map, navigate only when a token has one unambiguous occurrence.
            var matches: [(SketchSource, NSRange)] = []
            for file in sources {
                let masked = ProcessingSourceScanner.scan(file.content).code
                for range in identifierRanges(bug.wrongCode, in: masked) {
                    matches.append((file, range))
                }
            }
            if matches.count == 1, let match = matches.first {
                bug.locate(in: match.0, range: match.1)
            }
        }
        return bug
    }

    private func tokenRange(_ token: String, in file: SketchSource, near range: NSRange) -> NSRange? {
        guard !token.isEmpty else { return nil }
        let candidates = identifierRanges(token, in: file.content)
        // WebKit may point at the opening parenthesis just after a missing function name.
        return candidates.first {
            NSLocationInRange(range.location, $0) || NSMaxRange($0) == range.location
        }
    }

    private func identifierRanges(_ token: String, in code: String) -> [NSRange] {
        let pattern = #"(?<![\p{L}\p{N}_$])"# + NSRegularExpression.escapedPattern(for: token) + #"(?![\p{L}\p{N}_$])"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        return regex.matches(in: code, range: NSRange(code.startIndex..., in: code)).map(\.range)
    }

    private static func positiveInteger(_ value: Any?) -> Int {
        guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() else { return 0 }
        let n = number.doubleValue
        guard n.isFinite, n > 0, n < Double(Int32.max), n.rounded() == n else { return 0 }
        return Int(n)
    }

    private static func unsupportedImport(in code: String) -> ProcessingSourceScanner.Issue? {
        let pattern = #"\bimport\s+(?:static\s+)?([\w.*]+)\s*;"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let allowed = ["processing.core.*", "processing.data.*", "processing.data.StringList",
                       "java.util.ArrayList", "java.util.HashMap", "java.util.Iterator", "java.util.*"]
        for match in regex.matches(in: code, range: NSRange(code.startIndex..., in: code)) {
            let name = (code as NSString).substring(with: match.range(at: 1))
            if allowed.contains(name) || name.hasPrefix("processing.core.") { continue }
            let help = name.hasPrefix("processing.video.")
                ? "Use CameraView(\"back\") or CameraView(\"front\") for camera input."
                : "Use the built-in APIs or a p5.js project with browser-compatible JavaScript libraries."
            return ProcessingSourceScanner.Issue(message: "Desktop Java package “\(name)” cannot run in Processing.js on iOS. \(help)", offset: match.range.location)
        }
        return nil
    }

    private static func resource(_ name: String, extension ext: String) throws -> String {
        guard let url = Bundle.main.url(forResource: name, withExtension: ext) else {
            throw failure("The sketch runtime is missing \(name).\(ext). Please reinstall the app.")
        }
        return try String(contentsOf: url, encoding: .utf8)
    }

    private static func failure(_ message: String) -> NSError {
        NSError(domain: "SketchRuntime", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }
}

/// A conservative PDE lexical pass, not a replacement for the Processing compiler.
/// Ignores comments and quoted literals; reports only definite structural errors.
private enum ProcessingSourceScanner {
    struct Issue { let message: String; let offset: Int }
    struct Result { let code: String; let issue: Issue? }

    static func scan(_ source: String) -> Result {
        let text = Array(source.utf16)
        var masked = text
        var stack: [(UInt16, Int)] = []
        var index = 0
        var issue: Issue?
        func hide(_ start: Int, _ end: Int) {
            for position in start..<end where text[position] != 10 && text[position] != 13 {
                masked[position] = 32
            }
        }
        while index < text.count {
            let c = text[index]
            let next = index + 1 < text.count ? text[index + 1] : 0
            if c == 47 && next == 47 {
                let start = index
                while index < text.count && text[index] != 10 && text[index] != 13 { index += 1 }
                hide(start, index)
                continue
            }
            if c == 47 && next == 42 {
                let start = index
                index += 2
                while index + 1 < text.count && !(text[index] == 42 && text[index + 1] == 47) { index += 1 }
                if index + 1 >= text.count {
                    issue = Issue(message: "SyntaxError: Unclosed block comment. Add */.", offset: start)
                    hide(start, text.count)
                    break
                }
                index += 2
                hide(start, index)
                continue
            }
            if c == 34 || c == 39 {
                let start = index
                index += 1
                while index < text.count && text[index] != c && text[index] != 10 && text[index] != 13 {
                    if text[index] == 92 { index += 1 }
                    if index < text.count { index += 1 }
                }
                if index >= text.count || text[index] != c {
                    issue = Issue(message: "SyntaxError: Unclosed quoted literal.", offset: start)
                    break
                }
                index += 1
                hide(start, index)
                continue
            }
            if [40, 91, 123].contains(c) { stack.append((c, index)) }
            if let expected = [UInt16(41): UInt16(40), 93: 91, 125: 123][c] {
                guard let opening = stack.last, opening.0 == expected else {
                    issue = Issue(message: "SyntaxError: Unexpected closing bracket \(String(UnicodeScalar(c)!)).", offset: index)
                    break
                }
                stack.removeLast()
            }
            index += 1
        }
        if issue == nil, let opening = stack.last {
            let closing: [UInt16: String] = [40: ")", 91: "]", 123: "}"]
            issue = Issue(message: "SyntaxError: Missing \(closing[opening.0]!) for this opening bracket.", offset: opening.1)
        }
        return Result(code: String(decoding: masked, as: UTF16.self), issue: issue)
    }
}
