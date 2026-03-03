import Testing
import Foundation

@testable import vreader

// MARK: - SearchService Tests

@Suite("SearchService")
struct SearchServiceTests {

    // MARK: - Helpers

    private func makeService(chapters: [String: String] = [:]) -> SearchService {
        SearchService(contentProvider: MockContentProvider(chapters: chapters))
    }

    private func single(_ text: String) -> [String: String] { ["0": text] }

    private func multi(_ texts: [String]) -> [String: String] {
        Dictionary(uniqueKeysWithValues: texts.enumerated().map {
            (String($0.offset), $0.element)
        })
    }

    // MARK: - Basic Search

    @Test("finds exact match in single chapter")
    func basicSearch() async {
        let svc = makeService(chapters: single(
            "The quick brown fox jumps over the lazy dog"
        ))
        let results = await svc.search(query: "brown fox")
        #expect(results.count == 1)
        #expect(results[0].chapterIndex == 0)
    }

    @Test("finds multiple matches in same chapter")
    func multipleMatches() async {
        let svc = makeService(chapters: single(
            "The cat sat on the mat. The cat ate the rat."
        ))
        let results = await svc.search(query: "the")
        #expect(results.count >= 3)
    }

    @Test("finds matches across chapters")
    func crossChapter() async {
        let svc = makeService(chapters: multi([
            "Chapter one has apple.", "No match.", "Also apple."
        ]))
        let results = await svc.search(query: "apple")
        #expect(results.count == 2)
    }

    @Test("case-insensitive by default")
    func caseInsensitive() async {
        let svc = makeService(chapters: single("Hello HELLO hello"))
        let results = await svc.search(query: "hello")
        #expect(results.count == 3)
    }

    // MARK: - Empty / No Match

    @Test("empty query returns no results")
    func emptyQuery() async {
        let results = await makeService(chapters: single("content"))
            .search(query: "")
        #expect(results.isEmpty)
    }

    @Test("whitespace query returns no results")
    func whitespaceQuery() async {
        let results = await makeService(chapters: single("content"))
            .search(query: "   ")
        #expect(results.isEmpty)
    }

    @Test("no match returns empty")
    func noMatch() async {
        let results = await makeService(chapters: single("quick fox"))
            .search(query: "elephant")
        #expect(results.isEmpty)
    }

    @Test("no text layer returns empty")
    func noTextLayer() async {
        let results = await makeService().search(query: "anything")
        #expect(results.isEmpty)
    }

    // MARK: - CJK

    @Test("finds CJK characters")
    func cjkSearch() async {
        let results = await makeService(
            chapters: single("关于三体问题的书")
        ).search(query: "三体")
        #expect(results.count == 1)
    }

    @Test("normalizes full-width to half-width")
    func fullWidthNorm() async {
        let results = await makeService(
            chapters: single("Ｈｅｌｌｏ Ｗｏｒｌｄ")
        ).search(query: "Hello")
        #expect(results.count == 1)
    }

    @Test("searches Japanese text")
    func japanese() async {
        let results = await makeService(
            chapters: single("これはテストです")
        ).search(query: "テスト")
        #expect(results.count == 1)
    }

    @Test("searches Korean text")
    func korean() async {
        let results = await makeService(
            chapters: single("안녕하세요 세계")
        ).search(query: "세계")
        #expect(results.count == 1)
    }

    // MARK: - Diacritics

    @Test("diacritics-insensitive match")
    func diacriticsInsensitive() async {
        let results = await makeService(
            chapters: single("café crème brûlée")
        ).search(query: "cafe", options: SearchOptions(diacriticInsensitive: true))
        #expect(results.count == 1)
    }

    @Test("diacritics-sensitive rejects unaccented")
    func diacriticsSensitive() async {
        let results = await makeService(
            chapters: single("café")
        ).search(query: "cafe", options: SearchOptions(diacriticInsensitive: false))
        #expect(results.isEmpty)
    }

    // MARK: - Special Characters

    @Test("treats regex metacharacters as literal")
    func specialChars() async {
        let results = await makeService(
            chapters: single("Price $19.99 (tax)")
        ).search(query: "$19.99")
        #expect(results.count == 1)
    }

    @Test(
        "handles all regex metacharacters safely",
        arguments: [".", "*", "+", "?", "[", "]", "(", ")", "{", "}", "\\", "^", "$", "|"]
    )
    func metachars(char: String) async {
        let results = await makeService(
            chapters: single("text \(char) here")
        ).search(query: char)
        #expect(results.count >= 1)
    }

    // MARK: - Result Limiting & Context

    @Test("limits results to max count")
    func resultLimit() async {
        let results = await makeService(
            chapters: single(String(repeating: "word ", count: 500))
        ).search(query: "word", options: SearchOptions(maxResults: 100))
        #expect(results.count <= 100)
    }

    @Test("provides context snippet for matches")
    func contextSnippet() async {
        let results = await makeService(
            chapters: single("Before important After more text")
        ).search(query: "important")
        #expect(results.count == 1)
        #expect(results[0].contextSnippet.contains("Before"))
    }

    // MARK: - Edge Cases

    @Test("single character query works")
    func singleChar() async {
        let results = await makeService(chapters: single("abcabc"))
            .search(query: "a")
        #expect(results.count == 2)
    }

    @Test("query longer than content returns empty")
    func longQuery() async {
        let results = await makeService(chapters: single("hi"))
            .search(query: "this query is much longer than content")
        #expect(results.isEmpty)
    }

    @Test("handles newlines in content")
    func newlines() async {
        let results = await makeService(
            chapters: single("Line one\nLine two\nLine three")
        ).search(query: "two")
        #expect(results.count == 1)
    }
}
