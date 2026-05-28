# .claude/ — AI Development Configuration

This directory contains configuration for AI coding tools — primarily [Claude Code](https://docs.anthropic.com/en/docs/claude-code), with cross-tool support via `AGENTS.md` at the project root.

## Prerequisites

### Codex CLI (for `/cc-suite:*` audit commands)

The `cc-suite` plugin uses OpenAI's Codex as an independent second opinion for code audits, driving it via `codex exec` (a killable, deadline-bounded CLI runner — no MCP bridge). Install Codex globally and log in with your subscription:

```bash
npm install -g @openai/codex
codex login                   # Log in with your ChatGPT subscription (recommended)
codex --version               # Verify it's on PATH
```

Subscription auth (`codex login` with ChatGPT Plus/Pro) is dramatically cheaper than `OPENAI_API_KEY` pay-per-token billing for sustained sessions. API keys work as a fallback (`codex login --with-api-key`).

### Why a second AI model?

Claude writes the code; Codex audits it independently. Cross-model verification catches blind spots a single model would miss. This is built into `/cc-suite:audit`, `/cc-suite:audit-fix`, and `/fix-issue`.

## Directory Structure

```
.claude/
├── README.md              # This file
├── settings.json          # Team-shared settings (checked in)
├── settings.local.json    # Local permissions allowlist (also checked in for vreader)
├── rules/                 # Auto-loaded project rules
├── commands/              # Project-specific slash commands
├── skills/                # Project-tracked skills (the relevant ones for vreader)
├── agents/                # Subagent definitions for /feature-workflow
├── hooks/                 # UserPromptSubmit hook (>>-prefix prompt refinement)
├── docs-guardian/         # (currently empty — see Notes below)
├── tdd-guardian/          # TDD Guardian config (xcodebuild test command)
└── loc-guardian.local.md  # Per-file LOC limit + Swift extraction patterns
```

## Settings

| File | Purpose |
|------|---------|
| `settings.json` | Plugin allowlist + UserPromptSubmit hook (no plugins currently enabled) |
| `settings.local.json` | Bash/MCP permission allowlist. Tracked in git so the team shares the same allow set. |

## Rules (`rules/`)

Auto-loaded into every Claude Code session as project context. After the cleanup pass, only the rules that actually apply to vreader's iOS Swift codebase remain:

| File | Scope |
|------|-------|
| `00-engineering-principles.md` | Local engineering principles + pointer to `AGENTS.md` |
| `10-tdd.md` | TDD workflow for Swift/XCTest with `xcodebuild test`, pattern catalog |
| `20-logging-and-docs.md` | Dev docs update policy |
| `22-comment-maintenance.md` | Keep code comments in sync with changes |
| `40-version-bump.md` | `MARKETING_VERSION` + `CURRENT_PROJECT_VERSION` in `project.yml`, then `xcodegen generate` |
| `50-codebase-conventions.md` | Actor isolation, persistence, reader architecture, notification bus, error handling, OSLog, DEBUG gating |

## Slash Commands (`commands/`)

Project-specific commands (not from plugins):

| Command | Purpose |
|---------|---------|
| `/bump` | Version bump (project.yml → xcodegen → commit → tag → push) |
| `/feature-workflow` | Gated agent-driven workflow with specialized subagents |
| `/fix` | Root-cause bug fixing with TDD |
| `/fix-issue` | End-to-end GitHub issue resolver (fetch, branch, fix, audit, PR) |
| `/merge-prs` | Review and merge open PRs sequentially |
| `/test-guide` | Generate manual testing guide |

## Agents (`agents/`)

Subagent definitions used by `/feature-workflow`:

| Agent | Role |
|-------|------|
| `planner` | Research, edge cases, modular work items |
| `implementer` | TDD-driven code changes |
| `auditor` | Diff review for correctness and rule violations |
| `test-runner` | Test execution and E2E coordination |
| `verifier` | Final pre-release checklist |
| `spec-guardian` | Validates work against specifications |
| `impact-analyst` | Finds minimal correct change set |
| `release-steward` | Commit messages and release notes |
| `manual-test-author` | Manual testing guide maintenance |

## Hooks (`hooks/`)

| File | Trigger | Purpose |
|------|---------|---------|
| `refine_prompt.sh` | UserPromptSubmit | When a prompt starts with `>>`, sends it through Haiku for refinement, copies the result to clipboard, and blocks the original prompt. Independent of project type. |

## Guardian Configs

- **`tdd-guardian/config.json`** — drives the TDD Guardian agents. Configured with vreader's `xcodebuild build-for-testing && xcodebuild test-without-building` flow.
- **`docs-guardian/`** — directory exists but the config has been removed; vreader has no website docs that need automated audit.
- **`loc-guardian.local.md`** — 300-line cap per file, with Swift-aware extraction patterns (PersistenceActor extensions, ReaderContainerView+Concern.swift, etc.).

## Plugins

`settings.json` currently has no `enabledPlugins`. Add plugins here when needed; previous web-focused plugins (`frontend-design`, `rust-analyzer-lsp`) were removed because vreader is an iOS Swift project.

## Skills

`.claude/skills/` is tracked in git. After the cleanup pass, only skills relevant to vreader's iOS Swift context remain:

| Skill | When used |
|-------|-----------|
| `ai-coding-agents` | Multi-tool orchestration guidance (Codex CLI / Claude Code CLI) |
| `mcp-dev` / `mcp-server-manager` | MCP server configuration |
| `plan-audit` / `plan-verify` / `planning` | Implementation planning |
| `release-gate` | Quality gate checks |
| `sim-transfer` | Push files into the iOS Simulator |
| `triage` | Classify reported issues into bugs/features |

Web/Tauri skills (`react-app-dev`, `tauri-*`, `tiptap-*`, `css-design-tdd`, `shortcut-audit`, `rust-tauri-backend`) were removed in the same cleanup pass.

## Related Files (Project Root)

| File | Purpose |
|------|---------|
| `AGENTS.md` | Single source of truth for AI tool instructions (read by Claude, Codex, etc.) |
| `CLAUDE.md` | Claude Code entry point — `@AGENTS.md` directive |
| `CLAUDE.local.md` | Personal instructions (gitignored — create as needed) |
| `docs/subsystems/debug-bridge.md` | Reference for the `vreader-debug://` URL scheme used by feature #44 |
