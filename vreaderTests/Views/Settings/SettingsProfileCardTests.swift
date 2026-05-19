// Purpose: Composition tests for SettingsProfileCard — the design's
// library-identity profile-header card (`ProfileCardLibrary` in
// `vreader-profile-stats.jsx`). Feature #67 WI-3.
//
// COMPOSITION assertions, not pixel snapshots: the card builds for
// every theme, its Stats button invokes the `onOpenStats` closure, and
// the header / subline copy is pinned.

import Testing
import SwiftUI
import UIKit
import Foundation
@testable import vreader

@Suite("SettingsProfileCard composition — feature #67 WI-3")
@MainActor
struct SettingsProfileCardTests {

    private func makeCard(
        bookCount: Int = 152,
        monthReadingSeconds: Int = 149_400,
        theme: ReaderThemeV2 = .paper,
        onOpenStats: @escaping () -> Void = {}
    ) -> SettingsProfileCard {
        SettingsProfileCard(
            theme: theme,
            bookCount: bookCount,
            monthReadingSeconds: monthReadingSeconds,
            onOpenStats: onOpenStats
        )
    }

    // MARK: - Builds

    @Test func buildsForEveryReaderTheme() {
        for theme in ReaderThemeV2.allCases {
            let card = makeCard(theme: theme)
            _ = card.body
        }
    }

    // MARK: - Stats action seam

    @Test func statsActionInvokesTheOnOpenStatsClosure() {
        var fired = false
        let card = makeCard(onOpenStats: { fired = true })
        // statsActionForTesting is a closure-only seam — it confirms the
        // card invokes its onOpenStats closure. The card itself posts no
        // notification; the notification hand-off is WI-4's wiring.
        card.statsActionForTesting()
        #expect(fired)
    }

    @Test func statsActionFiresEachTimeInvoked() {
        var count = 0
        let card = makeCard(onOpenStats: { count += 1 })
        card.statsActionForTesting()
        card.statsActionForTesting()
        #expect(count == 2)
    }

    // MARK: - Header copy (library-identity model)

    @Test func headerIsAlwaysYourLibrary() {
        // Library-identity model (#862 Option A) — never a user name.
        for count in [0, 1, 152] {
            let card = makeCard(bookCount: count)
            #expect(card.headerTextForTesting == "Your library")
        }
    }

    // MARK: - Subline copy

    @Test func sublineForEmptyLibraryIsZeroBooksZeroHours() {
        let card = makeCard(bookCount: 0, monthReadingSeconds: 0)
        #expect(card.sublineTextForTesting == "0 books · 0h read this month")
    }

    @Test func sublineForOneBookUsesSingularBook() {
        // Singular "book", not "books".
        let card = makeCard(bookCount: 1, monthReadingSeconds: 0)
        #expect(card.sublineTextForTesting == "1 book · 0h read this month")
    }

    @Test func sublineForPopulatedLibraryMatchesDesignValue() {
        // The design's "152 books · 41h read this month" (149 400 s = 41h30m).
        let card = makeCard(bookCount: 152, monthReadingSeconds: 149_400)
        #expect(card.sublineTextForTesting == "152 books · 41h read this month")
    }

    @Test func sublineSubHourReadingShowsLessThanOneHour() {
        // 30 minutes of reading → "<1h" (never "0h" while reading happened).
        let card = makeCard(bookCount: 3, monthReadingSeconds: 1_800)
        #expect(card.sublineTextForTesting == "3 books · <1h read this month")
    }

    @Test func sublineTwoBooksUsesPluralBooks() {
        let card = makeCard(bookCount: 2, monthReadingSeconds: 7_200)
        #expect(card.sublineTextForTesting == "2 books · 2h read this month")
    }

    // MARK: - Design-fill pins (vreader-profile-stats.jsx ProfileCardLibrary)

    /// Extracts the sRGB components of a `Color` for pinning.
    private func components(_ color: Color) -> (r: CGFloat, g: CGFloat, b: CGFloat, a: CGFloat) {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(color).getRed(&r, green: &g, blue: &b, alpha: &a)
        return (r, g, b, a)
    }

    @Test func cardBackgroundMatchesDesignLightAndDark() {
        // Design: `t.isDark ? 'rgba(255,255,255,0.04)' : '#fff'`.
        let light = components(SettingsProfileCardColors.cardBackground(isDark: false))
        #expect(light.r == 1 && light.g == 1 && light.b == 1)
        #expect(abs(light.a - 1.0) < 0.005)

        let dark = components(SettingsProfileCardColors.cardBackground(isDark: true))
        #expect(dark.r == 1 && dark.g == 1 && dark.b == 1)
        #expect(abs(dark.a - 0.04) < 0.005)
    }

    @Test func glyphTileFillMatchesDesignLightAndDark() {
        // Design: `t.isDark ? 'rgba(255,255,255,0.06)' : 'rgba(0,0,0,0.04)'`.
        let light = components(SettingsProfileCardColors.glyphTileFill(isDark: false))
        #expect(light.r == 0 && light.g == 0 && light.b == 0)
        #expect(abs(light.a - 0.04) < 0.005)

        let dark = components(SettingsProfileCardColors.glyphTileFill(isDark: true))
        #expect(dark.r == 1 && dark.g == 1 && dark.b == 1)
        #expect(abs(dark.a - 0.06) < 0.005)
    }

    @Test func statsPillFillMatchesDesignLightAndDark() {
        // Design: `t.isDark ? 'rgba(255,255,255,0.08)' : 'rgba(60,40,20,0.08)'`.
        let light = components(SettingsProfileCardColors.statsPillFill(isDark: false))
        #expect(abs(light.r - 60 / 255.0) < 0.005)
        #expect(abs(light.g - 40 / 255.0) < 0.005)
        #expect(abs(light.b - 20 / 255.0) < 0.005)
        #expect(abs(light.a - 0.08) < 0.005)

        let dark = components(SettingsProfileCardColors.statsPillFill(isDark: true))
        #expect(dark.r == 1 && dark.g == 1 && dark.b == 1)
        #expect(abs(dark.a - 0.08) < 0.005)
    }
}
