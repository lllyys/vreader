// Purpose: Observable store for reader theme and typography settings.
// Persists via @AppStorage and provides computed UIKit values for bridges.
//
// Key decisions:
// - @Observable for SwiftUI reactivity.
// - @AppStorage for persistence across app launches.
// - Computed UIFont, UIColor, etc. derived from current settings.
// - Provides bridge-specific config objects (MDRenderConfig, TXTViewConfig).
// - CJK letter spacing is 0.05em equivalent when enabled.
// - Line spacing stored as multiplier; converted to absolute points for UIKit.
//
// @coordinates-with: ReaderTheme.swift, TypographySettings.swift, MDTypes.swift,
//   TXTTextViewBridge.swift

import Foundation
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// Observable store for reader appearance settings.
/// Wraps UserDefaults for persistence and provides computed UIKit values.
@Observable
@MainActor
final class ReaderSettingsStore {

    // MARK: - Storage Keys

    static let themeKey = "readerTheme"
    static let typographyKey = "readerTypography"

    // MARK: - Persisted State

    /// Current color theme.
    var theme: ReaderTheme {
        didSet {
            defaults.set(theme.rawValue, forKey: Self.themeKey)
        }
    }

    /// Typography settings (font size, line spacing, font family, CJK spacing).
    var typography: TypographySettings {
        didSet {
            do {
                let data = try JSONEncoder().encode(typography)
                defaults.set(data, forKey: Self.typographyKey)
            } catch {
                assertionFailure("Failed to encode TypographySettings: \(error)")
            }
        }
    }

    // MARK: - Private

    private let defaults: UserDefaults

    // MARK: - Init

    /// Creates a store backed by the given UserDefaults.
    /// - Parameter defaults: UserDefaults instance. Use a custom suite for testing.
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        // Restore theme
        self.theme = ReaderTheme(rawValue: defaults.string(forKey: Self.themeKey) ?? "")
            ?? .default

        // Restore typography
        if let data = defaults.data(forKey: Self.typographyKey),
           let decoded = try? JSONDecoder().decode(TypographySettings.self, from: data) {
            self.typography = decoded
        } else {
            self.typography = TypographySettings()
        }
    }

    // MARK: - Computed UIKit Values

    #if canImport(UIKit)
    /// UIFont for current font family and size.
    var uiFont: UIFont {
        let size = typography.fontSize
        switch typography.fontFamily {
        case .system:
            return .systemFont(ofSize: size)
        case .serif:
            // Georgia is the most reliable serif on iOS
            return UIFont(name: "Georgia", size: size) ?? .systemFont(ofSize: size)
        case .monospace:
            return .monospacedSystemFont(ofSize: size, weight: .regular)
        }
    }

    /// Background color from current theme.
    var uiBackgroundColor: UIColor {
        theme.backgroundColor
    }

    /// Primary text color from current theme.
    var uiTextColor: UIColor {
        theme.textColor
    }

    /// Secondary text color from current theme.
    var uiSecondaryTextColor: UIColor {
        theme.secondaryTextColor
    }

    /// Absolute line spacing in points (fontSize * (multiplier - 1.0)).
    var lineSpacingPoints: CGFloat {
        typography.fontSize * (typography.lineSpacing - 1.0)
    }

    /// CJK inter-character spacing. 0 when disabled, ~0.05em equivalent when enabled.
    var cjkLetterSpacing: CGFloat {
        typography.cjkSpacing ? typography.fontSize * 0.05 : 0
    }
    #endif

    // MARK: - Bridge Configs

    #if canImport(UIKit)
    /// MDRenderConfig bridged from current settings.
    var mdRenderConfig: MDRenderConfig {
        MDRenderConfig(
            fontSize: typography.fontSize,
            lineSpacing: lineSpacingPoints,
            textColor: uiTextColor
        )
    }

    /// TXTViewConfig bridged from current settings.
    var txtViewConfig: TXTViewConfig {
        var config = TXTViewConfig()
        config.fontSize = typography.fontSize
        config.lineSpacing = lineSpacingPoints
        config.textColor = uiTextColor
        config.backgroundColor = uiBackgroundColor
        config.letterSpacing = cjkLetterSpacing
        switch typography.fontFamily {
        case .system:
            config.fontName = nil
        case .serif:
            config.fontName = "Georgia"
        case .monospace:
            config.fontName = UIFont.monospacedSystemFont(ofSize: 12, weight: .regular).fontName
        }
        return config
    }
    #endif
}
