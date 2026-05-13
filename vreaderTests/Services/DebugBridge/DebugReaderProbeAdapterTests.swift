// Purpose: Tests for DebugReaderProbeAdapter (feature #44 DebugBridge).
// Validates that the default-implemented v2 protocol fields
// (currentTTSState / currentTTSOffsetUTF16) can be overridden by wiring a
// `ttsProbe` closure — the integration seam used by ReaderContainerView
// (feature #45 WI-4c-c) to surface TTS state into DebugSnapshot.

#if DEBUG

import XCTest
@testable import vreader

@MainActor
final class DebugReaderProbeAdapterTests: XCTestCase {

    // MARK: - TTS probe defaults

    func test_currentTTSState_isNilWhenTTSProbeUnset() {
        let adapter = DebugReaderProbeAdapter(
            fingerprintKey: "txt:abc:1024",
            format: "txt"
        )
        XCTAssertNil(adapter.currentTTSState)
    }

    func test_currentTTSOffsetUTF16_isNilWhenTTSProbeUnset() {
        let adapter = DebugReaderProbeAdapter(
            fingerprintKey: "txt:abc:1024",
            format: "txt"
        )
        XCTAssertNil(adapter.currentTTSOffsetUTF16)
    }

    // MARK: - TTS probe wired

    func test_currentTTSState_returnsClosureValue() {
        let adapter = DebugReaderProbeAdapter(
            fingerprintKey: "txt:abc:1024",
            format: "txt"
        )
        adapter.ttsProbe = { (state: "speaking", offsetUTF16: 42) }
        XCTAssertEqual(adapter.currentTTSState, "speaking")
    }

    func test_currentTTSOffsetUTF16_returnsClosureValue() {
        let adapter = DebugReaderProbeAdapter(
            fingerprintKey: "txt:abc:1024",
            format: "txt"
        )
        adapter.ttsProbe = { (state: "speaking", offsetUTF16: 42) }
        XCTAssertEqual(adapter.currentTTSOffsetUTF16, 42)
    }

    func test_currentTTSOffsetUTF16_returnsNilFromClosure() {
        // .idle state → no meaningful offset → closure returns nil for offset
        // while still returning "idle" for state.
        let adapter = DebugReaderProbeAdapter(
            fingerprintKey: "txt:abc:1024",
            format: "txt"
        )
        adapter.ttsProbe = { (state: "idle", offsetUTF16: nil) }
        XCTAssertEqual(adapter.currentTTSState, "idle")
        XCTAssertNil(adapter.currentTTSOffsetUTF16)
    }
}

#endif
