---
branch: feat/feature-101-wi-2a-reading-time-model
threadId: 019eb59e-6bee-7333-a754-36aa7230585e
rounds: 2
final_verdict: ship-as-is
date: 2026-06-11
---

# Feature #101 WI-2a — Gate 4 implementation audit

Plan: `dev-docs/plans/20260611-feature-101-reading-time.md` (WI-2a: per-book
`firstSessionDate` fetch + the testable `BookReadingTimeModel.build`
deriving the Book details Reading time group strings). Runner:
`scripts/run-codex.sh` (codex exec, read-only). Round-2 session:
`019eb5a9-aaba-7163-a775-c19b89538918`.

## Round 1 findings

| Finding | Severity | Resolution |
|---|---|---|
| `BookReadingTimeModel.swift:47` — average rounded raw seconds then `formatDuration` floored to minutes, so 90–119s averages rendered "1m" instead of "2m" (the plan's "rounds to minutes" contract) | Medium | **Fixed** — rounds at the minute level (`(total/count/60).rounded()` then format `minutes*60`); parameterized boundary tests at 89/90/95/119/120/149/150s. |
| `PersistenceActorStatsReadTests.swift:372` — WI additions grew an already-over-budget test file to 422 lines with duplicated local helpers | Low | **Fixed** — both per-book suites moved to `PersistenceActorPerBookStatsTests.swift` with the shared helpers defined once; the read-tests file trimmed to 292 lines. |

Round 1 also explicitly confirmed `firstSessionDate(forBookWithKey:)` is
actor-safe and fetch-efficient (filtered query, store-side sort,
`fetchLimit = 1`, no cross-actor model leakage).

## Round 2 (verify)

Clean — both fixes confirmed in the diff, boundary tests pin the
regression, no new issues.

## Verdict

ship-as-is. Tests: 27 green across the 4 touched suites (15 model
derivations incl. the rounding boundaries, 2 first-date fetches, 3
per-book stats fetches, 7 untouched read-suite regressions).
