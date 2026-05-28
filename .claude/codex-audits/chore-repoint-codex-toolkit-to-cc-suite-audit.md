---
branch: chore/repoint-codex-toolkit-to-cc-suite
threadId: codex-exec-direct
rounds: 1
final_verdict: ship-as-is
date: 2026-05-28
---

## Scope

Docs/instruction-only change: repoints the repo's agent-workflow files from
the retired `codex-toolkit` Codex **MCP** plugin to **`cc-suite`** (which
drives Codex via `codex exec`, no MCP). No Swift source changed; the
`project.pbxproj` delta is the rule-40 version bump (3.40.1/682 →
3.40.2/683, after rebasing onto main which had advanced to v3.40.1) that
trips this audit-gate hook.

Files changed (12): `.claude/skills/fix-issue/SKILL.md`,
`.claude/commands/fix-issue.md`, `.claude/skills/feature-workflow/SKILL.md`,
`.claude/commands/feature-workflow.md`, `.claude/hooks/check_codex_audit_artifact.sh`,
`.claude/rules/47-feature-workflow.md`, `.claude/rules/48-parallel-execution.md`,
`.claude/README.md`, `.claude/codex-audits/README.md`, `docs/bugs.md` (Rules),
`project.yml`, `vreader.xcodeproj/project.pbxproj`.

Wording style (per the independent Codex consult that preceded this change):
**hybrid** — tool-agnostic invariant ("the project's configured independent
Codex audit runner") + concrete current command (`/cc-suite:audit`,
`/cc-suite:audit-fix`, `/cc-suite:review-plan`, `/cc-suite:bug-analyze`) +
an explicit "do NOT use Codex MCP / `ToolSearch +codex`" guard.

## Audit method (dogfood)

This audit was run through **cc-suite's own engine** — `codex exec`
(read-only sandbox, `-C` the repo) — i.e. the very path this PR documents.
It succeeding end-to-end is itself the migration's validation. Run directly
rather than via the cc-suite job runner, so no job/session id is registered
(`threadId: codex-exec-direct`). Prompt: `/tmp/codex-audit-repoint.md`;
output: `/tmp/codex-audit-repoint-out.md`.

## Findings

**Zero findings.** Codex independently verified all six focus areas:

1. No live routing instruction still points at `mcp__plugin_codex-toolkit_codex__codex`,
   `codex-reply`, `ToolSearch +codex`, or `/codex-toolkit:*` — the only
   remaining mentions are explicit "do NOT use" guards or historical logs.
2. No broken/contradictory step introduced (no orphaned "2a availability
   test" / "4d" references; the rewritten Gate-2/Gate-4/Phase-4 sections are
   self-consistent).
3. Gate→command mapping correct: `/cc-suite:review-plan` = Gate 2;
   `/cc-suite:audit` / `/cc-suite:audit-fix` = Gate 4 / fix Phase 4;
   `/cc-suite:bug-analyze` = root-cause.
4. `check_codex_audit_artifact.sh` passes `bash -n`; the edited heredoc
   guidance is coherent with cc-suite and introduced no unsafe backtick/`$`
   command substitution.
5. The two near-duplicate pairs (fix-issue SKILL↔command,
   feature-workflow SKILL↔command) stay in sync.
6. Historical `.claude/codex-audits/*.md` logs and historical `docs/bugs.md`
   tracker notes were correctly left untouched (only the top-of-file
   workflow Rules and `codex-audits/README.md` changed).

## Verdict

ship-as-is — verified by `codex exec` (cc-suite engine), zero findings.

## Out of scope / follow-up (human)

`.cc-suite.md` config is NOT generated here (cc-suite is running on
defaults). Per the consult, the human runs `/cc-suite:setup`, then the
useful content from the tracked `.codex-toolkit.md` (stack, test command,
source dirs, skip patterns, Swift/SwiftData/WKWebView audit instructions) is
ported and `.codex-toolkit.md` deleted in a follow-up.
