# 48 — Parallel Execution

## Purpose

Parallelism is an **isolation tool first and a speed tool second**. Use it when it reduces wall-clock time without weakening review, audit, TDD order, or resource ownership. Use it wrong and you trade serial work for merge hell, audit gaps, or simulator flakiness.

This rule applies to: spawning subagents, launching parallel `/fix-issue` runs, splitting work across git worktrees, or running concurrent feature implementations.

## Decision test

Before parallelizing, estimate honestly:

```
expected wall-clock saved  >  setup + review + conflict + resource-contention + failure cost
```

| Cost | What it covers |
|---|---|
| **setup** | Worktree creation, branch hygiene, subagent brief writing, DerivedData warmup |
| **review** | Main-agent integration time when subagent returns |
| **conflict** | Shared file edits (`project.yml`, `docs/features.md`, `docs/architecture.md`) → rebase |
| **resource** | Single simulator, single device, one Codex/test session at a time |
| **failure** | Probability the subagent drifts and needs collapse + redo |

If the answer isn't clearly positive, don't parallelize.

## Hard rules (non-negotiable)

1. **Author/auditor separation**: the agent that writes a plan, code, or PR is never the agent that audits it. (Codex MCP being a separate process satisfies this by accident; preserve the boundary explicitly.)
2. **Hard dependency blocks downstream Gate 3**: if feature B depends on feature A, you cannot start B's TDD until A is `DONE`. Dependency graph in the tracker is the source of truth.
3. **One writer per file/area at a time**: two agents can work the same feature if their write sets are disjoint and explicit. Two agents writing the same file is a merge conflict you will lose.

## Strong defaults (negotiable with cause)

- Shared-file edits (status flips, version bumps, doc-sync) require **one owner** or a **final integration pass**. They batch at PR merge time, not in parallel.
- Planning subagents are **read-only by default** — return content/patch for the main agent to apply. Write access only when the subagent has its own worktree.
- Parallel Xcode builds require **explicit simulator/device ownership**. Otherwise contention produces misleading test failures.

## Subagent contract (every spawn must specify)

| Field | Required content |
|---|---|
| **Objective** | One sentence — what deliverable you want |
| **Inputs** | Exact file paths to read; relevant audit-gap context (don't rely on "absorbing" parent conversation) |
| **Allowed writes** | Either "none" (read-only, return content) or a specific path prefix |
| **Forbidden actions** | What it must NOT do (e.g., "no Swift code", "no `xcodebuild`", "no PR") |
| **Output format** | What the return message must contain |
| **Stop condition** | When to return — explicit completion criteria |

A subagent without one of these will drift.

## Subagent failure handling

- Subagent output is **advisory until reviewed** by the main agent.
- If it drifts, **re-brief once** with a narrower task. Don't ask it to self-correct indefinitely.
- If still bad, **collapse to the main agent**. Discard the subagent's output.
- **Never merge or apply** generated code/plan text without main-agent review.

## Decision matrix (gate-by-gate)

| Two work units' state | Approach |
|---|---|
| Both Gate 1 (planning) | Single agent, sequential — context switch is cheap |
| Mixed Gate 1 (planning) + Gate 3 (TDD) | Inline Gate 3 + read-only subagent for Gate 1 (tight brief) |
| Both Gate 2 (plan audit) | Parallel OK — independent Codex sessions, different threads |
| Same feature, Gate 2 of plan + Gate 3 of WI on same plan | **Serialize** — never implement against an unaudited plan |
| Both Gate 3 (TDD) on disjoint files | Worktrees + one agent each |
| Both Gate 3 (TDD) on overlapping files | **Serialize** — one writer per area |
| Same feature, WI-N-1 Gate 5 + WI-N Gate 3 | Parallel only if WI-N doesn't depend on WI-N-1's verification result |
| Both Gate 4 (impl audit) | Parallel OK — independent audits |
| Both Gate 5 (verification) | **Serialize** — single device/simulator |
| Mixed Gate 5 + Gate 3 | Parallel OK — different resources |

## Worktree rules

- Use a worktree when **isolation prevents more cost than it adds**. A 30-min high-risk schema change can deserve one; a 4-hour docs-only plan rarely does.
- Worktrees go under `.claude/worktrees/<feature-or-issue-id>/`.
- After removing a worktree, **clean its DerivedData**: each worktree creates its own (~5GB). The `/fix-issue` skill's multi-issue mode includes the cleanup pass; replicate it.
- Never give two concurrent agents the same worktree. One worktree = one writer.
- The main checkout's working tree must be clean before spawning a worktree-based agent — pre-existing dirty state poisons the agent's git context.

## Worked examples

**Good — mixed gates, this session's `#46 WI-0a + #48 planning`**:
- Main agent on `feat/46-wi-0a-...` branch implementing Swift code (Gate 3).
- Spawned read-only subagent reading 14 files + writing one markdown plan to `dev-docs/plans/20260503-feature-48-...md` (Gate 1).
- No file-write overlap. Subagent's output reviewed and integrated by main agent.

**Good — `/fix-issue` multi-issue mode**:
- N issues, N worktrees, N agents. Each runs its own pipeline. Cleanup pass removes stale DerivedData after each worktree is removed.

**Bad — would have been wrong**:
- `#46` and `#47` in parallel: hard dependency (`#47` needs `#46`'s blob storage layout). Tracker says so explicitly. Parallelizing would have wasted `#47`'s implementation.

**Bad — would have been wrong**:
- Spawning a subagent with prompt "implement WI-0a, you have full context" — context absorption fails; the subagent will misremember field names and produce uncompilable code.

## What this rule does NOT cover

- Per-PR parallelism (CI runs across PRs) — handled by the CI infrastructure, not this rule.
- Agent-to-agent communication mid-flight — out of scope; subagents are fire-and-forget with single return.
