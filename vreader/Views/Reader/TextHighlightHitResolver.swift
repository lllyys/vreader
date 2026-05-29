// Purpose: Layout-aware tap-on-highlight resolution for the TXT/MD native
// bridges (Bug #287 / GH #1268). Wraps the pure char-index
// `TextHighlightHitTester` with a 44pt-minimum-touch-target tolerance
// (`HighlightHitTolerance`): when the tap's exact character index lands
// outside every highlight range, fall back to expanding each highlight's
// glyph bounding rect toward the HIG minimum and resolve the nearest
// expanded band. This is the seam that lets a near-miss tap open the
// highlight popover (and be absorbed) instead of falling through to the
// page-turn / chrome-toggle router.
//
// Needs a `NSLayoutManager` + `NSTextContainer` to compute glyph rects,
// so it lives here rather than in the pure `TextHighlightHitTester`. The
// tolerance math itself stays in the pure `HighlightHitTolerance`.
//
// @coordinates-with: TextHighlightHitTester.swift, HighlightHitTolerance.swift,
//   TXTTextViewBridgeCoordinator.swift, TXTChunkedReaderBridge.swift

#if canImport(UIKit)
import Foundation
import UIKit

enum TextHighlightHitResolver {
    /// Resolves a tap (in text-container coordinates) to a highlight lookup
    /// entry. Exact char-index membership wins first; on a miss, the
    /// tolerance band over each highlight's glyph rect is consulted. Returns
    /// nil when neither path resolves — the caller then routes the tap to
    /// the page-turn / chrome path.
    @MainActor
    static func resolve(
        containerPoint: CGPoint,
        layoutManager: NSLayoutManager,
        textContainer: NSTextContainer,
        lookup: [PersistedHighlightLookupEntry]
    ) -> PersistedHighlightLookupEntry? {
        guard !lookup.isEmpty else { return nil }

        // 1) Exact path — preserves the prior overlap "most-recent wins" rule.
        let charIndex = layoutManager.characterIndex(
            for: containerPoint,
            in: textContainer,
            fractionOfDistanceBetweenInsertionPoints: nil
        )
        if let exact = TextHighlightHitTester.hitTest(charIndex: charIndex, in: lookup) {
            return exact
        }

        // 2) Tolerance path — expand each highlight's per-line glyph rects
        // toward the 44pt minimum and resolve the nearest expanded band.
        // Per-line-fragment rects (not the single union bounding box) so a
        // multi-line highlight's ragged-edge whitespace gaps are NOT
        // absorbed — only the actually-painted fragments get a slop band.
        var candidates: [(id: UUID, rect: CGRect)] = []
        for entry in lookup where entry.range.length > 0 {
            let glyphRange = layoutManager.glyphRange(
                forCharacterRange: entry.range, actualCharacterRange: nil
            )
            guard glyphRange.length > 0 else { continue }
            layoutManager.enumerateEnclosingRects(
                forGlyphRange: glyphRange,
                withinSelectedGlyphRange: NSRange(location: NSNotFound, length: 0),
                in: textContainer
            ) { rect, _ in
                if rect.width > 0, rect.height > 0 {
                    candidates.append((entry.id, rect))
                }
            }
        }
        guard let nearestID = HighlightHitTolerance.nearestHit(
            point: containerPoint, candidates: candidates
        ) else { return nil }
        return lookup.first(where: { $0.id == nearestID })
    }
}
#endif
