// Purpose: Chunked/lazy loading for large TXT files.
// Loads text in 64KB chunks to avoid loading entire large files into memory.
// Provides viewport-based loading and memory pressure eviction.
//
// Key decisions:
// - Default chunk size is 64KB (good balance of granularity vs overhead).
// - Chunks are byte-aligned; text decoding snaps to valid UTF-8 boundaries.
// - Memory budget enforced by evicting distant chunks on demand.
// - Thread-safe via actor isolation.
//
// @coordinates-with TXTOffsetMapper.swift, TXTTextViewBridge.swift

import Foundation

/// Manages chunked loading of large TXT file data.
///
/// Divides the file into fixed-size byte chunks and loads/decodes them on demand.
/// Supports viewport-based loading (load chunks near current scroll position)
/// and memory pressure eviction (drop distant chunks).
/// @MainActor-isolated to protect mutable `loadedChunks` state.
/// All access must occur on the main actor (UI-driven loading pattern).
@MainActor
final class TXTChunkedLoader {

    // MARK: - Constants

    /// Default chunk size in bytes (64 KB).
    nonisolated static let defaultChunkSize = 64 * 1024

    // MARK: - Properties

    /// The raw file data (or a memory-mapped reference).
    private let data: Data

    /// Total byte count of the file (may differ from data.count for lazy scenarios).
    let totalByteCount: Int

    /// Chunk size in bytes.
    private let chunkSize: Int

    /// Number of chunks needed to cover the entire file.
    let chunkCount: Int

    /// Cache of decoded chunk texts, keyed by chunk index.
    private var loadedChunks: [Int: String] = [:]

    /// Bytes trimmed from the end of each chunk due to partial UTF-8 sequences.
    /// Carried over to the start of the next chunk during decoding.
    private var trailingBytes: [Int: Data] = [:]

    /// Number of currently loaded (cached) chunks.
    var loadedChunkCount: Int { loadedChunks.count }

    // MARK: - Init

    /// Creates a chunked loader for the given data.
    ///
    /// - Parameters:
    ///   - data: The raw file data (can be empty for metadata-only calculations).
    ///   - totalByteCount: Total byte count of the file.
    ///   - chunkSize: Size of each chunk in bytes. Defaults to 64 KB.
    init(data: Data, totalByteCount: Int, chunkSize: Int = defaultChunkSize) {
        self.data = data
        self.totalByteCount = totalByteCount
        self.chunkSize = max(chunkSize, 1) // Prevent division by zero
        if totalByteCount <= 0 {
            self.chunkCount = 0
        } else {
            self.chunkCount = (totalByteCount + self.chunkSize - 1) / self.chunkSize
        }
    }

    // MARK: - Chunk Geometry

    /// Returns the byte range for a given chunk index, or nil if out of bounds.
    func chunkByteRange(forChunkIndex index: Int) -> Range<Int>? {
        guard index >= 0, index < chunkCount else { return nil }
        let start = index * chunkSize
        let end = min(start + chunkSize, totalByteCount)
        return start..<end
    }

    /// Returns the chunk index containing the given byte offset.
    /// Clamps to valid range.
    func chunkIndex(forByteOffset offset: Int) -> Int {
        guard chunkCount > 0 else { return 0 }
        let clamped = min(max(offset, 0), totalByteCount - 1)
        return min(clamped / chunkSize, chunkCount - 1)
    }

    // MARK: - Loading

    /// Loads and decodes the text for a given chunk index.
    ///
    /// Returns cached text if already loaded. Returns nil for invalid indices
    /// or if the data doesn't cover this chunk.
    ///
    /// - Important: For correct UTF-8 boundary handling, chunks should be loaded
    ///   sequentially (chunk N-1 before chunk N). Partial trailing bytes from
    ///   chunk N-1 are carried over to the start of chunk N. Random-access loading
    ///   of isolated chunks may produce incorrect results at chunk boundaries.
    func loadChunkText(at index: Int) -> String? {
        if let cached = loadedChunks[index] { return cached }

        guard let byteRange = chunkByteRange(forChunkIndex: index) else { return nil }
        guard byteRange.upperBound <= data.count else { return nil }

        // Prepend any trailing bytes carried over from the previous chunk
        var subdata: Data
        if index > 0, let carry = trailingBytes[index - 1] {
            subdata = carry + data[byteRange]
        } else {
            subdata = Data(data[byteRange])
        }

        // Decode as UTF-8, snapping to valid boundaries
        let text = decodeUTF8Snapping(subdata, chunkIndex: index)
        loadedChunks[index] = text
        return text
    }

    /// Returns the full text by concatenating all chunks. Suitable for small files only.
    func fullText() -> String {
        guard chunkCount > 0 else { return "" }
        var chunks: [String] = []
        chunks.reserveCapacity(chunkCount)
        for i in 0..<chunkCount {
            if let chunk = loadChunkText(at: i) {
                chunks.append(chunk)
            }
        }
        return chunks.joined()
    }

    // MARK: - Viewport

    /// Returns chunk indices that should be loaded for a viewport centered at the given byte offset.
    ///
    /// - Parameters:
    ///   - centerByteOffset: The byte offset at the center of the viewport.
    ///   - windowChunks: Number of chunks to load on each side of center. Default 1.
    /// - Returns: Sorted array of valid chunk indices.
    func chunkIndicesForViewport(
        centerByteOffset: Int,
        windowChunks: Int = 1
    ) -> [Int] {
        guard chunkCount > 0 else { return [] }
        let clampedWindow = max(0, windowChunks)
        let centerChunk = chunkIndex(forByteOffset: centerByteOffset)
        let lower = max(0, centerChunk - clampedWindow)
        let upper = min(chunkCount - 1, centerChunk + clampedWindow)
        return Array(lower...upper)
    }

    // MARK: - Memory Management

    /// Evicts cached chunks that are far from the given chunk index.
    ///
    /// Keeps the `maxLoaded` chunks closest to `keepNear`, evicts the rest.
    func evictDistantChunks(keepNear centerChunk: Int, maxLoaded: Int) {
        let clampedMax = max(0, maxLoaded)
        guard loadedChunks.count > clampedMax else { return }

        // Sort loaded chunk indices by distance from center
        let sorted = loadedChunks.keys.sorted { a, b in
            abs(a - centerChunk) < abs(b - centerChunk)
        }

        // Keep only the closest ones
        let toEvict = sorted.dropFirst(clampedMax)
        for index in toEvict {
            loadedChunks.removeValue(forKey: index)
            trailingBytes.removeValue(forKey: index)
        }
    }

    // MARK: - Private Helpers

    /// Decodes a Data slice as UTF-8, handling partial sequences at chunk boundaries.
    /// Stores any trimmed trailing bytes in `trailingBytes[chunkIndex]` for carry-over.
    private func decodeUTF8Snapping(_ data: Data, chunkIndex: Int) -> String {
        // Try direct UTF-8 decoding first
        if let text = String(data: data, encoding: .utf8) {
            trailingBytes[chunkIndex] = nil
            return text
        }

        // If that fails (partial UTF-8 at boundaries), trim trailing incomplete sequences
        var trimmed = data
        // UTF-8 multi-byte sequences are at most 4 bytes
        let maxTrim = min(3, trimmed.count)
        for trimCount in 1...maxTrim {
            trimmed = data.dropLast(trimCount)
            if let text = String(data: Data(trimmed), encoding: .utf8) {
                trailingBytes[chunkIndex] = Data(data.suffix(trimCount))
                return text
            }
        }

        // Last resort: lossy decoding
        trailingBytes[chunkIndex] = nil
        return String(decoding: data, as: UTF8.self)
    }
}
