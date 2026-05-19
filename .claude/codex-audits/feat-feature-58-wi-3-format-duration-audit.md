---
branch: feat/feature-58-wi-3-format-duration
threadId: 019e40c3-69c7-77e1-b615-d28fc177af8a
rounds: 2
final_verdict: ship-as-is
date: 2026-05-19
---

# Gate 4 — Implementation Audit: feature #58 WI-3 (ReadingTimeFormatter.formatDuration)

Codex MCP (read-only sandbox), thread `019e40c3-69c7-77e1-b615-d28fc177af8a`.
Author/auditor separation per rule 48: Codex is a separate process.

Changed files:
- `vreader/Utils/ReadingTimeFormatter.swift` (MODIFIED) — adds `formatDuration(totalSeconds:)`
- `vreaderTests/Utils/ReadingTimeFormatterTests.swift` (MODIFIED) — adds `ReadingTimeFormatterDurationTests`

## Round 1 — findings (0 Critical / 0 High / 0 Medium / 2 Low)

| # | Severity | Issue | Resolution |
|---|---|---|---|
| 1 | Low | The duration test suite covered the plan catalogue but did not pin the very-large-value edge — a later refactor could change `Int.max` behavior unnoticed. | **Fixed.** Added `extremeValuesStayStable` — asserts `formatDuration(.max) == "2562047788015215h 30m"` and `formatDuration(.min) == "0m"`. The `.max` assertion was run under `xcodebuild test` (no overflow). |
| 2 | Low | The `ReadingTimeFormatter` type doc said the formatter is for display "in the library" — stale now that `formatDuration` is for the stats dashboard. | **Fixed.** Broadened the type comment to name both the Library list rows and the reading-stats dashboard. |

Round-1 confirmation: `formatDuration` matches the WI-3 plan catalogue exactly
for 0 / 59 / 60 / 3599 / 3600 / 5400 / 90000 / negatives. The 3599→3600 boundary
and the >24h no-rollup behavior are correct. The `Int.max` path does not
overflow. The `"<1m"`-vs-`"0m"` divergence from `formatReadingTime` is
intentional and correct for a stats dashboard; the small duplication versus
`formatReadingTime` is acceptable given two genuinely different contracts.

## Round 2 — verification

Codex confirmed both Low findings resolved, no remaining correctness/edge/doc/
duplication issues. The implementing session ran the gate: **35 tests in 2
suites pass** (`ReadingTimeFormatterTests` + the new `formatDuration` suite).

## Verdict

**ship-as-is** (round 2). 0 open findings at any severity. WI-3 is a
foundational WI — a pure formatting function with no user-observable behavior;
Gate 5a is satisfied by unit tests + this audit.
