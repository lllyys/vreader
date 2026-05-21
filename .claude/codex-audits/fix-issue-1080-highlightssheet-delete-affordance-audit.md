# Codex Gate-4 audit — fix-issue #1080 (Bug #249)

- **Branch**: `fix/issue-1080-highlightssheet-delete-affordance`
- **Base**: `ecfedcb2` (main, v3.38.37)
- **Date**: 2026-05-21
- **Thread**: `019e47fd-9b06-79d3-b011-4f460107f005`
- **Model**: gpt-5.5 (read-only sandbox)

## Verdict

**`needs-fix`** — and the fix is non-code: file `needs-design` and stop the slice.

## Attempted shape

Adding `.contextMenu` "Delete" action to `HighlightCardV3` and `StandaloneNoteCard`, wired to the existing `HighlightListViewModel.removeHighlight` / `AnnotationListViewModel.removeAnnotation` paths. All 22 `HighlightsSheetTests` passed (1.957s). The technical correctness was sound — `@Observable` re-render, `.readerHighlightRemoved` + `.foliateRequestAnnotationJSDelete` notification contracts preserved, idempotent on repeated delete.

## Findings

### High — Rule 51 (UI/UX from claude.ai/design only)

The `.contextMenu` Delete action is **a new user-visible affordance** on `HighlightsSheet`. The committed `dev-docs/designs/vreader-fidelity-v1/project/vreader-notes-unified.jsx` does NOT depict destructive row/card actions on this surface. Rule 51's "system chrome" exemption is narrowly scoped to OS chrome (status bar, home indicator, dynamic island), NOT to contextual menus added to app content.

The orchestrator's brief argued Option 2 ("Add Delete to an existing UIMenu / context menu — no new visible UI, just an extra menu item") was rule-51 exempt — but the premise was wrong: there is no existing UIMenu / `.contextMenu` on these cards to extend. Introducing `.contextMenu` IS introducing a new visible affordance (the popup menu appears on long-press), even though the default rendering looks unchanged.

`docs/bugs.md` Bug #249 itself says `BLOCKED: needs-design` explicitly. The `vreader-highlight-popover.jsx` Delete vocabulary in the in-reader popover is design-precedent for the verb, but not design-coverage for THIS surface and THIS interaction state. Per rule 51's "What 'designed' means" subsection: '"Looks similar to existing X" does NOT count.'

### Medium — None

The production data path through `HighlightListViewModel.removeHighlight` is sound. The VM emits `.readerHighlightRemoved` (UUID-keyed) and `.foliateRequestAnnotationJSDelete` (CFI-keyed for EPUB anchors) — the same notification contract the in-reader popover delete uses (bug #229 / GH #938). `@Observable` change tracking would propagate the deletion through SwiftUI's render loop correctly. Persistence delete is idempotent on missing rows (silent return).

### Low — File length

`HighlightAnnotationCard.swift` would have gone from 275 → 327 lines, over the ~300-line soft guideline. Splitting the test hooks or extracting card helpers would have been reasonable but not blocking.

### Low — Audit ran read-only

Codex sandbox is read-only; the file diff was reviewed directly. Tests were run by the implementing agent (22/22 pass).

## Action taken

1. Implementation reverted in the worktree (all four changed files returned to base).
2. Filed `Design needed` issue **GH #1103** with labels `enhancement` + `needs-design`.
3. Marked Bug #249 row Notes column with `BLOCKED: needs-design (#1103)`.
4. No PR opened, no version bump, no merge — the slice is stopped per rule 51's workflow.

## Resumption gate

When the design bundle for the HighlightsSheet delete affordance commits under `dev-docs/designs/vreader-fidelity-v1/project/`, a fresh `/fix-issue #1080` run can resume against the designed shape. The implementation pattern explored in this branch (closures + `.contextMenu` OR `List` + `.swipeActions` + reskinned card rows) is recorded here as prior art for that run.
