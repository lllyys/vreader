---
title: session 014jggU2u3f3t6YRoPLS457u-audit · 2026-07-11
updated: 2026-07-11
status: logbook
session: 014jggU2u3f3t6YRoPLS457u-audit
transcript: ""
---

## [2026-07-11T00:45+08:00] session 014jggU2-audit — canon repair, verification, and Codex audit-fix

**Intent.** Repair, complete, and independently audit the 36 codebase dossiers compiled
by the 2026-07-10 survey (see [[session 014jggU2u3f3t6YRoPLS457u · 2026-07-10]]): fix the
provenance corruption, verify every page under an uncapped evidence schema, build the
coverage and relationship ledgers, then run the cc-suite Codex (gpt-5.6-sol) audit-fix
loop for factual accuracy AND full-codebase coverage. Plan (Codex-reviewed, 3 rounds):
dev-docs/plans/20260711-canon-codebase-compile-audit.md.

**Context — incident being repaired.** The 2026-07-10 survey workflow's harness
delivered script arguments as a JSON string, so template values rendered as literal
`undefined`: 30 pages got `Sources [[undefined]]`, 8 got `updated: undefined`, 4 got a
`Verified` line dated `undefined`. Additionally, the 07-10 minute recorded
`_compile-state.json` and `_verify.json` as created when they had not yet been written —
that discrepancy is corrected by THIS phase actually creating them. The 07-10 minute is
closed history and stays untouched; this second minute for the same working session is a
user-approved deviation from one-session-one-file (approval 2026-07-11, Gate H2).

**Decisions.**
- Composite dossiers (one page per module, page-level trust tier) approved by the user
  (Gate H1) — implies dossier **Decision — composite dossier schema**.
- All 36 pages re-verified under an uncapped structured-evidence schema; the 11
  cap-limited 07-10 verifier returns are superseded.
- Coverage is ledger-driven: per-file coverage rows + a mechanically extracted
  relationship edge ledger; Codex verdicts land per row, not as prose.

**Changes.**
- canon/* dossiers (repair + verification edits; see backlinks)
- canon/decisions/composite-dossier-schema.md (new)
- canon/_coverage-manifest.md (v2), canon/_coverage-ledger.json,
  canon/_edge-ledger.json, canon/_verify.json, canon/_compile-state.json
- canon/architecture/system-overview.md, canon/modules/test-architecture.md (new)

**Codex audit-fix outcome (appended at finalization).**
11 sequential `codex exec` calls (gpt-5.6-sol via cc-suite's `codex-runner.mjs`, read-only
sandbox; C2-E onward at effort `low` per user request, earlier calls at `high`):

- **C1a/C1b** (coverage, 2 calls): 34 dossier-ownership/level ledger corrections + 21
  coverage-gap findings across 20 dossiers. All fixed via a 20-agent parallel fix window
  before C2 began (per the plan's resequencing — coverage settles before accuracy audits
  run against a moving corpus).
- **C2-A..E** (accuracy, 6 calls, 39 dossiers audited — every non-canonical page exactly
  once): 85 factual findings (19 High, 41 Medium, 25 Low) across 27 dossiers. Notable
  finds: `PersistenceActor` is not actually a single globally-serialized writer in
  production (views construct their own instances); the text-mapping `OffsetMap` layer
  is built but not wired into any live reader; a WebDAV blob-store MOVE-412 race can
  leave a mismatched blob silently reported `.alreadyExists`; the diagnostics redactor
  misses single-quoted secret values; library tag/series filtering silently no-ops;
  book-source chapter caching never activates in production (no call site passes a
  cache). All 85 findings fixed — 22 dossiers via a parallel fix batch run concurrently
  with the tail of the Codex chain, the remaining 5 (C2-E's automation-tooling,
  composite-dossier-schema, six-gate-lane-dispatch, bug-history, feature-history) via a
  16-agent batch alongside the C3 relationship fixes.
- **C3a/C3b** (relationship closure, 2 calls): resolved 77 of the mechanically-extracted
  `_edge-ledger.json`'s 116 rows — 66 confirmed `represented` (the grep extractor had
  under-paired real edges), 1 `dead-code-candidate` (`TOCProviding` protocol: zero
  conformers or consumers anywhere in the repo), 10 JS-bridge rows reclassified from one
  coarse aggregate into precise per-file conformer/producer pairings (`EPUBBilingualJS`/
  `FoliateBilingualJS`/`ReadiumBilingualCommander`/`ReadiumBilingualEvalAdapter` are
  script generators, not `WKScriptMessageHandler` conformers), 14 newly-discovered edges
  (5 protocol seams, 3 persistence boundaries, 3 JS-bridge relationships, 1 Swift↔Kotlin
  Locator non-finite-handling divergence). All written into the ledger (now 141 rows) and
  into 11 dossiers.
- **One operational incident**: Codex failed session-wide after C2-D2b (2 clean failures
  on C2-E including a diagnosed retry, confirmed via a trivial diagnostic probe as an
  external outage, not a prompt or wrapper defect); recovered ~20 min later, chain
  resumed with no data loss.

**Final state**: 33 factual (`module`/`architecture`) dossiers `verified` with full
uncapped evidence, 1 interpretive hub (`system-overview`) + 5 interpretive
(`decisions`/`timeline`) pages `proposed` by design, 1 `canonical` (pre-existing, AI
never wrote this tier). Coverage ledger: 4,621 files, zero unmapped. Press/health green
throughout every structural gate.

**Open threads.**
- Human review pass (`bureau:review`) to promote vetted dossiers to `canonical`.
- Acknowledged residuals (not silently dropped, named for a future pass): `archive/plans/`,
  `dev-docs/plans/`, `dev-docs/verification/` remain genuinely mixed-content directories
  (bug-plan and feature-plan files interleaved) not yet split file-by-file; `docs/features.md`'s
  127-row count is arithmetic (130 IDs − 3 named gaps), not an independently re-parsed
  table count — noted in-page as needing re-verification against the live tracker.

**Source.** transcript (Claude Code session 014jggU2u3f3t6YRoPLS457u, audit phase)
