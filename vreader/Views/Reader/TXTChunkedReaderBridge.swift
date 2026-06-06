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
    /// Bug #1230 / GH #1230: Simplified↔Traditional conversion applied to the
    /// RENDERED chunk text only. Mirrors the paged path's precedent
    /// (TXTReaderContainerView ~line 437: "offsetMap discarded — reading
    /// positions and highlights in source-text coordinates remain valid"):
    /// SimpTrad is 1:1 UTF-16 for BMP CJK, so `chunks` / `chunkStartOffsets` /
    /// position math stay in SOURCE (raw) coordinates — only the display string
    /// is converted.
    var chineseConversion: ChineseConversionDirection = .none
    var restoreChunkIndex: Int?
    var restoreIntraChunkOffset: CGFloat?
    weak var delegate: TXTTextViewBridgeDelegate?

    /// Character offsets at the start of each chunk (cumulative UTF-16 lengths).
    let chunkStartOffsets: [Int]

    /// Dynamic navigation target (document-global UTF-16 offset). Set by container
    /// view when navigating from annotation panel, search results, etc. (bug #52)
    var scrollToOffset: Int?
    /// Bug #312: when true, the `scrollToOffset` jump pins the destination
    /// character to the TOP edge (TOC / chapter / bookmark) via the target
    /// glyph's rect, instead of the linear intra-chunk fraction tuned for
    /// search/restore.
    var scrollSnapToTop: Bool = false

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

    static func dismantleUIView(_ uiView: UITableView, coordinator: Coordinator) {
        // Bug #322 / GH #1542 (mirrors TXTTextViewBridge.dismantleUIView): cancel
        // any pending/in-flight locate bloom when the reader tears down, so a
        // queued work item doesn't fire against a detached table / cell.
        coordinator.cancelLandingBloom()
    }

    // MARK: - Chunk Resolution (pure, testable)

    /// Bug #1230 / GH #1230: per-chunk Simplified↔Traditional conversion for the
    /// RENDERED display text. Pure + static so it is unit-testable without a
    /// UITableView (`TXTChunkedReaderConversionTests`). The Coordinator's
    /// `attributedString(forChunk:)` calls this; the converted string feeds only
    /// the attributed-string builder. `chunkStartOffsets` / `chunkUTF16Lengths`
    /// stay in source coordinates — valid because SimpTrad is 1:1 UTF-16 for BMP
    /// CJK (same invariant the paged path relies on).
    nonisolated static func renderedChunkText(
        _ raw: String, conversion: ChineseConversionDirection
    ) -> String {
        conversion != .none
            ? TextMapper.apply(transforms: [SimpTradTransform(direction: conversion)], to: raw).text
            : raw
    }

    /// Bug #27 (chunked regression): is there a saved position to restore on
    /// open? When true the table is hidden (alpha 0) until restore lands, so the
    /// reader never paints chapter 1 then visibly jumps. False (no restore, or an
    /// out-of-range chunk index) → the table stays visible immediately.
    static func hasPendingRestore(
        restoreGlobalOffset: Int?, restoreChunkIndex: Int?, chunkCount: Int
    ) -> Bool {
        if let g = restoreGlobalOffset, g > 0 { return true }
        if let c = restoreChunkIndex, c >= 0, c < chunkCount { return true }
        return false
    }

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

    /// Bug #322 / GH #1542: resolves the matched locate-bloom highlight's
    /// document-global range to the cell that should bloom — its chunk index
    /// and the chunk-LOCAL `NSRange` to pass to that cell's
    /// `HighlightableTextView.playLandingBloom`. Mirrors the non-chunked path:
    /// `TXTTextViewBridge.landingTrigger` decides WHETHER to bloom (the nav
    /// range exactly matches a persisted highlight); this maps WHERE. Pure +
    /// static so it is unit-testable without a `UITableView`. Returns nil for an
    /// empty offsets array or a zero-length range (no glyph to wash).
    static func landingBloomTarget(
        matchedRange: NSRange, chunkStartOffsets: [Int]
    ) -> (chunkIndex: Int, chunkLocalRange: NSRange)? {
        guard matchedRange.length > 0,
              let chunkIndex = chunkIndex(
                  forGlobalOffset: matchedRange.location,
                  chunkStartOffsets: chunkStartOffsets
              ) else { return nil }
        let localStart = matchedRange.location - chunkStartOffsets[chunkIndex]
        guard localStart >= 0 else { return nil }
        return (
            chunkIndex,
            NSRange(location: localStart, length: matchedRange.length)
        )
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

    /// Bug #324 / GH #1546: applies the reader theme accent
    /// (`config.accentColor`) as the cell text view's `tintColor`, which drives
    /// the selection caret, grab handles, and selection-highlight color. Only
    /// assigns when the value differs, mirroring the bridge's existing
    /// `backgroundColor` re-apply discipline. Static + internal so it is unit-
    /// testable with a plain `UITextView` (no `UITableView` needed).
    static func applyTintColor(to textView: UITextView, config: TXTViewConfig) {
        if textView.tintColor != config.accentColor {
            textView.tintColor = config.accentColor
        }
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
        context.coordinator.chineseConversion = chineseConversion
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
        // Bug #27 (chunked regression): if there's a saved position to restore,
        // hide the table (alpha 0) so the deferred restore's scroll happens BEFORE
        // the reader is ever painted — otherwise SwiftUI commits a frame at
        // contentOffset 0 (chapter 1) and the user sees a flash + jump. Ported
        // from #27's original (non-chunked) alpha gate. `attemptChunkRestore`
        // reveals once the scroll settles; a safety timer guarantees the screen
        // is never left blank if restore can't land.
        let pendingRestore = Self.hasPendingRestore(
            restoreGlobalOffset: restoreGlobalOffset,
            restoreChunkIndex: restoreChunkIndex,
            chunkCount: chunks.count
        )
        if pendingRestore {
            tableView.alpha = 0
            let coordinator = context.coordinator
            // Safety net: never leave the content hidden if restore never lands.
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak tableView] in
                guard let tableView, tableView.alpha == 0 else { return }
                coordinator.revealContent(tableView)
            }
        }

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
        // Bug #1230 / GH #1230: a Simplified↔Traditional toggle re-renders every
        // chunk, so invalidate the cache + reload exactly like a config change.
        let conversionChanged = context.coordinator.chineseConversion != chineseConversion
        if configChanged || conversionChanged {
            context.coordinator.config = config
            context.coordinator.chineseConversion = chineseConversion
            context.coordinator.attrStringCache.removeAll()
            tableView.backgroundColor = config.backgroundColor
            tableView.reloadData()
        }

        // Dynamic navigation from annotation panel, search, etc. (bug #52)
        // Bug #312 (Codex Gate-4 MED): a snap-mode change re-arms the jump even to
        // the SAME offset (search headroom ⇄ TOC top-pin), so the new positioning
        // applies instead of being deduped away.
        if let offset = scrollToOffset,
           offset != context.coordinator.lastScrollToOffset
            || scrollSnapToTop != context.coordinator.lastSnapToTop {
            context.coordinator.lastScrollToOffset = offset
            context.coordinator.lastSnapToTop = scrollSnapToTop
            // Bug #312: a TOC / chapter / bookmark jump pins the destination
            // glyph to the top; a search hit keeps the linear intra-chunk fraction.
            context.coordinator.scrollToGlobalOffset(offset, in: tableView, snapToTop: scrollSnapToTop)
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

        scheduleLandingBloomIfNeeded(tableView: tableView, coordinator: context.coordinator)
    }

    /// Bug #322 / GH #1542: schedule the #74 locate bloom when a navigate lands
    /// on a SAVED highlight in the chunked reader — parity with the non-chunked
    /// `TXTTextViewBridge.updateUIView` trigger. Gated on the navigate NONCE
    /// (advances on every nav incl. a re-tap on the same highlight) so a re-tap
    /// re-blooms; NOT on scroll dedupe. The trigger is a CANCELLABLE work item:
    /// a superseding nav cancels the prior pending bloom (via
    /// `cancelLandingBloom`), and a user tap/scroll cancels it too (design §3
    /// interruptibility). The 0.35 s delay matches the non-chunked path so the
    /// navigate's scroll brings the target chunk's cell on-screen + laid out
    /// before the bloom fires.
    private func scheduleLandingBloomIfNeeded(
        tableView: UITableView, coordinator: Coordinator
    ) {
        guard highlightNonce != coordinator.lastBloomNonce else { return }
        coordinator.lastBloomNonce = highlightNonce
        coordinator.cancelLandingBloom()  // supersede any prior bloom
        guard let landed = TXTTextViewBridge.landingTrigger(
            highlightRange: highlightRange, persisted: persistedHighlights
        ), let target = TXTChunkedReaderBridge.landingBloomTarget(
            matchedRange: landed.range,
            chunkStartOffsets: coordinator.chunkStartOffsets
        ) else { return }

        let family = TXTTextViewBridge.bloomThemeFamily(for: config.backgroundColor)
        let reduceMotion = UIAccessibility.isReduceMotionEnabled
        let colorName = landed.colorName
        let chunkIndex = target.chunkIndex
        let localRange = target.chunkLocalRange
        coordinator.bloomingChunkIndex = chunkIndex
        let work = DispatchWorkItem { [weak tableView, weak coordinator] in
            guard let tableView, let coordinator else { return }
            // The navigate's scroll-to-offset brings the target chunk on-screen;
            // by the 0.35 s settle the cell is normally dequeued + laid out. If
            // it is still off-screen (very late layout), the cell-render path in
            // `cellForRowAt` would paint the persisted highlight — the bloom is a
            // transient cue, so dropping it for an un-dequeued cell is acceptable
            // (mirrors the non-chunked path, where a navigate that doesn't bring
            // the range on-screen also can't bloom).
            guard let cell = tableView.cellForRow(
                at: IndexPath(row: chunkIndex, section: 0)
            ) as? ChunkedTextCell else {
                coordinator.bloomingChunkIndex = nil
                return
            }
            cell.textContentView.playLandingBloom(
                range: localRange, colorName: colorName,
                family: family, reduceMotion: reduceMotion
            )
        }
        coordinator.pendingBloom = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: work)
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
        /// Bug #1230 / GH #1230: conversion direction applied to RENDERED chunk
        /// text in `attributedString(forChunk:)`. Source coordinates unchanged.
        var chineseConversion: ChineseConversionDirection = .none
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

        /// Bug #289: true while a programmatic position restore is in flight, so
        /// the scroll callbacks it triggers don't persist a transient position.
        /// Mirrors the non-chunked bridge's restore-suppression guard.
        private var isRestoringPosition = false

        /// Tracks last processed scrollToOffset to avoid redundant scrolls (bug #52).
        var lastScrollToOffset: Int?
        /// Bug #312 (Codex Gate-4 MED): the snap mode of the last honored jump,
        /// part of the dedupe key so a search→TOC (or TOC→search) jump to the
        /// SAME offset still re-scrolls into the new positioning.
        var lastSnapToTop = false

        /// Tracks last processed highlightRange to avoid redundant applications (bug #53).
        var lastHighlightRange: NSRange?

        /// Last navigate-nonce consumed (Bug #154 / GH #443). When the
        /// container's `highlightNonce` differs from this, a navigate event
        /// occurred — re-paint the temporary highlight + re-arm the 3 s
        /// auto-clear timer even if `lastHighlightRange` is unchanged.
        var lastHighlightNonce: Int = 0

        /// Bug #322 / GH #1542: the last navigate-nonce a locate bloom fired
        /// for. SEPARATE from `lastHighlightNonce` so the bloom gate advances
        /// independently of the temporary-highlight repaint gate; the bloom is
        /// keyed on the nonce (which advances on every navigate, incl. a re-tap
        /// on the same highlight) so a re-tap re-blooms. `.min` so the first nav
        /// fires. Mirrors the non-chunked `TXTTextViewBridge.Coordinator`.
        var lastBloomNonce: Int = .min

        /// Bug #322 / GH #1542: the cancellable scroll-settle-delayed bloom
        /// trigger. A superseding navigation cancels it before it fires, and a
        /// user tap / user-driven scroll cancels it too (design §3
        /// interruptibility). Mirrors the non-chunked bridge's `pendingBloom`.
        var pendingBloom: DispatchWorkItem?

        /// Bug #322 / GH #1542: chunk index whose cell a bloom was started on,
        /// so `cancelLandingBloom` can tear the in-flight bloom down on that
        /// specific cell. nil when no bloom has been fired (or after cancel).
        /// The bloom cancel/user-scroll helpers live in
        /// `TXTChunkedHighlightHelper.swift` alongside the other coordinator
        /// highlight methods.
        var bloomingChunkIndex: Int?

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
        ///
        /// Bug #312: when `snapLocalOffset` is set (a TOC / chapter / bookmark
        /// jump), the intra-chunk adjustment uses the TARGET glyph's rect to pin
        /// that character to the top edge instead of the linear `intraFraction`
        /// (which lands mid-chunk because 16KB chunks aren't chapter-aligned).
        func attemptChunkRestore(
            in tableView: UITableView,
            toChunkIndex index: Int,
            intraFraction: CGFloat? = nil,
            snapLocalOffset: Int? = nil
        ) {
            guard index >= 0, index < chunks.count else {
                restoreRetryCount = 0
                revealContent(tableView); return
            }

            // Bug #289: suppress position SAVE while the programmatic restore +
            // its layout-driven scroll callbacks run; cleared once they settle.
            isRestoringPosition = true

            guard tableView.bounds.width > 0 else {
                // Bug #27: exhausted retries → reveal so the screen isn't left blank.
                guard restoreRetryCount < Self.maxRestoreRetries else {
                    // Audit: reset so a LATER restore/navigation gets a full retry
                    // budget (a stale exhausted count would re-introduce the flash).
                    restoreRetryCount = 0
                    isRestoringPosition = false
                    revealContent(tableView)
                    return
                }
                restoreRetryCount += 1
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self, weak tableView] in
                    guard let self, let tableView else { return }
                    self.attemptChunkRestore(
                        in: tableView, toChunkIndex: index,
                        intraFraction: intraFraction, snapLocalOffset: snapLocalOffset
                    )
                }
                return
            }

            tableView.scrollToRow(
                at: IndexPath(row: index, section: 0),
                at: .top,
                animated: false
            )

            // Adjust for intra-chunk position.
            if let snapLocalOffset {
                // Bug #312: pin the target glyph to the top edge. scrollToRow(.top)
                // put the chunk top at the visible top; adding the glyph's y within
                // the cell pushes the content up so the destination line is at the
                // top. `scrollToRow(animated:false)` updates contentOffset
                // synchronously but does NOT dequeue/lay out the cell in the same
                // turn, so force a layout pass before querying the cell — otherwise
                // `cellForRow` is nil and the jump lands at the (arbitrary,
                // non-chapter-aligned) chunk top. Falls back to the chunk top only
                // if the cell still can't be resolved.
                tableView.layoutIfNeeded()
                // The text width is the cell width minus the textView's left+right
                // `textContainerInset` (16 + 16). Compute the glyph y in a
                // STANDALONE layout at that width — NOT off the live cell's
                // layoutManager, whose textContainer width may not have propagated
                // yet (width ≈ 0 → one char per line → a huge y that overscrolls
                // to the chunk end).
                let textWidth = tableView.bounds.width - 32
                let attr = attributedString(forChunk: index)
                if let glyphTopY = Self.glyphTopY(
                    forChunk: attr, localOffset: snapLocalOffset, textWidth: textWidth
                ) {
                    tableView.contentOffset.y += glyphTopY
                }
            } else if let fraction = intraFraction, fraction > 0 {
                let cellRect = tableView.rectForRow(at: IndexPath(row: index, section: 0))
                if cellRect.height > 0 {
                    tableView.contentOffset.y += cellRect.height * fraction
                }
            }

            // Bug #27: the scroll has landed — reveal the table (it was hidden in
            // makeUIView so chapter 1 never flashed). Bug #289: release the SAVE
            // suppression once the post-scroll layout callbacks settle. Reset the
            // retry budget so a later restore/navigation starts fresh (audit).
            restoreRetryCount = 0
            revealContent(tableView)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                self?.isRestoringPosition = false
            }
        }

        /// Bug #312: the y-offset of the glyph at chunk-local UTF-16 `localOffset`
        /// within a text column of `textWidth` — used to pin a TOC / chapter jump's
        /// destination character to the top edge. Computed in a STANDALONE
        /// `NSLayoutManager` at the cell's known text width (NOT off the live cell,
        /// whose `textContainer` width may be unset right after `layoutIfNeeded`,
        /// which would stack one char per line and overscroll to the chunk end).
        /// The cell's textView has `lineFragmentPadding = 0` and `textContainerInset`
        /// top 0, so the standalone layout (padding 0, no top inset) matches it.
        /// Returns nil when the chunk is empty or the width is non-positive. The
        /// local offset is valid in the rendered attr string under the same
        /// 1:1-BMP-UTF16 invariant the chunked bridge relies on.
        static func glyphTopY(
            forChunk attr: NSAttributedString, localOffset: Int, textWidth: CGFloat
        ) -> CGFloat? {
            guard attr.length > 0, textWidth > 0 else { return nil }
            let storage = NSTextStorage(attributedString: attr)
            let layoutManager = NSLayoutManager()
            let container = NSTextContainer(
                size: CGSize(width: textWidth, height: .greatestFiniteMagnitude)
            )
            container.lineFragmentPadding = 0
            layoutManager.addTextContainer(container)
            storage.addLayoutManager(layoutManager)
            let clamped = min(max(localOffset, 0), attr.length - 1)
            let glyphRange = layoutManager.glyphRange(
                forCharacterRange: NSRange(location: clamped, length: 1),
                actualCharacterRange: nil
            )
            layoutManager.ensureLayout(for: container)
            return layoutManager.boundingRect(forGlyphRange: glyphRange, in: container).minY
        }

        /// Bug #27: reveal the table after a restore lands (it was hidden in
        /// `makeUIView` to suppress the chapter-1 flash). Idempotent; a brief fade
        /// restores the designed open transition (Rule 51 carve-out — restoring
        /// existing behavior, not new UI).
        func revealContent(_ tableView: UITableView) {
            guard tableView.alpha < 1 else { return }
            UIView.animate(withDuration: 0.12) { tableView.alpha = 1 }
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
            // Bug #324 / GH #1546: tint each cell's selection (caret, grab
            // handles, selection-highlight) with the reader theme accent so it
            // matches the sepia/paper theme instead of the system blue. Applied
            // per cell here (the chunked path has one UITextView per cell); a
            // theme change reloads the table, re-running this with the new
            // config, so the refresh path is covered too.
            TXTChunkedReaderBridge.applyTintColor(to: cell.textContentView, config: config)
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
            // Bug #322 / GH #1542 (design §3): cancel a pending/in-flight locate
            // bloom on a USER-driven scroll. Gated on the same user-scroll
            // signal as the temporary-highlight clear (`isTracking ||
            // isDragging || isDecelerating`) so the navigate's OWN programmatic
            // scroll (which has those flags false) does not self-cancel the
            // about-to-fire bloom. A SEPARATE call from
            // `clearTemporaryHighlightIfNeeded` because the bloom fires on a
            // PERSISTENT highlight, so the temporary-highlight guard there would
            // skip it.
            cancelLandingBloomIfUserScroll(scrollView)
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
                // Bug #322 / GH #1542: a user-driven drag that ends without
                // deceleration is still a real interaction — cancel the bloom.
                cancelLandingBloomIfUserScroll(scrollView)
                clearTemporaryHighlightIfNeeded(scrollView: scrollView)
                reportScrollPosition(scrollView)
            }
        }

        // MARK: - Content Tap (Toolbar Toggle / Tap-on-Highlight)

        @objc func handleContentTap(_ gesture: UITapGestureRecognizer) {
            // Bug #322 / GH #1542 (design §3 interruptibility): a tap is a user
            // interaction — cancel any pending/in-flight locate bloom before
            // dispatching the tap (highlight-tap popover OR chrome toggle).
            // Mirrors the non-chunked coordinator's `handleContentTap`.
            cancelLandingBloom()
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
            // Bug #287 / GH #1268: exact char-index membership first, then a
            // 44pt-minimum tolerance band over each highlight's chunk-local
            // glyph rect — so a near-miss tap resolves (and is absorbed)
            // instead of falling through to the page-turn router. The
            // tolerance candidates are built from THIS chunk's local extent
            // of each highlight, matching the source-rect clipping below.
            let chunkLengthForCandidates = textView.textStorage.length
            let hit: PersistedHighlightLookupEntry
            if let exact = TextHighlightHitTester.hitTest(
                charIndex: globalCharIndex, in: lookup
            ) {
                hit = exact
            } else {
                var candidates: [(id: UUID, rect: CGRect)] = []
                for entry in lookup where entry.range.length > 0 {
                    let entryLocalStart = max(0, entry.range.location - chunkOffset)
                    let entryLocalEnd = min(
                        chunkLengthForCandidates,
                        entry.range.location + entry.range.length - chunkOffset
                    )
                    let entryLocalLen = entryLocalEnd - entryLocalStart
                    guard entryLocalLen > 0 else { continue }
                    let candidateGlyphRange = lm.glyphRange(
                        forCharacterRange: NSRange(
                            location: entryLocalStart, length: entryLocalLen
                        ),
                        actualCharacterRange: nil
                    )
                    guard candidateGlyphRange.length > 0 else { continue }
                    // Per-line-fragment rects (not the union bounding box) so a
                    // multi-line highlight's ragged-edge whitespace is not
                    // absorbed — only the painted fragments get a slop band.
                    lm.enumerateEnclosingRects(
                        forGlyphRange: candidateGlyphRange,
                        withinSelectedGlyphRange: NSRange(location: NSNotFound, length: 0),
                        in: textView.textContainer
                    ) { candidateRect, _ in
                        if candidateRect.width > 0, candidateRect.height > 0 {
                            candidates.append((entry.id, candidateRect))
                        }
                    }
                }
                guard let nearestID = HighlightHitTolerance.nearestHit(
                    point: containerPoint, candidates: candidates
                ), let resolved = lookup.first(where: { $0.id == nearestID }) else {
                    return nil
                }
                hit = resolved
            }
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
            // Bug #1230 / GH #1230: convert the RENDERED text only; `chunks` and
            // `chunkStartOffsets` stay in source coordinates (1:1 UTF-16 for BMP
            // CJK), so highlight/position math is unaffected — same invariant the
            // paged path relies on (offsetMap discarded).
            let text = TXTChunkedReaderBridge.renderedChunkText(
                chunks[index], conversion: chineseConversion
            )
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
            // Bug #289: skip while a programmatic restore is in flight — its
            // scrollToRow / contentOffset adjustment fires scroll callbacks that
            // would otherwise persist a transient position.
            guard !isRestoringPosition else { return }
            // Bug #289 (audit): resolve the row at the inset-adjusted VISIBLE top,
            // not `indexPathsForVisibleRows?.first` (the row at the table-bounds
            // top). Near a chunk boundary the bounds-top row can sit entirely in
            // the inset-covered band, which would measure the previous chunk's end.
            let visibleTopY = scrollView.contentOffset.y + tableView.contentInset.top
            let topPoint = CGPoint(x: tableView.bounds.midX, y: visibleTopY)
            guard let topIndexPath = tableView.indexPathForRow(at: topPoint)
                    ?? tableView.indexPathsForVisibleRows?.first else { return }
            let chunkIndex = topIndexPath.row
            guard chunkIndex < chunkStartOffsets.count, chunkIndex < chunks.count else { return }

            // Estimate intra-chunk offset from scroll fraction through the cell.
            // Bug #289: measure at the table's VISIBLE top (contentOffset.y +
            // contentInset.top) — the point RESTORE's scrollToRow(.top) aligns to —
            // so SAVE and RESTORE agree. The pre-fix code omitted the inset and
            // persisted a position ~contentInset.top px earlier each save.
            let cellRect = tableView.rectForRow(at: topIndexPath)
            let offset = TXTChunkedScrollOffset.topCharOffsetUTF16(
                contentOffsetY: scrollView.contentOffset.y,
                contentInsetTop: tableView.contentInset.top,
                cellOriginY: cellRect.origin.y,
                cellHeight: cellRect.height,
                chunkStartOffset: chunkStartOffsets[chunkIndex],
                chunkUTF16Count: chunks[chunkIndex].utf16.count
            )
            delegate?.scrollPositionDidChange(topCharOffsetUTF16: offset)
        }
    }
}
#endif
