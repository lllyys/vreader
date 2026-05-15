// Purpose: Converts SearchHit into a Locator using format-specific resolution logic.
// Parses sourceUnitId to determine format, then delegates to LocatorFactory.
//
// Key decisions:
// - sourceUnitId parsing is the single source of truth for format detection.
// - EPUB: "epub:<href>" → LocatorFactory.epub with progression=0 (search doesn't know position).
// - PDF: "pdf:page:<N>" → LocatorFactory.pdf with page number.
// - TXT: "txt:segment:<N>" → compute global UTF-16 offset from segment base + hit offset.
// - MD: "md:segment:<N>" → same offset logic as TXT, using LocatorFactory.mdPosition.
// - Returns nil for unrecognized formats or invalid sourceUnitId formats.
//
// @coordinates-with SearchHit (SearchIndexStore.swift), LocatorFactory.swift, TokenSpan.swift,
//   MDTextExtractor.swift

import Foundation

/// Resolves search hits to Locator positions for reader navigation.
enum SearchHitToLocatorResolver {

    /// Resolves a search hit to a Locator.
    ///
    /// - Parameters:
    ///   - hit: The search result to resolve.
    ///   - fingerprint: The document's fingerprint.
    ///   - segmentBaseOffsets: For TXT format, maps segment index → cumulative UTF-16 offset.
    ///                         Not needed for EPUB/PDF.
    /// - Returns: A Locator for navigating to the search result, or nil if resolution fails.
    static func resolve(
        hit: SearchHit,
        fingerprint: DocumentFingerprint,
        segmentBaseOffsets: [Int: Int]? = nil
    ) -> Locator? {
        let unitId = hit.sourceUnitId
        guard !unitId.isEmpty else { return nil }

        if unitId.hasPrefix("epub:") {
            return resolveEPUB(hit: hit, fingerprint: fingerprint, unitId: unitId)
        } else if unitId.hasPrefix("pdf:page:") {
            return resolvePDF(hit: hit, fingerprint: fingerprint, unitId: unitId)
        } else if unitId.hasPrefix("txt:segment:") {
            return resolveTXT(
                hit: hit,
                fingerprint: fingerprint,
                unitId: unitId,
                segmentBaseOffsets: segmentBaseOffsets
            )
        } else if unitId.hasPrefix("md:segment:") {
            return resolveMD(
                hit: hit,
                fingerprint: fingerprint,
                unitId: unitId,
                segmentBaseOffsets: segmentBaseOffsets
            )
        }

        return nil
    }

    // MARK: - Private

    private static func resolveEPUB(
        hit: SearchHit,
        fingerprint: DocumentFingerprint,
        unitId: String
    ) -> Locator? {
        // "epub:chapter1.xhtml" → href = "chapter1.xhtml"
        let href = String(unitId.dropFirst("epub:".count))
        guard !href.isEmpty else { return nil }

        return LocatorFactory.epub(
            fingerprint: fingerprint,
            href: href,
            progression: 0, // Search doesn't know within-chapter position
            textQuote: cleanSnippetForTextQuote(hit.snippet)
        )
    }

    private static func resolvePDF(
        hit: SearchHit,
        fingerprint: DocumentFingerprint,
        unitId: String
    ) -> Locator? {
        // "pdf:page:5" → page = 5
        let pageStr = String(unitId.dropFirst("pdf:page:".count))
        guard let page = Int(pageStr), page >= 0 else { return nil }

        return LocatorFactory.pdf(
            fingerprint: fingerprint,
            page: page,
            textQuote: cleanSnippetForTextQuote(hit.snippet)
        )
    }

    /// Strips display chrome from a search snippet so the resulting string is
    /// safe to feed into plain-text matchers (`window.find()` for EPUB, PDFKit
    /// `findString(_:withOptions:)` for PDF).
    ///
    /// `SearchQueryExecutor.extractSnippet` returns
    /// `"...prefix<b>match</b>suffix..."` for display in the search results
    /// list. Plain-text matchers cannot find literal `<b>` tags or leading
    /// `...` ellipses in rendered DOM/page text, so the yellow search
    /// highlight silently never paints when the raw snippet is stashed as
    /// `textQuote` (Bug #182 / GH #594).
    ///
    /// Strategy: when the snippet contains a `<b>…</b>` pair, return just the
    /// bolded text — that's the actual matched portion of the source. When the
    /// bold pair is missing (defensive fallback for future snippet format
    /// changes), strip leading/trailing `...` markers and any literal `<b>` /
    /// `</b>` markers (the only HTML emitted by `extractSnippet` today). Other
    /// angle-bracket text — math notation like `1 < 2 > 1`, generics — is
    /// preserved verbatim. Returns `nil` for `nil` input or for snippets that
    /// collapse to empty after cleaning.
    static func cleanSnippetForTextQuote(_ snippet: String?) -> String? {
        guard let snippet, !snippet.isEmpty else { return nil }

        // Prefer the <b>…</b> matched portion: it's the exact substring of the
        // chapter / page text that the matcher needs to find. Trim defensively
        // — an empty or whitespace-only match (e.g. `<b></b>` from a corrupt
        // snippet) would behave as "match everything" / "no-op" downstream
        // depending on which matcher consumes it. Returning nil here lets the
        // reader skip the highlight pass entirely instead of silently no-oping.
        if let openRange = snippet.range(of: "<b>"),
           let closeRange = snippet.range(
               of: "</b>", range: openRange.upperBound..<snippet.endIndex
           ) {
            let match = String(snippet[openRange.upperBound..<closeRange.lowerBound])
            let trimmed = match.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : match
        }

        // Fallback: strip the display chrome (leading/trailing ellipses and
        // ONLY the specific `<b>` / `</b>` markers that extractSnippet emits).
        // Deliberately narrow — a permissive `<...>` strip would mangle math
        // notation like "1 < 2 > 1" or future snippet formats containing
        // literal angle brackets.
        var cleaned = snippet
        while cleaned.hasPrefix("...") { cleaned.removeFirst(3) }
        while cleaned.hasSuffix("...") { cleaned.removeLast(3) }
        cleaned = cleaned.replacingOccurrences(of: "<b>", with: "")
        cleaned = cleaned.replacingOccurrences(of: "</b>", with: "")
        let trimmed = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func resolveTXT(
        hit: SearchHit,
        fingerprint: DocumentFingerprint,
        unitId: String,
        segmentBaseOffsets: [Int: Int]?
    ) -> Locator? {
        // "txt:segment:2" → segmentIndex = 2
        let segStr = String(unitId.dropFirst("txt:segment:".count))
        guard let segIndex = Int(segStr), segIndex >= 0 else { return nil }

        // Compute global UTF-16 offset: segment base + match offset within segment
        guard let bases = segmentBaseOffsets, let segBase = bases[segIndex] else {
            return nil
        }

        let globalStart = segBase + hit.matchStartOffsetUTF16
        let globalEnd = segBase + hit.matchEndOffsetUTF16

        return Locator.validated(
            bookFingerprint: fingerprint,
            charOffsetUTF16: globalStart,
            charRangeStartUTF16: globalStart,
            charRangeEndUTF16: globalEnd
        )
    }

    private static func resolveMD(
        hit: SearchHit,
        fingerprint: DocumentFingerprint,
        unitId: String,
        segmentBaseOffsets: [Int: Int]?
    ) -> Locator? {
        // "md:segment:1" → segmentIndex = 1
        let segStr = String(unitId.dropFirst("md:segment:".count))
        guard let segIndex = Int(segStr), segIndex >= 0 else { return nil }

        guard let bases = segmentBaseOffsets, let segBase = bases[segIndex] else {
            return nil
        }

        let globalStart = segBase + hit.matchStartOffsetUTF16
        let globalEnd = segBase + hit.matchEndOffsetUTF16

        return Locator.validated(
            bookFingerprint: fingerprint,
            charOffsetUTF16: globalStart,
            charRangeStartUTF16: globalStart,
            charRangeEndUTF16: globalEnd
        )
    }
}
