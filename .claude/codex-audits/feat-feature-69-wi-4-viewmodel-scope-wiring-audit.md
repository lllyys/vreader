---
branch: feat/feature-69-wi-4-viewmodel-scope-wiring
threadId: 019e3e57-f407-7ef0-b5fc-42a14cea23df
rounds: 2
final_verdict: ship-as-is
date: 2026-05-19
---

# Gate-4 Implementation Audit — Feature #69 WI-4

WI-4: `AIAssistantViewModel` scope wiring — `contextExtractor` retyped
to `any AIContextExtracting`, `summarize` carries `fullText` / `scope`
/ `chapterBounds`, `selectedScope` observable + `setScope`.

## Files audited

- `vreader/ViewModels/AIAssistantViewModel.swift` (modified)
- `vreader/Views/Reader/AISummaryTabView.swift` (modified — 1-line build fix)
- `vreaderTests/ViewModels/AIAssistantViewModelScopeTests.swift` (new)
- `vreaderTests/ViewModels/AIAssistantViewModelTests.swift` (test migration)
- `vreaderTests/ViewModels/AIReaderIntegrationTests.swift` (test migration)
- `vreaderTests/Views/Reader/AISummaryTabViewTests.swift` (test migration)

## Round 1 — findings

| file:line | severity | issue | resolution |
|---|---|---|---|
| `AIAssistantViewModelScopeTests.swift:205` | Medium | `setScopeDuringLoadingUpdatesScopeWithoutCorruptingState` did not exercise "during loading" — both the test and `AIAssistantViewModel` are `@MainActor`, so the `async let` child cannot preempt; `setScope` ran before `summarize` started. | **Fixed** — replaced with `setScopeDuringInFlightRequestDoesNotCorruptState` + a `GatedAIProvider` test double. The provider's `sendRequest` (off the MainActor) yields to an `entered` AsyncStream then blocks on a `release` stream; the test awaits `entered` (proving the request is genuinely in flight), asserts `.loading` + `.section`, mutates scope, asserts no second request, releases, awaits completion. |
| `AIAssistantViewModelScopeTests.swift:218` | Low | The scope-regression suite pinned only `explain` and `vocabulary`; `translate` and `askQuestion` had no `RecordingExtractor`-backed forwarding assertion. | **Fixed** — added `translateStillUsesSectionScope` and `askQuestionStillUsesSectionScope`, asserting `.section` scope + `textContent`-as-`fullText` passthrough + `chapterBounds == nil`. |

Clean in round 1: the production changes match plan §2.5/§2.6 —
`contextExtractor` retyped to `any AIContextExtracting`, `summarize`
requires `fullText` and carries `scope`/`chapterBounds`,
`selectedScope`/`setScope` present, `performAction` forwards `fullText`
+ explicit `AIContextBudget.defaultMaxUTF16`, non-summarize paths
preserve `.section`. The test-file `textContent:`→`fullText:` migration
touched only `summarize(...)` calls.

## Round 2 — verification

Codex re-reviewed the test file: "Clean. No new Critical/High/Medium
issues … The new in-flight test is materially sound … That removes the
earlier actor-scheduling false positive … The non-summarize regression
pins are now complete for the WI-4 contract."

## Verdict

**ship-as-is.** Zero open Critical/High/Medium findings after 2
rounds. 14 scope tests pass + 51 tests across the 4 affected suites
(`AIAssistantViewModelScope`, `AIAssistantViewModel`,
`AIReaderIntegration`, `AISummaryTabView`).

## Note — `AISummaryTabView.swift` build-fix

WI-4 changed `summarize`'s signature, so `AISummaryTabView.runSummarize`
(WI-5's file) needed a 1-line build fix: `textContent:` → `fullText:`,
still passing the section content with the default `.section` scope —
byte-identical pre-#69 behavior. WI-5 does the real chip-strip rework.
