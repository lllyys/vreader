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
  - **Verification harness** (DEBUG only): `vreader-debug://` URL scheme drives reset / seed / open / settle / snapshot / eval from `xcrun simctl openurl`, so verification runs don't need computer-use for reproduction or assertion. See `docs/subsystems/debug-bridge.md`.
  - **Version bump per PR**: every PR must include a `chore: bump version to X.Y.Z` commit as its last commit before opening — patch for fixes/docs/chores, minor for new features, major for breaking changes. Tag is cut from the merge commit on `main` post-merge. See `.claude/rules/40-version-bump.md`.
  - **Docs sync per PR**: when a PR adds a service, schema, notification, environment key, or user-visible feature, update `docs/architecture.md` and/or `README.md` in the same PR (separate commit before the version bump). Triggers + checklist in `.claude/rules/24-doc-sync.md`.
  - **Merge gate — fix-or-implement**: a PR that references an open bug (`Refs #N` against `docs/bugs.md`) does not merge until that bug's status is `FIXED`. A PR that references an open feature does not merge until the feature reaches `DONE`. Tracker-only updates (re-classifying severity, correcting a recommendation, adding screenshots) ride along with the fix PR — they don't ship as standalone merges. Pure meta-process changes (rule additions, repo reorgs, tooling) are exempt because they don't reference a bug/feature row.
  - **Close gate — verified, not just merged**: a GitHub Issue does NOT close until the work is verified — by default end-to-end against a real environment, with a narrow exception for bugs whose failure mode physically cannot be observed on a device (race conditions, failure injection paths, etc.). Symmetric for both trackers:
    - **Bugs**: `docs/bugs.md` status `FIXED` means "code shipped to main with passing tests" (the merge gate). Closing the GH issue requires either:
      - **Device verification (default)** — install the new build on device/simulator, run the original repro, confirm the actual symptom is gone. Apply the `awaiting-device-verification` label between merge and verification so the debt is queryable.
      - **Verification exception (narrow)** — when the failure mode physically cannot be reproduced on a device without a fault-injection harness that doesn't exist (e.g., "auth fails mid-MKCOL", "SwiftData save fails mid-pair", "two restores race for different chapters", "concurrent insert during restore picker"), close under exception with: (a) a deterministic high-fidelity integration test that exercises the same failure path through the real subsystem boundaries (not a casual stub), (b) the `verification-exception` label, (c) a closure comment citing the test + the evidence file in `dev-docs/verification/`. Casual unit tests with stubs do not qualify — the test must drive the same code paths the production failure would hit. If neither real-environment repro nor a high-fidelity integration test is feasible, keep the issue open with the `verification-blocked` label and a follow-up to build the harness (potentially as a feature).
    - **Features**: `docs/features.md` status `DONE` means "implementation merged with passing tests" (the merge gate). Closing the GH issue requires reaching status `VERIFIED`: every acceptance criterion exercised end-to-end (XCUITest + DebugBridge auto-verification, or an explicit on-device manual verification log) — for non-UI features, end-to-end against a real backend (e.g., backup → restore round-trip against a live WebDAV server, not just an in-memory mock).
    - The closure comment must cite the verification (commit SHA + what was tested + what was observed; for exception-class bugs, name the integration test + its evidence file). Until then, the GH issue stays open with the relevant label and a "shipped in vX.Y.Z, awaiting verification" comment so the work doesn't drop off the radar.
  - **Feature implementation workflow** (binding 6-gate sequence — never skip a gate). Full rule at `.claude/rules/47-feature-workflow.md`. Summary: Plan → Independent plan audit → TDD implementation → Implementation audit loop → Device/integration verification → Merge.
  - **Parallel execution** — when running multiple agents, subagents, or worktrees, follow `.claude/rules/48-parallel-execution.md`. Core thesis: parallelism is an isolation tool first and a speed tool second; only parallelize when expected wall-clock saved exceeds setup + review + conflict + resource + failure costs. Hard rules: author/auditor separation, hard dependency blocks downstream Gate 3, one writer per file/area at a time.
  - **Background shells** — full rule at `.claude/rules/49-background-shells.md`. Hard rules: never start a second background shell to wait on a first; never `pgrep -f "<toolname>"` as a gate (matches the class, not the instance, so future invocations re-arm the wait); wait on identity (exact PID, sentinel file, output marker), not likeness. One async job = one owner = one completion channel. Origin incident: 2026-05-10 left two `pgrep -f "xcodebuild test"` poll loops alive for 3+ hours when later bug-fix iterations re-armed the predicate.
  - **Task workflow** (three files, one flow). The `## Rules` section at the top of each tracker is **binding** — it's the authoritative workflow for that file, not decorative prose:
    - `docs/tasks.md` — **inbox**. User writes free-form descriptions. Agent triages (classify only, do not fix or implement during triage). Classification rules, deduplication, and triage record format are at the top of the file.
    - `docs/bugs.md` — **bug tracker**. Something implemented but broken. Bug fix workflow (Understand → RED → GREEN → REFACTOR → Verify → Track) is at the top of the file.
    - `docs/features.md` — **feature tracker**. Something never implemented. Must be planned before implementation (Problem, Scope, Edge Cases, Test Plan, Acceptance Criteria). Plan template and statuses are at the top of the file.
  - **Key rules**:
    - Bugs vs features: broken implementation → `docs/bugs.md`; never implemented → `docs/features.md`. Never mix.
    - Triage is classification only — do not fix bugs or implement features during triage.
    - Features must reach `PLANNED` status before `IN PROGRESS`. Exception: features resolved incidentally by a bug fix.
  - **GitHub Issues** (mechanical mirror — every feature + every bug gets one):
    - **When to create — features**: every feature that reaches `PLANNED` status gets a GH issue. Trigger is mechanical (status = PLANNED + no `GH: #N` already in Notes → create). Idempotent: skip creation if `GH: #N` is already present. **Why mechanical not priority-based**: a `PLANNED` feature has problem + scope + edge cases + test plan + acceptance criteria — exactly the threshold where contributors benefit from a public handle for `Refs #N`, design discussion, and verification follow-up. Priority-based mirroring is leaky in this repo's history (medium features mirrored, some high ones not).
    - **When to create — bugs**: every bug logged in `docs/bugs.md` gets a GH issue. Trigger is mechanical (any new bug row + no `GH: #N` already in Notes → create). Idempotent: skip if `GH: #N` is already present. **Why mechanical not selective**: priority-based mirroring drops critical bugs by accident (Low/Medium triage misses + later escalations). The GH issue is also where verification logs land for bug-row → GH-close, so every bug needs the handle anyway.
    - **When NOT to create (either tracker)**: status is `DEFERRED`, `WONT DO`, `DUPLICATE`, or feature was resolved incidentally by a bug fix.
    - **Local-only escape hatch**: a feature that's planned but explicitly should not be mirrored to GH gets `Mirror: no` in the Notes column. The rule respects this and skips creation.
    - **GH issue body = pointer, not second source of truth**: title `Feature #N: <short summary>` or `Bug #N: <short summary>`. Body has (1) short problem statement, (2) link back to the row + plan in `docs/features.md` / `docs/bugs.md`, (3) acceptance criteria copied once for readability, (4) explicit "Source of truth: `docs/features.md`" line. Design decisions and scope changes happen in the markdown tracker; GH comments that materially change scope must be ported back to the tracker in the same PR.
    - **On create**: add `GH: #123` to the Notes column. Use labels: `bug` or `enhancement` (GitHub's "feature" label is named `enhancement`); plus `severity:high`/`severity:medium` if priority warrants.
    - **PRs use `Refs #N`**, not `Fixes #N` — prevents premature auto-close.
    - **On resolve** (post-merge finalizer, do not close before merge AND do not close before verification — see "Close gate — verified, not just merged" above):
      1. Verify markdown status is updated to terminal-verified state (`FIXED` then device-verified for bugs; `VERIFIED` for features).
      2. Verify fix is on `main`.
      3. Run the verification pass (re-run repro for bugs; exercise acceptance criteria for features).
      4. Post closure comment: commit SHA, what was tested, what was observed, cause summary (bugs) or acceptance result (features).
      5. Run `gh issue close #N`.
      Between merge and verification, leave the issue open with a "shipped in vX.Y.Z, awaiting verification" comment.
    - **Exception**: Small single-issue fixes may use `Fixes #N` in PR body for auto-close.
    - **Partial delivery**: Keep issue open. Use task checklist in issue body or split into follow-up issues.
- AI coding tool auth:
  - **Prefer subscription auth over API keys** for all AI coding tools (Claude Code, Codex CLI, Gemini CLI). Subscription plans are dramatically cheaper for sustained coding sessions — API billing can cost 10–30x more.
  - Claude Code: log in with Claude Max subscription. Codex CLI: `codex login` with ChatGPT Plus/Pro. Gemini CLI: Google account login.
  - API keys work as a fallback for light or automated usage.
  - **Local AI smoke test**: `.secrets/test-llm.sh` posts a one-shot prompt against OpenRouter's free tier to confirm the key + wire format work. Key lives in `.secrets/.env` (gitignored). Use this for quick external-LLM sanity checks; in-app AI features should be driven through the app's own provider profiles, not this script.
