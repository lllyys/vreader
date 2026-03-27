// Purpose: Loads chapter content by slicing the full decoded text.
// GH #30 rewrite: decodes full file once (Legado strategy), then slices
// chapters by globalStartUTF16 + textLengthUTF16. Eliminates per-chunk
// byte-range decode that fails for GBK/Big5 at block boundaries.
//
// Key decisions:
// - Actor-isolated for thread safety (concurrent chapter loads are safe).
// - Full-file decode happens lazily on first loadChapter call.
// - 3-chapter LRU cache (prev/cur/next Legado pattern).
// - Falls back to empty string for out-of-bounds UTF-16 ranges.
//
// @coordinates-with: TXTChapter, TXTService.swift, TXTReaderViewModel.swift

import Foundation

/// Loads chapter content by slicing the full decoded text by UTF-16 offsets.
actor TXTChapterContentLoader {
    private let fileData: Data
    private let encoding: String.Encoding
    private var fullText: NSString?  // lazy — decoded on first load
    private var cache: [Int: String] = [:]
    static let maxCacheSize = 3

    init(fileData: Data, encoding: String.Encoding) {
        self.fileData = fileData
        self.encoding = encoding
    }

    /// Loads a chapter's text by slicing the full decoded string.
    func loadChapter(_ chapter: TXTChapter) throws -> String {
        if let cached = cache[chapter.index] { return cached }

        // Lazy full-file decode (once)
        if fullText == nil {
            fullText = (String(data: fileData, encoding: encoding)
                ?? String(data: fileData, encoding: .utf8)
                ?? "") as NSString
        }

        guard let full = fullText else { return "" }

        let text: String
        let start = chapter.globalStartUTF16
        let length = chapter.textLengthUTF16

        if start >= 0, length >= 0, start < full.length {
            let safeLen = min(length, full.length - start)
            text = safeLen > 0
                ? full.substring(with: NSRange(location: start, length: safeLen))
                : ""
        } else {
            // Unpopulated UTF-16 offsets — should not happen with new builder
            throw TXTChapterLoadError.decodeFailed(chapterIndex: chapter.index)
        }

        // Evict if cache full
        if cache.count >= Self.maxCacheSize {
            let sorted = cache.keys.sorted {
                abs($0 - chapter.index) > abs($1 - chapter.index)
            }
            if let evict = sorted.first { cache.removeValue(forKey: evict) }
        }

        cache[chapter.index] = text
        return text
    }

    /// Preloads adjacent chapters (prev + next) in background.
    func preloadAdjacent(currentIndex: Int, chapters: [TXTChapter]) {
        for i in [currentIndex - 1, currentIndex + 1] {
            guard i >= 0, i < chapters.count else { continue }
            _ = try? loadChapter(chapters[i])
        }
    }

    /// Evicts all entries except the given indices.
    func evictExcept(indices: Set<Int>) {
        for key in cache.keys where !indices.contains(key) {
            cache.removeValue(forKey: key)
        }
    }

    /// Current cache size.
    var cacheCount: Int { cache.count }
}

/// Errors from TXTChapterContentLoader.
enum TXTChapterLoadError: Error, Sendable {
    case decodeFailed(chapterIndex: Int)
}
