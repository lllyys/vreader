---
description: Create a GH issue for a feature row in docs/features.md and stamp `GH: #N` into its Notes column
argument-hint: "<feature-id>"
---

# File Feature Issue

Create a GitHub issue mirroring an existing row in `docs/features.md`, then update that row's Notes column with `GH: #N`. Mirror of `/file-bug` for the features tracker.

## Input

```text
$ARGUMENTS
```

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

Use the `Edit` tool to add `GH: #<issue-number>` to the Notes column. The `check_gh_issue_mirror.sh` PreToolUse hook will allow this edit because the new content carries `GH: #N`.

**Failure mode — issue created, row update failed**:
Print the URL + the exact row line the user needs to write, exit nonzero.

## Phase 4 — Report

```
Filed feature #<id> as GH issue #<N>: <URL>
```

Done. Do NOT commit — the user folds the row edit into whatever PR is in flight.

## Examples

`/file-feature 47` → reads row #47, opens GH issue with `enhancement` + severity labels, stamps `GH: #N` onto the row.

`/file-feature 50` (status TODO) → "promote to PLANNED first" message and stops.

`/file-feature 51 Mirror: no` → not how arguments work; the `Mirror: no` directive lives in the row's Notes column and the command auto-detects it.
