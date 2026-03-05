// Purpose: Renders Markdown text to NSAttributedString using regex-based parsing.
// Handles CommonMark baseline: headings, bold, italic, code spans, code blocks,
// links, lists, blockquotes, thematic breaks, paragraphs.
//
// Key decisions:
// - Regex-based approach works without swift-markdown SPM dependency.
// - Future: replace with MarkupWalker from swift-markdown for full AST fidelity.
// - Normalized rendered text follows the canonical rules in WI-6B plan (Section 2.3).
// - Font sizing: H1=2.0x, H2=1.6x, H3=1.3x, H4=1.1x, H5=1.0x, H6=0.9x.
// - Code uses monospace at 0.9x. Code blocks add background color.
// - Lists: bullet prefix for unordered, number prefix for ordered.
// - Blockquotes: head indent + muted color.
//
// @coordinates-with: MDTypes.swift, MDParser.swift

import Foundation
#if canImport(UIKit)
import UIKit
#endif

/// Renders Markdown text to NSAttributedString with canonical text normalization.
enum MDAttributedStringRenderer {

    // MARK: - Heading Scale Factors

    private static let headingScales: [Int: CGFloat] = [
        1: 2.0, 2: 1.6, 3: 1.3, 4: 1.1, 5: 1.0, 6: 0.9,
    ]

    // MARK: - Public API

    /// Renders Markdown text to MDDocumentInfo with attributed string and metadata.
    static func render(text: String, config: MDRenderConfig) -> MDDocumentInfo {
        guard !text.isEmpty else {
            return MDDocumentInfo(
                renderedText: "",
                renderedAttributedString: NSAttributedString(string: ""),
                headings: [],
                title: nil
            )
        }

        let result = NSMutableAttributedString()
        var headings: [MDHeading] = []
        var firstH1Title: String?

        let lines = text.components(separatedBy: "\n")
        var index = 0

        while index < lines.count {
            let line = lines[index]

            // Fenced code block (``` or ~~~)
            if let fenceResult = parseFencedCodeBlock(lines: lines, startIndex: index, config: config) {
                let offset = (result.string as NSString).length
                result.append(fenceResult.attributedString)
                index = fenceResult.nextIndex
                _ = offset // Code blocks don't produce headings
                continue
            }

            // Thematic break (---, ***, ___)
            if isThematicBreak(line) {
                result.append(NSAttributedString(string: "\n"))
                index += 1
                continue
            }

            // ATX Heading (# through ######)
            if let headingResult = parseHeading(line: line, config: config) {
                let offset = (result.string as NSString).length
                headings.append(MDHeading(
                    level: headingResult.level,
                    text: headingResult.text,
                    charOffsetUTF16: offset
                ))
                if headingResult.level == 1 && firstH1Title == nil {
                    firstH1Title = headingResult.text
                }
                result.append(headingResult.attributedString)
                index += 1
                continue
            }

            // Blockquote (> ...)
            if line.trimmingCharacters(in: .whitespaces).hasPrefix(">") {
                let quoteResult = parseBlockquote(line: line, config: config)
                result.append(quoteResult)
                index += 1
                continue
            }

            // Unordered list (- or * or +)
            if isUnorderedListItem(line) {
                let listResult = parseUnorderedListItem(line: line, config: config)
                result.append(listResult)
                index += 1
                continue
            }

            // Ordered list (1. 2. etc.)
            if let orderedResult = parseOrderedListItem(line: line, config: config) {
                result.append(orderedResult)
                index += 1
                continue
            }

            // Empty line
            if line.trimmingCharacters(in: .whitespaces).isEmpty {
                index += 1
                continue
            }

            // Regular paragraph
            let paraResult = renderInlineMarkup(text: line, config: config)
            result.append(paraResult)
            result.append(NSAttributedString(string: "\n"))
            index += 1
        }

        let renderedText = result.string

        return MDDocumentInfo(
            renderedText: renderedText,
            renderedAttributedString: result,
            headings: headings,
            title: firstH1Title
        )
    }

    // MARK: - Block Parsers

    private static func parseHeading(
        line: String,
        config: MDRenderConfig
    ) -> (level: Int, text: String, attributedString: NSAttributedString)? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("#") else { return nil }

        var level = 0
        for ch in trimmed {
            if ch == "#" { level += 1 } else { break }
        }
        guard level >= 1, level <= 6 else { return nil }
        guard trimmed.count > level else { return nil }

        let afterHash = String(trimmed.dropFirst(level))
        guard afterHash.first == " " || afterHash.first == "\t" else { return nil }

        let headingText = afterHash
            .trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: #"\s*#+\s*$"#, with: "", options: .regularExpression)

        guard !headingText.isEmpty else { return nil }

        let scale = headingScales[level] ?? 1.0
        let fontSize = config.fontSize * scale

        #if canImport(UIKit)
        let font = UIFont.boldSystemFont(ofSize: fontSize)
        let attrStr = NSMutableAttributedString(
            string: headingText + "\n",
            attributes: [
                .font: font,
                .foregroundColor: config.textColor,
            ]
        )
        #else
        let attrStr = NSMutableAttributedString(string: headingText + "\n")
        #endif

        return (level: level, text: headingText, attributedString: attrStr)
    }

    private static func parseFencedCodeBlock(
        lines: [String],
        startIndex: Int,
        config: MDRenderConfig
    ) -> (attributedString: NSAttributedString, nextIndex: Int)? {
        let line = lines[startIndex].trimmingCharacters(in: .whitespaces)
        let fenceChar: Character
        if line.hasPrefix("```") { fenceChar = "`" }
        else if line.hasPrefix("~~~") { fenceChar = "~" }
        else { return nil }

        let fenceCount = line.prefix(while: { $0 == fenceChar }).count
        guard fenceCount >= 3 else { return nil }

        var codeLines: [String] = []
        var endIndex = startIndex + 1

        while endIndex < lines.count {
            let closingLine = lines[endIndex].trimmingCharacters(in: .whitespaces)
            let closingCount = closingLine.prefix(while: { $0 == fenceChar }).count
            let fenceSet = CharacterSet(charactersIn: String(fenceChar))
            if closingCount >= fenceCount && closingLine.trimmingCharacters(in: fenceSet).isEmpty {
                endIndex += 1
                break
            }
            codeLines.append(lines[endIndex])
            endIndex += 1
        }

        let codeText = codeLines.joined(separator: "\n") + "\n"

        #if canImport(UIKit)
        let monoFont = UIFont.monospacedSystemFont(ofSize: config.fontSize * 0.9, weight: .regular)
        let attrStr = NSAttributedString(
            string: codeText,
            attributes: [
                .font: monoFont,
                .foregroundColor: config.textColor,
                .backgroundColor: UIColor.secondarySystemBackground,
            ]
        )
        #else
        let attrStr = NSAttributedString(string: codeText)
        #endif

        return (attributedString: attrStr, nextIndex: endIndex)
    }

    private static func parseBlockquote(
        line: String,
        config: MDRenderConfig
    ) -> NSAttributedString {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        var content = String(trimmed.dropFirst()) // Remove >
        if content.hasPrefix(" ") { content = String(content.dropFirst()) }

        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.headIndent = 20
        paragraphStyle.firstLineHeadIndent = 20

        #if canImport(UIKit)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: config.fontSize),
            .foregroundColor: UIColor.secondaryLabel,
            .paragraphStyle: paragraphStyle,
        ]
        #else
        let attrs: [NSAttributedString.Key: Any] = [.paragraphStyle: paragraphStyle]
        #endif

        return NSAttributedString(string: content + "\n", attributes: attrs)
    }

    private static func isThematicBreak(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.count >= 3 else { return false }
        let stripped = trimmed.replacingOccurrences(of: " ", with: "")
        return stripped.allSatisfy({ $0 == "-" }) ||
               stripped.allSatisfy({ $0 == "*" }) ||
               stripped.allSatisfy({ $0 == "_" })
    }

    private static func isUnorderedListItem(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        return trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") || trimmed.hasPrefix("+ ")
    }

    private static func parseUnorderedListItem(
        line: String,
        config: MDRenderConfig
    ) -> NSAttributedString {
        // Count indent level (tabs or 2+ spaces per level)
        let indent = countIndentLevel(line)
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        let content = String(trimmed.dropFirst(2)) // Remove "- " / "* " / "+ "

        let prefix = String(repeating: "\t", count: indent) + "\u{2022} "
        let rendered = renderInlineMarkup(text: content, config: config)
        let result = NSMutableAttributedString(string: prefix)

        #if canImport(UIKit)
        result.addAttributes(
            [.font: UIFont.systemFont(ofSize: config.fontSize), .foregroundColor: config.textColor],
            range: NSRange(location: 0, length: result.length)
        )
        #endif

        result.append(rendered)
        result.append(NSAttributedString(string: "\n"))
        return result
    }

    private static func parseOrderedListItem(
        line: String,
        config: MDRenderConfig
    ) -> NSAttributedString? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        // Match "N. " or "N) " pattern
        guard let match = trimmed.range(of: #"^(\d+)[.)]\s"#, options: .regularExpression) else {
            return nil
        }

        let indent = countIndentLevel(line)
        let numberStr = trimmed[trimmed.startIndex..<trimmed.index(before: match.upperBound)]
            .trimmingCharacters(in: .whitespaces)
        let content = String(trimmed[match.upperBound...])

        let prefix = String(repeating: "\t", count: indent) + "\(numberStr) "
        let rendered = renderInlineMarkup(text: content, config: config)
        let result = NSMutableAttributedString(string: prefix)

        #if canImport(UIKit)
        result.addAttributes(
            [.font: UIFont.systemFont(ofSize: config.fontSize), .foregroundColor: config.textColor],
            range: NSRange(location: 0, length: result.length)
        )
        #endif

        result.append(rendered)
        result.append(NSAttributedString(string: "\n"))
        return result
    }

    private static func countIndentLevel(_ line: String) -> Int {
        var spaces = 0
        for ch in line {
            if ch == "\t" { spaces += 4 }
            else if ch == " " { spaces += 1 }
            else { break }
        }
        return spaces / 2
    }

    // MARK: - Inline Markup

    /// Renders inline Markdown (bold, italic, code spans, links) within a line.
    static func renderInlineMarkup(
        text: String,
        config: MDRenderConfig
    ) -> NSAttributedString {
        let result = NSMutableAttributedString()

        #if canImport(UIKit)
        let baseFont = UIFont.systemFont(ofSize: config.fontSize)
        let boldFont = UIFont.boldSystemFont(ofSize: config.fontSize)
        let italicFont = UIFont.italicSystemFont(ofSize: config.fontSize)
        let monoFont = UIFont.monospacedSystemFont(ofSize: config.fontSize * 0.9, weight: .regular)
        let baseAttrs: [NSAttributedString.Key: Any] = [
            .font: baseFont,
            .foregroundColor: config.textColor,
        ]
        #else
        let baseAttrs: [NSAttributedString.Key: Any] = [:]
        #endif

        // Inline patterns — find earliest match each iteration
        let patterns: [(String, String)] = [
            ("code", #"`([^`]+)`"#),
            ("boldItalic", #"\*\*\*(.+?)\*\*\*"#),
            ("bold", #"\*\*(.+?)\*\*"#),
            ("italic", #"\*(.+?)\*"#),
            ("link", #"\[([^\]]+)\]\(([^)]+)\)"#),
        ]

        var remaining = text

        while !remaining.isEmpty {
            // Find the earliest match across all patterns
            var earliest: (kind: String, range: Range<String.Index>)?
            for (kind, pattern) in patterns {
                if let range = remaining.range(of: pattern, options: .regularExpression) {
                    if earliest == nil || range.lowerBound < earliest!.range.lowerBound {
                        earliest = (kind, range)
                    }
                }
            }

            guard let match = earliest else {
                // No more inline markup — append the rest as plain text
                result.append(NSAttributedString(string: remaining, attributes: baseAttrs))
                break
            }

            // Append text before the match
            let before = String(remaining[remaining.startIndex..<match.range.lowerBound])
            if !before.isEmpty {
                result.append(NSAttributedString(string: before, attributes: baseAttrs))
            }

            let fullMatch = String(remaining[match.range])

            switch match.kind {
            case "code":
                let codeContent = String(fullMatch.dropFirst().dropLast())
                #if canImport(UIKit)
                result.append(NSAttributedString(string: codeContent, attributes: [
                    .font: monoFont, .foregroundColor: config.textColor,
                ]))
                #else
                result.append(NSAttributedString(string: codeContent))
                #endif

            case "boldItalic":
                let content = String(fullMatch.dropFirst(3).dropLast(3))
                #if canImport(UIKit)
                let biDescriptor = baseFont.fontDescriptor.withSymbolicTraits([.traitBold, .traitItalic])
                    ?? baseFont.fontDescriptor
                let biFont = UIFont(descriptor: biDescriptor, size: config.fontSize)
                result.append(NSAttributedString(string: content, attributes: [
                    .font: biFont, .foregroundColor: config.textColor,
                ]))
                #else
                result.append(NSAttributedString(string: content))
                #endif

            case "bold":
                let content = String(fullMatch.dropFirst(2).dropLast(2))
                #if canImport(UIKit)
                result.append(NSAttributedString(string: content, attributes: [
                    .font: boldFont, .foregroundColor: config.textColor,
                ]))
                #else
                result.append(NSAttributedString(string: content))
                #endif

            case "italic":
                let content = String(fullMatch.dropFirst().dropLast())
                #if canImport(UIKit)
                result.append(NSAttributedString(string: content, attributes: [
                    .font: italicFont, .foregroundColor: config.textColor,
                ]))
                #else
                result.append(NSAttributedString(string: content))
                #endif

            case "link":
                if let innerMatch = fullMatch.range(of: #"\[([^\]]+)\]"#, options: .regularExpression),
                   let urlMatch = fullMatch.range(of: #"\(([^)]+)\)"#, options: .regularExpression) {
                    let linkText = String(fullMatch[innerMatch]).dropFirst().dropLast()
                    let urlStr = String(fullMatch[urlMatch]).dropFirst().dropLast()
                    var linkAttrs = baseAttrs
                    if let url = URL(string: String(urlStr)) {
                        linkAttrs[.link] = url
                    }
                    result.append(NSAttributedString(string: String(linkText), attributes: linkAttrs))
                }

            default:
                break
            }

            remaining = String(remaining[match.range.upperBound...])
        }

        return result
    }
}
