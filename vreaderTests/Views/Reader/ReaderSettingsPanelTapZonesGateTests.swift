// Purpose: Regression guard for feature #54 WI-4 — the Tap Zones section is
// GONE from `ReaderSettingsPanel`, and its `TapZoneStore` wiring is GONE
// from `ReaderContainerView`. The bug #162 / GH #482 gate
// (`shouldShowTapZonesSection`) gated a section that was only ever shown
// in Unified mode; with the Native/Unified toggle retired (feature #54)
// there is no Unified mode and no install site for `TapZoneStore`-configured
// actions, so the whole section + its `tapZoneStore` plumbing are removed.
//
// The `TapZoneStore` / `TapZoneConfig` *types* survive (a separate
// feature-#25 cleanup owns their retirement) — `TapZoneTests.swift` still
// exercises them directly and is intentionally untouched.
//
// @coordinates-with: vreader/Views/Reader/ReaderSettingsPanel.swift,
//   vreader/Views/Reader/ReaderContainerView.swift

import Testing
import Foundation
@testable import vreader

@Suite("ReaderSettingsPanel — Tap Zones section removed (feature #54 WI-4)")
struct ReaderSettingsPanelTapZonesGateTests {

    private static func loadSource(
        _ relativePath: String,
        testFilePath: String = #filePath
    ) throws -> String {
        let repoRoot = URL(fileURLWithPath: testFilePath)
            .deletingLastPathComponent() // Reader/
            .deletingLastPathComponent() // Views/
            .deletingLastPathComponent() // vreaderTests/
            .deletingLastPathComponent() // repo root
        return try String(contentsOf: repoRoot.appendingPathComponent(relativePath), encoding: .utf8)
    }

    // MARK: - ReaderSettingsPanel

    @Test func tapZoneSectionIsRemovedFromPanel() throws {
        let source = try Self.loadSource("vreader/Views/Reader/ReaderSettingsPanel.swift")
        #expect(
            !source.contains("tapZoneSection"),
            "feature #54 WI-4 removes the `tapZoneSection` from ReaderSettingsPanel."
        )
        #expect(
            !source.contains("shouldShowTapZonesSection"),
            "the bug #162 `shouldShowTapZonesSection` gate has no subject after the section is removed (feature #54 WI-4)."
        )
        #expect(
            !source.contains("unifiedDispatchInstallsTapZoneOverlay"),
            "`unifiedDispatchInstallsTapZoneOverlay` is dead after the Tap Zones section is removed (feature #54 WI-4)."
        )
    }

    @Test func panelDoesNotReferenceTapZoneStore() throws {
        let source = try Self.loadSource("vreader/Views/Reader/ReaderSettingsPanel.swift")
        #expect(
            !source.contains("TapZoneStore"),
            "ReaderSettingsPanel must not reference `TapZoneStore` after feature #54 WI-4 removes the Tap Zones section."
        )
    }

    // MARK: - ReaderContainerView (§2g — the call-graph reaches here)

    @Test func containerDoesNotConstructTapZoneStore() throws {
        let source = try Self.loadSource("vreader/Views/Reader/ReaderContainerView.swift")
        // `ReaderContainerView` was the only `TapZoneStore()` construction
        // site in the app target; with the panel's `tapZoneStore` parameter
        // removed, the `@State` and the sheet argument are both gone.
        #expect(
            !source.contains("TapZoneStore"),
            "ReaderContainerView must not construct/pass `TapZoneStore` after feature #54 WI-4 (§2g)."
        )
        #expect(
            !source.contains("tapZoneStore"),
            "ReaderContainerView must not retain a `tapZoneStore` `@State` or pass it to ReaderSettingsPanel (feature #54 WI-4)."
        )
    }

    // MARK: - The TapZoneStore / TapZoneConfig types still exist

    /// Feature #54 removes only the *use* of TapZoneStore from the panel +
    /// container — the type itself survives (its full retirement is a
    /// separate feature-#25 cleanup). `TapZoneStore` is `@MainActor`, so
    /// this test is too.
    @MainActor
    @Test func tapZoneStoreTypeStillExists() {
        let store = TapZoneStore()
        #expect(store.config.leftAction == TapZoneConfig.default.leftAction)
    }
}
