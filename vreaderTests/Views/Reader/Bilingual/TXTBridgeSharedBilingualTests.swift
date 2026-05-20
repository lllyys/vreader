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

    func test_nonIdentity_selectionStartInSynthetic_dropped() async {
        let tv = UITextView()
        tv.text = "AAA[T]BBB"
        let segments: [BilingualDisplaySegmentMap.Segment] = [
            .source(sourceRange: 0..<3, displayRange: 0..<3),
            .synthetic(displayRange: 3..<6),
            .source(sourceRange: 3..<6, displayRange: 6..<9)
        ]
        let map = BilingualDisplaySegmentMap(sourceLength: 6, segments: segments)
        let exp = expectation(description: "no notification posted")
        exp.isInverted = true
        let token = NotificationCenter.default.addObserver(
            forName: .readerHighlightRequested, object: nil, queue: .main
        ) { _ in exp.fulfill() }
        defer { NotificationCenter.default.removeObserver(token) }
        TXTBridgeShared.postSelectionNotification(
            .readerHighlightRequested,
            from: tv,
            range: NSRange(location: 4, length: 1),  // starts in synthetic
            bilingualSegmentMap: map
        )
        await fulfillment(of: [exp], timeout: 0.3)
    }

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
