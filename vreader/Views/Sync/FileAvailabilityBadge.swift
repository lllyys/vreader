// Purpose: Badge overlay for library items showing file download state.
// Shows download progress, retry button for failed, cloud icon for metadata-only.
//
// Key decisions:
// - Compact badge design for use as overlay on book cards/rows.
// - Retry action exposed as a closure for parent coordination.
// - Only visible when state is not .available (no badge needed when file is ready).
//
// @coordinates-with: SyncTypes.swift, FileAvailabilityStateMachine.swift

import SwiftUI

/// Badge overlay showing file availability state on library items.
struct FileAvailabilityBadge: View {
    let state: FileAvailability
    var onRetry: (() -> Void)?

    var body: some View {
        if state != .available {
            HStack(spacing: 4) {
                Image(systemName: iconName)
                    .font(.caption2)
                if state == .failed || state == .stale {
                    Button(action: { onRetry?() }) {
                        Text("Retry")
                            .font(.caption2)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(.ultraThinMaterial, in: Capsule())
            .accessibilityElement(children: .combine)
            .accessibilityLabel(AccessibilityFormatters.accessibleFileAvailability(state: state))
        }
    }

    private var iconName: String {
        switch state {
        case .metadataOnly: return "icloud"
        case .queuedDownload: return "icloud.and.arrow.down"
        case .downloading: return "arrow.down.circle"
        case .available: return "checkmark.circle"
        case .failed: return "exclamationmark.triangle"
        case .stale: return "arrow.clockwise.icloud"
        }
    }
}
