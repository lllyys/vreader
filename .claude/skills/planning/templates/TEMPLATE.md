# Codex Plan Template

Use this template for `full-plan` mode.

---
title: "<topic>"
created_at: "<YYYY-MM-DD HH:MM local>"
mode: "full-plan"
---

## Outcomes

- Desired behavior:
- Constraints:
- Non-goals:

## Constraints & Dependencies

- Runtime/toolchain versions:
- OS/platform assumptions:
- External services:
- Required environment variables / secrets:
- Feature flags:

## Current Behavior Inventory

- Entry points:
- Data flow:
- Persistence:
- Known invariants:

## Target Rules

List explicit rules with precedence. Each rule should include trigger/context, expected behavior, scope, exclusions, failure modes.

## Decision Log

- D1:
  - Options:
  - Decision:
  - Rationale:
  - Rejected alternatives:

## Open Questions

- Q1:
  - Why it matters:
  - Who decides:
  - Default if unresolved:

## Data Model (if applicable)

- Tables/keys/columns:
- Versions:
- Compatibility:

## API / Contract Changes (if applicable)

- Tool/schema changes:
- Backward compatibility:
- Versioning strategy:

## Observability (if applicable)

- Metrics:
- Logs:
- Debug toggles:

## Work Items

### WI-001: <short name>

- Goal:
- Acceptance (measurable):
- Tests (first):
  - File(s):
  - Intent:
- Touched areas:
  - File(s):
  - Symbols:
- Dependencies:
- Risks + mitigations:
- Rollback:
- Estimate: S/M/L

## Testing Procedures

- Fast checks:
- Full gate:
- When to run each:

## Rollout Plan (if applicable)

- Feature flags:
- Staging steps:
- Kill switch / revert steps:

## Manual Test Checklist

- [ ] …

