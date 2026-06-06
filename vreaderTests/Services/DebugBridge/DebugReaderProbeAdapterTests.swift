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

    // MARK: - Landing-bloom probe (feature #74)

    func test_landingBloomCount_isZeroWhenProbeUnset() {
        // Protocol-default + adapter both report 0 (no bloom recorded yet) so
        // non-TXT probes compile + read cleanly.
        let adapter = DebugReaderProbeAdapter(
            fingerprintKey: "txt:abc:1024",
            format: "txt"
        )
        XCTAssertEqual(adapter.landingBloomCount, 0)
        XCTAssertEqual(adapter.landingBloomPeakIntensity, 0)
    }

    func test_landingBloomCount_returnsClosureValue() {
        let adapter = DebugReaderProbeAdapter(
            fingerprintKey: "txt:abc:1024",
            format: "txt"
        )
        adapter.landingBloomProbe = { (count: 2, peakIntensity: 0.86) }
        XCTAssertEqual(adapter.landingBloomCount, 2)
    }

    func test_landingBloomPeakIntensity_returnsClosureValue() {
        let adapter = DebugReaderProbeAdapter(
            fingerprintKey: "txt:abc:1024",
            format: "txt"
        )
        adapter.landingBloomProbe = { (count: 1, peakIntensity: 0.7) }
        XCTAssertEqual(adapter.landingBloomPeakIntensity, 0.7)
    }

    // MARK: - awaitSettle strategy wiring (bug #141)

    func test_awaitSettle_usesStrategyWhenSet() async throws {
        // When a settleStrategy is wired, awaitSettle must delegate to it
        // (and NOT fall through to the 100ms placeholder).
        let adapter = DebugReaderProbeAdapter(
            fingerprintKey: "epub:abc:1024",
            format: "epub"
        )
        nonisolated(unsafe) var strategyCalledWith: TimeInterval?
        adapter.settleStrategy = { @MainActor timeout in
            strategyCalledWith = timeout
        }

        try await adapter.awaitSettle(timeout: 7.5)
        XCTAssertEqual(strategyCalledWith, 7.5)
    }

    func test_awaitSettle_propagatesStrategyError() async {
        // A throwing strategy must surface its error, not be swallowed.
        let adapter = DebugReaderProbeAdapter(
            fingerprintKey: "epub:abc:1024",
            format: "epub"
        )
        adapter.settleStrategy = { @MainActor _ in
            throw DebugReaderProbeError.settleTimeout
        }

        do {
            try await adapter.awaitSettle(timeout: 1.0)
            XCTFail("expected settleTimeout to propagate")
        } catch DebugReaderProbeError.settleTimeout {
            // expected
        } catch {
            XCTFail("wrong error: \(error)")
        }
    }

    func test_awaitSettle_fallsBackToPlaceholderWhenStrategyNil() async throws {
        // No strategy → the 100ms placeholder path runs without throwing.
        // (TXT/MD/PDF keep this fallback — settleStrategy is only wired
        // for EPUB/AZW3.)
        let adapter = DebugReaderProbeAdapter(
            fingerprintKey: "txt:abc:1024",
            format: "txt"
        )
        try await adapter.awaitSettle(timeout: 1.0)
    }
}

#endif
