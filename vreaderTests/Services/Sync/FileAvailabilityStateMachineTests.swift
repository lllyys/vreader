// Purpose: Tests for FileAvailabilityStateMachine — all valid transitions,
// invalid transitions, canOpenReader, full lifecycle, error recovery.

import Testing
import Foundation
@testable import vreader

@Suite("FileAvailabilityStateMachine")
struct FileAvailabilityStateMachineTests {

    let machine = FileAvailabilityStateMachine()

    // MARK: - Valid Transitions

    @Test func metadataOnlyToQueuedDownloadOnUserOpen() {
        let result = machine.transition(from: .metadataOnly, event: .userOpen)
        #expect(result == .queuedDownload)
    }

    @Test func metadataOnlyToQueuedDownloadOnAutoDownload() {
        let result = machine.transition(from: .metadataOnly, event: .autoDownload)
        #expect(result == .queuedDownload)
    }

    @Test func queuedDownloadToDownloadingOnSchedulerStart() {
        let result = machine.transition(from: .queuedDownload, event: .schedulerStart)
        #expect(result == .downloading)
    }

    @Test func downloadingToAvailableOnDownloadComplete() {
        let result = machine.transition(from: .downloading, event: .downloadComplete(checksumValid: true))
        #expect(result == .available)
    }

    @Test func downloadingToFailedOnDownloadFailed() {
        let result = machine.transition(from: .downloading, event: .downloadFailed)
        #expect(result == .failed)
    }

    @Test func availableToStaleOnCorruptionDetected() {
        let result = machine.transition(from: .available, event: .corruptionDetected)
        #expect(result == .stale)
    }

    @Test func failedToQueuedDownloadOnRetry() {
        let result = machine.transition(from: .failed, event: .retry)
        #expect(result == .queuedDownload)
    }

    @Test func staleToQueuedDownloadOnRetry() {
        let result = machine.transition(from: .stale, event: .retry)
        #expect(result == .queuedDownload)
    }

    // MARK: - Invalid Transitions (no-op, returns current state)

    @Test func metadataOnlyIgnoresSchedulerStart() {
        let result = machine.transition(from: .metadataOnly, event: .schedulerStart)
        #expect(result == .metadataOnly)
    }

    @Test func metadataOnlyIgnoresDownloadComplete() {
        let result = machine.transition(from: .metadataOnly, event: .downloadComplete(checksumValid: true))
        #expect(result == .metadataOnly)
    }

    @Test func availableIgnoresUserOpen() {
        let result = machine.transition(from: .available, event: .userOpen)
        #expect(result == .available)
    }

    @Test func availableIgnoresRetry() {
        let result = machine.transition(from: .available, event: .retry)
        #expect(result == .available)
    }

    @Test func downloadingIgnoresUserOpen() {
        let result = machine.transition(from: .downloading, event: .userOpen)
        #expect(result == .downloading)
    }

    @Test func failedIgnoresSchedulerStart() {
        let result = machine.transition(from: .failed, event: .schedulerStart)
        #expect(result == .failed)
    }

    @Test func queuedDownloadIgnoresRetry() {
        let result = machine.transition(from: .queuedDownload, event: .retry)
        #expect(result == .queuedDownload)
    }

    // MARK: - Checksum Mismatch

    @Test func downloadingToFailedOnChecksumMismatch() {
        let result = machine.transition(from: .downloading, event: .downloadComplete(checksumValid: false))
        #expect(result == .failed)
    }

    // MARK: - canOpenReader

    @Test func canOpenReaderOnlyForAvailable() {
        #expect(machine.canOpenReader(state: .available) == true)
        #expect(machine.canOpenReader(state: .metadataOnly) == false)
        #expect(machine.canOpenReader(state: .queuedDownload) == false)
        #expect(machine.canOpenReader(state: .downloading) == false)
        #expect(machine.canOpenReader(state: .failed) == false)
        #expect(machine.canOpenReader(state: .stale) == false)
    }

    // MARK: - Full Lifecycle

    @Test func fullLifecycleMetadataOnlyToAvailable() {
        var state = FileAvailability.metadataOnly
        state = machine.transition(from: state, event: .userOpen)
        #expect(state == .queuedDownload)
        state = machine.transition(from: state, event: .schedulerStart)
        #expect(state == .downloading)
        state = machine.transition(from: state, event: .downloadComplete(checksumValid: true))
        #expect(state == .available)
        #expect(machine.canOpenReader(state: state))
    }

    @Test func errorRecoveryLifecycle() {
        var state = FileAvailability.downloading
        state = machine.transition(from: state, event: .downloadFailed)
        #expect(state == .failed)
        #expect(!machine.canOpenReader(state: state))
        state = machine.transition(from: state, event: .retry)
        #expect(state == .queuedDownload)
        state = machine.transition(from: state, event: .schedulerStart)
        #expect(state == .downloading)
        state = machine.transition(from: state, event: .downloadComplete(checksumValid: true))
        #expect(state == .available)
        #expect(machine.canOpenReader(state: state))
    }

    @Test func staleRecoveryLifecycle() {
        var state = FileAvailability.available
        state = machine.transition(from: state, event: .corruptionDetected)
        #expect(state == .stale)
        #expect(!machine.canOpenReader(state: state))
        state = machine.transition(from: state, event: .retry)
        #expect(state == .queuedDownload)
        state = machine.transition(from: state, event: .schedulerStart)
        #expect(state == .downloading)
        state = machine.transition(from: state, event: .downloadComplete(checksumValid: true))
        #expect(state == .available)
    }

    // MARK: - Edge: Multiple retries

    @Test func multipleRetriesFromFailed() {
        var state = FileAvailability.failed
        for _ in 0..<5 {
            state = machine.transition(from: state, event: .retry)
            #expect(state == .queuedDownload)
            state = machine.transition(from: state, event: .schedulerStart)
            state = machine.transition(from: state, event: .downloadFailed)
            #expect(state == .failed)
        }
    }
}
