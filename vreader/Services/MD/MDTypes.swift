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
    #endif

    /// Creates a default render config.
    static var `default`: MDRenderConfig { MDRenderConfig() }

    static func == (lhs: MDRenderConfig, rhs: MDRenderConfig) -> Bool {
        #if canImport(UIKit)
        return lhs.fontSize == rhs.fontSize
            && lhs.lineSpacing == rhs.lineSpacing
            && lhs.textColor == rhs.textColor
        #else
        return lhs.fontSize == rhs.fontSize && lhs.lineSpacing == rhs.lineSpacing
        #endif
    }
}
