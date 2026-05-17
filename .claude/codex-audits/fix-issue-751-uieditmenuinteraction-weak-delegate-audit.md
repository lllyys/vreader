---
branch: fix/issue-751-uieditmenuinteraction-weak-delegate
threadId: 019e345b-e17f-7131-b698-a0e90342ada1
rounds: 3
final_verdict: ship-as-is
date: 2026-05-17
---

# Codex Audit — Bug #205 / GH #751

UIEditMenuInteraction logs `[EditMenuInteraction] <compose failure>`; the
TXT tap-on-highlight delete menu never appears.

**Files audited:**
- `vreader/Views/Reader/HighlightActionPresenter.swift`
- `vreaderTests/Views/Reader/UIKitHighlightActionPresenterTests.swift`

## Root cause

`UIEditMenuInteraction` holds its `delegate` *weakly* (confirmed from the
iOS 26.5 SDK header: `@property (nonatomic, weak, nullable, readonly)
id<UIEditMenuInteractionDelegate> delegate;`). The pre-fix presenter
created `PresenterDelegate` as a local in `present(for:in:)` with no
owning reference, so it deallocated the instant `present` returned. UIKit
then queried a nil delegate when it asynchronously composed the menu, got
no menu, and logged the compose failure. Also confirmed: the
`UIEditMenuInteractionDelegate` protocol is NOT `NS_SWIFT_UI_ACTOR` (only
`UIEditMenuConfiguration` / `UIEditMenuInteraction` /
`UIEditMenuInteractionAnimating` are), so the delegate methods are
imported `nonisolated`.

## Round 1 — 3 findings

| # | Severity | Finding | Resolution |
|---|---|---|---|
| 1 | High | First fix kept the delegate in the presenter's `liveDelegates` array, but the reader containers construct `UIKitHighlightActionPresenter()` inline in `body`; `TXTTextViewBridge.updateUIView` rebinds the coordinator's presenter to a fresh instance every SwiftUI render, deallocating the old presenter — and its `liveDelegates` — putting the bug back one level up. | **Fixed.** Rewrote: the delegate is now associated onto the `UIEditMenuInteraction` itself (`objc_setAssociatedObject`, `OBJC_ASSOCIATION_RETAIN_NONATOMIC`). The interaction — retained by the host view — owns the delegate; the presenter is removed from the ownership graph entirely and is now stateless. Presenter ephemerality is irrelevant. |
| 2 | Medium | `liveDelegates` was pruned only from `willDismissMenuFor`; if that callback never fires the delegate leaks for the presenter's lifetime. | **Fixed by the round-1 rewrite + round-2 sweep.** Lifetime is now bound to the interaction (hence the host view). See round 2. |
| 3 | Medium | Tests asserted internal bookkeeping (`liveDelegateCountForTests`), not the regression boundary. | **Fixed.** Tests now assert `interaction.delegate != nil` after `present` returns — since the interaction holds `delegate` weakly, a non-nil read directly proves the delegate is retained (pre-fix it read nil). |

## Round 2 — 2 findings

| # | Severity | Finding | Resolution |
|---|---|---|---|
| 1 | Medium | Not leak-free on all paths: if `presentEditMenu` aborts and `willDismissMenuFor` never fires on a still-live view, the interaction + associated delegate linger until the view is torn down. | **Fixed.** `present` now calls `removePriorMenuInteractions(from:)` — sweeps any edit-menu interaction a prior `present` installed on the same view (keyed on the delegate association) before adding the new one. A superseded/aborted presentation cannot accumulate. The text view's own built-in `UIEditMenuInteraction` has no association under our key and is left in place. |
| 2 | Low | Header comment said `OBJC_ASSOCIATION_RETAIN`; code uses `.OBJC_ASSOCIATION_RETAIN_NONATOMIC`. | **Fixed.** Comment corrected. |

## Round 3 — clean

Verbatim: "Clean. I don't see any remaining findings in the code you
showed." Confirmed: the sweep does not touch unrelated interactions;
sweep ordering (associate → sweep → add) means the new interaction never
sweeps itself; re-entrancy from sweeping a live interaction is harmless
(idempotent `removeInteraction`, `FireOnceBox`-guarded completion); no
mutation-during-iteration (snapshot then remove, all `@MainActor`); no
remaining leak path, dead code, or comment drift.

## Lifetime summary (post-fix)

- **Normal dismiss:** `willDismissMenuFor` removes the interaction from
  the host view → interaction deallocates → associated delegate
  deallocates.
- **Superseded presentation:** the next `present` on the same view
  sweeps the prior presenter-installed interaction.
- **Host view torn down mid-menu:** view deallocates → its `interactions`
  array deallocates → interaction deallocates → association released →
  delegate deallocates. No callback required.

No retain cycle: `hostView` is weak; the interaction owns the delegate;
the view owns the interaction; the delegate does not retain the view.

## Verdict

**ship-as-is.** Zero open findings after 3 rounds. The fix resolves the
root cause and the two follow-on lifetime concerns the audit surfaced.
