---
branch: feat/feature-76-wi-3-remove-vertical-gates
threadId: 019e8723-3a7c-7572-b6a4-ea516865b86d
rounds: 2
final_verdict: ship-as-is
date: 2026-06-02
---

# Codex audit — Feature #76 WI-3 (remove `#vertical` windowing gates, axis-aware primitives)

Independent Codex audit (cc-suite via `scripts/run-codex.sh`, model `gpt-5.5`,
effort `high`, read-only) of WI-3 — the load-bearing WI that removes the
`!this.#vertical` gates from the windowed continuous-scroll path so K=3 windowing
runs for vertical-writing AZW3/MOBI (Bug #283), and generalizes the remaining
windowed primitives over the ScrollModel axis. **Critical invariant: the shipped
+ VERIFIED horizontal-tb (#73) path stays byte-identical.**

- Round 1 session: `019e8723-3a7c-7572-b6a4-ea516865b86d`
- Round 2 session: `019e872d-1304-72a2-b57b-d2cfbeae6c5d`

## Scope

- `vreader/Services/Foliate/JS/paginator.js` — 9 gate/hardcode sites (`#ensureWindow`, `#viewRelativeStart`, `#scrollToRect`, `#scrollTo` sign, `#scrollToAnchor`, `#afterScroll`, `#scrollPrev`, `#scrollNext`, `#maybeCrossSectionBoundary`) + new `#axisScrollSize`/`#axisClientSize` helpers + `scrollModelFor` vertical-rl `rectStartProp` + `#getRectMapper`.
- `vreader/Services/Foliate/FoliateScrollModel.swift` (mirror: vertical-rl `rectStartProp`).
- `vreader/Services/Foliate/JS/foliate-bundle.js` (rebuilt).
- `vreaderTests/Services/Foliate/{FoliateScrollModelTests, FoliateVerticalWindowBundleTests}.swift`.

## Round 1 — findings

| Severity | Issue | Resolution |
|---|---|---|
| **High** | `scrollModelFor('vertical-rl')` used `rectStartProp: 'left'`, but under WebKit's negative `scrollLeft` the logical reading-order start of a vertical-rl section is its RIGHT edge — so `#elementAxisStart` (and everything keyed off it) drifted by ~`sectionWidth − clientWidth`. | FIXED — vertical-rl `rectStartProp` → `'right'` in the JS `scrollModelFor` AND the Swift `FoliateScrollModel` mirror; `FoliateScrollModelTests` updated. R2 confirmed first/rightmost section start ≈0, increasing leftward. |
| **Medium** | `#getRectMapper` scrolled branch still keyed on blanket `this.#vertical`, so vertical-lr (directionSign +1) wrongly used the vertical-rl mirror. | FIXED — the scrolled mapper now branches on `#activeScrollModel`: vertical-rl (directionSign<0) mirrors (`size−right`), vertical-lr (directionSign>0) maps non-mirrored (`left+margin`, the horizontal-axis analogue of horizontal-tb), horizontal-tb unchanged. |
| Low | `#scrollTo` compared the raw DOM offset to the logical offset before signing → a vertical-rl no-op seek never short-circuited. | FIXED — the `directionSign` sign is applied BEFORE the early-return compare. |
| Low | Tests didn't pin `#viewRelativeStart`/`#scrollToRect`/`#scrollToAnchor`/`#afterScroll` or the vertical-rl right-edge. | FIXED — `FoliateVerticalWindowBundleTests` extended to 11 tests. |

## Round 2 — verification

**R1 High + Medium resolved in code.** Auditor confirmed:
- vertical-rl uses `rectStartProp: 'right'` (source + bundle); the `#elementAxisStart` math is correct.
- vertical-lr keeps `'left'`; the non-mirrored rect mapper is consistent with directionSign +1.
- **horizontal-tb is byte-identical across all WI-3 sites** (model stays scrollTop/height/top/+1, so the helper substitutions collapse to the old expressions); `#scrollTo` horizontal compare unchanged.

The only round-2 "High" was the working-tree observation that `FoliateVerticalWindowBundleTests.swift` was untracked while `project.pbxproj` referenced it — a staging artifact, resolved by committing the file together with the project change (done in this WI's commit).

## Verdict

**ship-as-is.** Build + all affected suites GREEN: `FoliateVerticalWindowBundleTests` 11, `FoliateScrollModelTests` 6, `FoliateScrolledWindowMathTests` 19, `FoliatePaginatorScrollBoundaryTests` 15, `FoliateVerticalContainerLayoutTests` 5. Horizontal regression device-verified on mini-azw3. **Vertical-writing behavior (the new capability) is audit-clean + unit-tested; its DEVICE verification on a real vertical-rl book is WI-5** (no vertical-rl AZW3 DebugBridge seed exists; the real `被讨厌的勇气.azw3` needs sim-transfer) — the planned WI-3/WI-5 split.
