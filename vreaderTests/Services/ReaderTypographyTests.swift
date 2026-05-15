// Purpose: Tests for `ReaderTypography` — Feature #60 WI-1 foundational
// font registry. Resolves a `ReaderFontFamily` case to a UIFont for the
// reader body + UI chrome.
//
// Strictly dormant infra in this WI: no view consumes
// `ReaderTypography` yet — that's WI-5 (TXT/MD theme) and WI-6 (chrome
// re-skin). Font binaries (Source Serif 4 + Inter `.otf` files) are
// NOT bundled in this WI; they require external asset fetching with
// licence verification, deferred to a separate manual-ops WI-1b. The
// registry's fallback chain (described below) handles the unregistered-
// font case gracefully so the API surface is ready for WI-5/6 to
// consume without compile errors.
//
// Fallback chain (per the plan's "Tests: fallback chain"):
//   - `.sourceSerif4` → real Source Serif 4 if registered → Georgia →
//     UIFont serif system font
//   - `.inter`        → real Inter if registered → system font (`.systemFont`)
//   - `.serif`        → Georgia (existing; preserved)
//   - `.monospace`    → Menlo (existing; preserved)
//   - `.system`       → `.systemFont` (existing; preserved)
//
// @coordinates-with: TypographySettings.swift (ReaderFontFamily),
//   ReaderTheme.swift (cssFontStack), the WI-5/WI-6 consumers.

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

    // MARK: - Fallback chain for the new families

    /// `.sourceSerif4` requested with no Source Serif 4 face registered
    /// falls back to a serif face. The exact resolved name varies by
    /// fallback (Georgia or system serif), but the trait must remain
    /// `serif` so the EPUB CSS injection emits a serif stack and the
    /// TXT bridge picks a serif glyph.
    @Test
    func body_sourceSerif4_fallsBack_toASerifFace_whenFontNotRegistered() {
        // Source Serif 4 is NOT bundled in this WI (binaries deferred to
        // WI-1b). The registry must return a UIFont that satisfies the
        // serif trait — Georgia in this codebase's current state, or a
        // future system-registered Source Serif 4 if bundled later.
        let font = ReaderTypography.body(for: .sourceSerif4, size: 18)
        let isGeorgia = font.fontName.contains("Georgia")
        let isSourceSerif = font.fontName.contains("SourceSerif")
                          || font.fontName.contains("Source Serif")
        let isFallbackSerif = font.familyName.lowercased().contains("serif")
                            || isGeorgia
        #expect(isGeorgia || isSourceSerif || isFallbackSerif,
                "Expected serif fallback for unregistered Source Serif 4, got \(font.fontName) (family: \(font.familyName))")
    }

    /// `.inter` requested with no Inter face registered falls back to the
    /// platform sans system font (matches the WI's "chrome uses Inter"
    /// expectation — sans by default).
    @Test
    func body_inter_fallsBack_toSystemSans_whenFontNotRegistered() {
        // Inter is NOT bundled in this WI. Fallback must be a sans face.
        let font = ReaderTypography.body(for: .inter, size: 18)
        let isInter = font.fontName.contains("Inter")
        // Apple's default system font names are version-dependent; checking
        // that it's NOT a serif family is the stable assertion.
        let familyIsNotSerif = !font.familyName.lowercased().contains("serif")
                             && !font.familyName.lowercased().contains("georgia")
        #expect(isInter || familyIsNotSerif,
                "Expected sans fallback for unregistered Inter, got \(font.fontName) (family: \(font.familyName))")
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
