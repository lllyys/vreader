// Purpose: HighlightRenderer adapter for PDF format (Phase R4a).
// Translates highlight operations into PDFAnnotation create/remove calls.
// Maintains a highlightId → [PDFAnnotation] mapping needed for deletion
// (PDFKit has no lookup-by-ID API).
//
// Key decisions:
// - Delegates to PDFAnnotationBridge for annotation creation and rect handling.
// - annotationMap retains the ID → annotations mapping so remove(id:) can
//   find and delete the correct annotations (fixes bug #87).
// - setDocument() must be called after the PDF loads, before any operations.
// - Weak reference to PDFDocument to avoid retain cycles with PDFView.
//
// @coordinates-with: HighlightRenderer.swift, PDFAnnotationBridge.swift,
//   PDFReaderContainerView.swift, PDFViewBridge.swift,
//   HighlightCoordinator.swift

#if canImport(UIKit)
import Foundation
import PDFKit

/// Highlight renderer for PDF format.
/// Creates/removes PDFAnnotation objects and tracks them by highlight ID.
@MainActor
final class PDFHighlightRenderer: HighlightRenderer {
    /// PDF document reference. Set after document loads via `setDocument(_:)`.
    private(set) weak var document: PDFDocument?

    /// Maps highlight IDs to their created PDFAnnotation objects.
    /// Needed for deletion — PDFKit has no lookup-by-ID API.
    private(set) var annotationMap: [UUID: [PDFAnnotation]] = [:]

    /// Sets the PDF document for annotation operations.
    /// Only clears the annotation map when the document identity actually changes
    /// (e.g., new file opened). Re-setting the same document is a no-op.
    func setDocument(_ document: PDFDocument) {
        guard self.document !== document else { return }
        self.document = document
        annotationMap = [:]
    }

    func apply(record: HighlightRecord) {
        guard let document, let anchor = record.anchor else { return }
        let annotations = PDFAnnotationBridge.createHighlightFromAnchor(
            anchor, color: record.color, in: document
        )
        if !annotations.isEmpty {
            annotationMap[record.highlightId] = annotations
        }
    }

    func remove(id: UUID) {
        guard let annotations = annotationMap.removeValue(forKey: id) else { return }
        for annotation in annotations {
            annotation.page?.removeAnnotation(annotation)
        }
    }

    func restore(
        records: [HighlightRecord],
        forHref href: String?,
        using evaluator: ((String) -> Void)?
    ) {
        // PDF doesn't filter by chapter and goes through PDFAnnotation,
        // not JS — both parameters are EPUB-specific; ignored here.
        _ = (href, evaluator)
        guard let document else { return }
        annotationMap = PDFAnnotationBridge.restoreHighlights(
            for: document, from: records
        )
    }
}
#endif
