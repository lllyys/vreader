// Purpose: Bug #207 / GH #765 — saved-highlight restore modifier
// for `FoliateSpikeView` (AZW3/MOBI). Sibling of `+Selection.swift`
// (Bug #201 new-selection flow) and `+HighlightTap.swift` (Bug #199
// tap-on-existing-highlight flow).
//
// Flow:
//   1. Foliate-js emits `create-overlay` per section when that
//      section's SVG overlay is attached (foliate-host.js:48-52).
//   2. `FoliateSpikeView.Coordinator.handleMessage` posts
//      `.foliateOverlayReadyForSection` with `sectionIndex` +
//      `fingerprintKey` (Bug #207 fix in FoliateSpikeView.swift).
//   3. This modifier observes that notification (filtered by
//      `fingerprintKey`), queries `PersistenceActor.fetchHighlights`,
//      and hands the records to `FoliateHighlightRestoreDispatcher`
//      which fans each one out as a per-CFI
//      `.foliateRequestAnnotationJSCreate` notification.
//   4. The Coordinator's existing observer (Bug #201 PR #764) picks
//      up each per-CFI event and evaluates
//      `FoliateHighlightRenderer.addAnnotationJS` on the live
//      WKWebView, painting the highlight.
//
// **Why fire on every create-overlay (not just the first)**: Foliate-js
// emits one create-overlay per section. A highlight whose CFI lives
// in section 3 can't paint when section 0 fires create-overlay
// (its overlayer doesn't exist yet — view.js:384 `if (obj)`
// short-circuits). When the user navigates to section 3, its own
// create-overlay fires, the restore re-runs, and section-3 CFIs now
// resolve. `addAnnotation` is idempotent (view.js:387
// `overlayer.remove(value)` precedes add) so re-firing for
// already-painted sections is a no-op.
//
// **Why this lives in its own file**: same reason as
// `+Selection.swift` — the spike view is already 540+ lines after
// Bug #189 + Feature #53 WI-5 + Bug #199 + Bug #201 + Bug #207. The
// 300-line guideline (`50-codebase-conventions.md`) is binding for
// fresh additions; mirroring the +Selection pattern keeps each
// handler local and reviewable.
//
// @coordinates-with: FoliateSpikeView.swift,
//   FoliateHighlightRestoreDispatcher.swift,
//   PersistenceActor+Highlights.swift,
//   ReaderNotifications.swift (.foliateOverlayReadyForSection,
//   .foliateRequestAnnotationJSCreate)

#if canImport(UIKit)
import SwiftUI
import SwiftData
import OSLog

// MARK: - View modifier

/// Observes `.foliateOverlayReadyForSection`, queries persistence
/// for the book's saved highlights, and dispatches per-CFI restore
/// events via `FoliateHighlightRestoreDispatcher`.
private struct FoliateHighlightRestoreModifier: ViewModifier {
    let fingerprintKey: String?
    @Environment(\.modelContext) private var modelContext
    /// **Latest-wins coalescing** (Codex Gate 4 round 1, Medium): each
    /// `.foliateOverlayReadyForSection` event would otherwise spawn an
    /// untracked `Task` that re-fetches the full highlight set and
    /// re-dispatches every CFI. If two sections fire close together
    /// (initial book open + immediate scroll), the un-coalesced
    /// version produced duplicate fetches; if the reader closed
    /// mid-flight, the work didn't cancel. Tracking a single
    /// in-flight task and cancelling it before starting a fresh one
    /// gives us "latest event wins" semantics while remaining
    /// correct (JS `addAnnotation` is idempotent — the final
    /// dispatch covers every CFI whose overlayer is currently
    /// attached).
    @State private var restoreTask: Task<Void, Never>?

    func body(content: Content) -> some View {
        content
            .onReceive(
                NotificationCenter.default.publisher(for: .foliateOverlayReadyForSection)
            ) { note in
                guard let key = fingerprintKey,
                      let info = note.userInfo,
                      let receivedKey = info["fingerprintKey"] as? String,
                      receivedKey == key else { return }
                scheduleRestore(forFingerprintKey: key)
            }
            .onDisappear {
                restoreTask?.cancel()
                restoreTask = nil
            }
    }

    @MainActor
    private func scheduleRestore(forFingerprintKey key: String) {
        restoreTask?.cancel()
        let persistence = PersistenceActor(modelContainer: modelContext.container)
        restoreTask = Task { @MainActor in
            do {
                let highlights = try await persistence.fetchHighlights(forBookWithKey: key)
                // Bail if a newer event already cancelled us mid-fetch.
                if Task.isCancelled { return }
                FoliateHighlightRestoreDispatcher.dispatch(
                    highlights: highlights,
                    fingerprintKey: key
                )
            } catch is CancellationError {
                // Latest-wins coalescing OR view dismissal — expected
                // churn, not a failure. Logging would turn normal
                // navigation into noise. (Codex Gate 4 round 2, Low.)
                return
            } catch {
                let log = Logger(
                    subsystem: "com.vreader.app",
                    category: "FoliateSpikeView+Restore"
                )
                log.error(
                    "fetchHighlights failed: \(String(describing: error), privacy: .public)"
                )
            }
        }
    }
}

extension View {
    /// Bug #207 / GH #765: attach the saved-highlight restore handler
    /// to a `FoliateSpikeView.body`. Filters incoming
    /// `.foliateOverlayReadyForSection` notifications by
    /// `fingerprintKey` so concurrent Foliate readers don't
    /// cross-fire.
    func foliateHighlightRestoreHandler(fingerprintKey: String?) -> some View {
        modifier(FoliateHighlightRestoreModifier(fingerprintKey: fingerprintKey))
    }
}

#endif
