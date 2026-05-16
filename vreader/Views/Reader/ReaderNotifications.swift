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
    /// the highlight's UUID and a `sourceRect` in the coordinate space of
    /// the same `UIView` the bridge later passes to
    /// `HighlightActionPresenting.present(for:in:)` — see the doc on
    /// `ReaderHighlightTapEvent.sourceRect` for the cross-bridge contract.
    /// Feature #53 / GH #596.
    static let readerHighlightTapped = Notification.Name("vreader.readerHighlightTapped")
    /// Posted after annotation import completes (bug #88).
    /// Reader containers observe this to re-render persisted highlights.
    static let readerHighlightsDidImport = Notification.Name("vreader.readerHighlightsDidImport")
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

    /// Feature #60 WI-7c1: posted by a reader bridge when the user
    /// finishes a long-press selection. The
    /// `SelectionPopoverPresenterModifier` observes this and presents
    /// `SelectionPopoverView` (WI-7a) as a SwiftUI sheet; actions
    /// route through `SelectionPopoverActionRouter` (WI-7b). The
    /// notification's `object` is the `TextSelectionInfo` payload.
    /// Bridges should suppress their legacy `UIMenu` when they post
    /// this (the swap lands per-bridge in WI-7c2..7c5).
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

/// Carries the tap event for an existing highlight (Feature #53).
/// Posted via `.readerHighlightTapped` from any reader format's bridge.
///
/// **`sourceRect` coordinate-space contract (Bug #203 / GH #743)**: the rect
/// must be in the coordinate space of the same `UIView` the bridge passes
/// to `HighlightActionPresenting.present(for:in:)`. The presenter feeds it
/// to `UIEditMenuConfiguration.sourcePoint`, which UIKit interprets in the
/// interaction-view's coords. Per-bridge:
///   - TXT (non-chunked): textView-local; presenter view is the textView.
///   - TXT chunked: tableView-local; presenter view is the tableView. The
///     chunked gesture wrapper converts textView-local rects from the
///     pure-point overload via `textView.convert(_, to: tableView)`.
///   - EPUB: webView-local from JS `getBoundingClientRect()`; presenter
///     view is the webView.
///   - PDF: pdfView-local via `pdfView.convert(hit.bounds, from: page)`.
///   - Foliate (AZW3/MOBI): `.zero` (known follow-up — Foliate JS doesn't
///     forward annotation rects yet); the menu anchors at view origin.
/// Window-space rects (the pre-Bug-#203 contract) anchored the menu
/// off-screen whenever the host UIView was offset within its window.
struct ReaderHighlightTapEvent: Sendable, Equatable {
    let highlightID: UUID
    let sourceRect: CGRect
}
