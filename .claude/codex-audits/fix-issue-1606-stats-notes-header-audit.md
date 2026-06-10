---
branch: fix/issue-1606-stats-notes-header
threadId: bug337-run-codex
rounds: 1
final_verdict: ship-as-is
date: 2026-06-10
---

# Gate-4 Codex audit — Bug #337 (stats per-book NOTES header wraps)

Independent audit via `scripts/run-codex.sh` (gpt-5.4), read-only.

## Round 1

**No material findings.** The fix (`.lineLimit(1)` + `.minimumScaleFactor(0.8)`
+ `.fixedSize(horizontal: false, vertical: true)` on the shared header label) is
proportionate: `lineLimit(1)` is the operative change that stops the `NOTES`
wrap; `minimumScaleFactor(0.8)` guards the active-column state (the inline
chevron shares the 38pt slot) without truncating `NOTES` at this font size;
`fixedSize` is harmless (forces no extra width, right-alignment via the trailing
`Spacer` still works). No regressions to `TIME`/`HL`/`READ`, the leading `BOOK`
header, or the sort-button hit target.

Low-severity open note (no change needed): the tightest case is `NOTES` while
the active column (text + chevron in 38pt). If that ever clips on-device, the
follow-up would be a column-specific treatment or a small width rebalance — not
a shared-header rewrite. Device verification (below) confirms `NOTES` renders
single-line in the inactive state.

## Verdict

**ship-as-is.** Device-verified: the per-book table header renders
`BOOK | TIME | HL | NOTES | READ` all single-line — `NOTES` no longer wraps to
"NOTE / S" (`dev-docs/verification/artifacts/bug-337-notes-header-single-line-20260610.png`).
16 `StatsPerBookTableTests` green (the header-label contract is pinned by
`columnHeaderLabelsMatchTheDesign`).
