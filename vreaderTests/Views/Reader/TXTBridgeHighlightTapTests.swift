// Purpose: Tests for `TXTTextViewBridge.Coordinator.resolveHighlightTap`
// (Feature #53 WI-2 / GH #596). Verifies the tap-point → CGPoint →
// character-index → highlight-UUID pipeline produces correct
// `ReaderHighlightTapEvent`s against a real `HighlightableTextView`
// fixture and returns nil for taps that miss every persisted range.
//
// @coordinates-with: TXTTextViewBridgeCoordinator.swift,
//   HighlightableTextView.swift, TextHighlightHitTester.swift

#if canImport(UIKit)
import Testing
import UIKit
import Foundation
@testable import vreader

@MainActor
private func makeFixture(text: String) -> HighlightableTextView {
    let tv = HighlightableTextView()
    tv.isEditable = false
    tv.isSelectable = true
    tv.attributedText = NSAttributedString(
        string: text,
        attributes: [.font: UIFont.systemFont(ofSize: 16)]
    )
    // Wide enough to keep the layout single-line for predictable
    // character-index → bounding-rect mapping.
    tv.frame = CGRect(x: 0, y: 0, width: 800, height: 200)
    tv.textContainer.lineFragmentPadding = 0
    tv.textContainerInset = .zero
    // Force layout so layoutManager bounding-rect calls return valid rects.
    tv.layoutManager.ensureLayout(for: tv.textContainer)
    return tv
}

@Suite("TXTBridgeHighlightTap")
struct TXTBridgeHighlightTapTests {

    @Test @MainActor
    func resolveHighlightTap_emptyLookup_returnsNil() {
        let tv = makeFixture(text: "hello world")
        let result = TXTTextViewBridge.Coordinator.resolveHighlightTap(
            tapPoint: CGPoint(x: 10, y: 5),
            in: tv,
            lookup: []
        )
        #expect(result == nil)
    }

    @Test @MainActor
    func resolveHighlightTap_pointInsideRange_returnsEvent() {
        let tv = makeFixture(text: "hello world")
        let id = UUID()
        // Cover "world" (range location 6, length 5).
        let lookup = [PersistedHighlightLookupEntry(
            id: id, range: NSRange(location: 6, length: 5)
        )]
        // Compute the visual x-coord of the first character of "world" (index 6).
        let lm = tv.layoutManager
        let glyphRange = lm.glyphRange(
            forCharacterRange: NSRange(location: 6, length: 1),
            actualCharacterRange: nil
        )
        let charRect = lm.boundingRect(forGlyphRange: glyphRange, in: tv.textContainer)
        let tapPoint = CGPoint(x: charRect.midX, y: charRect.midY)

        let result = TXTTextViewBridge.Coordinator.resolveHighlightTap(
            tapPoint: tapPoint, in: tv, lookup: lookup
        )
        #expect(result?.highlightID == id)
        #expect(result?.sourceRect != .zero)
    }

    @Test @MainActor
    func resolveHighlightTap_pointOutsideRange_returnsNil() {
        let tv = makeFixture(text: "hello world")
        let id = UUID()
        // Cover "hello" only — taps over "world" should miss.
        let lookup = [PersistedHighlightLookupEntry(
            id: id, range: NSRange(location: 0, length: 5)
        )]
        let lm = tv.layoutManager
        let glyphRange = lm.glyphRange(
            forCharacterRange: NSRange(location: 6, length: 1),
            actualCharacterRange: nil
        )
        let charRect = lm.boundingRect(forGlyphRange: glyphRange, in: tv.textContainer)
        let tapPoint = CGPoint(x: charRect.midX, y: charRect.midY)

        let result = TXTTextViewBridge.Coordinator.resolveHighlightTap(
            tapPoint: tapPoint, in: tv, lookup: lookup
        )
        #expect(result == nil)
    }

    @Test @MainActor
    func resolveHighlightTap_returnsNonZeroSourceRect_forVisibleHighlight() {
        let tv = makeFixture(text: "hello world")
        let id = UUID()
        let lookup = [PersistedHighlightLookupEntry(
            id: id, range: NSRange(location: 0, length: 5)  // "hello"
        )]
        let tapPoint = CGPoint(x: 5, y: 5)
        guard let event = TXTTextViewBridge.Coordinator.resolveHighlightTap(
            tapPoint: tapPoint, in: tv, lookup: lookup
        ) else {
            Issue.record("Expected a hit for tap at (5, 5) over 'hello' range")
            return
        }
        // Bounding rect should have non-zero width (the rendered "hello").
        #expect(event.sourceRect.width > 0)
        #expect(event.sourceRect.height > 0)
    }
}
#endif
