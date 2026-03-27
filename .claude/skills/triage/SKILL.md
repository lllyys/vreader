---
name: triage
description: "Classify and route incoming issues to the correct tracker (bugs vs features). Use this skill whenever the user reports a problem, describes unexpected behavior, asks you to triage, process the inbox, check tasks, or pastes an error/crash log. Also trigger when the user says things like 'this is broken', 'I found a bug', 'X doesn't work', 'add support for Y', or describes any issue that needs classification. Even casual complaints like 'the reader crashes when I open big files' should trigger this skill."
---

# Issue Triage

Classify incoming issues and route them to the correct tracker. This is classification only — you do NOT fix bugs or implement features during triage.

## When This Runs

- User says "triage", "check tasks", "process inbox", "check the inbox"
- User reports a problem: "X doesn't work", "I found a bug", "this crashes"
- User pastes an error log, crash trace, or screenshot description
- User requests a feature: "can you add X", "it would be nice if Y"
- User writes items in the project's task inbox file

## How It Works

### Step 1: Find the project's tracker files

Look for these files (or similar) in the project:

| File                | Purpose                        | Common paths                           |
| ------------------- | ------------------------------ | -------------------------------------- |
| **Inbox**           | Where new issues land          | `docs/tasks.md`, `tasks.md`, `TODO.md` |
| **Bug tracker**     | Broken implementations         | `docs/bugs.md`, `bugs.md`, `BUGS.md`   |
| **Feature tracker** | Never-implemented capabilities | `docs/features.md`, `features.md`      |

If these files don't exist, ask the user where issues should go. If the project has no tracker files at all, offer to create them with a minimal template.

### Step 2: Gather the issue

The issue comes from one of two sources:

**A) Inbox file** — read the "New" section for unprocessed items.
**B) Conversation** — the user described the issue directly. Capture it.

For each issue, you need:

- **What the user described** (symptoms, not diagnosis)
- **What area of the code it touches** (investigate if unclear)

### Step 3: Investigate

Before classifying, actually look at the code:

1. Search the codebase for the relevant area (files, functions, components)
2. Determine: was this feature ever implemented? Does the code exist but behave incorrectly?
3. Search existing bug and feature trackers for duplicates

This investigation is what separates good triage from guessing. A "broken search" report could be a bug (search exists but returns wrong results) or a feature (search was never built). You can't tell without looking.

### Step 4: Classify

| Classification        | When                                          | Action                                  |
| --------------------- | --------------------------------------------- | --------------------------------------- |
| **Bug**               | Implemented but broken                        | Record in bug tracker                   |
| **Feature**           | Never implemented                             | Record in feature tracker               |
| **Duplicate (open)**  | Matches an existing open bug/feature          | Reference existing ID, don't create new |
| **Duplicate (fixed)** | Matches a fixed bug — it's a regression       | Reopen the existing bug                 |
| **Needs-info**        | Can't classify without more context           | Ask the user                            |
| **No-action**         | Not a bug or feature (docs, config, question) | Note the reason                         |

**The critical distinction**: something that was built but doesn't work is a **bug**. Something that was never built is a **feature**. Partially implemented = bug for the broken part + feature for the missing part (link them).

### Step 5: Record

**For a new bug:**

1. Assign the next available ID in the bug tracker
2. Add a summary row to the tracker table
3. Add an entry to the "Open Bug Details" section with:
   - Repro steps (how to trigger it)
   - Expected behavior
   - Actual behavior
   - (Optional) Root cause if obvious from investigation

**For a new feature:**

1. Assign the next available ID in the feature tracker
2. Add a summary row

**For a duplicate:**

- Don't create a new ID
- Reference the existing one

**For a regression (reopened bug):**

- Set the existing bug's status to REOPENED
- Update its detail entry with the new context

### Step 6: Update the inbox

If the issue came from an inbox file:

1. Move the description from "New" to "Triaged"

2. Add a one-line triage record:

   ```
   YYYY-MM-DD | bug #N | brief description
   ```

3. For no-action or needs-info items, prefix with `> ` (blockquote) so they stand out

### Step 7: GitHub issues (high severity only)

Create a GitHub issue for every new bug and feature. Use `gh issue create`.

When creating:

- **Bugs**: label `bug` + severity label (`severity:high`, `severity:medium`, or no severity label for low)
- **Features**: label `enhancement`
- Title format: `Bug #N: short description` or `Feature #N: short description`
- Body: include repro steps (bugs) or description (features)
- Add `GH: #NNN` to the tracker's Notes column after creating
- Use `Refs #N` in PRs (not `Fixes #N` — prevents premature auto-close)

Skip GitHub issues only for DUPLICATE, NO-ACTION, and NEEDS-INFO classifications.

## Output Format

After triaging, report to the user:

```
Triaged: [bug #N / feature #N / DUPLICATE OF #N / REOPENED #N / NO-ACTION / NEEDS-INFO]
Area: [file/component affected]
Reason: [one-line explanation of the classification]
```

If multiple items were triaged, show a summary table.

## Examples

**Example 1: Bug report**

```
User: "the reader crashes when I open large AZW3 files"
→ Investigate: AZW3 reader exists (FoliateViewBridge.swift), crash is in scheme handler for >100MB files
→ Classification: Bug (implemented but crashes)
→ Record: bug #106 in docs/bugs.md
→ Report: "Triaged: bug #106 | Area: Foliate/FoliateURLSchemeHandler | Large AZW3 files crash the reader"
```

**Example 2: Feature request**

```
User: "can we add dark mode for the reader?"
→ Investigate: Theme system exists but only has light theme
→ Classification: Feature (never implemented)
→ Record: feature #43 in docs/features.md
→ Report: "Triaged: feature #43 | Area: Reader/Theme | Dark mode for reader not yet implemented"
```

**Example 3: Duplicate**

```
User: "search doesn't work in EPUB"
→ Investigate: search exists, find existing bug #99
→ Classification: Duplicate of bug #99
→ Report: "Triaged: DUPLICATE OF bug #99 | Already tracked"
```

**Example 4: Direct issue (no inbox file)**

```
User: "this button does nothing when I tap it"
→ Ask: "Which button? In which screen?"
→ Classification: NEEDS-INFO
→ Report: "Triaged: NEEDS-INFO | Need to know which button and screen to investigate"
```

## Important Rules

- **Triage is classification, not execution.** Don't fix bugs or implement features during triage. Just classify and record.
- **Never delete user content.** Items in the inbox belong to the user. If something looks like a re-report, it means the previous fix didn't work — reopen the bug.
- **Investigate before classifying.** Read the actual code. Don't guess whether something is a bug or feature based on the description alone.
- **One issue per triage.** If the user reports multiple things in one message, triage each separately.

