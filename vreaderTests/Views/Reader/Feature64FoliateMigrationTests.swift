// Purpose: Feature #64 WI-9 — guards the migration of the Foliate (AZW3/MOBI)
// reader container from feature #55's `notePreviewPresenterIfAvailable` (the
// read-only note preview) to the unified highlight-action popover's
// `unifiedHighlightPopoverPresenterIfAvailable`.
//
// WI-9's behavioral change: a *tap* on an existing AZW3/MOBI highlight opens
// the unified highlight-action popover (color / note / copy / share / delete)
// — NOT feature #55's read-only note callout. The Foliate highlight tap
// arrives from the JS `foliateHighlightTapHandler`, which posts
// `.readerHighlightTapped` (the unified popover's trigger, unchanged).
//
// Foliate has no `HighlightRenderer` conformer, so — unlike WI-6/7/8 — it
// cannot pass a `HighlightCoordinator` as the popover's `mutating:` boundary.
// WI-9 introduces `FoliateHighlightMutator` (a `HighlightMutating` conformer
// composing `HighlightPersisting` + `FoliateHighlightJSBridge`); the Foliate
// container passes that as `mutating:`. This source-grep test fences the WI-9
// migration of `FoliateSpikeView`; the end-to-end behavior (tap → unified
// popover) is exercised at Gate 5 device verification.

#if canImport(UIKit)
import Testing
import Foundation
@testable import vreader

@Suite("Feature #64 WI-9 — Foliate container migration")
@MainActor
struct Feature64FoliateMigrationTests {

    /// Repo root resolved by walking up from this test file:
    /// `vreaderTests/Views/Reader/` → repo root.
    private static func foliateContainerSource(testFilePath: String = #filePath) throws -> String {
        let repoRoot = URL(fileURLWithPath: testFilePath)
            .deletingLastPathComponent()  // Reader/
            .deletingLastPathComponent()  // Views/
            .deletingLastPathComponent()  // vreaderTests/
            .deletingLastPathComponent()  // repo root
        let url = repoRoot
            .appendingPathComponent("vreader/Views/Reader/FoliateSpikeView.swift")
        return try String(contentsOf: url, encoding: .utf8)
    }

    @Test("Foliate container attaches the unified popover, not feature #55's note preview")
    func foliateAttachesUnifiedHighlightPopoverPresenter() throws {
        let source = try Self.foliateContainerSource()
        #expect(
            source.contains("unifiedHighlightPopoverPresenterIfAvailable"),
            "FoliateSpikeView must attach `unifiedHighlightPopoverPresenterIfAvailable` (feature #64 WI-9)."
        )
        #expect(
            !source.contains("notePreviewPresenterIfAvailable"),
            "FoliateSpikeView must no longer attach `notePreviewPresenterIfAvailable` — superseded by the unified popover (feature #64 WI-9)."
        )
    }

    @Test("Foliate container passes a FoliateHighlightMutator as the mutating boundary")
    func foliatePassesFoliateHighlightMutatorAsMutating() throws {
        let source = try Self.foliateContainerSource()
        // Pin the plan-critical `mutating:` boundary — the unified popover's
        // color / note / delete actions are inert if `mutating` regresses to
        // `nil`. Foliate has no `HighlightRenderer`, so its `HighlightMutating`
        // is the WI-9 `FoliateHighlightMutator` (persistence + JS bridge), not
        // a `HighlightCoordinator`.
        #expect(
            source.contains("FoliateHighlightMutator"),
            "FoliateSpikeView must build a `FoliateHighlightMutator` as the unified popover's `mutating:` boundary (feature #64 WI-9)."
        )
        #expect(
            source.contains("mutating:"),
            "FoliateSpikeView must pass a `mutating:` boundary to the unified popover (feature #64 WI-9)."
        )
    }
}
#endif
