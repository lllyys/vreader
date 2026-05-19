---
branch: feat/feature-64-wi-2-form-presenter
threadId: 019e405e-0806-7ca0-b765-532c533c307d
rounds: 2
final_verdict: ship-as-is
date: 2026-05-19
---

# Gate-4 Implementation Audit — Feature #64 WI-2 (pure form-decision presenter)

## Scope

WI-2 of the unified cross-format highlight-action popover. One new production file:

- `vreader/Views/Reader/HighlightPopoverPresenter.swift` (NEW) — a stateless enum: `content(for:sourceRect:chapter:)` (the canonical `HighlightRecord` → `HighlightPopoverContent` mapping), `form(...)` (the pure anchored-card-vs-bottom-sheet decision), `resolvedForm(...)` (folds in host-`UIView` availability). `cardMaxNoteLines = 6`.

Plus `HighlightPopoverPresenterTests.swift` (NEW, 14 tests incl. a parity fence) and the `HighlightPopoverViewModel.swift` refactor (WI-1's temporary static `content(...)` mapping deleted; the view model now delegates to `HighlightPopoverPresenter.content(...)`; the unused `import CoreGraphics` removed).

## Round 1 — Codex `019e405e-0806-7ca0-b765-532c533c307d`

Two project-file findings, both **caused by branch staleness** (the WI-2 branch was created off an older `origin/main`; a sibling agent merged PR #968 in between, and `xcodegen generate` ran against a stale `project.yml`):

| # | File:line | Severity | Issue | Fix |
|---|-----------|----------|-------|-----|
| F1 | `project.pbxproj:1468` | **High** | The regen dropped the unrelated `TXTChunkedSearchHighlightClearTests.swift` file/build-phase entries that exist on `origin/main` — silently removing an existing regression suite from the test target. | Rebase onto current `origin/main`, re-regenerate. |
| F2 | `project.pbxproj:5421` | Medium | The project file regressed the app version from `3.36.8 (523)` on `origin/main` to `3.36.7 (522)`. | Restore the `origin/main` version values; do the WI-2 bump as the dedicated tail commit. |

The Swift WI-2 delta was confirmed **clean** in round 1: `HighlightPopoverPresenter` delivers the pure presenter promised in plan §3.2; the form table is correct (VoiceOver / `noteLineCount > 6` / `.zero` rect ⇒ sheet; exactly 6 stays card; no-host degrades only in `resolvedForm`); the view-model refactor introduces no new concurrency hazard; no residual dead code from the removed WI-1 mapping helper; the parity fence is meaningful (covers the behavioral partitions of the inherited `resolvedForm` table).

## Resolution

Rebased the WI-2 branch onto current `origin/main` (HEAD `e2960bb`), then re-ran `xcodegen generate` from the worktree root against the up-to-date `project.yml`. Verified:

- `TXTChunkedSearchHighlightClear` references restored (`grep -c` → 4).
- Version in pbxproj is `3.36.8` / `523` (matches `origin/main` — no rollback). The dedicated WI-2 patch bump (`3.36.8` → `3.36.9`) is the tail commit per rule 40.
- `HighlightPopoverPresenter` correctly registered (`grep -c` → 8: presenter + test).
- WI-2 test gate re-ran post-rebase: 36 tests pass.

## Round 2 — Codex `019e405e-0806-7ca0-b765-532c533c307d` (re-audit of the fix)

Verdict: **"The two project-file findings are resolved."** Codex re-checked the branch at `e2960bb` against `origin/main`: `project.pbxproj` contains the restored `TXTChunkedSearchHighlightClearTests` entries, keeps `MARKETING_VERSION = 3.36.8` / `CURRENT_PROJECT_VERSION = 523`, and the remaining delta is limited to registering the new presenter + its test. **No remaining open Critical/High/Medium findings.**

## Verdict

**ship-as-is** — 2 rounds (round 1 caught a branch-staleness pbxproj regression, fixed by rebase + re-regen; round 2 clean).
