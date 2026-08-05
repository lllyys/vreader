---
branch: feat/164-wi-5-viewmodel
threadId: 019fcfb9-0c34-7832-9e7a-c998e3f1297f
rounds: 3
final_verdict: ship-as-is
date: 2026-08-05
---

# Codex Audit Log — Feature #164 (GH #2023) WI-5

`DiagnosticsViewModel` / `DiagnosticsUiState` / `DiagnosticsDayGrouper` — the
filter / compose / group / label layer between WI-4's `DiagnosticsLogStore` and
WI-6's Compose surfaces. Foundational tier, but it owns every user-visible string
format in the viewer, so its tests are the contract WI-6 renders against.

Runner: `scripts/run-codex.sh` (rule 53). Reports: `.reports/audit-r1.txt`,
`.reports/audit-r2.txt`, `.reports/audit-r3.txt`.

| Round | Session id | Verdict |
| --- | --- | --- |
| 1 | `019fcf9c-d124-7043-a711-2b2faee56892` | block-recommended |
| 2 | `019fcfab-905f-7e20-b31b-48e72c2ea088` | follow-up-recommended |
| 3 | `019fcfb9-0c34-7832-9e7a-c998e3f1297f` | **ship-as-is** |

The audit prompt named the three deliberate iOS divergences up front and asked the
auditor to judge each, and explicitly asked it to adjudicate the plan's open
rule-51 question (the day header for a day that is neither today nor yesterday)
rather than accept the author's reading.

## Round 1 — 1 High, 3 Low

**HIGH — `load()` permitted overlapping calls.** `DiagnosticsLogStore`'s own KDoc
states that loads are expected to be SINGLE-FLIGHT and that `lastLoadDegraded` is a
store-WIDE latch whose verdict belongs to the load that completes last. The
ViewModel did not serialise, so two reads in flight could let one batch inherit the
other's capture-source verdict — a diagnostics export naming the wrong provenance,
which is the one thing this feature must never do. The auditor also noted that an
earlier load's `finally` could publish `isLoading = false` while a later load was
still running.

*Fix*: a `Mutex` around the store read plus an `AtomicInteger` of outstanding calls,
so the spinner drops only when the last one finishes. Regression test
`overlappingLoadsAreSerialisedAndTheSpinnerOutlastsTheFirstOne` asserts max
concurrency 1, that the queued read has not started, that `isLoading` survives the
first load's `finally`, and that the last-completing batch is the one on screen.
Verified RED against **both** halves of the defect independently (mutex removed →
the queued read starts; unconditional `isLoading = false` → the spinner drops early).

**LOW — Purpose KDoc inaccurate (rule 22).** It claimed "1:1 in semantics" while
three Android divergences are deliberate, and claimed a throw always leaves
`hasLoaded` false — untrue for a failed RELOAD, which correctly retains the previous
batch. *Fix*: reworded to name the three plan-authorised divergences and to state the
first-load / reload distinction.

**LOW — reload coverage gap.** Nothing proved a reload drops a stale positional
expanded id; deleting that line would have passed the suite. *Fix*:
`aReloadOntoASmallerBatchDropsTheStaleExpandedRow`, verified RED with the reset
removed.

**LOW — `DiagnosticsViewModelTest` exceeds ~300 lines. ACCEPTED, not fixed.** The
convention as practised in this package exempts test suites: the sibling
`DiagnosticsRedactorTest` (1,117 lines) and `DiagnosticsLogStoreTest` (1,067 lines)
are far larger, and splitting one coherent ViewModel suite would scatter shared
fixtures for a line count alone. Round 2 examined the siblings itself and accepted
this rationale.

## Round 2 — both Highs' fixes verified, one shared residual

R1-3 RESOLVED, R1-4 accepted. R1-1 and R1-2 came back **PARTIALLY RESOLVED** for one
shared reason: `pendingLoads` was incremented *before* the initial `publish()` entered
the `try`, and `publish()` calls the injected clock/zone/locale — so a throwing clock
could leak the count between the increment and the `finally` and strand `isLoading`
true for every later load. No new findings; round 1's clean areas re-confirmed clean.

*Fix*: the increment is now the only statement outside the `try`, and `AtomicInteger`
cannot throw. New regression test `aThrowingClockDoesNotLeakTheOutstandingLoadCount`
(a clock that throws during the first load's publish, then a healthy load, asserting
the spinner is down), verified RED with the `try` moved back after `publish()`.

This was a code change answering an independent auditor's finding, so it was **not**
self-certified — round 3 was run to confirm it.

## Round 3 — ship-as-is

> R1-1: RESOLVED — Every exit path decrements exactly once before the final publish; a
> throwing final publish can mask the original exception but cannot leak the count.
> R1-2: RESOLVED — The regression test fails under the old placement because the second
> load leaves `isLoading` true, and passes only when the first load's count is released.
>
> VERDICT: ship-as-is

No new findings.

## Rule 51 adjudication (the plan flagged this for a ruling, not an author's choice)

The plan's WI-5 spec says that if the older-day header is judged **undepicted** rather
than derivable, that is a `needs-design` filing and not an implementer's call. Put to
the auditor independently in every round; it raised **no finding** in any of them.

The header is `"Today · 10 June"` / `"Yesterday · 9 June"` (`vreader-diagnostics.jsx:308`);
an older day renders the same date fragment **alone** (`"8 June"`). This is the only
composition that invents nothing — it reuses the depicted `"D Month"` fragment and
omits a relative word that would be false — and it is exactly what iOS #96 already
ships against the same design bundle (`DiagnosticsDaySection.header`,
`DiagnosticsLevelStyle.swift:102-105`). Treated as derivable; **no `needs-design`
filing**. Same ruling, same reasoning, for the footer's number agreement
(`"1 entry"`, `"0 of 1 entry"`) and the descriptor composition (`"Persistence errors"`),
all of which follow iOS's established `activeFilterDescriptor`.

Two design gaps that DO bind this feature are already filed and are not WI-5's to
resolve: **GH #2021** (WARN level treatment — WI-5 ships plan section 6.3's interim,
WARN reachable under `All` only, asserted explicitly so a later change is
test-breaking) and **GH #2022** (capture-unavailable empty state — which is why the
degraded-capture flag is deliberately *not* surfaced in this layer's UI state).

## Deliberate divergences from iOS, all judged and none flagged

1. **Three footer grammars, not iOS's two.** iOS predates the F3 artboard; the
   filtered-empty line is a distinct sentence (`"0 of N entries"`,
   `vreader-diagnostics.jsx:484`), not the filtered line with a zero in it.
2. **Category matching through `DiagnosticsCategoryBounding.chipFor`**, not iOS's raw
   tag equality — the bounding rule exists only on Android, and matching the raw tag
   would leave every collapsed framework entry reachable under `All` alone.
3. **State recomputed into a `MutableStateFlow`** rather than the plan's sketched
   `map`/`stateIn`. That pattern exists to flatten a repository Flow; this store is a
   one-shot `suspend load()`, and `stateIn(WhileSubscribed)` would leave `state.value`
   stale until the screen subscribes — while `load()` runs before first composition.
   The shape used is the house `InBookSearchViewModel` (#133) one.

## Test gate

`ANDROID_CMD="cd android && ./gradlew :app:testDebugUnitTest --tests '*diagnostics*' --rerun-tasks" scripts/run-android-tests.sh`
→ `RUN-ANDROID-TESTS RESULT: SUCCEEDED`, **307 tests / 0 failures** across the
diagnostics package (252 before this WI; +55 = 42 `DiagnosticsViewModelTest` + 13
`DiagnosticsDayGrouperTest`). Counts read from the JUnit XML, not from
`BUILD SUCCESSFUL`.

## Mutation pass (the brief's required kill map — every mutation killed)

| # | Mutation | Killed by |
| --- | --- | --- |
| 1 | `Errors` → `{ERROR}` (drop ASSERT) | `errorsChipMatchesTheErrorAndAssertSet_neverJustError` + 4 more |
| 2 | counts computed over the filtered list | `chipCountsAreCategoryIndependent`, `chipCountsAreAlsoIndependentOfTheActiveLevelChip` |
| 3 | row identity = `entry.hashCode()` | `byteIdenticalEntriesExpandIndependently`, `rowIdentityIsThePositionInTheFilteredList` |
| 4 | filtered-empty footer → the filtered-with-results format | `theFilteredEmptyFooterUsesItsOwnGrammar`, `theFilteredEmptyFooterAgreesWithTheTotalInNumber` |
| 5 | day header drops the `· D Month` suffix | 9 grouper tests + `sectionsUseTheInjectedClockAndZone` |
| 6 | yesterday = `now - 86_400_000` instead of `LocalDate.minusDays(1)` | `yesterdayIsTheLocalCalendarDay_notNowMinus24Hours` (only) |
| 7 | date formatter hardcodes `Locale.ENGLISH` | `aNonGregorianLocaleLocalisesTheMonth…`, `sectionHeadersFollowTheInjectedLocale` |
| 8 | mutex removed from `load()` | `overlappingLoadsAreSerialisedAndTheSpinnerOutlastsTheFirstOne` |
| 9 | unconditional `isLoading = false` in the `finally` | same test, different assertion |
| 10 | reload keeps the expanded id | `aReloadOntoASmallerBatchDropsTheStaleExpandedRow` |
| 11 | `try` moved back after the first `publish()` | `aThrowingClockDoesNotLeakTheOutstandingLoadCount` |

Mutations 6 and 7 were run specifically to prove the DST and non-Gregorian-locale
tests assert real behaviour rather than "it didn't crash" — each was killed by its own
test and no other. **No surviving mutations.**
