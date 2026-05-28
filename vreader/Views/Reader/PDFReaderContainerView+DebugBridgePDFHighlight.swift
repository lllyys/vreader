// Purpose: DEBUG-only `pdf-highlight` observer for PDFReaderContainerView
// (feature #17 verification harness). The `pdf-highlight` DebugBridge command
// (`RealDebugBridgeContext+PDFHighlight.swift`) posts
// `.debugBridgePDFHighlightCommand` carrying a page index + a normalized rect
// (0...1 page coordinate space) + an optional color; this modifier builds the
// SAME `ReaderSelectionEvent` (anchor `AnnotationAnchor.pdf(page:, rects:)`)
// the long-press-drag selection gesture produces and calls
// `PDFReaderContainerView.handleHighlightAction(event:container:color:)`
// directly — the SAME production creation path (coordinator →
// PersistenceActor.addHighlight → PDFAnnotationBridge.createHighlightFromAnchor)
// — so the highlight is persisted AND rendered as a PDFAnnotation. There is NO
// parallel highlight-creation routine; the bridge-created highlight is
// byte-identical to a gesture-created one at the same (page, rect): same
// `Locator.page`, same anchor rects, same `selectedText`, same color.
//
// Faithfulness guards (Codex Gate-4 rounds 1 + 2):
// - HIGH 1 (r1) — the observer no-ops unless the document is loaded and `page`
//   is in range; otherwise the anchor would render nothing while the record was
//   already persisted (an invisible, library-contaminating highlight).
// - MEDIUM 1 (r1) — the observer navigates the PDF to `page` FIRST so the
//   persisted locator page (derived from `currentPageIndex`) equals the anchor
//   page — mirroring the gesture reality that you can only select the visible
//   page.
// - MEDIUM 1 (r2) — `selectedText` is derived from the LIVE, already-unlocked
//   `PDFDocument` the reader is showing (read via `highlightRenderer.document`,
//   bound by `PDFViewBridge`), NOT a fresh `PDFDocument(url:)` (expensive on
//   large PDFs + still-LOCKED for password PDFs).
// - MEDIUM 2 (r2) — a bridge highlight is created ONLY when real glyphs sit
//   under the rect. When the live selection is empty / whitespace the observer
//   NO-OPs + logs (no highlight) — mirroring production `selectionDidChange`,
//   which never posts `.readerTextSelected` for an empty selection. There is no
//   create-anyway marker path.
// - HIGH 2 (r1) / HIGH (r2) — the parser rejects page-overflow rects AND
//   zero-area rects (`w <= 0` / `h <= 0`); a real selection always has positive
//   area on the page.
// - MEDIUM 3 (r1) — the observer routes every injection through the single
//   `handleHighlightAction` with the requested color (default yellow).
//
// Why this seam (not a real touch): the gesture path needs a long-press-drag
// text selection, which requires a real touch / CU; the virtual-display test
// environment can't synthesize it. PDFKit's `selectionDidChange` only produces
// the (page, normalized-rects) anchor — exactly what this command supplies
// directly — so injecting at the anchor boundary faithfully reuses everything
// downstream of the selection.
//
// Format scoping: only the PDF host registers this observer. EPUB / TXT / MD /
// AZW3 hosts don't, so a stray URL fired while they're mounted is silently a
// no-op (a PDF-shaped highlight persisted against a non-PDF book would be
// invisible and contaminate the library) — the same posture as the TXT/MD
// `highlight` observer.
//
// Lives in its own `ViewModifier` (mirroring
// `EPUBReaderContainerView+DebugBridgeScrollBoundary.swift`) so the PDF body
// stays within the Swift type-checker's complexity budget. Entire file
// compiled out of Release builds via `#if DEBUG`; the Release stub supplies an
// `EmptyModifier` so DebugBridge symbols never leak.
//
// @coordinates-with PDFReaderContainerView.swift,
//   PDFReaderContainerView+Highlights.swift, PDFAnnotationBridge.swift,
//   DebugBridgeNotifications.swift, RealDebugBridgeContext+PDFHighlight.swift

import SwiftUI

#if canImport(UIKit)

#if !DEBUG
// Release stub: the body of PDFReaderContainerView references
// `debugBridgePDFHighlightObserverModifier`; we provide an `EmptyModifier`
// here so Release builds compile without any DebugBridge symbols.
extension PDFReaderContainerView {
    var debugBridgePDFHighlightObserverModifier: EmptyModifier {
        EmptyModifier()
    }
}
#endif

#if DEBUG

import CoreGraphics
import OSLog
import PDFKit

/// DEBUG-only logger for the `pdf-highlight` verification observer. Records the
/// faithfulness guards' no-op reasons (Codex Gate-4 round-1 HIGH 1) so a
/// verification run can see WHY an injected highlight was skipped instead of
/// silently producing nothing.
let debugPDFHighlightLog = Logger(subsystem: "com.vreader.app", category: "DebugBridgePDFHighlight")

extension PDFReaderContainerView {

    /// The `ViewModifier` that observes `.debugBridgePDFHighlightCommand` and
    /// dispatches into `handleDebugBridgePDFHighlightCommand`. The body reads
    /// this property unconditionally; the Release stub above supplies an
    /// `EmptyModifier` so DebugBridge symbols never leak into release builds.
    var debugBridgePDFHighlightObserverModifier: some ViewModifier {
        PDFDebugBridgeHighlightObserver(
            onCommand: { page, rect, color in
                handleDebugBridgePDFHighlightCommand(page: page, rect: rect, color: color)
            }
        )
    }

    /// Handle a `.debugBridgePDFHighlightCommand` notification by building the
    /// SAME `ReaderSelectionEvent` (anchor `AnnotationAnchor.pdf(page:, rects:)`)
    /// the gesture produces and calling `handleHighlightAction(event:container:color:)`
    /// — the production creation path.
    ///
    /// Faithfulness guards (Codex Gate-4 rounds 1 + 2):
    /// - HIGH 1 (round 1) — no-op unless the document is loaded and `page` is in
    ///   range (`0..<totalPages`). Otherwise `createHighlightFromAnchor` renders
    ///   nothing while `coordinator.create` has already persisted a record,
    ///   leaving an invisible, library-contaminating highlight.
    /// - MEDIUM 1 (round 1) — navigate the PDF to `page` FIRST so
    ///   `currentPageIndex == page`. `handleHighlightAction` derives the
    ///   record's locator from `viewModel.makeCurrentLocator()` (which reads
    ///   `currentPageIndex`); a real gesture can only select on the visible
    ///   page, so navigating first mirrors that reality and guarantees
    ///   `Locator.page == page`.
    /// - MEDIUM 1 (round 2) — derive `selectedText` from the LIVE, already
    ///   loaded + unlocked `PDFDocument` the reader is showing (read via the
    ///   renderer's `document`, bound by `PDFViewBridge`), NOT a fresh
    ///   `PDFDocument(url:)`. Reloading from URL is expensive on large PDFs and
    ///   yields a still-LOCKED document for password PDFs (so it would extract
    ///   nothing). Reusing the live document is byte-identical to what a gesture
    ///   selection reads.
    /// - MEDIUM 2 (round 2) — a bridge highlight is created ONLY when real
    ///   glyphs sit under the rect. When the live selection is empty /
    ///   whitespace (the rect covers blank page space), the observer NO-OPs +
    ///   logs — it does NOT create a highlight. This mirrors production
    ///   `selectionDidChange`, which never posts `.readerTextSelected` for an
    ///   empty selection, so no gesture highlight exists for "no text under
    ///   rect" either.
    /// - MEDIUM 3 (round 1) — always route through
    ///   `handleHighlightAction(event:container:color:)` with the requested
    ///   color (default yellow), so the color is honored on both the
    ///   coordinator and fallback paths — no parallel direct-coordinator branch.
    @MainActor
    func handleDebugBridgePDFHighlightCommand(
        page: Int,
        rect: NormalizedRect,
        color: String?
    ) {
        guard let container = modelContainer else {
            debugPDFHighlightLog.info("pdf-highlight no-op: model container not ready")
            return
        }
        // HIGH 1: guard loaded state + page range before any creation so a bad
        // page can't persist an invisible (non-rendering) highlight.
        guard viewModel.isDocumentLoaded, viewModel.totalPages > 0 else {
            debugPDFHighlightLog.info(
                "pdf-highlight no-op: document not loaded (loaded=\(viewModel.isDocumentLoaded, privacy: .public), totalPages=\(viewModel.totalPages, privacy: .public))"
            )
            return
        }
        guard page >= 0, page < viewModel.totalPages else {
            debugPDFHighlightLog.info(
                "pdf-highlight no-op: page \(page, privacy: .public) out of range 0..<\(viewModel.totalPages, privacy: .public)"
            )
            return
        }

        // MEDIUM 1 (round 1): navigate-first. Setting `restoredPage` +
        // `pageDidChange` mirrors the production `.readerNavigateToLocator`
        // handler and makes `currentPageIndex == page`, so the persisted
        // locator page equals the anchor page.
        restoredPage = page
        viewModel.pageDidChange(to: page)

        // MEDIUM 1 (round 2): derive the selected text from the LIVE document
        // the reader is showing — `highlightRenderer.document` is the live,
        // already-unlocked `PDFDocument` bound by `PDFViewBridge.updateUIView`.
        // No `PDFDocument(url:)` reload (expensive + still-locked for password
        // PDFs).
        let rawText = PDFDebugHighlightAnchor.selectedText(
            document: highlightRenderer.document, page: page, rect: rect
        )

        // MEDIUM 2 (round 2): faithful create-gate. Only create when real
        // (non-whitespace) glyphs sit under the rect — mirroring production
        // `selectionDidChange`'s non-empty-selection guard. Empty ⇒ no-op +
        // log, NO highlight (no gesture highlight exists for blank page space).
        guard let selectedText = PDFDebugHighlightAnchor.faithfulSelectedText(rawText) else {
            debugPDFHighlightLog.info(
                "pdf-highlight no-op: no text under rect on page \(page, privacy: .public) — not creating a highlight (mirrors the gesture's non-empty-selection gate)"
            )
            return
        }

        let event = PDFDebugHighlightAnchor.makeSelectionEvent(
            page: page, rect: rect, selectedText: selectedText
        )

        // Stash the event the same way the `.readerTextSelected` path does so
        // `handleHighlightAction` reads consistent state, then invoke the SAME
        // production creation path the "Highlight" confirmation button triggers.
        // MEDIUM 3: pass the requested color (default yellow) through the one
        // method — no direct-coordinator bypass.
        pendingSelectionEvent = event
        handleHighlightAction(
            event: event,
            container: container,
            color: PDFDebugHighlightAnchor.resolvedColor(color)
        )
    }
}

/// Pure helper that builds the PDF highlight `AnnotationAnchor` /
/// `ReaderSelectionEvent` from a page + normalized rect — the SAME shape
/// PDFKit's `selectionDidChange` produces via
/// `PDFAnnotationBridge.makeSelectionEvent`. Extracted so it is unit-testable
/// without a live `PDFView` / gesture.
enum PDFDebugHighlightAnchor {

    /// Builds the `.pdf` anchor for a page + normalized rect. The single rect
    /// is in 0...1 page coordinate space (denormalized to page-space downstream
    /// by `PDFAnnotationBridge.createHighlightFromAnchor`).
    static func makeAnchor(page: Int, rect: NormalizedRect) -> AnnotationAnchor {
        let cgRect = CGRect(x: rect.x, y: rect.y, width: rect.w, height: rect.h)
        return .pdf(page: page, rects: [cgRect])
    }

    /// Builds the full `ReaderSelectionEvent` the highlight-creation path
    /// consumes. `selectedText` carries the actual glyphs under the rect from
    /// the LIVE document (Codex Gate-4 round-2 MEDIUM 1) — matching a gesture
    /// selection; `sourceRect` is `.zero` (no on-screen popover anchoring is
    /// needed for a CU-free injection). Callers pass a non-empty, trimmed
    /// string (gated by `faithfulSelectedText`); there is no marker / empty
    /// fallback — the observer no-ops before reaching here when no glyphs sit
    /// under the rect (MEDIUM 2).
    static func makeSelectionEvent(
        page: Int,
        rect: NormalizedRect,
        selectedText: String
    ) -> ReaderSelectionEvent {
        ReaderSelectionEvent(
            selectedText: selectedText,
            anchor: makeAnchor(page: page, rect: rect),
            sourceRect: .zero
        )
    }

    /// Derive the raw selected text under a normalized rect on a page of the
    /// LIVE `PDFDocument` the reader is showing — the same string a real
    /// gesture selection would carry (Codex Gate-4 round-2 MEDIUM 1). Takes the
    /// already-loaded + unlocked document (read from the renderer's `document`)
    /// rather than reloading `PDFDocument(url:)`: reloading is expensive on
    /// large PDFs and yields a still-LOCKED document for password PDFs.
    ///
    /// Reuses `PDFAnnotationBridge.denormalizeRects` to map the 0...1 rect into
    /// page space (NO duplicated denormalization), then calls
    /// `PDFPage.selection(for:)`. Returns nil when the document/page can't be
    /// resolved or the rect covers whitespace; the create-gate
    /// (`faithfulSelectedText`) turns that into a no-op (MEDIUM 2).
    static func selectedText(document: PDFDocument?, page: Int, rect: NormalizedRect) -> String? {
        guard let document,
              page >= 0, page < document.pageCount,
              let pdfPage = document.page(at: page) else {
            return nil
        }
        let pageBounds = pdfPage.bounds(for: .mediaBox)
        let normalized = CGRect(x: rect.x, y: rect.y, width: rect.w, height: rect.h)
        guard let displayRect = PDFAnnotationBridge.denormalizeRects(
            [normalized], pageBounds: pageBounds
        ).first else {
            return nil
        }
        return pdfPage.selection(for: displayRect)?.string
    }

    /// The faithful create-gate (Codex Gate-4 round-2 MEDIUM 2). Mirrors
    /// production `selectionDidChange`'s non-empty-selection guard EXACTLY:
    /// production stores the RAW `selection.string` and only *checks*
    /// `!selectedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty`
    /// before posting. So this returns the RAW string (untrimmed — byte-
    /// identical to what a gesture would persist) when it carries real
    /// (non-whitespace) content, and nil for nil / empty / all-whitespace input
    /// so the observer no-ops (no highlight) — there is no gesture highlight for
    /// "no text under rect".
    static func faithfulSelectedText(_ raw: String?) -> String? {
        guard let raw,
              !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        return raw
    }

    /// Resolve the highlight color the observer passes into
    /// `handleHighlightAction` (Codex Gate-4 round-1 MEDIUM 3). An explicit
    /// color (already allowlist-validated by the parser) is honored; an absent
    /// color falls back to `"yellow"` — the gesture default. Because BOTH the
    /// coordinator and fallback creation paths in `handleHighlightAction` now
    /// take this color, the requested color is never silently dropped.
    static func resolvedColor(_ color: String?) -> String {
        color ?? "yellow"
    }

    /// Parse the notification's `"rect"` userInfo (a 4-element `[Double]`
    /// `[x, y, w, h]`) back into a `NormalizedRect`. Returns nil for a missing
    /// or wrong-arity array so the observer can bail rather than crash.
    static func rect(from array: [Double]?) -> NormalizedRect? {
        guard let array, array.count == 4 else { return nil }
        return NormalizedRect(x: array[0], y: array[1], w: array[2], h: array[3])
    }
}

/// Local `ViewModifier` mirroring the EPUB `EPUBDebugBridgeScrollBoundaryObserver`
/// shape. Parses the notification's `(page, rect, color)` userInfo and forwards
/// to `onCommand`. Kept local to this file so the PDF body's observer chain
/// stays off the main `body` type-check path.
private struct PDFDebugBridgeHighlightObserver: ViewModifier {
    let onCommand: (_ page: Int, _ rect: NormalizedRect, _ color: String?) -> Void

    func body(content: Content) -> some View {
        content.onReceive(
            NotificationCenter.default.publisher(for: .debugBridgePDFHighlightCommand)
        ) { notification in
            guard let page = notification.userInfo?["page"] as? Int,
                  let rectArray = notification.userInfo?["rect"] as? [Double],
                  let rect = PDFDebugHighlightAnchor.rect(from: rectArray) else { return }
            let color = notification.userInfo?["color"] as? String
            onCommand(page, rect, color)
        }
    }
}

#endif
#endif
