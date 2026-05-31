// Purpose: Tests for `TextHighlightHitTester` pure-function hit-test
// (Feature #53 WI-2 / GH #596). Verifies character-index resolution
// against persisted-highlight lookup entries — covers hit, miss,
// boundary, overlap, empty-input, zero-length-range, and multi-entry
// ordering rules.
//
// @coordinates-with: TextHighlightHitTester.swift, TextReaderUIState.swift

import Testing
import Foundation
@testable import vreader

@Suite("TextHighlightHitTester")
struct TextHighlightHitTesterTests {

    private func makeEntry(id: UUID = UUID(), start: Int, length: Int, hasNote: Bool = false) -> PersistedHighlightLookupEntry {
        PersistedHighlightLookupEntry(id: id, range: NSRange(location: start, length: length), hasNote: hasNote)
    }

    @Test
    func hitTest_emptyLookup_returnsNil() {
        let result = TextHighlightHitTester.hitTest(charIndex: 5, in: [])
        #expect(result == nil)
    }

    @Test
    func hitTest_insideSingleRange_returnsThatEntry() {
        let id = UUID()
        let e = makeEntry(id: id, start: 10, length: 5) // [10..14]
        let result = TextHighlightHitTester.hitTest(charIndex: 12, in: [e])
        #expect(result?.id == id)
    }

    @Test
    func hitTest_atRangeStart_returnsEntry() {
        let id = UUID()
        let e = makeEntry(id: id, start: 10, length: 5)
        let result = TextHighlightHitTester.hitTest(charIndex: 10, in: [e])
        #expect(result?.id == id)
    }

    @Test
    func hitTest_atRangeEndExclusive_returnsNil() {
        // NSLocationInRange is upper-exclusive: index 15 is NOT in [10..14].
        let e = makeEntry(start: 10, length: 5)
        let result = TextHighlightHitTester.hitTest(charIndex: 15, in: [e])
        #expect(result == nil)
    }

    @Test
    func hitTest_outsideAllRanges_returnsNil() {
        let result = TextHighlightHitTester.hitTest(
            charIndex: 100, in: [makeEntry(start: 10, length: 5), makeEntry(start: 20, length: 3)]
        )
        #expect(result == nil)
    }

    @Test
    func hitTest_overlapping_returnsMostRecent() {
        // Two ranges cover index 12: the older one [10..14] (id1) and the
        // newer one [11..13] (id2). The most-recently-added entry wins on
        // overlap (visually topmost).
        let id1 = UUID()
        let id2 = UUID()
        let result = TextHighlightHitTester.hitTest(
            charIndex: 12,
            in: [makeEntry(id: id1, start: 10, length: 5), makeEntry(id: id2, start: 11, length: 3)]
        )
        #expect(result?.id == id2)
    }

    // MARK: - Bug #295: noted-highlight preference on ambiguous overlap

    @Test
    func hitTest_overlapping_prefersNotedOverTopmostNoteless() {
        // The topmost (newer) highlight [11..13] is note-less; the older
        // [10..14] carries a note. A tap in the overlap must open the NOTED
        // one (older), not an empty editor over the color-only top highlight.
        let noted = UUID()
        let noteless = UUID()
        let result = TextHighlightHitTester.hitTest(
            charIndex: 12,
            in: [
                makeEntry(id: noted, start: 10, length: 5, hasNote: true),
                makeEntry(id: noteless, start: 11, length: 3, hasNote: false),
            ]
        )
        #expect(result?.id == noted)
    }

    @Test
    func hitTest_overlapping_bothNoted_returnsTopmost() {
        // Both noted → topmost (most recent) still wins.
        let older = UUID()
        let newer = UUID()
        let result = TextHighlightHitTester.hitTest(
            charIndex: 12,
            in: [
                makeEntry(id: older, start: 10, length: 5, hasNote: true),
                makeEntry(id: newer, start: 11, length: 3, hasNote: true),
            ]
        )
        #expect(result?.id == newer)
    }

    @Test
    func hitTest_overlapping_bothNoteless_returnsTopmost() {
        // Neither noted → unchanged behavior: topmost (most recent) wins, and
        // the editor shows its designed "Add a note…" empty state.
        let older = UUID()
        let newer = UUID()
        let result = TextHighlightHitTester.hitTest(
            charIndex: 12,
            in: [
                makeEntry(id: older, start: 10, length: 5, hasNote: false),
                makeEntry(id: newer, start: 11, length: 3, hasNote: false),
            ]
        )
        #expect(result?.id == newer)
    }

    @Test
    func hitTest_singleNotelessHighlight_stillResolves() {
        // A lone color-only highlight still resolves (its empty-note editor is
        // the intended state, not a bug).
        let id = UUID()
        let result = TextHighlightHitTester.hitTest(
            charIndex: 12, in: [makeEntry(id: id, start: 10, length: 5, hasNote: false)]
        )
        #expect(result?.id == id)
    }

    @Test
    func hitTest_notedNotCoveringIndex_doesNotWin() {
        // A noted highlight that does NOT cover the tapped index must not be
        // preferred over a note-less one that does.
        let notedElsewhere = UUID()
        let notelessHere = UUID()
        let result = TextHighlightHitTester.hitTest(
            charIndex: 12,
            in: [
                makeEntry(id: notedElsewhere, start: 30, length: 5, hasNote: true),
                makeEntry(id: notelessHere, start: 10, length: 5, hasNote: false),
            ]
        )
        #expect(result?.id == notelessHere)
    }

    @Test
    func hitTest_zeroLengthRange_alwaysMisses() {
        // A degenerate zero-length range can't contain any character.
        let e = makeEntry(start: 10, length: 0)
        let result = TextHighlightHitTester.hitTest(charIndex: 10, in: [e])
        #expect(result == nil)
    }

    @Test
    func hitTest_multipleNonOverlapping_returnsCorrectEntry() {
        let id1 = UUID()
        let id2 = UUID()
        let id3 = UUID()
        let entries = [makeEntry(id: id1, start: 0, length: 5), makeEntry(id: id2, start: 10, length: 5), makeEntry(id: id3, start: 20, length: 5)]
        #expect(TextHighlightHitTester.hitTest(charIndex: 2, in: entries)?.id == id1)
        #expect(TextHighlightHitTester.hitTest(charIndex: 12, in: entries)?.id == id2)
        #expect(TextHighlightHitTester.hitTest(charIndex: 22, in: entries)?.id == id3)
        // Gap between ranges: index 7 is not in any.
        #expect(TextHighlightHitTester.hitTest(charIndex: 7, in: entries) == nil)
    }

    @Test
    func entry_isValueTypeAndEquatable() {
        let id = UUID()
        let r = NSRange(location: 1, length: 2)
        let a = PersistedHighlightLookupEntry(id: id, range: r)
        let b = PersistedHighlightLookupEntry(id: id, range: r)
        #expect(a == b)
    }
}
