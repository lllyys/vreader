# Verification Evidence Schema

Every transition of a `docs/features.md` row to `VERIFIED` requires
a paired evidence file in this directory. The file's frontmatter is
machine-checked by `.claude/hooks/check_terminal_status_evidence.sh`
(PreToolUse) so the tracker edit physically cannot land without it.

**Bug `FIXED` flips are NOT enforced by the hook.** Per AGENTS.md,
`FIXED` is the merge gate (code shipped to main with passing tests
= enough). The on-device verification before closing the GH issue
is checked at the issue-close step, not at the bug-row flip.

## Filename

`feature-<id>-<YYYYMMDD>.md` for features. `bug-<id>-<YYYYMMDD>.md`
for bugs. Multiple verification runs against the same id are
distinguished by date suffix; the hook reads the **most recent**.

## Required frontmatter

```yaml
---
kind: feature | bug
id: 47
status_target: VERIFIED | FIXED
commit_sha: <40-hex of HEAD when verification ran>
app_version: <MARKETING_VERSION (build CURRENT_PROJECT_VERSION)>
date: 2026-05-04
verifier: <name or "claude">
device_or_simulator: <e.g. "iPhone 17 Pro Simulator">
os_version: <e.g. "iOS 26.3">
build_configuration: Debug | Release
backend: <e.g. "rclone WebDAV ~/vreader-webdav-data" or "n/a">
result: pass | partial | fail
---
```

## Required body sections

The hook does not parse the body, but the workflow rule
(`.claude/rules/47-feature-workflow.md` Gate 5) requires these
sections to exist in the markdown:

1. `## Acceptance criteria` — table mapping each criterion from the
   feature/bug plan to **observed** behavior + a pass/fail column.
   Every criterion in the plan must appear; "deferred" or "blocked"
   counts as fail unless the row explains why and the
   `result` field is `partial`.
2. `## Commands run` — fenced code blocks of the actual shell /
   simctl / curl / xcrun commands the verifier executed. Reproducible
   recipe — anyone should be able to re-run.
3. `## Observations` — free-form narrative. What surprised you? What
   was almost a regression? What's brittle for next time?
4. `## Artifacts` — paths to screenshots, log captures, or
   `.xcresult` bundles produced during the run. Optional but
   strongly recommended.

## Result semantics

- `pass` — every acceptance criterion verified end-to-end. Tracker
  status may move to `VERIFIED` (feature) / `FIXED` (bug) and the
  GH issue may be closed.
- `partial` — some criteria pass, some are explicitly deferred with
  a follow-up row in the tracker. Tracker status may NOT move to
  `VERIFIED`; it stays at `DONE awaiting partial-VERIFIED` and a
  follow-up evidence file is required.
- `fail` — at least one criterion regressed. Tracker status moves
  back to `IN PROGRESS` (feature) or `REOPENED` (bug). Do not flip
  to `VERIFIED`/`FIXED`.

## What counts as evidence?

- Real device / real simulator runs (preferred).
- Live integration tests against the actual backend (rclone WebDAV
  is the current local default — see
  `dev-docs/integration-tests/feature-47-webdav-rclone.md`).
- Unit + protocol tests alone are NOT verification — they cover the
  audit gate (Gate 4), not the integration gate (Gate 5). A purely
  unit-test-backed evidence file with `result: pass` will be flagged
  by the hook (commit_sha + commands_run sanity check).

## Examples

- `feature-46-20260503.md` — first evidence file in this directory.
  curl-driven verification against rclone because xcodebuild env-var
  propagation was unreliable. `result: pass` covering all 6
  acceptance criteria.

## When the hook blocks

If you try to `Edit`/`Write` a tracker row to `VERIFIED`/`FIXED`
without a matching evidence file, the hook prints the missing path
and exits non-zero. Two ways to proceed:

1. Run the verification, write the evidence file, retry the edit.
2. (Escape hatch — use sparingly) prefix the next prompt with
   `verify-skip:<id>:<reason>` and the hook will allow the edit but
   require a `partial` evidence file with the reason recorded
   within 7 days.
