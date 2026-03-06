// Purpose: Unit tests for TokenSpan model — validation, edge cases, Sendable/Equatable.

import Testing
import Foundation
@testable import vreader

@Suite("TokenSpan")
struct TokenSpanTests {

    // MARK: - Basic construction

    @Test func basicTokenSpan() {
        let span = TokenSpan(
            bookFingerprintKey: "txt:abc123:1024",
            normalizedToken: "hello",
            startOffsetUTF16: 0,
            endOffsetUTF16: 5,
            sourceUnitId: "txt:segment:0"
        )
        #expect(span.bookFingerprintKey == "txt:abc123:1024")
        #expect(span.normalizedToken == "hello")
        #expect(span.startOffsetUTF16 == 0)
        #expect(span.endOffsetUTF16 == 5)
        #expect(span.sourceUnitId == "txt:segment:0")
    }

    // MARK: - sourceUnitId canonical formats

    @Test func epubSourceUnitId() {
        let span = TokenSpan(
            bookFingerprintKey: "epub:abc:1024",
            normalizedToken: "test",
            startOffsetUTF16: 10,
            endOffsetUTF16: 14,
            sourceUnitId: "epub:chapter1.xhtml"
        )
        #expect(span.sourceUnitId.hasPrefix("epub:"))
    }

    @Test func pdfSourceUnitId() {
        let span = TokenSpan(
            bookFingerprintKey: "pdf:def:2048",
            normalizedToken: "page",
            startOffsetUTF16: 0,
            endOffsetUTF16: 4,
            sourceUnitId: "pdf:page:0"
        )
        #expect(span.sourceUnitId.hasPrefix("pdf:page:"))
    }

    @Test func txtSourceUnitId() {
        let span = TokenSpan(
            bookFingerprintKey: "txt:ghi:512",
            normalizedToken: "word",
            startOffsetUTF16: 100,
            endOffsetUTF16: 104,
            sourceUnitId: "txt:segment:3"
        )
        #expect(span.sourceUnitId.hasPrefix("txt:segment:"))
    }

    // MARK: - Edge cases

    @Test func emptyToken() {
        let span = TokenSpan(
            bookFingerprintKey: "txt:abc:100",
            normalizedToken: "",
            startOffsetUTF16: 0,
            endOffsetUTF16: 0,
            sourceUnitId: "txt:segment:0"
        )
        #expect(span.normalizedToken.isEmpty)
        #expect(span.startOffsetUTF16 == span.endOffsetUTF16)
    }

    @Test func cjkToken() {
        let span = TokenSpan(
            bookFingerprintKey: "txt:abc:100",
            normalizedToken: "世界",
            startOffsetUTF16: 2,
            endOffsetUTF16: 4,
            sourceUnitId: "txt:segment:0"
        )
        #expect(span.normalizedToken == "世界")
    }

    @Test func emojiToken() {
        // Emoji: 😀 = 2 UTF-16 code units
        let span = TokenSpan(
            bookFingerprintKey: "txt:abc:100",
            normalizedToken: "😀",
            startOffsetUTF16: 6,
            endOffsetUTF16: 8,
            sourceUnitId: "txt:segment:0"
        )
        #expect(span.endOffsetUTF16 - span.startOffsetUTF16 == 2)
    }

    @Test func equatableConformance() {
        let span1 = TokenSpan(
            bookFingerprintKey: "txt:abc:100",
            normalizedToken: "hello",
            startOffsetUTF16: 0,
            endOffsetUTF16: 5,
            sourceUnitId: "txt:segment:0"
        )
        let span2 = TokenSpan(
            bookFingerprintKey: "txt:abc:100",
            normalizedToken: "hello",
            startOffsetUTF16: 0,
            endOffsetUTF16: 5,
            sourceUnitId: "txt:segment:0"
        )
        #expect(span1 == span2)
    }
}
