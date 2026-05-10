First, log the fire: run `mkdir -p .claude/cron-logs && echo "$(date -Iseconds) feature FIRED" >> .claude/cron-logs/feature.log`. Then perform the task below. At the end of this iteration, run `echo "$(date -Iseconds) feature ENDED <outcome>" >> .claude/cron-logs/feature.log` where <outcome> is one of: work_done | no_work_in_scope | blocked | error.

Select a feature to implement from GitHub issues or local tasks, and use /feature-workflow to implement the feature.

SCOPE: feature implementation only. Per `.claude/rules/47-feature-workflow.md`, `/feature-workflow` is the binding 6-gate sequence (Plan → Independent plan audit → TDD → Implementation audit → Device/integration verification → Merge); never skip a gate. If no feature is at PLANNED status with a ready dev-docs/plans/* document, log `no_work_in_scope` and stop — do not pick a TODO/IDEA-level feature and start drafting a plan inside this iteration; that's planning work, not implementation.
