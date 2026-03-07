# Bug Tracker

Track bugs here. Tell the agent "fix bug #N" to start a fix.

## How to use

1. Add bugs as you find them (fill in Summary and File/Area at minimum)
2. Tell the agent: "fix bug #2" — it will follow the workflow in AGENTS.md

- **Bug fix workflow** (follow this order for every bug):
  1. **Understand**: Read the file/area, reproduce the symptom, identify root cause (not just location).Run `/codex-toolkit:bug-analyze`
  2. **RED**: Write a failing test that proves the bug exists.
  3. **GREEN**: Minimal fix to make the test pass.
  4. **REFACTOR**: Clean up without changing behavior.
  5. **Verify**: Run tests, confirm the fix, check for regressions. Run `/codex-toolkit:audit-fix` on changed files
  6. **Track**: Update `docs/bugs.md` status to FIXED.
  7. Do NOT commit unless explicitly requested.

4. Agent updates Status when done

## Statuses

- `TODO` — not started
- `IN PROGRESS` — being worked on
- `FIXED` — fix committed
- `WONT FIX` — intentional behavior or out of scope

## Bugs

### Description

1. ~~CJK search returns no results~~
2. ~~2026.02The search results are incomplete; only a few results are shown.~~
3. ~~Progress cannot be saved. Each time the TXT file is opened, it starts from the beginning.~~
4. ~~The performance of text search is poor. I have to wait for a while each time I open the search panel.~~
5. The performance of the text page is poor. I have to wait for a while each time I open a TXT book.
6. ~~The reading settings do not take effect.~~
7. ~~Scrolling performance is poor in the TXT reader.~~
8. ~~There is nothing displayed on the reading panel.~~
9. The theme does not work in EPUB.
10. Theme changes do not take effect in TXT; they only apply after changing the font size or reopening the file.
11. Opening a large TXT file causes very poor scrolling performance; the page is nearly impossible to scroll.
12.

### Summary

| # | Summary                                                                                               | File/Area | Severity | Status  | Notes                                                                                                                                          |
| - | ----------------------------------------------------------------------------------------------------- | --------- | -------- | ------- | ---------------------------------------------------------------------------------------------------------------------------------------------- |
| 1 | CJK search returns no results                                                                         | Search/\* | High     | FIXED   | FTS5 tokenization + encoding + race condition (0d48d0a)                                                                                        |
| 2 | The search results are incomplete; only a few results are shown.                                      | Search/\* | High     | FIXED   | FTS5 returned 1 hit per segment; now expands to all occurrences via span map                                                                   |
| 3 | Progress cannot be saved. Each time the TXT file is opened, it starts from the beginning.             | Reader/\* | High     | FIXED   | TXTTextViewBridge delegate was nil; wired ViewModel as delegate                                                                                |
| 4 | The performance of text search is poor. I have to wait for a while each time I open the search panel. | Reader/\* | Medium   | FIXED   | SearchViewModel created before indexing; panel opens instantly, index builds in background                                                     |
| 5 | The performance of the text page is poor. I have to wait for a while each time I open a TXT book.     | TXT/\*    | Medium   | PARTIAL | Used mappedIfSafe + O(n) word count. UITextView layout for large files needs chunked loading (TXTChunkedLoader exists but not yet wired)       |
| 6 | The reading settings do not take effect.                                                              | Reader/\* | High     | FIXED   | settingsStore was created but never passed to reader host/container views; now wired through TXT and MD readers                                |
| 7 | Scrolling performance is poor in the TXT reader.                                                      | TXT/\*    | Medium   | FIXED   | Enabled allowsNonContiguousLayout + throttled scroll callbacks to \~10fps with end-of-scroll flush                                             |
| 8 | There is nothing displayed on the reading panel.                                                      | Reader/\* | Medium   | FIXED   | Annotations panel had placeholder views; wired real BookmarkListView, HighlightListView, AnnotationListView, TOCListView with PersistenceActor |
| 9 |                                                                                                       |           |          | TODO    |                                                                                                                                                |

