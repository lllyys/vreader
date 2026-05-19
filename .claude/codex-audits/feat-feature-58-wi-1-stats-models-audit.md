---
branch: feat/feature-58-wi-1-stats-models
threadId: 019e4053-b048-7233-ab66-4775011c1c09
rounds: 3
final_verdict: ship-as-is
date: 2026-05-19
---

# Gate 4 — Implementation Audit: feature #58 WI-1 (ReadingStatsModels)

Codex MCP (read-only sandbox), thread `019e4053-b048-7233-ab66-4775011c1c09`.
Author/auditor separation per rule 48: Codex is a separate process from the
implementing Claude Code session.

Changed files:
- `vreader/Services/Stats/ReadingStatsModels.swift` (NEW, 298 lines)
- `vreaderTests/Services/Stats/ReadingStatsModelsTests.swift` (NEW, 223 lines)
- `vreaderTests/Services/Stats/ReadingDashboardSnapshotTests.swift` (NEW, 130 lines)

## Round 1 — findings (0 Critical / 0 High / 2 Medium / 1 Low)

| # | Severity | File:line | Issue | Resolution |
|---|---|---|---|---|
| 1 | Medium | ReadingStatsModels.swift:65 | The API contract says each window is half-open `[start, now)`, but `dateInterval` returns a raw `DateInterval` — `DateInterval.contains(_:)` is end-INCLUSIVE, so a WI-2 consumer using the obvious helper would wrongly count a session at exactly `now`. | **Fixed.** Added `ReadingStatsWindow.contains(_:now:calendar:)` — explicit half-open `date >= start && date < end` (allTime → always true). `dateInterval` doc now warns callers to use `contains(...)` not `DateInterval.contains(_:)`. Added 4 regression tests incl. `containsExcludesExactlyNow`. |
| 2 | Medium | ReadingStatsModels.swift:205 | `ReadingDashboardSnapshot` documented to carry all 7 `windowTotals` in canonical order, but the memberwise init accepted missing/duplicate/misordered entries — invariant not enforced. | **Fixed (round 2).** The struct now has a SINGLE initializer that normalizes its input: missing window → zero-filled, duplicate → first wins, input order discarded. Output is always 7 entries in canonical `allCases` order. No production or test code path can build a malformed snapshot. |
| 3 | Low | ReadingStatsModelsTests.swift:111 | Sort matrix coverage incomplete — missing `title` desc, `highlights` asc, `notes` asc; `storageString` round-trip incomplete for the 8 field/direction combos. | **Fixed.** Added the 3 missing comparator cases; `roundTripsThroughStorageString` is now `@Test(arguments: ReadingDashboardSortField.allCases, [true, false])` — full 8-combo matrix. |

Round-1 clean dimensions: no Swift 6 `Sendable` issues (all members value-typed,
`Locator` is `Codable`/`Sendable`); no `Codable` synthesis issues; no dead code;
files under 300 lines. Rolling-window math (`now - N·86400s`) confirmed correct
for a "rolling N-day" window — calendar-day arithmetic would drift on DST and is
not what the contract specifies.

## Round 2 — re-audit (1 Medium + 2 Low)

| # | Severity | Issue | Resolution |
|---|---|---|---|
| 2 (re-open) | Medium | Finding 2 was fixed by a `make(...)` factory + convention, NOT by type safety — the raw memberwise init still admitted malformed input. | **Fixed (round 3 verified).** Removed `make(...)`; folded the normalization INTO the sole initializer. Malformed construction is now impossible at the type level. |
| 3 (partial) | Low | `storageString` round-trip still omitted `.highlights` desc and `.notes` asc. | **Fixed.** Full 8-combo matrix via parameterized arguments. |
| new | Low | Test file grew to 325 lines (> ~300 guideline). | **Fixed.** Split into `ReadingStatsModelsTests.swift` (223) + `ReadingDashboardSnapshotTests.swift` (130). |

## Round 3 — verification

Codex confirmed all findings resolved, no new issues in the updated worktree.
Note: Codex could not re-run `xcodebuild test` (no execution approval in its
read-only sandbox) — test verification on its side was static-review only. The
implementing session ran the gate: **33 tests in 4 suites pass** under
`xcodebuild test -only-testing:vreaderTests` on iPhone 17 Pro Simulator.

## Verdict

**ship-as-is** (round 3). 0 open Critical/High/Medium/Low findings after 3
rounds (rule-47 max is 3). WI-1 is a foundational WI — pure value types, no
user-observable behavior; Gate 5a is satisfied by unit tests + this audit.
