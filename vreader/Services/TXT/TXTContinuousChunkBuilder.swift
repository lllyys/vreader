// Purpose: Turns a full decoded book string into rendering chunks plus
// cumulative document-global UTF-16 start offsets, for the continuous-scroll
// TXT surface (Bug #180 re-scoped fix). The continuous surface is the existing
// chunked UITableView, fed the WHOLE book instead of one chapter.
//
// Key decisions:
// - Pure function (enum namespace) — no state, no @MainActor, fully testable.
// - Reuses `TXTTextChunker.split` so chunk boundaries match the large-file
//   path exactly (16 KB target, paragraph-aligned).
// - `chunkStartOffsets` are cumulative UTF-16 lengths; chunk K's offset is the
//   sum of all preceding chunks' UTF-16 lengths. First offset is always 0.
// - These offsets ARE the continuous-surface contract: they are document-global,
//   the same coordinate space the persistence layer uses.
//
// @coordinates-with: TXTTextChunker.swift, TXTReaderViewModel.swift,
//   TXTChunkedReaderBridge.swift

import Foundation

/// Builds (chunks, chunkStartOffsets) for the continuous-scroll TXT surface.
enum TXTContinuousChunkBuilder {

    /// Result of splitting a book into a continuous chunk array.
    struct Result: Sendable, Equatable {
        /// Text chunks. Joined, they equal the input text exactly.
        let chunks: [String]
        /// Cumulative document-global UTF-16 start offset of each chunk.
        /// Same count as `chunks`; first element is 0.
        let chunkStartOffsets: [Int]
    }

    /// Splits the full decoded book text into 16 KB chunks and computes the
    /// cumulative document-global UTF-16 start offsets.
    static func build(fullText: String, targetChunkSize: Int = 16384) -> Result {
        guard !fullText.isEmpty else {
            return Result(chunks: [], chunkStartOffsets: [])
        }
        let chunks = TXTTextChunker.split(
            text: fullText, targetChunkSize: targetChunkSize
        )
        var offsets: [Int] = []
        offsets.reserveCapacity(chunks.count)
        var cumulative = 0
        for chunk in chunks {
            offsets.append(cumulative)
            cumulative += chunk.utf16.count
        }
        return Result(chunks: chunks, chunkStartOffsets: offsets)
    }
}
