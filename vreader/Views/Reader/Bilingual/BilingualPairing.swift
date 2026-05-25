// Purpose: Shared bilingual block↔translation pairing contract (Bug #266).
// Both the EPUB (`EPUBBilingualPipeline`) and AZW3/MOBI
// (`FoliateBilingualPipeline`) renderers map an ordered list of enumerated
// blocks onto an ordered list of translated segments. This is the single
// place that decides HOW they pair, so the "never a wrong pairing" invariant
// is enforced once for every format rather than copied per-pipeline.
//
// The bug: the render-side enumerate (a DOM walk) and the translation-side
// segmentation (plain-text paragraph split) are produced by independent code
// on different representations. When they diverge in count — e.g. a nested
// `<blockquote><p>` double-counts on the DOM side — pairing segment[i] onto
// block[i] up to `min(count)` drifts: paragraph N's translation lands under
// the wrong paragraph. A translation shown under the wrong paragraph is
// actively misleading — worse than showing none.
//
// Contract: pair by position ONLY when the two counts agree 1:1. On ANY
// mismatch (or no cached translation) return an empty map → the renderer
// paints source-only. The primary defense against the mismatch is making the
// enumerate count match the segmentation (EPUB now enumerates leaf blocks
// only — see `EPUBBilingualJS`); this is the fail-safe for residual divergence.
//
// @coordinates-with: EPUBBilingualPipeline.swift, FoliateBilingualPipeline.swift,
//   EPUBBilingualJS.swift, BilingualBlock.swift, ChapterSegmenter.swift

import Foundation

enum BilingualPairing {

    /// Maps each enumerated block's `bid` to its translated segment by
    /// position — but ONLY when `blocks.count == segments.count`. Returns an
    /// empty map (source-only) when there is no cached translation or the
    /// counts disagree, so a count divergence can never produce a wrong
    /// paragraph→translation pairing (Bug #266).
    static func translationsByBid(
        blocks: [BilingualBlock],
        translatedSegments: [String]?
    ) -> [String: String] {
        guard let segments = translatedSegments, !segments.isEmpty else {
            return [:]
        }
        // 1:1 or nothing. A partial (min-count) pairing is exactly the
        // misalignment this guards against.
        guard blocks.count == segments.count else {
            return [:]
        }
        var map: [String: String] = [:]
        map.reserveCapacity(blocks.count)
        for i in 0..<blocks.count {
            map[blocks[i].bid] = segments[i]
        }
        return map
    }
}
