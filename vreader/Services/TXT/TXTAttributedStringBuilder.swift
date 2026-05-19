// Purpose: Builds NSAttributedString from plain text + TXTViewConfig.
// Extracted from TXTTextViewBridge.applyText so it can run off the main thread.
//
// Key decisions:
// - Static, pure function with no UIKit view dependencies.
// - @Sendable safe — can be called from Task.detached for background construction.
// - UIFontMetrics scaling applied for Dynamic Type support.
// - Feature #68: `buildChapterStart` adds the design's chapter-start
//   typography (serif heading restyle + accent drop-cap). CONTRACT — it
//   only ever ADDS attributes; the backing string is byte-identical to
//   the input, so every offset-based subsystem (positions, highlights,
//   search, TTS) is unaffected. The plain `build` path is untouched.
//
// @coordinates-with: TXTTextViewBridge.swift, TXTReaderContainerView.swift,
//   ChapterStartTypography.swift

#if canImport(UIKit)
import UIKit

/// Sendable wrapper for NSAttributedString, safe because the wrapped value
/// is immutable and never mutated after construction.
struct SendableAttributedString: @unchecked Sendable {
    let value: NSAttributedString
}

enum TXTAttributedStringBuilder {

    /// Builds a Sendable-wrapped NSAttributedString for cross-isolation transfer.
    static func buildSendable(text: String, config: TXTViewConfig) -> SendableAttributedString {
        SendableAttributedString(value: build(text: text, config: config))
    }

    /// Builds an NSAttributedString from plain text and the given config.
    /// Safe to call from any thread.
    static func build(text: String, config: TXTViewConfig) -> NSAttributedString {
        let baseFont: UIFont
        if let name = config.fontName {
            baseFont = UIFont(name: name, size: config.fontSize)
                ?? .systemFont(ofSize: config.fontSize)
        } else {
            baseFont = .systemFont(ofSize: config.fontSize)
        }
        let font = UIFontMetrics.default.scaledFont(for: baseFont)

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

        return NSAttributedString(string: text, attributes: attributes)
    }

    // MARK: - Chapter-start typography (feature #68 WI-2)

    /// Builds a Sendable-wrapped chapter-start attributed string.
    static func buildChapterStartSendable(
        text: String, config: TXTViewConfig, headingLineLength: Int
    ) -> SendableAttributedString {
        SendableAttributedString(value: buildChapterStart(
            text: text, config: config, headingLineLength: headingLineLength
        ))
    }

    /// Builds the attributed string for a chapter, applying the design's
    /// chapter-start typography (feature #68) via `TXTChapterStartDecorator`.
    ///
    /// CONTRACT: the returned string's backing `.string` is IDENTICAL to
    /// `build(text:config:).string` — only attributes are added. No
    /// characters are inserted, removed, or case-transformed.
    ///
    /// - Parameters:
    ///   - text: the chapter's body text (already Chinese-converted if
    ///     applicable — the conversion runs upstream).
    ///   - config: appearance; `accentColor` drives the drop-cap,
    ///     `chapterHeadingColor` drives the heading restyle.
    ///   - headingLineLength: UTF-16 length of the leading heading line
    ///     that is ALREADY part of `text` (regex-detected chapters). 0
    ///     means no heading line is present in the body (synthetic /
    ///     "前言" chapters) — those chapters get the drop-cap only, with
    ///     NO heading restyle.
    static func buildChapterStart(
        text: String, config: TXTViewConfig, headingLineLength: Int
    ) -> NSAttributedString {
        let base = build(text: text, config: config)
        return TXTChapterStartDecorator.decorate(
            base: base, text: text, config: config,
            headingLineLength: headingLineLength
        )
    }
}
#endif
