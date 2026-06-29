---
branch: feat/feature-127-wi-4-assign-sheet
threadId: 019f12d9-5ce4-7f51-a319-2d1f11df2f16
rounds: 1
final_verdict: ship-as-is
date: 2026-06-29
---

# Gate-4 audit — feature #127 WI-4 (assign-to-collections sheet)

Independent Codex audit (gpt-5.5, high reasoning, read-only sandbox) of WI-4: the
`AssignToCollectionsSheet` + `SheetRoute` + the book long-press, over the WI-1/2/3
data layer + shelf-bar.

## Findings — 1 High + 3 Medium + 1 Low, all fixed

| file | severity | issue | resolution |
|---|---|---|---|
| `MainActivity.kt` | High | The "book deleted → close sheet" check read the collection-FILTERED `state.books`. Opening the sheet from a filtered collection and unassigning the book from it would drop the book from `state.books` → the sheet auto-closed, violating the no-auto-close batch contract. | **Fixed.** Added `LibraryViewModel.allBooks` (the UNFILTERED library StateFlow); the sheet resolves its book from it, and only closes when `book == null && allBooks.isNotEmpty()` (library loaded + book genuinely gone). |
| `LibraryViewModel.kt` / repo / dao | Medium | `createCollectionAndAssign` wasn't atomic — `createCollection` could commit, then `assign` fail on an FK race, leaving an orphan empty collection. | **Fixed.** Added `CollectionDao.createAndAssign` `@Transaction` (insert + addMembership atomically; an FK failure rolls BOTH back) + `CollectionRepository.createAndAssign`; the VM delegates to it. New `createAndAssign_fkFailure_rollsBack_noOrphanCollection` test proves no orphan. |
| `CollectionSheets.kt` | Medium | Design fidelity — the AssignSheet design wraps the checklist in a rounded card with row dividers; the rows were rendered bare. | **Fixed.** Wrapped the rows in a `Surface` card (rounded 14dp) with `HorizontalDivider`s between rows (per the design). |
| `LibraryScreen.kt` | Medium | The long-press assign had no `onLongClickLabel` → TalkBack announced a generic action. | **Fixed.** Added `onLongClickLabel = "Add to collection"` to the grid + list `combinedClickable`. |
| `MainActivity.kt` | Low | `viewModel.collectionIdsForBook(route.bookKey)` created a new Flow each recomposition. | **Fixed.** `remember(route.bookKey) { … }`. |

## Auditor confirmations

- `SheetRouteSaver` handles colon-containing fingerprintKeys correctly:
  `"assign:epub:abc:123".removePrefix("assign:")` → `epub:abc:123`.
- The duplicate-name path does not assign and surfaces the failure event; the `@Transaction` shape is
  the correct atomic create-then-assign.

## Test evidence

- `CollectionRepositoryTest` — 13/13 (incl. `createAndAssign` happy-path + the FK-rollback / no-orphan).
- `LibraryViewModelCollectionsTest` — 5/5 (filter/reset/no-leak + createCollectionAndAssign create+assign + dup).
- `LibraryViewModelTest` — 4/4.
- `AssignSheetUiTest` — 3 connected (render checked/unchecked via `useUnmergedTree`, tap toggles, inline create).

## Verdict

ship-as-is (after the 5 fixes). WI-4 is behavioral; WI-5 adds the manage sheet, WI-6 the backup/restore.
