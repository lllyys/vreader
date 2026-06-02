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
    /// Bug #312: true when the pending `scrollToOffset` is a TOC / chapter /
    /// bookmark jump (a point offset with no match range) that should pin its
    /// destination to the TOP edge, vs. a search hit (a char range) that keeps
    /// the ~0.25 viewport headroom showing context. Set by
    /// `handleNavigateToLocator`; read by the TXT bridges when consuming
    /// `scrollToOffset`.
    var scrollSnapToTop: Bool { get set }
    /// Monotonic counter bumped on every `.readerNavigateToLocator` event.
    /// Bug #154 / GH #443: a search-tap to an already-current target re-sets
    /// `scrollToOffset` / `highlightRange` to values they already hold — an
    /// `@Observable` no-op write that never re-evaluates the SwiftUI body, so
    /// the temporary highlight is never re-applied. The nonce always changes,
    /// guaranteeing the body re-evaluates and the bridge re-paints.
    var highlightNonce: Int { get set }
    var persistedHighlightRanges: [PaintedHighlight] { get set }
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
    ///
    /// Bug #154 / GH #443: `highlightNonce` is bumped on every navigation that
    /// is actually performed. When a search-tap targets the location the
    /// reader is already at, `scrollToOffset` / `highlightRange` are
    /// re-assigned to values they already hold — an `@Observable` no-op write
    /// that does NOT re-evaluate the SwiftUI body, so the reader bridge's
    /// `updateUIView` never runs and the temporary highlight is never
    /// re-painted. The nonce always advances, so the body re-evaluates and the
    /// bridge re-paints + re-arms its 3 s auto-clear timer. The bump is placed
    /// AFTER the nil-offset guard so an ignored event never fires a spurious
    /// re-paint.
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
        // Bug #312: a search hit carries a char RANGE (highlight the match → keep
        // the search headroom that shows it in context); a TOC / chapter /
        // bookmark jump carries only a point offset (no range) → snap the
        // destination to the top edge so the chapter title pins to the top
        // instead of landing ~¼ down.
        state.scrollSnapToTop = (state.highlightRange == nil)
        state.highlightNonce &+= 1
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
        // This legacy path persists a "yellow" highlight (see addHighlight
        // below); the optimistic paint carries the same color.
        state.persistedHighlightRanges.append(
            PaintedHighlight(range: newRange, colorName: "yellow")
        )
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

    /// Captured-value payload for `handleAnnotationSave`. Built
    /// synchronously by `prepareAnnotationSave(state:deps:)` before the
    /// surrounding `dismiss()` clears `pendingAnnotationInfo`.
    struct AnnotationSaveRequest: Sendable {
        let info: TextSelectionInfo
        let trimmed: String
        let locator: Locator
    }

    /// Synchronously validates the annotation save inputs and captures
    /// them into an `AnnotationSaveRequest` for the async handler.
    /// Clears `pendingAnnotationInfo` AS PART OF the same synchronous
    /// pass — so the AddNoteSheet's `dismiss()` (which fires
    /// immediately after `onSave()`) doesn't race the Task body.
    ///
    /// Returns nil when any of the guards fail (no pending info,
    /// trimmed note text empty, locator factory returns nil) — in
    /// every nil-return case, `pendingAnnotationInfo` is still cleared
    /// so the sheet dismisses.
    ///
    /// Bug #188 fix: extracting this function means the modifier-side
    /// "capture-by-value before dismiss-race" pattern is now testable
    /// without booting SwiftUI. The regression test simulates the
    /// production sequence (prepare → mutate state → handler) and
    /// pins the contract.
    @MainActor
    static func prepareAnnotationSave(
        state: some ReaderNotificationHandlerStateProtocol,
        deps: ReaderNotificationDeps
    ) -> AnnotationSaveRequest? {
        guard let info = state.pendingAnnotationInfo else {
            state.pendingAnnotationInfo = nil
            return nil
        }
        let trimmed = state.annotationNoteText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            state.pendingAnnotationInfo = nil
            return nil
        }
        guard let locator = deps.locatorFactory(
            deps.bookFingerprint,
            info.startUTF16,
            info.endUTF16,
            deps.sourceText()
        ) else {
            state.pendingAnnotationInfo = nil
            return nil
        }
        state.pendingAnnotationInfo = nil
        return AnnotationSaveRequest(info: info, trimmed: trimmed, locator: locator)
    }

    /// Persist an annotation note + matching HighlightRecord. Bug #181
    /// + Bug #188 fix: the handler now takes the validated `info` /
    /// `trimmed` / `locator` as pre-captured value arguments so it can
    /// run inside a `Task` spawned from a SwiftUI button action without
    /// reading view state that the surrounding `dismiss()` has already
    /// cleared.
    ///
    /// Why this signature shape:
    /// - The AddNoteSheet's Save button calls `onSave(); dismiss()`
    ///   synchronously. `dismiss()` triggers the parent `.sheet(...)`
    ///   binding's setter, which clears `uiState.pendingAnnotationInfo`
    ///   synchronously, BEFORE the `Task { await ... }` body runs.
    /// - If the handler reads `state.pendingAnnotationInfo` inside the
    ///   Task (the pre-bug-188 shape), the first guard sees nil and the
    ///   whole flow becomes a no-op — bug #188's signature failure mode.
    /// - The modifier's `onSave` now does sync validation + capture
    ///   BEFORE spawning the Task; this handler just does the dual-
    ///   write. The handler never reads from `state` and never mutates
    ///   `pendingAnnotationInfo` — the modifier owns dismissal.
    ///
    /// Bug #181 atomicity: only creates the HighlightRecord when the
    /// AnnotationRecord write succeeded, so Notes ↔ Highlights stay in
    /// lockstep.
    @MainActor
    static func handleAnnotationSave(
        info: TextSelectionInfo,
        trimmed: String,
        locator: Locator,
        deps: ReaderNotificationDeps,
        highlightCoordinator: HighlightCoordinator
    ) async {
        let persistence = deps.annotationPersistence
        let key = deps.bookFingerprintKey
        // Stay in lockstep: only create the highlight when the annotation
        // persisted successfully. If addAnnotation throws, both writes
        // are skipped so the Notes and Highlights tabs don't diverge.
        do {
            _ = try await persistence.addAnnotation(locator: locator, content: trimmed, toBookWithKey: key)
        } catch {
            return
        }
        await highlightCoordinator.create(
            locator: locator,
            selectedText: info.selectedText,
            color: "yellow",
            note: trimmed
        )
    }

    /// Cancel the "Add Note" flow — clears pending info without persistence.
    @MainActor
    static func handleAnnotationCancel(
        state: some ReaderNotificationHandlerStateProtocol
    ) {
        state.pendingAnnotationInfo = nil
    }
}
