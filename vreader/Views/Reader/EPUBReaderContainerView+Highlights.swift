// Purpose: Highlight action handling, note input sheet, and highlight restoration
// for EPUBReaderContainerView. Pure code extraction — no logic changes.
//
// @coordinates-with: EPUBReaderContainerView.swift, EPUBHighlightActions.swift,
//   EPUBHighlightBridge.swift, EPUBHighlightRenderer.swift, HighlightCoordinator.swift

#if canImport(UIKit)
import SwiftUI
import SwiftData

extension EPUBReaderContainerView {

    // MARK: - Highlight Actions

    /// Persists a highlight and injects the CSS highlight into the WKWebView.
    /// Phase R4b: delegates to coordinator (which calls renderer for JS injection).
    ///
    /// WI-7c5b: `color` is the `NamedHighlightColor.rawValue` the user
    /// picked in the SelectionPopover (`resolveHighlightColor(from:)`
    /// supplies `"yellow"` when a producer omits it). It flows to
    /// `HighlightCoordinator.create(color:)` and, on the coordinator-
    /// not-ready fallback, to `PersistenceActor.addHighlight(color:)`
    /// directly — both already accept a color.
    func handleHighlightAction(
        event: ReaderSelectionEvent,
        container: ModelContainer,
        color: String
    ) {
        guard let locator = viewModel.makeCurrentLocator() else { return }

        if let coordinator = highlightCoordinator {
            Task {
                await coordinator.create(
                    locator: locator,
                    anchor: event.anchor,
                    selectedText: event.selectedText,
                    color: color
                )
            }
        } else {
            // Fallback: direct persistence if the coordinator is not
            // ready (a rare appear-race). Routes through
            // `addHighlight(color:)` directly so the chosen color is
            // honored — the old `EPUBHighlightActions.persistHighlight`
            // helper hardcoded "yellow" and is removed as the now-dead
            // local cleanup (plan v10 / Codex plan-v10 round 1 Low).
            let persistence = PersistenceActor(modelContainer: container)
            Task {
                if let record = try? await persistence.addHighlight(
                    locator: locator, anchor: event.anchor,
                    selectedText: event.selectedText, color: color,
                    note: nil, toBookWithKey: viewModel.bookFingerprintKey
                ), let js = EPUBHighlightActions.createHighlightJS(for: record) {
                    pendingHighlightJS = js
                }
            }
        }
    }

    // MARK: - Note Input Sheet

    @ViewBuilder
    var noteInputSheet: some View {
        NavigationStack {
            VStack(spacing: 16) {
                if let event = pendingSelectionEvent {
                    Text(event.selectedText)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal)
                }
                TextEditor(text: $noteText)
                    .frame(minHeight: 100)
                    .padding(.horizontal)
                    .accessibilityIdentifier("epubNoteTextEditor")
                Spacer()
            }
            .padding(.top)
            .navigationTitle("Add Note")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        showNoteSheet = false
                        pendingSelectionEvent = nil
                    }
                    .accessibilityIdentifier("epubNoteCancelButton")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") {
                        guard let event = pendingSelectionEvent,
                              let container = modelContainer else {
                            showNoteSheet = false
                            return
                        }
                        handleHighlightWithNote(
                            event: event,
                            container: container,
                            note: noteText.isEmpty ? nil : noteText
                        )
                        showNoteSheet = false
                    }
                    .accessibilityIdentifier("epubNoteSaveButton")
                }
            }
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }

    /// Persists a highlight with an attached note.
    /// Phase R4b: delegates to coordinator.
    func handleHighlightWithNote(
        event: ReaderSelectionEvent,
        container: ModelContainer,
        note: String?
    ) {
        guard let locator = viewModel.makeCurrentLocator() else {
            pendingSelectionEvent = nil
            return
        }

        if let coordinator = highlightCoordinator {
            Task {
                await coordinator.create(
                    locator: locator,
                    anchor: event.anchor,
                    selectedText: event.selectedText,
                    color: "yellow",
                    note: note
                )
            }
        } else {
            // Fallback: direct persistence if coordinator not ready
            let persistence = PersistenceActor(modelContainer: container)
            Task {
                if let record = try? await persistence.addHighlight(
                    locator: locator, anchor: event.anchor,
                    selectedText: event.selectedText, color: "yellow",
                    note: note, toBookWithKey: viewModel.bookFingerprintKey
                ), let js = EPUBHighlightActions.createHighlightJS(for: record) {
                    pendingHighlightJS = js
                }
            }
        }
        pendingSelectionEvent = nil
    }

    /// Restores saved highlights for the current chapter after a page finishes loading.
    /// Phase R4b: delegates to coordinator which calls EPUBHighlightRenderer.
    func restoreHighlightsOnLoad(evaluateJS: @escaping (String) -> Void) {
        guard let href = viewModel.currentPosition?.href else { return }
        highlightRenderer.currentHref = href

        if let coordinator = highlightCoordinator {
            // Bug #103: pass `evaluateJS` directly through the restore
            // call instead of swapping `onInjectJS`. A user-driven
            // highlight created during the restore await window now
            // continues to use `onInjectJS` (the normal callback) and
            // lands at the right destination — instead of being
            // misrouted to this temporary page-ready evaluator.
            //
            // Bug #103 follow-up: capture `href` immutably and pass it
            // into the restore call so a second `restoreHighlightsOnLoad`
            // (e.g., user-fast-navigates to a new chapter) doesn't
            // make this call's JS reflect the new chapter's records
            // via the shared mutable `currentHref`.
            let capturedHref = href
            Task {
                await coordinator.restoreAll(forHref: capturedHref, using: evaluateJS)
            }
        } else {
            // Fallback: direct fetch if coordinator not ready
            guard let container = modelContainer else { return }
            let persistence = PersistenceActor(modelContainer: container)
            Task {
                let highlights = (try? await persistence.fetchHighlights(
                    forBookWithKey: viewModel.bookFingerprintKey
                )) ?? []
                let js = EPUBHighlightActions.restoreHighlightsJS(
                    highlights: highlights, currentHref: href
                )
                if !js.isEmpty { evaluateJS(js) }
            }
        }
    }
}
#endif
