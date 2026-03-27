---
description: End-to-end GitHub issue resolver — fetch, classify, fix, audit, PR
argument-hint: "#123 [#456 ...]"
---

# Fix Issue

Resolve one or more GitHub issues end-to-end: fetch, classify, branch, fix with TDD, Codex audit loop, gate, and PR.

## Input

```text
$ARGUMENTS
```

## Pre-flight Checks

1. **Parse arguments** — extract issue numbers (e.g. `#123`, `123`, `#123 #456`).
   - No arguments: print usage and STOP.
2. **Check working tree** — run `git status --porcelain`. If dirty, do not revert unrelated changes; isolate your work with a branch.
3. **Confirm branch** — run `git branch --show-current` and `git fetch origin`.

## Single-Issue Pipeline

When exactly one issue number is provided, run phases 1-6 sequentially.

### Phase 1: Fetch & Classify

```bash
gh issue view {N} --json number,title,body,labels,state,assignees
```

- If issue not found or closed: warn user, ask whether to proceed, or STOP.
- Classify by labels or body content:

| Classification | Trigger | Path |
|---------------|---------|------|
| Bug | label contains `bug`, or body mentions error/crash/broken | Bug path (Phase 3a) |
| Feature | label contains `feature`/`enhancement` | Feature path (Phase 3b) |
| Question | label contains `question` | Question path (Phase 3c) |
| Ambiguous | no matching labels | Ask user to classify |

### Phase 2: Branch Setup

- Generate slug from title: lowercase, strip non-ASCII, replace spaces with `-`, truncate to 40 chars.
- Branch name: `fix/issue-{N}-{slug}` (bug) or `feat/issue-{N}-{slug}` (feature).
- If branch already exists: ask user — reuse or rename.
- Create and checkout the branch.

### Phase 3: Resolve

#### 3a. Bug Path

Follow the philosophy from `/fix` — no half measures.

1. **Reproduce** — Read relevant code, trace call chain from symptom to root cause.
2. **Diagnose** — Find root cause, check for similar patterns elsewhere.
3. **RED** — Write a failing test capturing the bug (see `.claude/rules/10-tdd.md`):
   - SwiftData bug → persistence test with in-memory container
   - WKWebView bridge bug → parser/coordinator unit test
   - ViewModel bug → Swift Testing async test with `@MainActor`
   - Utility bug → parameterized `@Test(arguments:)` covering the broken case
4. **GREEN** — Fix the root cause with minimal, focused changes.
5. **REFACTOR** — Clean up without changing behavior.

#### 3b. Feature Path

1. **Research** — Search for best practices, prior art, established patterns (AGENTS.md mandate).
2. **Plan** — Design the implementation. If it would touch 10+ files or need 4+ work items, redirect to `/feature-workflow` and STOP this pipeline.
3. **TDD implement** — RED/GREEN/REFACTOR per work item.
4. **Edge cases** — Brainstorm and test: empty input, null, Unicode/CJK, rapid actions, concurrent access.

#### 3c. Question Path

1. **Research** — Read code and docs to compose a thorough answer.
2. **Detect language** — Check the issue author's language from the issue title and body. Reply in the **same language** the author used.
3. **Respond** — Post the answer as a comment:
   ```bash
   gh issue comment {N} --body "{answer in author's language}"
   ```
4. **STOP** — No branch, no PR needed. Clean up the branch if created.

### Phase 4: Codex Audit Loop (max 3 iterations)

**Goal**: Targeted audit of changed files, not a generic sweep.

#### 4a. Collect changed files

```bash
git diff main --name-only
git diff main
```

#### 4b. Initial audit via Codex MCP

Use `ToolSearch` with query `+codex` to discover Codex tools.

**Availability test** — before the real audit, send a short ping:
```
mcp__codex__codex with:
  prompt: "Respond with 'ok' if you can read this."
```
If Codex does not respond or errors out, skip to **4f. Fallback** immediately.

If Codex responds:

**Audit prompt:**
```
mcp__codex__codex with:
  sandbox: read-only
  prompt: |
    Audit these files changed for GitHub issue #{N}: {title}
    Files: {changed file list}
    Diff summary: {git diff main --stat}
    Focus:
    1. Correctness & logic — does the fix actually solve the root cause?
    2. Edge cases — boundary conditions, nil, Unicode/CJK, concurrent access
    3. Security — JS/CSS injection safety in evaluateJavaScript() and WKWebView bridges
    4. Duplicate code — repeated logic that should be unified
    5. Dead code — unused imports, unreachable branches, orphaned functions
    6. Shortcuts & patches — workarounds, TODO markers, band-aids
    7. VReader compliance — Swift 6 concurrency, @MainActor correctness, SwiftData actor isolation, file size <300 lines
    8. Bridge safety — FoliateJSEscaper used for all JS string interpolation, message parser handles all edge cases
    Report as: file:line | severity (Critical/High/Medium/Low) | issue | fix
```

#### 4c. Parse & fix

Fix **every** finding — Critical, High, Medium, and Low.

#### 4d. Verify via Codex reply

Use `mcp__codex__codex-reply` on the same thread:

```
I fixed these issues: {list of fixes with file:line}
Verify ALL fixes are correct. Check for new issues introduced by the fixes.
Updated diff: {git diff main --stat}
```

#### 4e. Loop or exit

- **Zero findings**: audit passes, exit loop.
- **Any findings remain** and iteration < 3: fix everything and verify again.
- 3 iterations reached with findings still open: STOP. Report all remaining issues.

#### 4f. Fallback — manual mini-audit

If Codex MCP is unavailable, perform a manual audit:
1. Logic & Correctness
2. Duplication
3. Dead Code
4. Refactoring Debt
5. Shortcuts & Patches
6. Bridge Safety (JS injection, message parsing)

Read each changed file, analyze, fix Critical/High issues.

### Phase 5: Gate

Run up to 3 attempts:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test \
  -project vreader.xcodeproj -scheme vreader \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:vreaderTests
```

- Pass: proceed to Phase 6.
- Fail: read errors, fix, retry.
- 3 failures: report errors, keep branch, STOP.

Also verify:
- Update `docs/bugs.md` status if fixing a tracked bug.
- Update `docs/architecture.md` if component communication changed.

### Phase 6: Create PR

```bash
gh pr create --title "{type}: {concise description}" --body "$(cat <<'EOF'
## Summary

{1-3 bullet points describing what changed and why}

Refs #{N}

## What Changed

{list of key changes}

## Codex Audit

{audit summary — iterations run, findings fixed}

## Validation

- [x] `xcodebuild test` passes
- [x] Tests cover changed behavior (TDD)
- [x] Codex audit loop completed ({M} iterations)

## Type of Change

- [{x if bug}] Bug fix
- [{x if feature}] Feature
EOF
)"
```

Report the PR URL to the user.

---

## Multi-Issue Pipeline

When multiple issue numbers are provided (e.g. `#123 #456 #789`).

### M1: Fetch & Validate All

Fetch all issues in parallel:
```bash
gh issue view {N} --json number,title,body,labels,state
```

- Filter out closed issues (warn user).
- Filter out questions (handle inline with `gh issue comment`, no worktree needed).
- Remaining issues proceed to worktree pipeline.

### M2: Create Worktrees

For each issue, create an isolated git worktree:
```bash
git worktree add .claude/worktrees/issue-{N} -b fix/issue-{N}-{slug} main
```

### M3: Parallel Execution

Spawn one Agent per issue, each running the **full single-issue pipeline** (Phases 1-6) inside its worktree directory.

### M4: Collect Results

After all agents complete, display a summary table:

```
| Issue | Status | Branch | PR |
|-------|--------|--------|------|
| #123  | Done   | fix/issue-123-slug | #45 |
| #456  | Failed (gate) | fix/issue-456-slug | — |
```

### M5: Cleanup Worktrees

```bash
# Remove successful worktrees
git worktree remove .claude/worktrees/issue-{N}

# Keep failed ones for investigation
```

---

## Error Handling

| Scenario | Action |
|----------|--------|
| No arguments | Print usage, STOP |
| Issue not found / closed | Warn, ask user |
| Dirty working tree | Isolate with branch, don't revert unrelated changes |
| No labels (ambiguous type) | Ask user to classify |
| Codex MCP unavailable | Fall back to manual mini-audit |
| Gate fails 3x | Report errors, keep branch, STOP |
| Feature too large (10+ files) | Redirect to `/feature-workflow` |
| Branch already exists | Ask user: reuse or rename |
