# Feature #133 — Android find-in-book (in-reader text search) (parity-checklist box F, part 2 of 3)

**Numbering:** box F = #132 (chrome shell + TOC/bookmarks, LIVE), #133 (this — find-in-book), #134 (More/details/share, LIVE). Bilingual = #131; library search = #128 (LIVE).

**Deps token (rule 55):** `Deps:[feat:#132, feat:#128]` — both are **already merged and live**. #133 hangs its entry point on #132's top-bar Search icon (the `onOpenSearch` slot, currently a null placeholder), and reuses #128's `search_sections` FTS4 index **for TXT/MD only** (EPUB uses Readium's own search — see §2 two-track model, the round-2 CRITICAL-1 resolution).

**Design authority (rule 51):** `dev-docs/designs/vreader-fidelity-v1/project/vreader-search.jsx` — the "This book" scope (search field + Cancel, This-book/All-books toggle, recents, grouped-by-chapter results, no-results). Placement + icon states are in `.../design-notes/reader-search-and-more-menu.md`. Coverage gaps + resolutions are in §8; the **no-needs-design** conclusion is §9.

**Status:** Gate-1 draft v3.1 (2026-07-12, Gate-2 round-3 audit resolved — the sole remaining Medium closed via a resumable intra-chunk pagination cursor). Gate-2 clean.

---

## 0. Precondition reality (verified against the live tree)

| v1 claim | Reality (verified) |
|---|---|
| #128/#132 "merged (precondition)" | Both are **LIVE on `main`**. A Gate-3-ready dependency, not a gate. |
| `SearchDao` is an interface | **abstract `@Dao class SearchDao`** (`data/SearchDao.kt:25`). New methods are `abstract` (Room-generated) or concrete defaults. |
| `SearchQueryBuilder.ftsQuery` returns the MATCH String | Returns **`BuiltQuery?`** = `{ fts: String, tokens: List<String> }` or null (`search/SearchQueryBuilder.kt:18,27`). `buildFtsParts` is **private** (`:54`). |
| `SnippetBuilder` returns Compose `AnnotatedString` | Returns **`Snippet(text: String, matchRanges: List<IntRange>)`** (`search/SnippetBuilder.kt:12,22`); `findMatches` is **private** and operates on whitespace-COLLAPSED display text (`:68,114`). The Compose layer maps ranges → styled spans. |
| `ReaderChromeScaffold` has `onJumpToLocator`; wire the sheet inside it | It has **`onOpenSearch: (() -> Unit)? = null`** only (`reader/chrome/ReaderChromeScaffold.kt:112`) and forwards it to `ReaderTopChrome(onSearch=…)`. **No `onJumpToLocator` anywhere.** The scaffold owns NO sheet/repo/scope/navigator. |
| TXT/MD host threads a Search callback | `TxtReaderActivity` uses the scaffold with `tocEntries = emptyList()` (no TOC) and **passes no `onOpenSearch`** (defaults null). |
| App wiring is a standalone `AppContainer` file | Wiring is the **`AppContainer` class inside `VReaderApp.kt`**. |
| Locator validation is `Locator.validate()` | Both exist on canonical `vreader.contracts.Locator`: `validate(): LocatorValidationError?` (write-side, used by `ReadiumLocatorReconstructor`) and **`validatedOrNull(): Locator?`** (read-side — `Locator.kt:52,70`). The **constructor requires the identity triple** `contentSHA256`/`fileByteCount`/`format`. |

**Two Locator types coexist (never conflate):** canonical `vreader.contracts.Locator` (TXT/MD scroll targets, persisted position, built with the identity triple) vs Readium `org.readium.r2.shared.publication.Locator` (only inside `ReaderActivity`/`EpubNavigatorFragment.go(readium)`; obtained from **Readium's own APIs** — §2 EPUB track).

**Host architecture (verified):** EPUB `ReaderActivity` does NOT use `ReaderChromeScaffold` — it renders **FOUR ComposeViews** over the Readium `EpubNavigatorFragment` (`popoverOverlay`, `sheetLayer`, `topBand`, `bottomBand` — `ReaderActivity.kt:567,568,586,603`; the "three ComposeViews" file comment is stale — `sheetLayer`/`EpubReaderSheets` is the 4th). The Search slot is owned by `EpubTopBand` in `reader/EpubReaderChrome.kt`, whose signature currently has NO search callback and calls `ReaderTopChrome(...)` WITHOUT `onSearch` (`EpubReaderChrome.kt:80,101`). `ReaderActivity` already holds `publication: Publication?` (`:99`) and `navigator: EpubNavigatorFragment?` (`:98`), and jumps via `nav.go(readiumLocator): Boolean`. It has a real TOC. TXT/MD/AZW3/PDF use `ReaderChromeScaffold`; TXT/MD jump = `listState.scrollToItem(document.chunkForOffset(charOffsetUTF16))`; AZW3 = `Azw3Document.goTo(canonical)`; PDF = `listState.scrollToItem(pageIndex)`. `onOpenSearch` is null in ALL four hosts today.

---

## 1. Problem

#132's reader top bar exposes a Search icon slot (`onOpenSearch`), but it is a null placeholder — Android has no in-reader text search. `vreader-search.jsx` depicts a search sheet whose **"This book"** path is book-scoped full-text search returning matches grouped by chapter with jump-to-location rows. iOS ships exactly this as `Services/Search/` (FTS5 `SearchIndexStore` + PAGINATED `SearchService.search(query, bookFingerprint, page, pageSize)`) surfaced through `ReaderSearchCoordinator.swift`; iOS's `SearchHit` stores `sourceUnitId` (`epub:<href>`) **+ per-hit `matchStartOffsetUTF16`/`matchEndOffsetUTF16`** — i.e. iOS's index carries the href + occurrence offsets that Android's #128 index does NOT.

Feature #128 built a cross-book FTS4 index but scoped OUT the in-book surface. Two hard facts about that index reshape this feature (Gate-2 round-1 CRITICALs, still true):
1. **The index is CHUNK-level, not occurrence-level.** `SearchSectionEntity` (`data/SearchEntities.kt:47`) is a ~4 KB chunk; a chunk with 10 matches is ONE row.
2. **The index carries NO source-location columns** — `bookKey, sectionIndex, chunkOrdinal, sectionTitle, text, indexedText`, with **no EPUB href, no source char offset, no page**.

**The round-2 CRITICALs forced two further decisions (see §2):**
- **EPUB position resolution CANNOT come from the FTS index** (round-2 C1). `sectionIndex` is a running content-iterator counter (incremented on every href-change OR heading — `EpubTextExtractor.kt:93-95`), NOT a spine index, and the href is never persisted, so `sectionIndex → readingOrder[i].href` is not recoverable. And `ReadiumLocatorReconstructor.toReadium` REQUIRES a nonblank `href` (`ReadiumLocatorReconstructor.kt:106`) — a text-quote-only canonical locator resolves to null for every EPUB hit. **Resolution: EPUB uses Readium-Kotlin's own `SearchService` (`publication.search(query)`), which returns real Readium `Locator`s.**
- **`BuiltQuery.tokens` cannot represent FTS occurrences** (round-2 C2). `tokens` is a flat highlight list (a CJK phrase `"编 程"` → `["编","程"]`, prefix-star lives only in `fts`), and `SnippetBuilder.findMatches` is private + operates on whitespace-collapsed display text. **Resolution: a NEW dedicated raw-offset matcher driven by a structured query (phrase/prefix/AND units derived from the FTS build), used for TXT/MD.**

---

## 2. Surface area

### The two-track model (round-2 CRITICAL 1 — EPUB and TXT/MD resolve positions differently)

**EPUB → Readium `SearchService` (NOT the FTS index for position).** **TXT/MD → the #128 FTS index + a runtime resolver.** The FTS index still provides the fast library-wide `search_index_state` and is the source of TXT/MD grouping/counts/snippets; for EPUB it plays no role (Readium's search does it all). This is the honest architecture — each format uses the position engine that actually owns its coordinates.

#### EPUB track — Readium's built-in search (round-2 C1 resolution, evidence-backed)

Readium-Kotlin **3.3.0** (`readium-shared:3.3.0`, `android/app/build.gradle.kts:111-114`) ships a `SearchService`. Verified against the actual runtime jar (`readium-shared-3.3.0-runtime.jar`, `javap`):
- `SearchServiceKt.isSearchable(publication): Boolean` — capability probe.
- `suspend fun Publication.search(query: String, options: SearchService.Options = …): SearchIterator` (the top-level extension) — `@ExperimentalReadiumApi` (the SAME annotation `EpubTextExtractor` already uses).
- `SearchIterator.next(): Try<LocatorCollection, SearchError>` — pages of REAL Readium `Locator`s; `getResultCount(): Int?`; `close()`.
- The default engine `StringSearchService` (+ `IcuAlgorithm`) is bundled, backed by the publication `content` service — the SAME content service `EpubTextExtractor` requires, so `isSearchable` is true for any EPUB Android can already index.
- Each `LocatorCollection.locators[i]` is a `Locator` with `href` (real, resolvable), `title` (the chapter label — grouping key), and `text: Locator.Text(before, highlight, after)` (the snippet, already computed). Verified fields: `Locator.getHref/getTitle/getText`, `Locator.Text.getBefore/getHighlight/getAfter`.

So for EPUB there is **nothing to reconstruct**: `publication.search(q)` → grouped `Locator`s → group by `Locator.title` → snippet from `Locator.text` → jump via `nav.go(locator)` (the `ReaderActivity` already-live path). **No href column, no text-quote reconstruction, no FTS occurrence expansion for EPUB.**

- **`search/EpubInBookSearchEngine.kt`** (NEW) — wraps the Readium seam. `suspend fun search(query, cursor: EpubSearchCursor?, pageSize): InBookSearchPage` and `suspend fun isSearchable(): Boolean`. Drives `SearchIterator.next()` page-by-page (the cursor is the live iterator held per session), maps each `Locator` → `InBookHit(sectionTitle=locator.title, readiumLocator=locator, snippet=locator.text.highlight, before/after)`, groups by `title`. A `PublicationSearchSource` interface seam (mirrors `PublicationLocatorSource` in `ReadiumLocatorReconstructor`) exposes `isSearchable()` + `search()` + `nextPage()` so the engine is unit-testable with a fake iterator (Readium `Publication` is `final`/unmockable). ~130 lines. **`@ExperimentalReadiumApi` opt-in, same as `EpubTextExtractor`.**

**EPUB residual risk (much smaller than v2's):** Readium search is snippet/href-complete and returns canonical Readium locators the navigator jumps to natively — no href-guess, no wrong-resource risk. The residual is only *engine variance*: `StringSearchService` is substring/ICU, not the exact same NFKC+CJK-per-char normalization #128's FTS uses, so EPUB and TXT/MD may differ slightly on exotic folding (e.g. a ß→ss or full-width edge). This is an acceptable per-format engine difference (each uses its native search), documented in §6, and both are correct within their own semantics; a jump that Readium can't produce (`next()` yields empty) simply yields fewer EPUB hits — never a wrong jump.

#### TXT/MD track — FTS index + runtime resolver (round-1 C2 path, unchanged in spirit)

TXT/MD have no Readium publication; they use the #128 FTS index. `TxtDocument.of(decoded.text)` (`reader/TxtDocument.kt`) is a pure, deterministic, offset-addressable function: `sectionIndex == chunkOrdinal == chunk index` (`TxtMdTextExtractor.kt:31-37`); `offsetForChunk(i)` gives the exact UTF-16 start of chunk `i`; `chunkForOffset(offset)` inverts it (the reader's own jump mechanism). So the resolver re-runs `TxtDocument.of`, takes `chunkStart = offsetForChunk(sectionIndex)`, and adds the intra-chunk raw offset from the new matcher (below) → `charOffsetUTF16`. **DB stays v7, no migration, no reindex.**

- **`InBookSearchDao` methods — ADDITIVE to `data/SearchDao.kt`** (the ONLY shared-with-#128 file; extending an existing file needs no regen). Concrete signatures (round-1 HIGH #1/#2/#3):

  ```kotlin
  /**
   * One PAGE of matching chunks for a TXT/MD book, reading-order-stable and cursor-paged. Returns whole
   * SearchSectionEntity chunks (occurrence expansion happens in the repository — FTS4 has no per-occurrence
   * row). Cursor = the (sectionIndex, chunkOrdinal, id) of the prior page's last chunk; first page passes
   * (-1, -1, -1). `s.id = f.rowid` (the LIVE join shape). Ordered by the unique (sectionIndex, chunkOrdinal,
   * id) tuple — reading order, deterministic. FTS4 has NO bm25 → reading-order is the STATED ranking (§6).
   */
  @Query(
      "SELECT s.* FROM search_sections_fts f " +
          "JOIN search_sections s ON s.id = f.rowid " +
          "WHERE search_sections_fts MATCH :ftsQuery AND s.bookKey = :bookKey " +
          "AND ( s.sectionIndex > :afterSectionIndex " +
          "   OR (s.sectionIndex = :afterSectionIndex AND s.chunkOrdinal > :afterChunkOrdinal) " +
          "   OR (s.sectionIndex = :afterSectionIndex AND s.chunkOrdinal = :afterChunkOrdinal AND s.id > :afterId) ) " +
          "ORDER BY s.sectionIndex ASC, s.chunkOrdinal ASC, s.id ASC " +
          "LIMIT :limit",
  )
  abstract suspend fun matchingChunksPage(
      bookKey: String, ftsQuery: String,
      afterSectionIndex: Int, afterChunkOrdinal: Int, afterId: Long, limit: Int,
  ): List<SearchSectionEntity>

  /**
   * The current chunk INCLUSIVELY (round-3 completeness): the first matching chunk AT-OR-AFTER the
   * cursor tuple, so a partially-consumed chunk (cursor.occurrenceIndex > 0) is RE-FETCHED rather than
   * skipped by `matchingChunksPage`'s strict `>`. Same match/order shape, but `>=` on the tuple, LIMIT 1.
   */
  @Query(
      "SELECT s.* FROM search_sections_fts f " +
          "JOIN search_sections s ON s.id = f.rowid " +
          "WHERE search_sections_fts MATCH :ftsQuery AND s.bookKey = :bookKey " +
          "AND ( s.sectionIndex > :atSectionIndex " +
          "   OR (s.sectionIndex = :atSectionIndex AND s.chunkOrdinal > :atChunkOrdinal) " +
          "   OR (s.sectionIndex = :atSectionIndex AND s.chunkOrdinal = :atChunkOrdinal AND s.id >= :atId) ) " +
          "ORDER BY s.sectionIndex ASC, s.chunkOrdinal ASC, s.id ASC LIMIT 1",
  )
  abstract suspend fun chunkAtOrAfter(
      bookKey: String, ftsQuery: String,
      atSectionIndex: Int, atChunkOrdinal: Int, atId: Long,
  ): SearchSectionEntity?

  /** Total matching CHUNK count for a book (the cheap aggregate; NOT an occurrence count). */
  @Query(
      "SELECT COUNT(*) FROM search_sections_fts f JOIN search_sections s ON s.id = f.rowid " +
          "WHERE search_sections_fts MATCH :ftsQuery AND s.bookKey = :bookKey",
  )
  abstract suspend fun matchingChunkCount(bookKey: String, ftsQuery: String): Int

  /** Per-book index-state as an OBSERVABLE Flow (round-1 MEDIUM #1 — the existing indexState() is one-shot). */
  @Query("SELECT * FROM search_index_state WHERE bookKey = :bookKey")
  abstract fun observeIndexState(bookKey: String): Flow<SearchIndexStateEntity?>
  ```
  (~+30 lines to `data/SearchDao.kt`; NO schema change, DB stays v7.)

- **`search/StructuredQuery.kt`** (NEW — the round-2 C2 core). `SearchQueryBuilder` gains a public `fun structuredQuery(raw: String): StructuredQuery?` that returns typed units instead of the flat `tokens` — reusing the SAME normalize/segment/sanitize pipeline `ftsQuery` uses, and the SAME `buildFtsParts` grouping (promoted to feed both). `StructuredQuery(units: List<QueryUnit>)` where `QueryUnit` = `Phrase(tokens: List<String>)` (a CJK per-char run — must match IN ORDER, contiguous), `PrefixTerm(token: String)` (the final Latin bareword — matches a prefix), or `Term(token: String)` (an implicit-AND bareword — matches whole-token). This is the structured representation the flat `tokens` cannot express. ~40 lines added to `SearchQueryBuilder.kt` + a small `StructuredQuery` data-class file. **Additive; `ftsQuery`/`BuiltQuery`/`tokens` are untouched (the library `SearchRepository` keeps using them).**

- **`search/RawOffsetMatcher.kt`** (NEW — the round-2 C2 dedicated matcher). `fun occurrences(rawChunkText: String, query: StructuredQuery, fromOccurrenceIndex: Int, maxThisPage: Int): RawOccurrenceSlice` where `RawOccurrence(rawStartUTF16: Int, rawEndUTF16: Int, occurrenceIndex: Int)` are offsets into the **RAW `text`** (NOT display-collapsed) tagged with their 0-based position in the chunk's deterministic occurrence enumeration, and `RawOccurrenceSlice(occurrences: List<RawOccurrence>, nextOccurrenceIndex: Int?)`. The matcher enumerates the chunk's occurrences DETERMINISTICALLY in start order, **SKIPS the first `fromOccurrenceIndex`**, and emits at most `maxThisPage` — `nextOccurrenceIndex` is non-null iff the chunk has MORE un-emitted occurrences past this slice (the resume point on the next page; null = the chunk is fully consumed). **`maxThisPage` is a per-PAGE WINDOW bound, NOT a per-chunk truncation — round-3 MEDIUM: no occurrence is ever dropped.** A repetitive chunk with, say, 40 occurrences is emitted across successive pages (page 1: indices 0..k-1, `nextOccurrenceIndex=k`; page 2 resumes at k; …) because the repository threads `occurrenceIndex` through the pagination cursor (§"pagination completeness" below). Algorithm: scan the raw chunk by code point; at each position attempt to match the WHOLE structured query starting there, honoring:
  - **`Phrase(tokens)`** — the normalized raw substring must equal the tokens joined in order (CJK: each token is one code point, contiguous, no intervening non-CJK); grows the raw span code-point-by-code-point, normalizing each candidate, until it covers the phrase (the `SnippetBuilder.matchAt` growth idea, but phrase-aware and against raw offsets).
  - **`PrefixTerm(token)`** — the normalized raw word STARTS WITH the token (prefix), bounded by a word/space/CJK boundary.
  - **`Term(token)`** — the normalized raw word EQUALS the token.
  - **AND across units** — an occurrence is anchored on the FIRST unit's raw span (that is the jump target + highlight); the remaining units need only be PRESENT in the chunk (the chunk already matched via FTS `implicit-AND`, so presence holds — the matcher's job is to locate a concrete anchor, not re-verify AND).
  - **Overlap/dedupe** — non-overlapping, start-ordered; the enumeration order (which defines `occurrenceIndex`) is the deterministic start order, so the same `fromOccurrenceIndex` always resumes at the same occurrence across page requests.
  - Edge cases: surrogate pairs (never split a pair — advance by `Character.charCount`); NFKC/ß→ss/combining-mark folding (normalize each candidate window, so a raw `ß` folds to `ss` before compare); a folded-only match with no locatable raw anchor → 0 occurrences (the repository falls back to the section head, no jump offset — honest). ~160 lines.

- **`search/InBookSearchModels.kt`** (NEW) — DTOs: `RawOccurrence`, `RawOccurrenceSlice`, `InBookHit(sectionTitle: String?, canonicalLocator: Locator? /* TXT/MD */, readiumLocator: ReadiumLocator? /* EPUB */, snippet: String, matchRanges: List<IntRange>)`, `InBookGroup(title: String, hits: List<InBookHit>)`, `InBookSearchPage(groups, nextCursor: SearchCursor?, matchingChunkCount: Int?, moreAvailable: Boolean)`, `SearchCursor` (sealed: **`Fts(sectionIndex, chunkOrdinal, id, occurrenceIndex)` for TXT/MD — the `occurrenceIndex` is the round-3 completeness field: it is the next un-emitted occurrence WITHIN the chunk `(sectionIndex, chunkOrdinal, id)`, so a partially-consumed repetitive chunk RESUMES rather than being skipped**; `Epub(iteratorToken)` for EPUB), `InBookSearchUiState` (sealed: `Idle` / `Indexing` / `Results(groups, moreAvailable)` / `NoResults` / `Error`). Exactly ONE of the two locator fields is non-null per hit; the host jumps by whichever is present. ~70 lines.

- **`search/TxtMdInBookHitResolver.kt`** (NEW) — TXT/MD resolver: re-decode via `TxtDecoder.decode(file)` + `TxtDocument.of(text)` (memoized per session), `charOffsetUTF16 = offsetForChunk(section.sectionIndex) + occ.rawStartUTF16`, build canonical `Locator(triple, charOffsetUTF16, charRangeStart/End)`, `validatedOrNull()`. ~80 lines.

- **`search/InBookSearchRepository.kt`** (NEW) — the FORMAT-DISPATCHING boundary. `suspend fun page(bookKey, format, rawQuery, cursor: SearchCursor?, pageSize): InBookSearchPage`. For **EPUB** → delegates to `EpubInBookSearchEngine` (Readium). For **TXT/MD** → `SearchQueryBuilder.ftsQuery(raw)` (round-1 MEDIUM #2 — always via it; null/operator-only → empty page, no MATCH) drives `matchingChunksPage`, then `SearchQueryBuilder.structuredQuery(raw)` + `RawOffsetMatcher` expands each chunk, `TxtMdInBookHitResolver` builds the canonical locator, group by "Section N". Cancellation-cooperative (`coroutineContext.isActive` — round-1 MEDIUM #4). ~160 lines.

  **Pagination completeness — resume WITHIN a chunk (round-3 MEDIUM, the append-on-scroll completeness contract).** The FTS cursor is `Fts(sectionIndex, chunkOrdinal, id, occurrenceIndex)`. A page fills to `pageSize` occurrences (NOT `pageSize` chunks): the repository starts at the cursor's chunk with `RawOffsetMatcher.occurrences(rawText, query, fromOccurrenceIndex = cursor.occurrenceIndex, maxThisPage = remainingBudget)`; if that chunk still has more occurrences than the page budget, the page's `nextCursor = Fts(sameChunk, occurrenceIndex = slice.nextOccurrenceIndex)` — the SAME chunk repeats on the next page, resuming at the next un-emitted occurrence, so NO occurrence is skipped. Only once a chunk is fully consumed (`slice.nextOccurrenceIndex == null`) does the repository advance to the next chunk via `matchingChunksPage(afterSectionIndex=…, afterChunkOrdinal=…, afterId=…)` and reset `occurrenceIndex = 0`. To fetch the current partially-consumed chunk again the repository re-queries it INCLUSIVELY (a `chunkAtOrAfter` DAO variant, WI-1) so `> :afterId` doesn't skip it. `moreAvailable = (nextCursor != null)`. **Every occurrence in every matched chunk is eventually retrievable across pages — bounded per page, complete across pages; the cap is a per-page window, never a truncation.** (An internal per-chunk hard ceiling still exists ONLY as an OOM guard set far above any realistic occurrence count — e.g. 100 000; it is a memory-safety bound, not a product limit, and normal content never reaches it.)

- **`search/InBookSearchViewModel.kt`** (NEW) — `viewModelScope`; `trim → debounce(250 ms) → distinctUntilChanged → flatMapLatest` (cancel-on-new-query), tagged-query rejection (discard a stale batch whose query ≠ live query — the live library `SearchViewModel` pattern, round-1 MEDIUM #4), combines with `observeIndexState(bookKey)` for TXT/MD so a HELD query re-runs when the current book settles (EPUB is never "indexing" — Readium search is synchronous over an open publication, so EPUB skips the Indexing gate), `Error` state on failure, recents, append-on-scroll paging (`loadMore()` advances the cursor). Dismiss-only-after-successful-jump is the HOST's contract. ~160 lines.

### New — UI (`search/` Compose)

- **`search/InBookSearchSheet.kt`** (NEW) — `@Composable fun InBookSearchSheet(theme, bookTitle, state, query, onQueryChange, onPickRecent, onJump: (InBookHit) -> JumpResult, onLoadMore, onDismiss)`. Autofocus field + Cancel (design), grouped results (append-on-scroll — `onLoadMore` when the last group nears the viewport, NO disclosure row — §8/§9 M2 resolution), `Indexing` hint (TXT/MD only), `NoResults`, recents. testTags `inbook-search-sheet`, `-field`, `-result-$group-$i`, `-no-results`, `-indexing`, `-recent-$i`. ~200 lines.
- **`search/InBookSearchRows.kt`** (NEW) — group header (serif title + per-group count) + hit row (snippet with bold `matchRanges` spans + chevron; NO `p.N` badge — §8, iOS precedent). ~130 lines.

### Modified (existing files — each host owns its own search state)

- **`data/SearchDao.kt`** (#128) — add the 3 methods above (additive; DB stays v7).
- **`search/SearchQueryBuilder.kt`** (#128) — add the public `structuredQuery(raw): StructuredQuery?` + promote the private grouping so both `ftsQuery` and `structuredQuery` share it (round-2 C2). Additive; existing `ftsQuery`/`BuiltQuery` untouched. ~+40 lines.
- **`reader/TxtReaderActivity.kt`** — own `InBookSearchViewModel` + render `InBookSearchSheet` overlay + pass `onOpenSearch` to its `ReaderChromeScaffold` call + resolve a picked hit via `listState.scrollToItem(document.chunkForOffset(hit.canonicalLocator!!.charOffsetUTF16!!))`. ~+40 lines.
- **`reader/ReaderActivity.kt`** (EPUB) — own `InBookSearchViewModel` (with the Readium engine) + render the search sheet in the **existing `sheetLayer` ComposeView** (the 4th overlay, already present) + resolve a picked hit via `nav.go(hit.readiumLocator!!): Boolean` → `JumpResult`. ~+55 lines.
- **`reader/EpubReaderChrome.kt`** (round-2 MEDIUM #1) — add `onSearch: (() -> Unit)?` to `EpubTopBand` + pass it to `ReaderTopChrome(onSearch = onSearch, …)` (currently omitted at `:101`). ~+5 lines.
- **`reader/chrome/ReaderChromeScaffold.kt`** — NO CHANGE; `onOpenSearch` already exists. TXT/MD (and, if ever indexed, AZW3/PDF) hosts pass a non-null callback; the scaffold already forwards it. (round-1 HIGH #5 — sheet ownership is the host's; the scaffold stays a pure signal.)
- **`VReaderApp.kt` (`AppContainer` class)** — expose an `inBookSearchViewModelFactory(bookKey, format, file, publicationProvider)` — for TXT/MD it wires `SearchRepository` + the resolver; for EPUB it wires the `EpubInBookSearchEngine` over the host's live `publication`. ~+20 lines.

**OUT of scope:** #128's index-build path (reused for TXT/MD, not modified beyond the additive DAO); **PDF/AZW3 find-in-book** — no text index and no Readium publication → the Search icon is **HIDDEN** on those hosts (they never pass `onOpenSearch`, exactly as today — no-dead-control); the "All books" scope (#128's `SearchScreen`); operator syntax; highlighted/note filters. **A migration to persist EPUB href/offset columns is NOT NEEDED and NOT taken** (Readium search obviates it — see §3 rejected-alt #4).

---

## 3. Prior art / project precedent / rejected alternatives

**Prior art:** #128's FTS4 stack (`SearchSectionEntity`/`SearchDao`, `SearchQueryBuilder`, `SnippetBuilder`, `SearchTextNormalizer`, `TxtDocument`) is the TXT/MD foundation; Readium-Kotlin 3.3.0's `SearchService`/`StringSearchService` is the EPUB foundation (proven present in the runtime jar); `ReadiumLocatorReconstructor` (#135) is NOT used here (its href requirement is what ruled out the FTS-text-quote path for EPUB — round-2 C1). iOS parity: `SearchService` (paginated, book-scoped, `SearchHit` carries href + occurrence offsets — richer than Android's FTS index, which is why EPUB pivots to Readium's own search), `SearchResultsGroupedList` (which DROPPED the design's `p.N` badge).

**Rejected alternatives:**
1. **A separate per-book FTS index** — #128 already indexes TXT/MD by `bookKey`; reuse via `WHERE s.bookKey = :key`.
2. **Reuse #128's `firstHitsPerBook`** — needs ALL occurrences grouped by chapter; the new `matchingChunksPage` + `RawOffsetMatcher` is required (TXT/MD).
3. **Parse FTS4 `offsets()` for per-occurrence positions** (round-1 C1) — byte offsets into the normalized/segmented `indexedText`, not raw UTF-16; no mapping table. Rejected for a raw re-scan (`RawOffsetMatcher`).
4. **Resolve EPUB hits from the FTS index (via `sectionIndex→href` or a persisted href column + Room migration)** (round-2 C1) — REFUTED as unrecoverable AND unnecessary: `sectionIndex` is a content-iterator counter, not a spine index (`EpubTextExtractor.kt:93-95`), and the href isn't stored; and Readium's `publication.search()` already returns real href-bearing, snippet-bearing Locators. A migration+reindex to add an href column would be expensive work to reproduce, worse, what Readium gives for free. **Not taken — DB stays v7.**
5. **Build EPUB occurrences from `BuiltQuery.tokens`** (round-2 C2) — the flat `tokens` can't express phrase/prefix/AND; and EPUB doesn't use the FTS occurrence path at all now (Readium search). For TXT/MD, a NEW `StructuredQuery` + `RawOffsetMatcher` replaces the flawed "reuse SnippetBuilder's private matcher" idea.
6. **Operator chips / "FTS5" helper copy** — iOS-only helper text (rule 51); Android sanitizes operators.
7. **Find-in-book on PDF/AZW3** — no index, no Readium publication; hide the Search icon (no-dead-control).

---

## 4. Work-item sequencing (12 atomic WIs)

Every WI enumerates its **exact new/modified files**. **All impl classes are NEW Kotlin files → single-writer ownership; a new Kotlin file IS dispatchable via a Gradle source-set glob** (unlike iOS). Tier: **foundational = WI-1..WI-8** (pure/persistence-read/DTO); **behavioral = WI-9..WI-11**; **tail = WI-12**. WI-10/WI-11 modify DIFFERENT host files (disjoint), except the single `AppContainer` in `VReaderApp.kt` (serialize that one edit at integration).

**WI-1 (foundational) — DAO query + count + pagination (TXT/MD).** `matchingChunksPage`, `chunkAtOrAfter`, `matchingChunkCount`, `observeIndexState` in `data/SearchDao.kt`. `chunkAtOrAfter` re-fetches the CURRENT chunk INCLUSIVELY (round-3 completeness — so a partially-consumed chunk can be resumed at its next occurrence without the `> :afterId` exclusive bound skipping it): same query as `matchingChunksPage` but with `>=` on the `(sectionIndex, chunkOrdinal, id)` tuple and `LIMIT 1`.
- Files: **M** `data/SearchDao.kt`; **N** `test/.../data/InBookSearchDaoTest.kt`.
- Tests (Robolectric, in-memory Room): all matching chunks in one book; other books excluded; cursor paging disjoint/ordered/gapless; last page empty; `matchingChunkCount`; `chunkAtOrAfter` returns the SAME chunk when the cursor still points into it (resume path); `s.id = f.rowid`; `observeIndexState` null→row.

**WI-2 (foundational) — structured query (round-2 C2 half 1).** Public `SearchQueryBuilder.structuredQuery` + shared grouping + `StructuredQuery` model.
- Files: **M** `search/SearchQueryBuilder.kt`, **N** `search/StructuredQuery.kt`, **N** `test/.../search/StructuredQueryTest.kt`.
- Tests: CJK run → one `Phrase`; final Latin bareword → `PrefixTerm`; other barewords → `Term`; AND/OR/NOT quoted (not operators); special-only → null; blank → null; mixed CJK+Latin ordering; `ftsQuery` output UNCHANGED (regression).

**WI-3 (foundational) — raw-offset matcher (round-2 C2 half 2).** `RawOffsetMatcher` over raw text with `StructuredQuery`, cursor-resumable within a chunk.
- Files: **N** `search/RawOffsetMatcher.kt`, **N** `search/InBookSearchModels.kt` (`RawOccurrence`, `RawOccurrenceSlice`, `SearchCursor` + DTOs), **N** `test/.../search/RawOffsetMatcherTest.kt`.
- Tests: N occurrences in one chunk; RAW UTF-16 span exact (NOT display-collapsed); surrogate-pair never split; ß→ss; NFKC full-width→half; combining marks; tight CJK phrase span (关于**编程**的书 → 编程 only); prefix-term boundary; overlapping-match dedupe; folded-only-no-raw-anchor → 0 (head fallback). **Completeness (round-3 MEDIUM — NOT a truncation test): a chunk with 40 occurrences, requested with `maxThisPage=10`, is retrieved IN FULL across 4 successive calls that thread `fromOccurrenceIndex` (0→10→20→30) — the union of all slices equals all 40 occurrences in order, with no gap and no duplicate, and the 4th slice's `nextOccurrenceIndex == null`; `occurrenceIndex` is stable across calls so a resume lands on the exact next occurrence.**

**WI-4 (foundational) — TXT/MD hit resolver.** `InBookSearchHitResolver` interface + `TxtMdInBookHitResolver`.
- Files: **N** `search/InBookSearchHitResolver.kt`, **N** `search/TxtMdInBookHitResolver.kt`, **N** `test/.../search/TxtMdInBookHitResolverTest.kt`.
- Tests: `TxtDocument.of` re-derivation matches the extractor's boundaries (extract→resolve→`chunkForOffset` round-trip returns the same chunk); `charOffsetUTF16 = offsetForChunk(sectionIndex) + rawStart`; `validatedOrNull()` non-null; fingerprint match; CJK offset exact; edge chunk.

**WI-5 (foundational) — EPUB Readium search engine (round-2 C1).** `EpubInBookSearchEngine` + the `PublicationSearchSource` seam.
- Files: **N** `search/EpubInBookSearchEngine.kt`, **N** `test/.../search/EpubInBookSearchEngineTest.kt`.
- Tests (fake `PublicationSearchSource` — Readium `Publication` is final): `isSearchable` gates; `next()` pages mapped to `InBookHit` (title→group, `Locator.text.highlight`→snippet, `readiumLocator` set); grouped by `Locator.title`; empty iterator → NoResults; iterator exhaustion → `moreAvailable=false`; a `SearchError` → `Error`; CJK query passes through.

**WI-6 (foundational) — repository (format dispatch + group projection).** `InBookSearchRepository` routes EPUB→engine, TXT/MD→FTS+matcher+resolver.
- Files: **N** `search/InBookSearchRepository.kt`, **N** `test/.../search/InBookSearchRepositoryTest.kt`.
- Tests: EPUB path delegates to the engine (fake); TXT/MD path groups by "Section N", expands a multi-hit chunk, advances the FTS cursor; **resume-within-chunk completeness (round-3 MEDIUM): a single chunk with more occurrences than `pageSize` is emitted across successive `page(...)` calls that thread the `Fts(...,occurrenceIndex)` cursor — the union across pages equals every occurrence in that chunk (no gap, no duplicate), `nextCursor` stays on the same chunk until it is fully consumed, then advances via `chunkAtOrAfter`→`matchingChunksPage` with `occurrenceIndex=0`; `moreAvailable` false only when the whole book is exhausted**; blank→empty (no MATCH); MATCH-char safety (round-1 M2: quotes/`*`/parens/colon/caret/leading-`-`/AND-OR-NOT case/special-only→null/very-long all via `SearchQueryBuilder`); cancellation mid-expansion.

**WI-7 (foundational) — per-book index-state → UI state (TXT/MD).** `observeIndexState` gate; EPUB bypasses it.
- Files: **M** `search/InBookSearchRepository.kt` (or a thin `IndexStateGate` in models), **N** `test/.../search/InBookIndexStateTest.kt`.
- Tests: TXT/MD missing/indexing→Indexing (not false NoResults); indexed+0→NoResults; skipped_unsupported→hidden-icon flag; failed→retry; held query re-runs on settle; EPUB never enters Indexing.

**WI-8 (foundational) — ViewModel + recents + append-on-scroll paging.** `InBookSearchViewModel`.
- Files: **N** `search/InBookSearchViewModel.kt`, **N** `test/.../search/InBookSearchViewModelTest.kt`.
- Tests: debounce; flatMapLatest cancel; stale-tag discard; reset-on-change; TXT/MD index-state flip re-run; error state; `loadMore()` appends the next page (both tracks); recents dedupe/cap 8 (GLOBAL `RecentSearchesStore` — §6); cleared→Idle.

**WI-9 (behavioral) — sheet + rows UI.** `InBookSearchSheet` + `InBookSearchRows`.
- Files: **N** `search/InBookSearchSheet.kt`, **N** `search/InBookSearchRows.kt`, **N** `test/.../search/InBookSearchSheetTest.kt` (Compose/Robolectric).
- Tests: autofocus+Cancel; grouped headers+counts; bold snippet; tap→`onJump(hit)`; append-on-scroll fires `onLoadMore` near the end; Indexing hint (TXT/MD); NoResults; recent tap fills query.

**WI-10 (behavioral) — TXT/MD host wiring.** `TxtReaderActivity` owns the VM, renders the sheet, passes `onOpenSearch`, resolves via chunk scroll.
- Files: **M** `reader/TxtReaderActivity.kt`, **M** `VReaderApp.kt` (factory), **N** `androidTest/.../reader/TxtFindInBookTest.kt`.
- Tests (emulator): Search icon on TXT; type→hits→tap→scroll-to-offset; zero-hit→NoResults; MD parity.

**WI-11 (behavioral) — EPUB host wiring (round-2 C1 + M1).** `ReaderActivity` renders the sheet in `sheetLayer`, `EpubTopBand` gets `onSearch`, resolves via `nav.go`.
- Files: **M** `reader/ReaderActivity.kt`, **M** `reader/EpubReaderChrome.kt` (round-2 M1 — the `EpubTopBand` `onSearch` edit), **M** `VReaderApp.kt` (factory — serialize with WI-10 on this one file), **N** `androidTest/.../reader/EpubFindInBookTest.kt`.
- Tests (emulator): Search icon on the EPUB top band (now that `EpubTopBand` forwards `onSearch`); type→grouped-by-chapter hits (from Readium search)→tap→`nav.go` lands (href/progression changes); CJK find on a real CJK EPUB; a no-Readium-locator query yields fewer hits, sheet stays usable.

**WI-12 (tail) — acceptance + verification + tracker.** End-to-end on EPUB (Readium search) + TXT + MD (FTS+resolver) with REAL large fixtures (道诡异仙 EPUB / 黑暗血时代 TXT) for CJK find + huge-book responsiveness; confirm PDF/AZW3 show NO Search icon; box-F partial note; Gate-4 + Gate-5 evidence file.
- Files: **N** `dev-docs/verification/feature-133-<date>.md`; + `androidTest/.../reader/SearchHiddenOnPdfAzw3Test.kt`.

---

## 5. Test catalogue

| File | Cases |
|---|---|
| `test/.../data/InBookSearchDaoTest.kt` | matching chunks in one book; other books excluded; cursor disjoint/ordered/gapless; last page empty; `chunkAtOrAfter` re-fetches the current chunk (resume); count; `s.id=f.rowid`; `observeIndexState` |
| `test/.../search/StructuredQueryTest.kt` | CJK→Phrase; final Latin→PrefixTerm; others→Term; keyword-quote; special-only→null; blank→null; mixed order; `ftsQuery` regression-unchanged |
| `test/.../search/RawOffsetMatcherTest.kt` | multi-occurrence; RAW span (not collapsed); surrogate; ß→ss; NFKC width; combining; tight CJK phrase; prefix boundary; overlap dedupe; folded-only→0; **completeness: 40-occurrence chunk retrieved in full across paged `fromOccurrenceIndex` calls (union = all 40, no gap/dupe, last slice `nextOccurrenceIndex==null`)** |
| `test/.../search/TxtMdInBookHitResolverTest.kt` | chunk round-trip; offset math; valid locator; fingerprint; CJK; edge chunk |
| `test/.../search/EpubInBookSearchEngineTest.kt` | isSearchable gate; paged `next()`→InBookHit; title grouping; snippet from `Locator.text`; empty→NoResults; exhaustion→moreAvailable=false; SearchError→Error; CJK |
| `test/.../search/InBookSearchRepositoryTest.kt` | EPUB delegates; TXT/MD group+expand+cursor; resume-within-chunk completeness (over-`pageSize` chunk emitted across pages, union = all its occurrences, advances only when consumed); blank→empty; MATCH-char safety; cancellation |
| `test/.../search/InBookIndexStateTest.kt` | TXT/MD indexing→Indexing; indexed+0→NoResults; skipped_unsupported; failed→retry; re-run on settle; EPUB bypasses |
| `test/.../search/InBookSearchViewModelTest.kt` | debounce; flatMapLatest; stale-tag; reset; re-run; error; loadMore append (both tracks); recents; cleared→Idle |
| `test/.../search/InBookSearchSheetTest.kt` (Compose) | autofocus+Cancel; grouped render+counts; bold snippet; tap→onJump; append-on-scroll; Indexing; NoResults; recent tap |
| `androidTest/.../reader/TxtFindInBookTest.kt` | Search icon on TXT; type→hits→scroll-to-offset; zero→NoResults; MD parity |
| `androidTest/.../reader/EpubFindInBookTest.kt` | Search icon on EPUB; Readium-search hits grouped→tap→nav.go href change; CJK find; no-locator query stays usable |
| `androidTest/.../reader/SearchHiddenOnPdfAzw3Test.kt` | Search icon ABSENT on PDF + AZW3 |

Edge cases: zero hits; many hits (append-on-scroll paging, both tracks); **a single highly-repetitive chunk with more occurrences than one page — all retrievable across pages via the intra-chunk cursor, none dropped**; CJK find; huge book; TXT/MD current book not-yet-indexed (Indexing, not false NoResults); PDF/AZW3 (icon hidden); rapid typing (debounce + stale-tag); special MATCH chars (TXT/MD via `SearchQueryBuilder`); EPUB engine-variance (fewer hits, never wrong jump).

---

## 6. Risks + mitigations

1. **Dep on #128 + #132 (both LIVE).** Reuse `search_sections` (TXT/MD) via `WHERE bookKey`; hang on #132's `onOpenSearch`. Not a gate.
2. **The FTS index is chunk-level + location-less** (round-1 C1+C2). TXT/MD resolved by `RawOffsetMatcher` (raw re-scan) + `TxtDocument.offsetForChunk`. EPUB does NOT use the FTS index for position (risk 3). DB stays v7.
3. **EPUB position resolution** (round-2 C1). Uses Readium `publication.search()` — real href+title+snippet+navigable Locators; `sectionIndex→href` was unrecoverable and is not needed. Residual: engine variance (Readium ICU/substring vs FTS NFKC+CJK) may differ on exotic folding — acceptable per-format difference, never a wrong jump (a missing Readium locator = fewer EPUB hits). Verified against the 3.3.0 runtime jar (`SearchService`/`StringSearchService`/`SearchIterator.next()→LocatorCollection`).
4. **Occurrence representation** (round-2 C2). TXT/MD uses a NEW `StructuredQuery` (phrase/prefix/AND) + `RawOffsetMatcher` over raw text — NOT the flat `BuiltQuery.tokens`, NOT the private `SnippetBuilder.findMatches`. EPUB uses Readium's `Locator.text` directly (no occurrence math).
5. **PDF/AZW3 have no index + no Readium publication.** Search icon HIDDEN (no-dead-control).
6. **TXT/MD index staleness.** `observeIndexState(bookKey)` → `Indexing`; definitive `NoResults` only when `indexed`. EPUB is synchronous (no Indexing).
7. **FTS4 has no ranking** (TXT/MD). Reading-order (`sectionIndex, chunkOrdinal, id`, then intra-chunk `occurrenceIndex`) is the stated ranking; append-on-scroll pagination over that cursor. **No silent hit loss (round-3 MEDIUM):** the cursor carries the intra-chunk occurrence index, so a highly-repetitive chunk resumes across pages rather than truncating at a per-chunk cap — every occurrence is bounded per page but COMPLETE across pages (§8/§9 M2). No truncation surface; results just load as you scroll.
8. **CJK fidelity.** TXT/MD: `RawOffsetMatcher` phrase-matches CJK per-char runs tight + offset-exact. EPUB: Readium ICU handles CJK. Tested on the 道诡异仙/黑暗血时代 fixtures.
9. **Two search entry points** ("This book" here vs #128 "All books"). Documented; a unified toggle is a needs-design follow-up.

**Recents decision (round-1 M5):** reuse the GLOBAL `RecentSearchesStore` (design shows no per-book persistence; matches iOS).

---

## 7. Backward compat

- **DB stays v7.** All new DAO methods are additive over the existing FTS4 tables; no migration, no reindex, no schema change (the round-2 C1 EPUB pivot to Readium search REMOVED the only thing that had threatened v7 — a persisted href column). Normal per-PR version bump only.
- No new schema, no backup-contract change (FTS index is a local derived cache; recents per-device).
- No change to #128's library-search behavior (`ftsQuery`/`BuiltQuery`/`firstHitsPerBook`/`SearchScreen`/`SearchViewModel` untouched; `structuredQuery` is additive).

---

## 8. Rule-51 design gate — coverage + resolutions

`vreader-search.jsx` + `reader-search-and-more-menu.md` cover: search field + Cancel; This-book/All-books toggle; recents ("Tap to repeat"); grouped-by-chapter results (top "N matches in M chapters" count, per-group serif header + right-aligned count, per-row snippet + chevron); `NoResults`; Search-icon placement + states.

| State | Depicted? | Resolution (rule 51) |
|---|---|---|
| Field + Cancel + This-book toggle | YES | As depicted. |
| Recents ("Tap to repeat") | YES | As depicted (global recents — §6). |
| Grouped results + counts + snippet + chevron | YES | As depicted. |
| `NoResults` | YES | As depicted; TXT/MD gated on `indexed`. |
| **`p.N` per-row page badge** | STATIC MOCK (hardcoded) | **NOT honestly derivable** (no page/progression; EPUB pagination viewport-dependent; TXT/MD no physical page). **iOS DROPPED it** (`SearchResultsGroupedList.swift`: "the design's `p.{page}` per-result badge is dropped; the group header carries the location instead"). **Omit `p.N`, the group header carries the location** — matching the shipped iOS surface for the SAME feature; removes a data-less mock, invents nothing. |
| **"Indexing…" (TXT/MD not yet indexed)** | NO (only definitive NoResults depicted) | **Reuse the designed `NoResults` empty container with honest hint copy** (the #128 shipped honest-empty pattern; same container, different string). Not a new surface. |
| **Hidden Search control on PDF/AZW3** | Icon depicted present | **HIDE the icon** (no-dead-control — host omits `onOpenSearch`, the shipped #129/#132/#134 pattern). Hiding is the established pattern, not a "disabled with a reason" new surface. |
| **Large result sets** | NO | **Append-on-scroll pagination, NO disclosure row** (M2 choice (a) — see §9). Pagination is **complete** (round-3 MEDIUM): the cursor threads the intra-chunk `occurrenceIndex`, so results are bounded PER PAGE but every occurrence — even in a highly-repetitive chunk — is retrievable across successive pages; nothing is truncated or dropped. The only hard bound is an internal OOM ceiling set far above any realistic occurrence count (a memory-safety guard, not a product limit). Results simply load as you scroll — the grouped list already implies this. No new visible message. |
| **Jump-failure (EPUB `nav.go` false / no Readium locator)** | NO | **Sheet STAYS OPEN, no new UI** (the #132/#135 navigation-outcome posture — `JumpResult.Failed` → the user picks another hit). No toast/error surface. |

---

## 9. needs-design conclusion — **NO** (all states resolve within committed design + existing patterns)

**No `needs-design` issue is required.** Explicitly:
- `p.N` → **omitted**, matching shipped iOS.
- "Indexing…" (TXT/MD) → the **designed `NoResults` container + honest hint copy** (#128 pattern).
- PDF/AZW3 → **hidden icon** (no-dead-control, shipped pattern).
- **Large result sets → M2 CHOICE (a): pure append-on-scroll pagination with NO disclosure row, and (round-3 MEDIUM) COMPLETE pagination — no silent truncation.** The intra-chunk `occurrenceIndex` is part of the cursor, so every occurrence (even in a highly-repetitive chunk) is retrievable across successive pages; page size is a per-PAGE window, not a per-chunk truncation. Results just load as the user scrolls the grouped list (a standard interaction the design's scrollable grouped list already implies). The only hard bound is an internal OOM ceiling far above any realistic occurrence count (memory-safety, not a product limit). **No new visible message/state is introduced, so rule 51 is satisfied without a design.**
- Jump-failure → **sheet stays open** (#132/#135 posture).

The v2 "terminal disclosure row" (which round-2 M2 correctly flagged as a new undesigned visible state) is **removed**; append-on-scroll replaces it. **The round-3 refinement makes that append-on-scroll genuinely complete** — the intra-chunk cursor guarantees no occurrence is dropped, so the "results just load as you scroll" claim is now true even for repetitive chunks. No bespoke "Load more" button is added. If a future product decision wants a distinct "Load more" affordance or a unified in-sheet scope toggle, THAT is when `needs-design` would be filed — this feature does not require it.

---

## Gate-2 round-2 findings + resolutions (revision history)

Independent Codex audit (round 2): all 5 round-1 Highs + most Mediums cleared; **Critical 2, High 0, Medium 2, Low 0** remained. Each resolved in v3:

| # | Sev | Finding | Resolution in v3 |
|---|---|---|---|
| C1 | Critical | EPUB text-quote resolution impossible — `ReadiumLocatorReconstructor.toReadium` requires nonblank `href` (returns null otherwise, `:106`); `PublicationLocatorSource` has no text-quote search; before/after is only copied onto an href-resolved base. Investigate `sectionIndex→spine href`. | **INVESTIGATED + REFUTED**: `sectionIndex` is a running content-iterator counter (incremented per href-change OR heading — `EpubTextExtractor.kt:93-95`), NOT `readingOrder[i]`, and href is never persisted → not recoverable. **RESOLVED via Readium's own `SearchService`** (verified present in `readium-shared-3.3.0-runtime.jar`: `SearchServiceKt.isSearchable/search`, `SearchIterator.next()→Try<LocatorCollection>`, bundled `StringSearchService`). `publication.search(q)` returns real href+title+snippet Locators the navigator jumps to natively. **DB stays v7** (no href-column migration needed). §2 EPUB track, §3 rej-alt #4, WI-5/WI-11. |
| C2 | Critical | `BuiltQuery.tokens` can't represent FTS occurrences — flat highlight list (CJK `"编 程"`→`["编","程"]`), prefix lives only in `fts`, `SnippetBuilder.findMatches` private + display-collapsed → its ranges are NOT raw offsets. Specify a NEW dedicated raw-offset matcher from the STRUCTURED query. | **RESOLVED**: new `SearchQueryBuilder.structuredQuery(raw): StructuredQuery?` (`Phrase`/`PrefixTerm`/`Term` units, from the shared `buildFtsParts` grouping — NOT the flat `tokens`) + new `RawOffsetMatcher` scanning RAW `text` for per-occurrence raw UTF-16 offsets honoring phrase/prefix/AND + CJK + surrogate/NFKC/ß→ss/combining edge cases. TXT/MD only (EPUB uses Readium `Locator.text`). §2, WI-2/WI-3. |
| M1 | Medium | EPUB overlay topology wrong (4 ComposeViews, not 3) + WI-10 file list omits `EpubReaderChrome.kt` (`EpubTopBand` has no search callback, calls `ReaderTopChrome` without `onSearch`). | **FIXED**: §0 + §2 corrected to FOUR ComposeViews (`popoverOverlay`/`sheetLayer`/`topBand`/`bottomBand`, `ReaderActivity.kt:567-627`); the EPUB sheet renders in the existing `sheetLayer`; **WI-11 now lists `reader/EpubReaderChrome.kt`** (the `EpubTopBand onSearch` edit, `:80,101`). |
| M2 | Medium | The truncation-disclosure row is a NEW undesigned visible state (rule 51). | **CHOSE (a) — no truncation surface**: pure append-on-scroll pagination, NO disclosure row; the per-chunk cap + page size are INTERNAL non-user-visible safety limits (documented, not a UI state). §8/§9 updated; v2's disclosure row removed. **Not needs-design.** *(Refined in v3.1 — round-3 M1 below: the "high cap" is replaced by a resumable intra-chunk cursor so pagination is genuinely COMPLETE.)* |

### Gate-2 round-3 findings + resolutions

Independent Codex audit (round 3): both round-2 Criticals + both Mediums VERIFIED resolved; **exactly ONE Medium** remained. Resolved in v3.1:

| # | Sev | Finding | Resolution in v3.1 |
|---|---|---|---|
| M1 | Medium | `RawOffsetMatcher`'s `maxPerChunk` still SILENTLY truncates occurrences past the cap; once a matched chunk is consumed by append-on-scroll, past-cap occurrences are unrecoverable — so "no silent hit loss" / "results just load as you scroll" were FALSE for highly-repetitive chunks. A "high" cap does not make search complete. | **RESOLVED via the auditor's prescribed option (b) — intra-chunk cursor.** (a) The pagination cursor gains an intra-chunk index: `SearchCursor.Fts(sectionIndex, chunkOrdinal, id, occurrenceIndex)`; a partially-consumed chunk RESUMES at `occurrenceIndex` on the next page (via the new `chunkAtOrAfter` inclusive DAO re-fetch), never skipped to the next chunk. (b) `maxPerChunk` is reframed as `maxThisPage` — a per-PAGE window bound the repository advances through via the cursor; `RawOffsetMatcher` returns `RawOccurrenceSlice(occurrences, nextOccurrenceIndex?)` and no occurrence is dropped. (c) WI-1 DAO (`chunkAtOrAfter`) + WI-3 matcher contract + WI-6 repository + §6 risk 7 + §8/§9 + the WI-3/repository tests now assert COMPLETENESS (a 40-occurrence chunk retrieved in full across paged calls, union = all, no gap/dupe, last slice `nextOccurrenceIndex==null`) rather than testing that a cap truncates. (d) The "internal non-user-visible safety limits" framing that implied silent drop is replaced with "bounded per page, complete across pages"; the only hard bound is an internal OOM guard far above any realistic count. Strictly within append-on-scroll — NO new visible surface, no truncation row, no Load-More control (rule 51 unchanged). |

- v3.1 (2026-07-12): Gate-2 round-3 resolution — the sole remaining Medium: intra-chunk `occurrenceIndex` in the pagination cursor + `chunkAtOrAfter` inclusive re-fetch + `RawOccurrenceSlice` per-page window, so TXT/MD pagination is COMPLETE (no silent occurrence drop). WI-1/WI-3/WI-6 contracts + tests assert full retrievability across pages. No new visible surface. Gate-2 clean → dispatch.
- v3 (2026-07-12): Gate-2 round-2 resolution — EPUB pivots to Readium `SearchService` (C1), TXT/MD gets `StructuredQuery`+`RawOffsetMatcher` (C2), 4-ComposeView + `EpubReaderChrome.kt` corrected (M1), append-on-scroll no-truncation-surface (M2). Two-track model; 12 WIs.
- v2 (2026-07-12): Gate-2 round-1 resolution — occurrence-expansion + runtime-resolver, 11-WI split, host-owned sheets, honest `p.N`/indexing, no needs-design.
- v1 (2026-07-10): Gate-1 draft (box F planner, renumbered #132→#133).
