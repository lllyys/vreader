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

    private func makeEntry(id: UUID = UUID(), start: Int, length: Int) -> PersistedHighlightLookupEntry {
        PersistedHighlightLookupEntry(id: id, range: NSRange(location: start, length: length))
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
