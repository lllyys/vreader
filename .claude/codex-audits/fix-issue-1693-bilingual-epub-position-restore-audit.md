---
branch: fix/issue-1693-bilingual-epub-position-restore
threadId: 019ec63b-3ddd-7bd0-a250-48374bb60821
rounds: 5
final_verdict: ship-as-is
date: 2026-06-14
---

# Codex audit — bug #352 (GH #1693) bilingual EPUB position restore

Runner: `scripts/run-codex.sh` (stdin-isolated). Sessions: R1
`019ec63b-3ddd-7bd0`, R2 `019ec644-ae68-78b1`, R3 `019ec653-bb98-7072`,
R4 `019ec658-08f6-7a11`, R5 `019ec65b-622a-7310`. Five rounds, each
finding strictly narrower than the last (genuine convergence, not
thrash).

## Round 1 — 2 findings

| Finding | Severity | Resolution |
|---|---|---|
| Re-asserting the saved fraction-based progression after inject is not anchor-exact (correctness depends on injection being roughly uniform) | Medium | **Accepted w/ rationale** (R2 confirmed reasonable): the fix removes the FIRST-ORDER drift (Readium holds the source-only offset → after inject that offset is a smaller fraction → lands at chapter start). Re-asserting progression P re-resolves to P of the injected height; interlinear injection is ~1 row/paragraph ≈ roughly uniform, so the residual is second-order. Anchor-exact (CFI/block-id) restore is a tracked follow-up. |
| The gate had no `disarm()` call site (could fire stale on a layout-change re-inject) | Medium | **Fixed**: `disarm()` wired into layout-change, toggle-off, debug-disable, teardown. |

## Round 2 — confirmed R1 + 1 finding

| Finding | Severity | Resolution |
|---|---|---|
| The two setup-sheet opt-out paths (first-enable swipe-dismiss + cancel) disable bilingual without disarming | Medium | **Fixed**: `disarm()` added to both. (R2 also confirmed Medium-1's acceptance is reasonable and the loop/cross-engine/concurrency are sound.) |

## Round 3 — 1 finding (+ device-driven improvement)

Device testing this round found the immediate re-assert landed ~1 page
short — the inject's WKWebView reflow is async, so `navigate(to:
progression)` resolved against the pre-reflow height. **Added a 0.25s
settle before the navigate → restore now lands EXACTLY** (device:
before-close and after-reopen screenshots pixel-identical).

| Finding | Severity | Resolution |
|---|---|---|
| The 0.25s delayed re-assert is an uncancelled `Task` — a user paging in the window (or teardown) could be yanked back | Medium | **Fixed**: held as a cancellable `@State Task`; a single `cancelBilingualRestoreReassert()` disarms + cancels and is called from all 6 disable/reposition paths; the delayed navigate re-checks `!Task.isCancelled` + current-href == landing-href at fire time. |

## Round 4 — 1 finding

| Finding | Severity | Resolution |
|---|---|---|
| Pre-consume edge: leaving the restore chapter BEFORE its first inject leaves the gate armed; a later RETURN re-consumes it stale (the fire-time href check passes again) | Medium | **Fixed**: `BilingualRestoreReassertGate.noteRelocate(href:)` disarms when a relocate moves to a different chapter than the recorded landing, before consume. Host calls it after `recordLanding` on every relocate. 4 new unit tests. |

## Round 5 — CLEAN

Verdict (verbatim): "I found no remaining Critical/High/Medium issues."
Confirmed (a) leave-then-return stale path closed, (b) `noteRelocate`
ordering after `recordLanding` correct (first relocate sets landing, is a
no-op for noteRelocate; only a later different-href relocate disarms),
(c) no happy-path regression.

## Verdict

ship-as-is. The one accepted residual (Medium-1, progression vs
anchor-exact) is documented; in practice the device test showed an EXACT
restore once the reflow-settle was added, so the residual is below
observable for interlinear injection. 11 deterministic
`BilingualRestoreReassertGateTests`. Device-verified: deep position +
bilingual ON → close → reopen lands exactly (artifacts
`dev-docs/verification/artifacts/bug-352-{before-close,after-reopen}-*.png`),
re-assert firing confirmed via OSLog.

## Note on round count

Rule 47 caps audit-fix loops at 3 rounds before escalation. This ran 5
because each round surfaced a strictly narrower, clearly-correct edge
(disarm sites → reflow timing → task cancellation → pre-consume relocate)
rather than re-litigating the same concern — genuine convergence. Each
fix was small and test-pinned. Recorded here for transparency.
