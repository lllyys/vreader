// Purpose: Feature #64 WI-7 — guards the migration of the PDF reader
// container from feature #55's `notePreviewPresenterIfAvailable` (the
// read-only note preview) to the unified highlight-action popover's
// `unifiedHighlightPopoverPresenterIfAvailable`, and the removal of the
// feature #53 highlight long-press `UIMenu` from `PDFViewBridge`.
//
// WI-7's behavioral change mirrors WI-6 (TXT/MD): a *tap* on an existing
// PDF highlight annotation posts `.readerHighlightTapped`, which the unified
// popover observes. The feature #53 long-press `present(...)` path is removed
// from `PDFViewBridge` — `PDFViewBridge` no longer registers the highlight
// `UILongPressGestureRecognizer`, no longer has `handleHighlightLongPress`,
// and no longer carries the `highlightActionPresenter` / `onHighlightTapAction`
// wiring.
//
// `PDFViewBridge.Coordinator.handleTap` resolving a tap to a highlight is the
// kept trigger — its pure hit-test core is `PDFHighlightTapResolver`
// (`PDFHighlightTapResolverTests`). These source-grep tests fence the WI-7
// migration of the two production files the WI touches; the end-to-end
// behavior (tap → unified popover) is exercised at Gate 5 device verification.
//
// Supersedes `PDFHighlightLongPressGateTests.swift` (deleted in WI-7): that
// file preserved the PDF long-press gate coverage carried over from WI-6's
// deleted `Feature55NativeWiringTests`; WI-7 removes the gated production code,
// so the gate tests retire with it.

#if canImport(UIKit)
import Testing
import Foundation
@testable import vreader

@Suite("Feature #64 WI-7 — PDF container migration")
@MainActor
struct Feature64PDFMigrationTests {

    // MARK: - Source-wiring guards

    /// Repo root resolved by walking up from this test file:
    /// `vreaderTests/Views/Reader/` → repo root.
    private static func repoRoot(testFilePath: String = #filePath) -> URL {
        URL(fileURLWithPath: testFilePath)
            .deletingLastPathComponent()  // Reader/
            .deletingLastPathComponent()  // Views/
            .deletingLastPathComponent()  // vreaderTests/
            .deletingLastPathComponent()  // repo root
    }

    private static func pdfContainerSource() throws -> String {
        let url = repoRoot()
            .appendingPathComponent("vreader/Views/Reader/PDFReaderContainerView.swift")
        return try String(contentsOf: url, encoding: .utf8)
    }

    private static func pdfBridgeSource() throws -> String {
        let url = repoRoot()
            .appendingPathComponent("vreader/Views/Reader/PDFViewBridge.swift")
        return try String(contentsOf: url, encoding: .utf8)
    }

    // MARK: - Container migration

    @Test("PDF container attaches the unified popover, not feature #55's note preview")
    func pdfAttachesUnifiedHighlightPopoverPresenter() throws {
        let source = try Self.pdfContainerSource()
        #expect(
            source.contains("unifiedHighlightPopoverPresenterIfAvailable"),
            "PDFReaderContainerView must attach `unifiedHighlightPopoverPresenterIfAvailable` (feature #64 WI-7)."
        )
        #expect(
            !source.contains("notePreviewPresenterIfAvailable"),
            "PDFReaderContainerView must no longer attach `notePreviewPresenterIfAvailable` — superseded by the unified popover (feature #64 WI-7)."
        )
        // Pin the plan-critical `mutating:` boundary — the unified popover's
        // color / note / delete actions are inert if `mutating` regresses to
        // `nil` or the wrong object. The PDF container's `HighlightMutating`
        // is its `HighlightCoordinator`.
        #expect(
            source.contains("mutating: highlightCoordinator"),
            "PDFReaderContainerView must pass `mutating: highlightCoordinator` to the unified popover (feature #64 WI-7)."
        )
    }

    @Test("PDF container removed the feature #53 long-press UIMenu bridge wiring")
    func pdfContainerFeature53WiringRemoved() throws {
        let source = try Self.pdfContainerSource()
        #expect(
            !source.contains("highlightActionPresenter:"),
            "PDFReaderContainerView must no longer pass `highlightActionPresenter:` to PDFViewBridge (feature #64 WI-7)."
        )
        #expect(
            !source.contains("onHighlightTapAction:"),
            "PDFReaderContainerView must no longer pass `onHighlightTapAction:` to PDFViewBridge (feature #64 WI-7)."
        )
    }

    // MARK: - Bridge migration

    @Test("PDFViewBridge removed the feature #53 highlight long-press machinery")
    func pdfBridgeLongPressMachineryRemoved() throws {
        let source = try Self.pdfBridgeSource()
        #expect(
            !source.contains("handleHighlightLongPress"),
            "PDFViewBridge must no longer have `handleHighlightLongPress` — the long-press `UIMenu` is replaced by the unified popover (feature #64 WI-7)."
        )
        #expect(
            !source.contains("highlightActionPresenter"),
            "PDFViewBridge must no longer carry the `highlightActionPresenter` property (feature #64 WI-7)."
        )
        #expect(
            !source.contains("onHighlightTapAction"),
            "PDFViewBridge must no longer carry the `onHighlightTapAction` property (feature #64 WI-7)."
        )
        #expect(
            !source.contains("highlightLongPressName"),
            "PDFViewBridge must no longer register the named highlight `UILongPressGestureRecognizer` (feature #64 WI-7)."
        )
    }

    @Test("PDFViewBridge keeps the tap path that posts .readerHighlightTapped")
    func pdfBridgeKeepsReaderHighlightTappedTrigger() throws {
        let source = try Self.pdfBridgeSource()
        // The tap → highlight hit-test → `.readerHighlightTapped` post is the
        // unified popover's trigger — WI-7 must keep it (only the long-press
        // delete `UIMenu` is removed).
        #expect(
            source.contains(".readerHighlightTapped"),
            "PDFViewBridge.Coordinator.handleTap must still post `.readerHighlightTapped` — the unified popover's trigger (feature #64 WI-7)."
        )
        #expect(
            source.contains("resolveHighlightTapEvent"),
            "PDFViewBridge must keep `resolveHighlightTapEvent` — the hit-test feeding `.readerHighlightTapped` (feature #64 WI-7)."
        )
    }
}
#endif
