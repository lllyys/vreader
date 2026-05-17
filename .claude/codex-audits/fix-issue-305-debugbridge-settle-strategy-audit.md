---
branch: fix/issue-305-debugbridge-settle-strategy
threadId: 019e3443-3085-7d32-8bf1-729f687da31d
rounds: 3
final_verdict: ship-as-is
date: 2026-05-17
---

# Codex Audit — Bug #141 (GH #305): DebugBridge settle strategy

Implementation audit (Gate 4) of the settle-strategy wiring that replaces
`DebugReaderProbeAdapter.awaitSettle`'s 100ms `Task.sleep` placeholder with
a real render-settled signal (EPUB `didFinish`, AZW3/MOBI Foliate
`relocate`). DEBUG-only DevTools code.

Codex MCP, sandbox `read-only`, approval-policy `never`. Thread
`019e3443-3085-7d32-8bf1-729f687da31d`.

## Round 1 — 2 Medium, 1 Low

- **Medium #1 — same-key reopen leaks a settle waiter.** `unregister(_:)`
  cleared settle state only inside the `if activeReader === reader` block.
  When reader A is replaced by reader B for the same book before A's
  `onDisappear`, A's `unregister` is a no-op, so A's pending settle waiter
  survives until its timeout instead of failing when A dies.
  **Fixed**: `unregister(_:)` now calls
  `clearSettleState(forFingerprintKey:preservingToken:)` UNCONDITIONALLY
  (before the `if`), passing `preservingToken: expectedReaderToken` so the
  outgoing probe clears only its OWN `(key, token)` state and leaves the
  incoming reader B's state intact. The in-`if` call (normal close, nothing
  replaced the reader) keeps `preservingToken: nil` to clear everything.

- **Medium #2 — negative timeout traps.** `awaitReaderSettled` built
  `UInt64(timeout * 1_000_000_000)`; a negative `timeout` traps the
  conversion instead of producing `settleTimeout`.
  **Fixed**: `guard timeout > 0 else { throw .settleTimeout }`, placed
  AFTER the already-settled fast-path check so a settled key with a
  zero/negative timeout still fast-paths.

- **Low — missing edge-case tests.** No coverage for non-positive timeout
  or the same-key reopen path.
  **Fixed**: added `case9a/9b/9c` (zero / negative / zero-but-settled),
  `case10` (unregister cancels a pending waiter), `case11` + `case11b`
  (same-key reopen: A's late unregister preserves B's settle state, clears
  A's, and does not cancel a waiter on B's token).

Codex explicitly found NO double-resume path: all resume paths are
`@MainActor` and each removes the waiter before resuming.

## Round 2 — 1 Low

- **Low — test file size.** The settle test file reached 443 lines, past
  the repo's ~300-line convention.
  **Fixed**: split into `SettleStubProbe.swift` (33), `…SettleCoreTests`
  (191), `…SettleCleanupTests` (197), `…SettleEdgeCaseTests` (99). No test
  bodies changed — same 17 tests redistributed.

Codex confirmed both round-1 Mediums genuinely resolved: the
non-positive-timeout guard prevents the trap and preserves the settled
fast path; the unconditional `unregister` cleanup + `preservingToken`
closes the reopen leak with no residual hole. The double `clearSettleState`
call in the normal-close path is safe (both `@MainActor`, no suspension
point between them, each call removes a bucket before resuming so no
double-resume).

## Round 3 — clean

Confirmed the test-file split introduced no behavior change, no lost
coverage, no duplicate `SettleStubProbe`, and all 4 new files are
`#if DEBUG`-gated. Verdict: `ship-as-is`.

## Final verdict

**ship-as-is** — zero open Critical/High/Medium/Low findings after 3
rounds. Test gate: 17 settle tests (Core/Cleanup/EdgeCase suites) + 8
adapter tests + 24 registry tests all pass on iPhone 17 Pro Max.
