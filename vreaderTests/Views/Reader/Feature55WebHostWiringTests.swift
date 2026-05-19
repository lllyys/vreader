// Purpose: Feature #55 WI-7 — guards the web-host (EPUB / Foliate AZW3-MOBI)
// wiring of the tap-on-annotated-text note preview.
//
// WI-7's behavioral change is integration — `NotePreviewModifier` attached to
// `EPUBReaderContainerView` and `FoliateSpikeView`, plus the *removal* of
// feature #53's tap-time `HighlightActionPresenter.present(...)` call from
// `EPUBWebViewBridgeCoordinator.handleHighlightTapMessage` and
// `FoliateHighlightTapHandlerModifier`. Unlike the native bridges (WI-6),
// the EPUB / Foliate highlight tap arrives from a JS event — there is no
// native long-press recognizer to re-home #53's menu onto, so #53's tap-time
// menu is *dropped* for these hosts in v1 (highlight delete stays reachable
// via the Annotations panel). The end-to-end (tap → preview sheet) is
// exercised at Gate 5 device verification.
//
// These unit tests guard the pieces that CAN be verified without driving a
// live WKWebView / Foliate-js bundle: the composed data path the wiring
// depends on — a tapped EPUB / Foliate highlight becomes a
// `ReaderHighlightTapEvent`, which `NotePreviewPresenter` then resolves to
// a presentation form. In v1 the containers attach the preview with no host
// view (the documented `NotePreviewContainerSupport` contract, shared with
// WI-6's TXT/MD/PDF), so `resolvedForm(...)` presents the bottom SHEET for
// both hosts — EPUB's would-be callout degrades for lack of an anchor view,
// and Foliate carries `sourceRect == .zero` (foliate-host.js forwards no
// rect) so its base `form(...)` is already the sheet.

import Testing
import Foundation
import CoreGraphics
@testable import vreader

@Suite("Feature #55 WI-7 — web-host note-preview wiring")
struct Feature55WebHostWiringTests {

    // MARK: - EPUB tap path: real rect → anchored callout

    @Test("an EPUB highlight tap resolves to a ReaderHighlightTapEvent the note preview consumes")
    func epubTapMessageProducesNotePreviewEvent() {
        // `EPUBWebViewBridgeCoordinator.handleHighlightTapMessage` parses the
        // JS `highlightTapHandler` payload via this helper, then posts
        // `.readerHighlightTapped` — the event `NotePreviewModifier` observes.
        // WI-7 removed the tap-time delete-menu presenter; the parsed event
        // is now consumed only by the note preview.
        let id = UUID()
        let body: [String: Any] = [
            "id": id.uuidString,
            "rectX": 12.5, "rectY": 80.0,
            "rectWidth": 96.0, "rectHeight": 22.0
        ]
        let event = EPUBHighlightBridge.parseHighlightTapMessage(body)
        #expect(event?.highlightID == id)
        #expect(event?.sourceRect == CGRect(x: 12.5, y: 80, width: 96, height: 22))
    }

    @Test("an EPUB tap presents the v1 sheet form — the container supplies no host view")
    func epubTapResolvesToSheetInV1() {
        // EPUB's JS bridge forwards a real `getBoundingClientRect`, so the
        // base `form(...)` decision for a short note + no VoiceOver is
        // `.callout`. But `EPUBReaderContainerView` attaches
        // `notePreviewPresenterIfAvailable` with the default
        // `hostViewProvider: { nil }` — the documented v1 contract for
        // every native + web container (`NotePreviewContainerSupport`
        // header; WI-6 shipped TXT/MD/PDF the same way). With no host view
        // to anchor a callout, `resolvedForm(...)` degrades it to `.sheet`.
        // So EPUB presents the bottom-sheet preview in v1; the
        // rect-anchored callout is a deferred refinement.
        let record = Self.makeHighlightRecord(note: "a short note")
        let content = NotePreviewPresenter.content(
            for: record,
            sourceRect: CGRect(x: 12.5, y: 80, width: 96, height: 22)
        )
        // The base decision would be `.callout` (real rect, short note)…
        #expect(
            NotePreviewPresenter.form(
                for: content, isVoiceOverRunning: false, noteLineCount: 1
            ) == .callout
        )
        // …but with no host view (the v1 container default) it resolves
        // to the sheet — the actual shipped EPUB behavior.
        #expect(
            NotePreviewPresenter.resolvedForm(
                for: content,
                isVoiceOverRunning: false,
                noteLineCount: 1,
                hasHostView: false
            ) == .sheet
        )
    }

    // MARK: - Foliate tap path: zero rect → bottom sheet

    @Test("a Foliate highlight tap resolves a CFI to the persisted highlight's id")
    func foliateTapResolvesCFIToHighlightID() {
        // `FoliateHighlightTapHandlerModifier` resolves the foliate-host.js
        // CFI back to the persisted highlight via this resolver, then posts
        // `.readerHighlightTapped` with `sourceRect == .zero`. WI-7 removed
        // the tap-time delete-menu presenter from that modifier.
        let id = UUID()
        let record = Self.makeHighlightRecord(
            highlightId: id,
            anchor: .epub(
                href: "chapter1.xhtml",
                cfi: "epubcfi(/6/4!/4/2)",
                serializedRange: Self.serializedRange()
            )
        )
        let resolved = FoliateHighlightTapResolver.resolveHighlightID(
            forCFI: "epubcfi(/6/4!/4/2)", in: [record]
        )
        #expect(resolved == id)
    }

    @Test("a Foliate tap event carries a zero rect, which resolves to the sheet form")
    func foliateTapZeroRectResolvesToSheet() {
        // foliate-host.js does not forward the annotation screen rect, so
        // `FoliateHighlightTapHandlerModifier` posts the event with
        // `sourceRect == .zero`. `NotePreviewPresenter.form` must resolve a
        // zero rect to `.sheet` — the bottom sheet needs no anchor. This is
        // the WI-7 Foliate decision (plan §2.9): no rect → sheet form.
        let event = ReaderHighlightTapEvent(highlightID: UUID(), sourceRect: .zero)
        #expect(event.sourceRect == .zero)

        let record = Self.makeHighlightRecord(note: "a short note")
        let content = NotePreviewPresenter.content(
            for: record, sourceRect: event.sourceRect
        )
        // Even a short note + no VoiceOver resolves to `.sheet` purely
        // because the rect is zero — the Foliate path.
        let form = NotePreviewPresenter.form(
            for: content, isVoiceOverRunning: false, noteLineCount: 1
        )
        #expect(form == .sheet)
    }

    @Test("an empty CFI resolves to no highlight — a malformed Foliate tap no-ops")
    func foliateEmptyCFIResolvesToNil() {
        let record = Self.makeHighlightRecord(
            anchor: .epub(
                href: "chapter1.xhtml",
                cfi: "epubcfi(/6/4!/4/2)",
                serializedRange: Self.serializedRange()
            )
        )
        #expect(
            FoliateHighlightTapResolver.resolveHighlightID(
                forCFI: "", in: [record]
            ) == nil
        )
    }

    // MARK: - Fixture

    private static func serializedRange() -> EPUBSerializedRange {
        EPUBSerializedRange(
            startContainerPath: "/body/p[1]/text()[1]",
            startOffset: 0,
            endContainerPath: "/body/p[1]/text()[1]",
            endOffset: 19
        )
    }

    private static func makeHighlightRecord(
        highlightId: UUID = UUID(),
        note: String? = nil,
        anchor: AnnotationAnchor? = nil
    ) -> HighlightRecord {
        let fp = DocumentFingerprint(
            contentSHA256: String(repeating: "a", count: 64),
            fileByteCount: 1024,
            format: .epub
        )
        let locator = Locator(
            bookFingerprint: fp,
            href: nil, progression: nil, totalProgression: nil,
            cfi: nil, page: nil, charOffsetUTF16: nil,
            charRangeStartUTF16: nil, charRangeEndUTF16: nil,
            textQuote: nil, textContextBefore: nil, textContextAfter: nil
        )
        return HighlightRecord(
            highlightId: highlightId,
            locator: locator,
            anchor: anchor,
            profileKey: "default",
            selectedText: "highlighted passage",
            color: "yellow",
            note: note,
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            updatedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
    }
}
