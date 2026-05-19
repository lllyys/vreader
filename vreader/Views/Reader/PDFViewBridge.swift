// Purpose: UIViewRepresentable wrapping PDFKit's PDFView for PDF rendering.
// Provides page change notifications, page navigation, zoom control,
// text selection observation, highlight annotation lifecycle,
// and password unlock delegation back to the ViewModel.
//
// Key decisions:
// - Uses PDFKit (system framework) for rendering — no third-party dependencies.
// - Coordinator calls ViewModel directly (avoids protocol conformance issues on struct).
// - Page change notification via NotificationCenter (PDFViewPageChanged).
// - Selection change notification via PDFViewSelectionChanged — posts ReaderSelectionEvent.
// - Zoom level configurable; defaults to autoScale for fit-width.
// - Non-editable: read-only display mode.
// - restorePage applied once after document loads.
// - Tap gesture gated on currentSelection == nil to avoid clearing active selection.
// - Highlight restoration and creation processed via updateUIView from container state.
//
// @coordinates-with: PDFReaderViewModel.swift, PDFReaderContainerView.swift,
//   PDFAnnotationBridge.swift, ReaderNotifications.swift

#if canImport(UIKit)
import SwiftUI
import PDFKit

/// SwiftUI wrapper for PDFKit's PDFView.
struct PDFViewBridge: UIViewRepresentable {
    let url: URL
    var restorePage: Int?
    var password: String?
    /// Incremented on each password submission to trigger re-unlock even with same password.
    var passwordAttemptId: Int = 0
    let viewModel: PDFReaderViewModel
    /// Highlight records to restore as visible annotations. Processed once after document loads.
    var highlightRecords: [HighlightRecord]?
    /// Anchor + color for a newly created highlight. Processed once then cleared via the ID.
    var pendingHighlight: PDFHighlightNotificationPayload?
    /// Incremented each time a new highlight is created, to trigger processing in updateUIView.
    var pendingHighlightId: Int = 0
    /// Temporary search highlight text to find and select on the current page (bug #43).
    /// When set, updateUIView uses PDFDocument.findString to locate and select the text.
    var searchHighlightText: String?
    /// Phase R4: renderer for managing highlight annotations with ID tracking.
    var highlightRenderer: PDFHighlightRenderer?
    /// Bug #198: reader theme used to flip the PDFView gutter background
    /// (the area surrounding the rendered PDF page). When nil, falls back to
    /// PDFKit's default (light gray) — preserves the old behavior for any
    /// caller that hasn't been wired through. Page-interior pixels are still
    /// rendered by PDFKit from the source PDF (white for typical text PDFs);
    /// inverting page colors in dark mode is a separate feature.
    /// The reader color theme — drives the PDF gutter background tint.
    /// Feature #60 WI-11: migrated from the legacy `ReaderTheme`.
    var theme: ReaderThemeV2?

    func makeUIView(context: Context) -> PDFView {
        let pdfView = PDFView()
        pdfView.autoScales = true
        pdfView.displayMode = .singlePageContinuous
        pdfView.displayDirection = .vertical

        // Accessibility
        pdfView.accessibilityIdentifier = "pdfView"

        // Bug #198: theme the PDFView gutter so Dark theme produces a
        // visibly dark background around the page, matching Sepia / Light
        // behavior (which previously only flipped the chrome bar).
        context.coordinator.lastAppliedTheme = Self.applyThemeIfChanged(
            pdfView: pdfView,
            theme: theme,
            lastAppliedTheme: context.coordinator.lastAppliedTheme
        )

        context.coordinator.pdfView = pdfView
        context.coordinator.viewModel = viewModel
        context.coordinator.highlightRenderer = highlightRenderer

        // Tap gesture for toolbar toggle (bug #32 — same pattern as TXT #21).
        // Feature #64 WI-7: a tap that hits a persisted highlight annotation
        // posts `.readerHighlightTapped` (the unified popover's trigger) via
        // `handleTap` — see `Coordinator.handleTap`.
        let tapGesture = UITapGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleTap(_:))
        )
        tapGesture.delegate = context.coordinator
        pdfView.addGestureRecognizer(tapGesture)

        // Observe page changes
        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.pageDidChange(_:)),
            name: .PDFViewPageChanged,
            object: pdfView
        )

        // Observe selection changes for annotation pipeline
        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.selectionDidChange(_:)),
            name: .PDFViewSelectionChanged,
            object: pdfView
        )

        loadDocument(into: pdfView, coordinator: context.coordinator)

        return pdfView
    }

    func updateUIView(_ pdfView: PDFView, context: Context) {
        // Bug #198: re-apply theme background when the user switches theme
        // mid-session. The reverse path (concrete-theme -> nil) isn't
        // handled because it doesn't exist in production wiring
        // (ReaderContainerView always threads the live settingsStore) and
        // previews start nil with lastAppliedTheme also nil so the
        // inconsistency never materializes.
        context.coordinator.lastAppliedTheme = Self.applyThemeIfChanged(
            pdfView: pdfView,
            theme: theme,
            lastAppliedTheme: context.coordinator.lastAppliedTheme
        )

        // Re-bind the renderer on every update — `highlightRenderer` is owned
        // by `PDFReaderContainerView` as `@State` and feeds the coordinator's
        // tap hit-test (`resolveHighlightTapEvent`).
        context.coordinator.highlightRenderer = highlightRenderer

        // Handle password retry: if attempt ID changed, try unlocking
        if let password,
           passwordAttemptId != context.coordinator.lastPasswordAttemptId,
           let document = pdfView.document, document.isLocked {
            context.coordinator.lastPasswordAttemptId = passwordAttemptId
            let unlocked = document.unlock(withPassword: password)
            if unlocked {
                let totalPages = document.pageCount
                viewModel.passwordAccepted(totalPages: totalPages)
                // Restore page after unlock
                if let page = restorePage,
                   page < document.pageCount,
                   let pdfPage = document.page(at: page) {
                    pdfView.go(to: pdfPage)
                }
            } else {
                viewModel.passwordRejected()
            }
        }

        // Navigate to page if requested and not yet applied
        if let page = restorePage,
           context.coordinator.lastRestoredPage != page,
           let document = pdfView.document,
           !document.isLocked {
            context.coordinator.lastRestoredPage = page
            if page < document.pageCount, let pdfPage = document.page(at: page) {
                pdfView.go(to: pdfPage)
            }
        }

        // Restore saved highlights (once, after document loads)
        if let records = highlightRecords,
           !context.coordinator.didRestoreHighlights,
           let document = pdfView.document,
           !document.isLocked {
            context.coordinator.didRestoreHighlights = true
            // Phase R4: use renderer to track annotation map (needed for delete)
            if let renderer = highlightRenderer {
                renderer.setDocument(document)
                renderer.restore(records: records)
            } else {
                PDFAnnotationBridge.restoreHighlights(for: document, from: records)
            }
        }

        // Create visible annotation for a newly persisted highlight
        // Note: When coordinator is active, new highlights go through renderer.apply()
        // instead of this path. This remains as fallback for pre-coordinator create.
        if let highlight = pendingHighlight,
           pendingHighlightId != context.coordinator.lastPendingHighlightId,
           let document = pdfView.document,
           !document.isLocked {
            context.coordinator.lastPendingHighlightId = pendingHighlightId
            PDFAnnotationBridge.createHighlightFromAnchor(
                highlight.anchor, color: highlight.color, in: document
            )
        }

        // Temporary search highlight via text selection (bug #43)
        if let searchText = searchHighlightText,
           searchText != context.coordinator.lastSearchHighlightText,
           let document = pdfView.document,
           !document.isLocked {
            context.coordinator.lastSearchHighlightText = searchText
            // Issue 7: Cancel any previous clear timer to prevent stale timer
            // from clearing the wrong selection during fast navigation.
            context.coordinator.clearSearchWorkItem?.cancel()
            // Delay slightly to allow page navigation to complete before searching
            let pdfViewRef = pdfView
            let coordinator = context.coordinator
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                let selections = document.findString(searchText, withOptions: .caseInsensitive)
                // Issue 1: Filter selections to the current (target) page.
                // findString returns matches across the entire document. For duplicate
                // quotes, pick the match on the page we just navigated to.
                let targetPage = pdfViewRef.currentPage
                let match = selections.first(where: { sel in
                    guard let targetPage else { return true }
                    return sel.pages.contains(targetPage)
                }) ?? selections.first
                if let match {
                    // Issue 2: Suppress selectionDidChange while setting search selection.
                    coordinator.isSearchHighlighting = true
                    pdfViewRef.setCurrentSelection(match, animate: true)
                    coordinator.isSearchHighlighting = false
                    // Issue 7: Use cancellable DispatchWorkItem for auto-clear.
                    let clearItem = DispatchWorkItem { [weak pdfViewRef, weak coordinator] in
                        pdfViewRef?.clearSelection()
                        // Issue 6: Reset lastSearchHighlightText so the same quote
                        // can be navigated to again after the highlight clears.
                        coordinator?.lastSearchHighlightText = nil
                        coordinator?.clearSearchWorkItem = nil
                    }
                    coordinator.clearSearchWorkItem = clearItem
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3.0, execute: clearItem)
                }
            }
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    // MARK: - Private

    private func loadDocument(into pdfView: PDFView, coordinator: Coordinator) {
        let fileURL = url
        let pwd = password
        let restorePage = restorePage
        let viewModel = viewModel

        Task.detached {
            guard let document = PDFDocument(url: fileURL) else {
                await MainActor.run {
                    viewModel.documentDidFailToLoad(error: "Failed to load PDF document.")
                }
                return
            }

            await MainActor.run {
                pdfView.document = document

                if document.isLocked {
                    if let pwd, document.unlock(withPassword: pwd) {
                        viewModel.documentDidLoad(totalPages: document.pageCount)
                    } else {
                        viewModel.documentNeedsPassword()
                    }
                } else {
                    let totalPages = document.pageCount
                    viewModel.documentDidLoad(totalPages: totalPages)

                    if let page = restorePage, page < totalPages,
                       let pdfPage = document.page(at: page) {
                        coordinator.lastRestoredPage = page
                        pdfView.go(to: pdfPage)
                    }
                }
            }
        }
    }

    // MARK: - Theme application (bug #198)

    /// Sets `pdfView.backgroundColor` from the supplied `ReaderThemeV2`'s
    /// `backgroundColor` token so the gutter area surrounding the rendered
    /// PDF page reflects the reader theme (Paper / Sepia / Dark / OLED /
    /// Photo) instead of staying on PDFKit's default light gray. Pure
    /// helper — testable without a real UIViewRepresentable construction.
    /// Does NOT invert the rendered page pixels; PDFKit continues to draw
    /// the source PDF's own colors (typically white pages with black
    /// text). Inverting the page interior in dark theme is a separate
    /// feature. (Feature #60 WI-11: migrated from the legacy `ReaderTheme`.)
    static func applyThemeBackground(to pdfView: PDFView, theme: ReaderThemeV2) {
        pdfView.backgroundColor = theme.backgroundColor
    }

    /// Gated reapplication used by `makeUIView` / `updateUIView`. When `theme`
    /// is non-nil and differs from `lastAppliedTheme`, applies it and returns
    /// the new last-applied value; otherwise returns `lastAppliedTheme`
    /// unchanged so an unrelated update (page nav, scroll fraction) doesn't
    /// redundantly reset the background. Extracted so tests can drive the
    /// exact production code path with a real `PDFView` and assert against
    /// `pdfView.backgroundColor` directly.
    static func applyThemeIfChanged(
        pdfView: PDFView,
        theme: ReaderThemeV2?,
        lastAppliedTheme: ReaderThemeV2?
    ) -> ReaderThemeV2? {
        guard let theme, lastAppliedTheme != theme else { return lastAppliedTheme }
        applyThemeBackground(to: pdfView, theme: theme)
        return theme
    }

    // MARK: - Coordinator

    @MainActor
    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var viewModel: PDFReaderViewModel?
        weak var pdfView: PDFView?
        /// Tracks the last restored page to avoid re-applying on every updateUIView.
        var lastRestoredPage: Int?
        /// Tracks the last password attempt ID to detect retries (including same password).
        var lastPasswordAttemptId: Int = 0
        /// Whether saved highlights have been restored on this document.
        var didRestoreHighlights: Bool = false
        /// Tracks the last processed pending highlight ID to avoid re-creating.
        var lastPendingHighlightId: Int = 0
        /// Tracks the last search highlight text to avoid re-processing (bug #43).
        /// Reset to nil when the auto-clear timer fires so the same quote can be
        /// navigated to again (Issue 6).
        var lastSearchHighlightText: String?
        /// When true, suppresses selectionDidChange from posting .readerTextSelected
        /// (prevents search highlight from opening the highlight action sheet).
        var isSearchHighlighting: Bool = false
        /// Bug #198: tracks the last applied reader theme so updateUIView only
        /// re-applies `applyThemeBackground` when the user actually switched.
        /// Feature #60 WI-11: migrated from the legacy `ReaderTheme`.
        var lastAppliedTheme: ReaderThemeV2?
        /// Feature #64 WI-7: weak reference to the renderer that owns the
        /// `[UUID: [PDFAnnotation]]` map. `handleTap` consults this to detect
        /// taps on highlight annotations and post `.readerHighlightTapped`
        /// (the unified popover's trigger) before falling through to the
        /// chrome-toggle path.
        weak var highlightRenderer: PDFHighlightRenderer?
        /// Cancellable work item for the selection auto-clear timer (Issue 7).
        /// Stored so a new search highlight can cancel the previous timer, preventing
        /// a stale timer from clearing the wrong selection.
        var clearSearchWorkItem: DispatchWorkItem?

        @objc func pageDidChange(_ notification: Notification) {
            guard let pdfView,
                  let currentPage = pdfView.currentPage,
                  let document = pdfView.document else {
                return
            }
            let pageIndex = document.index(for: currentPage)
            viewModel?.pageDidChange(to: pageIndex)
        }

        @objc func selectionDidChange(_ notification: Notification) {
            // Skip posting the text selection notification when a search highlight
            // is being programmatically applied (Issue 2 — avoids opening highlight sheet).
            guard !isSearchHighlighting else { return }

            guard let pdfView,
                  let selection = pdfView.currentSelection,
                  let selectedText = selection.string,
                  !selectedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  let document = pdfView.document else {
                return
            }

            // Get selection pages and rects
            let selectionPages = selection.selectionsByLine()
            var allRects: [CGRect] = []
            var firstPageIndex: Int?

            for lineSelection in selectionPages {
                guard let pages = lineSelection.pages as? [PDFPage] else { continue }
                for page in pages {
                    let pageIndex = document.index(for: page)
                    if firstPageIndex == nil { firstPageIndex = pageIndex }
                    let bounds = lineSelection.bounds(for: page)
                    if bounds != .zero {
                        allRects.append(bounds)
                    }
                }
            }

            guard let pageIndex = firstPageIndex,
                  let page = document.page(at: pageIndex),
                  !allRects.isEmpty else {
                return
            }

            let pageBounds = page.bounds(for: .mediaBox)

            // Convert first rect to screen coordinates for popup positioning
            let firstRect = allRects[0]
            let screenRect: CGRect
            if let convertedRect = pdfView.convert(firstRect, from: page) as CGRect? {
                screenRect = pdfView.convert(convertedRect, to: nil)
            } else {
                screenRect = firstRect
            }

            let event = PDFAnnotationBridge.makeSelectionEvent(
                selectedText: selectedText,
                pageIndex: pageIndex,
                viewRects: allRects,
                pageBounds: pageBounds,
                sourceRect: screenRect
            )

            NotificationCenter.default.post(
                name: .readerTextSelected,
                object: event
            )
        }

        @objc func handleTap(_ gesture: UITapGestureRecognizer) {
            // Gate tap on no active selection to avoid clearing selection
            if let pdfView, pdfView.currentSelection != nil {
                return
            }

            // Feature #64 WI-7: check whether the tap hit an existing
            // highlight annotation before the chrome-toggle path. If it did,
            // post `.readerHighlightTapped` (which the unified highlight-action
            // popover observes via `HighlightPopoverModifier`) and DO NOT fire
            // `.readerContentTapped`. WI-7 removed feature #53's long-press
            // delete `UIMenu` and feature #55's read-only note preview — a tap
            // now opens the unified popover.
            if let event = resolveHighlightTapEvent(at: gesture.location(in: pdfView ?? UIView())) {
                NotificationCenter.default.post(
                    name: .readerHighlightTapped, object: event
                )
                return
            }

            NotificationCenter.default.post(name: .readerContentTapped, object: nil)
        }

        /// Resolves a point in `pdfView` coordinates to a `ReaderHighlightTapEvent`
        /// when it lands on a persisted highlight annotation — the hit-test
        /// `handleTap` uses to post `.readerHighlightTapped` (the unified
        /// popover's trigger). Returns nil on a miss.
        private func resolveHighlightTapEvent(at location: CGPoint) -> ReaderHighlightTapEvent? {
            guard let pdfView,
                  let renderer = highlightRenderer,
                  !renderer.annotationMap.isEmpty,
                  let page = pdfView.page(for: location, nearest: false)
            else { return nil }
            let pagePoint = pdfView.convert(location, to: page)
            guard let highlightID = PDFHighlightTapResolver.resolveHighlightID(
                atPagePoint: pagePoint,
                onPage: page,
                annotationMap: renderer.annotationMap
            ) else { return nil }
            // Screen rect for popover anchoring: the first annotation whose
            // bounds contain the point, converted to PDFView coords.
            var sourceRect: CGRect = .zero
            if let annotations = renderer.annotationMap[highlightID],
               let hit = annotations.first(where: {
                   $0.page === page && $0.bounds.contains(pagePoint)
               }) {
                sourceRect = pdfView.convert(hit.bounds, from: page)
            }
            return ReaderHighlightTapEvent(highlightID: highlightID, sourceRect: sourceRect)
        }

        // Bug #32: allow the chrome-toggle tap to fire alongside PDFView's
        // internal gestures. Feature #64 WI-7 removed the highlight
        // long-press recognizer (the unified popover is tap-triggered), so
        // the tap is the only recognizer this coordinator owns — it always
        // recognizes simultaneously with PDFKit's gestures.
        nonisolated func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            true
        }

        deinit {
            MainActor.assumeIsolated {
                clearSearchWorkItem?.cancel()
                clearSearchWorkItem = nil
            }
            NotificationCenter.default.removeObserver(self)
        }
    }
}
#endif
