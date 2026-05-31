// Purpose: Shared @Observable UI state for TXT and MD reader containers (Phase R3).
// Eliminates duplicate @State variables between TXTReaderContainerView and
// MDReaderContainerView. Format-specific state (chunks, attributed strings,
// locator factories) remains in each container.
//
// Key decisions:
// - @Observable enables fine-grained SwiftUI tracking without individual @State vars.
// - Conforms to ReaderNotificationHandlerStateProtocol so the notification modifier
//   can mutate state directly (no Binding wiring needed).
// - Pagination helpers (syncPagedState, updatePagination, updateAutoPageTurner)
//   centralise logic that was duplicated identically in both containers.
// - refreshPersistedHighlights loads DB records into persistedHighlightRanges.
//
// @coordinates-with: ReaderNotificationModifier.swift, ReaderNotificationHandlers.swift,
//   TXTReaderContainerView.swift, MDReaderContainerView.swift,
//   NativeTextPageNavigator.swift, AutoPageTurner.swift

#if canImport(UIKit)
import Foundation
import UIKit

@Observable
@MainActor
final class TextReaderUIState: ReaderNotificationHandlerStateProtocol {

    // MARK: - Highlight & Annotation State

    /// Navigation target from search results. Updated via notification.
    var scrollToOffset: Int?
    /// Match highlight range for search navigation.
    var highlightRange: NSRange?
    /// Whether the current highlight is temporary (search nav) or persistent (user-created).
    var highlightIsTemporary: Bool = true
    /// Monotonic counter bumped on every `.readerNavigateToLocator` event
    /// (Bug #154 / GH #443). When a search-tap targets the location the reader
    /// is already at, `scrollToOffset` / `highlightRange` are re-assigned to
    /// values they already hold — an `@Observable` no-op write that does NOT
    /// re-evaluate the SwiftUI body, so the bridge's `updateUIView` never runs
    /// and the temporary highlight is never re-painted. The 3 s auto-clear
    /// timer also clears only the bridge coordinator's range, never this
    /// `highlightRange`, so the two drift apart. Bumping this counter on every
    /// navigate event forces a real observable change → body re-evaluation →
    /// bridge re-paint, regardless of whether the range value changed.
    var highlightNonce: Int = 0
    /// Persisted highlights loaded from DB on file open. Each carries its
    /// stored color name so the layout-manager painter renders the color
    /// the user chose (Bug #208 / GH #776) instead of a hardcoded yellow.
    var persistedHighlightRanges: [PaintedHighlight] = []
    /// Parallel lookup mapping each persisted range to its highlight UUID,
    /// used by tap-on-highlight hit-test (Feature #53 WI-2).
    /// `persistedHighlightRanges` is kept separate so the layout-manager
    /// painter contract is unchanged.
    var persistedHighlightLookup: [PersistedHighlightLookupEntry] = []
    /// Pending annotation info for the "Add Note" flow.
    var pendingAnnotationInfo: TextSelectionInfo?
    /// Text input for the annotation note.
    var annotationNoteText: String = ""

    // MARK: - Reading Progress

    /// Current reading progress for the scrubber bar (0.0-1.0).
    var readingProgress: Double = 0

    // MARK: - Paged Mode State (B08, B10, B11)

    /// Page navigator for paged mode. Nil when in scroll mode or large file.
    var pageNavigator: NativeTextPageNavigator?
    /// Tracks the current page for SwiftUI reactivity.
    var pagedCurrentPage: Int = 0
    /// Auto page turner instance (B10). Created when autoPageTurn is enabled.
    var autoPageTurner: AutoPageTurner?
    /// Side-effect run after the auto-page-turn timer advances a page and the
    /// page counter has been re-synced (Bug #258 / GH #1125). The container
    /// installs this once in its body-level `.task` to persist the new position
    /// (`viewModel.updateScrollPosition`), which `TextReaderUIState` cannot do
    /// itself because the view model lives in the container. The Int is the
    /// current page's UTF-16 char offset (nil if unavailable). Marked
    /// `@ObservationIgnored` — it is wiring, not observable reader state.
    @ObservationIgnored
    var onAutoAdvancePersist: ((Int?) -> Void)?

    // MARK: - Pagination Helpers

    /// Syncs the page counter from the navigator for SwiftUI reactivity.
    /// Returns the character offset of the current page (for position persistence), or nil.
    @discardableResult
    func syncPagedState() -> Int? {
        guard let nav = pageNavigator else { return nil }
        pagedCurrentPage = nav.currentPage
        if nav.totalPages > 1 {
            readingProgress = nav.progression
        }
        return nav.currentPageCharRange?.location
    }

    /// Creates or updates the page navigator when entering paged mode.
    /// Pass the rendered attributed string and the initial scroll offset (nil after first paginate).
    ///
    /// Bug #215 / GH #837: `viewportSize` is the paginator's per-page box.
    /// The MD paged renderer (`NativeTextPagedView`) does NOT cover the full
    /// screen — `ReaderBottomChrome` and the top safe area both inset its
    /// frame. Paginating against `UIScreen.main.bounds.size` produced pages
    /// sized for the wrong box: the layout-manager packed too much text per
    /// page, and the renderer (which clips to its actual smaller box) cut
    /// the last line mid-glyph. The MD container threads the measured box
    /// via a `GeometryReader`. Callers without a measured viewport (TXT,
    /// or test-time defaults) get `UIScreen.main.bounds.size` to preserve
    /// the legacy behavior.
    func updatePagination(
        isPagedMode: Bool,
        attributedText: NSAttributedString?,
        initialRestoreOffset: Int?,
        autoPageTurnEnabled: Bool,
        autoPageTurnInterval: TimeInterval,
        viewportSize: CGSize = UIScreen.main.bounds.size
    ) {
        guard isPagedMode else {
            // Explicit switch to scroll mode — destroy navigator.
            autoPageTurner?.stop()
            pageNavigator = nil
            return
        }
        guard let attrStr = attributedText else {
            // Bug #82: isPagedMode=true but attributedText not ready yet.
            // Preserve existing navigator to avoid falling back to scroll.
            return
        }

        let nav = pageNavigator ?? NativeTextPageNavigator()
        nav.paginateAttributed(
            attributedText: attrStr,
            viewportSize: viewportSize
        )

        // Restore position from saved offset on first paginate
        if pageNavigator == nil, let offset = initialRestoreOffset {
            nav.jumpToOffset(utf16Offset: offset)
        }

        pageNavigator = nav

        if autoPageTurnEnabled {
            updateAutoPageTurner(
                enabled: true,
                isPagedMode: isPagedMode,
                interval: autoPageTurnInterval
            )
        }
    }

    /// Starts or stops the auto page turner (B10).
    func updateAutoPageTurner(enabled: Bool, isPagedMode: Bool, interval: TimeInterval) {
        guard enabled, isPagedMode, let nav = pageNavigator else {
            autoPageTurner?.stop()
            return
        }

        let turner = autoPageTurner ?? AutoPageTurner()
        turner.interval = interval
        // Bug #258 / GH #1125: bridge each timer-driven advance into the
        // observable view state. Without this, the timer mutated only the
        // navigator's internal page — `pagedCurrentPage` (which drives the
        // renderer's explicit `currentPage` param) never updated, so the page
        // never re-rendered and `snapshot.position` stayed flat. We sync here
        // instead of posting `.readerNextPage` because that observer also
        // pauses the turner (Bug #131's manual-turn semantics), which would
        // halt auto-advance after one tick.
        turner.onAdvance = { [weak self] in
            guard let self else { return }
            let offset = self.syncPagedState()
            self.onAutoAdvancePersist?(offset)
        }
        turner.start(navigator: nav)
        autoPageTurner = turner
    }

    // MARK: - Highlight Persistence

    /// Loads persisted highlight ranges from fetched DB records.
    /// WI-2: also populates `persistedHighlightLookup` so the bridge
    /// coordinator can resolve a tapped range back to its highlight UUID
    /// for the inline edit/delete menu.
    func refreshPersistedHighlights(from records: [HighlightRecord]) {
        var highlights: [PaintedHighlight] = []
        var lookup: [PersistedHighlightLookupEntry] = []
        highlights.reserveCapacity(records.count)
        lookup.reserveCapacity(records.count)
        for record in records {
            guard let start = record.locator.charRangeStartUTF16,
                  let end = record.locator.charRangeEndUTF16,
                  end > start else { continue }
            let range = NSRange(location: start, length: end - start)
            // Bug #208: carry the stored color through to the painter.
            highlights.append(PaintedHighlight(range: range, colorName: record.color))
            lookup.append(PersistedHighlightLookupEntry(
                id: record.highlightId,
                range: range,
                // Bug #295: carry note-presence so an ambiguous tap prefers
                // the noted highlight over an overlapping color-only one.
                hasNote: !(record.note ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ))
        }
        persistedHighlightRanges = highlights
        persistedHighlightLookup = lookup
    }
}
#endif
