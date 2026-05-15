// Purpose: Tests for `ReaderThemeV2`'s Codable migration alias — Feature
// #60 WI-2. Existing per-book persisted theme choices stored the old
// `ReaderTheme` rawValue ("light" / "sepia" / "dark"). To keep those
// settings readable when WI-4+ switches the reader engines to V2,
// `ReaderThemeV2`'s decoder accepts both the legacy names AND the new
// names ("paper" / "sepia" / "dark" / "oled" / "photo"). Encoding
// always emits the new name.
//
// Cross-ref: rule 47 backward-compat requirement + plan section
// "Modified types > `ReaderTheme.swift`" ("the deprecation preserves
// Codable read-paths for existing per-book persisted settings").

#if canImport(UIKit)
import Testing
import Foundation
@testable import vreader

@Suite("ReaderThemeV2 Codable migration — Feature #60 WI-2")
struct ReaderThemeMigrationTests {

    // MARK: - Legacy-name decoding (the migration path)

    /// Existing per-book JSON shaped as `{"theme":"light"}` MUST continue
    /// decoding — otherwise users lose their per-book theme settings on
    /// the WI-4 cutover. The legacy `"light"` maps to `.paper`.
    @Test
    func decode_legacyLight_yieldsPaper() throws {
        let json = "\"light\""
        let decoded = try JSONDecoder().decode(
            ReaderThemeV2.self,
            from: Data(json.utf8)
        )
        #expect(decoded == .paper)
    }

    /// Legacy `"sepia"` stayed the same name. No migration needed; pinned
    /// here so a future renaming doesn't silently break it.
    @Test
    func decode_legacySepia_yieldsSepia() throws {
        let json = "\"sepia\""
        let decoded = try JSONDecoder().decode(
            ReaderThemeV2.self,
            from: Data(json.utf8)
        )
        #expect(decoded == .sepia)
    }

    /// Legacy `"dark"` — same name. Pinned for the same reason.
    @Test
    func decode_legacyDark_yieldsDark() throws {
        let json = "\"dark\""
        let decoded = try JSONDecoder().decode(
            ReaderThemeV2.self,
            from: Data(json.utf8)
        )
        #expect(decoded == .dark)
    }

    // MARK: - New-name decoding (the future-default path)

    @Test
    func decode_newNames_roundTrip() throws {
        for theme in ReaderThemeV2.allCases {
            let json = "\"\(theme.rawValue)\""
            let decoded = try JSONDecoder().decode(
                ReaderThemeV2.self,
                from: Data(json.utf8)
            )
            #expect(decoded == theme)
        }
    }

    // MARK: - Encoding produces the new name only (no `light` regression)

    @Test
    func encode_paper_producesNewName_notLegacy() throws {
        let data = try JSONEncoder().encode(ReaderThemeV2.paper)
        let json = try #require(String(data: data, encoding: .utf8))
        #expect(json == "\"paper\"")
    }

    @Test
    func encode_allThemes_useSemanticName() throws {
        for theme in ReaderThemeV2.allCases {
            let data = try JSONEncoder().encode(theme)
            let json = try #require(String(data: data, encoding: .utf8))
            #expect(json == "\"\(theme.rawValue)\"")
        }
    }

    // MARK: - Round-trip stability (no silent name flips)

    /// Decode-then-encode of a new-name JSON must produce byte-identical
    /// JSON. Decode-then-encode of a legacy-name JSON must produce the
    /// MIGRATED name (the migration is one-way, that's the intent).
    @Test
    func roundTrip_newName_preservesBytes() throws {
        for theme in ReaderThemeV2.allCases {
            let inJSON = "\"\(theme.rawValue)\""
            let decoded = try JSONDecoder().decode(
                ReaderThemeV2.self,
                from: Data(inJSON.utf8)
            )
            let outData = try JSONEncoder().encode(decoded)
            let outJSON = try #require(String(data: outData, encoding: .utf8))
            #expect(outJSON == inJSON)
        }
    }

    @Test
    func roundTrip_legacyLight_migratesToPaper_oneWay() throws {
        let inJSON = "\"light\""
        let decoded = try JSONDecoder().decode(
            ReaderThemeV2.self,
            from: Data(inJSON.utf8)
        )
        let outData = try JSONEncoder().encode(decoded)
        let outJSON = try #require(String(data: outData, encoding: .utf8))
        #expect(outJSON == "\"paper\"")
        #expect(decoded == .paper)
    }

    // MARK: - Unknown strings fail loudly

    /// Unknown rawValues throw a `DecodingError`. We intentionally don't
    /// silently coerce to `.paper` — that would mask schema breakage in
    /// future versions. If a user's per-book JSON ever contained an
    /// unknown theme, the caller decides the fallback policy (e.g.,
    /// re-use the global default).
    @Test
    func decode_unknownName_throws() {
        let json = "\"chartreuse\""
        #expect(throws: DecodingError.self) {
            _ = try JSONDecoder().decode(
                ReaderThemeV2.self,
                from: Data(json.utf8)
            )
        }
    }

    @Test
    func decode_emptyString_throws() {
        let json = "\"\""
        #expect(throws: DecodingError.self) {
            _ = try JSONDecoder().decode(
                ReaderThemeV2.self,
                from: Data(json.utf8)
            )
        }
    }
}
#endif
