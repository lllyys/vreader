import Testing
import Foundation

@testable import vreader

// MARK: - Mock Persistence

final class MockUserDefaults: UserDefaultsProtocol {
    var storage: [String: Any] = [:]

    func value(forKey key: String) -> Any? {
        storage[key]
    }

    func set(_ value: Any?, forKey key: String) {
        storage[key] = value
    }
}

// MARK: - ThemeService Tests

@Suite("ThemeService")
struct ThemeServiceTests {

    // MARK: - Default Values

    @Test("provides sensible defaults on first launch")
    func defaultValues() {
        let defaults = MockUserDefaults()
        let service = ThemeService(defaults: defaults)

        #expect(service.currentTheme == .light)
        #expect(service.fontSize >= 12)
        #expect(service.fontSize <= 32)
        #expect(service.fontFamily == .system)
        #expect(service.lineSpacing >= 1.0)
        #expect(service.lineSpacing <= 2.0)
        #expect(service.margin == .normal)
    }

    @Test("default font size is 18")
    func defaultFontSize() {
        let service = ThemeService(defaults: MockUserDefaults())

        #expect(service.fontSize == 18)
    }

    @Test("default line spacing is 1.5")
    func defaultLineSpacing() {
        let service = ThemeService(defaults: MockUserDefaults())

        #expect(service.lineSpacing == 1.5)
    }

    // MARK: - Theme Selection

    @Test(
        "supports all theme options",
        arguments: [
            ReaderTheme.light,
            ReaderTheme.dark,
            ReaderTheme.sepia,
            ReaderTheme.oledBlack,
        ]
    )
    func allThemes(theme: ReaderTheme) {
        let service = ThemeService(defaults: MockUserDefaults())
        service.setTheme(theme)

        #expect(service.currentTheme == theme)
    }

    @Test("OLED black theme uses pure black background")
    func oledBlackBackground() {
        let service = ThemeService(defaults: MockUserDefaults())
        service.setTheme(.oledBlack)

        let bg = service.backgroundColor
        #expect(bg.red == 0.0)
        #expect(bg.green == 0.0)
        #expect(bg.blue == 0.0)
    }

    // MARK: - Persistence

    @Test("persists theme selection")
    func persistTheme() {
        let defaults = MockUserDefaults()
        let service1 = ThemeService(defaults: defaults)
        service1.setTheme(.sepia)

        let service2 = ThemeService(defaults: defaults)
        #expect(service2.currentTheme == .sepia)
    }

    @Test("persists font size")
    func persistFontSize() {
        let defaults = MockUserDefaults()
        let service1 = ThemeService(defaults: defaults)
        service1.setFontSize(24)

        let service2 = ThemeService(defaults: defaults)
        #expect(service2.fontSize == 24)
    }

    @Test("persists font family")
    func persistFontFamily() {
        let defaults = MockUserDefaults()
        let service1 = ThemeService(defaults: defaults)
        service1.setFontFamily(.serif)

        let service2 = ThemeService(defaults: defaults)
        #expect(service2.fontFamily == .serif)
    }

    @Test("persists line spacing")
    func persistLineSpacing() {
        let defaults = MockUserDefaults()
        let service1 = ThemeService(defaults: defaults)
        service1.setLineSpacing(1.8)

        let service2 = ThemeService(defaults: defaults)
        #expect(abs(service2.lineSpacing - 1.8) < 0.01)
    }

    // MARK: - Font Size Bounds

    @Test("font size clamps to minimum 12")
    func fontSizeMinimum() {
        let service = ThemeService(defaults: MockUserDefaults())
        service.setFontSize(8)

        #expect(service.fontSize == 12)
    }

    @Test("font size clamps to maximum 32")
    func fontSizeMaximum() {
        let service = ThemeService(defaults: MockUserDefaults())
        service.setFontSize(48)

        #expect(service.fontSize == 32)
    }

    @Test("font size accepts values within range")
    func fontSizeWithinRange() {
        let service = ThemeService(defaults: MockUserDefaults())
        service.setFontSize(20)

        #expect(service.fontSize == 20)
    }

    @Test(
        "font size boundary values",
        arguments: [
            (12, 12), // exact minimum
            (32, 32), // exact maximum
            (11, 12), // below minimum
            (33, 32), // above maximum
            (0, 12),  // zero
            (-5, 12), // negative
        ]
    )
    func fontSizeBoundaries(input: Int, expected: Int) {
        let service = ThemeService(defaults: MockUserDefaults())
        service.setFontSize(input)

        #expect(service.fontSize == expected)
    }

    // MARK: - Line Spacing Bounds

    @Test("line spacing clamps to minimum 1.0")
    func lineSpacingMinimum() {
        let service = ThemeService(defaults: MockUserDefaults())
        service.setLineSpacing(0.5)

        #expect(service.lineSpacing == 1.0)
    }

    @Test("line spacing clamps to maximum 2.0")
    func lineSpacingMaximum() {
        let service = ThemeService(defaults: MockUserDefaults())
        service.setLineSpacing(3.0)

        #expect(service.lineSpacing == 2.0)
    }

    // MARK: - Contrast Validation

    @Test("light theme maintains WCAG AA contrast ratio")
    func lightThemeContrast() {
        let service = ThemeService(defaults: MockUserDefaults())
        service.setTheme(.light)

        let ratio = service.contrastRatio
        #expect(ratio >= 4.5) // WCAG AA minimum
    }

    @Test("dark theme maintains WCAG AA contrast ratio")
    func darkThemeContrast() {
        let service = ThemeService(defaults: MockUserDefaults())
        service.setTheme(.dark)

        let ratio = service.contrastRatio
        #expect(ratio >= 4.5)
    }

    @Test("sepia theme maintains WCAG AA contrast ratio")
    func sepiaThemeContrast() {
        let service = ThemeService(defaults: MockUserDefaults())
        service.setTheme(.sepia)

        let ratio = service.contrastRatio
        #expect(ratio >= 4.5)
    }

    @Test("OLED black theme maintains WCAG AA contrast ratio")
    func oledThemeContrast() {
        let service = ThemeService(defaults: MockUserDefaults())
        service.setTheme(.oledBlack)

        let ratio = service.contrastRatio
        #expect(ratio >= 4.5)
    }

    // MARK: - Font Family

    @Test(
        "supports all font families",
        arguments: [
            FontFamily.system,
            FontFamily.serif,
            FontFamily.sansSerif,
        ]
    )
    func allFontFamilies(family: FontFamily) {
        let service = ThemeService(defaults: MockUserDefaults())
        service.setFontFamily(family)

        #expect(service.fontFamily == family)
    }

    // MARK: - Margin

    @Test(
        "supports all margin options",
        arguments: [
            MarginSize.narrow,
            MarginSize.normal,
            MarginSize.wide,
        ]
    )
    func allMargins(margin: MarginSize) {
        let service = ThemeService(defaults: MockUserDefaults())
        service.setMargin(margin)

        #expect(service.margin == margin)
    }

    // MARK: - CSS Generation

    @Test("generates valid CSS string for Readium injection")
    func cssGeneration() {
        let service = ThemeService(defaults: MockUserDefaults())
        service.setFontSize(20)
        service.setLineSpacing(1.6)
        service.setFontFamily(.serif)

        let css = service.readerCSS

        #expect(css.contains("font-size"))
        #expect(css.contains("20"))
        #expect(css.contains("line-height"))
        #expect(!css.isEmpty)
    }

    // MARK: - Edge Cases

    @Test("handles corrupted persisted data gracefully")
    func corruptedDefaults() {
        let defaults = MockUserDefaults()
        defaults.storage["theme"] = "nonexistent_theme"
        defaults.storage["fontSize"] = "not_a_number"

        let service = ThemeService(defaults: defaults)

        // Should fall back to defaults, not crash
        #expect(service.currentTheme == .light)
        #expect(service.fontSize == 18)
    }
}
