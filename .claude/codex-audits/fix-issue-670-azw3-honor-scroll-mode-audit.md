---
branch: fix/issue-670-azw3-honor-scroll-mode
threadId: 019e2707-b30f-7b70-8d21-3dd119abe676
rounds: 4
final_verdict: ship-as-is
date: 2026-05-14
---

# Codex audit log — Bug #189 (GH #670) AZW3/MOBI ignores reading-mode toggle

## Round 1 findings

| file:line | severity | issue | fix |
|---|---|---|---|
| `vreader/Views/Reader/ReaderContainerView.swift:521` | High | Fix was applied to `FoliateReaderContainerView` (line 189), but the active AZW3 route dispatches to `FoliateSpikeView`. The user-visible bug stays unfixed. | Extend the fix to `FoliateSpikeView` — accept `settingsStore`, push `setLayout` after `readerAPI.init`, mirror EPUB's `scrollView.isScrollEnabled = !isPaged`, support live-toggle via `updateUIView`. **Fixed.** |
| `vreaderTests/Views/Reader/FoliateReaderContainerViewTests.swift:159` | Low | `preference == .paged ? "paginated" : "scrolled"` silently maps unknown future enum cases to `"scrolled"`. | Rewrote as exhaustive switch; added `allCases` assertion. **Fixed.** |

## Round 2 findings

| file:line | severity | issue | fix |
|---|---|---|---|
| `vreader/Views/Reader/FoliateSpikeView.swift:260` | Medium | `isBookReady = true` flipped before `readerAPI.init({})` resolved. A toggle during init pushed setLayout against a not-yet-attached renderer (silently dropped), then the captured stale flow won. | Bundle init+setLayout into one async iife with a JS-side global `window.__vreaderTargetFlow` updated by `updateUIView`; iife reads global post-await for freshest value. **Fixed.** |

## Round 3 findings

| file:line | severity | issue | fix |
|---|---|---|---|
| `vreader/Views/Reader/FoliateSpikeView.swift:284` | Medium | `evaluateJavaScript` completion fires on Promise-creation, not Promise-resolution. Flipping `isBookReady` in the completion still races against the awaited init. | Added new `"layout-ready"` script message handler; iife posts it after init + setLayout actually resolve; native `isBookReady` flip moved into the message handler. **Fixed.** |

## Round 4 findings

No findings. Final verdict: **ship-as-is**.

## Resolution summary

Bug body's proposed fix (one-line edit at `FoliateReaderContainerView.swift:189`) was correct for the future-aspirational path but not the active path. The active fix required:

- Threading `settingsStore` through `ReaderContainerView` → `FoliateSpikeView` → `FoliateSpikeWebView` → `Coordinator`.
- A pure `FoliateLayoutFlowMapper` enum (exhaustive switch over `EPUBLayoutPreference`) shared by both paths.
- A native↔JS readiness handshake (`layout-ready` script message) so `isBookReady` truly reflects renderer attachment, not Promise creation.
- A JS-side mutable global (`window.__vreaderTargetFlow`) so in-flight toggles during init are captured.

All four Codex findings (1 High + 2 Medium + 1 Low across rounds 1–3) fixed before round-4 clean verdict.

## Tests added

- `FoliateLayoutFlowMapperTests` (4 cases — paged, scroll, nil, exhaustive allCases) at `vreaderTests/Views/Reader/FoliateReaderContainerViewTests.swift:152-183`.
- Updated `FoliateSpikeViewTapTests` Coordinator init call to pass `initialLayoutFlow:`.

Test gate: 62/62 Foliate tests across 9 suites pass on iPhone 17 Pro Simulator.
