# Phase D Implementation Plan (Forward)

**Date**: 2026-03-17
**Status**: FORWARD — 9 WIs planned (D07 split into D07a + D07b)
**Scope**: Book source scraping — Legado-compatible rule engine for web novels

**Reference**: Legado BookSource schema at `/Users/ll/.claude/projects/-Users-ll-Desktop-workspace-vreader/memory/reference_legado_book_source.md`

---

## WI-D01: BookSource Model + SwiftData Schema + Management UI

**Problem**: Need a data model that represents web content sources with configurable extraction rules, compatible with Legado's JSON format for import/export.

**Files to create/modify**:
- Create: `vreader/Models/BookSource.swift` — SwiftData @Model
- Create: `vreader/Models/BookSourceRules.swift` — rule sub-models (SearchRule, BookInfoRule, TocRule, ContentRule)
- Create: `vreader/Views/BookSource/BookSourceListView.swift` — management UI
- Create: `vreader/Views/BookSource/BookSourceEditorView.swift` — edit individual source
- Create: `vreader/Services/PersistenceActor+BookSource.swift`
- Create: `vreaderTests/Models/BookSourceTests.swift`
- Create: `vreaderTests/Services/PersistenceActor+BookSourceTests.swift`

**Tests FIRST**:
- `testBookSource_codableRoundTrip`
- `testBookSource_allFieldsEncoded`
- `testBookSource_optionalFields_nilSafe`
- `testBookSource_uniqueByURL`
- `testBookSource_enableDisable`
- `testSearchRule_codableRoundTrip`
- `testTocRule_codableRoundTrip`
- `testContentRule_codableRoundTrip`
- `testBookSourceCRUD_createReadUpdateDelete`
- `testBookSource_emptyURL_rejected`
- `testBookSource_duplicateURL_rejected`

**Implementation approach**:
1. BookSource @Model: `sourceURL` (unique), `sourceName`, `sourceType` (0=text), `enabled`, `searchURL`, `header`, `ruleSearch`, `ruleBookInfo`, `ruleToc`, `ruleContent`
2. Rule sub-models as Codable structs stored as JSON Data on BookSource
3. Management UI: list with enable/disable toggles, swipe to delete, add button
4. Editor: form-based with text fields for each rule
5. No built-in sources — all user-imported

**Edge cases**: Empty source name, URL without scheme (add https://), very long rule strings, special characters in URLs, sources with login requirements (defer to D08).

**Acceptance criteria**: CRUD operations on book sources. Enable/disable toggle. Data persists across launches. Codable for import/export.

**Dependencies**: None.

**Effort**: M

---

## WI-D02: HTTP Client + Encoding Detection + Cookies/Headers

**Problem**: Web scraping needs a robust HTTP client that handles encoding detection (GB2312/GBK common for Chinese novel sites), cookie persistence, custom headers, and rate limiting.

**Files to create/modify**:
- Create: `vreader/Services/BookSource/BookSourceHTTPClient.swift`
- Create: `vreader/Services/BookSource/EncodingDetector.swift`
- Create: `vreader/Services/BookSource/CookieStore.swift`
- Create: `vreaderTests/Services/BookSource/BookSourceHTTPClientTests.swift`
- Create: `vreaderTests/Services/BookSource/EncodingDetectorTests.swift`

**Tests FIRST**:
- `testFetchPage_success_returnsHTML`
- `testFetchPage_404_returnsError`
- `testFetchPage_timeout_returnsError`
- `testFetchPage_customHeaders_included`
- `testFetchPage_cookiesPersisted`
- `testFetchPage_rateLimited_respectsDelay`
- `testEncodingDetect_UTF8`
- `testEncodingDetect_GB2312`
- `testEncodingDetect_GBK`
- `testEncodingDetect_metaCharset_overridesHTTPHeader`
- `testEncodingDetect_noCharset_defaultsUTF8`
- `testEncodingDetect_BOM_detected`
- `testCookieStore_savesAndRestores`
- `testCookieStore_perDomain`
- `testRateLimit_concurrentRate_respected`

**Implementation approach**:
1. URLSession-based client (not WKWebView for scraping)
2. Encoding detection: check HTTP Content-Type header, then HTML meta charset, then BOM, then heuristic (CFStringConvertEncodingToNSStringEncoding)
3. Cookie persistence via HTTPCookieStorage.shared (per-source isolation via cookie jar)
4. Custom headers from BookSource.header field (User-Agent, Referer, etc.)
5. Rate limiting via DispatchSemaphore or async throttle (BookSource.concurrentRate)

**Edge cases**: Double-encoded content (UTF-8 decoded as Latin-1), redirect chains, HTTPS certificate errors, very large pages (>1MB), connection drops mid-download.

**Acceptance criteria**: Fetches pages with correct encoding. Cookies persist per domain. Rate limiting prevents IP bans. Custom headers sent correctly.

**Dependencies**: None (parallel with D01).

**Effort**: M

---

## WI-D03: Rule Engine (CSS Selectors, Regex, Legado Syntax)

**Problem**: BookSource rules specify how to extract data from HTML. Need a rule engine that supports CSS selectors, regex, and Legado-specific operators (`@`, `!`, chaining) — the core Legado rule types.

**XPath deferral**: XPath support deferred to D08 spike. MVP uses CSS selectors + regex only. Sources with XPath-only rules are marked as "limited compatibility" on import (see D05 compatibility classification).

**Files to create/modify**:
- Create: `vreader/Services/BookSource/RuleEngine.swift` — main dispatcher
- Create: `vreader/Services/BookSource/CSSRuleEvaluator.swift` — SwiftSoup CSS
- Create: `vreader/Services/BookSource/RegexRuleEvaluator.swift` — regex extraction
- Create: `vreader/Services/BookSource/LegadoSyntaxParser.swift` — parse Legado operators (`@`, `!`, chaining)
- Create: `vreader/Services/BookSource/RuleParser.swift` — parse rule syntax to determine type
- Create: `vreaderTests/Services/BookSource/RuleEngineTests.swift`
- Create: `vreaderTests/Services/BookSource/CSSRuleEvaluatorTests.swift`
- Create: `vreaderTests/Services/BookSource/LegadoSyntaxParserTests.swift`
- Create: `vreaderTests/Services/BookSource/RuleParserTests.swift`
- Add dependency: SwiftSoup (HTML parser with CSS selector support)

**Tests FIRST**:
- `testCSSRule_extractText_byClass`
- `testCSSRule_extractAttribute_href`
- `testCSSRule_extractList_multipleMatches`
- `testCSSRule_nestedSelector`
- `testRegexRule_extractGroup`
- `testRegexRule_replacePattern`
- `testRuleParser_detectsCSS`
- `testRuleParser_detectsXPath_marksLimitedCompat` (starts with //, flags as deferred)
- `testRuleParser_detectsRegex` (starts with :regex:)
- `testRuleEngine_dispatchesCorrectly`
- `testRuleEngine_emptyRule_returnsEmpty`
- `testRuleEngine_invalidHTML_returnsEmpty`
- `testRuleEngine_CJKContent_correctExtraction`
- `testLegadoSyntax_atOperator_accessesAttribute` (e.g., `tag.a@href`)
- `testLegadoSyntax_bangOperator_selectsByIndex` (e.g., `class.item!0`)
- `testLegadoSyntax_paginationChaining_followsNextPage`
- `testLegadoSyntax_cleanupRules_stripTagsAndWhitespace`
- `testLegadoSyntax_relativeURL_resolvedAgainstBase`

**Implementation approach**:
1. SwiftSoup for CSS selector evaluation (pure Swift, no C dependencies)
2. Regex via NSRegularExpression
3. RuleParser detects type: `//{path}` = XPath (flagged as "limited compatibility", deferred to D08), `:regex:{pattern}` = regex, otherwise CSS + Legado syntax
4. Legado rule syntax operators:
   - `@` — attribute accessor (e.g., `tag.a@href` extracts the href attribute)
   - `!` — index selector (e.g., `class.item!0` selects first match)
   - Pagination chaining — rules that follow `nextTocUrl`/`nextContentUrl` for multi-page extraction
   - Cleanup semantics — `##regex` for content cleanup, `@get:{rule}` for post-processing
   - Relative URL resolution — extracted URLs resolved against page base URL
5. LegadoSyntaxParser: tokenizes Legado rule strings into evaluable operations

**Edge cases**: Malformed HTML (SwiftSoup is lenient), rules matching 0 elements, rules matching too many elements, nested rules (rule within rule result), Unicode in selectors, very large HTML documents (>5MB).

**Acceptance criteria**: CSS selectors extract correct elements from fixture HTML. Legado operators (`@`, `!`, chaining, cleanup) work correctly. Regex extraction and replacement work. Rule type auto-detection is correct. XPath rules detected and flagged as "limited compatibility" (deferred to D08).

**Dependencies**: WI-D01 (schema defines rule format).

**Effort**: M

---

## WI-D04: Pipeline MVP (Search -> Book Info -> Chapter List -> Content)

**Problem**: The four-stage pipeline connects D01 (model), D02 (HTTP), D03 (rules) into an end-to-end scraping flow. One vetted source working end-to-end.

**Files to create/modify**:
- Create: `vreader/Services/BookSource/BookSourcePipeline.swift`
- Create: `vreader/Services/BookSource/PipelineStage.swift` — enum for progress tracking
- Create: `vreader/Views/BookSource/BookSourceSearchView.swift` — search UI
- Create: `vreader/Views/BookSource/BookSourceChapterListView.swift` — chapter list
- Create: `vreader/Views/BookSource/BookSourceReaderView.swift` — chapter reader
- Create: `vreaderTests/Services/BookSource/BookSourcePipelineTests.swift`

**Tests FIRST**:
- `testPipeline_search_returnsBookList`
- `testPipeline_bookInfo_extractsMetadata`
- `testPipeline_toc_extractsChapterList`
- `testPipeline_content_extractsChapterText`
- `testPipeline_endToEnd_withFixtureHTML`
- `testPipeline_searchNoResults_returnsEmpty`
- `testPipeline_invalidURL_returnsError`
- `testPipeline_networkError_propagates`
- `testPipeline_emptyContent_returnsError`
- `testPipeline_nextPageURL_followsPagination`
- `testPipeline_cancelDuringFetch_stops`
- `testPipeline_progressCallback_reportStages`

**Implementation approach**:
1. Pipeline stages: Search -> BookInfo -> TOC -> Content
2. Each stage: fetch URL -> apply rules -> extract data -> pass to next
3. Search: `searchURL.replace("{{key}}", keyword)` -> fetch -> ruleSearch
4. BookInfo: fetch bookUrl -> ruleBookInfo -> extract tocUrl
5. TOC: fetch tocUrl -> ruleToc -> chapter list (handle nextTocUrl pagination)
6. Content: fetch chapterUrl -> ruleContent -> cleaned text (handle nextContentUrl)
7. Use fixture HTML files for integration tests (no network in tests)
8. Progress callback at each stage for UI

**Edge cases**: Multi-page TOC (nextTocUrl), multi-page chapter content (nextContentUrl), empty search results, source that requires login, source returning non-HTML (JSON), rate limiting triggering mid-pipeline.

**Acceptance criteria**: One real web novel source works end-to-end: search, view book info, browse chapters, read chapter content. Pipeline reports progress at each stage. Errors are descriptive.

**Dependencies**: WI-D02 (HTTP client), WI-D03 (rule engine).

**Effort**: M

---

## WI-D05: Legado JSON Import/Export

**Problem**: The Legado ecosystem has thousands of user-shared book sources in JSON format. Import/export compatibility lets VReader tap into this ecosystem.

**Files to create/modify**:
- Create: `vreader/Services/BookSource/LegadoImporter.swift`
- Create: `vreader/Services/BookSource/LegadoExporter.swift`
- Create: `vreaderTests/Services/BookSource/LegadoImporterTests.swift`
- Create: `vreaderTests/Services/BookSource/LegadoExporterTests.swift`
- Add: `vreaderTests/Fixtures/legado_sample_source.json` — fixture

**Compatibility classification**: On import, classify each source's rule compatibility:
- **Full** — CSS selectors + regex only (all rules supported)
- **Limited** — contains XPath-only rules (deferred to D08; source imported but flagged)
- **Unsupported** — requires JS execution (imported but marked non-functional)

Show a compatibility badge in the source list UI (green/yellow/red). Users can see at a glance which imported sources will work.

**Tests FIRST**:
- `testImportLegadoJSON_classifyCSSOnly_full`
- `testImportLegadoJSON_classifyXPathRules_limited`
- `testImportLegadoJSON_classifyJSRules_unsupported`
- `testImportLegadoJSON_compatBadge_shownInList`
- `testImportLegadoJSON_singleSource`
- `testImportLegadoJSON_multipleSourcesArray`
- `testImportLegadoJSON_unknownFields_ignored`
- `testImportLegadoJSON_missingOptionalFields_defaults`
- `testImportLegadoJSON_duplicateURL_skips`
- `testImportLegadoJSON_invalidJSON_returnsError`
- `testImportLegadoJSON_emptyArray_noOp`
- `testExportToLegadoJSON_validFormat`
- `testExportToLegadoJSON_roundTrip`
- `testImportLegadoJSON_audioSource_typePreserved`
- `testImportLegadoJSON_500Sources_performsUnder2Seconds`

**Implementation approach**:
1. Parse Legado JSON array of BookSource objects
2. Map Legado fields to VReader BookSource model (field name mapping)
3. Handle type differences: Legado uses Int for sourceType, String for rules
4. Unknown fields ignored (forward compatibility)
5. Export: serialize VReader BookSource array to Legado-compatible JSON
6. Import via file picker or URL (share sheet)

**Edge cases**: Very large import files (500+ sources), sources with JS execution rules (mark as unsupported), sources with loginUrl (import but mark), sources with empty required fields, mixed encoding in JSON file.

**Acceptance criteria**: Legado JSON files import correctly. Exported JSON re-imports in Legado. 500-source import completes in <2s. Unknown fields don't crash.

**Dependencies**: WI-D01 (schema).

**Effort**: M

---

## WI-D06: Chapter Cache + Offline Reading

**Problem**: Users need to read cached chapters offline after fetching them once. Cache should persist across app launches.

**Files to create/modify**:
- Create: `vreader/Services/BookSource/ChapterCache.swift`
- Create: `vreader/Services/BookSource/ChapterCacheStore.swift` — disk persistence
- Create: `vreaderTests/Services/BookSource/ChapterCacheTests.swift`
- Modify: `vreader/Services/BookSource/BookSourcePipeline.swift` — check cache before fetch

**Tests FIRST**:
- `testCache_storeAndRetrieve_chapter`
- `testCache_miss_returnsNil`
- `testCache_persistsAcrossInstances`
- `testCache_eviction_LRU`
- `testCache_maxSize_respected`
- `testCache_bookDeletion_clearsCachedChapters`
- `testCache_corruptedFile_returnsNilAndCleans`
- `testCache_concurrentAccess_safe`
- `testPipeline_hitCache_skipsNetwork`
- `testPipeline_cacheMiss_fetchesAndCaches`

**Implementation approach**:
1. Disk-based cache: `<AppSupport>/ChapterCache/<sourceURL_hash>/<chapterURL_hash>.txt`
2. LRU eviction when total cache exceeds configurable max (default 500MB)
3. Metadata stored in SQLite (chapter URL, cached date, size, book reference)
4. Pipeline checks cache first; on miss, fetches and caches
5. Manual "Download All" button for offline preparation

**Edge cases**: Corrupted cache files, cache during low storage, concurrent reads/writes, chapter content update on source (stale cache).

**Acceptance criteria**: Cached chapters load instantly without network. Cache persists across launches. LRU eviction keeps cache within bounds. Corrupt files cleaned up.

**Dependencies**: WI-D04 (pipeline).

**Effort**: M

---

## WI-D07a: Update Detection

**Problem**: Users need to know when web novels have new chapters. Periodic background checks compare remote TOC against cached chapter list.

**Files to create/modify**:
- Create: `vreader/Services/BookSource/UpdateChecker.swift`
- Create: `vreaderTests/Services/BookSource/UpdateCheckerTests.swift`
- Modify: `vreader/Views/Library/LibraryView.swift` — update badge

**Tests FIRST**:
- `testUpdateCheck_newChapters_detected`
- `testUpdateCheck_noNewChapters_noNotification`
- `testUpdateCheck_networkError_gracefulDegradation`
- `testUpdateCheck_rateLimited_respectsInterval`
- `testUpdateCheck_disabledSource_skipped`
- `testUpdateCheck_batchCheck_allSources`
- `testUpdateCheck_chapterCountDecreased_handledGracefully`
- `testUpdateCheck_backgroundTask_scheduledCorrectly`

**Implementation approach**:
1. UpdateChecker: fetch TOC, compare chapter count with cached count
2. Background refresh via BGAppRefreshTask (requires `BGTaskSchedulerPermittedIdentifiers` in Info.plist)
3. Configurable interval (default: 6 hours, minimum: 1 hour)
4. Badge on library books with new chapters
5. Schedule next check via `BGTaskScheduler.shared.submit()` after each run
6. Respect system background execution limits (iOS may delay or skip)

**Edge cases**: Source goes offline, chapter count decreases (removed chapters), very frequent updates (rate limit), background refresh permissions denied, app killed before task completes.

**Acceptance criteria**: New chapters detected and shown as badge. Background check scheduled via BGTaskScheduler. Rate limiting respected. Graceful degradation on network failure.

**Dependencies**: WI-D04 (pipeline — needs TOC fetching).

**Effort**: M

---

## WI-D07b: Source Sharing

**Problem**: Sharing sources with other users is essential for the ecosystem. Users need to export/import individual sources easily.

**Files to create/modify**:
- Create: `vreader/Services/BookSource/SourceSharingService.swift`
- Create: `vreaderTests/Services/BookSource/SourceSharingServiceTests.swift`

**Tests FIRST**:
- `testSharing_exportSourceAsJSON`
- `testSharing_importSharedSource`
- `testSharing_URLScheme_opens`
- `testSharing_QRCode_generation`

**Implementation approach**:
1. Sharing: export single source as JSON via share sheet
2. URL scheme: `vreader://import-source?url=...` for one-tap import
3. Optional QR code for source sharing

**Edge cases**: Malformed URL scheme, QR code too dense for complex sources, importing a source that already exists.

**Acceptance criteria**: Source sharing via JSON/URL works. QR code generation works. URL scheme triggers import flow.

**Dependencies**: WI-D05 (Legado import — reuses import logic).

**Effort**: S

---

## WI-D08: Optional JS Execution + XPath Spike

**Problem**: Some Legado sources use JavaScript rules (`<js>code</js>` or `{{code}}`). Others use XPath-only selectors (deferred from D03 MVP). This is a spike to evaluate feasibility of both, not a committed feature.

**Files to create/modify**:
- Create: `vreader/Services/BookSource/JSRuleEvaluator.swift` — JavaScriptCore evaluation
- Create: `vreaderTests/Services/BookSource/JSRuleEvaluatorTests.swift`
- Create: `docs/codex-plans/SPIKE_D08_RESULTS.md` — spike findings

**Tests FIRST**:
- `testJSRule_simpleExpression_evaluates`
- `testJSRule_accessDOM_viaStringInput`
- `testJSRule_timeout_5seconds`
- `testJSRule_infiniteLoop_timesOut`
- `testJSRule_memoryLimit_enforced`
- `testJSRule_noNetworkAccess`
- `testJSRule_returnString_extracted`

**Implementation approach**:
1. Use JavaScriptCore (JSContext) — no WKWebView needed
2. Sandbox: no network access, no filesystem access, 5-second timeout
3. Input: HTML string injected as variable, JS rule evaluated
4. Output: string result extracted
5. Decision gate: If >30% of popular sources need JS, implement. Otherwise, mark JS sources as "unsupported" on import.

**Edge cases**: Malicious JS (sandboxed), memory exhaustion, infinite loops (timeout), JS that expects browser DOM (won't work in JSContext).

**Acceptance criteria**: Spike document produced with go/no-go decision. If go: JS rules evaluate in sandbox with timeout. If no-go: JS sources marked unsupported on import with user-visible indicator.

**Dependencies**: WI-D04 (pipeline must work without JS first).

**Effort**: L

---

## Sprint Plan

**Sprint D1** (parallel): D01 (model) + D02 (HTTP client) — M + M
**Sprint D2** (parallel, after D01): D03 (rule engine) + D05 (Legado import) — M + M
**Sprint D3** (sequential, after D2+D2): D04 (pipeline MVP) — M
**Sprint D4** (parallel, after D3): D06 (cache) + D07a (update detection) — M + M
**Sprint D4b** (parallel with D4, after D5): D07b (source sharing) — S
**Sprint D5** (optional, after D3): D08 (JS spike) — L

## Checkpoint Criteria

- Book sources can be created, edited, enabled/disabled
- Legado JSON import/export works (500+ sources)
- At least one real web novel source works end-to-end
- Chapter caching enables offline reading
- Update detection shows new chapter badges (D07a)
- Source sharing via JSON and URL scheme works (D07b)
- All existing tests pass

## Manual Testing

See `docs/manual-test-checklist.md` for phase-specific test items.
