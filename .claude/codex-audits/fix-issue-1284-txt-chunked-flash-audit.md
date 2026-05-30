---
branch: fix/issue-1284-txt-chunked-flash
threadId: codex-exec-2026-05-31-bug27
rounds: 1
final_verdict: ship-as-is
date: 2026-05-31
---

# Codex audit — Bug #27 / GH #1284 (chunked TXT chapter-1 flash on open)

`codex exec --sandbox read-only` audit of the alpha-gate port to the chunked path.

## Findings (both fixed)

| # | file | sev | issue | fix |
|---|---|---|---|---|
| 1 | TXTChunkedReaderBridge.swift | Medium | `restoreRetryCount` was never reset after success/exhaustion → a later restore/navigation could get a depleted retry budget and re-introduce the flash under a layout race. | Reset `restoreRetryCount = 0` at every terminal path (success, exhaustion, out-of-range index). |
| 2 | TXTChunkedHighlightHelper.swift:17,23 | Low | `scrollToGlobalOffset`'s early returns (empty offsets / chunk-index miss) didn't reveal a restore-hidden table → blank for the full 1.2s safety timeout on bad metadata. | `revealContent(tableView)` before both early returns (idempotent, harmless for normal dynamic nav). |

## Path check (auditor)

No permanent alpha=0 (stuck-blank) path. All hide paths are covered by: the
success reveal, the retry-exhaustion reveal (~0.65s), the index-guard reveal, the
1.2s safety net (≈550ms slack over the worst retry ladder), and now the
scrollToGlobalOffset early-return reveals. `updateUIView` doesn't fight the gate;
`hasPendingRestore` correct (offset 0 / out-of-range chunk not pending).

## Verdict: ship-as-is.

`hasPendingRestore` predicate unit-tested (`TXTChunkedReaderBridgeRestoreTests`,
4 cases). The alpha-timing reveal is UIKit bridge-interaction (not unit-testable
without a live table) — verified by the audit path-check; on-device visual recheck
pending CU.
