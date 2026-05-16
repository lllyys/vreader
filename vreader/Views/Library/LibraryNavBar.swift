// Purpose: Feature #60 WI-9 — re-skinned Library nav bar. A row of
// circular pill buttons over the warm-paper shell, replacing the
// system `.navigationBar` toolbar `LibraryView` used pre-#60.
//
// Layout follows `dev-docs/designs/vreader-fidelity-v1/project/
// vreader-library.jsx` `LibraryScreen`'s nav-bar block:
//
//   [Settings]            [Search] [Grid/List] [Plus]
//
// The design depicts four pill buttons. `LibraryView` carries more
// real surfaces than the design's mock (Collections, OPDS catalogs,
// AI chat) — those are rendered with the SAME designed pill treatment
// (`pillBtn`) rather than invented chrome, per rule 51's "designed
// visual treatment with the app's real data model". The leading slot
// keeps Settings (design parity); the trailing group holds every
// other action as a designed pill.
//
// @coordinates-with: LibraryView.swift, LibraryCardTokens.swift,
//   LibraryPillButton.swift, SyncStatusView.swift,
//   `dev-docs/designs/vreader-fidelity-v1/project/vreader-library.jsx`

import SwiftUI

/// Re-skinned Library nav bar — a row of circular pill buttons.
struct LibraryNavBar: View {
    /// Active library view mode — drives the grid/list toggle glyph.
    let viewMode: LibraryViewMode
    /// Whether AI chat is available (feature-flag + key gated). When
    /// false the AI pill is omitted entirely — no disabled chrome.
    let isAIChatAvailable: Bool
    /// Whether the Search pill should be shown. False for an empty
    /// library — there is nothing to search, so the pill is omitted
    /// rather than left as a dead control.
    let isSearchEnabled: Bool
    /// Optional sync-status monitor; renders the compact badge when set.
    let syncMonitor: SyncStatusMonitor?

    let onSettings: () -> Void
    let onSearchToggle: () -> Void
    let onViewModeToggle: () -> Void
    let onCollections: () -> Void
    let onOPDSCatalogs: () -> Void
    let onAIChat: () -> Void
    let onImport: () -> Void

    var body: some View {
        HStack(spacing: LibraryCardTokens.navPillSpacing) {
            // Leading: Settings (design parity).
            LibraryPillButton(
                systemImage: "gearshape",
                accessibilityLabel: "Settings",
                accessibilityIdentifier: "settingsToolbarButton",
                action: onSettings
            )

            if let syncMonitor {
                SyncStatusView(monitor: syncMonitor)
            }

            Spacer(minLength: 0)

            // Trailing group: every other Library action as a designed pill.
            // The Search pill is omitted for an empty library (nothing
            // to search) rather than rendered as a dead control.
            if isSearchEnabled {
                LibraryPillButton(
                    systemImage: "magnifyingglass",
                    accessibilityLabel: "Search",
                    accessibilityIdentifier: "librarySearchToggleButton",
                    action: onSearchToggle
                )
            }
            LibraryPillButton(
                systemImage: viewMode == .grid ? "list.bullet" : "square.grid.2x2",
                accessibilityLabel: viewMode == .grid
                    ? "Switch to list view"
                    : "Switch to grid view",
                accessibilityIdentifier: "viewModeToggle",
                action: onViewModeToggle
            )
            LibraryPillButton(
                systemImage: "folder",
                accessibilityLabel: "Collections",
                accessibilityIdentifier: "collectionsToolbarButton",
                action: onCollections
            )
            LibraryPillButton(
                systemImage: "globe",
                accessibilityLabel: "OPDS Catalogs",
                accessibilityIdentifier: "opdsCatalogsToolbarButton",
                action: onOPDSCatalogs
            )
            if isAIChatAvailable {
                LibraryPillButton(
                    systemImage: "bubble.left.and.bubble.right",
                    accessibilityLabel: "AI Chat",
                    accessibilityIdentifier: "aiChatToolbarButton",
                    action: onAIChat
                )
            }
            LibraryPillButton(
                systemImage: "plus",
                accessibilityLabel: "Import books",
                accessibilityIdentifier: "importBooksToolbarButton",
                action: onImport
            )
        }
        .padding(.horizontal, LibraryCardTokens.shellEdgePadding)
    }
}
