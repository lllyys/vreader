// Purpose: Unit tests for SearchHitToLocatorResolver — SearchHit to Locator conversion.

import Testing
import Foundation
@testable import vreader

@Suite("SearchHitToLocatorResolver")
struct SearchHitToLocatorResolverTests {

    // MARK: - Test fixtures

    private static let epubFP = DocumentFingerprint(
        contentSHA256: "aabbccdd00112233aabbccdd00112233aabbccdd00112233aabbccdd00112233",
        fileByteCount: 10240,
        format: .epub
    )

    private static let pdfFP = DocumentFingerprint(
        contentSHA256: "aabbccdd00112233aabbccdd00112233aabbccdd00112233aabbccdd00112234",
        fileByteCount: 20480,
        format: .pdf
    )

    private static let txtFP = DocumentFingerprint(
        contentSHA256: "aabbccdd00112233aabbccdd00112233aabbccdd00112233aabbccdd00112235",
        fileByteCount: 512,
        format: .txt
    )

    // MARK: - EPUB resolution

    @Test func resolveEPUBHit() {
        let hit = SearchHit(
            fingerprintKey: Self.epubFP.canonicalKey,
            sourceUnitId: "epub:chapter1.xhtml",
            snippet: "...some text...",
            matchStartOffsetUTF16: 42,
            matchEndOffsetUTF16: 50
        )

        let locator = SearchHitToLocatorResolver.resolve(hit: hit, fingerprint: Self.epubFP)
        #expect(locator != nil)
        #expect(locator?.href == "chapter1.xhtml")
        #expect(locator?.bookFingerprint == Self.epubFP)
    }

    // MARK: - PDF resolution

    @Test func resolvePDFHit() {
        let hit = SearchHit(
            fingerprintKey: Self.pdfFP.canonicalKey,
            sourceUnitId: "pdf:page:5",
            snippet: "...pdf text...",
            matchStartOffsetUTF16: 10,
            matchEndOffsetUTF16: 20
        )

        let locator = SearchHitToLocatorResolver.resolve(hit: hit, fingerprint: Self.pdfFP)
        #expect(locator != nil)
        #expect(locator?.page == 5)
        #expect(locator?.bookFingerprint == Self.pdfFP)
    }

    @Test func resolvePDFPageZero() {
        let hit = SearchHit(
            fingerprintKey: Self.pdfFP.canonicalKey,
            sourceUnitId: "pdf:page:0",
            snippet: "first page",
            matchStartOffsetUTF16: 0,
            matchEndOffsetUTF16: 10
        )

        let locator = SearchHitToLocatorResolver.resolve(hit: hit, fingerprint: Self.pdfFP)
        #expect(locator != nil)
        #expect(locator?.page == 0)
    }

    // MARK: - TXT resolution

    @Test func resolveTXTHit() {
        let hit = SearchHit(
            fingerprintKey: Self.txtFP.canonicalKey,
            sourceUnitId: "txt:segment:2",
            snippet: "...txt content...",
            matchStartOffsetUTF16: 15,
            matchEndOffsetUTF16: 25
        )

        // With segment base offsets: segment 0 = 0..100, segment 1 = 100..200, segment 2 = 200..300
        let segmentBaseOffsets: [Int: Int] = [0: 0, 1: 100, 2: 200]

        let locator = SearchHitToLocatorResolver.resolve(
            hit: hit,
            fingerprint: Self.txtFP,
            segmentBaseOffsets: segmentBaseOffsets
        )
        #expect(locator != nil)
        // The global offset should be segment base (200) + hit offset (15) = 215
        #expect(locator?.charOffsetUTF16 == 215)
    }

    @Test func resolveTXTRange() {
        let hit = SearchHit(
            fingerprintKey: Self.txtFP.canonicalKey,
            sourceUnitId: "txt:segment:0",
            snippet: "hello",
            matchStartOffsetUTF16: 0,
            matchEndOffsetUTF16: 5
        )

        let segmentBaseOffsets: [Int: Int] = [0: 0]

        let locator = SearchHitToLocatorResolver.resolve(
            hit: hit,
            fingerprint: Self.txtFP,
            segmentBaseOffsets: segmentBaseOffsets
        )
        #expect(locator != nil)
        #expect(locator?.charOffsetUTF16 == 0)
    }

    // MARK: - Edge cases

    @Test func invalidSourceUnitIdFormat() {
        let hit = SearchHit(
            fingerprintKey: Self.txtFP.canonicalKey,
            sourceUnitId: "invalid:format",
            snippet: "text",
            matchStartOffsetUTF16: 0,
            matchEndOffsetUTF16: 4
        )

        let locator = SearchHitToLocatorResolver.resolve(hit: hit, fingerprint: Self.txtFP)
        #expect(locator == nil)
    }

    @Test func pdfNonNumericPage() {
        let hit = SearchHit(
            fingerprintKey: Self.pdfFP.canonicalKey,
            sourceUnitId: "pdf:page:abc",
            snippet: "text",
            matchStartOffsetUTF16: 0,
            matchEndOffsetUTF16: 4
        )

        let locator = SearchHitToLocatorResolver.resolve(hit: hit, fingerprint: Self.pdfFP)
        #expect(locator == nil)
    }

    @Test func txtMissingSegmentBaseOffset() {
        let hit = SearchHit(
            fingerprintKey: Self.txtFP.canonicalKey,
            sourceUnitId: "txt:segment:99",
            snippet: "text",
            matchStartOffsetUTF16: 0,
            matchEndOffsetUTF16: 4
        )

        // No segment 99 in base offsets
        let segmentBaseOffsets: [Int: Int] = [0: 0]

        let locator = SearchHitToLocatorResolver.resolve(
            hit: hit,
            fingerprint: Self.txtFP,
            segmentBaseOffsets: segmentBaseOffsets
        )
        #expect(locator == nil)
    }

    // MARK: - MD resolution

    private static let mdFP = DocumentFingerprint(
        contentSHA256: "aabbccdd00112233aabbccdd00112233aabbccdd00112233aabbccdd00112236",
        fileByteCount: 256,
        format: .md
    )

    @Test func resolveMDHit() {
        let hit = SearchHit(
            fingerprintKey: Self.mdFP.canonicalKey,
            sourceUnitId: "md:segment:1",
            snippet: "...md content...",
            matchStartOffsetUTF16: 10,
            matchEndOffsetUTF16: 20
        )

        let segmentBaseOffsets: [Int: Int] = [0: 0, 1: 50]

        let locator = SearchHitToLocatorResolver.resolve(
            hit: hit,
            fingerprint: Self.mdFP,
            segmentBaseOffsets: segmentBaseOffsets
        )
        #expect(locator != nil)
        // Global offset = segment base (50) + hit offset (10) = 60
        #expect(locator?.charOffsetUTF16 == 60)
    }

    @Test func resolveMDHitMissingOffsets() {
        let hit = SearchHit(
            fingerprintKey: Self.mdFP.canonicalKey,
            sourceUnitId: "md:segment:0",
            snippet: "text",
            matchStartOffsetUTF16: 0,
            matchEndOffsetUTF16: 4
        )

        let locator = SearchHitToLocatorResolver.resolve(
            hit: hit,
            fingerprint: Self.mdFP,
            segmentBaseOffsets: nil
        )
        #expect(locator == nil)
    }

    // MARK: - Edge cases

    @Test func emptySourceUnitId() {
        let hit = SearchHit(
            fingerprintKey: Self.txtFP.canonicalKey,
            sourceUnitId: "",
            snippet: "text",
            matchStartOffsetUTF16: 0,
            matchEndOffsetUTF16: 4
        )

        let locator = SearchHitToLocatorResolver.resolve(hit: hit, fingerprint: Self.txtFP)
        #expect(locator == nil)
    }

    // MARK: - Snippet sanitization — Bug #182 / GH #594
    //
    // SearchQueryExecutor.extractSnippet returns "...prefix<b>match</b>suffix..."
    // for display in the search results list. The EPUB reader feeds the locator's
    // `textQuote` to `window.find()` (plain-text matcher); the PDF reader feeds it
    // to PDFKit's `findString(_:withOptions:)` (also plain-text). Neither matcher
    // can find a string with literal `<b>` tags or leading `...` ellipses, so the
    // yellow search highlight silently never paints. Fix: the resolver must strip
    // the snippet's display markers before stashing it as `textQuote`, preferring
    // the bolded match (the actual found text) when present.

    @Test func resolveEPUBHit_stripsBoldAndEllipsisFromTextQuote() {
        let hit = SearchHit(
            fingerprintKey: Self.epubFP.canonicalKey,
            sourceUnitId: "epub:chapter1.xhtml",
            snippet: "...The quick brown <b>fox</b> jumps over the lazy dog...",
            matchStartOffsetUTF16: 16,
            matchEndOffsetUTF16: 19
        )

        let locator = SearchHitToLocatorResolver.resolve(hit: hit, fingerprint: Self.epubFP)
        #expect(locator != nil)
        // The bolded match is the actual found text; that's the term that needs
        // to land in window.find().
        #expect(locator?.textQuote == "fox")
    }

    @Test func resolvePDFHit_stripsBoldAndEllipsisFromTextQuote() {
        let hit = SearchHit(
            fingerprintKey: Self.pdfFP.canonicalKey,
            sourceUnitId: "pdf:page:5",
            snippet: "...begin <b>middle</b> end...",
            matchStartOffsetUTF16: 9,
            matchEndOffsetUTF16: 15
        )

        let locator = SearchHitToLocatorResolver.resolve(hit: hit, fingerprint: Self.pdfFP)
        #expect(locator != nil)
        #expect(locator?.textQuote == "middle")
    }

    @Test func resolveEPUBHit_snippetWithoutBoldTags_fallsBackToStrippedText() {
        // Defensive: if the snippet ever loses its <b> markers (FTS5 mode change,
        // upstream refactor), the resolver should still strip leading/trailing
        // ellipses and any straggling tags so the textQuote is plain-text.
        let hit = SearchHit(
            fingerprintKey: Self.epubFP.canonicalKey,
            sourceUnitId: "epub:chapter1.xhtml",
            snippet: "...some plain context fox jumps...",
            matchStartOffsetUTF16: 22,
            matchEndOffsetUTF16: 25
        )

        let locator = SearchHitToLocatorResolver.resolve(hit: hit, fingerprint: Self.epubFP)
        #expect(locator != nil)
        // Without <b> tags we can't recover just the match, but at minimum the
        // ellipsis sentinels must be gone — they will always break plain-text
        // matchers if left in.
        let textQuote = locator?.textQuote ?? ""
        #expect(!textQuote.hasPrefix("..."))
        #expect(!textQuote.hasSuffix("..."))
        #expect(!textQuote.contains("<b>"))
        #expect(!textQuote.contains("</b>"))
    }

    @Test func resolveEPUBHit_snippetAtBoundary_handlesAbsentEllipsis() {
        // Boundary case: when the match is at the very start or end of the
        // chapter, extractSnippet omits one or both `...` markers. The bold
        // match must still be extracted correctly.
        let hit = SearchHit(
            fingerprintKey: Self.epubFP.canonicalKey,
            sourceUnitId: "epub:chapter1.xhtml",
            snippet: "<b>Beginning</b> of the chapter goes here...",
            matchStartOffsetUTF16: 0,
            matchEndOffsetUTF16: 9
        )

        let locator = SearchHitToLocatorResolver.resolve(hit: hit, fingerprint: Self.epubFP)
        #expect(locator != nil)
        #expect(locator?.textQuote == "Beginning")
    }

    @Test func resolveEPUBHit_snippetWithUnicodeAndCJK_preservedInsideBold() {
        // The match itself can contain Unicode, CJK, combining marks. The
        // extractor must preserve them byte-for-byte — only the surrounding
        // display chrome (ellipsis, <b>, </b>) is removed.
        let hit = SearchHit(
            fingerprintKey: Self.epubFP.canonicalKey,
            sourceUnitId: "epub:chapter1.xhtml",
            snippet: "...prelude <b>café résumé 北京</b> postlude...",
            matchStartOffsetUTF16: 11,
            matchEndOffsetUTF16: 22
        )

        let locator = SearchHitToLocatorResolver.resolve(hit: hit, fingerprint: Self.epubFP)
        #expect(locator != nil)
        #expect(locator?.textQuote == "café résumé 北京")
    }

    // MARK: - cleanSnippetForTextQuote — direct pure-function coverage
    //
    // The resolver tests above exercise the cleaning indirectly via the EPUB
    // and PDF paths. These tests target `cleanSnippetForTextQuote` directly
    // to lock down the contract for the branches Codex flagged as
    // most-likely-to-silently-regress: nil, empty, whitespace-only, lone
    // tag halves, empty bold, and the math-notation case that motivated
    // narrowing the fallback strip from "any `<...>`" to "literal `<b>` /
    // `</b>` only".

    @Test func cleanSnippetForTextQuote_nilInput_returnsNil() {
        #expect(SearchHitToLocatorResolver.cleanSnippetForTextQuote(nil) == nil)
    }

    @Test func cleanSnippetForTextQuote_emptyInput_returnsNil() {
        #expect(SearchHitToLocatorResolver.cleanSnippetForTextQuote("") == nil)
    }

    @Test func cleanSnippetForTextQuote_whitespaceOnly_returnsNil() {
        #expect(SearchHitToLocatorResolver.cleanSnippetForTextQuote("   \n\t  ") == nil)
    }

    @Test func cleanSnippetForTextQuote_emptyBoldPair_returnsNil() {
        // The reader cannot highlight an empty match. Collapse `<b></b>` to nil
        // rather than handing window.find() / PDFKit findString an empty string
        // (which behaves as "match everything" / "no-op" depending on the API).
        #expect(SearchHitToLocatorResolver.cleanSnippetForTextQuote("...prefix <b></b> suffix...") == nil)
    }

    @Test func cleanSnippetForTextQuote_whitespaceOnlyBoldPair_returnsNil() {
        // Same defense for `<b>   </b>` — whitespace-only matches would have
        // the same downstream effect as an empty match.
        let cleaned = SearchHitToLocatorResolver.cleanSnippetForTextQuote("...prefix <b>   </b> suffix...")
        // Either nil (best) or trimmed-then-empty-rejected — both are acceptable
        // contracts for the caller. The contract that's NOT acceptable is
        // returning whitespace, since that would silently fail downstream.
        if let cleaned {
            #expect(cleaned.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false,
                    "if non-nil, must be non-empty after trim")
        }
    }

    @Test func cleanSnippetForTextQuote_loneOpenTag_fallsBackAndStripsTag() {
        // `<b>` with no closing `</b>` — corrupt snippet. The bold-extraction
        // branch returns no range; the fallback path runs and strips the lone
        // `<b>`. Should NOT crash, should NOT contain the literal `<b>`.
        let cleaned = SearchHitToLocatorResolver.cleanSnippetForTextQuote("...some <b>partial text without close...")
        #expect(cleaned != nil)
        #expect(cleaned?.contains("<b>") == false)
        #expect(cleaned?.hasPrefix("...") == false)
        #expect(cleaned?.hasSuffix("...") == false)
    }

    @Test func cleanSnippetForTextQuote_loneCloseTag_fallsBackAndStripsTag() {
        // `</b>` with no opening `<b>`. Same expectation as the lone open.
        let cleaned = SearchHitToLocatorResolver.cleanSnippetForTextQuote("...some partial text without open</b> tail...")
        #expect(cleaned != nil)
        #expect(cleaned?.contains("</b>") == false)
    }

    @Test func cleanSnippetForTextQuote_mathNotation_preservedNotMangled() {
        // Regression guard for Codex audit finding: literal angle brackets in
        // math notation must NOT be stripped (they're not HTML tags). The
        // previous over-broad implementation would have mangled "1 < 2 > 1"
        // into "1 1" because anything between `<` and `>` got removed. The
        // narrower fallback only strips literal `<b>` / `</b>`.
        let cleaned = SearchHitToLocatorResolver.cleanSnippetForTextQuote("if 1 < 2 > 1 then …")
        #expect(cleaned != nil)
        #expect(cleaned?.contains("1 < 2 > 1") == true,
                "math notation must not be eaten by the fallback strip")
    }
}
