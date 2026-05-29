// Purpose: Feature #42 WI-13 — Phase-1 acceptance pass (Readium EPUB engine,
// flag FORCED ON). This file covers the SEARCH-NAV / THEME-FONT / TTS-FOLLOW /
// HIGHLIGHT-RESTORE criteria CU-free, plus the documented-partial criteria
// (highlight CREATE + bilingual translation content) whose CU-free drive is not
// reachable in the runner. The RENDER / POSITION / PHOTO-BG / NAVIGATION
// criteria live in `Feature42ReadiumAcceptanceRenderVerificationTests`.
//
// See the render-file header for the flag-forcing + host-vs-runner rationale.
// Authoritative CU-free evidence for the bridge-dependent assertions is the
// HOST driver recorded in dev-docs/verification/feature-42-20260529.md.
//
// Documented-partial criteria (recorded as partial, NOT forced into a brittle
// pass):
//   • Highlight CREATE — under Readium, a highlight is created from a finalized
//     WKWebView text selection (`.readerHighlightRequested`); there is NO
//     `vreader-debug://highlight?start=&end=` observer on the Readium host (it
//     targets the legacy EPUB/TXT/MD containers only), and XCUITest cannot
//     synthesize a WKWebView text-selection drag on iOS 26. The create→persist→
//     decoration pipeline (incl. RESTORE) is unit-covered by
//     `ReadiumSelectionHighlightBuilderTests` + `ReadiumDecorationHighlight
//     AdapterTests`. This suite only asserts CU-free that the snapshot
//     `highlightCount` field — the signal the restore path reads — is wired and
//     queryable under the Readium engine (NOT an end-to-end restore proof; see
//     `test_c4_highlightSnapshotWiring`'s doc).
//   • Bilingual TRANSLATION CONTENT — needs a configured AI provider; the
//     enumerate→inject decoration pipeline is unit-covered (`ReadiumBilingual
//     CommanderTests`, `ReadiumBilingualEvalAdapterTests`). Translation content
//     is provider-gated and out of scope for a deterministic CU-free run.
//
// @coordinates-with: ReadiumEPUBHost+Navigation.swift,
//   ReadiumEPUBHost+TTSFollow.swift, ReadiumDecorationHighlightAdapter.swift,
//   SearchViewModel.swift, VerificationDebugBridgeHelper.swift

import XCTest

@MainActor
final class Feature42ReadiumAcceptanceFeaturesVerificationTests: XCTestCase {
    var app: XCUIApplication!
    var bridgeHelper: VerificationDebugBridgeHelper!

    typealias Corpus = Feature42ReadiumAcceptanceRenderVerificationTests.Corpus

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = launchApp(
            seed: .epubFixture,
            resetPreferences: true,
            // Readium ON + TTS mock so ttsOffsetUTF16 advances headless (WI-4e).
            extraLaunchArguments: Feature42ReadiumAcceptanceRenderVerificationTests.readiumOnArgs
                + ["--tts-test-mode"]
        )
        bridgeHelper = VerificationDebugBridgeHelper(app: app)
    }

    override func tearDownWithError() throws {
        app = nil
        bridgeHelper = nil
    }

    // MARK: - Helpers

    func bridgeReachable() -> Bool {
        bridgeHelper.settleApp(token: "f42f-probe-\(Int(Date().timeIntervalSince1970))", timeout: 5)
    }

    @discardableResult
    func openCorpus(fixture: String, key: String) -> Bool {
        bridgeHelper.resetApp()
        _ = bridgeHelper.settleApp(token: "reset-\(fixture)", timeout: 8)
        bridgeHelper.seedFixture(named: fixture)
        _ = bridgeHelper.settleApp(token: "seed-\(fixture)", timeout: 10)
        bridgeHelper.open(bookId: key)
        return bridgeHelper.settleApp(token: "open-\(fixture)", timeout: 20)
    }

    func evalEPUB(_ js: String, tag: String) -> Any? {
        bridgeHelper.eval(bridge: "epub", js: js)
        _ = bridgeHelper.settleApp(token: "eval-\(tag)", timeout: 8)
        return bridgeHelper.readEval(bridge: "epub")?["result"]
    }

    func snapshot(_ dest: String, tag: String) -> [String: Any]? {
        bridgeHelper.snapshotApp(dest: dest)
        _ = bridgeHelper.settleApp(token: "snap-\(tag)", timeout: 8)
        return bridgeHelper.readSnapshot(dest: dest)
    }

    func skipReason() -> String {
        "Bug #242/#1054: DebugBridge unreachable from the XCUITest runner sandbox " +
        "(NSPOSIX 61). Evidence carried by the HOST driver — see " +
        "dev-docs/verification/feature-42-20260529.md."
    }

    // MARK: - Criterion 3 — Theme + font apply

    /// Apply a dark theme + a font-size change; the snapshot reflects both, and
    /// the rendered body background is dark (not white). Drives the same
    /// `EPUBPreferences` path the settings UI uses.
    func test_c3_themeAndFont_apply() throws {
        try XCTSkipUnless(bridgeReachable(), skipReason())
        XCTAssertTrue(openCorpus(fixture: "mini-epub3", key: Corpus.epub3))

        bridgeHelper.theme(mode: "dark", fontSize: 24)
        XCTAssertTrue(bridgeHelper.settleApp(token: "theme-dark", timeout: 12))

        let snap = snapshot("f42-theme.json", tag: "theme")
        XCTAssertEqual(snap?["theme"] as? String, "dark",
                       "snapshot theme should reflect the applied dark theme")
        XCTAssertEqual(snap?["fontSize"] as? Int, 24,
                       "snapshot fontSize should reflect the applied 24pt size")

        // Audit Low-1 fix: the rendered body font-size should track the
        // requested 24pt (readium-css maps the pt preference to a px value near
        // it; host-observed ≈23.9px for 24pt). Assert it's in a tight band
        // around the requested size. Audit R2-Low-A: XCTUnwrap so a nil /
        // non-numeric eval result FAILS explicitly rather than silently passing
        // (a regression in the eval seam must not look like a green font check).
        let fontPx = evalEPUB("parseFloat(getComputedStyle(document.body).fontSize)", tag: "font")
        let px = try XCTUnwrap((fontPx as? NSNumber)?.doubleValue,
            "body font-size eval should return a numeric px value (got \(String(describing: fontPx)))")
        XCTAssertGreaterThanOrEqual(px, 22.0,
            "body font-size should track the 24pt preference (got \(px), expected ≈24)")
        XCTAssertLessThanOrEqual(px, 26.0,
            "body font-size should track the 24pt preference (got \(px), expected ≈24)")
    }

    // MARK: - Criterion 5 — Search → navigate to result

    /// Audit M3 fix: search for a CHAPTER-2-ONLY token (`filler`) from a fresh
    /// open on chapter 1, so a passing assertion genuinely proves the search
    /// result NAVIGATED across the spine (the earlier `verifiableneedle` token
    /// lives in chapter 1 = the already-open spine, so a pass was vacuous). The
    /// existing FTS + Readium nav mapping (WI-9) drives `.readerNavigateToLocator`.
    func test_c5_searchNavigatesToResult() throws {
        try XCTSkipUnless(bridgeReachable(), skipReason())
        XCTAssertTrue(openCorpus(fixture: "mini-epub2", key: Corpus.epub2))
        let preHref = (evalEPUB("location.href", tag: "search-pre") as? String) ?? ""
        XCTAssertTrue(preHref.hasSuffix("chapter1.xhtml"),
                      "fresh open should render chapter 1 before the search (got '\(preHref)')")

        // search?query=...&index=0 opens the sheet, runs the query, taps result 0.
        bridgeHelper.search(query: "filler", index: 0)  // chapter-2-only token
        XCTAssertTrue(bridgeHelper.settleApp(token: "search-nav", timeout: 15),
                      "reader should settle after the search result navigation")

        // The chapter-2 token must navigate the reader INTO chapter 2.
        let postHref = (evalEPUB("location.href", tag: "search-post") as? String) ?? ""
        XCTAssertTrue(postHref.hasSuffix("chapter2.xhtml"),
                      "search for a chapter-2 token should navigate to chapter 2 (got '\(postHref)')")
    }

    // MARK: - Criterion 7 — TTS plays + navigator follows

    /// Start TTS; the snapshot's ttsState becomes speaking and ttsOffsetUTF16
    /// advances (the navigator-follow path, WI-10/10b). `--tts-test-mode` swaps
    /// the synth so offsets advance headless.
    func test_c7_tts_offsetAdvances() throws {
        try XCTSkipUnless(bridgeReachable(), skipReason())
        XCTAssertTrue(openCorpus(fixture: "mini-epub3", key: Corpus.epub3))

        bridgeHelper.ttsAction("start")
        XCTAssertTrue(bridgeHelper.settleApp(token: "tts-start", timeout: 12))

        let s1 = snapshot("f42-tts1.json", tag: "tts1")
        XCTAssertEqual(s1?["ttsState"] as? String, "speaking",
                       "TTS state should be speaking after start")
        let off1 = s1?["ttsOffsetUTF16"] as? Int ?? -1

        // Let narration progress, then re-snapshot.
        _ = bridgeHelper.settleApp(token: "tts-progress", timeout: 6)
        let s2 = snapshot("f42-tts2.json", tag: "tts2")
        let off2 = s2?["ttsOffsetUTF16"] as? Int ?? -1

        bridgeHelper.ttsAction("stop")
        _ = bridgeHelper.settleApp(token: "tts-stop", timeout: 8)

        XCTAssertGreaterThanOrEqual(off1, 0, "ttsOffsetUTF16 should be reported while speaking")
        XCTAssertGreaterThan(off2, off1,
                             "ttsOffsetUTF16 should advance during playback (off1=\(off1) off2=\(off2))")
    }

    // MARK: - Criterion 4 — highlight snapshot wiring (DOCUMENTED PARTIAL)

    /// Audit M4 fix: this is HONESTLY a snapshot-wiring check, NOT an end-to-end
    /// restore proof. Under the Readium engine a highlight is CREATED from a
    /// finalized WKWebView text selection (`.readerHighlightRequested`) — there
    /// is no `vreader-debug://highlight?start=&end=` observer on the Readium
    /// host (it targets the legacy EPUB/TXT/MD containers), and XCUITest cannot
    /// synthesize a WKWebView selection drag on iOS 26 — so neither CREATE nor a
    /// seeded persisted EPUB highlight is reachable CU-free here. The
    /// create→persist→decoration→restore pipeline is unit-covered
    /// (`ReadiumSelectionHighlightBuilderTests`, `ReadiumDecorationHighlight
    /// AdapterTests`). What this CU-free test legitimately asserts: the snapshot
    /// `highlightCount` field — the signal the restore path reads — is wired and
    /// queryable under the Readium engine (not silently nil), so a future
    /// gesture/CU run can assert a non-zero count without a wiring surprise.
    func test_c4_highlightSnapshotWiring() throws {
        try XCTSkipUnless(bridgeReachable(), skipReason())
        XCTAssertTrue(openCorpus(fixture: "mini-epub3", key: Corpus.epub3))

        let snap = snapshot("f42-hl.json", tag: "hl")
        // A freshly-opened book has no highlights → exactly 0 (NOT merely >= 0,
        // which any nil-coalesced value would satisfy). Asserting the exact
        // baseline proves the field is genuinely reported, not absent.
        XCTAssertEqual(snap?["highlightCount"] as? Int, 0,
                       "highlightCount must be reported as 0 for a fresh open under Readium " +
                       "(restore-path snapshot wiring; create+restore are unit-covered — see test doc)")
    }

    // MARK: - Criterion 10 — Footnote noteref resolves in-publication

    /// The CJK fixture's chapter 1 carries a footnote `noteref` (`href=
    /// chapter2.xhtml#note1`). Readium follows internal links natively; the
    /// live tap requires CU, but we confirm CU-free that the noteref EXISTS and
    /// points at an in-publication target the navigator can resolve.
    func test_c10_footnote_noterefPresent() throws {
        try XCTSkipUnless(bridgeReachable(), skipReason())
        XCTAssertTrue(openCorpus(fixture: "mini-cjk", key: Corpus.cjk))

        let href = evalEPUB(
            "(document.querySelector('a[epub\\\\:type=\"noteref\"]') || document.querySelector('a[href*=\"#note\"]') || {}).getAttribute ? (document.querySelector('a[epub\\\\:type=\"noteref\"]') || document.querySelector('a[href*=\"#note\"]')).getAttribute('href') : null",
            tag: "noteref"
        )
        XCTAssertNotNil(href, "chapter 1 should expose a footnote noteref link")
        if let h = href as? String {
            XCTAssertTrue(h.contains("#note"),
                          "the noteref should target an in-publication footnote anchor (got '\(h)')")
        }
    }

    // MARK: - Criterion 6 — Bilingual pipeline (enumerate; provider-gated content)

    /// Documented-partial: bilingual TRANSLATION CONTENT needs a configured AI
    /// provider. The enumerate→inject decoration PIPELINE is unit-covered
    /// (ReadiumBilingualCommanderTests / ReadiumBilingualEvalAdapterTests). This
    /// test records that the criterion is provider-gated by asserting the
    /// pipeline's structural precondition: the corpus chapter exposes
    /// enumerable paragraph blocks the commander would decorate.
    func test_c6_bilingual_enumerableBlocksPresent() throws {
        try XCTSkipUnless(bridgeReachable(), skipReason())
        XCTAssertTrue(openCorpus(fixture: "mini-cjk", key: Corpus.cjk))
        let pCount = evalEPUB("document.querySelectorAll('p').length", tag: "bil-pc")
        XCTAssertEqual(pCount as? Int, 3,
                       "bilingual enumerate operates over the chapter's paragraph blocks " +
                       "(translation content is provider-gated — see test doc)")
    }
}
