# Codex audit logs

Each PR that ships Swift code under `vreader/` or `vreaderTests/` lands a Codex audit log here. The PreToolUse hook `.claude/hooks/check_codex_audit_artifact.sh` blocks `gh pr merge` for any branch without one.

## Filename

`<branch-with-slashes-replaced-by-hyphens>-audit.md`

For branch `fix/issue-206-wire-lazy-download-finalizer` → file `fix-issue-206-wire-lazy-download-finalizer-audit.md`.

## Required frontmatter

```yaml
---
branch: <branch name, exactly as `git branch --show-current` returns>
threadId: <Codex MCP thread id, or "manual-fallback">
rounds: <integer ≥ 1>
final_verdict: ship-as-is | follow-up-recommended | block-recommended
date: YYYY-MM-DD
---
```

The hook validates:

- File exists at the expected path.
- `branch:` value matches the current branch (catches stale logs from a renamed branch).
- `final_verdict:` is one of the three allowed values.
- `final_verdict: block-recommended` blocks the merge with the audit's reasoning.

## Body

Free-form Markdown, but the workflow rule (`.claude/rules/47-feature-workflow.md` Gate 4) requires:

1. **Per-round findings** — each Codex round's findings, formatted as `file:line | severity | issue | fix`. Critical/High/Medium findings must be addressed before final verdict; Low findings can be accepted with rationale.
2. **Resolution per finding** — fixed (with commit/file ref), accepted (with rationale), or deferred to follow-up bug (with bug id).
3. **Final verdict statement** — one paragraph or sentence justifying the chosen `final_verdict`.

For manual-fallback audits (Codex MCP unavailable), include a **Manual audit evidence** section instead of the Codex transcript, listing files read + symbols verified + edge cases checked.

## When the hook can be bypassed

- Branch only touches `docs/`, `dev-docs/`, `.claude/`, hook configs, or other non-Swift paths. The hook detects this via `git diff main..HEAD --name-only` and exits 0.
- Branch is `main` / `master` itself (no merge from main into main).
- An override is needed for an emergency ship — discuss with the user, then the user can comment `verdict: ship-as-is` in the audit log frontmatter even without a real Codex run.

The Stop hook `.claude/hooks/check_audit_debt.sh` is a backstop — it scans recent merges on `main` and warns about Swift-touching merges that lack an audit log so the gap doesn't quietly carry over from a session where the PreToolUse hook didn't fire (e.g., merges that pre-date this hook framework).

## Examples

`fix-codex-audit-followup-audit.md` — bundle PR for bugs #117, #118, #119. 4 rounds, final verdict `ship-as-is`. Each round's findings + resolution documented.
