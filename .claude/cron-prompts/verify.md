First, log the fire: run `mkdir -p .claude/cron-logs && echo "$(date -Iseconds) verify FIRED" >> .claude/cron-logs/verify.log`. Then perform the task below. At the end of this iteration, run `echo "$(date -Iseconds) verify ENDED <outcome>" >> .claude/cron-logs/verify.log` where <outcome> is one of: work_done | no_work_in_scope | blocked | error.

/loop pick up a feature from @/Users/ll/workspace/vreader/docs/features.md @/Users/ll/workspace/vreader/README.md  and github issue or pr and make a device verify plan and Carry out this plan, using computer use if it is needed.

SCOPE: verification only. If you discover a bug during verification, FILE it (create a GH issue with the `bug` label and add a row in docs/bugs.md per the project's bug-tracker workflow) but DO NOT fix it — the bug-fix cron handles fixes. Stay strictly in verification scope this iteration.
