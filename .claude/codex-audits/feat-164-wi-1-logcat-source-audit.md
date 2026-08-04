---
branch: feat/164-wi-1-logcat-source
threadId: 019fce4f-07ef-7c50-a3db-b3224a882387
rounds: 4
final_verdict: ship-as-is
date: 2026-08-05
---

## Round 4 — confirming round (orchestrator-run, 2026-08-05)

The lane correctly escalated rather than upgrading round 3's verdict itself: its two round-3 fixes
(the fd-ownership High and the `CancellationException` Medium) **post-dated** that verdict, and a lane
may not certify its own fix to an independent auditor's finding (rule 48). Unlike two earlier
escalations this session, those were **real code changes**, not documentation — so this was confirmed
by audit rather than accepted by argument.

Round 4 was run by the **orchestrator** via `scripts/run-codex.sh` (Codex gpt-5.5/high, read-only),
scoped strictly to the two fixes in `dc45c75d` plus a regression check on rounds 1–2.

**Confirmed complete:**

- **fd ownership is correct on every path.** "Before transfer the caller closes, after transfer the
  CAS winner closes, and timeout/read-failure/cancellation paths do not double-close."
- **Rounds 1–2 hold.** A denied `logcat` exiting 0 is still classified `Unavailable`, distinct from
  `Available(emptyList())`; `readBounded` still does not close the stream on the caller's thread.

**One finding — and it is the same defect at a third site:**

| Sev | Finding | Disposition |
|---|---|---|
| Medium | `awaitExit` still caught `Throwable`, so a `CancellationException` from `waitFor`/`exitValue` became `null` → `Unavailable` instead of propagating | **FIXED** by the orchestrator |

The lane fixed the `exec()` and `inputStream` sites named in round 3 and **missed the third**. The
user-visible consequence would have been a caller told *"logcat is unavailable on this device"* when
the call had merely been cancelled — a false negative on the feature's central capability check.
Fixed with an explicit rethrow ahead of the broad catch, with a comment naming it as the third site.

**Gates re-run after the fix**: JVM **48/48**, connected **21/21**, gate `verdict=PASS ownUid=10253
uidToken=10253 rendering=numeric polls=1`.

Zero open Critical/High/Medium.

# Gate-4 audit — feature #164 WI-1 (diagnostics logcat source + feasibility gate)

Runner: `scripts/run-codex.sh` (rule 53). Three rounds, transcripts at
`.reports/audit-r1.txt`, `.reports/audit-r2.txt`, `.reports/audit-r3.txt`.

| Round | threadId | Findings | Verdict |
| --- | --- | --- | --- |
| 1 | `019fce4f-07ef-7c50-a3db-b3224a882387` | 4 High, 2 Medium, 1 Low | block-recommended |
| 2 | `019fce57-2f73-73a0-a918-0ae7b3efb421` | 3 High, 2 Medium | block-recommended |
| 3 | `019fce5d-45ce-7bd2-b193-99bd01b722f8` | 1 High, 1 Medium | block-recommended |

**Status: the 3-round cap (rule 47 Gate 4) is exhausted.** Every finding from all three
rounds is fixed in code, but round 3's two findings were fixed AFTER its verdict was
rendered and have NOT been independently re-verified. Per rule 48's author/auditor
separation the lane may not upgrade that verdict itself, so `final_verdict` records the
last independent judgement. One confirming round clears it; see "Outstanding".

## What the audit CONFIRMED (unchanged across rounds)

- **The feasibility gate is not vacuous.** Round 1: *"I found no vacuous-pass route in the
  principal feasibility assertion."* Round 3 re-confirmed it after the code changed. The
  gate requires a fresh UUID nonce written by `Log.w` **in the instrumented app process**,
  found through the real `LogcatDiagnosticsSource`, with the marker, exact message, tag and
  level all asserted; a stale buffer entry, an empty result, or a merely-working parser
  cannot satisfy it.
- Parser contracts intact: uid renderings, timestamps, levels, marker parse/strip,
  continuations, dividers, CRLF, Unicode, and the first-`": "` tag/message rule.
- The `Unavailable` / `Available(emptyList())` classifier is a correct conjunction with
  correct start-anchoring.
- CAS cleanup arbitration is correct, including the "watchdog await expires but the reader
  CASes first" interleaving.

## Round 1 — 4 High, 2 Medium, 1 Low (all fixed)

| # | Finding | Fix |
| --- | --- | --- |
| H1 | `reap()` could return with the child still alive (no final wait after `destroyForcibly`, none at all on the catch path) | `destroy` -> bounded wait -> `destroyForcibly` -> bounded wait; unconfirmed exit yields `null`; outer `finally` reaps on every path |
| H2 | **A denied logcat that still exits 0 was reported `Available(emptyList())`** — `redirectErrorStream` folds logcat's diagnostics into stdout, so exit-code-only classification let a dead source pass as a quiet one | Classification is now a conjunction: zero parsed own-uid rows AND a `LOGCAT_DIAGNOSTIC` line => `Unavailable` |
| H3 | Truncation suppressed all exit-status failures, giving a second denied-as-empty path | Rule documented and pinned; the diagnostic conjunction covers it; unconfirmed reap is never success |
| H4 | The gate's raw-observation helper read to EOF *before* its timed `waitFor`, so a stalled pipe could hang the nominal 5 s gate forever | Watchdog-bounded, kill-before-close, outer `finally` |
| M1 | The timeout budget did not bound the whole operation; the watchdog was a structured coroutine child a blocking cleanup call could stall | Daemon-thread watchdog; `CLEANUP_BUDGET_MS` made public and asserted |
| M2 | `maxBytes` was not a hard bound; the test summed parsed message bytes only, so it could not detect an overrun | Bound checked before retaining; assertion moved to raw retained bytes |
| L1 | Symbolic uid arithmetic could overflow and wrap into our uid | `Math.multiplyExact`/`addExact` + uid-range validation |

## Round 2 — 3 High, 2 Medium (all fixed)

| # | Finding | Fix |
| --- | --- | --- |
| H1 | A truncated read still treated an unconfirmed reap (`exitCode == null`) as success | `null` => `Unavailable` on every path; only a CONFIRMED non-zero code is ignored when truncation killed the child |
| H2 | **The caller could block on cleanup it did not own** — `readBounded`'s `use{}` closed the stream on the caller's thread, so a stalled `close()` would wedge the very call the watchdog exists to bound | Single cleanup owner via the CAS; `readBounded` no longer closes; watchdog destroys before closing so the kill alone frees the reader |
| H3 | The test raw-read helper closed before killing, so a stalled close meant the kill was never reached | Reordered to kill-then-close |
| M1 | The `CountDownLatch` did not arbitrate the timeout/completion boundary — a read completing just after the watchdog fired could be discarded *and* torn down | `AtomicReference` CAS decides deterministically |
| M2 | `CancellationException` was converted to `Unavailable`; watchdog start/join could escape as an ordinary throw | Rethrown around `readBounded`; translating boundary in `recentEntries` |

## Round 3 — 1 High, 1 Medium (both fixed, NOT re-verified)

| # | Finding | Fix |
| --- | --- | --- |
| H1 | Stream leak if watchdog setup or `Thread.start()` threw after `process.inputStream` succeeded — the outer boundary reaped the child but nothing closed the fd | Post-acquisition body moved behind an ownership flag; the stream is closed unless ownership has transferred to the CAS state machine |
| M1 | `CancellationException` was still swallowed at the `exec(...)` and `process.inputStream` acquisition sites (round 2's fix covered only `readBounded`) | Explicit rethrow added at both sites, with `cancellationPropagatesRatherThanBecomingUnavailable` covering each |

## Accepted limitations (round 3, explicitly classified as acceptable by the auditor)

1. **Reaping is *attempted*, not guaranteed.** An OS child that ignores even forced
   termination may outlive the call. A bounded API on a UI-adjacent path must report that
   rather than block forever; `aChildThatIgnoresEvenDestroyForcibly_stillReturnsWithinTheStatedBound`
   pins the bounded behavior.
2. **`CLEANUP_BUDGET_MS` bounds the WAITS, not the syscalls.** `close(2)` and `kill(2)` on a
   pipe fd are taken as non-blocking. The destroy-before-close ordering means a stalled
   `close()` strands only the daemon watchdog, never the caller —
   `aStalledCloseCannotWedgeTheCaller_becauseTheKillUnblocksTheReader` fails if that
   ordering is ever reversed. A blocking `destroy()` remains an accepted platform assumption.
3. **The watchdog-start failure path is fixed by construction but not unit-tested.** Forcing
   `Thread.start()` to throw would need a production thread-factory seam added solely for a
   `SecurityException` that cannot occur on Android; the ownership `finally` covers it.
4. **The gate runs in a `debuggable` instrumented process.** Parity on a NON-debuggable
   build is the plan's WI-9 acceptance item (§7), not WI-1's.

## Outstanding

Round 3's two findings are fixed and both gates are green (JVM 48/48, connected 21/21, 0
skipped), but the fixes post-date the last independent verdict. To clear
`final_verdict` to `ship-as-is` / `follow-up-recommended`, run one confirming round
scoped to those two fixes — the ownership `finally` in `collect`/`collectFrom` and the two
`CancellationException` rethrows.

## Mutation evidence (the gate is not vacuous — verified empirically, not argued)

`LogcatLineParser.parse` was forced to return `emptyList()` and the connected suite re-run
on the emulator: **5 of 13 tests went red, including
`feasibilityGate_appProcessReadsBackItsOwnLogcatLine`** (`GATE-SUMMARY verdict=FAIL
polls=30` — it polled the entire 5 s budget and never found the nonce, while the raw dump
still showed 206 lines, i.e. the data was there and only the parser was blind). Reverted;
restored run `GATE-SUMMARY verdict=PASS polls=1`.

## Feasibility verdict (the point of this WI)

**PASS.** `emulator-5554`, API 35, AOSP `sdk_gphone64_arm64`. The app process
(`untrusted_app`, no `run-as`, no shell) execs `/system/bin/logcat` and reads back its own
`Log.w` line on the first poll. uid rendering on this device is **numeric** (`uidToken=10241`
== `Process.myUid()`); the symbolic `u0_a209` form is covered by unit fixtures only.
uid filtering corroborated: the app saw **57** lines while the shell uid (which carries
group `1007(log)`) sees **5554** across **23** distinct uids.
