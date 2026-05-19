// Purpose: Regression guard for feature #54 WI-4 — the Reading Mode picker
// is GONE from `ReaderSettingsPanel`. The bug #158 / GH #468 gate
// (`shouldShowReadingModeSection`) and the `readingModeSection` it gated
// are both deleted: feature #54 retired the Native/Unified toggle entirely,
// so there is no picker to gate.
//
// Pre-#54 this suite tested the bug #158 capability gate. Post-#54 the gate
// has no subject; this suite now pins the *absence* of the picker — a
// source-level guard that the section, its gate helper, and the
// `ReadingMode` enum are not re-introduced into the panel.
//
// @coordinates-with: vreader/Views/Reader/ReaderSettingsPanel.swift

import Testing
import Foundation
@testable import vreader

@Suite("ReaderSettingsPanel — Reading Mode picker removed (feature #54 WI-4)")
struct ReaderSettingsPanelReadingModeGateTests {

    /// Loads the `ReaderSettingsPanel.swift` production source by walking
    /// up from this test's compile-time `#filePath` to the repo root.
    private static func loadPanelSource(testFilePath: String = #filePath) throws -> String {
        let repoRoot = URL(fileURLWithPath: testFilePath)
            .deletingLastPathComponent() // Reader/
            .deletingLastPathComponent() // Views/
            .deletingLastPathComponent() // vreaderTests/
            .deletingLastPathComponent() // repo root
        return try String(
            contentsOf: repoRoot.appendingPathComponent("vreader/Views/Reader/ReaderSettingsPanel.swift"),
            encoding: .utf8
        )
    }

    @Test func readingModeSectionIsRemoved() throws {
        let source = try Self.loadPanelSource()
        #expect(
            !source.contains("readingModeSection"),
            "feature #54 WI-4 removes the `readingModeSection` — the Native/Unified picker is gone."
        )
    }

    @Test func shouldShowReadingModeSectionHelperIsRemoved() throws {
        let source = try Self.loadPanelSource()
        #expect(
            !source.contains("shouldShowReadingModeSection"),
            "the bug #158 `shouldShowReadingModeSection` gate has no subject after the picker is removed (feature #54 WI-4)."
        )
    }

    @Test func panelDoesNotReferenceReadingMode() throws {
        let source = try Self.loadPanelSource()
        // The panel must not *read* `store.readingMode`, observe it, or
        // use the `ReadingMode` enum — the picker bound to it is gone, the
        // `.onChange(of: store.readingMode)` observer is removed, and
        // `savePerBookSnapshot` no longer snapshots it. (A comment that
        // *explains* the removal is fine — we ban the code references,
        // not the literal substring.)
        #expect(
            !source.contains("store.readingMode"),
            "ReaderSettingsPanel must not read `store.readingMode` after feature #54 WI-4."
        )
        #expect(
            !source.contains("ReadingMode."),
            "ReaderSettingsPanel must not reference `ReadingMode.<case>` after feature #54 WI-4."
        )
        #expect(
            !source.contains("$store.readingMode"),
            "ReaderSettingsPanel must not bind to `$store.readingMode` after feature #54 WI-4 removes the picker."
        )
    }

    @Test func panelHeaderDoesNotMentionReadingMode() throws {
        let source = try Self.loadPanelSource()
        // The file header `// Purpose:` line named "reading mode"; that
        // reference must be removed when the picker is.
        let header = String(source.prefix(800))
        #expect(
            !header.lowercased().contains("reading mode"),
            "the ReaderSettingsPanel file header must not name the removed `reading mode` picker (feature #54 WI-4)."
        )
    }
}
