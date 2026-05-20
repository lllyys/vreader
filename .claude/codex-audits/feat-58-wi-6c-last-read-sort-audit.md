---
branch: feat/58-wi-6c-last-read-sort
threadId: 019e4556-a252-78e2-b25a-328e147d8b0f
rounds: 3
final_verdict: ship-as-is
date: 2026-05-20
---

# Codex Gate-4 audit — feature #58 WI-6c

WI-6c adds the 5th sortable `Last read` column to `StatsPerBookTable`, unblocked by PR #1060's `stats-followups-artboards.jsx` design bundle (GH #1059 D3-B resolution). Implementation chose the Alt-1 always-5-columns design variant over the canonical sort-menu variant because the existing 4 columns already use header-tap sorting; introducing a separate sort-menu surface would have been a larger redesign than D3-B's scope.

## Round 1 — `a535a61`

**Findings**: 1 Medium, 1 Low.

- **Medium** — Cell formatter mismatch: the `Read` cell reused `ReadingTimeFormatter.formatRelativeLastRead`, which returns verbose Library-row strings ("Just now", "Yesterday", "12m ago", "11mo ago"). That formatter is built for Library metadata, not the 52pt compact column. The Alt-1 design warns the column is borderline at 402pt and breaks below 360pt; its `ROWS_WITH_LASTREAD` sample uses tokens like "2h", "1d", "3d", "5w". Cell also lacked `.lineLimit(1)`.
- **Low** — `ReadingStatsModels.swift` is now 320 lines (was 298; convention <300). Codex assessment: "I would not block this PR on a split. The delta is small and localized, and splitting during parallel WI work on the same surface would add merge churn for little gain." Accepted as-is.

**Fix commit `1a0bbb0`** (`fix(#58 WI-6c): compact Last-read cell tokens (Codex Gate-4 round-1)`):
- Added `StatsPerBookTable.lastReadCellText(for:relativeTo:)` as a dashboard-specific compact-token formatter (`0m`/`Xm`/`Xh`/`Xd`/`Xw`/`Xmo`/`Xy`/`—`). Bucket boundaries match the Library formatter so the two surfaces stay in sync; only the rendering is shortened.
- Added `.lineLimit(1)` to the cell.
- Added 3 new tests (`lastReadCellNilRendersAsEmptyMarker`, `lastReadCellEmitsCompactTokens` with 14 boundary cases, `lastReadCellHandlesFutureDateAsZero`, `lastReadCellNeverEmitsLibraryVerboseStrings` as regression guard).

## Round 2 — `dd38ac9`

**Findings**: 1 Medium.

- **Medium** — Year-boundary regression in the round-1 fix: the new formatter computed `months = days / 30` then gated the year branch on `months >= 12`. For 360..364-day dates, `days / 30 == 12` (≥ 12) so the year branch fired, but `days / 365 == 0`, producing the spurious "0y" token. The contract says <1y returns months ("Xmo") and ≥1y returns years ("Xy"). The round-1 tests jumped from `60d` straight to `365d`, missing the 360..364d range.

Codex also noted the analogous bug exists in the shared `ReadingTimeFormatter.formatRelativeLastRead` (Library list rows) but is outside this PR's scope.

**Fix commit `d54c38d`** (`fix(#58 WI-6c): year-boundary off-by-one in Last-read cell formatter`):
- Gated the year branch on the raw day count (`days < 365`) instead of the month proxy. 360..364d now correctly returns "12mo"; ≥365d returns "1y".
- Added 3 boundary cases to `lastReadCellEmitsCompactTokens` (`359d → 11mo`, `360d → 12mo`, `364d → 12mo`) plus the existing `365d → 1y`.

## Round 3 — `7c6657f`

**Findings**: 0 Critical / 0 High / 0 Medium / 0 Low.

Codex verdict: "PASS. The round-2 Medium is resolved. `StatsPerBookTable.lastReadCellText` now keys the year transition off raw `days < 365`, so the previous `360...364d -> 0y` bug is gone. The added regression cases correctly pin `359d → 11mo`, `360d → 12mo`, `364d → 12mo`, `365d → 1y`. I do not see any new regressions in the WI-6c diff. Comparator behavior remains correct, the compact-token formatter now matches the chosen Alt-1 table constraint, and the targeted test coverage closes the previously missing boundary range."

## Verdict

**Gate 4 PASSED at round 3.** Three rounds within rule-47's max of 3. Zero open findings at any severity. Ready to merge once Gate 5 verification (slice verification, since WI-6c is a behavioral UI change) lands in the PR body.
