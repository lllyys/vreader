---
title: ADR 0001 — Adopt bureau
updated: 2026-07-10
status: canonical
sources: []
---

# ADR 0001 — Adopt bureau

**Context.** AI sessions are unrecorded meetings; natural-language docs drift, go stale,
and contradict each other. We want one consistency-checked canon a human can inspect.

**Decision.** Capture each session to an append-only [[Logbook]]; compile it into
consistency-checked dossiers (the SSOT); render with the press. The logbook is
low-authority but faithful; the cabinets are authoritative for current truth and carry
provenance back to the logbook.

**Consequences.** Drift is fought structurally: one owned layer, mechanical render,
every claim traceable to its origin session.
