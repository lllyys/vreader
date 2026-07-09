---
branch: fix/issue-1891-pipe-split-hooks
threadId: 019f449e-31f4-7ac2-8bb6-8c6e59720c4c
rounds: 1
final_verdict: follow-up-recommended
date: 2026-07-09
---

# Codex Audit Log — Bug #361 (GH #1891)

Fix: `check_unfinished_verification.sh` and `check_gh_issue_mirror.sh` split
tracker rows on every `|` including backslash-escaped `\|`, shifting all
subsequent cell indices (Status read from the Sev/Prio cell, Notes from the
Status cell). Fix masks `\|` with `\x01` before splitting and restores after
— the `scripts/deps-check.sh` pattern (sed pre-pass for the awk lane,
`str.replace` for the python lanes). Secondary runtime fix: the mirror hook's
block message used `${KIND^}` (bash 4+), a fatal "bad substitution" under the
`/bin/bash` 3.2 shebang runtime that turned every exit-2 block into a
non-blocking exit 1; replaced with a case-based title.

## Scope of audit

`git diff main...HEAD`: both hooks plus two new regression suites
(`.claude/hooks/__tests__/check_unfinished_verification.test.sh`,
`.claude/hooks/__tests__/check_gh_issue_mirror.test.sh`). Audit prompt
covered escaping correctness (`\\|`, pipe at cell start/end, multiple `\|`
per cell, pre-existing `\x01`), exit-code contract preservation (Stop hook
always 0; mirror hook 0/2), bash-3.2 pitfalls, and test quality (RED cases
pinning the pre-fix misparse; positive/negative controls). Codex read the
full hook files + both suites and ran `git diff --check` and `/bin/bash -n`
on all four files (read-only sandbox — suites were run by the lane, both
`ALL PASS`).

## Round 1 findings (1)

| File:line | Severity | Issue | Resolution |
| --- | --- | --- | --- |
| `check_gh_issue_mirror.sh:135`, `check_unfinished_verification.sh:118` | Low | Sentinel not bijective: a tracker row already containing a literal `\x01` control byte is restored as `\|`; in the mirror hook, OLD/NEW comparisons could collapse a real `\x01` and an escaped pipe to the same parsed value. No literal `\x01` exists anywhere in the repo. | **Accepted with rationale.** The mask/restore shape is the repo-standard escaped-pipe pattern from `scripts/deps-check.sh` (which shares the identical limitation) and is exactly what the bug's fix spec mandated. A literal control-A byte in a hand-edited markdown tracker table is pathological, not a realistic input; making the sentinel bijective would require a two-char escape scheme replicated portably across the sed/awk lane and both python lanes, diverging the three scripts for a case with no occurrence in the repo. If a control byte ever lands in a tracker, the failure mode is a mis-restored cell in an advisory hook message or one spurious block — not data corruption. |

Codex otherwise confirmed: escaped-pipe handling correct for `\\|`, escaped
pipe at cell start/end, and multiple `\|` per cell; both RED directions
genuinely pinned (false block when a GH ref shifts out of Notes; false allow
when Status shifts into the priority/severity cell); positive/negative
controls present; the `${KIND^}` bash-3.2 regression directly covered.

## Verdict

`follow-up-recommended` — zero Critical/High/Medium; the single Low is
accepted with the rationale above (Gate-4 acceptance bar met). Full
transcript: lane-local `.reports/audit-r1.txt` (not committed).
