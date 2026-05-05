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
        ///
        /// When called with a `scrollView`, the clear only fires for scrolls that the
        /// user is actually driving (`isTracking || isDragging || isDecelerating`).
        /// Programmatic scrolls — and the late `scrollViewDidScroll` callbacks
        /// TextKit 1's lazy layout dispatches well after `setContentOffset` returns —
        /// have all three flags false, so they are correctly skipped.
        ///
        /// When called with `nil` (e.g. from `handleContentTap`, search-clear notification,
        /// or any non-scroll-driven dismiss path), the clear is unconditional.
        ///
        /// Bug history: bug #43 first added an `isProgrammaticScroll` boolean guard;
        /// Issue 8 upgraded it to a counter; bug #99 cause #3 surfaced that the
        /// counter's 0.3s decrement was racing TextKit's late layout callbacks. The
        /// `isTracking/isDragging/isDecelerating` triplet is the canonical signal —
        /// it doesn't need a timer at all.
        func clearSearchHighlightIfTemporary(scrollView: UIScrollView? = nil) {
            if let scrollView,
               !scrollView.isTracking,
               !scrollView.isDragging,
               !scrollView.isDecelerating {
                return
            }
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

            // Clear temporary search highlight on user scroll. Pass the scrollView
            // so the helper can distinguish user scrolls (clear) from programmatic-
            // scroll-induced layout callbacks (skip). Bug #99.
            if currentHighlightRange != nil {
                let beforeClear = currentHighlightRange
                clearSearchHighlightIfTemporary(scrollView: scrollView)
                if currentHighlightRange != beforeClear {
                    rebuildHighlights(in: textView)
                }
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
