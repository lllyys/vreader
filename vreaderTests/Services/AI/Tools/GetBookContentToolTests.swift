// Purpose: Feature #91 WI-6c — pin the get_book_content orchestration over a stub
// BookContentProvider: resolve by title (ambiguity-aware); gate on locality +
// format (the pure GetBookContentGate, tested separately) producing explicit
// isError results for not-found / ambiguous / not-local / unsupported-format;
// extract + char/byte-cap the text; a read failure → isError — never a throw.
// Also pins the structural canonical-format derivation (drift-proof, Gate-4 High).
//
// @coordinates-with: GetBookContentTool.swift, GetBookContentGate.swift,
//   dev-docs/plans/20260603-feature-91-agentic-tool-calling.md (WI-6c)

import Testing
import Foundation
@testable import vreader

private enum StubProviderError: Error { case boom }

private actor StubContentProvider: BookContentProvider {
    private let resolution: BookTitleResolution
    private let text: String
    private let extractThrows: Bool
    private(set) var findCalls = 0
    private(set) var extractCalls = 0

    init(resolution: BookTitleResolution, text: String = "", extractThrows: Bool = false) {
        self.resolution = resolution
        self.text = text
        self.extractThrows = extractThrows
    }

    func findBook(title: String) async -> BookTitleResolution {
        findCalls += 1
        return resolution
    }

    func extractText(fingerprintKey: String) async throws -> String {
        extractCalls += 1
        if extractThrows { throw StubProviderError.boom }
        return text
    }
}

@Suite("Feature #91 WI-6c — GetBookContentTool")
struct GetBookContentToolTests {

    private static func info(
        format: String, local: Bool = true, title: String = "The Book"
    ) -> BookContentInfo {
        BookContentInfo(
            fingerprintKey: "\(format):\(String(repeating: "a", count: 64)):4096",
            title: title, isReadable: local)
    }

    private func tool(
        _ provider: StubContentProvider, maxChars: Int = 8_000, maxContentBytes: Int = 16_000
    ) -> GetBookContentTool {
        GetBookContentTool(provider: provider, maxChars: maxChars, maxContentBytes: maxContentBytes)
    }

    // MARK: - Structural canonical-format derivation (Gate-4 High)

    @Test("BookContentInfo.format is DERIVED from the fingerprint key, never a column")
    func formatDerivedFromKey() {
        #expect(Self.info(format: "txt").format == "txt")
        #expect(Self.info(format: "epub").format == "epub")
        #expect(Self.info(format: "azw3").format == "azw3")
        // A malformed key derives nil (no format to trust).
        #expect(BookContentInfo(fingerprintKey: "txt:bad:1", title: "X", isReadable: true).format == nil)
    }

    @Test("a book with a malformed fingerprint key reports unreadable metadata, never extracts")
    func malformedKeyUnreadable() async {
        let provider = StubContentProvider(
            resolution: .found(BookContentInfo(fingerprintKey: "txt:bad:1", title: "Broken", isReadable: true)),
            text: "secret")
        let result = await tool(provider).run(.object(["title": .string("Broken")]))
        #expect(result.isError == true)
        #expect(result.content.localizedCaseInsensitiveContains("unreadable metadata"))
        #expect(await provider.extractCalls == 0)
    }

    // MARK: - Definition

    @Test("definition advertises the tool name + required title")
    func definitionShape() {
        let def = tool(StubContentProvider(resolution: .notFound)).definition
        #expect(def.name == "get_book_content")
        #expect(def.inputSchema["required"] == .array([.string("title")]))
        #expect(def.inputSchema["properties"]?["title"]?["type"]?.stringValue == "string")
    }

    // MARK: - Bad input

    @Test("a missing title yields an isError result and does NOT resolve a book")
    func missingTitle() async {
        let provider = StubContentProvider(resolution: .found(Self.info(format: "epub")))
        let result = await tool(provider).run(.object(["nope": .number(1)]))
        #expect(result.isError == true)
        #expect(await provider.findCalls == 0)
    }

    // MARK: - Resolution + gating (each an explicit isError result)

    @Test("a title with no matching book reports not-found")
    func bookNotFound() async {
        let provider = StubContentProvider(resolution: .notFound)
        let result = await tool(provider).run(.object(["title": .string("Ghost")]))
        #expect(result.isError == true)
        #expect(result.content.localizedCaseInsensitiveContains("no book titled"))
        #expect(await provider.extractCalls == 0)
    }

    @Test("two books sharing a title yield an ambiguity result with authors, never extracts")
    func ambiguousTitle() async {
        let provider = StubContentProvider(resolution: .ambiguous([
            BookContentMatch(title: "Dune", author: "Frank Herbert"),
            BookContentMatch(title: "Dune", author: "Someone Else"),
        ]))
        let result = await tool(provider).run(.object(["title": .string("Dune")]))
        #expect(result.isError == true)
        #expect(result.content.localizedCaseInsensitiveContains("several books match"))
        #expect(result.content.contains("Frank Herbert"))   // author disambiguator surfaced
        #expect(await provider.extractCalls == 0)            // never picks one silently
    }

    @Test("a remote-only book reports 'not downloaded', never extracts")
    func notLocal() async {
        let provider = StubContentProvider(resolution: .found(Self.info(format: "epub", local: false)))
        let result = await tool(provider).run(.object(["title": .string("The Book")]))
        #expect(result.isError == true)
        #expect(result.content.localizedCaseInsensitiveContains("isn't downloaded"))
        #expect(await provider.extractCalls == 0)
    }

    @Test("a native AZW3 book reports unsupported-format, never extracts")
    func unsupportedFormat() async {
        let provider = StubContentProvider(resolution: .found(Self.info(format: "azw3")))
        let result = await tool(provider).run(.object(["title": .string("The Book")]))
        #expect(result.isError == true)
        #expect(result.content.contains("AZW3"))
        #expect(result.content.localizedCaseInsensitiveContains("can't be extracted"))
        #expect(await provider.extractCalls == 0)
    }

    @Test("locality is reported before format: a remote AZW3 says 'not downloaded'")
    func localityBeatsFormat() async {
        let provider = StubContentProvider(resolution: .found(Self.info(format: "azw3", local: false)))
        let result = await tool(provider).run(.object(["title": .string("The Book")]))
        #expect(result.isError == true)
        #expect(result.content.localizedCaseInsensitiveContains("isn't downloaded"))
    }

    // MARK: - Happy path

    @Test("a local supported book returns its text under a header")
    func extractsLocalBook() async {
        let provider = StubContentProvider(
            resolution: .found(Self.info(format: "epub", title: "Moby Dick")), text: "Call me Ishmael.")
        let result = await tool(provider).run(.object(["title": .string("Moby Dick")]))
        #expect(result.isError == false)
        #expect(result.content.contains("Call me Ishmael."))
        #expect(result.content.contains("Moby Dick"))
        #expect(await provider.extractCalls == 1)
    }

    @Test("an extraction failure becomes an isError result, not a crash")
    func extractThrows() async {
        let provider = StubContentProvider(
            resolution: .found(Self.info(format: "txt")), text: "", extractThrows: true)
        let result = await tool(provider).run(.object(["title": .string("The Book")]))
        #expect(result.isError == true)
        #expect(result.content.localizedCaseInsensitiveContains("couldn't read"))
    }

    // MARK: - Caps

    @Test("max_chars caps the returned text")
    func maxCharsCap() async {
        let long = (0..<300).map { "L\($0)" }.joined(separator: " ")
        let provider = StubContentProvider(resolution: .found(Self.info(format: "txt")), text: long)
        let result = await tool(provider).run(
            .object(["title": .string("The Book"), "max_chars": .number(30)]))
        #expect(result.isError == false)
        #expect(result.content.contains("L0"))        // early text present
        #expect(!result.content.contains("L299"))     // late text capped off
        #expect(result.content.contains("…"))         // truncation marker
    }

    @Test("start_char windows into a LATER section of the text")
    func startCharWindowsLater() async {
        let text = String(repeating: "A", count: 50) + String(repeating: "B", count: 50)
        let provider = StubContentProvider(resolution: .found(Self.info(format: "txt")), text: text)
        let result = await tool(provider).run(
            .object(["title": .string("The Book"), "start_char": .number(50), "max_chars": .number(10)]))
        #expect(result.isError == false)
        #expect(result.content.contains("BBBBBBBBBB"))     // the window at offset 50
        #expect(!result.content.contains("AAAA"))          // the earlier section is skipped
        #expect(result.content.contains("characters 50–60 of 100"))
    }

    @Test("a start_char past the end is an explicit out-of-range error")
    func startCharOutOfRange() async {
        let provider = StubContentProvider(
            resolution: .found(Self.info(format: "txt")), text: "short")   // 5 chars
        let result = await tool(provider).run(
            .object(["title": .string("The Book"), "start_char": .number(100)]))
        #expect(result.isError == true)
        #expect(result.content.localizedCaseInsensitiveContains("past the end"))
    }

    @Test("a book with no extractable text reports it, not an empty success")
    func emptyExtract() async {
        let provider = StubContentProvider(resolution: .found(Self.info(format: "txt")), text: "")
        let result = await tool(provider).run(.object(["title": .string("The Book")]))
        #expect(result.isError == false)
        #expect(result.content.localizedCaseInsensitiveContains("no extractable text"))
        #expect(await provider.extractCalls == 1)
    }

    @Test("the returned content is byte-bounded even for a large CJK book")
    func byteBounded() async {
        let cjk = String(repeating: "这是一本很长的中文书。", count: 200)   // multibyte, large
        let provider = StubContentProvider(resolution: .found(Self.info(format: "txt")), text: cjk)
        let result = await tool(provider, maxChars: 5_000, maxContentBytes: 512)
            .run(.object(["title": .string("The Book")]))
        #expect(result.isError == false)
        #expect(result.content.utf8.count <= 512)
        #expect(result.content.contains("…"))   // body byte-clamped → more text remains
    }

    @Test("the range header's END reflects the byte-clamped body, not the pre-clamp window")
    func headerEndMatchesClampedBody() async {
        // A CJK book whose window (5000-char request) is byte-clamped well short of
        // 5000 chars → the header's END must equal the chars actually returned, so a
        // model paging with start_char=END does not skip the clamped-off text.
        let total = 400
        let cjk = String(repeating: "字", count: total)   // 400 chars, 1200 bytes
        let provider = StubContentProvider(resolution: .found(Self.info(format: "txt")), text: cjk)
        let result = await tool(provider, maxChars: 5_000, maxContentBytes: 300)
            .run(.object(["title": .string("The Book")]))
        #expect(result.isError == false)
        #expect(result.content.utf8.count <= 300)
        // Parse the END the header advertises and count the '字' chars actually present.
        let returned = result.content.filter { $0 == "字" }.count
        #expect(result.content.contains("characters 0–\(returned) of \(total)"))
        #expect(returned < total)                 // it WAS clamped short of the full book
    }
}
