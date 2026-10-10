import Testing
@testable import Processing_for_iOS

struct SketchDiagnosticsTests {
    @Test(arguments: [
        "ReferenceError: Can't find variable: missingValue",
        "ReferenceError: missingValue is not defined",
        "SyntaxError: Unexpected token '}'",
        "TypeError: null is not an object (evaluating 'value.x')",
        "RangeError: Maximum call stack size exceeded",
        "Sketch failed for an unexpected reason"
    ])
    func runtimeErrorsAreNeverSilentlyDiscarded(message: String) {
        #expect(CodeErrorDetectionEngine.bug(fromString: message) != nil)
    }
}

import Foundation
import WebKit

// WebKit rendering requires the shared host window; keep these integration tests serial.
@Suite(.serialized)
@MainActor
struct SketchRuntimeTests {
    struct FailureCase: Sendable {
        let language: String
        let main: String
        var helper: String? = nil
        let message: String
        var file: String? = nil
        var line: Int? = nil
    }

    @Test(arguments: [
        FailureCase(language: "js", main: "function setup() {\n  missingValue();\n}", message: "missingValue", file: "main", line: 2),
        FailureCase(language: "js", main: "function setup() { helper(); }", helper: "function helper() {\n  const value = null;\n  value.x();\n}", message: "TypeError", file: "Helper.js", line: 3),
        FailureCase(language: "js", main: "function setup() {\n const x = ;\n}", message: "SyntaxError", file: "main", line: 2),
        FailureCase(language: "js", main: "function setup() { createCanvas(20,20); }\nfunction draw() { throw new RangeError('draw failed'); }", message: "draw failed", file: "main", line: 2),
        FailureCase(language: "js", main: "function setup() {\n Promise.reject(new Error('async failed'));\n}", message: "async failed", file: "main", line: 2),
        FailureCase(language: "js", main: "throw 'plain thrown value';", message: "plain thrown value"),
        FailureCase(language: "js", main: "Promise.reject('   ');", message: "empty error"),
        FailureCase(language: "js", main: "function setup() {\n setTimeout(() => { throw new Error('timer failed'); }, 0);\n}", message: "timer failed", file: "main", line: 2),
        FailureCase(language: "js", main: "function setup() { helper(); }", helper: "// 🧑🏽‍💻\r\nfunction helper() {\r\n missingValue();\r\n}", message: "missingValue", file: "Helper.js", line: 3),
        FailureCase(language: "js", main: "function setup() {\n const element = document.createElement('img');\n element.src = 'data/missing.png';\n document.body.appendChild(element);\n}", message: "Could not load resource"),
        FailureCase(language: "js", main: "function preload() { loadImage('data/missing.png'); }\nfunction setup() { createCanvas(20,20); }", message: "Could not load resource", file: "main", line: 1),
        FailureCase(language: "js", main: "throw {toString() { throw 1; }, get stack() { throw 2; }};", message: "unreadable error"),
        FailureCase(language: "pde", main: "/* @pjs preload=\"data/missing.png\"; */\nvoid setup() { size(20,20); }", message: "Could not load resource"),
        FailureCase(language: "pde", main: "void setup() { size(20,20); }\nvoid draw() { missingValue(); }", message: "missingValue", file: "main", line: 2),
        FailureCase(language: "pde", main: "void setup() {\n int x = ;\n}", message: "SyntaxError")
    ])
    func actualRuntimeReportsFailures(example: FailureCase) async throws {
        let fixture = try SketchFixture(language: example.language, main: example.main,
                                        helper: example.helper.map { ["Helper.js": $0] } ?? [:])
        defer { fixture.remove() }
        let program = try fixture.project.prepareRuntime()
        #expect(program.preflightBug == nil)
        let browser = RuntimeProbe()
        defer { browser.close() }
        try browser.load(program, in: fixture.project.folder)
        let payload = try await browser.message(named: "error")
        let bug = try #require(program.bug(fromMessage: payload))
        #expect(bug.message.contains(example.message))
        if let file = example.file {
            #expect(bug.fileName == (file == "main" ? fixture.mainName : file))
            #expect(bug.line == example.line)
            if !bug.wrongCode.isEmpty {
                let source = try #require(program.sources.first { $0.name == bug.fileName })
                #expect((source.content as NSString).substring(with: bug.range(inSource: source.content)) == bug.wrongCode)
            }
        }
    }

    @Test(arguments: ["js", "pde"])
    func validSketchRendersWithQuotesUnicodeAndHTMLInsideStrings(language: String) async throws {
        let literal = "</script><script>throw new Error('injected')</script> 🧑🏽‍💻 % %@"
        let code = language == "js" ?
            "const text = \"\(literal)\";\nfunction setup() { createCanvas(20,20); background(23,45,67); noLoop(); }" :
            "String text = \"\(literal)\";\nvoid setup() { size(20,20); background(23,45,67); noLoop(); }"
        let fixture = try SketchFixture(language: language, main: code)
        defer { fixture.remove() }
        let program = try fixture.project.prepareRuntime()
        #expect(program.preflightBug == nil)
        let browser = RuntimeProbe()
        defer { browser.close() }
        try browser.load(program, in: fixture.project.folder)
        _ = try await browser.message(named: "iosbridge", event: "ready")
        _ = try await browser.message(named: "iosbridge", event: "heartbeat")
        let pixel = try await browser.webView.evaluateJavaScript("Array.from(document.querySelector('canvas').getContext('2d').getImageData(0,0,1,1).data)") as? [Int]
        #expect(pixel == [23, 45, 67, 255])
        #expect(browser.errors.isEmpty)
    }

    @Test func executionOrderAndSecondFileLocationsStayStable() async throws {
        let fixture = try SketchFixture(language: "js", main: "const order = ['main'];", helper: [
            "ZLast.js": "order.push('last');\nfunction setup() { window.result = order.join(','); noLoop(); }",
            "AFirst.js": "order.push('first');"
        ])
        defer { fixture.remove() }
        let browser = RuntimeProbe()
        defer { browser.close() }
        try browser.load(fixture.project.prepareRuntime(), in: fixture.project.folder)
        _ = try await browser.message(named: "iosbridge", event: "ready")
        _ = try await browser.message(named: "iosbridge", event: "heartbeat")
        let order = try await browser.webView.evaluateJavaScript("window.result") as? String
        #expect(order == "main,first,last")
        #expect(browser.errors.isEmpty)
    }

    @Test func explicitlyHandledAssetFailuresCanRecover() async throws {
        let fixture = try SketchFixture(language: "js", main: "function setup() { loadImage('data/missing.png', () => {}, () => { window.webkit.messageHandlers.iosbridge.postMessage({event:'recovered'}); }); noLoop(); }")
        defer { fixture.remove() }
        let browser = RuntimeProbe()
        defer { browser.close() }
        try browser.load(fixture.project.prepareRuntime(), in: fixture.project.folder)
        _ = try await browser.message(named: "iosbridge", event: "recovered")
        #expect(browser.errors.isEmpty)
    }

    @Test func reportsOnlyTheFirstFailure() async throws {
        let fixture = try SketchFixture(language: "js", main: "function setup() { setTimeout(() => { throw new Error('first'); }, 0); }")
        defer { fixture.remove() }
        let browser = RuntimeProbe()
        defer { browser.close() }
        try browser.load(fixture.project.prepareRuntime(), in: fixture.project.folder)
        _ = try await browser.message(named: "error")
        _ = try await browser.webView.evaluateJavaScript("window.dispatchEvent(new ErrorEvent('error', {message:'second', error:new Error('second')}))")
        #expect(browser.errors.count == 1)
    }

    @Test(arguments: [
        ("void setup() {\n size(20,20);", 1, "Missing }"),
        ("void setup() {\n size(20,20];\n}", 2, "Unexpected closing"),
        ("/* unterminated", 1, "Unclosed block comment"),
        ("String value = \"unterminated;", 1, "Unclosed quoted literal")
    ])
    func processingStructureErrorsHaveOriginalLocations(code: String, line: Int, message: String) throws {
        let fixture = try SketchFixture(language: "pde", main: code)
        defer { fixture.remove() }
        let bug = try #require(fixture.project.prepareRuntime().preflightBug)
        #expect(bug.fileName == fixture.mainName)
        #expect(bug.line == line)
        #expect(bug.message.contains(message))
        #expect(bug.range(inSource: code).location != NSNotFound)
    }

    @Test func processingIgnoresBracketsAndIdentifiersInsideCommentsAndStrings() throws {
        let code = "// missingValue {\r\nString text = \"missingValue [ \\\"\";\r\nvoid setup() { missingValue(); }\r\n/* } */"
        let fixture = try SketchFixture(language: "pde", main: code, helper: ["Other.pde": "// missingValue"])
        defer { fixture.remove() }
        let program = try fixture.project.prepareRuntime()
        #expect(program.preflightBug == nil)
        let bug = try #require(program.bug(fromMessage: ["message": "ReferenceError: Can't find variable: missingValue"]))
        #expect(bug.fileName == fixture.mainName)
        #expect(bug.line == 3)
        #expect((code as NSString).substring(with: bug.range(inSource: code)) == "missingValue")
        #expect(bug.range(inSource: "// changed\n" + code).location == NSNotFound)
    }

    @Test func ambiguousProcessingReferencesDoNotGuessAFile() throws {
        let fixture = try SketchFixture(language: "pde", main: "void setup() { missingValue(); }",
                                        helper: ["Helper.pde": "void helper() { missingValue(); }"])
        defer { fixture.remove() }
        let program = try fixture.project.prepareRuntime()
        let bug = try #require(program.bug(fromMessage: ["message": "ReferenceError: Can't find variable: missingValue",
                                                         "url": "processing-generated.js", "line": 1]))
        #expect(!bug.hasSourceLocation)
    }

    @Test func bridgeRejectsMalformedPayloadsAndUnsafeLocations() throws {
        let fixture = try SketchFixture(language: "js", main: "let value = 1;")
        defer { fixture.remove() }
        let program = try fixture.project.prepareRuntime()
        for body: Any in [NSNull(), "oops", ["message": NSNull()], ["message": 42], ["message": ""]] {
            #expect(program.bug(fromMessage: body) == nil)
        }
        for line: Any in [-1, Int.max, true, "1", Double.infinity] {
            let bug = try #require(program.bug(fromMessage: ["message": "TypeError: invalid", "url": "sketch-source.js", "line": line]))
            #expect(!bug.hasSourceLocation)
        }
    }

    @Test(arguments: [false, true])
    func suggestionsOnlyReplaceTheLocatedTokenInUnchangedCode(editBeforeApplying: Bool) throws {
        let code = "void setup() {\n backgroun(23, 45, 67);\n}"
        let fixture = try SketchFixture(language: "pde", main: code)
        defer { fixture.remove() }
        let bug = try #require(fixture.project.prepareRuntime().bug(fromMessage: ["message": "ReferenceError: Can't find variable: backgroun"]))
        let file = try #require(fixture.project.sourceCodeFiles.first)
        let editor = PDEEditorViewController(sourceCodeFile: file)!
        editor.loadViewIfNeeded()
        editor.highlightCompilerError(ofCode: bug)
        if editBeforeApplying { editor.editor.text = "// a new edit\n" + code }
        editor.replaceCharacters(in: bug.range(inSource: code), with: "background")
        let expected = editBeforeApplying ? "// a new edit\n" + code : "void setup() {\n background(23, 45, 67);\n}"
        #expect(editor.editor.text == expected)
        if !editBeforeApplying { #expect(try String(contentsOfFile: file.filePath) == expected) }
    }

    @Test func failedSaveRetainsEditsAndDoesNotOverwriteTheStoredSketch() throws {
        let fixture = try SketchFixture(language: "js", main: "const original = 1;")
        defer { fixture.remove() }
        let file = try #require(fixture.project.sourceCodeFiles.first)
        let originalURL = URL(fileURLWithPath: file.filePath)
        let editor = PDEEditorViewController(sourceCodeFile: file)!
        editor.loadViewIfNeeded()
        editor.editor.text = "const edited = 2;"
        file.filePath = fixture.project.folder.path // A directory cannot be replaced by a source file.
        #expect(!editor.saveCode())
        #expect(file.saveError != nil)
        #expect(file.content == "const edited = 2;")
        #expect(try String(contentsOf: originalURL) == "const original = 1;")
        file.filePath = originalURL.path
        #expect(editor.saveCode())
        #expect(file.saveError == nil)
        #expect(try String(contentsOf: originalURL) == "const edited = 2;")
    }

    @Test func editorCompletionSupportsTypingUndoAndSaving() throws {
        let fixture = try SketchFixture(language: "js", main: "bac")
        defer { fixture.remove() }
        let file = try #require(fixture.project.sourceCodeFiles.first)
        let editor = PDEEditorViewController(sourceCodeFile: file)!
        let scene = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = try #require(scene.windows.first { $0.isKeyWindow })
        let previousRoot = window.rootViewController
        window.rootViewController = editor
        defer { editor.editor.resignFirstResponder(); window.rootViewController = previousRoot }
        editor.loadViewIfNeeded()
        #expect(editor.editor.becomeFirstResponder())
        editor.editor.selectedRange = NSRange(location: 3, length: 0)
        let show = try #require(editor.keyCommands?.first { $0.input == " " && $0.modifierFlags == .control })
        let showAction = try #require(show.action)
        #expect(UIApplication.shared.sendAction(showAction, to: editor, from: show, for: nil))
        let accept = try #require(editor.keyCommands?.first { $0.input == "\t" && $0.modifierFlags.isEmpty })
        let acceptAction = try #require(accept.action)
        #expect(UIApplication.shared.sendAction(acceptAction, to: editor, from: accept, for: nil))
        #expect(editor.editor.text == "background()")
        #expect(editor.editor.selectedRange.location == 11)
        let undo = try #require(editor.editor.undoManager)
        #expect(undo.canUndo)
        undo.undo()
        #expect(editor.editor.text == "bac")
        undo.redo()
        #expect(editor.editor.text == "background()")
        #expect(editor.saveCode())
        #expect(try String(contentsOfFile: file.filePath) == "background()")
    }

    @Test func unreadableAndEmptyProjectsFailBeforeLaunching() throws {
        let fixture = try SketchFixture(language: "js", main: "")
        defer { fixture.remove() }
        let url = fixture.project.folder.appendingPathComponent(fixture.mainName)
        try Data([0xff, 0xfe, 0xff]).write(to: url)
        #expect(throws: (any Error).self) { try fixture.project.prepareRuntime() }
        try FileManager.default.removeItem(at: url)
        #expect(throws: (any Error).self) { try fixture.project.prepareRuntime() }
    }
}

@MainActor
private struct SketchFixture {
    let project: SimpleTextProject
    var mainName: String { "\(project.name).\(project.sourceCodeExtension)" }

    init(language: String, main: String, helper: [String: String] = [:]) throws {
        let name = "DiagnosticTest_" + UUID().uuidString
        project = language == "pde" ? PDEProject(withProjectName: name) : P5JSProject(withProjectName: name)
        do {
            try main.write(to: project.folder.appendingPathComponent(mainName), atomically: true, encoding: .utf8)
            for (name, content) in helper {
                try content.write(to: project.folder.appendingPathComponent(name), atomically: true, encoding: .utf8)
            }
        } catch {
            remove()
            throw error
        }
    }

    func remove() { try? FileManager.default.removeItem(at: project.folder) }
}

@MainActor
private final class RuntimeProbe: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
    private(set) var webView: WKWebView!
    private var messages: [(String, [String: Any])] = []
    private var receive: ((String, [String: Any]) -> Void)?
    var errors: [[String: Any]] { messages.filter { $0.0 == "error" }.map(\.1) }

    override init() {
        super.init()
        let config = WKWebViewConfiguration()
        config.mediaTypesRequiringUserActionForPlayback = []
        config.preferences.setValue(true, forKey: "allowFileAccessFromFileURLs")
        config.userContentController.add(self, name: "error")
        config.userContentController.add(self, name: "iosbridge")
        webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 320, height: 480), configuration: config)
        webView.navigationDelegate = self
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        scene?.windows.first(where: \.isKeyWindow)?.addSubview(webView)
    }

    func load(_ program: SketchProgram, in folder: URL) throws {
        let url = folder.appendingPathComponent("test-runtime.html")
        try program.htmlPage.write(to: url, atomically: true, encoding: .utf8)
        webView.loadFileURL(url, allowingReadAccessTo: folder)
    }

    func close() {
        webView.stopLoading()
        webView.removeFromSuperview()
        webView.configuration.userContentController.removeAllScriptMessageHandlers()
        receive = nil
    }

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any] else { return }
        messages.append((message.name, body))
        receive?(message.name, body)
    }

    func message(named name: String, event: String? = nil) async throws -> [String: Any] {
        func matches(_ channel: String, _ body: [String: Any]) -> Bool {
            channel == name && (event == nil || body["event"] as? String == event)
        }
        if let existing = messages.first(where: { matches($0.0, $0.1) }) { return existing.1 }
        return try await withCheckedThrowingContinuation { continuation in
            let timeout = DispatchWorkItem { [weak self] in
                guard let self = self, self.receive != nil else { return }
                self.receive = nil
                continuation.resume(throwing: NSError(domain: "RuntimeTest", code: 1,
                    userInfo: [NSLocalizedDescriptionKey: "Timed out waiting for \(name). Received: \(self.messages)"]))
            }
            receive = { [weak self] channel, body in
                guard matches(channel, body) else { return }
                self?.receive = nil
                timeout.cancel()
                continuation.resume(returning: body)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 20, execute: timeout)
        }
    }
}
