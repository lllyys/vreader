---
branch: fix/issue-1303-highlight-empty-edit-panel
threadId: codex-exec-readonly
rounds: 3
final_verdict: ship-as-is
date: 2026-05-31
---

# Codex audit — Bug #295 / GH #1303 (highlight tap opens empty edit panel)

Read-only `codex exec` audit, 3 rounds (converged clean).

## Fix summary

- Root cause: an ambiguous tap (overlapping highlights, or a near-miss within
  the #287 44pt tolerance) resolved to a note-LESS highlight instead of the
  intended noted one → empty editor. The note-seeding chain was correct; the
  defect was tap RESOLUTION.
- Fix (pure logic, no new UI — Rule 51 carve-out):
  - `PersistedHighlightLookupEntry` gains `hasNote: Bool` (default false).
  - `TextHighlightHitTester.hitTest`: on overlap, the topmost NOTED candidate
    covering the index wins; else topmost covering entry (unchanged when none
    or all are noted, so a lone color-only highlight keeps its "Add a note…"
    empty state).
  - `TextHighlightHitResolver` tolerance path: prefer the nearest NOTED
    candidate within tolerance, else nearest of all.
  - `hasNote` populated at every lookup construction site.
  - Same-session note edits: `HighlightCoordinator.updateNote` calls the narrow
    `renderer.refreshNoteMetadata(records:)` (default no-op; only the text
    renderer rebuilds its lookup) so `hasNote` updates immediately without a
    visual repaint.

## Round 1 findings

| file:line | severity | issue | resolution |
|---|---|---|---|
| TXTChapterHighlightHelper.swift:103 | High | chapter-local `lookupForChapter` rebuilt entries without `hasNote` → chapter-paged TXT lost the preference. | Fixed — propagate `hasNote`; test added. |
| HighlightCoordinator.swift:191 | Medium | note save/clear didn't refresh the lookup → same-session staleness. | Fixed (round 1 via `restore`; refined in round 2). |

## Round 2 findings (introduced by the round-1 Medium fix)

| file:line | severity | issue | resolution |
|---|---|---|---|
| PDFHighlightRenderer.swift:67 | High | round-1 used the broad `renderer.restore` in `updateNote`, which on PDF appends/duplicates annotations. | Fixed — added narrow `refreshNoteMetadata` hook (default no-op; text-only override); `updateNote` no longer calls visual `restore`. |
| HighlightCoordinatorMutationTests.swift:344 | High | stale test asserted `restoreCalls == 0` while round-1 called `restore`. | Fixed — `restore` no longer called; test asserts `restoreCalls==0` AND `refreshNoteMetadataCalls==1`. |

## Round 3

No findings. Confirmed: `updateNote` does no visual repaint; PDF/EPUB/Foliate
no-op `refreshNoteMetadata`; all lookup sites preserve `hasNote`; test updated.

## Verdict

ship-as-is. Tests: 98/98 across 7 highlight suites green. Behavior-only (no new
chrome). The end-to-end "tap an overlapped noted highlight opens its note"
flow is device-verified against a real book at the close gate.
