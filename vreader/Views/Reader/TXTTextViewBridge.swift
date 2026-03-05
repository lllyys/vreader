// Purpose: UIViewRepresentable wrapping UITextView for TXT document rendering.
// Provides selection range extraction, scroll position -> offset mapping,
// and configurable appearance. This is a feasibility spike prototype.
//
// Key decisions:
// - Uses TextKit 1 (NSLayoutManager) for reliable offset mapping.
// - Non-editable UITextView for reading — selection enabled for highlights.
// - Coordinator handles delegate callbacks (scroll, selection change).
// - All offset conversions delegate to TXTOffsetMapper for testability.
//
// @coordinates-with TXTOffsetMapper.swift, TXTChunkedLoader.swift, Locator.swift

#if canImport(UIKit)
import SwiftUI
import UIKit

/// Configuration for TXT text view appearance.
struct TXTViewConfig: Sendable {
    var fontSize: CGFloat = 18
    var fontName: String? = nil // nil = system font
    var lineSpacing: CGFloat = 6
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

/// SwiftUI wrapper for a read-only UITextView displaying plain text.
struct TXTTextViewBridge: UIViewRepresentable {
    let text: String
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
        // Detect if config changed by comparing against stored config
        let configChanged = context.coordinator.lastConfig.fontSize != config.fontSize
            || context.coordinator.lastConfig.fontName != config.fontName
            || context.coordinator.lastConfig.lineSpacing != config.lineSpacing

        // Update text or re-apply styling if config changed
        if textView.attributedText.string != text || configChanged {
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

        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .paragraphStyle: paragraphStyle,
            .foregroundColor: UIColor.label,
        ]

        textView.attributedText = NSAttributedString(string: text, attributes: attributes)
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

        init(delegate: TXTTextViewBridgeDelegate?, config: TXTViewConfig = TXTViewConfig()) {
            self.delegate = delegate
            self.lastConfig = config
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
            guard let textView = scrollView as? UITextView else {
                return
            }

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
