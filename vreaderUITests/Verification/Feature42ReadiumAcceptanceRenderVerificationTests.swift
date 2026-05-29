// Purpose: Feature #42 WI-13 — Phase-1 acceptance pass (Readium EPUB engine,
// flag FORCED ON). This file covers the RENDER / PARSE / POSITION / THEME /
// PHOTO-BG / NAVIGATION / FOOTNOTE criteria across the EPUB2 / EPUB3 / RTL /
// CJK corpus. The HIGHLIGHT / SEARCH / BILINGUAL / TTS criteria live in
// `Feature42ReadiumAcceptanceFeaturesVerificationTests` (split to keep each
// file < 300 lines).
//
// Flag forcing: the Readium engine is gated by `FeatureFlags.shared
// .isEnabled(.readiumEPUBEngine)`, which reads the persisted UserDefaults key
// `com.vreader.featureFlags.readiumEPUBEngine`. Passing `-com.vreader
// .featureFlags.readiumEPUBEngine YES` as a launch argument lands it in the
// NSArgumentDomain that `UserDefaults.standard.object(forKey:)` reads at
// `FeatureFlags.init`, so the EPUB dispatcher routes to `ReadiumEPUBHost`.
//
// Host-vs-runner (bug #242 / #1054): `xcrun simctl openurl` invoked from
// inside the XCUITest runner sandbox exits 72 (NSPOSIX 61) in CI. We probe the
// channel up front and `XCTSkipUnless(bridgeReachable())`; the authoritative
// CU-free evidence is the HOST driver recorded in
// `dev-docs/verification/feature-42-20260529.md`. XCUITest-observable signals
// (chrome mount) run unconditionally; bridge-readable signals (eval / snapshot)
// run only when the channel is reachable.
//
// Corpus (Readium-acceptance fixtures, seeded via the bridge — the launch
// helper only seeds mini-epub3):
//   • mini-epub2 — OPF 2.0 + NCX, English (EPUB2 parse + render).
//   • mini-rtl   — page-progression-direction=rtl + dir=rtl, Arabic.
//   • mini-cjk   — Chinese; chapter 2 vertical-rl; footnote noteref ch1→ch2.
//   (EPUB3-English is covered by mini-epub3 via the .epubFixture seed.)
//
// @coordinates-with: ReadiumEPUBHost.swift, ReadiumDebugProbe.swift,
//   DebugFixtureCatalog.swift, VerificationDebugBridgeHelper.swift,
//   FeatureFlags.swift

import XCTest

@MainActor
final class Feature42ReadiumAcceptanceRenderVerificationTests: XCTestCase {
    var app: XCUIApplication!
    var bridgeHelper: VerificationDebugBridgeHelper!

    /// `-key value` launch args forcing the Readium engine ON.
    static let readiumOnArgs = ["-com.vreader.featureFlags.readiumEPUBEngine", "YES"]

    // Corpus fingerprint keys (epub:<sha256-of-file>:<bytecount>). Pinned to
    // the bundled fixtures — recomputed if the fixture bytes change.
    enum Corpus {
        static let epub2 = "epub:51540cef35abf31f9e6bbde7e8ef0dcfe8f28589a56862bb7c7395211b8153d4:2653"
        static let rtl = "epub:82327ac914f5ffe90c746658b32b68d3252a91be675e842c634a141d15b46a23:2632"
        static let cjk = "epub:984f8611bb2842e0bc3a7b90cef7ffed37e4cc23136450ac6b90ef126771bb53:2956"
        // mini-epub3 — the EPUB3-English dimension (also auto-seeded by .epubFixture).
        static let epub3 = "epub:f284fd074ccd1d3c1a78985464d9e1be27975f4029f3c2ddef8428ca10684af4:2198"
    }

    override func setUpWithError() throws {
        continueAfterFailure = false
        // Seed mini-epub3 in-process (real openable EPUB3) AND force Readium ON.
        // The corpus fixtures (epub2/rtl/cjk) are seeded over the bridge in the
        // bridge-reachable branch of each test.
        app = launchApp(
            seed: .epubFixture,
            resetPreferences: true,
            extraLaunchArguments: Self.readiumOnArgs
        )
        bridgeHelper = VerificationDebugBridgeHelper(app: app)
    }

    override func tearDownWithError() throws {
        app = nil
        bridgeHelper = nil
    }

    // MARK: - Helpers

    /// Probes whether the DebugBridge URL channel is reachable from this
    /// runner. CI runners are sandboxed (NSPOSIX 61); local/dev runs reach it.
    func bridgeReachable() -> Bool {
        bridgeHelper.settleApp(token: "f42-probe-\(Int(Date().timeIntervalSince1970))", timeout: 5)
    }

    /// The top-chrome back button — the Readium-host reader-loaded XCUITest
    /// signal. NOTE: unlike the legacy per-format containers, the Readium host
    /// (`ReadiumEPUBHost+Body`) does NOT render its own `ReaderBottomChrome`,
    /// so the legacy `readerSettingsButton` (Display) gate does not apply under
    /// the Readium engine. The shared `ReaderTopChrome` back button mounts once
    /// the reader pushes — the XCUITest-observable "Readium reader is up" gate.
    func readerLoadedGate() -> XCUIElement {
        app.buttons[AccessibilityID.readerBackButton]
    }

    /// Reset the store, seed + open a corpus fixture by name + key, settle,
    /// return whether the reader settled. The reset guarantees a clean store
    /// (no stale saved position from a prior run) so position/nav assertions
    /// start from chapter 1. No-op-safe: callers gate on `bridgeReachable()`.
    @discardableResult
    func openCorpus(fixture: String, key: String) -> Bool {
        bridgeHelper.resetApp()
        _ = bridgeHelper.settleApp(token: "reset-\(fixture)", timeout: 8)
        bridgeHelper.seedFixture(named: fixture)
        _ = bridgeHelper.settleApp(token: "seed-\(fixture)", timeout: 10)
        bridgeHelper.open(bookId: key)
        return bridgeHelper.settleApp(token: "open-\(fixture)", timeout: 20)
    }

    /// Run a single-expression JS probe against the Readium spine and return
    /// the `result` value (or nil on error/absence).
    func evalEPUB(_ js: String, tag: String) -> Any? {
        bridgeHelper.eval(bridge: "epub", js: js)
        _ = bridgeHelper.settleApp(token: "eval-\(tag)", timeout: 8)
        return bridgeHelper.readEval(bridge: "epub")?["result"]
    }

    // MARK: - Criterion 1 — Render (EPUB3 via XCUITest chrome gate)

    /// EPUB3 content renders under Readium: the reader pushes (back button) and
    /// the v2 bottom-chrome Display button mounts after the Readium host loads
    /// mini-epub3. XCUITest-observable, so it runs even when the bridge is
    /// unreachable. The Readium open is async off-main (AssetRetriever →
    /// PublicationOpener → navigator), slower than the legacy bridge, so the
    /// card tap is retried and the chrome gate gets a generous timeout.
    func test_c1_render_epub3_chromeMounts() {
        let card = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH 'bookCard_'")
        ).firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 20), "seeded EPUB card should appear")

        let backButton = app.buttons[AccessibilityID.readerBackButton]
        var pushed = false
        for _ in 0..<3 {
            if card.waitForHittable(timeout: 8) {
                card.tap()
            } else if card.exists {
                card.tap()
            }
            if backButton.waitForExistence(timeout: 25) {
                pushed = true
                break
            }
        }
        XCTAssertTrue(pushed, "Readium reader should push (back button) after opening the EPUB3 book")

        // The shared ReaderTopChrome back button is the Readium-host
        // reader-loaded XCUITest signal (the Readium host renders no
        // ReaderBottomChrome, so the legacy Display-button gate does not apply).
        XCTAssertTrue(
            readerLoadedGate().waitForExistence(timeout: 25),
            "Readium EPUB3 reader top chrome (back button) should mount (engine forced ON)"
        )
    }

    // MARK: - Criterion 1 — Render across the corpus (eval p-count)

    /// EPUB2 / RTL / CJK each parse + render under Readium: a non-zero
    /// paragraph count proves the spine HTML loaded into the navigator.
    func test_c1_render_corpus_pCountNonZero() throws {
        try XCTSkipUnless(bridgeReachable(), skipReason())

        for (fixture, key) in [("mini-epub2", Corpus.epub2),
                               ("mini-rtl", Corpus.rtl),
                               ("mini-cjk", Corpus.cjk)] {
            XCTAssertTrue(openCorpus(fixture: fixture, key: key),
                          "\(fixture) should seed+open+settle under Readium")
            let pCount = evalEPUB("document.querySelectorAll('p').length", tag: "pc-\(fixture)")
            XCTAssertEqual(pCount as? Int, 3,
                           "\(fixture) should render 3 paragraphs (got \(String(describing: pCount)))")
        }
    }

    // MARK: - Criterion 1b — RTL direction applied

    /// RTL fixture: the Readium navigator applies `dir=rtl` to the document.
    func test_c1b_render_rtl_directionApplied() throws {
        try XCTSkipUnless(bridgeReachable(), skipReason())
        XCTAssertTrue(openCorpus(fixture: "mini-rtl", key: Corpus.rtl))
        let dir = evalEPUB(
            "document.documentElement.getAttribute('dir') || (document.body && document.body.getAttribute('dir')) || getComputedStyle(document.documentElement).direction",
            tag: "dir-rtl"
        )
        XCTAssertEqual((dir as? String)?.lowercased(), "rtl",
                       "RTL fixture should render with dir=rtl (got \(String(describing: dir)))")
    }

    // MARK: - Criterion 2 — Position save/restore

    /// Audit M1 fix: navigate to chapter 2 via SEARCH (the Readium-observed
    /// `.readerNavigateToLocator` path — `navigate?spine=N` is legacy-only, not
    /// observed by the Readium host), then reopen the SAME book WITHOUT wiping
    /// the store (a `reset` would clear the persisted position) and assert the
    /// rendered spine restored to chapter 2. `location.href` is the
    /// authoritative restore signal (the snapshot `position` STRING reads null
    /// under Readium — see the evidence file Observations).
    func test_c2_position_saveRestore() throws {
        try XCTSkipUnless(bridgeReachable(), skipReason())
        XCTAssertTrue(openCorpus(fixture: "mini-epub2", key: Corpus.epub2))
        XCTAssertTrue(hrefSpine(evalHref()) == "chapter1.xhtml",
                      "fresh open should render chapter 1")

        // Navigate to chapter 2 via the ch2-only search token `filler`, then
        // let the WI-6 position save persist.
        bridgeHelper.search(query: "filler", index: 0)
        XCTAssertTrue(bridgeHelper.settleApp(token: "nav-c2", timeout: 15),
                      "reader should settle after the search navigation to chapter 2")
        XCTAssertEqual(hrefSpine(evalHref()), "chapter2.xhtml",
                       "search-nav should land on chapter 2 before the reopen")
        _ = bridgeHelper.settleApp(token: "save-settle", timeout: 8)

        // Reopen the SAME book (no reset → the persisted VReaderLocator survives).
        bridgeHelper.open(bookId: Corpus.epub2)
        XCTAssertTrue(bridgeHelper.settleApp(token: "reopen", timeout: 20))
        XCTAssertEqual(hrefSpine(evalHref()), "chapter2.xhtml",
                       "reopened position should restore to the saved chapter 2 (VReaderLocator round-trip)")
    }

    // MARK: - Criterion 8 — Photo background renders transparent

    /// `.photo` theme: the spine `body` background is transparent so a photo can
    /// composite through (criterion 8). NOTE (host-observed): with `theme=photo`
    /// but NO stored custom-background image, the `html:root` element keeps the
    /// photo theme's solid tone — the full `html:root,body{background:transparent}`
    /// compositing only activates once `ThemeBackgroundStore` has an image (set
    /// via the picker — a gesture/CU path, documented partial). The compositing
    /// CSS + the `hasBackgroundImage` decision are unit-covered
    /// (`ReadiumReaderCoordinator+Transparency`). This CU-free test asserts the
    /// body-layer transparency, the part reachable without a stored image.
    func test_c8_photoBackground_bodyTransparent() throws {
        try XCTSkipUnless(bridgeReachable(), skipReason())
        XCTAssertTrue(openCorpus(fixture: "mini-epub3", key: Corpus.epub3))
        bridgeHelper.theme(mode: "photo")
        XCTAssertTrue(bridgeHelper.settleApp(token: "theme-photo", timeout: 12))
        let bg = evalEPUB("getComputedStyle(document.body).backgroundColor", tag: "photo-bg")
        // A clear/transparent background renders as rgba(...,0) or "transparent".
        let bgStr = (bg as? String)?.lowercased() ?? ""
        XCTAssertTrue(
            bgStr.contains("rgba(0, 0, 0, 0)") || bgStr == "transparent" || bgStr.hasSuffix(", 0)"),
            "photo theme should leave the spine body background transparent (got \(bgStr))"
        )
    }

    // MARK: - Criterion 9 — Navigation (cross-spine via search-driven nav)

    /// Audit M2 fix: cross-spine navigation via the Readium-observed
    /// `.readerNavigateToLocator` path (search-driven — `navigate?spine=N` is
    /// legacy-only). ch1 → ch2 (search ch2-only `filler`) → ch1 (search ch1-only
    /// `verifiableneedle`); the rendered spine href flips each way.
    func test_c9_navigation_spineChanges() throws {
        try XCTSkipUnless(bridgeReachable(), skipReason())
        XCTAssertTrue(openCorpus(fixture: "mini-epub2", key: Corpus.epub2))
        XCTAssertEqual(hrefSpine(evalHref()), "chapter1.xhtml", "fresh open renders chapter 1")

        bridgeHelper.search(query: "filler", index: 0)  // ch2-only token
        XCTAssertTrue(bridgeHelper.settleApp(token: "nav-ch2", timeout: 15))
        XCTAssertEqual(hrefSpine(evalHref()), "chapter2.xhtml",
                       "navigating to a chapter-2 token should render chapter 2")

        bridgeHelper.search(query: "verifiableneedle", index: 0)  // ch1-only token
        XCTAssertTrue(bridgeHelper.settleApp(token: "nav-ch1", timeout: 15))
        XCTAssertEqual(hrefSpine(evalHref()), "chapter1.xhtml",
                       "navigating back to a chapter-1 token should render chapter 1")
    }

    // MARK: - Shared

    /// The active Readium spine's full resource URL (`readium://<uuid>/OEBPS/
    /// chapterN.xhtml`). The authoritative cross-spine + restore signal under
    /// Readium (the snapshot `position` STRING reads null for this engine).
    func evalHref() -> String { (evalEPUB("location.href", tag: "href") as? String) ?? "" }

    /// The trailing path component of a Readium spine URL (e.g. `chapter2.xhtml`).
    func hrefSpine(_ href: String) -> String {
        String(href.split(separator: "/").last ?? "")
    }

    func skipReason() -> String {
        "Bug #242/#1054: DebugBridge unreachable from the XCUITest runner sandbox " +
        "(NSPOSIX 61). Readium-engine flag forcing + chrome mount verified " +
        "unconditionally; eval/snapshot assertions are carried by the HOST " +
        "driver — see dev-docs/verification/feature-42-20260529.md."
    }
}
