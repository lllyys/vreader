---
branch: feat/feature-76-wi2-3-windowing
threadId: codex-exec-gpt-5.5-20260601
rounds: 1
final_verdict: ship-as-is
date: 2026-06-01
---

# Codex Audit — Feature #76 WI-3 scaffolding (axis-aware windowed primitives)

## Scope

Parameterize the windowed-scroll primitives in vendored `paginator.js` through an
axis-aware ScrollModel (`#activeScrollModel`, `#axisScrollOffset`,
`#setAxisScrollOffset`, `#elementAxisSize`, `#elementAxisStart`) instead of
hardcoding `scrollTop`/`height`/`top`. Rewrites `#onNeighbourExpand`,
`#evictOutsideWindow`, `#elementScrollTop` (now a pass-through), `#windowedResolve`.

**Intent: ZERO behavior change.** horizontal-tb (#73) model is
`{scrollTop, height, top, +1}`, so every helper reduces to the exact prior
expression. Vertical writing stays GATED (`#ensureWindow`'s `|| this.#vertical`
early-return + the `!this.#vertical` resolve/promote guards are unchanged), so the
vertical branch of the helpers is dead scaffolding — completed later after the
WI-0 on-device measurement of WebKit vertical multicol layout.

Files: `vreader/Services/Foliate/JS/paginator.js`, `…/foliate-bundle.js` (rebuilt).

## Round 1 — findings

Codex (gpt-5.5, read-only). **No findings.** Independently verified:
- `#axisScrollOffset()` ≡ `container.scrollTop`; `#elementAxisStart` ≡ old
  `#elementScrollTop`; `#elementAxisSize` ≡ `rect.height` (the `Math.max(0,…)`
  clamp is a no-op on a non-negative height).
- `#onNeighbourExpand` / `#evictOutsideWindow` / `#windowedResolve` preserve the
  same deltas, comparisons, scroll adjustment, and `(view,index,intra)` selection
  for horizontal-tb.
- `#elementScrollTop` pass-through is correct; callers unaffected.
- Vertical genuinely still gated; no path runs the vertical branch.
- No JS syntax / typo / sign / NaN issues; no path changes #73 runtime behavior.

## Test evidence

- `FoliatePaginatorScrollBoundaryTests` (15) — source↔bundle parity + boundary
  assertions GREEN.
- `FoliateScrolledWindowMathTests` (19) + `FoliateScrollModelTests` (6) GREEN.
- esbuild built cleanly (valid bundle).

## WI tier

Behavior-preserving refactor (no observable change; #73 byte-identical; vertical
gated) → effectively foundational; merges on the parity/unit guards + this audit.
The behavioral vertical slice (ungate + vertical-rl coordinate math) is the
follow-up gated on WI-0 device measurement, device-verified in WI-5 on the real
`Bei Tao Yan De Yong Qi` vertical-writing AZW3.

## Verdict

ship-as-is (zero findings; horizontal-tb byte-identity independently confirmed).
