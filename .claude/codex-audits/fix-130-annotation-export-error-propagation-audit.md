---
branch: fix/130-annotation-export-error-propagation
threadId: manual-fallback
rounds: 1
final_verdict: ship-as-is
date: 2026-05-06
---

## Manual audit evidence

Same family as bug #129 (silent error swallow via `try?`). Manual audit performed.

### Files changed

| File | Change |
|---|---|
| `vreader/Views/Reader/AnnotationsPanelView.swift` | `exportAnnotations()`: five `try?` calls replaced with explicit do/catch paths feeding the existing `importMessage` alert. |
| `docs/bugs.md` | New row #130 (FIXED, Medium, GH: #279). |

### Why fix

Five silent failure modes:
1. Fetch highlights throws → `[]` used → export proceeds without highlights, no warning.
2. Fetch bookmarks throws → same.
3. Fetch annotations (notes) throws → same.
4. JSON serialize throws → `guard return` aborts silently; share sheet never appears.
5. File write throws → `isShowingExportShare = true` still flips, presents an empty/missing file.

### Fix shape

- Each fetch wrapped in `do/catch`. On error, the kind ("highlights" / "bookmarks" / "notes") is appended to `fetchErrors`. Export still proceeds with whatever fetched successfully.
- After successful share-sheet present, if `fetchErrors` is non-empty, set `importMessage = "Exported with warnings: skipped X (fetch failed)."` so user knows the export wasn't complete.
- JSON serialize: explicit do/catch; on failure set `importMessage = "Export failed: <error>."` and return without flipping `isShowingExportShare`.
- File write: same.

### Edge cases checked

- **All fetches throw**: `fetchErrors = ["highlights", "bookmarks", "notes"]`, payload built with empty arrays, JSON serialize succeeds (empty payload is valid), file written, share sheet appears, alert says "Exported with warnings: skipped highlights, bookmarks, notes (fetch failed)." User can decide whether to share the empty export.
- **Partial fetch failure**: e.g., highlights fetch fails, others succeed → exports the partial payload, alert says "Exported with warnings: skipped highlights." Better than the previous silent partial export.
- **JSON serialize throws** (theoretically — types are Codable, so unlikely): caught, alert message, no share.
- **Temp file write throws** (e.g., disk full): caught, alert message, no share.
- **`AnnotationRecord` type vs `AnnotationNoteRecord`**: confirmed correct type by grepping `func fetchAnnotations` in the codebase. Compile-checked: \`** BUILD SUCCEEDED **\`.

### What I deliberately did NOT change

- The import path (already had proper error handling).
- The `importMessage` @State name: kept since refactoring it to `statusMessage` would expand the diff. Comment in the export function notes the shared meaning.
- The share-sheet flow itself (UIActivityViewController dispatch).

### Tests added

None. UI-state plumbing change (closure type + alert path). The 9 + 13 + 13 = 35 existing export/import/parser tests cover the data-layer behavior unchanged.

### Verdict

**ship-as-is**. Same family as bug #129 — close error-feedback gap with a mechanical fix. No new abstractions, no regression risk. Closes bug #130 / GH #279 cleanly.
