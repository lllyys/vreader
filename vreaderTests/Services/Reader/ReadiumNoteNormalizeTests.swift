// Bug #303: the Readium host's select → Note path persists a highlight WITH a
// note via `HighlightCoordinator.create(note:)`. The new decision the Note save
// introduces over a plain highlight is note normalization — a blank / whitespace-
// only note must degrade to `nil` (a plain highlight), otherwise the trimmed text
// is stored. These pin that seam. The observer + `AddNoteSheet` presentation +
// live WKWebView text selection are exercised by device verification (mirroring
// the WI-8 builder/selection split), not here.
//
// @coordinates-with vreader/Services/Reader/ReadiumSelectionHighlightBuilder.swift,
//   vreader/Views/Reader/ReadiumEPUBHost+Annotations.swift

import Testing
import Foundation
@testable import vreader

@Suite("ReadiumSelectionHighlightBuilder.normalizeNote (Bug #303)")
struct ReadiumNoteNormalizeTests {

    @Test("empty string → nil (plain highlight)")
    func emptyToNil() {
        #expect(ReadiumSelectionHighlightBuilder.normalizeNote("") == nil)
    }

    @Test("whitespace / newlines only → nil (plain highlight)")
    func whitespaceToNil() {
        #expect(ReadiumSelectionHighlightBuilder.normalizeNote("   ") == nil)
        #expect(ReadiumSelectionHighlightBuilder.normalizeNote("\n\t  \n") == nil)
    }

    @Test("non-empty note is trimmed and kept")
    func trimsAndKeeps() {
        #expect(ReadiumSelectionHighlightBuilder.normalizeNote("  hello  ") == "hello")
        #expect(ReadiumSelectionHighlightBuilder.normalizeNote("a note") == "a note")
    }

    @Test("internal whitespace is preserved, only the ends are trimmed")
    func preservesInternalWhitespace() {
        #expect(
            ReadiumSelectionHighlightBuilder.normalizeNote("  two  words  ") == "two  words"
        )
    }

    @Test("CJK note survives normalization")
    func cjkNote() {
        #expect(ReadiumSelectionHighlightBuilder.normalizeNote(" 笔记 ") == "笔记")
    }
}
