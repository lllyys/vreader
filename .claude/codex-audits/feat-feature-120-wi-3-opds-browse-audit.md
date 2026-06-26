---
branch: feat/feature-120-wi-3-opds-browse
threadId: 019f0405-wi3
rounds: 2
final_verdict: ship-as-is
date: 2026-06-26
---

# Feature #120 WI-3 — Codex audit (OPDS browse screen + error views + browse VM)

Changed files:
- `opds/ui/OpdsBrowseUiState.kt`, `OpdsBrowseViewModel.kt`, `OpdsBrowseScreen.kt`, `OpdsErrorView.kt`
- tests: `OpdsBrowseViewModelTest.kt` (10, Robolectric/JVM), `OpdsBrowseScreenTest.kt` (5) + `OpdsErrorViewTest.kt` (3) instrumented.

## Round 1 — 2 High, 2 Medium, 2 Low

| file:line | severity | issue | resolution |
|---|---|---|---|
| OpdsBrowseViewModel (baseUrl) | High | a single mutable `baseUrl` was shared across pages; page-1 rows recomputed keys/sourceUris/download URLs from it, so a page-2 with a different base could re-key page-1 rows or download against the wrong base | FIXED — entries held as `FeedEntry(entry, base)` capturing each page's own baseUrl; `keyOf`/`importableSourceUris`/`displayFormat`/`download` resolve against `fe.base`, never a global |
| OpdsBrowseViewModel (append) | High | dedupe ran only within a page; `entries + acquisition` could append cross-page duplicates → shared download state, wrong `download(key)` target | FIXED — a `seenKeys` set (cleared on non-append) dedupes across pages by `keyOf`; regression test `loadMore_dedupesDuplicateAcrossPages` |
| OpdsBrowseViewModel (onFeed) | Medium | entries with an acquisition link but none auto-importable (buy/borrow/sample) rendered as Get and only failed on tap | FIXED — `onFeed` filters to `importableLinks(it).isNotEmpty()`; test `nonImportableAcquisition_isNotShownAsBook` |
| OpdsBrowseViewModel (currentUrl) | Medium | `loadMore` set `currentUrl` to the next-page URL, so a later `open()`/`retry()` reloaded page 2 and wiped page-1 nav rows | FIXED — renamed `feedUrl`, updated only when `!append` |
| OpdsBrowseScreen | Low | unused `subtitle` state field / no search trailing | FIXED — removed the unused `subtitle` (OPDS search is out-of-scope per the plan; NavScreen has no subtitle slot) |
| OpdsErrorView | Low | error copy dropped the status code vs the design | (addressed, then re-tuned in round 2 — see below) |

## Round 2 — 2 Low

| file:line | severity | issue | resolution |
|---|---|---|---|
| OpdsBrowseViewModel keyOf | Low | id-less fallback key used the first importable link in feed order → a reordered page could split dedupe | FIXED — fallback now uses the lexically-smallest resolved importable href (order-independent) |
| OpdsErrorView | Low | hardcoded "401"/"404" titles misreport a 403 (→auth) or a parse error (→notfound), since the VM mapping is many-to-one | FIXED — cause-level titles ("Sign-in required" / "Feed not found"); the cause + CTA stay accurate without a false code |

All round-1 High/Medium fixes confirmed correct in round 2 (page-local base carried through keys/import/download, cross-page dedupe present, non-importable filtered, `feedUrl` stable, nav rows survive pagination).

## Summary

2 High + 2 Medium + 4 Low across 2 rounds, all fixed and covered (10 VM + 8 instrumented green on
emulator-5554). **Verdict: ship-as-is.**
