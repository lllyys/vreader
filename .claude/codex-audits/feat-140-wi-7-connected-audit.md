---
branch: feat/140-wi-7-connected
threadId: 019fd1bb-be83-7f51-aa66-730cc704f919
rounds: 3
final_verdict: ship-as-is
date: 2026-08-05
---

# Codex Audit Log — Feature #140 WI-7 (GH #2064)

The real-book connected round-trip: the WI that proves an AZW3 Contents tap
actually MOVES the reader. One file in scope:

- `android/app/src/androidTest/kotlin/com/vreader/app/reader/foliate/Azw3TocConnectedTest.kt`

Auditor: Codex `gpt-5.5`, reasoning `high`, via `scripts/run-codex.sh` (rule 53).
Sessions: r1 `019fd1a5-003f-7260-9379-a29d58c4f541`, r2
`019fd1b5-2cd3-72e1-912e-589254c9b341`, r3 `019fd1bb-be83-7f51-aa66-730cc704f919`
(the `threadId` above is the final round's). Raw transcripts:
`.reports/audit-r{1,2,3}*.txt` (not committed).

The audit prompt was aimed at the four ways this WI could be worthless: a
position-change assertion that a drift could satisfy, a negative control with no
teeth, a smuggled `Succeeded`-means-motion assertion, and a hostile-payload test
that overclaims what it proves.

## Round 1 — 1 High, 2 Medium, 5 Low → `block-recommended`

| Sev | Finding | Disposition |
| --- | --- | --- |
| **High** | The discriminator checked "the position changed" and "it landed in the tapped chapter" against two DIFFERENT relocate samples, leaving a hole: drift moves the reader somewhere else, a later relocate reports the target, both assertions pass, the tap caused nothing. | **Fixed.** Relocates now carry a monotonic sequence (`Reported`); `awaitReport(since, …, predicate)` requires ONE event to satisfy moved + moved-forward + tapped-chapter together. |
| **Medium** | `settledRelocate()` accepted a single unchanged 1.2 s sample, so a delayed layout/settle relocate arriving after it was indistinguishable from the jump. | **Fixed.** `settledReport()` requires the position to HOLD STILL for a continuous 5 s (the same window the negative control observes) and returns the LATEST report so its sequence cannot be stale. The discriminator additionally asserts the opening `tocHref` is non-null — without it the avoid-the-current-chapter guard is inert — and that the target href differs from it. |
| **Medium** | The negative control's liveness half ran under a 30 s budget while the no-change verdict was reached over 5 s, so it did not prove the shorter window sufficient. | **Fixed.** Liveness now uses the SAME `OBSERVE_WINDOW_MS` and requires `tocHref == targetHref`. |
| Low | A missing fixture `assumeTrue`-skips, and a skip exits 0 exactly like a pass (plan R7 / bug #369). Auditor suggested hard-failing instead. | **Accepted with rationale + hardened.** `assumeTrue` is what the plan's WI-7 block mandates and what `Azw3ReaderActivityTest` / `Azw3GoToSliceTest` already do; changing it would red every fixture-less checkout. Instead a missing fixture now emits a LOUD `Log.e`, and the lane quotes `tests`/`skipped` verbatim from the JUnit XML. Round 2 accepted this. |
| Low | The staged `wi7-book.azw3` was cached and could be a different book than the APK ships. | **Fixed** — re-copied from the test APK's assets on every call. Round 2 confirmed re-copying under the live reader is safe (foliate has already fetched the bytes into a Blob by `Loaded`). |
| Low | The highlight assertion's message claimed "the highlighted row", but it compared hrefs only. | **Fixed** — it now pins `foliateTocIndexFor`'s documented last-match-wins index (`hrefs.indexOfLast`). |
| Low | `COST_CEILING_MS = 1000` against a measured `0 ms` is decoration. | **Fixed** — mean of 20 iterations in MICROseconds against `MAIN_THREAD_BUDGET_US = 50_000` (~3 dropped frames at 60 Hz; the parse runs on the thread that paints, which is the one non-arbitrary ceiling available). |
| Low | 520-line file vs the ~300-line guideline. | **Accepted** — the lane's write-set is exactly this one file, so splitting is unavailable. The auditor called it an acceptable documented deviation in both rounds. |

## Round 2 — 1 Medium, 1 Low → `block-recommended`

Round 2 confirmed round 1's High and both Mediums fixed, and the correlation
real; it noted that `awaitReport`'s latest-snapshot polling could miss a
short-lived qualifying relocate, and ruled that a **false-fail/flake risk, not a
false pass** — i.e. it errs toward strictness.

| Sev | Finding | Disposition |
| --- | --- | --- |
| **Medium** | The await was dated from the SETTLED sample, not from the jump. A drift or re-render landing in the gap between `settledReport()` and `goTo` could satisfy all three predicates without the tap causing anything. | **Fixed.** `dispatchJump()` reads the report sequence and issues `doc.goTo` inside ONE main-thread continuation — `onRelocate` also runs on Main, and `goTo` injects its JS before its first suspension point — so nothing can slip between them. The discriminator, the tocHref-match test and the control's liveness half all date their awaits from that dispatch sequence. |
| Low | The name says `withElapsedMs` while the assertion moved to microseconds. | **Fixed without renaming.** The measurement stays in microseconds (an integer ms clock reads 0 for this work); the log now also carries the fractional milliseconds those samples yield, so the name matches what is recorded. The name itself is declared verbatim by the plan's WI-7 test list and the lane brief, so it was kept. |

## Round 3 — 0 findings → `ship-as-is`

> "No remaining finding is a blocker or follow-up. The dispatch-sequence gap is
> closed, the negative control remains a real discriminator, no ack-means-motion
> assertion is present, the pathological tests are correctly scoped to payloads,
> and the harness looks acceptable for this connected test class."

Standing verdicts carried across all three rounds:

- **No forbidden `ack means motion` assertion exists in this file.** The known-bad
  shape lives at `Azw3GoToSliceTest.kt:90`; here the `Azw3GoToResult` is logged
  and never asserted on.
- **No test name, KDoc or message claims a pathological BOOK FILE opens.** Scope
  is the payload throughout (plan §5.4 stage 1 / R13 / follow-up F6).
- **The payload probes ride the production path**: injected JS calls
  `window.__vreaderPost` → `reader.html`'s `send()` → `vreaderHost.postMessage`
  → `addWebMessageListener` → `FoliateBridgePolicy.isTrustedMessage` →
  `FoliateMessageParser.parse` (`FoliateBridge.kt:132`). An ART
  `StackOverflowError` would be observable — no matching `BookReady` would be
  collected, timing the await out, or the instrumentation process would die.

## Test gate

`TEST_UDID`/`ANDROID_SERIAL=emulator-5554`, `--rerun-tasks`, one class per
invocation (rule 52 Cause D):

```
RUN-ANDROID-TESTS RESULT: SUCCEEDED
tests="8" failures="0" errors="0" skipped="0" time="24.027"
```

Counts read from `android/app/build/outputs/androidTest-results/connected/debug/*.xml`,
never from `BUILD SUCCESSFUL`. **Zero skips** — the fixture was staged, so the
real-book cases RAN (plan R7).
