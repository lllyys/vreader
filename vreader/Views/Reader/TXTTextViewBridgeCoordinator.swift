// Purpose: Coordinator for TXTTextViewBridge — handles UITextViewDelegate callbacks,
// scroll position tracking, selection changes, and highlight management.
//
// @coordinates-with TXTTextViewBridge.swift, TXTViewConfig.swift, TXTOffsetMapper.swift,
//   TXTBridgeShared.swift, HighlightableTextView.swift

#if canImport(UIKit)
import UIKit

extension TXTTextViewBridge {
    final class Coordinator: NSObject, UITextViewDelegate, UIGestureRecognizerDelegate {
        weak var delegate: TXTTextViewBridgeDelegate?
        var lastConfig: TXTViewConfig
        var lastAppliedAttrText: NSAttributedString?
        var lastAppliedText: String?

        /// Base attributed string (source without highlights). Used by timer to rebuild.
        var baseAttributedText: NSAttributedString?
        /// Persisted highlight ranges from DB (bug #55). Stored for timer rebuild.
        var persistedHighlights: [NSRange] = []
        /// Active search/navigation highlight range (bug #43).
        var currentHighlightRange: NSRange?
        /// Timer to auto-clear temporary highlight after 3s (bug #54).
        var highlightClearTimer: Timer?
        /// Weak reference to the text view, used by notification-based highlight clear.
        weak var activeTextView: UITextView?
        /// Observation token for searchHighlightClear notification.
        nonisolated(unsafe) var highlightClearObserver: NSObjectProtocol?

        var hasRestoredPosition = false
        private var lastScrollCallbackTime: CFTimeInterval = 0
        private static let scrollThrottleInterval: CFTimeInterval = 0.1
        private var restoreRetryCount = 0
        private static let maxRestoreRetries = 5
        var suppressScrollCallbacks = false
        var lastScrollToTarget: Int?
        /// Guards search highlight from being cleared by programmatic scroll (bug #43 regression).
        /// Uses a counter instead of a boolean (Issue 8) so overlapping programmatic scrolls
        /// don't clear the guard prematurely — each scroll increments the counter, and
        /// the guard is only lowered when all scrolls have settled (counter reaches 0).
        var programmaticScrollCount = 0

        init(delegate: TXTTextViewBridgeDelegate?, config: TXTViewConfig = TXTViewConfig()) {
            self.delegate = delegate
            self.lastConfig = config
            super.init()

            // Observe searchHighlightClear to dismiss temporary highlights on new search
            highlightClearObserver = NotificationCenter.default.addObserver(
                forName: .searchHighlightClear, object: nil, queue: .main
            ) { [weak self] _ in
                self?.clearSearchHighlightIfTemporary()
                if let tv = self?.activeTextView {
                    self?.rebuildHighlights(in: tv)
                }
            }
        }

        deinit {
            // Coordinator is @MainActor-isolated via UITextViewDelegate; deinit is nonisolated.
            // Use assumeIsolated to satisfy strict concurrency for non-Sendable property access.
            MainActor.assumeIsolated {
                if let observer = highlightClearObserver {
                    NotificationCenter.default.removeObserver(observer)
                }
                highlightClearTimer?.invalidate()
                highlightClearTimer = nil
            }
        }

        /// Clears the current temporary search highlight and cancels any auto-clear timer.
        /// Skips clearing when `programmaticScrollCount > 0` (bug #43 regression fix,
        /// Issue 8: counter-based guard) so that search navigation scroll doesn't
        /// immediately dismiss the highlight.
        func clearSearchHighlightIfTemporary() {
            guard programmaticScrollCount <= 0 else { return }
            highlightClearTimer?.invalidate()
            highlightClearTimer = nil
            currentHighlightRange = nil
        }

        /// Rebuilds highlight visualization from coordinator state (for timer callback).
        /// Uses layout manager drawing — NEVER modifies text storage (bug #47 v12).
        func rebuildHighlights(in textView: UITextView) {
            guard let htv = textView as? HighlightableTextView else { return }
            htv.setHighlightRanges(persisted: persistedHighlights, active: currentHighlightRange)
        }

        /// Restores scroll position, retrying if the view has no valid frame.
        /// TextKit returns zero-rect line fragments when the text container has
        /// zero width, so charOffsetToScrollOffset returns 0 for all offsets.
        func attemptScrollRestore(in textView: UITextView, toCharOffset offset: Int) {
            guard textView.bounds.width > 0 else {
                guard restoreRetryCount < Self.maxRestoreRetries else { return }
                restoreRetryCount += 1
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self, weak textView] in
                    guard let self, let textView else { return }
                    self.attemptScrollRestore(in: textView, toCharOffset: offset)
                }
                return
            }

            let textLength = (textView.text as NSString?)?.length ?? 0
            let clampedOffset = min(max(offset, 0), textLength)
            let scrollY = TXTOffsetMapper.charOffsetToScrollOffset(
                charOffset: clampedOffset,
                layoutManager: textView.layoutManager,
                textContainer: textView.textContainer
            )
            textView.setContentOffset(CGPoint(x: 0, y: scrollY), animated: false)
        }

        // MARK: - Content Tap (Toolbar Toggle)

        @objc func handleContentTap(_ gesture: UITapGestureRecognizer) {
            clearSearchHighlightIfTemporary()
            if let tv = gesture.view as? UITextView {
                rebuildHighlights(in: tv)
            }
            TXTBridgeShared.postContentTappedNotification()
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            TXTBridgeShared.gestureRecognizerShouldRecognizeSimultaneously()
        }

        // MARK: - Link Interaction Policy

        func textView(
            _ textView: UITextView,
            shouldInteractWith URL: URL,
            in characterRange: NSRange,
            interaction: UITextItemInteraction
        ) -> Bool {
            // Only allow http and https links
            let scheme = URL.scheme?.lowercased()
            return scheme == "http" || scheme == "https"
        }

        // MARK: - Edit Menu (Bug #44: Highlight & Note)

        func textView(
            _ textView: UITextView,
            editMenuForTextIn range: NSRange,
            suggestedActions: [UIMenuElement]
        ) -> UIMenu? {
            TXTBridgeShared.buildReaderEditMenu(
                range: range, textView: textView, suggestedActions: suggestedActions,
                isAITranslateAvailable: AIReaderAvailability.isAvailable(
                    featureFlags: FeatureFlags.shared,
                    keychainService: KeychainService(),
                    consentManager: AIConsentManager()
                )
            )
        }

        func textViewDidChangeSelection(_ textView: UITextView) {
            // Suppress during text replacement to prevent crash (bug #47 v11)
            if let htv = textView as? HighlightableTextView, htv.isReplacingText { return }
            let nsRange = textView.selectedRange
            if let utf16Range = TXTOffsetMapper.selectionToUTF16Range(
                nsRange: nsRange,
                text: textView.text ?? ""
            ) {
                delegate?.selectionDidChange(utf16Range: utf16Range)
            }
        }

        func scrollViewDidScroll(_ scrollView: UIScrollView) {
            guard !suppressScrollCallbacks else { return }
            if let htv = scrollView as? HighlightableTextView, htv.isReplacingText { return }
            guard let textView = scrollView as? UITextView else { return }

            // Clear temporary search highlight on user scroll
            if currentHighlightRange != nil {
                clearSearchHighlightIfTemporary()
                rebuildHighlights(in: textView)
            }

            // Throttle: skip if called within the throttle interval
            let now = CACurrentMediaTime()
            guard now - lastScrollCallbackTime >= Self.scrollThrottleInterval else { return }
            lastScrollCallbackTime = now

            let topOffset = TXTOffsetMapper.scrollOffsetToCharOffset(
                scrollY: scrollView.contentOffset.y,
                layoutManager: textView.layoutManager,
                textContainer: textView.textContainer
            )
            delegate?.scrollPositionDidChange(topCharOffsetUTF16: topOffset)
        }

        /// Flush final scroll position when scrolling ends (deceleration complete).
        func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
            sendScrollPosition(scrollView)
        }

        func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
            if !decelerate { sendScrollPosition(scrollView) }
        }

        private func sendScrollPosition(_ scrollView: UIScrollView) {
            guard !suppressScrollCallbacks else { return }
            if let htv = scrollView as? HighlightableTextView, htv.isReplacingText { return }
            guard let textView = scrollView as? UITextView else { return }
            lastScrollCallbackTime = CACurrentMediaTime()
            let topOffset = TXTOffsetMapper.scrollOffsetToCharOffset(
                scrollY: scrollView.contentOffset.y,
                layoutManager: textView.layoutManager,
                textContainer: textView.textContainer
            )
            delegate?.scrollPositionDidChange(topCharOffsetUTF16: topOffset)
        }
    }
}
#endif
