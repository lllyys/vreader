---
branch: feat/feature-76-wi-2-container-axis-layout
threadId: 019e8705-06d8-7153-a223-74002f91292e
rounds: 2
final_verdict: ship-as-is
date: 2026-06-02
---

# Codex audit — Feature #76 WI-2 (axis-aware scrolled container layout)

Independent Codex audit (cc-suite via `scripts/run-codex.sh`, model `gpt-5.5`,
effort `high`, read-only) of WI-2: the scrolled-mode `#container` now lays out
sections along the active scroll axis (`#applyScrolledContainerAxis`) so the
windowed surface (WI-3) accumulates in the right direction for vertical-writing
AZW3/MOBI. Horizontal-writing (#73) stays byte-identical.

- Round 1 session: `019e8705-06d8-7153-a223-74002f91292e`
- Round 2 session: `019e870c-9ac5-7b93-a4c0-c5279f83491e`

## Scope

- `vreader/Services/Foliate/JS/paginator.js` (`#applyScrolledContainerAxis` + call in `#display` and the `flow` `attributeChangedCallback`)
- `vreader/Services/Foliate/JS/foliate-bundle.js` (rebuilt via `build-bundle.sh`)
- `vreaderTests/Services/Foliate/FoliateVerticalContainerLayoutTests.swift` (new, 5 source↔bundle contract tests)

## Round 1 — findings

| Severity | Issue | Resolution |
|---|---|---|
| **High** | `flexDirection: row-reverse` for `directionSign < 0` DOUBLE-reverses vertical-rl, because the host already forces `dir=rtl` for every vertical book (`paginator.js:~1146`, incl. vertical-lr) and `direction` inherits into the shadow tree; vertical-lr was also mismatched (forced rtl despite `directionSign:+1`). | FIXED — the helper now sets `flexDirection: 'row'` (plain) + an EXPLICIT `direction = directionSign < 0 ? 'rtl' : 'ltr'`, and resets `direction` too in the horizontal-writing branch. Round 2 confirmed this matches `#axisScrollOffset`'s sign handling for both vertical-rl (negative scrollLeft) and vertical-lr; the container direction governs flex-child order without affecting iframe document contents. |
| **Medium** | A paged→scrolled `flow` switch re-rendered but never applied the layout, so a vertical book could enter scrolled mode block-stacked until the next navigation. | FIXED — `attributeChangedCallback('flow')` now calls `if (this.scrolled && this.#view) this.#applyScrolledContainerAxis()` after `render()` and before `#ensureWindow()`. Round 2 confirmed placement/gating. |
| **Low** | The reset test only checked for any `removeProperty`, and didn't inspect the bundle body. | FIXED — asserts `removeProperty('display'/'flex-direction'/'direction')` in BOTH source and bundle, quote-agnostic (esbuild rewrites to double quotes). |

## Round 2 — verification

HIGH + MEDIUM confirmed **resolved**. Two minor new findings:

| Severity | Issue | Resolution |
|---|---|---|
| Medium | The new test file was untracked while `project.pbxproj` referenced it (working-tree-only observation). | Non-issue — the file is committed together with the pbxproj change in this WI's commit. |
| Low | The ordering test matched the flow-callback call first (both call sites are correct, but `#display`'s ordering was under-pinned). | FIXED — the test now scopes the before-`#ensureWindow` ordering assertion to the extracted `#display` body specifically. |

## Verdict

**ship-as-is.** Build + 5 WI-2 tests + existing Foliate parity suites
(`FoliatePaginatorScrollBoundaryTests` 15/15, `FoliateTapToleranceBundleTests` 4/4)
GREEN; the horizontal-writing #73 path is byte-identical (the vertical-axis branch
leaves no inline style). WI-2 is the layout substrate; WI-3 removes the
`#ensureWindow` `#vertical` gate, WI-4/5/6 verify (incl. the large-CJK memory gate).
