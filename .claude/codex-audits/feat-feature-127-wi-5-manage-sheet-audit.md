---
branch: feat/feature-127-wi-5-manage-sheet
threadId: 019f12f4
rounds: 2
final_verdict: ship-as-is
date: 2026-06-29
---

# Gate-4 audit — feature #127 WI-5 (collections manage UI)

WI-5 adds the collections **manage** surface for the Android library. Scope after the
round-2 rule-51 rework: the manage sheet (`CollectionsManageSheet` / `ManageSheetContent`)
lists collections + book counts, taps a name → inline rename, and an inline "New Collection"
create row — opened from the **designed scoped-collection header** ("N books · edit collection",
`vreader-library-android.jsx` `scope === 'collection'`). Files: `LibraryScreen.kt` (scoped
header), `CollectionSheets.kt` (manage sheet), `MainActivity.kt` (route wiring),
`LibraryViewModel.kt` (rename/create/delete seams), `ManageSheetUiTest.kt`.

## Round 1 (Codex 019f12f4, gpt-5.5/high) — 2 Medium, both rule-51 (no self-designed UI)

| file:line | severity | issue | resolution |
|---|---|---|---|
| `LibraryScreen.kt` (nav bar) | Medium | The manage entry point was an **invented** nav-bar Folder pill — not depicted in the committed design (the library top bar shows Search + More, not a Folder pill). Route through a designed affordance or block on design. | **FIXED** — removed the pill. The manage sheet is now opened ONLY from the DESIGNED scoped-collection header's "edit collection" affordance (`scope === 'collection'` in `vreader-library-android.jsx`), which this WI adds to `LibraryScreen` (back breadcrumb → "All", serif collection name, "N books · edit collection" subtitle). |
| `CollectionSheets.kt:268` | Medium | The trailing `DeleteOutline` button is **not faithful** to `CollectionsManageSheet` — the design has no inline delete control; delete lives behind an Edit-mode per-collection detail disclosure that is **not depicted**. Remove it or get delete designed first. | **FIXED** — removed the trash `IconButton` + its `onDelete` wiring + the `DeleteOutline`/`IconButton` imports. Delete UI deferred to **needs-design #1875**. `LibraryViewModel.deleteCollection` retained (commented) as the seam the deferred UI will wire; the delete capability stays repo-backed + tested (`CollectionRepositoryTest`, `LibraryViewModelCollectionsTest` reset-on-delete). |

Auditor explicitly accepted: the inline rename state is a reasonable read of the edit
affordance; the manage sheet hidden-when-empty is acceptable; the tests are fine.

## Round 2 (Codex `bb38tru1f`, gpt-5.5/high) — re-audit of the reworked diff: 1 Medium + 1 Low

Confirmed both round-1 Mediums resolved (the invented nav pill + trash button are gone; the scoped
header is the designed entry). Two NEW findings on the reworked diff:

| file:line | severity | issue | resolution |
|---|---|---|---|
| `LibraryScreen.kt:81` | Medium | The scoped-collection surface still rendered the all-library action row (view-toggle + import pills) ABOVE the back breadcrumb. The committed `scope === 'collection'` design goes from the status strip directly to the back row → title → "N books · edit collection"; the pills are an extra visible surface not in the scoped design. | **FIXED** — moved the nav-pill `Row` INTO the All-only (`else`) branch. The scoped view now renders only the designed `ScopedCollectionHeader` (no pills). |
| `CollectionSheets.kt:1` + `LibraryScreen.kt:1` | Low | The diff pushed both files over the ~300-line convention (`CollectionSheets.kt` 311, `LibraryScreen.kt` 319). | **FIXED** — extracted the manage sheet (`ManageCollectionsSheet`/`ManageSheetContent`/`ManageNewCollectionRow`) AND the scoped header into a new file `library/CollectionManageSheet.kt`. Now: `CollectionSheets.kt` 191, `LibraryScreen.kt` 292, new file ~210 — all under 300. |

## Round 3 (Codex `bcpcx5y6e`, gpt-5.5/high) — confirm the round-2 fixes

**Clean re-audit. No findings.** The auditor confirmed: the scoped view no longer shows nav pills
(round-2 Medium resolved); the All view is unchanged/correct; `ScopedCollectionHeader(collectionName,
bookCount, onBack, onEditCollection)` is a faithful, correct extraction; the file split is clean (no
behavior change, no duplicate/dead code, no broken imports).

## Verdict

**ship-as-is.** Three rounds: round 1 (2 Medium rule-51 — invented nav pill + trash button) →
round 2 (1 Medium scoped-view pills + 1 Low file-size) → round 3 clean. Zero open
Critical/High/Medium/Low. The delete UI is the only deferred item (needs-design #1875), with the
capability repo/VM-backed + tested. Build: main + unit + androidTest compile clean.

## Gate-5 slice verification

`ManageSheetUiTest` (connected, vreader-test AVD API-35): **3/3 tests passed (0 skipped, 0 failed)** —
lists collections + counts, tap-name → inline rename submit, "New Collection" inline-create submit.
Note: the run took 3 attempts to land — the first two TIMEOUT'd at the instrumentation stage because
stale hung `adb shell getprop` processes (accumulated from repeated boot-state probes) congested adbd;
killing those + `adb kill-server/start-server` cleared it and the test passed cleanly. A pure
environment artifact, not a code/test defect (rule 52 contention class). The deferred delete UI
(needs-design #1875) is out of this slice.
