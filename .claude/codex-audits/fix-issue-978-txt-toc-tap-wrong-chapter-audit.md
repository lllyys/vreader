---
branch: fix/issue-978-txt-toc-tap-wrong-chapter
threadId: 019e41b6-774b-7272-81ef-7ab3645fe679
rounds: 1
final_verdict: ship-as-is
date: 2026-05-20
---

# Codex audit — Bug #234 / GH #978

TXT reader: a Contents/TOC tap navigates to the wrong chapter or silently
does nothing (intermittent).

## Scope

| File | Change |
|---|---|
| `vreader/ViewModels/TXTReaderViewModel.swift` | Removed `navigateToChapterByTitle`; added `navigateToTOCTap(globalOffsetUTF16:)` |
| `vreader/Views/Reader/TXTReaderContainerView.swift` | `onNavigate` closure routes the TOC tap through `navigateToTOCTap`; dropped `tocEntries` capture |
| `vreaderTests/Services/TXT/TXTChapterIntegrationTests.swift` | Removed 3 `navigateToChapterByTitle` tests; added `makeDuplicateTitleChapterResult()` + 3 `navigateToTOCTap` regression tests |
| `docs/bugs.md` | Row #234 → `IN PROGRESS` |

## Round 1 — threadId `019e41b6-774b-7272-81ef-7ab3645fe679`

**Findings: none.** Codex verdict: no findings, ship-as-is.

Codex independently confirmed:

- `navigateToGlobalOffset` is a sound resolver for a TOC tap — it picks the
  last chapter with `globalStartUTF16 <= offset`, which is exact when
  `offset` is a chapter's document-global start, and behaves sensibly for
  `offset == 0`, mid-chapter offsets, offsets past EOF, and empty chapter
  lists (`guard … !chIdx.chapters.isEmpty`).
- The key invariant behind the fix: TXT chapter indices
  (`TXTService` / `TXTTocRuleEngine`) and TXT TOC entries are both built
  from the **same regex match locations in the same decoded text**, so a
  TOC entry's `charOffsetUTF16` aligns with the chapter's
  `globalStartUTF16`.
- Behavior parity preserved — continuous mode still routes via
  `uiState.scrollToOffset`; non-continuous mode delegates to
  `navigateToTOCTap`, which preserves the old `chapterIndex != nil` vs
  `else` split internally.
- `rg navigateToChapterByTitle vreader` shows **no remaining production
  callers** after the container change.
- The new regression tests exercise the bug:
  `tocTapDuplicateTitlesResolvesByOffset` would fail against the old
  title-based `firstIndex(where:)` resolver (tapping chapter 2/3 would
  have landed on the first `"Chapter"`). Fixture is realistic for TXT
  (duplicate chapter headings, distinct global starts).

**Residual risk (not a finding):** no new targeted test for the
`globalStartUTF16 == -1` fallback inside `navigateToGlobalOffset` — but that
path is unchanged by this patch and remains indirectly covered by the
existing offset-translation / chapter-offset tests. Accepted: out of scope
for this fix.

## Verdict

**ship-as-is.** Zero findings in one round. The fix removes the buggy
title-string resolver entirely and routes the TOC tap through the existing
offset-based resolver; the change is minimal, parity-preserving, and the
regression tests are RED against the pre-fix code.
