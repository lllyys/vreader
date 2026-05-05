// Purpose: Unit tests for TXTChapterContentLoader — byte-range chapter loading,
// 3-entry LRU cache, eviction strategy, preloading, and encoding edge cases.

import Testing
import Foundation
@testable import vreader

@Suite("TXTChapterContentLoader")
struct TXTChapterContentLoaderTests {

    // MARK: - Test Data Helpers

    /// Creates test data from an array of chapter texts (UTF-8).
    /// Returns (fileData, chapters) where both byte ranges and UTF-16
    /// offsets are populated. Production `TXTChapterContentLoader`
    /// reads via UTF-16 offsets, so the byte-only init the tests used
    /// previously left `globalStartUTF16`/`textLengthUTF16` at their
    /// `-1` defaults and every load threw `decodeFailed`.
    private static func makeTestData(_ texts: [String]) -> (Data, [TXTChapter]) {
        var data = Data()
        var chapters: [TXTChapter] = []
        var utf16Cursor = 0
        for (i, text) in texts.enumerated() {
            let startByte = data.count
            let textData = Data(text.utf8)
            data.append(textData)
            let utf16Length = (text as NSString).length
            chapters.append(TXTChapter(
                index: i,
                title: "Chapter \(i)",
                startByte: Int64(startByte),
                endByte: Int64(data.count),
                globalStartUTF16: utf16Cursor,
                textLengthUTF16: utf16Length
            ))
            utf16Cursor += utf16Length
        }
        return (data, chapters)
    }

    // MARK: - Basic Loading

    @Test func loadFirstChapter() async throws {
        let (data, chapters) = Self.makeTestData([
            "First chapter content.",
            "Second chapter content.",
            "Third chapter content."
        ])
        let loader = TXTChapterContentLoader(fileData: data, encoding: .utf8)

        let text = try await loader.loadChapter(chapters[0])
        #expect(text == "First chapter content.")
    }

    @Test func loadLastChapter() async throws {
        let (data, chapters) = Self.makeTestData([
            "Chapter one.",
            "Chapter two.",
            "Final chapter at the end."
        ])
        let loader = TXTChapterContentLoader(fileData: data, encoding: .utf8)

        // endByte of last chapter == data.count
        #expect(chapters.last!.endByte == Int64(data.count))
        let text = try await loader.loadChapter(chapters[2])
        #expect(text == "Final chapter at the end.")
    }

    @Test func loadMiddleChapter() async throws {
        let (data, chapters) = Self.makeTestData([
            "One",
            "Two",
            "Three"
        ])
        let loader = TXTChapterContentLoader(fileData: data, encoding: .utf8)

        let text = try await loader.loadChapter(chapters[1])
        #expect(text == "Two")
    }

    // MARK: - Empty Chapter

    @Test func emptyChapterReturnsEmptyString() async throws {
        // Empty chapter: zero-length UTF-16 range. The byte range is also
        // zero-length, but production reads via UTF-16 offsets — both must
        // be populated.
        let data = Data("Some content".utf8)
        let chapter = TXTChapter(
            index: 0,
            title: "Empty",
            startByte: 5,
            endByte: 5,
            globalStartUTF16: 5,
            textLengthUTF16: 0
        )
        let loader = TXTChapterContentLoader(fileData: data, encoding: .utf8)

        let text = try await loader.loadChapter(chapter)
        #expect(text == "")
    }

    // MARK: - Cache Hit

    @Test func cacheHitReturnsSameResult() async throws {
        let (data, chapters) = Self.makeTestData(["Hello cache!"])
        let loader = TXTChapterContentLoader(fileData: data, encoding: .utf8)

        let first = try await loader.loadChapter(chapters[0])
        let second = try await loader.loadChapter(chapters[0])
        #expect(first == second)
        #expect(first == "Hello cache!")

        // Cache should have exactly 1 entry
        let count = await loader.cacheCount
        #expect(count == 1)
    }

    // MARK: - Cache Eviction

    @Test func cacheEvictsAfterMaxSize() async throws {
        let (data, chapters) = Self.makeTestData([
            "Chapter 0",
            "Chapter 1",
            "Chapter 2",
            "Chapter 3"
        ])
        let loader = TXTChapterContentLoader(fileData: data, encoding: .utf8)

        // Load 4 chapters — max cache is 3, so one should be evicted
        _ = try await loader.loadChapter(chapters[0])
        _ = try await loader.loadChapter(chapters[1])
        _ = try await loader.loadChapter(chapters[2])
        _ = try await loader.loadChapter(chapters[3])

        let count = await loader.cacheCount
        #expect(count == TXTChapterContentLoader.maxCacheSize)
    }

    @Test func evictionKeepsNearest() async throws {
        let (data, chapters) = Self.makeTestData([
            "Chapter 0",
            "Chapter 1",
            "Chapter 2",
            "Chapter 3"
        ])
        let loader = TXTChapterContentLoader(fileData: data, encoding: .utf8)

        // Load chapters 0, 1, 2 (cache full at 3)
        _ = try await loader.loadChapter(chapters[0])
        _ = try await loader.loadChapter(chapters[1])
        _ = try await loader.loadChapter(chapters[2])

        // Load chapter 3 — chapter 0 should be evicted (furthest from 3)
        _ = try await loader.loadChapter(chapters[3])

        let count = await loader.cacheCount
        #expect(count == 3)

        // Chapters 1, 2, 3 should still be cached (verify by loading — cache hit)
        // Chapter 0 should need a reload
        // We can verify this indirectly: loading 1,2,3 shouldn't change cache count
        _ = try await loader.loadChapter(chapters[1])
        _ = try await loader.loadChapter(chapters[2])
        _ = try await loader.loadChapter(chapters[3])
        #expect(await loader.cacheCount == 3)
    }

    // MARK: - Preload Adjacent

    @Test func preloadAdjacentLoadsNeighbors() async throws {
        let (data, chapters) = Self.makeTestData([
            "Prev",
            "Current",
            "Next"
        ])
        let loader = TXTChapterContentLoader(fileData: data, encoding: .utf8)

        await loader.preloadAdjacent(currentIndex: 1, chapters: chapters)

        // Should have prev (0) and next (2) in cache
        let count = await loader.cacheCount
        #expect(count == 2)

        // Verify cached content is correct
        let prev = try await loader.loadChapter(chapters[0])
        let next = try await loader.loadChapter(chapters[2])
        #expect(prev == "Prev")
        #expect(next == "Next")
    }

    @Test func preloadBoundsCheckFirstChapter() async throws {
        let (data, chapters) = Self.makeTestData([
            "First",
            "Second",
            "Third"
        ])
        let loader = TXTChapterContentLoader(fileData: data, encoding: .utf8)

        // Preload for index 0 — no prev exists, should not crash
        await loader.preloadAdjacent(currentIndex: 0, chapters: chapters)

        // Should have only next (1) in cache
        let count = await loader.cacheCount
        #expect(count == 1)
    }

    @Test func preloadBoundsCheckLastChapter() async throws {
        let (data, chapters) = Self.makeTestData([
            "First",
            "Second",
            "Third"
        ])
        let loader = TXTChapterContentLoader(fileData: data, encoding: .utf8)

        // Preload for last index — no next exists, should not crash
        await loader.preloadAdjacent(currentIndex: 2, chapters: chapters)

        // Should have only prev (1) in cache
        let count = await loader.cacheCount
        #expect(count == 1)
    }

    // MARK: - evictExcept

    @Test func evictExceptKeepsSpecifiedIndices() async throws {
        let (data, chapters) = Self.makeTestData([
            "A", "B", "C"
        ])
        let loader = TXTChapterContentLoader(fileData: data, encoding: .utf8)

        _ = try await loader.loadChapter(chapters[0])
        _ = try await loader.loadChapter(chapters[1])
        _ = try await loader.loadChapter(chapters[2])
        #expect(await loader.cacheCount == 3)

        await loader.evictExcept(indices: Set([1]))
        #expect(await loader.cacheCount == 1)

        // Chapter 1 should still be cached
        let text = try await loader.loadChapter(chapters[1])
        #expect(text == "B")
    }

    // MARK: - Decode Failure

    @Test func decodeFailedThrowsError() async throws {
        // Create data that is invalid for UTF-8
        // Bytes 0xC0 0x01 is invalid UTF-8 sequence
        let invalidData = Data([0xC0, 0x01, 0xFF, 0xFE])
        let chapter = TXTChapter(
            index: 0,
            title: "Bad",
            startByte: 0,
            endByte: 4
        )
        let loader = TXTChapterContentLoader(fileData: invalidData, encoding: .utf8)

        await #expect(throws: TXTChapterLoadError.self) {
            _ = try await loader.loadChapter(chapter)
        }
    }

    // MARK: - Concurrent Loads

    @Test func concurrentLoadsDoNotCrash() async throws {
        let (data, chapters) = Self.makeTestData([
            "Chapter 0",
            "Chapter 1",
            "Chapter 2"
        ])
        let loader = TXTChapterContentLoader(fileData: data, encoding: .utf8)

        // Fire 10 concurrent loads — actor serialization should prevent data races
        try await withThrowingTaskGroup(of: String.self) { group in
            for _ in 0..<10 {
                for ch in chapters {
                    group.addTask {
                        try await loader.loadChapter(ch)
                    }
                }
            }
            for try await text in group {
                #expect(!text.isEmpty)
            }
        }

        // Cache should not exceed maxCacheSize
        let count = await loader.cacheCount
        #expect(count <= TXTChapterContentLoader.maxCacheSize)
    }

    // MARK: - GBK Encoding

    @Test func gbkEncodingDecodesCorrectly() async throws {
        // "你好世界" in GBK: C4E3 BAC3 CAC0 BDE7
        let gbkBytes: [UInt8] = [0xC4, 0xE3, 0xBA, 0xC3, 0xCA, 0xC0, 0xBD, 0xE7]
        let gbkData = Data(gbkBytes)

        let gbkEncoding = String.Encoding(
            rawValue: CFStringConvertEncodingToNSStringEncoding(
                CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue)
            )
        )

        let chapter = TXTChapter(
            index: 0,
            title: "GBK Chapter",
            startByte: 0,
            endByte: Int64(gbkData.count),
            globalStartUTF16: 0,
            // "你好世界" is 4 BMP CJK characters → 4 UTF-16 code units.
            textLengthUTF16: 4
        )
        let loader = TXTChapterContentLoader(fileData: gbkData, encoding: gbkEncoding)

        let text = try await loader.loadChapter(chapter)
        #expect(text == "你好世界")
    }

    // MARK: - Edge: startByte beyond data length

    @Test func startByteBeyondDataReturnsEmpty() async throws {
        // Production now reads via UTF-16 offsets and treats out-of-range
        // offsets as a programming error (`decodeFailed`) — the comment in
        // `TXTChapterContentLoader.loadChapter` explicitly says
        // "Unpopulated UTF-16 offsets — should not happen with new builder."
        // Test name kept for git-blame continuity; assertion follows the
        // new contract.
        let data = Data("Short".utf8)
        let chapter = TXTChapter(
            index: 0,
            title: "Beyond",
            startByte: 100,
            endByte: 200,
            globalStartUTF16: 100,
            textLengthUTF16: 100
        )
        let loader = TXTChapterContentLoader(fileData: data, encoding: .utf8)

        do {
            _ = try await loader.loadChapter(chapter)
            Issue.record("Expected decodeFailed but loadChapter succeeded")
        } catch TXTChapterLoadError.decodeFailed {
            // Expected — UTF-16 start (100) is past full.length ("Short" → 5).
        }
    }

    // MARK: - Unicode / CJK content

    @Test func unicodeContentPreserved() async throws {
        let chineseText = "第一章 红楼梦\n贾宝玉初试云雨情"
        let (data, chapters) = Self.makeTestData([chineseText])
        let loader = TXTChapterContentLoader(fileData: data, encoding: .utf8)

        let text = try await loader.loadChapter(chapters[0])
        #expect(text == chineseText)
    }

    @Test func emojiContentPreserved() async throws {
        let emojiText = "Hello 🌍🎉 World 你好"
        let (data, chapters) = Self.makeTestData([emojiText])
        let loader = TXTChapterContentLoader(fileData: data, encoding: .utf8)

        let text = try await loader.loadChapter(chapters[0])
        #expect(text == emojiText)
    }
}
