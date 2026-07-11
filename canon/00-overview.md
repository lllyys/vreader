---
title: Overview
updated: 2026-07-10
---

# Overview

This is a **bureau** workspace — the durable canon distilled from your AI sessions.

- **Cabinets** are the memory drawers (this folder's siblings: `decisions/`, and whatever
  topic drawers you add — `architecture/`, `characters/`, `timeline/`, …). They are the SSOT,
  but **read each claim by its `status:`** — only `canonical` pages are settled fact; the rest
  are proposed, verified-not-approved, stale, or contested (see the trust-tier table below).
- **[[Logbook]]** is the append-only history: *how we know / when it entered*. Low
  authority, faithful record. One entry per session.

Every cabinet claim links back to the minute that introduced it, so the canon is
traceable and regenerable in principle.

## Workflow

| Command | Does |
|---------|------|
| `bureau:note` | take a live note into the running minute (run at decision points) |
| `bureau:file-session` | file the rich minute for the current session |
| `bureau:compile` | distil minutes into dossiers (with provenance) |
| `bureau:review` | the human gate — promote vetted claims to `canonical`, reject the rest |
| `bureau:lint` | semantic consistency sweep across cabinets (contradictions, gaps, drift) |
| `bureau:query` | answer a question from the canon — cited, tier-aware |
| `bureau:status` | what's uncompiled / pending review / stale / contested |
| `bureau:inspect` | build + open the gazette (gazette) |

## Reading this as memory — honor the trust tier

These cabinets double as repo memory, so **no claim is trusted as fact until a human has
approved it**. Every page carries a `status:`; honor it on every recalled claim:

| `status:` | trust | treat as |
|-----------|-------|----------|
| `canonical` | human-approved | **fact** |
| `verified` | checked against the repo, not yet approved | checked, confirm if it matters |
| `proposed` | AI claim, unchecked | **unverified — verify before relying** |
| `stale` | a verified source changed | outdated — re-verify |
| `contested` | two claims disagree | disputed — do not rely |

AI tools write `proposed`/`verified` and `contested` (compile), `contested`/`stale` (lint
`--apply`), and `stale` (review's staleness re-check); only `bureau:review` — a human — writes
`canonical`. Never treat a `proposed`, `stale`, or `contested` claim as fact.
