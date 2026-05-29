// Purpose: Bug #286 — TXT TOC entries must align with the reader's full-text
// chapter index. Both the TOC builder and the reader's chapter index must come
// from a single source of truth (same decode + same full-text rule detection),
// so TOC entry N's charOffsetUTF16 == reader chapter N's globalStartUTF16.

import Testing
import Foundation
@testable import vreader

@Suite("Bug #286 — TXT TOC ↔ reader chapter-index alignment")
struct ReaderTOCTXTAlignmentTests {

    private let fingerprint = DocumentFingerprint(
        contentSHA256: "abcdef0123456789abcdef0123456789abcdef0123456789abcdef0123456789",
        fileByteCount: 500,
        format: .txt
    )

    /// Body text long enough to never match any chapter rule (>30 chars).
    private let body = "这是一段足够长的内容，用来模拟真实小说的段落内容，不会被任何章节规则匹配到。"

    // MARK: - Core invariant: TOC offsets == reader chapter offsets

    /// The reader builds chapters via `buildChapterIndexFromFullText` over the
    /// `decodeForDisplayAndSearch` string. The TOC must produce entries whose
    /// offsets land EXACTLY on those chapter starts so `navigateToGlobalOffset`
    /// floor-snaps to the correct chapter.
    @Test("TOC entry offsets equal reader chapter-index offsets (UTF-8)")
    func tocOffsetsEqualChapterIndexOffsets_utf8() {
        let text = "\(body)\n第一章 黎明破晓\n\(body)\n第二章 日落黄昏\n\(body)\n第三章 风云再起\n\(body)"
        let data = Data(text.utf8)

        let entries = TXTService.buildTXTTOCEntries(data: data, fingerprint: fingerprint)
        let chapterStarts = Set(readerChapterStartOffsets(for: data))

        #expect(!entries.isEmpty)
        for entry in entries {
            let offset = entry.locator.charOffsetUTF16 ?? -1
            #expect(chapterStarts.contains(offset))
        }
    }

    // MARK: - Encoding asymmetry axis (GBK)

    private var gbk: String.Encoding {
        String.Encoding(
            rawValue: CFStringConvertEncodingToNSStringEncoding(
                CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue)
            )
        )
    }

    /// Builds a GBK file whose first 8KB+ is pure ASCII so the 8KB sample-based
    /// encoding detector guesses "UTF-8", while the GBK body past the sample
    /// boundary is NOT valid UTF-8. This is the exact shape that broke the
    /// pre-fix TOC: its raw `String(data:encoding:)` with a UTF-8-only fallback
    /// returned a different string (or nil) than the reader's full GBK ladder,
    /// shifting every offset / emptying the TOC. The fix routes both through
    /// `decodeForDisplayAndSearch`.
    private func gbkFileWithAsciiHead() throws -> Data {
        // >8KB ASCII head: TXTService.encodingSampleSize == 8192.
        let asciiHead = String(repeating: "Lorem ipsum dolor sit amet. ", count: 400) // ~11KB
        let cjkBody = "\(body)\n第一章 黎明\n\(body)\n第二章 日落\n\(body)\n第三章 黄昏\n\(body)"
        return try #require((asciiHead + "\n" + cjkBody).data(using: gbk))
    }

    @Test("GBK file (ASCII head): TOC offsets equal reader chapter-index offsets")
    func gbkAlignment() throws {
        let data = try gbkFileWithAsciiHead()
        // The full data must NOT be valid UTF-8 — otherwise the sample misdetect
        // axis isn't exercised.
        #expect(String(data: data, encoding: .utf8) == nil)
        // The 8KB sample IS valid UTF-8 (pure ASCII), so the sample detector
        // guesses UTF-8 — the pre-fix trap.
        #expect(TXTService.detectEncodingFromSample(data) == "UTF-8")

        let entries = TXTService.buildTXTTOCEntries(data: data, fingerprint: fingerprint)
        let chapterStarts = Set(readerChapterStartOffsets(for: data))

        #expect(entries.count >= 2)
        for entry in entries {
            let offset = entry.locator.charOffsetUTF16 ?? -1
            #expect(chapterStarts.contains(offset))
        }
    }

    /// Decode parity: the bytes the TOC builder decodes must be the SAME string
    /// the reader decodes. This is the root-cause invariant for the encoding
    /// axis — the ASCII-head GBK file makes the pre-fix decode diverge.
    @Test("GBK file (ASCII head): TOC decode string matches reader decode")
    func gbkDecodeParity() throws {
        let data = try gbkFileWithAsciiHead()
        let readerDecoded = try #require(TXTService.decodeForDisplayAndSearch(data)?.0)
        let tocDecoded = try #require(TXTService.decodeTXTForTOC(data)?.0)
        #expect(tocDecoded == readerDecoded)
    }

    // MARK: - Pattern-shift axis (> 512KB sample boundary)

    /// `detectBestRule` samples the first 512KB to PICK a rule, then extracts over
    /// the full text. This fixture has a genuine pattern shift: the first >512KB is
    /// dominated by `第N章` (rule family A); the tail switches to `Chapter N`
    /// (rule family B). The 512KB sample therefore picks family A, and the tail's
    /// family-B headings are NOT chapters. The bug-relevant guarantee: TOC and
    /// reader make the SAME pick over the SAME decoded string, so every TOC offset
    /// still lands exactly on a reader chapter start — across the boundary.
    @Test("pattern-shift across 512KB: TOC offsets equal reader chapter offsets")
    func patternShiftAlignment() {
        // sampleSizeUTF16 == 512*1024 == 524288. Each block ≈ 90 UTF-16 units;
        // ~7000 `第N章` blocks (~630K) fills past the sample window. Array join
        // keeps the build O(n) (not repeated String += which is O(n²)).
        let familyABlocks = 7000
        var blocks: [String] = []
        for i in 1...familyABlocks {
            blocks.append("第\(i)章 标题\n\(body)\n\(body)\n")
        }
        // Tail switches to a competing rule family (English Chapter N). Because the
        // sample window picks 第N章, these are body text — NOT chapters — for both
        // passes. The assertion is that TOC and reader agree, not the rule identity.
        for j in 1...5 {
            blocks.append("Chapter \(j) Tail Heading\n\(body)\n\(body)\n")
        }
        // A final 第N章 past the boundary, which IS a chapter under the chosen rule.
        let lastNumber = familyABlocks + 1
        blocks.append("第\(lastNumber)章 收尾\n\(body)\n")
        let builder = blocks.joined()
        let data = Data(builder.utf8)

        // Sanity: the fixture genuinely crosses the rule-detection sample window.
        #expect(builder.utf16.count > TXTTocRuleEngine.sampleSizeUTF16)

        let entries = TXTService.buildTXTTOCEntries(data: data, fingerprint: fingerprint)
        let chapterStarts = Set(readerChapterStartOffsets(for: data))

        #expect(entries.count > 50)
        for entry in entries {
            let offset = entry.locator.charOffsetUTF16 ?? -1
            #expect(chapterStarts.contains(offset))
        }
        // The 第N章 chapter past the 512KB sample window must be present + aligned
        // (proves full-text extraction, not sample-only).
        #expect(entries.contains { $0.title == "第\(lastNumber)章 收尾" })
        // The competing family-B "Chapter N" tail headings must NOT become TOC
        // entries (the chosen rule is 第N章) — and the reader must agree.
        #expect(!entries.contains { $0.title.hasPrefix("Chapter ") })
    }

    // MARK: - Production path (ReaderTOCFactory.buildTOC ↔ openChapterBased)

    /// End-to-end through the wired production entry point: `ReaderTOCFactory`
    /// loads the file from disk, decodes, and builds the TOC. Compare its entry
    /// offsets to the SAME file opened via `TXTService.openChapterBased` — the
    /// real reader path. Uses the GBK ASCII-head fixture so a wiring regression
    /// back to the pre-fix decode would diverge and fail. (Codex Gate-4 M1.)
    @Test("ReaderTOCFactory.buildTOC offsets equal openChapterBased chapter starts (GBK)")
    func productionPathAlignment() async throws {
        let data = try gbkFileWithAsciiHead()
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("bug286-\(UUID().uuidString).txt")
        try data.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let entries = await ReaderTOCFactory.buildTOC(
            format: "txt", fileURL: url, fingerprint: fingerprint
        )

        let service = TXTService()
        let openResult = try await service.openChapterBased(url: url)
        await service.close()
        let chapterStarts = Set(openResult.chapterIndex.chapters.map(\.globalStartUTF16))

        #expect(entries.count >= 2)
        for entry in entries {
            let offset = entry.locator.charOffsetUTF16 ?? -1
            #expect(chapterStarts.contains(offset))
        }
    }

    // MARK: - Edge cases

    @Test("single-chapter / no-pattern text returns empty TOC (matches reader)")
    func noPatternReturnsEmpty() {
        let text = "这是一段普通文本，没有任何章节标记在里面。\n也没有数字开头的行或者特殊符号。\n就是一些非常普通的话而已，什么也没有。"
        let data = Data(text.utf8)
        let entries = TXTService.buildTXTTOCEntries(data: data, fingerprint: fingerprint)
        #expect(entries.isEmpty)
    }

    @Test("empty data returns empty TOC")
    func emptyReturnsEmpty() {
        let entries = TXTService.buildTXTTOCEntries(data: Data(), fingerprint: fingerprint)
        #expect(entries.isEmpty)
    }

    @Test("TOC builder does not emit the synthetic 前言 preamble as a tappable entry")
    func noPreambleEntry() {
        let text = "\(body)\n第一章 标题\n\(body)\n第二章 后续\n\(body)"
        let data = Data(text.utf8)
        let entries = TXTService.buildTXTTOCEntries(data: data, fingerprint: fingerprint)
        #expect(!entries.contains { $0.title == "前言" })
        // First real chapter offset is non-zero (preamble precedes it).
        #expect(entries.first?.locator.charOffsetUTF16 ?? 0 > 0)
    }

    // MARK: - Helper: reader's chapter-index start offsets

    /// Reproduces the reader's chapter-index pipeline (decode + full-text rule +
    /// `buildChapterIndexFromFullText`) and returns each chapter's UTF-16 start.
    private func readerChapterStartOffsets(for data: Data) -> [Int] {
        guard let (full, encName) = TXTService.decodeForDisplayAndSearch(data) else { return [] }
        let rule = TXTTocRuleEngine.detectBestRule(
            text: full, rules: TXTTocRuleEngine.defaultRules
        )
        let index = TXTService.buildChapterIndexFromFullText(
            fullText: full as NSString,
            totalBytes: Int64(data.count),
            encodingName: encName,
            rule: rule
        )
        return index.chapters.map(\.globalStartUTF16)
    }
}
