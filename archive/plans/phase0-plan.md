# Phase 0 Implementation Plan (Codex-reviewed)

**Date**: 2026-03-16
**Status**: APPROVED after Codex review corrections
**Scope**: 11 WIs — architectural foundation + performance + dual-mode scaffold

## Codex Review Corrections Applied

1. F01 scoped to close/background/session — `open()` stays format-specific (different race guards per format)
2. F10 PDF tests changed to negative tests (prove PDF stays Native)
3. F05 narrowed: encoding sample + defer indexing. "Load visible chunks first" deferred to Phase B
4. F06 bumped to L — needs disk DB lifecycle, segmentBaseOffsets persistence, corruption recovery
5. F09 bumped to L — needs migration strategy for existing locators/anchors
6. F02 capabilities made context-aware: `capabilities(engine:contentComplexity:)` not just per-format
7. F05+F06 co-designed in same sprint — indexing deferral depends on persistent index design

## Sprint Plan

**Sprint 1** (6 WIs, parallel):
- F01 (lifecycle coordinator) — M
- F02 (capabilities) — S
- F03 (text source) — M
- F04 (backup protocol) — S
- F09 (locator normalization) — L
- F11 (page navigator) — S

**Sprint 2** (5 WIs, after Sprint 1):
- F05 + F06 together (streaming open + persistent index) — L+L
- F07 (reading mode toggle) — S, depends on F02
- F08 (TextKit 2 spike) — L, start early
- F10 (mode-switch tests) — S, depends on F09

## Effort Corrections

| WI | Plan estimate | Codex-corrected |
|----|--------------|-----------------|
| F05 | M | **L** (needs protocol/VM changes for deferred indexing) |
| F06 | M | **L** (disk DB lifecycle + segmentBaseOffsets + corruption recovery) |
| F09 | M | **L** (needs migration plan for existing data) |

## Implementation Rules

- TDD: RED → GREEN → REFACTOR for every WI
- Commit after each WI passes tests
- No behavior change for existing features
- All 2040+ existing tests must pass after each WI
