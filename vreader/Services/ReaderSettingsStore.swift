import Foundation
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif
@Observable
@MainActor
final class ReaderSettingsStore {
    static let themeKey = "readerTheme"
    static let typographyKey = "readerTypography"
    static let readingModeKey = "readerReadingMode"
    static let useCustomBackgroundKey = "readerUseCustomBackground"
    static let backgroundOpacityKey = "readerBackgroundOpacity"
    static let epubLayoutKey = "readerEPUBLayout"
    static let autoPageTurnKey = "readerAutoPageTurn"
    static let autoPageTurnIntervalKey = "readerAutoPageTurnInterval"
    static let pageTurnAnimationKey = "readerPageTurnAnimation"
    static let chineseConversionKey = "readerChineseConversion"
    /// The reader color theme. Feature #60 WI-11: migrated from the
    /// legacy 3-case `ReaderTheme` to the 5-case `ReaderThemeV2`
    /// (Paper / Sepia / Dark / OLED / Photo) so all 5 themes are
    /// user-selectable. Persisted as the V2 rawValue; legacy values
    /// (`light` / `sepia` / `dark`) still decode via
    /// `ReaderThemeV2(legacyOrNew:)`.
    var theme: ReaderThemeV2 { didSet { guard !suppressPersistence else { return }; defaults.set(theme.rawValue, forKey: Self.themeKey) } }
    var readingMode: ReadingMode { didSet { guard !suppressPersistence else { return }; defaults.set(readingMode.rawValue, forKey: Self.readingModeKey) } }
    var epubLayout: EPUBLayoutPreference { didSet { guard !suppressPersistence else { return }; defaults.set(epubLayout.rawValue, forKey: Self.epubLayoutKey) } }
    /// Whether auto page turning is enabled (Issue 9).
    var autoPageTurn: Bool { didSet { guard !suppressPersistence else { return }; defaults.set(autoPageTurn, forKey: Self.autoPageTurnKey) } }
    /// Page turn animation style (B11).
    var pageTurnAnimation: PageTurnAnimation {
        didSet { guard !suppressPersistence else { return }; defaults.set(pageTurnAnimation.rawValue, forKey: Self.pageTurnAnimationKey) }
    }
    /// Interval in seconds between auto page turns (Issue 9). Clamped to 1...60.
    ///
    /// Bug #222: this is a computed `get`/`set` over `_autoPageTurnInterval`,
    /// NOT a stored property with a clamping `didSet`. Under the `@Observable`
    /// macro a `didSet` that re-assigns its own property recurses unboundedly
    /// (the macro rewrites the property into a computed accessor over a backing
    /// store, so the `didSet`'s self-assignment re-enters the synthesized
    /// setter) → stack overflow. The `get`/`set` form clamps in `set` with no
    /// observer re-entry — same pattern as `backgroundOpacity` below.
    var autoPageTurnInterval: TimeInterval {
        get { _autoPageTurnInterval }
        set {
            _autoPageTurnInterval = max(1.0, min(60.0, newValue))
            guard !suppressPersistence else { return }
            defaults.set(_autoPageTurnInterval, forKey: Self.autoPageTurnIntervalKey)
        }
    }
    private var _autoPageTurnInterval: TimeInterval
    /// Chinese Simplified/Traditional conversion direction (E04).
    var chineseConversion: ChineseConversionDirection {
        didSet { guard !suppressPersistence else { return }; defaults.set(chineseConversion.rawValue, forKey: Self.chineseConversionKey) }
    }
    var typography: TypographySettings {
        didSet { guard !suppressPersistence else { return }; if let data = try? JSONEncoder().encode(typography) { defaults.set(data, forKey: Self.typographyKey) } }
    }
    var useCustomBackground: Bool { didSet { guard !suppressPersistence else { return }; defaults.set(useCustomBackground, forKey: Self.useCustomBackgroundKey) } }
    var backgroundOpacity: Double {
        get { _backgroundOpacity }
        set { _backgroundOpacity = min(max(newValue, 0.0), 1.0); if !suppressPersistence { defaults.set(_backgroundOpacity, forKey: Self.backgroundOpacityKey) } }
    }
    private var _backgroundOpacity: Double
    /// Feature #60 WI-12 (#795): bumped by `ReaderSettingsPanel` whenever
    /// the custom background image is replaced on disk. Readers that cache
    /// the image — `EPUBReaderContainerView`'s injected `data:` URL,
    /// `ThemeBackgroundView`'s `UIImage` — observe this and re-read the
    /// file when the bytes change but `theme` / `useCustomBackground` do
    /// not. Session-scoped invalidation signal; never persisted.
    var customBackgroundRevision: Int = 0
    /// When true, property mutations do NOT write to UserDefaults (bug #84 audit fix).
    /// Used by `applyResolvedSettings` to avoid leaking per-book overrides into global defaults.
    private var suppressPersistence = false
    private let defaults: UserDefaults
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.theme = Self.loadTheme(defaults)
        self.readingMode = Self.loadReadingMode(defaults)
        self.typography = Self.loadTypography(defaults)
        self.epubLayout = Self.loadEPUBLayout(defaults)
        self.pageTurnAnimation = Self.loadPageTurnAnimation(defaults)
        self.chineseConversion = Self.loadChineseConversion(defaults)
        self.autoPageTurn = defaults.bool(forKey: Self.autoPageTurnKey)
        // Bug #222: assign the backing store directly (mirrors `_backgroundOpacity`
        // below). `loadAutoPageTurnInterval` already clamps to 1...60, and
        // `autoPageTurnInterval` is now a computed property — assigning it here
        // would route through the clamping setter for no benefit.
        self._autoPageTurnInterval = Self.loadAutoPageTurnInterval(defaults)
        self.useCustomBackground = defaults.bool(forKey: Self.useCustomBackgroundKey)
        self._backgroundOpacity = Self.loadBackgroundOpacity(defaults)
    }

    // MARK: - Loaders (single source of truth for init + reconcile)

    /// Feature #60 WI-11: decodes the persisted theme via
    /// `ReaderThemeV2(legacyOrNew:)` so a `readerTheme` value written by
    /// a pre-WI-11 build (legacy `ReaderTheme` rawValue) still resolves
    /// — `light` → `.paper`, `sepia` / `dark` unchanged. A missing or
    /// unknown value falls back to `.default` (`.paper`).
    private static func loadTheme(_ defaults: UserDefaults) -> ReaderThemeV2 {
        ReaderThemeV2(legacyOrNew: defaults.string(forKey: themeKey))
    }
    private static func loadReadingMode(_ defaults: UserDefaults) -> ReadingMode {
        ReadingMode(rawValue: defaults.string(forKey: readingModeKey) ?? "") ?? .native
    }
    private static func loadTypography(_ defaults: UserDefaults) -> TypographySettings {
        if let data = defaults.data(forKey: typographyKey),
           let parsed = try? JSONDecoder().decode(TypographySettings.self, from: data) {
            return parsed
        }
        return TypographySettings()
    }
    private static func loadEPUBLayout(_ defaults: UserDefaults) -> EPUBLayoutPreference {
        EPUBLayoutPreference(rawValue: defaults.string(forKey: epubLayoutKey) ?? "") ?? .scroll
    }
    private static func loadPageTurnAnimation(_ defaults: UserDefaults) -> PageTurnAnimation {
        PageTurnAnimation(rawValue: defaults.string(forKey: pageTurnAnimationKey) ?? "") ?? .none
    }
    private static func loadChineseConversion(_ defaults: UserDefaults) -> ChineseConversionDirection {
        ChineseConversionDirection(rawValue: defaults.string(forKey: chineseConversionKey) ?? "") ?? .none
    }
    private static func loadAutoPageTurnInterval(_ defaults: UserDefaults) -> TimeInterval {
        let stored = defaults.double(forKey: autoPageTurnIntervalKey)
        return stored > 0 ? max(1.0, min(60.0, stored)) : 5.0
    }
    private static func loadBackgroundOpacity(_ defaults: UserDefaults) -> Double {
        min(max((defaults.object(forKey: backgroundOpacityKey) as? Double) ?? 0.15, 0.0), 1.0)
    }
    /// Bug #147: re-reads every key from UserDefaults and mirrors the
    /// values into this store. Used by `ReaderSettingsPanel` after
    /// disabling a per-book override — the override file is deleted but
    /// the live store still holds the per-book values until reopen.
    /// This method recomputes from the global defaults so the live
    /// reader reflects the new state immediately.
    /// Idempotent — when defaults already match, no writes happen.
    /// Suppresses persistence (defaults are the source of truth here;
    /// double-writing the same value is harmless but wasteful).
    func reconcileFromDefaults() {
        suppressPersistence = true
        defer { suppressPersistence = false }
        let newTheme = Self.loadTheme(defaults)
        if theme != newTheme { theme = newTheme }
        let newReadingMode = Self.loadReadingMode(defaults)
        if readingMode != newReadingMode { readingMode = newReadingMode }
        // Codex audit fix: load typography unconditionally (with default
        // fallback when defaults has no entry) — same shape as init.
        // The previous version only assigned when defaults had a
        // decodable value, leaving live per-book typography in place
        // for the common "global typography never customized" case.
        let newTypography = Self.loadTypography(defaults)
        if typography != newTypography { typography = newTypography }
        let newEPUBLayout = Self.loadEPUBLayout(defaults)
        if epubLayout != newEPUBLayout { epubLayout = newEPUBLayout }
        let newPageTurn = Self.loadPageTurnAnimation(defaults)
        if pageTurnAnimation != newPageTurn { pageTurnAnimation = newPageTurn }
        let newChinese = Self.loadChineseConversion(defaults)
        if chineseConversion != newChinese { chineseConversion = newChinese }
        let newAutoPage = defaults.bool(forKey: Self.autoPageTurnKey)
        if autoPageTurn != newAutoPage { autoPageTurn = newAutoPage }
        let newInterval = Self.loadAutoPageTurnInterval(defaults)
        if autoPageTurnInterval != newInterval { autoPageTurnInterval = newInterval }
        let newUseCustomBg = defaults.bool(forKey: Self.useCustomBackgroundKey)
        if useCustomBackground != newUseCustomBg { useCustomBackground = newUseCustomBg }
        let newOpacity = Self.loadBackgroundOpacity(defaults)
        if backgroundOpacity != newOpacity { backgroundOpacity = newOpacity }
    }

    /// Applies resolved per-book settings onto this store instance (bug #84).
    /// Suppresses UserDefaults persistence so per-book overrides don't leak into global defaults.
    func applyResolvedSettings(_ resolved: ResolvedSettings) {
        suppressPersistence = true
        defer { suppressPersistence = false }
        // Feature #60 WI-11: decode the per-book `themeName` via the
        // strict `ReaderThemeV2(recognized:)` so a legacy value
        // (`light` → `.paper`) still applies, while an unknown / corrupt
        // value leaves the live theme untouched (no silent reset).
        if let t = ReaderThemeV2(recognized: resolved.themeName), t != theme { theme = t }
        if let m = ReadingMode(rawValue: resolved.readingMode), m != readingMode { readingMode = m }
        if resolved.fontSize != typography.fontSize { typography.fontSize = resolved.fontSize }
        if resolved.lineSpacing != typography.lineSpacing { typography.lineSpacing = resolved.lineSpacing }
        if let f = ReaderFontFamily(rawValue: resolved.fontName), f != typography.fontFamily {
            typography.fontFamily = f
        }
    }

    #if canImport(UIKit)
    /// Resolved UIFont for the reader body. Per Feature #60 WI-1, the
    /// 5-case `ReaderFontFamily` is handled uniformly by
    /// `ReaderTypography.body(for:size:)` which encodes the fallback
    /// chain for cases whose binary isn't bundled (`.sourceSerif4`
    /// falls back to Georgia; `.inter` falls back to the system font).
    var uiFont: UIFont {
        ReaderTypography.body(for: typography.fontFamily, size: typography.fontSize)
    }
    // Feature #60 WI-5/WI-11: TXT/MD reader colors come straight from
    // `ReaderThemeV2`'s token surface. WI-11 migrated `theme` itself to
    // `ReaderThemeV2`, so these accessors read its 5-token surface
    // (`backgroundColor` / `inkColor` / `subColor`) directly — no
    // `asV2` projection needed.
    var uiBackgroundColor: UIColor { theme.backgroundColor }
    var uiTextColor: UIColor { theme.inkColor }
    var uiSecondaryTextColor: UIColor { theme.subColor }
    var lineSpacingPoints: CGFloat { typography.fontSize * (typography.lineSpacing - 1.0) }
    var cjkLetterSpacing: CGFloat { typography.cjkSpacing ? typography.fontSize * 0.05 : 0 }
    #endif
    #if canImport(UIKit)
    var mdRenderConfig: MDRenderConfig {
        // Feature #60 WI-5: thread the V2 token surface through the
        // Markdown renderer so blockquotes and code-block backgrounds
        // pick up per-theme colors instead of platform defaults.
        // Feature #68: accentColor / chapterHeadingColor thread the V2
        // accent + sub tokens through so the MD chapter-start drop-cap
        // and leading-heading restyle follow the active theme.
        MDRenderConfig(
            fontSize: typography.fontSize,
            lineSpacing: lineSpacingPoints,
            textColor: uiTextColor,
            secondaryColor: theme.subColor,
            codeBackgroundColor: theme.paperColor,
            accentColor: theme.accentColor,
            chapterHeadingColor: theme.subColor
        )
    }
    var txtViewConfig: TXTViewConfig {
        var c = TXTViewConfig(); c.fontSize = typography.fontSize; c.lineSpacing = lineSpacingPoints
        c.textColor = uiTextColor; c.backgroundColor = uiBackgroundColor; c.letterSpacing = cjkLetterSpacing
        // Feature #68: thread the V2 accent + sub tokens through so the
        // TXT chapter-start drop-cap (accent) and in-text heading restyle
        // (sub) follow the active theme.
        c.accentColor = theme.accentColor
        c.chapterHeadingColor = theme.subColor
        // Resolve the TXT bridge's `fontName` via `ReaderTypography` so the
        // 5-case ReaderFontFamily (Feature #60 WI-1) is handled uniformly.
        // `.system` → nil (TextKit picks the system font); everything else
        // → the registry's resolved face. WI-5 will plumb the registry
        // through the TXT bridge directly so the body face flows through
        // instead of round-tripping through fontName-string.
        switch typography.fontFamily {
        case .system:
            c.fontName = nil
        case .serif, .monospace, .sourceSerif4, .inter:
            c.fontName = ReaderTypography.body(
                for: typography.fontFamily, size: typography.fontSize
            ).fontName
        }
        return c
    }
    #endif
}
