---
branch: feat/feature-58-wi-2-stats-aggregator
threadId: 019e40b9-4d10-7840-b198-707d9b8b71b2
rounds: 2
final_verdict: ship-as-is
date: 2026-05-19
---

# Gate 4 — Implementation Audit: feature #58 WI-2 (ReadingStatsAggregator)

Codex MCP (read-only sandbox), thread `019e40b9-4d10-7840-b198-707d9b8b71b2`.
Author/auditor separation per rule 48: Codex is a separate process from the
implementing Claude Code session.

Changed files:
- `vreader/Services/Stats/ReadingStatsAggregator.swift` (NEW, ~160 lines) — the actor
- `vreader/Services/PersistenceActor+Stats.swift` (MODIFIED +55) — `fetchAllReadingSessions` / `fetchAllReadingStats`
- `docs/architecture.md` (+1, doc-sync)
- `vreaderTests/Services/Stats/ReadingStatsAggregatorTests.swift` (NEW)
- `vreaderTests/Services/Stats/PersistenceActorStatsReadTests.swift` (NEW)

## Round 1 — findings (0 Critical / 1 High / 1 Medium / 0 Low)

| # | Severity | File:line | Issue | Resolution |
|---|---|---|---|---|
| 1 | High | ReadingStatsAggregator.swift (computePerBook) | The per-book table was built only from `sessionsByKey`, so a live `Book` with zero sessions was omitted entirely — contradicts the plan's resolved edge case (a) ("zero-session book → still show a `0m` row"). | **Fixed.** `computePerBook` now builds rows from the UNION of every live `Book.fingerprintKey` and every session key (`Set(bookByKey.keys).union(sessionsByKey.keys)`). A live book with no sessions → a `0m` row, `lastReadAt` nil; an orphan session key still surfaces as a deleted-book row. Reading seconds / `lastReadAt` are still derived from `ReadingSession` rows ONLY — the F10 "never read `ReadingStats`" rule is preserved. |
| 2 | Medium | ReadingStatsAggregatorTests.swift | Tests did not cover edge case (a), and never verified live-book `annotations`/`highlights` relationship counts despite the plan promising that coverage. | **Fixed.** Added `liveBookWithNoSessionsStillShownAsZeroRow` (seeds a Book with zero sessions, asserts the `0m` row) and `liveBookHighlightAndNoteCountsMatchRelationships` (seeds 3 `Highlight` + 2 `AnnotationNote` via the cascade relationship, asserts the counts). |

Round-1 clean dimensions: the F8/F10 consistency model is correctly implemented
— one actor-local `ModelContext`, no `ReadingStats` reads in `snapshot`, window
bucketing by `startedAt`, `lastReadAt = max(endedAt ?? startedAt)`,
`lifetimeTotalSeconds = sum(max(0, durationSeconds))`, `trackingSince =
min(startedAt)`. No Swift 6 concurrency issues (actor isolation correct,
`ModelContext` confined within the actor method, `@Sendable () -> Calendar`
provider sound, no `@Model` leaks across the boundary).

## Round 2 — verification

Codex confirmed both findings resolved, zero open findings at any severity.
Note: Codex could not re-run `xcodebuild test` (read-only sandbox). The
implementing session ran the gate: **18 tests in 2 suites pass** under
`xcodebuild test -only-testing:vreaderTests` on iPhone 17 Pro Simulator.

## Verdict

**ship-as-is** (round 2). 0 open Critical/High/Medium/Low findings after 2
rounds (rule-47 max is 3). WI-2 is a foundational WI — an actor with no
user-observable behavior; Gate 5a is satisfied by unit tests + this audit.
