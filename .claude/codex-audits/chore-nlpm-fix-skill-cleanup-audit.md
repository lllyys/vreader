---
branch: chore/nlpm-fix-skill-cleanup
threadId: manual-fallback
rounds: 1
final_verdict: ship-as-is
date: 2026-05-28
---

## Scope

Tooling-docs only. Acts on the `/nlpm:fix` scoring pass (avg 87.6/100) per the
user's explicit disposition: **delete** three imported-from-another-project
skills, **adapt** the rest. No Swift, no app behavior. The `project.pbxproj`
delta is the rule-40 version bump (3.40.3/684 → 3.40.4/685) which trips this
audit-gate hook.

### Deleted (user-directed, git-recoverable)
- `.claude/skills/release-gate/` (SKILL.md + scripts/run_release_gate.sh) — ran
  `pnpm check:all` / `pnpm lint && pnpm test && pnpm build`, useless in an
  iOS/Xcode repo (vreader's gate is `xcodebuild test`, per rule 10 + `.cc-suite.md`).
- `.claude/skills/mcp-dev/` (SKILL.md + references/paths.md + scripts/scan_mcp.sh) — "VMark" MCP-dev tooling.
- `.claude/skills/mcp-server-manager/` (SKILL.md + scripts/scan_mcp_servers.py) — "VMark"/tauri MCP example.

### Adapted
- `.claude/README.md`: removed the two skills-table rows for the deleted skills; updated the cleanup note (provenance: removed 2026-05-28, surfaced by `/nlpm:fix`).
- `.claude/skills/ai-coding-agents/SKILL.md:10`: "VMark development" → "vreader development".
- `.claude/skills/plan-audit/SKILL.md:3,15`: `docs/codex-plans/*` → `dev-docs/plans/*` (vreader's canonical plan dir per AGENTS.md + rule 47).
- `.claude/skills/plan-verify/SKILL.md:15`: same path adaptation.
- `.claude/agents/planner.md:22`: same path adaptation (caught by a follow-up sweep of `.claude/agents/`, which the `/nlpm` discover patterns don't cover).
- `.claude/commands/fix.md`: added frontmatter (`description` + `argument-hint`); description explicitly distinguishes `/fix` from the full `/fix-issue` pipeline.
- `.claude/commands/test-guide.md`: added frontmatter `description` (lifted from its own body line).

## Manual audit evidence

Manual fallback: the change is deletions + markdown string substitutions —
no code logic, security surface, or instruction-routing to audit by Codex.

### Checks performed
1. **No dangling refs from the deletions** — pre-delete grep for
   `release-gate|mcp-dev|mcp-server-manager` across the repo found only
   `.claude/README.md` (fixed in this PR) + a `docs/features.md` "release-gate
   script" mention that refers to the DebugBridge release-verification *script*,
   NOT the skill (left untouched, correct). Post-edit grep for `VMark` /
   `docs/codex-plans` across `.claude/` returns zero.
2. **Deletions are git-tracked** — recoverable from history; `git rm -r` only.
   User explicitly directed the three deletions.
3. **Path adaptation correctness** — `dev-docs/plans/` is vreader's documented
   plan directory (AGENTS.md, rule 47, feature-workflow). `docs/codex-plans/`
   does not exist in this repo.
4. **Frontmatter additions are minimal + accurate** — `description` only (+
   `argument-hint` for fix.md which uses `$ARGUMENTS`); no guessed
   `allowed-tools`. Reload confirmed both descriptions now register.
5. **Build** — `xcodegen generate` succeeded; pbxproj at 3.40.4/685. No Swift
   changed.

### NOT addressed here (reported, needs separate human decision — out of scope)
- `AGENTS.md:23` ↔ `.claude/rules/10-tdd.md:3` coverage-gate contradiction
  (AGENTS.md claims a `ut` gate; 10-tdd.md says no structural gate). Behavioral
  contradiction — which side is authoritative is a judgment call.
- `.claude/commands/fix.md` workflow diverges from `/fix-issue` (skips
  `IN PROGRESS` + pre-FIXED verify) — may be a deliberate quick-fix shortcut.
- ~95% duplication between the `fix-issue`/`feature-workflow` command and skill
  files — structural refactor, not a mechanical fix.

## Verdict

ship-as-is — tooling-docs cleanup, deletions user-directed + git-recoverable,
adaptations are unambiguous string/path fixes, no code risk.
