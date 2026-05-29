// Purpose: Feature #42 Phase 1 WI-6 — the pure, nonisolated Readium `Locator` ↔
// `VReaderLocator` envelope mapping pair for the Readium EPUB reader. Extracted
// from `ReadiumEPUBReaderViewModel.swift` to keep that file focused on the open
// lifecycle + debounced save/restore wiring; the mapping is a side-effect-free
// translation that unit-tests without a render.
//
// Key decisions:
// - Authoritative leg is `readiumLocatorJSON` — Readium's own deterministic
//   `jsonString()` (sorted keys, preserves href/type/locations). Decode back via
//   the symmetric `Locator(jsonString:)`.
// - The legacy `Locator` leg is intentionally lossy (href + progression only):
//   it exists so a flag-OFF reopen via the legacy engine's `loadPosition` can
//   resume at an approximate position. Full fidelity lives in the Readium leg.
// - `try?` everywhere — a serialization/decode failure degrades to nil, never
//   throws (the SwiftData-safe posture documented on `VReaderLocator`).
//
// WI-7 (preferences): adds the FULL `EPUBPreferences` mapping that translates
// vreader's existing reader settings — `ReaderThemeV2` + `TypographySettings` +
// `EPUBLayoutPreference` — into the preferences the Readium navigator applies
// live. Key decisions:
// - Theme: vreader's 5 themes collapse onto Readium's 3 bases (`paper → .light`,
//   `sepia → .sepia`, `dark`/`oled`/`photo → .dark`) AND each carries vreader's
//   EXACT `backgroundColor`/`inkColor` as explicit `Color` overrides. Readium's
//   `EPUBSettings.effectiveBackgroundColor` is `backgroundColor ?? theme.bg`, so
//   the explicit color WINS over the base swatch — the base theme only seeds the
//   CSS class (selection/link tinting, image filter) while vreader's warm paper /
//   pure-black oled / photo overlay render faithfully. (`Color(uiColor:)` drops
//   alpha; bg/ink tokens are all alpha 1.0 so no loss.)
// - fontSize: Readium's `fontSize` is a MULTIPLIER (1.0 = 100% of the publisher
//   base), not an absolute pt. vreader's `TypographySettings.fontSize` default is
//   18pt, so we map `pt / 18 → multiplier` (18 → 1.0, 36 → 2.0, 12 → 0.66, 64 →
//   3.55). This is independent of the legacy engine's calibrated-px CSS injection
//   (a different model); a Phase-1 approximation refined by device verification.
// - lineHeight = `lineSpacing` (both are multipliers in compatible ranges).
// - fontFamily: `.system → nil` (publisher default), `.serif → .serif`,
//   `.monospace → .monospace`. Bundled custom faces map to the closest Readium
//   generic (`.sourceSerif4 → .serif`, `.inter → .sansSerif`) — registering the
//   .otf with the navigator's `fontFamilyDeclarations` (a file-serving
//   `CSSFontFamilyDeclaration`) is a documented Phase-1 follow-up.
// - publisherStyles = false so vreader's font/theme overrides actually apply over
//   the book's own CSS (Readium ignores most overrides when publisherStyles on).
// - pageMargins = 1.0 (publisher default factor); the host's `.ignoresSafeArea()`
//   + the navigator's own safe-area insets keep content off the Dynamic Island /
//   home indicator (#163), so a modest factor is sufficient.
//
// Known Phase-1 limitation (Gate-4 round-1 Medium — gates the WI-14 default-ON
// flip, tracked for WI-13 acceptance): the `.photo` theme + `useCustomBackground`
// render only as an OPAQUE theme color here. The legacy EPUB engine composites a
// decorative background IMAGE behind semi-transparent reader content via a CSS
// `background-image` + the SwiftUI `ThemeBackgroundView`; Readium applies our
// opaque `backgroundColor` to the navigator view + CSS root, which occludes the
// `ThemeBackgroundView` and does not reproduce the image. The result is readable
// (opaque dark bg + light ink) but loses the photo overlay. Faithful parity needs
// a transparent navigator/webview + image compositing (or background-image CSS
// injection) — a deferred slice, NOT shipped behind this dark flag.
//
// @coordinates-with ReadiumEPUBReaderViewModel.swift, VReaderLocator.swift,
//   Locator.swift, ReaderThemeV2.swift, TypographySettings.swift

import Foundation
import ReadiumShared
import ReadiumNavigator

extension ReadiumEPUBReaderViewModel {

    // MARK: - Full preferences mapping (WI-7)

    /// The font-size pt that anchors the Readium multiplier at 1.0 (= 100% of
    /// the publisher base). vreader's unified `TypographySettings.fontSize`
    /// default is 18pt, so a CALIBRATED `.epub` size equal to this base maps to
    /// 1.0. (Gate-4 round-1: the multiplier is computed from the calibrated
    /// `.epub` size, not the raw unified pt — see `epubPreferences`.)
    nonisolated static var fontSizeBasePt: CGFloat { 18.0 }

    /// Default horizontal page-margin factor (Readium publisher default). The
    /// host's `.ignoresSafeArea()` + navigator safe-area insets handle #163.
    nonisolated static var defaultPageMargins: Double { 1.0 }

    /// Translates vreader's reader settings into a full Readium `EPUBPreferences`
    /// the navigator applies live. Pure + `nonisolated static` so the mapping is
    /// unit-testable without a render. See the file header for every decision.
    ///
    /// `calibratedFontSizePt` is the per-format-calibrated EPUB point size the
    /// host computes via `ReaderSettingsStore.calibrator.calibratedSize(
    /// forUnified: typography.fontSize, target: .epub)` (Gate-4 round-1 Medium):
    /// the legacy EPUB engine renders through that same `.epub` calibration band,
    /// so feeding the calibrated value (not the raw unified pt) keeps perceived
    /// size consistent across the legacy and Readium engines. The Readium
    /// `fontSize` is a MULTIPLIER of the publisher base, so we divide by
    /// `fontSizeBasePt`.
    nonisolated static func epubPreferences(
        theme: ReaderThemeV2,
        typography: TypographySettings,
        layout: EPUBLayoutPreference,
        calibratedFontSizePt: CGFloat
    ) -> EPUBPreferences {
        EPUBPreferences(
            backgroundColor: Color(uiColor: theme.backgroundColor),
            fontFamily: readiumFontFamily(for: typography.fontFamily),
            fontSize: Double(calibratedFontSizePt / fontSizeBasePt),
            lineHeight: Double(typography.lineSpacing),
            pageMargins: defaultPageMargins,
            publisherStyles: false,
            scroll: layout == .scroll,
            textColor: Color(uiColor: theme.inkColor),
            theme: readiumTheme(for: theme)
        )
    }

    /// Collapses vreader's 5 themes onto Readium's 3 base themes. The base seeds
    /// the CSS class; the explicit bg/ink colors (set alongside) carry the exact
    /// vreader shade and win via `effectiveBackgroundColor`.
    nonisolated static func readiumTheme(for theme: ReaderThemeV2) -> ReadiumNavigator.Theme {
        switch theme {
        case .paper: return .light
        case .sepia: return .sepia
        case .dark, .oled, .photo: return .dark
        }
    }

    /// Maps vreader's `ReaderFontFamily` to a Readium `FontFamily`.
    ///
    /// Gate-4 round-1 Medium: `.system` maps to `.sansSerif`, NOT nil. Because
    /// these preferences set `publisherStyles = false`, a nil `fontFamily` makes
    /// Readium fall back to its OWN base stack (an old-style serif), not the
    /// platform/system sans-serif vreader's `.system` means everywhere else
    /// (`UIFont.systemFont` → San Francisco). `.sansSerif` is the closest Readium
    /// generic to SF (Readium has no SF face). Bundled custom faces map to the
    /// closest generic class — registering the .otf via the navigator's
    /// `fontFamilyDeclarations` (a file-serving `CSSFontFamilyDeclaration`) is a
    /// documented Phase-1 follow-up.
    nonisolated static func readiumFontFamily(
        for family: ReaderFontFamily
    ) -> ReadiumNavigator.FontFamily? {
        switch family {
        case .system: return .sansSerif
        case .serif, .sourceSerif4: return .serif
        case .monospace: return .monospace
        case .inter: return .sansSerif
        }
    }

    /// Wraps a Readium `Locator` in a durable `VReaderLocator` envelope tagged
    /// `engine: .readium`. The authoritative leg is `readiumLocatorJSON` —
    /// Readium's own deterministic `jsonString()` serialization (sorted keys,
    /// preserves `href`/`type`/`locations`). A best-effort, intentionally lossy
    /// legacy `Locator` (just `href` + `progression`) is also carried so a
    /// flag-OFF reopen can resume at an approximate position. Returns nil only
    /// if Readium fails to serialize the locator (it never should — logged by
    /// the caller).
    nonisolated static func makeVReaderLocator(
        from readiumLocator: ReadiumShared.Locator,
        fingerprintKey: String,
        fingerprint: DocumentFingerprint,
        originalFormat: BookFormat
    ) -> VReaderLocator? {
        guard let json = try? readiumLocator.jsonString() else { return nil }
        let legacy = Locator(
            bookFingerprint: fingerprint,
            href: readiumLocator.href.string,
            progression: readiumLocator.locations.progression,
            totalProgression: readiumLocator.locations.totalProgression,
            cfi: nil, page: nil,
            charOffsetUTF16: nil, charRangeStartUTF16: nil, charRangeEndUTF16: nil,
            textQuote: nil, textContextBefore: nil, textContextAfter: nil
        )
        return VReaderLocator(
            fingerprintKey: fingerprintKey,
            originalFormat: originalFormat,
            engine: .readium,
            readiumLocatorJSON: json,
            legacyLocator: legacy
        )
    }

    /// Decodes the Readium `Locator` back out of a `.readium` envelope. Returns
    /// nil for a non-Readium envelope, a nil/malformed `readiumLocatorJSON`, or
    /// any decode failure — `try?`, never throws (SwiftData-safe posture).
    nonisolated static func readiumLocator(
        from envelope: VReaderLocator
    ) -> ReadiumShared.Locator? {
        guard envelope.engine == .readium, let json = envelope.readiumLocatorJSON else {
            return nil
        }
        return try? ReadiumShared.Locator(jsonString: json)
    }
}
