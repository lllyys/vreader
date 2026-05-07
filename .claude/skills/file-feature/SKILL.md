---
name: file-feature
description: "Create a GitHub issue for a feature row in docs/features.md and stamp `GH: #N` into its Notes column. Use this skill whenever the user wants to file/mirror/create a GH issue for an existing feature row, or asks 'create issue for feature #N', 'file feature 47', 'mirror feature 32 to GH', 'this feature needs a GH issue'. Also trigger when the `check_gh_issue_mirror.sh` PreToolUse hook blocks an edit to a `docs/features.md` row because it lacks `GH: #N`. Skip if status is `TODO` (promote to `PLANNED` first) or Notes contains `Mirror: no`."
---

# File Feature Issue

Create a GitHub issue mirroring an existing row in `docs/features.md`, then update that row's Notes column with `GH: #N`. Mirror of `/file-bug` for the features tracker.

## Input

Parse the user's request to extract a single integer feature ID (e.g. from `/file-feature 47`, `file feature #47`, or `mirror feature 47 to GH`). If the user did not name an ID, ask before proceeding.

## Phase 0 — Pre-flight

1. **Argument check**: parse `$ARGUMENTS` as a single integer feature ID. Empty / non-numeric → print usage `/file-feature <id>` and STOP.

2. **`gh` auth check**: `gh auth status`. If unauthenticated → print and STOP.

3. **Repo check**: `gh repo view --json nameWithOwner -q .nameWithOwner`. If errors → print and STOP.

4. **Row lookup**: `grep -n "^| <id>[ |]" docs/features.md | head -1`. If empty → STOP.

5. **Mirror-required state check**: status must be one of `PLANNED`, `IN PROGRESS`, `DONE`, `VERIFIED`. If `TODO` (not yet planned), print `Feature #<id> is at TODO — promote to PLANNED first per AGENTS.md` and STOP.

6. **Mirror: no escape**: if the Notes column contains `Mirror: no`, print `Feature #<id> is marked Mirror: no — skipping per row directive.` and STOP cleanly.

7. **Existing-issue check**: if Notes already has `GH: #N`, print and STOP cleanly (idempotent).

## Phase 1 — Build the issue

From the row, extract `title` (cell 2), `area` (cell 3), `priority` (cell 4), `status` (cell 5), `notes` (cell 6).

Compose:
- **Issue title**: `Feature #<id>: <title>`
- **Labels**: `enhancement`. If priority is `High` add `severity:high`. `Medium` → `severity:medium`. `Low` → no severity.
- **Body** (heredoc):

```
**Tracker row**: `docs/features.md` #<id>
**Source of truth**: docs/features.md
**Priority**: <priority>
**Status**: <status>
**Area**: <area>

## Description

<notes>

---

This issue mirrors the feature-tracker row. The row is the source of truth — material design / scope changes happen in `docs/features.md`; GH comments that change scope must be ported back to the tracker in the same PR.

If a Plan exists in `dev-docs/plans/` it is referenced from the row.
```

## Phase 2 — Create the issue

```sh
gh issue create --title "<title>" --label "<labels>" --body "<body>"
```

Capture URL + extract issue number. Same failure-mode handling as `/file-bug` (network retry once, rate-limit/label-missing/duplicate handling). On any partial-success (issue created but downstream fails), exit nonzero with the URL printed so the user can finish manually.

## Phase 3 — Update the row

Use the `Edit` tool to insert `GH: #<issue-number>` into the row's Notes column. Markdown table rows end with `|`, so the insertion always goes **before the trailing `|`**, separated from prior content by exactly one space.

The Edit's `old_string` is the original full row line. The `new_string` is the same line with `GH: #<N>` inserted into the Notes cell.

Two surface patterns (both yield the same outcome — the only difference is what whitespace already exists before the trailing `|`):

a. **Notes ends with non-space content** (typical): `... existing notes |` → `... existing notes GH: #<N> |` (one leading space before `GH:`).
b. **Notes already has trailing whitespace before the `|`**: `... existing notes   |` → `... existing notes GH: #<N> |` (collapse the run of trailing spaces to one).

Never put `GH: #<N>` after the trailing `|` — that puts it outside the table cell and the mirror hook won't see it.

The `check_gh_issue_mirror.sh` PreToolUse hook will allow this edit because the new content carries `GH: #N`.

**Failure mode — issue created but row update failed**:
This is the dangerous case. Print:
```
GH issue #<N> created at <URL>, but failed to update docs/features.md row.
Manually add `GH: #<N>` to the Notes column of feature #<id>:

  | <id> | ... | <status> | <existing notes> GH: #<N> |
```
Exit nonzero so the user sees the partial success.

## Phase 4 — Report

```
Filed feature #<id> as GH issue #<N>: <URL>
```

Done. Do NOT commit — the user folds the row edit into whatever PR is in flight.

## Examples

`/file-feature 47` → reads row #47, opens GH issue with `enhancement` + severity labels, stamps `GH: #N` onto the row.

`/file-feature 50` (status TODO) → "promote to PLANNED first" message and stops.

`/file-feature 51 Mirror: no` → not how arguments work; the `Mirror: no` directive lives in the row's Notes column and the command auto-detects it.
