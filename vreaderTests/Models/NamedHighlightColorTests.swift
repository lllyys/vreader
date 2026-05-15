// Purpose: Tests for `NamedHighlightColor` — UI-domain enum for the four
// named highlight colors in Feature #60's SelectionPopover (WI-3).
//
// Additive over the existing raw-`String` `Highlight.color` schema; this
// type does NOT replace the storage boundary in `Highlight.swift` /
// `HighlightRecord.swift` / `BackupSectionDTOs.swift` / `ExportedAnnotation.swift`.
// The compatibility test below pins `from(storageString:)` decode
// behavior — it is NOT a guarantee that the storage types stay raw
// `String`. The storage-boundary guarantee lives in the design of
// those files (still raw `String` as of this WI) and in Codex Gate 2
// round 1's plan audit, which would catch a future schema narrowing.

import Testing
import Foundation
@testable import vreader

@Suite("NamedHighlightColor — Feature #60 WI-3")
struct NamedHighlightColorTests {

    // MARK: - Exhaustive switch (compile-time guarantee via CaseIterable)

    @Test
    func allCases_containsExactlyFourColors() {
        let cases = NamedHighlightColor.allCases
        #expect(cases.count == 4)
        #expect(Set(cases) == [.yellow, .pink, .green, .blue])
    }

    // MARK: - rawValue is the semantic name (storage contract)

    @Test
    func rawValue_isSemanticName_forEachCase() {
        #expect(NamedHighlightColor.yellow.rawValue == "yellow")
        #expect(NamedHighlightColor.pink.rawValue == "pink")
        #expect(NamedHighlightColor.green.rawValue == "green")
        #expect(NamedHighlightColor.blue.rawValue == "blue")
    }

    // MARK: - Derived hex per design bundle

    /// Hex values pinned from
    /// `dev-docs/designs/vreader-fidelity-v1/project/vreader-reader.jsx`
    /// `SelectionPopover` `colorMap`. A drift in these breaks the visual
    /// contract against the design — the test catches it.
    @Test
    func hex_matchesDesignBundle_forEachCase() {
        #expect(NamedHighlightColor.yellow.hex == "#f0d25a")
        #expect(NamedHighlightColor.pink.hex == "#e88ca0")
        #expect(NamedHighlightColor.green.hex == "#8cc88c")
        #expect(NamedHighlightColor.blue.hex == "#8cb4e8")
    }

    // MARK: - Codable round-trip via semantic-name rawValue

    @Test
    func codable_roundTrip_preservesEnumViaSemanticName() throws {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        for color in NamedHighlightColor.allCases {
            let data = try encoder.encode(color)
            let decoded = try decoder.decode(NamedHighlightColor.self, from: data)
            #expect(decoded == color)
        }
    }

    @Test
    func codable_encodesAsSemanticNameString() throws {
        let encoder = JSONEncoder()
        let data = try encoder.encode(NamedHighlightColor.pink)
        let asString = try #require(String(data: data, encoding: .utf8))
        #expect(asString == "\"pink\"")
    }

    // MARK: - from(storageString:) — best-effort decoder

    @Test
    func fromStorageString_happyPath_returnsMatchingCase() {
        #expect(NamedHighlightColor.from(storageString: "yellow") == .yellow)
        #expect(NamedHighlightColor.from(storageString: "pink") == .pink)
        #expect(NamedHighlightColor.from(storageString: "green") == .green)
        #expect(NamedHighlightColor.from(storageString: "blue") == .blue)
    }

    @Test
    func fromStorageString_unknownInput_returnsNil_noCoercion() {
        // Per Codex Gate 2 round 1: the decoder must NOT default unknown
        // values to `.yellow`. The caller decides whether to fall back.
        #expect(NamedHighlightColor.from(storageString: "red") == nil)
        #expect(NamedHighlightColor.from(storageString: "") == nil)
        #expect(NamedHighlightColor.from(storageString: "#ff0000") == nil)
        #expect(NamedHighlightColor.from(storageString: "YELLOW") == nil) // case-sensitive
        #expect(NamedHighlightColor.from(storageString: " yellow ") == nil) // no trimming
    }

    // MARK: - Compatibility with existing Highlight.color string schema

    /// Per Codex Gate 2 round 1 (High finding): `NamedHighlightColor` is
    /// strictly additive — it does NOT change `Highlight.color` /
    /// `HighlightRecord.color` / backup DTO / export-import payload
    /// schemas. Those continue to be raw `String`. This test pins the
    /// **decode contract** of `from(storageString:)` so the named
    /// picker correctly classifies legacy and future strings:
    /// 1. Unknown raw strings (legacy hex, empty, custom future name)
    ///    decode to nil — the caller must decide the fallback.
    /// 2. The "yellow" sentinel (the historical default used by every
    ///    existing highlight in persistence) decodes to `.yellow`.
    /// Note: this is a decode-contract pin, not a guarantee that
    /// `Highlight.color` will remain `String`. Schema narrowing of
    /// the storage types is caught by Codex Gate 2 plan audit, not
    /// by this unit test.
    @Test
    func compatibility_existingStorageStringsRemainValidAndUnaltered() {
        let storageStrings: [(input: String, expectedDecode: NamedHighlightColor?)] = [
            // Historical default used since the first highlights shipped.
            ("yellow", .yellow),
            // New named colors landing post-WI-7.
            ("pink",  .pink),
            ("green", .green),
            ("blue",  .blue),
            // Hypothetical legacy hex stored before the named scheme.
            ("#fff3a3", nil),
            // An empty string from a corrupted import.
            ("",       nil),
            // A user-defined custom color from a future feature.
            ("custom-mauve", nil),
        ]
        for (input, expected) in storageStrings {
            let decoded = NamedHighlightColor.from(storageString: input)
            #expect(decoded == expected,
                    "from(storageString: \"\(input)\") = \(String(describing: decoded)) — expected \(String(describing: expected))")
        }
    }
}
