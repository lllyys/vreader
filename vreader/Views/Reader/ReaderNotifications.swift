// Purpose: Shared notification names and types for reader bridge↔container coordination.
// Extracted from ReaderContainerView.swift (WI-002) — zero logic change.
//
// @coordinates-with ReaderContainerView.swift, TXTTextViewBridge.swift,
//   TXTChunkedReaderBridge.swift, TXTReaderContainerView.swift, MDReaderContainerView.swift,
//   EPUBReaderContainerView.swift, PDFReaderContainerView.swift,
//   AnnotationAnchor.swift

import Foundation
import CoreGraphics

extension Notification.Name {
    /// Posted by reader bridges when the user taps the content area.
    /// Used by ReaderContainerView to toggle toolbar visibility.
    static let readerContentTapped = Notification.Name("vreader.readerContentTapped")
    /// Posted by ReaderContainerView when the user taps the bookmark button.
    /// Format-specific container views observe this and save a bookmark at the current position.
    static let readerBookmarkRequested = Notification.Name("vreader.readerBookmarkRequested")
    /// Posted by ReaderContainerView when the user taps a search result.
    /// The notification's `object` is the `Locator` to navigate to.
    /// Format-specific container views observe this and scroll/navigate accordingly.
    static let readerNavigateToLocator = Notification.Name("vreader.readerNavigateToLocator")
    /// Posted by text view bridges when the user selects "Highlight" from the edit menu.
    /// The notification's `object` is a `TextSelectionInfo` with selected text and range.
    static let readerHighlightRequested = Notification.Name("vreader.readerHighlightRequested")
    /// Posted by text view bridges when the user selects "Add Note" from the edit menu.
    /// The notification's `object` is a `TextSelectionInfo` with selected text and range.
    static let readerAnnotationRequested = Notification.Name("vreader.readerAnnotationRequested")
    /// Posted by reader ViewModels at the end of close(), after recomputeStats completes.
    /// LibraryView observes this to refresh with guaranteed up-to-date stats (bug #45).
    static let readerDidClose = Notification.Name("vreader.readerDidClose")
    /// Posted by SearchViewModel when the search query changes (including clear).
    /// Reader bridges observe this to dismiss any temporary search highlight.
    static let searchHighlightClear = Notification.Name("vreader.searchHighlightClear")
    /// Posted by format-specific readers when the user selects text for annotation.
    /// The notification's `object` is a `ReaderSelectionEvent` carrying the anchor and rect.
    static let readerTextSelected = Notification.Name("vreader.readerTextSelected")
    /// Posted by format-specific containers when the reading position changes.
    /// The notification's `object` is the current `Locator`.
    /// ReaderContainerView observes this to pass the live locator to the AI panel.
    static let readerPositionDidChange = Notification.Name("vreader.readerPositionDidChange")
    /// Posted by TapZoneOverlay when the user taps the "previous page" zone.
    static let readerPreviousPage = Notification.Name("vreader.readerPreviousPage")
    /// Posted by TapZoneOverlay when the user taps the "next page" zone.
    static let readerNextPage = Notification.Name("vreader.readerNextPage")
    /// Posted by text view bridges when the user selects "Define" from the edit menu.
    /// The notification's `object` is a `TextSelectionInfo` with selected text and range.
    static let readerDefineRequested = Notification.Name("vreader.readerDefineRequested")
    /// Posted by text view bridges when the user selects "Translate" from the edit menu.
    /// The notification's `object` is a `TextSelectionInfo` with selected text and range.
    static let readerTranslateRequested = Notification.Name("vreader.readerTranslateRequested")
    /// Posted by HighlightListViewModel when a highlight is deleted from the annotations panel.
    /// The notification's `object` is the highlight UUID string. (bug #78)
    /// Reader containers observe this to remove the visual highlight immediately.
    static let readerHighlightRemoved = Notification.Name("vreader.readerHighlightRemoved")
    /// Posted by reader bridges (TXT/MD/EPUB/Foliate/PDF) when the user
    /// taps an existing highlight in the content area.
    /// The notification's `object` is a `ReaderHighlightTapEvent` carrying
    /// the highlight's UUID and a `sourceRect`. Feature #64's
    /// `HighlightPopoverModifier` observes this to open the unified
    /// highlight-action popover anchored at `sourceRect` — see the doc on
    /// `ReaderHighlightTapEvent.sourceRect` for the cross-bridge
    /// coordinate-space contract. (Originally feature #53 / GH #596; the
    /// feature-#53 long-press `UIMenu` was replaced by the unified popover and
    /// torn down in feature #64 WI-10 — this notification is the surviving,
    /// now tap-triggered, entry point.)
    static let readerHighlightTapped = Notification.Name("vreader.readerHighlightTapped")
    /// Feature #1121: a programmatic "navigate then auto-open the editor" request
    /// from the HighlightsSheet Edit handoff. Object is a `ReaderHighlightEditRequest`.
    /// The per-format bridge resolves the highlight after re-render and re-posts a
    /// `readerHighlightTapped` with `openInEditMode: true`.
    static let readerHighlightEditRequested = Notification.Name("vreader.readerHighlightEditRequested")
    /// Posted after annotation import completes (bug #88).
    /// Reader containers observe this to re-render persisted highlights.
    static let readerHighlightsDidImport = Notification.Name("vreader.readerHighlightsDidImport")
    /// Feature #60 WI-6b: posted by the shared `ReaderBottomChrome`
    /// toolbar when the user taps one of its four buttons.
    /// `ReaderContainerView` observes these and presents the matching
    /// sheet/panel. Posting (rather than threading handler closures
    /// through the per-format host views) keeps `ReaderBottomChrome`
    /// composable inside any container with no extra plumbing.
    static let readerOpenContents = Notification.Name("vreader.readerOpenContents")
    static let readerOpenNotes = Notification.Name("vreader.readerOpenNotes")
    static let readerOpenDisplay = Notification.Name("vreader.readerOpenDisplay")
    static let readerOpenAI = Notification.Name("vreader.readerOpenAI")
    /// Feature #60 WI-6c / Feature #56 WI-8: posted by the reader
    /// More-menu popover (`ReaderMorePopover`) when the user taps a row.
    /// `ReaderContainerView` observes these and runs the matching
    /// action. Posting (rather than threading closures through the
    /// shared `ReaderTopChrome` and per-format hosts) keeps the
    /// popover composable in one place. Each maps 1:1 from a
    /// `ReaderMoreMenuRow` case via `ReaderMoreMenuRow.notification`
    /// — the declared row set may grow over time (WI-8 added two
    /// rows; WI-15 may rename one); the inverse `init?(notification:)`
    /// is the single source of truth for the round-trip.
    ///
    /// `.readerMoreToggleAutoTurn` flips `ReaderSettingsStore.autoPageTurn`
    /// (the only row with real backing state — the design draws it as
    /// a toggle). `.readerMoreBookDetails` opens the reader Book Details
    /// sheet (`BookDetailsSheet`, feature #61).
    ///
    /// Feature #56 WI-8 — the bilingual row returns (formerly deferred
    /// under GH #790): `.readerMoreBilingual` is posted from the
    /// bilingual row; host containers route it to the
    /// `BilingualReadingViewModel.setEnabled(...)` toggle, except in
    /// the `.unavailable` state where the host routes to AI Settings.
    /// `.readerMoreReTranslateChapter` is posted from the conditional
    /// re-translate row (design §#864); the host presents
    /// `ReTranslatePickerSheet`. The re-translate row is only visible
    /// when bilingual mode is on for the book.
    static let readerMoreReadAloud = Notification.Name("vreader.readerMoreReadAloud")
    static let readerMoreToggleAutoTurn = Notification.Name("vreader.readerMoreToggleAutoTurn")
    static let readerMoreBilingual = Notification.Name("vreader.readerMoreBilingual")
    static let readerMoreReTranslateChapter = Notification.Name("vreader.readerMoreReTranslateChapter")
    /// Feature #56 WI-14 (declared in WI-8 per plan): posted by
    /// `BookTranslationCoordinator` whenever a global-book-translation
    /// run advances. A reader open on a book being translated observes
    /// this to drive its `ReaderTranslateBanner` (progress / cancel).
    /// `userInfo` carries `["fingerprintKey": String, "completed": Int,
    /// "total": Int, "phase": String]`. Defined here so the contract is
    /// stable when WI-14 lands the producer and reader-side consumer.
    static let readerBookTranslationProgressDidChange = Notification.Name(
        "vreader.reader.bookTranslationProgressDidChange"
    )
    /// Feature #56 WI-14: posted by the active per-format reader container
    /// (TXT/MD/EPUB/PDF/Foliate) once its `ChapterTextProviding` adapter
    /// is constructed. The host `ReaderContainerView` caches the provider
    /// so the Book Details sheet can hand it to `BookTranslationViewModel`
    /// without depending on per-format internals. `userInfo` carries
    /// `["fingerprintKey": String]`; the provider itself is the
    /// notification `object` (an `any ChapterTextProviding` reference).
    /// Filtered by fingerprint so concurrent readers do not cross-wire.
    static let readerBookTranslationTextProviderAvailable = Notification.Name(
        "vreader.reader.bookTranslationTextProviderAvailable"
    )
    static let readerMoreBookDetails = Notification.Name("vreader.readerMoreBookDetails")
    static let readerMoreShareBook = Notification.Name("vreader.readerMoreShareBook")
    static let readerMoreExportAnnotations = Notification.Name("vreader.readerMoreExportAnnotations")
    /// Feature #56 WI-7b: posted by `BilingualReadingViewModel` whenever the
    /// bilingual state a renderer must react to changes — bilingual toggled
    /// on/off, or a unit's translation became available (prefetch landed) or
    /// was recorded unavailable (offline cache-miss). The `userInfo` carries
    /// `["fingerprintKey": String]` so a renderer filters to its own book.
    /// Each format renderer (WI-10..13) observes this to re-inject / clear
    /// the interlinear translation for the affected unit.
    static let readerBilingualDidChange = Notification.Name("vreader.reader.bilingualDidChange")
    /// Feature #71 WI-7: posted when a chapter section is stitched into the
    /// EPUB continuous-scroll DOM (`sectionMaterialized` lifecycle hook).
    /// Appended/prepended sections never fire `didFinish`, so this is the
    /// per-section signal the EPUB bilingual surfaces modifier observes to
    /// drive a SECTION-SCOPED enumerate (`enumerateJS(spineIndex:)`) — keeping
    /// each stitched chapter's bids namespaced (`s{N}b…`) so translations
    /// inject per section with no cross-section bid bleed. The `userInfo`
    /// carries `["fingerprintKey": String, "spineIndex": Int]` so a renderer
    /// filters to its own book and section. Posted with no View capture from
    /// the long-lived `EPUBContinuousScrollConfig.onSectionMaterialized`
    /// closure.
    static let readerBilingualSectionMaterialized = Notification.Name(
        "vreader.reader.bilingualSectionMaterialized")
    /// Feature #71 WI-7 (Gate-4 round-2 MEDIUM 2): posted when a chapter section
    /// is EVICTED from the EPUB continuous-scroll DOM (the coordinator's
    /// far-from-anchor trim emits `removeChapterSectionJS`). The bilingual
    /// surfaces modifier observes this to drop the evicted section's bucket from
    /// `EPUBBilingualOrchestrator.blocksBySection` (`clearBlocks(forSection:)`),
    /// so stale per-section caches do not accumulate and worsen any flatten
    /// path. Mirror of `.readerBilingualSectionMaterialized` — `userInfo`
    /// carries `["fingerprintKey": String, "spineIndex": Int]` and it is posted
    /// with no View capture from the long-lived
    /// `EPUBContinuousScrollCoordinator` eviction path via the config's
    /// `onSectionEvicted` seam.
    static let readerBilingualSectionEvicted = Notification.Name(
        "vreader.reader.bilingualSectionEvicted")
    /// Feature #56 WI-13: posted by the PDF below-page bilingual panel's
    /// offline-state Retry button. The PDF host observes and calls
    /// `BilingualReadingViewModel.retryUnit(currentUnit)` to refetch
    /// only the offline page's translation (NOT the whole-book
    /// `resetTriggerState()` — Gate-2 v5 round-1 H2). No payload.
    static let readerBilingualRetry = Notification.Name("vreader.reader.bilingualRetry")
    /// Feature #56 WI-13: posted by the PDF below-page bilingual panel's
    /// offline-state "Open AI tab" button (also reusable by future
    /// affordances). `ReaderContainerView` observes, gates on
    /// `resolvedAICoordinator.isAIAvailable` (matches the
    /// `.readerTranslateRequested` defense-in-depth precedent), and
    /// sets `aiInitialTab = .translate` + `showAIPanel = true`. No
    /// payload — opens the AI Translate tab without a selection.
    static let readerOpenAITranslate = Notification.Name("vreader.reader.openAITranslate")
    /// Feature #56 WI-15: posted by `ChapterReTranslateViewModel` when a
    /// re-translation succeeds. The active per-format reader container
    /// observes (matched by `["fingerprintKey": String]`), updates its
    /// `BilingualReadingViewModel.translationsByUnit[unit] = segments`,
    /// and re-renders the affected unit. Payload:
    /// `["fingerprintKey": String, "unit": TranslationUnitID, "segments": [String]]`.
    static let readerBilingualReTranslateApplied = Notification.Name("vreader.reader.bilingualReTranslateApplied")
    /// Posted when a footnote link is detected in EPUB content (foliate-js).
    /// Object is [String: String] with "href" and "text" keys.
    static let epubFootnoteDetected = Notification.Name("vreader.epubFootnoteDetected")
    /// Feature #53 WI-5: posted by `FoliateSpikeView`'s coordinator when the
    /// Foliate-js bridge emits `annotation-show` (user tapped an existing
    /// highlight). The `userInfo` carries `["cfi": String, "fingerprintKey":
    /// String]`. The outer `FoliateSpikeView.body` observes it (where
    /// `modelContext` is in scope), resolves CFI → UUID via
    /// `FoliateHighlightTapResolver`, and posts the cross-format
    /// `.readerHighlightTapped` event. Filtered by `fingerprintKey` so
    /// concurrent Foliate readers don't cross-fire.
    static let foliateAnnotationTapRequested = Notification.Name("vreader.foliateAnnotationTapRequested")
    /// Bug #199 / GH #733: posted by `FoliateSpikeView.body`'s Delete-
    /// action handler after persisting a deletion. The Coordinator observes
    /// it (its `webView` is in scope), filters by `fingerprintKey`, and
    /// runs `readerAPI.deleteAnnotation({ value: cfi })` so the rendered
    /// annotation disappears from the Foliate-js overlay immediately
    /// instead of lingering until the next book reopen. `userInfo` carries
    /// `["cfi": String, "fingerprintKey": String]`.
    static let foliateRequestAnnotationJSDelete = Notification.Name("vreader.foliateRequestAnnotationJSDelete")
    /// Bug #201 / GH #739: posted by `FoliateSpikeView.Coordinator`'s
    /// `case "selection":` handler after parsing the JS `selection`
    /// message via `FoliateMessageParser.parseSelection`. The outer
    /// `FoliateSpikeView.body` observes it (where `modelContext` is in
    /// scope), filters by `fingerprintKey`, and presents an action
    /// sheet ("Highlight" / "Cancel"). On Highlight: persist the
    /// highlight via `PersistenceActor.addHighlight` and evaluate
    /// `FoliateHighlightRenderer.addAnnotationJS(...)` on the live
    /// WKWebView so the rendered annotation appears immediately.
    /// `userInfo` carries `["cfi": String, "text": String,
    /// "fingerprintKey": String, "sectionIndex": Int]`.
    static let foliateSelectionDetected = Notification.Name("vreader.foliateSelectionDetected")
    /// Bug #201 / GH #739: sibling of `.foliateRequestAnnotationJSDelete`
    /// for the create path. Posted by `FoliateSpikeView+Selection`'s
    /// `handleHighlight` after persistence add fires; the Coordinator
    /// observes it (its `webView` is in scope), filters by
    /// `fingerprintKey`, and runs
    /// `FoliateHighlightRenderer.addAnnotationJS(cfi:color:)` so the
    /// rendered annotation appears on the Foliate-js overlay without
    /// waiting for the next book reopen. `userInfo` carries
    /// `["cfi": String, "color": String, "fingerprintKey": String]`.
    static let foliateRequestAnnotationJSCreate = Notification.Name("vreader.foliateRequestAnnotationJSCreate")

    /// Bug #207 / GH #765: posted by `FoliateSpikeView.Coordinator`
    /// when the Foliate-js bundle finishes attaching a section's
    /// SVG overlay (`create-overlay` JS event from foliate-host.js).
    /// The overlay is now ready to accept `readerAPI.addAnnotation`
    /// calls for that section's CFIs. `FoliateSpikeView+Restore`
    /// observes this, filters by `fingerprintKey`, queries persistence
    /// for saved highlights, and fans them out as per-CFI
    /// `.foliateRequestAnnotationJSCreate` events the Coordinator's
    /// existing observer evaluates. `userInfo` carries
    /// `["sectionIndex": Int, "fingerprintKey": String]`. Without
    /// this round-trip, saved AZW3/MOBI highlights persist in
    /// SwiftData but never re-paint on book reopen — the data
    /// layer is correct, only the visual restore fails.
    static let foliateOverlayReadyForSection = Notification.Name("vreader.foliateOverlayReadyForSection")

    /// Feature #56 WI-11: posted by `FoliateSpikeView.Coordinator`
    /// after parsing a `bilingualEnumerate` script-message payload.
    /// Carries `userInfo = ["blocks": [BilingualBlock], "fingerprintKey": String]`.
    /// The observer in `FoliateBilingualContainerView` resolves the
    /// current unit via the bilingual VM and dispatches both the
    /// translation prefetch and (if a cached translation exists)
    /// the inject JS through the `foliateRequestBilingualEvalJS`
    /// observer. Filtered by `fingerprintKey` so concurrent
    /// AZW3/MOBI readers do not cross-fire.
    static let foliateBilingualBlocksEnumerated = Notification.Name("vreader.foliateBilingualBlocksEnumerated")

    /// Feature #56 WI-11: posted by the bilingual container to ask
    /// the live `FoliateSpikeView.Coordinator` to evaluate a JS
    /// payload (enumerate / inject / clear). Carries
    /// `userInfo = ["js": String, "fingerprintKey": String]`. The
    /// Coordinator's observer evaluates the JS against its live
    /// `WKWebView`. Mirrors the
    /// `.foliateRequestAnnotationJSCreate` /
    /// `.foliateRequestAnnotationJSDelete` pattern so the seam
    /// stays consistent across the highlight + bilingual surfaces.
    /// Filtered by `fingerprintKey` so concurrent AZW3/MOBI
    /// readers do not cross-fire.
    static let foliateRequestBilingualEvalJS = Notification.Name("vreader.foliateRequestBilingualEvalJS")

    /// Feature #56 WI-11: posted by `FoliateSpikeView.Coordinator`
    /// when Foliate-js fires a `section-load` event (a new section
    /// has been rendered into the DOM). Carries
    /// `userInfo = ["sectionIndex": Int, "fingerprintKey": String]`.
    /// The bilingual container observes this to refresh its
    /// enumerate payload against the freshly-loaded section.
    /// Filtered by `fingerprintKey` so concurrent AZW3/MOBI
    /// readers do not cross-fire.
    static let foliateSectionLoaded = Notification.Name("vreader.foliateSectionLoaded")

    /// Feature #56 WI-11 (Gate-4 audit H1): posted by
    /// `FoliateSpikeView.Coordinator` on every `relocate` event so
    /// the bilingual container can update its current-section
    /// tracking even when the position change does not load a new
    /// section (page turn within an already-loaded section in
    /// paginated mode). Carries
    /// `userInfo = ["sectionIndex": Int, "sectionTotal": Int,
    ///              "fraction": Double, "tocHref": String?,
    ///              "tocLabel": String?, "fingerprintKey": String]`.
    /// Filtered by `fingerprintKey`. Bug #260 added `fraction` /
    /// `sectionTotal` / `tocLabel` so the AZW3/MOBI bottom-chrome
    /// scrubber + position label have a live progress source.
    static let foliateRelocated = Notification.Name("vreader.foliateRelocated")

    /// Bug #260 / GH #1130: posted by the AZW3/MOBI bottom-chrome
    /// scrubber (in `FoliateBilingualContainerView`) when the user
    /// drags to seek. Carries
    /// `userInfo = ["fraction": Double, "fingerprintKey": String]`.
    /// `FoliateSpikeView.Coordinator` observes it and evaluates
    /// `readerAPI.goToFraction(<clamped>)` against its live
    /// `WKWebView`. A dedicated channel (not the bilingual eval
    /// channel) so the seek path is self-documenting — mirrors the
    /// Bug #239 `.readerNextPage` / `.readerPreviousPage` precedent.
    /// Filtered by `fingerprintKey` so concurrent AZW3/MOBI readers
    /// do not cross-fire.
    static let foliateRequestSeekFraction = Notification.Name("vreader.foliateRequestSeekFraction")

    /// Bug #262 / GH #1136: posted by `FoliateSpikeView.Coordinator`
    /// on `book-ready` when the parsed Foliate-js `toc` is non-empty.
    /// Carries `userInfo = ["toc": [FoliateTOCItem], "fingerprintKey": String]`.
    /// `FoliateBilingualContainerView` observes it, converts the tree via
    /// `FoliateTOCConverter`, and feeds `ReaderContainerView.tocEntries`
    /// (the live AZW3/MOBI Contents source — the file-based
    /// `ReaderTOCFactory.buildTOC` has no Foliate parser, so the TOC only
    /// exists in the live WebView's book-ready payload). Filtered by
    /// `fingerprintKey` so concurrent readers do not cross-fire. Not posted
    /// for an empty TOC, so `TOCSheet`'s genuine "no contents" state is
    /// preserved for sparse books.
    static let foliateBookReadyTOC = Notification.Name("vreader.foliateBookReadyTOC")

    /// Bug #262 / GH #1136: posted by `FoliateBilingualContainerView`
    /// converting `.foliateBookReadyTOC` into flat `[TOCEntry]`. Carries
    /// `userInfo = ["entries": [TOCEntry], "fingerprintKey": String]`.
    /// `ReaderContainerView` observes it and assigns `tocEntries` so the
    /// bottom-chrome Contents button (Bug #260) finally lists chapters for
    /// AZW3/MOBI. Filtered by `fingerprintKey`.
    static let foliateTOCAvailable = Notification.Name("vreader.foliateTOCAvailable")

    /// Bug #262 / GH #1136: posted by `FoliateBilingualContainerView` when
    /// a shared TOC / Notes / Highlight row tap fires `.readerNavigateToLocator`
    /// for an AZW3/MOBI book. Carries
    /// `userInfo = ["target": String, "fingerprintKey": String]` where
    /// `target` is the locator's CFI (preferred) or EPUB-style href.
    /// `FoliateSpikeView.Coordinator` observes it and evaluates
    /// `readerAPI.goTo('<escaped>')` against its live `WKWebView`. A
    /// dedicated channel (mirrors `.foliateRequestSeekFraction`) so the
    /// row-tap navigation path is self-documenting. Filtered by
    /// `fingerprintKey` so concurrent AZW3/MOBI readers do not cross-fire.
    static let foliateRequestSeekTarget = Notification.Name("vreader.foliateRequestSeekTarget")

    /// Feature #60 WI-7c1: posted by a reader bridge when the user
    /// finishes a long-press selection. The
    /// `SelectionPopoverPresenterModifier` observes this and presents
    /// `SelectionPopoverView` (WI-7a) as a SwiftUI sheet; actions
    /// route through `SelectionPopoverActionRouter` (WI-7b). Bridges
    /// should suppress their legacy `UIMenu` when they post this
    /// (the swap landed per-bridge across WI-7c2..7c5).
    ///
    /// WI-7c5a: the notification's `object` is a
    /// `SelectionPopoverRequestPayload` (`selection` +
    /// optional `requestToken`). A producer that still posts a bare
    /// `TextSelectionInfo` decodes as a tokenless payload —
    /// `SelectionPopoverRequest.payload(from:)` handles both shapes.
    static let readerSelectionPopoverRequested = Notification.Name("vreader.readerSelectionPopoverRequested")
}

/// Carries text selection info from bridges to container views via NotificationCenter.
struct TextSelectionInfo: Equatable, Sendable {
    let selectedText: String
    let startUTF16: Int
    let endUTF16: Int
}

// MARK: - Highlight color resolution (Feature #60 WI-7c2)

/// Extract the highlight color from a `.readerHighlightRequested`
/// notification's `userInfo`. Falls back to `"yellow"` when:
/// - `userInfo` is missing entirely (legacy producers — the
///   UIMenu callers from chunked TXT / MD bridges before
///   WI-7c3..7c5 land — don't set it)
/// - the `"color"` key holds a non-String value (drifted producer)
///
/// The post-popover producer (WI-7b `SelectionPopoverActionRouter`)
/// sets `userInfo["color"]` to the chosen
/// `NamedHighlightColor.rawValue` (`"yellow"` / `"pink"` /
/// `"green"` / `"blue"`).
@MainActor
func resolveHighlightColor(from notification: Notification) -> String {
    (notification.userInfo?["color"] as? String) ?? "yellow"
}

/// Cross-format selection event for the annotation pipeline.
/// Posted via `.readerTextSelected` notification when the user selects text
/// in any reader format (EPUB, PDF, TXT/MD).
struct ReaderSelectionEvent: Sendable {
    /// The selected text content.
    let selectedText: String
    /// Format-specific anchor identifying the exact location of the selection.
    let anchor: AnnotationAnchor
    /// Screen rect of the selection, for popup positioning.
    let sourceRect: CGRect
}

/// Carries a PDF highlight anchor and color for creating a visible annotation.
/// Used by PDFReaderContainerView to pass data to PDFViewBridge via state.
struct PDFHighlightNotificationPayload {
    let anchor: AnnotationAnchor
    let color: String
}

/// Carries the tap event for an existing highlight. Posted via
/// `.readerHighlightTapped` from any reader format's bridge; observed by
/// feature #64's `HighlightPopoverModifier` to open the unified
/// highlight-action popover.
///
/// **`sourceRect` coordinate-space contract (Bug #203 / GH #743)**: the rect
/// must be in the coordinate space of the same `UIView` the bridge supplies
/// as the popover's `hostViewProvider`. `UIKitHighlightPopoverPresenter` feeds
/// it to `UIPopoverPresentationController.sourceRect`, which UIKit interprets
/// in the host view's coords. Per-bridge:
///   - TXT (non-chunked): textView-local; presenter view is the textView.
///   - TXT chunked: tableView-local; presenter view is the tableView. The
///     chunked gesture wrapper converts textView-local rects from the
///     pure-point overload via `textView.convert(_, to: tableView)`.
///   - EPUB: webView-local from JS `getBoundingClientRect()`; presenter
///     view is the webView.
///   - PDF: pdfView-local via `pdfView.convert(hit.bounds, from: page)`.
///   - Foliate (AZW3/MOBI): `.zero` (known follow-up — Foliate JS doesn't
///     forward annotation rects yet); with no rect the unified popover
///     resolves to its bottom-sheet form.
/// Window-space rects (the pre-Bug-#203 contract) anchored the popover
/// off-screen whenever the host UIView was offset within its window.
struct ReaderHighlightTapEvent: Sendable, Equatable {
    let highlightID: UUID
    let sourceRect: CGRect
    /// Feature #1121: when true the unified popover opens directly in `.editing`
    /// mode (the "Edit handoff" auto-open from the HighlightsSheet Notes menu).
    /// Defaults false so every existing tap-driven producer + behavior is
    /// unchanged. A real user tap always leaves this false.
    var openInEditMode: Bool = false
}

/// Feature #1121: a programmatic request to navigate to a highlight and then
/// auto-open its editor. Posted by the HighlightsSheet "Edit" handoff; observed
/// by the mounted `HighlightPopoverModifier`, which — after a short navigation
/// settle — resolves the highlight (book-scoped) and opens the unified card in
/// editing mode via the `.zero`-rect sheet form (format-agnostic; no per-format
/// anchor rect needed). Carries the book key + a single-flight token so a
/// stale/superseded request (the user tapped another highlight, triggered a
/// newer edit, or the request targets a different book) is ignored.
struct ReaderHighlightEditRequest: Sendable, Equatable {
    let highlightID: UUID
    /// The book the request targets — observers ignore a mismatch.
    let bookFingerprintKey: String
    /// Monotonic per-session token; a newer request supersedes an older one.
    let token: UUID
}
