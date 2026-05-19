// Purpose: Feature #64 WI-4 — `HighlightPopoverActionRouter`, the
// `@MainActor @Observable` state + dispatch core of the unified
// highlight-action popover.
//
// The SwiftUI `HighlightPopoverModifier` is a thin observer of this router:
// the router owns the popover's interaction state (`content`, `mode`,
// `noteDraft`, `pressedColor`, `shareItem`) and routes every
// `HighlightPopoverAction`. Extracting the state + dispatch into an
// `@Observable` class — instead of burying it in a `ViewModifier` body — makes
// the whole action contract unit-testable with no SwiftUI render scaffolding
// (the same rationale as feature #60's `SelectionPopoverActionRouter`).
//
// Key decisions:
// - Format-agnostic: every mutation routes through ONE `HighlightMutating`
//   boundary. Non-Foliate formats inject a `HighlightCoordinator`; the Foliate
//   format injects its own `HighlightMutating` conformer (WI-9). The router
//   never branches on format.
// - The note draft is router-owned (`noteDraft`), reset on `present` (a
//   highlight swap) and re-seeded from the note on `beginEdit` (R1-6) — so a
//   rapid second tap never shows the previous highlight's stale draft.
// - `HighlightMutationOutcome` routing (R1-5 / §2.6): `.success` → refresh the
//   on-screen content from the returned record (+ return to reading after a
//   save); `.notFound` → dismiss; `.failed` → stay open, no local mutation.
// - Copy / Share are host-view-independent: Copy writes `UIPasteboard`; Share
//   sets `shareItem` (the modifier presents it via `.sheet(item:)`). Both
//   dismiss the popover first (R2-F7).
//
// @coordinates-with: HighlightCoordinator.swift (HighlightMutating),
//   HighlightPopoverContent.swift, HighlightPopoverMode.swift,
//   HighlightPopoverAction.swift, HighlightPopoverPresenter.swift,
//   HighlightPopoverModifier.swift

#if canImport(UIKit)
import Foundation
import UIKit

/// State + dispatch core of the unified highlight-action popover.
@Observable
@MainActor
final class HighlightPopoverActionRouter {

    /// The popover content currently on screen, or `nil` when dismissed.
    private(set) var content: HighlightPopoverContent?
    /// The card's interaction sub-state.
    private(set) var mode: HighlightPopoverMode = .reading
    /// The router-owned note-editor draft (R1-6 — a controlled value).
    private(set) var noteDraft: String = ""
    /// Transient press feedback on a color circle.
    private(set) var pressedColor: NamedHighlightColor?
    /// Set by a `.share` action — the excerpt text to share. The modifier
    /// observes this, tears the popover down with a real dismiss completion,
    /// and only THEN presents the system share sheet (so two modals never
    /// stack — R2-F7). `nil` ⇒ no share pending.
    private(set) var pendingShareText: String?

    /// True while a popover is presented.
    var isPresented: Bool { content != nil }

    private let mutating: any HighlightMutating

    init(mutating: any HighlightMutating) {
        self.mutating = mutating
    }

    // MARK: - Presentation

    /// Presents (or replaces) the popover for `content`. Always resets the
    /// interaction state: `mode` → `.reading`, `noteDraft` → `""` — so a rapid
    /// second tap on a different highlight never carries the prior highlight's
    /// stale draft or editing mode (R1-6).
    func present(_ content: HighlightPopoverContent) {
        self.content = content
        mode = .reading
        noteDraft = ""
        pressedColor = nil
    }

    /// Dismisses the popover and resets the interaction state.
    func dismiss() {
        content = nil
        mode = .reading
        noteDraft = ""
        pressedColor = nil
    }

    /// Updates the router-owned draft as the user types — the modifier's
    /// `onDraftChange` funnel.
    func updateDraft(_ draft: String) {
        noteDraft = draft
    }

    // MARK: - Action dispatch

    /// Routes a `HighlightPopoverAction` emitted by the popover view.
    func route(_ action: HighlightPopoverAction) async {
        guard let current = content else { return }
        switch action {
        case .beginEdit:
            noteDraft = current.note ?? ""
            mode = .editing
        case .cancelEdit:
            // `cancelEdit` doubles as the delete-confirm "Cancel" — both
            // return the card to the reading mode.
            mode = .reading
        case let .changeColor(color):
            await handleChangeColor(color, current: current)
        case let .saveNote(draft):
            await handleSaveNote(draft, current: current)
        case .requestDelete:
            mode = .confirmingDelete
        case .confirmDelete:
            await handleConfirmDelete(current: current)
        case .copy:
            UIPasteboard.general.string = current.highlightedText
            dismiss()
        case .share:
            // Record the share text and tear the popover content down. The
            // modifier observes `pendingShareText`, dismisses the popover
            // surface with a real completion, and only then presents the
            // share sheet — so two modals never stack (R2-F7). `dismiss()`
            // is called AFTER capturing the text because it clears state.
            let text = current.highlightedText
            dismiss()
            pendingShareText = text
        }
    }

    /// Clears the pending-share text. The modifier calls this once it has
    /// consumed `pendingShareText` (after the popover dismissal completes and
    /// the share sheet is presented).
    func clearPendingShare() {
        pendingShareText = nil
    }

    // MARK: - Outcome handling

    private func handleChangeColor(
        _ color: NamedHighlightColor, current: HighlightPopoverContent
    ) async {
        pressedColor = color
        let outcome = await mutating.changeColor(
            highlightID: current.id, to: color.rawValue
        )
        pressedColor = nil
        applyOutcome(outcome)
    }

    private func handleSaveNote(
        _ draft: String, current: HighlightPopoverContent
    ) async {
        let outcome = await mutating.updateNote(highlightID: current.id, note: draft)
        switch outcome {
        case let .success(record):
            refreshContent(from: record)
            mode = .reading
        case .notFound:
            dismiss()
        case .failed:
            // Keep the editor open so the user can retry.
            break
        }
    }

    private func handleConfirmDelete(current: HighlightPopoverContent) async {
        let outcome = await mutating.deleteHighlight(highlightID: current.id)
        switch outcome {
        case .success, .notFound:
            // `.success` — deleted; `.notFound` — already gone (a concurrent-
            // deletion race). Either way the highlight no longer exists, so
            // the popover dismisses.
            dismiss()
        case .failed:
            // A genuine persistence failure keeps the popover (and the
            // highlight) — return to the reading mode out of the confirm
            // sub-state so the user can retry.
            mode = .reading
        }
    }

    /// Applies a mutation outcome that does not itself change the mode
    /// (recolor): refresh on `.success`, dismiss on `.notFound`, no-op on
    /// `.failed`.
    private func applyOutcome(_ outcome: HighlightMutationOutcome) {
        switch outcome {
        case let .success(record):
            refreshContent(from: record)
        case .notFound:
            dismiss()
        case .failed:
            break
        }
    }

    /// Rebuilds `content` from a mutated record, preserving the original tap's
    /// `sourceRect` + `chapter` so the popover stays anchored in place.
    private func refreshContent(from record: HighlightRecord) {
        guard let current = content else { return }
        content = HighlightPopoverPresenter.content(
            for: record, sourceRect: current.sourceRect, chapter: current.chapter
        )
    }
}
#endif
