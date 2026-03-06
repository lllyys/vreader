// Purpose: SwiftUI view showing sync status badge.
// Displays state icon + text, tappable for details when in error state.
//
// Key decisions:
// - Observes SyncStatusMonitor for reactive UI updates.
// - Feature-flagged: hidden when sync is disabled.
// - Minimal footprint for library toolbar integration.
//
// @coordinates-with: SyncStatusMonitor.swift, SyncTypes.swift

import SwiftUI

/// Compact sync status indicator for use in navigation bars / toolbars.
struct SyncStatusView: View {
    let monitor: SyncStatusMonitor

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: iconName)
                .font(.caption)
                .foregroundStyle(iconColor)
            Text(statusText)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .opacity(monitor.status == .disabled ? 0 : 1)
    }

    // MARK: - Private

    private var iconName: String {
        switch monitor.status {
        case .disabled: return "icloud.slash"
        case .idle: return "checkmark.icloud"
        case .syncing: return "arrow.triangle.2.circlepath.icloud"
        case .error: return "exclamationmark.icloud"
        case .offline: return "icloud.slash"
        }
    }

    private var iconColor: Color {
        switch monitor.status {
        case .disabled, .offline: return .secondary
        case .idle: return .green
        case .syncing: return .blue
        case .error: return .red
        }
    }

    private var statusText: String {
        switch monitor.status {
        case .disabled: return "Sync Off"
        case .idle: return "Synced"
        case .syncing: return "Syncing…"
        case .error: return "Sync Error"
        case .offline: return "Offline"
        }
    }
}
