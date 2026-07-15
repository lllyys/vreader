---
branch: feat/138-wi5b-body-windowed
threadId: 019f6489-fb4b-7d60-80ac-c53ccb166524, 019f6498-2f9c-78a1-a736-77cf457a39fd, 019f64a4-8d66-71d1-9040-ecab1b3565cd
rounds: 3
final_verdict: ship-as-is
---

# Gate-4 Codex audit — feature #138 WI-5b (TxtPagedBody windowed pagination lifecycle)

Auditor: Codex `gpt-5.5` / reasoning=high (read-only sandbox), 3 rounds.
Scope: `android/app/src/main/kotlin/com/vreader/app/reader/TxtReaderBody.kt` diff
(`origin/main..HEAD`). Author/auditor separation preserved (Codex ≠ the implementing
Claude session).

Raw round outputs: `.reports/feat138-wi5b-audit.txt`,
`.reports/feat138-wi5b-audit-r2.txt`, `.reports/feat138-wi5b-audit-r3.txt`.

## Round 1 — 2 High + 1 Medium (all fixed)

- **H1 (lost-update / stale-snapshot replay):** the remembered snapshot hand-off
  flow was not reset on a new pass, so the restarted main collector replayed the
  previous generation's last snapshot and consumed the once-per-pass clamp on stale
  data. **Fix:** null-reset the hand-off flow(s) before bumping `openSeq`, so the
  first non-null the collector sees is genuinely this pass's first window.
- **H2 (reveal yanks a user who paged away):** the settled collector treated
  `pendingResumeReveal != null` as "programmatic pending", suppressing a real user
  swipe while the reveal was merely armed → the reveal could later yank. **Fix:**
  `programmaticPending` keys only on `localScrollTarget` (reflow clamp) or an
  in-flight `resumePage` recreation — not on a merely-armed reveal.
- **M (append-only violation):** an on-demand `ensureMeasuredThrough` snapshot,
  captured before a concurrent background append advanced, could transiently shrink
  `pageCount`. **Fix:** a never-shrink guard in the main collector + the jump effect
  (drop a within-pass snapshot smaller than the installed one; never on the pass's
  first snapshot, so a legitimate reflow's smaller first window still installs).

## Round 2 — 2 findings (all fixed)

- **H1 (StateFlow conflation):** a conflated `MutableStateFlow` could drop the true
  first window under a fast republish burst → a deep resume mis-routed through the
  unconditional clamp. **Fix:** switched to a non-conflated buffered
  `MutableSharedFlow` (`replay=1`).
- **H2/M (`restored` flips before the recreation lands):** the reveal flipped
  `restored` when it QUEUED the recreation, not when it LANDED. **Fix:** `restored`
  flips in the `recreationSettled` branch (the recreated pager settling on its
  page); the no-op-reveal + user-takeover paths flip immediately (nothing to await).

## Round 3 — 1 High + 1 Medium (all fixed)

- **H1 (tryEmit + SUSPEND overflow contradiction):** `tryEmit` on a `SUSPEND`-overflow
  SharedFlow does not suspend — it drops and returns false (ignored). **Fix:**
  `BufferOverflow.DROP_OLDEST` (buffer 256) so every off-main `tryEmit` succeeds
  without suspending; dropping an intermediate window is harmless (the frontier grows
  monotonically → the clamp decision stays correct; the final complete snapshot always
  lands) and the session worker never blocks.
- **M (in-progress swipe from page 0 before settledPage changes):** a drag begun
  exactly as the anchor seals could be overridden by the recreation, because
  `userInteractedSinceOpen` is only set on a SETTLED non-zero page. **Fix:** the reveal
  also drops when `pagerState.isScrollInProgress` from page 0.

Round 3 additionally CONFIRMED the round-2 `restored`-timing fix correct.

## Verdict — ship-as-is

All Critical/High/Medium findings across the 3 rounds are resolved in code and the
fixes are covered by the connected tests. No open Critical/High/Medium remains. The
only residual observation is emulator-timing flakiness of the connected tests under a
sustained multi-class run (documented MEMORY #133/#127) — a test-execution property,
not a code defect: every affected class (`TxtPagedWindowedConnectedTest`,
`TxtPagedBodyConnectedTest`, `TxtPagedSourceOffsetJumpConnectedTest`) passes in
isolation on a rested emulator, which is how the Gate-5 lane runs them.

Confirmed clean by the auditor across rounds: no cache-clear-on-append, no busy/
frame-poll loop, the body no longer owns `activeToken` (cancellation/generation live
in `PaginationSession`), and the off-main session callbacks are marshalled to the main
thread before any Compose-state write.
