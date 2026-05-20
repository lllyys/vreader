---
branch: feat/58-wi-6a-reading-dashboard-view
threadId: 019e452c-8f32-7ae3-bb3c-f5b647518de2
rounds: 2
final_verdict: ship-as-is
date: 2026-05-20
---

# Gate-4 audit — feat/58-wi-6a-reading-dashboard-view

**Verdict (Round 1)**: follow-up-recommended
**Verdict (Round 2 — final)**: ship-as-is

**Round-1 verdict** (preserved for history):

**Summary**: The WI-6a SwiftUI surface matches the plan’s composition: `ReadingDashboardView` composes `StatsTimeWindowBar` + a single hero total + `StatsPerBookTable`, with VM-owned async selection routed through `selectWindow` / `selectSort`. The diff cleanly omits both deferred items (no Custom range picker; no `last-read` column) and preserves the VM’s `latestRequestID` stale-result discipline.

## Findings

### Critical / High / Medium (must fix)
(none)

### Low (optional; defer or accept with rationale)
- `vreader/Views/Stats/ReadingDashboardView.swift:43`: Sheet title is `"Stats"` (`ReadingDashboardView.sheetTitle`), while the pinned design’s `FullStatsDashboard` uses a sheet title of `"Reading"` in `dev-docs/designs/vreader-fidelity-v1/project/vreader-profile-stats.jsx:393`. If `"Stats"` is the intended app chrome, consider aligning the design bundle (or documenting the intentional divergence) so rule-51 traceability is unambiguous.
- `vreader/Views/Stats/ReadingDashboardView.swift:160`: Hero subtitle copy maps windows to `"last 7 days"`, `"last 30 days"`, etc. The pinned JSX renders `Reading time, {TIME_WINDOWS.label.toLowerCase()}` (e.g. “7d”, “30d”) in `dev-docs/designs/vreader-fidelity-v1/project/vreader-profile-stats.jsx:404`. This may be intentional readability polish, but it is user-visible copy; consider either (a) matching the bundle verbatim or (b) recording the divergence explicitly in the plan/docs so it does not look self-invented.

## What was verified
- `vreader/Views/Stats/ReadingDashboardView.swift`
- `vreader/Views/Stats/StatsTimeWindowBar.swift`
- `vreader/Views/Stats/StatsPerBookTable.swift`
- `vreader/ViewModels/ReadingDashboardViewModel.swift`
- `vreader/Services/Stats/ReadingStatsModels.swift`
- `vreaderTests/Views/Stats/ReadingDashboardViewTests.swift`
- `vreaderTests/Views/Stats/StatsTimeWindowBarTests.swift`
- `vreaderTests/Views/Stats/StatsPerBookTableTests.swift`
- `dev-docs/plans/20260519-feature-58-reading-dashboard.md`
- `dev-docs/designs/vreader-fidelity-v1/project/vreader-profile-stats.jsx`

- Symbols confirmed:
  - `ReadingDashboardSortField` has exactly `.title`, `.readingTime`, `.highlights`, `.notes` (`vreader/Services/Stats/ReadingStatsModels.swift:174`).
  - `StatsPerBookTable.sortableFields` uses exactly that 4-field set (`vreader/Views/Stats/StatsPerBookTable.swift:53`) and no 5th `last-read` column exists in the view.
  - `ReadingStatsWindow` has exactly 7 cases (`today`, `last7Days`, `last30Days`, `last90Days`, `last180Days`, `last365Days`, `allTime`) and there is no `custom` case (`vreader/Services/Stats/ReadingStatsModels.swift:23`); no `case custom` references exist in the new views.

- Edge cases checked:
  - `viewModel.snapshot == nil` → hero duration falls back to `formatDuration(0)` via `?? 0` (`vreader/Views/Stats/ReadingDashboardView.swift:63`).
  - Sort toggle math: active column flips `ascending`; inactive column sets `ascending: false` (`vreader/Views/Stats/StatsPerBookTable.swift:184`).
  - Snapshot total lookup: `ReadingDashboardSnapshot.total(for:)` zero-fills if missing (`vreader/Services/Stats/ReadingStatsModels.swift:261`), and the hero tolerates that via the same lookup.
  - Async race safety: VM uses `latestRequestID` gating so stale `refresh()` results cannot overwrite newer state (`vreader/ViewModels/ReadingDashboardViewModel.swift:95`).

- Safety/compliance confirmed:
  - New SwiftUI views contain no `WKWebView`, no `evaluateJavaScript`, no JS escaping surface, no `#if DEBUG`, and no `print()` (scanned under `vreader/Views/Stats/*.swift`).
  - Files are under ~300 lines: `ReadingDashboardView.swift` (~172), `StatsTimeWindowBar.swift` (~108), `StatsPerBookTable.swift` (~191).

---

# Round 2 (re-audit) — 2026-05-20 — commit `0d153ea`

**Verdict**: ship-as-is

## Round-1 findings status

- [RESOLVED] Sheet title mismatch: `ReadingDashboardView.sheetTitle` is now `"Reading"`, matching the pinned design’s `FullStatsDashboard` sheet title (`<Sheet … title="Reading" …>`).
- [RESOLVED] Hero subtitle copy mismatch: `activeWindowSublabel` now uses `viewModel.activeWindow.label.lowercased()`, matching the pinned JSX’s `TIME_WINDOWS.label.toLowerCase()` contract (and still uppercased on-screen via `.textCase(.uppercase)`).

## Regression check (no new findings from the fixes)

- The new constants are *more* traceable to the design bundle than before (both changes remove a user-visible divergence rather than introduce one).
- `sheetTitleMatchesTheDesign` was updated to assert `"Reading"`, consistent with the new pinned constant.
- `activeWindowSublabel`’s new behavior is narrow and deterministic (purely derived from `ReadingStatsWindow.label`), and does not change any async flow, VM wiring, or testing seams.

## Tests (composition)

- Attempted to run `xcodebuild test` locally for `vreaderTests/ReadingDashboardViewTests`, but the sandbox environment cannot execute the suite end-to-end:
  - iOS Simulator destination unavailable (no simulator runtimes/devices present).
  - macOS destination build failed due to code signing requiring a Development Team for targets `vreader`, `vreaderTests`, and `vreaderUITests`.
- Static check: the updated assertions in `ReadingDashboardViewTests.swift` align with the updated constants in `ReadingDashboardView.swift`, so there is no internal mismatch introduced by the fixes.
