// Bug #302: tapping a stored highlight in the Readium EPUB engine must open the
// edit popover. The producer side wires `observeDecorationInteractions` →
// `.readerHighlightTapped`; the pure mapping from a decoration-activation id +
// rect to the cross-format `ReaderHighlightTapEvent` is the unit-testable seam
// (the live navigator tap → activation is exercised by device verification,
// mirroring the WI-8 builder/selection split). These pin that mapping: a valid
// `HighlightRecord` UUID id round-trips, a missing rect degrades to `.zero`, and
// a foreign/malformed id is ignored (no bogus tap).
//
// @coordinates-with vreader/Services/Reader/ReadiumDecorationHighlightAdapter.swift

#if canImport(UIKit)
import Testing
import Foundation
import CoreGraphics
@testable import vreader

private func makeHighlightRecord(id: UUID) -> HighlightRecord {
    let fp = DocumentFingerprint(
        contentSHA256: String(repeating: "a", count: 64), fileByteCount: 10, format: .epub
    )
    let locator = Locator(
        bookFingerprint: fp, href: "ch1.xhtml", progression: 0.5, totalProgression: nil,
        cfi: nil, page: nil, charOffsetUTF16: nil, charRangeStartUTF16: nil,
        charRangeEndUTF16: nil, textQuote: nil, textContextBefore: nil, textContextAfter: nil
    )
    return HighlightRecord(
        highlightId: id, locator: locator, anchor: nil, profileKey: "key",
        selectedText: "the passage", color: "yellow", note: nil,
        createdAt: Date(timeIntervalSince1970: 1_700_000_000),
        updatedAt: Date(timeIntervalSince1970: 1_700_000_000)
    )
}

@Suite("ReadiumDecorationHighlightAdapter.tapEvent (Bug #302)")
struct ReadiumDecorationTapEventTests {

    @Test("a valid highlight-UUID decoration id maps to a tap event with that id + rect")
    func validIdWithRect() throws {
        let id = UUID()
        let rect = CGRect(x: 10, y: 20, width: 100, height: 18)
        let event = try #require(
            ReadiumDecorationHighlightAdapter.tapEvent(
                forDecorationId: id.uuidString, rect: rect
            )
        )
        #expect(event.highlightID == id)
        #expect(event.sourceRect == rect)
    }

    @Test("a missing rect degrades to .zero (default popover anchor)")
    func nilRectToZero() throws {
        let id = UUID()
        let event = try #require(
            ReadiumDecorationHighlightAdapter.tapEvent(
                forDecorationId: id.uuidString, rect: nil
            )
        )
        #expect(event.highlightID == id)
        #expect(event.sourceRect == .zero)
    }

    // MARK: - Bug #316: tap-point fallback for the anchored card

    @Test("rect nil but a tap point present → a 1×1 anchor at the point (non-zero)")
    func nilRectWithPoint_anchorsAtPoint() throws {
        let id = UUID()
        let point = CGPoint(x: 140, y: 260)
        let event = try #require(
            ReadiumDecorationHighlightAdapter.tapEvent(
                forDecorationId: id.uuidString, rect: nil, point: point
            )
        )
        #expect(event.highlightID == id)
        #expect(event.sourceRect == CGRect(origin: point, size: CGSize(width: 1, height: 1)))
        #expect(event.sourceRect != .zero)
    }

    /// Bug #316 end-to-end form resolution: the point-derived non-zero anchor,
    /// PLUS the navigator host view the Readium host now supplies
    /// (`ReadiumEPUBHost+Body` → `highlightAdapter.hostView`), resolves to the
    /// anchored CARD — not the bottom sheet. (A `.zero` rect, or a non-zero rect
    /// with no host view, still degrades to `.sheet`.) This pins both halves of
    /// the fix, addressing the Codex note that the non-zero rect alone is
    /// insufficient without `hasHostView`.
    @Test("point-derived anchor + a host view resolves to the card, .zero/no-host to the sheet")
    func pointAnchor_withHost_resolvesToCard() throws {
        let id = UUID()
        let point = CGPoint(x: 140, y: 260)
        let tapped = try #require(
            ReadiumDecorationHighlightAdapter.tapEvent(
                forDecorationId: id.uuidString, rect: nil, point: point
            )
        )
        let content = HighlightPopoverPresenter.content(
            for: makeHighlightRecord(id: id), sourceRect: tapped.sourceRect, chapter: nil
        )
        #expect(HighlightPopoverPresenter.resolvedForm(
            for: content, isVoiceOverRunning: false, noteLineCount: 0, hasHostView: true
        ) == .card)
        // No host view → still the sheet (the gap before the host-view plumbing).
        #expect(HighlightPopoverPresenter.resolvedForm(
            for: content, isVoiceOverRunning: false, noteLineCount: 0, hasHostView: false
        ) == .sheet)
    }

    @Test("a real rect takes precedence over the tap point")
    func rectWinsOverPoint() throws {
        let id = UUID()
        let rect = CGRect(x: 10, y: 20, width: 100, height: 18)
        let event = try #require(
            ReadiumDecorationHighlightAdapter.tapEvent(
                forDecorationId: id.uuidString, rect: rect, point: CGPoint(x: 999, y: 999)
            )
        )
        #expect(event.sourceRect == rect)
    }

    @Test("neither rect nor point → .zero (still the sheet fallback)")
    func neitherRectNorPoint_isZero() throws {
        let id = UUID()
        let event = try #require(
            ReadiumDecorationHighlightAdapter.tapEvent(
                forDecorationId: id.uuidString, rect: nil, point: nil
            )
        )
        #expect(event.sourceRect == .zero)
    }

    @Test("a non-UUID decoration id is ignored (nil — no bogus tap)")
    func malformedIdIsNil() {
        #expect(
            ReadiumDecorationHighlightAdapter.tapEvent(
                forDecorationId: "not-a-uuid", rect: .zero
            ) == nil
        )
    }

    @Test("an empty decoration id is ignored")
    func emptyIdIsNil() {
        #expect(
            ReadiumDecorationHighlightAdapter.tapEvent(forDecorationId: "", rect: nil) == nil
        )
    }
}
#endif
