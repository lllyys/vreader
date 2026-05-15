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
        // Bug #166 (partial fix): raised upper bound 32 → 64.
        // Use a value safely above the new bound so the clamp still fires.
        var settings = TypographySettings()
        settings.fontSize = 100
        #expect(settings.fontSize == TypographySettings.fontSizeRange.upperBound)
    }

    @Test func fontSizeAtMinBoundary() {
        var settings = TypographySettings()
        settings.fontSize = 12
        #expect(settings.fontSize == 12)
    }

    @Test func fontSizeAtMaxBoundary() {
        // Bug #166 (partial fix): max raised 32 → 64.
        var settings = TypographySettings()
        settings.fontSize = 64
        #expect(settings.fontSize == 64)
    }

    // MARK: - Bug #166 (partial fix) — slider ceiling raised 32 → 64

    /// Bug #166 (Slider-max sub-piece): user reports max 32pt is too small
    /// for EPUB because CSS font-size injection compounds with the book's
    /// own stylesheet base sizes. Raise the upper bound to 64pt so users
    /// can dial in a comfortable size on EPUB without app-side
    /// per-renderer perceptual calibration (the cross-format-consistency
    /// half of the bug, which remains feature-class scope, is NOT
    /// addressed by this partial fix).
    @Test func fontSizeRangeUpperBoundIs64() {
        #expect(TypographySettings.fontSizeRange.upperBound == 64, "Bug #166 partial fix: max font size raised from 32 to 64; if this regresses, accessibility users on EPUB will run out of headroom again.")
    }

    @Test func fontSizeRangeLowerBoundUnchangedAt12() {
        // Defensive: the lower bound stays at 12pt — the bug body only
        // calls out the upper bound being too small. A regression that
        // also lifted the floor would be a separate accessibility concern.
        #expect(TypographySettings.fontSizeRange.lowerBound == 12)
    }

    @Test func fontSizeAt48ptStaysExact() {
        // Mid-range value that would have been clamped pre-fix (to 32);
        // post-fix it must pass through unchanged. Pins the actual
        // user-visible improvement.
        var settings = TypographySettings()
        settings.fontSize = 48
        #expect(settings.fontSize == 48)
    }

    @Test func fontSizeAt64ptStaysExactNotClamped() {
        // Boundary check: exactly the new upper bound passes through.
        var settings = TypographySettings()
        settings.fontSize = 64
        #expect(settings.fontSize == 64)
    }

    @Test func fontSizeAt65ptClampsDownTo64() {
        // One above the boundary clamps to the bound (not to the old 32).
        var settings = TypographySettings()
        settings.fontSize = 65
        #expect(settings.fontSize == 64)
    }

    @Test func decodedFontSizeAbove64ClampsToBound() {
        // Persistence path: a settings JSON that somehow carries
        // fontSize > 64 (older debug build, manual edit, etc.) must
        // clamp on decode — not crash, not pass through.
        struct Wrapper: Codable { let typography: TypographySettings }
        let json = """
        {"typography": {"fontSize": 200, "lineSpacing": 1.4, "fontFamily": "system", "cjkSpacing": false}}
        """.data(using: .utf8)!
        let decoded = try? JSONDecoder().decode(Wrapper.self, from: json)
        #expect(decoded != nil, "Decode must not throw")
        #expect(decoded?.typography.fontSize == 64)
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

    /// Per Feature #60 WI-1: `ReaderFontFamily` extended additively from
    /// 3 to 5 cases. Historical `.system` / `.serif` / `.monospace` kept
    /// for per-book-persistence compat; added `.sourceSerif4` and
    /// `.inter` as the visual-identity-v2 body + chrome faces.
    @Test func fontFamilyAllCases() {
        #expect(ReaderFontFamily.allCases.count == 5)
        #expect(ReaderFontFamily.allCases.contains(.system))
        #expect(ReaderFontFamily.allCases.contains(.serif))
        #expect(ReaderFontFamily.allCases.contains(.monospace))
        #expect(ReaderFontFamily.allCases.contains(.sourceSerif4))
        #expect(ReaderFontFamily.allCases.contains(.inter))
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
