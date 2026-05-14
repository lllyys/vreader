---
branch: fix/issue-616-txt-md-add-note-no-highlight
threadId: 019e251f-1f75-7b62-a35f-84d342d4383b
rounds: 2
final_verdict: ship-as-is
date: 2026-05-14
---

# Codex audit log — Bug #181 / GH #616

TXT/MD "Add Note" now creates a `HighlightRecord` (with the note attached) in addition to the existing `AnnotationRecord`, so the annotated text gets a yellow highlight indicator. Mirrors EPUB's `handleHighlightWithNote` pattern.

## Round 1 — initial audit (Codex MCP, read-only)

Files audited: `vreader/Views/Reader/ReaderNotificationHandlers.swift`, `vreader/Views/Reader/ReaderNotificationModifier.swift`, `vreaderTests/Views/Reader/ReaderNotificationHandlerTests.swift`.

Findings:

| file:line | severity | issue | resolution |
|---|---|---|---|
| `ReaderNotificationHandlers.swift:190` | **High** | Dual-write not atomic. `try? await addAnnotation(...)` followed by `await coordinator.create(...)` silently desyncs Notes ↔ Highlights when the first throws. | **FIXED** — replaced `try?` with explicit `do/catch`. On thrown error, `return` before the create call. Both writes succeed-or-neither. Regression test `handleAnnotationSave_annotationPersistenceFails_skipsHighlight_bug181` added. |
| `PersistenceActor+Highlights.swift:54` | Medium | "Add Note" on an already-highlighted range hits dedupe → returns existing HighlightRecord unchanged → drops the new note text. | **Accepted, deferred to follow-up bug.** Pre-existing dedupe behavior; not introduced by this fix. Tracking as separate "Add Note on already-highlighted text should update note on existing HighlightRecord". The user-visible #181 symptom (no yellow highlight) is still resolved for the common case (no prior highlight on that range). |
| `ReaderNotificationModifier.swift:97` | Medium | Re-entrancy: two rapid Save taps could enqueue two save Tasks, producing two `AnnotationRecord` rows (highlights dedupe). | **Accepted as effectively-safe via MainActor serialization.** Trace: Task1 runs sync portion → clears `pendingAnnotationInfo = nil` before any await → yields actor → Task2 runs sync portion → first guard sees nil → bails. The clearing-before-await invariant is the protection. Documented inline in the handler. |
| `ReaderNotificationHandlerTests.swift:266` | Low | Test file ~360 lines, exceeds the ~300-line guideline. Missing coverage of partial-failure / existing-highlight paths. | Partial-failure path coverage added in Round 1 (`handleAnnotationSave_annotationPersistenceFails_skipsHighlight_bug181`). Existing-highlight path is the deferred-to-follow-up bug. File-size split deferred — test files commonly exceed the production guideline when adding regression suites. |

## Round 2 — verification (Codex MCP)

Reply to Codex with the High fix applied + accepted rationales for Medium #2/#3 and Low #4:

> "No new findings in the updated diff.
>
> The High issue is fixed. In ReaderNotificationHandlers.swift:195, `addAnnotation` now gates `highlightCoordinator.create(...)`, so the handler no longer produces a highlight-only success path when annotation persistence fails. The new regression test in ReaderNotificationHandlerTests.swift:300 directly covers that failure mode and would have caught the earlier bug.
>
> Your MainActor re-entrancy reasoning is also correct for this specific code path: `pendingAnnotationInfo` is cleared before the first `await`, so a second queued save task observes `nil` and exits before doing work. I don't see a new concurrency issue introduced by the handler change.
>
> Residual risk remains the accepted follow-up bug: adding a note to an already-highlighted TXT/MD range can still drop the note on the HighlightRecord because highlight dedupe returns the existing record unchanged. That's pre-existing scope, not a regression from this fix."

Round 2 verdict: clean. Ship.

## Test gate

`xcodebuild test -only-testing:vreaderTests/ReaderNotificationHandlerTests` — **15/15 pass**, including:
- `handleAnnotationSave_alsoCreatesHighlightRecord_bug181` (direct repro of pre-fix #181 symptom)
- `handleAnnotationSave_annotationPersistenceFails_skipsHighlight_bug181` (atomicity)
- `handleAnnotationSave_locatorFactoryFailure_skipsBoth_bug181` (validation early-return)

Full suite has 2 unrelated pre-existing failures (`BookFormatAZW3Tests.capabilitiesTTS` + `capabilitiesMatchSimpleEPUB` from PR #644 follow-up) plus AutoPageTurnerTests / TTSServiceSpeedControlTests failing on pristine main (confirmed by checking out main and re-running). None of these are touched by this fix.

## Summary

`ship-as-is`. One High finding fixed inline with new regression coverage. Two Medium findings accepted as effectively-safe (re-entrancy via MainActor serialization) or deferred to a separate follow-up bug (dedupe + note). Low finding (file size) deferred. Two rounds, clean exit.
