---
branch: feat/feature-70-wi-4-foliate-wiring
threadId: 019e3f56-8dec-7aa0-be5e-1b254373f374
rounds: 3
final_verdict: ship-as-is
date: 2026-05-19
---

# Codex audit log — Feature #70 (GH #491) WI-4 — first-time AZW3/MOBI font-size wiring

Gate 4 (implementation audit) of the 6-gate feature workflow. Independent
auditor: Codex MCP, thread `019e3f56`. Read-only sandbox. 3 rounds (the
Gate-4 cap).

Audited diff: `vreader/Views/Reader/FoliateSpikeView.swift`,
`vreaderTests/Views/Reader/FoliateSpikeThemeCSSTests.swift`.

## Round 1 findings

0 Critical / 0 High / 1 Medium / 1 Low. Codex confirmed the scope checks
passed (early-return removed, layout/theme diffed independently;
`themeCSS(for:)` matches the approved helper shape; `Coordinator.init`
source-compatible via a defaulted `initialThemeCSS`; `setStyles` payloads
escaped via `FoliateJSEscaper.escapeForJSString`; theme colors/font-family
not wired; no out-of-scope files touched).

| # | Severity | Finding | Resolution |
|---|---|---|---|
| 1 | Medium | Pre-ready font-size race: `updateUIView` stored the latest `themeCSS` only in `coordinator.currentThemeCSS` while not-ready; the `book-ready` iife snapshotted `currentThemeCSS` into its JS string BEFORE `await readerAPI.init({})`. A font-size change landing during the init window would be lost — the iife applied the stale snapshot, and no later `updateUIView` diff fired (`currentThemeCSS` already held the newest value). | Mirrored the `window.__vreaderTargetFlow` layout-flow solution: `updateUIView`'s themeCSS branch always stashes the calibrated CSS into a JS-side global `window.__vreaderTargetThemeCSS`; the `book-ready` iife seeds that global before `await init` and reads it AFTER the await for `setStyles` — so a mid-init change updates the global and the resuming iife picks up the freshest value. |
| 2 | Low | The WI-4 tests covered the pure helper / calibration / escaper in isolation but not the bridge seams. | Extracted a pure static `Coordinator.setStylesJS(forCSS:)` helper (escapes via `FoliateJSEscaper.escapeForJSString`), used by `updateUIView`'s ready path; added 4 tests — `Coordinator` seeds `currentThemeCSS` from `initialThemeCSS`, the default is nil (source-compat), `setStylesJS` builds an escaped call carrying the calibrated size, `setStylesJS` escapes hostile CSS. |

Round-1 verdict: follow-up-recommended.

## Round 2 re-review

Codex confirmed the round-1 Low resolved and the larger init-window race
reduced, but found a **narrower residual Medium**:

| # | Severity | Finding | Resolution |
|---|---|---|---|
| 3 | Medium | A font-size change landing AFTER the `book-ready` iife reads `window.__vreaderTargetThemeCSS` (post-`await init`) but BEFORE native flips `isBookReady` on `layout-ready` would still be lost — `updateUIView` took the pre-ready stash-only branch, no later SwiftUI diff guaranteed. | The `layout-ready` handler now, right after `isBookReady = true`, force-applies one `setStyles` of the freshest `currentThemeCSS` (which `updateUIView` keeps current on every diff). Whatever value landed in the post-init/pre-ready window is reconciled at the ready transition. `setStyles` is idempotent. Added `layoutReadyFlipsReadyAndPreservesThemeCSS`. |

Round-2 verdict: follow-up-recommended.

## Round 3 re-review

Codex confirmed the round-2 residual Medium is resolved: the `layout-ready`
reconcile closes the remaining window — `updateUIView` keeps `currentThemeCSS`
current, and `case "layout-ready"` flips `isBookReady` then immediately
reapplies the freshest CSS via `Coordinator.setStylesJS(forCSS:)`.
`handleMessage` is `@MainActor` so `webView` access stays on the correct
actor; the reapplied payload is `FoliateJSEscaper`-escaped. The added test is
aligned with the fix. No new Critical/High/Medium issues.

Round-3 verdict: **ship-as-is**.

## Outcome

Zero open Critical/High/Medium findings after 3 rounds (the Gate-4 cap).
Gate 4 passes for WI-4.
