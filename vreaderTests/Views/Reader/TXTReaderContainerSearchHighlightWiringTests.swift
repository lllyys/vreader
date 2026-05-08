// Bug #154 / GH #443 — regression guard for the search-tap highlight wiring.
//
// The bug: TXTReaderContainerView declared an orphan `@State private var
// highlightRange: NSRange?` that was passed to TXTTextViewBridge but never
// assigned anywhere. ReaderNotificationModifier's `.readerNavigateToLocator`
// handler writes to `uiState.highlightRange` (TextReaderUIState), but the
// bridge instantiations read from the orphan local @State, so the temporary
// yellow highlight never rendered for TXT search-tap navigation.
//
// MDReaderContainerView.swift:312 was correctly wired (`uiState.highlightRange`).
// Only TXT regressed.
//
// This test pins the wiring at the source-text level: the bridge instantiations
// must read from `uiState.highlightRange` / `uiState.highlightIsTemporary`,
// and the orphan local @State declarations must NOT be re-introduced.

import Testing
import Foundation

@Suite("TXTReaderContainer Search Highlight Wiring (Bug #154)")
struct TXTReaderContainerSearchHighlightWiringTests {

    // Use #filePath to anchor at this test's compile-time location, then walk
    // up to the repo root and into the production source. ProcessInfo SRCROOT
    // isn't reliably set at simulator runtime, but #filePath is a literal baked
    // in at compile time.
    private static func loadContainerSource(testFilePath: String = #filePath) throws -> String {
        let testURL = URL(fileURLWithPath: testFilePath)
        // testFilePath = .../vreader/vreaderTests/Views/Reader/TXTReaderContainerSearchHighlightWiringTests.swift
        // Walk up 4 levels (file → Reader → Views → vreaderTests) to reach the repo root.
        let repoRoot = testURL
            .deletingLastPathComponent() // Reader/
            .deletingLastPathComponent() // Views/
            .deletingLastPathComponent() // vreaderTests/
            .deletingLastPathComponent() // repo root
        let sourceURL = repoRoot
            .appendingPathComponent("vreader/Views/Reader/TXTReaderContainerView.swift")
        return try String(contentsOf: sourceURL, encoding: .utf8)
    }

    @Test func orphanLocalHighlightRangeStateIsRemoved() throws {
        let source = try Self.loadContainerSource()
        // The orphan declaration that broke search-tap highlight rendering.
        // Either form (with type annotation) of an unassigned local @State
        // for highlightRange is forbidden — uiState.highlightRange is the
        // single source of truth.
        let banned = "@State private var highlightRange: NSRange?"
        #expect(
            !source.contains(banned),
            "TXTReaderContainerView must not re-introduce an orphan local `@State private var highlightRange`. Use `uiState.highlightRange` (set by ReaderNotificationModifier) instead. See bug #154 / GH #443."
        )
    }

    @Test func orphanLocalHighlightIsTemporaryStateIsRemoved() throws {
        let source = try Self.loadContainerSource()
        let banned = "@State private var highlightIsTemporary: Bool"
        #expect(
            !source.contains(banned),
            "TXTReaderContainerView must not re-introduce an orphan local `@State private var highlightIsTemporary`. Use `uiState.highlightIsTemporary` instead. See bug #154 / GH #443."
        )
    }

    @Test func bridgeWiringReadsHighlightFromUIState() throws {
        let source = try Self.loadContainerSource()
        // Both the small-file path (`readerContent`) and the large-file
        // chunked path (`chunkedReaderContent`) must read from uiState. The
        // chapter path (WI-7) intentionally hardcodes nil — that's a separate
        // concern tracked by its own comment in the file.
        let required = "highlightRange: uiState.highlightRange"
        let occurrences = source.components(separatedBy: required).count - 1
        #expect(
            occurrences >= 2,
            "TXTReaderContainerView must pass `uiState.highlightRange` to TXTTextViewBridge in BOTH the small-file (readerContent) and large-file (chunkedReaderContent) paths. Found \(occurrences) occurrence(s); expected ≥ 2. See bug #154 / GH #443."
        )
    }

    @Test func bridgeWiringReadsHighlightTemporaryFromUIState() throws {
        let source = try Self.loadContainerSource()
        let required = "highlightIsTemporary: uiState.highlightIsTemporary"
        let occurrences = source.components(separatedBy: required).count - 1
        #expect(
            occurrences >= 2,
            "TXTReaderContainerView must pass `uiState.highlightIsTemporary` to TXTTextViewBridge in BOTH the small-file and chunked paths. Found \(occurrences) occurrence(s); expected ≥ 2. See bug #154 / GH #443."
        )
    }

}
