// Purpose: Feature #99 WI-3 — the bilingual pill's press state
// (design `BSBilingualPill` pressed). Split from ReaderTopChrome.swift
// for the ~300-line file budget.
//
// @coordinates-with: ReaderTopChrome.swift, BilingualPill.swift,
//   ReaderThemeV2.swift

import SwiftUI

/// Feature #99: the bilingual pill's press state (design
/// `BSBilingualPill` pressed) — accent fill at hex-33 alpha (20%) +
/// a 2pt ring at hex-55 alpha (33%) while the finger is down; the
/// pill's own hex-1a (10%) background shows through at rest.
struct BilingualPillButtonStyle: ButtonStyle {
    let theme: ReaderThemeV2

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                Capsule().fill(
                    configuration.isPressed
                        ? Color(theme.accentColor).opacity(0.20)
                        : Color.clear
                )
            )
            .overlay(
                Capsule().strokeBorder(
                    configuration.isPressed
                        ? Color(theme.accentColor).opacity(0.33)
                        : Color.clear,
                    lineWidth: 2
                )
            )
    }
}
