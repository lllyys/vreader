// Purpose: Configuration types shared by TXT/MD text view bridges.
// Contains the appearance configuration struct and the delegate protocol
// for selection/scroll callbacks.
//
// @coordinates-with TXTTextViewBridge.swift, TXTChunkedReaderBridge.swift,
//   MDReaderContainerView.swift

#if canImport(UIKit)
import UIKit

/// Configuration for TXT text view appearance.
struct TXTViewConfig: @unchecked Sendable {
    var fontSize: CGFloat = 18
    var fontName: String? = nil // nil = system font
    var lineSpacing: CGFloat = 6
    var textColor: UIColor = UIColor(red: 0.10, green: 0.10, blue: 0.10, alpha: 1.0)
    var backgroundColor: UIColor = .white
    var letterSpacing: CGFloat = 0
    var textInset: UIEdgeInsets = UIEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)

    /// Returns true if rendering-relevant fields match (excludes textInset).
    func renderingEquals(_ other: TXTViewConfig) -> Bool {
        fontSize == other.fontSize
            && fontName == other.fontName
            && lineSpacing == other.lineSpacing
            && textColor == other.textColor
            && backgroundColor == other.backgroundColor
            && letterSpacing == other.letterSpacing
    }
}

/// Callback events from the text view bridge.
@MainActor
protocol TXTTextViewBridgeDelegate: AnyObject {
    /// Called when the user's selection changes. Range is in UTF-16 offsets.
    func selectionDidChange(utf16Range: UTF16Range)
    /// Called when the visible scroll position changes. Offset is in UTF-16 units.
    func scrollPositionDidChange(topCharOffsetUTF16: Int)
    /// Bug #180: user reached the bottom of the loaded chapter and the scroll
    /// has settled there. ViewModels typically respond by advancing to the
    /// next chapter (no-op when there is none). Default impl is empty so
    /// callers other than TXTReaderViewModel stay unaffected.
    func didScrollPastBottomBoundary()
    /// Bug #180: user reached the top of the loaded chapter and the scroll
    /// has settled there. ViewModels typically respond by going to the
    /// previous chapter. Default impl is empty.
    func didScrollPastTopBoundary()
}

extension TXTTextViewBridgeDelegate {
    func didScrollPastBottomBoundary() {}
    func didScrollPastTopBoundary() {}
}
#endif
