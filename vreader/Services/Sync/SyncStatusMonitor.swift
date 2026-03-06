// Purpose: Observable sync status for UI display.
// Tracks current sync state, last sync date, pending changes count, and errors.
//
// Key decisions:
// - @Observable @MainActor for SwiftUI data binding.
// - Simple property-based updates — no async observation needed for V2.
// - errorDescription computed from status for convenience.
//
// @coordinates-with: SyncTypes.swift, SyncService.swift

import Foundation
import Observation

/// Observable sync status for UI display.
@Observable
@MainActor
final class SyncStatusMonitor {

    /// Current sync status.
    private(set) var status: SyncStatus = .disabled

    /// When sync last completed successfully.
    private(set) var lastSyncDate: Date?

    /// Number of local changes not yet synced.
    private(set) var pendingChangesCount: Int = 0

    /// Human-readable error description, if status is `.error`.
    var errorDescription: String? {
        if case .error(let message) = status {
            return message
        }
        return nil
    }

    // MARK: - Updates

    /// Updates the sync status and optionally the last sync date.
    func update(status: SyncStatus, lastSyncDate: Date? = nil) {
        self.status = status
        if let lastSyncDate {
            self.lastSyncDate = lastSyncDate
        }
    }

    /// Updates the pending changes count (clamped to >= 0).
    func update(pendingChangesCount: Int) {
        self.pendingChangesCount = max(0, pendingChangesCount)
    }
}
