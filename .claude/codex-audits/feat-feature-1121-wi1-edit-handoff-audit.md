---
branch: feat/feature-1121-wi1-edit-handoff
threadId: codex-exec-2026-05-31-feat1121-wi1
rounds: 1
final_verdict: ship-as-is
date: 2026-05-31
---

# Gate-4 audit — Feature #1121 WI-1 (edit-handoff foundation)

`codex exec --sandbox read-only`. **No findings.** Foundational, non-presenting
slice: adds the types + threads the open-in-edit intent through the popover
pipeline + the pure `HighlightEditHandoff` router. `edit()` stays navigate-only and
no bridge observes `.readerHighlightEditRequested` yet → strict runtime no-op.

Auditor confirmations:
- Existing tap behavior unchanged (all `ReaderHighlightTapEvent` producers omit the
  trailing-defaulted `openInEditMode`; `present(_:initialMode: .reading)` preserves
  the old `present(_)` semantics — mode .reading, draft "").
- Intent thread has no stale-mode race: `handleTap` (@MainActor) sets
  `presentedInitialMode` before the async lookup; only the latest `latestTapToken`
  publishes `presented`; a superseding normal tap resets to `.reading` first.
- `.editing` draft seed matches `beginEdit`; Equatable/Sendable intact + source-compatible.
- `HighlightEditHandoff.action` projects highlightId / annotationId correctly.

## Gate-2 plan audit (round 1): 2 High + 5 Medium + 2 Low — all addressed in the
plan/WI-1 scope (see plan "Gate-2 audit fixes applied"). H1 (lost flag) fixed in WI-1;
the per-format ack/resolver/cancellation findings scope WI-2.

## Verdict: ship-as-is.
