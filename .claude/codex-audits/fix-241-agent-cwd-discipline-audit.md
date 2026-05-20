---
branch: fix/241-agent-cwd-discipline
gh_issue: 1050
bug_id: 241
verdict: ship-as-is
audit_rounds: 1
auditor: codex-mcp
audit_thread: 019e44a5-2427-7a73-b18a-39fbb212cf3e
date: 2026-05-20
---

# Gate-4 audit — bug #241 / GH #1050 (agent cwd discipline)

## Scope

Docs/rules-only change. No Swift code, no tests. Fix direction chosen: (2) brief-template codification.

Files audited:
- `.claude/rules/48-parallel-execution.md` (new "Worktree cwd discipline" subsection)
- `AGENTS.md` (parallel-execution bullet — one-line pointer to the new subsection)
- `docs/bugs.md` (row #241 — TODO → FIXED with fix description)
- `archive/bugs-history.md` (Bug #241 history entry)
- `project.yml` + `vreader.xcodeproj/project.pbxproj` (version bump 3.38.7 → 3.38.8, build 582 → 583)

## Audit dimensions (Gate-4 docs-flavored)

1. Clarity — does the rule explain WHY the preamble matters?
2. Completeness — every Bash call, pwd confirmation, consequence stated?
3. Cross-references — precedent citations consistent across rule + AGENTS.md + bug row + history?
4. Tone / discipline — preamble template binding (not advisory)?
5. Scope creep — does the change stay within direction (2), or drift into (1) harness fix / (3) runtime hook?

## Codex verdict

`ship-as-is` — no Critical/High/Medium findings. Zero Low findings.

## Codex summary

> The rule addition is clear and appropriately binding. In `.claude/rules/48-parallel-execution.md` line 82, the failure mode is explicit, the consequence is concrete, and the mandate/checklist/template cover the required cases: exact worktree path, `cd` at the start of every `Bash` call, `pwd` confirmation before first write, and no small-task exemption. The tone matches rule 48's existing style: operational, prescriptive, and consequence-driven rather than advisory.
>
> Cross-references are consistent enough for this scope. `AGENTS.md` line 39 points orchestrators to the new subsection and preserves the binding language; `docs/bugs.md` line 638 and `archive/bugs-history.md` line 377 both align with the same precedent chain and fix direction. It stays within direction (2) brief-template codification and explicitly keeps harness/runtime-hook options as out-of-scope follow-ups rather than drifting into them.

## Decision

Merge gate cleared. No follow-up required.
