// Purpose: CU-free Gate-5 verification suite for Feature #55 —
// "Tap on annotated text to view note content inline".
//
// Feature #55 ships a tap-on-annotated-text note preview: after a user
// attaches a note to a highlighted passage, tapping that annotated
// region in the reader surfaces the note body *inline* — a
// `NotePreviewSheetView` (the design bundle's `NotePreviewSheet`) — WITHOUT
// opening the full Annotations panel. Before #55 the note body was only
// reachable through the panel's Highlights tab.
//
// Why this suite exists — and why it is CU-free:
//   The #55 implementation agent concluded Gate-5 "needs computer-use".
//   That conflated "synthesizing a tap" with "needs CU": XCUITest
//   synthesizes its own gestures. The feature-#26 verification suite
//   (`Feature26TextToSpeechVerificationTests`) proved tap-driven reader
//   features verify cleanly through the XCUITest accessibility API with
//   no computer-use. This suite does the same for #55.
//
// What this suite verifies (feature #55 acceptance criteria):
//   - (a) tapping annotated text shows the note body WITHOUT opening the
//     full panel — after creating a highlight+note via the reader's own
//     selection-popover "Note" flow, a tap on the same annotated region
//     presents the `notePreviewSheet` whose `notePreviewSheetBody`
//     carries the note text, and the Annotations panel sheet
//     (`annotationsPanelSheet`) is NOT present.
//   - (b) dismissible — tapping the preview's "Done" button
//     (`notePreviewSheetDone`) tears the `notePreviewSheet` down.
//   - (c) consistent UX across formats — the same long-press → "Note" →
//     type → tap → `notePreviewSheet` → dismiss flow is exercised
//     per-format for TXT, MD, and EPUB (the three formats with an
//     openable DebugBridge seed fixture; PDF and AZW3/MOBI lack one —
//     `TestSeeder` only provides real-file TXT/MD/EPUB fixtures, and the
//     `.books` PDF records are metadata-only and never open, Bug #209).
//
// Design / pattern notes:
//   - The note-preview surface is `NotePreviewSheetView`. Feature #55 v1
//     presents the bottom-SHEET form for ALL containers — the anchored
//     `NoteCalloutView` is a deferred refinement (`hostViewProvider`
//     defaults to `{ nil }` in `notePreviewPresenterIfAvailable`, and
//     `NotePreviewPresenter.resolvedForm` degrades a callout with no host
//     view to the sheet). So every format here asserts against the
//     `notePreviewSheet` identifiers, not `noteCallout`.
//   - **The selection menu is the feature-#60 `SelectionPopoverView` for
//     ALL THREE formats.** Feature #60 WI-7c replaced the legacy
//     `UIEditMenuInteraction` "Highlight / Add Note / Define / Translate"
//     UIMenu with a SwiftUI `SelectionPopoverView` (a `.sheet`) on the
//     TXT non-chunked, TXT chunked, MD, AND EPUB long-press paths
//     (`TXTTextViewBridgeCoordinator` posts `.readerSelectionPopoverRequested`
//     instead of building a UIMenu). So a long-press on selected text
//     surfaces a popover with a "Note" action row (`selectionPopoverNote`)
//     — identical for native and EPUB. Tapping it routes through
//     `SelectionPopoverActionRouter` → `.readerAnnotationRequested`.
//   - Getting a highlight-WITH-a-note onto screen to tap: the
//     `vreader-debug://` harness has NO highlight/annotation seed action
//     and `TestSeeder` seeds no highlights. So this suite drives the
//     reader's own selection-popover "Note" flow to CREATE the
//     annotation:
//       * TXT / MD — `.readerAnnotationRequested` opens the shared
//         `AddNoteSheet` (`addNoteTextEditor` / `addNoteSave`).
//         `ReaderNotificationHandlers.handleAnnotationSave` persists the
//         annotation AND a `HighlightRecord` with `note: <text>` and
//         paints the highlight at the selected range.
//       * EPUB — `.readerAnnotationRequested` opens the EPUB note input
//         sheet (`epubNoteTextEditor` / `epubNoteSaveButton`) →
//         `handleHighlightWithNote` persists a highlight with the note.
//   - The tap that triggers the preview lands on the SAME coordinate the
//     long-press used — the note-save paints the highlight at that
//     selected range, so a tap there hit-tests the painted highlight and
//     the bridges post `.readerHighlightTapped`
//     (`TXTTextViewBridgeCoordinator.handleContentTap` →
//     `resolveHighlightTap`; EPUB's JS `highlightTapHandler` →
//     `EPUBWebViewBridgeCoordinator.handleHighlightTapMessage`).
//     `NotePreviewModifier` observes that event and presents the sheet.
//   - Drives the app entirely through the XCUITest accessibility API
//     (element queries + synthesized long-press / tap) — no computer-use.
//     The book-open uses the library card tap, NOT the DebugBridge `open`
//     URL (which cannot reliably commit a NavigationStack push in a
//     headless `simctl openurl` session — feature-#54 pilot lesson).
//   - **Query reader content by element TYPE, and popover/sheet leaves
//     by LABEL — not by clobbered identifiers.** Bug #214: a SwiftUI
//     container's `.accessibilityIdentifier` propagates onto AND
//     clobbers its leaf elements' own identifiers. This bites three
//     surfaces here:
//       * Reader content — `txtReaderContent` / `epubReaderContent` are
//         clobbered by their container `Group`; TXT/MD content is queried
//         as a `UITextView` (`app.textViews`), EPUB as a `WKWebView`
//         (`app.webViews`).
//       * `SelectionPopoverView` — its root carries
//         `.accessibilityIdentifier("selectionPopover")`, which clobbers
//         every action button's identifier (a UI-hierarchy dump confirms
//         the "Note" button surfaces as `identifier: 'selectionPopover',
//         label: 'Note'`). The "Note" action is queried by its
//         accessibility LABEL ("Note") scoped to the `selectionPopover`
//         container.
//       * `NotePreviewSheetView` — its root carries
//         `.accessibilityIdentifier("notePreviewSheet")`, clobbering the
//         leaf `notePreviewSheetBody` / `notePreviewSheetDone`
//         identifiers. The `notePreviewSheet` CONTAINER identifier still
//         resolves (it is the outermost element carrying it); the "Done"
//         button is found by LABEL inside it, and the note body is proved
//         by a static-text label scan inside it.
//     All three are `.sheet`-presented SwiftUI views.
//
// @coordinates-with: NotePreviewSheetView.swift, NotePreviewModifier.swift,
//   NotePreviewContainerSupport.swift, NotePreviewViewModel.swift,
//   SelectionPopoverView.swift, SelectionPopoverActionRouter.swift,
//   TXTTextViewBridgeCoordinator.swift, EPUBWebViewBridgeCoordinator.swift,
//   ReaderNotificationHandlers.swift, AddNoteSheet.swift, LaunchHelper.swift,
//   TestConstants.swift

import XCTest

@MainActor
final class Feature55NotePreviewVerificationTests: XCTestCase {

    // MARK: - The note text typed into the note editors

    /// The note body created and then verified. A distinctive multi-word
    /// string so the `notePreviewSheetBody` content assertion is
    /// unambiguous (it cannot accidentally match reader chrome text).
    private static let noteBody = "Verification note fifty five"

    /// The reader content surface a format renders into — used only to
    /// confirm the reader's content view has mounted (via a SCOPED,
    /// fast query). The long-press / tap coordinate is anchored on the
    /// app window, not on the content element, because an unscoped
    /// `app.textViews` / `app.webViews` enumeration on a content-heavy
    /// reader triggers a pathologically slow full-accessibility-tree
    /// walk (observed: a multi-minute stall querying a large UITextView).
    private enum ReaderSurface {
        /// TXT / MD — a `UITextView` whose container identifier
        /// (`txtReaderContainer` / `mdReaderContainer`) is inherited by
        /// the text view (Bug #214 propagation), so a scoped
        /// `textViews.matching(identifier:)` query resolves it fast.
        case nativeText(containerIdentifier: String)
        /// EPUB — a `WKWebView`.
        case webView

        /// A scoped existence query for this surface — fast because it
        /// is keyed to an identifier (native) or a single element type
        /// (`webViews`, of which the reader has exactly one).
        func contentElement(in app: XCUIApplication) -> XCUIElement {
            switch self {
            case .nativeText(let identifier):
                return app.textViews
                    .matching(identifier: identifier).firstMatch
            case .webView:
                return app.webViews.firstMatch
            }
        }
    }

    /// Per-format note-editor wiring. TXT/MD share `AddNoteSheet`; EPUB
    /// uses its own note input sheet — different identifiers, identical
    /// shape (a `TextEditor` + a "Save" button).
    private struct NoteEditor {
        let editorIdentifier: String
        let saveIdentifier: String
    }

    // MARK: - Launch

    /// Launches with the given seed and `--reset-preferences` for a known
    /// UserDefaults + a clean (no stale highlights) database (Bug #152 /
    /// the `TXTHighlightGestureVerificationTests` precedent).
    private func launch(seed: TestSeedState) -> XCUIApplication {
        launchApp(seed: seed, resetPreferences: true)
    }

    // MARK: - Note-preview element queries
    //
    // Bug #214 lesson again: `NotePreviewSheetView`'s root `VStack`
    // carries `.accessibilityIdentifier("notePreviewSheet")`, which
    // SwiftUI propagates onto its descendants — so the leaf identifiers
    // `notePreviewSheetBody` / `notePreviewSheetDone` are clobbered by
    // the container identifier and do NOT resolve as element queries.
    // The `notePreviewSheet` container identifier itself DOES resolve
    // (it is the outermost element carrying it); descendants are reached
    // by scoping a TYPE / LABEL query inside that container.

    /// Any element carrying the `notePreviewSheet` identifier — used only
    /// as an existence/disappearance signal for the preview sheet, never
    /// as a scoping parent (the identifier propagates to multiple
    /// descendants, so `firstMatch` is not guaranteed to be the root).
    private func notePreviewSheet(in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)
            .matching(identifier: "notePreviewSheet").firstMatch
    }

    /// The "Done" dismiss control in the preview sheet — criterion (b).
    /// Queried by exact LABEL ("Done") across ALL element types, app-wide:
    ///   - The per-button `notePreviewSheetDone` identifier is clobbered
    ///     by the container's propagated `notePreviewSheet` identifier,
    ///     and the propagated identifier is not a reliable scoping parent
    ///     (see `selectionPopoverNote`).
    ///   - The element is matched as `.any`, not `.button`: under iOS 26
    ///     a SwiftUI `.buttonStyle(.plain)` `Button` can surface with an
    ///     automation type that an `app.buttons` query misses (the runner
    ///     logs an "Automation type mismatch: computed Button … vs
    ///     PopUpButton" diagnostic). `descendants(matching: .any)` resolves
    ///     it regardless of the heuristic, and `.tap()` works on any type.
    ///   - "Done" is unambiguous while the preview sheet is the frontmost
    ///     surface — no other "Done" control is on screen at that point.
    private func notePreviewDone(in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(
            NSPredicate(format: "label == 'Done'")
        ).firstMatch
    }

    /// The `SelectionPopoverView`'s "Note" action button — the entry
    /// point for attaching a note, shared by TXT / MD / EPUB after the
    /// feature-#60 WI-7c selection-popover migration.
    ///
    /// **Queried by exact LABEL, NOT by the per-button identifier nor by
    /// scoping into the popover container.** Bug #214 lesson:
    /// `SelectionPopoverView`'s root carries
    /// `.accessibilityIdentifier("selectionPopover")`, which SwiftUI
    /// propagates onto — and clobbers — EVERY descendant: the selection
    /// preview `StaticText`, the color buttons, AND each action button
    /// all surface with `identifier: 'selectionPopover'`. So (1) the
    /// per-button `selectionPopoverNote` identifier does NOT resolve, and
    /// (2) `matching(identifier: "selectionPopover").firstMatch` resolves
    /// to whichever element is first in the tree (observed: the preview
    /// `StaticText`), so it cannot be used as a scoping parent. The
    /// button's accessibility LABEL ("Note", set by
    /// `SelectionPopoverActionRow.label`) is NOT clobbered and is unique
    /// among buttons — the reader's bottom-chrome annotations button is
    /// labelled "Notes" (plural), not "Note" — so an exact
    /// `label == 'Note'` button query resolves the popover's Note action
    /// unambiguously.
    private func selectionPopoverNote(in app: XCUIApplication) -> XCUIElement {
        app.buttons.matching(
            NSPredicate(format: "label == 'Note'")
        ).firstMatch
    }

    // MARK: - Book-open helper

    /// Opens the first (and only) seeded book and waits for the reader
    /// chrome. The card tap is retried because a first tap can land before
    /// the library `LazyVGrid` finishes its initial layout pass — the same
    /// legitimate timing race handled in
    /// `Feature54ReadingModeRemovalVerificationTests.openSeededBook`.
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
            if card.waitForExistence(timeout: 20) {
                if card.waitForHittable(timeout: 10) || card.exists { card.tap() }
            } else if row.waitForExistence(timeout: 3) {
                if row.waitForHittable(timeout: 10) || row.exists { row.tap() }
            }
            if backButton.waitForExistence(timeout: 30) { return true }
        }
        return false
    }

    // MARK: - The shared per-format flow

    /// Drives feature #55's tap-on-annotated-text flow end-to-end for one
    /// format and asserts its three acceptance criteria.
    ///
    /// Steps:
    ///   1. Open the book; wait for the reader content surface.
    ///   2. Long-press a word (away from chrome) → the `SelectionPopoverView`.
    ///   3. Tap the popover's "Note" action → the format's note editor;
    ///      type the note; tap Save. The note-save persists a
    ///      `HighlightRecord` with the note AND paints the highlight at
    ///      the selected range.
    ///   4. Tap the SAME coordinate → the painted highlight hit-tests,
    ///      the bridge posts `.readerHighlightTapped`, and
    ///      `NotePreviewModifier` presents `NotePreviewSheetView`.
    ///   5. (a) assert the `notePreviewSheet` + `notePreviewSheetBody`
    ///      carrying the note text, and the `annotationsPanelSheet` is
    ///      ABSENT (the preview did not open the full panel).
    ///   6. (b) tap "Done" → the `notePreviewSheet` is gone.
    private func runNotePreviewFlow(
        seed: TestSeedState,
        surface: ReaderSurface,
        editor: NoteEditor,
        anchorOffset: CGVector,
        formatName: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let app = launch(seed: seed)
        XCTAssertTrue(
            openSeededBook(in: app),
            "[\(formatName)] the seeded book should open into the reader",
            file: file, line: line
        )

        // Confirm the reader's content view actually mounted — a scoped,
        // fast query (NOT an unscoped `app.textViews`/`app.webViews`
        // enumeration, which stalls on a content-heavy reader). The
        // window-anchored gesture below would otherwise risk landing on
        // an empty shell.
        XCTAssertTrue(
            surface.contentElement(in: app).waitForExistence(timeout: 25),
            "[\(formatName)] the reader's content surface should mount " +
            "after opening the book",
            file: file, line: line
        )
        // Let the content settle so the long-press selects real text and
        // the painted-highlight lookup is populated before the verifying
        // tap. EPUB's WKWebView needs JS render time; the native readers
        // need a layout pass. A short, bounded wait — no gesture fires
        // mid-layout.
        _ = XCTWaiter().wait(for: [], timeout: 2.5)

        // The single anchor coordinate — long-press AND the verifying tap
        // both use it, so the tap lands inside the highlight painted at
        // the long-pressed range. Anchored on the app WINDOW (which
        // resolves instantly), not the content element: an unscoped
        // content-element coordinate query can trigger the slow
        // full-accessibility-tree walk. The reader content fills the
        // window, so a normalized window offset lands on the text.
        let anchor = app.windows.firstMatch
            .coordinate(withNormalizedOffset: anchorOffset)

        // --- Create the highlight + note via the selection popover.
        anchor.press(forDuration: 1.2)
        let noteAction = selectionPopoverNote(in: app)
        XCTAssertTrue(
            noteAction.waitForExistence(timeout: 8),
            "[\(formatName)] the long-press SelectionPopover should offer a " +
            "\"Note\" action (selectionPopoverNote) — the entry point for " +
            "attaching a note (feature-#60 WI-7c migrated TXT/MD/EPUB to " +
            "the selection popover)",
            file: file, line: line
        )
        XCTAssertTrue(
            noteAction.waitForHittable(timeout: 4) || noteAction.exists,
            "[\(formatName)] the SelectionPopover \"Note\" action should be " +
            "hittable",
            file: file, line: line
        )
        noteAction.tap()

        typeNoteAndSave(
            editor: editor, in: app,
            formatName: formatName, file: file, line: line
        )

        // The note sheet dismisses; the note-save runs on a Task and
        // persists + paints the highlight. Wait for the editor to be gone
        // before proceeding.
        _ = app.textViews.matching(identifier: editor.editorIdentifier)
            .firstMatch.waitForDisappearance(timeout: 8)
        _ = XCTWaiter().wait(for: [], timeout: 1.5)

        // Settle the reader before the verifying tap. When the native
        // note sheet dismisses, the reader's underlying text selection is
        // often still active, which re-presents the `SelectionPopoverView`
        // on top of the now-painted highlight. A tap on the highlight in
        // that state is consumed as a selection-dismiss gesture and never
        // reaches the bridge's highlight hit-test — so `.readerHighlightTapped`
        // is not posted and the note preview never appears. This clears
        // the lingering popover + selection so the verifying tap is the
        // FIRST gesture the painted highlight receives.
        clearLingeringSelection(in: app, surface: surface)

        // --- Tap the annotated region → the note preview.
        assertTapShowsNotePreview(
            anchor: anchor, in: app, formatName: formatName,
            file: file, line: line
        )
    }

    // MARK: - Sub-flows

    /// Clears the text selection (and any `SelectionPopoverView` it is
    /// driving) that lingers after the note sheet dismisses, so the
    /// verifying tap is the first gesture the painted highlight receives.
    ///
    /// Why this is needed: when the note sheet dismisses, the reader's
    /// underlying text selection — `UITextView`-side for the native
    /// readers, JS-side for EPUB — is often still active. A tap on the
    /// (now-painted) highlight in that state is consumed as a
    /// selection-dismiss / re-select gesture: it never reaches the
    /// bridge's highlight hit-test, so `.readerHighlightTapped` is not
    /// posted and the note preview never appears. (Observed for both the
    /// native readers — the popover re-presents — and EPUB — the iOS edit
    /// menu re-appears on the re-selected word.)
    ///
    /// - Always: if a `SelectionPopoverView` is showing, tap its "Close"
    ///   control (label "Close" — the per-button `selectionPopoverClose`
    ///   identifier is clobbered by the container, same Bug #214
    ///   propagation as the "Note" action).
    /// - Then a neutral content tap that clears the residual selection
    ///   without disturbing the painted highlight:
    ///   * Native readers — a LOW tap (dy ≈ 0.8): the seeded fixtures'
    ///     text occupies the upper half, so this lands on blank reader
    ///     space below the highlighted word; the native readers only
    ///     toggle chrome on a content tap.
    ///   * EPUB — a CENTRE tap (dy ≈ 0.5): the seeded `mini-epub3.epub`
    ///     page carries text only near the top, so the centre is blank
    ///     EPUB content well clear of the highlighted word; a centre tap
    ///     clears the WKWebView's JS text selection without page-turning.
    ///     (A low/edge tap is avoided for EPUB — it risks landing on the
    ///     bottom progress chrome or a page-navigation region.)
    private func clearLingeringSelection(
        in app: XCUIApplication, surface: ReaderSurface
    ) {
        let close = app.buttons.matching(
            NSPredicate(format: "label == 'Close'")
        ).firstMatch
        if close.exists {
            if close.isHittable { close.tap() }
            _ = close.waitForDisappearance(timeout: 5)
        }
        let neutralDY: CGFloat
        switch surface {
        case .nativeText: neutralDY = 0.8
        case .webView:    neutralDY = 0.5
        }
        app.windows.firstMatch
            .coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: neutralDY))
            .tap()
        _ = XCTWaiter().wait(for: [], timeout: 1.2)
    }

    /// Dismisses a `SelectionPopoverView` or an iOS edit menu that a
    /// spurious text-selection (from a verifying tap that was consumed as
    /// a selection gesture) raised, and clears the residual selection —
    /// so the next verifying tap can hit the painted highlight cleanly.
    /// Used by `assertTapShowsNotePreview`'s tap retry.
    private func clearSelectionMenus(in app: XCUIApplication) {
        // The `SelectionPopoverView`'s Close control (label "Close").
        let close = app.buttons.matching(
            NSPredicate(format: "label == 'Close'")
        ).firstMatch
        if close.exists, close.isHittable { close.tap() }
        // A neutral CENTRE tap dismisses the iOS edit menu (Copy / Look
        // Up / …) if it is up and clears the underlying selection. Centre
        // is blank space on the seeded fixtures and never page-turns.
        app.windows.firstMatch
            .coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.55))
            .tap()
        _ = XCTWaiter().wait(for: [], timeout: 1.0)
    }

    /// Types `Self.noteBody` into the note editor and taps Save. Shared by
    /// the native `AddNoteSheet` and the EPUB note input sheet — both are
    /// a `TextEditor` (a `UITextView` to XCUITest) + a "Save" button.
    private func typeNoteAndSave(
        editor: NoteEditor,
        in app: XCUIApplication,
        formatName: String,
        file: StaticString,
        line: UInt
    ) {
        let editorField = app.textViews
            .matching(identifier: editor.editorIdentifier).firstMatch
        XCTAssertTrue(
            editorField.waitForExistence(timeout: 10),
            "[\(formatName)] the note sheet's text editor " +
            "(\(editor.editorIdentifier)) should appear after tapping the " +
            "popover's \"Note\" action",
            file: file, line: line
        )
        XCTAssertTrue(
            editorField.waitForHittable(timeout: 5) || editorField.exists,
            "[\(formatName)] the note text editor should be hittable",
            file: file, line: line
        )
        editorField.tap()
        editorField.typeText(Self.noteBody)

        let save = app.buttons
            .matching(identifier: editor.saveIdentifier).firstMatch
        XCTAssertTrue(
            save.waitForExistence(timeout: 6),
            "[\(formatName)] the note sheet's Save button " +
            "(\(editor.saveIdentifier)) should be present",
            file: file, line: line
        )
        // The Save button is disabled while the note is empty; the typed
        // text enables it. Wait for hittable so the tap is not a no-op.
        XCTAssertTrue(
            save.waitForHittable(timeout: 6),
            "[\(formatName)] the Save button should become hittable after " +
            "typing the note text (it is disabled while the note is empty)",
            file: file, line: line
        )
        save.tap()
    }

    /// Taps `anchor` (the annotated region) and asserts feature #55's
    /// criteria (a) and (b):
    ///   - (a) the `notePreviewSheet` is presented, its
    ///     `notePreviewSheetBody` carries the note text, and the
    ///     `annotationsPanelSheet` is NOT present.
    ///   - (b) tapping "Done" tears the `notePreviewSheet` down.
    private func assertTapShowsNotePreview(
        anchor: XCUICoordinate,
        in app: XCUIApplication,
        formatName: String,
        file: StaticString,
        line: UInt
    ) {
        // Tap the annotated region. `clearLingeringSelection` (run just
        // before this) has dismissed any residual text selection so this
        // tap is the first gesture the painted highlight receives — the
        // bridge's highlight hit-test fires, posts `.readerHighlightTapped`,
        // and `NotePreviewModifier` presents the preview. A single tap is
        // issued, then retried ONCE if the preview did not appear (a tap
        // can still occasionally be consumed by the reader's selection
        // gesture; a second tap after dismissing the spurious selection
        // hits the highlight). The retry is bounded at one extra attempt
        // so a genuine regression still fails fast.
        let sheet = notePreviewSheet(in: app)
        anchor.tap()
        var presented = sheet.waitForExistence(timeout: 12)
        if !presented {
            clearSelectionMenus(in: app)
            anchor.tap()
            presented = sheet.waitForExistence(timeout: 12)
        }
        XCTAssertTrue(
            presented,
            "[\(formatName)] criterion (a): tapping the annotated region " +
            "should present the inline note preview (notePreviewSheet) — " +
            "the bridge posts .readerHighlightTapped and NotePreviewModifier " +
            "presents NotePreviewSheetView",
            file: file, line: line
        )

        // Criterion (a), the note-body half: the preview shows the note
        // text. `NotePreviewSheetView` renders the body as a `Text` in a
        // `ScrollView` tagged `notePreviewSheetBody` — but the container
        // identifier clobbers that leaf identifier, so the note text is
        // asserted by scanning static texts inside the `notePreviewSheet`
        // container for the distinctive note string.
        XCTAssertTrue(
            notePreviewShowsNoteText(in: app),
            "[\(formatName)] criterion (a): the note preview should display " +
            "the note text \"\(Self.noteBody)\" that was attached — the " +
            "tap-to-preview surfaces the actual note content",
            file: file, line: line
        )

        // Criterion (a), the "without opening the full panel" half: the
        // Annotations panel sheet must NOT be present. #55's whole point
        // is an INLINE preview distinct from the panel.
        XCTAssertFalse(
            app.otherElements[AccessibilityID.annotationsPanelSheet].exists,
            "[\(formatName)] criterion (a): the Annotations panel " +
            "(annotationsPanelSheet) must NOT be open — the note preview " +
            "shows the note inline WITHOUT opening the full panel",
            file: file, line: line
        )

        // Criterion (b): the preview is dismissible. The design spec for
        // #55 criterion (b) is "dismissible by tapping away OR swiping" —
        // this asserts the explicit "Done" control first (the strongest
        // proof: a deliberate dismiss affordance), and if the runner's
        // element-type heuristic prevents the tap landing, falls back to
        // the sheet swipe-down (the other documented dismiss path; the
        // `.sheet` has `.presentationDragIndicator(.visible)`). Either
        // path satisfies criterion (b); the assertion is that the preview
        // goes away.
        let done = notePreviewDone(in: app)
        XCTAssertTrue(
            done.waitForExistence(timeout: 6),
            "[\(formatName)] criterion (b): the note preview should offer a " +
            "\"Done\" dismiss control",
            file: file, line: line
        )
        if done.isHittable {
            done.tap()
        }
        let stillUpSheet = notePreviewSheet(in: app)
        if stillUpSheet.exists {
            // The Done tap did not (or could not) dismiss — use the other
            // designed dismiss gesture: swipe the sheet down.
            stillUpSheet.swipeDown()
        }
        XCTAssertTrue(
            notePreviewSheet(in: app).waitForDisappearance(timeout: 10),
            "[\(formatName)] criterion (b): the note preview should be " +
            "dismissible — after tapping \"Done\" (or swiping the sheet " +
            "down) the notePreviewSheet should no longer exist",
            file: file, line: line
        )
    }

    /// True when the note text is visible on screen while the note
    /// preview is the frontmost surface. SwiftUI surfaces a `Text`'s
    /// content as a `staticText` element's label; `NotePreviewSheetView`
    /// renders the note body as a `Text`. The note string
    /// (`Self.noteBody`) is a distinctive multi-word phrase that is shown
    /// nowhere else in the app, so an app-wide `label CONTAINS <note>`
    /// static-text query — checked while the preview sheet is up — proves
    /// the preview is displaying the note body. (An app-wide query is
    /// used rather than scoping to the `notePreviewSheet` element because
    /// that identifier propagates to multiple descendants and `firstMatch`
    /// is not a reliable scoping parent — see `selectionPopoverNote`.)
    private func notePreviewShowsNoteText(in app: XCUIApplication) -> Bool {
        let needle = Self.noteBody
        return app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS %@ OR value CONTAINS %@",
                        needle, needle)
        ).firstMatch.waitForExistence(timeout: 8)
    }

    // MARK: - (a)(b)(c) — TXT (native text reader)

    /// Feature #55 criteria (a) + (b) on the TXT reader, and the TXT third
    /// of criterion (c): long-press → SelectionPopover "Note" → type →
    /// Save creates a highlight+note; a tap on that annotated region
    /// presents the inline `notePreviewSheet` with the note body and no
    /// Annotations panel; "Done" dismisses it.
    func test_verify_feature_55_txt_tap_annotated_text_shows_note_preview() throws {
        runNotePreviewFlow(
            seed: .positionTest,
            surface: .nativeText(containerIdentifier: "txtReaderContainer"),
            editor: NoteEditor(
                editorIdentifier: "addNoteTextEditor",
                saveIdentifier: "addNoteSave"
            ),
            // Upper-third of the reader window — over body text, well
            // clear of the top chrome (~108pt) and bottom chrome.
            anchorOffset: CGVector(dx: 0.5, dy: 0.32),
            formatName: "TXT"
        )
    }

    // MARK: - (a)(b)(c) — MD (native Markdown reader)

    /// Feature #55 criteria (a) + (b) on the Markdown reader, and the MD
    /// third of criterion (c). `MDReaderContainerView` renders through the
    /// shared `TXTTextViewBridge`, so the same long-press → "Note" → tap →
    /// `notePreviewSheet` flow applies — this confirms #55 works on the
    /// Markdown render path, not just plain TXT.
    func test_verify_feature_55_md_tap_annotated_text_shows_note_preview() throws {
        runNotePreviewFlow(
            seed: .mdTOC,
            surface: .nativeText(containerIdentifier: "mdReaderContainer"),
            editor: NoteEditor(
                editorIdentifier: "addNoteTextEditor",
                saveIdentifier: "addNoteSave"
            ),
            anchorOffset: CGVector(dx: 0.5, dy: 0.34),
            formatName: "MD"
        )
    }

    // MARK: - (a)(b)(c) — EPUB (WKWebView reader)

    /// Feature #55 criteria (a) + (b) on the EPUB reader, and the EPUB
    /// third of criterion (c). EPUB's highlight taps arrive from the JS
    /// `highlightTapHandler` channel and its note is persisted via
    /// `handleHighlightWithNote` — a different bridge from the native
    /// readers. This confirms the cross-format `.readerHighlightTapped`
    /// → `NotePreviewModifier` wiring holds for the WKWebView reader.
    ///
    /// Known environmental flake (NOT a feature or test-logic defect):
    /// on the iOS 26 Simulator the runner can log `Class
    /// UIAccessibilityLoaderWebShared is implemented in both
    /// WebCore.axbundle and WebKit.axbundle` and crash in *teardown* —
    /// after this test's assertions have already executed — when the EPUB
    /// WKWebView's accessibility bundle unloads. The remedy is a re-run;
    /// the test itself is deterministic. (Documented identically in
    /// `Feature26TextToSpeechVerificationTests`.)
    func test_verify_feature_55_epub_tap_annotated_text_shows_note_preview() throws {
        runNotePreviewFlow(
            seed: .epubFixture,
            surface: .webView,
            editor: NoteEditor(
                editorIdentifier: "epubNoteTextEditor",
                saveIdentifier: "epubNoteSaveButton"
            ),
            // The EPUB reader is paginated; `mini-epub3.epub` chapter 1
            // flows across pages, and the page shown when the reader
            // opens can carry text only near the TOP (the tail of a
            // paragraph). A long-press lands on / extends to the nearest
            // word, and the highlight is painted at that word's DOM
            // position. Anchoring just below the top chrome (dy ≈ 0.16)
            // — where the first line of whatever page is shown reliably
            // sits — keeps the long-press AND the verifying tap on the
            // same word, so the tap hit-tests the painted highlight.
            anchorOffset: CGVector(dx: 0.5, dy: 0.16),
            formatName: "EPUB"
        )
    }
}
