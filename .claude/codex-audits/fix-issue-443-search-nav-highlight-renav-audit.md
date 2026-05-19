---
branch: fix/issue-443-search-nav-highlight-renav
threadId: 019e400c-aa4e-7e03-8c6e-ace56365cc73
rounds: 2
final_verdict: ship-as-is
date: 2026-05-19
---

# Codex Audit — Bug #154 / GH #443

Search-tap navigation in TXT reader skips the temporary yellow highlight at the
destination. Runtime-traced root cause: a search-nav to an already-current
target re-sets `uiState.highlightRange` / `scrollToOffset` to values they
already hold — an `@Observable` no-op write that never re-evaluates the SwiftUI
body — so the reader bridge's `updateUIView` never runs and the temporary
highlight is never re-painted.

## Fix summary

- `TextReaderUIState` + `ReaderNotificationHandlerStateProtocol`: new monotonic
  `highlightNonce: Int`.
- `ReaderNotificationHandlers.handleNavigateToLocator`: bumps the nonce (`&+=`)
  after the nil-offset guard, on every navigate event.
- `ReaderNotificationModifier`: switched from a duplicate inline copy of the
  navigate logic to call the extracted, unit-tested `handleNavigateToLocator`.
- `TXTTextViewBridge` + `TXTChunkedReaderBridge`: new `highlightNonce` param;
  new pure static `TXTTextViewBridge.highlightShouldReapply(rangeChanged:nonceChanged:)`
  folds a nonce change into the highlight-change signal so a repeat-nav
  re-paints + re-arms the 3 s auto-clear timer even when the NSRange is
  byte-for-byte identical.
- 4 TXT bridge sites + 1 MD bridge site pass `highlightNonce: uiState.highlightNonce`.

## Round 1 — 2 findings (both fixed)

| File:line | Severity | Issue | Resolution |
|---|---|---|---|
| `TXTTextViewBridge.swift` (auto-clear timer) | Medium | The 3 s auto-clear timer nils only `coordinator.currentHighlightRange`, never `uiState.highlightRange`. A later unrelated `updateUIView` (font/theme change) sees `highlightRange != currentHighlightRange` and re-paints the already-expired temporary highlight. | **Fixed.** Added `onTemporaryHighlightCleared: (@MainActor () -> Void)?` to `TXTTextViewBridge`; the container wires it to `uiState.highlightRange = nil`. Invoked from the timer closure AND from `clearSearchHighlightIfTemporary` (user-scroll + `.searchHighlightClear` paths), so model + coordinator clear in lockstep. Added a `guard currentHighlightRange != nil` to `clearSearchHighlightIfTemporary` so a stray scroll callback after the highlight already cleared is a true no-op. |
| `TXTChunkedHighlightHelper.swift:120` | Medium | Same drift in the chunked path — `startHighlightAutoClearTimer` clears coordinator-local state but never `uiState.highlightRange`. | **Fixed.** Added `onTemporaryHighlightCleared` to `TXTChunkedReaderBridge` + its coordinator; the timer closure now fires it after `clearHighlight` + `lastHighlightRange = nil`. The `applyHighlight`-driven `clearHighlight` (highlight-replacement, not an expiry) deliberately does NOT fire the callback. |

## Round 2 — 1 finding (separately filed, pre-existing)

| File:line | Severity | Issue | Resolution |
|---|---|---|---|
| `TXTChunkedReaderBridge.swift` (`Coordinator.init`) | Medium | The chunked bridge has no `.searchHighlightClear` observer and no scroll-driven clear — so for large / continuous-chaptered TXT, a new search or user scroll never clears the temporary highlight (only the 3 s timer does). | **Accepted / separately filed as Bug #232 / GH #960.** This is a pre-existing structural gap in `TXTChunkedReaderBridge` (its `Coordinator.init` has always been bare), NOT a regression introduced by this fix, and a different symptom from Bug #154's repeat-nav repaint defect. Codex explicitly agreed (round-3 reply) the disposition is reasonable: "The chunked `.searchHighlightClear` / scroll-clear gap is a separate pre-existing defect, not part of Bug #154's confirmed root cause… I would not require that to be fixed in this PR, provided you file it separately." Filed per the repo's discover-a-bug → file-don't-fix-in-an-unrelated-PR rule. The round-1 chunked finding (timer-path drift) WAS fixed here because the 3 s timer is the path Bug #154's nonce directly interacts with. |

## Round 2 — items verified sound

The Codex round-2 verification confirmed, with zero new findings on the round-1
fix: the non-chunked bridge clears model + coordinator in lockstep on
timer/scroll/`.searchHighlightClear`; the `onTemporaryHighlightCleared`-triggered
re-render does not loop or spuriously re-arm (`highlightShouldReapply(false, false)`
is false when the callback nils `uiState.highlightRange` against an
already-nil coordinator range + unchanged nonce); the `[uiState]` closure
capture is correct and free of retain-cycle concern; the chunked replacement
path correctly does not fire the callback; no new Swift 6 actor issue.

Also verified round 1: the nonce solves the repeat-nav no-op-write case; both
bridges use `highlightShouldReapply`; `&+=` wraparound is safe with the bridges'
`!=` comparison; the nil-offset guard avoids spurious nonce bumps; the
modifier's duplicate navigate logic is fully removed; the `@MainActor` story is
consistent.

## Verdict

**ship-as-is.** Both round-1 findings fixed and re-verified clean. The single
round-2 finding is a pre-existing, separately-filed bug (#232) explicitly out of
this PR's scope, with Codex's concurrence. RED→GREEN proven by reverting the
fix's behavior and observing exactly the 3 Bug #154 tests fail. The fix is
correct and complete for Bug #154's actual symptom (repeat-nav repaint) plus
the timer-expiry model-drift that the nonce interacts with.
