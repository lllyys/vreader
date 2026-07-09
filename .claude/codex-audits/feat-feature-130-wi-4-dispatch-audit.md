---
branch: feat/feature-130-wi-4-dispatch
threadId: 019f4467-0184-7942-9712-c3548e25368d
rounds: 2
final_verdict: ship-as-is
---

# Gate-4 audit — feature #130 WI-4 (/dispatch orchestrator)

Auditor: cc-suite runner, gpt-5.5, read-only. Round 1 on thread
`019f4467-0184-7942-9712-c3548e25368d` (high effort, full-branch walk against
plan v6 + the shipped primitives); round 2 fresh focused verification on
thread `019f446d-ed70-7e70-b06f-7cbb184f3f01`.

## Round 1 — block-recommended

- **Critical**: the integration tail didn't pin WHERE tracker/docs/version
  edits happen (an executor could commit shared files on main), and one line
  contradicted the plan by describing orchestrator tracker-write commits on
  local main. → Fixed (`39166a28`): 5d/5e mandate Edit on files under
  `<worktree>/` committed via `git -C <worktree>`; bump = the branch's LAST
  commit; pre-PR assertion (`origin/main..HEAD` shows
  fix+artifact+tracker+bump AND contamination probes clean); the
  pull-rebase rationale now cites cron finalizer chore(tracker) commits.
- **High**: contamination check placed AFTER the merge block → dual
  pre-merge call sites (post-HANDOFF + pre-PR) + shared definition; shape
  test asserts line-number ordering vs `gh pr merge`.
- **High**: invalid/missing HANDOFFs leaked lease/worktree → ONE cleanup
  routine for EVERY non-ready outcome (release + teardown-or-preserve +
  ledger + requeue-once/escalate).
- **High**: kill-switch/N=1 inline fallbacks ran unlocked → Step 0
  reordered (lock FIRST); both fallbacks run under the `dispatch` lock.
- **High**: single batch-end tag pass → per-PR tag immediately after each
  merge (rule 40; a batch-end pass corrupts the next slot's latest-tag
  input).
- **Medium**: teardown didn't own branch deletion as claimed →
  `--delete-branch` flag (post-merge only; requeued branches survive; gh's
  `--delete-branch` stays banned) + tests. **Medium**: shape test
  presence-only → +7 invariant anchors incl. an ordering assertion.
- **Low**: lane-order wording inconsistency → canonical order stated once.

## Round 2 — ship-as-is

Findings 1–7 verified resolved with citations; no new Critical/High in the
renumbering/teardown-parsing sweep. Three Lows, all FIXED post-verdict
rather than accepted: implementer.md's frontmatter + numbered steps now
match the canonical order (test gate 4 before audit 5, re-test on
audit-driven changes); the Gate-6-comments wording disambiguated from the
skill's step numbering; teardown flag-permutation tests added
(`--force --delete-branch` both orders).

## Test evidence

`dispatch-shape.test.sh` — 34 static gates ALL PASS (incl. the
contamination-before-merge ordering assertion); `worktree.test.sh` —
13 cases ALL PASS (incl. branch-preserve/delete paths + permutations +
8-way cap race).
