---
branch: feat/feature-42-wi13-acceptance
threadId: 019e73fa-d5ed-7f93-944e-e109d82f72ff
rounds: 2
final_verdict: follow-up-recommended
date: 2026-05-29
---

# Codex Audit Log — Feature #42 WI-13 (Phase-1 acceptance pass, GH #1234)

Change: the WI-13 acceptance verification for the Readium EPUB engine (flag
default-OFF, FORCED ON for this run). Adds 3 corpus EPUB fixtures
(`mini-{epub2,rtl,cjk}.epub`) + catalog entries, a 2-file XCUITest acceptance
suite, DebugBridge-helper command wrappers, an evidence file (`result: partial`),
and a tracker reconcile (#42 stale PLANNED → IN PROGRESS). No production reader
code touched (DebugFixtureCatalog is DEBUG-only).

Model: gpt-5.5 via `codex exec --sandbox read-only` (cc-suite path, not the MCP
bridge — per MEMORY). Author/auditor separation preserved (Claude authored; Codex
audited as a separate process).

## Scope of audit

- Corpus-fixture validity (EPUB2 OPF2.0+NCX / RTL page-progression-direction /
  CJK vertical-rl) — parseable under the Readium streamer.
- Acceptance-suite host-vs-runner correctness (bug #242/#1054: no in-runner
  bridge calls asserted as working; bridge-dependent cases `XCTSkipUnless`).
- Criterion-coverage honesty (no vacuous passes).
- No flaky waits (settle-sentinel poll, not bare sleep).
- Fingerprint-key format vs `DocumentFingerprint.canonicalKey`.
- Tracker reconcile consistency with `result: partial`.

## Round 1 (4 Medium + 1 Low) — all fixed

- **M1** `test_c2_position_saveRestore` used the legacy-only `navigate?spine=N`
  (not observed by the Readium host) → would not exercise Readium save/restore.
  FIX: search-driven nav to the ch2-only token `filler`, reopen the SAME book
  WITHOUT a `reset`, assert `location.href` ends with `chapter2.xhtml`.
- **M2** `test_c9_navigation_spineChanges` same `navigate?spine` dependency.
  FIX: cross-spine via search (`filler`→ch2, `verifiableneedle`→ch1), assert
  `location.href` flips.
- **M3** `test_c5_searchNavigatesToResult` searched a ch1 token (= already-open
  spine) → vacuous pass. FIX: search the ch2-only `filler` from a fresh ch1
  open, assert navigation INTO chapter2.xhtml.
- **M4** `test_c4_highlightRestore_countPersists` was vacuous (never seeded a
  highlight, accepted `>= 0`). FIX: renamed `test_c4_highlightSnapshotWiring`,
  no longer claims restore, asserts exact `highlightCount == 0` for a fresh open
  (= the field is genuinely reported, not nil-coalesced); create+restore are
  unit-covered (documented in the test doc).
- **Low-1** c3 font assertion was `> 0`. FIX: tight `[22, 26]` band (≈24pt).

Also removed the now-unused `navigate`/`present` helper methods from
`VerificationDebugBridgeHelper.swift` (no dead code); added `evalHref()` /
`hrefSpine()` helpers; changed c8 to assert `document.body` transparency (the
layer that IS transparent under `theme=photo`; full `html:root` transparency is
custom-image-gated, documented).

## Round 2 — verdict follow-up-recommended (zero open Critical/High/Medium)

Round 2 confirmed M1–M4 + Low-1 resolved, fixtures valid, host-vs-runner correct
(`XCTSkipUnless(bridgeReachable())` on every bridge-dependent case), tracker
reconcile consistent with `result: partial`, eval-href helpers correct for the
`readium://.../chapterN.xhtml` shape, and c8 body-assertion matches the evidence
note. Two residual Low — both fixed:

- **R2-Low-A** c3 font band only asserted inside `if let px = NSNumber?` → a nil
  eval would silently pass. FIX: `try XCTUnwrap` so a nil/non-numeric eval FAILS
  explicitly.
- **R2-Low-B** the features-suite file-header prose still said "RESTORE is
  exercised here via a persisted highlight's snapshot `highlightCount`" (stale
  after M4). FIX: header reworded — restore is unit-covered; the suite only
  asserts the snapshot-field wiring CU-free.

## Acceptance bar (rule 47 Gate 4)

Zero open Critical/High/Medium after round 2; both round-2 Lows fixed. Verdict
`follow-up-recommended` ∈ {ship-as-is, follow-up-recommended} → Gate-4 clean.
