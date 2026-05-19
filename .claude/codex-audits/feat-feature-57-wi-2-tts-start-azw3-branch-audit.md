---
branch: feat/feature-57-wi-2-tts-start-azw3-branch
threadId: 019e3e83-01e9-7fc2-bab9-f7adb91bab59
rounds: 2
final_verdict: ship-as-is
date: 2026-05-19
---

# Codex Audit — feature #57 WI-2 (startTTS() AZW3 branch + in-flight extraction gate)

Gate-4 implementation audit of the WI-2 diff (vs `origin/main`).

## Scope

Files changed:
- `vreader/Views/Reader/TTSTextSource.swift` — NEW pure helper (`source(for:)`, `shouldStartExtraction(extractionInFlight:cachedText:)`)
- `vreader/Views/Reader/ReaderContainerView.swift` — `@State azw3ExtractionTask`; `foliateCoordinatorBox` made `internal`; `.onDisappear` extraction-task cleanup
- `vreader/Views/Reader/ReaderContainerView+Sheets.swift` — `startTTS()` `@MainActor` + `TTSTextSource` routing; new `startAZW3TTS(ai:)` + `speakLoadedText(ai:)`; `ensureAIReady()` AZW3 gate
- `vreaderTests/Views/Reader/TTSTextSourceTests.swift` — NEW (7 tests)

## Round 1 — findings

| file:line | severity | issue | fix |
|---|---|---|---|
| ReaderContainerView+Sheets.swift:107 / ReaderContainerView.swift:544 | Medium | The AZW3 extraction path is launched via two unstructured `Task {}` blocks and was never cancelled on reader dismissal. `extractPlainText()`'s own 12 s timeout means the gate eventually clears, but a dismiss does not change `ttsService.state` and there was no `.onDisappear` cleanup for `azw3ExtractionTask` — so a late completion could still run the post-await block and call `startSpeaking` after the reader closed; the task lifetime was not tied to the view lifecycle. | Cancel `azw3ExtractionTask` on reader `.onDisappear`, nil it there, and gate the post-await path on cancellation. |

Clean dimensions (round 1): the omitted WI-2 timeout wrapper is sound (WI-1's `extractPlainText()` already carries the 12 s timeout and is non-throwing → `Task<String?, Never>` suffices); the three idempotency layers are present (`ttsService.state != .idle` / `azw3ExtractionTask != nil` / cached `loadedTextContent`); rapid repeated taps during the first extraction do not spawn a second walk; empty/nil extraction is a no-op; `ensureAIReady()` correctly skips the dead Foliate file-load path; the `@MainActor` annotations and `@State` access pattern are coherent (the `azw3ExtractionTask` store/clear stays on the main actor — race-free); `TTSTextSource` / `source(for:)` / `shouldStartExtraction` / `startAZW3TTS` / `speakLoadedText` are well-shaped; WI-2 is correctly classed behavioral.

## Resolution

**Medium — fixed.** (1) A production (non-DEBUG) `.onDisappear { azw3ExtractionTask?.cancel(); azw3ExtractionTask = nil }` added to `ReaderContainerView`'s body — dismissal cancels the in-flight extraction `Task` and nils the gate, tying the task lifetime to the view lifecycle. (2) `startAZW3TTS`'s post-await block now starts with `guard !task.isCancelled else { return }` — a dismiss-cancelled task suppresses the late `startSpeaking` and skips the gate-clear (which `.onDisappear` already performed).

This refines the plan's §10 "accepted limitation" (the plan had accepted the uncancelled task as harmless because a dismissed reader's `extractPlainText()` returns nil off the `weak` webView). The auditor's `.onDisappear` cancellation is the cleaner, non-fragile form and is adopted.

## Round 2 — verification

Re-reviewed `ReaderContainerView.swift` + `ReaderContainerView+Sheets.swift`. Verdict: **no remaining Critical/High/Medium.** The extraction gate is now lifecycle-bound; the post-await path suppresses late speech via `!task.isCancelled` before any `startSpeaking` or gate mutation; no double-clear hazard (normal path clears once, dismissed path returns before clearing — `.onDisappear` is the single owner); no material orphaned-task issue (the await-and-speak task, after dismissal, is bounded on the cancelled extraction task and exits immediately with no side effects).

## Verdict

**ship-as-is.** Zero open Critical/High/Medium after 2 rounds. Build succeeds under Swift 6 strict concurrency; the 7 `TTSTextSourceTests` + 6 `FoliateSpikeViewTTSTests` all pass.
