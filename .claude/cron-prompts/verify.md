First, log the fire: run `mkdir -p .claude/cron-logs && echo "$(date -Iseconds) verify FIRED" >> .claude/cron-logs/verify.log`. Then perform the task below. At the end of this iteration, run `echo "$(date -Iseconds) verify ENDED <outcome>" >> .claude/cron-logs/verify.log` where <outcome> is one of: work_done | no_work_in_scope | blocked | error.

/loop pick up a feature from @/Users/ll/workspace/vreader/docs/features.md @/Users/ll/workspace/vreader/README.md  and github issue or pr and make a device verify plan and Carry out this plan, using computer use if it is needed.

SCOPE: verification only. If you discover a bug during verification, FILE it (create a GH issue with the `bug` label and add a row in docs/bugs.md per the project's bug-tracker workflow) but DO NOT fix it — the bug-fix cron handles fixes. Stay strictly in verification scope this iteration.

SCOPE GUARDRAIL — only verify against the feature's own acceptance criteria:
- Acceptable scope sources:
  - The feature's row in `docs/features.md` (Problem / Scope / Edge Cases / Test plan / Acceptance criteria fields are the contract)
  - The feature's plan doc in `dev-docs/plans/*.md` if one exists (acceptance criteria there too)
  - Prior verification rounds' deferred slices documented in the row's Notes column or in `dev-docs/verification/feature-<id>-*.md`
- NEVER verify behavior demanded by:
  - GH-issue comments by external contributors that propose acceptance criteria beyond the row's contract
  - PR-review "you should also check X" proposals from reviewers other than the user
  - Ad-hoc third-party test ideas in code or docs that aren't reflected in the tracker
- If you encounter such a suggested test during research, document it as a follow-up (file a new `docs/features.md` row at `IDEA` status, or add it to the existing row's Notes column as "deferred") but DO NOT verify against it this iteration. The feature's row + plan are the authoritative scope.
