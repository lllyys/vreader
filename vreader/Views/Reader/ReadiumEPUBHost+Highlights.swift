// Purpose: Feature #42 Phase 1 WI-8 (new-highlight slice) — selection→popover→
// create wiring for `ReadiumEPUBHost`. The coordinator's
// `shouldShowMenuForSelection` delegate forwards a finalized Readium `Selection`
// here; the host caches it under a token and surfaces the designed
// `SelectionPopoverView` color picker (rule 51 — reuse, no new UI). On a color
// tap the popover routes through `SelectionPopoverActionRouter` →
// `.readerHighlightRequested`, which this host resolves back to the cached
// selection, maps to a `HighlightRecord` via `ReadiumSelectionHighlightBuilder`,
// and persists + renders through the host's shared `HighlightCoordinator` (whose
// renderer is the `ReadiumDecorationHighlightAdapter`, so the new highlight
// PAINTS as a Readium decoration immediately).
//
// Mirror of the legacy `EPUBReaderContainerView+Highlights` / its selection-
// token round-trip — the legacy path is untouched.
//
// @coordinates-with: ReadiumEPUBHost.swift, ReadiumReaderCoordinator.swift,
//   ReadiumSelectionHighlightBuilder.swift, ReadiumSelectionTokenCache.swift,
//   SelectionPopoverPresenter.swift, SelectionPopoverActionRouter.swift,
//   HighlightCoordinator.swift

#if canImport(UIKit)
import SwiftUI
import ReadiumNavigator

/// WI-8: bundles the Readium host's highlight observers into one `ViewModifier`
/// so `ReadiumEPUBHost` stays under the ~300-line budget. The host builds it from
/// `highlightObservers` with closures over its `@State` (token cache / adapter /
/// coordinator); this modifier only owns the SwiftUI wiring.
struct ReadiumHighlightObservers: ViewModifier {
    let theme: ReaderThemeV2
    let onDismiss: () -> Void
    let onHighlightRequested: (Notification) -> Void
    let onHighlightRemoved: (UUID) -> Void
    let onHighlightsDidImport: () -> Void

    func body(content: Content) -> some View {
        content
            // Present the designed color-picker popover on a finalized selection
            // (rule 51 — reuse, no new UI). Close/dismiss drops the cached selection.
            .selectionPopoverPresenter(theme: theme, onDismiss: onDismiss)
            // The popover's color tap → `.readerHighlightRequested` (token + color);
            // the host resolves the token to the cached selection and creates.
            .onReceive(NotificationCenter.default.publisher(for: .readerHighlightRequested)) { note in
                onHighlightRequested(note)
            }
            // Clear a removed highlight's decoration (cross-format Bug #78 pipeline).
            .onReceive(NotificationCenter.default.publisher(for: .readerHighlightRemoved)) { note in
                guard let idString = note.object as? String,
                      let id = UUID(uuidString: idString) else { return }
                onHighlightRemoved(id)
            }
            // Re-restore after an annotation import refreshes the set.
            .onReceive(NotificationCenter.default.publisher(for: .readerHighlightsDidImport)) { _ in
                onHighlightsDidImport()
            }
    }
}

extension ReadiumEPUBHost {

    /// WI-8: the highlight-observer bundle attached to the host body via
    /// `.modifier(...)` so the host file stays under the ~300-line budget. Wires:
    /// the designed `SelectionPopoverView` presenter (color picker on a finalized
    /// selection), the `.readerHighlightRequested` create handler, the
    /// `.readerHighlightRemoved` decoration-clear, and the `.readerHighlightsDidImport`
    /// re-restore. Mirrors the legacy EPUB container's observers (rule 51 — reuse).
    var highlightObservers: ReadiumHighlightObservers {
        ReadiumHighlightObservers(
            theme: settingsStore.theme,
            onDismiss: { readiumSelectionTokenCache.clear() },
            onHighlightRequested: { handleReadiumHighlightRequested($0) },
            onHighlightRemoved: { id in highlightAdapter.remove(id: id) },
            onHighlightsDidImport: { [coordinator = highlightCoordinator] in
                Task { await coordinator?.restoreAll() }
            }
        )
    }

    /// Called from the coordinator's `shouldShowMenuForSelection` (via the
    /// representable's `onSelection`). Caches the Readium `Selection` under a
    /// fresh token and posts `.readerSelectionPopoverRequested` so the presenter
    /// mounts the designed color-picker popover. `startUTF16` / `endUTF16` are
    /// placeholder (the popover only displays `selectedText`; the real text-quote
    /// anchor lives in the cached `Selection`). A selection with no highlight text
    /// is dropped — there is nothing to highlight.
    @MainActor
    func handleReadiumSelection(_ selection: Selection) {
        let highlight = selection.locator.text.highlight ?? ""
        guard !highlight.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return
        }
        let token = readiumSelectionTokenCache.store(selection)
        let info = TextSelectionInfo(
            selectedText: highlight,
            startUTF16: 0,
            endUTF16: highlight.utf16.count
        )
        SelectionPopoverRequest.post(selection: info, requestToken: token)
    }

    /// Called from the `.readerHighlightRequested` observer. Resolves the token
    /// back to the cached Readium `Selection`, maps it to the create inputs, and
    /// persists + renders via the shared `HighlightCoordinator`. A token miss
    /// (TXT/MD tokenless action, stale/replayed notification) no-ops. After a
    /// successful create the navigator's selection is cleared so the system menu
    /// dismisses with the popover.
    @MainActor
    func handleReadiumHighlightRequested(_ note: Notification) {
        let token = note.userInfo?["selectionRequestToken"] as? UUID
        guard let selection = readiumSelectionTokenCache.resolve(token: token),
              let inputs = ReadiumSelectionHighlightBuilder.makeInputs(
                from: selection, fingerprint: fingerprint
              ),
              let coordinator = highlightCoordinator
        else { return }
        let color = resolveHighlightColor(from: note)
        // Clear the live selection synchronously so the native Readium edit menu
        // dismisses alongside the popover (the create await runs in a Task).
        navCommander.clearSelection()
        Task {
            await coordinator.create(
                locator: inputs.locator,
                anchor: inputs.anchor,
                selectedText: inputs.selectedText,
                color: color
            )
        }
    }
}
#endif
