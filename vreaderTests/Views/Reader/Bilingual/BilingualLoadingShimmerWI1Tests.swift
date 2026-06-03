// Purpose: Feature #77 WI-1 — pin the foundational "loading shimmer" seams
// shared by every bilingual renderer (Readium / legacy-EPUB / Foliate):
//
//   1. `ReaderThemeV2.bilingualLoadingCSSRule()` — the theme-aware shimmer CSS
//      (the `@keyframes bShim` animation + `.vreader-shimmer-bar` styling), so
//      an in-flight translation shows a shimmer placeholder rather than empty
//      space or a downgraded body line.
//   2. `EPUBBilingualJS.bilingualInjectLoadingJS(loadingBids:spineIndex:)` —
//      inserts a `<div class="vreader-bilingual vreader-bilingual-loading"
//      data-vreader-decoration>` (2 shimmer bars) after each enumerated block,
//      skipping any block that already carries a decoration so a landed
//      translation is never downgraded back to a shimmer.
//   3. The inject (translation-landed) path drops the loading class via
//      `existing.classList.remove('vreader-bilingual-loading')` before writing
//      the translated text, so the shimmer node becomes the final block in place.
//   4. `EPUBBilingualOrchestrator.buildLoadingJS(forSection:)` — the host-side
//      builder mirroring `buildInjectJS`, section-scoped.
//   5. `BilingualReadingViewModel.setInFlight(_:)` — the single funnel for every
//      `inFlightUnits` mutation, posting `.readerBilingualPrefetchDidChange`
//      with the FULL current set so a renderer can authoritatively (re)draw or
//      clear the shimmer across start / finish / cancel / retry / re-translate.
//
// These are pure JS/CSS-source-string + notification pins (the same shape the
// existing `EPUBBilingualJSTests` use). Runtime WebView behavior is exercised
// at slice-verification time over a fixture book.
//
// @coordinates-with: ReaderThemeV2+EPUBCSS.swift, EPUBBilingualJS.swift,
//   EPUBBilingualOrchestrator.swift, BilingualReadingViewModel.swift,
//   ReaderNotifications.swift,
//   dev-docs/plans/20260603-feature-77-bilingual-loading.md (WI-1)

import Testing
import Foundation
@testable import vreader

// MARK: - 1. Theme CSS rule

@MainActor
@Suite("Feature #77 WI-1 — bilingualLoadingCSSRule")
struct BilingualLoadingCSSRuleTests {

    @Test("light theme emits the shimmer keyframes + bar rule")
    func lightThemeRule() {
        let css = ReaderThemeV2.paper.bilingualLoadingCSSRule()
        // Gate-4 Low: the @keyframes name is namespaced to avoid colliding with
        // an arbitrary book stylesheet's own animations.
        #expect(css.contains("@keyframes vreaderBilingualShim"))
        #expect(!css.contains("@keyframes bShim "))   // the old generic name is gone
        #expect(css.contains(".vreader-bilingual-loading .vreader-shimmer-bar"))
        #expect(css.contains("animation: vreaderBilingualShim"))
        #expect(css.contains("background-size: 200% 100%"))
        // The loading decoration suppresses the translation border so the
        // placeholder reads as a shimmer, not a quoted block.
        #expect(css.contains("border-left-color: transparent"))
    }

    @Test("light vs dark use different shimmer gradients")
    func themeAwareGradient() {
        let light = ReaderThemeV2.paper.bilingualLoadingCSSRule()
        let dark = ReaderThemeV2.dark.bilingualLoadingCSSRule()
        // Dark uses a white-on-dark gradient; light uses a dark-on-light one.
        #expect(light.contains("rgba(20,14,4"))
        #expect(dark.contains("rgba(255,255,255"))
        #expect(light != dark)
    }

    @Test("oled (dark) matches the dark gradient")
    func oledIsDarkGradient() {
        let css = ReaderThemeV2.oled.bilingualLoadingCSSRule()
        #expect(css.contains("rgba(255,255,255"))
    }
}

// MARK: - 2 & 3. Loading-inject JS + class-clear on landed translation

@Suite("Feature #77 WI-1 — EPUBBilingualJS loading")
struct EPUBBilingualJSLoadingTests {

    @Test("loading-inject JS creates a loading decoration with shimmer bars per bid")
    func loadingInjectShape() {
        let js = EPUBBilingualJS.bilingualInjectLoadingJS(loadingBids: ["b1", "b2"])
        #expect(js.contains("'b1'"))
        #expect(js.contains("'b2'"))
        // The decoration node carries BOTH the base block class and the
        // loading modifier so the shared CSS targets it AND highlight/CFI
        // sibling walks skip it via the decoration attribute.
        #expect(js.contains(EPUBBilingualJS.blockClassName))
        #expect(js.contains(EPUBBilingualJS.loadingClassName))
        #expect(js.contains(EPUBBilingualJS.decorationAttribute))
        #expect(js.contains(EPUBBilingualJS.shimmerBarClassName))
    }

    @Test("loading-inject skips a block that already has a decoration (no downgrade)")
    func loadingInjectSkipsDecorated() {
        let js = EPUBBilingualJS.bilingualInjectLoadingJS(loadingBids: ["b1"])
        // The guard must check the decoration attribute on the next sibling so
        // a landed translation (or an existing loading node) is not replaced
        // with a fresh shimmer.
        #expect(js.contains("hasAttribute('\(EPUBBilingualJS.decorationAttribute)')"))
        #expect(js.contains("don't downgrade") || js.contains("continue"))
    }

    @Test("loading-inject bids route through FoliateJSEscaper")
    func loadingInjectEscapes() {
        // A bid containing a single quote must be escaped so it cannot break
        // out of the JS string literal.
        let js = EPUBBilingualJS.bilingualInjectLoadingJS(loadingBids: ["b'1"])
        #expect(!js.contains("'b'1'"))      // raw unescaped form must not appear
        #expect(js.contains("\\u0027") || js.contains("\\'"))
    }

    @Test("empty bids still produce well-formed no-op JS")
    func loadingInjectEmpty() {
        let js = EPUBBilingualJS.bilingualInjectLoadingJS(loadingBids: [])
        #expect(js.contains("(function()"))
        #expect(js.contains("var bids = [];"))
    }

    // Gate-4 Medium: EPUB enumerate PRESERVES a pre-existing `data-vreader-bid`
    // from book HTML, so a crafted book can carry a `"` / `]` bid. The selector
    // value must be CSS-escaped at runtime (not just JS-string-escaped) before
    // it reaches `querySelector('[data-vreader-bid="…"]')`.
    @Test("loading-inject hardens the CSS selector via __vreaderBidEsc")
    func loadingInjectSelectorHardened() {
        let js = EPUBBilingualJS.bilingualInjectLoadingJS(loadingBids: ["b1"])
        #expect(js.contains("function __vreaderBidEsc"))
        #expect(js.contains("CSS.escape"))
        // The selector must route the bid through the escaper, never raw.
        #expect(js.contains("__vreaderBidEsc(bid)"))
    }

    @Test("inject (translation) path also hardens the CSS selector")
    func injectSelectorHardened() {
        let js = EPUBBilingualJS.bilingualInjectJS(
            translationsByBid: ["b1": "Bonjour"], spineIndex: nil)
        #expect(js.contains("function __vreaderBidEsc"))
        #expect(js.contains("__vreaderBidEsc(bid)"))
    }

    @Test("a hostile bid is contained in the JS literal AND neutralised in the selector")
    func hostileBidStaysContained() {
        // `"` and `]` are HARMLESS inside the single-quoted `var bids = [...]`
        // literal (they only threaten the CSS selector). FoliateJSEscaper leaves
        // them raw — that is correct; the selector is protected at runtime by
        // `__vreaderBidEsc` (CSS.escape). So the value rides through as a valid
        // literal AND the selector is hardened.
        let js = EPUBBilingualJS.bilingualInjectLoadingJS(loadingBids: ["evil\"]"])
        #expect(js.contains("'evil\"]'"))            // valid single-quoted literal
        #expect(js.contains("__vreaderBidEsc(bid)")) // selector-context hardening

        // A single quote — the genuine JS-literal breaker — IS escaped so a bid
        // can never break out of the `var bids = [...]` array.
        let jsQuote = EPUBBilingualJS.bilingualInjectLoadingJS(loadingBids: ["e'vil"])
        #expect(jsQuote.contains("'e\\'vil'"))
    }

    @Test("inject (translation-landed) path clears the loading class before writing text")
    func injectClearsLoadingClass() {
        let js = EPUBBilingualJS.bilingualInjectJS(
            translationsByBid: ["b1": "Bonjour"], spineIndex: nil)
        // When a translation lands on a block that currently shows a shimmer,
        // the update branch must remove the loading modifier so the same node
        // becomes the final translation block in place (no flicker / re-insert).
        #expect(js.contains("classList.remove('\(EPUBBilingualJS.loadingClassName)')"))
    }
}

// MARK: - 4. Orchestrator buildLoadingJS

@MainActor
@Suite("Feature #77 WI-1 — EPUBBilingualOrchestrator.buildLoadingJS")
struct EPUBBilingualOrchestratorLoadingTests {

    @Test("buildLoadingJS returns nil when no blocks are known")
    func loadingNilNoBlocks() {
        let orchestrator = EPUBBilingualOrchestrator()
        #expect(orchestrator.buildLoadingJS() == nil)
        #expect(orchestrator.buildLoadingJS(forSection: 0) == nil)
    }

    @Test("buildLoadingJS (flattened) contains every known block's bid")
    func loadingFlattenedAllBids() throws {
        let orchestrator = EPUBBilingualOrchestrator()
        orchestrator.updateBlocks([
            BilingualBlock(bid: "b1", text: "Hello"),
            BilingualBlock(bid: "b2", text: "World")
        ])
        let js = try #require(orchestrator.buildLoadingJS())
        #expect(js.contains("'b1'"))
        #expect(js.contains("'b2'"))
        #expect(js.contains(EPUBBilingualJS.loadingClassName))
    }

    @Test("buildLoadingJS(forSection:) scopes to that section's blocks only")
    func loadingSectionScoped() throws {
        let orchestrator = EPUBBilingualOrchestrator()
        orchestrator.updateBlocks(
            [BilingualBlock(bid: "s0a", text: "A", sectionIndex: 0)],
            forSection: 0)
        orchestrator.updateBlocks(
            [BilingualBlock(bid: "s1a", text: "B", sectionIndex: 1)],
            forSection: 1)
        let js = try #require(orchestrator.buildLoadingJS(forSection: 0))
        #expect(js.contains("'s0a'"))
        #expect(!js.contains("'s1a'"))   // section 1's bid must NOT leak in
    }
}

// MARK: - 5. setInFlight funnel + notification

@MainActor
@Suite("Feature #77 WI-1 — BilingualReadingViewModel.setInFlight funnel")
struct BilingualSetInFlightFunnelTests {

    private func makeVM() -> BilingualReadingViewModel {
        BilingualReadingViewModel(
            bookFingerprintKey: "epub:\(String(repeating: "a", count: 64)):1024",
            perBookBaseURL: FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString, isDirectory: true))
    }

    private func unit(_ s: String) -> TranslationUnitID {
        TranslationUnitID(kind: .epubHref, value: s)
    }

    @Test("setInFlight posts .readerBilingualPrefetchDidChange with the FULL set + key")
    func postsFullSet() async {
        let vm = makeVM()
        let key = vm.bookFingerprintKey
        var received: Set<TranslationUnitID>?
        var receivedKey: String?
        let token = NotificationCenter.default.addObserver(
            forName: .readerBilingualPrefetchDidChange, object: nil, queue: nil
        ) { note in
            received = note.userInfo?["inFlightUnits"] as? Set<TranslationUnitID>
            receivedKey = note.userInfo?["fingerprintKey"] as? String
        }
        defer { NotificationCenter.default.removeObserver(token) }

        vm.setInFlight([unit("u1"), unit("u2")])
        #expect(received == [unit("u1"), unit("u2")])
        #expect(receivedKey == key)
        #expect(vm.inFlightUnits == [unit("u1"), unit("u2")])
        #expect(vm.isFetching == true)
    }

    @Test("setInFlight to empty clears isFetching and posts the empty set")
    func clearsToEmpty() async {
        let vm = makeVM()
        vm.setInFlight([unit("u1")])
        var received: Set<TranslationUnitID>?
        let token = NotificationCenter.default.addObserver(
            forName: .readerBilingualPrefetchDidChange, object: nil, queue: nil
        ) { note in received = note.userInfo?["inFlightUnits"] as? Set<TranslationUnitID> }
        defer { NotificationCenter.default.removeObserver(token) }

        vm.setInFlight([])
        #expect(received == [])
        #expect(vm.inFlightUnits.isEmpty)
        #expect(vm.isFetching == false)
    }

    @Test("setInFlight is a no-op (no post) when the set is unchanged")
    func noPostWhenUnchanged() async {
        let vm = makeVM()
        vm.setInFlight([unit("u1")])
        var postCount = 0
        let token = NotificationCenter.default.addObserver(
            forName: .readerBilingualPrefetchDidChange, object: nil, queue: nil
        ) { _ in postCount += 1 }
        defer { NotificationCenter.default.removeObserver(token) }

        vm.setInFlight([unit("u1")])   // identical → guard short-circuits
        #expect(postCount == 0)
    }

    @Test("applyReTranslateResult routes through the funnel (clears the unit + posts)")
    func reTranslateRoutesThroughFunnel() async {
        let vm = makeVM()
        vm.setInFlight([unit("u1"), unit("u2")])
        var received: Set<TranslationUnitID>?
        let token = NotificationCenter.default.addObserver(
            forName: .readerBilingualPrefetchDidChange, object: nil, queue: nil
        ) { note in received = note.userInfo?["inFlightUnits"] as? Set<TranslationUnitID> }
        defer { NotificationCenter.default.removeObserver(token) }

        vm.applyReTranslateResult(["seg"], for: unit("u1"))
        #expect(received == [unit("u2")])          // u1 removed, u2 still in flight
        #expect(vm.inFlightUnits == [unit("u2")])
    }
}
