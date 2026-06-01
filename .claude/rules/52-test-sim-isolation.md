# 52 — Test / Simulator Isolation (no more ghost `xcodebuild test`)

## The recurring failure

`xcodebuild test` wedges: the process sits at **0% CPU with zero output** and
lingers for hours as a "ghost" (the task UI shows it running; `ps` shows it
sleeping forever). It never completes and never fails — it just hangs.

This has happened **many times**. Every instance shares one cause.

## Root cause (TWO distinct causes — both observed 2026-05-31)

### Cause A — simulator contention

A `xcodebuild test` run boots/installs onto a booted simulator and drives it. If
— while that run is in flight — the SAME simulator (same UDID) is ALSO driven by
verification traffic (`scripts/sim-tap.sh`, `idb`, `xcrun simctl openurl
vreader-debug://…`, `simctl io`, screenshots), the two contend for the one device
and the test runner deadlocks. With no timeout, the wedged process ghosts
indefinitely.

Aggravator: launching the test with `run_in_background: true` and then
immediately starting sim-driving in the next tool call — the collision is
guaranteed, and the ghost is invisible until someone checks `ps`.

### Cause B — orphaned/wedged build daemon (`SWBBuildService`)

`xcodebuild test` delegates compilation to Xcode's shared build daemon
`SWBBuildService`. When a hung `xcodebuild` is killed with `kill -9`, the daemon
is **left in a wedged state**. The NEXT `xcodebuild` build then hangs at 0% CPU
with NO compiler children and the **simulator completely idle** — i.e. it looks
identical to Cause A but contention is NOT involved. This is what produced the
"hung again?" recurrence right after killing the first ghost.

**Therefore:** never `kill -9` a hung `xcodebuild` without ALSO clearing the
daemon: `pkill -9 -x SWBBuildService`. The `scripts/run-tests.sh` watchdog now
does this automatically on timeout. A bare xcodebuild kill is a half-cleanup that
poisons the next run.

### Cause C — the full suite is just SLOW (not a hang)

The entire `vreaderTests` suite takes **>20 min** to build + run (hundreds of
tests incl. slow SwiftUI view tests). Running it as a per-WI gate looks
identical to a hang — `xcodebuild` sits there for 20+ min — but it is genuinely
working (the log shows `◇ Test case … started` lines streaming). Observed
2026-05-31: a clean-environment full-suite run built fine and was mid-tests when
a 20-min watchdog killed it.

**Therefore: do NOT run the whole `vreaderTests` suite as a per-WI gate.** Run the
**targeted `-only-testing:` suites that cover the change** — they finish in
seconds to a couple of minutes and are the appropriate gate. Reserve the full
suite for a periodic/CI sweep with a long budget (`TIMEOUT_SECS=2400`+).

```bash
# Per-WI gate — targeted, fast (seconds):
scripts/run-tests.sh vreaderTests/DebugCommandTests
# (pass multiple via repeated -only-testing is not supported by the wrapper's
#  single-arg form; run the wrapper once per suite, or extend it if needed.)

# Full-suite sweep — periodic, long budget:
TIMEOUT_SECS=2400 scripts/run-tests.sh vreaderTests
```

## Hard rules

1. **Never drive a simulator while `xcodebuild test` runs against it.** Tests and
   sim-driving (`sim-tap` / `idb` / `simctl openurl eval` / `simctl io` /
   screenshots / verification) are **mutually exclusive on one UDID**. Serialize:
   finish the test run, THEN drive the sim — or drive a DIFFERENT UDID
   (`TEST_UDID=<other>`).
2. **Always run unit-test gates through `scripts/run-tests.sh`.** It pins the
   destination by UDID, enforces a hard wall-clock timeout (default 900s), waits
   on the exact pid (rule 49), kills the process tree on timeout, and prints one
   unambiguous final line (`RUN-TESTS RESULT: SUCCEEDED|FAILED|TIMEOUT|NO_BOOTED_SIM`).
   A wedge now self-terminates in ≤15 min instead of ghosting for hours.
3. **A `RUN-TESTS RESULT: TIMEOUT` is not a flaky test — it's contention.** Do not
   "retry harder." Confirm nothing is driving the sim, then re-run. If you need
   verification in parallel, boot a second simulator and pass its UDID via
   `TEST_UDID`.
4. **Before ending a turn, confirm no live `xcodebuild`:** `pgrep -x xcodebuild`
   (NOT `pgrep -f xcodebuild` — `-f` matches the pattern inside your own grep
   command line and always returns ≥1, a false positive that has masked real
   state before). Zero = clean.
5. **Never pipe `scripts/run-tests.sh` through `tail` / `grep` / `head`.** `tail
   -N` on a PIPE emits NOTHING until EOF, so it buffers away every streaming `◇
   Test case` marker AND the single `RUN-TESTS RESULT:` line the watchdog exists
   to print. The output file stays empty mid-run, which makes a healthy run and a
   wedged run look identical — you lose the only cheap liveness signal. Let the
   watchdog's stdout go STRAIGHT to the output file (it already self-limits its
   output); read the file or wait for the native completion notification. Origin:
   2026-06-01, a `run-tests.sh … | tail -30` background invocation produced a
   0-byte output file for ~5 min; the run looked ghosted but the empty file was
   just `tail` buffering — the actual diagnosis required `ps`. (If you must
   shorten a FOREGROUND, already-finished log, `tail` the output FILE after the
   RESULT line lands — never insert `tail` into the live pipe.)

### Diagnosing "is it hung?" — process liveness, NOT the output file

When a backgrounded test run looks stalled, do NOT infer state from an empty or
silent output file (see rule 5 — it may just be pipe buffering). Infer it from
the **build process**:

```bash
# A genuine run ALWAYS has a live xcodebuild; during compile, also
# swift-frontend / clang. Zero of these = no work happening, full stop.
ps -Ao pid=,%cpu=,command= | grep -iE "xcodebuild|swift-frontend|clang|xctest|SWBBuildService" | grep -v grep
```

- **`xcodebuild` present (any CPU, even 0% briefly between phases)** → working;
  wait for the native completion notification.
- **`xcodebuild` totally absent + watchdog/wrapper still "alive"** → ghost. Kill
  the wrapper tree, `pkill -9 -x SWBBuildService` (Cause B), re-run.
- CoreSimulator runtime daemons (`…/RuntimeRoot/…` at 0%) are the booted sim's
  idle background services — unrelated noise, never evidence of a build.

## Quick reference

```bash
# Unit-test gate (default vreaderTests, 15-min watchdog):
scripts/run-tests.sh

# A single suite, longer budget:
TIMEOUT_SECS=1200 scripts/run-tests.sh vreaderTests/DebugCommandTests

# Tests on one sim while verifying on another (true parallelism):
TEST_UDID=<test-sim-udid> scripts/run-tests.sh    # tests here
#   ... drive <other-udid> with sim-tap in a separate step ...
```

## Relationship to other rules

- **Rule 49 (background shells):** this rule's watchdog waits on the exact pid and
  is cancelled when the test finishes first — it never re-arms on a future run.
  The `pgrep -f` false-positive warning here is the same class of bug rule 49
  flags for `pgrep -f "xcodebuild test"` waiters.
- **Rule 48 (parallel execution):** "single simulator → serialize" is the Gate-5
  decision-matrix row. This rule makes the test-vs-verification case explicit and
  gives it a tool.
