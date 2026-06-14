---
branch: fix/issue-1692-selection-card-quick-release
threadId: 019ec603-8c42-7e62-8b1f-d652bd4c1750
rounds: 1
final_verdict: ship-as-is
date: 2026-06-13
---

# Codex audit — bug #351 (GH #1692) selection-card quick-release flicker

Runner: `scripts/run-codex.sh` (codex exec, stdin-isolated), session
`019ec603-8c42-7e62-8b1f-d652bd4c1750`, 1 round.

## Round 1 — No findings

Verdict (verbatim summary): the fix matches the root cause — the
outside-tap dismiss path checks a present-time grace before dismissing;
`presentedAt` is refreshed on every `.readerSelectionPopoverRequested`
re-post (covers the original quick-release AND the handle-drag re-post),
and `dismiss()` clears it so state doesn't leak across dismiss/reselect.
The #338 contracts are preserved: drag-to-expand still works (gesture
still simultaneous + tap-only) and a deliberate outside-tap still
dismisses once the 0.35s window expires.

Edge cases reviewed (all clear):
- `pending = next` action path not resetting `presentedAt`: **not a live
  problem** — every shipped action route is `.dispatched` (the router no
  longer returns `.deferredNotYetWired` for shipped actions), so `next`
  is always nil there and the next present re-stamps `presentedAt`
  regardless. Accepted with rationale.
- Rapid re-selection: each post stamps a fresh `presentedAt`. Covered.
- A genuine dismiss tap within 0.35s is intentionally swallowed — an
  explicit, test-pinned tradeoff consistent with the root cause.
- `@MainActor`/`Date` usage acceptable; the policy is deterministic and
  unit-tested with injected `Date`s; only the UI integration points call
  `Date()` directly.

A true "ignore the finger-up that completed this selection" identity
signal would be cleaner but isn't exposed across the SwiftUI
`SpatialTapGesture` / UIKit / Readium boundary; the timing guard is the
reasonable fix given that constraint.

## Verdict

ship-as-is. Zero findings. Test gate
`vreaderTests/SelectionPopoverPresenterTests` green (5 new
`SelectionPopoverOutsideTapPolicyTests` + the existing suites). Device
verification recorded in the PR.
