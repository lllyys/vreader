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
// @coordinates-with TXTOffsetMapper.swift, TXTChunkedLoader.swift, Locator.swift,
//   MDReaderContainerView.swift

#if canImport(UIKit)
import SwiftUI
import UIKit

/// Configuration for TXT text view appearance.
struct TXTViewConfig: Sendable {
    var fontSize: CGFloat = 18
    var fontName: String? = nil // nil = system font
    var lineSpacing: CGFloat = 6
    var textColor: UIColor = UIColor(red: 0.10, green: 0.10, blue: 0.10, alpha: 1.0)
    var backgroundColor: UIColor = .white
    var letterSpacing: CGFloat = 0
    var textInset: UIEdgeInsets = UIEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)
}

/// Callback events from the text view bridge.
@MainActor
protocol TXTTextViewBridgeDelegate: AnyObject {
    /// Called when the user's selection changes. Range is in UTF-16 offsets.
    func selectionDidChange(utf16Range: UTF16Range)
    /// Called when the visible scroll position changes. Offset is in UTF-16 units.
    func scrollPositionDidChange(topCharOffsetUTF16: Int)
}

/// SwiftUI wrapper for a read-only UITextView displaying plain or attributed text.
struct TXTTextViewBridge: UIViewRepresentable {
    let text: String
    /// Optional pre-built attributed string (e.g., from Markdown rendering).
    /// When non-nil, used directly instead of building from `text` + config.
    var attributedText: NSAttributedString?
    let config: TXTViewConfig
    var restoreOffset: Int?
    weak var delegate: TXTTextViewBridgeDelegate?

    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()
        textView.isEditable = false
        textView.isSelectable = true
        textView.showsVerticalScrollIndicator = true
        textView.alwaysBounceVertical = true
        textView.delegate = context.coordinator
        textView.textContainerInset = config.textInset
        textView.textContainer.lineFragmentPadding = 0

        // Performance: defer off-screen glyph layout for large documents.
        // TextKit 1 will only compute layout for the visible region + buffer.
        textView.layoutManager.allowsNonContiguousLayout = true

        applyText(to: textView)

        // Restore scroll position if requested
        if let offset = restoreOffset {
            DispatchQueue.main.async {
                restoreScrollPosition(in: textView, toCharOffset: offset)
            }
        }

        return textView
    }

    func updateUIView(_ textView: UITextView, context: Context) {
        // Keep delegate reference in sync (SwiftUI may recreate the struct)
        context.coordinator.delegate = delegate

        // Detect if config changed by comparing against stored config
        let lastCfg = context.coordinator.lastConfig
        let configChanged = lastCfg.fontSize != config.fontSize
            || lastCfg.fontName != config.fontName
            || lastCfg.lineSpacing != config.lineSpacing
            || lastCfg.textColor != config.textColor
            || lastCfg.backgroundColor != config.backgroundColor
            || lastCfg.letterSpacing != config.letterSpacing

        // Update text or re-apply styling if config changed
        let textChanged = textView.attributedText.string != text
        let attrChanged = attributedText != nil && !textView.attributedText.isEqual(to: attributedText!)
        if textChanged || attrChanged || configChanged {
            applyText(to: textView)
            context.coordinator.lastConfig = config
        }

        // Re-apply inset changes
        if textView.textContainerInset != config.textInset {
            textView.textContainerInset = config.textInset
        }

        // Handle offset restore — apply only once per value to avoid fighting user scroll
        if let offset = restoreOffset, context.coordinator.lastRestoredOffset != offset {
            context.coordinator.lastRestoredOffset = offset
            restoreScrollPosition(in: textView, toCharOffset: offset)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(delegate: delegate, config: config)
    }

    // MARK: - Private

    private func applyText(to textView: UITextView) {
        if let attributedText {
            // Use pre-built attributed string (e.g., from Markdown rendering)
            textView.attributedText = attributedText
            textView.adjustsFontForContentSizeCategory = true
        } else {
            // Build plain-text attributed string from text + config
            let baseFont: UIFont
            if let name = config.fontName {
                baseFont = UIFont(name: name, size: config.fontSize) ?? .systemFont(ofSize: config.fontSize)
            } else {
                baseFont = .systemFont(ofSize: config.fontSize)
            }
            let font = UIFontMetrics.default.scaledFont(for: baseFont)
            textView.adjustsFontForContentSizeCategory = true

            let paragraphStyle = NSMutableParagraphStyle()
            paragraphStyle.lineSpacing = config.lineSpacing

            var attributes: [NSAttributedString.Key: Any] = [
                .font: font,
                .paragraphStyle: paragraphStyle,
                .foregroundColor: config.textColor,
            ]
            if config.letterSpacing != 0 {
                attributes[.kern] = config.letterSpacing
            }

            textView.backgroundColor = config.backgroundColor
            textView.attributedText = NSAttributedString(string: text, attributes: attributes)
        }
    }

    private func restoreScrollPosition(in textView: UITextView, toCharOffset offset: Int) {
        let layoutManager = textView.layoutManager
        let textLength = (textView.text as NSString?)?.length ?? 0
        let clampedOffset = min(max(offset, 0), textLength)
        let scrollY = TXTOffsetMapper.charOffsetToScrollOffset(
            charOffset: clampedOffset,
            layoutManager: layoutManager,
            textContainer: textView.textContainer
        )
        textView.setContentOffset(CGPoint(x: 0, y: scrollY), animated: false)
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject, UITextViewDelegate {
        weak var delegate: TXTTextViewBridgeDelegate?
        var lastConfig: TXTViewConfig
        /// Tracks the last restored offset to avoid re-applying on every updateUIView.
        var lastRestoredOffset: Int?
        /// Throttle scroll callbacks to ~10fps to avoid expensive TextKit queries per frame.
        private var lastScrollCallbackTime: CFTimeInterval = 0
        private static let scrollThrottleInterval: CFTimeInterval = 0.1

        init(delegate: TXTTextViewBridgeDelegate?, config: TXTViewConfig = TXTViewConfig()) {
            self.delegate = delegate
            self.lastConfig = config
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

        func textViewDidChangeSelection(_ textView: UITextView) {
            let nsRange = textView.selectedRange
            if let utf16Range = TXTOffsetMapper.selectionToUTF16Range(
                nsRange: nsRange,
                text: textView.text ?? ""
            ) {
                delegate?.selectionDidChange(utf16Range: utf16Range)
            }
        }

        func scrollViewDidScroll(_ scrollView: UIScrollView) {
            guard let textView = scrollView as? UITextView else { return }

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
