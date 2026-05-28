---
branch: feat/feature-71-wi-6b-i-live-rendering
threadId: 019e6726-105c-7571-8dbe-b300c718e3da
rounds: 3
final_verdict: ship-as-is
date: 2026-05-27
---

# Codex Audit — Feature #71 WI-6b-i (EPUB continuous scroll: live rendering core)

Gate-4 implementation audit of `git diff main` for WI-6b-i. Author = implementing
Claude session; auditor = Codex MCP (separate process — author/auditor separation
satisfied). 3 rounds (rule-47 max), terminal verdict **ship-as-is**.

## Scope of the diff

- `vreader/Views/Reader/EPUBContinuousScrollCoordinator.swift` — new `materializeInitialWindow()` (append anchor + extend ±1, same stale-generation / failed-eval abort posture as `extend`).
- `vreader/Views/Reader/EPUBContinuousScrollBridge.swift` — `EPUBContinuousScrollConfig` gains `handle` (late-binding evaluator) + `onWindowedPosition`; struct now `#if canImport(UIKit)`-gated; the pure `parse` extension stays ungated.
- `vreader/Views/Reader/EPUBWebViewBridge.swift` — `makeUIView` binds `handle.webView`; `updateUIView` loads a file-backed bootstrap once; `loadContinuousBootstrap` helper.
- `vreader/Views/Reader/EPUBWebViewBridgeCoordinator.swift` — `didLoadContinuousBootstrap` flag; `didFinish` continuous branch → `materializeInitialWindow`; `handleContinuousScrollMessage` fires `onWindowedPosition`.
- `vreader/Views/Reader/EPUBReaderContainerView.swift` — `@State continuousScrollConfig`; `buildContinuousScrollConfig` (flag-gated); mode-aware `onProgressChange`; one-way mode-switch retirement; passes `continuousScroll:` to the bridge.
- `vreader/Services/FeatureFlags.swift` — `FeatureFlagKey.epubContinuousScroll` (ships dark, persisted-overridable).
- `vreaderTests/Views/Reader/EPUBContinuousScrollCoordinatorTests.swift` — 4 `materializeInitialWindow` tests.

## Round 1 findings

| file:line | severity | issue | resolution |
|---|---|---|---|
| EPUBWebViewBridge.swift:290 | Critical | Early `return` in the continuous branch skips later `contentURL`/seek/`pendingJS`/theme updates, so chapter navigation (TOC/bookmark/search) no-ops. `.scroll` is the **default** user-selectable EPUB layout → shipping this regresses the default reading mode. | **FIXED via flag-gate.** Added `FeatureFlagKey.epubContinuousScroll` (default false). `buildContinuousScrollConfig` guards on it, so the live default `.scroll` keeps the legacy single-chapter path verbatim — zero regression. Continuous (with its known-incomplete navigation, deferred to 6b-ii/iii) is only reachable with the flag overridden on. User explicitly chose the dark-flag approach over folding 6b-iii forward. |
| EPUBWebViewBridge.swift:296 | High | `currentURL = contentURL` in the bootstrap branch conflates "bootstrap loaded" with "chapter loaded" → a scroll→paged switch skips `loadFileURL` and leaves the stitched bootstrap alive in paged mode. | **FIXED.** Removed the assignment. `currentURL` stays unchanged in continuous mode, so leaving continuous → paged sees `currentURL != contentURL` and force-reloads the real chapter, wiping the bootstrap. |
| EPUBReaderContainerView.swift:503 | High | `linkedStylesheetLoader` resolves `relativeHref` against the OPF base, not the chapter directory → nested chapters with cross-dir `<link href="../css/x.css">` miss CSS. | **DEFERRED (accepted).** The merged + Gate-2-audited WI-6a provider seam passes only the bare `relativeHref` (no chapter context); a correct fix requires changing that seam → tracked as WI-6b-ii follow-up. Documented inline. Correct for flat EPUBs / fixtures; not user-reachable while continuous ships dark. Codex round 2 downgraded this from blocker to deferred debt. |

## Round 2 findings

| file:line | severity | issue | resolution |
|---|---|---|---|
| EPUBWebViewBridge.swift:290 | High | High #2 only fixed scroll→paged. The round-trip scroll→paged→scroll leaves `didLoadContinuousBootstrap == true`, so re-entering scroll returns without reloading → stuck on the old paged single-chapter doc. | **FIXED via one-way hard-block.** Added `.onChange(of: epubLayout)` that invalidates + nils `continuousScrollConfig` when leaving `.scroll`. Config is built only in the open `.task`, so it's never rebuilt mid-open; re-entering `.scroll` lands on legacy single-chapter scroll, not a stale stitched doc. Full live mode-switch teardown is WI-6b-iii. Matches Codex's "keep mode switching out of scope and hard-block" option. |

Round 2 also confirmed: flag-gate is a sound resolution to the Critical; High #3 acceptable to defer given the dark-flag posture.

## Round 3

Codex verdict (verbatim summary): the one-way retirement closes the bidirectional
mode-switch hole — continuous is never rebuilt during the same open, `invalidate()`
cancels stale in-flight coordinator work, and the `currentURL` behavior guarantees
the first switch out of continuous reloads the real chapter DOM. **"No remaining
Critical, High, or Medium findings in the current `git diff main` for WI-6b-i."**

## Verdict

**ship-as-is.** Zero open Critical/High/Medium. One residual Low/deferred item
(linked-stylesheet chapter-relative resolution) tracked as WI-6b-ii follow-up debt,
acceptable while continuous ships dark behind `FeatureFlags.epubContinuousScroll`.
