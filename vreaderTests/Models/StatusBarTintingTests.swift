// Purpose: Contract tests for the feature #60 WI-10 status-bar tinting —
// `ReaderThemeV2.preferredColorScheme` resolves to `.dark` for the
// dark-family themes (Dark / OLED / Photo) and `.light` for the
// light-family themes (Paper / Sepia), so the system status-bar text
// stays legible against the reader background.
//
// Per the plan's WI-10 catalogue: "`preferredColorScheme` resolves to
// `.dark` for `isDark` themes (Dark / OLED / Photo) and `.light` for
// Paper / Sepia."
//
// @coordinates-with: ReaderThemeV2.swift, ReaderContainerView.swift

import Testing
import SwiftUI
@testable import vreader

@Suite("Status-bar tinting — feature #60 WI-10")
@MainActor
struct StatusBarTintingTests {

    // MARK: - Per-theme color scheme

    @Test("Paper theme resolves to the light color scheme")
    func paperResolvesToLight() {
        #expect(ReaderThemeV2.paper.preferredColorScheme == .light)
    }

    @Test("Sepia theme resolves to the light color scheme")
    func sepiaResolvesToLight() {
        #expect(ReaderThemeV2.sepia.preferredColorScheme == .light)
    }

    @Test("Dark theme resolves to the dark color scheme")
    func darkResolvesToDark() {
        #expect(ReaderThemeV2.dark.preferredColorScheme == .dark)
    }

    @Test("OLED theme resolves to the dark color scheme")
    func oledResolvesToDark() {
        #expect(ReaderThemeV2.oled.preferredColorScheme == .dark)
    }

    @Test("Photo theme resolves to the dark color scheme")
    func photoResolvesToDark() {
        #expect(ReaderThemeV2.photo.preferredColorScheme == .dark)
    }

    // MARK: - Consistency with isDark

    @Test("preferredColorScheme is dark exactly when isDark is true")
    func colorSchemeTracksIsDark() {
        // The status-bar tint must follow the existing `isDark`
        // predicate exactly — no theme may drift between the two.
        for theme in ReaderThemeV2.allCases {
            if theme.isDark {
                #expect(theme.preferredColorScheme == .dark, "\(theme) isDark")
            } else {
                #expect(theme.preferredColorScheme == .light, "\(theme) light")
            }
        }
    }

    @Test("Exactly three themes resolve to dark")
    func threeThemesAreDark() {
        let darkCount = ReaderThemeV2.allCases.filter {
            $0.preferredColorScheme == .dark
        }.count
        #expect(darkCount == 3)
    }

    @Test("Exactly two themes resolve to light")
    func twoThemesAreLight() {
        let lightCount = ReaderThemeV2.allCases.filter {
            $0.preferredColorScheme == .light
        }.count
        #expect(lightCount == 2)
    }

    // MARK: - Legacy ReaderTheme projection

    @Test("Legacy ReaderTheme projects to a color scheme via asV2")
    func legacyThemeProjectsToColorScheme() {
        // The legacy `ReaderTheme.asV2` projection is retained as the
        // backward-compat decode bridge — `ReaderThemeV2(legacyOrNew:)`
        // routes legacy persisted values through it. (Feature #60 WI-11
        // migrated `ReaderSettingsStore.theme` itself to `ReaderThemeV2`,
        // so the reader container now reads `theme.preferredColorScheme`
        // directly; this test still pins the legacy projection.)
        #expect(ReaderTheme.light.asV2.preferredColorScheme == .light)
        #expect(ReaderTheme.sepia.asV2.preferredColorScheme == .light)
        #expect(ReaderTheme.dark.asV2.preferredColorScheme == .dark)
    }
}
