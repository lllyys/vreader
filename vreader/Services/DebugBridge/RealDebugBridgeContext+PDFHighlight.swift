// Purpose: `pdf-highlight` command handler for the vreader-debug:// scheme
// (feature #17 verification harness — drive PDF highlight CREATION CU-free so
// the selection-driven highlight → PDFAnnotation render + persist can be
// device-verified WITHOUT a real long-press-drag text selection, which needs a
// real touch / CU unavailable on the virtual-display test environment). This
// command posts `.debugBridgePDFHighlightCommand` carrying the page index, the
// normalized rect (as a 4-element `[Double]` `[x, y, w, h]`), and the optional
// color. The live `PDFReaderContainerView` observer builds a
// `ReaderSelectionEvent` with a `.pdf` anchor and calls the SAME
// `handleHighlightAction` the gesture uses (coordinator →
// PersistenceActor.addHighlight → PDFAnnotationBridge.createHighlightFromAnchor)
// — no parallel highlight-creation routine.
// DEBUG-only — entire file compiled out of Release.
//
// Split from RealDebugBridgeContext.swift for the 300-line LOC guideline
// (mirrors RealDebugBridgeContext+ScrollBoundary.swift / +Navigate.swift).
//
// @coordinates-with: DebugBridge.swift, DebugCommand.swift,
//   DebugBridgeNotifications.swift,
//   PDFReaderContainerView+DebugBridgePDFHighlight.swift
//   (the .debugBridgePDFHighlightCommand observer), RealDebugBridgeContextTests.swift

#if DEBUG

import Foundation

extension RealDebugBridgeContext {

    /// Feature #17 — drive PDF highlight CREATION for the active PDF reader.
    ///
    /// Posts `.debugBridgePDFHighlightCommand` carrying the `page` index, the
    /// normalized `rect` as a 4-element `[Double]` `[x, y, w, h]`, and the
    /// optional `color`. The live `PDFReaderContainerView` observes it, builds
    /// a `ReaderSelectionEvent` whose anchor is `AnnotationAnchor.pdf(page:,
    /// rects:)`, and calls the SAME `handleHighlightAction` the long-press-drag
    /// gesture path uses — so the highlight is persisted AND rendered through
    /// the production creation seam (no parallel routine). If no PDF reader is
    /// loaded the URL is silently a no-op (the same posture as `highlight` /
    /// `navigate` / `seek` / `present`).
    func pdfHighlight(page: Int, rect: NormalizedRect, color: String?) async throws {
        var userInfo: [String: Any] = [
            "page": page,
            "rect": [rect.x, rect.y, rect.w, rect.h]
        ]
        if let color {
            userInfo["color"] = color
        }
        NotificationCenter.default.post(
            name: .debugBridgePDFHighlightCommand,
            object: nil,
            userInfo: userInfo
        )
        log.info(
            "pdfHighlight: posted pdfHighlightCommand page=\(page, privacy: .public) rect=\(rect.x, privacy: .public),\(rect.y, privacy: .public),\(rect.w, privacy: .public),\(rect.h, privacy: .public) color=\(color ?? "nil", privacy: .public)"
        )
    }
}

#endif
