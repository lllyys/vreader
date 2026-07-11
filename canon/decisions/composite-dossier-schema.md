---
title: Decision — composite dossier schema
updated: 2026-07-11
status: proposed
---

# Decision — composite dossier schema

This workspace's module and architecture dossiers are **claim composites** — one page
per subsystem holding that subsystem's purpose, key types, dependencies, data flow, and
history — rather than the compile skill's default of one atomic claim per page.

Rules that make the composite shape safe:

- A composite page's `status: verified` means a verification pass checked the page's
  claims against the repository and recorded its artifact evidence inline in the page's
  own `**Verified.**` line — it records what a verification pass checked, not a proof
  that every claim is correct. Independent audits remain necessary: the Phase-3 Codex
  audit itself found the "verified" automation-tooling dossier had a wrong hook count
  (claimed 5, actual 6).
- Any substantive edit to a `verified` page (a claim added, changed, or deleted)
  demotes the whole page to `proposed` until a fresh full-page verification passes.
  This demotion-on-edit rule, and the "stays `proposed`" rule below, are proposed
  knowledge-base policy followed by convention in this compile pass — no repository
  hook, script, or CI check currently enforces either.
- A factual page that cannot fully verify stays `proposed` and carries a one-line
  `**Blocked.**` reason; interpretive pages (decisions, timeline, the system-overview
  hub) are `proposed` by design until human review.
- Conflicts still follow the compile skill's contested policy — never silent overwrite.

Rationale: the alternative (~500+ atomic claim pages for a 305K-LOC codebase) would make
human review and maintenance impractical; page-level tiers with whole-page demotion keep
the trust semantics unambiguous at reviewable scale. User approved this deviation
2026-07-11 (plan Gate H1); promotion of this page to `canonical` via bureau:review is
the formal ratification.

**Sources.** [[session 014jggU2u3f3t6YRoPLS457u-audit · 2026-07-11]]
