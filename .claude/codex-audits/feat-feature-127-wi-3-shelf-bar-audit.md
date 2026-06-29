---
branch: feat/feature-127-wi-3-shelf-bar
threadId: 019f12bf-cf6f-7b41-82d5-ad9ca4be9f55
rounds: 1
final_verdict: ship-as-is
date: 2026-06-29
---

# Gate-4 audit — feature #127 WI-3 (collections shelf-bar + VM membership filter)

Independent Codex audit (gpt-5.5, high reasoning, read-only sandbox) of WI-3: the
`CollectionShelfBar` Compose chip row + the `LibraryViewModel` `flatMapLatest`
membership filter (over the WI-1/WI-2 data layer).

## Findings — 2 Medium, both fixed; no Critical/High

| file | severity | issue | resolution |
|---|---|---|---|
| `LibraryScreen.kt` | Medium | A selected collection with no members fell into the global `EmptyState` ("No books yet / Tap + to import") — misleading (the library HAS books) and import wouldn't add to the collection. No committed design for a collection-filter-empty state exists. | **Fixed (rule-51-safe).** The import `EmptyState` now shows ONLY for a truly-empty library (`selectedCollectionId == null`); a filtered-empty collection renders nothing rather than inventing an empty-collection surface. The user returns via the "All" chip. |
| `LibraryViewModel.kt` | Medium | Collection error surfacing was incomplete — `delete`/`assign`/`unassign` launched raw repo calls, so a thrown FK-race exception (assign to a just-deleted collection) would crash instead of emitting `CollectionOpFailed`. | **Fixed.** All five collection mutations route through one `runCollectionOp` try/catch boundary that surfaces both a `Result` failure AND a thrown exception as `LibraryEvent.CollectionOpFailed` (CancellationException re-thrown). |

## Auditor confirmations (clean)

- **Rule 51 fidelity:** `CollectionShelfBar` matches the committed `CollectionBar` — 8dp gap, 18dp
  horizontal padding, 13.5sp sans, active = ink bg + page-bg text + bold, inactive = ~5% ink tint,
  radius 100. Omitting the manage/reorder affordance is correct for this slice (WI-4/WI-5 own those
  surfaces; a half-built manage button would be worse under the design gate).
- `flatMapLatest` cancels the previous membership flow (no stale leak); the reset-to-All guard's
  lifetime `collections.collect` is safe and cancels with the VM; the initial-`emptyList` reset race
  isn't reachable (a user only taps chips after real collections render). Selection survives rotation
  via VM state. MainActivity wiring + exhaustive event handling correct.

## Test evidence

- `LibraryViewModelCollectionsTest` — 3/3 (chip filters to members; "All" resets; delete-selected resets
  to All; `flatMapLatest` no-leak on selection switch).
- `LibraryViewModelTest` — regression green (constructor change absorbed).
- `CollectionShelfBarUiTest` — 3 connected (render "All" + chips; tap → reports id / null; active chip
  carries `selected` semantics). Simple clicks on a directly-rendered composable (no Activity/gesture).

## Verdict

ship-as-is. WI-3 is behavioral; WI-4 (assign sheet) + WI-5 (manage sheet) add the create/assign surfaces.
