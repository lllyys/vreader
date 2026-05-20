# GitHub issue review

_Started 2026-05-20 11:21 UTC_

---

## User

https://github.com/lllyys/vreader/issues/1059 https://github.com/lllyys/vreader/issues/1058

## Assistant

_[tool: list_files]_

_[tool: web_fetch]_

_[tool: web_fetch]_

_[tool: read_file]_

_[tool: read_file]_

_[tool: read_file]_

_[tool: read_file]_

_[tool: read_file]_

_[tool: grep]_

_[tool: web_fetch]_

_[tool: web_fetch]_

_[tool: grep]_

_[tool: read_file]_

_[tool: read_file]_

_[tool: update_todos]_

I've got it. Two issues, both follow-ups to the Reading-Stats dashboard in `vreader-profile-stats.jsx`:

- **#1058** — Custom date-range picker (what happens when you tap the `Custom` pill)
- **#1059** — `last-read` as a 5th sortable column in `SortablePerBookTable`

Both files declare the existing design but leave a load-bearing surface undrawn. I'll add a canvas that explores both, canonical + variants + edge states, matching the paper/Source-Serif vocabulary of the existing artboards.

Plan for the design system (so I commit and don't drift):
- **#1058 canonical** — mini month-grid sheet anchored from the `Custom` pill (popover on tap), with quick-preset rail (Last 7d / This month / Last month / This year / All time before the launch date). States: empty, picking-start, picking-end, applied-with-pill-update, error (start>end / future), no-results-in-range.
- **#1059 canonical** — keep 4 visible columns; expose `Last read` via the *sort menu* and show the value contextually under the book title when it's the active sort (the time-bar gets swapped for "Last read · 3d ago"). Variants: always-on 5th column with compact ("3d"), horizontal scroll with sticky Book, and a column-chooser swap.

_[tool: read_file]_

_[tool: grep]_

_[tool: write_file]_

Now I have everything. Writing the artboards file.

_[tool: write_file]_

_[tool: done]_

_[tool: update_todos]_

_[tool: fork_verifier_agent]_

Designed both follow-ups in one canvas, **`VReader Stats Followups Canvas.html`**.

**#1058 — Custom range picker** (canonical: paper sub-sheet over the dashboard)
- States: empty, picking-end (with range preview), range chosen, applied, error (start > end), no sessions in range, dark.
- Quick-preset rail (Last 7 / 14 / This month / Last month / This year / All time) on top of the month grid so single-tap cases stay 1-tap.
- Read-density dots under dates so the user sees where they actually read before committing.
- Custom pill updates to `Custom · May 1 – May 15` after apply.
- Popover variant kept as alt (works for ≤1-month ranges).

**#1059 — Last-read 5th column** (canonical: sort-menu addition, not always-visible)
- `Last read` joins the Sort menu (with a NEW badge); when active, the per-row time-bar swaps for `Last read · 3d ago` so the iPhone-narrow 4-column layout stays intact.
- Nil rows sort to the bottom and render as "No sessions recorded".
- Two compare variants: always-5 compact columns, and a per-slot column chooser popover.

Post-it notes inside each section explain the canonical-choice reasoning.

