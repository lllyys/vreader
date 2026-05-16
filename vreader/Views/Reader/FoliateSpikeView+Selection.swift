// Purpose: Bug #201 / GH #739 — new-selection action-sheet handler for
// `FoliateSpikeView` (AZW3/MOBI). Sibling of `+HighlightTap.swift`
// (Bug #199's tap-on-existing-highlight flow).
//
// Flow:
//   1. Foliate-js fires `selection` when the user finishes a long-press
//      selection (caught by the Coordinator in FoliateSpikeView.swift,
//      which posts `.foliateSelectionDetected` via the dispatcher).
//   2. The view-modifier here observes that notification (filtered by
//      `fingerprintKey`), stashes the event in local state, and
//      presents a `confirmationDialog` with "Highlight" / "Cancel".
//   3. On Highlight: build a `Locator` carrying the selection's CFI,
//      build an `AnnotationAnchor.epub(href:"", cfi:cfi, …)` (the
//      Foliate-side serializedRange placeholder mirrors how the
//      existing `FoliateHighlightTapResolver` reads only CFI back),
//      call `PersistenceActor.addHighlight`, then evaluate
//      `FoliateHighlightRenderer.addAnnotationJS(cfi:color:)` on the
//      live WKWebView so the highlight paints immediately instead of
//      waiting for a reload.
//
// Why this lives in its own file (not inline in FoliateSpikeView.swift):
// the spike view is already at 470+ lines after Bug #189 + Feature #53
// WI-5 + Bug #199. The 300-line guideline (`50-codebase-conventions.md`)
// is binding for fresh additions; keeping each handler in its own
// modifier file mirrors the +HighlightTap pattern.
//
// @coordinates-with: FoliateSpikeView.swift, FoliateSelectionDispatcher.swift,
//   FoliateMessageParser.swift, FoliateHighlightRenderer.swift,
//   PersistenceActor+Highlights.swift, AnnotationAnchor.swift,
//   ReaderNotifications.swift (`.foliateSelectionDetected`)

#if canImport(UIKit)
import SwiftUI
import SwiftData
import OSLog

// MARK: - View modifier

/// SwiftUI view modifier applied to `FoliateSpikeView.body`. Owns the
/// observer + dialog state independent of the host view's body so the
/// host stays small.
private struct FoliateSelectionHandlerModifier: ViewModifier {
    let fingerprintKey: String?
    @Environment(\.modelContext) private var modelContext
    @State private var pending: PendingSelection?

    /// Local-only DTO carrying everything the action-sheet handler
    /// needs. Avoids touching the production-level `FoliateSelectionEvent`
    /// struct (which lives in the cross-format parser layer).
    private struct PendingSelection: Equatable {
        let cfi: String
        let text: String
        let fingerprintKey: String
    }

    func body(content: Content) -> some View {
        content
            .onReceive(
                NotificationCenter.default.publisher(for: .foliateSelectionDetected)
            ) { note in
                guard let key = fingerprintKey,
                      let info = note.userInfo,
                      let receivedKey = info["fingerprintKey"] as? String,
                      receivedKey == key,
                      let cfi = info["cfi"] as? String,
                      let text = info["text"] as? String,
                      !text.isEmpty else { return }
                pending = PendingSelection(
                    cfi: cfi,
                    text: text,
                    fingerprintKey: key
                )
            }
            .confirmationDialog(
                "Text Selection",
                isPresented: pendingBinding,
                titleVisibility: .visible,
                presenting: pending
            ) { selection in
                Button("Highlight") {
                    handleHighlight(selection)
                }
                .accessibilityIdentifier("foliateSelectionHighlightButton")
                Button("Cancel", role: .cancel) {
                    pending = nil
                }
                .accessibilityIdentifier("foliateSelectionCancelButton")
            } message: { selection in
                Text(selection.text)
            }
    }

    /// Custom Bool binding that mirrors `pending != nil` for the
    /// confirmation dialog. SwiftUI's `confirmationDialog(_:isPresented:
    /// titleVisibility:presenting:)` requires a Bool binding; the data
    /// (`pending`) drives presentation.
    private var pendingBinding: Binding<Bool> {
        Binding(
            get: { pending != nil },
            set: { presenting in
                if !presenting { pending = nil }
            }
        )
    }

    @MainActor
    private func handleHighlight(_ selection: PendingSelection) {
        defer { pending = nil }

        guard let fp = DocumentFingerprint(canonicalKey: selection.fingerprintKey) else { return }

        // Foliate-js exposes a CFI but no DOM-range XPath; use a
        // placeholder `serializedRange` (mirrors what the existing
        // `FoliateHighlightTapResolver` round-trips — it reads only
        // `cfi` from the anchor). `href` empty for the same reason:
        // Foliate-js does not expose a stable href per section in
        // the selection event.
        let placeholderRange = EPUBSerializedRange(
            startContainerPath: "",
            startOffset: 0,
            endContainerPath: "",
            endOffset: 0
        )
        let anchor = AnnotationAnchor.epub(
            href: "",
            cfi: selection.cfi,
            serializedRange: placeholderRange
        )
        let locator = Locator(
            bookFingerprint: fp,
            href: nil,
            progression: nil,
            totalProgression: nil,
            cfi: selection.cfi,
            page: nil,
            charOffsetUTF16: nil,
            charRangeStartUTF16: nil,
            charRangeEndUTF16: nil,
            textQuote: selection.text,
            textContextBefore: nil,
            textContextAfter: nil
        )

        let persistence = PersistenceActor(modelContainer: modelContext.container)
        let bookKey = selection.fingerprintKey
        let cfi = selection.cfi
        let text = selection.text

        Task { @MainActor in
            do {
                _ = try await persistence.addHighlight(
                    locator: locator,
                    anchor: anchor,
                    selectedText: text,
                    color: "yellow",
                    note: nil,
                    toBookWithKey: bookKey
                )
                // Paint the highlight on the live Foliate overlay so
                // the user sees feedback immediately rather than on
                // next reopen. Post a notification the Coordinator
                // (which holds `webView`) picks up and evaluates.
                NotificationCenter.default.post(
                    name: .foliateRequestAnnotationJSCreate,
                    object: nil,
                    userInfo: [
                        "cfi": cfi,
                        "color": "yellow",
                        "fingerprintKey": bookKey,
                    ]
                )
                HapticFeedbackProvider().triggerLightImpact()
            } catch {
                let log = Logger(
                    subsystem: "com.vreader.app",
                    category: "FoliateSpikeView+Selection"
                )
                log.error(
                    "addHighlight failed: \(String(describing: error), privacy: .public)"
                )
            }
        }
    }
}

extension View {
    /// Bug #201 / GH #739: attach the new-selection action-sheet
    /// handler to a `FoliateSpikeView.body`. Filters incoming
    /// `.foliateSelectionDetected` notifications by `fingerprintKey` so
    /// concurrent Foliate readers don't cross-fire.
    func foliateSelectionHandler(fingerprintKey: String?) -> some View {
        modifier(FoliateSelectionHandlerModifier(fingerprintKey: fingerprintKey))
    }
}

#endif
