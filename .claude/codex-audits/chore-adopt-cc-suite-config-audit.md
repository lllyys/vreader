---
branch: chore/adopt-cc-suite-config
threadId: manual-fallback
rounds: 1
final_verdict: ship-as-is
date: 2026-05-28
---

## Scope

Config/dev-tooling only. Adopts the cc-suite project config + Codex/Gemini
bridge (the `/cc-suite:setup` → `/cc-suite:init` flow), following the
codex-toolkit→cc-suite repoint (PR #1219). No Swift, no `.claude/` workflow
instructions, no app behavior. The `project.pbxproj` delta is the rule-40
version bump (3.40.2/683 → 3.40.3/684) which trips this audit-gate hook.

Files: `.codex-toolkit.md` → `.cc-suite.md` (rename + content port),
`GEMINI.md` (new, `@AGENTS.md`), `.codex/config.toml` (new),
`.codex/prompts/.gitkeep` + `.gemini/{skills,commands}/.gitkeep` (new),
`.gitignore` (cc-suite block + bridge-symlink ignores), `project.yml` /
`project.pbxproj` (version bump).

## Manual audit evidence

Manual fallback used because the change is config/markdown only — there is no
code logic, security surface, or instruction routing for Codex to audit. (The
prior PR #1219 already validated cc-suite's `codex exec` engine end-to-end.)

### Checks performed

1. **`.cc-suite.md` content fidelity** — diffed against the retired
   `.codex-toolkit.md`: stack, `xcodebuild test` command, source dirs,
   defaults (model gpt-5.5 / effort high / audit-type mini / sandbox
   workspace-write), `Audit Focus` (balanced), `Skip Patterns`, and the
   `Project-Specific Instructions` Swift-6/SwiftData/WKWebView convention
   block all carried over verbatim. gpt-5.5 confirmed available via
   `codex-preflight.sh` (status ok; models include gpt-5.5).
2. **Section headings preserved** — cc-suite's runner parses `Defaults`,
   `Audit Focus`, and `Project-Specific Instructions` by heading; all three
   retained exactly (verified against `commands/shared/codex-call.md`).
3. **AGENTS.md / CLAUDE.md untouched** — `init.sh` output confirmed both
   skipped ("AGENTS.md already exists — leaving alone"; "CLAUDE.md has unique
   content … left alone"). `git status` shows neither modified.
4. **MCP registration deliberately skipped** — did NOT run
   `/cc-suite:bridge-mcp` / `mcp_codex.sh`. Rationale: cc-suite drives Codex
   via `codex exec`, never the `codex-cli` MCP (its own docs say the MCP
   hangs), and PR #1219 added guards against routing audits through a Codex
   MCP. Registering `{"command":"codex","args":["mcp-server"]}` in `.mcp.json`
   would be unused + contradictory. No `.mcp.json` created. `.codex/config.toml`
   has no MCP block. Coherent with the codex-exec-only stance.
5. **No machine-specific artifacts committed** — the bridge symlinks
   `.claude/skills/cc-suite` (absolute, version-pinned `…/0.7.0/…` path) and
   `.agents/` are gitignored (verified via `git check-ignore`) and absent from
   the staged set. Only machine-agnostic, team-shareable files committed.
6. **gitignore correctness** — cc-suite's managed block (local AI state,
   `.codex/*` / `.gemini/*` with checked-in subdir exceptions) left intact; the
   symlink-ignore block added OUTSIDE the managed `>>> cc-suite >>>` markers so
   `/cc-suite:unbridge` won't clobber it.
7. **Build** — `xcodegen generate` + version bump verified pbxproj at
   3.40.3 / 684. (No Swift changed; no build risk from this PR.)

## Verdict

ship-as-is — config/tooling only, content-faithful port, no code or
instruction risk. Bridge is non-destructive to the binding AGENTS.md/CLAUDE.md.
