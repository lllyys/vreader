---
description: Run the gated, agent-driven workflow end-to-end.
argument-hint: "[work-name]"
---

# Feature Workflow (Gated Orchestrator)

Goal: take a high-level plan and drive it to completion using specialized subagents, TDD gates, and explicit acceptance.

## Inputs

- `work-name`: short slug (e.g. `file-mgmt-rebuild-phase0`)
- Optional: an existing plan doc to refine.

## Workflow (always in this order)

1) **Plan (Planner agent)**
   - Create or refine a modular plan in the project docs directory.
   - Break into Work Items with explicit acceptance criteria, tests, and rollback notes.

2) **Spec Check (Spec Guardian agent)**
   - Validate plan vs specs and project rules in `AGENTS.md` and `.claude/rules/*.md`.
   - Stop if specs conflict or constraints are violated.

3) **Impact (Impact Analyst agent)**
   - For each Work Item, map the minimal file set, dependency edges, and risks.
   - Propose the smallest correct change boundaries.

4) **Implement (Implementer agent)**
   - For each Work Item, do a **preflight investigation** before writing tests:
     - Reproduce/describe current behavior and expected behavior.
     - Trace the exact call chain and identify the smallest test seam.
     - Confirm the minimal file impact; update the Impact map if needed.
     - Subagent delegation is encouraged for this "map and report" step.
   - For each Work Item: write the test first (RED), implement (GREEN), refactor safely.
   - Encourage subagent delegation for large/mechanical diffs; always review + run gates after.
   - Keep side effects isolated; keep changes local; keep files under ~300 lines.

5) **Test (Test Runner agent)**
   - Run `pnpm check:all` (and `cargo test` when Rust changes).
   - If UI flows are impacted, request the user to run the app and use Tauri MCP for E2E.

6) **Audit (Auditor agent)**
   - Review diffs for correctness, architecture drift, and rule violations.
   - If issues found: loop back to Implement for fixes.

7) **Manual Test Guide (Manual Test Author agent)**
   - Update manual testing docs incrementally per Work Item.
   - Ensure final “end-to-end” guide exists and is coherent.

8) **Verify (Verifier agent)**
   - Re-run gates as needed; produce a final checklist.

9) **Release (Release Steward agent)**
   - Propose one commit per Work Item with clear messages.
   - Commit only after explicit user “accept + commit”.

## Acceptance Contract

- “Accept” means: tests green, rules satisfied, scope minimal, no known data-loss path introduced.
- If uncertain: stop and ask rather than guessing.
