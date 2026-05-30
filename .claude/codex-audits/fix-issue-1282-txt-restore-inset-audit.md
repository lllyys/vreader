---
branch: fix/issue-1282-txt-restore-inset
threadId: codex-exec-2026-05-30-bug289
rounds: 1
final_verdict: ship-as-is
date: 2026-05-30
---

# Codex audit — Bug #289 / GH #1282 (chunked TXT restore position drift)

Independent `codex exec --sandbox read-only` audit of the fix (pure pixel→char
seam `TXTChunkedScrollOffset` + wiring into `reportScrollPosition`).

## Findings (both fixed)

| # | file | sev | issue | fix |
|---|---|---|---|---|
| 1 | TXTChunkedReaderBridge.swift:905 | Medium | `indexPathsForVisibleRows?.first` is the row at the table-BOUNDS top, not the inset-adjusted VISIBLE top; near a chunk boundary the bounds-top row can sit entirely in the inset band → measures the previous chunk's end. | Resolve the row via `indexPathForRow(at: CGPoint(y: contentOffset.y + contentInset.top))`, falling back to first-visible for overscroll/empty gaps. |
| 2 | restore path | Low | Restore-generated scroll callbacks could persist a transient position (no chunked-bridge restore-suppression, unlike the non-chunked path). Auditor recommended fixing in-PR. | Added `isRestoringPosition` flag, set across `attemptChunkRestore` (incl. retries), cleared 0.3s after the scroll settles; `reportScrollPosition` early-returns while set. |

## Auditor confirmations

- Inset sign + coordinate space correct (`.never` + `contentInset.top = safeAreaTop` → visible-top content-y = `contentOffset.y + contentInset.top`; restore's `scrollToRow(.top)` aligns to the same point).
- Pure helper handles non-positive cell height, low/high clamp, chunk-start addition, empty chunk.
- Primary inset fix is sufficient for the documented cumulative drift; the row-selection + suppression are robustness hardening.

## Verdict

Both findings fixed per the auditor's own recommendations; pixel→char math
unit-tested (8 cases, incl. the RED inset case). **ship-as-is.**
