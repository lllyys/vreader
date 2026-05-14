// Purpose: ViewModifier that attaches shared reader notification handlers.
// Eliminates duplicate .onReceive blocks between TXT and MD container views (WI-003).
//
// Key decisions:
// - Owns AddNoteSheet presentation (single owner — containers must NOT attach their own).
// - contentTapped stays local in each container (chrome toggle is container-specific).
// - Uses ReaderNotificationHandlers for testable pure logic.
// - Takes a TextReaderUIState object (Phase R3) — mutates properties directly.
// - Phase R4b: highlight create/delete delegated to HighlightCoordinator.
//   Coordinator calls TextHighlightRenderer which mutates the same uiState.
//
// @coordinates-with ReaderNotificationHandlers.swift, TextReaderUIState.swift,
//   TXTReaderContainerView.swift, MDReaderContainerView.swift,
//   ReaderNotifications.swift, AddNoteSheet.swift, HighlightCoordinator.swift

import SwiftUI

/// ViewModifier that attaches 5 notification handlers + AddNoteSheet.
struct ReaderNotificationModifier: ViewModifier {
    let deps: ReaderNotificationDeps
    let uiState: TextReaderUIState
    let highlightCoordinator: HighlightCoordinator

    func body(content: Content) -> some View {
        @Bindable var bindableState = uiState

        content
            .onReceive(NotificationCenter.default.publisher(for: .readerBookmarkRequested)) { _ in
                // Bookmark is fire-and-forget — no UI state mutation needed
                Task {
                    await ReaderNotificationHandlers.handleBookmarkRequest(deps: deps)
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .readerNavigateToLocator)) { notification in
                guard let locator = notification.object as? Locator else { return }
                // Sync handler — mutate state directly (no race)
                guard let offset = locator.charOffsetUTF16 ?? locator.charRangeStartUTF16 else { return }
                uiState.scrollToOffset = offset
                uiState.highlightIsTemporary = true
                if let start = locator.charRangeStartUTF16,
                   let end = locator.charRangeEndUTF16, end > start {
                    uiState.highlightRange = NSRange(location: start, length: end - start)
                } else {
                    uiState.highlightRange = nil
                }
                deps.onNavigate(offset)
            }
            .onReceive(NotificationCenter.default.publisher(for: .readerHighlightRequested)) { notification in
                guard let info = notification.object as? TextSelectionInfo else { return }
                guard info.endUTF16 > info.startUTF16 else { return } // audit fix: validate range
                guard let locator = deps.locatorFactory(
                    deps.bookFingerprint, info.startUTF16, info.endUTF16, deps.sourceText()
                ) else { return }
                // Phase R4b: delegate to coordinator (persists + applies via renderer)
                Task {
                    await highlightCoordinator.create(
                        locator: locator,
                        selectedText: info.selectedText,
                        color: "yellow"
                    )
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .readerAnnotationRequested)) { notification in
                guard let info = notification.object as? TextSelectionInfo else { return }
                uiState.pendingAnnotationInfo = info
                uiState.annotationNoteText = ""
            }
            // Bug #88: re-render highlights after annotation import
            .onReceive(NotificationCenter.default.publisher(for: .readerHighlightsDidImport)) { _ in
                Task { await highlightCoordinator.restoreAll() }
            }
            // Phase R4b: delegate removal to coordinator (removes visual + re-fetches)
            .onReceive(NotificationCenter.default.publisher(for: .readerHighlightRemoved)) { notification in
                guard let idString = notification.object as? String,
                      let highlightId = UUID(uuidString: idString) else {
                    // Fallback: clear active highlight if UUID parsing fails
                    uiState.highlightRange = nil
                    return
                }
                Task {
                    await highlightCoordinator.handleRemoval(highlightId: highlightId)
                }
            }
            .sheet(isPresented: .init(
                get: { uiState.pendingAnnotationInfo != nil },
                set: { if !$0 { uiState.pendingAnnotationInfo = nil } }
            )) {
                AddNoteSheet(
                    selectedText: uiState.pendingAnnotationInfo?.selectedText ?? "",
                    noteText: $bindableState.annotationNoteText,
                    onSave: {
                        // Bug #181: delegate to the canonical handler so the
                        // annotation persistence path AND the HighlightRecord
                        // creation path stay in lockstep. Previously this was
                        // inlined and only called addAnnotation, leaving the
                        // text without a visible highlight indicator.
                        Task {
                            await ReaderNotificationHandlers.handleAnnotationSave(
                                state: uiState,
                                deps: deps,
                                highlightCoordinator: highlightCoordinator
                            )
                        }
                    },
                    onCancel: {
                        uiState.pendingAnnotationInfo = nil
                    }
                )
                .presentationDetents([.medium])
            }
    }
}

// MARK: - View Extension

extension View {
    /// Attaches shared reader notification handlers and AddNoteSheet.
    func readerNotificationHandlers(
        deps: ReaderNotificationDeps,
        uiState: TextReaderUIState,
        highlightCoordinator: HighlightCoordinator
    ) -> some View {
        modifier(ReaderNotificationModifier(
            deps: deps,
            uiState: uiState,
            highlightCoordinator: highlightCoordinator
        ))
    }
}
