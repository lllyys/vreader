---
branch: fix/issue-1268-foliate-tap-tolerance
threadId: codex-exec-readonly
rounds: 3
final_verdict: ship-as-is
date: 2026-05-31
---

# Codex audit — Bug #287 / GH #1268 (AZW3/Foliate highlight tap tolerance)

Read-only `codex exec` audit, 3 rounds (converged clean).

## Fix summary

- Root cause: AZW3/Foliate highlight taps had no tolerance — only foliate-js's
  exact `Overlayer.hitTest` fired `show-annotation`, so a near-miss turned the
  page instead of opening the popover. (The #287 fix covered the other 4
  formats; Foliate was deferred.)
- Foliate renders via our OWN editable JS sources bundled by esbuild
  (`build-bundle.sh`). Fix across 3 source files + rebuilt bundle:
  1. `overlayer.js`: new `hitTestWithTolerance({x,y}, minTarget=44, skipPrefix)`
     — per-rect slop `max(0,(44-dim)/2)`, inclusive expanded edges,
     nearest-center on overlap, skips `skipPrefix` (search) overlays. Mirrors
     Swift `HighlightHitTolerance`. Exact `hitTest` unchanged.
  2. `view.js` `#createOverlayer`: the annotation click handler runs in the
     CAPTURE phase (so it precedes the host's bubble tap handler), tries exact
     then tolerant (`SEARCH_PREFIX`-skipping) lookup, and on a hit sets
     `e.__vreaderAnnotationHit = true` + emits `show-annotation`. Fallback also
     fires when the exact hit is a search overlay (so a real highlight under it
     isn't shadowed).
  3. `foliate-host.js`: its bubble-phase click handler early-returns when
     `event.__vreaderAnnotationHit` is set — absorbing the tap (no
     page-turn/chrome), so the popover is the sole action.

## Files

- `vreader/Services/Foliate/JS/overlayer.js`, `view.js`, `foliate-host.js`
- `vreader/Services/Foliate/JS/foliate-bundle.js` (rebuilt)
- `vreaderTests/Services/Foliate/FoliateTapToleranceBundleTests.swift` (new contract test)

## Round 1 findings

| file:line | severity | issue | resolution |
|---|---|---|---|
| overlayer.js | Low | tolerant bounds upper-exclusive vs Swift inclusive. | Fixed — `<=` on expanded right/bottom. |
| view.js | Medium | tolerant lookup could pick a search overlay then drop it, shadowing a real highlight in tolerance. | Fixed — `skipPrefix` param skips search overlays inside candidate selection. |

## Round 2 findings

| file:line | severity | issue | resolution |
|---|---|---|---|
| view.js | Medium | exact `hitTest` could return a search overlay; fallback only ran on `!value`, so a real highlight under an exact search hit fell through. | Fixed — fallback now also runs when the exact hit `startsWith(SEARCH_PREFIX)`. |

## Round 3

No findings. Confirmed: capture-before-bubble ordering guaranteed (same `doc`,
capture vs bubble); marker persists on the event; search-overlay shadowing
resolved in both exact and tolerant paths; non-annotation taps unchanged; no
esbuild tree-shaking concern.

## Verdict

ship-as-is. Behavior-only (Rule 51 carve-out — the popover already exists, no
new chrome). Tests: `FoliateTapToleranceBundleTests` (source + bundle contract)
+ `FoliatePaginatorScrollBoundaryTests` parity green. JS tap behavior is not
Swift-runnable; the end-to-end "near-miss AZW3 highlight tap opens the popover
without turning the page" is device-verified against the real
`Bei Tao Yan De Yong Qi.azw3` (no AZW3 seed fixture) at the close gate.
