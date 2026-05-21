// Purpose: Tests for DebugPresentSheetEffect — the pure mapping from a
// DebugBridge `present` command's (SheetKind, tab) to the reader-host
// presentation effect (Bug #253 verification harness). Pins the fidelity
// invariant: the effect resolves to the SAME `annotationsRoute` /
// `showAIPanel` / `showSettings` the production chrome buttons set, so the
// harness exercises the real presentation path (no parallel logic).

#if DEBUG

import XCTest
@testable import vreader

final class DebugPresentSheetEffectTests: XCTestCase {

    // MARK: - toc → AnnotationsSheetRoute.toc

    func test_resolve_tocNoTab_defaultsToContents() {
        let effect = DebugPresentSheetEffect.resolve(sheet: .toc, tab: nil)
        XCTAssertEqual(effect, .annotations(.toc(initialTab: .contents)))
    }

    func test_resolve_tocContents_routesToContentsTab() {
        let effect = DebugPresentSheetEffect.resolve(sheet: .toc, tab: "contents")
        XCTAssertEqual(effect, .annotations(.toc(initialTab: .contents)))
    }

    func test_resolve_tocBookmarks_routesToBookmarksTab() {
        let effect = DebugPresentSheetEffect.resolve(sheet: .toc, tab: "bookmarks")
        XCTAssertEqual(effect, .annotations(.toc(initialTab: .bookmarks)))
    }

    // MARK: - highlights → AnnotationsSheetRoute.highlights

    func test_resolve_highlightsNoTab_defaultsToAll() {
        let effect = DebugPresentSheetEffect.resolve(sheet: .highlights, tab: nil)
        XCTAssertEqual(effect, .annotations(.highlights(initialFilter: .all)))
    }

    func test_resolve_highlightsEachFilter_routesToFilter() {
        let cases: [(String, HighlightsSheetFilter)] = [
            ("all", .all),
            ("highlights", .highlights),
            ("notes", .notes),
            ("bookmarks", .bookmarks),
        ]
        for (raw, expected) in cases {
            let effect = DebugPresentSheetEffect.resolve(sheet: .highlights, tab: raw)
            XCTAssertEqual(effect, .annotations(.highlights(initialFilter: expected)),
                           "highlights filter \(raw) must route to \(expected)")
        }
    }

    // MARK: - ai → showAIPanel + aiInitialTab

    func test_resolve_aiNoTab_defaultsToSummarize() {
        let effect = DebugPresentSheetEffect.resolve(sheet: .ai, tab: nil)
        XCTAssertEqual(effect, .ai(initialTab: .summarize))
    }

    func test_resolve_aiEachTab_routesToTab() {
        let cases: [(String, AIReaderTab)] = [
            ("summarize", .summarize),
            ("translate", .translate),
            ("chat", .chat),
        ]
        for (raw, expected) in cases {
            let effect = DebugPresentSheetEffect.resolve(sheet: .ai, tab: raw)
            XCTAssertEqual(effect, .ai(initialTab: expected),
                           "AI tab \(raw) must route to \(expected)")
        }
    }

    // MARK: - settings → showSettings

    func test_resolve_settings_routesToSettings() {
        let effect = DebugPresentSheetEffect.resolve(sheet: .settings, tab: nil)
        XCTAssertEqual(effect, .settings)
    }

    // MARK: - bookmarks → TOC sheet on Bookmarks tab

    func test_resolve_bookmarks_routesToTOCBookmarksTab() {
        // `bookmarks` is a top-level alias presenting the TOC sheet's
        // Bookmarks tab (the "leave the page" navigation surface).
        let effect = DebugPresentSheetEffect.resolve(sheet: .bookmarks, tab: nil)
        XCTAssertEqual(effect, .annotations(.toc(initialTab: .bookmarks)))
    }

    // MARK: - exhaustiveness

    func test_resolve_everySheetKind_resolvesToAnEffect() {
        // No SheetKind falls through to a nil/crash — every case maps.
        for kind in DebugCommand.SheetKind.allCases {
            _ = DebugPresentSheetEffect.resolve(sheet: kind, tab: nil)
        }
    }
}

#endif
