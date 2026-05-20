// Purpose: Composition tests for SettingsIconRow — the design's 30pt
// colored-icon settings row (`vreader-panels.jsx` `SettingsSheet`
// `Row`). Feature #67 WI-2.
//
// These are COMPOSITION assertions, not pixel snapshots: every variant
// builds, the destructive flag drives the title color, and the row
// builds for every `ReaderThemeV2` theme.

import Testing
import SwiftUI
import Foundation
@testable import vreader

@Suite("SettingsIconRow composition — feature #67 WI-2")
@MainActor
struct SettingsIconRowTests {

    // MARK: - Builds — every content combination

    @Test func buildsWithTitleOnly() {
        let row = SettingsIconRow(
            theme: .paper,
            icon: Image(systemName: "globe"),
            iconBackground: .blue,
            title: "Book Sources"
        )
        _ = row.body
    }

    @Test func buildsWithTitleAndDetail() {
        let row = SettingsIconRow(
            theme: .paper,
            icon: Image(systemName: "externaldrive.badge.icloud"),
            iconBackground: .blue,
            title: "WebDAV Backup",
            detail: "Legado-compatible scraping"
        )
        _ = row.body
    }

    @Test func buildsWithTitleAndTrailingValue() {
        let row = SettingsIconRow(
            theme: .paper,
            icon: Image(systemName: "character.textbox"),
            iconBackground: .orange,
            title: "Replacement Rules",
            trailingValue: "5"
        )
        _ = row.body
    }

    @Test func buildsWithDetailAndTrailingValueAndChevron() {
        let row = SettingsIconRow(
            theme: .paper,
            icon: Image(systemName: "speaker.wave.2"),
            iconBackground: .indigo,
            title: "HTTP TTS",
            detail: "System voice · 1.0×",
            trailingValue: "On"
        )
        _ = row.body
    }

    @Test func buildsWithChevronHidden() {
        let row = SettingsIconRow(
            theme: .paper,
            icon: Image(systemName: "info.circle"),
            iconBackground: .gray,
            title: "Version",
            trailingValue: "3.37.6",
            showsChevron: false
        )
        _ = row.body
    }

    // MARK: - Destructive variant

    @Test func destructiveFlagDrivesTitleColor() {
        // The destructive row renders its title in the design's danger
        // color (`#c44`); a non-destructive row uses the theme ink.
        let plain = SettingsIconRow(
            theme: .paper,
            icon: Image(systemName: "trash"),
            iconBackground: .gray,
            title: "Delete All Data"
        )
        let destructive = SettingsIconRow(
            theme: .paper,
            icon: Image(systemName: "trash"),
            iconBackground: .gray,
            title: "Delete All Data",
            isDestructive: true
        )
        #expect(plain.resolvedTitleColorForTesting != destructive.resolvedTitleColorForTesting)
        #expect(destructive.resolvedTitleColorForTesting == SettingsRowColors.destructiveTitle)
    }

    @Test func nonDestructiveTitleColorIsThemeInk() {
        let row = SettingsIconRow(
            theme: .paper,
            icon: Image(systemName: "globe"),
            iconBackground: .blue,
            title: "Book Sources"
        )
        #expect(row.resolvedTitleColorForTesting == Color(ReaderThemeV2.paper.inkColor))
    }

    // MARK: - Trailing generic content

    @Test func buildsWithCustomTrailingContent() {
        // The generic `Trailing` slot accepts an arbitrary view (e.g. a
        // Toggle for the AI group's rows in WI-5).
        let row = SettingsIconRow(
            theme: .paper,
            icon: Image(systemName: "sparkles"),
            iconBackground: .red,
            title: "AI Assistant",
            showsChevron: false
        ) {
            Toggle("", isOn: .constant(true)).labelsHidden()
        }
        _ = row.body
    }

    // MARK: - Layout metrics (design `vreader-panels.jsx` `Row`)

    @Test func rowMetricsMatchTheDesignRow() {
        // The design `Row`: 30pt tile, `borderRadius: 8`, `size={17}`
        // glyph, `gap: 12` tile→title, `padding: '12px ...'`,
        // `marginTop: 1` title→detail, `marginRight: 4` value→chevron.
        #expect(SettingsRowMetrics.iconTileSize == 30)
        #expect(SettingsRowMetrics.iconTileCornerRadius == 8)
        #expect(SettingsRowMetrics.iconGlyphSize == 17)
        #expect(SettingsRowMetrics.tileToTitleSpacing == 12)
        #expect(SettingsRowMetrics.verticalPadding == 12)
        #expect(SettingsRowMetrics.titleToDetailSpacing == 1)
        #expect(SettingsRowMetrics.trailingValueGap == 4)
    }

    @Test func rowFontMetricsMatchTheDesignRow() {
        // Design font sizes: title 15, detail 11, value 14, chevron 13.
        #expect(SettingsRowMetrics.titleFontSize == 15)
        #expect(SettingsRowMetrics.detailFontSize == 11)
        #expect(SettingsRowMetrics.trailingValueFontSize == 14)
        #expect(SettingsRowMetrics.chevronSize == 13)
    }

    // MARK: - Every theme

    @Test func buildsForEveryReaderTheme() {
        // The row is theme-input even though Settings only uses `.paper`
        // — future-proof, mirrors `ReaderSheetChrome`'s every-theme test.
        for theme in ReaderThemeV2.allCases {
            let row = SettingsIconRow(
                theme: theme,
                icon: Image(systemName: "gear"),
                iconBackground: .blue,
                title: "Setting",
                detail: "Detail line",
                trailingValue: "Value"
            )
            _ = row.body
        }
    }
}
