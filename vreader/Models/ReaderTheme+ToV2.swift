// Purpose: Feature #60 — legacy `ReaderTheme` ↔ `ReaderThemeV2` bridge.
// Two faces of the same migration:
//
//  1. `ReaderTheme.asV2` (WI-4) — type-level projection used by
//     code that holds a legacy `ReaderTheme` value at runtime.
//  2. `ReaderThemeV2(legacyOrNew:)` (WI-11) — non-throwing string
//     mapper. WI-11 migrates `ReaderSettingsStore.theme` to
//     `ReaderThemeV2`; the UserDefaults `readerTheme` key and the
//     per-book `themeName` field both carry bare rawValue strings
//     (not JSON-wrapped), so the `Codable` decoder is awkward at
//     those call sites. This is the single source of truth for
//     "interpret a stored theme string".
//
// Mapping (matches the Codable alias in `ReaderThemeV2.init(from:)`):
//   legacy "light" → .paper
//   legacy "sepia" → .sepia  (same name in V2)
//   legacy "dark"  → .dark   (same name in V2)
//
// `ReaderTheme.asV2` stays a `var` (not `init?(legacy:)`) because the
// legacy→V2 mapping is total — an optional return would be misleading.
// OLED and Photo have no legacy equivalent; before WI-11 they were
// reachable only by the V2-aware reader-engine paths, and from WI-11
// onward also by the 5-theme settings picker.

import Foundation

extension ReaderTheme {
    /// V2 projection of this legacy theme. Used by injection paths
    /// (EPUB CSS, TXT/MD theme) and by the WI-11 backward-compat
    /// decode in `ReaderThemeV2(legacyOrNew:)`.
    var asV2: ReaderThemeV2 {
        switch self {
        case .light: return .paper
        case .sepia: return .sepia
        case .dark:  return .dark
        }
    }
}

extension ReaderThemeV2 {
    /// Maps a stored theme string — a new `ReaderThemeV2` rawValue, a
    /// legacy `ReaderTheme` rawValue, `nil`, or an unknown value — to a
    /// `ReaderThemeV2`. Feature #60 WI-11 backward-compat decode.
    ///
    /// Resolution order:
    ///  1. New rawValue (`paper` / `sepia` / `dark` / `oled` / `photo`).
    ///  2. Legacy `ReaderTheme` rawValue (`light` → `.paper`; `sepia` /
    ///     `dark` already covered by step 1, so this only fires for
    ///     `light`).
    ///  3. `nil` or unknown → `.default` (`.paper`).
    ///
    /// Non-throwing on purpose: every call site (UserDefaults load,
    /// per-book `themeName` apply) already owns a fallback policy, and
    /// the policy is uniformly "fall back to the default theme". The
    /// throwing `Codable` decoder remains for JSON-wrapped values; this
    /// agrees with it for every value the decoder accepts.
    init(legacyOrNew raw: String?) {
        self = ReaderThemeV2(recognized: raw) ?? .default
    }

    /// Strict counterpart of `init(legacyOrNew:)`: returns `nil` for an
    /// unknown or `nil` string instead of falling back to `.default`.
    /// Used where the caller must NOT clobber existing state on a
    /// corrupt value — e.g. `ReaderSettingsStore.applyResolvedSettings`
    /// only assigns the theme when the per-book `themeName` is a
    /// recognized value, leaving the live theme untouched otherwise.
    ///
    /// Recognizes the same set as `init(legacyOrNew:)`: the 5 new
    /// rawValues plus the legacy `ReaderTheme` rawValue `light`
    /// (`sepia` / `dark` are shared names).
    init?(recognized raw: String?) {
        guard let raw else { return nil }
        if let v2 = ReaderThemeV2(rawValue: raw) {
            self = v2
        } else if let legacy = ReaderTheme(rawValue: raw) {
            self = legacy.asV2
        } else {
            return nil
        }
    }
}
