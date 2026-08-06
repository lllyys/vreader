---
branch: feat/141-wi-1-toc-title-filter
threadId: 019fd4df-d798-70f1-81fc-e173f751612e
rounds: 4
final_verdict: ship-as-is
gate: 4
kind: implementation-audit
feature: 141
work_item: WI-1
plan: dev-docs/plans/20260806-feature-141-android-filterable-toc.md
---

# Gate 4 — feature #141 WI-1 (`TocTitleFilter`)

## Round 4 — orchestrator-run confirming round (2026-08-06): **VERDICT: `ship-as-is`**

Round 3 hit the rule-47 cap at `block-recommended` with 1 High, 2 Medium, 1 Low open. The lane fixed
all four **after** that verdict and returned `blocked` rather than certify its own fixes — the right
call, and the same discipline #165 WI-7's lane showed. This round exists only to verify those four
fixes and the two plan deviations.

| # | Sev | Finding | Round-4 verdict |
|---|---|---|---|
| 1 | **High** | `TocRowText.matchRanges` handed back the fold's **own `ArrayList`**, so `(row.matchRanges as MutableList).clear(); addAll(other)` could re-point one row's tint at another row's ranges — defeating the pairing invariant with **no constructor call and no subclass**. | **RESOLVED** — `TocTitleFilter.kt:66-68` returns `emptyList()` or `Collections.unmodifiableList(ArrayList(matchRanges))`: non-aliased **and** JVM-unmodifiable. No other accessor in the file retains an internal mutable collection. |
| 2 | Med | The API-shape test would still pass if a raw `(title, ranges)` producer were re-added. | **RESOLVED** — `TocTitleFilterTest.kt:537-550` reflects over `TocRowText.Companion.declaredMethods`, asserts exactly two producers, and rejects one taking raw `String` + `List`. It constrains the API **shape**, not today's behaviour. |
| 3 | Med | `TocFilterResult.Matched` was a sealed **interface**, so a same-package file could supply an inconsistent `size`/`get` pair and crash a consumer iterating `0 until size`. | **RESOLVED** — `TocTitleFilter.kt:111-139` is now a sealed **class** with a private constructor and a private nested impl; a subclass would have to call the private constructor. Pinned by a reflection test at `:553-574`. |
| 4 | Low | KDoc referenced the removed `Matched.indices`. | **RESOLVED** — `:332-337`. |

### Both plan deviations AGREED

**(a) `Matched` exposes `size` / `get(position)` / `contains(originalIndex)` instead of plan §5.1's
`val indices: IntArray`.** Handing out a mutable array made the strictly-ascending precondition of
`contains`'s binary search a *convention a caller could break*. The auditor confirmed WI-4's
`LazyColumn` retains everything it needs. **(b) `TocFoldedToc` drops the `entries` field** — nothing
read it; the original entries stay with the sheet caller. Dead-state removal.

### No new findings, and the hot path was checked

The defensive copy is **per returned row range list only**, not whole-corpus: `FoldedTitle.matchRanges`
builds only that row's occurrences (`:204-214`) and `TocRowText` snapshots only that small list
(`:66-68`). `filter` still preserves ascending original indices (`:160-168`, `:327-329`), `rowText`
still resolves title and ranges from **one** corpus index (`:175-187`), and `contains` is still a
binary search (`:126-127`) — so the immutability hardening did not disturb the measured budgets.

Auditor note: verified by branch diff and static inspection; it did not run Gradle (read-only
sandbox). The orchestrator re-runs the suite independently before opening the PR.

Auditor: Codex `gpt-5.6-sol`, read-only sandbox, driven through `scripts/run-codex.sh` (rule 53).
Three rounds — the rule-47 cap. Round transcripts: `.reports/audit-r{1,2,3}.txt` (worktree-local).

| Round | threadId | Verdict | Findings |
| --- | --- | --- | --- |
| 1 | `019fd4c5-9827-7513-856f-c3b10f085ce5` | `block-recommended` | 1 High, 1 Medium, 4 Low |
| 2 | `019fd4d9-7d18-7c91-b8f9-d1f42bc42eef` | `block-recommended` | 1 High (partial close of r1's High); Medium + Low classes explicitly empty |
| 3 | `019fd4df-d798-70f1-81fc-e173f751612e` | `block-recommended` | 1 High, 2 Medium, 1 Low; Critical explicitly empty |

**No round returned a clean verdict, so this artifact records `block-recommended` — the last verdict
an independent auditor actually gave.** Every round-3 finding was fixed afterwards, but rule 47 caps
Gate 4 at three rounds, so those fixes are NOT independently verified. The lane's HANDOFF is
`blocked` for exactly that reason; see "State at handoff" below.

---

## Round 1

| # | Sev | Finding | Disposition |
| --- | --- | --- | --- |
| 1 | Critical | *none* | — |
| 2 | **High** | `TocRowText` was forgeable: the constructor was private, but an `internal` companion exposed `untinted(title)` / `tinted(title, ranges)`, so any module code could pair one row's title with another row's ranges — the exact defect plan §5.2.1 exists to prevent, relocated into the seam built to close it. | **Fixed** (r1): the factories were deleted; `TocRowText` became a `sealed interface` with a single file-private implementation. Round 2 judged this only a *partial* close — see r2 finding 1. |
| 3 | Medium | `TocFilterResult.Matched` publicly accepted and exposed a mutable `IntArray`, so the strictly-ascending precondition of `contains`'s binary search was a convention a caller could break (`intArrayOf(7,0,3)`, or mutation after construction). | **Fixed**: `Matched` no longer exposes an array. It offers `size` / `get(position)` / `contains(originalIndex)` over an implementation-owned array. **Deviation from plan §5.1**, which declared `class Matched(val indices: IntArray)`; the plan's composable sketch's `result.indices.size` / `result.indices[i]` become `result.size` / `result[i]`. Round 2: *"The plan deviation is correct. WI-4's `LazyColumn` retains everything it needs."* |
| 4 | Low | Hostile index-map cases named by the plan were unpinned: astral inside/as-query, CJK Ext B, stacked marks, an orphan mark followed by a matchable base. | **Fixed**: added `surrogatePairs_before_inside_after_andAsTheQuery`, `stackedCombiningMarks_allExtendTheSameBaseCharacter`, `orphanCombiningMarkBeforeAMatch_doesNotShiftTheRange`, `lengthChangingFoldAdjacentToAStackedMark`, plus `codePointsAreTheIntendedOnes` pinning every fixture constant. Closed in r2. |
| 5 | Low | The cost-B `best = min(all passes)` assertion was implied by the cold assertion and therefore gated nothing. | **Fixed**: the warm statistic is `min(passes 2..n)` — independent of the cold reading — and passes are labelled `cold`/`warm` in the log. Closed in r2. |
| 6 | Low | **Plan erratum, not an implementation defect.** Plan §3's measured table claims the ligature U+FB01 does not fold and lists it as an accepted divergence from iOS. Unicode full case folding maps U+FB01 to `"fi"` (CaseFolding.txt carries a full mapping for the Latin ligatures), so ICU closes it and Android *agrees* with iOS. | **Not fixed here — reported.** `dev-docs/` is outside this work item's write-set. The implementation follows the plan's normative *algorithm* (ICU full folding) rather than its predicted table, and `ligature_foldsLikeIcuFullCaseFolding` pins the measured behaviour. Round 1: *"Renaming the test and pinning measured ICU behavior was the right implementation decision."* Orchestrator to correct plan §3, its residual/divergence text, and the §8.1 test name. |
| 7 | Low | File length vs the ~300-line guideline. | **Accepted, not actioned.** Round 1: *"Rule 50 says '~300 lines,' not a hard cap, and the declared write-set prevents a sensible split. Cutting useful documentation merely to cross the number would weaken rule-22 maintainability. No fix is required."* Re-adjudicated and re-accepted in rounds 2 and 3. |

Round 1 also confirmed, on inspection: the folding algorithm is correct (per-display-code-point ICU
full folding → NFD → Mn removal → UTF-16 index duplication → following-mark end extension, with no
off-by-one); the ASCII fast path is exact across U+0000–U+007F; both `filter` early branches leave
the lazy corpus untouched; blank titles cannot match or tint `Untitled`; corpus construction is
immutable and safe for Compose reads; and making `collapseLineBreaks` `internal` has only the
intended additional caller.

## Round 2

Medium and Low classes **explicitly empty**. F3, F4, F5 and F7 closed; F6 confirmed as a plan
erratum outside this write-set.

| # | Sev | Finding | Disposition |
| --- | --- | --- | --- |
| 1 | **High** | r1's High only *partially* closed. A sealed **interface** may still be implemented by another file in the same package + module, so a forged mismatched title/ranges pair remained writable, and the test's "no subtype a caller can add" claim was false. Prescribed fix: a sealed/abstract **class** with a private constructor and private nested implementation, exposing only producers that accept an entry or a corpus index — never raw title/ranges. | **Fixed** exactly as prescribed: `sealed class TocRowText private constructor(...)`, one `private class Row` nested inside it, and two companion producers — `plain(entry)` (no range parameter at all) and `forRow(corpus, index, foldedQuery)` (one index drives both halves). `TocFoldedToc` gained `internal matchTitleAt` / `matchRangesAt` so `forRow` can read the corpus. Round 3 verified the subclass hole is closed but found a *different* escape — see r3 finding 1. |

Round 2 fresh checks, all clean: no boxing, no behaviour change, no extra per-composition allocation
from the interface calls; the shared empty-result singleton is safe; the `matchedResult` test helper
is sound and makes nothing tautological; `TocFoldedToc.filter` returning a raw fresh `IntArray` is
correctly scoped.

## Round 3 (final)

Critical **explicitly empty**.

| # | Sev | Finding | Disposition |
| --- | --- | --- | --- |
| 1 | **High** | The subclass hole was closed, but `matchRanges` handed back the very `ArrayList` `FoldedTitle.matchRanges` had just built. `(row.matchRanges as MutableList).clear(); addAll(otherRowsRanges)` therefore re-pointed one row's tint at another row's ranges through a nominally read-only `List` — no constructor and no subclass required. | **Fixed after round 3, unverified.** `TocRowText.matchRanges` is now an unmodifiable snapshot: `Collections.unmodifiableList(ArrayList(matchRanges))`, with `emptyList()` reused when empty so the unfiltered path still allocates nothing. Both halves matter — the copy breaks aliasing to the fold, the wrapper defeats the cast-and-mutate. Pinned by `rowText_rangesAreAnImmutableSnapshotNotTheFoldsOwnList`, which a mutation removing the wrapper kills. |
| 2 | Medium | `tocRowText_cannotBeSubclassedOrForgedAnywhere` pinned constructor/subclass shape but not ownership of the exposed range collection, and would also pass if a raw `(title, ranges)` companion producer were re-added. | **Fixed after round 3, unverified.** Added the mutation regression above, plus `tocRowText_hasNoProducerThatAcceptsARawTitleAndRangePair`, which asserts the companion has exactly two producers and that none takes a `String` first argument together with a `List` — so re-adding the round-1 defect trips a test even though the class shape would still look correct. |
| 3 | Medium | The `Matched` asymmetry was not defensible as documented: another same-package file could implement the sealed interface with inconsistent `size`/`get`, which crashes a consumer iterating `0 until size` rather than merely misplacing the pinned row. The test name `matched_ownsItsIndicesAndIsNotCallerConstructible` was therefore false. | **Fixed after round 3, unverified.** `Matched` now gets the same hardening as `TocRowText`: `sealed class Matched private constructor()`, one `private class Indices` nested inside it, and an `internal companion` exposing `EMPTY` and `of(ascending)`. The test is renamed `matched_cannotBeSubclassedAndOwnsItsIndices` and asserts the class shape rather than the former, weaker claim. |
| 4 | Low | KDoc on `isActiveFilteredOut` still referenced the removed `Matched.indices` property. | **Fixed after round 3, unverified.** Rewritten to describe the implementation-owned ascending indices reached through `contains`. |

Round 3 re-confirmed: the untitled-label behaviour is still correct (blank titles fold to `""`, never
match `"untitled"`, and both rendering branches return the label with empty ranges without consulting
a fold); no new hot-path allocation; no dead refactor code; the 382-line file remained acceptable
under the constrained write-set.

---

## State at handoff

Applied after round 3 and **green**, but not seen by an independent auditor:

- `TocRowText.matchRanges` is an unmodifiable, non-aliased snapshot (r3 #1).
- `tocRowText_hasNoProducerThatAcceptsARawTitleAndRangePair` + the mutation regression (r3 #2).
- `Matched` hardened to sealed-class + private constructor + private nested impl (r3 #3).
- The stale `Matched.indices` KDoc corrected (r3 #4).

Gates after those edits: JVM `TocTitleFilterTest` **54 tests / 0 skipped / 0 failures**; full app JVM
suite **2 435 / 0 skipped / 0 failures**; connected `TocFilterCostTest` **3/3** on the real
1 859-entry `黑暗血时代.txt`.

**Why the lane hands off `blocked`.** The brief's bar for `ready-for-integration` is an audit that is
"clean or follow-up-recommended". The last verdict from an independent auditor is
`block-recommended`, and the fixes that answer it postdate the third and final permitted round. The
orchestrator should either verify these four edits directly — the precedent is this feature's own
Gate-2 v4, which closed round-3 tightening edits without a fourth round — or authorise one more
round.

## Mutation testing

Ten mutations were run; each was reverted after its run, and each reddened *specific* tests.

| # | Mutation | Tests killed |
| --- | --- | --- |
| 1 | blank branch returns `Matched(0..n-1)` instead of the `Unfiltered` singleton | 4 — `whitespaceOnlyQuery_treatedAsEmpty`, `emptyQuery_returnsAllEntriesWithOriginalIndices`, `blankQuery_returnsUnfilteredSingleton_notAList`, `blankQuery_neverForcesTheFold` |
| 2 | public `TocRowText` constructor | 1 — the API-shape test |
| 3 | `FoldedTitle.of` fed `UNTITLED_LABEL` for a blank title | 1 — `queryUntitled_matchesZeroRows_inTocWithBlankTitles` |
| 4 | the simple-folding `UCharacter.foldCase(int, Boolean)` overload | 4 — `caseFold_sharpS`, `caseFold_usesFullFoldingNotSimple`, `matchRanges_mapBackToDisplay_afterLengthChangingFold`, `ligature_foldsLikeIcuFullCaseFolding` |
| 5 | blank-title branch returns ranges | 1 — `rowText_untitledRow_hasEmptyRangesEvenWhenQueryMatchesTheLabel` |
| 6 | drop the `ends`-extension rule | 2 — `matchRanges_endExtendsOverTrailingCombiningMark`, `diacriticInsensitive_decomposed` |
| 7 | folded indices used directly as display indices (the design mock's bug) | 4 |
| 8 | `contains()` always `true` | 1 — `isActiveFilteredOut_activeFilteredOut_isTrue` |
| 9 | mutation 7 re-run against the round-1-hardened suite | **7** (up from 4 — evidence the r1 #4 additions bite) |
| 10 | drop the unmodifiable snapshot on `matchRanges` | 1 — `rowText_rangesAreAnImmutableSnapshotNotTheFoldsOwnList` |

No mutation killed zero tests.

## On-target cost measurement (plan §6, moved into WI-1 so WI-4 decides with a number)

Emulator `vreader-test` (API 35), real 1 859-entry `黑暗血时代.txt` pushed per run, titles produced by
the shipped `TxtMdTocProvider`, fixture identity pinned by SHA-256 + decoded length + entry count.

| Cost | Budget | Measured | Verdict |
| --- | --- | --- | --- |
| **A** — not-filtering path (12-row window + `filter("")`) | ≤ 8 ms | **0.039 ms**, corpus `Lazy` NOT forced | pass, ~200× headroom |
| **B** — corpus fold, 1 859 titles | ≤ 120 ms | **30 ms cold / 24 ms warm-best** (runs: 30,24,26,36,42) | pass, ~4× headroom |
| **C** — worst single keystroke | ≤ 8 ms | **0.998 ms** (worst of 6 real CJK queries) | pass, ~8× headroom |

**Consequence for WI-4: do NOT build plan §6's off-thread corpus fold.** It was pre-designed to be
built "iff WI-1's cost-B measurement exceeded 120 ms"; the measurement is 30 ms cold. The plan feared
a 5–100× desktop-to-device factor on the 18.66 ms desktop figure; the actual factor is ~1.6×.
Likewise no debounce is warranted — cost C sits at ~12 % of its budget.
