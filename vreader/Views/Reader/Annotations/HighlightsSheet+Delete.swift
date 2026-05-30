// Purpose: Bug #249 / GH #1080 — `HighlightsSheet`'s delete + copy actions
// and the per-row interaction handlers for the committed delete affordance
// (`dev-docs/designs/vreader-fidelity-v1/project/vreader-notes-delete.jsx`).
//
// Split out of `HighlightsSheet.swift` to keep the main view file under the
// ~300-line guideline (`.claude/rules/50-codebase-conventions.md` §9) — the
// same `+Export` / `+Support` cross-file pattern.
//
// The delete routes through the already-loaded `HighlightListViewModel.
// removeHighlight` / `AnnotationListViewModel.removeAnnotation` (the data
// path the feature #62 WI-5 migration left intact); Copy mirrors the
// in-reader popover's `.copy` semantics (`HighlightPopoverActionRouter` —
// `UIPasteboard.general.string`). Edit is a navigate-to-passage handoff (the
// sheet does not embed an editor — the design hands editing off to the
// existing `HighlightActionCard` / note editor).
//
// @coordinates-with: HighlightsSheet.swift, NotesRowState.swift,
//   NotesActionMenu.swift, HighlightListViewModel.swift,
//   AnnotationListViewModel.swift

#if canImport(UIKit)
import SwiftUI
import UIKit

extension HighlightsSheet {

    // MARK: - Per-row handlers (the design's `handlers(id)` closures)

    /// Open the ⋯ action menu over `rowId`.
    func openMenu(for rowId: UUID) {
        rowState = rowState.openingMenu(for: rowId)
    }

    /// Begin delete confirmation on `rowId` (from the menu's Delete item or
    /// the swipe drawer's Delete cell). Shows the inline confirm strip.
    func beginDeleteConfirmation(for rowId: UUID) {
        rowState = rowState.confirmingDelete(for: rowId)
    }

    /// Reveal the left-swipe drawer on `rowId`.
    func revealSwipe(for rowId: UUID) {
        rowState = rowState.revealingSwipe(for: rowId)
    }

    /// Cancel / Undo / scrim tap — return every row to rest. No delete.
    func dismissRowState() {
        rowState = rowState.dismissed()
    }

    /// Confirm the delete for `item`: flip to the spinner phase, run the
    /// `PersistenceActor`-backed remove through the loaded VM, then either
    /// dismiss (success — the stream reflows the row out) or show the error
    /// chip (failure).
    func confirmDelete(_ item: AnnotationStreamItem) async {
        let id = item.id
        rowState = rowState.deleting(id)
        let ok = await performDelete(item)
        // Async-race guard: if the user moved on to another row (or dismissed)
        // while this delete was in flight, `rowState` is no longer THIS row in
        // `.deleting`. The persistence remove still committed (the record is
        // gone from the stream regardless), but we must NOT clobber whatever
        // interaction the user has since started on another row.
        guard rowState.activeRowId == id, rowState.phase == .deleting else { return }
        if ok {
            // The VM already removed the record from its in-memory array, so
            // `currentStream` no longer contains the row. Returning to rest
            // lets the LazyVStack drop it.
            rowState = rowState.dismissed()
        } else {
            rowState = rowState.failed(id)
        }
    }

    /// Retry a failed delete — re-invoke the same remove.
    func retryDelete(_ item: AnnotationStreamItem) async {
        await confirmDelete(item)
    }

    /// Copy the row's text to the pasteboard (the menu's Copy item). A
    /// highlight copies its quoted passage; a standalone note copies its
    /// body — mirroring the in-reader popover's `.copy`.
    func copy(_ item: AnnotationStreamItem) {
        switch item {
        case .highlight(let record):
            UIPasteboard.general.string = record.selectedText
        case .standalone(let record):
            UIPasteboard.general.string = record.content
        }
        rowState = rowState.dismissed()
    }

    /// Edit handoff — navigate to the passage and dismiss the sheet so the
    /// user lands where the in-reader edit affordance (the highlight popover
    /// for highlights, the note editor for standalones) is reachable. The
    /// sheet itself does not embed an editor (the design's "handoff, not
    /// re-implementation"). Auto-opening the editor after the jump is tracked
    /// as a follow-up (the in-reader popover only opens on a real
    /// `.readerHighlightTapped`, which has no programmatic post-navigation
    /// entry point yet).
    func edit(_ item: AnnotationStreamItem) {
        rowState = rowState.dismissed()
        // Navigate to the passage (the #1080 handoff) …
        switch item {
        case .highlight(let record):  onNavigate(record.locator)
        case .standalone(let record): onNavigate(record.locator)
        }
        onDismiss()
        // … then Feature #1121 WI-2: request the in-reader editor to auto-open.
        // For a highlight we post `.readerHighlightEditRequested`; the mounted
        // `HighlightPopoverModifier` resolves the record (book-scoped) and opens
        // the unified card in editing mode. A standalone-note editor path is WI-3
        // (still navigate-only). The book key + a single-flight token scope/order
        // the request (HighlightEditHandoff + the VM's latest-token supersession).
        switch HighlightEditHandoff.action(
            for: item, bookFingerprintKey: bookFingerprintKey, token: UUID()
        ) {
        case .requestHighlightEdit(let request):
            NotificationCenter.default.post(
                name: .readerHighlightEditRequested, object: request
            )
        case .openStandaloneNote:
            break // WI-3
        }
    }

    // MARK: - Delete plumbing

    /// Runs the actual remove through the loaded view model. Returns whether
    /// the VM reports success (its `errorMessage` stays nil). The VMs remove
    /// the record from both `PersistenceActor` storage and their in-memory
    /// array, and post the reader-sync notifications (`.readerHighlightRemoved`
    /// + the Foliate JS-strip for `.epub`-anchored highlights).
    private func performDelete(_ item: AnnotationStreamItem) async -> Bool {
        switch item {
        case .highlight(let record):
            guard let vm = highlightVM else { return false }
            await vm.removeHighlight(highlightId: record.highlightId)
            return vm.errorMessage == nil
        case .standalone(let record):
            guard let vm = annotationVM else { return false }
            await vm.removeAnnotation(annotationId: record.annotationId)
            return vm.errorMessage == nil
        }
    }

    /// Maps a stream item to its action kind for the menu / confirm copy.
    func actionKind(for item: AnnotationStreamItem) -> NotesActionKind {
        switch item {
        case .highlight:  return .highlight
        case .standalone: return .standalone
        }
    }

    // MARK: - Card composition (the design's `HighlightCardV4` shell)

    /// The card itself, with the trailing ⋯ accessory and the
    /// phase-appropriate body override (confirm strip / error chip / spinner
    /// mute) wired in.
    @ViewBuilder
    func cardContent(for item: AnnotationStreamItem, phase: NotesRowPhase) -> some View {
        let overrides = phaseUsesBodyOverride(phase)
        // Tap-to-jump is suppressed while any non-default interaction (menu /
        // confirm / swipe / deleting / error) owns the row — so an outside tap
        // dismisses the interaction rather than navigating (the design
        // disables jump in `menu-open`; same logic for the other phases).
        let canJump = (phase == .default)
        switch item {
        case .highlight(let record):
            HighlightCardV3(
                theme: theme,
                highlight: record,
                metaLabel: metaLabel(for: record.locator),
                onJump: { onNavigate($0); onDismiss() },
                usesBodyOverride: overrides,
                jumpEnabled: canJump,
                metaTrailing: { moreAccessory(for: item, phase: phase) },
                bodyOverride: { deleteBodyOverride(for: item, phase: phase) }
            )
            .accessibilityIdentifier("highlightCard-\(record.highlightId)")
        case .standalone(let record):
            StandaloneNoteCard(
                theme: theme,
                note: record,
                metaLabel: metaLabel(for: record.locator),
                onJump: { onNavigate($0); onDismiss() },
                usesBodyOverride: overrides,
                jumpEnabled: canJump,
                metaTrailing: { moreAccessory(for: item, phase: phase) },
                bodyOverride: { deleteBodyOverride(for: item, phase: phase) }
            )
            .accessibilityIdentifier("standaloneNoteCard-\(record.annotationId)")
        }
    }

    /// The confirm strip / error chip replaces the body for these phases.
    func phaseUsesBodyOverride(_ phase: NotesRowPhase) -> Bool {
        switch phase {
        case .confirming, .deleting, .error: return true
        default: return false
        }
    }

    /// The trailing meta-row accessory: the ⋯ button at rest / menu-open; a
    /// spinner + "Deleting…" while the delete is in flight (the design hides
    /// the ⋯ during `deleting`); nothing during swipe / confirm / error (the
    /// drawer or the body strip owns the row then).
    @ViewBuilder
    func moreAccessory(for item: AnnotationStreamItem, phase: NotesRowPhase) -> some View {
        switch phase {
        case .deleting:
            HStack(spacing: 6) {
                ProgressView().controlSize(.mini)
                Text("Deleting…")
                    .font(.system(size: 11))
                    .foregroundStyle(Color(theme.subColor))
            }
        case .swipeRevealed, .confirming, .error:
            EmptyView()
        default:
            NotesMoreButton(
                theme: theme,
                isActive: phase == .menuOpen,
                accessibilityLabel: moreButtonLabel(for: item),
                onTap: { openMenu(for: item.id) }
            )
        }
    }

    /// The body region replacement for the confirm / error phases. Returns an
    /// `EmptyView` for every other phase (the card then renders its normal
    /// body — gated by `usesBodyOverride`).
    @ViewBuilder
    func deleteBodyOverride(for item: AnnotationStreamItem, phase: NotesRowPhase) -> some View {
        switch phase {
        case .confirming, .deleting:
            NotesDeleteConfirm(
                theme: theme,
                kind: actionKind(for: item),
                isBusy: phase == .deleting,
                onCancel: { dismissRowState() },
                onConfirm: { Task { await confirmDelete(item) } }
            )
        case .error:
            NotesRowError(
                theme: theme,
                message: actionKind(for: item) == .standalone
                    ? "Couldn't delete the note. Tap retry."
                    : "Couldn't delete. Tap retry.",
                onRetry: { Task { await retryDelete(item) } },
                onUndo: { dismissRowState() }
            )
        default:
            EmptyView()
        }
    }

    /// VoiceOver label for the ⋯ button — names the row's kind + chapter.
    func moreButtonLabel(for item: AnnotationStreamItem) -> String {
        switch item {
        case .highlight(let r):
            let chapter = chapterTitle(for: r.locator) ?? "this position"
            return "Actions for highlight on \(chapter)"
        case .standalone(let r):
            let chapter = chapterTitle(for: r.locator) ?? "this position"
            return "Actions for note on \(chapter)"
        }
    }
}

// MARK: - Testing hooks

#if DEBUG
extension HighlightsSheet {

    /// Loads the view models, deletes the highlight through the real
    /// `removeHighlight` path, and returns the resulting stream (newest-first
    /// All filter) — for the bug-249 delete-effect test. Mirrors the
    /// `loadStreamForTesting` hook: returns the value rather than mutating
    /// `@State` (which is not observable outside a render tree).
    func deleteHighlightForTesting(highlightId: UUID) async -> [AnnotationStreamItem] {
        let (hVM, aVM) = await loadVMsForTesting()
        await hVM.removeHighlight(highlightId: highlightId)
        return AnnotationStreamBuilder.stream(
            highlights: hVM.highlights, annotations: aVM.annotations, filter: .all
        )
    }

    /// As `deleteHighlightForTesting`, for a standalone annotation.
    func deleteAnnotationForTesting(annotationId: UUID) async -> [AnnotationStreamItem] {
        let (hVM, aVM) = await loadVMsForTesting()
        await aVM.removeAnnotation(annotationId: annotationId)
        return AnnotationStreamBuilder.stream(
            highlights: hVM.highlights, annotations: aVM.annotations, filter: .all
        )
    }

    /// Loads the VMs, copies the highlight's quote to the pasteboard.
    func copyHighlightForTesting(highlightId: UUID) async {
        let (hVM, _) = await loadVMsForTesting()
        guard let record = hVM.highlights.first(where: { $0.highlightId == highlightId }) else { return }
        copy(.highlight(record))
    }

    /// Loads the VMs, copies the standalone note's body to the pasteboard.
    func copyAnnotationForTesting(annotationId: UUID) async {
        let (_, aVM) = await loadVMsForTesting()
        guard let record = aVM.annotations.first(where: { $0.annotationId == annotationId }) else { return }
        copy(.standalone(record))
    }

    /// Builds + loads a fresh pair of VMs over the sheet's container — the
    /// shared setup for the delete/copy hooks.
    private func loadVMsForTesting() async -> (HighlightListViewModel, AnnotationListViewModel) {
        let persistence = PersistenceActor(modelContainer: modelContainer)
        let hVM = HighlightListViewModel(
            bookFingerprintKey: bookFingerprintKey,
            store: persistence, totalTextLengthUTF16: nil
        )
        let aVM = AnnotationListViewModel(
            bookFingerprintKey: bookFingerprintKey, store: persistence
        )
        await hVM.loadHighlights()
        await aVM.loadAnnotations()
        return (hVM, aVM)
    }
}
#endif
#endif
