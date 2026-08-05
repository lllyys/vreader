---
branch: feat/164-wi-4-log-store
threadId: 019fcf5f-6cc4-7cf2-86a5-7887b478ad90
rounds: 3
final_verdict: block-recommended
date: 2026-08-05
---

# Gate-4 audit — feature #164 WI-4 (`DiagnosticsLogStore`)

Auditor: Codex `gpt-5.6-sol` via `scripts/run-codex.sh` (rule 53), read-only sandbox.
Author/auditor separation held: the implementing session never graded its own fixes — each
round's dispositions were returned by the auditor.

Round transcripts (session ids):

| Round | Session id | Verdict |
| --- | --- | --- |
| 1 | `019fcf41-f068-7ea1-a9b1-d816f9f0efb4` | follow-up-recommended |
| 2 | `019fcf51-3c5b-7d71-a00b-9e03711973c2` | block-recommended |
| 3 | `019fcf5f-6cc4-7cf2-86a5-7887b478ad90` | block-recommended |

Full transcripts: `.reports/audit-r1.txt`, `.reports/audit-r2.txt`, `.reports/audit-r3.txt`
(worktree-local, not committed).

Scope audited: the whole of this WI's two-file write-set —
`android/app/src/main/kotlin/com/vreader/app/diagnostics/DiagnosticsLogStore.kt` and
`android/app/src/test/kotlin/com/vreader/app/diagnostics/DiagnosticsLogStoreTest.kt` —
against WI-4's 12 acceptance criteria, the iOS original, and the shipped collaborators.

## Outcome: BLOCKED at the 3-round cap, on a finding this WI cannot legally fix

One **High** remains open. It is **not fixable inside WI-4's declared write-set**, so it is
escalated rather than worked around, and this lane stops rather than pushing past it.

## HIGH-1 (OPEN, escalated) — primary-source degradation never reaches the store

`lastLoadDegraded` cannot observe the case it exists for.

- `RingBufferDiagnosticsSource.recentEntries` has no *modelled* `Unavailable` path — every normal
  return is `Available` (a throw from it is still contained by the composite).
- `CompositeDiagnosticsSource` returns `Unavailable` only when **both** sources fail.
- Therefore `logcat = Unavailable` + `ring = Available` collapses to a flat `Available`, the store
  clears `degraded`, and the export prints `capture source: logcat + breadcrumbs` while the
  platform log is dead.

Consequence: `CAPTURE_SOURCE_DEGRADED` is unreachable for exactly the operational case §6.5
specifies it for, so **WI-4 acceptance criterion 2 and the plan's API-sketch contract ("the last
load's PRIMARY source reported Unavailable") cannot be met by any implementation confined to this
write-set.**

**Origin — pre-existing, not introduced here.** The auditor confirmed this is a plan/contract
defect that Gate 2 missed: the plan defines a flat `Available(entries)` / `Unavailable(reason)`
and *then* asks the store to report the primary's state. Once the composite collapses the two
sources into one flat result, WI-4 cannot reconstruct the lost provenance.

**Not yet user-facing.** Neither `DiagnosticsLogStore` nor `CompositeDiagnosticsSource` has any
production construction at this HEAD (container wiring is WI-7/WI-8), so this is a contract gap to
close before the feature ships, not a live defect. It should be closed before WI-6b/WI-7 build on
the signal.

**Minimal fix (auditor-specified), for a follow-up WI with the right write-set:**

1. `DiagnosticsLogSource.kt` (WI-1) — carry provenance on success, e.g.
   `Available(entries, primaryUnavailable: Boolean = false)`.
2. `CompositeDiagnosticsSource.kt` (WI-3) — set it whenever the primary read yields `Unavailable`
   (including a contained primary exception); preserve it through the empty and `limit <= 0`
   branches; keep both-unavailable as `Unavailable`.
3. `DiagnosticsLogStore.kt` — latch on `Unavailable`, a contained ordinary exception, **or**
   `Available(primaryUnavailable = true)`, while still returning the partial entries.
4. Tests — composite: primary-unavailable + healthy ring returns ring entries with provenance set,
   healthy primary yields false, secondary-only degradation does not masquerade as primary,
   zero-limit preserves provenance; store: a partially-available result returns entries *and* sets
   the latch, a later healthy load clears it, export selects `CAPTURE_SOURCE_DEGRADED`; plus one
   composition test over a failing primary + real ring + composite + store.

Per the auditor, **no sound fix existed inside the two files** ("any local inference would be
guessing after the composite discarded the information"), and WI-4 correctly neither canonised the
flat behaviour in a passing test nor shipped an ignored failing one.

## MEDIUM-1 (OPEN, escalated) — test file exceeds the ~300-line rule

`DiagnosticsLogStoreTest.kt` is ~919 lines. The auditor **accepted** the rationale for the overlap
with WI-3's `DiagnosticsCategoryBoundingTest` (WI-4's criterion 6 is about the raw-vs-chip
*interaction* on the same fixture, not the bounding rule in isolation) but holds the file size at
Medium, and explicitly says it "should be escalated rather than fixed by WI-4 unilaterally" —
splitting requires creating a third file, i.e. an orchestrator write-set amendment. Recorded here
for that decision. (For context, the repo's practiced convention for test files is looser:
`DiagnosticsRedactorTest.kt` is 1117 lines.)

## Resolved during the loop

| Finding | Round | Disposition |
| --- | --- | --- |
| M — `catch (Throwable)` laundered `Error`/`OutOfMemoryError` into a degraded load | 1 | **RESOLVED** — narrowed to `catch (Exception)`; `CancellationException` and `Error` propagate; the fabricated-then-discarded `Unavailable` reason removed |
| M — concurrency: `lastLoadDegraded` not bound to a returned batch | 1 | **PARTIALLY RESOLVED, accepted** — a compound return is not mandatory given the plan-pinned `List` API; single-flight precondition documented and last-to-complete-wins pinned by test |
| L — cancellation test asserted against a second, untouched store (tautological) | 1 | **RESOLVED** — one store driven through degraded → cancelled, plus the mirror case |
| L — whitespace-only category unpinned; test name misdescribed the contract | 1 | **RESOLVED** — contract is non-**empty**, not non-blank, and is now pinned |
| L — edge tests proved only "does not throw" | 1 | **RESOLVED** — exact strings at `Long.MIN_VALUE`/`-1`/`0`/`Long.MAX_VALUE`, plus RTL, `Int.MIN/MAX` limits, negative `maxEntries`, `limit == maxEntries` |
| L — `HEADER_LINE_COUNT` let a header change stay self-consistently green | 1 | **RESOLVED** — the three literal header lines are asserted |
| L — the "overlapping loads" test never overlapped, so the KDoc's "pinned by test" was false | 2 | **RESOLVED** — `GatedSource` holds both loads in flight (`inFlight == 2` asserted pre-release); the pair shares start order and verdicts and differs only in release order, asserting opposite outcomes, so neither first-started-wins, last-started-wins, nor never-latching can pass |
| L — KDoc contradicted the narrowed exception behaviour, and overstated the limitation | 2, 3 | **RESOLVED in round 3** — "ordinary `Exception`" everywhere, "no *modelled* `Unavailable` path" rather than "no failure path", degraded-label doc covers the contained-exception case, and the premature "shipped app"/"production wiring" claim replaced with the accurate "no production construction yet" |

## Verification

- `RUN-ANDROID-TESTS RESULT: SUCCEEDED` — `DiagnosticsLogStoreTest` **51 tests, 0 failures,
  0 errors**; whole `*diagnostics*` package **233 tests, 0 failures, 0 errors** (counts read from
  the JUnit XML under `android/app/build/test-results/testDebugUnitTest/`, not from
  `BUILD SUCCESSFUL`). Always `--rerun-tasks`.
- **Mutation pass — 5 mutations, all killed** (the 4 mandated + 1 self-initiated); the two that
  touch code the audit fixes restructured were re-killed afterwards:

| Mutation | Killed by |
| --- | --- |
| `exportText` skips the redactor for the first entry | 2 tests, incl. the secret-leak assertion |
| `categories()` returns `DiagnosticsCategoryBounding.chips(...)` | 5 criterion-5 tests — while **both criterion-6 tests stayed green**, which is the separation the crux requires |
| `lastLoadDegraded` always `false` | 6 tests, incl. the export capture-source line |
| clamp without `max(0, …)` | 2 tests; `takeLast(-7)` throws — the iOS Gate-4 crash class |
| continuation indent dropped | 3 tests, incl. the entry-line forgery guard |

- Auditor's independent security pass: **no store-level path bypasses `DiagnosticsRedactor`** —
  every `entry.message` is redacted before any splitting or rendering, with no fast path for
  empty, multi-line, CRLF/bare-CR, or entry-header-mimicking messages. The header lines carry only
  constants, the entry count and a formatted timestamp. Residual leak shapes are the redactor's own
  documented limitations (bare opaque secrets, the ambiguous spaced-value suffix), not a WI-4 gap.
- The round-3 sandbox could not run Gradle (read-only), so its test claims are static; the
  authoritative counts are the lane's own runs above.

## Recommendation to the orchestrator

Do not merge on this lane's authority. Two decisions are needed:

1. **HIGH-1** — schedule the 3-file provenance fix above as a follow-up WI (or fold it into WI-1/WI-3
   re-opens) before WI-6b/WI-7 consume the availability signal. The plan's §6.5 contract and WI-4
   acceptance criterion 2 stay unmet until then.
2. **MEDIUM-1** — decide whether to amend a write-set to split `DiagnosticsLogStoreTest.kt`.

Everything else in WI-4 is green, and the store's behaviour is otherwise correct against the plan,
the iOS original, and all 12 acceptance criteria.
