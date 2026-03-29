// Purpose: Immutable data structures for TXT chapter indexing.
// A chapter is defined by byte offset range in the file, enabling lazy content loading.
//
// Key decisions:
// - Byte offsets (Int64) instead of character offsets — format-agnostic, works with any encoding.
// - Codable for JSON persistence (WI-3).
// - Sendable for safe cross-actor use.
// - UTF-16 fields (-1 default) populated lazily by WI-4 offset translation layer.
//
// @coordinates-with: TXTChapterIndexBuilder.swift, TXTService.swift

import Foundation

/// A chapter discovered by streaming the file.
struct TXTChapter: Codable, Sendable, Equatable {
    /// Zero-based chapter index.
    let index: Int
    /// Chapter title (trimmed match text or synthetic "Chapter N").
    let title: String
    /// Inclusive start byte offset in the file.
    let startByte: Int64
    /// Exclusive end byte offset in the file.
    let endByte: Int64
    /// Cumulative UTF-16 offset of this chapter's start. -1 until populated.
    var globalStartUTF16: Int = -1
    /// UTF-16 length of this chapter's decoded text. -1 until populated.
    var textLengthUTF16: Int = -1
}

/// Immutable chapter index for a TXT file.
struct TXTChapterIndex: Codable, Sendable, Equatable {
    /// Ordered list of chapters covering the entire file.
    let chapters: [TXTChapter]
    /// Total file size in bytes.
    let totalBytes: Int64
    /// Detected encoding name (e.g. "UTF-8", "GBK").
    let detectedEncoding: String
    /// Total UTF-16 code unit count of the full file text. 0 until populated.
    var totalTextLengthUTF16: Int = 0

    /// Whether the index has no chapters.
    var isEmpty: Bool { chapters.isEmpty }
    /// Number of chapters.
    var count: Int { chapters.count }

    /// Returns the title at the given index, or nil if out of bounds.
    func title(at index: Int) -> String? {
        guard index >= 0, index < chapters.count else { return nil }
        return chapters[index].title
    }
}
