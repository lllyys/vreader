// Purpose: Feature #60 visual-identity v2 (WI-10) — status-bar tinting.
// Projects a `ReaderThemeV2` to a SwiftUI `ColorScheme` so the reader
// container can drive `preferredColorScheme(_:)`. The system status-bar
// text colour follows `preferredColorScheme`: a `.dark` scheme yields
// light status-bar text (legible over a dark reader background); a
// `.light` scheme yields dark text (legible over a light background).
//
// Kept in its own file so `ReaderThemeV2.swift` stays SwiftUI-free —
// the core token enum imports only Foundation + UIKit; only this
// projection needs `ColorScheme`.
//
// @coordinates-with: ReaderThemeV2.swift, ReaderContainerView.swift,
//   StatusBarTintingTests.swift

import SwiftUI

extension ReaderThemeV2 {
    /// The SwiftUI color scheme this theme should drive via
    /// `preferredColorScheme(_:)`. Resolves to `.dark` for the
    /// dark-family themes (Dark / OLED / Photo) and `.light` for the
    /// light-family themes (Paper / Sepia) — strictly tracking the
    /// existing `isDark` predicate so the status bar stays legible.
    var preferredColorScheme: ColorScheme {
        isDark ? .dark : .light
    }
}
