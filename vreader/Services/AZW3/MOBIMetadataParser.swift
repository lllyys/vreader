// Purpose: Extracts title + author from MOBI/AZW3 EXTH records (types 503 +
// 100). Native PDB/MOBI binary parsing — no WKWebView, no Foliate-js
// dependency. Companion to MOBICoverExtractor; shares the same binary layout
// but reads different EXTH record types.
//
// Key decisions:
// - All integers are big-endian per MOBI spec.
// - Returns (nil, nil) on any parse failure (truncated, missing EXTH, no
//   matching records, decode failure). Never crashes; never throws.
// - Title preference: EXTH 503 (Updated title) only. Falls back to nil so
//   AZW3MetadataExtractor can use the filename as a final default.
//   The palmdb header title (bytes 0..32 of the file) is NOT used because it's
//   conventionally underscore-joined (`The_Masque_of_the_Red_Death`) and the
//   filename fallback is more user-presentable for files that lack EXTH 503.
// - Author from EXTH 100. Multiple-author files are not supported in v0
//   (returns the first-encountered EXTH 100).
//
// @coordinates-with: MOBICoverExtractor.swift, MetadataExtractor.swift
//   (AZW3MetadataExtractor)

import Foundation

enum MOBIMetadataParser {

    /// Extracts (title, author) from a MOBI/AZW3 file's EXTH records.
    /// Returns nil values for any field that's unavailable. Never crashes.
    static func extractTitleAndAuthor(from fileURL: URL) -> (title: String?, author: String?) {
        guard let data = try? Data(contentsOf: fileURL, options: .mappedIfSafe),
              data.count >= pdbHeaderSize else {
            return (nil, nil)
        }

        let numRecords = Int(readUInt16BE(data, offset: 76))
        guard numRecords > 0 else { return (nil, nil) }

        let recordTableEnd = pdbHeaderSize + numRecords * recordEntrySize
        guard data.count >= recordTableEnd else { return (nil, nil) }

        let recordOffsets = parseRecordOffsets(data: data, numRecords: numRecords)

        guard let record0 = extractRecord(data: data, offsets: recordOffsets, index: 0) else {
            return (nil, nil)
        }

        // PalmDOC header = bytes 0..15 (16 bytes); MOBI header starts at
        // byte 16. We need at least 132 bytes (16 + 116 for exthFlag at 112).
        guard record0.count >= 132 else { return (nil, nil) }

        // Verify MOBI magic at offset 16
        let mobiMagic = String(data: record0[16..<20], encoding: .ascii)
        guard mobiMagic == "MOBI" else { return (nil, nil) }

        let mobiLength = readUInt32BE(record0, offset: 20)

        // Text-encoding field at MOBI offset 28 → absolute record0 offset 44.
        // Common values: 65001 = UTF-8, 1252 = Windows-1252. Used to decode
        // EXTH text payloads. Default to UTF-8 if the field is absent or
        // unknown (works for ASCII + already-UTF-8 content).
        let textEncoding = readUInt32BE(record0, offset: 44)

        let exthFlag = readUInt32BE(record0, offset: 128)
        let hasEXTH = (exthFlag & 0x40) != 0
        guard hasEXTH else { return (nil, nil) }

        // EXTH starts right after MOBI header
        let exthStart = 16 + Int(mobiLength)
        guard exthStart + 12 <= record0.count else { return (nil, nil) }

        let exthMagic = String(data: record0[exthStart..<(exthStart + 4)], encoding: .ascii)
        guard exthMagic == "EXTH" else { return (nil, nil) }

        let exthLength = Int(readUInt32BE(record0, offset: exthStart + 4))
        let exthRecordCount = Int(readUInt32BE(record0, offset: exthStart + 8))
        // Codex Medium fix: validate exthLength covers at least the 12-byte
        // header AND fits inside record 0. Then bound the per-record loop
        // by `exthEnd` (NOT record0.count) so a corrupt exthRecordCount or
        // recLength can't run past the declared EXTH region into adjacent
        // bytes (which would let us silently parse non-EXTH data as a
        // pseudo-record and return garbage metadata).
        guard exthLength >= 12, exthStart + exthLength <= record0.count else {
            return (nil, nil)
        }
        let exthEnd = exthStart + exthLength

        var title: String?
        var author: String?
        var cursor = exthStart + 12

        for _ in 0..<exthRecordCount {
            guard cursor + 8 <= exthEnd else { break }
            let recType = readUInt32BE(record0, offset: cursor)
            let recLength = Int(readUInt32BE(record0, offset: cursor + 4))
            // recLength includes the 8-byte header; payload spans
            // [cursor + 8, cursor + recLength).
            guard recLength >= 8, cursor + recLength <= exthEnd else { break }

            // EXTH 100 = Author, 503 = Updated title.
            // Multi-author files: first EXTH 100 wins (the `author == nil`
            // guard). v0 doesn't model multi-author; rare in Kindle exports.
            if recType == 100, author == nil {
                author = decodeText(record0[(cursor + 8)..<(cursor + recLength)],
                                    textEncoding: textEncoding)
            } else if recType == 503, title == nil {
                title = decodeText(record0[(cursor + 8)..<(cursor + recLength)],
                                   textEncoding: textEncoding)
            }

            cursor += recLength
            // Early exit once both fields are filled — rest of EXTH is
            // typically image offsets and metadata not relevant here.
            if title != nil && author != nil { break }
        }

        return (title, author)
    }

    // MARK: - Binary Helpers
    // Duplicated from MOBICoverExtractor to keep the cover-extraction
    // surface untouched while adding metadata extraction. A shared
    // MOBIBinaryParser is the obvious next refactor; deferred to keep this
    // diff minimal.

    private static let pdbHeaderSize = 78
    private static let recordEntrySize = 8

    private static func readUInt16BE(_ data: Data, offset: Int) -> UInt16 {
        UInt16(data[offset]) << 8 | UInt16(data[offset + 1])
    }

    private static func readUInt32BE(_ data: Data, offset: Int) -> UInt32 {
        UInt32(data[offset]) << 24
            | UInt32(data[offset + 1]) << 16
            | UInt32(data[offset + 2]) << 8
            | UInt32(data[offset + 3])
    }

    private static func parseRecordOffsets(data: Data, numRecords: Int) -> [Int] {
        (0..<numRecords).map { i in
            let entryOffset = pdbHeaderSize + i * recordEntrySize
            return Int(readUInt32BE(data, offset: entryOffset))
        }
    }

    private static func extractRecord(data: Data, offsets: [Int], index: Int) -> Data? {
        guard index >= 0, index < offsets.count else { return nil }
        let start = offsets[index]
        let end = (index + 1 < offsets.count) ? offsets[index + 1] : data.count
        guard start >= 0, end > start, end <= data.count else { return nil }
        return Data(data[start..<end])
    }

    /// Decodes EXTH payload bytes using the MOBI file's declared text
    /// encoding.
    ///
    /// Strategy (Codex round-2 finding addressed):
    ///
    /// 1. **Always try UTF-8 first.** Pure-ASCII payloads decode identically
    ///    in UTF-8, CP1252, and most legacy codepages, so a successful UTF-8
    ///    decode is correct regardless of the declared encoding. UTF-8 also
    ///    covers the modern codepage 65001 (the dominant Kindle export
    ///    format).
    /// 2. **If UTF-8 fails AND `textEncoding == 1252`, try Windows-1252.**
    ///    Older Kindle/Calibre exports of Western-language books often use
    ///    CP1252; this preserves accented characters that UTF-8 rejects.
    /// 3. **For any other declared codepage (e.g., 932 Shift-JIS, 950 Big5,
    ///    1251 Cyrillic), return nil rather than forcing CP1252.** CP1252
    ///    is permissive (any byte sequence decodes) and would silently
    ///    surface mojibake instead of letting `AZW3MetadataExtractor` fall
    ///    back to a clean filename-derived title. We'd rather drop unusual-
    ///    codepage metadata than display garbage.
    /// 4. Returns nil for empty / whitespace-only payloads.
    ///
    /// Future work: extend the explicit codepage table for Asian-language
    /// MOBIs (932, 936, 949, 950) when a fixture surfaces.
    private static func decodeText(_ slice: Data, textEncoding: UInt32) -> String? {
        guard !slice.isEmpty else { return nil }

        // Step 1: UTF-8. Catches codepage 65001 + any ASCII-only payload.
        if let utf8 = String(data: slice, encoding: .utf8) {
            return nonEmptyTrimmed(utf8)
        }

        // Step 2: only fall back to CP1252 when the file declares it.
        if textEncoding == 1252,
           let cp1252 = String(data: slice, encoding: .windowsCP1252) {
            return nonEmptyTrimmed(cp1252)
        }

        // Step 3: unknown codepage with non-UTF-8 bytes → return nil so
        // AZW3MetadataExtractor falls back to filename rather than display
        // mojibake.
        return nil
    }

    private static func nonEmptyTrimmed(_ s: String) -> String? {
        let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
