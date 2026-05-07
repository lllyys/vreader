---
description: "Create a GH issue for a bug row in docs/bugs.md and stamp `GH: #N` into its Notes column"
argument-hint: "<bug-id>"
---

# File Bug Issue

Create a GitHub issue mirroring an existing row in `docs/bugs.md`, then update that row's Notes column with `GH: #N` so the PreToolUse mirror hook stops blocking edits to it. Single tool flow that prevents the "issue created, row not updated" failure mode.

## Input

```text
$ARGUMENTS
```

## Phase 0 — Pre-flight

1. **Argument check**: parse `$ARGUMENTS` as a single integer bug ID.
   - Empty / non-numeric → print usage:
     `/file-bug <bug-id>  e.g. /file-bug 115`
     and STOP.

2. **`gh` auth check**: run `gh auth status` (any remote). If unauthenticated → print
   `gh CLI is not authenticated. Run \`gh auth login\` first.` and STOP.

3. **Repo check**: run `gh repo view --json nameWithOwner -q .nameWithOwner` from inside the project. If it errors → print `Not inside a GitHub repo (no upstream remote). gh repo set-default may help.` and STOP.

4. **Row lookup**: `grep -n "^| <id>[ |]" docs/bugs.md | head -1`. If empty → print `Bug #<id> not found in docs/bugs.md` and STOP.

5. **Existing-issue check**: read the matching row's Notes column. If it already contains `GH: #N`, print `Bug #<id> already has GH: #N — nothing to do.` and STOP cleanly (idempotent).

## Phase 1 — Build the issue

From the row, extract:
- `title` (cell 2)
- `area` (cell 3)
- `priority` (cell 4)
- `status` (cell 5)
- `notes` (cell 6)

Compose:
- **Issue title**: `Bug #<id>: <title>`
- **Labels**: `bug`. If priority is `High` add `severity:high`. If `Medium`, `severity:medium`. (If `Low`, no severity label.)
- **Body** (heredoc):

```
**Tracker row**: `docs/bugs.md` #<id>
**Source of truth**: docs/bugs.md
**Severity**: <priority>
**Status**: <status>
**Area**: <area>

## Description

<notes>

---

This issue mirrors the bug-tracker row. Material design / scope changes happen in `docs/bugs.md`; GH comments that change scope must be ported back to the tracker in the same PR.
```

## Phase 2 — Create the issue

Run:
```sh
gh issue create --title "<title>" --label "<labels>" --body "<body>"
```

Capture the issue URL from stdout. Extract the issue number (last path segment of the URL).

**Failure modes** (all exit nonzero with the issue URL if it exists):
- Network failure → re-run once after 3s; if still failing, print URL (if any) + error and STOP.
- Rate limit → print `gh API rate-limited. Try again later.` and STOP.
- Label not found → re-run with just `bug` label, warn the user that severity wasn't applied.
- Duplicate issue (gh detected) → use the existing one, fall through to Phase 3.

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
GH issue #<N> created at <URL>, but failed to update docs/bugs.md row.
Manually add `GH: #<N>` to the Notes column of bug #<id>:

  | <id> | ... | <status> | <existing notes> GH: #<N> |
```
Exit nonzero so the user sees the partial success.

## Phase 4 — Report

Print:
```
Filed bug #<id> as GH issue #<N>: <URL>
```

Done. Do NOT commit — the docs/bugs.md edit is staged but uncommitted; the user folds it into whatever PR is in flight.

## Examples

`/file-bug 115` → reads row #115 from docs/bugs.md, opens GH issue with bug + severity:high labels, stamps GH: #N onto the row.

`/file-bug` → prints usage and stops.

`/file-bug 999` (nonexistent) → prints "Bug #999 not found" and stops.
