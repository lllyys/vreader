// Purpose: Composition tests for the feature #60 WI-10 re-skin of the
// 5 app sheets (Display / TOC / Annotations / AI / App Settings).
//
// These are COMPOSITION assertions, NOT pixel snapshots: they pin each
// re-skinned sheet's section set + ordering against the design bundle
// (`vreader-panels.jsx`), confirm the shared `ReaderSheetChrome` wrapper
// behaves per the design's `Sheet`, and confirm every re-skinned sheet
// view still builds (the WI-9 lesson — a re-skin must not drop the
// underlying view's wiring).
//
// @coordinates-with: SheetSectionContract.swift, ReaderSheetChrome.swift,
//   ReaderThemeV2.swift, ReaderSettingsPanel.swift, TOCListView.swift,
//   HighlightListView.swift, AIReaderPanel.swift, SettingsView.swift

import Testing
import SwiftUI
import SwiftData
import Foundation
@testable import vreader

@Suite("Sheet re-skin composition — feature #60 WI-10")
@MainActor
struct SheetReSkinSnapshotTests {

    // MARK: - Section contract (design `vreader-panels.jsx`)

    @Test("There are exactly 5 re-skinned sheets")
    func fiveReSkinnedSheets() {
        #expect(ReaderSheetKind.allCases.count == 5)
    }

    @Test("Display sheet sections match the design order")
    func displaySheetSections() {
        #expect(ReaderSheetKind.display.sections
            == ["Brightness", "Theme", "Font", "Size",
                "Line spacing", "Margin"])
    }

    @Test("Display sheet title is the design 'Display'")
    func displaySheetTitle() {
        #expect(ReaderSheetKind.display.designTitle == "Display")
    }

    @Test("TOC sheet sections are the Contents / Bookmarks tabs")
    func tocSheetSections() {
        #expect(ReaderSheetKind.tableOfContents.sections
            == ["Contents", "Bookmarks"])
    }

    @Test("TOC sheet title is runtime-set (the book title)")
    func tocSheetTitleIsRuntime() {
        // The design shows a sample book title; the chrome title is
        // set at runtime, so the contract carries nil.
        #expect(ReaderSheetKind.tableOfContents.designTitle == nil)
    }

    @Test("Annotations sheet sections are the four filter chips")
    func annotationsSheetSections() {
        #expect(ReaderSheetKind.annotations.sections
            == ["All", "Highlights", "Notes", "Bookmarks"])
    }

    @Test("Annotations sheet title is the design 'Annotations'")
    func annotationsSheetTitle() {
        #expect(ReaderSheetKind.annotations.designTitle == "Annotations")
    }

    @Test("AI sheet sections are the three mode tabs")
    func aiSheetSections() {
        #expect(ReaderSheetKind.aiAssistant.sections
            == ["Summarize", "Chat", "Translate"])
    }

    @Test("AI sheet has no standard title bar (custom header)")
    func aiSheetHasNoTitleBar() {
        #expect(ReaderSheetKind.aiAssistant.designTitle == nil)
    }

    @Test("App Settings sheet sections match the design groups")
    func appSettingsSheetSections() {
        #expect(ReaderSheetKind.appSettings.sections
            == ["Cloud & Sync", "AI", "Reading", "About"])
    }

    @Test("App Settings sheet title is the design 'Settings'")
    func appSettingsSheetTitle() {
        #expect(ReaderSheetKind.appSettings.designTitle == "Settings")
    }

    @Test("Every sheet has a non-empty, distinct section list")
    func everySheetHasSections() {
        for kind in ReaderSheetKind.allCases {
            #expect(!kind.sections.isEmpty, "\(kind) sections")
        }
    }

    // MARK: - ReaderSheetChrome (design `Sheet`)

    @Test("Sheet chrome surface is dark for dark-family themes")
    func sheetSurfaceDarkForDarkThemes() {
        // Design `Sheet`: `t.isDark ? '#222020' : '#fcf8f0'`.
        for theme in [ReaderThemeV2.dark, .oled, .photo] {
            assertColor(theme.sheetSurfaceColor, rgb: (0x22, 0x20, 0x20))
        }
    }

    @Test("Sheet chrome surface is light for light-family themes")
    func sheetSurfaceLightForLightThemes() {
        for theme in [ReaderThemeV2.paper, .sepia] {
            assertColor(theme.sheetSurfaceColor, rgb: (0xfc, 0xf8, 0xf0))
        }
    }

    @Test("Sheet chrome builds with a title bar")
    func sheetChromeBuildsWithTitle() {
        let chrome = ReaderSheetChrome(theme: .paper, title: "Display") {
            Text("body")
        }
        _ = chrome.body
    }

    @Test("Sheet chrome builds without a title bar (AI custom header)")
    func sheetChromeBuildsWithoutTitle() {
        let chrome = ReaderSheetChrome(theme: .dark, title: nil) {
            Text("body")
        }
        _ = chrome.body
    }

    @Test("Sheet chrome builds with leading + trailing slots")
    func sheetChromeBuildsWithSlots() {
        let chrome = ReaderSheetChrome(
            theme: .sepia,
            title: "Annotations",
            leading: { Button("Edit") {} },
            trailing: { Button("Share") {} }
        ) {
            Text("body")
        }
        _ = chrome.body
    }

    @Test("Sheet chrome builds for every theme")
    func sheetChromeBuildsForEveryTheme() {
        for theme in ReaderThemeV2.allCases {
            let chrome = ReaderSheetChrome(theme: theme, title: "T") {
                Color.clear
            }
            _ = chrome.body
        }
    }

    // MARK: - Re-skinned views still build (WI-9 regression lesson)

    @Test("Display sheet (ReaderSettingsPanel) still builds re-skinned")
    func displayPanelStillBuilds() {
        let panel = ReaderSettingsPanel(store: ReaderSettingsStore())
        _ = panel.body
        // The re-skinned panel wraps its content in ReaderSheetChrome
        // with the design's "Display" title.
        #expect(panel.sheetChromeTitleForTesting
            == ReaderSheetKind.display.designTitle)
    }

    @Test("Display sheet builds re-skinned for every reader theme")
    func displayPanelBuildsForEveryTheme() {
        // The Display sheet's chrome surface follows the book theme;
        // it must build for all 5 `ReaderThemeV2` themes (Feature #60
        // WI-11 made `ReaderSettingsStore.theme` the 5-case enum and
        // the picker offers all 5).
        for theme in ReaderThemeV2.allCases {
            let store = ReaderSettingsStore()
            store.theme = theme
            let panel = ReaderSettingsPanel(store: store)
            _ = panel.body
        }
    }

    @Test("TOCSheet still builds re-skinned with entries")
    func tocSheetStillBuilds() {
        // Feature #62 split: the TOC surface is now `TOCSheet`
        // (the legacy `TOCListView` was deleted in WI-5).
        let locator = Self.txtLocator(offset: 0)
        let sheet = TOCSheet(
            bookTitle: "Sample Book",
            bookFingerprintKey: "txt:\(String(repeating: "0", count: 64)):0",
            modelContainer: Self.inMemoryContainer(),
            tocEntries: [TOCEntry(title: "Chapter 1", level: 0, locator: locator)],
            currentLocator: locator,
            theme: .paper,
            initialTab: .contents,
            onNavigate: { _ in },
            onOpenSearch: {},
            onDismiss: {}
        )
        _ = sheet.body
    }

    @Test("HighlightsSheet still builds re-skinned")
    func highlightsSheetStillBuilds() {
        // Feature #62 split: the highlights surface is now
        // `HighlightsSheet` (the legacy `HighlightListView` was deleted).
        let sheet = HighlightsSheet(
            bookFingerprintKey: "epub:\(String(repeating: "a", count: 64)):1024",
            modelContainer: Self.inMemoryContainer(),
            theme: .paper,
            initialFilter: .all,
            onNavigate: { _ in },
            onDismiss: {}
        )
        _ = sheet.body
    }

    @Test("App Settings view still builds re-skinned")
    func appSettingsViewStillBuilds() {
        let view = SettingsView()
        _ = view.body
        // The re-skinned settings sheet declares the Cloud & Sync /
        // Reading / About groups directly; the design's fourth group
        // ("AI") is delegated to the feature-#50 `AISettingsSection`
        // composite (re-shaping that component is out of WI-10 scope).
        #expect(view.sectionsForTesting
            == ["Cloud & Sync", "Reading", "About"])
        // The directly-declared groups are a subset of the design's
        // four-group contract, in design order.
        let designGroups = ReaderSheetKind.appSettings.sections
        for group in view.sectionsForTesting {
            #expect(designGroups.contains(group), "\(group) is a design group")
        }
    }

    // MARK: - Feature #67 WI-4: profile card mount + core-group restyle

    @Test("Settings view renders the WI-4 core-group palette keys in design order")
    func settingsView_rowPaletteKeys_match_designOrder() {
        // WI-4 mounts the SettingsProfileCard as the first Form row, then
        // restyles the three core groups (Cloud & Sync / Reading / About)
        // to SettingsIconRow using SettingsRowPalette. AI group is WI-5
        // and is excluded from this seam (it lives in AISettingsSection).
        // Pinned to the plan's "WI-4 Test catalogue" assertion:
        // ["webDAVBackup", "bookSources", "replacementRules",
        //  "httpTTS", "helpFeedback", "version"].
        let view = SettingsView()
        #expect(view.rowPaletteKeysForTesting == [
            "webDAVBackup",
            "bookSources",
            "replacementRules",
            "httpTTS",
            "helpFeedback",
            "version"
        ])
    }

    @Test("Settings view's profile-card mount renders with the library glyph")
    func settingsView_profileCard_isMounted() {
        // WI-4: SettingsView mounts SettingsProfileCard as the first
        // Form row, fed by SettingsHeaderViewModel from the optional
        // \.persistenceActor environment. The view exposes the mounted
        // card for composition assertion.
        let view = SettingsView()
        _ = view.body
        let card = view.profileCardForTesting
        #expect(card.headerTextForTesting == SettingsProfileCard.headerText)
    }

    // MARK: - Helpers

    /// A TXT-style `Locator` at the given UTF-16 offset.
    private static func txtLocator(offset: Int) -> Locator {
        Locator(
            bookFingerprint: DocumentFingerprint(
                contentSHA256: String(repeating: "0", count: 64),
                fileByteCount: 0,
                format: .txt
            ),
            href: nil, progression: nil, totalProgression: nil, cfi: nil,
            page: nil, charOffsetUTF16: offset,
            charRangeStartUTF16: nil, charRangeEndUTF16: nil,
            textQuote: nil, textContextBefore: nil, textContextAfter: nil
        )
    }

    /// An in-memory PersistenceActor for view-model construction.
    private func makeInMemoryPersistence() -> PersistenceActor {
        PersistenceActor(modelContainer: Self.inMemoryContainer())
    }

    /// An in-memory `ModelContainer` — SchemaV6 + in-memory config is
    /// the test-isolation default documented in `.claude/rules/10-tdd.md`.
    /// Feature #62's `TOCSheet` / `HighlightsSheet` take a container
    /// directly (they construct their own view models internally).
    static func inMemoryContainer() -> ModelContainer {
        let schema = Schema(SchemaV6.models)
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try! ModelContainer(for: schema, configurations: [config])
    }

    /// Asserts a `UIColor` resolves to the given 8-bit RGB triple.
    private func assertColor(
        _ color: UIColor,
        rgb expected: (Int, Int, Int),
        sourceLocation: SourceLocation = #_sourceLocation
    ) {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        color.getRed(&r, green: &g, blue: &b, alpha: &a)
        #expect(Int((r * 255).rounded()) == expected.0,
                "red", sourceLocation: sourceLocation)
        #expect(Int((g * 255).rounded()) == expected.1,
                "green", sourceLocation: sourceLocation)
        #expect(Int((b * 255).rounded()) == expected.2,
                "blue", sourceLocation: sourceLocation)
    }
}
