---
branch: feat/139-wi-2-toc-engine
threadId: 019fcb5c-0411-7f20-a842-a04e4d019c30
rounds: 3
final_verdict: ship-as-is
date: 2026-08-04
---

# Gate-4 audit — feature #139 WI-2 (`TxtTocRuleEngine`: detect + bounded extract)

Item: `feat:#139/WI-2`. Auditor: Codex via `scripts/run-codex.sh` (rule 53), read-only sandbox,
three rounds. Thread ids: r1 `019fcb5c-0411-7f20-a842-a04e4d019c30`,
r2 `019fcb64-2f8d-7b90-8a12-b0150eac7ea5`, r3 in `.reports/audit-r3.txt`.
Raw transcripts: `.reports/audit-r{1,2,3}.txt` (lane-local, gitignored).

Scope audited: `DetectedHeading.kt`, `TxtTocRuleEngine.kt`, `TxtTocRuleEngineTest.kt`, against the
iOS source of truth `vreader/Services/TXT/TXTTocRuleEngine.swift:38-132` and WI-1's `TxtTocRules.kt`.

The audit prompt named the load-bearing risk explicitly: every `sourceOffsetUtf16` becomes a
**navigation locator** (it feeds `txtBookmarkLocator` / `jumpToOffset` and #138's paged
`ensureMeasuredThrough` seam), so an off-by-one offset is a user-visible defect. Round 1 was
therefore pointed at offset correctness, the early-stop `limit` (Gate-2 R2 MEDIUM), cancellation,
and ReDoS bounds — and at whether any test was vacuous.

## Round 1 — verdict `follow-up-recommended`

| Sev | Finding | Disposition |
| --- | --- | --- |
| MEDIUM | Cancellation is checked every 1 024 **matches**, not per scanned input. One `find()` / `next()` is a non-suspending `java.util.regex` call that can traverse a 14 MB document uninterrupted, so the header's "stops promptly" / "well under a frame" claims were not guaranteed. Proposed fix: scan by bounded **line regions**. | **PARTIALLY ACCEPTED** (`aa93faa3`). Diagnosis accepted — the over-claim is rewritten to state the real bound (one uninterrupted walk of the gap to the next match, ≈ a full pass, measured ~100 ms on the real book) and `extractHeadings_largeNoMatchDocument_isACatastrophicRegressionSmokeTest` makes the worst case an executed assertion. **The prescribed fix was REJECTED as unsound** — see below. |
| LOW | `detectBestRule_isCancellationCooperative` would pass even if `countMatches` had no cancellation check at all (with `activeChecks = 1` the cancelling query lands on the rule boundary, before counting starts). | **FIXED** (`aa93faa3`). Split into `_betweenRules` and `_whileCountingOneRulesMatches` (one enabled rule, 4× the check interval in matches, `CancelAfter(activeChecks = 2)` so the cancelling query must originate inside `countMatches`). |
| LOW | The sampling tests never discriminate `sampleOf`'s surrogate-boundary branch — a regression at exactly 512 K, at a straddling pair, or on a lone surrogate would go unnoticed. | **FIXED** (`aa93faa3`). `sampleOf` is `internal` with four direct boundary tests: exactly-the-window, pair straddling the boundary, pair ending at the boundary, lone unpaired surrogate preserved. |

### Why line-region chunking was rejected (the round-1 MEDIUM's prescribed fix)

`TxtTocRules.WS` is the D1b widening to ICU-`\s` semantics — `[\s\p{Z}\x{0085}]` — which **contains
line terminators**. The rules' whitespace positions therefore genuinely match across a newline:
probed directly with `java.util.regex` MULTILINE, rule 1 matches `"第\n一\n章 标题"` at offset 0,
spanning two terminators. iOS's ICU `\s` behaves identically, so this is **parity, not a bug**.
Splitting the scan into line-bounded regions would silently drop such matches — trading a bounded
~100 ms *background* latency for a correctness divergence from iOS.

Round 2 was asked to verify this independently rather than take the author's word, and did:

> "The cross-terminator claim is true for shipped rule 1: both `{0,4}` whitespace positions can
> consume line terminators… Rejecting simple line-bounded scanning was correct. An
> equivalence-preserving overlapping-region scheme is theoretically possible … but disabled rules
> 24/25 allow unbounded same-line matches, Unicode terminator/CRLF handling is delicate, and a huge
> single line remains unsplittable without changing semantics. The complexity is not justified for
> the measured background cost."

The behaviour is now pinned by `extractHeadings_aRuleCanMatchAcrossALineTerminator_soTheScanIsNotLineSplittable`,
so a future "scan line by line" optimization fails a test instead of silently regressing.

## Round 2 — verdict `follow-up-recommended` (zero Critical/High/Medium)

| Sev | Finding | Disposition |
| --- | --- | --- |
| LOW | A cancel landing during the **final** `next()` / initial `find()` that returns `null` is swallowed: both loops exit and return a normal result without a further `ensureActive()`. | **FIXED**. `coroutineContext.ensureActive()` now runs after each scan loop before the normal return, in both entry points. Two deterministic regression tests: `extractHeadings_cancelDuringTheFinalScanStep_isNotSwallowed` (document too small for any in-loop interval check, asserts exactly 2 queries = entry + post-loop) and `detectBestRule_cancelAfterTheLastRule_isNotSwallowed` (`activeChecks = 1 + enabled-rule count`, so the cancelling query must be the post-loop one). |
| LOW | Rule-22 drift: the comments promised a single-line match/title, which the newly pinned cross-terminator behaviour contradicts; and "off the main thread" is a caller property (WI-4's `withContext`), not something this engine enforces. | **FIXED**. Header + `extractHeadings` KDoc now state that the `.` tail cannot cross a terminator but the marker's `WS` positions can, so a title may carry an embedded newline (iOS parity); `DetectedHeading.title`'s KDoc says the same and points collapsing at the presentation layer; the header states the engine does not hop threads itself and must not be called on the main thread. |
| LOW | The no-match timing test claimed "bounded and linear" and cited ~100 ms, but tests one size against a 10 s ceiling; also mislabelled the fixture as 14 MB. | **FIXED**. Renamed to `…_isACatastrophicRegressionSmokeTest`; the comment now disclaims linearity and the ~100 ms figure, defers a real budget to WI-8's device evidence, and states the fixture is ~14 M UTF-16 code units — about twice the real book's 7 029 609. |
| LOW | The 664-line test file exceeds the ~300-line convention. | **ACCEPTED, not fixed.** (a) The convention (`.claude/rules/00-engineering-principles.md`) is written for code files, and this module's suites routinely exceed it — `VReaderDatabaseMigrationTest.kt` 832, `InBookSearchViewModelTest.kt` 658, `InBookSearchRepositoryTest.kt` 545, `ChapterTranslationServiceTest.kt` 542, `TxtTocRulesTest.kt` 532 (the immediately preceding WI). (b) Splitting needs a shared harness file (the `CancelAfter` Job and the `runWithJob`/`startCoroutine` helper) **outside this lane's declared three-file write-set**. Round 3 concurred: "maintainability debt, but splitting it within this narrowly declared write-set would be disproportionate and is not a shipping defect." |

Round 2 also confirmed, from scratch: iOS fidelity of the sampling window, enabled filter,
strictly-greater tie-break, `>= 2` threshold, whole-match trimmed titles, blank-title drop, document
order and skip-on-uncompilable; offsets at true line starts under LF/CR/CRLF, in bounds, never
inside a surrogate pair; coherent `hitLimit` for the `cap + 1` caller; blank titles not consuming
the limit; genuine early stop (the next match is never sought); no material ReDoS exposure; and the
`CancelAfter` / `runWithJob` harness non-vacuous.

## Round 3 — verdict `ship-as-is` (zero findings at any severity)

Verification round. Confirmed both terminal `ensureActive()` calls are correctly placed, that both
new regression tests **would fail without the fix** and their query-count arithmetic is right, that
no cancellation path remains swallowed, that all comments in both production files are now literally
true, that the fixture is exactly 14 000 000 UTF-16 code units, and that the terminal checks change
no uncancelled result, no matching fidelity, no offset and no limit behaviour ("throwing instead of
returning when the caller's job is cancelled is the correct coroutine contract"). L4 accepted.

## Author-side defect caught before round 1

The first local run of the suite exposed a **false-passing test harness**: `CancelAfter` was written
as `Job by delegate`, and Kotlin interface delegation forwards *every* member — including
`CoroutineContext.get`. `coroutineContext[Job]` therefore returned the delegate, never the counting
job, so `isActive` was never queried, cancellation never fired, and
`extractHeadings_stopsAtLimit_doesNotMaterializeBeyondIt` passed **vacuously** (`job.checks == 0 <
195`). Fixed by overriding `get`, and guarded permanently by an explicit anti-vacuity assertion
(`job.checks >= 1`) plus a KDoc naming the trap. Two engine bugs were also caught by the same first
run being honest: the CRLF offset expectation in the test was the author's arithmetic error, not the
engine's (the engine was right).

## Test gate

`RUN-ANDROID-TESTS RESULT: SUCCEEDED` —
`./gradlew :app:testDebugUnitTest --tests '*TxtTocRuleEngineTest*' --tests '*TxtTocRulesTest*'`,
**46 + 21 = 67 tests, 0 failures, 0 skipped**. JVM only; no emulator required.
