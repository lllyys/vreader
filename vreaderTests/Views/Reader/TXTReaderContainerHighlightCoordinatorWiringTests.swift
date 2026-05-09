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
        // The chapter path (chapterReaderContent) intentionally hardcodes []
        // because chapter-local offset translation is WI-7.
        let required = "persistedHighlights: uiState.persistedHighlightRanges"
        let occurrences = source.components(separatedBy: required).count - 1
        #expect(
            occurrences >= 2,
            "TXTReaderContainerView must pass `uiState.persistedHighlightRanges` to TXTTextViewBridge in BOTH the small-file (readerContent) and chunked (chunkedReaderContent) paths. Found \(occurrences) occurrence(s); expected ≥ 2. See bug #160 / GH #476."
        )
    }
}
