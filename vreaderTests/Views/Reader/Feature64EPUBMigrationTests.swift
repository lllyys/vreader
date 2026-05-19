// Purpose: Feature #64 WI-8 — guards the migration of the EPUB reader
// container from feature #55's `notePreviewPresenterIfAvailable` (the
// read-only note preview) to the unified highlight-action popover's
// `unifiedHighlightPopoverPresenterIfAvailable`.
//
// WI-8's behavioral change: a *tap* on an existing EPUB highlight opens the
// unified highlight-action popover (color / note / copy / share / delete) —
// NOT feature #55's read-only note callout. The EPUB highlight tap arrives
// from the JS `highlightTapHandler` channel; `EPUBWebViewBridgeCoordinator`
// posts `.readerHighlightTapped`, which the unified popover observes (the
// same trigger feature #55 used). EPUB never carried feature #53's long-press
// `UIMenu` (feature #55 already removed it for the web host), so — unlike
// WI-6/WI-7 — there is no `highlightActionPresenter` / `onHighlightTapAction`
// bridge wiring to strip; WI-8 is purely the attach swap.
//
// This source-grep test fences the WI-8 migration of `EPUBReaderContainerView`;
// the end-to-end behavior (tap → unified popover) is exercised at Gate 5
// device verification.

#if canImport(UIKit)
import Testing
import Foundation
@testable import vreader

@Suite("Feature #64 WI-8 — EPUB container migration")
@MainActor
struct Feature64EPUBMigrationTests {

    /// Repo root resolved by walking up from this test file:
    /// `vreaderTests/Views/Reader/` → repo root.
    private static func epubContainerSource(testFilePath: String = #filePath) throws -> String {
        let repoRoot = URL(fileURLWithPath: testFilePath)
            .deletingLastPathComponent()  // Reader/
            .deletingLastPathComponent()  // Views/
            .deletingLastPathComponent()  // vreaderTests/
            .deletingLastPathComponent()  // repo root
        let url = repoRoot
            .appendingPathComponent("vreader/Views/Reader/EPUBReaderContainerView.swift")
        return try String(contentsOf: url, encoding: .utf8)
    }

    @Test("EPUB container attaches the unified popover, not feature #55's note preview")
    func epubAttachesUnifiedHighlightPopoverPresenter() throws {
        let source = try Self.epubContainerSource()
        #expect(
            source.contains("unifiedHighlightPopoverPresenterIfAvailable"),
            "EPUBReaderContainerView must attach `unifiedHighlightPopoverPresenterIfAvailable` (feature #64 WI-8)."
        )
        #expect(
            !source.contains("notePreviewPresenterIfAvailable"),
            "EPUBReaderContainerView must no longer attach `notePreviewPresenterIfAvailable` — superseded by the unified popover (feature #64 WI-8)."
        )
    }

    @Test("EPUB container passes its HighlightCoordinator as the mutating boundary")
    func epubPassesHighlightCoordinatorAsMutating() throws {
        let source = try Self.epubContainerSource()
        // Pin the plan-critical `mutating:` boundary — the unified popover's
        // color / note / delete actions are inert if `mutating` regresses to
        // `nil` or the wrong object. EPUB's `HighlightMutating` is its
        // `HighlightCoordinator` (over `EPUBHighlightRenderer`).
        #expect(
            source.contains("mutating: highlightCoordinator"),
            "EPUBReaderContainerView must pass `mutating: highlightCoordinator` to the unified popover (feature #64 WI-8)."
        )
    }
}
#endif
