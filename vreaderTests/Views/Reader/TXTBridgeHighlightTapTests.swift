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

    /// Per Bug #203 (GH #743): `resolveHighlightTap` must return the rect in
    /// the textView's local coordinate space — NOT window-space. The presenter
    /// passes this rect to `UIEditMenuConfiguration.sourcePoint`, which is
    /// interpreted in the interaction-view's coords (the textView itself for
    /// the non-chunked TXT path). Returning window-space would anchor the
    /// menu off-screen when the textView is at a non-zero window origin
    /// (which is always the case in a real reader chrome).
    @Test @MainActor
    func resolveHighlightTap_returnsViewLocalRect_notWindowSpace() {
        let tv = makeFixture(text: "hello world")
        // Embed the textView in a window at a non-zero origin so view-space
        // and window-space differ by exactly (50, 100). If the bug were
        // present (the old `textView.convert(_, to: nil)` path), every
        // sourceRect.origin would be offset by these values.
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 800, height: 600))
        tv.frame = CGRect(x: 50, y: 100, width: 700, height: 200)
        window.addSubview(tv)

        let id = UUID()
        let lookup = [PersistedHighlightLookupEntry(
            id: id, range: NSRange(location: 0, length: 5)  // "hello"
        )]
        // Tap in textView-local coords near the start of "hello".
        let tapPoint = CGPoint(x: 5, y: 5)
        guard let event = TXTTextViewBridge.Coordinator.resolveHighlightTap(
            tapPoint: tapPoint, in: tv, lookup: lookup
        ) else {
            Issue.record("Expected a hit")
            return
        }

        // In textView-local space the "hello" rect starts near (0, 0) plus
        // whatever inset. It must NOT have absorbed the window offset (50,
        // 100). If x ≥ 50 or y ≥ 100, the bridge is still emitting
        // window-space coords.
        #expect(event.sourceRect.origin.x < 50,
                "sourceRect.x should be textView-local; got \(event.sourceRect.origin.x) — likely still window-space (offset by 50)")
        #expect(event.sourceRect.origin.y < 100,
                "sourceRect.y should be textView-local; got \(event.sourceRect.origin.y) — likely still window-space (offset by 100)")
    }
}
#endif
