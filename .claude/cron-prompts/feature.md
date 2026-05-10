First, log the fire: run `mkdir -p .claude/cron-logs && echo "$(date -Iseconds) feature FIRED" >> .claude/cron-logs/feature.log`. Then perform the task below. At the end of this iteration, run `echo "$(date -Iseconds) feature ENDED <outcome>" >> .claude/cron-logs/feature.log` where <outcome> is one of: work_done | no_work_in_scope | blocked | error.

Select a feature to implement from GitHub issues or local tasks, and use /feature-workflow to implement the feature.

SCOPE: feature implementation only. Per `.claude/rules/47-feature-workflow.md`, `/feature-workflow` is the binding 6-gate sequence (Plan → Independent plan audit → TDD → Implementation audit → Device/integration verification → Merge); never skip a gate.

PICK ORDER (highest priority first):

1. **`IN PROGRESS` features** with at least one merged WI — resume next pending WI.
2. **`PLANNED` features with a `dev-docs/plans/*-feature-<id>-*.md` doc** — Gate 1 already passed; enter at Gate 2 (if not yet audited) or Gate 3 (if audited and clean).
3. **`PLANNED` features without a dev-docs/plans doc** — row-template definition was filled but full implementation plan was never lifted. Drawing up the plan doc IS this iteration's work (Gate 1 → Gate 2 → first WI of Gate 3 if time allows). Per the user-confirmed framing, "the plan must be drawn up before reaching Gate 1" — that means write it now, do not bail out.
4. **`TODO` features** — only if their row already has Problem/Scope/Edge Cases/Test plan/Acceptance criteria filled in (i.e., they're effectively `PLANNED`-equivalent and the status flip was just missed). Otherwise skip — those need triage first, which is `/triage` work, not feature-workflow work.

If no feature qualifies under categories 1–4, log `no_work_in_scope` and stop. Do NOT invent scope or pick an `IDEA`-level / empty-row entry.
