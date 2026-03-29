// Purpose: Tests for TXTLazyTextProvider — lazy full-text concatenation
// for AI, search, and TTS features.

import Testing
import Foundation
@testable import vreader

// MARK: - Tests

@Suite("TXTLazyTextProvider")
struct TXTLazyTextProviderTests {

    // MARK: - Fixtures

    private static let ch1 = "Hello, World!"
    private static let ch2 = "Second chunk."
    private static let ch3 = "Third chapter"
    private static let allText = ch1 + ch2 + ch3

    private static func makeChaptersAndLoader() -> ([TXTChapter], TXTChapterContentLoader) {
        let data = Data(allText.utf8)
        let ch1Len = (ch1 as NSString).length
        let ch2Len = (ch2 as NSString).length
        let ch3Len = (ch3 as NSString).length

        let chapters = [
            TXTChapter(index: 0, title: "Chapter 1", startByte: 0, endByte: Int64(data.count),
                       globalStartUTF16: 0, textLengthUTF16: ch1Len),
            TXTChapter(index: 1, title: "Chapter 2", startByte: 0, endByte: Int64(data.count),
                       globalStartUTF16: ch1Len, textLengthUTF16: ch2Len),
            TXTChapter(index: 2, title: "Chapter 3", startByte: 0, endByte: Int64(data.count),
                       globalStartUTF16: ch1Len + ch2Len, textLengthUTF16: ch3Len),
        ]
        let loader = TXTChapterContentLoader(fileData: data, encoding: .utf8)
        return (chapters, loader)
    }

    // MARK: - getFullText

    @Test("getFullText concatenates all chapters")
    func testGetFullTextConcatenatesAllChapters() async throws {
        let (chapters, loader) = Self.makeChaptersAndLoader()
        let provider = TXTLazyTextProvider(contentLoader: loader, chapters: chapters)

        let fullText = try await provider.getFullText()
        #expect(fullText == Self.allText)
    }

    @Test("getFullText caches result — only loads once")
    func testGetFullTextCachesResult() async throws {
        let (chapters, loader) = Self.makeChaptersAndLoader()
        let provider = TXTLazyTextProvider(contentLoader: loader, chapters: chapters)

        let first = try await provider.getFullText()
        let second = try await provider.getFullText()

        #expect(first == second)
    }

    @Test("invalidateCache forces reload on next getFullText")
    func testInvalidateCacheForcesReload() async throws {
        let (chapters, loader) = Self.makeChaptersAndLoader()
        let provider = TXTLazyTextProvider(contentLoader: loader, chapters: chapters)

        let first = try await provider.getFullText()
        await provider.invalidateCache()
        let second = try await provider.getFullText()

        #expect(first == second)
    }

    @Test("empty chapters returns empty string")
    func testEmptyChaptersReturnsEmptyString() async throws {
        let loader = TXTChapterContentLoader(fileData: Data(), encoding: .utf8)
        let provider = TXTLazyTextProvider(contentLoader: loader, chapters: [])

        let fullText = try await provider.getFullText()
        #expect(fullText == "")
    }

    @Test("single chapter returns its text")
    func testSingleChapter() async throws {
        let text = "Hello"
        let data = Data(text.utf8)
        let chapter = TXTChapter(
            index: 0, title: "Only", startByte: 0, endByte: Int64(data.count),
            globalStartUTF16: 0, textLengthUTF16: (text as NSString).length
        )
        let loader = TXTChapterContentLoader(fileData: data, encoding: .utf8)
        let provider = TXTLazyTextProvider(contentLoader: loader, chapters: [chapter])

        let fullText = try await provider.getFullText()
        #expect(fullText == "Hello")
    }
}
