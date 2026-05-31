// Feature #75 WI-1 — tests for the pure PageAxisResolver seam that maps a loaded
// EPUB spine document's computed writing-mode / direction (+ dir attr, lang, and
// the book-level readingDirection hint) to a per-document PageAxis. Gate-2 of the
// plan established: computed values are authoritative; the hint + lang only
// resolve `.auto` / ambiguous cases; resolution is PER-DOCUMENT (the probe runs
// per spine item), never book-level.

import Testing
@testable import vreader

@Suite("PageAxisResolver")
struct PageAxisResolverTests {

    // MARK: - Vertical writing wins outright

    @Test func verticalRL_writingMode_isVerticalRL() {
        // vertical-rl is authoritative regardless of direction.
        #expect(PageAxisResolver.resolve(
            writingMode: "vertical-rl", direction: "ltr",
            dir: nil, lang: "ja", readingDirectionHint: .ltr) == .verticalRL)
    }

    @Test func verticalRL_caseInsensitive() {
        #expect(PageAxisResolver.resolve(
            writingMode: "Vertical-RL", direction: "rtl",
            dir: nil, lang: nil, readingDirectionHint: .auto) == .verticalRL)
    }

    @Test func verticalLR_outOfScope_fallsBackToHorizontal() {
        // vertical-lr is deferred (#75 scope is vertical-rl); it must NOT map to
        // .verticalRL — it falls through to horizontal resolution.
        #expect(PageAxisResolver.resolve(
            writingMode: "vertical-lr", direction: "ltr",
            dir: nil, lang: nil, readingDirectionHint: .ltr) == .horizontalLTR)
    }

    // MARK: - Computed direction is authoritative for horizontal

    @Test func horizontal_computedRTL_isHorizontalRTL() {
        #expect(PageAxisResolver.resolve(
            writingMode: "horizontal-tb", direction: "rtl",
            dir: nil, lang: nil, readingDirectionHint: .ltr) == .horizontalRTL)
    }

    @Test func horizontal_computedLTR_isHorizontalLTR() {
        // Computed LTR beats an RTL hint — the rendered direction is what matters.
        #expect(PageAxisResolver.resolve(
            writingMode: "horizontal-tb", direction: "ltr",
            dir: nil, lang: "ar", readingDirectionHint: .rtl) == .horizontalLTR)
    }

    // MARK: - Ambiguous computed → dir attr → hint → lang

    @Test func ambiguousComputed_dirAttrRTL_isHorizontalRTL() {
        #expect(PageAxisResolver.resolve(
            writingMode: "horizontal-tb", direction: "",
            dir: "rtl", lang: nil, readingDirectionHint: .ltr) == .horizontalRTL)
    }

    @Test func ambiguousComputed_noDir_hintRTL_isHorizontalRTL() {
        #expect(PageAxisResolver.resolve(
            writingMode: "horizontal-tb", direction: "",
            dir: nil, lang: nil, readingDirectionHint: .rtl) == .horizontalRTL)
    }

    @Test func ambiguousComputed_autoHint_rtlLang_isHorizontalRTL() {
        // .auto resolves from the language: Arabic → RTL.
        #expect(PageAxisResolver.resolve(
            writingMode: "horizontal-tb", direction: "",
            dir: nil, lang: "ar", readingDirectionHint: .auto) == .horizontalRTL)
    }

    @Test func autoHint_rtlLang_withRegionSubtag_isRTL() {
        // Region subtags don't change the primary subtag's directionality.
        #expect(PageAxisResolver.resolve(
            writingMode: "horizontal-tb", direction: "",
            dir: nil, lang: "ar-EG", readingDirectionHint: .auto) == .horizontalRTL)
        #expect(PageAxisResolver.resolve(
            writingMode: "horizontal-tb", direction: "",
            dir: nil, lang: "he-IL", readingDirectionHint: .auto) == .horizontalRTL)
    }

    @Test func autoHint_ltrLang_isHorizontalLTR() {
        #expect(PageAxisResolver.resolve(
            writingMode: "horizontal-tb", direction: "",
            dir: nil, lang: "en", readingDirectionHint: .auto) == .horizontalLTR)
    }

    @Test func autoHint_noLang_defaultsLTR() {
        #expect(PageAxisResolver.resolve(
            writingMode: "horizontal-tb", direction: "",
            dir: nil, lang: nil, readingDirectionHint: .auto) == .horizontalLTR)
    }

    // MARK: - Empty / unknown inputs default to LTR (safe)

    @Test func allEmpty_defaultsHorizontalLTR() {
        #expect(PageAxisResolver.resolve(
            writingMode: "", direction: "",
            dir: nil, lang: nil, readingDirectionHint: .ltr) == .horizontalLTR)
    }

    @Test func dirAttr_overriddenByComputed() {
        // Computed direction is authoritative over the dir attribute.
        #expect(PageAxisResolver.resolve(
            writingMode: "horizontal-tb", direction: "ltr",
            dir: "rtl", lang: nil, readingDirectionHint: .rtl) == .horizontalLTR)
    }

    // MARK: - Whitespace / case normalization (audit Medium)

    @Test func whitespacePadded_writingMode_stillVertical() {
        #expect(PageAxisResolver.resolve(
            writingMode: "  vertical-rl\n", direction: "ltr",
            dir: nil, lang: nil, readingDirectionHint: .ltr) == .verticalRL)
    }

    @Test func whitespacePadded_direction_stillRTL() {
        #expect(PageAxisResolver.resolve(
            writingMode: " horizontal-tb ", direction: "  RTL ",
            dir: nil, lang: nil, readingDirectionHint: .ltr) == .horizontalRTL)
    }

    @Test func whitespacePadded_dirAttr_normalized() {
        #expect(PageAxisResolver.resolve(
            writingMode: "horizontal-tb", direction: "",
            dir: " RTL ", lang: nil, readingDirectionHint: .ltr) == .horizontalRTL)
    }

    @Test func whitespacePadded_lang_normalized() {
        #expect(PageAxisResolver.resolve(
            writingMode: "horizontal-tb", direction: "",
            dir: nil, lang: " AR-eg ", readingDirectionHint: .auto) == .horizontalRTL)
    }

    // MARK: - Precedence boundaries (audit Low)

    @Test func ltrHint_beatsRTLLang() {
        // An explicit .ltr hint beats an RTL lang (lang only resolves .auto).
        #expect(PageAxisResolver.resolve(
            writingMode: "horizontal-tb", direction: "",
            dir: nil, lang: "ar", readingDirectionHint: .ltr) == .horizontalLTR)
    }

    @Test func dirAttr_beatsHint() {
        // dir attribute is consulted before the book-level hint.
        #expect(PageAxisResolver.resolve(
            writingMode: "horizontal-tb", direction: "",
            dir: "ltr", lang: nil, readingDirectionHint: .rtl) == .horizontalLTR)
    }

    // MARK: - Extended RTL language set (audit Low)

    @Test(arguments: ["ar", "he", "iw", "fa", "prs", "ur", "ps", "sd", "ug", "yi", "dv", "ckb", "syr"])
    func autoHint_rtlLanguageTags(_ tag: String) {
        #expect(PageAxisResolver.resolve(
            writingMode: "horizontal-tb", direction: "",
            dir: nil, lang: tag, readingDirectionHint: .auto) == .horizontalRTL)
    }

    @Test func autoHint_ambiguousKurmanjiKurdish_notRTL() {
        // bare `ku` is script-ambiguous (Latin Kurmanji) → default LTR.
        #expect(PageAxisResolver.resolve(
            writingMode: "horizontal-tb", direction: "",
            dir: nil, lang: "ku", readingDirectionHint: .auto) == .horizontalLTR)
    }
}
