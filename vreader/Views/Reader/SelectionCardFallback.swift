// Purpose: Bug #350 — the TXT/MD selection card rode UIKit's
// `editMenuForTextIn` request EXCLUSIVELY. UIKit does not request an
// edit menu for every selection (observed: the first long-press of a
// fresh session can select — handles visible — without a menu request;
// synthetic HID selections never produce one), so a live selection
// could exist with NO card until a handle drag finally triggered a
// request. This helper adds the triage's fix-direction: a DEBOUNCED
// selection-finalized fallback that posts the card request when a
// non-empty selection settles, deduplicated against the menu fast
// path in both directions.
//
// @coordinates-with: TXTTextViewBridgeCoordinator.swift,
//   TXTChunkedReaderBridge.swift, SelectionPopoverPresenter.swift

#if canImport(UIKit)
import Foundation
import UIKit

/// Debounced selection-finalized card fallback (bug #350). One instance
/// per text-view coordinator. `@MainActor` — driven from UIKit delegate
/// callbacks.
@MainActor
final class SelectionCardFallback {

    /// How long a non-empty selection must stay unchanged before the
    /// fallback posts ("finalized"). Long enough that an in-progress
    /// long-press/drag keeps superseding it; short enough that the card
    /// feels immediate when UIKit never requests a menu.
    static let debounceSeconds: TimeInterval = 0.35

    private var workItem: DispatchWorkItem?
    private var lastPostedRange: NSRange?
    private let debounce: TimeInterval

    init(debounce: TimeInterval = SelectionCardFallback.debounceSeconds) {
        self.debounce = debounce
    }

    /// Call from `textViewDidChangeSelection`. An empty selection cancels
    /// any pending post and clears the dedup state (so re-selecting the
    /// same word after a dismissal posts again). A non-empty one arms the
    /// debounce; `post` runs only if no newer change superseded it and
    /// neither path already posted this exact range. `post` receives the
    /// armed range and should re-validate it against the live selection.
    func selectionChanged(range: NSRange, post: @escaping @MainActor (NSRange) -> Void) {
        workItem?.cancel()
        workItem = nil
        guard range.length > 0 else {
            lastPostedRange = nil
            return
        }
        let item = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.workItem = nil
            guard self.lastPostedRange != range else { return }
            self.lastPostedRange = range
            post(range)
        }
        workItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + debounce, execute: item)
    }

    /// Whether the `editMenuForTextIn` fast path should post for `range`
    /// (false when the fallback already posted the same range).
    func shouldMenuPathPost(range: NSRange) -> Bool {
        lastPostedRange != range
    }

    /// Record that the menu fast path posted `range`, so the pending
    /// fallback (if any) dedups against it.
    func recordMenuPathPost(range: NSRange) {
        lastPostedRange = range
    }

    /// Cancel any pending post and clear state (teardown / bridge reuse).
    func cancel() {
        workItem?.cancel()
        workItem = nil
        lastPostedRange = nil
    }
}
#endif
