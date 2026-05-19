// Bug #160 / GH #476 — regression guard for TXT highlight coordinator wiring.
//
// The bug: TXTReaderContainerView declared `highlightCoordinator` and
// `highlightRenderer` as @State but never assigned them. The fallback
// `makeNoOpCoordinator()` (using NoOpHighlightStore) was always used, so
// every gesture-driven highlight was silently dropped — menu dismissed,
// no DB row, no yellow paint, Highlights tab stayed empty.
//
// MDReaderContainerView's `.task` block wires both immediately:
//   let renderer = TextHighlightRenderer(uiState: uiState)
//   highlightRenderer = renderer
//   ...
//   let coordinator = HighlightCoordinator(renderer: renderer, ...)
//   highlightCoordinator = coordinator
//
// TXT was missing both assignments. Additionally, TXT used a local
// `@State persistedHighlightRanges` array (loaded manually in .task)
// that diverged from the renderer's writes to `uiState.persistedHighlightRanges`.
// New highlights would have written to uiState but the bridge read the
// orphan local array — so even a wired coordinator would not paint.
//
// This test pins the wiring at the source-text level. Pattern mirrors
// `TXTReaderContainerSearchHighlightWiringTests.swift` (bug #154).

import Testing
import Foundation

@Suite("TXTReaderContainer Highlight Coordinator Wiring (Bug #160)")
struct TXTReaderContainerHighlightCoordinatorWiringTests {

    private static func loadContainerSource(testFilePath: String = #filePath) throws -> String {
        let testURL = URL(fileURLWithPath: testFilePath)
        let repoRoot = testURL
            .deletingLastPathComponent() // Reader/
            .deletingLastPathComponent() // Views/
            .deletingLastPathComponent() // vreaderTests/
            .deletingLastPathComponent() // repo root
        let sourceURL = repoRoot
            .appendingPathComponent("vreader/Views/Reader/TXTReaderContainerView.swift")
        return try String(contentsOf: sourceURL, encoding: .utf8)
    }

    @Test func taskBlockAssignsHighlightRenderer() throws {
        let source = try Self.loadContainerSource()
        // Mirror MD's pattern at MDReaderContainerView.swift:109-110:
        //   let renderer = TextHighlightRenderer(uiState: uiState)
        //   highlightRenderer = renderer
        // The exact form is what we pin — the assignment must exist somewhere.
        let assignment = "highlightRenderer = renderer"
        let instantiation = "TextHighlightRenderer(uiState: uiState)"
        #expect(
            source.contains(assignment),
            "TXTReaderContainerView must assign `highlightRenderer = renderer` in its .task block, mirroring MDReaderContainerView. See bug #160 / GH #476."
        )
        #expect(
            source.contains(instantiation),
            "TXTReaderContainerView must instantiate `TextHighlightRenderer(uiState: uiState)` in its .task block. See bug #160 / GH #476."
        )
    }

    @Test func taskBlockAssignsHighlightCoordinator() throws {
        let source = try Self.loadContainerSource()
        // The coordinator assignment is what makes gesture-driven highlights
        // reach the real PersistenceActor instead of NoOpHighlightStore.
        let assignment = "highlightCoordinator = coordinator"
        let instantiation = "HighlightCoordinator("
        #expect(
            source.contains(assignment),
            "TXTReaderContainerView must assign `highlightCoordinator = coordinator` in its .task block. Without this, makeNoOpCoordinator() is always used and gesture-driven highlights never persist. See bug #160 / GH #476."
        )
        #expect(
            source.contains(instantiation),
            "TXTReaderContainerView must instantiate `HighlightCoordinator(...)` in its .task block. See bug #160 / GH #476."
        )
    }

    @Test func orphanLocalPersistedHighlightRangesStateIsRemoved() throws {
        let source = try Self.loadContainerSource()
        // The orphan @State array that diverged from uiState.persistedHighlightRanges.
        // The renderer writes to uiState; the bridge must read from uiState too.
        let banned = "@State private var persistedHighlightRanges: [NSRange]"
        #expect(
            !source.contains(banned),
            "TXTReaderContainerView must not re-introduce orphan `@State private var persistedHighlightRanges`. Use `uiState.persistedHighlightRanges` (written by TextHighlightRenderer.apply / .restore) as the single source of truth. See bug #160 / GH #476."
        )
    }

    @Test func bridgeReadsPersistedHighlightsFromUIState() throws {
        let source = try Self.loadContainerSource()
        // Both small-file (readerContent) and chunked (chunkedReaderContent)
        // bridge instantiations must read `uiState.persistedHighlightRanges`.
        // Chapter path (chapterReaderContent) translates global ranges to
        // chapter-local via `chapterLocalHighlightRanges` (returns
        // `highlights.persisted`) — that translation path is exercised by
        // `chapterPassesPersistedHighlightLookup` below.
        let required = "persistedHighlights: uiState.persistedHighlightRanges"
        let occurrences = source.components(separatedBy: required).count - 1
        #expect(
            occurrences >= 2,
            "TXTReaderContainerView must pass `uiState.persistedHighlightRanges` to TXTTextViewBridge in BOTH the small-file (readerContent) and chunked (chunkedReaderContent) paths. Found \(occurrences) occurrence(s); expected ≥ 2. See bug #160 / GH #476."
        )
    }

    /// Feature #64 WI-6: the TXT container migrated from feature #55's
    /// `notePreviewPresenterIfAvailable` to the unified highlight-action
    /// popover's `unifiedHighlightPopoverPresenterIfAvailable`. The old
    /// feature #53 long-press `UIMenu` wiring (`highlightActionPresenter:` +
    /// `onHighlightTapAction:` passed to `TXTTextViewBridge`) is removed —
    /// a *tap* on a highlight now opens the unified popover. These
    /// source-check tests pin the migrated wiring so a refactor cannot
    /// regress it.

    @Test func attachesUnifiedHighlightPopoverPresenter() throws {
        let source = try Self.loadContainerSource()
        // The TXT container must attach the feature #64 unified popover.
        #expect(
            source.contains("unifiedHighlightPopoverPresenterIfAvailable"),
            "TXTReaderContainerView must attach `unifiedHighlightPopoverPresenterIfAvailable` (feature #64 WI-6). A tap on a highlight opens the unified highlight-action popover."
        )
        // And must NOT still attach feature #55's superseded note preview.
        #expect(
            !source.contains("notePreviewPresenterIfAvailable"),
            "TXTReaderContainerView must no longer attach `notePreviewPresenterIfAvailable` — feature #55's note preview is superseded by the unified popover (feature #64 WI-6)."
        )
    }

    @Test func feature53LongPressMenuWiringRemoved() throws {
        let source = try Self.loadContainerSource()
        // Feature #64 WI-6 removes the #53 long-press UIMenu wiring from the
        // TXT bridge call sites — the unified popover's action row carries
        // Delete, opened by a tap.
        #expect(
            !source.contains("highlightActionPresenter:"),
            "TXTReaderContainerView must no longer pass `highlightActionPresenter:` to TXTTextViewBridge — the feature #53 long-press delete menu is superseded by the unified popover (feature #64 WI-6)."
        )
        #expect(
            !source.contains("onHighlightTapAction:"),
            "TXTReaderContainerView must no longer pass `onHighlightTapAction:` to TXTTextViewBridge (feature #64 WI-6)."
        )
    }

    @Test func chapterPassesPersistedHighlightLookup() throws {
        let source = try Self.loadContainerSource()
        // Small-file + chunked use `persistedHighlightLookup: uiState.persistedHighlightLookup`.
        // Chapter mode uses the chapter-local translation `highlights.lookup` from the
        // `chapterLocalHighlightRanges`-equivalent helper that returns the lookup too.
        // So the parameter LABEL must appear in 3 places (one of which may use a
        // different RHS).
        let label = "persistedHighlightLookup:"
        let occurrences = source.components(separatedBy: label).count - 1
        #expect(
            occurrences >= 3,
            "TXTReaderContainerView must pass `persistedHighlightLookup:` to TXTTextViewBridge in ALL THREE paths. Found \(occurrences) occurrence(s); expected ≥ 3. See bug #202 / GH #740."
        )
    }
}
