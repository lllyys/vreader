---
branch: fix/issue-1358-readium-note-sheet
threadId: 019e86c4-d599-7303-9858-f78d0bcbddba
rounds: 1
final_verdict: ship-as-is
date: 2026-06-02
---

# Codex audit — Bug #303 (GH #1358): Readium EPUB select → Note parity

Independent Codex audit (cc-suite via `scripts/run-codex.sh`, model `gpt-5.5`,
effort `high`, read-only) of the fix that adds the `.readerAnnotationRequested`
observer + the designed `AddNoteSheet` + a create-with-note path to
`ReadiumEPUBHost`, bringing the default EPUB engine to parity with legacy EPUB +
TXT/MD (where select → Note was a silent no-op).

## Scope audited

- `vreader/Views/Reader/ReadiumEPUBHost+Annotations.swift` (new)
- `vreader/Views/Reader/ReadiumEPUBHost.swift` (new `@State`)
- `vreader/Views/Reader/ReadiumEPUBHost+Body.swift` (`.modifier(annotationObservers)`)
- `vreader/Services/Reader/ReadiumSelectionHighlightBuilder.swift` (`normalizeNote`)
- `vreaderTests/Services/Reader/ReadiumNoteNormalizeTests.swift` (new)

## Findings (round 1) — 2 Low, zero Critical/High/Medium

| File:line | Severity | Issue | Resolution |
|---|---|---|---|
| `ReadiumEPUBHost+Annotations.swift` | Low | Interactive (drag-down) sheet dismissal bypassed cleanup — the stashed `pendingReadiumNoteSelection` could remain and the live navigator selection wasn't cleared (Save/Cancel buttons cleared them, a swipe-down didn't). | FIXED — `.sheet(isPresented:, onDismiss: onCancel)` so EVERY dismissal path runs cleanup; `handleReadiumNoteCancel` now also calls `navCommander.clearSelection()`. All statements idempotent (a Save already nils the pending selection + clears the navigator selection before the sheet closes). |
| `ReadiumEPUBHost+Annotations.swift` | Low | The note sheet omitted the established `.presentationDetents([.medium])` + `.presentationDragIndicator(.visible)` used by the legacy EPUB / TXT / MD `AddNoteSheet` mounts. | FIXED — added both modifiers to match. |

## Auditor confirmations (clean on the requested risks)

- **Token ordering** matches legacy EPUB (`EPUBReaderContainerView.swift:413`): the
  popover action posts synchronously; the observer resolves/consumes the token
  before the popover dismissal's `clear()`; a second action for the same token
  is a no-op. No double-consume.
- **Concurrency**: the save path captures `selection`/`inputs`/`note`/`coordinator`
  before spawning the `create` Task; the Readium adapter applies the persisted
  record as a decoration via the shared coordinator. No race.
- **SwiftUI**: `@State` projected bindings from the extension computed var are
  valid; `selectedText` refreshes when `pendingReadiumNoteSelection` is set before
  presentation.
- **Rule 51**: no new note UI invented — reuses the designed `AddNoteSheet`.

## Note on the test seam

`AddNoteSheet`'s Save button is `.disabled` when the note is empty/whitespace, so a
Note always carries text (same as TXT/MD); `normalizeNote`'s empty→nil branch is
defensive. The 5 `normalizeNote` tests pin the helper; the live WKWebView
selection → popover → sheet → persist flow is exercised by device verification
(the same builder/live-selection split the WI-8 highlight slice uses).

## Verdict

**ship-as-is.** Both Low findings fixed; build + 5 unit tests GREEN.
