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
