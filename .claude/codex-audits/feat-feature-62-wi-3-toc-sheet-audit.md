---
branch: feat/feature-62-wi-3-toc-sheet
threadId: 019e40af-a21c-7713-9ac8-3ec2df308be8
rounds: 2
final_verdict: ship-as-is
date: 2026-05-19
---

# Gate 4 — Implementation Audit — feature #62 WI-3

`TOCSheet` — the navigation sheet (Contents + Bookmarks) of the
annotations-panel split.

## Files audited

- `vreader/Views/Reader/Annotations/TOCSheet.swift` (new)
- `vreader/Views/Reader/Annotations/TOCSheet+Support.swift` (new — created in round 2 for the file-size fix)
- `vreader/Views/Reader/Annotations/TOCSheetRows.swift` (new)
- `vreaderTests/Views/Reader/Annotations/TOCSheetTests.swift` (new)

## Round 1 — findings

| # | file:line | Severity | Issue | Resolution |
|---|---|---|---|---|
| 1 | TOCSheet.swift `bookmarkSubtitle` | Medium | The bookmark sub-line dropped the chapter label — the `TOCSheetV2` design is `chapter · p. N · date`; output was only `p. N · date`. | **Fixed** — `bookmarkSubtitle` (now in `TOCSheet+Support.swift`) composes `chapter · p. N · date`; chapter derived via `chapterTitle(for:)` → `matchedEntryIndex(for:)` (the same last-at-or-before matching as the active TOC entry); each component degrades when unavailable. |
| 2 | TOCSheetRows.swift `TOCContentsRow` | Medium | `TOCContentsRow` rendered `entry.locator.page` raw (0-based for PDF) while `bookmarkSubtitle` rendered `page + 1` — the same physical page could show `p. 0` vs `p. 1`. | **Fixed** — both rows route page through `TOCSheet.displayPage(_:)` (`rawPage + 1`, `nil→nil`). Test `displayPageNormalizes` pins `0→1`, `46→47`, `nil→nil`. |
| 3 | TOCSheet.swift `bookmarksBody` | Medium | Opening on `.bookmarks` rendered the "No bookmarks yet" empty state before the `.task` load completed — a false empty state on first paint. | **Fixed** — added `@State bookmarksDidLoad`; `bookmarksBody` shows the empty state only after the load completes, a neutral `Color.clear` body before. DEBUG seam `bookmarksEmptyStateShown` + test `bookmarksEmptyStateOnlyAfterLoad` pin it. |
| 4 | TOCSheet.swift file size | Low | 333 lines, over the ~300 guideline. | **Fixed** — display helpers / `activeEntryIndex` / badge counts / DEBUG hooks moved to `TOCSheet+Support.swift`. `TOCSheet.swift` is now 245 lines; the `@State` vars changed `private`→`internal` for the cross-file extension (the `+Sheets.swift` pattern `ReaderContainerView` uses). |

No Critical or High findings.

## Round 2 — verification

Codex re-read all four fixes against the worktree (including the new
`TOCSheet+Support.swift`): "No Critical, High, or Medium findings remain."
The chapter composition, the `displayPage` normalization shared by both
rows, the load-gated empty state, and the file split all confirmed correct
and complete.

## Verdict

**ship-as-is.** Two audit rounds. Round 1: 3 Medium + 1 Low. Round 2: all
four fixed and confirmed. Zero open Critical/High/Medium. 16 tests pass
under `xcodebuild test`.
