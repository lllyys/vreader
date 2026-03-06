// Purpose: Deterministic state machine for file availability transitions.
// Implements the 6-state model from plan Section 4.3.
//
// Key decisions:
// - Pure function: no side effects, easily testable.
// - Invalid transitions return the current state (no-op).
// - Checksum mismatch on download complete transitions to .failed.
// - canOpenReader is true ONLY for .available state.
//
// @coordinates-with: SyncTypes.swift, SyncService.swift

import Foundation

/// Deterministic state machine for file download availability.
///
/// Valid transitions:
/// 1. metadataOnly → queuedDownload (on userOpen or autoDownload)
/// 2. queuedDownload → downloading (on schedulerStart)
/// 3. downloading → available (on downloadComplete with valid checksum)
/// 4. downloading → failed (on downloadFailed or checksum mismatch)
/// 5. available → stale (on corruptionDetected)
/// 6. failed → queuedDownload (on retry)
/// 7. stale → queuedDownload (on retry)
struct FileAvailabilityStateMachine: Sendable {

    /// Computes the next state given the current state and an event.
    /// Returns the current state unchanged for invalid transitions.
    func transition(from state: FileAvailability, event: FileAvailabilityEvent) -> FileAvailability {
        switch (state, event) {
        // 1. metadataOnly → queuedDownload
        case (.metadataOnly, .userOpen),
             (.metadataOnly, .autoDownload):
            return .queuedDownload

        // 2. queuedDownload → downloading
        case (.queuedDownload, .schedulerStart):
            return .downloading

        // 3. downloading → available (checksum valid)
        case (.downloading, .downloadComplete(checksumValid: true)):
            return .available

        // 4. downloading → failed (checksum invalid or download failed)
        case (.downloading, .downloadComplete(checksumValid: false)),
             (.downloading, .downloadFailed):
            return .failed

        // 5. available → stale
        case (.available, .corruptionDetected):
            return .stale

        // 6-7. failed/stale → queuedDownload
        case (.failed, .retry),
             (.stale, .retry):
            return .queuedDownload

        // All other combinations are invalid → no-op
        default:
            return state
        }
    }

    /// Whether the reader can be opened in the given state.
    /// Only `.available` allows reading.
    func canOpenReader(state: FileAvailability) -> Bool {
        state == .available
    }
}
