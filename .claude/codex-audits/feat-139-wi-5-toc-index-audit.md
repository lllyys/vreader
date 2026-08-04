---
branch: feat/139-wi-5-toc-index
threadId: 019fcbd7-e6aa-7b11-86e1-d47186a13752
rounds: 4
final_verdict: follow-up-recommended
date: 2026-08-04
---

# Gate-4 audit — feature #139 WI-5 (`txtTocIndexFor`)

Scope: `android/app/src/main/kotlin/com/vreader/app/reader/nav/TxtTocIndex.kt` +
`android/app/src/test/kotlin/com/vreader/app/reader/nav/TxtTocIndexTest.kt`. Auditor: Codex
(`gpt-5.6-sol`) via `scripts/run-codex.sh` (rule 53). Raw transcripts: `.reports/audit-r{1,2,3}.txt`
(not committed — lane-local).

Three questions drove every round: (Q1) does the function mirror `ReaderChromeModel.tocIndexFor`'s
contract at every boundary, (Q2) is the search genuinely O(log n), (Q3) could any named test pass
vacuously — the last being the priority, since WI-2 of this same feature shipped a test that passed
for free and WI-3's final round had to re-derive its arithmetic to rule out the same shape.

## Round 1 — `ship-as-is` (thread `019fcbc4-d665-7d30-9719-ab3cfad5d401`, effort low)

Zero findings. Confirmed the `-1`/`0` split, the `<=` boundary, duplicate right-bias, overflow-safe
`ushr` midpoint, loop termination, and that `CountingIntList.get` is reached by every ordinary
traversal shape. Because this ran at the wrapper's default low reasoning effort on a plan that has
already been wrong twice at High severity, it was not treated as sufficient.

## Round 2 — `block-recommended` (thread `019fcbc6-ab41-7131-b80a-70acf4881795`, effort high)

Prompted adversarially: *construct a wrong implementation that passes all 11 tests*.

**HIGH — a size-keyed mutant passed the whole suite.** `if (entryOffsets.size <= 2) return 0`
placed before the search: correct for one entry, wrong for two, and invisible because no fixture had
size 2. Traced by the auditor against all 11 tests.

**Fixes applied**
- Added `twoEntries_secondBoundaryAndDuplicateRightBias`.
- Generalized the single-fixture `everyOffsetInARange_agreesWithTheLinearReference` into
  `everyOffsetAndShape_agreesWithTheLinearReference` — the whole offset domain across 11 shapes
  (sizes 0..8, duplicate runs, a TOC starting at offset 0).

**Secondary findings, also fixed**
- The 32-read bound in the complexity probe could false-fail a *correct* O(log n) implementation
  doing two bound searches plus endpoint probes (~34 reads) → raised to `MAX_READS = 64`, which
  round 3 endorsed: still rejects √n jump search (~224), read-heavy O(log²n) (~256), linear (50 001).
- A single evenly-spaced fixture does not prove O(log n) — interpolation search is near-constant on
  `it * 10` while degrading on real, unevenly-chaptered books → added a second, skewed distribution.
  Round 3 measured a representative interpolation search at **13 557 probes** on it, confirming the
  fixture is genuinely adversarial.
- A test comment called 50 001 "the largest list that can ever reach this function"; the provider
  *rejects* >50 000 (emitting an empty TOC), so production's largest is 50 000 → comment corrected.

## Round 3 — `block-recommended` (thread `019fcbcf-7e64-7123-a053-23318a0de3a4`, effort high)

Verified every round-2 fix landed (the `size <= 2` mutant now dies; 64 is the right bound; the
skewed fixture is adversarial; the cap comment is accurate; the shapes are well-formed and the
skewed array is strictly increasing with no `Int` overflow) and explicitly re-confirmed **no
implementation defect** in the unchanged `TxtTocIndex.kt`.

**HIGH — a second size-keyed mutant, in the next gap.**
`if (entryOffsets.size in 9..TxtMdTocProvider.MAX_TOC_ENTRIES) return 0` passed all 12 tests,
because correctness shapes stopped at size 8 while the only large fixture was cap **+ 1**.

**Fixes applied.** Enumerating more sizes only moves the gap, so the response closes the family
rather than the example:
- `intermediateAndCapSizes_agreeWithTheLinearReference` — sizes 9, 16, 17, 33, 257, 1 000 and the
  production cap (50 000), each with a planted duplicate run and boundary/midpoint/past-last queries.
- `randomizedMonotonicShapes_agreeWithTheLinearReference` — 300 **seeded** (deterministic, never
  flaky) random sizes and non-decreasing shapes, each swept across its whole offset domain.
- The complexity probe now runs the real cap (50 000) as well as cap + 1, in both distributions.

The lane stopped here rather than self-certifying its own fix to an auditor's High (rule 48 hard
rule 1), and handed back `blocked` for a confirming round.

## Round 4 — `findings` (thread `019fcbd7-e6aa-7b11-86e1-d47186a13752`, run by the ORCHESTRATOR)

Run by the orchestrator, not the lane, so author/auditor separation held on the round-3 fix.

**Confirmed**: the complexity probe is a real discriminator — a correct-but-linear implementation
satisfies the value oracle but exceeds `MAX_READS` on the counted 50 000-entry list, so the lane's
"fails only that test" claim holds by inspection (matching mutation probe 1 below).

**HIGH — a third size-keyed mutant**, `if (entryOffsets.size == 65 && currentOffsetUtf16 >=
entryOffsets[1]) return 0`, passed all 14 tests, because nothing exercised size 65.

**Fix — the standard closure, not another fixture.** Three rounds of "add the size the auditor
picked" is an unbounded standard: any finite fixture list loses to a mutant keyed on an untested
exact size. So WI-5 adds **differential testing against a reference implementation**
(`differentialAgainstLinearReference_acrossSizesToTheCap`): a one-line linear
`referenceTocIndexFor` oracle, compared against the real function across many sizes and probe
offsets under a fixed seed (`20260804`). Its value is less the size coverage than that
**behavioural** mutants — the class that actually occurs, e.g. off-by-one boundaries — now fail on
essentially every sample instead of at one hand-picked fixture.

**Deviation from the prescribed sampling, deliberate and load-bearing.** The instruction was ~200
sizes drawn randomly from `1..MAX_TOC_ENTRIES`. A uniform draw hits any *specific* size with
probability ≈0.4%, so it would almost certainly not sample 65 — the acceptance criterion ("verify
the size-65 mutant now fails") would have failed. The sweep is therefore **exhaustive over 1..96**
(where hand-written special cases actually live; the lists are tiny, so it is nearly free) **plus
~104 log-uniform samples over 97..cap** (log-uniform because a uniform draw puts ~90% of samples
above 5 000 and never probes the hundreds). Same budget, same determinism, strictly more coverage.

**A gap the lane found in its own new test.** Mutation probe 10 (a *behavioural* "nearest entry"
mutant) initially failed six tests but **not** the differential one: its probes sat at entry starts
and entry+1, while "nearest" only diverges past a gap's midpoint. A floored gap-midpoint probe was
also insufficient (it rounds back into the agreeing half). The probe set now includes
`backing[i + 1] - 1` — late in the gap — and the differential catches that mutant too (7 failures).

## Mutation log (author-run; every probe executed against the real suite)

A test that cannot fail is worth nothing, so each claim below was verified by breaking the
implementation and observing which named tests went red.

| # | Mutation | Result |
|---|---|---|
| 0 | RED baseline: `= -1` stub | 10 of 11 fail (only `emptyEntries_returnsMinusOne` passes, coincidentally) |
| 1 | Correct but **linear** (`forEachIndexed`) | **only** `isBinarySearch_not_linear_over50000Entries` fails — "read 50001 of 50001 elements" |
| 2 | `<` instead of `<=` | 5 fail incl. `offsetExactlyAtEntryStart_returnsThatEntry`, `duplicateOffsets_*` |
| 3 | nothing-at-or-before → `-1` | 5 fail incl. `offsetBeforeFirstEntry_returnsZero`, `negativeOffset_*` |
| 4 | empty-list guard deleted | `emptyEntries_returnsMinusOne` fails (expected -1, got 0) |
| 5 | stdlib `binarySearch`, insertion point not decremented | 5 fail incl. `offsetInsideChapter_*`, `duplicateOffsets_*` |
| 6 | round-2 auditor's `size <= 2` mutant | fails `twoEntries_*` and `everyOffsetAndShape_*` |
| 7 | round-3 auditor's `size in 9..MAX_TOC_ENTRIES` mutant | fails `intermediateAndCapSizes_*`, `randomizedMonotonicShapes_*`, and `isBinarySearch_*` (`uniform@50000 … read nothing`) |
| 8 | round-4 auditor's `size == 65 && offset >= entryOffsets[1]` mutant, verbatim | fails `differentialAgainstLinearReference_*` — `size=65 offset=157 expected:<32> but was:<0>` |
| 9 | same shape at a different exhaustive-band size (`size == 91`) | fails `differentialAgainstLinearReference_*` — `size=91 offset=0 expected:<3> but was:<0>` |
| 10 | **behavioural** (not size-keyed): nearest entry instead of last at-or-before | fails 7 tests incl. the differential (after the late-in-gap probe was added; 6 without it — see round 4) |
| 11 | **residual probe**: `size == 4096` (one large size the sweep does not sample) | **SURVIVES — 0 failures.** Recorded, not solved. |

Probe 1 is the load-bearing one for complexity: it proves the complexity test discriminates on
*complexity alone*, rejecting an implementation that is otherwise entirely correct. Probe 10 is the
load-bearing one for the differential oracle: it is the mutant class that actually occurs in
practice, and it fails nearly everywhere. Probe 11 is the honest counterweight — see below.

## Why `follow-up-recommended` and not `ship-as-is`

The implementation is correct and was explicitly cleared by all four rounds — no round found a
defect in `TxtTocIndex.kt`. `block-recommended` would be wrong: it implies a defect, and there is
none. But `ship-as-is` would overclaim, because **mutation probe 11 demonstrates a measured
residual**: a mutant keyed on one exact size the sweep does not sample (4096) still passes the whole
suite. That is inherent to example-based testing — no finite suite excludes "special-case exactly
the untested input" — and the differential oracle reduces it to an adversarial curiosity rather than
a realistic defect class. It is recorded here rather than claimed solved. Accepted on that basis by
the orchestrator, who also ruled out a fifth round.

## Accepted / reported-upward, not fixed here

- **`ReaderChromeModel.kt:19` KDoc is inaccurate** (round 2, Low): it says `currentTocIndex` is `-1`
  when "there is no TOC **or no positional signal maps to a row**", but `tocIndexFor(null, null,
  nonEmptyPositions)` returns `0` — only an empty TOC yields `-1`. Real, but that file is outside
  WI-5's write-set (and the plan lists it OUT of scope), so it is reported in the HANDOFF rather
  than edited.
- **A read-counting probe cannot see CPU-only cost** between list reads (round 2): an O(log²n)
  implementation doing extra arithmetic between 16 reads would pass. Accepted — it is an inherent
  limit of counting reads, and the alternative (wall-clock timing) is flaky and would itself pass
  for a fast linear scan.
- **`entryOffsets` monotonicity is a documented precondition, not re-asserted here.** It is pinned at
  the source by `TxtTocRuleEngineTest` and `TxtMdTocProviderTest`, which each assert the emitted
  offsets equal their own `sorted()`. Re-validating inside the lookup would make it O(n) and defeat
  the whole point; round 2 confirmed unsorted input still returns an in-range row and cannot throw.

## Test gate

`RUN-ANDROID-TESTS RESULT: SUCCEEDED` — `:app:testDebugUnitTest --tests '*TxtTocIndexTest*'
--rerun-tasks`, **15 tests, 0 failures, 0 errors** in 0.094s (counts read from the JUnit XML, not
the `BUILD SUCCESSFUL` line). JVM only; no emulator.

Note on `ReaderChromeModel.kt:19` (the out-of-write-set KDoc defect this audit surfaced): the
orchestrator is handling it separately on `docs/bug-362-chrome-kdoc`.
