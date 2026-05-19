// Purpose: Data types for the Markdown reader: document info, render config, heading.
//
// Key decisions:
// - MDDocumentInfo holds both rendered text and NSAttributedString for dual use.
// - MDRenderConfig is Sendable for cross-actor transfer.
// - MDHeading captures level + title + character offset for future outline.
//
// @coordinates-with: MDParserProtocol.swift, MDReaderViewModel.swift

#if canImport(UIKit)
import UIKit
#endif
import Foundation

/// Metadata about a parsed Markdown document.
/// Note: @unchecked Sendable because NSAttributedString is immutable once constructed.
struct MDDocumentInfo: @unchecked Sendable {
    /// The rendered plain text (Markdown syntax stripped, list bullets materialized).
    let renderedText: String

    /// The rendered attributed string for rich display.
    let renderedAttributedString: NSAttributedString

    /// Headings found in the document (for future outline support).
    let headings: [MDHeading]

    /// Extracted title (first H1, or nil if none found).
    let title: String?

    /// Total rendered text length in UTF-16 code units.
    var renderedTextLengthUTF16: Int {
        (renderedText as NSString).length
    }
}

/// A heading found in the Markdown document.
struct MDHeading: Sendable, Equatable {
    /// Heading level (1-6).
    let level: Int
    /// Heading text content.
    let text: String
    /// Character offset (UTF-16) in the rendered text where this heading starts.
    let charOffsetUTF16: Int
}

/// Configuration for Markdown rendering appearance.
/// Note: @unchecked Sendable because UIColor is effectively immutable.
struct MDRenderConfig: @unchecked Sendable, Equatable {
    /// Base font size for body text.
    var fontSize: CGFloat = 18

    /// Line spacing between lines.
    var lineSpacing: CGFloat = 6

    #if canImport(UIKit)
    /// Text color for body text.
    var textColor: UIColor = .label

    /// Text color for secondary content (blockquote bodies). Feature
    /// #60 WI-5: this carries `ReaderThemeV2.subColor` so blockquotes
    /// pick up the per-theme alpha-blended dimmer-than-ink tint
    /// instead of the platform-default `.secondaryLabel`.
    /// Defaults to `.secondaryLabel` for backward compat with the
    /// platform-default render path.
    var secondaryColor: UIColor = .secondaryLabel

    /// Surface color for code-block backgrounds. Feature #60 WI-5:
    /// this carries `ReaderThemeV2.paperColor` so fenced code blocks
    /// pick up the per-theme paper-stack surface instead of the
    /// platform-default `.secondarySystemBackground`. The result is
    /// a subtle elevated-surface tint that follows the active theme.
    /// Defaults to `.secondarySystemBackground` for backward compat.
    var codeBackgroundColor: UIColor = .secondarySystemBackground

    /// Feature #68: drop-cap color for chapter-start typography. Used
    /// only by `MDChapterStartDecorator`. Defaults to `.label` for
    /// back-compat with non-decorated render paths (tests/previews).
    /// The live reader sets this to `ReaderThemeV2.accentColor`.
    var accentColor: UIColor = .label

    /// Feature #68: chapter-heading color for chapter-start typography.
    /// Used only by `MDChapterStartDecorator`'s leading-heading restyle.
    /// Defaults to `.secondaryLabel`. The live reader sets this to
    /// `ReaderThemeV2.subColor`.
    var chapterHeadingColor: UIColor = .secondaryLabel
    #endif

    /// Creates a default render config.
    static var `default`: MDRenderConfig { MDRenderConfig() }

    static func == (lhs: MDRenderConfig, rhs: MDRenderConfig) -> Bool {
        #if canImport(UIKit)
        return lhs.fontSize == rhs.fontSize
            && lhs.lineSpacing == rhs.lineSpacing
            && lhs.textColor == rhs.textColor
            && lhs.secondaryColor == rhs.secondaryColor
            && lhs.codeBackgroundColor == rhs.codeBackgroundColor
            && lhs.accentColor == rhs.accentColor
            && lhs.chapterHeadingColor == rhs.chapterHeadingColor
        #else
        return lhs.fontSize == rhs.fontSize && lhs.lineSpacing == rhs.lineSpacing
        #endif
    }
}
