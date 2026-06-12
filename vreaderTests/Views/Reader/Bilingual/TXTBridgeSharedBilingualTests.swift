// Purpose: Feature #56 WI-12b — pin `TXTBridgeShared.postSelectionNotification`'s
// bilingual segment-map routing. Codex Gate-4 H2 — selection-action
// notifications (Highlight / Add Note / Define / Translate) must carry
// source-domain offsets even when bilingual interlinear is rendering
// translation runs after each paragraph.
//
// Identity-map (off-mode) = byte-identical pass-through to today's
// behavior.
//
// @coordinates-with: TXTBridgeShared.swift, BilingualDisplaySegmentMap.swift,
//   ReaderNotifications.swift,
//   dev-docs/plans/20260519-feature-56-bilingual-reading.md (WI-12b)

import XCTest
@testable import vreader

@MainActor
final class TXTBridgeSharedBilingualTests: XCTestCase {

    // MARK: - identity map: byte-identical pass-through

    func test_identity_passThrough() async {
        let tv = UITextView()
        tv.text = "Hello world"
        let exp = expectation(description: "highlight requested")
        nonisolated(unsafe) var captured: TextSelectionInfo?
        let token = NotificationCenter.default.addObserver(
            forName: .readerHighlightRequested, object: nil, queue: .main
        ) { notification in
            captured = notification.object as? TextSelectionInfo
            exp.fulfill()
        }
        defer { NotificationCenter.default.removeObserver(token) }
        TXTBridgeShared.postSelectionNotification(
            .readerHighlightRequested,
            from: tv,
            range: NSRange(location: 0, length: 5),
            bilingualSegmentMap: BilingualDisplaySegmentMap.identity(sourceLength: 11)
        )
        await fulfillment(of: [exp], timeout: 1.0)
        XCTAssertEqual(captured?.startUTF16, 0)
        XCTAssertEqual(captured?.endUTF16, 5)
    }

    // MARK: - non-identity: synthetic-skip + offset routing

    func test_nonIdentity_selectionInSourceSegment_routesToSource() async {
        let tv = UITextView()
        tv.text = "AAA[T]BBB"
        let segments: [BilingualDisplaySegmentMap.Segment] = [
            .source(sourceRange: 0..<3, displayRange: 0..<3),
            .synthetic(displayRange: 3..<6),
            .source(sourceRange: 3..<6, displayRange: 6..<9)
        ]
        let map = BilingualDisplaySegmentMap(sourceLength: 6, segments: segments)
        let exp = expectation(description: "highlight requested")
        nonisolated(unsafe) var captured: TextSelectionInfo?
        let token = NotificationCenter.default.addObserver(
            forName: .readerHighlightRequested, object: nil, queue: .main
        ) { notification in
            captured = notification.object as? TextSelectionInfo
            exp.fulfill()
        }
        defer { NotificationCenter.default.removeObserver(token) }
        TXTBridgeShared.postSelectionNotification(
            .readerHighlightRequested,
            from: tv,
            range: NSRange(location: 6, length: 3),
            bilingualSegmentMap: map
        )
        await fulfillment(of: [exp], timeout: 1.0)
        XCTAssertEqual(captured?.startUTF16, 3)
        XCTAssertEqual(captured?.endUTF16, 6)
    }

    // (The former test_nonIdentity_selectionStartInSynthetic_dropped pinned
    // the WI-12b silent-drop contract; bug #350 overturned it — the same
    // input now anchors to the parent paragraph. See the Bug #350 extension
    // below: test_bug350_selectionInsideTranslationRow_anchorsToParentParagraph.)

    func test_nonIdentity_selectionEndAtSyntheticBoundary_preservesEnd() async {
        let tv = UITextView()
        tv.text = "AAA[T]BBB"
        let segments: [BilingualDisplaySegmentMap.Segment] = [
            .source(sourceRange: 0..<3, displayRange: 0..<3),
            .synthetic(displayRange: 3..<6),
            .source(sourceRange: 3..<6, displayRange: 6..<9)
        ]
        let map = BilingualDisplaySegmentMap(sourceLength: 6, segments: segments)
        let exp = expectation(description: "highlight requested")
        nonisolated(unsafe) var captured: TextSelectionInfo?
        let token = NotificationCenter.default.addObserver(
            forName: .readerHighlightRequested, object: nil, queue: .main
        ) { notification in
            captured = notification.object as? TextSelectionInfo
            exp.fulfill()
        }
        defer { NotificationCenter.default.removeObserver(token) }
        TXTBridgeShared.postSelectionNotification(
            .readerHighlightRequested,
            from: tv,
            range: NSRange(location: 0, length: 3),  // ends at synthetic-start
            bilingualSegmentMap: map
        )
        await fulfillment(of: [exp], timeout: 1.0)
        XCTAssertEqual(captured?.startUTF16, 0)
        XCTAssertEqual(captured?.endUTF16, 3)
    }
}

// MARK: - Bug #350: a selection STARTING in a synthetic run must still
// raise the card (projected to the source), not silently drop.

extension TXTBridgeSharedBilingualTests {

    /// Layout: source para A (display 0..<3), its translation row
    /// (3..<6), source para B (6..<9).
    private func makeInterlinearMap() -> BilingualDisplaySegmentMap {
        BilingualDisplaySegmentMap(sourceLength: 6, segments: [
            .source(sourceRange: 0..<3, displayRange: 0..<3),
            .synthetic(displayRange: 3..<6),
            .source(sourceRange: 3..<6, displayRange: 6..<9),
        ])
    }

    func test_bug350_selectionInsideTranslationRow_anchorsToParentParagraph() async {
        let tv = UITextView()
        tv.text = "AAA[T]BBB"
        let exp = expectation(description: "posted")
        nonisolated(unsafe) var captured: TextSelectionInfo?
        let token = NotificationCenter.default.addObserver(
            forName: .readerHighlightRequested, object: nil, queue: .main
        ) { n in captured = n.object as? TextSelectionInfo; exp.fulfill() }
        defer { NotificationCenter.default.removeObserver(token) }

        // Long-press selected a word INSIDE the translation row (4..<5).
        TXTBridgeShared.postSelectionNotification(
            .readerHighlightRequested, from: tv,
            range: NSRange(location: 4, length: 1),
            bilingualSegmentMap: makeInterlinearMap()
        )
        await fulfillment(of: [exp], timeout: 1.0)
        // Anchored to the PARENT source paragraph (the preceding source
        // segment's full range 0..<3) — the silent drop was bug #350.
        XCTAssertEqual(captured?.startUTF16, 0)
        XCTAssertEqual(captured?.endUTF16, 3)
        // Codex round 2 (Medium): the text must match the PROJECTED
        // source span, not the translation row the press landed on.
        XCTAssertEqual(captured?.selectedText, "AAA")
    }

    func test_bug350_selectionSpanningOutOfTranslationRow_startsAtFollowingSource() async {
        let tv = UITextView()
        tv.text = "AAA[T]BBB"
        let exp = expectation(description: "posted")
        nonisolated(unsafe) var captured: TextSelectionInfo?
        let token = NotificationCenter.default.addObserver(
            forName: .readerHighlightRequested, object: nil, queue: .main
        ) { n in captured = n.object as? TextSelectionInfo; exp.fulfill() }
        defer { NotificationCenter.default.removeObserver(token) }

        // Starts in the translation row (display 4), ends inside para B
        // (display 4..<8 → covers B's first two source chars 3..<5).
        TXTBridgeShared.postSelectionNotification(
            .readerHighlightRequested, from: tv,
            range: NSRange(location: 4, length: 4),
            bilingualSegmentMap: makeInterlinearMap()
        )
        await fulfillment(of: [exp], timeout: 1.0)
        XCTAssertEqual(captured?.startUTF16, 3)
        XCTAssertEqual(captured?.endUTF16, 5)
        // Codex round 2 (Medium): source span 3..<5 renders at display
        // 6..<8 — the first two chars of para B.
        XCTAssertEqual(captured?.selectedText, "BB")
    }

    func test_bug350_sourceStartSpanningIntoTranslationRow_postsSourceTextOnly() async {
        // Codex round 3 (Medium): a selection STARTING in source text that
        // extends into a synthetic row must post the SOURCE span's text —
        // not the display substring with translation content inside.
        let tv = UITextView()
        tv.text = "AAA[T]BBB"
        let exp = expectation(description: "posted")
        nonisolated(unsafe) var captured: TextSelectionInfo?
        let token = NotificationCenter.default.addObserver(
            forName: .readerHighlightRequested, object: nil, queue: .main
        ) { n in captured = n.object as? TextSelectionInfo; exp.fulfill() }
        defer { NotificationCenter.default.removeObserver(token) }

        // Display 1..<5: starts at source char 1, ends inside the
        // translation row.
        TXTBridgeShared.postSelectionNotification(
            .readerHighlightRequested, from: tv,
            range: NSRange(location: 1, length: 4),
            bilingualSegmentMap: makeInterlinearMap()
        )
        await fulfillment(of: [exp], timeout: 1.0)
        XCTAssertEqual(captured?.startUTF16, 1)
        XCTAssertEqual(captured?.endUTF16, 3)
        XCTAssertEqual(captured?.selectedText, "AA",
                       "Display substring would be 'AA[T' — synthetic content must be excluded.")
    }

    func test_bug350_syntheticWithNoPrecedingSource_stillDrops() async {
        let tv = UITextView()
        tv.text = "[T]AAA"
        // Synthetic FIRST (no parent paragraph before it).
        let map = BilingualDisplaySegmentMap(sourceLength: 3, segments: [
            .synthetic(displayRange: 0..<3),
            .source(sourceRange: 0..<3, displayRange: 3..<6),
        ])
        nonisolated(unsafe) var posted = false
        let token = NotificationCenter.default.addObserver(
            forName: .readerHighlightRequested, object: nil, queue: .main
        ) { _ in posted = true }
        defer { NotificationCenter.default.removeObserver(token) }

        TXTBridgeShared.postSelectionNotification(
            .readerHighlightRequested, from: tv,
            range: NSRange(location: 0, length: 2),
            bilingualSegmentMap: map
        )
        try? await Task.sleep(for: .milliseconds(200))
        XCTAssertFalse(posted, "no parent source paragraph exists — nothing to anchor")
    }
}
