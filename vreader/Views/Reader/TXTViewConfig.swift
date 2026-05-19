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

    /// Feature #68: drop-cap color for the chapter-start initial. Used
    /// only by `TXTAttributedStringBuilder.buildChapterStart`. Defaults
    /// to a near-black matching the `textColor` default so non-chapter
    /// call sites (tests, previews) keep their existing render. The live
    /// reader sets this to `ReaderThemeV2.accentColor` via the store.
    var accentColor: UIColor = UIColor(red: 0.10, green: 0.10, blue: 0.10, alpha: 1.0)

    /// Feature #68: in-text chapter-heading color. Used only by
    /// `buildChapterStart`'s heading-restyle path (regex-detected
    /// chapters). Defaults to a mid-gray for back-compat. The live reader
    /// sets this to `ReaderThemeV2.subColor` via the store.
    var chapterHeadingColor: UIColor = UIColor(white: 0.4, alpha: 1.0)

    /// Returns true if rendering-relevant fields match (excludes textInset).
    func renderingEquals(_ other: TXTViewConfig) -> Bool {
        fontSize == other.fontSize
            && fontName == other.fontName
            && lineSpacing == other.lineSpacing
            && textColor == other.textColor
            && backgroundColor == other.backgroundColor
            && letterSpacing == other.letterSpacing
            && accentColor == other.accentColor
            && chapterHeadingColor == other.chapterHeadingColor
    }
}

/// Callback events from the text view bridge.
@MainActor
protocol TXTTextViewBridgeDelegate: AnyObject {
    /// Called when the user's selection changes. Range is in UTF-16 offsets.
    func selectionDidChange(utf16Range: UTF16Range)
    /// Called when the visible scroll position changes. Offset is in UTF-16 units.
    func scrollPositionDidChange(topCharOffsetUTF16: Int)
}
#endif
