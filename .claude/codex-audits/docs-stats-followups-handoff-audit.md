---
branch: docs/stats-followups-handoff
threadId: manual-fallback
rounds: 1
final_verdict: ship-as-is
date: 2026-05-20
---

## Scope

Syncs the claude.ai/design "VReader Stats Followups Canvas"
handoff (chat8) into the `dev-docs/designs/vreader-fidelity-v1/`
bundle. Touches the design bundle, plus `project.yml` /
`project.pbxproj` (version bump 3.38.11/586 → 3.38.12/587).

**No Swift source files changed.** The audit-gate hook fires on
`project.pbxproj` — false positive of the Swift-file heuristic.
Manual mini-audit.

## Manual audit evidence

### What changed and why

Bundle sync (rsync, superset — nothing deleted): 3 new files —
`VReader Stats Followups Canvas.html`,
`stats-followups-artboards.jsx`, `chats/chat8.md`; `README.md`
updated (chat count 7 → 8, primary-file pointer generalized).

The handoff delivers the committed design for **two**
`needs-design` issues, both off feature **#58** (Reading-time +
activity dashboard, IN PROGRESS, WI-1–5 merged):

- **#1058** — Custom date-range picker for the
  `StatsTimeWindowBar`. Canonical: paper sub-sheet over the
  dashboard with a quick-preset rail (Last 7 / 14 / This month /
  Last month / This year / All time) on top of a month grid.
  Read-density dots under dates so the user sees where they
  actually read before committing. States: empty, picking-start,
  picking-end, applied (Custom pill updates to `Custom · May 1 –
  May 15`), error (start > end / future), no-sessions-in-range,
  dark. Popover alt kept for short (<1 month) ranges.

- **#1059** — `Last read` 5th sortable column for
  `SortablePerBookTable`. Canonical: `Last read` joins the Sort
  menu (NEW badge) rather than becoming an always-visible 5th
  column — keeps the iPhone-narrow 4-column layout intact. When
  active sort, per-row time-bar swaps for `Last read · 3d ago`.
  Nil rows sink to bottom and render "No sessions recorded".
  Compare variants: always-5 compact columns, horizontal scroll
  with sticky Book, per-slot column-chooser popover.

Both surfaces hang off the `FullStatsDashboard` committed in
`vreader-profile-stats.jsx` — the dashboard hero + daily-chart
are NOT redrawn; the new canvas only adds the two affordances.

### Correctness checks

1. **#1058 and #1059 are real, open `needs-design` issues** —
   verified via `gh issue view 1058` and `gh issue view 1059`:
   both OPEN, both labels `enhancement` + `needs-design`. Titles:
   "Design needed: Custom range picker for Feature #58 Stats
   time-window bar" and "Design needed: last-read column for
   Feature #58 SortablePerBookTable".
2. **Issue → feature linkage** — both issues' titles name feature
   #58. Feature #58's row in `docs/features.md` (line 113) carries
   no `BLOCKED: needs-design (#1058)` or `BLOCKED: needs-design
   (#1059)` annotation — the picker + last-read column are
   sub-affordance gaps from #58's plan, not row-level blocks (the
   row is already `IN PROGRESS` with WI-1–5 merged). No
   `docs/features.md` row is flipped here.
3. **Issue closure** — PR uses `Resolves #1058` and `Resolves
   #1059` so both `needs-design` issues auto-close on merge (same
   precedent as PRs #1037 / #1039 / #972 / #956 / #930 / #869 /
   #848: a `needs-design` issue is resolved by the design being
   committed).
4. **No Swift implemented** — design-delivery only. Building the
   picker + last-read column is gated feature-#58 feature-workflow
   work; deliberately not in this PR.
5. **Bundle-diff sanity** — `diff -rq` against the incoming
   handoff matched exactly the 4 expected files (README + 1 chat +
   1 HTML + 1 JSX). No silent overwrites of existing canvases.
   `VReader Prototype.html` (the master integration file pointed
   to by the URL's `?open_file=` param) is byte-identical to the
   already-committed copy, so no churn on the shared scaffold.
6. **Version bump** — 3.38.12 / build 587 (patch — docs /
   design-bundle sync). `xcodegen generate` confirmed both
   `project.yml` and `project.pbxproj` reflect the new pair.
   `xcodebuild build` SUCCEEDED on iPhone 17 Pro Simulator (Debug)
   — confirms the bump didn't desync the Xcode project.

## Verdict

ship-as-is — design-bundle sync + version bump. No Swift logic.
Manual fallback used because there is nothing to send to Codex.
