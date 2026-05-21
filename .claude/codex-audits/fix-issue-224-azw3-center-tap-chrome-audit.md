---
branch: fix/issue-224-azw3-center-tap-chrome
threadId: 019e4a65-d10f-7240-9a62-e2c4fd0133bd
rounds: 2
final_verdict: ship-as-is
date: 2026-05-21
---

# Codex audit — Bug #108 REOPEN / GH #224 (AZW3 center-tap chrome toggle)

## Scope

Files audited:
- `vreader/Services/Foliate/JS/foliate-host.js` (source — the content-tap
  handler + new `mapTapToHostViewport` helper)
- `vreader/Services/Foliate/JS/foliate-bundle.js` (esbuild output)
- `vreader/Views/Reader/ReaderTapZoneRouter.swift` (consumer of `{x,w}`)
- `vreader/Views/Reader/FoliateSpikeView.swift` (Swift `tap` case)
- `vreaderTests/Services/Foliate/FoliateHostTapCoordinateTests.swift`
  (regression guard)

## Root cause (device-confirmed)

In paginated mode foliate-js renders a section as a 2-column page inside an
iframe ~2× the screen width and pages by shifting that iframe horizontally via
the iframe element's `left` (e.g. `left: -359` over a 402px host viewport) to
reveal one column at a time. The Bug #239 fix (`bd7564c7`) made the content-tap
handler post `{x: event.clientX, w: documentElement.clientWidth}`. But
`event.clientX` is in the iframe's internal coordinate space (0..748) while
`documentElement.clientWidth` is a single column's width (374). So
`ReaderTapZoneRouter` computed `x/w ∈ ~1.0..2.0` on right-column pages and
classified center taps as right-zone → `.readerNextPage` instead of
`.readerContentTapped`. The toolbar never toggled. EPUB is unaffected (renders
in the top-level document, so its `clientX`/`clientWidth` are host-relative).

## Fix

New `mapTapToHostViewport(doc, clientX)` maps the click back to host-viewport
coordinates: `hostX = clientX + frameElement.getBoundingClientRect().left`,
`hostW = frameElement.ownerDocument.defaultView.innerWidth`. Defensive paths:
no `frameElement` → use `documentElement.clientWidth` (top-level case);
unusable host width / cross-origin throw → return `null` → caller posts bare
`tap` (chrome-toggle, the safe default).

## Round 1 — 2 Low findings (both fixed)

| File:line | Severity | Issue | Resolution |
|---|---|---|---|
| `foliate-host.js:190-192`, `foliate-bundle.js:6637-6639` | Low | `hostW` fell back to `frameEl.getBoundingClientRect().width` (the WIDE iframe), silently re-mixing coordinate spaces if `hostWin.innerWidth` were falsy instead of taking the safe bare-`tap` fallback. | **Fixed** — removed the iframe-width fallback; `hostW = hostWin && hostWin.innerWidth`, and `if (!isFinite(frameLeft) || !isFinite(hostW) || hostW <= 0) return null`. Bundle rebuilt. |
| `FoliateHostTapCoordinateTests.swift:93-170` | Low | Test was a scoped string/token check whose sampled region included explanatory comments — could pass even if executable code regressed while the comment still mentioned `frameElement`/`getBoundingClientRect`/`ownerDocument`. | **Fixed** — added `stripComments()` so matches are executable-only; assertions now pin executable patterns (`clientX + frameLeft`, `ownerDocument.defaultView`, `innerWidth`); added `sourceTapHandlerDoesNotPostRawClientCoords` asserting the post uses `{ x: mapped.x, w: mapped.w }` not the raw `{ x: x, w: w }`. |

## Round 2 — verification

**No findings. Verdict: ship-as-is.** Codex confirmed:
- The iframe-width fallback is gone; the `null`-return safe path is correct.
  `isFinite(undefined)` is `false`, so `hostW` undefined → `return null` →
  caller posts bare `tap` (preserves chrome-toggle).
- Bundle parity correct — same logic, no width fallback reintroduced.
- The test now genuinely guards executable code (comments stripped), pins both
  source and built bundle, and the extra test catches the regression shape.
- No new issues introduced.

Codex also confirmed in round 1 (carried forward):
- `hostX = clientX + frameRect.left` is the correct transform; sign is correct
  (right-column page has negative `left`); direction-agnostic for RTL (relies
  on the actual signed frame offset).
- No double-fire / duplicate-listener risk — listener lifecycle unchanged (one
  `click` listener per `load`, one `post('tap')` path per click).
- Variable shadowing resolved (`docWin` ≠ module-level `view`).

## Summary

Two-round audit, all findings fixed, final verdict **ship-as-is**. The fix is a
JS-side coordinate-space correction with safe defensive fallbacks; the bundle
was rebuilt from source via `build-bundle.sh`; the regression guard pins both
source and bundle with executable-pattern (comment-stripped) assertions.
