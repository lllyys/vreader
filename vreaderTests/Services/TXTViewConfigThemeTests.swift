// Purpose: Feature #60 WI-5 — pins the contract that
// `ReaderSettingsStore.txtViewConfig` and `mdRenderConfig` render
// TXT and MD content with the WI-2 `ReaderThemeV2` token surface
// (Paper / Sepia / Dark / OLED / Photo), not the legacy
// `ReaderTheme`'s 3-color palette. WI-11 migrated
// `ReaderSettingsStore.theme` itself to `ReaderThemeV2`, so these
// configs read its tokens directly.

#if canImport(UIKit)
import Testing
import UIKit
@testable import vreader

@Suite("TXTViewConfig / MDRenderConfig — V2 theme tokens")
struct TXTViewConfigThemeTests {

    @MainActor
    private func makeStore() -> ReaderSettingsStore {
        let defaults = UserDefaults(
            suiteName: "TXTViewConfigThemeTests-\(UUID().uuidString)"
        )!
        return ReaderSettingsStore(defaults: defaults)
    }

    private func rgbInts(_ color: UIColor) -> (r: Int, g: Int, b: Int) {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        color.getRed(&r, green: &g, blue: &b, alpha: &a)
        return (Int((r * 255).rounded()),
                Int((g * 255).rounded()),
                Int((b * 255).rounded()))
    }

    // MARK: - txtViewConfig.backgroundColor → V2 outer bg

    @Test @MainActor func txtViewConfig_lightTheme_usesV2PaperOuterBg() {
        var s = makeStore(); s.theme = .paper
        // Paper outer bg: 0xf4eee0 = (244, 238, 224)
        let bg = rgbInts(s.txtViewConfig.backgroundColor)
        #expect(bg == (244, 238, 224),
                "Light/paper theme TXTViewConfig.backgroundColor must use V2 paper outer bg, got \(bg)")
    }

    @Test @MainActor func txtViewConfig_sepiaTheme_usesV2SepiaOuterBg() {
        var s = makeStore(); s.theme = .sepia
        // Sepia outer bg: 0xe6d6b6 = (230, 214, 182)
        let bg = rgbInts(s.txtViewConfig.backgroundColor)
        #expect(bg == (230, 214, 182),
                "Sepia theme TXTViewConfig.backgroundColor must use V2 sepia outer bg, got \(bg)")
    }

    @Test @MainActor func txtViewConfig_darkTheme_usesV2DarkOuterBg() {
        var s = makeStore(); s.theme = .dark
        // Dark outer bg: 0x1a1815 = (26, 24, 21)
        let bg = rgbInts(s.txtViewConfig.backgroundColor)
        #expect(bg == (26, 24, 21),
                "Dark theme TXTViewConfig.backgroundColor must use V2 dark outer bg, got \(bg)")
    }

    // MARK: - txtViewConfig.textColor → V2 ink

    @Test @MainActor func txtViewConfig_lightTheme_usesV2PaperInk() {
        var s = makeStore(); s.theme = .paper
        // Paper ink: 0x1d1a14 = (29, 26, 20)
        let ink = rgbInts(s.txtViewConfig.textColor)
        #expect(ink == (29, 26, 20),
                "Light theme TXTViewConfig.textColor must use V2 paper ink, got \(ink)")
    }

    @Test @MainActor func txtViewConfig_sepiaTheme_usesV2SepiaInk() {
        var s = makeStore(); s.theme = .sepia
        // Sepia ink: 0x3a2913 = (58, 41, 19)
        let ink = rgbInts(s.txtViewConfig.textColor)
        #expect(ink == (58, 41, 19))
    }

    @Test @MainActor func txtViewConfig_darkTheme_usesV2DarkInk() {
        var s = makeStore(); s.theme = .dark
        // Dark ink: 0xd8d2c5 = (216, 210, 197)
        let ink = rgbInts(s.txtViewConfig.textColor)
        #expect(ink == (216, 210, 197))
    }

    // MARK: - mdRenderConfig parallels txtViewConfig

    @Test @MainActor func mdRenderConfig_lightTheme_usesV2PaperInk() {
        var s = makeStore(); s.theme = .paper
        let ink = rgbInts(s.mdRenderConfig.textColor)
        #expect(ink == (29, 26, 20),
                "MDRenderConfig.textColor must mirror txtViewConfig (both go through ReaderThemeV2.inkColor)")
    }

    @Test @MainActor func mdRenderConfig_darkTheme_usesV2DarkInk() {
        var s = makeStore(); s.theme = .dark
        let ink = rgbInts(s.mdRenderConfig.textColor)
        #expect(ink == (216, 210, 197))
    }

    // MARK: - Secondary text token (uiSecondaryTextColor → V2 sub)
    //
    // `sub` is encoded as ink-with-alpha so the RGB component is
    // ink's RGB and the alpha is per-theme. Pin both RGB and alpha
    // (Codex Gate 4 round 1) — alpha-only assertions would pass even
    // if a regression substituted the wrong RGB.

    private func rgba(_ color: UIColor) -> (r: Int, g: Int, b: Int, a: CGFloat) {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        color.getRed(&r, green: &g, blue: &b, alpha: &a)
        return (Int((r * 255).rounded()),
                Int((g * 255).rounded()),
                Int((b * 255).rounded()),
                a)
    }

    @Test @MainActor func uiSecondaryTextColor_lightTheme_usesV2SubRGBA() {
        var s = makeStore(); s.theme = .paper
        let c = rgba(s.uiSecondaryTextColor)
        // Paper sub: ink-RGB (29,26,20) + alpha 0.55
        #expect(c.r == 29 && c.g == 26 && c.b == 20,
                "Paper sub RGB must equal paper ink RGB, got (\(c.r),\(c.g),\(c.b))")
        #expect(abs(c.a - 0.55) < 0.01,
                "Paper sub alpha must be 0.55 (got \(c.a))")
    }

    @Test @MainActor func uiSecondaryTextColor_darkTheme_usesV2SubRGBA() {
        var s = makeStore(); s.theme = .dark
        let c = rgba(s.uiSecondaryTextColor)
        // Dark sub: ink-RGB (216,210,197) + alpha 0.5
        #expect(c.r == 216 && c.g == 210 && c.b == 197,
                "Dark sub RGB must equal dark ink RGB, got (\(c.r),\(c.g),\(c.b))")
        #expect(abs(c.a - 0.5) < 0.01,
                "Dark sub alpha must be 0.5 (got \(c.a))")
    }

    // MARK: - MDRenderConfig secondary + code-block colors (WI-5 round-1 fix)

    @Test @MainActor func mdRenderConfig_lightTheme_secondaryAndCodeBg() {
        var s = makeStore(); s.theme = .paper
        let cfg = s.mdRenderConfig
        // secondaryColor → V2 subColor (paper ink + alpha 0.55)
        let sec = rgba(cfg.secondaryColor)
        #expect(sec.r == 29 && sec.g == 26 && sec.b == 20,
                "Light MDRenderConfig.secondaryColor RGB must equal V2 paper subColor RGB")
        #expect(abs(sec.a - 0.55) < 0.01,
                "Light MDRenderConfig.secondaryColor alpha must equal V2 paper subColor alpha")
        // codeBackgroundColor → V2 paperColor (250,246,234)
        let codeBg = rgba(cfg.codeBackgroundColor)
        #expect(codeBg.r == 250 && codeBg.g == 246 && codeBg.b == 234,
                "Light MDRenderConfig.codeBackgroundColor must equal V2 paper paperColor RGB")
    }

    @Test @MainActor func mdRenderConfig_darkTheme_secondaryAndCodeBg() {
        var s = makeStore(); s.theme = .dark
        let cfg = s.mdRenderConfig
        let sec = rgba(cfg.secondaryColor)
        #expect(sec.r == 216 && sec.g == 210 && sec.b == 197,
                "Dark MDRenderConfig.secondaryColor RGB must equal V2 dark subColor RGB")
        #expect(abs(sec.a - 0.5) < 0.01)
        let codeBg = rgba(cfg.codeBackgroundColor)
        #expect(codeBg.r == 33 && codeBg.g == 32 && codeBg.b == 28,
                "Dark MDRenderConfig.codeBackgroundColor must equal V2 dark paperColor RGB")
    }
}
#endif
