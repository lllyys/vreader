---
branch: feat/feature-58-wi-4-dashboard-viewmodel
threadId: 019e40cb-56e6-7e23-81ff-29484ac51541
rounds: 2
final_verdict: ship-as-is
date: 2026-05-19
---

# Gate 4 — Implementation Audit: feature #58 WI-4 (ReadingDashboardViewModel)

Codex MCP (read-only sandbox), thread `019e40cb-56e6-7e23-81ff-29484ac51541`.
Author/auditor separation per rule 48: Codex is a separate process.

Changed files:
- `vreader/ViewModels/ReadingDashboardViewModel.swift` (NEW, ~120 lines) — the VM
- `vreader/Services/Stats/ReadingStatsAggregator.swift` (MODIFIED) — adds `ReadingStatsAggregating` protocol, conforms the actor
- `vreaderTests/ViewModels/ReadingDashboardViewModelTests.swift` (NEW)

## Round 1 — findings (0 Critical / 1 High / 1 Medium / 0 Low)

| # | Severity | Issue | Resolution |
|---|---|---|---|
| 1 | High | `refresh()` had no in-flight request tracking — overlapping `load()` / `selectWindow()` / `selectSort()` calls could complete out of order, letting a stale earlier result overwrite a newer snapshot while `activeWindow`/`sort` already point at newer state. | **Fixed.** `refresh()` claims a monotonic `latestRequestID`, captures `activeWindow`/`sort` into locals before the `await`, and after the aggregator returns (success OR catch) `guard requestID == latestRequestID else { return }` — a superseded request drops its result. |
| 2 | Medium | The suite covered serialized happy-path/error cases but never overlapping refreshes, so the stale-result bug would ship undetected. | **Fixed.** Added `staleRefreshDoesNotOverwriteANewerSnapshot` — a `GatedAggregator` actor whose `snapshot` blocks on a per-window `CheckedContinuation` gate the test opens. The test starts request A (today) + request B (last30Days), releases the NEWER B first, then A, and asserts the VM keeps B's snapshot. Fails on pre-fix code, passes on the fix. |

Round-1 confirmation: the VM otherwise matches the WI-4 contract — owns
`activeWindow`/`sort`, drives the aggregator, exposes `snapshot`, persists+
restores the sort under `stats.dashboardSort`, does NOT persist the window
(fresh dashboard opens on "Today" — correct per the design). The corrupt-sort
fallback and error-clears-after-success paths are correct. Swift 6 boundary is
sound — calling an `async` method on an `any ReadingStatsAggregating & Sendable`
from `@MainActor` is fine, and `actor ReadingStatsAggregator: ReadingStatsAggregating`
conformance is correct. `private(set)` on the observable props is fine.

## Round 2 — verification

Codex confirmed both findings resolved, zero open findings at any severity, no
remaining merge blocker. The implementing session ran the gate: **11 tests in 1
suite pass** (`xcodebuild test`, iPhone 17 Pro Simulator).

## Verdict

**ship-as-is** (round 2). 0 open Critical/High/Medium/Low findings after 2
rounds (rule-47 max is 3). WI-4 is a foundational WI — a ViewModel with no
user-visible surface yet (the View is WI-6); Gate 5a is satisfied by unit
tests + this audit.
