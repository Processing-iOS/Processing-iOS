import Foundation
import Testing
@testable import Processing_for_iOS

struct CodeCompletionTests {
    @Test(arguments: [
        "// back", "/* back", "\"back", "'back", "`back", "const pattern = /back",
        "const pattern = /[a-z]back", "object.back", "object.  back", "123back",
        "\"escaped \\\" back", "// 🧑🏽‍💻\r\n/* back"
    ])
    func doesNotSuggestInNonCodeOrMemberAccess(source: String) {
        let caret = NSRange(location: (source as NSString).length, length: 0)
        #expect(CodeCompletionEngine.request(source: source, selection: caret, language: "js", explicit: true) == nil)
    }

    struct EditCase: Sendable {
        let source: String
        let expected: String
    }

    @Test(arguments: [
        EditCase(source: "bac|", expected: "background(|)"),
        EditCase(source: "bac|(23, 45, 67);", expected: "background|(23, 45, 67);"),
        EditCase(source: "bac|kground(23);", expected: "background|(23);"),
        EditCase(source: "// 🧑🏽‍💻\r\n  bac| (42);", expected: "// 🧑🏽‍💻\r\n  background| (42);"),
        EditCase(source: "/* ignored */ bac|", expected: "/* ignored */ background(|)"),
        EditCase(source: "const ratio = width / bac|;", expected: "const ratio = width / background(|);"),
        EditCase(source: "// back\nbac|", expected: "// back\nbackground(|)")
    ])
    func editsOnlyTheIdentifierAndPlacesTheCaret(example: EditCase) throws {
        let (source, selection) = markedSource(example.source)
        let request = try #require(CodeCompletionEngine.request(source: source, selection: selection, language: "js"))
        let item = try #require(request.items.first { $0.name == "background" })
        let edit = try #require(request.edit(for: item, source: source, selection: selection))
        let result = (source as NSString).replacingCharacters(in: edit.range, with: edit.text)
        let expected = markedSource(example.expected)
        #expect(result == expected.0)
        #expect(edit.caret == expected.1.location)
    }

    @Test(arguments: ["js", "pde"])
    func offersCommandsForTheProjectLanguage(language: String) throws {
        let p5 = CodeCompletionEngine.request(source: "createCa", selection: NSRange(location: 8, length: 0), language: language)
        #expect(p5?.items.contains { $0.name == "createCanvas" } == (language == "js"))
        let pde = CodeCompletionEngine.request(source: "si", selection: NSRange(location: 2, length: 0), language: language)
        #expect(pde?.items.contains { $0.name == "size" } == (language == "pde"))
    }

    @Test func completesProjectNamesWithoutInventingFunctionCalls() throws {
        let names = CodeCompletionEngine.symbols(in: "let ballSpeed = 2; // balloonFake\nconst label = 'balloonText';", language: "js")
        let source = "const ballSize = 20;\nba"
        let caret = NSRange(location: (source as NSString).length, length: 0)
        let request = try #require(CodeCompletionEngine.request(source: source, selection: caret, language: "js", projectSymbols: names))
        #expect(request.items.contains { $0.name == "ballSize" })
        #expect(!request.items.contains { $0.name == "balloonFake" || $0.name == "balloonText" })
        let item = try #require(request.items.first { $0.name == "ballSpeed" })
        let edit = try #require(request.edit(for: item, source: source, selection: caret))
        #expect(edit.text == "ballSpeed")
    }

    @Test func rejectsStaleTextMovedCaretsAndUnsafeSelections() throws {
        let caret = NSRange(location: 3, length: 0)
        let request = try #require(CodeCompletionEngine.request(source: "bac", selection: caret, language: "js"))
        let item = try #require(request.items.first { $0.name == "background" })
        #expect(request.edit(for: item, source: "back", selection: caret) == nil)
        #expect(request.edit(for: item, source: "bac", selection: NSRange(location: 2, length: 0)) == nil)
        for selection in [NSRange(location: NSNotFound, length: 0), NSRange(location: -1, length: 0), NSRange(location: 9, length: 0), NSRange(location: 0, length: 3)] {
            #expect(CodeCompletionEngine.request(source: "bac", selection: selection, language: "js") == nil)
        }
    }

    @Test func explicitCompletionAllowsShortPrefixes() throws {
        let caret = NSRange(location: 1, length: 0)
        #expect(CodeCompletionEngine.request(source: "b", selection: caret, language: "pde") == nil)
        let request = try #require(CodeCompletionEngine.request(source: "b", selection: caret, language: "pde", explicit: true))
        #expect(request.items.contains { $0.name == "background" })
    }

    private func markedSource(_ marked: String) -> (String, NSRange) {
        let location = (marked as NSString).range(of: "|").location
        return (marked.replacingOccurrences(of: "|", with: ""), NSRange(location: location, length: 0))
    }
}
