// Purpose: Unit tests for TXTChunkedLoader — chunk boundary correctness,
// memory budget enforcement, viewport-based loading, and large file simulation.

import Testing
import Foundation
@testable import vreader

@Suite("TXTChunkedLoader")
@MainActor
struct TXTChunkedLoaderTests {

    // MARK: - Constants

    private static let defaultChunkSize = TXTChunkedLoader.defaultChunkSize

    // MARK: - Initialization

    @Test func initWithSmallData() {
        let data = Data("Hello, World!".utf8)
        let loader = TXTChunkedLoader(data: data, totalByteCount: data.count)
        #expect(loader.totalByteCount == data.count)
        #expect(loader.chunkCount >= 1)
    }

    @Test func initWithEmptyData() {
        let data = Data()
        let loader = TXTChunkedLoader(data: data, totalByteCount: 0)
        #expect(loader.totalByteCount == 0)
        #expect(loader.chunkCount == 0)
    }

    // MARK: - Chunk boundaries

    @Test func chunkBoundariesAlignCorrectly() {
        // Create data exactly 2.5 chunks in size
        let chunkSize = TXTChunkedLoader.defaultChunkSize
        let totalSize = chunkSize * 2 + chunkSize / 2
        let data = Data(repeating: 0x41, count: totalSize) // 'A' repeated
        let loader = TXTChunkedLoader(data: data, totalByteCount: totalSize)

        #expect(loader.chunkCount == 3)

        // First chunk: [0, chunkSize)
        let range0 = loader.chunkByteRange(forChunkIndex: 0)
        #expect(range0?.lowerBound == 0)
        #expect(range0?.upperBound == chunkSize)

        // Second chunk: [chunkSize, 2*chunkSize)
        let range1 = loader.chunkByteRange(forChunkIndex: 1)
        #expect(range1?.lowerBound == chunkSize)
        #expect(range1?.upperBound == chunkSize * 2)

        // Third chunk: [2*chunkSize, totalSize)
        let range2 = loader.chunkByteRange(forChunkIndex: 2)
        #expect(range2?.lowerBound == chunkSize * 2)
        #expect(range2?.upperBound == totalSize)
    }

    @Test func chunkIndexOutOfBounds() {
        let data = Data("Hello".utf8)
        let loader = TXTChunkedLoader(data: data, totalByteCount: data.count)
        #expect(loader.chunkByteRange(forChunkIndex: -1) == nil)
        #expect(loader.chunkByteRange(forChunkIndex: 100) == nil)
    }

    // MARK: - Loading chunks

    @Test func loadChunkReturnsCorrectText() {
        let text = "Hello, World! This is a test."
        let data = Data(text.utf8)
        let loader = TXTChunkedLoader(data: data, totalByteCount: data.count)

        let chunk0 = loader.loadChunkText(at: 0)
        #expect(chunk0 != nil)
        // For small text that fits in one chunk, it should return the whole text
        #expect(chunk0 == text)
    }

    @Test func loadChunkOutOfBoundsReturnsNil() {
        let data = Data("Hello".utf8)
        let loader = TXTChunkedLoader(data: data, totalByteCount: data.count)
        #expect(loader.loadChunkText(at: -1) == nil)
        #expect(loader.loadChunkText(at: 999) == nil)
    }

    // MARK: - Viewport-based loading

    @Test func chunksForViewportReturnsCorrectRange() {
        // Simulate a 256KB file with 64KB chunks = 4 chunks
        let chunkSize = TXTChunkedLoader.defaultChunkSize
        let totalSize = chunkSize * 4
        let data = Data(repeating: 0x41, count: totalSize)
        let loader = TXTChunkedLoader(data: data, totalByteCount: totalSize)

        // Viewport at byte offset in the middle of chunk 2
        let centerByte = chunkSize * 2 + chunkSize / 2
        let chunks = loader.chunkIndicesForViewport(
            centerByteOffset: centerByte,
            windowChunks: 1
        )
        // Should include chunk 1, 2, 3 (center +/- 1)
        #expect(chunks.contains(1))
        #expect(chunks.contains(2))
        #expect(chunks.contains(3))
    }

    @Test func chunksForViewportClampsToValidRange() {
        let chunkSize = TXTChunkedLoader.defaultChunkSize
        let totalSize = chunkSize * 3
        let data = Data(repeating: 0x41, count: totalSize)
        let loader = TXTChunkedLoader(data: data, totalByteCount: totalSize)

        // Viewport at start — should not include negative indices
        let chunks = loader.chunkIndicesForViewport(
            centerByteOffset: 0,
            windowChunks: 2
        )
        #expect(chunks.allSatisfy { $0 >= 0 })
        #expect(chunks.contains(0))
    }

    // MARK: - Memory budget

    @Test func evictDistantChunksEnforcesLimit() {
        let chunkSize = TXTChunkedLoader.defaultChunkSize
        let totalSize = chunkSize * 10
        let data = Data(repeating: 0x41, count: totalSize)
        let loader = TXTChunkedLoader(data: data, totalByteCount: totalSize)

        // Load many chunks
        for i in 0..<10 {
            _ = loader.loadChunkText(at: i)
        }

        // Evict, keeping only chunks near index 5 with budget of 3
        loader.evictDistantChunks(keepNear: 5, maxLoaded: 3)

        #expect(loader.loadedChunkCount <= 3)
    }

    @Test func evictDoesNotEvictActiveChunks() {
        let chunkSize = TXTChunkedLoader.defaultChunkSize
        let totalSize = chunkSize * 5
        let data = Data(repeating: 0x41, count: totalSize)
        let loader = TXTChunkedLoader(data: data, totalByteCount: totalSize)

        // Load chunks 2, 3, 4
        _ = loader.loadChunkText(at: 2)
        _ = loader.loadChunkText(at: 3)
        _ = loader.loadChunkText(at: 4)

        // Evict keeping near 3, budget 3 — all should stay
        loader.evictDistantChunks(keepNear: 3, maxLoaded: 3)
        #expect(loader.loadedChunkCount == 3)
    }

    // MARK: - Large file simulation

    @Test func largeFileChunkCountCorrect() {
        // 50 MB / 64 KB = 800 chunks (approx)
        let totalSize = 50 * 1024 * 1024
        let chunkSize = TXTChunkedLoader.defaultChunkSize
        let expectedChunks = (totalSize + chunkSize - 1) / chunkSize

        // We don't actually allocate 50MB — just test the math
        let data = Data() // empty, we just test metadata
        let loader = TXTChunkedLoader(data: data, totalByteCount: totalSize)
        #expect(loader.chunkCount == expectedChunks)
    }

    // MARK: - Byte offset to chunk index

    @Test func byteOffsetToChunkIndex() {
        let chunkSize = TXTChunkedLoader.defaultChunkSize
        let totalSize = chunkSize * 4
        let data = Data(repeating: 0x41, count: totalSize)
        let loader = TXTChunkedLoader(data: data, totalByteCount: totalSize)

        #expect(loader.chunkIndex(forByteOffset: 0) == 0)
        #expect(loader.chunkIndex(forByteOffset: chunkSize - 1) == 0)
        #expect(loader.chunkIndex(forByteOffset: chunkSize) == 1)
        #expect(loader.chunkIndex(forByteOffset: chunkSize * 3 + 100) == 3)
    }

    @Test func byteOffsetNegativeClamps() {
        let data = Data("Hello".utf8)
        let loader = TXTChunkedLoader(data: data, totalByteCount: data.count)
        #expect(loader.chunkIndex(forByteOffset: -10) == 0)
    }

    @Test func byteOffsetBeyondEndClamps() {
        let data = Data("Hello".utf8)
        let loader = TXTChunkedLoader(data: data, totalByteCount: data.count)
        let maxIndex = loader.chunkCount - 1
        #expect(loader.chunkIndex(forByteOffset: 1_000_000) == maxIndex)
    }

    // MARK: - Full text assembly for small files

    @Test func fullTextForSmallFile() {
        let text = "Hello, World! 你好世界 🎉"
        let data = Data(text.utf8)
        let loader = TXTChunkedLoader(data: data, totalByteCount: data.count)

        let assembled = loader.fullText()
        #expect(assembled == text)
    }
}
