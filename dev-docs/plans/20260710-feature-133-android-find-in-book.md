# Feature #133 — Android find-in-book (in-reader text search) (parity-checklist box F, part 2 of 3)

**Numbering:** box F = #132 (chrome shell + TOC/bookmarks), #133 (this — find-in-book), #134 (More/details/share). Bilingual = #131; library search = #128.

**Deps token (rule 55):** `Deps:[feat:#132, feat:#128]` — #133 reuses #128's `search_sections` FTS4 index (filtered to one book, new query shape) AND hangs its entry point on #132's top-bar Search icon. Both must MERGE before #133 dispatches.

**Design authority (rule 51):** `vreader-search.jsx` — the "This book" scope (search field + grouped results + jump). Every surface depicted; nothing invented.

**Status:** Gate-1 draft (2026-07-10). Gate-2 Codex audit pending.

## 1. Problem

#132's reader top bar has a Search icon, but Android has no in-reader text search. `vreader-search.jsx` depicts a search sheet with a "This book" / "All books" scope toggle; the **"This book"** path is book-scoped full-text search returning matches grouped by chapter with `p.N` badges and jump-to-location rows. iOS ships exactly this as `Services/Search/` (FTS5 `PersistentSearchIndex` + `SearchService.search(query, bookFingerprint, …)` — strictly book-scoped) surfaced through `ReaderSearchCoordinator.swift`. Feature #128 builds a cross-book FTS4 index (`search_sections` + `SearchIndexCoordinator` + extractors EPUB/TXT/MD) but explicitly scopes OUT the in-book surface ("belongs to an in-book search surface — a reader-chrome feature that doesn't exist yet"). #128's `SearchDao.sectionsMatching` returns first-hit-per-book; find-in-book needs ALL hits within one book, grouped by section, with per-hit location — a NEW query shape over the SAME index.

**Design inventory:** `SearchSheet` (search field + Cancel), the "This book" side of the scope toggle (the "All books" side is #128's `SearchScreen` — so on Android the two live in different entry points; reconciliation note in §6), `SearchResultsList` grouped-by-chapter with per-group count + `p.N` badge + `SnippetText` bold match + chevron jump, `NoResults` empty state, recents ("Tap to repeat"). **Scoped out:** operator-syntax chips (`"exact phrase"`, `darcy AND elizabeth`, `chapter:1`, `highlighted:yellow`, `note:`) — #128 already ruled these iOS-only helper copy; the "FTS5" string (Android uses FTS4); highlighted/note filters (needs-design).

**iOS parity:** `ReaderSearchCoordinator.swift`, `SearchResultRow.swift` + `SearchResultGrouping.swift`, `SearchQueryExecutor.swift`, `HighlightedSnippet.swift`.

## 2. Surface area

**Precondition:** #128 merged (`data/SearchDao.kt` FTS4 `search_sections`, `search/SearchIndexCoordinator.kt`, `search/SnippetBuilder.kt`, `search/SearchQueryBuilder.kt`, DB v7) AND #132 merged (`ReaderChromeScaffold` with the top-bar Search callback).

**New — search (`search/`):**
- Additive `SearchDao.allHitsInBook` (in #128's DAO file): `@Query("SELECT s.* FROM search_sections s JOIN search_sections_fts f ON s.rowid = f.rowid WHERE s.bookKey = :bookKey AND search_sections_fts MATCH :ftsQuery ORDER BY s.sectionIndex, s.id LIMIT :limit") suspend fun allHitsInBook(bookKey, ftsQuery, limit: Int = 500): List<SearchSectionEntity>`. The key difference from #128's first-hit-per-book. Order by the unique chunk ordinal (per the #128 audit's ordinal fix) + id. ~+8 lines to #128's DAO.
- `InBookSearchRepository.kt` — `suspend fun hits(bookKey, rawQuery): List<InBookHit>` where `InBookHit(sectionTitle, pageLabel: String?, snippet: AnnotatedString, locator: Locator)`. Builds from `SearchQueryBuilder.ftsQuery` (#128) + `allHitsInBook` + `SnippetBuilder` (#128, token-aware after the #128 audit fix) + a hit→`Locator` resolver; groups by `sectionTitle`. ~120 lines.
- `InBookSearchHitResolver.kt` — maps a matched `SearchSectionEntity` (bookKey + sectionIndex/ordinal + charOffset) to a jump `Locator` per format (EPUB href, TXT/MD charOffset). Mirrors iOS `SearchHitToLocatorResolver.swift`. ~90 lines.
- `InBookSearchViewModel.kt` — debounced query (250 ms), `StateFlow<InBookSearchUiState>` (`Idle`/`Empty`/`Results(groups)`/`NoResults`), recents (reuse #128's `RecentSearchesStore` if present, else a small per-book DataStore with atomic `updateData`). ~120 lines.

**New — UI (`search/`):**
- `InBookSearchSheet.kt` — `@Composable fun InBookSearchSheet(theme, bookTitle, state, query, onQueryChange, onPick, onJump, onDismiss)`. Autofocus field, grouped results (`SearchResultsList`), `NoResults`, recents. testTags `inbook-search-sheet`, `inbook-search-field`, `inbook-result-$section-$i`, `inbook-no-results`, `inbook-recent-$i`. Split into sheet + `InBookSearchRows.kt` (group header + hit row + snippet). ~200 + ~130 lines.

**Modified:**
- `data/SearchDao.kt` (#128) — add `allHitsInBook` (additive; NO schema/migration change, DB stays v7).
- `reader/chrome/ReaderChromeScaffold.kt` (#132) — wire the top-bar Search callback to open `InBookSearchSheet`; `onJump` → the host's `onJumpToLocator`. ~+20 lines.
- Each host's #132 chrome integration — supply the book `fingerprintKey` + jump callback. If #132 threads `onJumpToLocator`, small per host (~+10 each).
- `AppContainer` — expose `InBookSearchRepository`/`ViewModel` factory. ~+10 lines.

**OUT of scope:** #128's index-build path (reused, not modified beyond the additive DAO); PDF/AZW3 find-in-book (#128 doesn't text-index those → Search icon hidden/disabled with a reason); the "All books" scope (#128's `SearchScreen`); operator syntax; highlighted/note filters (needs-design).

## 3. Prior art / project precedent / rejected alternatives

**Prior art:** #128's FTS4 stack (`search_sections`, `SearchQueryBuilder` CJK per-char + operator sanitization, `SnippetBuilder`, `SearchIndexCoordinator`) is the foundation — #133 adds one query shape + a resolver + a book-scoped VM/UI. iOS `SearchQueryExecutor.swift` + `SearchHitToLocatorResolver.swift` + `ReaderSearchCoordinator.swift`. #132's chrome provides the entry point; #132's `onJumpToLocator` provides the jump seam.

**Rejected alternatives:**
1. *A separate per-book FTS index* — #128 already indexes every EPUB/TXT/MD book's sections keyed by `bookKey`; a second index is wasteful/drift-prone. Reuse via `WHERE bookKey = :key`. This is the core sequencing decision: #133 depends on #128.
2. *Reuse #128's `sectionsMatching` (first-hit-per-book)* — find-in-book needs ALL hits grouped by chapter; `allHitsInBook` required.
3. *Operator chips* — #128 ruled these iOS-only helper copy (rule 51); #133 matches.
4. *Find-in-book on PDF/AZW3* — no index (PdfRenderer has no text layer at minSdk 26; AZW3 is a WebView). Hide/disable the Search icon there with a reason (no-dead-control).

## 4. Work-item sequencing

**Tier: foundational = WI-1..WI-3 (persistence-reads/pure — still add per-WI slice where they change search behavior); behavioral = WI-4..WI-5; tail = WI-6.**

**WI-1 (foundational — GATED ON #128 MERGE) — `allHitsInBook` DAO + repository grouping.** Tests (Robolectric, in-memory Room seeded with #128's schema): all hits in one book (not first-per-book); other books excluded; CJK phrase; LIMIT respected; blank query → empty.

**WI-2 (foundational) — hit→locator resolver.** `InBookSearchHitResolver` per format. Tests: EPUB section→href locator; TXT/MD section→charOffset; resolved locator passes `Locator.validate()`; `fingerprintKey` matches.

**WI-3 (foundational) — `InBookSearchViewModel` + recents.** Debounced query, state machine, recents (atomic `updateData`). Tests: debounce coalesces; Idle→Results→NoResults; recents add/dedupe/cap; per-book recents isolation; query cleared → Idle.

**WI-4 (behavioral) — `InBookSearchSheet` UI.** Field + grouped results + snippets + empty/no-results/recents. Tests (Compose): grouped headers + per-group counts; bold snippet; tap → `onJump(locator)`; `inbook-no-results`; recent tap fills query.

**WI-5 (behavioral) — host wiring (Search icon → sheet → jump).** Wire #132's top-bar Search on EPUB/TXT/MD; hide/disable on PDF/AZW3 with reason. Tests (androidTest): EPUB search → hits → tap → navigator jumps; TXT search → scrolls to offset; PDF/AZW3 Search hidden/disabled.

**WI-6 (tail) — acceptance + device verification + tracker.** End-to-end on EPUB + TXT + MD, using the REAL large fixtures (道诡异仙 EPUB / 黑暗血时代 TXT) for CJK find + huge-book responsiveness; box-F partial note; Gate-4/5.

## 5. Test catalogue

| File | Cases |
|---|---|
| `test/.../search/InBookSearchDaoTest.kt` (Robolectric) | all hits in one book (multi-hit, not first-per-book); other books excluded; CJK per-char phrase; multi-term AND; LIMIT; zero hits → empty |
| `test/.../search/InBookSearchRepositoryTest.kt` | group by section; many hits (>200) truncated at LIMIT + count shown; blank→empty; snippet bolding present |
| `test/.../search/InBookSearchHitResolverTest.kt` | EPUB/TXT/MD locator mapping; resolved locator valid; CJK query resolves + snippet segments |
| `test/.../search/InBookSearchViewModelTest.kt` | debounce; state transitions; recents dedupe/cap/isolation; query cleared → Idle |
| `test/.../search/InBookSearchSheetTest.kt` (Compose) | grouped render; bold snippet; tap→onJump; no-results; recent tap; empty query → recents |
| `androidTest/.../reader/EpubFindInBookTest.kt` | fixture EPUB → hits grouped by chapter → tap → navigator href change; CJK find; huge book responsive |
| `androidTest/.../reader/TxtFindInBookTest.kt` | search → scroll to hit offset; zero-hit → no-results |
| `androidTest/.../reader/SearchHiddenOnPdfAzw3Test.kt` | Search hidden/disabled on PDF + AZW3 with reason |

Edge cases: zero hits, many hits (>LIMIT), CJK find, huge book, PDF/AZW3 unavailable.

## 6. Risks + mitigations

1. **Hard dependency on #128 + #132 merging.** `Deps:[feat:#128, feat:#132]` gates dispatch; do NOT build a throwaway index.
2. **PDF/AZW3 have no text index.** Hide/disable Search on those hosts (no-dead-control); honesty boundary, not a bug. A PDF text layer / AZW3 foliate-search bridge are separate follow-ups.
3. **Index staleness / not-yet-indexed book.** #128's coordinator indexes lazily; a fresh book may be unindexed when opened. The sheet observes `search_index_state`; while the current book is unindexed, show an "indexing…" state (or empty-with-hint) and re-query when indexing completes — mirrors #128's audit resolution of the same untruthful-empty concern (do NOT show the definitive "No matches" until the current book is indexed).
4. **CJK snippet/locator fidelity.** #128's per-char CJK segmentation means char-based offsets; the resolver maps segmented offsets back to source offsets (reuse #128's section char offsets). Test CJK explicitly.
5. **Two search entry points diverge** ("This book" here vs #128's "All books" `SearchScreen`). Document the reconciliation — the reader Search icon opens book-scoped `InBookSearchSheet`; the library search opens #128's screen. A unified scope toggle is a needs-design follow-up (the toggle isn't one honest surface until both exist).

## 7. Backward compat

- **DB stays v7** (from #128) — `allHitsInBook` additive, no migration.
- No new schema, no backup-contract change (the FTS index is a local derived cache, rebuilt by #128's coordinator; #128's no-auto-backup exclusion covers it).
- No change to #128's library-search behavior.

## Revision history

- v1 (2026-07-10): Gate-1 draft (box F planner, renumbered #132→#133). Gate-2 Codex audit pending.
