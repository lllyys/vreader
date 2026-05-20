---
branch: feat/feature-56-wi-13-pdf-translation-panel
threadId: 019e4357-f07b-7050-a3d1-85d0f3c9787c
rounds: 2
final_verdict: ship-as-is
date: 2026-05-20
---

# Codex Gate-4 audit log — feature #56 WI-13 PDF below-page bilingual panel

Independent audit thread: `019e4357-f07b-7050-a3d1-85d0f3c9787c` (Codex MCP, read-only sandbox, cwd `/Users/ll/workspace/vreader/.claude/worktrees/agent-ab963c44458f1bb40`).

The plan-side Gate-2 audit was Codex thread `019e4342-71b3-7930-8ff0-b356e1e7d529` (3 rounds, plan-clean — see plan revision history v5).

## Round 1 — 3 findings

| # | severity | file:line | issue | fix |
|---|---|---|---|---|
| 1 | High | `vreader/Views/Reader/PDFReaderContainerView+Bilingual.swift:90` | Persisted bilingual-on PDFs can open into a permanent `.loading` panel on page 1 / saved page 0 because `ensureBilingualViewModel()` constructs the VM and posts chrome state, but never kicks the initial `handlePositionChange`; the only automatic trigger is `.onChange(of: currentPageIndexNonce)`, which does not fire when the initial page stays `0`. | After constructing a VM whose `isEnabled == true` and `needsSetupSheet == false`, immediately call `triggerBilingualPositionChange()`. Fixed at line 126: `if vm.isEnabled && !vm.needsSetupSheet { triggerBilingualPositionChange() }`. |
| 2 | Medium | `vreader/Views/Reader/ReaderContainerView.swift:314` | `.readerOpenAITranslate` does not clear prior translate-tab state, so the PDF panel's "Open AI tab" affordance can reopen the AI sheet with stale `originalText` / `translatedText` from an earlier selection-driven translation instead of opening the cold Translate tab the plan specifies. | Before `showAIPanel = true`, reset `resolvedAICoordinator.translationViewModel` via the existing `reset()` method. Fixed at line ~320: `if let transVM = resolvedAICoordinator.translationViewModel { transVM.reset() }`. |
| 3 | Low | `vreaderTests/ViewModels/BilingualReadingViewModelRetryUnitTests.swift:99` | The retry suite does not actually cover the Gate-2 M2 "cancel unusual in-flight task before relaunching" branch it claims to cover; all current tests start from an idle VM, so `prefetchTasks.removeValue(forKey:)` + `cancel()` can regress without detection. | Add a blocking spy prefetcher, start a real in-flight task for the unit, call `retryUnit(_:)`, and assert the old task is cancelled and only the fresh task's result is applied. Fixed: `BlockingSpyPrefetcher` (poll-loop variant — avoids the `CheckedContinuation` leak class) + `retryUnit_cancelsInFlightTaskForSameUnit` test. |

Codex round-1 verdict (paraphrased): all 3 are real; `retryUnit(_:)`'s mutation/cancel ordering is safe under `@MainActor`; the `PDFBilingualPanelState.panelState(...)` derivation correctly does NOT read `lastTriggerUnit`; no unsafe interpolation path (translated text is rendered as SwiftUI `Text`, not injected into JS/HTML/CSS).

## Round 2 — clean

Codex confirms all 3 round-1 findings resolved. Verbatim:
> Clean. The 3 round-1 findings are resolved.
> - `vreader/Views/Reader/PDFReaderContainerView+Bilingual.swift:126` now triggers the initial position change on persisted-on reopen via `if vm.isEnabled && !vm.needsSetupSheet { triggerBilingualPositionChange() }`, which closes the "stuck loading on page 0" path without changing first-enable behavior.
> - `vreader/Views/Reader/ReaderContainerView.swift:320` now resets `translationViewModel` before opening `.readerOpenAITranslate`, so the cold Translate tab no longer inherits stale selection/result state.
> - `vreaderTests/ViewModels/BilingualReadingViewModelRetryUnitTests.swift:233` adds a real in-flight cancellation regression test using the public `handlePositionChange` path and verifies both cancellation observation and a fresh retry launch.
> I don't see anything still missing for those three findings. WI-13 is Gate-4 clean.

## Summary verdict

**ship-as-is.** Two rounds of audit, all findings resolved or closed cleanly. The diff:
- Delivers WI-13 per the plan v5 detail subsection: `PDFBilingualPanel.swift` (5 visual states, design-pinned heights, accessibility identifiers), `PDFBilingualPanelBodies.swift` (per-state body subviews), `PDFBilingualPanelState.swift` (pure synchronous derivation), `PDFReaderContainerView+Bilingual.swift` (host extension mirroring TXT/MD/EPUB precedent), the `bookFingerprint` visibility flip, `retryUnit(_:)` extension on `BilingualReadingViewModel+Prefetch.swift`, and `.readerBilingualRetry` + `.readerOpenAITranslate` notifications.
- Resolves all 6 Gate-2 v5 findings (3 High + 3 Medium) before code was written and all 3 Gate-4 round-1 findings (1 High + 1 Medium + 1 Low) before merge.
- 6762 unit tests pass under the pinned simulator (`1FAB9493-B97E-48F0-96C7-44A8E5AAA21E`) with parallel testing disabled.

## Test counts

- WI-13 net-new tests: 22 (PDFBilingualPanelStateTests) + 14 (PDFBilingualPanelTests) + 7 (BilingualReadingViewModelRetryUnitTests) = **43 new tests**.
- Overall suite: 6762 tests, all pass. (6761 before this WI; +1 new is the in-flight cancellation regression test added in round 1 fix.)

## Gate 5 follow-up

Per Gate-4 H1's verification recommendation: the "re-open persisted-on PDF, panel stays loading" regression is best caught by an XCUITest in Gate 5. The fix is in code + a unit test of `handlePositionChange` covers the VM-side contract; the host-extension call site is asserted indirectly by the static `ensureBilingualViewModel` logic. Slice verification on iPhone 17 Pro Simulator with a fixture PDF will land in Gate 5a (recorded in the PR description).
