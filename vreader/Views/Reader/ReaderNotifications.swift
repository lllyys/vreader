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
    /// the highlight's UUID and screen-space rect for popover anchoring.
    /// Feature #53 / GH #596.
    static let readerHighlightTapped = Notification.Name("vreader.readerHighlightTapped")
    /// Posted after annotation import completes (bug #88).
    /// Reader containers observe this to re-render persisted highlights.
    static let readerHighlightsDidImport = Notification.Name("vreader.readerHighlightsDidImport")
    /// Posted when a footnote link is detected in EPUB content (foliate-js).
    /// Object is [String: String] with "href" and "text" keys.
    static let epubFootnoteDetected = Notification.Name("vreader.epubFootnoteDetected")
}

/// Carries text selection info from bridges to container views via NotificationCenter.
struct TextSelectionInfo {
    let selectedText: String
    let startUTF16: Int
    let endUTF16: Int
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
/// `sourceRect` is in screen-space coordinates of the host UIView/UIWindow,
/// used by `HighlightActionPresenting` to anchor the inline menu popover.
struct ReaderHighlightTapEvent: Sendable, Equatable {
    let highlightID: UUID
    let sourceRect: CGRect
}
