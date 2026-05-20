// Purpose: UITableView-based chunked text renderer for large TXT files.
// Each cell renders one text chunk as a UITextView, avoiding a single
// massive NSAttributedString that chokes TextKit 1.
//
// Key decisions:
// - UITableView with self-sizing cells (UITableView.automaticDimension).
// - Each cell contains a non-editable UITextView for text selection support.
// - NSAttributedString built lazily per cell, cached in an LRU dictionary.
// - Scroll position tracked via visible cells → chunk index → character offset.
// - Supports restoring scroll position to a character offset on load.
//
// @coordinates-with: TXTChunkedHighlightHelper.swift, TXTTextChunker.swift,
//   TXTAttributedStringBuilder.swift, TXTReaderContainerView.swift, TXTViewConfig.swift,
//   ReaderNotifications.swift (observes .searchHighlightClear — bug #232 / GH #960)

#if canImport(UIKit)
import SwiftUI
import UIKit

/// UIViewRepresentable wrapping a UITableView that renders text in chunks.
/// Designed for large files where a single UITextView would be too slow.
struct TXTChunkedReaderBridge: UIViewRepresentable {
    let chunks: [String]
    let config: TXTViewConfig
    var restoreChunkIndex: Int?
    var restoreIntraChunkOffset: CGFloat?
    weak var delegate: TXTTextViewBridgeDelegate?

    /// Character offsets at the start of each chunk (cumulative UTF-16 lengths).
    let chunkStartOffsets: [Int]

    /// Dynamic navigation target (document-global UTF-16 offset). Set by container
    /// view when navigating from annotation panel, search results, etc. (bug #52)
    var scrollToOffset: Int?

    /// Highlight range (document-global UTF-16) for visual feedback. (bug #53)
    var highlightRange: NSRange?
    /// Whether the current highlight is temporary (search navigation) vs persistent
    /// (user-created). Temporary highlights auto-clear after 3s. (bug #54)
    var highlightIsTemporary: Bool = true
    /// Monotonic navigate-event counter (Bug #154 / GH #443). Mirrors the
    /// non-chunked `TXTTextViewBridge`'s same-named param: a search-tap to an
    /// already-current target re-sets `highlightRange` to a value it already
    /// holds, so the range diff alone never re-applies the highlight. The
    /// container bumps this nonce on every navigate event; a nonce change is
    /// folded into the bridge's highlight-change detection so a repeat-nav
    /// re-paints + re-arms the 3 s auto-clear timer.
    var highlightNonce: Int = 0
    /// Persisted highlights (document-global UTF-16) loaded from DB (bug #55).
    /// Each carries its stored color (Bug #208).
    var persistedHighlights: [PaintedHighlight] = []
    /// Persisted highlight lookup keyed by UUID — global UTF-16 ranges plus
    /// their highlight IDs, used by the tap-on-highlight hit-tester.
    /// Feature #53 WI-3. When empty, tap-on-highlight is dormant (the gesture
    /// falls through to the existing chrome-toggle behavior).
    var persistedHighlightLookup: [PersistedHighlightLookupEntry] = []
    /// Bug #154 / GH #443 (Codex audit): invoked when the 3 s auto-clear timer
    /// expires a *temporary* search/navigation highlight. The container wires
    /// this to nil `uiState.highlightRange` so the model and the coordinator's
    /// `lastHighlightRange` clear together — otherwise a later font/theme
    /// `updateUIView` re-paints the already-expired highlight from a stale
    /// `uiState`. Mirrors the non-chunked `TXTTextViewBridge` param.
    var onTemporaryHighlightCleared: (@MainActor () -> Void)?
    /// Top safe-area inset applied to the UITableView's `contentInset.top` so
    /// the first chunk renders below the Dynamic Island. Bug #179 (mirrors
    /// the non-chunked path's same-named param). Default `0` preserves prior
    /// behaviour for callers not yet threaded through.
    var safeAreaTopInset: CGFloat = 0

    /// Bug #180 (continuous-scroll re-scoped fix): chapter-awareness layer for
    /// chaptered TXT rendered as one continuous surface. `nil` for the legacy
    /// large-file (non-chaptered) caller — that path is unchanged. When
    /// non-nil, `chunkStartOffsets` already ARE document-global offsets, so
    /// the container derives the chapter from the reported scroll offset; the
    /// bridge's offset math is identical either way.
    var chapterOffsetIndex: TXTChapterOffsetIndex?

    /// Bug #180: document-global UTF-16 offset to restore the scroll to on
    /// first layout. Preferred over the fraction-based `restoreChunkIndex` /
    /// `restoreIntraChunkOffset` for accurate cross-chapter restore. `nil`
    /// leaves the table at the top (the legacy large-file caller passes
    /// `restoreChunkIndex` instead and leaves this nil).
    var restoreGlobalOffset: Int?

    /// Bug #239 — current reader layout preference. Threaded through to the
    /// coordinator on each `makeUIView` / `updateUIView` so the content-tap
    /// handler can route side-zone taps to `.readerNextPage` /
    /// `.readerPreviousPage` in `.paged` layout. In `.scroll` (the chunked
    /// renderer's natural mode) every tap collapses to
    /// `.readerContentTapped` per the legacy chrome-toggle contract.
    var layout: EPUBLayoutPreference?

    func makeCoordinator() -> Coordinator {
        Coordinator(delegate: delegate)
    }

    // MARK: - Chunk Resolution (pure, testable)

    /// Resolves a document-global UTF-16 offset to the index of the chunk
    /// containing it. Binary search over `chunkStartOffsets`; clamps to
    /// `[0, count-1]`. Returns `nil` for an empty offsets array.
    /// Bug #180: shared by `restoreGlobalOffset` routing and
    /// `scrollToGlobalOffset`; extracted as a pure static for unit testing.
    static func chunkIndex(
        forGlobalOffset globalOffset: Int, chunkStartOffsets: [Int]
    ) -> Int? {
        guard !chunkStartOffsets.isEmpty else { return nil }
        var lo = 0
        var hi = chunkStartOffsets.count - 1
        while lo < hi {
            let mid = (lo + hi + 1) / 2
            if chunkStartOffsets[mid] <= globalOffset {
                lo = mid
            } else {
                hi = mid - 1
            }
        }
        return lo
    }

    /// Computes the intra-chunk fraction (0.0–1.0) of a document-global offset
    /// within its chunk. Bug #180: extracted as a pure static for testing.
    static func intraChunkFraction(
        forGlobalOffset globalOffset: Int,
        chunkIndex: Int,
        chunkStartOffsets: [Int],
        chunkUTF16Lengths: [Int]
    ) -> CGFloat {
        guard chunkIndex >= 0, chunkIndex < chunkStartOffsets.count,
              chunkIndex < chunkUTF16Lengths.count else { return 0 }
        let chunkStart = chunkStartOffsets[chunkIndex]
        let chunkLen = chunkUTF16Lengths[chunkIndex]
        guard chunkLen > 0 else { return 0 }
        let local = CGFloat(globalOffset - chunkStart)
        return max(0, min(1, local / CGFloat(chunkLen)))
    }

    func makeUIView(context: Context) -> UITableView {
        let tableView = UITableView(frame: .zero, style: .plain)
        tableView.register(ChunkedTextCell.self, forCellReuseIdentifier: ChunkedTextCell.reuseID)
        tableView.dataSource = context.coordinator
        tableView.delegate = context.coordinator
        tableView.separatorStyle = .none
        tableView.allowsSelection = false
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 800
        tableView.backgroundColor = config.backgroundColor
        tableView.showsVerticalScrollIndicator = true
        tableView.accessibilityIdentifier = "chunkedTextTableView"
        // Bug #179: lift the first chunk below the Dynamic Island. Setting
        // `contentInset.top` on the UITableView (not the per-cell inset)
        // keeps cell sizing/highlight math unchanged.
        tableView.contentInset.top = max(0, safeAreaTopInset)
        tableView.contentInsetAdjustmentBehavior = .never

        context.coordinator.chunks = chunks
        context.coordinator.config = config
        context.coordinator.chunkStartOffsets = chunkStartOffsets
        context.coordinator.persistedHighlights = persistedHighlights
        context.coordinator.persistedHighlightLookup = persistedHighlightLookup
        context.coordinator.onTemporaryHighlightCleared = onTemporaryHighlightCleared
        context.coordinator.delegate = delegate
        // Bug #239 — seed the layout snapshot so the very first tap honors
        // the current paged/scroll mode.
        context.coordinator.pagedLayout = layout
        // Bug #232 / GH #960: hand the coordinator a table-view handle so its
        // `.searchHighlightClear` observer can route the clear.
        context.coordinator.tableView = tableView

        // Tap gesture for toolbar toggle
        let tapRecognizer = UITapGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleContentTap)
        )
        tapRecognizer.delegate = context.coordinator
        tableView.addGestureRecognizer(tapRecognizer)

        // Feature #64 WI-6: the feature #53 highlight long-press gesture (which
        // opened the bare delete `UIMenu`) is removed. A *tap* on a highlight
        // posts `.readerHighlightTapped`, observed by the unified
        // highlight-action popover — its action row carries Delete.

        // Restore scroll position — asyncAfter allows SwiftUI to size the table view
        // before scrolling. In makeUIView the view has no frame yet.
        // The coordinator retries if the view still has no valid frame (bug #23).
        //
        // Bug #180 (continuous-scroll re-scoped fix): when the container passes
        // a document-global `restoreGlobalOffset` (continuous chaptered TXT),
        // route it through `scrollToGlobalOffset` — which binary-searches the
        // containing chunk and applies the intra-chunk fraction. This is
        // accurate across chapter boundaries because chunk offsets and the
        // restore offset live in the same document-global space. The
        // fraction-based `restoreChunkIndex` path stays for the legacy
        // large-file caller (mutually exclusive — that caller leaves
        // `restoreGlobalOffset` nil).
        if let globalOffset = restoreGlobalOffset, globalOffset > 0 {
            let coordinator = context.coordinator
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak tableView] in
                guard let tableView else { return }
                coordinator.scrollToGlobalOffset(globalOffset, in: tableView)
            }
        } else if let chunkIdx = restoreChunkIndex, chunkIdx < chunks.count {
            let coordinator = context.coordinator
            let intraFraction = restoreIntraChunkOffset
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak tableView] in
                guard let tableView else { return }
                coordinator.attemptChunkRestore(
                    in: tableView,
                    toChunkIndex: chunkIdx,
                    intraFraction: intraFraction
                )
            }
        }

        return tableView
    }

    func updateUIView(_ tableView: UITableView, context: Context) {
        context.coordinator.delegate = delegate
        // Feature #64 WI-6: refresh tap-on-highlight inputs every update so
        // late-arriving highlights (created after the bridge was first
        // installed) become tap-targetable as soon as the lookup grows. The
        // tap posts `.readerHighlightTapped` for the unified popover.
        context.coordinator.persistedHighlightLookup = persistedHighlightLookup
        context.coordinator.onTemporaryHighlightCleared = onTemporaryHighlightCleared
        // Bug #239 — keep the layout snapshot current so a user toggling
        // Paged ↔ Scroll mid-session re-routes the next tap immediately.
        context.coordinator.pagedLayout = layout
        // Bug #232 / GH #960: keep the coordinator's table-view handle current
        // so the `.searchHighlightClear` observer always routes to the live
        // view.
        context.coordinator.tableView = tableView

        // Bug #179: re-apply safe-area top inset on every update (rotation,
        // split-screen resize, etc. can change `proxy.safeAreaInsets.top`).
        let clamped = max(0, safeAreaTopInset)
        if tableView.contentInset.top != clamped {
            tableView.contentInset.top = clamped
        }

        // Sync chunks and offsets if they changed (e.g., parent rebuilt chunks)
        let chunksChanged = context.coordinator.chunks.count != chunks.count
        if chunksChanged {
            context.coordinator.chunks = chunks
            context.coordinator.chunkStartOffsets = chunkStartOffsets
            context.coordinator.attrStringCache.removeAll()
            tableView.reloadData()
        }

        let configChanged = !context.coordinator.config.renderingEquals(config)
        if configChanged {
            context.coordinator.config = config
            context.coordinator.attrStringCache.removeAll()
            tableView.backgroundColor = config.backgroundColor
            tableView.reloadData()
        }

        // Dynamic navigation from annotation panel, search, etc. (bug #52)
        if let offset = scrollToOffset,
           offset != context.coordinator.lastScrollToOffset {
            context.coordinator.lastScrollToOffset = offset
            context.coordinator.scrollToGlobalOffset(offset, in: tableView)
        }

        // Sync persisted highlights via layout manager on visible cells (bug #55, bug #47 v12)
        if context.coordinator.persistedHighlights != persistedHighlights {
            context.coordinator.persistedHighlights = persistedHighlights
            for cell in tableView.visibleCells {
                guard let chunkedCell = cell as? TXTChunkedReaderBridge.ChunkedTextCell else { continue }
                let chunkIndex = chunkedCell.textContentView.tag
                let (persisted, active) = context.coordinator.chunkLocalHighlightRanges(forChunk: chunkIndex)
                chunkedCell.textContentView.setHighlightRanges(persisted: persisted, active: active)
            }
        }

        // Highlight range for visual feedback (bug #53).
        // Bug #154 / GH #443: fold a navigate-nonce change into the change
        // signal — a repeat-nav to an already-current target leaves
        // `highlightRange` byte-for-byte identical, so the range diff alone
        // would skip the re-paint and never re-arm the 3 s auto-clear timer.
        let nonceChanged = highlightNonce != context.coordinator.lastHighlightNonce
        if TXTTextViewBridge.highlightShouldReapply(
            rangeChanged: highlightRange != context.coordinator.lastHighlightRange,
            nonceChanged: nonceChanged
        ) {
            // Clear previous highlight
            context.coordinator.clearHighlight(in: tableView)
            context.coordinator.lastHighlightRange = highlightRange
            context.coordinator.lastHighlightNonce = highlightNonce
            if let range = highlightRange {
                context.coordinator.applyHighlight(range, in: tableView, isTemporary: highlightIsTemporary)
            }
        }
    }

    // MARK: - Cell

    final class ChunkedTextCell: UITableViewCell {
        static let reuseID = "ChunkedTextCell"

        let textContentView: HighlightableTextView = {
            let tv = HighlightableTextView()
            tv.isEditable = false
            tv.isSelectable = true
            tv.isScrollEnabled = false
            tv.textContainerInset = UIEdgeInsets(top: 0, left: 16, bottom: 0, right: 16)
            tv.textContainer.lineFragmentPadding = 0
            tv.translatesAutoresizingMaskIntoConstraints = false
            tv.backgroundColor = .clear
            return tv
        }()

        override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
            super.init(style: style, reuseIdentifier: reuseIdentifier)
            backgroundColor = .clear
            contentView.backgroundColor = .clear
            contentView.addSubview(textContentView)
            NSLayoutConstraint.activate([
                textContentView.topAnchor.constraint(equalTo: contentView.topAnchor),
                textContentView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
                textContentView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
                textContentView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            ])
        }

        required init?(coder: NSCoder) { fatalError() }
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject, UITableViewDataSource, UITableViewDelegate, UIGestureRecognizerDelegate, UITextViewDelegate {
        var chunks: [String] = []
        var config = TXTViewConfig()
        var chunkStartOffsets: [Int] = []
        /// Persisted highlights (document-global UTF-16) from DB (bug #55).
        /// Each carries its stored color (Bug #208).
        var persistedHighlights: [PaintedHighlight] = []
        /// Lookup table (UUID, global UTF-16 range) used by the tap-on-
        /// highlight hit-tester. Feeds the `.readerHighlightTapped` post.
        var persistedHighlightLookup: [PersistedHighlightLookupEntry] = []
        weak var delegate: TXTTextViewBridgeDelegate?

        /// LRU cache for attributed strings keyed by chunk index.
        var attrStringCache: [Int: NSAttributedString] = [:]
        private static let maxCacheSize = 20

        /// Throttle scroll callbacks.
        private var lastScrollTime: CFTimeInterval = 0
        private static let scrollThrottleInterval: CFTimeInterval = 0.1

        /// Retry counter for scroll restore when view has no valid frame yet.
        private var restoreRetryCount = 0
        private static let maxRestoreRetries = 5

        /// Tracks last processed scrollToOffset to avoid redundant scrolls (bug #52).
        var lastScrollToOffset: Int?

        /// Tracks last processed highlightRange to avoid redundant applications (bug #53).
        var lastHighlightRange: NSRange?

        /// Last navigate-nonce consumed (Bug #154 / GH #443). When the
        /// container's `highlightNonce` differs from this, a navigate event
        /// occurred — re-paint the temporary highlight + re-arm the 3 s
        /// auto-clear timer even if `lastHighlightRange` is unchanged.
        var lastHighlightNonce: Int = 0

        /// Bug #154 / GH #443 (Codex audit): fired whenever a temporary
        /// search/navigation highlight is cleared — the 3 s auto-clear timer,
        /// a user-driven scroll, or the `.searchHighlightClear` notification
        /// (bug #232 / GH #960). The container wires it to nil
        /// `uiState.highlightRange` so model + coordinator clear in lockstep.
        var onTemporaryHighlightCleared: (@MainActor () -> Void)?

        /// Whether the current active highlight is a temporary
        /// search/navigation highlight (`true`) or a persistent user-created
        /// one (`false`). Bug #232 / GH #960: only temporary highlights clear
        /// on a new search or a user scroll — a persistent highlight must
        /// survive both. Set by `applyHighlight(isTemporary:)`, reset by
        /// `clearHighlight`. Mirrors the non-chunked coordinator, where the
        /// temporary highlight lives in `currentHighlightRange` and persistent
        /// ones live separately in `persistedHighlights`.
        var activeHighlightIsTemporary = false

        /// The table view this coordinator drives. Bug #232 / GH #960: the
        /// `.searchHighlightClear` observer (registered in `init`) needs a
        /// table-view handle to route the clear through. Set by
        /// `makeUIView` / `updateUIView`. Weak — the table view owns the
        /// coordinator via `UIViewRepresentable.Context`, not vice versa.
        weak var tableView: UITableView?

        /// Bug #239 — current layout preference, mirrored from the bridge's
        /// `layout` parameter on every `updateUIView`. The chunked TXT
        /// content-tap handler consults this via `ReaderTapZoneRouter` so a
        /// side-tap in `.paged` layout posts `.readerNextPage` /
        /// `.readerPreviousPage` instead of toggling chrome. In `.scroll`
        /// (the chunked TXT renderer's default mode, since its surface is
        /// inherently scroll-based) every tap collapses to
        /// `.readerContentTapped` — preserving the chrome-toggle behavior.
        var pagedLayout: EPUBLayoutPreference?

        /// Observation token for the `.searchHighlightClear` notification
        /// (bug #232 / GH #960). `nonisolated(unsafe)` so `deinit` (which is
        /// nonisolated) can read it for `removeObserver`.
        nonisolated(unsafe) var highlightClearObserver: NSObjectProtocol?

        /// Timer to auto-clear highlight after a delay.
        /// Internal access needed by TXTChunkedHighlightHelper extension.
        var highlightClearTimer: Timer?

        /// Bug #99 cause #1: chunk index whose first render should
        /// kick off the auto-clear timer. When `applyHighlight` is
        /// called and the destination cell isn't visible, starting
        /// the 3 s timer immediately can race the scroll completion
        /// (cell becomes visible AFTER timer fires → highlight is
        /// cleared before user sees it). Setting this flag instead
        /// defers timer start to `cellForRowAt`, which fires when
        /// the cell actually renders.
        var pendingAutoClearForChunk: Int?

        init(delegate: TXTTextViewBridgeDelegate?) {
            self.delegate = delegate
            super.init()

            // Bug #232 / GH #960: observe `.searchHighlightClear` so a new
            // search dismisses a temporary search/navigation highlight
            // immediately, matching the non-chunked `TXTTextViewBridge`
            // coordinator. Pre-fix this `init` was bare and the chunked path
            // cleared a temporary highlight ONLY via the 3 s auto-clear timer.
            highlightClearObserver = NotificationCenter.default.addObserver(
                forName: .searchHighlightClear, object: nil, queue: .main
            ) { [weak self] _ in
                // A new search is not a scroll — clear unconditionally
                // (scrollView: nil), gated only on there being a temporary
                // highlight to clear.
                self?.clearTemporaryHighlightIfNeeded(scrollView: nil)
            }
        }

        deinit {
            // Coordinator is @MainActor-isolated via its UIKit delegate
            // conformances; deinit is nonisolated. Use assumeIsolated to
            // satisfy strict concurrency for non-Sendable property access.
            MainActor.assumeIsolated {
                if let observer = highlightClearObserver {
                    NotificationCenter.default.removeObserver(observer)
                }
                highlightClearTimer?.invalidate()
                highlightClearTimer = nil
            }
        }


        /// Restores scroll to a chunk index with optional intra-chunk fraction (0-1),
        /// retrying if the table view has no valid frame.
        func attemptChunkRestore(
            in tableView: UITableView,
            toChunkIndex index: Int,
            intraFraction: CGFloat? = nil
        ) {
            guard index >= 0, index < chunks.count else { return }

            guard tableView.bounds.width > 0 else {
                guard restoreRetryCount < Self.maxRestoreRetries else { return }
                restoreRetryCount += 1
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self, weak tableView] in
                    guard let self, let tableView else { return }
                    self.attemptChunkRestore(in: tableView, toChunkIndex: index, intraFraction: intraFraction)
                }
                return
            }

            tableView.scrollToRow(
                at: IndexPath(row: index, section: 0),
                at: .top,
                animated: false
            )

            // Adjust for intra-chunk position
            if let fraction = intraFraction, fraction > 0 {
                let cellRect = tableView.rectForRow(at: IndexPath(row: index, section: 0))
                if cellRect.height > 0 {
                    tableView.contentOffset.y += cellRect.height * fraction
                }
            }
        }

        // MARK: UITableViewDataSource

        func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
            chunks.count
        }

        func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
            guard let cell = tableView.dequeueReusableCell(
                withIdentifier: ChunkedTextCell.reuseID,
                for: indexPath
            ) as? ChunkedTextCell else {
                return UITableViewCell()
            }

            let index = indexPath.row
            // Set source text and highlight ranges separately (bug #47 v12).
            // Source text via setSourceText, highlights via layout manager drawing.
            // NEVER modify text storage for highlights — that crashes with active selection.
            let baseAttr = attributedString(forChunk: index)
            cell.textContentView.setSourceText(baseAttr)
            let (persisted, active) = chunkLocalHighlightRanges(forChunk: index)
            cell.textContentView.setHighlightRanges(persisted: persisted, active: active)
            cell.textContentView.backgroundColor = config.backgroundColor
            cell.textContentView.delegate = self
            cell.textContentView.tag = index  // Store chunk index for offset calculation

            // Bug #99 cause #1: kick off the deferred auto-clear timer
            // when the chunk that owns the active highlight finally
            // renders. Pre-fix: timer started in applyHighlight even
            // when cell wasn't visible — slow scroll could let the
            // timer fire before the user saw the highlight.
            if let pending = pendingAutoClearForChunk, pending == index, active != nil {
                pendingAutoClearForChunk = nil
                startHighlightAutoClearTimer(in: tableView)
            }

            return cell
        }

        // MARK: UITableViewDelegate

        func scrollViewDidScroll(_ scrollView: UIScrollView) {
            // Bug #232 / GH #960: clear a temporary search/navigation
            // highlight when the user drives the scroll. The helper gates on
            // `isTracking || isDragging || isDecelerating`, so programmatic
            // scrolls (and the late layout-driven callbacks they dispatch)
            // are correctly skipped. Runs before the throttle so a quick
            // flick still dismisses the highlight.
            clearTemporaryHighlightIfNeeded(scrollView: scrollView)

            let now = CACurrentMediaTime()
            guard now - lastScrollTime >= Self.scrollThrottleInterval else { return }
            lastScrollTime = now
            reportScrollPosition(scrollView)
        }

        func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
            reportScrollPosition(scrollView)
        }

        func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
            // Bug #232 / GH #960: also clear on a drag that ends without
            // deceleration — the user has finished a scroll gesture, so a
            // lingering temporary highlight should go. `isDragging` is still
            // true inside this callback, so the helper's user-scroll guard
            // passes.
            if !decelerate {
                clearTemporaryHighlightIfNeeded(scrollView: scrollView)
                reportScrollPosition(scrollView)
            }
        }

        // MARK: - Content Tap (Toolbar Toggle / Tap-on-Highlight)

        @objc func handleContentTap(_ gesture: UITapGestureRecognizer) {
            // Feature #64 WI-6: if the tap lands inside a persisted highlight
            // range, fire `.readerHighlightTapped` instead of toggling chrome.
            // A tap on a highlight opens the unified highlight-action popover
            // (via `HighlightPopoverModifier`) — its action row carries
            // Delete. Lookup-empty short-circuit keeps non-highlight callers
            // cost-free.
            if let tableView = gesture.view as? UITableView,
               !persistedHighlightLookup.isEmpty,
               let event = Self.resolveChunkedHighlightTap(
                   gesture: gesture,
                   in: tableView,
                   chunkStartOffsets: chunkStartOffsets,
                   lookup: persistedHighlightLookup
               ) {
                NotificationCenter.default.post(
                    name: .readerHighlightTapped, object: event
                )
                return
            }
            // Bug #239 — restore side-tap → page-turn for the chunked TXT
            // surface. Mirrors `TXTTextViewBridgeCoordinator.handleContentTap`:
            // in `.paged` layout the router posts `.readerNextPage` /
            // `.readerPreviousPage`; in `.scroll` / nil it collapses to
            // `.readerContentTapped` (the legacy chrome-toggle).
            if let tableView = gesture.view as? UITableView {
                let location = gesture.location(in: tableView)
                ReaderTapZoneRouter.dispatch(
                    x: location.x,
                    totalWidth: tableView.bounds.width,
                    layout: pagedLayout
                )
            } else {
                TXTBridgeShared.postContentTappedNotification()
            }
        }

        // MARK: - Tap-on-Highlight Resolution

        /// Resolves a gesture-driven tap into a `ReaderHighlightTapEvent`
        /// by walking from `UITableView` → containing cell → embedded
        /// `UITextView` → chunk-local char index → global char index →
        /// `TextHighlightHitTester`. Returns nil when the tap misses every
        /// persisted range (caller falls back to chrome-toggle).
        ///
        /// Extracted as static + internal so unit tests can drive it without
        /// going through a live `UITapGestureRecognizer`.
        /// `gesture` is `UIGestureRecognizer` (the base type) so both the
        /// tap recognizer (chrome-toggle / #55 note preview) and feature #55
        /// WI-6's long-press recognizer (#53 delete menu) can drive the same
        /// hit-test — both expose `location(in:)`.
        @MainActor
        static func resolveChunkedHighlightTap(
            gesture: UIGestureRecognizer,
            in tableView: UITableView,
            chunkStartOffsets: [Int],
            lookup: [PersistedHighlightLookupEntry]
        ) -> ReaderHighlightTapEvent? {
            guard !lookup.isEmpty else { return nil }
            let tapPointInTable = gesture.location(in: tableView)
            guard let indexPath = tableView.indexPathForRow(at: tapPointInTable),
                  let cell = tableView.cellForRow(at: indexPath) as? ChunkedTextCell
            else { return nil }
            let textView = cell.textContentView
            let tapPointInCell = tableView.convert(tapPointInTable, to: textView)
            guard let event = resolveChunkedHighlightTap(
                tapPointInCell: tapPointInCell,
                in: textView,
                chunkIndex: indexPath.row,
                chunkStartOffsets: chunkStartOffsets,
                lookup: lookup
            ) else { return nil }
            // Per Bug #203 (GH #743): the pure-point overload returns rects
            // in textView-local coords. Convert to tableView-local here
            // because the presenter is `present(for:in: tableView)` and
            // `UIEditMenuConfiguration.sourcePoint` expects coordinates in
            // the interaction-view's (tableView's) space.
            let tableViewRect = textView.convert(event.sourceRect, to: tableView)
            return ReaderHighlightTapEvent(
                highlightID: event.highlightID, sourceRect: tableViewRect
            )
        }

        /// Pure-point overload. Tests construct a CGPoint + textView fixture
        /// directly without driving through a UITableView. The chunk-offset
        /// math is what's actually under test here — converting a
        /// chunk-local character index into a document-global one before
        /// hitting `TextHighlightHitTester`.
        @MainActor
        static func resolveChunkedHighlightTap(
            tapPointInCell: CGPoint,
            in textView: UITextView,
            chunkIndex: Int,
            chunkStartOffsets: [Int],
            lookup: [PersistedHighlightLookupEntry]
        ) -> ReaderHighlightTapEvent? {
            guard !lookup.isEmpty else { return nil }
            guard chunkIndex >= 0, chunkIndex < chunkStartOffsets.count else {
                return nil
            }
            let chunkOffset = chunkStartOffsets[chunkIndex]
            let inset = textView.textContainerInset
            let containerPoint = CGPoint(
                x: tapPointInCell.x - inset.left,
                y: tapPointInCell.y - inset.top
            )
            let lm = textView.layoutManager
            let chunkLocalCharIndex = lm.characterIndex(
                for: containerPoint,
                in: textView.textContainer,
                fractionOfDistanceBetweenInsertionPoints: nil
            )
            let globalCharIndex = chunkOffset + chunkLocalCharIndex
            guard let hit = TextHighlightHitTester.hitTest(
                charIndex: globalCharIndex, in: lookup
            ) else { return nil }
            // The global range may straddle chunk boundaries; clip to this
            // chunk's local extent so the source rect anchors above the
            // visible slice in THIS cell, not above content the user can't
            // see (which would put the menu off-screen).
            let chunkLength = textView.textStorage.length
            let localStart = max(0, hit.range.location - chunkOffset)
            let localEnd = min(
                chunkLength, hit.range.location + hit.range.length - chunkOffset
            )
            let localLen = localEnd - localStart
            guard localLen > 0 else { return nil }
            let localRange = NSRange(location: localStart, length: localLen)
            let glyphRange = lm.glyphRange(
                forCharacterRange: localRange, actualCharacterRange: nil
            )
            let containerRect = lm.boundingRect(
                forGlyphRange: glyphRange, in: textView.textContainer
            )
            // Per Bug #203 (GH #743): return textView-local coords. The
            // gesture-based wrapper above converts to tableView-local before
            // handing to the presenter (which uses the rect as the source
            // point for `UIEditMenuConfiguration` in the tableView's space).
            let viewRect = containerRect.offsetBy(
                dx: inset.left, dy: inset.top
            )
            return ReaderHighlightTapEvent(
                highlightID: hit.id, sourceRect: viewRect
            )
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            // Feature #64 WI-6: with the feature #53 highlight long-press
            // removed, the only custom recognizer is the content-tap, which
            // keeps the legacy "always simultaneous" answer alongside the
            // cell UITextView's native gestures.
            return TXTBridgeShared.gestureRecognizerShouldRecognizeSimultaneously()
        }

        // MARK: - UITextViewDelegate

        /// Tracks selection changes for feature parity with TXTTextViewBridge (bug #54).
        func textViewDidChangeSelection(_ textView: UITextView) {
            // Suppress during text replacement to prevent crash (bug #47 v11)
            if let htv = textView as? HighlightableTextView, htv.isReplacingText { return }
            let nsRange = textView.selectedRange
            guard nsRange.length > 0 else { return }
            let chunkIndex = textView.tag
            // Codex Gate 4 round 1 (Low) sibling of the editMenuForTextIn
            // fix: clamp negative tags too. Pre-WI-7c3 this was only
            // a class-of-bug concern; aligning the two sites keeps
            // them symmetric.
            let chunkOffset = (chunkIndex >= 0 && chunkIndex < chunkStartOffsets.count)
                ? chunkStartOffsets[chunkIndex]
                : 0
            // Convert chunk-local range to document-global UTF16Range
            let globalStart = chunkOffset + nsRange.location
            let globalEnd = globalStart + nsRange.length
            delegate?.selectionDidChange(utf16Range: UTF16Range(startUTF16: globalStart, endUTF16: globalEnd))
        }

        // Edit Menu (Bug #48)

        func textView(
            _ textView: UITextView,
            editMenuForTextIn range: NSRange,
            suggestedActions: [UIMenuElement]
        ) -> UIMenu? {
            // Feature #60 WI-7c3: chunked TXT bridge swap. Mirrors
            // WI-7c2's non-chunked swap — post
            // `.readerSelectionPopoverRequested` to the WI-7c1
            // presenter and return an empty UIMenu to suppress the
            // iOS surface. The chunked path differs only in needing
            // a chunk-offset translation: local NSRange in the
            // current `UITextView` (cell) → document-global UTF-16
            // range. `TXTBridgeShared.postSelectionNotification`'s
            // existing `chunkOffset:` parameter handles that.
            //
            // Why the `range.length > 0` guard: iOS calls this for
            // caret placement (zero-length range) too; no popover
            // should appear in that case. Returning the empty
            // UIMenu unconditionally still suppresses iOS's default.
            //
            // The `textView.tag` carries the chunk index (set by
            // `cellForRowAt`). Out-of-range tags fall back to
            // offset 0 — defensive but should never fire in
            // production.
            if range.length > 0 {
                let chunkIndex = textView.tag
                // Codex Gate 4 round 1 (Low): clamp on both ends.
                // `textView.tag` is `Int` and could in principle be
                // negative; the existing high-side check
                // `< chunkStartOffsets.count` doesn't protect
                // against subscripting with a negative index (which
                // would crash). In production `cellForRowAt`
                // always sets a non-negative tag, but defensive
                // coding earns its keep at the table-view boundary.
                let chunkOffset = (chunkIndex >= 0 && chunkIndex < chunkStartOffsets.count)
                    ? chunkStartOffsets[chunkIndex]
                    : 0
                TXTBridgeShared.postSelectionNotification(
                    .readerSelectionPopoverRequested,
                    from: textView,
                    range: range,
                    chunkOffset: chunkOffset
                )
            }
            return UIMenu(children: [])
        }

        // Dynamic navigation (scrollToGlobalOffset) and highlight methods
        // (applyHighlight, clearHighlight, chunkLocalHighlightRanges, rebuildHighlightCell)
        // are in TXTChunkedHighlightHelper.swift.

        /// Active highlight state for re-application on cell reuse (bug #54).
        /// Internal setter needed by TXTChunkedHighlightHelper extension.
        var activeHighlightChunkIndex: Int?
        var activeHighlightLocalRange: NSRange?

        // MARK: - Private

        private func attributedString(forChunk index: Int) -> NSAttributedString {
            if let cached = attrStringCache[index] { return cached }

            guard index >= 0, index < chunks.count else { return NSAttributedString() }
            let text = chunks[index]
            let attrStr = TXTAttributedStringBuilder.build(text: text, config: config)
            attrStringCache[index] = attrStr

            // Evict oldest entries if cache is too large
            if attrStringCache.count > Self.maxCacheSize {
                // Keep entries closest to the requested index
                let sorted = attrStringCache.keys.sorted { abs($0 - index) < abs($1 - index) }
                for key in sorted.dropFirst(Self.maxCacheSize) {
                    attrStringCache.removeValue(forKey: key)
                }
            }

            return attrStr
        }

        private func reportScrollPosition(_ scrollView: UIScrollView) {
            guard let tableView = scrollView as? UITableView else { return }
            guard let firstVisible = tableView.indexPathsForVisibleRows?.first else { return }
            let chunkIndex = firstVisible.row
            guard chunkIndex < chunkStartOffsets.count, chunkIndex < chunks.count else { return }

            // Estimate intra-chunk offset from scroll fraction through the cell
            let cellRect = tableView.rectForRow(at: firstVisible)
            var intraOffset = 0
            if cellRect.height > 0 {
                let scrolledPast = scrollView.contentOffset.y - cellRect.origin.y
                let fraction = max(0, min(1, scrolledPast / cellRect.height))
                intraOffset = Int(fraction * CGFloat(chunks[chunkIndex].utf16.count))
            }

            let offset = chunkStartOffsets[chunkIndex] + intraOffset
            delegate?.scrollPositionDidChange(topCharOffsetUTF16: offset)
        }
    }
}
#endif
