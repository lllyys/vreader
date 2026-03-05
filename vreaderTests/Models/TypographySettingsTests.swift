// Purpose: Tests for TypographySettings — defaults, clamping, Codable, CJK flag.

import Testing
import Foundation
@testable import vreader

@Suite("TypographySettings")
struct TypographySettingsTests {

    // MARK: - Defaults

    @Test func defaultFontSize() {
        let settings = TypographySettings()
        #expect(settings.fontSize == 18)
    }

    @Test func defaultLineSpacing() {
        let settings = TypographySettings()
        #expect(settings.lineSpacing == 1.4)
    }

    @Test func defaultFontFamily() {
        let settings = TypographySettings()
        #expect(settings.fontFamily == .system)
    }

    @Test func defaultCJKSpacingOff() {
        let settings = TypographySettings()
        #expect(settings.cjkSpacing == false)
    }

    // MARK: - Font Size Clamping

    @Test func fontSizeClampedToMinimum() {
        var settings = TypographySettings()
        settings.fontSize = 8
        #expect(settings.fontSize == TypographySettings.fontSizeRange.lowerBound)
    }

    @Test func fontSizeClampedToMaximum() {
        var settings = TypographySettings()
        settings.fontSize = 40
        #expect(settings.fontSize == TypographySettings.fontSizeRange.upperBound)
    }

    @Test func fontSizeAtMinBoundary() {
        var settings = TypographySettings()
        settings.fontSize = 12
        #expect(settings.fontSize == 12)
    }

    @Test func fontSizeAtMaxBoundary() {
        var settings = TypographySettings()
        settings.fontSize = 32
        #expect(settings.fontSize == 32)
    }

    @Test func fontSizeNegativeClamps() {
        var settings = TypographySettings()
        settings.fontSize = -5
        #expect(settings.fontSize == TypographySettings.fontSizeRange.lowerBound)
    }

    // MARK: - Line Spacing Clamping

    @Test func lineSpacingClampedToMinimum() {
        var settings = TypographySettings()
        settings.lineSpacing = 0.5
        #expect(settings.lineSpacing == TypographySettings.lineSpacingRange.lowerBound)
    }

    @Test func lineSpacingClampedToMaximum() {
        var settings = TypographySettings()
        settings.lineSpacing = 3.0
        #expect(settings.lineSpacing == TypographySettings.lineSpacingRange.upperBound)
    }

    @Test func lineSpacingAtMinBoundary() {
        var settings = TypographySettings()
        settings.lineSpacing = 1.0
        #expect(settings.lineSpacing == 1.0)
    }

    @Test func lineSpacingAtMaxBoundary() {
        var settings = TypographySettings()
        settings.lineSpacing = 2.0
        #expect(settings.lineSpacing == 2.0)
    }

    // MARK: - Font Family

    @Test func fontFamilyAllCases() {
        #expect(ReaderFontFamily.allCases.count == 3)
        #expect(ReaderFontFamily.allCases.contains(.system))
        #expect(ReaderFontFamily.allCases.contains(.serif))
        #expect(ReaderFontFamily.allCases.contains(.monospace))
    }

    @Test func fontFamilyCodableRoundTrip() throws {
        for family in ReaderFontFamily.allCases {
            let data = try JSONEncoder().encode(family)
            let decoded = try JSONDecoder().decode(ReaderFontFamily.self, from: data)
            #expect(decoded == family)
        }
    }

    @Test func fontFamilyInvalidRawValue() {
        #expect(ReaderFontFamily(rawValue: "comic-sans") == nil)
        #expect(ReaderFontFamily(rawValue: "") == nil)
    }

    // MARK: - CJK Spacing

    @Test func cjkSpacingToggle() {
        var settings = TypographySettings()
        #expect(settings.cjkSpacing == false)
        settings.cjkSpacing = true
        #expect(settings.cjkSpacing == true)
    }

    // MARK: - Codable Round-Trip

    @Test func codableRoundTrip() throws {
        var settings = TypographySettings()
        settings.fontSize = 24
        settings.lineSpacing = 1.8
        settings.fontFamily = .serif
        settings.cjkSpacing = true

        let data = try JSONEncoder().encode(settings)
        let decoded = try JSONDecoder().decode(TypographySettings.self, from: data)

        #expect(decoded.fontSize == 24)
        #expect(decoded.lineSpacing == 1.8)
        #expect(decoded.fontFamily == .serif)
        #expect(decoded.cjkSpacing == true)
    }

    @Test func codableRoundTripDefaults() throws {
        let settings = TypographySettings()
        let data = try JSONEncoder().encode(settings)
        let decoded = try JSONDecoder().decode(TypographySettings.self, from: data)

        #expect(decoded.fontSize == 18)
        #expect(decoded.lineSpacing == 1.4)
        #expect(decoded.fontFamily == .system)
        #expect(decoded.cjkSpacing == false)
    }

    // MARK: - Edge Cases

    @Test func fontSizeZeroClamps() {
        var settings = TypographySettings()
        settings.fontSize = 0
        #expect(settings.fontSize == TypographySettings.fontSizeRange.lowerBound)
    }

    @Test func lineSpacingZeroClamps() {
        var settings = TypographySettings()
        settings.lineSpacing = 0
        #expect(settings.lineSpacing == TypographySettings.lineSpacingRange.lowerBound)
    }

    // MARK: - Backward Compatibility Decode

    @Test func decodeMissingCJKSpacingDefaultsToFalse() throws {
        let json = #"{"fontSize":20,"lineSpacing":1.5,"fontFamily":"serif"}"#
        let data = Data(json.utf8)
        let decoded = try JSONDecoder().decode(TypographySettings.self, from: data)
        #expect(decoded.cjkSpacing == false)
        #expect(decoded.fontSize == 20)
        #expect(decoded.fontFamily == .serif)
    }

    @Test func decodeUnknownFontFamilyFallsBackToSystem() throws {
        let json = #"{"fontSize":18,"lineSpacing":1.4,"fontFamily":"comic-sans","cjkSpacing":false}"#
        let data = Data(json.utf8)
        let decoded = try JSONDecoder().decode(TypographySettings.self, from: data)
        #expect(decoded.fontFamily == .system)
    }

    @Test func decodePartialPayloadUsesDefaults() throws {
        let json = #"{"fontSize":22}"#
        let data = Data(json.utf8)
        let decoded = try JSONDecoder().decode(TypographySettings.self, from: data)
        #expect(decoded.fontSize == 22)
        #expect(decoded.lineSpacing == 1.4)
        #expect(decoded.fontFamily == .system)
        #expect(decoded.cjkSpacing == false)
    }

    @Test func decodeEmptyObjectUsesDefaults() throws {
        let json = #"{}"#
        let data = Data(json.utf8)
        let decoded = try JSONDecoder().decode(TypographySettings.self, from: data)
        #expect(decoded.fontSize == 18)
        #expect(decoded.lineSpacing == 1.4)
        #expect(decoded.fontFamily == .system)
        #expect(decoded.cjkSpacing == false)
    }
}
