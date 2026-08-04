---
branch: feat/139-wi-5-toc-index
threadId: 019fcbcf-7e64-7123-a053-23318a0de3a4
rounds: 3
final_verdict: block-recommended
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

This fix is **not auditor-confirmed**: confirming it would be a 4th round, beyond the lane's 3-round
budget, so the lane stops and reports rather than self-certifying. It is, however, confirmed
mechanically — see the mutation log.

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

Probe 1 is the load-bearing one: it proves the complexity test discriminates on *complexity alone*,
rejecting an implementation that is otherwise entirely correct.

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
--rerun-tasks`, **14 tests, 0 failures, 0 errors** (counts read from the JUnit XML, not the
`BUILD SUCCESSFUL` line). JVM only; no emulator.
