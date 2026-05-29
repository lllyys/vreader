// Purpose: TXT paged-mode rendering + cross-chapter page advance (Bug #284 /
// GH #1261). Splits the paged-layout wiring out of the (already large)
// `TXTReaderContainerView.swift` per rule 50 §9.
//
// Before this fix, TXT paged layout routed the current chapter into a
// scrollable `TXTTextViewBridge` (`chapterReaderContent`) and the
// `.readerNextPage` / `.readerPreviousPage` observers called
// `uiState.pageNavigator?.nextPage()` — but the navigator was never created
// (`updatePaginationIfNeeded` was dead code), so a TXT page-turn was a no-op
// and the reader could only cross a chapter boundary via the TOC.
//
// This extension wires the same `NativeTextPagedView` paged renderer that MD
// already uses (design reader-navigation.md §3), feeding it the CURRENT
// chapter's attributed string, and adds the cross-chapter advance the design
// specifies for paged mode (§2.2): the last-page→next-chapter and
// first-page→previous-chapter turns load the adjacent chapter and land on its
// first / last page respectively, clamping (bounce) at the document ends.
//
// Key decisions:
// - Pagination runs over the CURRENT chapter only (chapters are loaded lazily
//   by the VM); cross-chapter navigation reuses the VM's existing
//   `nextChapter()` / `previousChapter()` machinery, then re-paginates the
//   freshly loaded chapter and jumps to the landing page.
// - The boundary decision is the pure `TXTPagedChapterAdvance` seam — this
//   file only performs the async I/O + paginate + jump it dictates.
// - Position persistence stays in chapter-LOCAL coordinates (the VM converts
//   to global), matching the existing Paged-mode contract.
//
// @coordinates-with: TXTReaderContainerView.swift, TXTPagedChapterAdvance.swift,
//   NativeTextPagedView.swift, NativeTextPageNavigator.swift,
//   TextReaderUIState.swift, TXTReaderViewModel.swift

#if canImport(UIKit)
import SwiftUI
import UIKit

extension TXTReaderContainerView {

    /// True when the reader is in paged layout AND has a chapter index to
    /// page through. Large files (chunked) keep scroll rendering — `isPagedMode`
    /// already excludes them.
    var isPagedChapterMode: Bool {
        isPagedMode && hasChapterDisplayForPaged
    }

    /// Mirror of the private `hasChapterDisplay` gate, re-derived here because
    /// the original is `private` to the main file. Paged rendering needs both a
    /// chapter index and loaded chapter text.
    private var hasChapterDisplayForPaged: Bool {
        viewModel.chapterIndex != nil && viewModel.currentChapterText != nil
    }

    // MARK: - Paged Chapter Content

    /// Renders the current chapter one page at a time via `NativeTextPagedView`,
    /// mirroring `MDReaderContainerView.pagedReaderContent`. Pagination is
    /// chrome-aware (design §3.1) and the per-page indicator de-duplicates with
    /// the bottom chrome's chapter label (design §3.2): it shows only when the
    /// chrome is hidden.
    @ViewBuilder
    func pagedChapterReaderContent(
        text: String,
        attributedText: NSAttributedString
    ) -> some View {
        GeometryReader { proxy in
            VStack(spacing: 0) {
                if let nav = uiState.pageNavigator {
                    NativeTextPagedView(
                        navigator: nav,
                        fullText: attributedText.string,
                        fullAttributedText: attributedText,
                        config: settingsStore?.txtViewConfig ?? TXTViewConfig(),
                        currentPage: uiState.pagedCurrentPage,
                        pageTurnAnimation: settingsStore?.pageTurnAnimation ?? .none,
                        layout: settingsStore?.epubLayout
                    )

                    if nav.totalPages > 0 && !isChromeVisible {
                        Text("\(uiState.pagedCurrentPage + 1) / \(nav.totalPages)")
                            .font(.caption)
                            .foregroundStyle(.secondary.opacity(0.6))
                            .padding(.bottom, 4)
                            .accessibilityIdentifier("txtPageIndicator")
                    }
                } else {
                    // Navigator not built yet (first render before paginate).
                    Color.clear
                }
            }
            .padding(.bottom, Self.pagedBottomPadding(chromeVisible: isChromeVisible))
            .onAppear {
                repaginatePagedChapter(
                    viewportSize: Self.paginatorViewportSize(
                        proxy: proxy.size, chromeVisible: isChromeVisible
                    )
                )
            }
            .onChange(of: proxy.size) { _, newSize in
                repaginatePagedChapter(
                    viewportSize: Self.paginatorViewportSize(
                        proxy: newSize, chromeVisible: isChromeVisible
                    )
                )
            }
            // Chrome toggle changes the usable height (bottom padding + the
            // page indicator appears) — re-paginate so boundaries match what
            // the renderer displays. Mirrors MD's Codex audit Round-1 High #2.
            .onChange(of: isChromeVisible) { _, newValue in
                repaginatePagedChapter(
                    viewportSize: Self.paginatorViewportSize(
                        proxy: proxy.size, chromeVisible: newValue
                    )
                )
            }
            // Bug #284 / GH #1261: re-paginate when the chapter's attributed
            // string changes. A cross-chapter page-turn loads a new chapter
            // (changing `attributedText`) WITHOUT changing the GeometryReader's
            // geometry, so no layout pass would drive a fresh paginate; this
            // reuses the measured viewport and applies the queued
            // `pendingPagedLanding` (first/last page of the new chapter). Also
            // covers font/theme rebuilds within a chapter.
            .onChange(of: attributedText) { _, _ in
                repaginatePagedChapter(
                    viewportSize: Self.paginatorViewportSize(
                        proxy: proxy.size, chromeVisible: isChromeVisible
                    )
                )
            }
        }
        .accessibilityIdentifier("txtReaderPagedChapterContent")
    }

    // MARK: - Pagination

    /// (Re)paginates the current chapter's attributed string for the paged
    /// renderer. Runs on first appearance, on viewport changes, and after a
    /// cross-chapter load (driven from the main file's `.task(id:)` via the
    /// chapter attrString change).
    ///
    /// Codex Gate-4 Round-1 (High #1 + #2): a queued `pendingPagedLanding` is
    /// applied ONLY when its `targetChapterIndex` matches the chapter the view
    /// model has actually loaded. A landing whose target does not match the
    /// current chapter (a failed/aborted load, or an intermediate chapter from
    /// a rapid double-tap) is left queued — it is never mis-applied to the
    /// wrong chapter, and the matching rebuild consumes it when it arrives.
    func repaginatePagedChapter(viewportSize: CGSize) {
        guard isPagedChapterMode, let attrStr = chapterAttrString else { return }

        let landingMatchesCurrentChapter =
            pendingPagedLanding?.targetChapterIndex == viewModel.currentChapterIdx

        let nav = uiState.pageNavigator ?? NativeTextPageNavigator()
        nav.paginateAttributed(attributedText: attrStr, viewportSize: viewportSize)

        // First-paginate of the INITIAL chapter restores the saved local
        // offset. Gated on no pending cross-chapter landing so a queued cross
        // never also applies the restore offset.
        if uiState.pageNavigator == nil, pendingPagedLanding == nil,
           let offset = initialRestoreOffset {
            nav.jumpToOffset(utf16Offset: offset)
        }
        uiState.pageNavigator = nav

        // Apply the queued landing only for the chapter it targeted.
        if let landing = pendingPagedLanding, landingMatchesCurrentChapter {
            let page: Int
            switch landing.edge {
            case .firstPage:
                page = TXTPagedChapterAdvance.landingPageForwardCross(newTotalPages: nav.totalPages)
            case .lastPage:
                page = TXTPagedChapterAdvance.landingPageBackwardCross(newTotalPages: nav.totalPages)
            }
            nav.jumpToPage(page)
            pendingPagedLanding = nil
        }

        if let offset = uiState.syncPagedState() {
            viewModel.updateScrollPosition(charOffsetUTF16: offset)
        }
    }

    // MARK: - Cross-chapter advance

    /// Handles `.readerNextPage` in paged chapter mode. Within-chapter turns
    /// delegate to the navigator; a last-page turn loads the next chapter (then
    /// the `.task(id:)` rebuild re-paginates and the matching
    /// `pendingPagedLanding` lands on its first page); a last-page-of-last-
    /// chapter turn clamps (bounce).
    ///
    /// Codex Gate-4 Round-1 (High #1 + #2): the landing carries its target
    /// chapter index and is OVERWRITTEN on each cross (never silently stacked).
    /// Application is gated by `targetChapterIndex == currentChapterIdx` in
    /// `repaginatePagedChapter`, so a failed load (index unchanged → no match,
    /// and no hard in-flight latch to deadlock) or an intermediate chapter from
    /// a rapid tap never consumes a landing meant for a different chapter. A
    /// rapid double-tap advancing two chapters is intended (two taps = two
    /// turns); each landing is consumed only by its own target's rebuild.
    func handlePagedNextPage() {
        guard isPagedChapterMode else { return }
        let nav = uiState.pageNavigator
        let decision = TXTPagedChapterAdvance.next(
            currentPage: nav?.currentPage ?? 0,
            totalPages: nav?.totalPages ?? 0,
            hasNextChapter: viewModel.hasNextChapter
        )
        switch decision {
        case .withinChapter:
            nav?.nextPage()
            if let offset = uiState.syncPagedState() {
                viewModel.updateScrollPosition(charOffsetUTF16: offset)
            }
        case .crossToNextChapter:
            pendingPagedLanding = TXTPagedLanding(
                targetChapterIndex: viewModel.currentChapterIdx + 1, edge: .firstPage
            )
            Task { await viewModel.nextChapter() }
        case .clampAtDocumentEnd, .clampAtDocumentStart:
            break // Bounce / no-op at the boundary.
        case .crossToPreviousChapter:
            break // unreachable for a forward turn
        }
        uiState.autoPageTurner?.pause()
    }

    /// Handles `.readerPreviousPage` in paged chapter mode. Symmetric to
    /// `handlePagedNextPage`: a first-page turn loads the previous chapter and
    /// lands on its last page; a first-page-of-first-chapter turn clamps.
    func handlePagedPreviousPage() {
        guard isPagedChapterMode else { return }
        let nav = uiState.pageNavigator
        let decision = TXTPagedChapterAdvance.previous(
            currentPage: nav?.currentPage ?? 0,
            totalPages: nav?.totalPages ?? 0,
            hasPreviousChapter: viewModel.hasPreviousChapter
        )
        switch decision {
        case .withinChapter:
            nav?.previousPage()
            if let offset = uiState.syncPagedState() {
                viewModel.updateScrollPosition(charOffsetUTF16: offset)
            }
        case .crossToPreviousChapter:
            pendingPagedLanding = TXTPagedLanding(
                targetChapterIndex: viewModel.currentChapterIdx - 1, edge: .lastPage
            )
            Task { await viewModel.previousChapter() }
        case .clampAtDocumentStart, .clampAtDocumentEnd:
            break
        case .crossToNextChapter:
            break // unreachable for a backward turn
        }
        uiState.autoPageTurner?.pause()
    }

    // MARK: - Chrome-aware viewport helpers
    //
    // Mirror `MDReaderContainerView`'s extracted `static` formulas (design
    // §3.1 / §3.2) so the paginator's `NSTextContainer` is sized to the
    // renderer's actual interior box. Duplicated rather than shared because
    // the two containers are independent value types; the formula is identical
    // and locked by `TXTReaderContainerViewPagedLayoutTests`.

    /// Chrome-aware bottom inset: chrome-visible reserves the chrome height +
    /// 8pt breath; chrome-hidden uses the design's 56pt baseline.
    static func pagedBottomPadding(chromeVisible: Bool) -> CGFloat {
        chromeVisible ? 128 + 8 : 56
    }

    /// Effective per-page viewport: proxy minus the chrome-aware bottom
    /// padding, the page-indicator reservation (chrome-hidden only), and the
    /// paged textView's `textContainerInset` on both axes. Clamped positive.
    static func paginatorViewportSize(proxy: CGSize, chromeVisible: Bool) -> CGSize {
        let bottomPad = pagedBottomPadding(chromeVisible: chromeVisible)
        let indicatorHeight: CGFloat = chromeVisible ? 0 : 24
        let inset = NativePagedContainer.textInset
        let width = max(proxy.width - 2 * inset, 1)
        let height = max(proxy.height - bottomPad - indicatorHeight - 2 * inset, 1)
        return CGSize(width: width, height: height)
    }
}
#endif
