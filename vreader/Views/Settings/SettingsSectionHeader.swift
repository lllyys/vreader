// Purpose: Bug #300 — section header for the app Settings sheet, painted with the
// sheet's designed `sub` token (`theme.subColor`) instead of the system
// `secondaryLabel`.
//
// The Settings sheet pins the `.paper` light theme but sets no
// `.preferredColorScheme`, so a plain `Section("…")` header resolves
// `secondaryLabel` to a faint light-gray in system Dark Mode — ~1.07:1 over the
// cream sheet surface (`#fcf8f0`), barely visible. #297 painted the row CARDS
// (`.listRowBackground`) but left the headers on the system color. Painting the
// designed `sub` token restores legibility regardless of system appearance —
// the same token the reader panel's `*SectionLabel` and the #285/#1292 contrast
// work use for secondary chrome. Kept Settings-local (no cross-feature import of
// the reader's `BilingualSectionLabel`).
//
// The font/casing are inherited from the enclosing `Form` section-header text
// style (SwiftUI applies it to a custom header view); only the COLOR is
// overridden — so this is a restore-to-designed recolor, not a typography
// redesign (Rule 51 exempt).
//
// @coordinates-with: SettingsView.swift, AISettingsSection.swift, ReaderThemeV2.swift

import SwiftUI
import UIKit

/// A Settings `Form` section header painted with the designed `sub` token.
struct SettingsSectionHeader: View {
    let theme: ReaderThemeV2
    let title: String

    /// Bug #300: the header color is the designed `sub` token, NOT the system
    /// `secondaryLabel` (which resolves faint in Dark Mode over the pinned cream
    /// sheet). Exposed as a static so the contrast/regression test can assert the
    /// header resolves a theme token, not a system default.
    static func color(for theme: ReaderThemeV2) -> UIColor { theme.subColor }

    var body: some View {
        Text(title)
            .foregroundStyle(Color(Self.color(for: theme)))
    }
}
