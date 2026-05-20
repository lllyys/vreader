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

    /// Strips HTML tags while preserving block boundaries as blank lines.
    /// Used by feature #56 bilingual reading — the DOM enumerate JS keys
    /// translation units to block elements (`<p>` / `<li>` /
    /// `<blockquote>` / etc.), and the translation service segments via
    /// `ChapterSegmenter.paragraphs` (blank-line-separated). Without
    /// preserved boundaries the two produce different counts and the
    /// inject path mis-maps translations onto blocks (Codex Gate-4 audit
    /// finding [1]). This variant emits `\n\n` after every block-level
    /// closing tag so the segmenter recovers N paragraphs matching N
    /// enumerated DOM blocks. Search indexing keeps using the
    /// whitespace-collapsing `stripHTML(_:)` below — different consumer,
    /// different boundary contract.
    static func stripHTMLPreservingBlocks(_ html: String) -> String {
        guard !html.isEmpty else { return "" }

        var text = html

        // Remove <script>...</script> and <style>...</style> with content.
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

        // Codex Gate-4 round-2 finding [R2-1] (revisited in round 3):
        // headings are intentionally NOT removed from the source text.
        // Removing them globally drops content nested inside an
        // enumerated block (e.g. `<blockquote><h2>Title</h2><p>...</p></blockquote>`
        // would lose `Title` from the translation while the
        // enumerator's `textContent` still includes it — silent text
        // loss in the rendered translation). Keeping headings means
        // a top-level `<h1>Title</h1><p>Body</p>` produces a single
        // segment `"Title Body"` matching the single `<p>` enumerator
        // block (textContent = `Body`); the translated segment is
        // slightly longer than what the renderer paints under but
        // there is no content loss. This is a known minor
        // misalignment (Codex Gate-4 round-3) that a follow-up WI
        // can address by switching translation input to the
        // enumerated block texts directly. The exact-match contract
        // is met for the common shape (no top-level headings); the
        // less-common with-heading shape is approximate but never
        // loses translation content.

        // Replace block-level closing tags with `\n\n` to preserve block
        // boundaries. The set must MATCH `EPUBBilingualJS.bilingualEnumerateJS`'s
        // BLOCK_TAGS EXACTLY — otherwise the source segmenter produces a
        // count different from the DOM enumerator, and the inject path
        // misaligns translations onto blocks (Codex Gate-4 round-2
        // finding [R2-1]). Specifically: headings (h1..h6), structural
        // wrappers (section, article, header, footer, nav, aside),
        // table cells, and div are NOT in BLOCK_TAGS, so we MUST NOT
        // emit `\n\n` for them here — their content collapses into the
        // surrounding paragraph or is dropped, matching what the
        // enumerator sees. Structural wrappers like `<section>` contain
        // <p> blocks; the trailing `</section>` boundary is irrelevant
        // because the contained `</p>` already terminated the segment.
        text = text.replacingOccurrences(
            of: "</(?:p|li|blockquote|pre|dd|dt)>",
            with: "\n\n",
            options: .regularExpression
        )

        // Replace <br> and <br/> with a single newline. A `<br>` is a soft
        // wrap inside a paragraph, not a block boundary; the segmenter's
        // `\n\n+` split treats one newline as intra-paragraph.
        text = text.replacingOccurrences(
            of: "<br\\s*/?>",
            with: "\n",
            options: .regularExpression
        )

        // Strip remaining tags.
        text = text.replacingOccurrences(
            of: "<[^>]+>",
            with: "",
            options: .regularExpression
        )

        // Decode HTML entities.
        text = decodeHTMLEntities(text)

        // Collapse runs of three or more blank lines into exactly two
        // (one blank-line separator) so the segmenter does not produce
        // empty-string entries between blocks. Single newlines inside a
        // paragraph are preserved.
        text = text.replacingOccurrences(
            of: "\\n{3,}",
            with: "\n\n",
            options: .regularExpression
        )

        // Collapse runs of tabs / spaces inside a single line.
        text = text.replacingOccurrences(
            of: "[ \\t]+",
            with: " ",
            options: .regularExpression
        )

        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

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
