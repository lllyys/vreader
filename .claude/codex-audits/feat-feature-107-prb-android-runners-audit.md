---
branch: feat/feature-107-prb-android-runners
threadId: 019ed6e2-4175-75b3-a66d-e262bd0fd3e0
rounds: 3
final_verdict: ship-as-is
date: 2026-06-18
---

# Gate-4 audit — feature #107 PR-B (Android test/verify runners + ghost sweep)

PR-B adds `scripts/run-android-tests.sh` (watchdog runner) + `run-android-verify.sh`
(delegate) + a real-process contract test, extends `scripts/sweep-ghosts.sh` for
Android ghost classes, and adds rule-52 "Cause D" + watchdog.md Android notes.

`scripts/`+`.claude/` is `shared` (not `code_paths_touched`), so the merge hook
doesn't require this log — recorded for Gate-4 discipline. Codex (gpt-5.4, high),
3 rounds. Sessions: r1 `019ed6e2-…`, r2 `019ed6e6-…`, r3 `019ed6e9-…`.

## Round 1 — 1 High + 2 Medium (+ a pre-launch latent watchdog fd bug found by the contract test)

| file | sev | issue | resolution |
|---|---|---|---|
| run-android-tests.sh | High | `pkill -9 -f org.gradle.launcher.daemon` is machine-global — could kill another repo's resident daemon. | Snapshot `PRE_DAEMONS` before launch; on timeout kill ONLY new daemons via `comm -13` diff (a run that connects to a pre-existing daemon leaves it alone). |
| run-android-tests.sh | Medium | "kill the process tree" was direct-children-only (`pkill -P`); a `bash -c` wrapper can orphan deeper descendants. | Recursive `kill_tree()` (pgrep -P recursion; no setsid — absent on macOS). |
| run-android-tests.sh | Medium | `adb get-state` ≠ booted-emulator detection (passes for a physical device; errors on multiple devices). | `emulator_online()` parses `adb devices` for an `emulator-NNNN … device` line. |
| (pre-audit, found by the contract test) | — | The watchdog subshell's backgrounded `sleep` held the captured stdout fd → a `$(...)` caller blocked until TIMEOUT. | Watchdog redirected to the LOG + `pkill -P "$wd"` kills its sleep child on cancel. |

## Round 2 — 1 new Medium (race I introduced)

| file | sev | issue | resolution |
|---|---|---|---|
| run-android-tests.sh | Medium | The parent cancelled the watchdog after `wait $pid`, which on timeout returns the instant `kill_tree` lands — interrupting the watchdog's Gradle-daemon cleanup. | A `FIRED` sentinel (`mktemp -u`) the watchdog touches BEFORE `kill_tree`; the parent `wait "$wd"` (lets cleanup finish) when FIRED exists, else cancels the still-sleeping watchdog. FIRED is the authoritative TIMEOUT signal; removed on every exit. |

Round 2 confirmed the 3 round-1 findings resolved.

## Round 3 — CLEAN

"No new Critical/High/Medium findings. The round-2 race is resolved." Confirmed:
the sentinel is set before the kill that unblocks `wait $pid` (race-free); FIRED
is removed on every exit + the temp name is fresh per run (no stale read); the
timeout-path `wait $wd` cannot hang (bounded local cleanup). Only a Low
`mktemp -u` TOCTOU note (acceptable for a local watchdog).

## Validation

`scripts/__tests__/run-android-tests.test.sh` — ALL PASS (SUCCEEDED / FAILED /
TIMEOUT-killed-in-2s / NO_EMULATOR, via real-process ANDROID_CMD stubs).
`sweep-ghosts.sh` syntax OK + CLEAN. verify.sh delegates correctly.

## Verdict

**ship-as-is.** 3-round real Codex audit; the rule-49/52/53-compliant Android
runner + ghost-sweep are sound (scoped daemon kill, recursive tree kill, real
emulator detection, race-free timeout).
