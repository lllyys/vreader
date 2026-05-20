// Purpose: Unit tests for the pure helpers exposed on
// DebugBridgeHighlightObserver (Bug #237 — verification harness
// highlight-driver). Validates the selected-text extraction logic shared
// by TXT and MD format hosts.

#if DEBUG

import XCTest
@testable import vreader

final class DebugBridgeHighlightObserverTests: XCTestCase {

    // MARK: - Helpers

    private func makeFingerprint() -> DocumentFingerprint {
        DocumentFingerprint(
            contentSHA256: String(repeating: "a", count: 64),
            fileByteCount: 1024,
            format: .txt
        )
    }

    private func makeLocator(start: Int, end: Int) -> Locator {
        Locator.validated(
            bookFingerprint: makeFingerprint(),
            charOffsetUTF16: start,
            charRangeStartUTF16: start,
            charRangeEndUTF16: end
        )!
    }

    // MARK: - Continuous source (TXT continuous mode / MD)

    func test_extractSelectedText_continuousSource_returnsSubstring() {
        let text = "Hello, world!"
        let locator = makeLocator(start: 7, end: 12) // "world"
        let selected = DebugBridgeHighlightObserver.extractSelectedText(
            locator: locator,
            continuousSource: text,
            chapterSource: nil,
            chapterLocalStart: nil,
            chapterLocalEnd: nil
        )
        XCTAssertEqual(selected, "world")
    }

    func test_extractSelectedText_continuousSource_atStart_returnsSubstring() {
        let text = "Hello, world!"
        let locator = makeLocator(start: 0, end: 5) // "Hello"
        let selected = DebugBridgeHighlightObserver.extractSelectedText(
            locator: locator,
            continuousSource: text,
            chapterSource: nil,
            chapterLocalStart: nil,
            chapterLocalEnd: nil
        )
        XCTAssertEqual(selected, "Hello")
    }

    func test_extractSelectedText_continuousSource_outOfBounds_returnsEmpty() {
        let text = "Hello"
        let locator = makeLocator(start: 0, end: 100) // way past end
        let selected = DebugBridgeHighlightObserver.extractSelectedText(
            locator: locator,
            continuousSource: text,
            chapterSource: nil,
            chapterLocalStart: nil,
            chapterLocalEnd: nil
        )
        XCTAssertEqual(selected, "", "out-of-range range returns empty, not crash")
    }

    func test_extractSelectedText_cjkContinuousSource_returnsSubstring() {
        // CJK characters are 1 UTF-16 code unit each in the BMP, so
        // start/end offsets match character indices.
        let text = "你好世界"
        let locator = makeLocator(start: 1, end: 3) // "好世"
        let selected = DebugBridgeHighlightObserver.extractSelectedText(
            locator: locator,
            continuousSource: text,
            chapterSource: nil,
            chapterLocalStart: nil,
            chapterLocalEnd: nil
        )
        XCTAssertEqual(selected, "好世")
    }

    func test_extractSelectedText_emojiAcrossSurrogatePair_snapsToScalarBoundary() {
        // Emoji like "🎉" are 2 UTF-16 code units (a surrogate pair).
        // String.Index(utf16Offset:in:) snaps to the nearest scalar
        // boundary; the helper must not crash.
        let text = "ab🎉cd"  // a(0) b(1) 🎉(2..3) c(4) d(5)
        let locator = makeLocator(start: 0, end: 4) // "ab🎉"
        let selected = DebugBridgeHighlightObserver.extractSelectedText(
            locator: locator,
            continuousSource: text,
            chapterSource: nil,
            chapterLocalStart: nil,
            chapterLocalEnd: nil
        )
        XCTAssertEqual(selected, "ab🎉")
    }

    // MARK: - Chapter source (TXT chapter mode)

    func test_extractSelectedText_chapterSource_usesChapterLocalOffsets() {
        // In chapter mode the locator's range is document-global, but
        // we have chapter-local source and chapter-local offsets — use
        // those to extract the substring.
        let chapterText = "Once upon a time"
        let documentOffset = 100 // arbitrary; chapter starts at offset 100
        let locator = makeLocator(start: documentOffset + 5, end: documentOffset + 9)
        let selected = DebugBridgeHighlightObserver.extractSelectedText(
            locator: locator,
            continuousSource: nil,
            chapterSource: chapterText,
            chapterLocalStart: 5, // "upon"
            chapterLocalEnd: 9
        )
        XCTAssertEqual(selected, "upon")
    }

    func test_extractSelectedText_chapterSource_preferredOverContinuous() {
        // If both sources are supplied, chapter source wins — that's the
        // chapter-mode posture.
        let chapterText = "chapter local text"
        let continuousText = "document-global continuous text"
        let locator = makeLocator(start: 0, end: 7)
        let selected = DebugBridgeHighlightObserver.extractSelectedText(
            locator: locator,
            continuousSource: continuousText,
            chapterSource: chapterText,
            chapterLocalStart: 0,
            chapterLocalEnd: 7
        )
        XCTAssertEqual(selected, "chapter")
    }

    // MARK: - Missing source

    func test_extractSelectedText_noSource_returnsEmpty() {
        // Loading state — no source text available. Helper returns "" so
        // the bridge can still persist the highlight (matching gesture
        // behavior when textContent is nil).
        let locator = makeLocator(start: 5, end: 10)
        let selected = DebugBridgeHighlightObserver.extractSelectedText(
            locator: locator,
            continuousSource: nil,
            chapterSource: nil,
            chapterLocalStart: nil,
            chapterLocalEnd: nil
        )
        XCTAssertEqual(selected, "")
    }

    func test_extractSelectedText_chapterSourceWithoutOffsets_returnsEmpty() {
        // Chapter source supplied but chapter-local offsets nil: the helper
        // can't recover document-global offsets from chapter source, so
        // returns "".
        let locator = makeLocator(start: 100, end: 110)
        let selected = DebugBridgeHighlightObserver.extractSelectedText(
            locator: locator,
            continuousSource: nil,
            chapterSource: "chapter text",
            chapterLocalStart: nil,
            chapterLocalEnd: nil
        )
        XCTAssertEqual(selected, "")
    }

    // MARK: - Default color constant

    func test_defaultColor_isYellow() {
        XCTAssertEqual(DebugBridgeHighlightObserver.defaultColor, "yellow",
                       "default color must match gesture-path fallback in resolveHighlightColor")
    }
}

#endif
