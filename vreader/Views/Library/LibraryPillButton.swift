// Purpose: Feature #60 WI-9 — the circular pill button used across the
// Library nav bar. Mirrors the design `pillBtn` style from
// `dev-docs/designs/vreader-fidelity-v1/project/vreader-library.jsx`:
// a 36pt circle filled with the warm wash, holding a 19pt SF Symbol
// glyph tinted the design dark brown.
//
// Key decisions:
// - Geometry + palette come from `LibraryCardTokens` — one home for
//   the design spec.
// - `.contentShape(Circle())` so the whole pill is tappable, not just
//   the glyph.
// - Accessibility label + identifier are required init params — every
//   pill is a discrete control an XCUITest harness must be able to
//   find; the pre-#60 toolbar buttons carried these identifiers and
//   the re-skin preserves them verbatim.
//
// @coordinates-with: LibraryNavBar.swift, LibraryCardTokens.swift

import SwiftUI

/// A circular nav-bar pill button — design `pillBtn`.
struct LibraryPillButton: View {
    let systemImage: String
    let accessibilityLabel: String
    let accessibilityIdentifier: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(
                    size: LibraryCardTokens.navIconSize,
                    weight: .medium
                ))
                .foregroundStyle(LibraryCardTokens.navIconTint)
                .frame(
                    width: LibraryCardTokens.navPillSize,
                    height: LibraryCardTokens.navPillSize
                )
                .background(
                    Circle().fill(LibraryCardTokens.navPillBackground)
                )
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityIdentifier(accessibilityIdentifier)
    }
}
