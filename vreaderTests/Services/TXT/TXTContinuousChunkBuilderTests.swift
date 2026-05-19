// Purpose: Unit tests for TXTContinuousChunkBuilder — turns a full decoded
// book string into (chunks, chunkStartOffsets) for the continuous-scroll
// UITableView surface (Bug #180 re-scoped fix, WI-3). Also covers the
// TXTChapterContentLoader.fullDecodedText() seam.
//
// Tests live in vreaderTests/Services/TXT/ to mirror the source path.

import Testing
import Foundation
@testable import vreader

@Suite("TXTContinuousChunkBuilder")
struct TXTContinuousChunkBuilderTests {

    @Test func concatenatedChunksEqualInput() {
        let text = String(repeating: "Hello world.\n", count: 5000)
        let result = TXTContinuousChunkBuilder.build(fullText: text)
        #expect(result.chunks.joined() == text)
    }

    @Test func chunkStartOffsetsAreCumulativeUTF16Lengths() {
        let text = String(repeating: "Paragraph text here.\n", count: 4000)
        let result = TXTContinuousChunkBuilder.build(fullText: text)
        #expect(result.chunkStartOffsets.count == result.chunks.count)
        #expect(result.chunkStartOffsets.first == 0)
        var cumulative = 0
        for (i, chunk) in result.chunks.enumerated() {
            #expect(result.chunkStartOffsets[i] == cumulative)
            cumulative += chunk.utf16.count
        }
        // Final cumulative must equal the whole text's UTF-16 length.
        #expect(cumulative == text.utf16.count)
    }

    @Test func chunkStartOffsetsStrictlyIncreasing() {
        let text = String(repeating: "Line.\n", count: 10000)
        let result = TXTContinuousChunkBuilder.build(fullText: text)
        for i in 1..<result.chunkStartOffsets.count {
            #expect(result.chunkStartOffsets[i] > result.chunkStartOffsets[i - 1])
        }
    }

    @Test func emptyTextProducesEmptyChunksAndOffsets() {
        let result = TXTContinuousChunkBuilder.build(fullText: "")
        #expect(result.chunks.isEmpty)
        #expect(result.chunkStartOffsets.isEmpty)
    }

    @Test func smallTextProducesSingleChunk() {
        let text = "Just a short story."
        let result = TXTContinuousChunkBuilder.build(fullText: text)
        #expect(result.chunks.count == 1)
        #expect(result.chunks[0] == text)
        #expect(result.chunkStartOffsets == [0])
    }

    @Test func cjkTextChunkOffsetsStayUTF16Consistent() {
        // CJK BMP chars are 1 UTF-16 unit each; offsets must still sum.
        let text = String(repeating: "战争与和平的故事。\n", count: 5000)
        let result = TXTContinuousChunkBuilder.build(fullText: text)
        #expect(result.chunks.joined() == text)
        var cumulative = 0
        for (i, chunk) in result.chunks.enumerated() {
            #expect(result.chunkStartOffsets[i] == cumulative)
            cumulative += chunk.utf16.count
        }
        #expect(cumulative == text.utf16.count)
    }

    @Test func surrogatePairTextRoundTrips() {
        // Emoji are surrogate pairs (2 UTF-16 units). Joined chunks must
        // still equal the input and offsets stay UTF-16-consistent.
        let text = String(repeating: "Story 😀 with emoji 🎉 here.\n", count: 4000)
        let result = TXTContinuousChunkBuilder.build(fullText: text)
        #expect(result.chunks.joined() == text)
        var cumulative = 0
        for (i, chunk) in result.chunks.enumerated() {
            #expect(result.chunkStartOffsets[i] == cumulative)
            cumulative += chunk.utf16.count
        }
        #expect(cumulative == text.utf16.count)
    }

    @Test func fullDecodedTextReturnsWholeBookString() async throws {
        let bookText = "Chapter One\nSome text.\nChapter Two\nMore text.\n"
        let data = try #require(bookText.data(using: .utf8))
        let loader = TXTChapterContentLoader(fileData: data, encoding: .utf8)
        let decoded = try await loader.fullDecodedText()
        #expect(decoded == bookText)
    }

    @Test func fullDecodedTextMatchesSlicingPathDecode() async throws {
        // The slicing path (loadChapter) and fullDecodedText() must decode
        // the same underlying string — same encoding, same bytes.
        let bookText = "First half of the book.\nSecond half of the book.\n"
        let data = try #require(bookText.data(using: .utf8))
        let loader = TXTChapterContentLoader(fileData: data, encoding: .utf8)
        let nsText = bookText as NSString
        let chapter = TXTChapter(
            index: 0, title: "All", startByte: 0,
            endByte: Int64(data.count),
            globalStartUTF16: 0, textLengthUTF16: nsText.length
        )
        let sliced = try await loader.loadChapter(chapter)
        let full = try await loader.fullDecodedText()
        #expect(sliced == full)
    }
}
