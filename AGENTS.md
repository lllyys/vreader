# [AGENTS.md](http://AGENTS.md)

Shared instructions for all AI agents (Claude, Codex, etc.).

- You are an AI assistant working on the project.
- **Read `docs/architecture.md` before making any code changes. Update it when adding new layers, patterns, services, or changing how components communicate.**
- Use English unless another language is requested.
- Follow the working agreement:
  - Run `git status -sb` at session start.
  - Read relevant files before editing.
  - Keep diffs focused; avoid drive-by refactors.
  - Do not commit unless explicitly requested.
  - Keep code files under \~300 lines (split proactively).
  - Keep features local; avoid cross-feature imports unless truly shared.
  - **Research before building**: For new features, search for industry best practices,  
    established conventions, and proven solutions (web search, official docs, prior art in  
    popular open-source projects). Don't invent when a well-tested pattern exists.
  - **Edge cases are not optional**: Brainstorm as many edge cases as possible — empty input,  
    null/undefined, max values, concurrent access, Unicode/CJK, RTL text, rapid repeated  
    actions, network failures, permission denials. Write tests for every one.
  - **Test-first is mandatory** for new behavior:
    - Write a failing test (RED), implement minimally (GREEN), refactor (REFACTOR).
    - Coverage thresholds are enforced — `ut` fails if coverage drops.
    - Exceptions: CSS-only, docs, config. See `.claude/rules/10-tdd.md` for full scope.
  - Run `xcodebuild test -only-testing:vreaderTests` for unit test gates. Skip UI tests during development.
  - Default simulator: **iPhone 17 Pro** (Dynamic Island — catches safe area bugs).
  - **Verification harness** (DEBUG only): `vreader-debug://` URL scheme drives reset / seed / open / settle / snapshot / eval from `xcrun simctl openurl`, so verification runs don't need computer-use for reproduction or assertion. See `dev-docs/debug-bridge.md`.
  - **Task workflow** (three files, one flow):
    - `docs/tasks.md` — **inbox**. User writes free-form descriptions. Agent triages (classify only, do not fix or implement during triage). See `docs/tasks.md` for classification rules, deduplication, and triage record format.
    - `docs/bugs.md` — **bug tracker**. Something implemented but broken. Follow the bug fix workflow defined in `docs/bugs.md` (Understand → RED → GREEN → REFACTOR → Verify → Track).
    - `docs/features.md` — **feature tracker**. Something never implemented. Must be planned before implementation (Problem, Scope, Edge Cases, Test Plan, Acceptance Criteria). See `docs/features.md` for plan template and statuses.
  - **Key rules**:
    - Bugs vs features: broken implementation → `docs/bugs.md`; never implemented → `docs/features.md`. Never mix.
    - Triage is classification only — do not fix bugs or implement features during triage.
    - Features must reach `PLANNED` status before `IN PROGRESS`. Exception: features resolved incidentally by a bug fix.
  - **GitHub Issues** (selective mirror, not full sync):
    - **When to create**: High-severity bugs, release blockers, and major features (`Priority: High`). Do not mirror every tracker row.
    - **On create**: Add `GH: #123` to the Notes column in bugs.md/features.md. Use labels: `bug`/`feature`, `severity:high`/`severity:medium`.
    - **PRs use `Refs #N`**, not `Fixes #N` — prevents premature auto-close.
    - **On resolve** (post-merge finalizer, do not close before merge):
      1. Verify markdown status is updated (FIXED/DONE).
      2. Verify fix is on `main`.
      3. Post closure comment: commit SHA, test evidence, cause summary (bugs) or acceptance result (features).
      4. Run `gh issue close #N`.
    - **Exception**: Small single-issue fixes may use `Fixes #N` in PR body for auto-close.
    - **Partial delivery**: Keep issue open. Use task checklist in issue body or split into follow-up issues.
- AI coding tool auth:
  - **Prefer subscription auth over API keys** for all AI coding tools (Claude Code, Codex CLI, Gemini CLI). Subscription plans are dramatically cheaper for sustained coding sessions — API billing can cost 10–30x more.
  - Claude Code: log in with Claude Max subscription. Codex CLI: `codex login` with ChatGPT Plus/Pro. Gemini CLI: Google account login.
  - API keys work as a fallback for light or automated usage.

