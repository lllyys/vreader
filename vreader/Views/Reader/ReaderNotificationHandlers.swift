// Purpose: Pure handler functions for reader notification events.
// Extracted from TXTReaderContainerView and MDReaderContainerView (WI-003).
// Handlers are tested against a mock state carrier — no SwiftUI coupling.
//
// Key decisions:
// - Handlers receive a state protocol + deps struct, making them testable.
// - locatorFactory closure abstracts format-specific locator creation
//   (LocatorFactory.txtRange vs .mdRange).
// - Each handler is a static function — no instance state.
//
// @coordinates-with ReaderNotificationModifier.swift,
//   TXTReaderContainerView.swift, MDReaderContainerView.swift

import Foundation

// MARK: - State Protocol

/// Mutable state carrier for notification handlers.
/// Implemented by both the SwiftUI modifier (via Bindings) and test mocks.
@MainActor
protocol ReaderNotificationHandlerStateProtocol: AnyObject {
    var scrollToOffset: Int? { get set }
    var highlightRange: NSRange? { get set }
    var highlightIsTemporary: Bool { get set }
    var persistedHighlightRanges: [NSRange] { get set }
    var pendingAnnotationInfo: TextSelectionInfo? { get set }
    var annotationNoteText: String { get set }
}

// MARK: - Dependencies

/// Dependencies injected by the container view into the handlers.
struct ReaderNotificationDeps {
    let bookFingerprintKey: String
    let bookFingerprint: DocumentFingerprint
    let bookmarkPersistence: any BookmarkPersisting
    let highlightPersistence: any HighlightPersisting
    let annotationPersistence: any AnnotationPersisting
    let locatorFactory: @MainActor (DocumentFingerprint, Int, Int, String?) -> Locator?
    let sourceText: @MainActor () -> String?
    let makeCurrentLocator: @MainActor () -> Locator
    let onNavigate: @MainActor (Int) -> Void
    /// Optional haptic feedback provider. When non-nil, fires on successful bookmark add.
    let hapticFeedback: (any HapticFeedbackProviding)?

    init(
        bookFingerprintKey: String,
        bookFingerprint: DocumentFingerprint,
        bookmarkPersistence: any BookmarkPersisting,
        highlightPersistence: any HighlightPersisting,
        annotationPersistence: any AnnotationPersisting,
        locatorFactory: @MainActor @escaping (DocumentFingerprint, Int, Int, String?) -> Locator?,
        sourceText: @MainActor @escaping () -> String?,
        makeCurrentLocator: @MainActor @escaping () -> Locator,
        onNavigate: @MainActor @escaping (Int) -> Void,
        hapticFeedback: (any HapticFeedbackProviding)? = nil
    ) {
        self.bookFingerprintKey = bookFingerprintKey
        self.bookFingerprint = bookFingerprint
        self.bookmarkPersistence = bookmarkPersistence
        self.highlightPersistence = highlightPersistence
        self.annotationPersistence = annotationPersistence
        self.locatorFactory = locatorFactory
        self.sourceText = sourceText
        self.makeCurrentLocator = makeCurrentLocator
        self.onNavigate = onNavigate
        self.hapticFeedback = hapticFeedback
    }
}

// MARK: - Handlers

/// Static handler functions for reader notifications.
/// Each function mutates the state carrier and optionally calls persistence.
enum ReaderNotificationHandlers {

    /// Bookmark the current position (no state mutation — pure persistence).
    /// Fires haptic feedback on success; suppresses haptic on failure.
    @MainActor
    static func handleBookmarkRequest(
        deps: ReaderNotificationDeps
    ) async {
        let locator = deps.makeCurrentLocator()
        let persistence = deps.bookmarkPersistence
        let key = deps.bookFingerprintKey
        do {
            _ = try await persistence.addBookmark(locator: locator, title: nil, toBookWithKey: key)
            deps.hapticFeedback?.triggerLightImpact()
        } catch {
            // Bookmark add failed — no haptic feedback
        }
    }

    /// Navigate to a locator (from search result or annotation panel).
    @MainActor
    static func handleNavigateToLocator(
        locator: Locator,
        state: some ReaderNotificationHandlerStateProtocol,
        deps: ReaderNotificationDeps
    ) {
        guard let offset = locator.charOffsetUTF16 ?? locator.charRangeStartUTF16 else { return }
        state.scrollToOffset = offset
        state.highlightIsTemporary = true
        if let start = locator.charRangeStartUTF16,
           let end = locator.charRangeEndUTF16, end > start {
            state.highlightRange = NSRange(location: start, length: end - start)
        } else {
            state.highlightRange = nil
        }
        deps.onNavigate(offset)
    }

    /// Create a persistent highlight from a text selection.
    @MainActor
    static func handleHighlightRequest(
        info: TextSelectionInfo,
        state: some ReaderNotificationHandlerStateProtocol,
        deps: ReaderNotificationDeps
    ) async {
        // Validate range (audit fix: prevent negative NSRange length)
        guard info.startUTF16 >= 0, info.endUTF16 > info.startUTF16 else { return }
        guard let locator = deps.locatorFactory(
            deps.bookFingerprint,
            info.startUTF16,
            info.endUTF16,
            deps.sourceText()
        ) else { return }
        state.highlightIsTemporary = false
        let newRange = NSRange(location: info.startUTF16, length: info.endUTF16 - info.startUTF16)
        state.highlightRange = newRange
        state.persistedHighlightRanges.append(newRange)
        let persistence = deps.highlightPersistence
        let key = deps.bookFingerprintKey
        try? await persistence.addHighlight(
            locator: locator,
            selectedText: info.selectedText,
            color: "yellow",
            note: nil,
            toBookWithKey: key
        )
    }

    /// Begin the "Add Note" flow — sets pending info, clears note text.
    @MainActor
    static func handleAnnotationRequest(
        info: TextSelectionInfo,
        state: some ReaderNotificationHandlerStateProtocol
    ) {
        state.pendingAnnotationInfo = info
        state.annotationNoteText = ""
    }

    /// Save the annotation note (from AddNoteSheet).
    @MainActor
    static func handleAnnotationSave(
        state: some ReaderNotificationHandlerStateProtocol,
        deps: ReaderNotificationDeps
    ) async {
        guard let info = state.pendingAnnotationInfo else {
            state.pendingAnnotationInfo = nil
            return
        }
        let trimmed = state.annotationNoteText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            state.pendingAnnotationInfo = nil
            return
        }
        guard let locator = deps.locatorFactory(
            deps.bookFingerprint,
            info.startUTF16,
            info.endUTF16,
            deps.sourceText()
        ) else {
            state.pendingAnnotationInfo = nil
            return
        }
        let persistence = deps.annotationPersistence
        let key = deps.bookFingerprintKey
        try? await persistence.addAnnotation(locator: locator, content: trimmed, toBookWithKey: key)
        state.pendingAnnotationInfo = nil
    }

    /// Cancel the "Add Note" flow — clears pending info without persistence.
    @MainActor
    static func handleAnnotationCancel(
        state: some ReaderNotificationHandlerStateProtocol
    ) {
        state.pendingAnnotationInfo = nil
    }
}
