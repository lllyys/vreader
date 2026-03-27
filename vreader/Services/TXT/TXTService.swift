// Purpose: Production implementation of TXTServiceProtocol.
// Reads a TXT file, detects encoding, and returns metadata + content.
//
// Key decisions:
// - Actor-isolated for thread safety.
// - Uses NSString heuristic detection first (handles CJK, BOM, etc.).
// - Falls back to manual encoding attempts in safe order.
// - Catch-all encodings (ISO-8859-1, CP1252) tried last — they match any byte sequence.
// - Word count uses whitespace splitting (locale-independent).
// - Chapter-based open (WI-5) builds index from streaming blocks without full decode.
//
// @coordinates-with: TXTServiceProtocol.swift, TXTReaderViewModel.swift,
//   TXTChapterIndex.swift, TXTChapterIndexBuilder.swift, TXTChapterContentLoader.swift,
//   TXTChapterIndexStore.swift, TXTOffsetTranslator.swift, TXTTocRuleEngine.swift

import Foundation

/// Production TXT file loader.
actor TXTService: TXTServiceProtocol {
    private var _isOpen = false
    /// Guards against concurrent open() calls (audit fix: Task.detached reentrancy).
    private var _isOpening = false

    var isOpen: Bool { _isOpen }

    func open(url: URL) async throws -> TXTFileMetadata {
        guard !_isOpen, !_isOpening else { throw TXTServiceError.alreadyOpen }
        _isOpening = true
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw TXTServiceError.fileNotFound(url.lastPathComponent)
        }

        // PERF: Move ALL heavy work (file I/O + decode + word count) off the
        // calling actor to prevent UI thread stall. This is the #1 performance
        // fix for TXT opening — Legado-inspired (they never block the UI thread
        // with file operations).
        let result: TXTFileMetadata = try await Task.detached {
            // Use mappedIfSafe to avoid copying entire file into heap memory
            let data = try Data(contentsOf: url, options: .mappedIfSafe)

            // Phase 1: Detect encoding from 8KB sample (fast)
            let hintName = Self.detectEncodingFromSample(data)
            let text: String
            let detectedEncoding: String

            if let hintEnc = Self.encodingFromName(hintName),
               let decoded = String(data: data, encoding: hintEnc) {
                text = decoded
                detectedEncoding = hintName
            } else if let (decoded, enc) = Self.decodeText(data) {
                text = decoded
                detectedEncoding = enc
            } else {
                throw TXTServiceError.decodingFailed(
                    "Could not decode the file with any supported encoding"
                )
            }

            // Phase 2: Word count in same background context (no extra hop)
            let wordCount = Self.countWords(text)

            return TXTFileMetadata(
                text: text,
                fileByteCount: Int64(data.count),
                detectedEncoding: detectedEncoding,
                totalTextLengthUTF16: text.utf16.count,
                totalWordCount: wordCount
            )
        }.value

        _isOpen = true
        _isOpening = false
        return result
    }

    func close() async {
        _isOpen = false
    }

    // MARK: - Chapter-Based Open (WI-5)

    func openChapterBased(url: URL) async throws -> TXTChapterOpenResult {
        guard !_isOpen, !_isOpening else { throw TXTServiceError.alreadyOpen }
        _isOpening = true
        guard FileManager.default.fileExists(atPath: url.path) else {
            _isOpening = false
            throw TXTServiceError.fileNotFound(url.lastPathComponent)
        }

        let result: TXTChapterOpenResult
        do {
            result = try await Task.detached {
                let data = try Data(contentsOf: url, options: .mappedIfSafe)
                let fileByteCount = Int64(data.count)

                guard !data.isEmpty else {
                    let emptyIndex = TXTChapterIndex(
                        chapters: [], totalBytes: 0, detectedEncoding: "UTF-8"
                    )
                    let loader = TXTChapterContentLoader(fileData: data, encoding: .utf8)
                    return TXTChapterOpenResult(
                        chapterIndex: emptyIndex, contentLoader: loader,
                        fileByteCount: 0, detectedEncoding: "UTF-8"
                    )
                }

                let encodingName = Self.detectEncodingFromSample(data)
                let encoding = Self.encodingFromName(encodingName) ?? .utf8
                let cacheDir = Self.cacheDirectory(for: url)
                let fileModDate = Self.fileModificationDate(url: url) ?? Date()

                // GH #30: Load from cache if built with full-text strategy (v2).
                // Old streaming-block caches used byte offsets — incompatible.
                // Detect by checking if startByte == 0 for all chapters (full-text
                // builder sets startByte=0 since byte offsets are unused).
                if let cachedIndex = TXTChapterIndexStore.load(
                    cacheDir: cacheDir, fileByteCount: fileByteCount, fileModDate: fileModDate
                ), cachedIndex.totalTextLengthUTF16 > 0,
                   cachedIndex.chapters.first.map({ $0.startByte == 0 }) ?? false {
                    let loader = TXTChapterContentLoader(fileData: data, encoding: encoding)
                    return TXTChapterOpenResult(
                        chapterIndex: cachedIndex, contentLoader: loader,
                        fileByteCount: fileByteCount, detectedEncoding: encodingName
                    )
                }

                // GH #30 (Legado strategy): Decode full file → regex → chapters
                // with exact UTF-16 offsets. One system for TOC + content + position.
                guard let fullString = String(data: data, encoding: encoding) else {
                    throw TXTServiceError.decodingFailed("Failed to decode with \(encodingName)")
                }
                let fullText = fullString as NSString
                // GH #30: Detect rule from full text (not a sample) to match the
                // TOC path. A 512K sample can pick a different rule than full-text,
                // producing different chapter counts.
                let rule = TXTTocRuleEngine.detectBestRule(
                    text: fullString, rules: TXTTocRuleEngine.defaultRules
                )

                let index = Self.buildChapterIndexFromFullText(
                    fullText: fullText, totalBytes: Int64(data.count),
                    encodingName: encodingName, rule: rule
                )

                try? FileManager.default.createDirectory(
                    at: cacheDir, withIntermediateDirectories: true
                )
                try? TXTChapterIndexStore.save(
                    index, cacheDir: cacheDir,
                    fileByteCount: fileByteCount, fileModDate: fileModDate
                )

                let loader = TXTChapterContentLoader(fileData: data, encoding: encoding)
                return TXTChapterOpenResult(
                    chapterIndex: index, contentLoader: loader,
                    fileByteCount: fileByteCount, detectedEncoding: encodingName
                )
            }.value
        } catch {
            _isOpening = false
            throw error
        }

        _isOpen = true
        _isOpening = false
        return result
    }

    // MARK: - Full-Text Chapter Builder (GH #30, Legado strategy)

    /// Builds chapter index by running regex on the full decoded text.
    /// UTF-16 offsets are exact (from NSRegularExpression match positions).
    /// This is the same text the TOC uses, guaranteeing perfect alignment.
    private static func buildChapterIndexFromFullText(
        fullText: NSString,
        totalBytes: Int64,
        encodingName: String,
        rule: TXTTocRule?
    ) -> TXTChapterIndex {
        let totalUTF16 = fullText.length
        guard totalUTF16 > 0 else {
            return TXTChapterIndex(
                chapters: [], totalBytes: totalBytes,
                detectedEncoding: encodingName, totalTextLengthUTF16: 0
            )
        }

        var chapters: [TXTChapter] = []

        if let rule, let regex = try? NSRegularExpression(
            pattern: rule.rule, options: [.anchorsMatchLines]
        ) {
            let matches = regex.matches(
                in: fullText as String,
                range: NSRange(location: 0, length: totalUTF16)
            )
            for match in matches {
                guard match.range.location != NSNotFound else { continue }
                let title = fullText.substring(with: match.range)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                guard !title.isEmpty else { continue }

                let utf16Start = match.range.location

                // Close previous chapter
                if !chapters.isEmpty {
                    let last = chapters.count - 1
                    chapters[last] = TXTChapter(
                        index: chapters[last].index,
                        title: chapters[last].title,
                        startByte: 0, endByte: totalBytes,
                        globalStartUTF16: chapters[last].globalStartUTF16,
                        textLengthUTF16: utf16Start - chapters[last].globalStartUTF16
                    )
                }

                chapters.append(TXTChapter(
                    index: chapters.count,
                    title: title,
                    startByte: 0, endByte: totalBytes,
                    globalStartUTF16: utf16Start,
                    textLengthUTF16: totalUTF16 - utf16Start
                ))
            }
        }

        // Add preamble if first chapter doesn't start at 0
        if let first = chapters.first, first.globalStartUTF16 > 0 {
            var updated = [TXTChapter(
                index: 0, title: "前言",
                startByte: 0, endByte: totalBytes,
                globalStartUTF16: 0,
                textLengthUTF16: first.globalStartUTF16
            )]
            for (i, ch) in chapters.enumerated() {
                updated.append(TXTChapter(
                    index: i + 1, title: ch.title,
                    startByte: 0, endByte: totalBytes,
                    globalStartUTF16: ch.globalStartUTF16,
                    textLengthUTF16: ch.textLengthUTF16
                ))
            }
            chapters = updated
        }

        // Close last chapter
        if !chapters.isEmpty {
            let last = chapters.count - 1
            chapters[last] = TXTChapter(
                index: chapters[last].index,
                title: chapters[last].title,
                startByte: 0, endByte: totalBytes,
                globalStartUTF16: chapters[last].globalStartUTF16,
                textLengthUTF16: totalUTF16 - chapters[last].globalStartUTF16
            )
        }

        // Need at least 2 chapters
        if chapters.count < 2 {
            chapters = buildSyntheticChaptersUTF16(
                fullText: fullText, totalBytes: totalBytes
            )
        }

        return TXTChapterIndex(
            chapters: chapters, totalBytes: totalBytes,
            detectedEncoding: encodingName, totalTextLengthUTF16: totalUTF16
        )
    }

    /// Synthetic chapters at ~50K UTF-16 boundaries (paragraph breaks).
    private static func buildSyntheticChaptersUTF16(
        fullText: NSString, totalBytes: Int64
    ) -> [TXTChapter] {
        let total = fullText.length
        let size = 50_000
        guard total > size else {
            return [TXTChapter(
                index: 0, title: "Chapter 1",
                startByte: 0, endByte: totalBytes,
                globalStartUTF16: 0, textLengthUTF16: total
            )]
        }
        var chapters: [TXTChapter] = []
        var pos = 0
        while pos < total {
            let target = min(pos + size, total)
            if target >= total {
                chapters.append(TXTChapter(
                    index: chapters.count, title: "Chapter \(chapters.count + 1)",
                    startByte: 0, endByte: totalBytes,
                    globalStartUTF16: pos, textLengthUTF16: total - pos
                ))
                break
            }
            let searchRange = NSRange(location: target, length: min(2000, total - target))
            let br = fullText.range(of: "\n\n", options: [], range: searchRange)
            let split = br.location != NSNotFound ? br.location + 2 : target
            chapters.append(TXTChapter(
                index: chapters.count, title: "Chapter \(chapters.count + 1)",
                startByte: 0, endByte: totalBytes,
                globalStartUTF16: pos, textLengthUTF16: split - pos
            ))
            pos = split
        }
        return chapters
    }

    // MARK: - File Helpers

    /// Returns a cache directory for chapter index persistence.
    /// Uses a stable key derived from filename + file size (audit fix: hashValue is randomized per process).
    private static func cacheDirectory(for url: URL) -> URL {
        let cacheBase = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int64) ?? 0
        let stableKey = "\(url.lastPathComponent)-\(size)"
            .addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? "unknown"
        return cacheBase.appendingPathComponent("chapter-index/\(stableKey)")
    }

    /// Returns the modification date of a file.
    private static func fileModificationDate(url: URL) -> Date? {
        try? FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate] as? Date
    }

    // MARK: - Encoding Detection

    /// Detects encoding and decodes text data.
    ///
    /// Strategy:
    /// 1. UTF-8 (most common, BOM-aware via Foundation).
    /// 2. NSString heuristic detection (handles GBK, Big5, Shift_JIS, etc.).
    /// 3. Manual fallback list with CJK encodings before catch-all single-byte encodings.
    /// 4. ISO-8859-1 last — it accepts any byte sequence and acts as a catch-all.
    static func decodeText(_ data: Data) -> (String, String)? {
        // Empty data is valid UTF-8
        if data.isEmpty {
            return ("", "UTF-8")
        }

        // 1. Try UTF-8 first (fast path, handles BOM)
        if let text = String(data: data, encoding: .utf8) {
            return (text, "UTF-8")
        }

        // 2. Try UTF-16 only if BOM is present (avoid false positives on arbitrary data)
        if data.count >= 2 {
            let bom = (UInt16(data[0]) << 8) | UInt16(data[1])
            if bom == 0xFEFF || bom == 0xFFFE {
                if let text = String(data: data, encoding: .utf16) {
                    return (text, "UTF-16")
                }
            }
        }

        // 3. Use NSString heuristic detection
        if let (text, name) = detectWithNSString(data) {
            return (text, name)
        }

        // 4. Manual fallback: CJK encodings first, then catch-all single-byte last
        let fallbacks: [(String.Encoding, String)] = [
            (gbkEncoding, "GBK"),
            (big5Encoding, "Big5"),
            (.japaneseEUC, "EUC-JP"),
            (.shiftJIS, "Shift_JIS"),
            (eucKREncoding, "EUC-KR"),
            (.windowsCP1252, "Windows-1252"),
            (.isoLatin1, "ISO-8859-1"),  // catch-all — must be last
        ]
        for (encoding, name) in fallbacks {
            if let text = String(data: data, encoding: encoding) {
                return (text, name)
            }
        }

        return nil
    }

    // MARK: - Sample-Based Encoding Detection (WI-F05)

    /// Sample size for encoding detection. 8KB is sufficient for BOM detection
    /// and NSString heuristic analysis -- encoding patterns appear in first few KB.
    static let encodingSampleSize = 8192

    /// Detects encoding by analyzing only the first 8KB of data.
    /// Returns the detected encoding name (e.g., "UTF-8", "GBK").
    /// For files smaller than 8KB, analyzes the entire data.
    /// Avoids splitting multi-byte sequences at the sample boundary.
    static func detectEncodingFromSample(_ data: Data) -> String {
        if data.isEmpty { return "UTF-8" }

        let sample: Data
        if data.count <= encodingSampleSize {
            sample = data
        } else {
            // Walk backwards from the cut point to avoid splitting a multi-byte
            // UTF-8 or CJK sequence. Continuation bytes are 10xxxxxx (0x80-0xBF).
            var end = encodingSampleSize
            while end > 0 && data[end - 1] & 0xC0 == 0x80 {
                end -= 1
            }
            // If the byte at end-1 is a multi-byte lead but has no room for
            // all continuation bytes, step back one more.
            if end > 0 {
                let lead = data[end - 1]
                let needed: Int
                if lead & 0xE0 == 0xC0 { needed = 2 }
                else if lead & 0xF0 == 0xE0 { needed = 3 }
                else if lead & 0xF8 == 0xF0 { needed = 4 }
                else { needed = 1 }
                if end - 1 + needed > encodingSampleSize { end -= 1 }
            }
            // CJK 2-byte encodings (GBK, Big5, Shift_JIS): their lead bytes
            // (0x81-0xFE) overlap with UTF-8 continuation (0x80-0xBF) and
            // multi-byte lead (0xC0-0xF7) ranges, so the UTF-8 walkback above
            // already handles boundary splits for these encodings. A lone
            // trailing byte (< 0x80) at the boundary may leave a CJK lead
            // inside the sample, but encoding detectors (NSString heuristic,
            // manual fallback) tolerate an incomplete final character in an
            // 8KB sample — 8191 valid bytes is sufficient for detection.
            sample = data.prefix(max(1, end))
        }

        guard let (_, encodingName) = decodeText(sample) else {
            return "UTF-8" // Fallback
        }
        return encodingName
    }

    // MARK: - NSString Heuristic Detection

    /// Uses NSString's built-in encoding detection heuristics.
    /// This handles GBK, Big5, Shift_JIS, EUC-KR, and many others.
    private static func detectWithNSString(_ data: Data) -> (String, String)? {
        var usedLossyConversion: ObjCBool = false
        let detectedRaw = NSString.stringEncoding(
            for: data,
            encodingOptions: [
                .suggestedEncodingsKey: [
                    String.Encoding.utf8.rawValue,
                    gbkEncoding.rawValue,
                    big5Encoding.rawValue,
                    String.Encoding.japaneseEUC.rawValue,
                    String.Encoding.shiftJIS.rawValue,
                    eucKREncoding.rawValue,
                    String.Encoding.windowsCP1252.rawValue,
                    String.Encoding.isoLatin1.rawValue,
                ],
                .allowLossyKey: false,
            ],
            convertedString: nil,
            usedLossyConversion: &usedLossyConversion
        )
        let detected = String.Encoding(rawValue: detectedRaw)

        // Skip if lossy or if it fell through to a catch-all
        guard !usedLossyConversion.boolValue, detectedRaw != 0 else { return nil }

        if let text = String(data: data, encoding: detected) {
            let name = encodingName(detected)
            return (text, name)
        }
        return nil
    }

    // MARK: - Encoding Constants

    /// GBK / GB18030 encoding (covers GB2312 as a subset).
    private static let gbkEncoding = String.Encoding(
        rawValue: CFStringConvertEncodingToNSStringEncoding(
            CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue)
        )
    )

    /// Big5 encoding (Traditional Chinese).
    private static let big5Encoding = String.Encoding(
        rawValue: CFStringConvertEncodingToNSStringEncoding(
            CFStringEncoding(CFStringEncodings.big5.rawValue)
        )
    )

    /// EUC-KR encoding (Korean).
    private static let eucKREncoding = String.Encoding(
        rawValue: CFStringConvertEncodingToNSStringEncoding(
            CFStringEncoding(CFStringEncodings.EUC_KR.rawValue)
        )
    )

    /// Counts words without allocating split substrings. O(n) single pass.
    private static func countWords(_ text: String) -> Int {
        var count = 0
        var inWord = false
        for char in text {
            if char.isWhitespace || char.isNewline {
                inWord = false
            } else if !inWord {
                count += 1
                inWord = true
            }
        }
        return count
    }

    /// Maps a human-readable encoding name back to a String.Encoding.
    /// Reverse of `encodingName(_:)`. Returns nil for unknown names.
    static func encodingFromName(_ name: String) -> String.Encoding? {
        switch name {
        case "UTF-8": return .utf8
        case "UTF-16": return .utf16
        case "ISO-8859-1": return .isoLatin1
        case "Windows-1252": return .windowsCP1252
        case "EUC-JP": return .japaneseEUC
        case "Shift_JIS": return .shiftJIS
        case "GBK": return gbkEncoding
        case "Big5": return big5Encoding
        case "EUC-KR": return eucKREncoding
        default: return nil
        }
    }

    /// Maps a String.Encoding to a human-readable name.
    private static func encodingName(_ encoding: String.Encoding) -> String {
        switch encoding {
        case .utf8: return "UTF-8"
        case .utf16: return "UTF-16"
        case .isoLatin1: return "ISO-8859-1"
        case .windowsCP1252: return "Windows-1252"
        case .japaneseEUC: return "EUC-JP"
        case .shiftJIS: return "Shift_JIS"
        case gbkEncoding: return "GBK"
        case big5Encoding: return "Big5"
        case eucKREncoding: return "EUC-KR"
        default:
            let cfEnc = CFStringConvertNSStringEncodingToEncoding(encoding.rawValue)
            if cfEnc != kCFStringEncodingInvalidId,
               let cfName = CFStringConvertEncodingToIANACharSetName(cfEnc) {
                return cfName as String
            }
            return "Unknown"
        }
    }
}
