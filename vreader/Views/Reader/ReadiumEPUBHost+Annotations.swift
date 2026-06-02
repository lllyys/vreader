// Purpose: Bug #303 — select → Note parity for `ReadiumEPUBHost`. The Readium
// host wired highlight CREATE (WI-8) but never observed `.readerAnnotationRequested`
// (the selection popover's "Note" action) and mounted no note-input sheet, so a
// selection → Note was a silent no-op on the default EPUB engine. Legacy
// `EPUBReaderContainerView` (`.readerAnnotationRequested` → `noteInputSheet`) and
// TXT/MD (`ReaderNotificationModifier` → `AddNoteSheet`) both mount it; this brings
// the Readium host to parity.
//
// Mirrors the sibling `ReadiumEPUBHost+Highlights` selection-token round-trip: the
// annotation request resolves the cached Readium `Selection`, stashes it across the
// sheet's lifetime (the token is consumed on resolve, like legacy
// `pendingSelectionEvent`), presents the DESIGNED `AddNoteSheet` (rule 51 — reuse,
// no new UI), and on Save creates a highlight WITH the note through the same
// `ReadiumSelectionHighlightBuilder` → `HighlightCoordinator.create(note:)` path,
// so the annotated highlight paints as a Readium decoration immediately.
//
// @coordinates-with: ReadiumEPUBHost.swift, ReadiumEPUBHost+Highlights.swift,
//   ReadiumSelectionHighlightBuilder.swift, ReadiumSelectionTokenCache.swift,
//   AddNoteSheet.swift, HighlightCoordinator.swift, SelectionPopoverActionRouter.swift

#if canImport(UIKit)
import SwiftUI
import ReadiumNavigator

/// Bug #303: bundles the Readium host's annotation (Note) observer + the designed
/// `AddNoteSheet` presentation into one `ViewModifier` so `ReadiumEPUBHost` stays
/// under the ~300-line budget. The host builds it from `annotationObservers` with
/// bindings/closures over its `@State`; this modifier owns only the SwiftUI wiring.
struct ReadiumAnnotationObservers: ViewModifier {
    @Binding var showNoteSheet: Bool
    @Binding var noteText: String
    /// The selected text shown read-only at the top of the note sheet.
    let selectedText: String
    let onAnnotationRequested: (Notification) -> Void
    let onSave: () -> Void
    let onCancel: () -> Void

    func body(content: Content) -> some View {
        content
            // The popover's "Note" tap posts `.readerAnnotationRequested` (token);
            // the host resolves it to the cached selection and raises the sheet.
            .onReceive(NotificationCenter.default.publisher(for: .readerAnnotationRequested)) { note in
                onAnnotationRequested(note)
            }
            // `onDismiss: onCancel` covers EVERY dismissal path — including a
            // drag-down that bypasses the buttons — so the stashed selection and
            // the live navigator selection are always cleaned up (audit-Low). It
            // is idempotent: a Save already nils the pending selection + clears the
            // navigator selection before the sheet closes.
            .sheet(isPresented: $showNoteSheet, onDismiss: onCancel) {
                AddNoteSheet(
                    selectedText: selectedText,
                    noteText: $noteText,
                    onSave: onSave,
                    onCancel: onCancel
                )
                // Match the established AddNoteSheet mounts (TXT/MD + legacy EPUB).
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
            }
    }
}

extension ReadiumEPUBHost {

    /// Bug #303: the annotation-observer bundle attached to the host body via
    /// `.modifier(...)`, alongside `highlightObservers`. Wires the
    /// `.readerAnnotationRequested` observer + the designed `AddNoteSheet`.
    var annotationObservers: ReadiumAnnotationObservers {
        ReadiumAnnotationObservers(
            showNoteSheet: $showReadiumNoteSheet,
            noteText: $readiumNoteText,
            selectedText: pendingReadiumNoteSelection?.locator.text.highlight ?? "",
            onAnnotationRequested: { handleReadiumAnnotationRequested($0) },
            onSave: { handleReadiumNoteSave() },
            onCancel: { handleReadiumNoteCancel() }
        )
    }

    /// Resolves the annotation request's token back to the cached Readium
    /// `Selection`, stashes it for the sheet's lifetime, and presents the note
    /// sheet. A token miss (tokenless action, stale/replayed notification) or a
    /// selection with no highlight text no-ops — nothing to annotate.
    @MainActor
    func handleReadiumAnnotationRequested(_ note: Notification) {
        let token = note.userInfo?["selectionRequestToken"] as? UUID
        guard let selection = readiumSelectionTokenCache.resolve(token: token) else { return }
        let highlight = selection.locator.text.highlight ?? ""
        guard !highlight.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        pendingReadiumNoteSelection = selection
        readiumNoteText = ""
        showReadiumNoteSheet = true
    }

    /// Saves the in-flight selection as a highlight WITH the entered note. Maps the
    /// stashed `Selection` to create inputs via `ReadiumSelectionHighlightBuilder`
    /// and persists + renders through the shared `HighlightCoordinator` (whose
    /// renderer is the `ReadiumDecorationHighlightAdapter`). An empty note degrades
    /// to a plain highlight (`note: nil`) — same as the legacy path. Dismisses the
    /// sheet and clears the pending selection in all branches.
    @MainActor
    func handleReadiumNoteSave() {
        defer {
            showReadiumNoteSheet = false
            pendingReadiumNoteSelection = nil
        }
        guard let selection = pendingReadiumNoteSelection,
              let inputs = ReadiumSelectionHighlightBuilder.makeInputs(
                from: selection, fingerprint: fingerprint
              ),
              let coordinator = highlightCoordinator
        else { return }
        let note = ReadiumSelectionHighlightBuilder.normalizeNote(readiumNoteText)
        // Clear the live selection synchronously so the native Readium edit menu
        // dismisses alongside the sheet (the create await runs in a Task).
        navCommander.clearSelection()
        Task { [coordinator] in
            await coordinator.create(
                locator: inputs.locator,
                anchor: inputs.anchor,
                selectedText: inputs.selectedText,
                color: "yellow",
                note: note
            )
        }
    }

    /// Cancels the note sheet without persisting; drops the pending selection and
    /// clears the live navigator selection. Runs on Cancel AND on any sheet
    /// dismissal (via `onDismiss`), so it must be idempotent — every statement is.
    @MainActor
    func handleReadiumNoteCancel() {
        showReadiumNoteSheet = false
        pendingReadiumNoteSelection = nil
        navCommander.clearSelection()
    }
}
#endif
