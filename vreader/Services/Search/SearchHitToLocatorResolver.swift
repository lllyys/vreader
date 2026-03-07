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
            textQuote: hit.snippet
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
            textQuote: hit.snippet
        )
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

        let globalOffset = segBase + hit.matchStartOffsetUTF16

        return LocatorFactory.txtPosition(
            fingerprint: fingerprint,
            charOffsetUTF16: globalOffset
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

        let globalOffset = segBase + hit.matchStartOffsetUTF16

        return LocatorFactory.mdPosition(
            fingerprint: fingerprint,
            charOffsetUTF16: globalOffset
        )
    }
}
