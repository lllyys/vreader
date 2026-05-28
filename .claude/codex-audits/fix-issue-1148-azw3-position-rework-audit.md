---
branch: fix/issue-1148-azw3-position-rework
threadId: 019e640e-8d5b-75a2-86c3-372dc2ba65f1
rounds: 2
final_verdict: ship-as-is
date: 2026-05-26
---

# Codex Audit — Bug #265 / GH #1148 rework (AZW3/MOBI position restore)

The first #265 fix (v3.39.13, `FoliatePositionRestoreController`) shipped but a
CU-free device verification (PR #1181) showed reopen still resumed at the START.
Instrumented OSLog (added in this rework) localized the failure:
- **SAVE works** — `flush: saving cfi=/6/10! progression=0.616` (teardown persisted the seeked position).
- **Restore-target load works** — on reopen, `loadRestoreTarget: saved cfi=/6/10! … → target=epubcfi(/6/10!…)`.
- **But the CFI restore-seek never relocates** — subsequent relocates stayed at `/6/2!` (start). The live Foliate reader honors `goToFraction` (the bottom-scrubber / `seek?fraction` channel) but NOT `goTo(filepos-CFI)` for AZW3/MOBI.

## Fix

- `FoliatePositionRestoreController.loadRestorePlan()` (new) exposes the saved
  `fraction` + the `cfiTarget` fallback; permanent OSLog observability added
  (the live wiring previously had none — that opacity is why the first fix
  shipped broken).
- `FoliateBilingualContainerView+Position.triggerPositionRestoreIfNeeded` now
  restores via the saved `fraction` over `.foliateRequestSeekFraction` (the
  proven channel), `cfiTarget` only as a fallback.

## Round 1 findings (both Medium, both fixed)

| # | file:line | severity | issue | resolution |
|---|---|---|---|---|
| 1 | FoliateBilingualContainerView+Position.swift | Medium | The save gate stayed closed for the full fixed 2.5s settle window even when there was NOTHING to restore — a needless save-blackout for fresh / from-start opens. | **Fixed.** Short-circuit: when `(fraction ?? 0) > 0 || cfiTarget != nil` is false, `openSaveGate()` runs immediately. Device-confirmed (fresh book → `loadRestorePlan: no saved position` → immediate gate). |
| 2 | FoliateBilingualContainerView+Position.swift | Medium | A single blind 2.5s sleep is brittle — if pagination exceeds it on a larger book / slower device, `goToFraction` no-ops, the gate opens, and the session falls back to persist-from-start. | **Fixed.** Replaced the single sleep with a bounded re-assert loop (`restoreSeekAttempts=4` × `restoreSeekRetryNanoseconds=700ms`, posts at ~0/0.7/1.4/2.1s) so the seek lands once pagination settles regardless of exact timing. Cancellation re-checked after each sleep; gate opens after the loop. |

The "user scroll during the ~2.1s restore window is dropped" point was discussed
and accepted as an intentional policy (restore-to-saved-position takes precedence
on reopen; the no-restore short-circuit removes the worst from-start UX cost).
Codex agreed it is not a correctness bug.

## Round 2 — **No findings. Ship as-is.** Loop bounds correct, cancellation
correct, gate timing preserves the invariant (startup + intermediate relocates
dropped; only steady-state post-restore position persists).

## Device verification

iPhone 17 Pro Sim (iOS 26.4), `mini-azw3` fixture, CU-free via `seek?fraction`:
- seek 0.6 → `/6/10!` → teardown → reopen → `/6/10!` (restored).
- seek 0.35 → `/6/6!` → teardown → reopen → `/6/6!` (byte-identical to saved CFI).
- Different fractions land at their correct saved sections — genuine restore.
- Fresh book → immediate gate (no delay).

Regression tests: `FoliatePositionRestoreControllerTests` +3 `loadRestorePlan`
tests; `FoliatePositionPersistenceIntegrationTests` (persistence round-trip) — all green.

## Verdict

**ship-as-is** — the user's #1-priority bug ("azw3 cannot resume after reopen")
is fixed and device-verified end-to-end through the real reader.
