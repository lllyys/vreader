// Purpose: Typography settings model with font size, line spacing, font family, CJK spacing.
// Provides clamped setters to enforce valid ranges and Codable for @AppStorage persistence.
//
// Key decisions:
// - Font size range 12...32 (readable on phone to tablet).
// - Line spacing multiplier 1.0...2.0 (tight to very loose).
// - Font family uses system fonts only (no custom font files).
// - CJK spacing flag adds inter-character spacing for CJK text.
// - Stored properties use private backing with clamped public setters.
//
// @coordinates-with: ReaderTheme.swift, ReaderSettingsStore.swift

import Foundation

/// Font family options for the reader.
enum ReaderFontFamily: String, Codable, CaseIterable, Sendable {
    case system
    case serif
    case monospace
}

/// Typography settings for reader display.
struct TypographySettings: Codable, Sendable, Equatable {

    // MARK: - Valid Ranges

    /// Allowed font size range (points).
    static let fontSizeRange: ClosedRange<CGFloat> = 12...32

    /// Allowed line spacing multiplier range.
    static let lineSpacingRange: ClosedRange<CGFloat> = 1.0...2.0

    // MARK: - Properties

    /// Font size in points. Clamped to `fontSizeRange`.
    var fontSize: CGFloat {
        get { _fontSize }
        set { _fontSize = Self.clamp(newValue, to: Self.fontSizeRange) }
    }

    /// Line spacing multiplier. Clamped to `lineSpacingRange`.
    var lineSpacing: CGFloat {
        get { _lineSpacing }
        set { _lineSpacing = Self.clamp(newValue, to: Self.lineSpacingRange) }
    }

    /// Selected font family.
    var fontFamily: ReaderFontFamily

    /// Whether to apply CJK inter-character spacing.
    var cjkSpacing: Bool

    // MARK: - Private Backing

    private var _fontSize: CGFloat
    private var _lineSpacing: CGFloat

    // MARK: - Init

    init(
        fontSize: CGFloat = 18,
        lineSpacing: CGFloat = 1.4,
        fontFamily: ReaderFontFamily = .system,
        cjkSpacing: Bool = false
    ) {
        self._fontSize = Self.clamp(fontSize, to: Self.fontSizeRange)
        self._lineSpacing = Self.clamp(lineSpacing, to: Self.lineSpacingRange)
        self.fontFamily = fontFamily
        self.cjkSpacing = cjkSpacing
    }

    // MARK: - Codable

    enum CodingKeys: String, CodingKey {
        case fontSize
        case lineSpacing
        case fontFamily
        case cjkSpacing
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let rawFontSize = (try? container.decodeIfPresent(CGFloat.self, forKey: .fontSize)) ?? 18
        let rawLineSpacing = (try? container.decodeIfPresent(CGFloat.self, forKey: .lineSpacing)) ?? 1.4
        self._fontSize = Self.clamp(rawFontSize, to: Self.fontSizeRange)
        self._lineSpacing = Self.clamp(rawLineSpacing, to: Self.lineSpacingRange)
        // Decode fontFamily with fallback to .system for unknown raw values
        if let rawFamily = try? container.decodeIfPresent(String.self, forKey: .fontFamily),
           let family = ReaderFontFamily(rawValue: rawFamily) {
            self.fontFamily = family
        } else {
            self.fontFamily = .system
        }
        self.cjkSpacing = (try? container.decodeIfPresent(Bool.self, forKey: .cjkSpacing)) ?? false
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(_fontSize, forKey: .fontSize)
        try container.encode(_lineSpacing, forKey: .lineSpacing)
        try container.encode(fontFamily, forKey: .fontFamily)
        try container.encode(cjkSpacing, forKey: .cjkSpacing)
    }

    // MARK: - Equatable

    static func == (lhs: TypographySettings, rhs: TypographySettings) -> Bool {
        lhs._fontSize == rhs._fontSize
            && lhs._lineSpacing == rhs._lineSpacing
            && lhs.fontFamily == rhs.fontFamily
            && lhs.cjkSpacing == rhs.cjkSpacing
    }

    // MARK: - Private

    private static func clamp(_ value: CGFloat, to range: ClosedRange<CGFloat>) -> CGFloat {
        min(max(value, range.lowerBound), range.upperBound)
    }
}
