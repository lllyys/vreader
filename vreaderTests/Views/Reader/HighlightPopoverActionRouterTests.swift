// Purpose: Feature #64 WI-4 — tests for `HighlightPopoverActionRouter`, the
// `@MainActor @Observable` state + dispatch core of the unified
// highlight-action popover. The SwiftUI `HighlightPopoverModifier` is a thin
// observer of this router; the router holds the popover's `mode` / `noteDraft`
// / `pressedColor` / `shareItem` state and routes every `HighlightPopoverAction`.
//
// Covers the plan §6 `HighlightPopoverModifier` matrix at the testable core:
// changeColor → the mutating boundary's changeColor (or the Foliate bridge);
// saveNote → updateNote; copy → pasteboard; share → shareItem set + popover
// dismissed; requestDelete → mode becomes confirmingDelete; confirmDelete →
// delete; .notFound outcome → dismiss; .failed → stays open, no local
// mutation; cancelEdit → mode back to reading; beginEdit → editing + draft
// seeded from the note; the presenter-owned noteDraft resets on a highlight
// swap.

#if canImport(UIKit)
import Testing
import Foundation
import CoreGraphics
import UIKit
@testable import vreader

// MARK: - Helpers

private let routerFP = DocumentFingerprint(
    contentSHA256: "router_test_sha_0000000000000000000000000000000000000000",
    fileByteCount: 100, format: .epub
)

@MainActor
private func routerContent(
    id: UUID = UUID(), note: String? = nil, color: String = "yellow"
) -> HighlightPopoverContent {
    HighlightPopoverContent(
        id: id, note: note, highlightedText: "the passage", colorName: color,
        createdAt: Date(timeIntervalSince1970: 1), chapter: "Ch. 1",
        sourceRect: CGRect(x: 1, y: 2, width: 30, height: 14), anchor: nil
    )
}

@MainActor
private func routerRecord(
    id: UUID, note: String? = nil, color: String = "pink"
) -> HighlightRecord {
    let locator = Locator.validated(bookFingerprint: routerFP, cfi: "x")!
    return HighlightRecord(
        highlightId: id, locator: locator, anchor: nil, profileKey: "k",
        selectedText: "the passage", color: color, note: note,
        createdAt: Date(timeIntervalSince1970: 1), updatedAt: Date(timeIntervalSince1970: 2)
    )
}

/// A `HighlightMutating` mock recording every call + returning a scripted
/// outcome.
@MainActor
private final class MutatingMock: HighlightMutating {
    var changeColorCalls: [(id: UUID, color: String)] = []
    var updateNoteCalls: [(id: UUID, note: String?)] = []
    var deleteCalls: [UUID] = []
    var colorOutcome: HighlightMutationOutcome = .failed
    var noteOutcome: HighlightMutationOutcome = .failed
    var deleteOutcome: HighlightMutationOutcome = .failed

    func changeColor(highlightID: UUID, to color: String) async -> HighlightMutationOutcome {
        changeColorCalls.append((highlightID, color))
        return colorOutcome
    }

    func updateNote(highlightID: UUID, note: String?) async -> HighlightMutationOutcome {
        updateNoteCalls.append((highlightID, note))
        return noteOutcome
    }

    func deleteHighlight(highlightID: UUID) async -> HighlightMutationOutcome {
        deleteCalls.append(highlightID)
        return deleteOutcome
    }
}

// MARK: - Tests

@Suite("HighlightPopoverActionRouter")
@MainActor
struct HighlightPopoverActionRouterTests {

    private func makeRouter(
        mutating: MutatingMock = MutatingMock()
    ) -> HighlightPopoverActionRouter {
        // The router is format-agnostic — it dispatches every action through
        // one `HighlightMutating` boundary. Non-Foliate formats inject a
        // `HighlightCoordinator`; the Foliate format injects its own
        // `HighlightMutating` conformer (WI-9). The router never branches on
        // format itself.
        HighlightPopoverActionRouter(mutating: mutating)
    }

    // MARK: Mode transitions

    @Test func requestDelete_entersConfirmingDelete() async {
        let router = makeRouter()
        router.present(routerContent())
        await router.route(.requestDelete)
        #expect(router.mode == .confirmingDelete)
    }

    @Test func cancelEdit_returnsToReading() async {
        let router = makeRouter()
        router.present(routerContent(note: "a note"))
        await router.route(.beginEdit)
        #expect(router.mode == .editing)
        await router.route(.cancelEdit)
        #expect(router.mode == .reading)
    }

    @Test func beginEdit_entersEditingAndSeedsDraftFromNote() async {
        let router = makeRouter()
        router.present(routerContent(note: "existing note"))
        await router.route(.beginEdit)
        #expect(router.mode == .editing)
        #expect(router.noteDraft == "existing note")
    }

    @Test func beginEdit_emptyNote_seedsEmptyDraft() async {
        let router = makeRouter()
        router.present(routerContent(note: nil))
        await router.route(.beginEdit)
        #expect(router.noteDraft == "")
    }

    // MARK: Feature #1121 — present(initialMode:)

    @Test func present_defaultInitialModeIsReading() {
        let router = makeRouter()
        router.present(routerContent(note: "a note"))
        #expect(router.mode == .reading)
        #expect(router.noteDraft == "") // reading never seeds a draft
    }

    @Test func present_editingInitialMode_opensEditingAndSeedsDraftFromNote() {
        let router = makeRouter()
        router.present(routerContent(note: "existing note"), initialMode: .editing)
        #expect(router.mode == .editing)
        #expect(router.noteDraft == "existing note") // seeded so the editor is ready
    }

    @Test func present_editingInitialMode_emptyNote_seedsEmptyDraft() {
        let router = makeRouter()
        router.present(routerContent(note: nil), initialMode: .editing)
        #expect(router.mode == .editing)
        #expect(router.noteDraft == "")
    }

    // MARK: changeColor

    @Test func changeColor_success_callsMutatingAndRefreshesContent() async {
        let mutating = MutatingMock()
        let id = UUID()
        mutating.colorOutcome = .success(routerRecord(id: id, color: "green"))
        let router = makeRouter(mutating: mutating)
        router.present(routerContent(id: id, color: "yellow"))

        await router.route(.changeColor(.green))

        #expect(mutating.changeColorCalls.count == 1)
        #expect(mutating.changeColorCalls.first?.color == "green")
        // A success refreshes the on-screen content with the new color.
        #expect(router.content?.colorName == "green")
        #expect(router.isPresented)
    }

    @Test func changeColor_notFound_dismisses() async {
        let mutating = MutatingMock()
        mutating.colorOutcome = .notFound
        let router = makeRouter(mutating: mutating)
        router.present(routerContent())
        await router.route(.changeColor(.blue))
        #expect(!router.isPresented)
    }

    @Test func changeColor_failed_staysOpenContentUnchanged() async {
        let mutating = MutatingMock()
        mutating.colorOutcome = .failed
        let router = makeRouter(mutating: mutating)
        router.present(routerContent(color: "yellow"))
        await router.route(.changeColor(.pink))
        #expect(router.isPresented)
        // A failure makes no local mutation.
        #expect(router.content?.colorName == "yellow")
    }

    // MARK: saveNote

    @Test func saveNote_success_callsUpdateNoteRefreshesAndReturnsToReading() async {
        let mutating = MutatingMock()
        let id = UUID()
        mutating.noteOutcome = .success(routerRecord(id: id, note: "saved note"))
        let router = makeRouter(mutating: mutating)
        router.present(routerContent(id: id, note: nil))
        await router.route(.beginEdit)

        await router.route(.saveNote("saved note"))

        #expect(mutating.updateNoteCalls.count == 1)
        #expect(mutating.updateNoteCalls.first?.note == "saved note")
        #expect(router.content?.note == "saved note")
        // A successful save returns the card to the reading mode.
        #expect(router.mode == .reading)
    }

    @Test func saveNote_failed_staysInEditing() async {
        let mutating = MutatingMock()
        mutating.noteOutcome = .failed
        let router = makeRouter(mutating: mutating)
        router.present(routerContent(note: "old"))
        await router.route(.beginEdit)
        await router.route(.saveNote("new draft"))
        // A failed save keeps the editor open so the user can retry.
        #expect(router.mode == .editing)
        #expect(router.isPresented)
    }

    @Test func saveNote_notFound_dismisses() async {
        let mutating = MutatingMock()
        mutating.noteOutcome = .notFound
        let router = makeRouter(mutating: mutating)
        router.present(routerContent())
        await router.route(.beginEdit)
        await router.route(.saveNote("x"))
        #expect(!router.isPresented)
    }

    // MARK: confirmDelete

    @Test func confirmDelete_success_deletesAndDismisses() async {
        let mutating = MutatingMock()
        let id = UUID()
        mutating.deleteOutcome = .success(routerRecord(id: id))
        let router = makeRouter(mutating: mutating)
        router.present(routerContent(id: id))
        await router.route(.requestDelete)
        await router.route(.confirmDelete)
        #expect(mutating.deleteCalls == [id])
        #expect(!router.isPresented)
    }

    /// A concurrent-deletion race (`.notFound`) on confirmDelete also
    /// dismisses — the highlight no longer exists.
    @Test func confirmDelete_notFound_dismisses() async {
        let mutating = MutatingMock()
        mutating.deleteOutcome = .notFound
        let router = makeRouter(mutating: mutating)
        router.present(routerContent())
        await router.route(.requestDelete)
        await router.route(.confirmDelete)
        #expect(!router.isPresented)
    }

    /// A genuine persistence failure on confirmDelete keeps the popover and
    /// returns the card to the reading mode out of the confirm sub-state.
    @Test func confirmDelete_failed_staysOpenReturnsToReading() async {
        let mutating = MutatingMock()
        mutating.deleteOutcome = .failed
        let router = makeRouter(mutating: mutating)
        router.present(routerContent())
        await router.route(.requestDelete)
        #expect(router.mode == .confirmingDelete)
        await router.route(.confirmDelete)
        #expect(router.isPresented)
        #expect(router.mode == .reading)
    }

    // MARK: copy & share

    @Test func copy_putsExcerptOnPasteboardAndDismisses() async {
        let router = makeRouter()
        router.present(routerContent())
        await router.route(.copy)
        #expect(UIPasteboard.general.string == "the passage")
        #expect(!router.isPresented)
    }

    @Test func share_setsPendingShareTextWithExcerptAndDismisses() async {
        let router = makeRouter()
        router.present(routerContent())
        await router.route(.share)
        // The router records the share text; the modifier consumes it AFTER
        // the popover surface has dismissed (so two modals never stack).
        #expect(router.pendingShareText == "the passage")
        #expect(!router.isPresented)
    }

    @Test func clearPendingShare_clearsTheText() async {
        let router = makeRouter()
        router.present(routerContent())
        await router.route(.share)
        #expect(router.pendingShareText != nil)
        router.clearPendingShare()
        #expect(router.pendingShareText == nil)
    }

    // MARK: presenter-owned draft reset on a highlight swap

    @Test func present_differentHighlight_resetsDraftAndMode() async {
        let router = makeRouter()
        router.present(routerContent(id: UUID(), note: "first note"))
        await router.route(.beginEdit)
        router.updateDraft("a half-typed edit")
        #expect(router.noteDraft == "a half-typed edit")

        // A rapid second tap on a DIFFERENT highlight must not carry the
        // stale draft or the editing mode.
        router.present(routerContent(id: UUID(), note: "second note"))
        #expect(router.mode == .reading)
        #expect(router.noteDraft == "")
    }

    @Test func dismiss_clearsPresentedAndResetsState() async {
        let router = makeRouter()
        router.present(routerContent(note: "n"))
        await router.route(.beginEdit)
        router.dismiss()
        #expect(!router.isPresented)
        #expect(router.content == nil)
        #expect(router.mode == .reading)
    }
}
#endif
