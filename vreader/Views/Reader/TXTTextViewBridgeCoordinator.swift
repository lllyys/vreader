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
        /// Persisted highlights from DB (bug #55). Stored for timer rebuild.
        /// Each carries its own color (Bug #208).
        var persistedHighlights: [PaintedHighlight] = []
        /// Parallel lookup mapping ranges to their highlight UUIDs. Used by
        /// `handleContentTap` to resolve a tap on a painted range back to
        /// the original `HighlightRecord.highlightId` for the inline-menu
        /// dispatcher. Feature #53 WI-2 / GH #596.
        var persistedHighlightLookup: [PersistedHighlightLookupEntry] = []
        /// WI-2b: Presenter for the inline edit/delete menu shown on
        /// tap-of-highlight. nil → coordinator only posts the notification
        /// and skips chrome-toggle (matches WI-2's dormant-subscriber path).
        var highlightActionPresenter: (any HighlightActionPresenting)?
        /// WI-2b: Action callback fired after the presenter dismisses with
        /// a non-nil action. Typically wraps `HighlightCoordinator.handleTapAction`.
        var onHighlightTapAction: (@MainActor (HighlightTapAction, UUID) async -> Void)?
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

        /// Scrolls so a search/navigation match is visible with headroom from the top
        /// of the viewport (bug #153). Distinct from `attemptScrollRestore`, which puts
        /// the saved offset at the top edge — that's correct for resuming a reading
        /// session, but for search-tap navigation the user benefits from seeing context
        /// before the match (and from the matched line not being pushed off-screen by
        /// `setContentOffset` clamping when the match is near the document end).
        ///
        /// After positioning, also calls `UITextView.scrollRangeToVisible(_:)` as a
        /// safety net: even if our computed target lands the line off-screen for some
        /// edge case (very long wrapped paragraphs, post-clamp visual drift), the
        /// system's "ensure visible" pass guarantees the highlight is in the viewport
        /// before the 3 s auto-clear timer fires.
        func scrollToMatchedOffset(in textView: UITextView, charOffset: Int, highlightRange: NSRange? = nil) {
            guard textView.bounds.width > 0 else {
                guard restoreRetryCount < Self.maxRestoreRetries else { return }
                restoreRetryCount += 1
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self, weak textView] in
                    guard let self, let textView else { return }
                    self.scrollToMatchedOffset(in: textView, charOffset: charOffset, highlightRange: highlightRange)
                }
                return
            }

            let textLength = (textView.text as NSString?)?.length ?? 0
            let clampedOffset = min(max(charOffset, 0), textLength)
            let lineY = TXTOffsetMapper.charOffsetToScrollOffset(
                charOffset: clampedOffset,
                layoutManager: textView.layoutManager,
                textContainer: textView.textContainer
            )
            let scrollY = TXTOffsetMapper.scrollOffsetForVisibleMatch(
                lineY: lineY,
                viewportHeight: textView.bounds.height,
                topInset: textView.textContainerInset.top
            )
            textView.setContentOffset(CGPoint(x: 0, y: scrollY), animated: false)

            // Safety net: ensure the matched range is in the viewport even if the
            // pre-clamp computation landed it just outside (very long wrapped paragraphs,
            // post-clamp drift, etc.). `scrollRangeToVisible` is a no-op if already visible.
            if let range = highlightRange,
               range.location != NSNotFound,
               range.location >= 0,
               range.location + range.length <= textLength {
                textView.scrollRangeToVisible(range)
            }
        }

        // MARK: - Content Tap (Toolbar Toggle)

        @objc func handleContentTap(_ gesture: UITapGestureRecognizer) {
            // Feature #53 WI-2: hit-test against persisted highlight ranges
            // first. On hit, post `.readerHighlightTapped` and SKIP the
            // chrome-toggle path so a tap on a highlight reliably opens the
            // inline edit/delete menu (acceptance criterion d: "tapping
            // non-highlighted text preserves existing scroll/chrome-toggle
            // behavior" — symmetric: tapping a highlight overrides it).
            if let tv = gesture.view as? UITextView,
               !persistedHighlightLookup.isEmpty,
               let event = Self.resolveHighlightTap(
                   gesture: gesture,
                   in: tv,
                   lookup: persistedHighlightLookup
               ) {
                NotificationCenter.default.post(
                    name: .readerHighlightTapped,
                    object: event
                )
                // WI-2b: present the inline edit/delete menu if wired.
                // The presenter is fired on the active text view, which
                // is in the responder chain and has a valid window for
                // UIEditMenuInteraction.addInteraction.
                if let presenter = highlightActionPresenter,
                   let onAction = onHighlightTapAction {
                    presenter.present(for: event, in: tv) { action in
                        guard let action else { return }
                        Task { @MainActor in
                            await onAction(action, event.highlightID)
                        }
                    }
                }
                return
            }
            clearSearchHighlightIfTemporary()
            if let tv = gesture.view as? UITextView {
                rebuildHighlights(in: tv)
            }
            TXTBridgeShared.postContentTappedNotification()
        }

        /// Resolves a tap into a `ReaderHighlightTapEvent` if the location
        /// lands inside a persisted highlight range. Returns nil when the
        /// tap misses every range (caller falls back to chrome-toggle).
        ///
        /// Extracted as static + internal so unit tests can drive it
        /// against a real UITextView fixture without going through a live
        /// UITapGestureRecognizer (UIKit's gesture system is hard to fake).
        @MainActor
        static func resolveHighlightTap(
            gesture: UITapGestureRecognizer,
            in textView: UITextView,
            lookup: [PersistedHighlightLookupEntry]
        ) -> ReaderHighlightTapEvent? {
            let tapPoint = gesture.location(in: textView)
            return resolveHighlightTap(
                tapPoint: tapPoint, in: textView, lookup: lookup
            )
        }

        /// Pure-point overload. Tests construct a CGPoint directly.
        @MainActor
        static func resolveHighlightTap(
            tapPoint: CGPoint,
            in textView: UITextView,
            lookup: [PersistedHighlightLookupEntry]
        ) -> ReaderHighlightTapEvent? {
            guard !lookup.isEmpty else { return nil }
            let inset = textView.textContainerInset
            let containerPoint = CGPoint(
                x: tapPoint.x - inset.left,
                y: tapPoint.y - inset.top
            )
            let lm = textView.layoutManager
            let charIndex = lm.characterIndex(
                for: containerPoint,
                in: textView.textContainer,
                fractionOfDistanceBetweenInsertionPoints: nil
            )
            guard let hit = TextHighlightHitTester.hitTest(
                charIndex: charIndex, in: lookup
            ) else { return nil }
            let glyphRange = lm.glyphRange(
                forCharacterRange: hit.range, actualCharacterRange: nil
            )
            let containerRect = lm.boundingRect(
                forGlyphRange: glyphRange,
                in: textView.textContainer
            )
            // Re-apply the inset to convert container-rect → textView-rect.
            // Per Bug #203 (GH #743): `UIEditMenuConfiguration.sourcePoint`
            // expects the interaction-view's coordinate space — the regular
            // TXT presenter is `present(for: event, in: tv)`, so the rect
            // must stay in textView-local coords. The previous code
            // converted to nil (window-space) which positioned the menu
            // off-screen when the textView wasn't at window origin.
            let viewRect = containerRect.offsetBy(
                dx: inset.left, dy: inset.top
            )
            return ReaderHighlightTapEvent(
                highlightID: hit.id,
                sourceRect: viewRect
            )
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
            // Feature #60 WI-7c2: TXT non-chunked bridge swap. The
            // legacy `TXTBridgeShared.buildReaderEditMenu` UIMenu
            // (Highlight / Add Note / Define / Translate) is
            // replaced by `SelectionPopoverView` (WI-7a), presented
            // by `SelectionPopoverPresenterModifier` (WI-7c1) on
            // `TXTReaderContainerView`. We post the selection on
            // `.readerSelectionPopoverRequested` (the presenter's
            // observed name) and return an empty UIMenu to suppress
            // iOS's default menu surface — the SwiftUI sheet takes
            // over as the visual presentation.
            //
            // Why the `range.length > 0` guard: iOS calls
            // `editMenuForTextIn` for cursor placement (zero-length
            // range) too; we don't want a popover for that — only
            // for actual text selection. Returning an empty UIMenu
            // unconditionally still suppresses iOS's default in the
            // zero-length case (which is fine — there's no useful
            // menu for an empty selection here anyway).
            //
            // Why we route through TXTBridgeShared.postSelectionNotification
            // rather than SelectionPopoverRequest.post (Codex Gate 4
            // round 1 Low): the shared helper already implements the
            // range→TextSelectionInfo extraction with UTF-16 + bounds
            // validation matching UITextView delegate semantics —
            // duplicating that contract on the producer side would
            // drift. WI-7c5a: that helper now delegates to
            // SelectionPopoverRequest.post for the popover name, so
            // the object is a typed SelectionPopoverRequestPayload
            // (tokenless for TXT); the presenter parses it via
            // SelectionPopoverRequest.payload(from:).
            if range.length > 0 {
                TXTBridgeShared.postSelectionNotification(
                    .readerSelectionPopoverRequested,
                    from: textView,
                    range: range
                )
            }
            return UIMenu(children: [])
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
