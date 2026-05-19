// Purpose: CU-free Gate-5 verification suite for Feature #54 — "Remove
// Native/Unified reading mode toggle; route by ReaderEngine internally".
//
// Feature #54 deleted the user-facing Reading Mode picker (Native vs
// Unified) and the Tap Zones section from `ReaderSettingsPanel`, and
// replaced the `readingMode`-branch reader dispatch with `ReaderEngine`
// routing in `ReaderContainerView`. This suite drives the app entirely
// through the XCUITest accessibility API (element queries + synthesized
// gestures) — it needs NO computer-use and does NOT rely on the
// DebugBridge `open` URL (which cannot reliably commit a NavigationStack
// push in a headless `simctl openurl` session — see
// `dev-docs/verification/feature-54-20260519.md` Observations).
//
// What this suite verifies (feature #54 acceptance criteria 1, 2, 5):
//   - Criterion 1 ("no reading-mode picker in normal use"): for each
//     openable format (TXT/EPUB/MD), open the book → open the Display
//     panel → assert NO "Reading Mode" section header and NO
//     "Native"/"Unified" picker segment exists anywhere in the panel.
//   - Criterion 2 ("replacement rules work in native MD without a mode
//     switch") — the *structural* "no mode switch" half: the MD book
//     opens into the native Markdown reader and renders content with no
//     Reading Mode picker present. Transform-application correctness is
//     covered by the 20 real-boundary integration tests cited in the
//     evidence file.
//   - Criterion 5 ("all existing reader features unchanged"): each of
//     the three openable formats opens into ITS native reader container
//     and renders content — proving `ReaderEngine` routing dispatches
//     correctly after the `readingMode`-branch deletion.
//
// Out of scope (recorded as the evidence file's documented partials):
//   - Criterion 3 (native EPUB replacement rules) is DEFERRED by the
//     plan to Phase D — it is not implemented, so no test can exercise
//     it.
//   - Criterion 4 (`readerReadingMode` UserDefaults key removed +
//     migration) is a preferences-plist / launch-migration concern, not
//     an XCUITest concern — covered device-side + by 14 unit tests.
//   - PDF and AZW3/MOBI have no openable debug seed (`TestSeeder` only
//     provides real-file TXT/MD/EPUB fixtures; the `.books` PDF records
//     are metadata-only and never open — Bug #209). Their `ReaderEngine`
//     routing (`pdfKit`, `foliateWeb`) is covered by `ReaderEngineTests`.
//
// @coordinates-with: ReaderSettingsPanel.swift, ReaderContainerView.swift,
//   ReaderEngine.swift, VerificationSettingsHelper.swift, TestSeeder.swift

import XCTest

@MainActor
final class Feature54ReadingModeRemovalVerificationTests: XCTestCase {

    // MARK: - Reading-mode picker token list

    /// Labels that, if found anywhere in the Display panel, would mean the
    /// removed Reading Mode picker (or one of its segments) is still
    /// present. Feature #54's contract is that NONE of these appear.
    /// "Native" and "Unified" were the two picker segments; "Reading Mode"
    /// was the section header; "Tap Zones" was the sibling section also
    /// removed by WI-4.
    private static let forbiddenReadingModeLabels = [
        "Reading Mode",
        "Tap Zones",
        "Tap Zone",
    ]

    // MARK: - Helpers

    /// Launches the app with the given seed and `--reset-preferences` so
    /// the run starts from a known UserDefaults state (Bug #152).
    private func launch(seed: TestSeedState) -> XCUIApplication {
        launchApp(seed: seed, resetPreferences: true)
    }

    /// Opens the first (and only) seeded book and waits for the reader
    /// chrome to appear. The card tap is retried because a first tap can
    /// land before the library `LazyVGrid` finishes its initial layout
    /// pass (the card is in the tree but not yet wired to navigation) —
    /// the same legitimate timing race handled in
    /// `Feature11EPUBBottomChromeVerificationTests`.
    ///
    /// - Returns: `true` when the reader's back button became visible.
    @discardableResult
    private func openSeededBook(in app: XCUIApplication) -> Bool {
        let card = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH 'bookCard_'")
        ).firstMatch
        let row = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH 'bookRow_'")
        ).firstMatch

        let backButton = app.buttons[AccessibilityID.readerBackButton]
        for _ in 0..<3 {
            if card.waitForExistence(timeout: 15) {
                if card.waitForHittable(timeout: 8) || card.exists { card.tap() }
            } else if row.waitForExistence(timeout: 3) {
                if row.waitForHittable(timeout: 8) || row.exists { row.tap() }
            }
            if backButton.waitForExistence(timeout: 20) { return true }
        }
        return false
    }

    /// Ensures the reader bottom chrome is visible. The chrome auto-hides;
    /// a content tap toggles it back on. Mirrors
    /// `Feature11EPUBBottomChromeVerificationTests.ensureChromeVisible`.
    private func ensureChromeVisible(in app: XCUIApplication) {
        let displayButton = app.buttons[AccessibilityID.readerSettingsButton]
        if displayButton.waitForExistence(timeout: 3) { return }
        app.tap()
        _ = displayButton.waitForExistence(timeout: 5)
    }

    /// Opens the Display (reader settings) panel, scrolls it top-to-bottom,
    /// and asserts that NO reading-mode picker artifact exists at any
    /// scroll position. This is feature #54's criterion 1.
    ///
    /// The panel is a scrollable `List`; SwiftUI lazy-renders sections, so
    /// a single snapshot would miss a section that is off-screen. The
    /// method swipes through the whole panel and checks the forbidden
    /// labels after each swipe — a removed section can never scroll into
    /// view, so a full traversal that never finds one is a sound proof of
    /// absence.
    private func assertNoReadingModePicker(
        in app: XCUIApplication,
        formatName: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let helper = VerificationSettingsHelper(app: app)
        let panel = helper.openReaderSettings(file: file, line: line)
        XCTAssertTrue(
            panel.exists,
            "[\(formatName)] Display panel should open",
            file: file, line: line
        )
        sweepPanelForReadingModeArtifacts(
            panel: panel, formatName: formatName, file: file, line: line
        )
        helper.closeReaderSettings(file: file, line: line)
    }

    /// Scrolls an already-open Display panel top-to-bottom and asserts the
    /// removed reading-mode picker artifacts are absent at every scroll
    /// position. Split out so a caller that has already opened the panel
    /// does not re-tap the Display button (which would dismiss the panel).
    private func sweepPanelForReadingModeArtifacts(
        panel: XCUIElement,
        formatName: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        // Check before scrolling, then after each of up to 10 swipes —
        // enough to traverse the full panel (12 sections) on the iPhone
        // 17 Pro viewport.
        for swipe in 0...10 {
            for label in Self.forbiddenReadingModeLabels {
                XCTAssertFalse(
                    panel.staticTexts[label].exists,
                    "[\(formatName)] Feature #54 removed the '\(label)' " +
                    "section — it must not appear in the Display panel " +
                    "(found after \(swipe) swipe(s))",
                    file: file, line: line
                )
            }
            // The two picker SEGMENTS render as buttons under
            // `.pickerStyle(.segmented)`. A "Native"/"Unified" button
            // inside the open settings panel would be the picker itself.
            for segment in ["Native", "Unified"] {
                XCTAssertFalse(
                    panel.buttons[segment].exists,
                    "[\(formatName)] Feature #54 removed the Native/Unified " +
                    "reading-mode picker — no '\(segment)' segment button " +
                    "should exist in the Display panel (after \(swipe) swipe(s))",
                    file: file, line: line
                )
            }
            if swipe < 10 { panel.swipeUp() }
        }
    }

    /// The native rendering surface a format's engine produces, identified
    /// by XCUITest ELEMENT TYPE rather than accessibility identifier.
    ///
    /// Identifier-based queries for the reader content are unreliable here:
    /// Bug #214 scoped `epubReaderContainer` / `epubReaderContent` to an
    /// inner SwiftUI `Group`, and a `Group` is a transparent container that
    /// does not always yield a queryable accessibility element — the
    /// existing `Feature11EPUBHighlightVerificationTests` documents that
    /// those identifiers "no longer resolve as a top-level query" and
    /// switches to `app.webViews.firstMatch`. This suite follows that
    /// proven pattern for ALL formats:
    ///   - EPUB → `epubWKWebView` engine → a `WKWebView` (`app.webViews`).
    ///   - TXT  → `textNative` engine → a `UITextView` (`app.textViews`)
    ///            for the full-text / chapter / continuous paths, or a
    ///            `UITableView` (`app.tables`) for the chunked large-file
    ///            path (`TXTChunkedReaderBridge`).
    ///   - MD   → `markdownNative` engine → a `UITextView` via the shared
    ///            `TXTTextViewBridge` (`MDReaderContainerView`).
    private enum NativeReaderSurface {
        /// EPUB — the WKWebView host.
        case webView
        /// TXT/MD — a UITextView, with a UITableView accepted as the
        /// alternative for TXT's chunked large-file path.
        case textViewOrTable

        /// Returns `true` if `app` currently shows this native surface.
        func isPresent(in app: XCUIApplication, timeout: TimeInterval) -> Bool {
            switch self {
            case .webView:
                return app.webViews.firstMatch.waitForExistence(timeout: timeout)
            case .textViewOrTable:
                if app.textViews.firstMatch.waitForExistence(timeout: timeout) {
                    return true
                }
                // Chunked large-file TXT renders through a UITableView.
                return app.tables.firstMatch.waitForExistence(timeout: 2)
            }
        }

        /// A human-readable description of the expected surface, for
        /// failure messages.
        var describedExpectation: String {
            switch self {
            case .webView: return "a WKWebView (app.webViews)"
            case .textViewOrTable: return "a UITextView or UITableView"
            }
        }
    }

    /// Asserts the reader for `formatName` opened (reader chrome pushed)
    /// and rendered its native engine's surface. This is feature #54's
    /// criterion 5 — `ReaderEngine` routing dispatches each format to its
    /// own native host after the `readingMode`-branch deletion.
    ///
    /// The proof has two parts:
    ///   1. The reader pushed — `readerBackButton` is present (the caller
    ///      has already confirmed this via `openSeededBook`, re-asserted
    ///      here for an attributable failure line).
    ///   2. The format's native rendering surface (by element type, see
    ///      `NativeReaderSurface`) mounted — proving the engine produced
    ///      an actual rendered view, not an empty shell or an error state.
    private func assertNativeReaderRenders(
        in app: XCUIApplication,
        surface: NativeReaderSurface,
        formatName: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertTrue(
            app.buttons[AccessibilityID.readerBackButton].waitForExistence(timeout: 15),
            "[\(formatName)] reader chrome should be present — the book " +
            "should have opened into the reader (feature #54)",
            file: file, line: line
        )
        XCTAssertTrue(
            surface.isPresent(in: app, timeout: 15),
            "[\(formatName)] native reader should render \(surface.describedExpectation) " +
            "— the format's native engine must produce a rendered surface " +
            "after ReaderEngine routing (feature #54 criterion 5)",
            file: file, line: line
        )
    }

    // MARK: - Criterion 1 + 5 — TXT (native text engine)

    /// TXT opens into the native `textNative` reader surface (criterion 5)
    /// and the Display panel carries no Reading Mode picker (criterion 1).
    func test_verify_feature_54_txt_native_engine_no_reading_mode_picker() throws {
        let app = launch(seed: .warAndPeace)
        XCTAssertTrue(
            openSeededBook(in: app),
            "War and Peace (TXT) should open into the reader"
        )
        // TXT renders through the `textNative` engine — a UITextView
        // (full-text / chapter / continuous) or a UITableView (chunked).
        assertNativeReaderRenders(in: app, surface: .textViewOrTable, formatName: "TXT")
        ensureChromeVisible(in: app)
        assertNoReadingModePicker(in: app, formatName: "TXT")
    }

    // MARK: - Criterion 1 + 5 — EPUB (native WKWebView engine)

    /// EPUB opens into the native `epubWKWebView` reader surface
    /// (criterion 5) and the Display panel carries no Reading Mode picker
    /// (criterion 1).
    func test_verify_feature_54_epub_native_engine_no_reading_mode_picker() throws {
        let app = launch(seed: .epubFixture)
        XCTAssertTrue(
            openSeededBook(in: app),
            "The seeded mini-epub3 EPUB should open into the reader"
        )
        // EPUB renders through the `epubWKWebView` engine — a WKWebView
        // (`EPUBReaderContainerView.swift`).
        assertNativeReaderRenders(in: app, surface: .webView, formatName: "EPUB")
        ensureChromeVisible(in: app)
        assertNoReadingModePicker(in: app, formatName: "EPUB")
    }

    // MARK: - Criterion 1 + 2 + 5 — MD (native Markdown engine)

    /// MD opens into the native `markdownNative` reader surface (criterion
    /// 5 + the structural half of criterion 2: replacement rules wire into
    /// the native MD reader with NO mode switch) and the Display panel
    /// carries no Reading Mode picker (criterion 1).
    func test_verify_feature_54_md_native_engine_no_reading_mode_picker() throws {
        let app = launch(seed: .mdTOC)
        XCTAssertTrue(
            openSeededBook(in: app),
            "The seeded MD book should open into the reader"
        )
        // MD renders through the `markdownNative` engine — a UITextView
        // via the shared `TXTTextViewBridge` (`MDReaderContainerView.swift`).
        assertNativeReaderRenders(in: app, surface: .textViewOrTable, formatName: "MD")
        ensureChromeVisible(in: app)
        assertNoReadingModePicker(in: app, formatName: "MD")
    }

    // MARK: - Criterion 1 — explicit cross-format picker-absence sweep

    /// A focused, single-purpose restatement of criterion 1: across the
    /// TXT seed, with the Display panel open and fully scrolled, the
    /// removed picker's section header and both segment labels are absent.
    /// Kept separate from the per-format engine tests so a criterion-1
    /// regression is attributable on its own line in the test report.
    func test_verify_feature_54_no_reading_mode_section_in_display_panel() throws {
        let app = launch(seed: .warAndPeace)
        XCTAssertTrue(
            openSeededBook(in: app),
            "War and Peace (TXT) should open into the reader"
        )
        ensureChromeVisible(in: app)

        let helper = VerificationSettingsHelper(app: app)
        let panel = helper.openReaderSettings()
        XCTAssertTrue(panel.exists, "Display panel should open")

        // The Display panel renders at least one known section header
        // ("Theme") — confirms the panel populated, so the absence
        // assertions below are checking a real, loaded panel rather than
        // an empty sheet.
        XCTAssertTrue(
            panel.staticTexts["Theme"].waitForExistence(timeout: 5),
            "Display panel should render its sections (Theme header visible)"
        )

        sweepPanelForReadingModeArtifacts(
            panel: panel, formatName: "TXT (focused sweep)"
        )
        helper.closeReaderSettings()
    }
}
