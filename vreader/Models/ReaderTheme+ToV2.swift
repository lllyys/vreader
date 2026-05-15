// Purpose: Feature #60 WI-4 — legacy `ReaderTheme` → `ReaderThemeV2`
// projection. Lets WI-4+ call sites (EPUB CSS, TXT/MD theme) drive
// the new 5-token surface while `ReaderSettingsStore.theme` still
// stores the 3-case legacy enum, until a later WI migrates the
// settings type itself.
//
// Why this is a `var` and not a `init?(legacy:)`:
// - The mapping is total (every legacy case has a V2 home), so an
//   optional return would be misleading.
// - Codable already handles persisted-string migration via the
//   legacy "light" alias in `ReaderThemeV2.init(from:)`. This file
//   covers the type-level projection used by code that holds a
//   `ReaderTheme` value at runtime.
//
// Mapping (matches the Codable alias):
//   .light → .paper
//   .sepia → .sepia
//   .dark  → .dark
//
// OLED and Photo have no legacy equivalent — they are reachable only
// via the V2-aware settings path that ships in a later WI.

import Foundation

extension ReaderTheme {
    /// V2 projection of this legacy theme. Used by WI-4+ injection
    /// paths while `ReaderSettingsStore.theme` is still 3-case typed.
    var asV2: ReaderThemeV2 {
        switch self {
        case .light: return .paper
        case .sepia: return .sepia
        case .dark:  return .dark
        }
    }
}
