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
//     switch") — verified in TWO halves:
//       * Structural half: the MD book opens into the native Markdown
//         reader and renders content with no Reading Mode picker.
//       * Transform-application half (round 2 — closes the gap the prior
//         two evidence files could not observe): a content-replacement
//         rule is created through the live Settings → Replacement Rules
//         UI, then the MD book is opened with NO mode switch, and the
//         rendered MD reader text is asserted to show the replacement
//         APPLIED — the original word is gone, the replacement word is
//         present. The MD reader is a `UITextView`, so its rendered text
//         is XCUITest-queryable; this is a real end-to-end assertion of
//         the replacement-rules-in-native-MD criterion, not a unit stub.
//   - Criterion 5 ("all existing reader features unchanged"): each of
//     the three openable formats opens into ITS native reader container
//     and renders content — proving `ReaderEngine` routing dispatches
//     correctly after the `readingMode`-branch deletion.
//
// Out of scope (recorded as the evidence file's documented partials):
//   - Criterion 3 (native EPUB replacement rules) is DEFERRED by the
//     plan to Phase D (blocked on feature #42) — it is not implemented,
//     so no test can exercise it. Criterion 3 IS part of feature #54's
//     acceptance contract, so the evidence file's result stays `partial`
//     and the feature row stays `DONE` (not `VERIFIED`) until Phase D
//     ships criterion 3.
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

    override func setUpWithError() throws {
        // Stop a test at its first failed assertion so a downstream
        // failure (e.g. "book won't open") is not buried under a
        // cascade of follow-on failures from the same root cause.
        continueAfterFailure = false
    }

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

    /// Opens the first seeded book when the library has just had a sheet
    /// dismissed over it.
    ///
    /// A book card can be on screen with a valid frame yet report a
    /// `{-1, -1}` hit point and `isHittable == false` for a short window
    /// after a sheet dismiss — the sheet's presentation/dimming layer is
    /// still being torn down. `XCUIElement.tap()` hard-fails on such an
    /// element. This helper tolerates that by, when the card is not
    /// hittable, tapping the **center of the card's own frame** via an
    /// absolute coordinate (which does not gate on `isHittable`). It still
    /// prefers a normal `.tap()` whenever the card reports hittable.
    ///
    /// - Returns: `true` when the reader's back button became visible.
    @discardableResult
    private func openSeededBookAfterSheetDismiss(in app: XCUIApplication) -> Bool {
        let card = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH 'bookCard_'")
        ).firstMatch
        let row = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH 'bookRow_'")
        ).firstMatch
        let backButton = app.buttons[AccessibilityID.readerBackButton]

        for _ in 0..<4 {
            let target: XCUIElement
            if card.waitForExistence(timeout: 15) {
                target = card
            } else if row.waitForExistence(timeout: 3) {
                target = row
            } else {
                continue
            }
            if target.waitForHittable(timeout: 6) {
                target.tap()
            } else if target.exists {
                // Card is laid out but not yet hittable (residual sheet
                // layer). Tap the centre of its frame by coordinate.
                target.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
                    .tap()
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

    // MARK: - Criterion 2 — replacement rule APPLIED in native MD (no mode switch)

    /// The word present in the seeded `.mdTOC` fixture
    /// (`TestSeeder.generateMDWithHeadings`) that the rule rewrites. The
    /// fixture's H1 heading is "# Introduction"; the body's first sentence
    /// also contains "introduction" — using the exact-case "Introduction"
    /// token keeps the rule a simple literal (non-regex) match and the
    /// fixture is the single source of truth for this string.
    private static let mdReplacementSource = "Introduction"

    /// The word the rule substitutes in. Chosen so it does NOT occur
    /// anywhere in the unmodified `.mdTOC` fixture — its appearance in the
    /// rendered reader text is therefore unambiguous proof the transform
    /// ran (and its absence in a no-rule control would be proof it did not).
    private static let mdReplacementTarget = "Prologue"

    /// Criterion 2 (transform-application half): a content-replacement rule
    /// created through the live Settings → Replacement Rules UI is APPLIED
    /// to the native Markdown reader's rendered text, with NO reading-mode
    /// switch anywhere in the flow (feature #54 removed that control).
    ///
    /// End-to-end path exercised — every step through the real UI / real
    /// subsystem, no stubs:
    ///   1. Seed the `.mdTOC` Markdown book.
    ///   2. Open Settings → Replacement Rules, add a global rule
    ///      ("Introduction" → "Prologue") by typing into the real edit
    ///      sheet's `TextField`s and tapping Save. A global rule
    ///      (`scopeKey == ""`) applies to any MD book — `MDReplacementRuleFetcher`.
    ///   3. Dismiss Settings and open the MD book. `MDReaderContainerView.task`
    ///      fetches the rule from the live `ModelContainer` and forwards it
    ///      to `MDFileLoader`, which runs `ReplacementTransform` over the
    ///      source text before the Markdown parse.
    ///   4. Assert the rendered MD reader text shows the replacement
    ///      APPLIED — "Prologue" present, "Introduction" absent. The MD
    ///      reader renders through a `UITextView` (`TXTTextViewBridge`), so
    ///      its text content is XCUITest-queryable.
    ///
    /// This closes the gap the prior two evidence files
    /// (`feature-54-20260519.md`, `feature-54-20260519-cu-free.md`) left
    /// open: criterion 2's behavioral correctness was only covered at the
    /// integration boundary (20 `MDReaderReplacementRulesTests` /
    /// `MDReplacementRuleFetcherTests`), never observed in the live reader UI.
    func test_verify_feature_54_replacement_rule_applies_in_native_md() throws {
        let app = launch(seed: .mdTOC)

        // --- Step 1: add a global replacement rule via the Settings UI ---
        addGlobalReplacementRule(
            in: app,
            pattern: Self.mdReplacementSource,
            replacement: Self.mdReplacementTarget
        )

        // --- Step 2: open the MD book (no mode switch — feature #54) ---
        // The Settings sheet was just dismissed, so use the post-dismiss
        // open helper that tolerates the residual-sheet-layer hittability
        // race.
        if !openSeededBookAfterSheetDismiss(in: app) {
            XCTFail(
                "The seeded MD book should open into the native Markdown " +
                "reader. Full tree:\n\(app.debugDescription)"
            )
            return
        }
        assertNativeReaderRenders(in: app, surface: .textViewOrTable, formatName: "MD")

        // --- Step 3: assert the rule was APPLIED to the rendered text ---
        let rendered = mdRenderedText(in: app)
        XCTAssertFalse(
            rendered.isEmpty,
            "The native MD reader should expose its rendered text content " +
            "for inspection (UITextView value / static texts)"
        )
        XCTAssertTrue(
            rendered.contains(Self.mdReplacementTarget),
            "Feature #54 criterion 2: the replacement rule " +
            "('\(Self.mdReplacementSource)' → '\(Self.mdReplacementTarget)') " +
            "should be APPLIED in the native MD reader with no mode switch " +
            "— the rendered text must contain '\(Self.mdReplacementTarget)'. " +
            "Rendered text begins: \(rendered.prefix(200))"
        )
        XCTAssertFalse(
            rendered.contains(Self.mdReplacementSource),
            "Feature #54 criterion 2: after the replacement rule runs, the " +
            "original word '\(Self.mdReplacementSource)' must no longer " +
            "appear in the native MD reader's rendered text — the transform " +
            "rewrites it to '\(Self.mdReplacementTarget)'. " +
            "Rendered text begins: \(rendered.prefix(200))"
        )
    }

    // MARK: - Replacement-rule UI helpers

    /// Adds one global (book-scope-empty) content replacement rule through
    /// the live Settings → Replacement Rules UI.
    ///
    /// The flow: library settings toolbar → Settings sheet → "Replacement
    /// Rules" row → the `ReplacementRulesView` Add (`+`) button → the
    /// `ReplacementRuleEditSheet` `Form`. The edit sheet's `TextField`s
    /// carry no accessibility identifier, so they are located by their
    /// SwiftUI placeholder strings ("Search pattern" / "Replace with"),
    /// which XCUITest exposes as the `textFields` element's identifier.
    /// `Save` is enabled once the pattern field is non-empty.
    private func addGlobalReplacementRule(
        in app: XCUIApplication,
        pattern: String,
        replacement: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        // Open Settings from the library toolbar.
        let settingsButton = app.buttons[AccessibilityID.settingsToolbarButton]
        XCTAssertTrue(
            settingsButton.waitForHittable(timeout: 10),
            "Settings toolbar button should be reachable from the library",
            file: file, line: line
        )
        settingsButton.tap()

        // Navigate to the Replacement Rules screen.
        let rulesRow = app.descendants(matching: .any)
            .matching(identifier: AccessibilityID.settingsReplacementRules)
            .firstMatch
        XCTAssertTrue(
            rulesRow.waitForExistence(timeout: 8),
            "Settings should expose the Replacement Rules row",
            file: file, line: line
        )
        rulesRow.tap()

        let addButton = app.buttons[AccessibilityID.replacementRulesAddButton]
        XCTAssertTrue(
            addButton.waitForExistence(timeout: 8),
            "ReplacementRulesView should present its Add (+) button",
            file: file, line: line
        )

        // Delete any rules left by a prior run. The `.mdTOC` seed forces a
        // disk-backed SwiftData store (`VReaderApp` whitelists it for
        // terminate-relaunch persistence) and `--reset-preferences` only
        // clears UserDefaults — so `ContentReplacementRule` rows survive
        // across test runs. Clearing them first keeps this test
        // deterministic and idempotent rather than accumulating cruft.
        clearExistingReplacementRules(in: app)

        // Open the Add-rule sheet.
        addButton.tap()

        // Fill in the rule. The two TextFields are keyed by placeholder.
        let patternField = app.textFields["Search pattern"]
        XCTAssertTrue(
            patternField.waitForExistence(timeout: 8),
            "The Add-rule sheet should present the 'Search pattern' field",
            file: file, line: line
        )
        patternField.tap()
        patternField.typeText(pattern)

        let replacementField = app.textFields["Replace with"]
        XCTAssertTrue(
            replacementField.waitForExistence(timeout: 5),
            "The Add-rule sheet should present the 'Replace with' field",
            file: file, line: line
        )
        replacementField.tap()
        replacementField.typeText(replacement)

        // Save — the confirmation-action button is labelled "Save". It
        // lives in the navigation bar's `confirmationAction` slot; the
        // software keyboard raised by the two `typeText` calls overlaps
        // the lower form but NOT the top navigation bar, so `Save` stays
        // hittable. Tapping it commits the rule and dismisses the
        // `ReplacementRuleEditSheet`, which also resigns the keyboard.
        let saveButton = app.buttons["Save"]
        XCTAssertTrue(
            saveButton.waitForExistence(timeout: 5),
            "The Add-rule sheet should present a Save button",
            file: file, line: line
        )
        // The Save button is disabled while the pattern field is empty;
        // it should now be enabled because the pattern was typed.
        XCTAssertTrue(
            saveButton.isEnabled,
            "Save should be enabled once a non-empty pattern is entered",
            file: file, line: line
        )
        saveButton.tap()

        // Wait for the `ReplacementRuleEditSheet` to fully dismiss before
        // doing anything else. The rule row below becomes visible in the
        // underlying list *through* the still-animating edit sheet, so
        // asserting the row alone is not proof the edit sheet's layer is
        // gone — and that layer, while present, intercepts hit-testing on
        // everything beneath it (the cause of a non-hittable `Done` and a
        // non-hittable library card). The `Search pattern` field is unique
        // to the edit sheet; its disappearance marks the sheet fully gone.
        XCTAssertTrue(
            patternField.waitForDisappearance(timeout: 8),
            "The Add-rule edit sheet should dismiss after Save",
            file: file, line: line
        )

        // The new rule's row should appear in the list — confirms the
        // insert committed to the live ModelContainer before we leave.
        let ruleRow = app.staticTexts
            .matching(NSPredicate(format: "label CONTAINS %@", pattern))
            .firstMatch
        XCTAssertTrue(
            ruleRow.waitForExistence(timeout: 8),
            "The saved replacement rule should appear in the rules list",
            file: file, line: line
        )

        // Dismiss the Settings sheet so the library is interactive again.
        dismissSettingsSheet(in: app, file: file, line: line)
    }

    /// Deletes every existing `ContentReplacementRule` row through the
    /// ReplacementRulesView's `EditButton` + swipe-to-delete affordance.
    ///
    /// Called before adding the test's own rule. The `.mdTOC` seed uses a
    /// disk-backed SwiftData store, so rules persist across runs; clearing
    /// them keeps the test's UI geometry and rule set deterministic.
    /// Tolerant by design — if there are no rules, it is a no-op.
    private func clearExistingReplacementRules(in app: XCUIApplication) {
        // Each rule renders a `ReplacementRuleRow` whose pattern/replacement
        // caption ("\"X\" → \"Y\"") is a static text. Delete rows until
        // none remain (bounded so a stuck delete cannot loop forever).
        for _ in 0..<20 {
            let ruleCaption = app.staticTexts
                .matching(NSPredicate(format: "label CONTAINS '→'"))
                .firstMatch
            guard ruleCaption.waitForExistence(timeout: 2) else { return }

            // Swipe the row to reveal its Delete action, then tap it.
            ruleCaption.swipeLeft()
            let deleteButton = app.buttons["Delete"]
            if deleteButton.waitForExistence(timeout: 3) {
                deleteButton.tap()
            } else {
                // Row did not open a swipe action — stop rather than spin.
                return
            }
            _ = ruleCaption.waitForDisappearance(timeout: 3)
        }
    }

    /// Dismisses the Settings sheet, returning the app to the library.
    ///
    /// Settings is a `.sheet`. After the rule-add flow the
    /// `ReplacementRulesView` is pushed onto the sheet's inner
    /// `NavigationStack`. This performs an **interactive swipe-down
    /// dismiss** by press-dragging from a point clearly *inside* the
    /// sheet's top strip (below the status bar / Dynamic Island, in the
    /// sheet's grabber + title-bar region) down to near the bottom of the
    /// screen. Starting the drag above the sheet — in the status-bar band
    /// — does not register on the sheet's presentation controller, which
    /// is why an earlier higher start point failed to dismiss.
    ///
    /// Dismissal is confirmed by the `settingsDoneButton` element (unique
    /// to the SettingsView root) AND the `replacementRulesAddButton`
    /// (unique to the pushed Replacement Rules screen) both leaving the
    /// tree — NOT by the library `settingsToolbarButton` existing, because
    /// that button sits in the accessibility tree *behind* the sheet the
    /// whole time. The gesture is retried in case a swipe is consumed.
    private func dismissSettingsSheet(
        in app: XCUIApplication,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let doneButton = app.buttons[AccessibilityID.settingsDoneButton]
        let rulesAddButton = app.buttons[AccessibilityID.replacementRulesAddButton]

        func sheetStillPresented() -> Bool {
            doneButton.exists || rulesAddButton.exists
        }

        for attempt in 0..<5 {
            guard sheetStillPresented() else { return }

            if attempt < 3 {
                // Interactive swipe-down dismiss. Start ~y=0.12 — inside
                // the sheet's top grabber/title strip (the sheet begins at
                // ~y=62/874 ≈ 0.07; the nav bar is lower at ~y=0.16) — and
                // drag to near the bottom.
                let top = app.coordinate(
                    withNormalizedOffset: CGVector(dx: 0.5, dy: 0.12)
                )
                let bottom = app.coordinate(
                    withNormalizedOffset: CGVector(dx: 0.5, dy: 0.92)
                )
                top.press(forDuration: 0.25, thenDragTo: bottom)
            } else {
                // Fallback: pop any pushed screen, then tap the root
                // `Done` button.
                if rulesAddButton.exists {
                    let back = app.navigationBars.buttons["Back"]
                    if back.exists && back.isHittable { back.tap() }
                }
                if doneButton.waitForHittable(timeout: 4) {
                    doneButton.tap()
                }
            }

            let cleared = XCTWaiter().wait(
                for: [
                    XCTNSPredicateExpectation(
                        predicate: NSPredicate(format: "exists == false"),
                        object: doneButton
                    ),
                    XCTNSPredicateExpectation(
                        predicate: NSPredicate(format: "exists == false"),
                        object: rulesAddButton
                    ),
                ],
                timeout: 5
            )
            if cleared == .completed { return }
        }

        XCTAssertFalse(
            sheetStillPresented(),
            "The Settings sheet should dismiss back to the library after " +
            "adding the replacement rule",
            file: file, line: line
        )
    }

    /// Returns the native Markdown reader's rendered text content.
    ///
    /// The MD reader renders through `TXTTextViewBridge`'s `UITextView`
    /// inside the `mdReaderContainer` subtree. XCUITest surfaces a
    /// `UITextView`'s text as the element's `value`; SwiftUI also exposes
    /// long text content as `staticTexts` descendants. To be robust across
    /// both representations this concatenates the reader's text-view
    /// `value`(s) and any `staticTexts` labels found inside the reader.
    private func mdRenderedText(in app: XCUIApplication) -> String {
        var pieces: [String] = []

        // The UITextView the MD reader renders into.
        let textViews = app.textViews.allElementsBoundByIndex
        for textView in textViews where textView.exists {
            if let value = textView.value as? String, !value.isEmpty {
                pieces.append(value)
            }
            if !textView.label.isEmpty {
                pieces.append(textView.label)
            }
        }

        // SwiftUI can also expose the rendered body as static texts; include
        // any whose label mentions either the source or the target word so
        // the assertion sees the transform outcome regardless of which
        // representation the platform chose.
        for token in [Self.mdReplacementSource, Self.mdReplacementTarget] {
            let matches = app.staticTexts
                .matching(NSPredicate(format: "label CONTAINS %@", token))
                .allElementsBoundByIndex
            for element in matches where element.exists {
                pieces.append(element.label)
            }
        }

        return pieces.joined(separator: "\n")
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
