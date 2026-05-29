// Purpose: Resolves a PDF tap location to the highlight UUID whose annotation
// contains that point. Feature #53 WI-6.
//
// PDFKit has no direct "annotation at point" API beyond `page.annotation(at:)`
// (which returns annotations of any type, including text fields and links).
// Walking the renderer's `annotationMap: [UUID: [PDFAnnotation]]` lets us
// answer the highlight-specific question and recover the UUID in one pass,
// which is what `.readerHighlightTapped`'s payload needs.
//
// Pure-function design so unit tests don't need a real PDFView gesture.
//
// @coordinates-with: PDFViewBridge.swift (gesture caller),
//   PDFHighlightRenderer.swift (annotationMap source),
//   ReaderNotifications.swift, AnnotationAnchor.swift

#if canImport(UIKit)
import Foundation
import CoreGraphics
import PDFKit

enum PDFHighlightTapResolver {
    /// Returns the UUID of the highlight whose annotation rect on `page`
    /// contains `point`, or `nil` if no highlight is hit.
    ///
    /// A highlight may comprise multiple `PDFAnnotation` objects (one per
    /// visual rect for multi-line selections); any of them containing the
    /// point counts as a hit. The first matching UUID wins — for
    /// overlapping highlights, dictionary iteration order is unspecified,
    /// so the caller should design UX around "tap one, get one" rather
    /// than relying on a specific tiebreak.
    static func resolveHighlightID(
        atPagePoint point: CGPoint,
        onPage page: PDFPage,
        annotationMap: [UUID: [PDFAnnotation]]
    ) -> UUID? {
        for (id, annotations) in annotationMap {
            for annotation in annotations {
                guard annotation.page === page else { continue }
                if annotation.bounds.contains(point) {
                    return id
                }
            }
        }
        return nil
    }

    /// Tolerance-aware variant (Bug #287 / GH #1268). A highlight
    /// annotation rect is typically a single text-line height (~17-22pt),
    /// below Apple's 44pt minimum touch target — so the exact
    /// `bounds.contains` above rejects a near-miss tap, which then turns
    /// the page instead of opening the highlight popover. This variant
    /// expands each on-page annotation rect via `HighlightHitTolerance`
    /// (bounded slop toward 44pt; zero for an already-tall annotation, so
    /// page-turn taps just outside a big highlight are not captured) and
    /// returns the highlight whose expanded rect's center is nearest the
    /// tap on overlap. Page identity is still enforced.
    static func resolveHighlightIDWithTolerance(
        atPagePoint point: CGPoint,
        onPage page: PDFPage,
        annotationMap: [UUID: [PDFAnnotation]]
    ) -> UUID? {
        // Exact membership first — a tap squarely inside highlight A must
        // resolve to A even if a nearby highlight B's expanded band would
        // also cover the point. Only when no annotation's exact bounds
        // contain the point do we consult the tolerance band.
        if let exact = resolveHighlightID(
            atPagePoint: point, onPage: page, annotationMap: annotationMap
        ) {
            return exact
        }
        var candidates: [(id: UUID, rect: CGRect)] = []
        for (id, annotations) in annotationMap {
            for annotation in annotations where annotation.page === page {
                candidates.append((id, annotation.bounds))
            }
        }
        return HighlightHitTolerance.nearestHit(point: point, candidates: candidates)
    }
}
#endif
