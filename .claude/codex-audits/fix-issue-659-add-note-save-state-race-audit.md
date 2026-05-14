---
branch: fix/issue-659-add-note-save-state-race
threadId: 019e2596-f4b1-72a1-af9f-d4791f7974b4
rounds: 2
final_verdict: ship-as-is
date: 2026-05-14
---

# Codex audit log — Bug #188 / GH #659

Bug #188 regression fix: TXT/MD Add Note Save no longer no-ops at v3.21.53. Root cause was the Bug #181 fix delegating `onSave` to a Task that read `state.pendingAnnotationInfo` AFTER `AddNoteSheet.dismiss()` had synchronously cleared it. This PR refactors the handler to take pre-captured value args + extracts a synchronous `prepareAnnotationSave` helper for the validation/capture/clear sequence.

## Round 1 — initial audit

Findings:

| file:line | severity | issue | resolution |
|---|---|---|---|
| `ReaderNotificationHandlerTests.swift:259` | Medium | The Bug #188 regression test proves the handler no longer depends on view state, but it doesn't exercise the production capture-then-Task race boundary in the modifier. A future refactor could move a state read back into the modifier-side async path and the test would still pass. | **FIXED** — extracted `prepareAnnotationSave(state:, deps:) -> AnnotationSaveRequest?` static function. Modifier's `onSave` now calls `prepareAnnotationSave` (sync, returns captured tuple + clears pendingAnnotationInfo) then spawns Task with the captured request. Added 5 new tests covering prepare (validInput, nilPendingInfo, emptyTrimmed, locatorFactory failure) + the production-sequence regression test (`prepareAndHandleAnnotationSave_isImmuneToPostPrepareStateMutation_bug188`) which prepares, then explicitly mutates state to simulate dismiss-after-Task-enqueue, then runs the handler — confirming both records still persist using only the captured request. |

## Round 2 — verification

> "No findings. The refactor preserves the Bug #188 fix. ReaderNotificationHandlers.swift now owns the full synchronous capture-and-clear step, and ReaderNotificationModifier.swift only enqueues async persistence with the captured request. That keeps the production path immune to `dismiss()` clearing `pendingAnnotationInfo` before the task body runs. The new tests pin the right contract: covers the sync prepare path and its guard cases, and now exercises the exact production sequence that mattered for the regression: prepare, mutate state afterward, then run persistence from captured values only. That closes the gap from round 1."

Verdict: **ship-as-is.**

## Test gate

`xcodebuild test -only-testing:vreaderTests/ReaderNotificationHandlerTests` — 18/18 pass, including:
- `prepareAnnotationSave_validInput_returnsRequestAndClearsPending`
- `prepareAnnotationSave_nilPendingInfo_returnsNil`
- `prepareAnnotationSave_emptyTrimmed_returnsNilAndClears`
- `prepareAnnotationSave_locatorFactoryFailure_returnsNilAndClears`
- `prepareAndHandleAnnotationSave_isImmuneToPostPrepareStateMutation_bug188` (production-sequence)
- `handleAnnotationSave_persistsBoth_withCapturedArgs`
- `handleAnnotationSave_immuneToPostCaptureStateMutation_bug188`
- `handleAnnotationSave_annotationPersistenceFails_skipsHighlight` (atomicity from Bug #181)

## Pre-FIXED simulator verify

On iPhone 17 Pro Sim (iOS 26.5) with the fixed build:

1. Reset library + seed war-and-peace.txt → open chapter 1.
2. Long-press "Lucca" → custom menu → tap Add Note.
3. Paste "Italian port — bug #188 verify" via clipboard fast-path → tap Save → modal dismisses.
4. SQLite confirms BOTH records:
   - `ZANNOTATIONNOTE`: 1 row, content "Italian port — bug #188 verify"
   - `ZHIGHLIGHT`: 1 row, selectedText="Lucca", note="Italian port — bug #188 verify", color="yellow"
5. Snapshot: `highlightCount: 1` (was 0 pre-fix).
6. Tap to dismiss chrome → **yellow background clearly visible on "Lucca" in line 1**.

Evidence: `dev-docs/verification/artifacts/bug-188-prefix-lucca-yellow-highlight-visible-20260514.png`.

This also unblocks Bug #181's GH #616 close-gate verification (Bug #181's `coordinator.create` call is now reached for real) AND Feature #4 criterion 8c (visual highlight on annotated text).

## Summary

`ship-as-is`. Bug #188 regression fixed via two-function decomposition (`prepareAnnotationSave` for sync validate+capture+clear; `handleAnnotationSave` for async dual-write). The modifier-side capture sequence is now testable as a pure function via `prepareAnnotationSave`. 18/18 tests pass; pre-FIXED simulator verify confirms both records persist + yellow highlight visible on annotated text.
