---
branch: feat/feature-76-wi1-scrollmodel
threadId: codex-exec-gpt-5.5-20260601
rounds: 1
final_verdict: ship-as-is
date: 2026-06-01
---

# Codex Audit — Feature #76 WI-1a (FoliateScrollModel derivation)

## Scope

Foundational Swift type `FoliateScrollModel` deriving the scrolled-mode scroll
model (`axis`, `scrollProp`, `sizeProp`, `rectStartProp`, `directionSign`) from a
section's computed `writing-mode`. Replaces the lossy `{vertical, rtl}`
(vertical-rl vs -lr collapse; axis sign unrecoverable) as the source-of-truth the
vendored `paginator.js` getDirection/ScrollModel will mirror. The `directionSign`
feeds the existing `FoliateScrolledWindowMath.logicalOffset(sign:)` seam (#1322).
Scrolled mode only; no consumer yet (lands ahead of WI-2/WI-3 windowing).

Files:
- `vreader/Services/Foliate/FoliateScrollModel.swift` (NEW — pure value type)
- `vreaderTests/Services/Foliate/FoliateScrollModelTests.swift` (NEW — 6 tests)

## Round 1 — findings

Codex (gpt-5.5, read-only). **No findings.**

Verified:
- Derivation table correct: horizontal-tb → vertical/scrollTop/height/top/+1;
  vertical-rl → horizontal/scrollLeft/width/left/−1; vertical-lr →
  horizontal/scrollLeft/width/left/+1.
- Unknown/empty fallback to the horizontal-tb model is safe — preserves the
  Feature #73 vertical-scroll path.
- `directionSign == -1` for vertical-rl matches WebKit negative `scrollLeft`
  (`logicalOffset(-300, -1) == 300`).
- Test coverage spans the table, unknown/unsupported modes, the sign-integration
  seam, and `isVerticalWriting`.
- Swift value-type / synthesized `Equatable` correct; no dead code.

## Test evidence

`vreaderTests/FoliateScrollModelTests` — 6 tests green (`RUN-TESTS RESULT: SUCCEEDED`).

## WI tier

**Foundational** (pure type, no user-observable behavior, #73 untouched) — per
rule 47 Gate 5, merges on unit tests + audit; no device verification required.
The behavioral consumers are WI-1b (JS getDirection mirror), WI-2 (#container
flex), WI-3 (ScrollModel-aware windowed primitives), device-verified in WI-5 on
the real vertical-writing AZW3 fixture.

## Verdict

ship-as-is (zero findings).
