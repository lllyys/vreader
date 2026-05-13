---
branch: triage/feature-55-tap-annotation-inline-note-view
feature: 55
date: 2026-05-14
final_verdict: ship-as-is
---

## Scope

Docs-only triage commit: adds Feature #55 row + GH #619 to `docs/features.md`.
No Swift source changes. No test changes.

## Audit

No logic to audit. The tracker entry is grounded in code-read evidence:
- `FoliateReaderContainerView+Highlights.swift:41-56`: `handleAnnotationShow(cfi:)` only
  posts `.readerHighlightRequested` → opens the full annotations panel. No inline note
  content is shown.
- `ReaderNotificationModifier.swift:108-113`: `onSave` handler creates `AnnotationRecord`
  only (via `addAnnotation()`). No tap handler exists to display the saved note inline.
- `TextReaderUIState.swift:128-134`: `refreshPersistedHighlights` loads only `HighlightRecord`
  — `AnnotationRecord` ranges are never in `persistedHighlightRanges`; there is nothing for
  a tap-gesture to hit-test against for annotation ranges in TXT/MD.
- Confirmed no inline note display path exists in any reader format. Feature #53 (inline
  edit/delete for highlights) is architecturally separate: it targets `HighlightRecord` tap
  detection, while #55 targets `AnnotationRecord` note-body display.

## Verdict

ship-as-is — documentation only, no code risk.
