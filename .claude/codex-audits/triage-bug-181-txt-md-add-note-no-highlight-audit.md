---
branch: triage/bug-181-txt-md-add-note-no-highlight
bug: 181
date: 2026-05-14
final_verdict: ship-as-is
---

## Scope

Docs-only triage commit: adds Bug #181 row + detail entry to `docs/bugs.md`.
No Swift source changes. No test changes.

## Audit

No logic to audit. The tracker entry is grounded in code-read evidence:
- `ReaderNotificationModifier.swift:108-113`: `onSave` handler calls
  `deps.annotationPersistence.addAnnotation(...)` only — no
  `highlightCoordinator.create(...)` call. Annotation range never enters
  `uiState.persistedHighlightRanges`.
- `TextReaderUIState.swift:128-134`: `refreshPersistedHighlights` loads only
  `HighlightRecord` objects — `AnnotationRecord` ranges are excluded by design.
- `EPUBReaderContainerView+Highlights.swift:105-133`: `handleHighlightWithNote`
  calls `coordinator.create(..., note: note)` → creates `HighlightRecord` with
  note → text IS rendered with yellow background.
- `MDReaderContainerView.swift`: also uses `.readerNotificationHandlers` with
  `annotationPersistence` — same gap affects MD.
- Feature #4 criterion 8c was documented as FAIL in round-3 verification
  (`2026-05-13`) and cross-referenced to bug #160. Bug #160 is FIXED but
  targets `HighlightRecord` chapter-mode rendering — architecturally separate
  from this gap (annotation save never creates a HighlightRecord at all).

## Verdict

ship-as-is — documentation only, no code risk.
