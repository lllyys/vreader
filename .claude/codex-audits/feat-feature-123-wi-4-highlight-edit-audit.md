---
branch: feat/feature-123-wi-4-highlight-edit
threadId: codex-exec-f123-wi4
rounds: 1
final_verdict: ship-as-is
date: 2026-06-28
---

# Feature #123 WI-4 (final) — existing-highlight edit / remove

A tap on an existing highlight decoration opens the popover in EDIT mode
(Note/Copy/Share/Remove + recolor). `ReaderHighlightController.observeActivations`
relays `(id, rect)`; `ReaderActivity.onHighlightTapped` looks up the record and
shows the EDIT popover; recolor/note-edit/remove persist through the repo on the
must-finish `appScope` and the `observeHighlights` Flow re-renders.

Files: `reader/ReaderHighlightController.kt`, `reader/ReaderActivity.kt`.

## Round 1 — findings

| # | file:line | severity | issue | resolution |
|---|---|---|---|---|
| 1 | ReaderActivity selectionCallback | Medium | Entering CREATE context set `pendingSelection` but did not clear the EDIT context (`pendingHighlightId`/`pendingSelectedText`); a stale edit context could make `saveNote()`/copy act on the old highlight. | FIXED — the selection callback now clears `pendingHighlightId`/`pendingSelectedText` before `showForSelection` (mirror of `onHighlightTapped` clearing the create context). |

Codex confirmed the rest sound: `onHighlightTapped` clears create context; app-scope
writes are correct must-finish mutations; the Flow re-application converges after
Room emits; recolor preserves the seeded `noteDraft`; EDIT note-save preserves
`activeColor`; copy/share null-safety holds; Readium 3.3.0 `OnActivatedEvent.rect`
(`event.rect`) confirmed against the class metadata.

## Slice / acceptance verification (emulator API 35)

- EDIT-mode popover renders (Note/Copy/Share/Remove) — `SelectionPopoverUiTest.editMode_showsRemove`.
- The edit/remove repo lifecycle (recolor + note + remove) through real Room — `AnnotationsConnectedTest` (updateHighlight + removeHighlight).
- Reopen re-render of a stored highlight on the LIVE navigator/WebView — `ReaderActivityTest.seededHighlight_appliesAsDecoration_onLiveNavigator`.
- `showForExisting` → EDIT mode transition — `SelectionPopoverViewModelTest`.
- The raw finger gestures (long-press-drag to select; tap a decoration to edit) are not headlessly automatable; their downstream is fully verified and the triggers use the documented Readium `selectionActionModeCallback` + `addDecorationListener` patterns (see the feature evidence file).

## Verdict
**ship-as-is.** The full create/edit/remove highlight lifecycle is implemented and
verified on-device at the substance + live-render level; the one Medium
state-invariant gap is fixed.
