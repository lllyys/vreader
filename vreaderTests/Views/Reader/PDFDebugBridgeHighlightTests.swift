// Purpose: Tests for the DEBUG-only PDF highlight-creation harness helper
// (feature #17 — `vreader-debug://pdf-highlight`). Verifies the pure
// page + normalized-rect → AnnotationAnchor / ReaderSelectionEvent
// construction that the PDFReaderContainerView observer feeds into the SAME
// handleHighlightAction the long-press-drag gesture uses.

#if DEBUG
#if canImport(UIKit)

import XCTest
import CoreGraphics
import PDFKit
import UIKit
@testable import vreader

final class PDFDebugBridgeHighlightTests: XCTestCase {

    func test_makeAnchor_buildsPDFAnchorWithNormalizedRect() {
        let anchor = PDFDebugHighlightAnchor.makeAnchor(
            page: 2,
            rect: NormalizedRect(x: 0.1, y: 0.2, w: 0.3, h: 0.4)
        )
        guard case .pdf(let page, let rects) = anchor else {
            return XCTFail("expected a .pdf anchor, got \(anchor)")
        }
        XCTAssertEqual(page, 2)
        XCTAssertEqual(rects.count, 1)
        XCTAssertEqual(rects[0], CGRect(x: 0.1, y: 0.2, width: 0.3, height: 0.4))
    }

    func test_makeAnchor_pageZeroAndFullPageRect() {
        let anchor = PDFDebugHighlightAnchor.makeAnchor(
            page: 0,
            rect: NormalizedRect(x: 0, y: 0, w: 1, h: 1)
        )
        guard case .pdf(let page, let rects) = anchor else {
            return XCTFail("expected a .pdf anchor, got \(anchor)")
        }
        XCTAssertEqual(page, 0)
        XCTAssertEqual(rects, [CGRect(x: 0, y: 0, width: 1, height: 1)])
    }

    func test_makeSelectionEvent_carriesAnchorAndSelectedText() {
        let event = PDFDebugHighlightAnchor.makeSelectionEvent(
            page: 1,
            rect: NormalizedRect(x: 0.25, y: 0.5, w: 0.5, h: 0.1),
            selectedText: "the quick brown fox"
        )
        guard case .pdf(let page, let rects) = event.anchor else {
            return XCTFail("expected a .pdf anchor, got \(event.anchor)")
        }
        XCTAssertEqual(page, 1)
        XCTAssertEqual(rects, [CGRect(x: 0.25, y: 0.5, width: 0.5, height: 0.1)])
        XCTAssertEqual(event.selectedText, "the quick brown fox")
    }

    func test_rectFromUserInfo_parsesFourComponentArray() {
        let rect = PDFDebugHighlightAnchor.rect(from: [0.1, 0.2, 0.3, 0.4])
        XCTAssertEqual(rect, NormalizedRect(x: 0.1, y: 0.2, w: 0.3, h: 0.4))
    }

    func test_rectFromUserInfo_rejectsWrongCount() {
        XCTAssertNil(PDFDebugHighlightAnchor.rect(from: [0.1, 0.2, 0.3]))
        XCTAssertNil(PDFDebugHighlightAnchor.rect(from: nil))
    }

    // MARK: - MEDIUM 3: color passes through (default yellow)
    //
    // The observer routes EVERY injection through
    // `handleHighlightAction(event:container:color:)` — explicit color honored,
    // nil ⇒ yellow — so the requested color is never dropped on the fallback
    // path (the old direct-coordinator branch silently hard-coded yellow when
    // the coordinator was nil).

    func test_resolvedColor_explicitColorHonored() {
        XCTAssertEqual(PDFDebugHighlightAnchor.resolvedColor("pink"), "pink")
        XCTAssertEqual(PDFDebugHighlightAnchor.resolvedColor("green"), "green")
        XCTAssertEqual(PDFDebugHighlightAnchor.resolvedColor("blue"), "blue")
    }

    func test_resolvedColor_nilFallsBackToYellow() {
        XCTAssertEqual(PDFDebugHighlightAnchor.resolvedColor(nil), "yellow")
    }

    // MARK: - MEDIUM 1+2: selectedText from the LIVE document, no-op when empty
    //
    // Codex Gate-4 round-2:
    //  - MEDIUM 1 — the selected text is derived from the LIVE, already-loaded
    //    + unlocked `PDFDocument` the reader is showing (passed in), NOT a
    //    fresh `PDFDocument(url:)` (expensive on large PDFs and still LOCKED
    //    for password PDFs). The pure helper now takes a `PDFDocument`.
    //  - MEDIUM 2 — a rect with no glyphs under it returns `nil` (NOT a
    //    marker string), and the create-gate (`shouldCreate`) declines to
    //    create a highlight — mirroring production `selectionDidChange`, which
    //    never posts `.readerTextSelected` for an empty selection. So a bridge
    //    highlight is created ONLY when real glyphs sit under the rect.
    //
    // The live-document end-to-end (renderer.document populated by the bridge
    // after the real PDFView loads) is device-verified, not unit-tested — these
    // unit tests drive the pure text-extraction + create-gate seams with a
    // document built in-process (which is byte-identical to a live one for
    // `PDFPage.selection(for:)`).

    func test_selectedText_nilDocument_returnsNil() {
        let text = PDFDebugHighlightAnchor.selectedText(
            document: nil, page: 0, rect: NormalizedRect(x: 0, y: 0, w: 1, h: 1)
        )
        XCTAssertNil(text)
    }

    func test_selectedText_outOfRangePage_returnsNil() throws {
        let document = try makeTextPDFDocument(text: "Hello World")
        let text = PDFDebugHighlightAnchor.selectedText(
            document: document, page: 99, rect: NormalizedRect(x: 0, y: 0, w: 1, h: 1)
        )
        XCTAssertNil(text)
    }

    func test_selectedText_fullPageRect_capturesGlyphsUnderRect() throws {
        let document = try makeTextPDFDocument(text: "FaithfulBridgeText")
        // A full-page rect selects all glyphs on the page.
        let text = PDFDebugHighlightAnchor.selectedText(
            document: document, page: 0, rect: NormalizedRect(x: 0, y: 0, w: 1, h: 1)
        )
        let unwrapped = try XCTUnwrap(text, "expected non-nil glyphs under a full-page rect")
        XCTAssertTrue(
            unwrapped.contains("FaithfulBridgeText"),
            "expected the page glyphs, got \(unwrapped)"
        )
    }

    func test_selectedText_whitespaceRect_gatesToNoCreate() throws {
        let document = try makeTextPDFDocument(text: "TopText")
        // A tiny rect in the bottom-right corner (no glyphs there — the text is
        // drawn near the top-left) yields no real selection: `selection(for:)`
        // returns nil OR an empty / whitespace string. Either way the faithful
        // create-gate turns it into a no-op (nil ⇒ no highlight) — the same
        // outcome as a gesture over blank page space, where no
        // `.readerTextSelected` ever fires.
        let raw = PDFDebugHighlightAnchor.selectedText(
            document: document, page: 0, rect: NormalizedRect(x: 0.95, y: 0.95, w: 0.02, h: 0.02)
        )
        XCTAssertNil(
            PDFDebugHighlightAnchor.faithfulSelectedText(raw),
            "a rect over blank page space must gate to no-create, got raw=\(String(describing: raw))"
        )
    }

    // MARK: - MEDIUM 2: create-gate (no-op when no glyphs under the rect)
    //
    // `shouldCreate(selectedText:)` is the faithful gate mirroring production
    // `selectionDidChange`'s non-empty-selection guard: a highlight is created
    // ONLY when the live selection under the rect carries real (non-whitespace)
    // text. nil / "" / all-whitespace ⇒ no create.

    func test_shouldCreate_nilText_isFalse() {
        XCTAssertNil(PDFDebugHighlightAnchor.faithfulSelectedText(nil))
    }

    func test_shouldCreate_emptyText_isFalse() {
        XCTAssertNil(PDFDebugHighlightAnchor.faithfulSelectedText(""))
    }

    func test_shouldCreate_whitespaceText_isFalse() {
        XCTAssertNil(PDFDebugHighlightAnchor.faithfulSelectedText("   \n\t  "))
    }

    func test_shouldCreate_realText_returnsRawStringUntrimmed() {
        // Byte-identity: production `selectionDidChange` stores the RAW
        // `selection.string` and only checks the trimmed form for emptiness.
        // The bridge must persist the same raw string (incl. surrounding
        // whitespace) a gesture would, not a trimmed variant.
        XCTAssertEqual(
            PDFDebugHighlightAnchor.faithfulSelectedText("  the quick brown fox  "),
            "  the quick brown fox  "
        )
    }

    func test_shouldCreate_realTextNoSurroundingWhitespace_returnsVerbatim() {
        XCTAssertEqual(
            PDFDebugHighlightAnchor.faithfulSelectedText("the quick brown fox"),
            "the quick brown fox"
        )
    }

    // MARK: - MEDIUM 1: persisted locator page == anchor page (navigate-first)
    //
    // The observer navigates the PDF to the requested page FIRST (mirroring
    // the production `.readerNavigateToLocator` handler), so `currentPageIndex`
    // equals the command's `page`, and `handleHighlightAction`'s
    // `makeCurrentLocator()` produces a locator whose `page` equals the anchor
    // page. A gesture can only select on the visible page, so this is the
    // faithful behavior — no page mismatch between annotation and record.

    @MainActor
    func test_navigateFirst_locatorPageMatchesAnchorPage() {
        let (vm, _, _) = Self.makeViewModel()
        vm.documentDidLoad(totalPages: 10)
        // Visible page starts at 0; the command targets page 3.
        XCTAssertEqual(vm.currentPageIndex, 0)

        // Simulate the observer's navigate-first step.
        vm.pageDidChange(to: 3)

        let anchor = PDFDebugHighlightAnchor.makeAnchor(
            page: 3, rect: NormalizedRect(x: 0.1, y: 0.1, w: 0.2, h: 0.05)
        )
        guard case .pdf(let anchorPage, _) = anchor else {
            return XCTFail("expected a .pdf anchor")
        }
        let locator = vm.makeCurrentLocator()
        XCTAssertEqual(locator.page, 3)
        XCTAssertEqual(locator.page, anchorPage,
                       "persisted locator page must equal the anchor page")
    }

    @MainActor
    private static func makeViewModel() -> (PDFReaderViewModel, MockPositionStore, MockSessionStore) {
        let fingerprint = DocumentFingerprint(
            contentSHA256: "pdf_debughl_test_sha256_00000000000000000000000000000000000000",
            fileByteCount: 50000,
            format: .pdf
        )
        let positionStore = MockPositionStore()
        let sessionStore = MockSessionStore()
        let clock = MockClock()
        let tracker = ReadingSessionTracker(
            clock: clock, store: sessionStore, deviceId: "test-device"
        )
        let vm = PDFReaderViewModel(
            bookFingerprint: fingerprint,
            positionStore: positionStore,
            sessionTracker: tracker,
            deviceId: "test-device"
        )
        return (vm, positionStore, sessionStore)
    }

    // MARK: - Helpers

    /// Builds a single-page PDF on disk with the given text drawn near the
    /// top-left of the page, so a full-page selection captures it and a
    /// bottom-right rect captures nothing.
    private func makeTextPDF(text: String) throws -> URL {
        let pageRect = CGRect(x: 0, y: 0, width: 612, height: 792)
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("pdfhl-\(UUID().uuidString).pdf")
        let renderer = UIGraphicsPDFRenderer(bounds: pageRect)
        try renderer.writePDF(to: url) { context in
            context.beginPage()
            let attrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 40)
            ]
            (text as NSString).draw(at: CGPoint(x: 36, y: 36), withAttributes: attrs)
        }
        return url
    }

    /// Builds an in-process `PDFDocument` (the same shape the LIVE reader
    /// holds) with the given text drawn near the top-left of a single page.
    /// `PDFPage.selection(for:)` behaves identically on this and on the live
    /// document the bridge binds into the renderer, so the unit tests can drive
    /// the MEDIUM 1 text-extraction seam without a real PDFView.
    private func makeTextPDFDocument(text: String) throws -> PDFDocument {
        let url = try makeTextPDF(text: text)
        defer { try? FileManager.default.removeItem(at: url) }
        return try XCTUnwrap(PDFDocument(url: url), "failed to load test PDFDocument")
    }
}

#endif
#endif
