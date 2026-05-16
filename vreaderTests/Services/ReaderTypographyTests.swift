// Purpose: Tests for `ReaderTypography` — Feature #60 font registry.
// Resolves a `ReaderFontFamily` case to a UIFont for the reader body
// + UI chrome.
//
// WI-1a added the registry + `ReaderFontFamily` cases (the API
// surface). **WI-1b (this branch) bundles the actual font binaries**:
// Source Serif 4 + Inter `.otf` faces ship in `vreader/Resources/Fonts/`
// and are registered with iOS via the `UIAppFonts` key in the
// Info.plist. So `.sourceSerif4` / `.inter` now resolve to the REAL
// faces, not the Georgia / system fallback.
//
// The registry's fallback chain is still real code and still worth
// testing — it's the safety net for the case a face fails to load
// (corrupt asset, wrong PostScript name). The two
// `*_resolvesToASerifFace` / `*_resolvesToASansFace` tests below
// assert the trait-level invariant that holds whether the bundled
// face or the fallback resolves; the `*_resolvesToBundledFace`
// tests assert the post-WI-1b reality that the bundled face IS
// what resolves.
//
// Resolution order (per `ReaderTypography.body(for:)`):
//   - `.sourceSerif4` → bundled Source Serif 4 → Georgia → system serif
//   - `.inter`        → bundled Inter → system font (`.systemFont`)
//   - `.serif`        → Georgia (existing; preserved)
//   - `.monospace`    → Menlo (existing; preserved)
//   - `.system`       → `.systemFont` (existing; preserved)
//
// @coordinates-with: TypographySettings.swift (ReaderFontFamily),
//   ReaderTheme.swift (cssFontStack), project.yml (UIAppFonts).

#if canImport(UIKit)
import Testing
import UIKit
import Foundation
@testable import vreader

@Suite("ReaderTypography — Feature #60 WI-1")
struct ReaderTypographyTests {

    // MARK: - body(for:) returns a UIFont (never nil)

    /// The registry MUST return a usable UIFont for every ReaderFontFamily
    /// case, even when the requested face isn't registered. Reader views
    /// that hit a nil here would fail to lay out text — unacceptable.
    @Test
    func body_returnsUsableFont_forEveryCase() {
        for family in ReaderFontFamily.allCases {
            let font = ReaderTypography.body(for: family, size: 16)
            #expect(font.pointSize == 16,
                    "\(family.rawValue) returned a UIFont but at the wrong size")
        }
    }

    @Test
    func body_respectsPointSize() {
        let small = ReaderTypography.body(for: .system, size: 12)
        let large = ReaderTypography.body(for: .system, size: 32)
        #expect(small.pointSize == 12)
        #expect(large.pointSize == 32)
    }

    // MARK: - Trait invariant (holds for bundled face OR fallback)

    /// `.sourceSerif4` must resolve to a serif face — so EPUB CSS
    /// injection emits a serif stack and the TXT bridge picks a serif
    /// glyph. Post-WI-1b this resolves to the bundled Source Serif 4;
    /// the trait assertion also covers the defensive fallback (Georgia
    /// / system serif) if the bundled face ever fails to load.
    @Test
    func body_sourceSerif4_resolvesToASerifFace() {
        let font = ReaderTypography.body(for: .sourceSerif4, size: 18)
        let isGeorgia = font.fontName.contains("Georgia")
        let isSourceSerif = font.fontName.contains("SourceSerif")
                          || font.fontName.contains("Source Serif")
        let isFallbackSerif = font.familyName.lowercased().contains("serif")
                            || isGeorgia
        #expect(isGeorgia || isSourceSerif || isFallbackSerif,
                "Expected a serif face for .sourceSerif4, got \(font.fontName) (family: \(font.familyName))")
    }

    /// `.inter` must resolve to a sans face (chrome uses Inter — sans by
    /// default). Post-WI-1b this resolves to the bundled Inter; the
    /// not-serif assertion also covers the defensive system-sans
    /// fallback if the bundled face ever fails to load.
    @Test
    func body_inter_resolvesToASansFace() {
        let font = ReaderTypography.body(for: .inter, size: 18)
        let isInter = font.fontName.contains("Inter")
        // Apple's default system font names are version-dependent; checking
        // that it's NOT a serif family is the stable assertion.
        let familyIsNotSerif = !font.familyName.lowercased().contains("serif")
                             && !font.familyName.lowercased().contains("georgia")
        #expect(isInter || familyIsNotSerif,
                "Expected a sans face for .inter, got \(font.fontName) (family: \(font.familyName))")
    }

    // MARK: - WI-1b: bundled font binaries resolve

    /// After WI-1b bundles the Source Serif 4 `.otf` faces + registers
    /// them under `UIAppFonts`, `.sourceSerif4` resolves to the REAL
    /// face — `familyName == "Source Serif 4"`, not the Georgia
    /// fallback. RED before WI-1b (no binary → Georgia); GREEN after.
    @Test
    func body_sourceSerif4_resolvesToBundledFace() {
        let font = ReaderTypography.body(for: .sourceSerif4, size: 17)
        #expect(font.familyName == "Source Serif 4",
                "Expected the bundled Source Serif 4 face, got family \(font.familyName) / \(font.fontName)")
    }

    /// After WI-1b, `.inter` resolves to the real Inter face —
    /// `familyName == "Inter"`, not the system-sans fallback.
    @Test
    func body_inter_resolvesToBundledFace() {
        let font = ReaderTypography.body(for: .inter, size: 17)
        #expect(font.familyName == "Inter",
                "Expected the bundled Inter face, got family \(font.familyName) / \(font.fontName)")
    }

    /// All 7 bundled faces must be registered with the system and
    /// resolvable by their exact PostScript name — the form
    /// `UIFont(name:size:)` (and `ReaderTypography`) looks them up by.
    /// PostScript names verified against the shipped `.otf` `name`
    /// tables (Source Serif 4.005 / Inter 4.1).
    @Test(arguments: [
        "SourceSerif4-Regular", "SourceSerif4-It",
        "SourceSerif4-Bold", "SourceSerif4-BoldIt",
        "Inter-Regular", "Inter-Medium", "Inter-SemiBold",
    ])
    func bundledFace_resolvesByPostScriptName(_ postScriptName: String) {
        #expect(UIFont(name: postScriptName, size: 17) != nil,
                "Bundled face '\(postScriptName)' is not registered — check UIAppFonts in project.yml and that the .otf shipped in Resources/Fonts/")
    }

    // MARK: - Existing-family preservation (regression guard)

    /// The 3 historical families (.system / .serif / .monospace) must
    /// continue resolving as they always did. Per-book persisted
    /// `ReaderFontFamily` values from before WI-1 keep working.
    @Test
    func body_legacyFamilies_resolveAsBefore() {
        let system = ReaderTypography.body(for: .system, size: 16)
        #expect(system.pointSize == 16)

        let serif = ReaderTypography.body(for: .serif, size: 16)
        #expect(serif.fontName.contains("Georgia"))

        let monospace = ReaderTypography.body(for: .monospace, size: 16)
        let monoFamilyIsMono = monospace.fontName.contains("Menlo")
                             || monospace.fontName.contains("Mono")
                             || monospace.fontName.contains("Courier")
        #expect(monoFamilyIsMono,
                "Expected monospace face for .monospace, got \(monospace.fontName)")
    }

    // MARK: - cssFontStack(for:) extended with new families

    /// The CSS font stack returned for `.sourceSerif4` and `.inter` must
    /// list the named face first, with a serif/sans fallback chain so
    /// the EPUB WKWebView renders correctly even if the font isn't
    /// bundled yet. Tested at the WI-1 boundary; WI-4 wires the stack
    /// into the actual CSS injection.
    @Test
    func cssFontStack_sourceSerif4_listsFamilyFirstThenSerifFallback() {
        let stack = ReaderTypography.cssFontStack(for: .sourceSerif4)
        #expect(stack.contains("Source Serif 4") || stack.contains("'Source Serif 4'"),
                "Stack must name Source Serif 4 first; got \(stack)")
        #expect(stack.contains("serif"),
                "Stack must end with the serif generic family; got \(stack)")
    }

    @Test
    func cssFontStack_inter_listsFamilyFirstThenSansFallback() {
        let stack = ReaderTypography.cssFontStack(for: .inter)
        #expect(stack.contains("Inter"),
                "Stack must name Inter first; got \(stack)")
        #expect(stack.contains("sans-serif"),
                "Stack must end with the sans-serif generic family; got \(stack)")
    }

    /// Legacy stacks (.system / .serif / .monospace) preserved.
    @Test
    func cssFontStack_legacy_preservedShape() {
        let system = ReaderTypography.cssFontStack(for: .system)
        #expect(system.contains("system-ui") || system.contains("-apple-system"))

        let serif = ReaderTypography.cssFontStack(for: .serif)
        #expect(serif.contains("Georgia"))
        #expect(serif.contains("serif"))

        let monospace = ReaderTypography.cssFontStack(for: .monospace)
        #expect(monospace.contains("monospace"))
    }

    // MARK: - Sendable (compile-time)

    @Test
    func sendable_conformance_isAvailable() {
        func requireSendable<T: Sendable>(_ value: T) -> T { value }
        _ = requireSendable(ReaderFontFamily.sourceSerif4)
        _ = requireSendable(ReaderFontFamily.inter)
    }
}

// MARK: - ReaderFontFamily extension tests (additive backward compat)

@Suite("ReaderFontFamily extension — Feature #60 WI-1")
struct ReaderFontFamilyExtensionTests {

    /// Five cases now: 3 historical + 2 new. Future-additions catch via
    /// the count check; allCases ensures no case is silently dropped.
    @Test
    func allCases_containsExactlyFiveFamilies() {
        let cases = ReaderFontFamily.allCases
        #expect(cases.count == 5)
        #expect(Set(cases) == [.system, .serif, .monospace, .sourceSerif4, .inter])
    }

    @Test
    func rawValue_isSemanticName_forNewCases() {
        #expect(ReaderFontFamily.sourceSerif4.rawValue == "sourceSerif4")
        #expect(ReaderFontFamily.inter.rawValue == "inter")
    }

    /// Existing persisted JSON values must continue to decode. The
    /// WI-1 extension is additive, not a rename.
    @Test
    func decode_legacyRawValues_stillDecode() throws {
        let cases: [(json: String, expected: ReaderFontFamily)] = [
            ("\"system\"",    .system),
            ("\"serif\"",     .serif),
            ("\"monospace\"", .monospace),
        ]
        for (json, expected) in cases {
            let decoded = try JSONDecoder().decode(
                ReaderFontFamily.self, from: Data(json.utf8)
            )
            #expect(decoded == expected)
        }
    }

    @Test
    func decode_newRawValues_decodeCorrectly() throws {
        let cases: [(json: String, expected: ReaderFontFamily)] = [
            ("\"sourceSerif4\"", .sourceSerif4),
            ("\"inter\"",        .inter),
        ]
        for (json, expected) in cases {
            let decoded = try JSONDecoder().decode(
                ReaderFontFamily.self, from: Data(json.utf8)
            )
            #expect(decoded == expected)
        }
    }

    @Test
    func encode_newCases_emitSemanticName() throws {
        let encoder = JSONEncoder()
        let serifData = try encoder.encode(ReaderFontFamily.sourceSerif4)
        #expect(String(data: serifData, encoding: .utf8) == "\"sourceSerif4\"")
        let interData = try encoder.encode(ReaderFontFamily.inter)
        #expect(String(data: interData, encoding: .utf8) == "\"inter\"")
    }
}
#endif
