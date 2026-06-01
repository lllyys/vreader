---
branch: feat/feature-76-wi1b-js-scrollmodel
threadId: codex-exec-gpt-5.5-20260601
rounds: 1
final_verdict: ship-as-is
date: 2026-06-01
---

# Codex Audit — Feature #76 WI-1b (JS getDirection → ScrollModel mirror)

## Scope

Additive JS half of WI-1 in vendored `paginator.js`: `getDirection` also returns
`writingMode`; a `scrollModelFor(writingMode)` helper mirrors the merged Swift
`FoliateScrollModel.scrolled(writingMode:)`; the `View` class stores `#scrollModel`
+ exposes a getter. No consumer yet (WI-3 consumes it). Intent: ZERO runtime
behavior change; Feature #73's horizontal-AZW3 windowed scroll byte-unchanged.
`foliate-bundle.js` regenerated via `build-bundle.sh` (esbuild 0.28.0).

Files: `vreader/Services/Foliate/JS/paginator.js`, `…/foliate-bundle.js` (built).

## Round 1 — findings

Codex (gpt-5.5, read-only). **No findings.**

- `getDirection` behavior-neutral: all call sites destructure named props; the
  extra `writingMode` doesn't affect `{vertical, rtl}` or `beforeRender`.
- `scrollModelFor` matches the Swift table exactly (horizontal-tb/default,
  vertical-rl −1, vertical-lr +1).
- `#scrollModel` default (`horizontal-tb`) safe; overwritten on every `View.load`.
- No runtime path consumes `View.scrollModel` → #73 unaffected in effect.
- Getter on the correct (View) class; no shadowing/typos; bundle reflects source.

## Test evidence

- `FoliatePaginatorScrollBoundaryTests` (15) — source↔bundle parity guard +
  boundary assertions GREEN (proves the rebuilt bundle matches source + #73
  boundary behavior holds).
- `FoliateScrolledWindowMathTests` (19) + `FoliateScrollModelTests` (6) GREEN.
- esbuild built cleanly (syntactically valid bundle).

## WI tier

**Foundational** — additive seam, no runtime behavior change, #73 untouched in
effect (Codex-confirmed). Per rule 47 Gate 5, merges on unit/parity tests +
audit; the behavioral device verification is WI-5 (when WI-3 makes the windowing
consume the model). Consistent with WI-1a + the #1322 seam.

## Verdict

ship-as-is (zero findings).
