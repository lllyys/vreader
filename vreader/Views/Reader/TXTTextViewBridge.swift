// Purpose: UIViewRepresentable wrapping UITextView for TXT/MD document rendering.
// Provides selection range extraction, scroll position -> offset mapping,
// and configurable appearance. Supports both plain text and NSAttributedString.
//
// Key decisions:
// - Uses TextKit 1 (NSLayoutManager) for reliable offset mapping.
// - Non-editable UITextView for reading — selection enabled for highlights.
// - Coordinator handles delegate callbacks (scroll, selection change).
// - All offset conversions delegate to TXTOffsetMapper for testability.
// - Optional `attributedText` parameter: if non-nil, uses it directly (MD reader).
//   If nil, builds plain-text attributed string from `text` + config (TXT reader).
// - Link interaction policy: only http/https URLs are tappable.
//
// @coordinates-with TXTViewConfig.swift, TXTTextViewBridgeCoordinator.swift,
//   TXTOffsetMapper.swift, TXTChunkedLoader.swift, Locator.swift,
//   MDReaderContainerView.swift, HighlightableTextView.swift

#if canImport(UIKit)
import SwiftUI
import UIKit

/// SwiftUI wrapper for a read-only UITextView displaying plain or attributed text.
struct TXTTextViewBridge: UIViewRepresentable {
    let text: String
    /// Optional pre-built attributed string (e.g., from Markdown rendering).
    /// When non-nil, used directly instead of building from `text` + config.
    var attributedText: NSAttributedString?
    let config: TXTViewConfig
    var restoreOffset: Int?
    /// Programmatic scroll target (e.g., from search result navigation).
    /// When this changes in updateUIView, the bridge scrolls to the offset.
    var scrollToOffset: Int?
    /// Temporary highlight range for search result visualization (bug #43).
    /// Applied as a yellow background attribute on the text storage.
    var highlightRange: NSRange?
    /// Whether the current highlight is temporary (search navigation) vs persistent
    /// (user-created). Temporary highlights auto-clear after 3s. (bug #54)
    var highlightIsTemporary: Bool = true
    /// Persisted highlight ranges loaded from DB on file open (bug #55).
    /// Applied as yellow background attributes that survive text rebuilds.
    var persistedHighlights: [NSRange] = []
    /// Parallel lookup mapping each persisted range to its highlight UUID
    /// (Feature #53 WI-2). Used by the bridge coordinator's tap handler
    /// to resolve a tap → highlight ID for the inline edit/delete menu.
    /// Defaults to empty so existing callers stay source-compatible until
    /// they wire the lookup; in that case the chrome-toggle path remains.
    var persistedHighlightLookup: [PersistedHighlightLookupEntry] = []
    /// Top safe-area inset added on top of `config.textInset.top` so the first
    /// line of text clears the Dynamic Island / status bar. Bug #179 (mirrors
    /// bug #163 for EPUB). Default `0` preserves prior behaviour for callers
    /// not yet threaded through. Wired by `TXTReaderContainerView` and
    /// `MDReaderContainerView` via `GeometryReader { proxy in ... }` using
    /// `proxy.safeAreaInsets.top`.
    var safeAreaTopInset: CGFloat = 0
    weak var delegate: TXTTextViewBridgeDelegate?

    func makeUIView(context: Context) -> UITextView {
        let textView = HighlightableTextView()
        textView.isEditable = false
        textView.isSelectable = true
        textView.showsVerticalScrollIndicator = true
        textView.alwaysBounceVertical = true
        textView.delegate = context.coordinator
        // Bug #179: combine base typographic padding with the SwiftUI
        // safe-area top inset so the first line clears the Dynamic Island.
        textView.textContainerInset = Self.combinedTextInset(
            base: config.textInset,
            safeAreaTop: safeAreaTopInset
        )
        textView.textContainer.lineFragmentPadding = 0

        // Performance: defer off-screen glyph layout for large documents.
        // TextKit 1 will only compute layout for the visible region + buffer.
        textView.layoutManager.allowsNonContiguousLayout = true

        // Tap gesture for toolbar toggle — fires alongside UITextView's own gestures
        let tapRecognizer = UITapGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleContentTap)
        )
        tapRecognizer.delegate = context.coordinator
        textView.addGestureRecognizer(tapRecognizer)

        // Keep a weak ref for notification-driven highlight clear
        context.coordinator.activeTextView = textView

        // Store base text in coordinator, set source text + highlight ranges separately.
        context.coordinator.baseAttributedText = buildBaseAttributedText()
        context.coordinator.persistedHighlights = persistedHighlights
        context.coordinator.persistedHighlightLookup = persistedHighlightLookup
        context.coordinator.lastAppliedText = text
        context.coordinator.lastAppliedAttrText = attributedText
        // Set highlights first so drawBackground has correct ranges during initial layout.
        Self.applyHighlights(to: textView, coordinator: context.coordinator)
        applySourceText(to: textView, coordinator: context.coordinator)

        // Restore scroll position if requested (one-shot — never re-applied).
        // Suppress scroll callbacks from the moment text is applied until restore
        // settles, to block TextKit relayout storms (bug #24/#25).
        // Hide the text view until restore completes to prevent the user seeing
        // content at offset 0 before the jump (bug #27).
        if let offset = restoreOffset, offset > 0 {
            context.coordinator.hasRestoredPosition = true
            context.coordinator.suppressScrollCallbacks = true
            textView.alpha = 0
            let coordinator = context.coordinator
            // Phase 1 (t+0.15s): Initial restore after SwiftUI sizes the view.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                // Force TextKit to complete layout before restoring position.
                // This triggers the TextKit 1 relayout synchronously rather than
                // waiting for it to happen asynchronously and destroy our position.
                let textLength = (textView.text as NSString?)?.length ?? 0
                if textLength > 0 {
                    let fullRange = NSRange(location: 0, length: min(textLength, offset + 4096))
                    textView.layoutManager.ensureLayout(forCharacterRange: fullRange)
                }
                coordinator.attemptScrollRestore(in: textView, toCharOffset: offset)
                // Phase 2 (t+0.2s): Brief safety net — re-apply if TextKit
                // relayout happened after ensureLayout. Short delay since
                // ensureLayout already forced layout completion.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    coordinator.attemptScrollRestore(in: textView, toCharOffset: offset)
                    coordinator.suppressScrollCallbacks = false
                    textView.alpha = 1
                }
            }
        } else if let offset = restoreOffset {
            // offset == 0: no need to hide, just mark as restored
            context.coordinator.hasRestoredPosition = true
        }

        return textView
    }

    func updateUIView(_ textView: UITextView, context: Context) {
        // Keep delegate reference in sync (SwiftUI may recreate the struct)
        context.coordinator.delegate = delegate

        // Detect changes to source text, config, or highlights
        let configChanged = !context.coordinator.lastConfig.renderingEquals(config)
        let textChanged = text != context.coordinator.lastAppliedText
        let attrChanged = attributedText !== context.coordinator.lastAppliedAttrText
        let persistedChanged = persistedHighlights != context.coordinator.persistedHighlights
        let highlightChanged = highlightRange != context.coordinator.currentHighlightRange

        // Update coordinator state
        let sourceChanged = textChanged || attrChanged || configChanged
        if sourceChanged {
            context.coordinator.baseAttributedText = buildBaseAttributedText()
            context.coordinator.lastConfig = config
            context.coordinator.lastAppliedText = text
            context.coordinator.lastAppliedAttrText = attributedText
        }
        if persistedChanged {
            context.coordinator.persistedHighlights = persistedHighlights
        }
        // Keep the WI-2 lookup in sync regardless of `persistedChanged`'s
        // NSRange-only diff: a record's UUID can change (e.g., delete then
        // re-create at the same range) without the range array changing.
        if context.coordinator.persistedHighlightLookup != persistedHighlightLookup {
            context.coordinator.persistedHighlightLookup = persistedHighlightLookup
        }
        if highlightChanged {
            context.coordinator.currentHighlightRange = highlightRange
            // Manage auto-clear timer for temporary highlights
            context.coordinator.highlightClearTimer?.invalidate()
            context.coordinator.highlightClearTimer = nil
            if let range = highlightRange, range.length > 0, highlightIsTemporary {
                context.coordinator.highlightClearTimer = Timer.scheduledTimer(
                    withTimeInterval: 3.0, repeats: false
                ) { [weak coordinator = context.coordinator, weak textView] _ in
                    DispatchQueue.main.async {
                        guard let coordinator, let textView else { return }
                        coordinator.currentHighlightRange = nil
                        coordinator.rebuildHighlights(in: textView)
                    }
                }
            }
        }

        let htv = textView as! HighlightableTextView

        // Update highlight ranges via layout manager — no text storage mutation (bug #47 v12)
        if persistedChanged || highlightChanged {
            Self.applyHighlights(to: htv, coordinator: context.coordinator)
        }

        // Update source text only when text/config changes (safe — no active selection during config change)
        if sourceChanged {
            applySourceText(to: htv, coordinator: context.coordinator)
        }

        // Re-apply inset changes. Bug #179: include safeAreaTopInset so the
        // Dynamic Island stays uncovered when the safe area changes (rotation,
        // split-screen, etc.) or when the bridge is rebuilt.
        let combined = Self.combinedTextInset(
            base: config.textInset,
            safeAreaTop: safeAreaTopInset
        )
        if textView.textContainerInset != combined {
            textView.textContainerInset = combined
        }

        // Programmatic scroll from search navigation. Bug #99 (cause #3): the
        // earlier `programmaticScrollCount` + 0.3s timer mechanism raced TextKit
        // 1's lazy-layout `scrollViewDidScroll` callbacks (which can arrive
        // 400-1200ms after `setContentOffset` returns). Replaced with a
        // canonical-signal approach in `clearSearchHighlightIfTemporary`: the
        // helper checks `scrollView.isTracking || isDragging || isDecelerating`
        // and only clears for actual user-driven scrolls. Programmatic scrolls
        // and their late layout callbacks all have those flags false, so they
        // skip the clear without needing any timer.
        //
        // Bug #153: route through `scrollToMatchedOffset` (top-quarter headroom
        // + `scrollRangeToVisible` safety net) so search-result navigation lands
        // the matched text comfortably inside the viewport — distinct from the
        // saved-position restore path, which is purposely top-edge.
        // Reset dedupe on text/attr identity change only; config-only changes (font/theme)
        // must not re-arm scroll — that would jump the user back to a stale search target.
        if Self.shouldScroll(to: scrollToOffset, lastTarget: context.coordinator.lastScrollToTarget,
                             sourceChanged: textChanged || attrChanged),
           let target = scrollToOffset {
            context.coordinator.lastScrollToTarget = target
            let textLength = (textView.text as NSString?)?.length ?? 0
            if textLength > 0 {
                let rangeEnd = min(textLength, target + 4096)
                textView.layoutManager.ensureLayout(forCharacterRange: NSRange(location: 0, length: rangeEnd))
            }
            context.coordinator.scrollToMatchedOffset(
                in: textView,
                charOffset: target,
                highlightRange: highlightRange
            )
        }

        // Scroll position restore is one-shot only (handled in makeUIView).
        // Do NOT re-apply restoreOffset here — doing so creates an observation
        // feedback loop: scroll → viewModel.currentOffsetUTF16 changes →
        // SwiftUI re-renders → updateUIView → restoreScrollPosition → scroll (bug #15).
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(delegate: delegate, config: config)
    }

    // MARK: - Static seams (testable)

    /// WI-2 Part 2c: determines whether a scroll should fire given the current dedupe state.
    /// When `sourceChanged` is true the coordinator's last target is treated as nil so that
    /// two different chapters sharing the same chapter-local Int both trigger a scroll.
    static func shouldScroll(to target: Int?, lastTarget: Int?, sourceChanged: Bool) -> Bool {
        guard let target else { return false }
        let effectiveLast: Int? = sourceChanged ? nil : lastTarget
        return target != effectiveLast
    }

    /// Bug #179: combine the base typographic `textInset` with the SwiftUI
    /// safe-area top so the first line of text clears the Dynamic Island /
    /// status bar. Sum-based composition keeps existing typographic padding
    /// (16pt default) intact and just shifts content down by the device's
    /// safe-area requirement. Negative inputs clamped to 0 to match
    /// UIScrollView's defensive behaviour around tiny-viewport edge cases
    /// (mirrors EPUB bug #167 audit-fix).
    static func combinedTextInset(
        base: UIEdgeInsets,
        safeAreaTop: CGFloat
    ) -> UIEdgeInsets {
        UIEdgeInsets(
            top: base.top + max(0, safeAreaTop),
            left: base.left,
            bottom: base.bottom,
            right: base.right
        )
    }

    // MARK: - Private

    /// Builds the base attributed string from source data (struct properties).
    /// NEVER reads from the textView — always uses struct's text/attributedText/config.
    private func buildBaseAttributedText() -> NSAttributedString {
        if let attributedText {
            return attributedText
        }
        return TXTAttributedStringBuilder.build(text: text, config: config)
    }

    /// Sets source text on the text view (no highlights — those are in the layout manager).
    private func applySourceText(to textView: HighlightableTextView, coordinator: Coordinator) {
        let base = coordinator.baseAttributedText ?? buildBaseAttributedText()
        textView.setSourceText(base)
        textView.adjustsFontForContentSizeCategory = true
        textView.backgroundColor = config.backgroundColor
    }

    /// Updates highlight visualization via the layout manager (bug #47 v12).
    /// NEVER modifies text storage — completely safe during active selection.
    private static func applyHighlights(to textView: HighlightableTextView, coordinator: Coordinator) {
        textView.setHighlightRanges(
            persisted: coordinator.persistedHighlights,
            active: coordinator.currentHighlightRange
        )
    }

    // Scroll restore logic is in Coordinator.attemptScrollRestore (supports retry).
    // Coordinator is defined in TXTTextViewBridgeCoordinator.swift.
}
#endif
