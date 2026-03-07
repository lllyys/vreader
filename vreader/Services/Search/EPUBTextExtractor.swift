// Purpose: Extracts plain text from EPUB spine items for search indexing.
// Iterates spine, strips HTML tags from each XHTML document, produces TextUnits.
//
// Key decisions:
// - Uses EPUBParserProtocol for testability (mock parser in tests).
// - HTML stripping via regex is sufficient for search indexing (not rendering).
// - Removes <script>/<style> content before stripping tags.
// - Decodes common HTML entities (&amp; &lt; &gt; &quot; &apos; &#NNN;).
// - Empty spine items are skipped to avoid indexing noise.
// - sourceUnitId uses "epub:<href>" convention matching SearchHitToLocatorResolver.
//
// @coordinates-with SearchTextExtractor.swift, EPUBParserProtocol.swift,
//   SearchHitToLocatorResolver.swift

import Foundation
import os

/// Extracts searchable text from EPUB files via spine item iteration.
struct EPUBTextExtractor: SearchTextExtractor {

    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "vreader",
        category: "EPUBTextExtractor"
    )

    func extractTextUnits(
        from url: URL,
        fingerprint: DocumentFingerprint
    ) async throws -> [TextUnit] {
        let parser = EPUBParser()
        let metadata = try await parser.open(url: url)
        do {
            let units = try await extractFromParser(parser, metadata: metadata)
            await parser.close()
            return units
        } catch {
            await parser.close()
            throw error
        }
    }

    /// Extracts text units from an already-open parser.
    /// Exposed for testing with mock parsers.
    func extractFromParser(
        _ parser: any EPUBParserProtocol,
        metadata: EPUBMetadata? = nil
    ) async throws -> [TextUnit] {
        guard let meta = metadata else {
            Self.logger.warning("extractFromParser called without metadata — returning empty")
            return []
        }

        var units: [TextUnit] = []

        for item in meta.spineItems {
            do {
                let xhtml = try await parser.contentForSpineItem(href: item.href)
                let plainText = Self.stripHTML(xhtml)
                let trimmed = plainText.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { continue }

                units.append(TextUnit(
                    sourceUnitId: "epub:\(item.href)",
                    text: trimmed
                ))
            } catch {
                // Skip inaccessible spine items — partial indexing is better than none
                Self.logger.warning("Skipping spine item \(item.href): \(error.localizedDescription)")
                continue
            }
        }

        return units
    }

    // MARK: - HTML Stripping

    /// Strips HTML tags and extracts plain text for search indexing.
    /// Not a full HTML parser — uses regex patterns sufficient for FTS indexing.
    static func stripHTML(_ html: String) -> String {
        guard !html.isEmpty else { return "" }

        var text = html

        // Remove <script>...</script> and <style>...</style> with content
        text = text.replacingOccurrences(
            of: "<script[^>]*>[\\s\\S]*?</script>",
            with: "",
            options: .regularExpression
        )
        text = text.replacingOccurrences(
            of: "<style[^>]*>[\\s\\S]*?</style>",
            with: "",
            options: .regularExpression
        )

        // Replace block-level closing tags with space to preserve word boundaries
        text = text.replacingOccurrences(
            of: "</(?:p|div|h[1-6]|li|tr|td|th|br|blockquote|pre|section|article|header|footer|nav|aside)>",
            with: " ",
            options: .regularExpression
        )

        // Replace <br> and <br/> with space
        text = text.replacingOccurrences(
            of: "<br\\s*/?>",
            with: " ",
            options: .regularExpression
        )

        // Strip remaining tags
        text = text.replacingOccurrences(
            of: "<[^>]+>",
            with: "",
            options: .regularExpression
        )

        // Decode HTML entities
        text = decodeHTMLEntities(text)

        // Collapse whitespace
        text = text.replacingOccurrences(
            of: "\\s+",
            with: " ",
            options: .regularExpression
        )

        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - HTML Entity Decoding

    private static func decodeHTMLEntities(_ text: String) -> String {
        var result = text
        // Named entities
        result = result.replacingOccurrences(of: "&amp;", with: "&")
        result = result.replacingOccurrences(of: "&lt;", with: "<")
        result = result.replacingOccurrences(of: "&gt;", with: ">")
        result = result.replacingOccurrences(of: "&quot;", with: "\"")
        result = result.replacingOccurrences(of: "&apos;", with: "'")
        result = result.replacingOccurrences(of: "&nbsp;", with: " ")

        // Numeric entities &#NNN; and &#xHHH;
        if let regex = try? NSRegularExpression(pattern: "&#(x?[0-9a-fA-F]+);") {
            let nsRange = NSRange(result.startIndex..., in: result)
            let matches = regex.matches(in: result, range: nsRange)

            // Process in reverse to preserve offsets
            for match in matches.reversed() {
                guard let range = Range(match.range, in: result),
                      let codeRange = Range(match.range(at: 1), in: result) else { continue }

                let codeStr = String(result[codeRange])
                let codePoint: UInt32?
                if codeStr.hasPrefix("x") || codeStr.hasPrefix("X") {
                    codePoint = UInt32(codeStr.dropFirst(), radix: 16)
                } else {
                    codePoint = UInt32(codeStr)
                }

                if let cp = codePoint, let scalar = Unicode.Scalar(cp) {
                    result.replaceSubrange(range, with: String(scalar))
                }
            }
        }

        return result
    }
}
