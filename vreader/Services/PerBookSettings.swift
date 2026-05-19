// Purpose: Per-book reading settings override model and storage.
// Allows users to customize font size, theme, etc. for individual books
// while falling back to global settings for unset fields.
//
// Key decisions:
// - All override fields are Optional — nil means "inherit from global".
// - Stored as JSON files keyed by fingerprint at <baseURL>/<sanitizedKey>.json.
// - Pure value type + enum namespace for store functions — no singletons.
// - resolve() merges per-book overrides onto global ReaderSettingsStore values.
// - File-based storage keeps per-book settings isolated from UserDefaults.
//
// @coordinates-with: ReaderSettingsStore.swift, ReaderTheme.swift,
//   TypographySettings.swift, ReaderContainerView.swift

import Foundation

// MARK: - Override Model

/// Optional per-book overrides. nil fields inherit from global settings.
///
/// `Codable`'s synthesized `init(from:)` ignores unknown JSON keys, so an
/// older per-book file that still carries a `readingMode` key (feature #54
/// retired it) decodes harmlessly into this trimmed struct.
struct PerBookSettingsOverride: Codable, Sendable, Equatable {
    var fontSize: CGFloat?
    var fontName: String?
    var lineSpacing: CGFloat?
    var letterSpacing: CGFloat?
    var themeName: String?

    init(
        fontSize: CGFloat? = nil,
        fontName: String? = nil,
        lineSpacing: CGFloat? = nil,
        letterSpacing: CGFloat? = nil,
        themeName: String? = nil
    ) {
        self.fontSize = fontSize
        self.fontName = fontName
        self.lineSpacing = lineSpacing
        self.letterSpacing = letterSpacing
        self.themeName = themeName
    }
}

// MARK: - Resolved Settings

/// Fully resolved settings — every field has a concrete value.
struct ResolvedSettings: Sendable, Equatable {
    let fontSize: CGFloat
    let fontName: String
    let lineSpacing: CGFloat
    let letterSpacing: CGFloat
    let themeName: String
}

// MARK: - Store

/// Namespace for per-book settings persistence and resolution.
enum PerBookSettingsStore {

    // MARK: - Read

    /// Returns the per-book override for the given fingerprint key, or nil if none saved.
    static func settings(for fingerprintKey: String, baseURL: URL) -> PerBookSettingsOverride? {
        let fileURL = fileURL(for: fingerprintKey, baseURL: baseURL)
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        return try? JSONDecoder().decode(PerBookSettingsOverride.self, from: data)
    }

    // MARK: - Write

    /// Saves a per-book override. Creates the storage directory if needed.
    static func save(_ settings: PerBookSettingsOverride, for fingerprintKey: String, baseURL: URL) throws {
        try FileManager.default.createDirectory(at: baseURL, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(settings)
        try data.write(to: fileURL(for: fingerprintKey, baseURL: baseURL), options: .atomic)
    }

    // MARK: - Delete

    /// Removes the per-book override for the given fingerprint key.
    static func delete(for fingerprintKey: String, baseURL: URL) {
        let fileURL = fileURL(for: fingerprintKey, baseURL: baseURL)
        try? FileManager.default.removeItem(at: fileURL)
    }

    // MARK: - Resolution

    /// Merges per-book overrides onto global settings. nil fields fall back to global values.
    @MainActor
    static func resolve(perBook: PerBookSettingsOverride?, global: ReaderSettingsStore) -> ResolvedSettings {
        let globalFontName: String = global.typography.fontFamily.rawValue
        let globalLetterSpacing: CGFloat = global.typography.cjkSpacing
            ? global.typography.fontSize * 0.05
            : 0

        guard let perBook else {
            return ResolvedSettings(
                fontSize: global.typography.fontSize,
                fontName: globalFontName,
                lineSpacing: global.typography.lineSpacing,
                letterSpacing: globalLetterSpacing,
                themeName: global.theme.rawValue
            )
        }

        return ResolvedSettings(
            fontSize: perBook.fontSize ?? global.typography.fontSize,
            fontName: perBook.fontName ?? globalFontName,
            lineSpacing: perBook.lineSpacing ?? global.typography.lineSpacing,
            letterSpacing: perBook.letterSpacing ?? globalLetterSpacing,
            themeName: perBook.themeName ?? global.theme.rawValue
        )
    }

    // MARK: - Private

    /// Derives a safe filename from a fingerprint key by replacing colons with underscores.
    private static func fileURL(for fingerprintKey: String, baseURL: URL) -> URL {
        let safeName = fingerprintKey.replacingOccurrences(of: ":", with: "_")
        let fileName = safeName.isEmpty ? "_empty_key" : safeName
        return baseURL.appendingPathComponent("\(fileName).json")
    }
}
