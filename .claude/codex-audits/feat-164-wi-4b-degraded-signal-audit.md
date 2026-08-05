---
branch: feat/164-wi-4b-degraded-signal
threadId: 019fcf81-c0d6-7bc0-9283-576b989f915e
rounds: 3
final_verdict: follow-up-recommended
date: 2026-08-05
---

# Gate-4 audit — feature #164 WI-4b (degradation provenance)

Auditor: Codex `gpt-5.6-sol` via `scripts/run-codex.sh` (rule 53), read-only sandbox.
Author/auditor separation held: every round's dispositions were returned by the auditor; the
implementing session never graded its own fix to an independent auditor's finding.

Round transcripts (session ids):

| Round | Session id | Verdict |
| --- | --- | --- |
| 1 | `019fcf74-89c1-7c90-a77a-2d97da695e84` | block-recommended |
| 2 | `019fcf7b-dffe-7f90-ba72-961ab1c43e5c` | follow-up-recommended |
| 3 | `019fcf81-c0d6-7bc0-9283-576b989f915e` | follow-up-recommended |

Full transcripts: `.reports/audit-r1.txt`, `.reports/audit-r2.txt`, `.reports/audit-r3.txt`
(worktree-local, not committed).

Scope audited: this WI's five-file write-set — `DiagnosticsLogSource.kt`,
`CompositeDiagnosticsSource.kt`, `DiagnosticsLogStore.kt`, `CompositeDiagnosticsSourceTest.kt`,
`DiagnosticsLogStoreTest.kt` — plus the unmodified leaf sources and plan §6.5, which fixes the
export header's wording.

## Outcome: WI-4's HIGH-1 is CLOSED, confirmed independently in all three rounds

Round 1: *"This does not reopen WI-4's original HIGH-1 — the dead-logcat case is fixed."*
Round 3, judged fresh: *"WI-4 HIGH-1 is closed. Every normal dead-platform path — explicit
`Unavailable`, contained ordinary exception, nested degradation, both legs unavailable, and
zero/negative limits — reaches `DiagnosticsLogStore.lastLoadDegraded` and the degraded export
header. Healthy empty reads do not set it, recovery clears it, and secondary-only failure
deliberately does not claim that logcat died. … no path was found where an actually unavailable
platform log is laundered into healthy."*

Final finding counts: **Critical 0, High 0, Medium 0, Low 1 (accepted + escalated, below).**

## The fix's shape, and why

`SourceResult.Available` gained a defaulted `degradedReason: String?`. Rejected the WI-4 auditor's
sketched `primaryUnavailable: Boolean` because "primary" is a compositing concept a leaf source
cannot honestly answer; a nullable reason reuses `Unavailable`'s existing vocabulary, so the
package carries one concept rather than two, and every existing `Available(...)` construction
compiles unchanged with unchanged meaning. Round 2 endorsed this: *"The nullable reason is better
than putting a compositing-specific `primaryUnavailable` Boolean on leaf sources."*

The composite computes the reason ONCE before its branches and returns it from both `Available`
paths — including the `limit <= 0` short-circuit, the branch a naive fix drops. Both-legs-dead
stays `Unavailable`. The store latches on it while still returning the partial entries.

**Ruling on secondary-only failure (asymmetry, deliberate).** A dead ring under a healthy logcat is
NOT reported. The export's `capture source:` line has exactly two values, both fixed verbatim by
plan §6.5 and rule 51; emitting `breadcrumbs only (platform log unavailable)` because the *ring*
failed would invert the truth, and inventing a third label is a design change, not a lane decision.
Round 1 raised this as a High; round 2 accepted the disposition after independently verifying that
`RingBufferDiagnosticsSource` has **no** `Unavailable` return path and that its realistic
catastrophic failures are `Error`s which now propagate — *"I found no realistic operational path
where the shipped ring returns `Unavailable`."* The limitation is now explicit in the result
contract, the composite doc and the store doc rather than papered over.

## Findings and dispositions

| Round | Severity | Finding | Disposition |
| --- | --- | --- | --- |
| 1 | High | Secondary-leg degradation discarded; `CAPTURE_SOURCE_FULL` documented as "the whole capture stack answered", which is false under the primary-only ruling | **RESOLVED** — the false doc claims corrected (`CAPTURE_SOURCE_FULL`, `degradedReason`'s contract, the store's known-limitation bullet); the product gap argued on the merits and **accepted by round 2** as needing a design/plan change, not a code change |
| 1 | Medium | `CompositeDiagnosticsSource.read()` caught `Throwable`, laundering `Error` into degradation; KDoc claimed otherwise | **RESOLVED** — narrowed to `catch (Exception)`, matching `DiagnosticsLogStore.load` whose own audit made the same correction. Load-bearing after WI-4b: a contained primary failure now also sets `degradedReason`, so swallowing an OOM would make the export blame the platform log for a JVM failure. Error propagation asserted on both legs |
| 1 | Low | Both-unavailable test asserted only the result subtype | **RESOLVED** — constituent reasons asserted |
| 1 | Low | Nested-degraded primary tested only through the merge branch | **RESOLVED** — repeated at `limit = 0` and `limit = -1` |
| 1 | Low | Throwing-secondary test asserted entries but not provenance | **RESOLVED** — asserts `degradedReason == null`, so treating only a *thrown* secondary as platform degradation cannot hide behind the explicitly-`Unavailable` test |
| 2 | Low | `DiagnosticsLogSource` KDoc still said implementations "NEVER throw" / named `CancellationException` as the sole propagating exception | **RESOLVED** — contract now states the real rule: ordinary operational `Exception`s become `Unavailable`; cancellation and non-containable `Error`s propagate |
| 2 | Low | Both-throwing test asserted only the subtype | **RESOLVED** — asserts each leg's exception type and message |
| 3 | Low | `LogcatDiagnosticsSource` catches `Throwable` at 5 sites, so it does not conform to that newly-stated contract | **ACCEPTED + ESCALATED** — see below |

### The one open Low (accepted with rationale, escalated to the orchestrator)

`LogcatDiagnosticsSource.kt:78,88,110,153,255` contain `Throwable`, so an `Error` raised inside the
logcat reader becomes `Unavailable` rather than propagating — which the composite would then report
as platform-log degradation. Verified directly, not taken on the auditor's word.

**That file is explicitly OUT of this WI's write-set** (the brief names it as forbidden and says a
fix that appears to need it is "a blocker to report, not a file to edit"). The code half is
therefore escalated as a named follow-up rather than reached for. The documentation half — the part
that was in scope — is fixed: the interface states the rule the package is converging on AND names
the deviation explicitly, rather than quietly weakening the contract to match the laggard.

Severity is genuinely Low: it is pre-existing WI-2 behaviour, it can only mis-attribute a JVM
`Error` as platform-log unavailability (never the reverse — it cannot make a dead log read healthy),
and neither class has a production construction at this HEAD (wiring is WI-7/WI-8).

## MEDIUM-1 from WI-4's audit — DECLINED, adjudicated (do not re-raise)

`DiagnosticsLogStoreTest.kt` exceeds the ~300-line guidance (now ~1,067 lines). **It is not split,
by orchestrator ruling.** The practiced convention in this very package is looser —
`DiagnosticsRedactorTest.kt` is 1,117 lines — and WI-4's auditor already accepted the substantive
justification for the overlap it flagged (criterion 6 asserts the raw-vs-chip *interaction* on the
same fixture, not the bounding rule in isolation, so the overlap with WI-3's suite is deliberate).
Splitting would add a third file and churn for a soft convention this repo does not enforce.
Recorded here so the next auditor sees it as **adjudicated, not ignored**.

## Verification

- `RUN-ANDROID-TESTS RESULT: SUCCEEDED` — whole `*diagnostics*` package **252 tests, 0 failures,
  0 errors**, up from the 233/0 baseline (+19 = 7 store `DiagnosticsLogStoreTest` 51 -> 58, 12
  composite `CompositeDiagnosticsSourceTest` 19 -> 31). Counts read from the JUnit
  XML under `android/app/build/test-results/testDebugUnitTest/`, never from `BUILD SUCCESSFUL` —
  a suite that runs 0 tests also prints that. Always `--rerun-tasks`.
- **RED was behavioural, not a compile error.** The store-level end-to-end tests were written
  first and run against the unfixed code: 239 tests, exactly 3 failures, each the provenance case
  (`aDeniedPlatformLogWithAHealthyRingServesBreadcrumbsAndReportsDegraded`,
  `aDeniedPlatformLogIsStillReportedWhenTheRequestedLimitIsZero`,
  `regainingThePlatformLogClearsTheDegradedLatch`), while the guard tests passed. That is the
  finding reproduced, not merely asserted.
- The headline test runs through the **real** `CompositeDiagnosticsSource` and the **real**
  `RingBufferDiagnosticsSource` into the **real** store; only the platform log is faked, because a
  JVM test cannot make logd deny a read. No stub is handed a pre-set flag.
- **Mutation pass — 5 mutations, all killed**, and the two composite branches proved
  *independently* diagnostic (neither mutation killed the other's tests):

| Mutation | Killed by |
| --- | --- |
| Composite drops the flag in the **merge** branch | 5 tests (3 composite + 2 store), incl. the headline; the limit tests correctly stayed GREEN |
| Composite drops the flag in the **`limit <= 0`** branch | exactly 3 tests (zero-limit, negative-limit, store zero-limit); the headline correctly stayed GREEN |
| Store never latches the new signal | 3 store tests, incl. the export-header path |
| Store latches but never clears | 3 tests, incl. `regainingThePlatformLogClearsTheDegradedLatch` and WI-4's own reset test |
| Composite ALSO reports a dead **secondary** (self-initiated: the spurious-set direction) | 2 tests — the ruling is enforced, not incidental |

- One weakness the mutation pass exposed and the lane fixed unprompted: the export-header assertion
  on the partial-availability path sat *behind* the latch assertion in the headline test, so a
  broken header mapping could only ever surface as a latch failure. It is now its own test,
  asserting the degraded wording present, the full-stack wording absent, and the breadcrumbs still
  in the payload.

## Recommendation to the orchestrator

Mergeable on this lane's work. Two items to carry:

1. **Follow-up (Low)** — narrow `LogcatDiagnosticsSource`'s five `catch (Throwable)` sites to
   `catch (Exception)` with error-propagation tests, completing the package-wide policy the
   interface now documents. Needs a write-set that includes that file.
2. **Design (pre-existing)** — surfacing *secondary*-leg failure honestly needs a third
   `capture source:` label, i.e. a plan §6.5 / design decision. Filing is the orchestrator's call;
   nothing in the shipped wiring reaches the case today.
