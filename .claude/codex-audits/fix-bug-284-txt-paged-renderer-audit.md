---
branch: fix/bug-284-txt-paged-renderer
threadId: codex-exec-local
rounds: 2
final_verdict: ship-as-is
date: 2026-05-29
---

# Gate-4 Codex audit — Bug #284 / GH #1261: TXT paged-mode cross-chapter page advance

Independent audit via `codex exec --sandbox read-only` (cc-suite path, no `-m`).
Author/auditor separation preserved (implementing Claude Code session vs. separate
Codex process).

## Scope

Fix wires a real TXT paged renderer (reusing MD's `NativeTextPagedView` +
`NativeTextPageNavigator`) and cross-chapter manual page-turn so paged TXT can
advance from chapter N's last page to chapter N+1's first page (design
`reader-navigation.md §2.2`). New files: `TXTPagedChapterAdvance.swift` (pure
decision logic + `TXTPagedLanding`), `TXTReaderContainerView+Paged.swift`
(renderer + handlers). `TXTReaderContainerView.swift` body extracted into
helper properties/methods to stay under the Swift type-checker complexity limit.

## Round 1 — `follow-up-recommended` (2 High)

- **High #1**: `pendingPagedLanding` could be left set if `nextChapter()` /
  `previousChapter()` failed to load (the VM catches the error, leaves the index
  unchanged); the queued landing could then mis-apply to the OLD chapter on an
  unrelated font/theme repaginate.
- **High #2**: a rapid double-tap could queue a second cross whose landing an
  INTERMEDIATE chapter consumes instead of the final target.
- Lows: navigator-reuse override, 0-page/clamp handling, position-persistence
  parity, @MainActor isolation, body-refactor behavior-preservation — all
  confirmed correct (no action needed).

## Round-1 fixes applied

`TXTPagedLanding` changed from a plain enum to a struct carrying
`targetChapterIndex` + `edge` (.firstPage / .lastPage). The handlers OVERWRITE
the landing on each cross (no hard in-flight latch — that would deadlock on a
failed load). `repaginatePagedChapter` applies the landing ONLY when
`pendingPagedLanding?.targetChapterIndex == viewModel.currentChapterIdx`, so a
non-matching landing (failed load → index unchanged; intermediate chapter →
wrong index) is never mis-applied; the next legitimate cross overwrites it.
Added 4 unit tests locking the `TXTPagedLanding` target-encoding semantics.

## Round 2 — `ship-as-is`

Codex confirmed both High findings resolved: a failed ch3→ch4 load leaves the
VM on ch3, so a later ch3 repaginate does not apply the ch4 landing (target
mismatch); a rapid double-tap either lands ch4 on its matching rebuild or skips
the stale landing entirely — in no ordering does a landing apply to the wrong
chapter, no crash, no stuck state. Stale-landing-after-failed-load is harmless
(gated by index, overwritten on next cross). No new issues from the struct
change or overwrite semantics.

## Tests

- `TXTPagedChapterAdvanceTests` — 18 tests (decision matrix incl. empty/short
  chapter + single-page chapter boundaries; `TXTPagedLanding` target encoding).
- `TXTReaderContainerViewPagedLayoutTests` — 7 tests (chrome-aware viewport
  formula + MD-parity lock).
- Full suite: 7600+ tests passing.
