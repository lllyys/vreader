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
    var theme: ReaderTheme { didSet { guard !suppressPersistence else { return }; defaults.set(theme.rawValue, forKey: Self.themeKey) } }
    var readingMode: ReadingMode { didSet { guard !suppressPersistence else { return }; defaults.set(readingMode.rawValue, forKey: Self.readingModeKey) } }
    var epubLayout: EPUBLayoutPreference { didSet { guard !suppressPersistence else { return }; defaults.set(epubLayout.rawValue, forKey: Self.epubLayoutKey) } }
    /// Whether auto page turning is enabled (Issue 9).
    var autoPageTurn: Bool { didSet { guard !suppressPersistence else { return }; defaults.set(autoPageTurn, forKey: Self.autoPageTurnKey) } }
    /// Page turn animation style (B11).
    var pageTurnAnimation: PageTurnAnimation {
        didSet { guard !suppressPersistence else { return }; defaults.set(pageTurnAnimation.rawValue, forKey: Self.pageTurnAnimationKey) }
    }
    /// Interval in seconds between auto page turns (Issue 9). Clamped to 1...60.
    var autoPageTurnInterval: TimeInterval {
        didSet {
            autoPageTurnInterval = max(1.0, min(60.0, autoPageTurnInterval))
            guard !suppressPersistence else { return }
            defaults.set(autoPageTurnInterval, forKey: Self.autoPageTurnIntervalKey)
        }
    }
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
        self.autoPageTurnInterval = Self.loadAutoPageTurnInterval(defaults)
        self.useCustomBackground = defaults.bool(forKey: Self.useCustomBackgroundKey)
        self._backgroundOpacity = Self.loadBackgroundOpacity(defaults)
    }

    // MARK: - Loaders (single source of truth for init + reconcile)

    private static func loadTheme(_ defaults: UserDefaults) -> ReaderTheme {
        ReaderTheme(rawValue: defaults.string(forKey: themeKey) ?? "") ?? .default
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
        if let t = ReaderTheme(rawValue: resolved.themeName), t != theme { theme = t }
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
    // Feature #60 WI-5: route TXT/MD reader colors through
    // `ReaderThemeV2`'s token surface. `theme.asV2` projects the
    // legacy 3-case enum (.light → .paper, .sepia → .sepia, .dark →
    // .dark) so existing persisted settings keep working; the
    // 5-token surface (`backgroundColor` / `inkColor` / `subColor`)
    // replaces the legacy 3-color palette so TXT and MD pick up
    // the new visual identity. EPUB went through the same
    // projection in WI-4.
    var uiBackgroundColor: UIColor { theme.asV2.backgroundColor }
    var uiTextColor: UIColor { theme.asV2.inkColor }
    var uiSecondaryTextColor: UIColor { theme.asV2.subColor }
    var lineSpacingPoints: CGFloat { typography.fontSize * (typography.lineSpacing - 1.0) }
    var cjkLetterSpacing: CGFloat { typography.cjkSpacing ? typography.fontSize * 0.05 : 0 }
    #endif
    #if canImport(UIKit)
    var mdRenderConfig: MDRenderConfig {
        // Feature #60 WI-5: thread the V2 token surface through the
        // Markdown renderer so blockquotes and code-block backgrounds
        // pick up per-theme colors instead of platform defaults.
        let v2 = theme.asV2
        return MDRenderConfig(
            fontSize: typography.fontSize,
            lineSpacing: lineSpacingPoints,
            textColor: uiTextColor,
            secondaryColor: v2.subColor,
            codeBackgroundColor: v2.paperColor
        )
    }
    var txtViewConfig: TXTViewConfig {
        var c = TXTViewConfig(); c.fontSize = typography.fontSize; c.lineSpacing = lineSpacingPoints
        c.textColor = uiTextColor; c.backgroundColor = uiBackgroundColor; c.letterSpacing = cjkLetterSpacing
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
