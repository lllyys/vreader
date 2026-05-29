// Purpose: Feature #42 Phase 1 WI-7 — unit tests for the FULL Readium
// `EPUBPreferences` mapping that translates vreader's existing reader settings
// (`ReaderThemeV2` + `TypographySettings` + `EPUBLayoutPreference`) into the
// preferences the Readium navigator applies live. Pure mapping — no render —
// so it pins every translation branch (theme → Readium Theme base + explicit
// colors, fontSize pt → multiplier, lineHeight, fontFamily, publisherStyles,
// scroll, pageMargins) and the determinism invariant.
//
// The live re-submit (host reads settings → recompute → submitPreferences) is
// exercised by device verification, not here — this file pins the pure seam.
//
// @coordinates-with vreader/ViewModels/ReadiumEPUBReaderViewModel+Mapping.swift,
//   vreader/Models/ReaderThemeV2.swift, vreader/Models/TypographySettings.swift

import Testing
import Foundation
import ReadiumShared
import ReadiumNavigator
@testable import vreader

@Suite("ReadiumEPUBReaderViewModel preferences mapping (WI-7)")
struct ReadiumEPUBPreferencesMappingTests {

    // MARK: - Helpers

    /// Drives the pure mapping. `calibratedFontSizePt` defaults to the raw
    /// `typography.fontSize` so the fontSize→multiplier math (18→1.0, 36→2.0) is
    /// asserted directly on the mapping; the host's `.epub`-calibration of that
    /// input is the host's concern (Gate-4 round-1 — verified at the call site).
    private func prefs(
        theme: ReaderThemeV2 = .paper,
        typography: TypographySettings = TypographySettings(),
        layout: EPUBLayoutPreference = .scroll
    ) -> EPUBPreferences {
        ReadiumEPUBReaderViewModel.epubPreferences(
            theme: theme, typography: typography, layout: layout,
            calibratedFontSizePt: typography.fontSize
        )
    }

    // MARK: - Theme → Readium Theme base + explicit colors

    // `ReadiumNavigator.Theme` is not `Sendable`, so it can't be a parameterized
    // test argument — assert each base via its Sendable `rawValue` String.
    @Test(arguments: [
        (ReaderThemeV2.paper, "light"),
        (ReaderThemeV2.sepia, "sepia"),
        (ReaderThemeV2.dark,  "dark"),
        (ReaderThemeV2.oled,  "dark"),
        (ReaderThemeV2.photo, "dark"),
    ])
    func theme_mapsToReadiumBase(_ vTheme: ReaderThemeV2, _ expectedRaw: String) {
        #expect(prefs(theme: vTheme).theme?.rawValue == expectedRaw)
    }

    @Test(arguments: [
        ReaderThemeV2.paper, .sepia, .dark, .oled, .photo,
    ])
    func theme_setsExplicitBackgroundAndTextColor(_ vTheme: ReaderThemeV2) {
        let p = prefs(theme: vTheme)
        // Every theme carries vreader's exact bg/ink so Readium's 3 base
        // themes don't flatten oled/photo/paper into generic light/dark.
        #expect(p.backgroundColor != nil)
        #expect(p.textColor != nil)
        #expect(p.backgroundColor == Color(uiColor: vTheme.backgroundColor))
        #expect(p.textColor == Color(uiColor: vTheme.inkColor))
    }

    /// OLED pure-black is the case Readium's `.dark` (#000000) happens to match,
    /// but paper's warm tint and photo's overlay do NOT — assert the explicit
    /// color is the vreader shade, not the Readium base default.
    @Test func theme_oledBackgroundIsPureBlack() {
        let p = prefs(theme: .oled)
        #expect(p.backgroundColor == Color(uiColor: ReaderThemeV2.oled.backgroundColor))
    }

    @Test func theme_paperBackgroundIsWarmTint_notReadiumWhite() {
        let p = prefs(theme: .paper)
        // Readium `.light` background is #FFFFFF; vreader paper is #f4eee0.
        #expect(p.backgroundColor == Color(uiColor: ReaderThemeV2.paper.backgroundColor))
        #expect(p.backgroundColor != Color(hex: "#FFFFFF"))
    }

    // MARK: - fontSize pt → Readium multiplier (base 18pt = 1.0)

    @Test func fontSize_defaultEighteen_mapsToOne() {
        let p = prefs(typography: TypographySettings(fontSize: 18))
        #expect(p.fontSize == 1.0)
    }

    @Test func fontSize_thirtySix_mapsToTwo() {
        let p = prefs(typography: TypographySettings(fontSize: 36))
        #expect(p.fontSize == 2.0)
    }

    @Test func fontSize_minTwelve_isFinitePositiveBelowOne() {
        let p = prefs(typography: TypographySettings(fontSize: 12))
        let fs = try! #require(p.fontSize)
        #expect(fs > 0)
        #expect(fs.isFinite)
        #expect(fs < 1.0)
        #expect(fs == 12.0 / 18.0)
    }

    @Test func fontSize_maxSixtyFour_isFinitePositiveAboveOne() {
        let p = prefs(typography: TypographySettings(fontSize: 64))
        let fs = try! #require(p.fontSize)
        #expect(fs > 1.0)
        #expect(fs.isFinite)
        #expect(fs == 64.0 / 18.0)
    }

    /// Gate-4 round-1: the multiplier is computed from the CALIBRATED `.epub`
    /// size the host feeds (not the raw unified pt). The legacy EPUB engine
    /// renders through `FontSizeCalibrator.calibratedSize(forUnified:target:.epub)`,
    /// so feeding the same calibrated value keeps perceived size consistent
    /// across engines.
    ///
    /// Bug #280: the `.epub` multiplier is now `1.0` (sim-measured cap-height
    /// parity with TXT — see `FontSizeCalibration.swift`), so at the 18pt
    /// default the calibrated value is 18 and the Readium relative multiplier
    /// is exactly 1.0. The invariant under test is that the mapping consumes
    /// the calibrated input (`fs == calibrated / 18`), not that the multiplier
    /// exceeds 1.0 (which only held under the un-verified 1.12 estimate).
    @Test func fontSize_usesCalibratedInput_notRawUnified() {
        let calibrated = FontSizeCalibrator().calibratedSize(forUnified: 18, target: .epub)
        let p = ReadiumEPUBReaderViewModel.epubPreferences(
            theme: .paper, typography: TypographySettings(fontSize: 18),
            layout: .paged, calibratedFontSizePt: calibrated
        )
        let fs = try! #require(p.fontSize)
        #expect(fs == Double(calibrated / 18.0))
        // The calibrated `.epub` value never drops below the raw unified value
        // (the multiplier is >= 1.0), so the relative multiplier is >= 1.0.
        #expect(fs >= 1.0)
    }

    // MARK: - lineHeight = lineSpacing multiplier

    @Test(arguments: [1.0, 1.4, 2.0])
    func lineHeight_matchesLineSpacing(_ spacing: Double) {
        let p = prefs(typography: TypographySettings(lineSpacing: CGFloat(spacing)))
        #expect(p.lineHeight == spacing)
    }

    // MARK: - fontFamily mapping

    @Test func fontFamily_system_isNil() {
        // .system → .sansSerif (Gate-4 round-1): with publisherStyles=false a nil
        // family would fall back to Readium's old-style serif, not vreader's SF.
        #expect(prefs(typography: TypographySettings(fontFamily: .system)).fontFamily == .sansSerif)
    }

    @Test func fontFamily_serif_isReadiumSerif() {
        #expect(prefs(typography: TypographySettings(fontFamily: .serif)).fontFamily == .serif)
    }

    @Test func fontFamily_monospace_isReadiumMonospace() {
        #expect(prefs(typography: TypographySettings(fontFamily: .monospace)).fontFamily == .monospace)
    }

    /// Phase-1 spike decision: bundled custom faces map to the closest Readium
    /// generic class (Source Serif 4 → serif, Inter → sans-serif) rather than
    /// registering the .otf with the navigator. Documented follow-up.
    @Test func fontFamily_sourceSerif4_mapsToSerif() {
        #expect(prefs(typography: TypographySettings(fontFamily: .sourceSerif4)).fontFamily == .serif)
    }

    @Test func fontFamily_inter_mapsToSansSerif() {
        #expect(prefs(typography: TypographySettings(fontFamily: .inter)).fontFamily == .sansSerif)
    }

    // MARK: - publisherStyles + scroll + pageMargins

    @Test func publisherStyles_isFalse_soOverridesApply() {
        // Must be false or Readium ignores our font/theme overrides.
        #expect(prefs().publisherStyles == false)
    }

    @Test func scroll_scrollLayout_isTrue() {
        #expect(prefs(layout: .scroll).scroll == true)
    }

    @Test func scroll_pagedLayout_isFalse() {
        #expect(prefs(layout: .paged).scroll == false)
    }

    @Test func pageMargins_isFinitePositive() {
        let m = try! #require(prefs().pageMargins)
        #expect(m > 0)
        #expect(m.isFinite)
    }

    // MARK: - Determinism

    @Test func mapping_isDeterministic_sameInputsEqualOutput() {
        let typo = TypographySettings(fontSize: 24, lineSpacing: 1.6, fontFamily: .serif)
        let a = ReadiumEPUBReaderViewModel.epubPreferences(theme: .sepia, typography: typo, layout: .paged, calibratedFontSizePt: 24)
        let b = ReadiumEPUBReaderViewModel.epubPreferences(theme: .sepia, typography: typo, layout: .paged, calibratedFontSizePt: 24)
        #expect(a.theme == b.theme)
        #expect(a.backgroundColor == b.backgroundColor)
        #expect(a.textColor == b.textColor)
        #expect(a.fontSize == b.fontSize)
        #expect(a.lineHeight == b.lineHeight)
        #expect(a.fontFamily == b.fontFamily)
        #expect(a.scroll == b.scroll)
        #expect(a.publisherStyles == b.publisherStyles)
        #expect(a.pageMargins == b.pageMargins)
    }

    // MARK: - WI-5 wrapper still works (scroll-only API)

    @Test func legacyLayoutOnlyWrapper_scroll_stillMapsScroll() {
        #expect(ReadiumEPUBReaderViewModel.epubPreferences(for: .scroll).scroll == true)
        #expect(ReadiumEPUBReaderViewModel.epubPreferences(for: .paged).scroll == false)
    }

    // MARK: - WI-7 photo/custom-background compositing (transparent navigator)

    /// When a custom decorative background should show through, the navigator's
    /// HTML body must NOT paint an opaque color — the mapping returns a NIL
    /// `backgroundColor`. Readium injects the `--USER__backgroundColor` body rule
    /// only when this is non-nil, so nil leaves the body transparent over the
    /// already-`.clear` spine WebViews and the composited `ThemeBackgroundView`
    /// behind shows through. The text color stays the legible theme ink.
    /// (Readium's `Color` is RGB-only with no alpha — nil is the only lever.)
    @Test func transparentBackground_clearsBackgroundColor_keepsTextColor() {
        let p = ReadiumEPUBReaderViewModel.epubPreferences(
            theme: .photo, typography: TypographySettings(), layout: .paged,
            calibratedFontSizePt: 18, transparentBackground: true
        )
        #expect(p.backgroundColor == nil)
        // Text color must stay the theme ink for legibility over the image.
        #expect(p.textColor == Color(uiColor: ReaderThemeV2.photo.inkColor))
        // The natural theme→base collapse is preserved (`.photo → .dark`); the
        // opaque `:root` background the night appearance would inject is cleared
        // by the coordinator's `setupUserScripts` injection, not a base swap.
        #expect(p.theme?.rawValue == "dark")
    }

    /// Default (no transparency) is unchanged — the opaque theme color path that
    /// every existing test pins must keep rendering the solid theme background.
    @Test func transparentBackground_defaultsFalse_keepsOpaqueThemeColor() {
        let p = ReadiumEPUBReaderViewModel.epubPreferences(
            theme: .photo, typography: TypographySettings(), layout: .paged,
            calibratedFontSizePt: 18
        )
        #expect(p.backgroundColor == Color(uiColor: ReaderThemeV2.photo.backgroundColor))
    }

    /// The pure decision: transparency is requested only when a custom background
    /// is enabled AND an image actually exists for the theme. Either missing →
    /// opaque (no regression for normal themes / enabled-but-no-image).
    @Test(arguments: [
        (true, true, true),
        (true, false, false),
        (false, true, false),
        (false, false, false),
    ])
    func shouldRenderTransparent_requiresBothEnabledAndImage(
        _ useCustomBackground: Bool, _ hasImage: Bool, _ expected: Bool
    ) {
        #expect(
            ReadiumEPUBReaderViewModel.shouldRenderTransparentBackground(
                useCustomBackground: useCustomBackground, hasBackgroundImage: hasImage
            ) == expected
        )
    }
}
