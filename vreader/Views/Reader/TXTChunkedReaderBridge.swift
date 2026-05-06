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
//   TXTAttributedStringBuilder.swift, TXTReaderContainerView.swift, TXTViewConfig.swift

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
    /// Persisted highlight ranges (document-global UTF-16) loaded from DB (bug #55).
    var persistedHighlights: [NSRange] = []

    func makeCoordinator() -> Coordinator {
        Coordinator(delegate: delegate)
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

        context.coordinator.chunks = chunks
        context.coordinator.config = config
        context.coordinator.chunkStartOffsets = chunkStartOffsets
        context.coordinator.persistedHighlights = persistedHighlights
        context.coordinator.delegate = delegate

        // Tap gesture for toolbar toggle
        let tapRecognizer = UITapGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleContentTap)
        )
        tapRecognizer.delegate = context.coordinator
        tableView.addGestureRecognizer(tapRecognizer)

        // Restore scroll position — asyncAfter allows SwiftUI to size the table view
        // before scrolling. In makeUIView the view has no frame yet.
        // The coordinator retries if the view still has no valid frame (bug #23).
        if let chunkIdx = restoreChunkIndex, chunkIdx < chunks.count {
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

        // Highlight range for visual feedback (bug #53)
        if highlightRange != context.coordinator.lastHighlightRange {
            // Clear previous highlight
            context.coordinator.clearHighlight(in: tableView)
            context.coordinator.lastHighlightRange = highlightRange
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
        /// Persisted highlight ranges (document-global UTF-16) from DB (bug #55).
        var persistedHighlights: [NSRange] = []
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
            let now = CACurrentMediaTime()
            guard now - lastScrollTime >= Self.scrollThrottleInterval else { return }
            lastScrollTime = now
            reportScrollPosition(scrollView)
        }

        func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
            reportScrollPosition(scrollView)
        }

        func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
            if !decelerate { reportScrollPosition(scrollView) }
        }

        // MARK: - Content Tap (Toolbar Toggle)

        @objc func handleContentTap(_ gesture: UITapGestureRecognizer) {
            TXTBridgeShared.postContentTappedNotification()
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            TXTBridgeShared.gestureRecognizerShouldRecognizeSimultaneously()
        }

        // MARK: - UITextViewDelegate

        /// Tracks selection changes for feature parity with TXTTextViewBridge (bug #54).
        func textViewDidChangeSelection(_ textView: UITextView) {
            // Suppress during text replacement to prevent crash (bug #47 v11)
            if let htv = textView as? HighlightableTextView, htv.isReplacingText { return }
            let nsRange = textView.selectedRange
            guard nsRange.length > 0 else { return }
            let chunkIndex = textView.tag
            let chunkOffset = chunkIndex < chunkStartOffsets.count ? chunkStartOffsets[chunkIndex] : 0
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
            let chunkIndex = textView.tag
            let chunkOffset = chunkIndex < chunkStartOffsets.count ? chunkStartOffsets[chunkIndex] : 0
            return TXTBridgeShared.buildReaderEditMenu(
                range: range, textView: textView, suggestedActions: suggestedActions,
                chunkOffset: chunkOffset,
                isAITranslateAvailable: AIReaderAvailability.isAvailable(
                    featureFlags: FeatureFlags.shared,
                    keychainService: KeychainService(),
                    consentManager: AIConsentManager()
                )
            )
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
