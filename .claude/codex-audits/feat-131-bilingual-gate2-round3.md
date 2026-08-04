Reading additional input from stdin...
OpenAI Codex v0.144.1
--------
workdir: /Users/ll/workspace/vreader
model: gpt-5.6-sol
provider: openai
approval: never
sandbox: read-only
reasoning effort: high
reasoning summaries: none
session id: 019f5433-221d-7dc0-9e3b-562083919c41
--------
user
Independent Gate-2 plan audit (ROUND 3) for feature #131 (Android bilingual interlinear reading, parity box D). Read the plan at dev-docs/plans/20260710-feature-131-android-bilingual-interlinear.md (v3) and verify its round-2-finding resolutions against the LIVE code.

Round 2 raised: H1 (TXT/MD has no chapter model — the render/translate unit must be real), H2 (EPUB enumerate-vs-segment count divergence recovery), H3 (#136 AI-config-reachability spinout + Style descope), M1 (WI-0 needs enforceable go/no-go + a navigator-race contract), M2 (EPUB render is DOM-injection NOT a Compose body), M3 (the DI/factory WI must come before the host renderers), M4 (Room version is 8, next is 8->9). v3 claims all are resolved. VERIFY the resolutions against live code:

1. TxtDocument (android/app/src/main/kotlin/com/vreader/app/reader/TxtDocument.kt): confirm it exposes ONLY text/chunkCount/offsetForChunk/chunkForOffset/textForChunk (line-based <=4000-char UTF-16 chunks) and has NO chapter/section model. Is the v3 'document-global segment ranges produced once by the segmenter, grouped into unit windows, render keyed by segment-range overlap of each chunk span' model SOUND and 1:1? Look hard for a case where a segment/translation could render twice or drop (paragraph spanning a chunk boundary; a >4000-char paragraph; overlap anchoring at the chunk where the range ENDS).
2. Readium 3.3.0: confirm EpubNavigatorFragment.evaluateJavascript + getCurrentLocator are public in the resolved AAR and ReaderActivity.navigator holds an EpubNavigatorFragment?.
3. Room: confirm data/VReaderDatabase.kt @Database version is currently 8 with MIGRATION_1_2..MIGRATION_7_8 in ALL_MIGRATIONS, so 8->9 + MIGRATION_8_9 is correct. Confirm @PrimaryKey + @Upsert is the project's DAO pattern (BookDao).
4. #118 seam: confirm AiProviderStore.snapshot() (with .active + apiKey(profile)), AiProviderFactory.create(profile,apiKey,dispatcher), AiClient.chat(AiRequest): AiResponse, AiRequest fields (model/messages/temperature/maxTokens/system), and AiError cases exist as the plan names them.
5. iOS parity source symbols exist (read vreader/Services/AI/): ChapterTranslationService.translatePreSegmented + cachedTranslation(expectedSegmentCount:), ChapterTranslationPrefetcher.translatedSegmentsDirect + cachedSegmentsDirect, ChapterSegmenter.sentenceRanges(in:), TranslationChunkContract, ChapterTranslationChunker.subSplit. The Android ports must match these contracts.
6. NEW risks the v3 changes introduce (the segment-window model, the direct-block path, the DI reorder, WI-4b+WI-9 both gating on #136). Any concurrency hazard in the VM generation/cancellation design.
7. Cohesion of the 11-WI split (WI-0 spike + WI-1..4a + WI-4b DI + WI-5/6 + WI-7a/7b + WI-8/9).

Output findings grouped by severity (Critical / High / Medium / Low), each with file:line evidence, then a FINAL VERDICT line exactly one of: ship-as-is | follow-up-recommended | block-recommended. ship-as-is or follow-up-recommended clears Gate-2 round 3.
codex
I’ll perform this as a read-only independent audit: first establish repository state, then inspect the v3 plan, live Android/iOS symbols, and the resolved Readium artifact. I’ll report only evidence-backed findings and the exact verdict token requested.
exec
/bin/zsh -lc "git status -sb && wc -l dev-docs/plans/20260710-feature-131-android-bilingual-interlinear.md docs/architecture.md && sed -n '1,260p' dev-docs/plans/20260710-feature-131-android-bilingual-interlinear.md" in /Users/ll/workspace/vreader
 succeeded in 528ms:
## main...origin/main
 M dev-docs/plans/20260710-feature-131-android-bilingual-interlinear.md
 M docs/features.md
?? .claude/codex-audits/feat-131-bilingual-gate2-round2.md
?? .claude/codex-audits/feat-131-bilingual-gate2-round3.md
?? .claude/codex-audits/feat-136-ai-provider-reachable-gate2.md
?? android/2026-06-29-223908-this-session-is-being-continued-from-a-previous-c.txt
?? dev-docs/plans/20260712-feature-136-android-ai-provider-reachable.md
?? dev-docs/security/
     240 dev-docs/plans/20260710-feature-131-android-bilingual-interlinear.md
     726 docs/architecture.md
     966 total
# Feature #131 — Android Bilingual Interlinear Reading (parity-checklist box D)

**Feature number assumption:** highest active row in `docs/features.md` is `#136`; `#131` is a landed `PLANNED` row (`GH: #1923`). The orchestrator adjusts if a row is claimed first.

**Design authority (rule 51):** the **authoritative** bilingual surfaces are in `dev-docs/designs/vreader-fidelity-v1/project/vreader-bilingual.jsx` (`BilingualSetupSheet` / `BilingualPageContent` / `BilingualPill` / `BILINGUAL_LANGS`) and `.../vreader-reader.jsx` (`ReaderTopChrome` renders `BilingualPill`; the bilingual toggle is a More-menu row via `onMoreAction`) and `.../vreader-more.jsx` (the "Bilingual mode" More-menu Row toggle). `.../vreader-ai-android.jsx` contains a SECOND, differently-shaped `BilingualSetupSheet` — see §3's setup-sheet resolution for why this plan reproduces the `vreader-bilingual.jsx` sheet and design-gates the divergence. Where a surface is NOT depicted it is scoped out and flagged.

**Status:** Gate-1 draft v3 (2026-07-12) — Gate-2 round-1 REDESIGN + round-2 findings resolved. Awaiting Gate-2 round-3 audit.

## 1. Problem

iOS ships bilingual interlinear reading (#56/#100): a per-book toggle renders each source paragraph followed by its translation in a muted style, backed by an AI provider, cached to disk. Android shipped the #118 AI provider foundation (provider store, OpenAI-compat + Anthropic SSE clients, chat/summary) but has **no bilingual capability**. Box D of the parity checklist requires the interlinear renderer + the bilingual setup sheet, building on #118.

The engineering questions are (a) **which render host(s)** get true interlinear, (b) **what the real TXT/MD segmentation unit is** (there is no chapter model — round-2 H1), and (c) **where the entry point lives**. The render-host feasibility was settled in v2 (EPUB-primary via Readium `EpubNavigatorFragment.evaluateJavascript`; TXT/MD Compose; AZW3/PDF deferred) and was **CONFIRMED correct by the Gate-2 round-2 audit** — it is not revisited here. This v3 resolves the round-2 findings that concern *how* the pipeline maps to real code:

- **Host** — EPUB is the **primary** target via `EpubNavigatorFragment.evaluateJavascript(script): String?` (public suspend method in the shipped Readium 3.3.0 AAR — round-2 re-verified: the transformed API JAR exposes `evaluateJavascript`, `getCurrentLocator()`, `firstVisibleElementLocator(...)`, `submitPreferences(...)`, and `ReaderActivity.navigator` holds the concrete `EpubNavigatorFragment?`). TXT/MD (Compose) are built alongside as the deterministic pipeline proof.
- **TXT/MD unit (round-2 H1)** — `TxtDocument` has NO chapter model; it is line-based ≤4000-char chunks addressed by UTF-16 offset. The v2 "one `BilingualInterlinearBody` per `items(chunkCount)` chunk on `txtChapterIndex` units" mapping is **discarded**: it does not give a 1:1 segment↔render contract. v3 defines **document-global units with segment UTF-16 ranges produced ONCE by the segmenter** and renders source/translation pairs from those same ranges (§2, §3).
- **Entry point** — the design puts the toggle in the **More-menu** (`vreader-more.jsx`; the live `MoreActionId.BILINGUAL` id is already reserved, and `MoreRow.Toggle` carries `on`/`onToggle`) + a **top-chrome pill** (`vreader-reader.jsx`). Both landed as box-F sub-features **#132 (top chrome) and #134 (More menu), now VERIFIED** — the entry wiring targets them directly (§4).

## 2. Surface area

### Render-host decision (settled in v2, CONFIRMED by round-2 — not reopened)

**Two hosts, in dependency order:**

1. **EPUB (Readium `EpubNavigatorFragment`) — PRIMARY.** Interlinear via `evaluateJavascript` (enumerate leaf blocks → inject translation DOM nodes → clear on teardown/reflow), mirroring iOS `EPUBBilingualOrchestrator`. Gated by **WI-0 (a Readium bilingual spike with enforceable go/no-go thresholds + a navigator-race contract — round-2 M1)** before the EPUB render WI (WI-7b) is built.
2. **TXT/MD (Compose `TxtReaderActivity`) — INCLUDED.** No WebView; deterministically Compose-testable. Renders from **document-global segment ranges** (round-2 H1), NOT one body per chunk.

**AZW3 (foliate WebView)** and **PDF** remain follow-ups / out (§"Files OUT of scope").

**Why both, not TXT/MD-only:** the *pipeline* (segment → chunk → translate → cache → interleave) is host-agnostic; only the *render injection* is host-specific. EPUB is the format most users read, so shipping box D without it would under-deliver. TXT/MD are included because the Compose host is the cheapest, most testable place to prove the pipeline end-to-end (deterministic tree assertions), de-risking the EPUB adapter. **Box D cannot be checked on a false "EPUB requires a fork" rationale** — that rationale is discarded and stays discarded.

### The TXT/MD segmentation unit + render mapping (round-2 H1 — the core v3 correction)

**Verified against live code:** `TxtDocument` (in `reader/TxtDocument.kt`) exposes only `text: String`, `chunkCount`, `offsetForChunk(index)`, `chunkForOffset(offsetUtf16)`, `textForChunk(index)` — line-based ≤4000-char chunks over UTF-16 offsets against the RAW text (no line-ending normalization). It has **no chapter/section concept**. `TxtMdTextExtractor` (in `search/`) explicitly emits one section per chunk "because TXT has no sub-resource grouping." A chunk can hold multiple paragraphs OR split one long paragraph. So the v2 "translate per chunk, render one body per chunk" contract is not achievable.

**v3 model — document-global units with segment ranges produced ONCE:**

- The whole `.txt`/`.md` is treated as **one translation document**. The **segmenter runs once over `TxtDocument.text`** (the full raw backing string) and emits, per segment, its **`IntRange` UTF-16 span** against that same backing string (the segmenter's `paragraphRanges(text)` / `sentenceRanges(text)` — the range-returning peers of `paragraphs`/`sentences`; iOS precedent `ChapterSegmenter.sentenceRanges(in:)` returns `[Range<Int>]`). These ranges are the SINGLE source of truth used by BOTH the translate side and the render side, so the two segment identically **by construction** (they read the same array).
- **Unit granularity for TXT/MD is the whole document, sub-batched for cache/prefetch by a deterministic "unit window."** To avoid translating a 14 MB book at once (and to keep cache rows bounded), segment ranges are grouped into fixed **unit windows** of contiguous segments (window size a constant, e.g. covering ≈ one on-screen span; the exact constant is set at build time and does not change the 1:1 contract). Each window is a `TranslationUnitId(kind = txtDocSegmentWindow, value = windowIndex)` — a document-global index, NOT a chunk index. `unitContaining(locator)` maps the reader's saved `charOffsetUTF16` → the segment whose range contains it → its window index (via a precomputed segment-start binary search, the same shape as `TxtDocument.chunkForOffset`). `unitAfter(unit)` = next window index or null at document end.
- **Render mapping (the LazyColumn):** the TXT/MD body still iterates the existing `items(count = document.chunkCount, key = { it })` loop (verified injection point, TxtReaderActivity.kt:1043) for source layout/selection/highlight parity — **but bilingual interlinear content is keyed by SEGMENT RANGE, not by chunk.** For each rendered chunk `i` (source UTF-16 span `[offsetForChunk(i), offsetForChunk(i+1))`), the body looks up every segment whose range **overlaps** that chunk span and, after the source text of that segment's portion, renders its cached translation (muted) — from the SAME range array the translator used. A segment spanning two chunks contributes its translation once, anchored at the chunk where its range ends (deterministic), so a paragraph split across a chunk boundary is translated once and rendered once. When bilingual is OFF, the loop is byte-identical to today (translations are additive overlays only).
- **MD source** = raw markdown segment text (translation renders as plain muted text, not re-markdown-rendered — matches the muted-secondary design line). Segmentation runs over the raw markdown string; MD markers are treated as ordinary characters by the paragraph splitter (blank-line delimited), consistent with `TxtMdTextExtractor` shipping raw markdown to search.

This closes H1: there is no invented chapter model, the render boundary IS the segmentation boundary, and disabled = source byte-parity because bilingual content is a pure overlay off the shared range array.

### New files

**Pipeline / domain (host-agnostic, pure or coroutine — JVM-testable):**

- `bilingual/TranslationUnitId.kt` — `data class TranslationUnitId(kind, value)` with `enum Kind { epubHref, foliateHref, txtDocSegmentWindow, mdDocSegmentWindow, pdfPageRange }`; `storageKey = "${kind.name}:$value"`. Mirrors iOS `TranslationUnitID.Kind` in spirit; the TXT/MD kinds are **document-global segment-window indices** (H1), NOT chunk indices. v3 uses `epubHref` + `txtDocSegmentWindow`/`mdDocSegmentWindow`; others reserved so the cache-key format never breaks. *(Assumption I could not fully confirm: iOS's exact Kind case names for the TXT/MD variants — the Android names are chosen to describe the real unit; the storageKey format is what the cache contract depends on.)*
- `bilingual/TranslationGranularity.kt` — `enum { paragraph, sentence }`. (Design's Granularity control.)
- `bilingual/BilingualLanguages.kt` — `BilingualLanguage(key, glyph, script)`; `BILINGUAL_LANGS` = the set from `vreader-bilingual.jsx` + `findOrDefault(key)`. Default `Chinese`.
- `bilingual/ChapterSegmenter.kt` — **NEW file (there is no existing Android segmenter; the `search/` module has none — verified).** Port of iOS `ChapterSegmenter`: `paragraphs(text)` / `sentences(text)` **plus the range-returning peers `paragraphRanges(text): List<IntRange>` / `sentenceRanges(text): List<IntRange>`** (UTF-16 spans against the input string — iOS `sentenceRanges(in:)` precedent). The ranges are what H1's mapping consumes. CJK-aware sentence enumeration (。！？ vs Latin). Pure.
- `bilingual/TranslationChunker.kt` — `chunk(segments, maxCharsPerChunk)` + `subSplit(text, maxChars)`. Port of iOS `ChapterTranslationChunker.chunk(...)` + `subSplit(...)` (verified: `chunk` returns index groups, oversize segment gets its own chunk; `subSplit` is the Bug #330 grapheme-safe over-budget splitter).
- `bilingual/TranslationChunkContract.kt` — `userPrompt(segments, targetLanguage)`; `decode(raw, expectedCount)` (strict JSON-array + code-fence strip); `sealed class DecodeError { NotAStringArray; CountMismatch(expected, actual) }`. Port of iOS `TranslationChunkContract`. (No `style` param — Style is descoped v1, §3/H3.)
- `bilingual/ChapterTextProvider.kt` — `interface { units(); sourceSegments(unit); sourceText(unit); unitContaining(locator); unitAfter(unit) }`. **`sourceSegments(unit)` returns the exact segment strings (from the shared range array)** — this is what the EPUB direct-block and TXT/MD paths both feed to the translator so counts pair 1:1. Resolution is host-specific: TXT/MD key on `charOffsetUTF16` → segment-window; EPUB keys on the current-resource `href` from `EpubNavigatorFragment.currentLocator`. Honest divergence from iOS's uniform Readium `Locator`, documented.
- `bilingual/TxtChapterTextProvider.kt` — provider over `TxtDocument` + the segmenter's range array (H1). Builds the document-global segment ranges once, groups them into windows, resolves `unitContaining` via a segment-start binary search over `charOffsetUTF16`. MD source = raw markdown segment text.
- `bilingual/EpubChapterTextProvider.kt` (WI-0-gated shape) — provider over the Readium `Publication` reading order; `units()` = spine hrefs, `unitContaining(locator)` = the locator's href, `sourceSegments(unit)` = the DOM-enumerated block texts (the render's OWN enumeration, for direct-block 1:1 — H2). Its render-side collaborator (the JS enumerate/inject adapter) is `EpubBilingualJs` (M2), defined by WI-0's findings.
- `bilingual/ChapterTranslationError.kt` — `sealed { Offline; TimedOut; ProviderFailed(msg); Cancelled }`. Maps from `AiError` (verified cases: `Auth401`, `RateLimited429`, `Offline`, `Timeout`, `Http(code)`, `Decode`, `Stream`, `InsecureUrl`, `Config`).
- `bilingual/ChapterTranslationService.kt` — the iOS-parity service, now with the **full divergence-recovery surface (round-2 H2)**:
  - `cachedTranslation(bookKey, unit, sourceText, targetLanguage, granularity, acceptCountMismatch=false)` — cache-only, segments the source to count-check; serves a row only when `sourceParagraphCount == segments.size` (or `acceptCountMismatch`). No provider (#306 parity).
  - `cachedTranslation(bookKey, unit, expectedSegmentCount, targetLanguage)` — **the divergence-fallback cache-only restore (iOS Bug #343)**: serves the canonical row only when its STORED `sourceParagraphCount == expectedSegmentCount` (the DOM enumerate's block count). **Needs no source text and no provider** → a cache-hit toggle/reopen restores with **zero provider calls**.
  - `translate(bookKey, unit, sourceText, targetLanguage, providerProfile, granularity, bypassCacheRead=false)` — segment → chunk → per-chunk `AiClient.chat` one-shot → `decode` → per-segment fallback → per-chunk graceful degrade (Bug #330: a single failed chunk renders source-only for its segments and is NOT cached; all-chunks-fail throws) → cache-write only on full success. Cache row stores `sourceParagraphCount = segments.size`. Cancellation: `ensureActive()` between chunks AND immediately before the Room write (§6).
  - `translatePreSegmented(bookKey, unit, segments, targetLanguage, providerProfile)` — **the count-divergence recovery (round-2 H2; iOS Bugs #268/#330/#343).** Takes the render's OWN enumerated block texts as `segments` (1:1 by construction), chunks them, translates with the same per-chunk graceful-degrade + cancellation contract, and — on full success only — **caches under the canonical key with the ENUMERATE's count as the stored contract** (so a later reopen restores via `cachedTranslation(expectedSegmentCount:)`). A partial degrade is NOT cached. A cache-write failure does not fail the translation.
  - Uses `AiClient.chat(AiRequest)` (one-shot, verified — NOT `streamChat`).
- `bilingual/ChapterTranslationPrefetcher.kt` — resolves the active profile from one `AiProviderStore.snapshot()` (`snapshot.active`), decrypts via `store.apiKey(profile)` (snapshot-consistent), builds an `AiClient` via an **injected factory param** (below), cache-first then translate. Adds the **direct-block peers (H2)**:
  - `prefetch(unit)` — the plain-text path (segment source → `translate`).
  - `prefetchDirect(unit, sourceSegments, targetLanguage)` — the divergence path (iOS `translatedSegmentsDirect`): same snapshot+resolve+error contract, then `service.translatePreSegmented(...)`.
  - `cachedDirect(unit, expectedCount, targetLanguage)` — the **zero-provider cache-only restore** (iOS `cachedSegmentsDirect` → `cachedTranslation(expectedSegmentCount:)`): **returns a cached translation on a hit WITHOUT requiring an active provider** (the #306 pre-gate precedent). This is what backs `EpubReaderBilingualConnectedTest.count-divergence handled` cache-restore assertions.
  - Throws `ChapterTranslationError`. Mirrors iOS `ChapterTranslationPrefetcher`.
- `bilingual/BilingualAiReadiness.kt` — `resolve(snapshot): Boolean` (active profile exists AND its decrypted key is non-empty). A cipher/decryption failure maps to **not-ready** (never crashes — §6). Drives the setup-sheet engine-strip configured/unconfigured state. Keep the gate to exactly what #118 enforces (no separate consent manager on Android — #118 has none; confirm during build).

**State / persistence:**

- `bilingual/PerBookBilingualStore.kt` — DataStore-Preferences, keyed by `bookFingerprintKey`, holding `{ enabled, targetLanguage, granularity }`. This is the Android `PerBookSettingsOverride` bilingual slice — the backup contract declares exactly `bilingualEnabled` / `bilingualTargetLanguage` / `bilingualGranularity` and **NO `bilingualStyle`** (verified). So this store writes exactly those three fields. Wiring into backup collect/restore is scoped OUT (§7) — additive later; until then bilingual config is device-local.
- `bilingual/BilingualViewModel.kt` — `StateFlow<BilingualUiState>` with `enabled`, `targetLanguage`, `granularity`, `needsSetupSheet`, `aiConfigured`, `translationsByUnit`, `inFlightUnits`, `unavailableUnits`, `errorUnit`. Setters + `dismissSetupSheet`, `onPositionChanged(locator)`, `retryUnit(unit)`. Generation/epoch-guarded prefetch (current + next unit), cancellation on disable / language / granularity change — port of iOS `BilingualReadingViewModel` + `+Prefetch`. Split to `BilingualPrefetchController.kt` if it nears ~300 lines. (No `style` field — the authoritative sheet has no Style control; Style is descoped v1 — §3.)

**Room (translation cache):**

- `data/ChapterTranslationEntity.kt` — `@Entity(tableName="chapter_translations", indices=[Index("bookKey")], foreignKeys=[FK→books.fingerprintKey ON DELETE CASCADE])`. **`@PrimaryKey val lookupKey: String`** (Room REQUIRES a PK; verified against `HighlightEntity`, which pairs a `@PrimaryKey` with a separate unique index). `lookupKey` = `bookKey|unitStorageKey|targetLanguage|promptVersion`. Other columns: `bookKey`, `unitStorageKey`, `targetLanguage`, `promptVersion`, `translatedJson`, `sourceParagraphCount`, `createdAt`. Mirrors iOS `ChapterTranslationRecord.lookupKey` (`book|unit|lang|prompt`, profile-agnostic — Bug #342). **`sourceParagraphCount` is load-bearing for H2**: it stores the enumerate's count on the `translatePreSegmented` path so `cachedTranslation(expectedSegmentCount:)` can restore.
- `data/ChapterTranslationDao.kt` — `getByLookupKey(key)`, `@Upsert suspend fun upsert(row)` (Upsert identifies by PK = `lookupKey`, so it is insert-or-replace by cache identity), `deleteByLookupKey(key)`. The project's Room pattern is `@PrimaryKey` + `@Upsert` (verified: `BookDao.upsert`).
- `bilingual/ChapterTranslationStore.kt` — coroutine wrapper returning a `CachedTranslation` (segments decoded from JSON), keeping Room entities off the boundary (the iOS `ChapterTranslationStore` precedent).

**Cache-identity (reconciled with iOS parity):** the 4-part key `book|unit|lang|promptVersion` is profile-AGNOSTIC / style-agnostic (Bug #342). Style is descoped v1 (§3/H3) so no `s=` component exists. **Granularity IS user-selectable**, so it is carried in `promptVersion` as an **effective composite**: `promptVersion = "bilingual-v1|g=${granularity}"` (a paragraph vs sentence translation is a different cache row — this also closes the iOS #344 "sentence silently ignored" class by construction). A granularity change must cancel in-flight jobs, bump the VM generation, clear shaped in-memory `translationsByUnit`, and force a correctly-keyed re-fetch (specified in WI-6).

**DI / factory (verified live):** `AiProviderFactory` is an `object` with `create(profile: AiProviderProfile, apiKey: String, dispatcher: CoroutineDispatcher = Dispatchers.IO): AiClient` (verified). So `ChapterTranslationPrefetcher` takes its OWN injected `clientFactory: (AiProviderProfile, String) -> AiClient` param **defaulting to `AiProviderFactory::create`** (production) and overridden with a fake in tests. The prefetcher builds `AiRequest(model = profile.model, messages = …, temperature = profile.temperature, maxTokens = profile.maxTokens, system = …)` from the resolved profile (verified `AiRequest` fields).

**AI-provider reachability — spun out to #136 (round-2 H3; ORCHESTRATOR/USER DECISION):** verified against the live code — `AppContainer` does **NOT** provide `AiProviderStore`, and there is **NO live navigation route to `AiProviderListScreen`** (MainActivity has no NavHost; the #118 screen + store + `AiSettingsViewModel` exist but are only exercised by instrumented/round-trip tests). A fresh-install user therefore cannot reach provider config today. This gap is now owned by a **NEW separate tiny feature #136 (AI provider setup made production-reachable)** — a **HARD dependency of #131**. #136 delivers: the AI-provider-entry sheet/route, its production reachability, `AiProviderStore` wired into `AppContainer`, and its own Gate-5 acceptance (`unconfigured → Set up → add provider → return → enable → translate`). **#131 keeps only the wiring** of the bilingual "Set up translation" affordance → #136's AI-provider-entry sheet (WI-9's entry-wiring), and consumes `AiProviderStore` from `AppContainer` (provided by #136). #131 does NOT invent the AI-config sheet or its nav (rule 51). *(Assumption: #136 IS now a `docs/features.md` row — filed 2026-07-12 as GH #1976; #131's `Deps` reference it.)*

**UI (Compose — every state depicted, reproducing `vreader-bilingual.jsx`):**

- `bilingual/BilingualSetupSheet.kt` — reproduces `vreader-bilingual.jsx`'s `BilingualSetupSheet` EXACTLY: header Cancel / Translate; a **preview strip**; a **language grid** over `BILINGUAL_LANGS` (glyph tiles, selected accent); a **Granularity** segmented control (Paragraph "Translate after each ¶" / Sentence "Translate after each sentence"); a **Translation engine** strip (configured: "Claude · with this book's context" + "Change…"; unconfigured: "No AI provider configured" + "Set up"). **No Style control, no provider/model card, no term-overrides toggle, no cost footer** — those belong to the other (`vreader-ai-android.jsx`) sheet, which this plan does not reproduce (§3). The **"Set up" CTA routes to #136's AI-provider-entry sheet** (wired in WI-9); "Change…" routes there too.
- `bilingual/BilingualInterlinearBody.kt` — **the Compose render surface for the TXT/MD host ONLY** (round-2 M2). Per source segment (from the shared range array): source `Text` then translation `Text` muted with accent left-border, `fontSize*0.88`, CJK font for cjk scripts, RTL handling for Arabic script. Consumes a **host-neutral bilingual state DTO** (see `BilingualRenderState` below). Loading state ("Translating chapter… N%" + per-segment dim). Error state ("Couldn't translate" + Retry). Partial/offline (`unavailableUnits`): source-only silent fallback (design's original-always-kept guarantee — iOS Decision 2). **This is NOT the EPUB render surface** — EPUB uses `EpubBilingualJs` DOM injection (M2 below).
- `bilingual/BilingualRenderState.kt` — the **host-neutral state DTO** shared by BOTH the Compose body and the EPUB adapter (round-2 M2): per-unit `{ segments: List<String>?, phase: Loaded|Loading(fraction)|Error|SourceOnly }`. Compose reads it to compose `Text`; the EPUB adapter reads the SAME type to build DOM. Compose and EPUB share the **state/value types, NOT the composable body**.
- `bilingual/EpubBilingualJs.kt` (WI-0-gated) — **the EPUB render surface (round-2 M2).** A pure Kotlin builder that, from a `BilingualRenderState` unit, produces the **JS strings** for `navigator.evaluateJavascript(...)`: (a) `enumScript` (enumerate current-resource leaf blocks → JSON `[{id,text}]`), (b) `injectScript(blockId, translationText)` (construct a translation DOM node after the block, CSP-safe: text set via `textContent`/`createTextNode`, never `innerHTML` string-concat; RTL/CJK via a class + injected `<style>`), (c) `clearScript()` (remove all injected nodes idempotently). Escaping is done in Kotlin (JSON-encode every interpolated string) so a translation containing quotes/`</script>`/newlines cannot break out. **No Compose here.** Consumes `BilingualRenderState`.
- `bilingual/EpubBilingualController.kt` (WI-0-gated) — the runtime actor that serializes enumerate→translate→inject/clear against the navigator using WI-0's chosen mechanism (a single mutex OR a monotonic navigator-session token — M1); checks the session token after every suspended JS/AI call; clears BEFORE publication teardown; re-applies on the identified production re-apply signal (M1).
- `bilingual/BilingualPill.kt` — the `EN ↔ 中` reader-**top-chrome** pill (per `vreader-reader.jsx` `ReaderTopChrome` + `vreader-bilingual.jsx` `BilingualPill`). Rendered by #132's top chrome; #131 provides the composable, #132's surface hosts it (§4).

### Modified files

- `data/VReaderDatabase.kt` — add `ChapterTranslationEntity` to `@Database entities`, bump `version` **8 → 9** (round-2 M4: the live DB is **v8**, migrations `MIGRATION_1_2`..`MIGRATION_7_8`; the number is allocated current→next **at implementation time** — against this checkout that is **8→9**), add **`MIGRATION_8_9`** (CREATE TABLE `chapter_translations` + `bookKey` index + FK→`books.fingerprintKey` CASCADE, DDL exactly matching Room's generated schema), **append `MIGRATION_8_9` to `ALL_MIGRATIONS` after `MIGRATION_7_8`**, add `abstract fun chapterTranslationDao()`. The translation-cache table is purely additive.
- `reader/TxtReaderActivity.kt` — own a `BilingualViewModel`; collect state; render translations in the existing `items(count = document.chunkCount, key = { it })` loop (verified injection point, TxtReaderActivity.kt:1043) **keyed by segment range overlap (H1)**, not per chunk; on position change call `vm.onPositionChanged(canonicalLocator.charOffsetUTF16)`. Strictly gated to `originalFormat ∈ {txt, md}`; disabled = body byte-unchanged (overlay-only). **This file is owned by #129 (VERIFIED); #131's edit lands on top of it (rule 48 one-writer-per-file) — #129 is merged, so this is a straight edit, not a blocker.**
- `reader/ReaderActivity.kt` (Readium EPUB) — WI-0-gated: attach `EpubBilingualController` to `navigator.evaluateJavascript`; re-apply on the identified production re-apply signal (M1); clear on teardown BEFORE publication teardown. Concrete surface defined by WI-0's spike output. `navigator: EpubNavigatorFragment?` is the verified live field.
- `VReaderApp.kt` / `AppContainer` — **consume `AiProviderStore` (provided by #136), and provide** `ChapterTranslationStore`, `PerBookBilingualStore`, `ChapterTranslationService`, `ChapterTranslationPrefetcher`, and a `BilingualViewModel` factory. **Extracted into the shared DI WI (WI-4b, round-2 M3)** so both host integrations depend on it. Mirrors #116/#118/#122 DI. *(Note: `AiProviderStore`-into-`AppContainer` is #136's deliverable; #131's DI WI wires the bilingual services around it.)*

**NOT modified:** `reader/chrome/ReaderBottomChrome.kt` gets **no** bilingual/Translate slot — the design's entry is the More-menu toggle (#134) + the top-chrome pill (#132), NOT a bottom-chrome slot. `ReaderBottomChrome`'s existing `extraSlot` is untouched.

### Files OUT of scope for v1

- **`Azw3ReaderActivity.kt` / `reader/foliate/`** — foliate WebView interlinear IS feasible (JS enumerate+inject in the pinned bundle) but deferred (bundle-patch JS + secure-bridge additions touching the security-sensitive #126 surface). Once WI-0 proves the EPUB JS pipeline, the foliate host reuses `EpubBilingualJs` with a bundle adapter.
- **`PdfReaderActivity.kt`** — no reflowable text layer. Out (`pdfPageRange` Kind reserved only).
- **The AI-provider setup sheet + its production reachability + `AiProviderStore` in `AppContainer`** — owned by **#136** (a hard dependency). #131 wires only the "Set up"/"Change…" affordance to #136's sheet.
- **Backup collect/restore of `PerBookSettingsOverride` bilingual fields** — contract fields exist; wiring is a small additive follow-up (§7). Bilingual config is device-local until then.
- **Style control** — descoped v1 (user decision, §3/H3). #131 keeps provider/model/**granularity**, DROPS the bilingual "Style" control.
- **"Translate entire book…" batch, re-translate/style-swap picker, cost/token estimation, term-overrides** — iOS/`vreader-ai-android.jsx` extras not in the authoritative `vreader-bilingual.jsx` sheet. Out.
- **Streaming translation progress** — the design's "38%" is chapter-level N-of-M chunk progress (from the chunker count), not token streaming. v1 shows N-of-M.

## 3. Prior art / project precedent / rejected alternatives

### The render-host decision (settled v2, CONFIRMED round-2)

**How iOS does interlinear:** iOS renders EPUB/AZW3 in a WKWebView it fully controls. `EPUBBilingualOrchestrator` injects JS that (1) enumerates leaf blocks posting `[{bid,text}]` to Swift, (2) after translation injects a translation node after each block. TXT/MD render in a text path where the renderer interleaves translation runs. The mechanism = **the app inserts translation nodes between source nodes.**

**Android EPUB feasibility (round-2 re-verified):** `javap`/the transformed API JAR on the resolved Readium 3.3.0 AAR expose public `evaluateJavascript(String, Continuation<? super String>)`, `getCurrentLocator()`, `firstVisibleElementLocator(...)`, `submitPreferences(...)`; `ReaderActivity.navigator: EpubNavigatorFragment?` holds the concrete fragment. So EPUB interlinear via JS injection is feasible with the public API — **no Readium fork.** The audit CONFIRMED this correction; it is not reopened.

**WI-0 — Readium bilingual spike (gates WI-7b; round-2 M1 rewrote its contract into enforceable go/no-go thresholds):** a throwaway harness that, against a real EPUB on the emulator, must PROVE (each is a pass/no-go criterion):

- **(a) Enumeration is deterministic + idempotent, with stable node IDs.** Enumerating the same current resource twice yields the same block IDs in the same order. Repeated `apply` produces **no duplicate injected nodes** (idempotent replacement).
- **(b) Clear wins over every older inject.** Under a rapid enable→disable / navigate sequence, a late-arriving inject issued before a `clear` must NOT survive the clear — enforced by the serialization mechanism below (a late inject checks the session token and no-ops).
- **(c) Recreation restores from cache** for every case: href away/back, same-href `submitPreferences` reflow, internal page-fragment recreation (the WebView pager recreates fragments), and activity recreation — each must re-apply the interlinear from the disk cache (via `cachedDirect(expectedCount)`, zero provider calls) with **an identified PRODUCTION re-apply signal** (a concrete navigator/lifecycle callback or `currentLocator`/fragment-lifecycle hook) for each case.
- **(d) Locator / visible-source preservation across injection**, with a stated permissible delta (injecting content may shift pagination by ≤ a stated bound; the reader's saved position must map back to the same source block).
- **(e) The enumerated block count vs the segmenter count** is measured; if they diverge (iOS #268), the **direct-block path** (`prefetchDirect` → `translatePreSegmented`, cached by enumerate count, restored by `cachedDirect(expectedCount)` — H2) is the recovery, proven end-to-end in the spike.

**Race contract (M1):** WI-0 specifies **either a single actor/mutex OR a monotonic navigator-session token**; every suspended JS/AI call is followed by a token/mutex check; cancellation/clear runs BEFORE publication teardown. **If WI-0 cannot find a deterministic production re-apply signal for a recreation case (c), that is an explicit NO-GO:** EPUB drops to a tracked follow-up and box D ships **TXT/MD-only** — with the honest reason (a specific spike finding), never the false "requires a fork."

**Rejected alternatives:**
1. **Readium interlinear via decorations only** — REJECTED (decorations style existing text; they cannot insert translation paragraphs). `evaluateJavascript` makes injection possible, so EPUB uses the JS seam.
2. **Forking Readium** — REJECTED + unnecessary (public `evaluateJavascript` seam exists).
3. **AZW3 foliate host first** — REJECTED for v1 (deferred, not dead; touches the security-sensitive #126 bridge).
4. **Eager whole-book pre-translation** — REJECTED (cost/latency). Lazily prefetch current+next + cache — port iOS.
5. **One `BilingualInterlinearBody` per chunk (v2)** — REJECTED (round-2 H1): a chunk is not a segment. Replaced by document-global segment ranges (§2).
6. **A Compose body as the EPUB render surface (v2)** — REJECTED (round-2 M2): Compose cannot render inside Readium's WebView. Replaced by `EpubBilingualJs` DOM injection sharing only the `BilingualRenderState` DTO.

### The setup-sheet resolution (rule 51) + Style descope (round-2 H3, USER DECISION)

There are **two committed, differently-shaped** `BilingualSetupSheet`s:
- `vreader-bilingual.jsx` → **language grid + Granularity + preview strip + Translation-engine strip (Set up/Change) + Cancel/Translate**. **No Style, no provider/model card, no term-overrides, no cost.**
- `vreader-ai-android.jsx` → **Languages (From/To) + Provider card + Style (Literal/Natural/Literary) + Keep-term-overrides toggle + cost footer.** **No language grid, no Granularity, no preview.**

**Resolution:** this plan reproduces the **`vreader-bilingual.jsx` sheet EXACTLY** as the authoritative Android-native bilingual sheet. **Style is DESCOPED for v1** (user decision): #131 keeps provider/model/**granularity**, DROPS the bilingual "Style" control. Consequently the store/VM carry no `style`, the chunk contract has no `style` param, and the cache key's `promptVersion` has no `s=` component. Keep rule 51: only implement the designed surface.

**Box-D parity note (H3 — do NOT claim full box-D parity):** the box-D parity checklist lists provider/model/**style**. Because Style is descoped v1, **WI-9 flips box D to done ONLY for provider/model/granularity + a descope note** — it does NOT claim full box-D parity. A **follow-up tracker/checklist amendment records the Style descope** (the plan does not silently drop it). If Style is later wanted on Android as a user control, that needs an **updated committed design** (a single sheet showing BOTH Style AND Granularity is not depicted anywhere — the one open design gate below).

### Other precedents applied

- **#118 provider seam**: reuse `AiProviderStore.snapshot()` (`snapshot.active`) + `store.apiKey(profile)` + `AiProviderFactory.create` (default of an injected factory param) + `AiClient.chat`. #118's AI files are unchanged; **#136** wires `AiProviderStore` into `AppContainer`; #131's DI WI wires the bilingual services.
- **Room additive-migration pattern** (#122/#123/#127/#128/#135): version bump + `MIGRATION_n_(n+1)` appended to `ALL_MIGRATIONS` + exact-DDL + `VReaderDatabaseMigrationTest` PRAGMA guard. `@PrimaryKey` + `@Upsert` is the project's DAO pattern (`BookDao`). Baseline is **v8** (M4).
- **DataStore JSON-in-Preferences** for `PerBookBilingualStore` (the `ReaderSettingsStore`/`AiProviderStore` pattern).
- **Pure-logic port**: iOS `ChapterSegmenter`/`ChapterTranslationChunker`/`TranslationChunkContract`/`ChapterTranslationService.translatePreSegmented`/`ChapterTranslationPrefetcher.translatedSegmentsDirect`+`cachedSegmentsDirect` are pure/heavily-unit-tested — direct Kotlin ports with the same test vectors (all verified to exist).
- **Entry point via #132/#134 (VERIFIED)**: the More-menu bilingual toggle (`MoreActionId.BILINGUAL` reserved; `MoreRow.Toggle` carries `on`/`onToggle`) + top-chrome pill are the landed integration points; #131 mounts the pill + wires the toggle (§4).

## 4. Work-item sequencing

**11 WIs/PRs (round-2 L2):** WI-0 (spike), WI-1..WI-4a (foundation/service), **WI-4b (shared DI/factory)**, WI-5, WI-6, WI-7a (Compose UI), **WI-7b (conditional EPUB render adapter — dropped if WI-0 = no-go)**, WI-8 (TXT/MD host integration), WI-9 (entry wiring + acceptance). Each WI = one PR. Build order (round-2 M3): **foundation/cache → service/direct-block APIs → shared DI/factory → VM state/prefetch → host-specific renderers (TXT/MD + EPUB) → entry wiring.**

**Dependency notes (round-2 L1 — exact landed integration points):**
- **`Deps: [feat:#136, feat:#132, feat:#134]`.** **#132 (top chrome) and #134 (More menu) are VERIFIED — dependencies satisfied** (the top-chrome host + `MoreActionId.BILINGUAL` toggle row are landed). **#129 (TXT/MD reader) is VERIFIED** — `TxtReaderActivity` is a straight edit, not a blocker. **#136 (AI provider setup made production-reachable) is the NEW hard blocker** for #131's entry-wiring (the "Set up"/"Change…" route) AND the DONE flip; it provides `AiProviderStore` in `AppContainer` and the reachable AI-config sheet. The live More model already reserves `MoreActionId.BILINGUAL` (verified).
- The pipeline + setup sheet + interlinear render (WI-0..WI-7) are built ahead; only the **entry wiring (WI-9)** and the **DI WI (WI-4b, for `AiProviderStore` in `AppContainer`)** wait on #136. The pill mount (WI-9) targets #132's VERIFIED top chrome; the toggle wire (WI-9) targets #134's VERIFIED More menu.

**WI-0 (spike): Readium EPUB bilingual injection — with enforceable go/no-go + race contract (M1).** The harness + criteria (a)–(e) and the race contract in §3. Output: a **go/no-go on EPUB-in-v1** (no-go if no deterministic production re-apply signal — box D ships TXT/MD-only, tracked) + the concrete `EpubChapterTextProvider` / `EpubBilingualJs` / `EpubBilingualController` surfaces. Deps: none (uses the existing #106 Readium host). Not TDD-gated (throwaway spike); its findings feed WI-7b.

**WI-1 (foundational): value types + pure segmentation/chunk/contract.** `TranslationUnitId` (document-global TXT/MD kinds — H1), `TranslationGranularity`, `BilingualLanguages`, **`ChapterSegmenter` (with `paragraphRanges`/`sentenceRanges` — H1)**, `TranslationChunker`, `TranslationChunkContract` (no `style` — H3), `ChapterTranslationError`. Pure; ported iOS vectors. Deps: none.

**WI-2 (foundational): Room translation cache.** `ChapterTranslationEntity` (PK = `lookupKey`, `sourceParagraphCount` column) + `Dao` (`@Upsert`) + `ChapterTranslationStore`; `VReaderDatabase` **8→9 `MIGRATION_8_9`** appended after `MIGRATION_7_8` (M4). Robolectric migration round-trip from **v8** + full-chain + upsert/get/delete-by-lookupKey + FK-CASCADE + exact-DDL guard. Deps: none.

**WI-3 (foundational): `ChapterTranslationService`** against a fake `AiClient`. `cachedTranslation` (both overloads incl. the **`expectedSegmentCount` divergence restore — H2**) + `translate` + **`translatePreSegmented` (H2: chunk, per-chunk degrade, cancellation, cache-write with the enumerate count on full success only)**. Deps: **WI-1, WI-2**. Tests: cache hit → zero client calls; miss → translate + write; decode fail → per-segment fallback; one-chunk fail → source-only that chunk (others translated, NOT cached); all-chunks fail → throw; cancellation → `Cancelled` (no write); `AiError` mapping incl. `Config`/`InsecureUrl` → `ProviderFailed`; **`translatePreSegmented` full-success caches under the enumerate count; partial degrade NOT cached; all-fail throws; `cachedTranslation(expectedSegmentCount)` returns on stored-count match, null on mismatch, needs no provider**.

**WI-4a (foundational): `ChapterTextProvider` (TXT/MD) + `ChapterTranslationPrefetcher` + `BilingualAiReadiness`.** `TxtChapterTextProvider` builds the **document-global segment ranges once (H1)**, groups into windows, resolves `unitContaining(charOffsetUTF16)` via segment-start binary search, `sourceSegments(unit)`. Prefetcher: `prefetch` + **`prefetchDirect` + `cachedDirect` (zero-provider cache restore — H2)**; resolves active profile from `snapshot()`, decrypts snapshot-consistent, builds client via the **injected factory param** (default `AiProviderFactory::create`), constructs `AiRequest` from the profile. Readiness = active profile with non-empty decrypted key; **cipher failure → not-ready, never a crash.** Fake store + fake factory. Deps: **WI-1, WI-3**. Tests: unit resolution + clamp + empty; **paragraph spanning a chunk boundary → one segment/one unit; multiple paragraphs in one chunk → distinct segments; a >4000-char paragraph → one segment across chunks; CR/LF/CRLF; MD markers; locator→unit mapping; source-byte parity while disabled**; cache-hit-no-profile still returns (#306); no-profile miss → `ProviderFailed`; `prefetchDirect` 1:1; `cachedDirect` restores with zero provider calls; readiness true/false; cipher-throw → readiness false (no crash).

**WI-4b (foundational — shared DI/factory, round-2 M3): AppContainer bilingual services.** Extract the DI/factory wiring into this EARLIER shared WI: `AppContainer` provides `ChapterTranslationStore`, `PerBookBilingualStore`, `ChapterTranslationService`, `ChapterTranslationPrefetcher`, and the `BilingualViewModel` factory — **consuming `AiProviderStore` from `AppContainer` (provided by #136).** Both host integrations (WI-7b, WI-8) depend on this. Deps: **WI-4a, feat:#136** (for `AiProviderStore` in `AppContainer`). Tests: container resolves the bilingual graph; the prefetcher's injected factory defaults to `AiProviderFactory::create`.

**WI-5 (behavioral): `PerBookBilingualStore` + `BilingualViewModel` state core.** Store per book (enabled/targetLanguage/granularity — no style); VM setters (persist + first-enable `needsSetupSheet`), language/granularity change clears cache-shaped state + bumps generation. Turbine tests: first-enable raises sheet; re-enable persisted does not; disable clears; language change resets; granularity change resets + re-keys; round-trip through store; no style field. Deps: **WI-1** (+ store).

**WI-6 (behavioral): VM prefetch trigger + generation/cancellation.** `onPositionChanged(charOffsetUTF16)` derives current unit, dedupes, prefetches current+next; a **monotonic position-request sequence** checked after every suspension; **per-unit generation tokens**; a **captured language/granularity/provider snapshot per launch**; generation bumps on disable/language/granularity/unit-change discard stale; `CancellationException` handled BEFORE generic error mapping; `Offline`→`unavailableUnits`; transient failure leaves unit unfetched + clears anchor to retry; `retryUnit`. Fake prefetcher. Deps: **WI-4a, WI-4b, WI-5**. Tests: current+next on unit change; same-unit no-op; cancel-mid discards stale; offline→unavailable; failure→retry-able; `retryUnit` re-fetches; granularity change cancels + re-fetches under the new key.

**WI-7a (behavioral): Compose UI — setup sheet + interlinear body (TXT/MD) + pill.** Reproduce `vreader-bilingual.jsx` (setup sheet: language grid / granularity / preview / engine strip configured+unconfigured; body: translated / loading N%+dimmed / error+Retry / offline source-only; pill). Consumes the **host-neutral `BilingualRenderState` DTO (M2)**. Light+dark. Compose UI tests each state. Deps: **WI-5** (state shape). NO Style control; the unconfigured "Set up" CTA renders and (in WI-9) routes to #136's sheet.

**WI-7b (behavioral, CONDITIONAL — only if WI-0 = go): EPUB render adapter (DOM injection, NOT Compose — round-2 M2).** `EpubBilingualJs` (enum/inject/clear JS builders, CSP-safe escaping) + `EpubBilingualController` (the serialization actor / session token — M1) + `EpubChapterTextProvider`, wired into `ReaderActivity`, driving DOM from the **shared `BilingualRenderState` DTO**. **Depends on WI-6 (VM prefetch) and WI-4b (DI) — the M3 fix; the WI-7a UI dependency is REMOVED except for the shared `BilingualRenderState`/value types.** Uses `prefetchDirect`/`cachedDirect` for the count-divergence path (H2). Connected test on a real EPUB (seeded cache): enable → interlinear injects; disable → nodes cleared; reflow/href-change/fragment-recreation/activity-recreation → re-applies from cache (zero provider calls); count-divergence handled (direct path). Unit tests: JS escaping/CSP-safe text insertion, RTL/CJK style, empty translations, loading cleanup, idempotent replacement, source-only fallback. Deps: **WI-0, WI-3, WI-4a, WI-4b, WI-6, (shared types from WI-7a)**. (If WI-0 = no-go, this WI is dropped and box D ships TXT/MD-only, tracked.)

**WI-8 (behavioral): `TxtReaderActivity` integration.** Wire VM into the `items(chunkCount)` loop **keyed by segment-range overlap (H1)** + position-change (`charOffsetUTF16`) + setup-sheet. `originalFormat`-gated (TXT/MD). Uses WI-4b's DI. **#129 is VERIFIED — straight edit.** Connected test (fake `AiClient` seam): enable → setup → confirm → interlinear from seeded cache; disable → source-only byte-parity; reopen persists enabled + renders from cache with zero client calls; paragraph-spanning-chunk-boundary renders one translation. Deps: **WI-6, WI-7a, WI-4b**.

**WI-9 (behavioral): entry wiring + acceptance.** Mount `BilingualPill` in **#132's VERIFIED top chrome**; wire the **#134 VERIFIED More-menu `MoreActionId.BILINGUAL` toggle** (`MoreRow.Toggle` `on`/`onToggle`) to the VM; **wire the setup sheet's "Set up"/"Change…" affordance → #136's AI-provider-entry sheet.** Full acceptance pass across EPUB (if WI-7b landed) + TXT/MD, including the fresh-user path `unconfigured → Set up (→ #136 sheet) → add provider → return → enable → translate` (the #136-owned reachability verified jointly). **Flip box D to done ONLY for provider/model/granularity + the Style-descope note (H3); file the follow-up checklist amendment; do NOT claim full box-D parity, do NOT flip DONE until #136 is landed.** Update `docs/architecture.md` (bilingual pipeline + the new `chapter_translations` schema + bilingual services in `AppContainer`). → DONE. Deps: **WI-8, WI-7b (if go), feat:#136, feat:#132, feat:#134**.

## 5. Test catalogue

JVM/Robolectric (`android/app/src/test/...bilingual/`): `ChapterSegmenterTest` (paragraph blank-line; sentence CJK 。！？ vs Latin; empty→[]; single; **`paragraphRanges`/`sentenceRanges` return correct UTF-16 spans**); `TranslationChunkerTest` (packs to budget; oversize→own chunk+subSplit; empty→[]); `TranslationChunkContractTest` (prompt shape; strict JSON decode; code-fence strip; count mismatch→`CountMismatch`; non-array→`NotAStringArray`); `ChapterTranslationServiceTest` (cache hit 0 calls; miss→translate→write; decode-fail per-segment fallback; one-chunk-fail partial-not-cached; all-fail→throw; cancellation→Cancelled no write; ensureActive-before-write; offline/timeout/429/http/config/insecure→error mapping; very long chapter N-of-M; stale-cache count-mismatch re-translates; **`translatePreSegmented` caches under enumerate count on full success; partial degrade not cached; all-fail throws; `cachedTranslation(expectedSegmentCount)` hit/miss with no provider**); `ChapterTranslationErrorMappingTest`; `TxtChapterTextProviderTest` (**paragraph spanning chunk boundary → one segment/unit; multiple paragraphs in one chunk → distinct segments; >4000-char paragraph → one segment across chunks; CR/LF/CRLF; MD markers; locator→unit mapping; unitAfter end→null; source-byte parity while disabled**); `ChapterTranslationPrefetcherTest` (snapshot-consistent profile+key; injected-factory used; `AiRequest` built from profile; cache-hit-no-profile #306; no-profile miss→ProviderFailed; **`prefetchDirect` 1:1; `cachedDirect` restores with zero provider calls**; CJK↔English + Latin round-trip via fake; cipher-throw→ProviderFailed not crash); `BilingualAiReadinessTest` (active+key→true; no active→false; empty key→false; **cipher-throw→false, no crash**); `PerBookBilingualStoreTest` (enabled/lang/granularity round-trip; no style field); `BilingualViewModelTest` (Turbine: first-enable sheet; re-enable no-sheet; disable clears; language reset; **granularity reset + re-key**; prefetch current+next; same-unit no-op; cancel-mid discards; offline→unavailable; error→errorUnit+retry; `retryUnit`); `EpubBilingualJsTest` (**JS escaping / CSP-safe text insertion; RTL/CJK style; empty translations; clear idempotent; inject idempotent replacement; source-only fallback** — WI-7b, if go).

Room migration: `VReaderDatabaseMigrationTest` (extend) **v8→v9 + full-chain from v8** + FK-CASCADE + `lookupKey`-as-PK; `ChapterTranslationDaoTest` (upsert-by-PK replaces; get/delete-by-lookupKey).

Compose UI (`androidTest/...bilingual/`): `BilingualSetupSheetUiTest` (language grid, granularity, preview, engine configured vs unconfigured; **no Style control present**; light+dark); `BilingualInterlinearBodyUiTest` (translated incl. CJK font + RTL Arabic; loading N%+dimmed; error+Retry; offline source-only; empty translation→source-only no crash); `BilingualPillUiTest`.

Connected (`androidTest/...reader/`): `TxtReaderBilingualConnectedTest` (API 35, fake `AiClient` via injected factory): enable→setup→confirm→interlinear from seeded Room cache; disable→source-only byte-parity; reopen persists enabled + renders from cache with zero client calls; **paragraph-spanning-chunk-boundary renders one translation**; TXT/MD gated (PDF inert); very long chapter scroll responsive; cancellation leaves no partial cache row. `EpubReaderBilingualConnectedTest` (only if WI-0=go): enable→inject on a real EPUB; disable→clear; href-change/fragment-recreation/activity-recreation→re-apply from cache (zero provider calls); **count-divergence handled via `prefetchDirect`/`cachedDirect`**.

Edge cases: empty translation, failed, partial per-chunk, CJK↔English + Latin + RTL, provider error/timeout/429/config/insecure, cancellation mid-translation + before-write, very long chapters, offline (cache-first + silent source-only), cipher-decrypt failure → not-ready (no crash), enumerate↔segment count divergence (direct path).

## 6. Risks + mitigations

- **Live-translation verification is AI-credential-gated (the box-D caveat).** The whole pipeline is verified without live creds via a deterministic **fake `AiClient`** injected through the prefetcher's `clientFactory` param (default `AiProviderFactory::create`; tests override). WI-3/4a/8 prove segment→chunk→decode→cache→interleave end-to-end incl. every error/edge path. Connected tests seed the Room cache and assert render-from-cache with zero client calls (render path proven offline). This mock/integration path is the box-D-required verification path; an optional live smoke confirms wire format but is NOT a gate. **#136's Gate-5 covers the fresh-user `unconfigured → Set up → add provider` reachability leg.**
- **TXT/MD segment↔render pairing (round-2 H1).** Both sides read the SAME segment range array (`paragraphRanges`/`sentenceRanges` over `TxtDocument.text`), so 1:1 holds by construction — no chapter model is invented, and a paragraph split across a chunk boundary is translated + rendered once. Granularity is in the cache key so a paragraph row is never read as sentences.
- **EPUB count divergence (round-2 H2).** The direct-block path (`prefetchDirect` → `translatePreSegmented`, cached by enumerate count, restored by `cachedDirect(expectedCount)` with zero provider calls) is now implemented across WI-3/WI-4a and exercised by `EpubReaderBilingualConnectedTest.count-divergence handled` — iOS Bugs #268/#330/#343 parity.
- **EPUB JS-injection race (round-2 M1).** WI-0's contract (single actor/mutex OR monotonic navigator-session token; token check after every suspended JS/AI call; clear before publication teardown; identified production re-apply signal per recreation case). No deterministic re-apply signal = explicit NO-GO → TXT/MD-only ship.
- **EPUB render surface (round-2 M2).** EPUB uses `EpubBilingualJs` DOM injection (CSP-safe, Kotlin-escaped), NOT the Compose body; both share only the `BilingualRenderState` DTO.
- **Concurrency.** WI-6: monotonic position-request sequence; per-unit generation tokens; captured language/granularity/provider snapshot per launch; cancellation on granularity change; `CancellationException` before generic error mapping; `ensureActive()` before the Room write; cipher/decrypt failures → not-ready (never a crash). Snapshot-consistent profile+key from one `snapshot()`.
- **Cost/latency of translating on scroll.** Lazy current+next prefetch + disk cache; N-of-M progress; cancellation on navigate-away/generation-bump.
- **Provider JSON non-compliance.** `TranslationChunkContract.decode` + per-segment fallback — never drops a paragraph.
- **DataStore per-book key growth.** One Preferences entry per book keyed by fingerprint; scales like `ReaderSettingsStore`/`AiProviderStore`.
- **#136 dependency risk.** #131's DONE flip + the "Set up" route + `AiProviderStore` in `AppContainer` all block on #136. #131's pipeline/UI (WI-0..WI-8 except WI-4b's DI) build ahead; WI-4b + WI-9 gate on #136.

## 7. Backward compat

- **Room migration additive (round-2 M4).** New `chapter_translations` (FK CASCADE, `lookupKey` PK, `sourceParagraphCount`). Existing rows untouched. Version allocated current→next at the merge slot; against this checkout **8→9, `MIGRATION_8_9`** appended after `MIGRATION_7_8`; migration test extended from **v8** guards it.
- **Reader unchanged when bilingual off** — the TXT/MD `items(chunkCount)` loop is byte-identical unless `enabled && format∈{txt,md} && translation present` (bilingual content is a pure segment-range overlay). `ReaderBottomChrome` is not modified. EPUB render adapter is inert unless bilingual is on.
- **#118 AI provider files unchanged** — the prefetcher/readiness are new consumers. **`AiProviderStore` into `AppContainer` is #136's change, not #131's**; #131's DI WI (WI-4b) wires the bilingual services around it.
- **Backup contract already compatible** — `PerBookSettingsOverride.bilingualEnabled/TargetLanguage/Granularity` exist (verified; no `bilingualStyle`), and there is no translation-cache backup section (the cache is device-local, re-derivable). #131 writes the three fields locally; backup collect/restore is a small additive follow-up (no contract change), out of v1 scope; until then bilingual config is device-local.
- **#132/#134/#129 landed** — the top-chrome pill mount + More-menu toggle + `TxtReaderActivity` edit land on VERIFIED surfaces (rule 48 one-writer-per-file is satisfied; #129 is merged).

## Design gates (rule 51 — for `needs-design` filing)

1. **"Bilingual mode" setup sheet with BOTH Style AND Granularity in one Android sheet** — `vreader-bilingual.jsx` depicts Granularity (no Style); `vreader-ai-android.jsx` depicts Style (no Granularity); no committed bundle shows both together. v1 reproduces the granularity-only `vreader-bilingual.jsx` sheet and **DROPS Style (user descope decision — §3/H3)**. If Style is wanted as an Android user control, file `Design needed: bilingual setup sheet (Style + Granularity) for feature #131`. **This is the one open design gate for #131.** The box-D Style parity gap is tracked by the WI-9 follow-up checklist amendment.
2. **#136 dependency (not a #131 design gate)** — the setup sheet's "Set up"/"Change…" affordance routes to #136's AI-provider-entry sheet. #136 owns the sheet + its production reachability + `AiProviderStore` in `AppContainer`; #131 wires the affordance and consumes the store. #131 does not invent the AI-config sheet (rule 51).

## Revision history

- v1 (2026-07-10): Gate-1 draft (Plan agent). Gate-2 Codex audit pending.
- v2 (2026-07-11): Gate-2 round-1 REDESIGN resolved — Readium-feasibility corrected, entry-point rebased on box F, setup-sheet design-gated, DI/cache/concurrency fixed.
- v3 (2026-07-12) — Gate-2 round-2 findings resolved: TXT/MD document-global segment model (H1); EPUB translatePreSegmented + count-keyed cache + direct-block prefetch (H2); #136 AI-provider-reachability spun out as a hard dependency (filed GH #1976) + Style descoped v1 (H3, user decision); WI-0 go/no-go + navigator-race contract (M1); EPUB DOM-injection adapter not Compose body (M2); DI/factory WI reordered (M3); Room 8→9 MIGRATION_8_9 (M4); deps/WI-count corrected (L1/L2). Awaiting Gate-2 round-3 audit.

## Notes on assumptions not fully confirmed against live code

- The exact iOS `TranslationUnitID.Kind` case names for the TXT/MD variants — the Android `Kind` names (`txtDocSegmentWindow`/`mdDocSegmentWindow`) describe the real document-global unit. Only the `storageKey` string format is load-bearing for the cache contract, and that is preserved.
- The unit-window size constant for TXT/MD sub-batching is left to build time (it does not affect the 1:1 segment↔render contract, only cache-row granularity/prefetch scope).

exec
/bin/zsh -lc 'rg -n "''^## 3|''^## 4|WI-0|navigator-race|go/no-go|segment range|anchored|overlap|#136|Style" dev-docs/plans/20260710-feature-131-android-bilingual-interlinear.md && nl -ba android/app/src/main/kotlin/com/vreader/app/reader/TxtDocument.kt && rg -n "class ReaderActivity|EpubNavigatorFragment|navigator|evaluateJavascript|getCurrentLocator" android/app/src/main/kotlin android/app/src/test android/app/src/androidTest --glob '"'*.kt' && rg -n \"@Database|version\\s*=|ALL_MIGRATIONS|MIGRATION_[0-9]+_[0-9]+|@Upsert|@PrimaryKey\" android/app/src/main/kotlin/com/vreader/app/data --glob '*.kt'" in /Users/ll/workspace/vreader
 succeeded in 0ms:
3:**Feature number assumption:** highest active row in `docs/features.md` is `#136`; `#131` is a landed `PLANNED` row (`GH: #1923`). The orchestrator adjusts if a row is claimed first.
25:1. **EPUB (Readium `EpubNavigatorFragment`) — PRIMARY.** Interlinear via `evaluateJavascript` (enumerate leaf blocks → inject translation DOM nodes → clear on teardown/reflow), mirroring iOS `EPUBBilingualOrchestrator`. Gated by **WI-0 (a Readium bilingual spike with enforceable go/no-go thresholds + a navigator-race contract — round-2 M1)** before the EPUB render WI (WI-7b) is built.
26:2. **TXT/MD (Compose `TxtReaderActivity`) — INCLUDED.** No WebView; deterministically Compose-testable. Renders from **document-global segment ranges** (round-2 H1), NOT one body per chunk.
36:**v3 model — document-global units with segment ranges produced ONCE:**
39:- **Unit granularity for TXT/MD is the whole document, sub-batched for cache/prefetch by a deterministic "unit window."** To avoid translating a 14 MB book at once (and to keep cache rows bounded), segment ranges are grouped into fixed **unit windows** of contiguous segments (window size a constant, e.g. covering ≈ one on-screen span; the exact constant is set at build time and does not change the 1:1 contract). Each window is a `TranslationUnitId(kind = txtDocSegmentWindow, value = windowIndex)` — a document-global index, NOT a chunk index. `unitContaining(locator)` maps the reader's saved `charOffsetUTF16` → the segment whose range contains it → its window index (via a precomputed segment-start binary search, the same shape as `TxtDocument.chunkForOffset`). `unitAfter(unit)` = next window index or null at document end.
40:- **Render mapping (the LazyColumn):** the TXT/MD body still iterates the existing `items(count = document.chunkCount, key = { it })` loop (verified injection point, TxtReaderActivity.kt:1043) for source layout/selection/highlight parity — **but bilingual interlinear content is keyed by SEGMENT RANGE, not by chunk.** For each rendered chunk `i` (source UTF-16 span `[offsetForChunk(i), offsetForChunk(i+1))`), the body looks up every segment whose range **overlaps** that chunk span and, after the source text of that segment's portion, renders its cached translation (muted) — from the SAME range array the translator used. A segment spanning two chunks contributes its translation once, anchored at the chunk where its range ends (deterministic), so a paragraph split across a chunk boundary is translated once and rendered once. When bilingual is OFF, the loop is byte-identical to today (translations are additive overlays only).
54:- `bilingual/TranslationChunkContract.kt` — `userPrompt(segments, targetLanguage)`; `decode(raw, expectedCount)` (strict JSON-array + code-fence strip); `sealed class DecodeError { NotAStringArray; CountMismatch(expected, actual) }`. Port of iOS `TranslationChunkContract`. (No `style` param — Style is descoped v1, §3/H3.)
56:- `bilingual/TxtChapterTextProvider.kt` — provider over `TxtDocument` + the segmenter's range array (H1). Builds the document-global segment ranges once, groups them into windows, resolves `unitContaining` via a segment-start binary search over `charOffsetUTF16`. MD source = raw markdown segment text.
57:- `bilingual/EpubChapterTextProvider.kt` (WI-0-gated shape) — provider over the Readium `Publication` reading order; `units()` = spine hrefs, `unitContaining(locator)` = the locator's href, `sourceSegments(unit)` = the DOM-enumerated block texts (the render's OWN enumeration, for direct-block 1:1 — H2). Its render-side collaborator (the JS enumerate/inject adapter) is `EpubBilingualJs` (M2), defined by WI-0's findings.
74:- `bilingual/PerBookBilingualStore.kt` — DataStore-Preferences, keyed by `bookFingerprintKey`, holding `{ enabled, targetLanguage, granularity }`. This is the Android `PerBookSettingsOverride` bilingual slice — the backup contract declares exactly `bilingualEnabled` / `bilingualTargetLanguage` / `bilingualGranularity` and **NO `bilingualStyle`** (verified). So this store writes exactly those three fields. Wiring into backup collect/restore is scoped OUT (§7) — additive later; until then bilingual config is device-local.
75:- `bilingual/BilingualViewModel.kt` — `StateFlow<BilingualUiState>` with `enabled`, `targetLanguage`, `granularity`, `needsSetupSheet`, `aiConfigured`, `translationsByUnit`, `inFlightUnits`, `unavailableUnits`, `errorUnit`. Setters + `dismissSetupSheet`, `onPositionChanged(locator)`, `retryUnit(unit)`. Generation/epoch-guarded prefetch (current + next unit), cancellation on disable / language / granularity change — port of iOS `BilingualReadingViewModel` + `+Prefetch`. Split to `BilingualPrefetchController.kt` if it nears ~300 lines. (No `style` field — the authoritative sheet has no Style control; Style is descoped v1 — §3.)
83:**Cache-identity (reconciled with iOS parity):** the 4-part key `book|unit|lang|promptVersion` is profile-AGNOSTIC / style-agnostic (Bug #342). Style is descoped v1 (§3/H3) so no `s=` component exists. **Granularity IS user-selectable**, so it is carried in `promptVersion` as an **effective composite**: `promptVersion = "bilingual-v1|g=${granularity}"` (a paragraph vs sentence translation is a different cache row — this also closes the iOS #344 "sentence silently ignored" class by construction). A granularity change must cancel in-flight jobs, bump the VM generation, clear shaped in-memory `translationsByUnit`, and force a correctly-keyed re-fetch (specified in WI-6).
87:**AI-provider reachability — spun out to #136 (round-2 H3; ORCHESTRATOR/USER DECISION):** verified against the live code — `AppContainer` does **NOT** provide `AiProviderStore`, and there is **NO live navigation route to `AiProviderListScreen`** (MainActivity has no NavHost; the #118 screen + store + `AiSettingsViewModel` exist but are only exercised by instrumented/round-trip tests). A fresh-install user therefore cannot reach provider config today. This gap is now owned by a **NEW separate tiny feature #136 (AI provider setup made production-reachable)** — a **HARD dependency of #131**. #136 delivers: the AI-provider-entry sheet/route, its production reachability, `AiProviderStore` wired into `AppContainer`, and its own Gate-5 acceptance (`unconfigured → Set up → add provider → return → enable → translate`). **#131 keeps only the wiring** of the bilingual "Set up translation" affordance → #136's AI-provider-entry sheet (WI-9's entry-wiring), and consumes `AiProviderStore` from `AppContainer` (provided by #136). #131 does NOT invent the AI-config sheet or its nav (rule 51). *(Assumption: #136 IS now a `docs/features.md` row — filed 2026-07-12 as GH #1976; #131's `Deps` reference it.)*
91:- `bilingual/BilingualSetupSheet.kt` — reproduces `vreader-bilingual.jsx`'s `BilingualSetupSheet` EXACTLY: header Cancel / Translate; a **preview strip**; a **language grid** over `BILINGUAL_LANGS` (glyph tiles, selected accent); a **Granularity** segmented control (Paragraph "Translate after each ¶" / Sentence "Translate after each sentence"); a **Translation engine** strip (configured: "Claude · with this book's context" + "Change…"; unconfigured: "No AI provider configured" + "Set up"). **No Style control, no provider/model card, no term-overrides toggle, no cost footer** — those belong to the other (`vreader-ai-android.jsx`) sheet, which this plan does not reproduce (§3). The **"Set up" CTA routes to #136's AI-provider-entry sheet** (wired in WI-9); "Change…" routes there too.
94:- `bilingual/EpubBilingualJs.kt` (WI-0-gated) — **the EPUB render surface (round-2 M2).** A pure Kotlin builder that, from a `BilingualRenderState` unit, produces the **JS strings** for `navigator.evaluateJavascript(...)`: (a) `enumScript` (enumerate current-resource leaf blocks → JSON `[{id,text}]`), (b) `injectScript(blockId, translationText)` (construct a translation DOM node after the block, CSP-safe: text set via `textContent`/`createTextNode`, never `innerHTML` string-concat; RTL/CJK via a class + injected `<style>`), (c) `clearScript()` (remove all injected nodes idempotently). Escaping is done in Kotlin (JSON-encode every interpolated string) so a translation containing quotes/`</script>`/newlines cannot break out. **No Compose here.** Consumes `BilingualRenderState`.
95:- `bilingual/EpubBilingualController.kt` (WI-0-gated) — the runtime actor that serializes enumerate→translate→inject/clear against the navigator using WI-0's chosen mechanism (a single mutex OR a monotonic navigator-session token — M1); checks the session token after every suspended JS/AI call; clears BEFORE publication teardown; re-applies on the identified production re-apply signal (M1).
101:- `reader/TxtReaderActivity.kt` — own a `BilingualViewModel`; collect state; render translations in the existing `items(count = document.chunkCount, key = { it })` loop (verified injection point, TxtReaderActivity.kt:1043) **keyed by segment range overlap (H1)**, not per chunk; on position change call `vm.onPositionChanged(canonicalLocator.charOffsetUTF16)`. Strictly gated to `originalFormat ∈ {txt, md}`; disabled = body byte-unchanged (overlay-only). **This file is owned by #129 (VERIFIED); #131's edit lands on top of it (rule 48 one-writer-per-file) — #129 is merged, so this is a straight edit, not a blocker.**
102:- `reader/ReaderActivity.kt` (Readium EPUB) — WI-0-gated: attach `EpubBilingualController` to `navigator.evaluateJavascript`; re-apply on the identified production re-apply signal (M1); clear on teardown BEFORE publication teardown. Concrete surface defined by WI-0's spike output. `navigator: EpubNavigatorFragment?` is the verified live field.
103:- `VReaderApp.kt` / `AppContainer` — **consume `AiProviderStore` (provided by #136), and provide** `ChapterTranslationStore`, `PerBookBilingualStore`, `ChapterTranslationService`, `ChapterTranslationPrefetcher`, and a `BilingualViewModel` factory. **Extracted into the shared DI WI (WI-4b, round-2 M3)** so both host integrations depend on it. Mirrors #116/#118/#122 DI. *(Note: `AiProviderStore`-into-`AppContainer` is #136's deliverable; #131's DI WI wires the bilingual services around it.)*
109:- **`Azw3ReaderActivity.kt` / `reader/foliate/`** — foliate WebView interlinear IS feasible (JS enumerate+inject in the pinned bundle) but deferred (bundle-patch JS + secure-bridge additions touching the security-sensitive #126 surface). Once WI-0 proves the EPUB JS pipeline, the foliate host reuses `EpubBilingualJs` with a bundle adapter.
111:- **The AI-provider setup sheet + its production reachability + `AiProviderStore` in `AppContainer`** — owned by **#136** (a hard dependency). #131 wires only the "Set up"/"Change…" affordance to #136's sheet.
113:- **Style control** — descoped v1 (user decision, §3/H3). #131 keeps provider/model/**granularity**, DROPS the bilingual "Style" control.
117:## 3. Prior art / project precedent / rejected alternatives
125:**WI-0 — Readium bilingual spike (gates WI-7b; round-2 M1 rewrote its contract into enforceable go/no-go thresholds):** a throwaway harness that, against a real EPUB on the emulator, must PROVE (each is a pass/no-go criterion):
133:**Race contract (M1):** WI-0 specifies **either a single actor/mutex OR a monotonic navigator-session token**; every suspended JS/AI call is followed by a token/mutex check; cancellation/clear runs BEFORE publication teardown. **If WI-0 cannot find a deterministic production re-apply signal for a recreation case (c), that is an explicit NO-GO:** EPUB drops to a tracked follow-up and box D ships **TXT/MD-only** — with the honest reason (a specific spike finding), never the false "requires a fork."
140:5. **One `BilingualInterlinearBody` per chunk (v2)** — REJECTED (round-2 H1): a chunk is not a segment. Replaced by document-global segment ranges (§2).
143:### The setup-sheet resolution (rule 51) + Style descope (round-2 H3, USER DECISION)
146:- `vreader-bilingual.jsx` → **language grid + Granularity + preview strip + Translation-engine strip (Set up/Change) + Cancel/Translate**. **No Style, no provider/model card, no term-overrides, no cost.**
147:- `vreader-ai-android.jsx` → **Languages (From/To) + Provider card + Style (Literal/Natural/Literary) + Keep-term-overrides toggle + cost footer.** **No language grid, no Granularity, no preview.**
149:**Resolution:** this plan reproduces the **`vreader-bilingual.jsx` sheet EXACTLY** as the authoritative Android-native bilingual sheet. **Style is DESCOPED for v1** (user decision): #131 keeps provider/model/**granularity**, DROPS the bilingual "Style" control. Consequently the store/VM carry no `style`, the chunk contract has no `style` param, and the cache key's `promptVersion` has no `s=` component. Keep rule 51: only implement the designed surface.
151:**Box-D parity note (H3 — do NOT claim full box-D parity):** the box-D parity checklist lists provider/model/**style**. Because Style is descoped v1, **WI-9 flips box D to done ONLY for provider/model/granularity + a descope note** — it does NOT claim full box-D parity. A **follow-up tracker/checklist amendment records the Style descope** (the plan does not silently drop it). If Style is later wanted on Android as a user control, that needs an **updated committed design** (a single sheet showing BOTH Style AND Granularity is not depicted anywhere — the one open design gate below).
155:- **#118 provider seam**: reuse `AiProviderStore.snapshot()` (`snapshot.active`) + `store.apiKey(profile)` + `AiProviderFactory.create` (default of an injected factory param) + `AiClient.chat`. #118's AI files are unchanged; **#136** wires `AiProviderStore` into `AppContainer`; #131's DI WI wires the bilingual services.
161:## 4. Work-item sequencing
163:**11 WIs/PRs (round-2 L2):** WI-0 (spike), WI-1..WI-4a (foundation/service), **WI-4b (shared DI/factory)**, WI-5, WI-6, WI-7a (Compose UI), **WI-7b (conditional EPUB render adapter — dropped if WI-0 = no-go)**, WI-8 (TXT/MD host integration), WI-9 (entry wiring + acceptance). Each WI = one PR. Build order (round-2 M3): **foundation/cache → service/direct-block APIs → shared DI/factory → VM state/prefetch → host-specific renderers (TXT/MD + EPUB) → entry wiring.**
166:- **`Deps: [feat:#136, feat:#132, feat:#134]`.** **#132 (top chrome) and #134 (More menu) are VERIFIED — dependencies satisfied** (the top-chrome host + `MoreActionId.BILINGUAL` toggle row are landed). **#129 (TXT/MD reader) is VERIFIED** — `TxtReaderActivity` is a straight edit, not a blocker. **#136 (AI provider setup made production-reachable) is the NEW hard blocker** for #131's entry-wiring (the "Set up"/"Change…" route) AND the DONE flip; it provides `AiProviderStore` in `AppContainer` and the reachable AI-config sheet. The live More model already reserves `MoreActionId.BILINGUAL` (verified).
167:- The pipeline + setup sheet + interlinear render (WI-0..WI-7) are built ahead; only the **entry wiring (WI-9)** and the **DI WI (WI-4b, for `AiProviderStore` in `AppContainer`)** wait on #136. The pill mount (WI-9) targets #132's VERIFIED top chrome; the toggle wire (WI-9) targets #134's VERIFIED More menu.
169:**WI-0 (spike): Readium EPUB bilingual injection — with enforceable go/no-go + race contract (M1).** The harness + criteria (a)–(e) and the race contract in §3. Output: a **go/no-go on EPUB-in-v1** (no-go if no deterministic production re-apply signal — box D ships TXT/MD-only, tracked) + the concrete `EpubChapterTextProvider` / `EpubBilingualJs` / `EpubBilingualController` surfaces. Deps: none (uses the existing #106 Readium host). Not TDD-gated (throwaway spike); its findings feed WI-7b.
177:**WI-4a (foundational): `ChapterTextProvider` (TXT/MD) + `ChapterTranslationPrefetcher` + `BilingualAiReadiness`.** `TxtChapterTextProvider` builds the **document-global segment ranges once (H1)**, groups into windows, resolves `unitContaining(charOffsetUTF16)` via segment-start binary search, `sourceSegments(unit)`. Prefetcher: `prefetch` + **`prefetchDirect` + `cachedDirect` (zero-provider cache restore — H2)**; resolves active profile from `snapshot()`, decrypts snapshot-consistent, builds client via the **injected factory param** (default `AiProviderFactory::create`), constructs `AiRequest` from the profile. Readiness = active profile with non-empty decrypted key; **cipher failure → not-ready, never a crash.** Fake store + fake factory. Deps: **WI-1, WI-3**. Tests: unit resolution + clamp + empty; **paragraph spanning a chunk boundary → one segment/one unit; multiple paragraphs in one chunk → distinct segments; a >4000-char paragraph → one segment across chunks; CR/LF/CRLF; MD markers; locator→unit mapping; source-byte parity while disabled**; cache-hit-no-profile still returns (#306); no-profile miss → `ProviderFailed`; `prefetchDirect` 1:1; `cachedDirect` restores with zero provider calls; readiness true/false; cipher-throw → readiness false (no crash).
179:**WI-4b (foundational — shared DI/factory, round-2 M3): AppContainer bilingual services.** Extract the DI/factory wiring into this EARLIER shared WI: `AppContainer` provides `ChapterTranslationStore`, `PerBookBilingualStore`, `ChapterTranslationService`, `ChapterTranslationPrefetcher`, and the `BilingualViewModel` factory — **consuming `AiProviderStore` from `AppContainer` (provided by #136).** Both host integrations (WI-7b, WI-8) depend on this. Deps: **WI-4a, feat:#136** (for `AiProviderStore` in `AppContainer`). Tests: container resolves the bilingual graph; the prefetcher's injected factory defaults to `AiProviderFactory::create`.
185:**WI-7a (behavioral): Compose UI — setup sheet + interlinear body (TXT/MD) + pill.** Reproduce `vreader-bilingual.jsx` (setup sheet: language grid / granularity / preview / engine strip configured+unconfigured; body: translated / loading N%+dimmed / error+Retry / offline source-only; pill). Consumes the **host-neutral `BilingualRenderState` DTO (M2)**. Light+dark. Compose UI tests each state. Deps: **WI-5** (state shape). NO Style control; the unconfigured "Set up" CTA renders and (in WI-9) routes to #136's sheet.
187:**WI-7b (behavioral, CONDITIONAL — only if WI-0 = go): EPUB render adapter (DOM injection, NOT Compose — round-2 M2).** `EpubBilingualJs` (enum/inject/clear JS builders, CSP-safe escaping) + `EpubBilingualController` (the serialization actor / session token — M1) + `EpubChapterTextProvider`, wired into `ReaderActivity`, driving DOM from the **shared `BilingualRenderState` DTO**. **Depends on WI-6 (VM prefetch) and WI-4b (DI) — the M3 fix; the WI-7a UI dependency is REMOVED except for the shared `BilingualRenderState`/value types.** Uses `prefetchDirect`/`cachedDirect` for the count-divergence path (H2). Connected test on a real EPUB (seeded cache): enable → interlinear injects; disable → nodes cleared; reflow/href-change/fragment-recreation/activity-recreation → re-applies from cache (zero provider calls); count-divergence handled (direct path). Unit tests: JS escaping/CSP-safe text insertion, RTL/CJK style, empty translations, loading cleanup, idempotent replacement, source-only fallback. Deps: **WI-0, WI-3, WI-4a, WI-4b, WI-6, (shared types from WI-7a)**. (If WI-0 = no-go, this WI is dropped and box D ships TXT/MD-only, tracked.)
189:**WI-8 (behavioral): `TxtReaderActivity` integration.** Wire VM into the `items(chunkCount)` loop **keyed by segment-range overlap (H1)** + position-change (`charOffsetUTF16`) + setup-sheet. `originalFormat`-gated (TXT/MD). Uses WI-4b's DI. **#129 is VERIFIED — straight edit.** Connected test (fake `AiClient` seam): enable → setup → confirm → interlinear from seeded cache; disable → source-only byte-parity; reopen persists enabled + renders from cache with zero client calls; paragraph-spanning-chunk-boundary renders one translation. Deps: **WI-6, WI-7a, WI-4b**.
191:**WI-9 (behavioral): entry wiring + acceptance.** Mount `BilingualPill` in **#132's VERIFIED top chrome**; wire the **#134 VERIFIED More-menu `MoreActionId.BILINGUAL` toggle** (`MoreRow.Toggle` `on`/`onToggle`) to the VM; **wire the setup sheet's "Set up"/"Change…" affordance → #136's AI-provider-entry sheet.** Full acceptance pass across EPUB (if WI-7b landed) + TXT/MD, including the fresh-user path `unconfigured → Set up (→ #136 sheet) → add provider → return → enable → translate` (the #136-owned reachability verified jointly). **Flip box D to done ONLY for provider/model/granularity + the Style-descope note (H3); file the follow-up checklist amendment; do NOT claim full box-D parity, do NOT flip DONE until #136 is landed.** Update `docs/architecture.md` (bilingual pipeline + the new `chapter_translations` schema + bilingual services in `AppContainer`). → DONE. Deps: **WI-8, WI-7b (if go), feat:#136, feat:#132, feat:#134**.
199:Compose UI (`androidTest/...bilingual/`): `BilingualSetupSheetUiTest` (language grid, granularity, preview, engine configured vs unconfigured; **no Style control present**; light+dark); `BilingualInterlinearBodyUiTest` (translated incl. CJK font + RTL Arabic; loading N%+dimmed; error+Retry; offline source-only; empty translation→source-only no crash); `BilingualPillUiTest`.
201:Connected (`androidTest/...reader/`): `TxtReaderBilingualConnectedTest` (API 35, fake `AiClient` via injected factory): enable→setup→confirm→interlinear from seeded Room cache; disable→source-only byte-parity; reopen persists enabled + renders from cache with zero client calls; **paragraph-spanning-chunk-boundary renders one translation**; TXT/MD gated (PDF inert); very long chapter scroll responsive; cancellation leaves no partial cache row. `EpubReaderBilingualConnectedTest` (only if WI-0=go): enable→inject on a real EPUB; disable→clear; href-change/fragment-recreation/activity-recreation→re-apply from cache (zero provider calls); **count-divergence handled via `prefetchDirect`/`cachedDirect`**.
207:- **Live-translation verification is AI-credential-gated (the box-D caveat).** The whole pipeline is verified without live creds via a deterministic **fake `AiClient`** injected through the prefetcher's `clientFactory` param (default `AiProviderFactory::create`; tests override). WI-3/4a/8 prove segment→chunk→decode→cache→interleave end-to-end incl. every error/edge path. Connected tests seed the Room cache and assert render-from-cache with zero client calls (render path proven offline). This mock/integration path is the box-D-required verification path; an optional live smoke confirms wire format but is NOT a gate. **#136's Gate-5 covers the fresh-user `unconfigured → Set up → add provider` reachability leg.**
208:- **TXT/MD segment↔render pairing (round-2 H1).** Both sides read the SAME segment range array (`paragraphRanges`/`sentenceRanges` over `TxtDocument.text`), so 1:1 holds by construction — no chapter model is invented, and a paragraph split across a chunk boundary is translated + rendered once. Granularity is in the cache key so a paragraph row is never read as sentences.
210:- **EPUB JS-injection race (round-2 M1).** WI-0's contract (single actor/mutex OR monotonic navigator-session token; token check after every suspended JS/AI call; clear before publication teardown; identified production re-apply signal per recreation case). No deterministic re-apply signal = explicit NO-GO → TXT/MD-only ship.
216:- **#136 dependency risk.** #131's DONE flip + the "Set up" route + `AiProviderStore` in `AppContainer` all block on #136. #131's pipeline/UI (WI-0..WI-8 except WI-4b's DI) build ahead; WI-4b + WI-9 gate on #136.
222:- **#118 AI provider files unchanged** — the prefetcher/readiness are new consumers. **`AiProviderStore` into `AppContainer` is #136's change, not #131's**; #131's DI WI (WI-4b) wires the bilingual services around it.
223:- **Backup contract already compatible** — `PerBookSettingsOverride.bilingualEnabled/TargetLanguage/Granularity` exist (verified; no `bilingualStyle`), and there is no translation-cache backup section (the cache is device-local, re-derivable). #131 writes the three fields locally; backup collect/restore is a small additive follow-up (no contract change), out of v1 scope; until then bilingual config is device-local.
228:1. **"Bilingual mode" setup sheet with BOTH Style AND Granularity in one Android sheet** — `vreader-bilingual.jsx` depicts Granularity (no Style); `vreader-ai-android.jsx` depicts Style (no Granularity); no committed bundle shows both together. v1 reproduces the granularity-only `vreader-bilingual.jsx` sheet and **DROPS Style (user descope decision — §3/H3)**. If Style is wanted as an Android user control, file `Design needed: bilingual setup sheet (Style + Granularity) for feature #131`. **This is the one open design gate for #131.** The box-D Style parity gap is tracked by the WI-9 follow-up checklist amendment.
229:2. **#136 dependency (not a #131 design gate)** — the setup sheet's "Set up"/"Change…" affordance routes to #136's AI-provider-entry sheet. #136 owns the sheet + its production reachability + `AiProviderStore` in `AppContainer`; #131 wires the affordance and consumes the store. #131 does not invent the AI-config sheet (rule 51).
235:- v3 (2026-07-12) — Gate-2 round-2 findings resolved: TXT/MD document-global segment model (H1); EPUB translatePreSegmented + count-keyed cache + direct-block prefetch (H2); #136 AI-provider-reachability spun out as a hard dependency (filed GH #1976) + Style descoped v1 (H3, user decision); WI-0 go/no-go + navigator-race contract (M1); EPUB DOM-injection adapter not Compose body (M2); DI/factory WI reordered (M3); Room 8→9 MIGRATION_8_9 (M4); deps/WI-count corrected (L1/L2). Awaiting Gate-2 round-3 audit.
     1	// Purpose: Addressable, range-based model of a decoded .txt — feature #111 WI-1.
     2	// Holds ONE backing decoded String and an array of chunk START offsets (UTF-16 code
     3	// units against the RAW text — NO line-ending normalization, so charOffsetUTF16 stays
     4	// exact for resume). Splits at line boundaries (CRLF/CR/LF kept inside the chunk);
     5	// hard-splits a runaway line at maxChunkChars (never mid-surrogate-pair). Visible
     6	// chunk text is materialized on demand (no per-chunk substrings retained). Pure JVM.
     7	package com.vreader.app.reader
     8	
     9	class TxtDocument private constructor(
    10	    val text: String,
    11	    private val starts: IntArray,
    12	) {
    13	    /** Number of chunks (0 for empty text). */
    14	    val chunkCount: Int get() = starts.size
    15	
    16	    /** The UTF-16 start offset of chunk [index] (clamped to a valid chunk). */
    17	    fun offsetForChunk(index: Int): Int {
    18	        if (starts.isEmpty()) return 0
    19	        return starts[index.coerceIn(0, starts.size - 1)]
    20	    }
    21	
    22	    /** The chunk index containing [offsetUtf16] (EOF-clamped); 0 for empty text. */
    23	    fun chunkForOffset(offsetUtf16: Int): Int {
    24	        if (starts.isEmpty()) return 0
    25	        val offset = offsetUtf16.coerceIn(0, text.length)
    26	        // Largest start <= offset (binary search).
    27	        var lo = 0; var hi = starts.size - 1; var ans = 0
    28	        while (lo <= hi) {
    29	            val mid = (lo + hi) ushr 1
    30	            if (starts[mid] <= offset) { ans = mid; lo = mid + 1 } else { hi = mid - 1 }
    31	        }
    32	        return ans
    33	    }
    34	
    35	    /** The text of chunk [index], materialized on demand from the backing string. */
    36	    fun textForChunk(index: Int): CharSequence {
    37	        if (starts.isEmpty()) return ""
    38	        val i = index.coerceIn(0, starts.size - 1)
    39	        val end = if (i + 1 < starts.size) starts[i + 1] else text.length
    40	        return text.subSequence(starts[i], end)
    41	    }
    42	
    43	    companion object {
    44	        const val DEFAULT_MAX_CHUNK_CHARS = 4000
    45	
    46	        /**
    47	         * Build a document from already-decoded [text]. Chunk boundaries fall after a
    48	         * line terminator (`\n`, `\r`, or `\r\n` — preserved in the chunk); a line longer
    49	         * than [maxChunkChars] is hard-split, but never between a surrogate pair.
    50	         */
    51	        fun of(text: String, maxChunkChars: Int = DEFAULT_MAX_CHUNK_CHARS): TxtDocument {
    52	            if (text.isEmpty()) return TxtDocument(text, IntArray(0))
    53	            // Primitive growable IntArray (no Int boxing) — a newline-dense 14MB file
    54	            // would otherwise spike tens of MB of boxed Integers + a duplicating copy.
    55	            var starts = IntArray(64)
    56	            var count = 0
    57	            fun push(v: Int) {
    58	                if (count == starts.size) starts = starts.copyOf(starts.size * 2)
    59	                starts[count++] = v
    60	            }
    61	            push(0)
    62	            var i = 0
    63	            var chunkStart = 0
    64	            val n = text.length
    65	            while (i < n) {
    66	                val c = text[i]
    67	                when {
    68	                    c == '\n' -> {
    69	                        i++
    70	                        if (i < n) { push(i); chunkStart = i }
    71	                    }
    72	                    c == '\r' -> {
    73	                        i++
    74	                        if (i < n && text[i] == '\n') i++   // CRLF stays one terminator
    75	                        if (i < n) { push(i); chunkStart = i }
    76	                    }
    77	                    else -> {
    78	                        i++
    79	                        // Hard-split a runaway line, but not mid-surrogate-pair (don't
    80	                        // split right after a high surrogate — its low half follows at i).
    81	                        if (i - chunkStart >= maxChunkChars && i < n && !text[i - 1].isHighSurrogate()) {
    82	                            push(i); chunkStart = i
    83	                        }
    84	                    }
    85	                }
    86	            }
    87	            return TxtDocument(text, starts.copyOf(count))
    88	        }
    89	    }
    90	}
android/app/src/androidTest/kotlin/com/vreader/app/backup/BookmarkBackupRestoreJumpTest.kt:41: *     landing precondition (`navigator.go(readium)` in WI-9's live navigator);
android/app/src/androidTest/kotlin/com/vreader/app/backup/BookmarkBackupRestoreJumpTest.kt:147:                // reconstructed Readium locator (the landing precision `navigator.go` uses at WI-9).
android/app/src/androidTest/kotlin/com/vreader/app/reader/EpubFindInBookTest.kt:22: * #128 FTS index. Instrumented because Readium's EpubNavigatorFragment renders in a REAL WebView (not
android/app/src/androidTest/kotlin/com/vreader/app/reader/EpubFindInBookTest.kt:30: *  - tapping a hit → `Locator.fromJSON(readiumLocatorJson)` → `navigator.go` LANDS (the reading href/
android/app/src/androidTest/kotlin/com/vreader/app/reader/EpubFindInBookTest.kt:91:            // The reading position actually moved (or at least the navigator accepted the go); the href is a
android/app/src/androidTest/kotlin/com/vreader/app/reader/EpubFindInBookTest.kt:99:            assertNotNull("the navigator still has a rendered locator after the jump", hrefAfter)
android/app/src/androidTest/kotlin/com/vreader/app/reader/EpubFindInBookTest.kt:193:     *  opens); returns the rendered href (asserts the navigator + VM are live). */
android/app/src/androidTest/kotlin/com/vreader/app/reader/EpubFindInBookTest.kt:205:        assertNotNull("the navigator rendered a reading locator", href)
android/app/src/main/kotlin/com/vreader/app/VReaderApp.kt:195:     * jumps to with `navigator.go`.
android/app/src/main/kotlin/com/vreader/app/annotations/EpubAnnotationMapper.kt:4:// Kept free of Compose/Activity so the mapping is unit-testable; the navigator wiring lives in
android/app/src/androidTest/kotlin/com/vreader/app/reader/EpubDisplaySettingsConnectedTest.kt:19: * EpubNavigatorFragment resolves its settings against a real WebView (not Robolectric). Seeds a
android/app/src/androidTest/kotlin/com/vreader/app/reader/EpubDisplaySettingsConnectedTest.kt:20: * non-default theme in the global ReaderSettingsStore, opens the reader, and asserts the navigator's
android/app/src/androidTest/kotlin/com/vreader/app/reader/EpubDisplaySettingsConnectedTest.kt:23: * This proves the setting reached + was resolved by the live navigator — not that the WebView painted
android/app/src/androidTest/kotlin/com/vreader/app/reader/EpubDisplaySettingsConnectedTest.kt:47:                assertNotNull("navigator accepted a background color", applied)
android/app/src/androidTest/kotlin/com/vreader/app/reader/EpubDisplaySettingsConnectedTest.kt:49:                    "the stored Dark theme background reached the live navigator",
android/app/src/androidTest/kotlin/com/vreader/app/reader/EpubDisplaySettingsConnectedTest.kt:60:                    "a live theme change re-submitted to the navigator",
android/app/src/androidTest/kotlin/com/vreader/app/reader/ReaderActivityTest.kt:18: * EpubNavigatorFragment renders in a real WebView (not Robolectric). Imports the
android/app/src/androidTest/kotlin/com/vreader/app/reader/ReaderActivityTest.kt:20: * asserts the navigator renders a locator (the content loaded) + the open marked
android/app/src/androidTest/kotlin/com/vreader/app/reader/ReaderActivityTest.kt:24:class ReaderActivityTest {
android/app/src/androidTest/kotlin/com/vreader/app/reader/ReaderActivityTest.kt:34:            // The open + render is async; poll the navigator's current locator.
android/app/src/androidTest/kotlin/com/vreader/app/reader/ReaderActivityTest.kt:41:            assertNotNull("the navigator rendered a reading locator (content loaded)", href)
android/app/src/androidTest/kotlin/com/vreader/app/reader/ReaderActivityTest.kt:77:     *  navigator/WebView (the reopen path `observeHighlights` → `applyHighlights`). Seeds the highlight
android/app/src/androidTest/kotlin/com/vreader/app/reader/ReaderActivityTest.kt:89:            assertNotNull("navigator rendered", href)
android/app/src/androidTest/kotlin/com/vreader/app/reader/ReaderActivityTest.kt:108:            assertTrue("the stored highlight applied as a decoration on the live navigator", applied >= 1)
android/app/src/androidTest/kotlin/com/vreader/app/reader/ReaderChromeConnectedTest.kt:19: * the Readium EpubNavigatorFragment. Instrumented because the navigator resolves its TOC + reading
android/app/src/androidTest/kotlin/com/vreader/app/reader/ReaderChromeConnectedTest.kt:22: * `navigator.go` (currentHref changes on a valid jump), that a false/stale jump leaves the sheet open with
android/app/src/androidTest/kotlin/com/vreader/app/reader/ReaderChromeConnectedTest.kt:46:            // Wait for the navigator to render a locator (content loaded).
android/app/src/androidTest/kotlin/com/vreader/app/reader/ReaderChromeConnectedTest.kt:57:            assertTrue("a valid TOC jump reported success (native navigator.go returned true)", jumped)
android/app/src/androidTest/kotlin/com/vreader/app/reader/EpubBookmarkNavTest.kt:20: * Feature #135 WI-7 — the EPUB bookmark host wiring, instrumented because Readium's EpubNavigatorFragment
android/app/src/androidTest/kotlin/com/vreader/app/reader/EpubBookmarkNavTest.kt:120:    /** Poll the navigator's rendered locator; returns the rendered href (asserts it rendered). */
android/app/src/androidTest/kotlin/com/vreader/app/reader/EpubBookmarkNavTest.kt:128:        assertNotNull("the navigator rendered a reading locator", href)
android/app/src/main/kotlin/com/vreader/app/search/InBookSearchModels.kt:85: *   never references the Readium type; the host reconstructs it and calls `navigator.go`.
android/app/src/androidTest/kotlin/com/vreader/app/reader/foliate/FoliateSpikeHarnessTest.kt:133:        InstrumentationRegistry.getInstrumentation().runOnMainSync { wv.evaluateJavascript(js, null) }
android/app/src/test/kotlin/com/vreader/app/reader/EpubPreferencesMappingTest.kt:15:import org.readium.r2.navigator.preferences.Color as ReadiumColor
android/app/src/test/kotlin/com/vreader/app/reader/EpubPreferencesMappingTest.kt:16:import org.readium.r2.navigator.preferences.FontFamily as ReadiumFontFamily
android/app/src/test/kotlin/com/vreader/app/search/EpubInBookSearchEngineTest.kt:23: * highlight -> snippet, the raw locator retained for `navigator.go`) is asserted against genuine objects,
android/app/src/test/kotlin/com/vreader/app/search/EpubInBookSearchEngineTest.kt:142:        // The RAW Readium locator is retained verbatim for navigator.go.
android/app/src/main/kotlin/com/vreader/app/search/EpubInBookSearchEngine.kt:5:// returns REAL href-bearing, snippet-bearing `Locator`s the navigator jumps to natively (`nav.go`), so the
android/app/src/main/kotlin/com/vreader/app/search/EpubInBookSearchEngine.kt:30://   group (honest — the navigator still jumps by the raw locator).
android/app/src/main/kotlin/com/vreader/app/search/EpubInBookSearchEngine.kt:50: * A single located EPUB search hit: the RAW Readium [readiumLocator] the navigator jumps to via
android/app/src/main/kotlin/com/vreader/app/search/EpubInBookSearchEngine.kt:51: * `navigator.go`, plus the presentation fields the hit row needs — the chapter [sectionTitle] (grouping
android/app/src/main/kotlin/com/vreader/app/reader/ReaderHighlightController.kt:1:// Purpose: feature #123 WI-3 — wraps Readium's selection + decoration APIs (EpubNavigatorFragment
android/app/src/main/kotlin/com/vreader/app/reader/ReaderHighlightController.kt:10:import org.readium.r2.navigator.Decoration
android/app/src/main/kotlin/com/vreader/app/reader/ReaderHighlightController.kt:11:import org.readium.r2.navigator.DecorableNavigator
android/app/src/main/kotlin/com/vreader/app/reader/ReaderHighlightController.kt:12:import org.readium.r2.navigator.epub.EpubNavigatorFragment
android/app/src/main/kotlin/com/vreader/app/reader/ReaderHighlightController.kt:17:class ReaderHighlightController(private val navigator: EpubNavigatorFragment) {
android/app/src/main/kotlin/com/vreader/app/reader/ReaderHighlightController.kt:31:        navigator.applyDecorations(decorations, GROUP)
android/app/src/main/kotlin/com/vreader/app/reader/ReaderHighlightController.kt:36:    suspend fun currentSelectionLocator(): ReadiumLocator? = navigator.currentSelection()?.locator
android/app/src/main/kotlin/com/vreader/app/reader/ReaderHighlightController.kt:38:    fun clearSelection() = navigator.clearSelection()
android/app/src/main/kotlin/com/vreader/app/reader/ReaderHighlightController.kt:43:        navigator.addDecorationListener(
android/app/src/main/kotlin/com/vreader/app/reader/ReadiumLocatorBridge.kt:93:     * The verbatim Readium Locator JSON to feed back to the navigator for a PRECISE
android/app/src/main/kotlin/com/vreader/app/reader/EpubPreferencesMapper.kt:18:import org.readium.r2.navigator.epub.EpubPreferences
android/app/src/main/kotlin/com/vreader/app/reader/EpubPreferencesMapper.kt:19:import org.readium.r2.navigator.preferences.Color as ReadiumColor
android/app/src/main/kotlin/com/vreader/app/reader/EpubPreferencesMapper.kt:20:import org.readium.r2.navigator.preferences.FontFamily as ReadiumFontFamily
android/app/src/main/kotlin/com/vreader/app/reader/nav/ReadiumTocProvider.kt:5:// zero-reconstruction `navigator.go` jump and (b) converts to the engine-neutral
android/app/src/test/kotlin/com/vreader/app/reader/Azw3DisplayCssTest.kt:156:    // FoliateBridge.setStyles runs through evaluateJavascript) wraps the CSS in a JSON-encoded literal.
android/app/src/main/kotlin/com/vreader/app/reader/nav/TocEntry.kt:5:// `Locator` (null for non-Readium hosts) so a TOC jump feeds `navigator.go` its
android/app/src/main/kotlin/com/vreader/app/reader/nav/TocEntry.kt:22: *                    zero-reconstruction `navigator.go` jump; null for non-Readium hosts.
android/app/src/main/kotlin/com/vreader/app/reader/nav/TocBookmarksSheet.kt:63: * The outcome of a bookmark jump. A jump can fail (EPUB `toReadium` null / `navigator.go` false; AZW3
android/app/src/main/kotlin/com/vreader/app/reader/EpubReaderChrome.kt:2:// (ReaderActivity). The EPUB host is the outlier: a Readium EpubNavigatorFragment (a View) renders the
android/app/src/main/kotlin/com/vreader/app/reader/EpubReaderChrome.kt:17:// Contents onJump → the host's `navigator.go(entry.epubReadiumLocator)` (Boolean): dismiss on success,
android/app/src/main/kotlin/com/vreader/app/reader/EpubReaderChrome.kt:24:// @coordinates-with: ReaderActivity.kt (owns the StateFlow + the ComposeViews + the navigator jump + the
android/app/src/main/kotlin/com/vreader/app/reader/ReaderChromeModel.kt:4:// EpubNavigatorFragment View under the chrome, not a Compose body), so it cannot reuse the Compose-native
android/app/src/main/kotlin/com/vreader/app/reader/ReaderChromeModel.kt:43: * read from the navigator's `currentLocator`) to [tocIndexFor].
android/app/src/main/kotlin/com/vreader/app/reader/ResumeResolver.kt:7:// applies the target to the Readium navigator.
android/app/src/main/kotlin/com/vreader/app/reader/ResumeResolver.kt:17:     * Feed [readiumLocatorJSON] to the navigator for an exact restore — and if that
android/app/src/main/kotlin/com/vreader/app/reader/ReadiumLocatorReconstructor.kt:64: * persisted bookmark (canonical-only) can be jumped to via `navigator.go`.
android/app/src/main/kotlin/com/vreader/app/reader/foliate/FoliateBridge.kt:83:        // the OS freezer can suspend it after a few idle seconds, so a page-turn (evaluateJavascript)
android/app/src/main/kotlin/com/vreader/app/reader/foliate/FoliateBridge.kt:161:     *  `evaluateJavascript` runs (no test-vs-production drift). Mirrors iOS Foliate `setStyles`. */
android/app/src/main/kotlin/com/vreader/app/reader/foliate/FoliateBridge.kt:166:    private fun eval(js: String) = webView.evaluateJavascript(js, null)
android/app/src/main/kotlin/com/vreader/app/reader/foliate/FoliateBridge.kt:303: * seam [FoliateBridge.setStyles] runs through `evaluateJavascript`, so the escaping the unit test pins
android/app/src/main/kotlin/com/vreader/app/reader/ReaderActivity.kt:2:// EpubNavigatorFragment in scroll mode (Spike-B-verified), opening the stored EPUB
android/app/src/main/kotlin/com/vreader/app/reader/ReaderActivity.kt:7:// EpubNavigatorFragment View under the chrome, not a Compose body) and the ONLY TOC-supplying host, so it
android/app/src/main/kotlin/com/vreader/app/reader/ReaderActivity.kt:15:// onJump → navigator.go(entry.epubReadiumLocator):Boolean (dismiss on success, stay-open on false, no
android/app/src/main/kotlin/com/vreader/app/reader/ReaderActivity.kt:24:// hit jumps via Locator.fromJSON(readiumLocatorJson) → navigator.go (Succeeded dismisses / Failed keeps open,
android/app/src/main/kotlin/com/vreader/app/reader/ReaderActivity.kt:87:import org.readium.r2.navigator.epub.EpubNavigatorFactory
android/app/src/main/kotlin/com/vreader/app/reader/ReaderActivity.kt:88:import org.readium.r2.navigator.epub.EpubNavigatorFragment
android/app/src/main/kotlin/com/vreader/app/reader/ReaderActivity.kt:89:import org.readium.r2.navigator.epub.EpubPreferences
android/app/src/main/kotlin/com/vreader/app/reader/ReaderActivity.kt:101:class ReaderActivity : AppCompatActivity() {
android/app/src/main/kotlin/com/vreader/app/reader/ReaderActivity.kt:110:    private var navigator: EpubNavigatorFragment? = null
android/app/src/main/kotlin/com/vreader/app/reader/ReaderActivity.kt:126:    // read from the navigator's currentLocator totalProgression (EPUB scroll mode).
android/app/src/main/kotlin/com/vreader/app/reader/ReaderActivity.kt:139:    // The live reading position as a canonical Locator (null until the navigator has a locator). Read on the
android/app/src/main/kotlin/com/vreader/app/reader/ReaderActivity.kt:168:        // The navigator fragment can't be restored before its FragmentFactory is set,
android/app/src/main/kotlin/com/vreader/app/reader/ReaderActivity.kt:178:        // value + live updates), mirroring how observeDisplaySettings feeds the navigator.
android/app/src/main/kotlin/com/vreader/app/reader/ReaderActivity.kt:206:            val nav: EpubNavigatorFragment? = withStarted {
android/app/src/main/kotlin/com/vreader/app/reader/ReaderActivity.kt:211:                    listener = object : EpubNavigatorFragment.Listener {
android/app/src/main/kotlin/com/vreader/app/reader/ReaderActivity.kt:214:                    configuration = EpubNavigatorFragment.Configuration().apply {
android/app/src/main/kotlin/com/vreader/app/reader/ReaderActivity.kt:220:                    add(containerId, EpubNavigatorFragment::class.java, Bundle(), READER_TAG)
android/app/src/main/kotlin/com/vreader/app/reader/ReaderActivity.kt:222:                supportFragmentManager.findFragmentByTag(READER_TAG) as EpubNavigatorFragment
android/app/src/main/kotlin/com/vreader/app/reader/ReaderActivity.kt:225:            navigator = nav
android/app/src/main/kotlin/com/vreader/app/reader/ReaderActivity.kt:268:    private suspend fun populateChromeModel(pub: Publication, current: Book, nav: EpubNavigatorFragment) {
android/app/src/main/kotlin/com/vreader/app/reader/ReaderActivity.kt:346:    /** Test hook: the count of highlights applied as decorations on the live navigator (-1 until the
android/app/src/main/kotlin/com/vreader/app/reader/ReaderActivity.kt:347:     *  first apply). Proves the reopen-render path ran against the real EpubNavigatorFragment. */
android/app/src/main/kotlin/com/vreader/app/reader/ReaderActivity.kt:361:                val nav = navigator ?: run { mode?.finish(); return@launch }
android/app/src/main/kotlin/com/vreader/app/reader/ReaderActivity.kt:449:        val nav = navigator ?: return
android/app/src/main/kotlin/com/vreader/app/reader/ReaderActivity.kt:462:        // Host owns the Publication (Readium's navigator does not close it). The
android/app/src/main/kotlin/com/vreader/app/reader/ReaderActivity.kt:477:    /** feature #129 WI-5 — apply the live "Display" settings to the navigator: re-submit Readium
android/app/src/main/kotlin/com/vreader/app/reader/ReaderActivity.kt:482:    private fun observeDisplaySettings(nav: EpubNavigatorFragment) {
android/app/src/main/kotlin/com/vreader/app/reader/ReaderActivity.kt:494:    private fun observePosition(nav: EpubNavigatorFragment, current: Book) {
android/app/src/main/kotlin/com/vreader/app/reader/ReaderActivity.kt:558:     *  navigator has no locator yet (currentCanonical null → no dead toggle). */
android/app/src/main/kotlin/com/vreader/app/reader/ReaderActivity.kt:571:     *  `navigator.go`. A null reconstruction (malformed/unresolvable/renamed href, or a different-book
android/app/src/main/kotlin/com/vreader/app/reader/ReaderActivity.kt:575:        val nav = navigator ?: return JumpResult.Failed
android/app/src/main/kotlin/com/vreader/app/reader/ReaderActivity.kt:586:     *  `Locator.fromJSON(JSONObject(json))` and `navigator.go`. A null/blank/malformed JSON (an un-jumpable
android/app/src/main/kotlin/com/vreader/app/reader/ReaderActivity.kt:592:        val nav = navigator ?: return JumpResult.Failed
android/app/src/main/kotlin/com/vreader/app/reader/ReaderActivity.kt:620:     *  body is a View (EpubNavigatorFragment), NOT a composable, the chrome cannot use the Compose-native
android/app/src/main/kotlin/com/vreader/app/reader/ReaderActivity.kt:715:     *  `navigator.go` (zero reconstruction). Returns Readium's Boolean success so the Contents sheet
android/app/src/main/kotlin/com/vreader/app/reader/ReaderActivity.kt:719:        val nav = navigator ?: return false
android/app/src/main/kotlin/com/vreader/app/reader/ReaderActivity.kt:726:     *  current href and navigates there. A tolerated no-op when the navigator/publication isn't ready. */
android/app/src/main/kotlin/com/vreader/app/reader/ReaderActivity.kt:728:        val nav = navigator ?: return
android/app/src/main/kotlin/com/vreader/app/reader/ReaderActivity.kt:847:    /** Test hook: the current reading href, or null until the navigator has rendered. */
android/app/src/main/kotlin/com/vreader/app/reader/ReaderActivity.kt:849:    fun currentHref(): String? = navigator?.currentLocator?.value?.href?.toString()
android/app/src/main/kotlin/com/vreader/app/reader/ReaderActivity.kt:895:    /** Test hook (feature #129 WI-5): the background ARGB the live navigator has *accepted/computed*
android/app/src/main/kotlin/com/vreader/app/reader/ReaderActivity.kt:896:     *  for its EpubSettings (the applied theme background), or null before the navigator/settings exist.
android/app/src/main/kotlin/com/vreader/app/reader/ReaderActivity.kt:897:     *  Proves the Display setting reached and was resolved by the live EpubNavigatorFragment — it does
android/app/src/main/kotlin/com/vreader/app/reader/ReaderActivity.kt:900:    fun appliedBackgroundArgb(): Int? = navigator?.settings?.value?.backgroundColor?.int
android/app/src/main/kotlin/com/vreader/app/reader/ReaderActivity.kt:932:        private const val READER_TAG = "reader-navigator"
android/app/src/main/kotlin/com/vreader/app/reader/ReaderActivity.kt:954: * feature #135 WI-7 — map an EPUB reader's LIVE reading position (extracted from the navigator's Readium
android/app/src/main/kotlin/com/vreader/app/data/Daos.kt:18:    // @Upsert (insert-or-UPDATE), NOT @Insert(REPLACE). REPLACE is delete-then-insert
android/app/src/main/kotlin/com/vreader/app/data/Daos.kt:20:    // wipe a book's saved position on every re-import (Gate-4 Critical). @Upsert
android/app/src/main/kotlin/com/vreader/app/data/Daos.kt:23:    // NOTE: the SAF import path does NOT use this whole-row @Upsert — it uses
android/app/src/main/kotlin/com/vreader/app/data/Daos.kt:28:    @Upsert
android/app/src/main/kotlin/com/vreader/app/data/Daos.kt:118:    @Upsert
android/app/src/main/kotlin/com/vreader/app/data/Daos.kt:136:    // unreliable on API 26/27), and @Upsert can't increment. INSERT OR IGNORE a zero row, then UPDATE
android/app/src/main/kotlin/com/vreader/app/data/Daos.kt:231:    @Upsert
android/app/src/main/kotlin/com/vreader/app/data/Daos.kt:249:    @Upsert
android/app/src/main/kotlin/com/vreader/app/data/CollectionEntities.kt:21:    @PrimaryKey val id: String,   // UUID string — internal PK, NOT the backup identity (name+createdAt is)
android/app/src/main/kotlin/com/vreader/app/data/SearchEntities.kt:48:    @PrimaryKey(autoGenerate = true) val id: Long = 0,
android/app/src/main/kotlin/com/vreader/app/data/SearchEntities.kt:90:    @PrimaryKey val bookKey: String,
android/app/src/main/kotlin/com/vreader/app/data/SearchEntities.kt:116:    @PrimaryKey(autoGenerate = true) val id: Long = 0,
android/app/src/main/kotlin/com/vreader/app/data/Entities.kt:20: * path goes through [BookDao.upsertPreservingAuthor], not the whole-row `@Upsert`).
android/app/src/main/kotlin/com/vreader/app/data/Entities.kt:24:    @PrimaryKey val fingerprintKey: String,
android/app/src/main/kotlin/com/vreader/app/data/Entities.kt:58:    @PrimaryKey val fingerprintKey: String,
android/app/src/main/kotlin/com/vreader/app/data/Entities.kt:105:    @PrimaryKey val highlightId: String,   // UUID string (iOS `highlightId: UUID` parity)
android/app/src/main/kotlin/com/vreader/app/data/Entities.kt:137:    @PrimaryKey val noteId: String,
android/app/src/main/kotlin/com/vreader/app/data/Entities.kt:170:    @PrimaryKey val bookmarkId: String,
android/app/src/main/kotlin/com/vreader/app/data/VReaderDatabase.kt:3:// MIGRATION_1_2 is the worked example of the additive-migration pattern (adds
android/app/src/main/kotlin/com/vreader/app/data/VReaderDatabase.kt:11:// Migration(n, n+1) to ALL_MIGRATIONS and bump `version`.
android/app/src/main/kotlin/com/vreader/app/data/VReaderDatabase.kt:21:@Database(
android/app/src/main/kotlin/com/vreader/app/data/VReaderDatabase.kt:29:    version = 8,
android/app/src/main/kotlin/com/vreader/app/data/VReaderDatabase.kt:44:        val MIGRATION_1_2: Migration = object : Migration(1, 2) {
android/app/src/main/kotlin/com/vreader/app/data/VReaderDatabase.kt:52:        val MIGRATION_2_3: Migration = object : Migration(2, 3) {
android/app/src/main/kotlin/com/vreader/app/data/VReaderDatabase.kt:67:        val MIGRATION_3_4: Migration = object : Migration(3, 4) {
android/app/src/main/kotlin/com/vreader/app/data/VReaderDatabase.kt:112:        val MIGRATION_4_5: Migration = object : Migration(4, 5) {
android/app/src/main/kotlin/com/vreader/app/data/VReaderDatabase.kt:138:        val MIGRATION_5_6: Migration = object : Migration(5, 6) {
android/app/src/main/kotlin/com/vreader/app/data/VReaderDatabase.kt:151:        val MIGRATION_6_7: Migration = object : Migration(6, 7) {
android/app/src/main/kotlin/com/vreader/app/data/VReaderDatabase.kt:198:        val MIGRATION_7_8: Migration = object : Migration(7, 8) {
android/app/src/main/kotlin/com/vreader/app/data/VReaderDatabase.kt:224:        val ALL_MIGRATIONS: Array<Migration> =
android/app/src/main/kotlin/com/vreader/app/data/VReaderDatabase.kt:226:                MIGRATION_1_2, MIGRATION_2_3, MIGRATION_3_4, MIGRATION_4_5,
android/app/src/main/kotlin/com/vreader/app/data/VReaderDatabase.kt:227:                MIGRATION_5_6, MIGRATION_6_7, MIGRATION_7_8,
android/app/src/main/kotlin/com/vreader/app/data/VReaderDatabase.kt:233:                .addMigrations(*ALL_MIGRATIONS)

exec
/bin/zsh -lc "nl -ba android/app/src/main/kotlin/com/vreader/app/reader/TxtDocument.kt && nl -ba android/app/src/main/kotlin/com/vreader/app/reader/TxtReaderActivity.kt | sed -n '1015,1075p' && nl -ba android/app/src/main/kotlin/com/vreader/app/data/VReaderDatabase.kt | sed -n '15,240p' && nl -ba android/app/src/main/kotlin/com/vreader/app/data/Daos.kt | sed -n '1,45p' && nl -ba android/app/src/main/kotlin/com/vreader/app/data/Entities.kt | sed -n '15,35p'" in /Users/ll/workspace/vreader
 succeeded in 0ms:
     1	// Purpose: Addressable, range-based model of a decoded .txt — feature #111 WI-1.
     2	// Holds ONE backing decoded String and an array of chunk START offsets (UTF-16 code
     3	// units against the RAW text — NO line-ending normalization, so charOffsetUTF16 stays
     4	// exact for resume). Splits at line boundaries (CRLF/CR/LF kept inside the chunk);
     5	// hard-splits a runaway line at maxChunkChars (never mid-surrogate-pair). Visible
     6	// chunk text is materialized on demand (no per-chunk substrings retained). Pure JVM.
     7	package com.vreader.app.reader
     8	
     9	class TxtDocument private constructor(
    10	    val text: String,
    11	    private val starts: IntArray,
    12	) {
    13	    /** Number of chunks (0 for empty text). */
    14	    val chunkCount: Int get() = starts.size
    15	
    16	    /** The UTF-16 start offset of chunk [index] (clamped to a valid chunk). */
    17	    fun offsetForChunk(index: Int): Int {
    18	        if (starts.isEmpty()) return 0
    19	        return starts[index.coerceIn(0, starts.size - 1)]
    20	    }
    21	
    22	    /** The chunk index containing [offsetUtf16] (EOF-clamped); 0 for empty text. */
    23	    fun chunkForOffset(offsetUtf16: Int): Int {
    24	        if (starts.isEmpty()) return 0
    25	        val offset = offsetUtf16.coerceIn(0, text.length)
    26	        // Largest start <= offset (binary search).
    27	        var lo = 0; var hi = starts.size - 1; var ans = 0
    28	        while (lo <= hi) {
    29	            val mid = (lo + hi) ushr 1
    30	            if (starts[mid] <= offset) { ans = mid; lo = mid + 1 } else { hi = mid - 1 }
    31	        }
    32	        return ans
    33	    }
    34	
    35	    /** The text of chunk [index], materialized on demand from the backing string. */
    36	    fun textForChunk(index: Int): CharSequence {
    37	        if (starts.isEmpty()) return ""
    38	        val i = index.coerceIn(0, starts.size - 1)
    39	        val end = if (i + 1 < starts.size) starts[i + 1] else text.length
    40	        return text.subSequence(starts[i], end)
    41	    }
    42	
    43	    companion object {
    44	        const val DEFAULT_MAX_CHUNK_CHARS = 4000
    45	
    46	        /**
    47	         * Build a document from already-decoded [text]. Chunk boundaries fall after a
    48	         * line terminator (`\n`, `\r`, or `\r\n` — preserved in the chunk); a line longer
    49	         * than [maxChunkChars] is hard-split, but never between a surrogate pair.
    50	         */
    51	        fun of(text: String, maxChunkChars: Int = DEFAULT_MAX_CHUNK_CHARS): TxtDocument {
    52	            if (text.isEmpty()) return TxtDocument(text, IntArray(0))
    53	            // Primitive growable IntArray (no Int boxing) — a newline-dense 14MB file
    54	            // would otherwise spike tens of MB of boxed Integers + a duplicating copy.
    55	            var starts = IntArray(64)
    56	            var count = 0
    57	            fun push(v: Int) {
    58	                if (count == starts.size) starts = starts.copyOf(starts.size * 2)
    59	                starts[count++] = v
    60	            }
    61	            push(0)
    62	            var i = 0
    63	            var chunkStart = 0
    64	            val n = text.length
    65	            while (i < n) {
    66	                val c = text[i]
    67	                when {
    68	                    c == '\n' -> {
    69	                        i++
    70	                        if (i < n) { push(i); chunkStart = i }
    71	                    }
    72	                    c == '\r' -> {
    73	                        i++
    74	                        if (i < n && text[i] == '\n') i++   // CRLF stays one terminator
    75	                        if (i < n) { push(i); chunkStart = i }
    76	                    }
    77	                    else -> {
    78	                        i++
    79	                        // Hard-split a runaway line, but not mid-surrogate-pair (don't
    80	                        // split right after a high surrogate — its low half follows at i).
    81	                        if (i - chunkStart >= maxChunkChars && i < n && !text[i - 1].isHighSurrogate()) {
    82	                            push(i); chunkStart = i
    83	                        }
    84	                    }
    85	                }
    86	            }
    87	            return TxtDocument(text, starts.copyOf(count))
    88	        }
    89	    }
    90	}
  1015	            .then(
  1016	                if (selectionController != null) {
  1017	                    // ONE detector distinguishes a TAP (edit an existing highlight) from a LONG-PRESS+drag
  1018	                    // (new selection) — two separate pointerInput detectors conflict over the same down event.
  1019	                    Modifier.pointerInput(selectionController) {
  1020	                        awaitEachGesture {
  1021	                            val down = awaitFirstDown(requireUnconsumed = false)
  1022	                            val longPress = awaitLongPressOrCancellation(down.id)
  1023	                            if (longPress != null) {
  1024	                                // long-press → selection; finalize only on a COMPLETED drag/up (not a cancel).
  1025	                                selectionController.beginAt(longPress.position)
  1026	                                val completed = drag(longPress.id) { change -> selectionController.extendTo(change.position); change.consume() }
  1027	                                if (completed) currentOnFinalize() else selectionController.clear()
  1028	                            } else if (!down.isConsumed) {
  1029	                                // null also means cancel (e.g. a scroll won) — only a TAP leaves the down
  1030	                                // unconsumed; a scroll consumes it, so it won't be misread as tap-to-edit.
  1031	                                currentOnTap(down.position)
  1032	                            }
  1033	                        }
  1034	                    }
  1035	                } else {
  1036	                    Modifier
  1037	                },
  1038	            ),
  1039	        state = listState,
  1040	        contentPadding = PaddingValues(horizontal = marginDp.dp, vertical = 16.dp),
  1041	    ) {
  1042	        // Count-based: indices on demand (a newline-dense 14MB file can be 100k+ chunks).
  1043	        items(count = document.chunkCount, key = { it }) { i ->
  1044	            val raw = document.textForChunk(i).toString()
  1045	            // .md → styled markdown spans (no read-aloud span wash — markers shift offsets, plan §OOS).
  1046	            // .txt → raw verbatim, with the spoken-sentence span washed when read-aloud is active.
  1047	            val span = if (isMarkdown) null else highlightSpan(i)
  1048	            val text = when {
  1049	                isMarkdown -> mapper.renderedText(i)   // #125: the mapper is the single render owner
  1050	                span != null -> buildAnnotatedString {
  1051	                    append(raw)
  1052	                    val a = span.first.coerceIn(0, raw.length); val b = (span.last + 1).coerceIn(a, raw.length)
  1053	                    if (b > a) addStyle(SpanStyle(background = wash), a, b)
  1054	                }
  1055	                else -> AnnotatedString(raw)
  1056	            }
  1057	            // annotation washes drawn BEHIND the text (getPathForRange) — separate from the read-aloud span.
  1058	            val washes = washesForChunk(i)
  1059	            var layout by remember(i) { mutableStateOf<TextLayoutResult?>(null) }
  1060	            var coords by remember(i) { mutableStateOf<androidx.compose.ui.layout.LayoutCoordinates?>(null) }
  1061	            if (selectionController != null) {
  1062	                LaunchedEffect(i, layout, coords) {
  1063	                    val l = layout; val c = coords
  1064	                    if (l != null && c != null) selectionController.registerChunk(i, l, c)
  1065	                }
  1066	                DisposableEffect(selectionController, i) { onDispose { selectionController.unregisterChunk(i) } }
  1067	            }
  1068	            // read `selection` (a State) so a selection change recomposes + redraws the accent.
  1069	            val selRange = if (selection != null) selectionController?.selectionForChunk(i) else null
  1070	            Text(
  1071	                text = text,
  1072	                // merge over the material default (the pre-#129 explicit-param behavior) so platform
  1073	                // text defaults (letterSpacing etc.) are kept — only the Display settings change.
  1074	                style = androidx.compose.material3.LocalTextStyle.current.merge(textStyle),
  1075	                onTextLayout = { layout = it },
    15	import androidx.room.Database
    16	import androidx.room.Room
    17	import androidx.room.RoomDatabase
    18	import androidx.room.migration.Migration
    19	import androidx.sqlite.db.SupportSQLiteDatabase
    20	
    21	@Database(
    22	    entities = [
    23	        BookEntity::class, ReadingPositionEntity::class, DailyReadingEntity::class,
    24	        HighlightEntity::class, AnnotationNoteEntity::class, BookmarkEntity::class,
    25	        CollectionEntity::class, BookCollectionCrossRef::class,
    26	        SearchSectionEntity::class, SearchSectionFtsEntity::class,
    27	        SearchIndexStateEntity::class, SearchStagingEntity::class,
    28	    ],
    29	    version = 8,
    30	    exportSchema = true,
    31	)
    32	abstract class VReaderDatabase : RoomDatabase() {
    33	    abstract fun bookDao(): BookDao
    34	    abstract fun readingPositionDao(): ReadingPositionDao
    35	    abstract fun readingStatsDao(): ReadingStatsDao
    36	    abstract fun annotationDao(): AnnotationDao
    37	    abstract fun collectionDao(): CollectionDao
    38	    abstract fun searchDao(): SearchDao
    39	
    40	    companion object {
    41	        private const val DB_NAME = "vreader.db"
    42	
    43	        /** v1 → v2: add the nullable `lastOpenedAt` recents column to `books`. */
    44	        val MIGRATION_1_2: Migration = object : Migration(1, 2) {
    45	            override fun migrate(db: SupportSQLiteDatabase) {
    46	                db.execSQL("ALTER TABLE books ADD COLUMN lastOpenedAt INTEGER")
    47	            }
    48	        }
    49	
    50	        /** v2 → v3: feature #122 — add the additive `daily_reading` per-day/per-book stats table +
    51	         *  its bookKey index. No data transform. DDL matches Room's generated schema exactly. */
    52	        val MIGRATION_2_3: Migration = object : Migration(2, 3) {
    53	            override fun migrate(db: SupportSQLiteDatabase) {
    54	                db.execSQL(
    55	                    "CREATE TABLE IF NOT EXISTS `daily_reading` (`date` TEXT NOT NULL, `bookKey` TEXT NOT NULL, " +
    56	                        "`minutes` INTEGER NOT NULL, PRIMARY KEY(`date`, `bookKey`))",
    57	                )
    58	                db.execSQL("CREATE INDEX IF NOT EXISTS `index_daily_reading_bookKey` ON `daily_reading` (`bookKey`)")
    59	            }
    60	        }
    61	
    62	        /** v3 → v4: feature #123 — add the additive `highlights`, `annotation_notes`, and `bookmarks`
    63	         *  annotation tables (each FK→books ON DELETE CASCADE; highlights has the unique
    64	         *  `(profileKey, anchorKey)` dedupe index). No data transform. DDL matches Room's generated
    65	         *  schema for v4 exactly (the migration test opens the real Room DB, whose structural PRAGMA
    66	         *  validation catches any drift). */
    67	        val MIGRATION_3_4: Migration = object : Migration(3, 4) {
    68	            override fun migrate(db: SupportSQLiteDatabase) {
    69	                db.execSQL(
    70	                    "CREATE TABLE IF NOT EXISTS `highlights` (`highlightId` TEXT NOT NULL, " +
    71	                        "`bookKey` TEXT NOT NULL, `profileKey` TEXT NOT NULL, `anchorKey` TEXT NOT NULL, " +
    72	                        "`color` TEXT NOT NULL, `selectedText` TEXT NOT NULL, `note` TEXT, " +
    73	                        "`locatorJSON` TEXT NOT NULL, `anchorJSON` TEXT, `createdAt` INTEGER NOT NULL, " +
    74	                        "`updatedAt` INTEGER NOT NULL, PRIMARY KEY(`highlightId`), " +
    75	                        "FOREIGN KEY(`bookKey`) REFERENCES `books`(`fingerprintKey`) " +
    76	                        "ON UPDATE NO ACTION ON DELETE CASCADE )",
    77	                )
    78	                db.execSQL("CREATE INDEX IF NOT EXISTS `index_highlights_bookKey` ON `highlights` (`bookKey`)")
    79	                db.execSQL(
    80	                    "CREATE UNIQUE INDEX IF NOT EXISTS `index_highlights_profileKey_anchorKey` " +
    81	                        "ON `highlights` (`profileKey`, `anchorKey`)",
    82	                )
    83	                db.execSQL(
    84	                    "CREATE TABLE IF NOT EXISTS `annotation_notes` (`noteId` TEXT NOT NULL, " +
    85	                        "`bookKey` TEXT NOT NULL, `profileKey` TEXT NOT NULL, `content` TEXT NOT NULL, " +
    86	                        "`locatorJSON` TEXT NOT NULL, `anchorJSON` TEXT, `createdAt` INTEGER NOT NULL, " +
    87	                        "`updatedAt` INTEGER NOT NULL, PRIMARY KEY(`noteId`), " +
    88	                        "FOREIGN KEY(`bookKey`) REFERENCES `books`(`fingerprintKey`) " +
    89	                        "ON UPDATE NO ACTION ON DELETE CASCADE )",
    90	                )
    91	                db.execSQL(
    92	                    "CREATE INDEX IF NOT EXISTS `index_annotation_notes_bookKey` " +
    93	                        "ON `annotation_notes` (`bookKey`)",
    94	                )
    95	                db.execSQL(
    96	                    "CREATE TABLE IF NOT EXISTS `bookmarks` (`bookmarkId` TEXT NOT NULL, " +
    97	                        "`bookKey` TEXT NOT NULL, `profileKey` TEXT NOT NULL, `title` TEXT, " +
    98	                        "`locatorJSON` TEXT NOT NULL, `createdAt` INTEGER NOT NULL, " +
    99	                        "`updatedAt` INTEGER NOT NULL, PRIMARY KEY(`bookmarkId`), " +
   100	                        "FOREIGN KEY(`bookKey`) REFERENCES `books`(`fingerprintKey`) " +
   101	                        "ON UPDATE NO ACTION ON DELETE CASCADE )",
   102	                )
   103	                db.execSQL("CREATE INDEX IF NOT EXISTS `index_bookmarks_bookKey` ON `bookmarks` (`bookKey`)")
   104	            }
   105	        }
   106	
   107	        /** v4 → v5: feature #127 — add the additive `collections` table (unique `nameKey` index) +
   108	         *  the `book_collection` many-to-many join (composite PK, both FKs ON DELETE CASCADE, a
   109	         *  `collectionId` index for the reverse lookup). No data transform. DDL matches Room's generated
   110	         *  v5 schema exactly (the migration test opens the real Room DB, whose structural PRAGMA
   111	         *  validation catches any drift). */
   112	        val MIGRATION_4_5: Migration = object : Migration(4, 5) {
   113	            override fun migrate(db: SupportSQLiteDatabase) {
   114	                db.execSQL(
   115	                    "CREATE TABLE IF NOT EXISTS `collections` (`id` TEXT NOT NULL, `name` TEXT NOT NULL, " +
   116	                        "`nameKey` TEXT NOT NULL, `createdAt` INTEGER NOT NULL, PRIMARY KEY(`id`))",
   117	                )
   118	                db.execSQL(
   119	                    "CREATE UNIQUE INDEX IF NOT EXISTS `index_collections_nameKey` ON `collections` (`nameKey`)",
   120	                )
   121	                db.execSQL(
   122	                    "CREATE TABLE IF NOT EXISTS `book_collection` (`bookKey` TEXT NOT NULL, " +
   123	                        "`collectionId` TEXT NOT NULL, PRIMARY KEY(`bookKey`, `collectionId`), " +
   124	                        "FOREIGN KEY(`bookKey`) REFERENCES `books`(`fingerprintKey`) " +
   125	                        "ON UPDATE NO ACTION ON DELETE CASCADE , " +
   126	                        "FOREIGN KEY(`collectionId`) REFERENCES `collections`(`id`) " +
   127	                        "ON UPDATE NO ACTION ON DELETE CASCADE )",
   128	                )
   129	                db.execSQL(
   130	                    "CREATE INDEX IF NOT EXISTS `index_book_collection_collectionId` " +
   131	                        "ON `book_collection` (`collectionId`)",
   132	                )
   133	            }
   134	        }
   135	
   136	        /** v5 → v6: feature #128 — add the nullable `author` column to `books` (library search).
   137	         *  Purely additive; migrated rows read `author = null` until a backfill or restore sets it. */
   138	        val MIGRATION_5_6: Migration = object : Migration(5, 6) {
   139	            override fun migrate(db: SupportSQLiteDatabase) {
   140	                db.execSQL("ALTER TABLE books ADD COLUMN author TEXT")
   141	            }
   142	        }
   143	
   144	        /** v6 → v7: feature #128 WI-4 — add the cross-book search index (all in the one `vreader.db`):
   145	         *  `search_sections` (+ bookKey index + FK→books CASCADE), its FTS4/unicode61 content-table
   146	         *  shadow `search_sections_fts`, `search_index_state` (+ FK→books CASCADE), and the transient
   147	         *  `search_sections_staging` buffer (+ bookKey index + FK→books CASCADE). The migration ships
   148	         *  the base + FTS VIRTUAL tables only; Room recreates the FTS content-table sync triggers when
   149	         *  it opens the DB. DDL matches Room's generated v7 schema exactly (the migration test opens the
   150	         *  real Room DB, whose structural PRAGMA validation catches any drift). No data transform. */
   151	        val MIGRATION_6_7: Migration = object : Migration(6, 7) {
   152	            override fun migrate(db: SupportSQLiteDatabase) {
   153	                db.execSQL(
   154	                    "CREATE TABLE IF NOT EXISTS `search_sections` (`id` INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL, " +
   155	                        "`bookKey` TEXT NOT NULL, `sectionIndex` INTEGER NOT NULL, `chunkOrdinal` INTEGER NOT NULL, " +
   156	                        "`sectionTitle` TEXT, `text` TEXT NOT NULL, `indexedText` TEXT NOT NULL, " +
   157	                        "FOREIGN KEY(`bookKey`) REFERENCES `books`(`fingerprintKey`) " +
   158	                        "ON UPDATE NO ACTION ON DELETE CASCADE )",
   159	                )
   160	                db.execSQL("CREATE INDEX IF NOT EXISTS `index_search_sections_bookKey` ON `search_sections` (`bookKey`)")
   161	                db.execSQL(
   162	                    "CREATE VIRTUAL TABLE IF NOT EXISTS `search_sections_fts` USING FTS4(" +
   163	                        "`indexedText` TEXT NOT NULL, tokenize=unicode61, content=`search_sections`)",
   164	                )
   165	                db.execSQL(
   166	                    "CREATE TABLE IF NOT EXISTS `search_index_state` (`bookKey` TEXT NOT NULL, " +
   167	                        "`indexerVersion` INTEGER NOT NULL, `indexedAt` INTEGER NOT NULL, `status` TEXT NOT NULL, " +
   168	                        "PRIMARY KEY(`bookKey`), FOREIGN KEY(`bookKey`) REFERENCES `books`(`fingerprintKey`) " +
   169	                        "ON UPDATE NO ACTION ON DELETE CASCADE )",
   170	                )
   171	                db.execSQL(
   172	                    "CREATE TABLE IF NOT EXISTS `search_sections_staging` (`id` INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL, " +
   173	                        "`bookKey` TEXT NOT NULL, `sectionIndex` INTEGER NOT NULL, `chunkOrdinal` INTEGER NOT NULL, " +
   174	                        "`sectionTitle` TEXT, `text` TEXT NOT NULL, `indexedText` TEXT NOT NULL, " +
   175	                        "FOREIGN KEY(`bookKey`) REFERENCES `books`(`fingerprintKey`) " +
   176	                        "ON UPDATE NO ACTION ON DELETE CASCADE )",
   177	                )
   178	                db.execSQL(
   179	                    "CREATE INDEX IF NOT EXISTS `index_search_sections_staging_bookKey` " +
   180	                        "ON `search_sections_staging` (`bookKey`)",
   181	                )
   182	            }
   183	        }
   184	
   185	        /** v7 → v8: feature #135 WI-3 — make re-bookmarking the same position idempotent by adding a
   186	         *  composite UNIQUE index on `bookmarks (bookKey, profileKey)` (the atomic-toggle enforcer,
   187	         *  mirroring the highlights `(profileKey, anchorKey)` dedupe precedent).
   188	         *
   189	         *  A pre-#135 create path (`upsertBookmark`, UUID-keyed) could have produced DUPLICATE rows at
   190	         *  the same `(bookKey, profileKey)`; `CREATE UNIQUE INDEX` would FAIL on such a duplicate. So
   191	         *  the migration first DEDUPES — deleting every duplicate LOSER, keeping a DETERMINISTIC winner
   192	         *  per `(bookKey, profileKey)`: the row with the greatest `updatedAt`, tie-broken by the
   193	         *  greatest `createdAt`, then the LOWEST `bookmarkId` (a total, stable order). This is a
   194	         *  targeted dedupe — a non-duplicate row (unique `(bookKey, profileKey)`) is never deleted, and
   195	         *  no other table is touched. THEN the unique index is created, matching Room's generated name
   196	         *  + columns (`index_bookmarks_bookKey_profileKey` on `(bookKey, profileKey)`) exactly, so
   197	         *  Room's structural PRAGMA validation passes. DDL is idempotent (`IF NOT EXISTS`). */
   198	        val MIGRATION_7_8: Migration = object : Migration(7, 8) {
   199	            override fun migrate(db: SupportSQLiteDatabase) {
   200	                // 1) Dedupe: delete every row that is NOT the deterministic winner within its
   201	                //    (bookKey, profileKey) group. The winner is the row whose (updatedAt, createdAt,
   202	                //    -rowid-preference-on-bookmarkId) is greatest — expressed as: a row is a loser iff
   203	                //    another row in the same group ranks strictly higher by (updatedAt DESC,
   204	                //    createdAt DESC, bookmarkId ASC).
   205	                db.execSQL(
   206	                    "DELETE FROM `bookmarks` WHERE `bookmarkId` IN (" +
   207	                        "SELECT b.`bookmarkId` FROM `bookmarks` b JOIN `bookmarks` w " +
   208	                        "ON b.`bookKey` = w.`bookKey` AND b.`profileKey` = w.`profileKey` " +
   209	                        "AND b.`bookmarkId` <> w.`bookmarkId` " +
   210	                        "WHERE (w.`updatedAt` > b.`updatedAt`) " +
   211	                        "OR (w.`updatedAt` = b.`updatedAt` AND w.`createdAt` > b.`createdAt`) " +
   212	                        "OR (w.`updatedAt` = b.`updatedAt` AND w.`createdAt` = b.`createdAt` " +
   213	                        "AND w.`bookmarkId` < b.`bookmarkId`))",
   214	                )
   215	                // 2) Now that each (bookKey, profileKey) is unique, create the unique index.
   216	                db.execSQL(
   217	                    "CREATE UNIQUE INDEX IF NOT EXISTS `index_bookmarks_bookKey_profileKey` " +
   218	                        "ON `bookmarks` (`bookKey`, `profileKey`)",
   219	                )
   220	            }
   221	        }
   222	
   223	        /** All registered migrations, oldest first. Append future Migration(n,n+1) here. */
   224	        val ALL_MIGRATIONS: Array<Migration> =
   225	            arrayOf(
   226	                MIGRATION_1_2, MIGRATION_2_3, MIGRATION_3_4, MIGRATION_4_5,
   227	                MIGRATION_5_6, MIGRATION_6_7, MIGRATION_7_8,
   228	            )
   229	
   230	        /** The production on-disk database (app-private storage). */
   231	        fun build(context: Context): VReaderDatabase =
   232	            Room.databaseBuilder(context.applicationContext, VReaderDatabase::class.java, DB_NAME)
   233	                .addMigrations(*ALL_MIGRATIONS)
   234	                .build()
   235	    }
   236	}
     1	// Purpose: Room DAOs — the Android analog of the iOS PersistenceActor CRUD
     2	// extensions (feature #106 WI-3). DAOs expose suspend writes + Flow reads; Room
     3	// serializes access off the main thread. Views never touch a DAO directly — the
     4	// repository (DTOs) is the boundary (rule 50 §2: never return @Model/entity types
     5	// across the layer).
     6	package com.vreader.app.data
     7	
     8	import androidx.room.Dao
     9	import androidx.room.Insert
    10	import androidx.room.OnConflictStrategy
    11	import androidx.room.Query
    12	import androidx.room.Transaction
    13	import androidx.room.Upsert
    14	import kotlinx.coroutines.flow.Flow
    15	
    16	@Dao
    17	interface BookDao {
    18	    // @Upsert (insert-or-UPDATE), NOT @Insert(REPLACE). REPLACE is delete-then-insert
    19	    // in SQLite, which would fire reading_positions' ON DELETE CASCADE and silently
    20	    // wipe a book's saved position on every re-import (Gate-4 Critical). @Upsert
    21	    // updates in place, preserving the child row.
    22	    //
    23	    // NOTE: the SAF import path does NOT use this whole-row @Upsert — it uses
    24	    // [upsertPreservingAuthor] below, so a duplicate import can't null-clobber a
    25	    // backfilled `author` (feature #128 WI-1 Gate-2 Critical). This whole-row upsert is
    26	    // kept for callers (e.g. the restore path pre-#128) that intentionally write every
    27	    // column, and is exercised by the reUpsert-preserves-position regression.
    28	    @Upsert
    29	    suspend fun upsert(book: BookEntity)
    30	
    31	    @Query("SELECT * FROM books ORDER BY addedAt DESC")
    32	    fun observeAll(): Flow<List<BookEntity>>
    33	
    34	    @Query("SELECT * FROM books WHERE fingerprintKey = :key")
    35	    suspend fun find(key: String): BookEntity?
    36	
    37	    // feature #116 WI-3 — one-shot snapshot for the backup collector (not the observable Flow).
    38	    // Ordered by fingerprintKey (NOT the library-display addedAt) so a repeat backup of unchanged
    39	    // content yields a byte-stable manifest (matches the iOS projection ordering).
    40	    @Query("SELECT * FROM books ORDER BY fingerprintKey")
    41	    suspend fun getAll(): List<BookEntity>
    42	
    43	    @Query("DELETE FROM books WHERE fingerprintKey = :key")
    44	    suspend fun delete(key: String)
    45	
    15	 * (`DocumentFingerprint.canonicalKey`). `localFilePath`/`sourceUri` are nullable
    16	 * until WI-4 wires SAF import → app-private-storage copy. `lastOpenedAt` is the
    17	 * v2 schema addition (recents) — null until first open. `author` is the v6 addition
    18	 * (feature #128 library search) — nullable, set by an author backfill or a restore,
    19	 * NEVER by the SAF import path (a duplicate import must not null-clobber it: the import
    20	 * path goes through [BookDao.upsertPreservingAuthor], not the whole-row `@Upsert`).
    21	 */
    22	@Entity(tableName = "books")
    23	data class BookEntity(
    24	    @PrimaryKey val fingerprintKey: String,
    25	    val title: String,
    26	    val originalFormat: String,   // BookFormat raw value (epub/pdf/txt/md/azw3)
    27	    val contentSHA256: String,
    28	    val fileByteCount: Long,
    29	    val localFilePath: String?,   // app-private storage path (set at import, WI-4)
    30	    val sourceUri: String?,       // SAF source URI metadata (WI-4)
    31	    val addedAt: Long,            // epoch millis
    32	    val lastOpenedAt: Long?,      // v2 addition — epoch millis of last open, or null
    33	    val author: String? = null,   // v6 addition (feature #128) — nullable; tail default so no positional site breaks
    34	)
    35	

codex
The live TXT model confirms the premise, but the render mapping needs closer scrutiny: the current host renders each chunk as one `Text`, so “translation after the segment portion” implies splitting/reconstructing the source presentation while preserving selection, highlights, markdown mapping, and offsets. I’m checking whether the plan’s range ownership rule is precise enough to prevent boundary duplicates/drops and whether its tests cover those host invariants.
exec
/bin/zsh -lc "rg -n \"class AiProviderStore|data class AiProviderSnapshot|fun snapshot|suspend fun snapshot|fun apiKey|suspend fun apiKey|object AiProviderFactory|class AiProviderFactory|fun create\\(|interface AiClient|fun chat|data class AiRequest|sealed.*AiError|Auth401|RateLimited429|InsecureUrl\" android/app/src/main/kotlin --glob '*.kt' && rg --files android/app/src/main/kotlin | rg '/ai/|Ai'" in /Users/ll/workspace/vreader
 succeeded in 0ms:
android/app/src/main/kotlin/com/vreader/app/tts/AndroidTtsEngine.kt:164:    override suspend fun create(enginePackage: String?): TtsEngine = AndroidTtsEngine(appContext, enginePackage)
android/app/src/main/kotlin/com/vreader/app/tts/TtsEngine.kt:45:    suspend fun create(enginePackage: String? = null): TtsEngine
android/app/src/main/kotlin/com/vreader/app/ai/AiProviderFactory.kt:10:object AiProviderFactory {
android/app/src/main/kotlin/com/vreader/app/ai/AiProviderFactory.kt:11:    fun create(profile: AiProviderProfile, apiKey: String, dispatcher: CoroutineDispatcher = Dispatchers.IO): AiClient {
android/app/src/main/kotlin/com/vreader/app/ai/AiProviderStore.kt:34:data class AiProviderSnapshot(val profiles: List<AiProviderProfile>, val activeId: String?) {
android/app/src/main/kotlin/com/vreader/app/ai/AiProviderStore.kt:41:class AiProviderStore(
android/app/src/main/kotlin/com/vreader/app/ai/AiProviderStore.kt:47:    suspend fun snapshot(): AiProviderSnapshot = read(dataStore.data.first()).toSnapshot()
android/app/src/main/kotlin/com/vreader/app/ai/AiProviderStore.kt:108:    fun apiKey(profile: AiProviderProfile): String = cipher.decrypt(profile.encryptedApiKey)
android/app/src/main/kotlin/com/vreader/app/ai/AiProviderStore.kt:112:    suspend fun apiKey(id: String): String? =
android/app/src/main/kotlin/com/vreader/app/ai/AiTypes.kt:12:data class AiRequest(
android/app/src/main/kotlin/com/vreader/app/ai/AiTypes.kt:27:sealed class AiError(message: String) : Exception(message) {
android/app/src/main/kotlin/com/vreader/app/ai/AiTypes.kt:28:    object Auth401 : AiError("authentication failed (401) — check the API key")
android/app/src/main/kotlin/com/vreader/app/ai/AiTypes.kt:29:    object RateLimited429 : AiError("rate limited (429) — try again shortly")
android/app/src/main/kotlin/com/vreader/app/ai/AiTypes.kt:36:    object InsecureUrl : AiError("the provider URL must be https:// (won't send the key over cleartext)")
android/app/src/main/kotlin/com/vreader/app/ai/AiClient.kt:25:interface AiClient {
android/app/src/main/kotlin/com/vreader/app/ai/AiClient.kt:29:    suspend fun chat(request: AiRequest): AiResponse
android/app/src/main/kotlin/com/vreader/app/ai/AiClient.kt:82:    final override suspend fun chat(request: AiRequest): AiResponse = withContext(dispatcher) {
android/app/src/main/kotlin/com/vreader/app/ai/AiClient.kt:144:            401, 403 -> AiError.Auth401
android/app/src/main/kotlin/com/vreader/app/ai/AiClient.kt:145:            429 -> AiError.RateLimited429
android/app/src/main/kotlin/com/vreader/app/ai/AiClient.kt:157:        throw AiError.InsecureUrl
android/app/src/main/kotlin/com/vreader/app/ai/AiProviderFactory.kt
android/app/src/main/kotlin/com/vreader/app/ai/AiProviderListScreen.kt
android/app/src/main/kotlin/com/vreader/app/ai/AiProviderStore.kt
android/app/src/main/kotlin/com/vreader/app/ai/AiTypes.kt
android/app/src/main/kotlin/com/vreader/app/ai/AiSettingsUiState.kt
android/app/src/main/kotlin/com/vreader/app/ai/AiMarkdownRenderer.kt
android/app/src/main/kotlin/com/vreader/app/ai/AiChatPanel.kt
android/app/src/main/kotlin/com/vreader/app/ai/AiChatViewModel.kt
android/app/src/main/kotlin/com/vreader/app/ai/AiChatUiState.kt
android/app/src/main/kotlin/com/vreader/app/ai/AiSettingsViewModel.kt
android/app/src/main/kotlin/com/vreader/app/ai/AnthropicProvider.kt
android/app/src/main/kotlin/com/vreader/app/ai/SseEventReader.kt
android/app/src/main/kotlin/com/vreader/app/ai/AiClient.kt
android/app/src/main/kotlin/com/vreader/app/ai/AiProviderKind.kt
android/app/src/main/kotlin/com/vreader/app/ai/OpenAiCompatibleProvider.kt
android/app/src/main/kotlin/com/vreader/app/ai/AiProviderEditSheet.kt

exec
/bin/zsh -lc "nl -ba android/app/src/main/kotlin/com/vreader/app/ai/AiProviderStore.kt | sed -n '1,125p' && nl -ba android/app/src/main/kotlin/com/vreader/app/ai/AiProviderFactory.kt && nl -ba android/app/src/main/kotlin/com/vreader/app/ai/AiClient.kt | sed -n '1,45p' && nl -ba android/app/src/main/kotlin/com/vreader/app/ai/AiTypes.kt | sed -n '1,48p' && rg -n \"AiProviderStore|AiProviderListScreen|AiSettings\" android/app/src/main/kotlin/com/vreader/app/VReaderApp.kt android/app/src/main/kotlin/com/vreader/app/MainActivity.kt android/app/src/main/kotlin --glob '*.kt'" in /Users/ll/workspace/vreader
 succeeded in 0ms:
     1	// Purpose: feature #118 WI-1 (#110 Phase 3) — persists saved AI provider profiles + the active
     2	// selection. Profile metadata (name/kind/baseUrl/model/temperature/maxTokens) lives in DataStore
     3	// as a JSON list; the API key is kept ONLY as a SecretCipher token (the #116 KeystoreSecretCipher).
     4	// Reuses the #116 WebDavServerStore DataStore+SecretCipher credential pattern, adding an active-id
     5	// and a request-start `snapshot()` (a chat/test reads one consistent profile, not live mid-request
     6	// store reads). The key + auth headers are NEVER logged.
     7	package com.vreader.app.ai
     8	
     9	import androidx.datastore.core.DataStore
    10	import androidx.datastore.preferences.core.Preferences
    11	import androidx.datastore.preferences.core.edit
    12	import androidx.datastore.preferences.core.stringPreferencesKey
    13	import com.vreader.app.backup.net.SecretCipher
    14	import kotlinx.coroutines.flow.Flow
    15	import kotlinx.coroutines.flow.first
    16	import kotlinx.coroutines.flow.map
    17	import kotlinx.serialization.Serializable
    18	import kotlinx.serialization.json.Json
    19	
    20	/** A saved AI provider. `encryptedApiKey` is a [SecretCipher] token, never plaintext. */
    21	@Serializable
    22	data class AiProviderProfile(
    23	    val id: String,
    24	    val name: String,
    25	    val kind: AiProviderKind,
    26	    val baseUrl: String,
    27	    val model: String,
    28	    val temperature: Double = 0.7,
    29	    val maxTokens: Int = 2048,
    30	    val encryptedApiKey: String,
    31	)
    32	
    33	/** A consistent point-in-time view: the profiles + which is active. */
    34	data class AiProviderSnapshot(val profiles: List<AiProviderProfile>, val activeId: String?) {
    35	    val active: AiProviderProfile? get() = profiles.firstOrNull { it.id == activeId }
    36	}
    37	
    38	@Serializable
    39	private data class AiStoreState(val profiles: List<AiProviderProfile> = emptyList(), val activeId: String? = null)
    40	
    41	class AiProviderStore(
    42	    private val dataStore: DataStore<Preferences>,
    43	    private val cipher: SecretCipher,
    44	    private val json: Json = Json { ignoreUnknownKeys = true; encodeDefaults = true },
    45	) {
    46	    /** One consistent profiles + active-id view (read once at request start). */
    47	    suspend fun snapshot(): AiProviderSnapshot = read(dataStore.data.first()).toSnapshot()
    48	
    49	    fun observe(): Flow<AiProviderSnapshot> = dataStore.data.map { read(it).toSnapshot() }
    50	
    51	    suspend fun list(): List<AiProviderProfile> = snapshot().profiles
    52	
    53	    suspend fun activeProfile(): AiProviderProfile? = snapshot().active
    54	
    55	    /**
    56	     * Insert/update a profile by [id]. [apiKey] is the PLAINTEXT to encrypt; pass null on an edit
    57	     * that leaves the key unchanged (the existing ciphertext is kept). A brand-new id REQUIRES a
    58	     * key. The first profile added becomes active. Returns the saved profile (key encrypted).
    59	     */
    60	    suspend fun upsert(
    61	        id: String,
    62	        name: String,
    63	        kind: AiProviderKind,
    64	        baseUrl: String,
    65	        model: String,
    66	        temperature: Double,
    67	        maxTokens: Int,
    68	        apiKey: String?,
    69	    ): AiProviderProfile {
    70	        lateinit var saved: AiProviderProfile
    71	        dataStore.edit { prefs ->
    72	            val cur = read(prefs)
    73	            val existing = cur.profiles.firstOrNull { it.id == id }
    74	            val encrypted = when {
    75	                apiKey != null -> cipher.encrypt(apiKey)
    76	                existing != null -> existing.encryptedApiKey  // unchanged on edit
    77	                else -> throw IllegalArgumentException("a new provider ($id) requires an API key")
    78	            }
    79	            saved = AiProviderProfile(id, name, kind, baseUrl, model, temperature, maxTokens, encrypted)
    80	            val next = cur.profiles.filterNot { it.id == id } + saved
    81	            val activeId = cur.activeId ?: id  // first provider becomes active
    82	            prefs[KEY] = json.encodeToString(AiStoreState(next, activeId))
    83	        }
    84	        return saved
    85	    }
    86	
    87	    /** Remove a profile. If it was active, the active selection moves to the first remaining (or null). */
    88	    suspend fun delete(id: String) {
    89	        dataStore.edit { prefs ->
    90	            val cur = read(prefs)
    91	            val next = cur.profiles.filterNot { it.id == id }
    92	            val activeId = if (cur.activeId == id) next.firstOrNull()?.id else cur.activeId
    93	            prefs[KEY] = json.encodeToString(AiStoreState(next, activeId))
    94	        }
    95	    }
    96	
    97	    /** Select the active provider (no-op if the id isn't present). */
    98	    suspend fun setActive(id: String) {
    99	        dataStore.edit { prefs ->
   100	            val cur = read(prefs)
   101	            if (cur.profiles.any { it.id == id }) prefs[KEY] = json.encodeToString(cur.copy(activeId = id))
   102	        }
   103	    }
   104	
   105	    /** Decrypt the key from a CAPTURED [profile] — snapshot-consistent (no live store read). The
   106	     *  chat/test request path uses THIS with a profile from a single [snapshot], so it can't pair
   107	     *  snapshot metadata with a concurrently-edited/deleted key. */
   108	    fun apiKey(profile: AiProviderProfile): String = cipher.decrypt(profile.encryptedApiKey)
   109	
   110	    /** The decrypted API key for [id] via a live read, or null if absent. Convenience for UI flows
   111	     *  that aren't mid-request; the request path should prefer [apiKey] (profile). */
   112	    suspend fun apiKey(id: String): String? =
   113	        list().firstOrNull { it.id == id }?.let { cipher.decrypt(it.encryptedApiKey) }
   114	
   115	    private fun read(prefs: Preferences): AiStoreState {
   116	        val raw = prefs[KEY] ?: return AiStoreState()
   117	        return runCatching { json.decodeFromString<AiStoreState>(raw) }.getOrDefault(AiStoreState())
   118	    }
   119	
   120	    private fun AiStoreState.toSnapshot() = AiProviderSnapshot(profiles, activeId)
   121	
   122	    companion object {
   123	        private val KEY = stringPreferencesKey("ai_providers_json")
   124	    }
   125	}
     1	// Purpose: feature #118 WI-2 (#110 Phase 3) — builds the right AiClient for a provider profile +
     2	// its decrypted API key. The chat/test request path resolves the active profile from a single
     3	// AiProviderStore.snapshot(), decrypts via apiKey(profile), and calls this — so the client is built
     4	// from one consistent snapshot, never live mid-request reads.
     5	package com.vreader.app.ai
     6	
     7	import kotlinx.coroutines.CoroutineDispatcher
     8	import kotlinx.coroutines.Dispatchers
     9	
    10	object AiProviderFactory {
    11	    fun create(profile: AiProviderProfile, apiKey: String, dispatcher: CoroutineDispatcher = Dispatchers.IO): AiClient {
    12	        val base = profile.baseUrl.ifBlank { profile.kind.defaultBaseUrl }
    13	        val model = profile.model.ifBlank { profile.kind.defaultModel }
    14	        return when (profile.kind) {
    15	            AiProviderKind.openAiCompatible ->
    16	                OpenAiCompatibleProvider(base, apiKey, model, profile.temperature, profile.maxTokens, dispatcher)
    17	            AiProviderKind.anthropicNative ->
    18	                AnthropicProvider(base, apiKey, model, profile.temperature, profile.maxTokens, dispatcher)
    19	        }
    20	    }
    21	}
     1	// Purpose: feature #118 WI-2 (#110 Phase 3) — the AI client seam + the shared HTTP/SSE plumbing.
     2	// `AiClient` mirrors iOS `AIProvider` (stream + one-shot + test-connection); `BaseHttpAiClient` owns
     3	// the POST-over-HttpURLConnection transport (the #116/#117 precedent), the typed-error mapping, the
     4	// bounded streaming loop (cancellation disconnects), and a bounded one-shot read. The provider
     5	// concretes supply only the endpoint path, auth headers, request body, and the per-wire payload
     6	// parse (OpenAI vs Anthropic). The API key + auth headers are NEVER logged.
     7	package com.vreader.app.ai
     8	
     9	import kotlinx.coroutines.CoroutineDispatcher
    10	import kotlinx.coroutines.Dispatchers
    11	import kotlinx.coroutines.ensureActive
    12	import kotlinx.coroutines.flow.Flow
    13	import kotlinx.coroutines.flow.flow
    14	import kotlinx.coroutines.flow.flowOn
    15	import kotlinx.coroutines.job
    16	import kotlinx.coroutines.withContext
    17	import java.io.ByteArrayOutputStream
    18	import java.io.IOException
    19	import java.io.InputStream
    20	import java.net.HttpURLConnection
    21	import java.net.SocketTimeoutException
    22	import java.net.URL
    23	import kotlin.coroutines.coroutineContext
    24	
    25	interface AiClient {
    26	    /** Streamed assistant text deltas. Cancelling the collector disconnects the HTTP stream. */
    27	    fun streamChat(request: AiRequest): Flow<AiChunk>
    28	    /** One-shot (non-streamed) completion. */
    29	    suspend fun chat(request: AiRequest): AiResponse
    30	    /** A tiny ping → Ok / typed Fail (the editor's Connection section). */
    31	    suspend fun testConnection(): AiTestResult
    32	}
    33	
    34	/** A parsed SSE delta: incremental [text] (or null if this event carries none) + a [done] sentinel. */
    35	data class DeltaParse(val text: String?, val done: Boolean)
    36	
    37	abstract class BaseHttpAiClient(
    38	    protected val baseUrl: String,
    39	    protected val apiKey: String,
    40	    protected val model: String,
    41	    protected val temperature: Double,
    42	    protected val maxTokens: Int,
    43	    private val dispatcher: CoroutineDispatcher = Dispatchers.IO,
    44	    private val connectTimeoutMs: Int = 15_000,
    45	    private val readTimeoutMs: Int = 60_000,
     1	// Purpose: feature #118 WI-2 (#110 Phase 3) — the AI client value types + typed errors, mirroring
     2	// iOS AITypes (AIRequest/AIResponse/AIStreamChunk/AIError). Provider-neutral; the OpenAI vs
     3	// Anthropic wire differences live in the providers.
     4	package com.vreader.app.ai
     5	
     6	enum class AiRole { system, user, assistant }
     7	
     8	data class AiMessage(val role: AiRole, val content: String)
     9	
    10	/** A chat request. `system` is the system prompt (Anthropic carries it top-level; the OpenAI
    11	 *  provider prepends it as a system message). */
    12	data class AiRequest(
    13	    val model: String,
    14	    val messages: List<AiMessage>,
    15	    val temperature: Double,
    16	    val maxTokens: Int,
    17	    val system: String? = null,
    18	)
    19	
    20	/** One streamed delta (the incremental assistant text). */
    21	data class AiChunk(val deltaText: String)
    22	
    23	/** A one-shot (non-streamed) response. */
    24	data class AiResponse(val text: String)
    25	
    26	/** Typed AI failures (HTTP + transport + protocol). */
    27	sealed class AiError(message: String) : Exception(message) {
    28	    object Auth401 : AiError("authentication failed (401) — check the API key")
    29	    object RateLimited429 : AiError("rate limited (429) — try again shortly")
    30	    object Offline : AiError("the provider couldn't be reached")
    31	    object Timeout : AiError("the provider took too long to respond")
    32	    class Http(val code: Int) : AiError("HTTP $code from the provider")
    33	    class Decode(detail: String) : AiError("couldn't parse the provider response: $detail")
    34	    class Stream(detail: String) : AiError("the stream ended abnormally: $detail")
    35	    /** Refused to send the API key over cleartext http:// to a non-local host. */
    36	    object InsecureUrl : AiError("the provider URL must be https:// (won't send the key over cleartext)")
    37	    class Config(detail: String) : AiError("provider misconfigured: $detail")
    38	}
    39	
    40	/** Test-connection outcome (the editor's Connection section). */
    41	sealed interface AiTestResult {
    42	    object Ok : AiTestResult
    43	    data class Fail(val error: AiError, val message: String) : AiTestResult
    44	}
android/app/src/main/kotlin/com/vreader/app/VReaderApp.kt:65:    // AiProviderStore precedent), global (not per-book), process-singleton so a settings change
android/app/src/main/kotlin/com/vreader/app/ai/AiProviderFactory.kt:3:// AiProviderStore.snapshot(), decrypts via apiKey(profile), and calls this — so the client is built
android/app/src/main/kotlin/com/vreader/app/ai/AiProviderListScreen.kt:46:fun AiProviderListScreen(
android/app/src/main/kotlin/com/vreader/app/ai/AiProviderStore.kt:41:class AiProviderStore(
android/app/src/main/kotlin/com/vreader/app/opds/ui/OpdsSourcesViewModel.kt:4:// #118 AiSettingsViewModel test path), and saves/deletes. The password is never logged.
android/app/src/main/kotlin/com/vreader/app/opds/ui/OpdsSourcesViewModel.kt:50:    // closed form). Mirrors AiSettingsViewModel.testGen.
android/app/src/main/kotlin/com/vreader/app/ai/AiChatViewModel.kt:2:// ACTIVE provider from one AiProviderStore snapshot, streams a chat answer (accumulating deltas),
android/app/src/main/kotlin/com/vreader/app/ai/AiChatViewModel.kt:24:    private val store: AiProviderStore,
android/app/src/main/kotlin/com/vreader/app/ai/AiSettingsViewModel.kt:2:// AiProviderStore for the list, owns the editor form state, runs Test Connection against the LIVE
android/app/src/main/kotlin/com/vreader/app/ai/AiSettingsViewModel.kt:20:class AiSettingsViewModel(
android/app/src/main/kotlin/com/vreader/app/ai/AiSettingsViewModel.kt:21:    private val store: AiProviderStore,
android/app/src/main/kotlin/com/vreader/app/VReaderApp.kt:65:    // AiProviderStore precedent), global (not per-book), process-singleton so a settings change
android/app/src/main/kotlin/com/vreader/app/reader/settings/ReaderSettingsStore.kt:2:// DataStore (the OpdsSourceStore / AiProviderStore JSON-in-Preferences precedent). Global, device-

exec
/bin/zsh -lc "rg -n \"translatePreSegmented|cachedTranslation\\(|translatedSegmentsDirect|cachedSegmentsDirect|sentenceRanges\\(|struct TranslationChunkContract|enum TranslationChunkContract|class TranslationChunkContract|struct ChapterTranslationChunker|enum ChapterTranslationChunker|subSplit\\(\" vreader/Services/AI --glob '*.swift' && rg --files vreader/Services/AI" in /Users/ll/workspace/vreader
 succeeded in 0ms:
vreader/Services/AI/ChapterTranslationChunker.swift:21:enum ChapterTranslationChunker {
vreader/Services/AI/ChapterTranslationChunker.swift:85:    static func subSplit(_ text: String, maxChars: Int) -> [String] {
vreader/Services/AI/ChapterTranslationPrefetcher.swift:141:        if let cached = await translationService.cachedTranslation(
vreader/Services/AI/ChapterTranslationPrefetcher.swift:196:    /// then `ChapterTranslationService.translatePreSegmented` (no disk cache).
vreader/Services/AI/ChapterTranslationPrefetcher.swift:197:    func translatedSegmentsDirect(
vreader/Services/AI/ChapterTranslationPrefetcher.swift:220:            let out = try await translationService.translatePreSegmented(
vreader/Services/AI/ChapterTranslationPrefetcher.swift:231:            Self.log.error("prefetchDirect translatePreSegmented failed: \(String(describing: error), privacy: .private)")
vreader/Services/AI/ChapterTranslationPrefetcher.swift:239:    func cachedSegmentsDirect(
vreader/Services/AI/ChapterTranslationPrefetcher.swift:244:        await translationService.cachedTranslation(
vreader/Services/AI/TranslationChunkContract.swift:24:enum TranslationChunkContract {
vreader/Services/AI/ChapterSegmenter.swift:73:    /// COUNT-PARITY CONTRACT: `sentenceRanges(in: s).count ==
vreader/Services/AI/ChapterSegmenter.swift:78:    static func sentenceRanges(in chapterText: String) -> [Range<Int>] {
vreader/Services/AI/ChapterPrefetching.swift:46:    func translatedSegmentsDirect(
vreader/Services/AI/ChapterPrefetching.swift:56:    func cachedSegmentsDirect(
vreader/Services/AI/ChapterPrefetching.swift:68:    func translatedSegmentsDirect(
vreader/Services/AI/ChapterPrefetching.swift:78:    func cachedSegmentsDirect(
vreader/Services/AI/ChapterTranslationService.swift:119:    func cachedTranslation(
vreader/Services/AI/ChapterTranslationService.swift:148:    func cachedTranslation(
vreader/Services/AI/ChapterTranslationService.swift:321:    /// `cachedTranslation(expectedSegmentCount:)` with zero provider calls.
vreader/Services/AI/ChapterTranslationService.swift:327:    func translatePreSegmented(
vreader/Services/AI/ChapterTranslationService.swift:412:            let pieces = ChapterTranslationChunker.subSplit(
vreader/Services/AI/AIProvider.swift
vreader/Services/AI/AgenticChatDriver.swift
vreader/Services/AI/MockAIProvider.swift
vreader/Services/AI/AITypes.swift
vreader/Services/AI/ChapterPrefetching.swift
vreader/Services/AI/AIToolRegistry.swift
vreader/Services/AI/ProviderKind.swift
vreader/Services/AI/ChatContextScope.swift
vreader/Services/AI/ProviderProfileStore.swift
vreader/Services/AI/ProviderConfigResolving.swift
vreader/Services/AI/ChapterTranslationPrefetcher.swift
vreader/Services/AI/UTF16Clamp.swift
vreader/Services/AI/AnthropicProvider+ToolUse.swift
vreader/Services/AI/SummaryScope.swift
vreader/Services/AI/InterruptedTranslationJobStore.swift
vreader/Services/AI/ChapterTranslationChunker.swift
vreader/Services/AI/AIConsentManager.swift
vreader/Services/AI/TranslationChunkContract.swift
vreader/Services/AI/WholeBookReducer.swift
vreader/Services/AI/ProviderProfileMigrator.swift
vreader/Services/AI/ProviderProfile.swift
vreader/Services/AI/ChatAnnotationContext.swift
vreader/Services/AI/SummaryScopeResolver.swift
vreader/Services/AI/ChapterBounds.swift
vreader/Services/AI/OpenAICompatibleProvider+ToolUse.swift
vreader/Services/AI/AIContextExtractor.swift
vreader/Services/AI/BookTranslationProgress.swift
vreader/Services/AI/AIResponseCache.swift
vreader/Services/AI/ChatAnnotationCache.swift
vreader/Services/AI/ChatContextScope+Menu.swift
vreader/Services/AI/ChatSourceSelection.swift
vreader/Services/AI/AIConfigurationStore.swift
vreader/Services/AI/AIContextExtracting.swift
vreader/Services/AI/BookTranslationCoordinator.swift
vreader/Services/AI/ChatCitation.swift
vreader/Services/AI/AIError.swift
vreader/Services/AI/ResolvedAIProviderConfig.swift
vreader/Services/AI/AIService.swift
vreader/Services/AI/ChatCitationFactory.swift
vreader/Services/AI/UTF16TextSlicer.swift
vreader/Services/AI/AIConfiguration.swift
vreader/Services/AI/AITool.swift
vreader/Services/AI/ChapterSegmenter.swift
vreader/Services/AI/BilingualAIReadiness.swift
vreader/Services/AI/TranslationStyle.swift
vreader/Services/AI/Tools/GetBookContentTool.swift
vreader/Services/AI/Tools/LibraryBookSearchGate.swift
vreader/Services/AI/Tools/SearchCurrentBookTool.swift
vreader/Services/AI/Tools/AgenticToolRegistryBuilder.swift
vreader/Services/AI/Tools/ListLibraryTool.swift
vreader/Services/AI/Tools/ToolResultText.swift
vreader/Services/AI/Tools/LibrarySearchBackendAdapter.swift
vreader/Services/AI/Tools/SearchOtherBooksTool.swift
vreader/Services/AI/Tools/ClosedBookTextExtractor.swift
vreader/Services/AI/Tools/BookContentProviderAdapter.swift
vreader/Services/AI/Tools/GetBookContentGate.swift
vreader/Services/AI/KeychainService+ProviderProfile.swift
vreader/Services/AI/ChapterTranslationService.swift
vreader/Services/AI/ChatContextAssembler.swift
vreader/Services/AI/AnthropicProvider+Streaming.swift
vreader/Services/AI/AnthropicProvider.swift
vreader/Services/AI/AIChatAgenticSupport.swift
vreader/Services/AI/AIReaderAvailability.swift

exec
/bin/zsh -lc "nl -ba vreader/Services/AI/ChapterSegmenter.swift | sed -n '1,125p' && nl -ba vreader/Services/AI/TranslationChunkContract.swift | sed -n '1,150p' && nl -ba vreader/Services/AI/ChapterTranslationChunker.swift | sed -n '1,125p' && nl -ba vreader/Services/AI/ChapterTranslationService.swift | sed -n '105,180p;300,390p' && nl -ba vreader/Services/AI/ChapterTranslationPrefetcher.swift | sed -n '185,260p'" in /Users/ll/workspace/vreader
 succeeded in 0ms:
     1	// Purpose: Pure segmentation utility for feature #56 bilingual reading. Splits
     2	// a chapter's plain text into translation segments — either paragraphs or
     3	// sentences, selected by the book's `granularity` setting (design §2.2).
     4	//
     5	// Key decisions:
     6	// - Paragraph split is blank-line / block-boundary based: a single newline is
     7	//   a soft wrap (same paragraph), a blank line separates paragraphs.
     8	// - Sentence split uses `String.enumerateSubstrings(.bySentences)`, which is
     9	//   locale-aware and handles CJK fullwidth terminators (。！？) as well as
    10	//   Latin punctuation — no manual punctuation table.
    11	// - Every produced segment is whitespace-trimmed and empty segments dropped,
    12	//   so a translation request never carries a blank segment.
    13	//
    14	// @coordinates-with: ChapterTranslationChunker.swift,
    15	//   ChapterTranslationService.swift,
    16	//   dev-docs/plans/20260519-feature-56-bilingual-reading.md (WI-4)
    17	
    18	import Foundation
    19	
    20	/// Pure paragraph / sentence segmentation for chapter translation.
    21	enum ChapterSegmenter {
    22	
    23	    /// Splits chapter text into paragraphs. Paragraphs are separated by one or
    24	    /// more blank lines; a single line break inside a paragraph is a soft wrap
    25	    /// and does not split. Each paragraph is trimmed; empty ones are dropped.
    26	    static func paragraphs(in chapterText: String) -> [String] {
    27	        // Bug #344 (Gate-4 Medium): derive from the SAME range scanner the
    28	        // TXT/MD display side uses, so the blank-line definition can never
    29	        // diverge between the two sides of the 1:1 contract. The old regex
    30	        // split only on `\\n[ \\t]*\\n+`, while the display scanner treats ANY
    31	        // whitespace-only line (incl. U+3000 / U+00A0 — common in CJK
    32	        // files) as a separator — that divergence made the display side
    33	        // count MORE paragraphs than the translation side and paint
    34	        // source-only. Each scan range contains at least one
    35	        // non-whitespace character by construction, so trimming never
    36	        // yields an empty (and no filter is applied — a filter could
    37	        // re-introduce a count skew against the raw ranges).
    38	        let ns = chapterText as NSString
    39	        return BilingualParagraphRanges.scan(sourceText: chapterText).map {
    40	            ns.substring(with: NSRange(
    41	                location: $0.lowerBound, length: $0.upperBound - $0.lowerBound))
    42	                // Preserve the pre-#344 contract: soft-wrap line endings
    43	                // inside a paragraph normalize to \n (Gate-4 round 2 —
    44	                // translation prompts + cached rows carried \n, never \r\n).
    45	                .replacingOccurrences(of: "\r\n", with: "\n")
    46	                .replacingOccurrences(of: "\r", with: "\n")
    47	                .trimmingCharacters(in: .whitespacesAndNewlines)
    48	        }
    49	    }
    50	
    51	    /// Splits chapter text into sentences. CJK-aware via
    52	    /// `enumerateSubstrings(.bySentences)`. Each sentence is trimmed; empty
    53	    /// fragments are dropped.
    54	    static func sentences(in chapterText: String) -> [String] {
    55	        var result: [String] = []
    56	        let full = chapterText.startIndex..<chapterText.endIndex
    57	        chapterText.enumerateSubstrings(in: full, options: [.bySentences, .localized]) {
    58	            substring, _, _, _ in
    59	            guard let substring else { return }
    60	            let trimmed = substring.trimmingCharacters(in: .whitespacesAndNewlines)
    61	            if !trimmed.isEmpty {
    62	                result.append(trimmed)
    63	            }
    64	        }
    65	        // `.bySentences` on a fragment with no terminal punctuation still
    66	        // yields the fragment; only a fully-empty input yields nothing.
    67	        return result
    68	    }
    69	
    70	    /// Bug #344: UTF-16 half-open ranges of each sentence (trimmed bounds),
    71	    /// in source order — the display-side twin of `sentences(in:)`.
    72	    ///
    73	    /// COUNT-PARITY CONTRACT: `sentenceRanges(in: s).count ==
    74	    /// sentences(in: s).count` for every input. Both walk the same
    75	    /// `.bySentences` enumeration with the same trim + drop-empty rules, so
    76	    /// the TXT/MD sentence-interlinear renderer and the translation
    77	    /// segmentation pair 1:1 by construction (the #266/#343 contract).
    78	    static func sentenceRanges(in chapterText: String) -> [Range<Int>] {
    79	        var result: [Range<Int>] = []
    80	        let full = chapterText.startIndex..<chapterText.endIndex
    81	        let whitespace = CharacterSet.whitespacesAndNewlines
    82	        chapterText.enumerateSubstrings(in: full, options: [.bySentences, .localized]) {
    83	            substring, substringRange, _, _ in
    84	            guard let substring else { return }
    85	            let nsRange = NSRange(substringRange, in: chapterText)
    86	            // Shrink the range to the trimmed bounds so the interlinear row
    87	            // lands flush after the sentence's last visible character —
    88	            // mirroring `sentences(in:)`'s trim. Surrogate halves are never
    89	            // whitespace, so per-UTF-16-unit scanning is safe.
    90	            let units = Array(substring.utf16)
    91	            var lead = 0
    92	            while lead < units.count,
    93	                  let scalar = Unicode.Scalar(UInt32(units[lead])),
    94	                  whitespace.contains(scalar) {
    95	                lead += 1
    96	            }
    97	            var trail = 0
    98	            while trail < units.count - lead,
    99	                  let scalar = Unicode.Scalar(UInt32(units[units.count - 1 - trail])),
   100	                  whitespace.contains(scalar) {
   101	                trail += 1
   102	            }
   103	            let start = nsRange.location + lead
   104	            let end = nsRange.location + nsRange.length - trail
   105	            // Whitespace-only fragments trim to nothing — `sentences(in:)`
   106	            // drops them, so the range scanner must too (count parity).
   107	            guard start < end else { return }
   108	            result.append(start..<end)
   109	        }
   110	        return result
   111	    }
   112	
   113	}
     1	// Purpose: The strict JSON-array prompt + decode contract for feature #56
     2	// bilingual chapter translation. The model is instructed to return ONLY a JSON
     3	// array of N translated strings in source order; the decoder strictly
     4	// validates that the response is exactly that — N string elements.
     5	//
     6	// Key decisions:
     7	// - `AIRequest` has no API-level `response_format` field (verified), so the
     8	//   "return only a JSON array" contract is prompt-level + strict JSON decode
     9	//   (v4 Gate-2 finding F5 — rare-delimiter splitting was rejected because the
    10	//   model can reproduce any delimiter; a JSON-array schema is unambiguous).
    11	// - The decoder tolerates a leading/trailing ```json fence and surrounding
    12	//   whitespace (models add them), but is strict about the element count and
    13	//   that every element is a string — anything else throws so the caller
    14	//   (`ChapterTranslationService`) falls back to one-segment-per-request.
    15	// - `style` is folded into the prompt HERE and only here (Gate-2 round-2 N4).
    16	//
    17	// @coordinates-with: ChapterSegmenter.swift, ChapterTranslationChunker.swift,
    18	//   ChapterTranslationService.swift, TranslationStyle.swift,
    19	//   dev-docs/plans/20260519-feature-56-bilingual-reading.md (WI-4)
    20	
    21	import Foundation
    22	
    23	/// Builds the chunk translation prompt and strictly decodes the response.
    24	enum TranslationChunkContract {
    25	
    26	    /// A decode failure — surfaced so the service can fall back to a
    27	    /// one-segment-per-request retry.
    28	    enum DecodeError: Error, Equatable {
    29	        /// The response was not a JSON array of strings.
    30	        case notAStringArray
    31	        /// The array length did not equal the expected segment count.
    32	        case countMismatch(expected: Int, actual: Int)
    33	    }
    34	
    35	    /// Builds the `userPrompt` for one chunk of source segments. The model is
    36	    /// told to translate each segment into `targetLanguage` in the given
    37	    /// `style` and return ONLY a JSON array of exactly N strings, same order.
    38	    static func userPrompt(
    39	        segments: [String],
    40	        targetLanguage: String,
    41	        style: TranslationStyle
    42	    ) -> String {
    43	        let count = segments.count
    44	        let styleClause: String
    45	        switch style {
    46	        case .literal:
    47	            styleClause = "Use a LITERAL, word-for-word translation that stays "
    48	                + "close to the source sentence structure."
    49	        case .natural:
    50	            styleClause = "Use NATURAL, idiomatic \(targetLanguage) phrasing that "
    51	                + "reads fluently to a native speaker."
    52	        case .literary:
    53	            styleClause = "Use a LITERARY, polished translation with elevated, "
    54	                + "well-crafted \(targetLanguage) prose."
    55	        }
    56	
    57	        // Number the segments so the model's array ordering is unambiguous.
    58	        let numbered = segments.enumerated()
    59	            .map { "[\($0.offset)] \($0.element)" }
    60	            .joined(separator: "\n\n")
    61	
    62	        return """
    63	        Translate each of the following \(count) text segment(s) into \(targetLanguage).
    64	        \(styleClause)
    65	
    66	        Respond with ONLY a JSON array of exactly \(count) string(s) — the \
    67	        translation of each segment, in the same order. No commentary, no keys, \
    68	        no markdown — just the JSON array.
    69	
    70	        Source segments:
    71	        \(numbered)
    72	        """
    73	    }
    74	
    75	    /// Strictly decodes a model response into exactly `expectedCount`
    76	    /// translated strings. Tolerates a surrounding ```json fence and
    77	    /// whitespace; throws `DecodeError` on anything that is not a JSON array
    78	    /// of exactly that many string elements.
    79	    static func decode(_ raw: String, expectedCount: Int) throws -> [String] {
    80	        let cleaned = stripCodeFence(raw).trimmingCharacters(in: .whitespacesAndNewlines)
    81	        guard let data = cleaned.data(using: .utf8) else {
    82	            throw DecodeError.notAStringArray
    83	        }
    84	        let decoded: [String]
    85	        do {
    86	            decoded = try JSONDecoder().decode([String].self, from: data)
    87	        } catch {
    88	            // Decodes-but-not-as-[String] (object, number element, nested
    89	            // array, …) → not a string array.
    90	            throw DecodeError.notAStringArray
    91	        }
    92	        guard decoded.count == expectedCount else {
    93	            throw DecodeError.countMismatch(expected: expectedCount, actual: decoded.count)
    94	        }
    95	        return decoded
    96	    }
    97	
    98	    /// Removes a leading/trailing Markdown code fence (```json … ``` or ``` … ```).
    99	    ///
   100	    /// The closing fence is removed ONLY when the final non-whitespace line is
   101	    /// exactly ```` ``` ````. A bare ```` ``` ```` occurring *inside* the
   102	    /// payload (e.g. a JSON string element that literally contains backticks)
   103	    /// is left intact — searching backwards for any backtick run would
   104	    /// truncate such a legitimate payload (Gate-4 round-1 Medium).
   105	    private static func stripCodeFence(_ raw: String) -> String {
   106	        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
   107	        guard text.hasPrefix("```") else { return text }
   108	
   109	        var lines = text.components(separatedBy: "\n")
   110	        // Drop the opening fence line (``` or ```json). With no newline at all
   111	        // the input is just a lone fence — nothing to unwrap.
   112	        guard lines.count > 1 else { return text }
   113	        lines.removeFirst()
   114	
   115	        // Drop the closing fence only if the LAST non-blank line is exactly ```.
   116	        if let lastNonBlankIndex = lines.lastIndex(where: {
   117	            !$0.trimmingCharacters(in: .whitespaces).isEmpty
   118	        }), lines[lastNonBlankIndex].trimmingCharacters(in: .whitespaces) == "```" {
   119	            lines.removeSubrange(lastNonBlankIndex...)
   120	        }
   121	        return lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
   122	    }
   123	}
     1	// Purpose: Pure chunking utility for feature #56 bilingual reading. Groups
     2	// translation segment indices into chunks each under a provider character
     3	// budget, so a chapter that exceeds the provider's context window is sent as
     4	// several requests (edge case (a)).
     5	//
     6	// Key decisions:
     7	// - A segment is NEVER split across chunks — the response↔source mapping
     8	//   depends on a 1:1 segment correspondence within a chunk.
     9	// - One over-budget segment occupies its own chunk; recombination across
    10	//   chunks is the caller's job (`ChapterTranslationService`).
    11	// - The budget is a CHARACTER count (`String.count`), not a byte count —
    12	//   CJK text is multi-byte in UTF-8 but the provider window is token/char
    13	//   based and char count is the closer, format-agnostic proxy.
    14	//
    15	// @coordinates-with: ChapterSegmenter.swift, ChapterTranslationService.swift,
    16	//   dev-docs/plans/20260519-feature-56-bilingual-reading.md (WI-4)
    17	
    18	import Foundation
    19	
    20	/// Pure segment-boundary chunker for chapter translation.
    21	enum ChapterTranslationChunker {
    22	
    23	    /// Groups `segments` indices into chunks, each chunk's total character
    24	    /// count not exceeding `maxCharsPerChunk` — except a single segment that
    25	    /// is itself over budget, which occupies its own chunk.
    26	    ///
    27	    /// - Parameter maxCharsPerChunk: the per-chunk character budget; expected
    28	    ///   to be `> 0`. A non-positive budget is defensively coerced to `1`
    29	    ///   (every non-empty segment then gets its own chunk) so the function
    30	    ///   never divides by zero or loops — but callers should pass a real
    31	    ///   provider budget.
    32	    /// - Returns: an ordered array of index arrays. Flattening it yields
    33	    ///   `0..<segments.count` in order — every index appears exactly once.
    34	    static func chunk(segments: [String], maxCharsPerChunk: Int) -> [[Int]] {
    35	        guard !segments.isEmpty else { return [] }
    36	        let budget = max(1, maxCharsPerChunk)
    37	
    38	        var chunks: [[Int]] = []
    39	        var current: [Int] = []
    40	        var currentCount = 0
    41	
    42	        for (index, segment) in segments.enumerated() {
    43	            let segmentCount = segment.count
    44	
    45	            // An over-budget segment that would not fit even an empty chunk:
    46	            // flush the current chunk, then give the big segment its own.
    47	            if segmentCount > budget {
    48	                if !current.isEmpty {
    49	                    chunks.append(current)
    50	                    current = []
    51	                    currentCount = 0
    52	                }
    53	                chunks.append([index])
    54	                continue
    55	            }
    56	
    57	            // Adding this segment would overflow the current chunk → start one.
    58	            if !current.isEmpty && currentCount + segmentCount > budget {
    59	                chunks.append(current)
    60	                current = []
    61	                currentCount = 0
    62	            }
    63	
    64	            current.append(index)
    65	            currentCount += segmentCount
    66	        }
    67	
    68	        if !current.isEmpty {
    69	            chunks.append(current)
    70	        }
    71	        return chunks
    72	    }
    73	
    74	    /// Bug #330: sub-splits a SINGLE over-budget segment (an oversized paragraph)
    75	    /// into ordered pieces each `≤ maxChars`, so it can be translated piece by
    76	    /// piece instead of sent whole (which overflows the provider context window
    77	    /// → error). Splits on the last whitespace within each budget window when one
    78	    /// exists (keeps words/sentences intact for space-delimited languages); falls
    79	    /// back to a hard character boundary for a long unbroken run (e.g. CJK, which
    80	    /// has no inter-word whitespace). Grapheme-based (`Character`/`String.Index`),
    81	    /// so it never splits a surrogate pair or combining sequence.
    82	    ///
    83	    /// - Returns: `[text]` unchanged when `text.count ≤ maxChars`; otherwise the
    84	    ///   ordered pieces, which concatenate back to `text`.
    85	    static func subSplit(_ text: String, maxChars: Int) -> [String] {
    86	        let cap = max(1, maxChars)
    87	        guard text.count > cap else { return [text] }
    88	
    89	        var pieces: [String] = []
    90	        var remaining = Substring(text)
    91	        while remaining.count > cap {
    92	            let hardEnd = remaining.index(remaining.startIndex, offsetBy: cap)
    93	            // Back up to the last whitespace within the [start, hardEnd) window.
    94	            var breakAt = hardEnd
    95	            var i = hardEnd
    96	            while i > remaining.startIndex {
    97	                let prev = remaining.index(before: i)
    98	                if remaining[prev].isWhitespace { breakAt = i; break }
    99	                i = prev
   100	            }
   101	            // No whitespace in the window (one long token) → hard split at cap.
   102	            if breakAt == remaining.startIndex { breakAt = hardEnd }
   103	            pieces.append(String(remaining[remaining.startIndex..<breakAt]))
   104	            remaining = remaining[breakAt...]
   105	        }
   106	        if !remaining.isEmpty { pieces.append(String(remaining)) }
   107	        return pieces
   108	    }
   109	}
   105	    /// cached translation when a fresh (count-matching) row exists, else nil.
   106	    /// Lets the prefetcher serve an already-translated chapter BEFORE the
   107	    /// provider gate (`resolveProviderConfig`), so a cached chapter still renders
   108	    /// when AI is later disabled / unconfigured / key-less — previously the gate
   109	    /// threw first and the disk cache (inside `translate`) was never reached.
   110	    /// Bug #342: profile-agnostic — the canonical row is shared across provider
   111	    /// profiles, so no profile is needed for a read at all.
   112	    /// Bug #343 `acceptCountMismatch`: self-healing consumers (the EPUB hosts
   113	    /// with the divergence fallback) may opt in to receive a fresh row whose
   114	    /// stored count differs from the live re-derived segmenter count — the
   115	    /// row may carry the DOM-enumerate contract (written by the divergence
   116	    /// fallback), which pairs 1:1 at inject time; on a true source change the
   117	    /// fallback re-translates and replaces the row. Default-off callers keep
   118	    /// the strict staleness guard.
   119	    func cachedTranslation(
   120	        bookFingerprintKey: String,
   121	        unit: TranslationUnitID,
   122	        sourceText: String,
   123	        targetLanguage: String,
   124	        granularity: TranslationGranularity = .paragraph,
   125	        acceptCountMismatch: Bool = false
   126	    ) async -> ChapterTranslationResult? {
   127	        let lookupKey = ChapterTranslationRecord.lookupKey(
   128	            bookFingerprintKey: bookFingerprintKey,
   129	            unitStorageKey: unit.storageKey,
   130	            targetLanguage: targetLanguage,
   131	            promptVersion: promptVersion)
   132	        let segments: [String]
   133	        switch granularity {
   134	        case .paragraph: segments = ChapterSegmenter.paragraphs(in: sourceText)
   135	        case .sentence:  segments = ChapterSegmenter.sentences(in: sourceText)
   136	        }
   137	        guard let cached = await store.translation(forKey: lookupKey) else { return nil }
   138	        guard cached.sourceParagraphCount == segments.count || acceptCountMismatch else {
   139	            return nil
   140	        }
   141	        return ChapterTranslationResult(segments: cached.translatedSegments, fromCache: true)
   142	    }
   143	
   144	    /// Bug #343: the divergence-fallback restore — serves the canonical row
   145	    /// only when its STORED count matches the caller's own structure (the DOM
   146	    /// enumerate's block count), so blocks↔segments pair 1:1 by contract.
   147	    /// Needs no provider config and no source text.
   148	    func cachedTranslation(
   149	        bookFingerprintKey: String,
   150	        unit: TranslationUnitID,
   151	        expectedSegmentCount: Int,
   152	        targetLanguage: String
   153	    ) async -> ChapterTranslationResult? {
   154	        let lookupKey = ChapterTranslationRecord.lookupKey(
   155	            bookFingerprintKey: bookFingerprintKey,
   156	            unitStorageKey: unit.storageKey,
   157	            targetLanguage: targetLanguage,
   158	            promptVersion: promptVersion)
   159	        guard let cached = await store.translation(forKey: lookupKey),
   160	              cached.sourceParagraphCount == expectedSegmentCount else { return nil }
   161	        return ChapterTranslationResult(segments: cached.translatedSegments, fromCache: true)
   162	    }
   163	
   164	    /// Translates `unit`'s source text into `targetLanguage`. Serves from the
   165	    /// disk cache on a hit; on a miss segments → chunks → requests → decodes →
   166	    /// caches. Throws `ChapterTranslationError` on a provider failure or
   167	    /// cancellation.
   168	    func translate(
   169	        bookFingerprintKey: String,
   170	        unit: TranslationUnitID,
   171	        sourceText: String,
   172	        targetLanguage: String,
   173	        providerProfileID: UUID,
   174	        config: ResolvedAIProviderConfig,
   175	        style: TranslationStyle,
   176	        granularity: TranslationGranularity = .paragraph,
   177	        // Bug #341: when true, the cache READ is skipped — a fresh cached row
   178	        // must not short-circuit an explicit re-translate into a stale no-op.
   179	        // The cache WRITE still runs: the upsert replaces the row by lookupKey
   180	        // in place, which is the atomic swap (the old translation survives
   300	                    translatedSegments: translated,
   301	                    sourceParagraphCount: segments.count))
   302	            } catch {
   303	                log.error("Cache-write failed (translation still returned): \(String(describing: error), privacy: .public)")
   304	            }
   305	        }
   306	
   307	        return ChapterTranslationResult(segments: translated, fromCache: false)
   308	    }
   309	
   310	    /// Bug #268: translates a PRE-SEGMENTED list of source segments directly,
   311	    /// bypassing `ChapterSegmenter`. Used by the bilingual EPUB
   312	    /// divergence-fallback: when the DOM leaf-enumerate's block count
   313	    /// diverges from the plain-text paragraph segmentation (nested `<pre>` /
   314	    /// mixed-content `<blockquote>`), translating the enumerate's OWN block
   315	    /// `text[]` makes blocks↔segments 1:1 BY CONSTRUCTION — eliminating the
   316	    /// whole-chapter source-only fallback. The returned array is always the same
   317	    /// length as `segments`.
   318	    ///
   319	    /// Bug #343: the result IS cached now — the canonical row stores the
   320	    /// ENUMERATE's count as its contract, so a toggle/reopen restores via
   321	    /// `cachedTranslation(expectedSegmentCount:)` with zero provider calls.
   322	    /// (#268 originally skipped the cache to avoid thrashing the plain-text
   323	    /// path's differently-counted row; post-#342 there is ONE canonical row
   324	    /// and the divergence fallback is its self-healing writer of last resort.)
   325	    /// A partially-degraded result (Bug #330) is NOT cached, mirroring
   326	    /// `translate`.
   327	    func translatePreSegmented(
   328	        bookFingerprintKey: String,
   329	        unit: TranslationUnitID,
   330	        segments: [String],
   331	        targetLanguage: String,
   332	        providerProfileID: UUID,
   333	        config: ResolvedAIProviderConfig,
   334	        style: TranslationStyle
   335	    ) async throws -> [String] {
   336	        guard !segments.isEmpty else { return [] }
   337	        let chunks = ChapterTranslationChunker.chunk(
   338	            segments: segments, maxCharsPerChunk: maxCharsPerChunk)
   339	        var translated = [String](repeating: "", count: segments.count)
   340	        // Bug #330: same graceful degradation as `translate` — a single chunk's
   341	        // failure leaves its segments source-only; an all-chunks failure surfaces
   342	        // the error.
   343	        var anyChunkSucceeded = false
   344	        var lastChunkError: Error?
   345	        for chunk in chunks {
   346	            do {
   347	                try Task.checkCancellation()
   348	            } catch {
   349	                throw ChapterTranslationError.cancelled
   350	            }
   351	            let chunkSegments = chunk.map { segments[$0] }
   352	            do {
   353	                let chunkResult = try await translateChunk(
   354	                    chunkSegments, targetLanguage: targetLanguage, config: config, style: style)
   355	                for (offset, segmentIndex) in chunk.enumerated() {
   356	                    translated[segmentIndex] = chunkResult[offset]
   357	                }
   358	                anyChunkSucceeded = true
   359	            } catch is CancellationError {
   360	                throw ChapterTranslationError.cancelled
   361	            } catch ChapterTranslationError.cancelled {
   362	                // Bug #330 (Codex): typed cancellation from `send()` must abort,
   363	                // not degrade.
   364	                throw ChapterTranslationError.cancelled
   365	            } catch {
   366	                log.error("Pre-segmented chunk failed (segments \(chunk) source-only): \(String(describing: error), privacy: .public)")
   367	                lastChunkError = error
   368	            }
   369	        }
   370	        if !anyChunkSucceeded, let err = lastChunkError {
   371	            throw err
   372	        }
   373	
   374	        // Bug #343: cache the fully-successful result under the canonical key
   375	        // with the ENUMERATE's count as the stored contract. Mirrors
   376	        // `translate`: a partial degrade is never cached (Bug #330), and a
   377	        // store-write failure does not fail the translation (rule 50 §6).
   378	        if lastChunkError == nil {
   379	            do {
   380	                try await store.upsert(ChapterTranslationRecord(
   381	                    bookFingerprintKey: bookFingerprintKey,
   382	                    unitStorageKey: unit.storageKey,
   383	                    targetLanguage: targetLanguage,
   384	                    providerProfileID: providerProfileID,
   385	                    promptVersion: promptVersion,
   386	                    translatedSegments: translated,
   387	                    sourceParagraphCount: segments.count))
   388	            } catch {
   389	                log.error("Pre-segmented cache-write failed (translation still returned): \(String(describing: error), privacy: .public)")
   390	            }
   185	            )
   186	            return result.segments
   187	        } catch {
   188	            Self.log.error("prefetch translate call failed for unit \(String(describing: unit), privacy: .public): \(String(describing: error), privacy: .private)")
   189	            throw error
   190	        }
   191	    }
   192	
   193	    /// Bug #268: translate the render's OWN enumerated block texts directly
   194	    /// (1:1 by construction), bypassing the unit's plain-text segmentation.
   195	    /// Same provider snapshot + resolve + error contract as `translatedSegments`,
   196	    /// then `ChapterTranslationService.translatePreSegmented` (no disk cache).
   197	    func translatedSegmentsDirect(
   198	        for unit: TranslationUnitID,
   199	        sourceSegments: [String],
   200	        targetLanguage: String
   201	    ) async throws -> [String] {
   202	        guard !sourceSegments.isEmpty else { return [] }
   203	        Self.log.debug("prefetchDirect start: unit \(String(describing: unit), privacy: .public), \(sourceSegments.count) segments")
   204	        // Snapshot the active profile + resolve its config (mirrors
   205	        // `translatedSegments` so a provider switch can't straddle).
   206	        guard let activeProfile = await ProviderProfileStore.shared
   207	            .activeProfileSnapshot() else {
   208	            Self.log.error("prefetchDirect: no active provider profile")
   209	            throw ChapterTranslationError.providerFailed("no active provider profile")
   210	        }
   211	        let config: ResolvedAIProviderConfig
   212	        do {
   213	            config = try await aiService.resolveProviderConfig(
   214	                profileID: activeProfile.id, modelOverride: nil)
   215	        } catch {
   216	            Self.log.error("prefetchDirect resolveProviderConfig failed: \(String(describing: error), privacy: .private)")
   217	            throw ChapterTranslationError.providerFailed("provider config unavailable")
   218	        }
   219	        do {
   220	            let out = try await translationService.translatePreSegmented(
   221	                bookFingerprintKey: bookFingerprintKey,
   222	                unit: unit,
   223	                segments: sourceSegments,
   224	                targetLanguage: targetLanguage,
   225	                providerProfileID: activeProfile.id,
   226	                config: config,
   227	                style: style)
   228	            Self.log.debug("prefetchDirect ok: \(out.count) translated segments")
   229	            return out
   230	        } catch {
   231	            Self.log.error("prefetchDirect translatePreSegmented failed: \(String(describing: error), privacy: .private)")
   232	            throw error
   233	        }
   234	    }
   235	
   236	    /// Bug #343: cache-only restore for the divergence fallback — serves the
   237	    /// canonical row when its stored contract matches the enumerate's own
   238	    /// block count. Needs no provider config (the #306 pre-gate precedent).
   239	    func cachedSegmentsDirect(
   240	        for unit: TranslationUnitID,
   241	        expectedCount: Int,
   242	        targetLanguage: String
   243	    ) async -> [String]? {
   244	        await translationService.cachedTranslation(
   245	            bookFingerprintKey: bookFingerprintKey,
   246	            unit: unit,
   247	            expectedSegmentCount: expectedCount,
   248	            targetLanguage: targetLanguage)?.segments
   249	    }
   250	}

exec
/bin/zsh -lc "rg -n \"readium|r2-navigator|3\\.3\\.0\" android gradle build.gradle.kts settings.gradle.kts gradle/libs.versions.toml --glob '*.kts' --glob '*.toml' --glob '*.gradle' 2>/dev/null; find ~/.gradle/caches/modules-2/files-2.1 -path '*readium*3.3.0*' -type f 2>/dev/null | head -50; find ~/.gradle/caches/transforms-* -type f \\( -name '*EpubNavigatorFragment*' -o -name 'classes.jar' \\) 2>/dev/null | head -20" in /Users/ll/workspace/vreader
 succeeded in 216ms:
/Users/ll/.gradle/caches/modules-2/files-2.1/org.readium.kotlin-toolkit/readium-streamer/3.3.0/64eae89c549412891cd2305bdc589ce78ce596e2/readium-streamer-3.3.0.pom
/Users/ll/.gradle/caches/modules-2/files-2.1/org.readium.kotlin-toolkit/readium-streamer/3.3.0/295ee0de4c0d933009ef84a000683c5012b0b0ab/readium-streamer-3.3.0.module
/Users/ll/.gradle/caches/modules-2/files-2.1/org.readium.kotlin-toolkit/readium-streamer/3.3.0/cd0c6f07bb9f17c4718645b421f80a7c8caeb29e/readium-streamer-3.3.0.aar
/Users/ll/.gradle/caches/modules-2/files-2.1/org.readium.kotlin-toolkit/readium-navigator/3.3.0/fa9ca42cd2606f432a5843df9cc4953fe808d696/readium-navigator-3.3.0.module
/Users/ll/.gradle/caches/modules-2/files-2.1/org.readium.kotlin-toolkit/readium-navigator/3.3.0/ec205146a3401ca43792b37bfb4b9b2d51fa6a35/readium-navigator-3.3.0.pom
/Users/ll/.gradle/caches/modules-2/files-2.1/org.readium.kotlin-toolkit/readium-navigator/3.3.0/162dd7fdee9e61a10441e5262792ec0d76b6011e/readium-navigator-3.3.0.aar
/Users/ll/.gradle/caches/modules-2/files-2.1/org.readium.kotlin-toolkit/readium-shared/3.3.0/a7670e6bf03624f06db1582204f2ef3bd27e092c/readium-shared-3.3.0.module
/Users/ll/.gradle/caches/modules-2/files-2.1/org.readium.kotlin-toolkit/readium-shared/3.3.0/18cb1433ca2d1d0c99e437a0780593e167367c5/readium-shared-3.3.0.aar
/Users/ll/.gradle/caches/modules-2/files-2.1/org.readium.kotlin-toolkit/readium-shared/3.3.0/b6c9f5890525ae8935421a147a8f315e86f9b57f/readium-shared-3.3.0.pom
zsh:1: no matches found: /Users/ll/.gradle/caches/transforms-*

exec
/bin/zsh -lc 'find /Users/ll/.gradle/caches -type f -name classes.jar 2>/dev/null | while IFS= read -r f; do if jar tf "$f" 2>/dev/null | rg -q '"'org/readium/r2/navigator/epub/EpubNavigatorFragment.class'; then echo \""'$f"; fi; done' in /Users/ll/workspace/vreader
 succeeded in 1742ms:
exec
/bin/zsh -lc 'AAR=/Users/ll/.gradle/caches/modules-2/files-2.1/org.readium.kotlin-toolkit/readium-navigator/3.3.0/162dd7fdee9e61a10441e5262792ec0d76b6011e/readium-navigator-3.3.0.aar; unzip -l "$AAR" | sed -n '"'1,35p'; unzip -p \""'$AAR" classes.jar | strings | rg -n -C 2 '"'evaluateJavascript|getCurrentLocator|EpubNavigatorFragment' | head -120" in /Users/ll/workspace/vreader
 succeeded in 611ms:
10639-#Z%�
10640-�o��z
10641:org/readium/r2/navigator/epub/EpubNavigatorFragment$Companion.class�X�s
10642-C8S�b%
10643-�W��
--
10803-[A�x
10804-���
10805:org/readium/r2/navigator/epub/EpubNavigatorFragment$Configuration$Companion.class
10806-�����
10807-�x`* V��
--
10891-��)�$ħ�
10892-6žp�
10893:org/readium/r2/navigator/epub/EpubNavigatorFragment$Configuration.class�[
10894-l�ƶ06
10895-�\��
--
11350-XTl<�ϧ
11351-ݤ"R
11352:org/readium/r2/navigator/epub/EpubNavigatorFragment$Listener$DefaultImpls.class�U�v
11353-�d��
11354-�4q��
--
11426-h#�z
11427-vq��}
11428:org/readium/r2/navigator/epub/EpubNavigatorFragment$Listener.class�V[S
11429-��,�p���-
11430-ձV�"�
--
11498-�cP4�lp���
11499-w�^*�
11500:org/readium/r2/navigator/epub/EpubNavigatorFragment$PageChangeListener.class
11501-�n�tK
11502-(�@[(S
--
11590-�>n�
11591-�H��|\
11592:org/readium/r2/navigator/epub/EpubNavigatorFragment$PagerAdapterListener.class�U�W
11593-��&d
11594-)��JjS(]��C�Z
--
11679->ShQ
11680-Mէ-�
11681:org/readium/r2/navigator/epub/EpubNavigatorFragment$PaginationListener$DefaultImpls.class
11682-S�n�@
11683-�F;�ey�
--
11736-�S�C�}�
11737-�ش��
11738:org/readium/r2/navigator/epub/EpubNavigatorFragment$PaginationListener.class
11739-���8o
11740-#V���H�
--
11797-|>�G)��
11798-���i,j�4
11799:org/readium/r2/navigator/epub/EpubNavigatorFragment$State$Initializing.class
11800-�fwmo�N�
11801-�qS~
--
11865-�)�K1c�
11866-%#/�
11867:org/readium/r2/navigator/epub/EpubNavigatorFragment$State$Loading.class
11868-��&$�
11869-��X�?�
--
11965-���y|
11966-v�I�
11967:org/readium/r2/navigator/epub/EpubNavigatorFragment$State$Ready.class�SKo
11968-��<���i
11969-6nʣ�
--
12031-;E!�L
12032-�S�j9�eE�K
12033:org/readium/r2/navigator/epub/EpubNavigatorFragment$State.class
12034-�fw�-K
12035-�����
--
12078-n(,(�TX�
12079-�{e;
12080:org/readium/r2/navigator/epub/EpubNavigatorFragment$WebViewListener.class�Z{|T�
12081-���N�N&
12082- �0@
--
12494-~��ks �y|
12495-3e{��
12496:org/readium/r2/navigator/epub/EpubNavigatorFragment$WhenMappings.class�S�N
12497-C�EA.*� 
12498-Zl�%���
--
12560-�q�Q�
12561-t�9B�'��
12562:org/readium/r2/navigator/epub/EpubNavigatorFragment$applyDecorations$1.class�T�o
12563-��v��qi
12564-���MC�
--
12630-�5�z��<)ް�p��M\l�
12631-��.�'�F
12632:org/readium/r2/navigator/epub/EpubNavigatorFragment$currentSelection$1.class�T[OSA
12633-��--
12634-bBb�m
--
12694-_��Q
12695-�j0�W
12696:org/readium/r2/navigator/epub/EpubNavigatorFragment$evaluateJavascript$1.class�UQS[E
12697-^LiG
12698-n�f��
--
12757-wX짻��
12758-k!��
12759:org/readium/r2/navigator/epub/EpubNavigatorFragment$firstVisibleElementLocator$1.class�T[O
12760-o ((U�`
12761-��Y�;���
--
12820-�nK{p8��9
12821-Q�(��wPK
12822:org/readium/r2/navigator/epub/EpubNavigatorFragment$notifyCurrentLocation$1.class�Z
12823-X\�u�����c
12824-#yl�H
--

exec
/bin/zsh -lc 'AAR=/Users/ll/.gradle/caches/modules-2/files-2.1/org.readium.kotlin-toolkit/readium-navigator/3.3.0/162dd7fdee9e61a10441e5262792ec0d76b6011e/readium-navigator-3.3.0.aar; unzip -p "$AAR" classes.jar | bsdtar -xOf - org/readium/r2/navigator/epub/EpubNavigatorFragment.class | strings | rg -n -C 3 '"'evaluateJavascript|getCurrentLocator|currentLocator|firstVisibleElementLocator|submitPreferences'" in /Users/ll/workspace/vreader
 succeeded in 515ms:
131-#kotlinx/coroutines/flow/StateFlowKt
132-MutableStateFlow
133->(Ljava/lang/Object;)Lkotlinx/coroutines/flow/MutableStateFlow;
134:_currentLocator
135-*Lkotlinx/coroutines/flow/MutableStateFlow;
136-,tableOfContentsTitleByHref_delegate$lambda$0
137-@(Lorg/readium/r2/shared/publication/Publication;)Ljava/util/Map;
--
172-S()Lkotlinx/coroutines/flow/StateFlow<Lorg/readium/r2/navigator/epub/EpubSettings;>;
173-getViewModel
174-8()Lorg/readium/r2/navigator/epub/EpubNavigatorViewModel;
175:submitPreferences
176-2(Lorg/readium/r2/navigator/epub/EpubPreferences;)V
177-preferences
178-I(Lorg/readium/r2/navigator/epub/EpubPreferences;)Lkotlinx/coroutines/Job;
179:evaluateJavascript
180-F(Ljava/lang/String;Lkotlin/coroutines/Continuation;)Ljava/lang/Object;
181-[(Ljava/lang/String;Lkotlin/coroutines/Continuation<-Ljava/lang/String;>;)Ljava/lang/Object;
182:Horg/readium/r2/navigator/epub/EpubNavigatorFragment$evaluateJavascript$1
183-label
184-X(Lorg/readium/r2/navigator/epub/EpubNavigatorFragment;Lkotlin/coroutines/Continuation;)V
185-result
--
419-event
420-<Lorg/readium/r2/navigator/epub/EpubNavigatorViewModel$Event;
421-:org/readium/r2/navigator/epub/EpubNavigatorViewModel$Event
422:getCurrentLocator
423-f(Lorg/readium/r2/navigator/Navigator;Lorg/readium/r2/shared/publication/Locator;ZILjava/lang/Object;)Z
424-locator
425-onSettingsChange
--
648-;$i$a$-forEach-EpubNavigatorFragment$loadedFragmentForHref$1
649-pageFragment
650-R()Lkotlinx/coroutines/flow/StateFlow<Lorg/readium/r2/shared/publication/Locator;>;
651:firstVisibleElementLocator
652-b(Lkotlin/coroutines/Continuation<-Lorg/readium/r2/shared/publication/Locator;>;)Ljava/lang/Object;
653-.Lorg/readium/r2/shared/ExperimentalReadiumApi;
654:Porg/readium/r2/navigator/epub/EpubNavigatorFragment$firstVisibleElementLocator$1
655-)findFirstVisibleLocator$readium_navigator
656-getMediaType
657-2()Lorg/readium/r2/shared/util/mediatype/MediaType;
--
774-f(Lorg/readium/r2/navigator/epub/EpubNavigatorFragment;)Lorg/readium/r2/shared/publication/Publication;
775-$access$getTableOfContentsTitleByHref
776-F(Lorg/readium/r2/navigator/epub/EpubNavigatorFragment;)Ljava/util/Map;
777:access$get_currentLocator$p
778-a(Lorg/readium/r2/navigator/epub/EpubNavigatorFragment;)Lkotlinx/coroutines/flow/MutableStateFlow;
779-<clinit>
780-=org/readium/r2/navigator/epub/EpubNavigatorFragment$Companion
--
824-r2PagerAdapter
825-currentReflowablePageFragment
826-currentFragment
827:currentLocator
828-tableOfContentsTitleByHref
829-(Lorg/readium/r2/shared/publication/Href;
830-Configuration

exec
/bin/zsh -lc 'AAR=/Users/ll/.gradle/caches/modules-2/files-2.1/org.readium.kotlin-toolkit/readium-navigator/3.3.0/162dd7fdee9e61a10441e5262792ec0d76b6011e/readium-navigator-3.3.0.aar; unzip -p "$AAR" classes.jar | bsdtar -xOf - org/readium/r2/navigator/epub/EpubNavigatorFragment.class | strings | sed -n '"'155,190p;400,430p;635,660p'" in /Users/ll/workspace/vreader
 succeeded in 519ms:
*Lorg/readium/r2/shared/publication/Layout;
)org/readium/r2/shared/publication/Locator
-org/readium/r2/navigator/epub/EpubPreferences
<org/readium/r2/navigator/epub/EpubNavigatorFragment$Listener
Forg/readium/r2/navigator/epub/EpubNavigatorFragment$PaginationListener
(org/readium/r2/shared/publication/Layout
*org/readium/r2/navigator/epub/EpubDefaults
kotlin/Lazy
kotlin/reflect/KClass
getListener$readium_navigator
@()Lorg/readium/r2/navigator/epub/EpubNavigatorFragment$Listener;
'getPaginationListener$readium_navigator
J()Lorg/readium/r2/navigator/epub/EpubNavigatorFragment$PaginationListener;
getConfig$readium_navigator
E()Lorg/readium/r2/navigator/epub/EpubNavigatorFragment$Configuration;
getSettings
%()Lkotlinx/coroutines/flow/StateFlow;
S()Lkotlinx/coroutines/flow/StateFlow<Lorg/readium/r2/navigator/epub/EpubSettings;>;
getViewModel
8()Lorg/readium/r2/navigator/epub/EpubNavigatorViewModel;
submitPreferences
2(Lorg/readium/r2/navigator/epub/EpubPreferences;)V
preferences
I(Lorg/readium/r2/navigator/epub/EpubPreferences;)Lkotlinx/coroutines/Job;
evaluateJavascript
F(Ljava/lang/String;Lkotlin/coroutines/Continuation;)Ljava/lang/Object;
[(Ljava/lang/String;Lkotlin/coroutines/Continuation<-Ljava/lang/String;>;)Ljava/lang/Object;
Horg/readium/r2/navigator/epub/EpubNavigatorFragment$evaluateJavascript$1
label
X(Lorg/readium/r2/navigator/epub/EpubNavigatorFragment;Lkotlin/coroutines/Continuation;)V
result
Ljava/lang/Object;
)kotlin/coroutines/intrinsics/IntrinsicsKt
getCOROUTINE_SUSPENDED
kotlin/ResultKt
throwOnFailure
Corg/readium/r2/navigator/epub/EpubNavigatorFragment$onViewCreated$2
k(Lorg/readium/r2/navigator/epub/EpubNavigatorFragment;Landroid/os/Bundle;Lkotlin/coroutines/Continuation;)V
handleEvent
?(Lorg/readium/r2/navigator/epub/EpubNavigatorViewModel$Event;)V
Dorg/readium/r2/navigator/epub/EpubNavigatorViewModel$Event$RunScript
getCommand
I()Lorg/readium/r2/navigator/epub/EpubNavigatorViewModel$RunScriptCommand;
J(Lorg/readium/r2/navigator/epub/EpubNavigatorViewModel$RunScriptCommand;)V
Korg/readium/r2/navigator/epub/EpubNavigatorViewModel$Event$OpenInternalLink
"org/readium/r2/navigator/Navigator
getTarget
*()Lorg/readium/r2/shared/publication/Link;
go$default
c(Lorg/readium/r2/navigator/Navigator;Lorg/readium/r2/shared/publication/Link;ZILjava/lang/Object;)Z
Norg/readium/r2/navigator/epub/EpubNavigatorViewModel$Event$InvalidateViewPager
PLorg/readium/r2/navigator/epub/EpubNavigatorViewModel$Event$InvalidateViewPager;
areEqual
'(Ljava/lang/Object;Ljava/lang/Object;)Z
invalidateResourcePager
event
<Lorg/readium/r2/navigator/epub/EpubNavigatorViewModel$Event;
:org/readium/r2/navigator/epub/EpubNavigatorViewModel$Event
getCurrentLocator
f(Lorg/readium/r2/navigator/Navigator;Lorg/readium/r2/shared/publication/Locator;ZILjava/lang/Object;)Z
locator
onSettingsChange
[(Lorg/readium/r2/navigator/epub/EpubSettings;Lorg/readium/r2/navigator/epub/EpubSettings;)V
REFLOWABLE
getFontSize
getR2PagerAdapter
setFontSize
6$i$a$-let-EpubNavigatorFragment$goToPreviousResource$2
locatorToResourceAtIndex
.(I)Lorg/readium/r2/shared/publication/Locator;
:$i$a$-let-EpubNavigatorFragment$locatorToResourceAtIndex$1
getCurrentFragment
"()Landroidx/fragment/app/Fragment;
fragmentAt
#(I)Landroidx/fragment/app/Fragment;
getItemId
(J)Ljava/lang/Object;
getLink$readium_navigator
url$default
(Lorg/readium/r2/shared/publication/Link;Lorg/readium/r2/shared/util/Url;Ljava/util/Map;ILjava/lang/Object;)Lorg/readium/r2/shared/util/Url;
;$i$a$-forEach-EpubNavigatorFragment$loadedFragmentForHref$1
pageFragment
R()Lkotlinx/coroutines/flow/StateFlow<Lorg/readium/r2/shared/publication/Locator;>;
firstVisibleElementLocator
b(Lkotlin/coroutines/Continuation<-Lorg/readium/r2/shared/publication/Locator;>;)Ljava/lang/Object;
.Lorg/readium/r2/shared/ExperimentalReadiumApi;
Porg/readium/r2/navigator/epub/EpubNavigatorFragment$firstVisibleElementLocator$1
)findFirstVisibleLocator$readium_navigator
getMediaType
2()Lorg/readium/r2/shared/util/mediatype/MediaType;
.org/readium/r2/shared/util/mediatype/MediaType
:Lorg/readium/r2/shared/util/mediatype/MediaType$Companion;
8org/readium/r2/shared/util/mediatype/MediaType$Companion

exec
/bin/zsh -lc 'AAR=/Users/ll/.gradle/caches/modules-2/files-2.1/org.readium.kotlin-toolkit/readium-navigator/3.3.0/162dd7fdee9e61a10441e5262792ec0d76b6011e/readium-navigator-3.3.0.aar; unzip -p "$AAR" classes.jar | bsdtar -xOf - org/readium/r2/navigator/epub/EpubNavigatorFragment.class | python3 -c '"'import sys,struct
b=sys.stdin.buffer.read(); p=8
u1=lambda: None
def u2():
 global p; v=struct.unpack_from(\">H\",b,p)[0]; p+=2; return v
def u4():
 global p; v=struct.unpack_from(\">I\",b,p)[0]; p+=4; return v
cp=[None]*u2(); i=1
while i<len(cp):
 t=b[p]; p+=1
 if t==1:
  n=u2(); cp[i]=b[p:p+n].decode(\"utf-8\",\"replace\"); p+=n
 elif t in (3,4): p+=4
 elif t in (5,6): p+=8; i+=1
 elif t in (7,8,16,19,20): p+=2
 elif t in (9,10,11,12,17,18): p+=4
 elif t==15: p+=3
 else: raise Exception(t)
 i+=1
p+=6
for _ in range(u2()): p+=2
def attrs():
 global p
 for _ in range(u2()): p+=2; p+=u4()
for _ in range(u2()): p+=6; attrs()
for _ in range(u2()):
 a=u2(); n=cp[u2()]; d=cp[u2()]; attrs()
 if n in (\"evaluateJavascript\",\"getCurrentLocator\",\"firstVisibleElementLocator\",\"submitPreferences\"): print(hex(a),n,d,\"PUBLIC\" if a&1 else \"NONPUBLIC\")'" in /Users/ll/workspace/vreader
 exited 1 in 544ms:
Traceback (most recent call last):
  File "<string>", line 25, in <module>
  File "<string>", line 24, in attrs
  File "<string>", line 7, in u4
struct.error: unpack_from requires a buffer of at least 110215 bytes for unpacking 4 bytes at offset 110211 (actual buffer size is 63601)

exec
/bin/zsh -lc 'AAR=/Users/ll/.gradle/caches/modules-2/files-2.1/org.readium.kotlin-toolkit/readium-navigator/3.3.0/162dd7fdee9e61a10441e5262792ec0d76b6011e/readium-navigator-3.3.0.aar; unzip -p "$AAR" classes.jar | bsdtar -xOf - org/readium/r2/navigator/epub/EpubNavigatorFragment.class | python3 -c '"'import sys,struct
b=sys.stdin.buffer.read(); p=8
def u2():
 global p; v=struct.unpack_from(\">H\",b,p)[0]; p+=2; return v
def u4():
 global p; v=struct.unpack_from(\">I\",b,p)[0]; p+=4; return v
cp=[None]*u2(); i=1
while i<len(cp):
 t=b[p]; p+=1
 if t==1:
  n=u2(); cp[i]=b[p:p+n].decode(\"utf-8\",\"replace\"); p+=n
 elif t in (3,4): p+=4
 elif t in (5,6): p+=8; i+=1
 elif t in (7,8,16,19,20): p+=2
 elif t in (9,10,11,12,17,18): p+=4
 elif t==15: p+=3
 else: raise Exception(t)
 i+=1
p+=6
for _ in range(u2()): p+=2
def attrs():
 global p
 for _ in range(u2()):
  p+=2; n=u4(); p+=n
for _ in range(u2()): p+=6; attrs()
for _ in range(u2()):
 a=u2(); n=cp[u2()]; d=cp[u2()]; attrs()
 if n in (\"evaluateJavascript\",\"getCurrentLocator\",\"firstVisibleElementLocator\",\"submitPreferences\"): print(hex(a),n,d,\"PUBLIC\" if a&1 else \"NONPUBLIC\")'" in /Users/ll/workspace/vreader
 succeeded in 522ms:
0x1 submitPreferences (Lorg/readium/r2/navigator/epub/EpubPreferences;)V PUBLIC
0x11 evaluateJavascript (Ljava/lang/String;Lkotlin/coroutines/Continuation;)Ljava/lang/Object; PUBLIC
0x1 getCurrentLocator ()Lkotlinx/coroutines/flow/StateFlow; PUBLIC
0x1 firstVisibleElementLocator (Lkotlin/coroutines/Continuation;)Ljava/lang/Object; PUBLIC
0x1041 submitPreferences (Lorg/readium/r2/navigator/preferences/Configurable$Preferences;)V PUBLIC

exec
/bin/zsh -lc "nl -ba dev-docs/plans/20260710-feature-131-android-bilingual-interlinear.md | sed -n '20,105p;117,195p;213,240p' && nl -ba android/app/src/main/kotlin/com/vreader/app/reader/ReaderActivity.kt | sed -n '80,120p;195,235p;445,470p;482,515p' && nl -ba android/app/build.gradle.kts | sed -n '103,117p'" in /Users/ll/workspace/vreader
 succeeded in 0ms:
    20	
    21	### Render-host decision (settled in v2, CONFIRMED by round-2 — not reopened)
    22	
    23	**Two hosts, in dependency order:**
    24	
    25	1. **EPUB (Readium `EpubNavigatorFragment`) — PRIMARY.** Interlinear via `evaluateJavascript` (enumerate leaf blocks → inject translation DOM nodes → clear on teardown/reflow), mirroring iOS `EPUBBilingualOrchestrator`. Gated by **WI-0 (a Readium bilingual spike with enforceable go/no-go thresholds + a navigator-race contract — round-2 M1)** before the EPUB render WI (WI-7b) is built.
    26	2. **TXT/MD (Compose `TxtReaderActivity`) — INCLUDED.** No WebView; deterministically Compose-testable. Renders from **document-global segment ranges** (round-2 H1), NOT one body per chunk.
    27	
    28	**AZW3 (foliate WebView)** and **PDF** remain follow-ups / out (§"Files OUT of scope").
    29	
    30	**Why both, not TXT/MD-only:** the *pipeline* (segment → chunk → translate → cache → interleave) is host-agnostic; only the *render injection* is host-specific. EPUB is the format most users read, so shipping box D without it would under-deliver. TXT/MD are included because the Compose host is the cheapest, most testable place to prove the pipeline end-to-end (deterministic tree assertions), de-risking the EPUB adapter. **Box D cannot be checked on a false "EPUB requires a fork" rationale** — that rationale is discarded and stays discarded.
    31	
    32	### The TXT/MD segmentation unit + render mapping (round-2 H1 — the core v3 correction)
    33	
    34	**Verified against live code:** `TxtDocument` (in `reader/TxtDocument.kt`) exposes only `text: String`, `chunkCount`, `offsetForChunk(index)`, `chunkForOffset(offsetUtf16)`, `textForChunk(index)` — line-based ≤4000-char chunks over UTF-16 offsets against the RAW text (no line-ending normalization). It has **no chapter/section concept**. `TxtMdTextExtractor` (in `search/`) explicitly emits one section per chunk "because TXT has no sub-resource grouping." A chunk can hold multiple paragraphs OR split one long paragraph. So the v2 "translate per chunk, render one body per chunk" contract is not achievable.
    35	
    36	**v3 model — document-global units with segment ranges produced ONCE:**
    37	
    38	- The whole `.txt`/`.md` is treated as **one translation document**. The **segmenter runs once over `TxtDocument.text`** (the full raw backing string) and emits, per segment, its **`IntRange` UTF-16 span** against that same backing string (the segmenter's `paragraphRanges(text)` / `sentenceRanges(text)` — the range-returning peers of `paragraphs`/`sentences`; iOS precedent `ChapterSegmenter.sentenceRanges(in:)` returns `[Range<Int>]`). These ranges are the SINGLE source of truth used by BOTH the translate side and the render side, so the two segment identically **by construction** (they read the same array).
    39	- **Unit granularity for TXT/MD is the whole document, sub-batched for cache/prefetch by a deterministic "unit window."** To avoid translating a 14 MB book at once (and to keep cache rows bounded), segment ranges are grouped into fixed **unit windows** of contiguous segments (window size a constant, e.g. covering ≈ one on-screen span; the exact constant is set at build time and does not change the 1:1 contract). Each window is a `TranslationUnitId(kind = txtDocSegmentWindow, value = windowIndex)` — a document-global index, NOT a chunk index. `unitContaining(locator)` maps the reader's saved `charOffsetUTF16` → the segment whose range contains it → its window index (via a precomputed segment-start binary search, the same shape as `TxtDocument.chunkForOffset`). `unitAfter(unit)` = next window index or null at document end.
    40	- **Render mapping (the LazyColumn):** the TXT/MD body still iterates the existing `items(count = document.chunkCount, key = { it })` loop (verified injection point, TxtReaderActivity.kt:1043) for source layout/selection/highlight parity — **but bilingual interlinear content is keyed by SEGMENT RANGE, not by chunk.** For each rendered chunk `i` (source UTF-16 span `[offsetForChunk(i), offsetForChunk(i+1))`), the body looks up every segment whose range **overlaps** that chunk span and, after the source text of that segment's portion, renders its cached translation (muted) — from the SAME range array the translator used. A segment spanning two chunks contributes its translation once, anchored at the chunk where its range ends (deterministic), so a paragraph split across a chunk boundary is translated once and rendered once. When bilingual is OFF, the loop is byte-identical to today (translations are additive overlays only).
    41	- **MD source** = raw markdown segment text (translation renders as plain muted text, not re-markdown-rendered — matches the muted-secondary design line). Segmentation runs over the raw markdown string; MD markers are treated as ordinary characters by the paragraph splitter (blank-line delimited), consistent with `TxtMdTextExtractor` shipping raw markdown to search.
    42	
    43	This closes H1: there is no invented chapter model, the render boundary IS the segmentation boundary, and disabled = source byte-parity because bilingual content is a pure overlay off the shared range array.
    44	
    45	### New files
    46	
    47	**Pipeline / domain (host-agnostic, pure or coroutine — JVM-testable):**
    48	
    49	- `bilingual/TranslationUnitId.kt` — `data class TranslationUnitId(kind, value)` with `enum Kind { epubHref, foliateHref, txtDocSegmentWindow, mdDocSegmentWindow, pdfPageRange }`; `storageKey = "${kind.name}:$value"`. Mirrors iOS `TranslationUnitID.Kind` in spirit; the TXT/MD kinds are **document-global segment-window indices** (H1), NOT chunk indices. v3 uses `epubHref` + `txtDocSegmentWindow`/`mdDocSegmentWindow`; others reserved so the cache-key format never breaks. *(Assumption I could not fully confirm: iOS's exact Kind case names for the TXT/MD variants — the Android names are chosen to describe the real unit; the storageKey format is what the cache contract depends on.)*
    50	- `bilingual/TranslationGranularity.kt` — `enum { paragraph, sentence }`. (Design's Granularity control.)
    51	- `bilingual/BilingualLanguages.kt` — `BilingualLanguage(key, glyph, script)`; `BILINGUAL_LANGS` = the set from `vreader-bilingual.jsx` + `findOrDefault(key)`. Default `Chinese`.
    52	- `bilingual/ChapterSegmenter.kt` — **NEW file (there is no existing Android segmenter; the `search/` module has none — verified).** Port of iOS `ChapterSegmenter`: `paragraphs(text)` / `sentences(text)` **plus the range-returning peers `paragraphRanges(text): List<IntRange>` / `sentenceRanges(text): List<IntRange>`** (UTF-16 spans against the input string — iOS `sentenceRanges(in:)` precedent). The ranges are what H1's mapping consumes. CJK-aware sentence enumeration (。！？ vs Latin). Pure.
    53	- `bilingual/TranslationChunker.kt` — `chunk(segments, maxCharsPerChunk)` + `subSplit(text, maxChars)`. Port of iOS `ChapterTranslationChunker.chunk(...)` + `subSplit(...)` (verified: `chunk` returns index groups, oversize segment gets its own chunk; `subSplit` is the Bug #330 grapheme-safe over-budget splitter).
    54	- `bilingual/TranslationChunkContract.kt` — `userPrompt(segments, targetLanguage)`; `decode(raw, expectedCount)` (strict JSON-array + code-fence strip); `sealed class DecodeError { NotAStringArray; CountMismatch(expected, actual) }`. Port of iOS `TranslationChunkContract`. (No `style` param — Style is descoped v1, §3/H3.)
    55	- `bilingual/ChapterTextProvider.kt` — `interface { units(); sourceSegments(unit); sourceText(unit); unitContaining(locator); unitAfter(unit) }`. **`sourceSegments(unit)` returns the exact segment strings (from the shared range array)** — this is what the EPUB direct-block and TXT/MD paths both feed to the translator so counts pair 1:1. Resolution is host-specific: TXT/MD key on `charOffsetUTF16` → segment-window; EPUB keys on the current-resource `href` from `EpubNavigatorFragment.currentLocator`. Honest divergence from iOS's uniform Readium `Locator`, documented.
    56	- `bilingual/TxtChapterTextProvider.kt` — provider over `TxtDocument` + the segmenter's range array (H1). Builds the document-global segment ranges once, groups them into windows, resolves `unitContaining` via a segment-start binary search over `charOffsetUTF16`. MD source = raw markdown segment text.
    57	- `bilingual/EpubChapterTextProvider.kt` (WI-0-gated shape) — provider over the Readium `Publication` reading order; `units()` = spine hrefs, `unitContaining(locator)` = the locator's href, `sourceSegments(unit)` = the DOM-enumerated block texts (the render's OWN enumeration, for direct-block 1:1 — H2). Its render-side collaborator (the JS enumerate/inject adapter) is `EpubBilingualJs` (M2), defined by WI-0's findings.
    58	- `bilingual/ChapterTranslationError.kt` — `sealed { Offline; TimedOut; ProviderFailed(msg); Cancelled }`. Maps from `AiError` (verified cases: `Auth401`, `RateLimited429`, `Offline`, `Timeout`, `Http(code)`, `Decode`, `Stream`, `InsecureUrl`, `Config`).
    59	- `bilingual/ChapterTranslationService.kt` — the iOS-parity service, now with the **full divergence-recovery surface (round-2 H2)**:
    60	  - `cachedTranslation(bookKey, unit, sourceText, targetLanguage, granularity, acceptCountMismatch=false)` — cache-only, segments the source to count-check; serves a row only when `sourceParagraphCount == segments.size` (or `acceptCountMismatch`). No provider (#306 parity).
    61	  - `cachedTranslation(bookKey, unit, expectedSegmentCount, targetLanguage)` — **the divergence-fallback cache-only restore (iOS Bug #343)**: serves the canonical row only when its STORED `sourceParagraphCount == expectedSegmentCount` (the DOM enumerate's block count). **Needs no source text and no provider** → a cache-hit toggle/reopen restores with **zero provider calls**.
    62	  - `translate(bookKey, unit, sourceText, targetLanguage, providerProfile, granularity, bypassCacheRead=false)` — segment → chunk → per-chunk `AiClient.chat` one-shot → `decode` → per-segment fallback → per-chunk graceful degrade (Bug #330: a single failed chunk renders source-only for its segments and is NOT cached; all-chunks-fail throws) → cache-write only on full success. Cache row stores `sourceParagraphCount = segments.size`. Cancellation: `ensureActive()` between chunks AND immediately before the Room write (§6).
    63	  - `translatePreSegmented(bookKey, unit, segments, targetLanguage, providerProfile)` — **the count-divergence recovery (round-2 H2; iOS Bugs #268/#330/#343).** Takes the render's OWN enumerated block texts as `segments` (1:1 by construction), chunks them, translates with the same per-chunk graceful-degrade + cancellation contract, and — on full success only — **caches under the canonical key with the ENUMERATE's count as the stored contract** (so a later reopen restores via `cachedTranslation(expectedSegmentCount:)`). A partial degrade is NOT cached. A cache-write failure does not fail the translation.
    64	  - Uses `AiClient.chat(AiRequest)` (one-shot, verified — NOT `streamChat`).
    65	- `bilingual/ChapterTranslationPrefetcher.kt` — resolves the active profile from one `AiProviderStore.snapshot()` (`snapshot.active`), decrypts via `store.apiKey(profile)` (snapshot-consistent), builds an `AiClient` via an **injected factory param** (below), cache-first then translate. Adds the **direct-block peers (H2)**:
    66	  - `prefetch(unit)` — the plain-text path (segment source → `translate`).
    67	  - `prefetchDirect(unit, sourceSegments, targetLanguage)` — the divergence path (iOS `translatedSegmentsDirect`): same snapshot+resolve+error contract, then `service.translatePreSegmented(...)`.
    68	  - `cachedDirect(unit, expectedCount, targetLanguage)` — the **zero-provider cache-only restore** (iOS `cachedSegmentsDirect` → `cachedTranslation(expectedSegmentCount:)`): **returns a cached translation on a hit WITHOUT requiring an active provider** (the #306 pre-gate precedent). This is what backs `EpubReaderBilingualConnectedTest.count-divergence handled` cache-restore assertions.
    69	  - Throws `ChapterTranslationError`. Mirrors iOS `ChapterTranslationPrefetcher`.
    70	- `bilingual/BilingualAiReadiness.kt` — `resolve(snapshot): Boolean` (active profile exists AND its decrypted key is non-empty). A cipher/decryption failure maps to **not-ready** (never crashes — §6). Drives the setup-sheet engine-strip configured/unconfigured state. Keep the gate to exactly what #118 enforces (no separate consent manager on Android — #118 has none; confirm during build).
    71	
    72	**State / persistence:**
    73	
    74	- `bilingual/PerBookBilingualStore.kt` — DataStore-Preferences, keyed by `bookFingerprintKey`, holding `{ enabled, targetLanguage, granularity }`. This is the Android `PerBookSettingsOverride` bilingual slice — the backup contract declares exactly `bilingualEnabled` / `bilingualTargetLanguage` / `bilingualGranularity` and **NO `bilingualStyle`** (verified). So this store writes exactly those three fields. Wiring into backup collect/restore is scoped OUT (§7) — additive later; until then bilingual config is device-local.
    75	- `bilingual/BilingualViewModel.kt` — `StateFlow<BilingualUiState>` with `enabled`, `targetLanguage`, `granularity`, `needsSetupSheet`, `aiConfigured`, `translationsByUnit`, `inFlightUnits`, `unavailableUnits`, `errorUnit`. Setters + `dismissSetupSheet`, `onPositionChanged(locator)`, `retryUnit(unit)`. Generation/epoch-guarded prefetch (current + next unit), cancellation on disable / language / granularity change — port of iOS `BilingualReadingViewModel` + `+Prefetch`. Split to `BilingualPrefetchController.kt` if it nears ~300 lines. (No `style` field — the authoritative sheet has no Style control; Style is descoped v1 — §3.)
    76	
    77	**Room (translation cache):**
    78	
    79	- `data/ChapterTranslationEntity.kt` — `@Entity(tableName="chapter_translations", indices=[Index("bookKey")], foreignKeys=[FK→books.fingerprintKey ON DELETE CASCADE])`. **`@PrimaryKey val lookupKey: String`** (Room REQUIRES a PK; verified against `HighlightEntity`, which pairs a `@PrimaryKey` with a separate unique index). `lookupKey` = `bookKey|unitStorageKey|targetLanguage|promptVersion`. Other columns: `bookKey`, `unitStorageKey`, `targetLanguage`, `promptVersion`, `translatedJson`, `sourceParagraphCount`, `createdAt`. Mirrors iOS `ChapterTranslationRecord.lookupKey` (`book|unit|lang|prompt`, profile-agnostic — Bug #342). **`sourceParagraphCount` is load-bearing for H2**: it stores the enumerate's count on the `translatePreSegmented` path so `cachedTranslation(expectedSegmentCount:)` can restore.
    80	- `data/ChapterTranslationDao.kt` — `getByLookupKey(key)`, `@Upsert suspend fun upsert(row)` (Upsert identifies by PK = `lookupKey`, so it is insert-or-replace by cache identity), `deleteByLookupKey(key)`. The project's Room pattern is `@PrimaryKey` + `@Upsert` (verified: `BookDao.upsert`).
    81	- `bilingual/ChapterTranslationStore.kt` — coroutine wrapper returning a `CachedTranslation` (segments decoded from JSON), keeping Room entities off the boundary (the iOS `ChapterTranslationStore` precedent).
    82	
    83	**Cache-identity (reconciled with iOS parity):** the 4-part key `book|unit|lang|promptVersion` is profile-AGNOSTIC / style-agnostic (Bug #342). Style is descoped v1 (§3/H3) so no `s=` component exists. **Granularity IS user-selectable**, so it is carried in `promptVersion` as an **effective composite**: `promptVersion = "bilingual-v1|g=${granularity}"` (a paragraph vs sentence translation is a different cache row — this also closes the iOS #344 "sentence silently ignored" class by construction). A granularity change must cancel in-flight jobs, bump the VM generation, clear shaped in-memory `translationsByUnit`, and force a correctly-keyed re-fetch (specified in WI-6).
    84	
    85	**DI / factory (verified live):** `AiProviderFactory` is an `object` with `create(profile: AiProviderProfile, apiKey: String, dispatcher: CoroutineDispatcher = Dispatchers.IO): AiClient` (verified). So `ChapterTranslationPrefetcher` takes its OWN injected `clientFactory: (AiProviderProfile, String) -> AiClient` param **defaulting to `AiProviderFactory::create`** (production) and overridden with a fake in tests. The prefetcher builds `AiRequest(model = profile.model, messages = …, temperature = profile.temperature, maxTokens = profile.maxTokens, system = …)` from the resolved profile (verified `AiRequest` fields).
    86	
    87	**AI-provider reachability — spun out to #136 (round-2 H3; ORCHESTRATOR/USER DECISION):** verified against the live code — `AppContainer` does **NOT** provide `AiProviderStore`, and there is **NO live navigation route to `AiProviderListScreen`** (MainActivity has no NavHost; the #118 screen + store + `AiSettingsViewModel` exist but are only exercised by instrumented/round-trip tests). A fresh-install user therefore cannot reach provider config today. This gap is now owned by a **NEW separate tiny feature #136 (AI provider setup made production-reachable)** — a **HARD dependency of #131**. #136 delivers: the AI-provider-entry sheet/route, its production reachability, `AiProviderStore` wired into `AppContainer`, and its own Gate-5 acceptance (`unconfigured → Set up → add provider → return → enable → translate`). **#131 keeps only the wiring** of the bilingual "Set up translation" affordance → #136's AI-provider-entry sheet (WI-9's entry-wiring), and consumes `AiProviderStore` from `AppContainer` (provided by #136). #131 does NOT invent the AI-config sheet or its nav (rule 51). *(Assumption: #136 IS now a `docs/features.md` row — filed 2026-07-12 as GH #1976; #131's `Deps` reference it.)*
    88	
    89	**UI (Compose — every state depicted, reproducing `vreader-bilingual.jsx`):**
    90	
    91	- `bilingual/BilingualSetupSheet.kt` — reproduces `vreader-bilingual.jsx`'s `BilingualSetupSheet` EXACTLY: header Cancel / Translate; a **preview strip**; a **language grid** over `BILINGUAL_LANGS` (glyph tiles, selected accent); a **Granularity** segmented control (Paragraph "Translate after each ¶" / Sentence "Translate after each sentence"); a **Translation engine** strip (configured: "Claude · with this book's context" + "Change…"; unconfigured: "No AI provider configured" + "Set up"). **No Style control, no provider/model card, no term-overrides toggle, no cost footer** — those belong to the other (`vreader-ai-android.jsx`) sheet, which this plan does not reproduce (§3). The **"Set up" CTA routes to #136's AI-provider-entry sheet** (wired in WI-9); "Change…" routes there too.
    92	- `bilingual/BilingualInterlinearBody.kt` — **the Compose render surface for the TXT/MD host ONLY** (round-2 M2). Per source segment (from the shared range array): source `Text` then translation `Text` muted with accent left-border, `fontSize*0.88`, CJK font for cjk scripts, RTL handling for Arabic script. Consumes a **host-neutral bilingual state DTO** (see `BilingualRenderState` below). Loading state ("Translating chapter… N%" + per-segment dim). Error state ("Couldn't translate" + Retry). Partial/offline (`unavailableUnits`): source-only silent fallback (design's original-always-kept guarantee — iOS Decision 2). **This is NOT the EPUB render surface** — EPUB uses `EpubBilingualJs` DOM injection (M2 below).
    93	- `bilingual/BilingualRenderState.kt` — the **host-neutral state DTO** shared by BOTH the Compose body and the EPUB adapter (round-2 M2): per-unit `{ segments: List<String>?, phase: Loaded|Loading(fraction)|Error|SourceOnly }`. Compose reads it to compose `Text`; the EPUB adapter reads the SAME type to build DOM. Compose and EPUB share the **state/value types, NOT the composable body**.
    94	- `bilingual/EpubBilingualJs.kt` (WI-0-gated) — **the EPUB render surface (round-2 M2).** A pure Kotlin builder that, from a `BilingualRenderState` unit, produces the **JS strings** for `navigator.evaluateJavascript(...)`: (a) `enumScript` (enumerate current-resource leaf blocks → JSON `[{id,text}]`), (b) `injectScript(blockId, translationText)` (construct a translation DOM node after the block, CSP-safe: text set via `textContent`/`createTextNode`, never `innerHTML` string-concat; RTL/CJK via a class + injected `<style>`), (c) `clearScript()` (remove all injected nodes idempotently). Escaping is done in Kotlin (JSON-encode every interpolated string) so a translation containing quotes/`</script>`/newlines cannot break out. **No Compose here.** Consumes `BilingualRenderState`.
    95	- `bilingual/EpubBilingualController.kt` (WI-0-gated) — the runtime actor that serializes enumerate→translate→inject/clear against the navigator using WI-0's chosen mechanism (a single mutex OR a monotonic navigator-session token — M1); checks the session token after every suspended JS/AI call; clears BEFORE publication teardown; re-applies on the identified production re-apply signal (M1).
    96	- `bilingual/BilingualPill.kt` — the `EN ↔ 中` reader-**top-chrome** pill (per `vreader-reader.jsx` `ReaderTopChrome` + `vreader-bilingual.jsx` `BilingualPill`). Rendered by #132's top chrome; #131 provides the composable, #132's surface hosts it (§4).
    97	
    98	### Modified files
    99	
   100	- `data/VReaderDatabase.kt` — add `ChapterTranslationEntity` to `@Database entities`, bump `version` **8 → 9** (round-2 M4: the live DB is **v8**, migrations `MIGRATION_1_2`..`MIGRATION_7_8`; the number is allocated current→next **at implementation time** — against this checkout that is **8→9**), add **`MIGRATION_8_9`** (CREATE TABLE `chapter_translations` + `bookKey` index + FK→`books.fingerprintKey` CASCADE, DDL exactly matching Room's generated schema), **append `MIGRATION_8_9` to `ALL_MIGRATIONS` after `MIGRATION_7_8`**, add `abstract fun chapterTranslationDao()`. The translation-cache table is purely additive.
   101	- `reader/TxtReaderActivity.kt` — own a `BilingualViewModel`; collect state; render translations in the existing `items(count = document.chunkCount, key = { it })` loop (verified injection point, TxtReaderActivity.kt:1043) **keyed by segment range overlap (H1)**, not per chunk; on position change call `vm.onPositionChanged(canonicalLocator.charOffsetUTF16)`. Strictly gated to `originalFormat ∈ {txt, md}`; disabled = body byte-unchanged (overlay-only). **This file is owned by #129 (VERIFIED); #131's edit lands on top of it (rule 48 one-writer-per-file) — #129 is merged, so this is a straight edit, not a blocker.**
   102	- `reader/ReaderActivity.kt` (Readium EPUB) — WI-0-gated: attach `EpubBilingualController` to `navigator.evaluateJavascript`; re-apply on the identified production re-apply signal (M1); clear on teardown BEFORE publication teardown. Concrete surface defined by WI-0's spike output. `navigator: EpubNavigatorFragment?` is the verified live field.
   103	- `VReaderApp.kt` / `AppContainer` — **consume `AiProviderStore` (provided by #136), and provide** `ChapterTranslationStore`, `PerBookBilingualStore`, `ChapterTranslationService`, `ChapterTranslationPrefetcher`, and a `BilingualViewModel` factory. **Extracted into the shared DI WI (WI-4b, round-2 M3)** so both host integrations depend on it. Mirrors #116/#118/#122 DI. *(Note: `AiProviderStore`-into-`AppContainer` is #136's deliverable; #131's DI WI wires the bilingual services around it.)*
   104	
   105	**NOT modified:** `reader/chrome/ReaderBottomChrome.kt` gets **no** bilingual/Translate slot — the design's entry is the More-menu toggle (#134) + the top-chrome pill (#132), NOT a bottom-chrome slot. `ReaderBottomChrome`'s existing `extraSlot` is untouched.
   117	## 3. Prior art / project precedent / rejected alternatives
   118	
   119	### The render-host decision (settled v2, CONFIRMED round-2)
   120	
   121	**How iOS does interlinear:** iOS renders EPUB/AZW3 in a WKWebView it fully controls. `EPUBBilingualOrchestrator` injects JS that (1) enumerates leaf blocks posting `[{bid,text}]` to Swift, (2) after translation injects a translation node after each block. TXT/MD render in a text path where the renderer interleaves translation runs. The mechanism = **the app inserts translation nodes between source nodes.**
   122	
   123	**Android EPUB feasibility (round-2 re-verified):** `javap`/the transformed API JAR on the resolved Readium 3.3.0 AAR expose public `evaluateJavascript(String, Continuation<? super String>)`, `getCurrentLocator()`, `firstVisibleElementLocator(...)`, `submitPreferences(...)`; `ReaderActivity.navigator: EpubNavigatorFragment?` holds the concrete fragment. So EPUB interlinear via JS injection is feasible with the public API — **no Readium fork.** The audit CONFIRMED this correction; it is not reopened.
   124	
   125	**WI-0 — Readium bilingual spike (gates WI-7b; round-2 M1 rewrote its contract into enforceable go/no-go thresholds):** a throwaway harness that, against a real EPUB on the emulator, must PROVE (each is a pass/no-go criterion):
   126	
   127	- **(a) Enumeration is deterministic + idempotent, with stable node IDs.** Enumerating the same current resource twice yields the same block IDs in the same order. Repeated `apply` produces **no duplicate injected nodes** (idempotent replacement).
   128	- **(b) Clear wins over every older inject.** Under a rapid enable→disable / navigate sequence, a late-arriving inject issued before a `clear` must NOT survive the clear — enforced by the serialization mechanism below (a late inject checks the session token and no-ops).
   129	- **(c) Recreation restores from cache** for every case: href away/back, same-href `submitPreferences` reflow, internal page-fragment recreation (the WebView pager recreates fragments), and activity recreation — each must re-apply the interlinear from the disk cache (via `cachedDirect(expectedCount)`, zero provider calls) with **an identified PRODUCTION re-apply signal** (a concrete navigator/lifecycle callback or `currentLocator`/fragment-lifecycle hook) for each case.
   130	- **(d) Locator / visible-source preservation across injection**, with a stated permissible delta (injecting content may shift pagination by ≤ a stated bound; the reader's saved position must map back to the same source block).
   131	- **(e) The enumerated block count vs the segmenter count** is measured; if they diverge (iOS #268), the **direct-block path** (`prefetchDirect` → `translatePreSegmented`, cached by enumerate count, restored by `cachedDirect(expectedCount)` — H2) is the recovery, proven end-to-end in the spike.
   132	
   133	**Race contract (M1):** WI-0 specifies **either a single actor/mutex OR a monotonic navigator-session token**; every suspended JS/AI call is followed by a token/mutex check; cancellation/clear runs BEFORE publication teardown. **If WI-0 cannot find a deterministic production re-apply signal for a recreation case (c), that is an explicit NO-GO:** EPUB drops to a tracked follow-up and box D ships **TXT/MD-only** — with the honest reason (a specific spike finding), never the false "requires a fork."
   134	
   135	**Rejected alternatives:**
   136	1. **Readium interlinear via decorations only** — REJECTED (decorations style existing text; they cannot insert translation paragraphs). `evaluateJavascript` makes injection possible, so EPUB uses the JS seam.
   137	2. **Forking Readium** — REJECTED + unnecessary (public `evaluateJavascript` seam exists).
   138	3. **AZW3 foliate host first** — REJECTED for v1 (deferred, not dead; touches the security-sensitive #126 bridge).
   139	4. **Eager whole-book pre-translation** — REJECTED (cost/latency). Lazily prefetch current+next + cache — port iOS.
   140	5. **One `BilingualInterlinearBody` per chunk (v2)** — REJECTED (round-2 H1): a chunk is not a segment. Replaced by document-global segment ranges (§2).
   141	6. **A Compose body as the EPUB render surface (v2)** — REJECTED (round-2 M2): Compose cannot render inside Readium's WebView. Replaced by `EpubBilingualJs` DOM injection sharing only the `BilingualRenderState` DTO.
   142	
   143	### The setup-sheet resolution (rule 51) + Style descope (round-2 H3, USER DECISION)
   144	
   145	There are **two committed, differently-shaped** `BilingualSetupSheet`s:
   146	- `vreader-bilingual.jsx` → **language grid + Granularity + preview strip + Translation-engine strip (Set up/Change) + Cancel/Translate**. **No Style, no provider/model card, no term-overrides, no cost.**
   147	- `vreader-ai-android.jsx` → **Languages (From/To) + Provider card + Style (Literal/Natural/Literary) + Keep-term-overrides toggle + cost footer.** **No language grid, no Granularity, no preview.**
   148	
   149	**Resolution:** this plan reproduces the **`vreader-bilingual.jsx` sheet EXACTLY** as the authoritative Android-native bilingual sheet. **Style is DESCOPED for v1** (user decision): #131 keeps provider/model/**granularity**, DROPS the bilingual "Style" control. Consequently the store/VM carry no `style`, the chunk contract has no `style` param, and the cache key's `promptVersion` has no `s=` component. Keep rule 51: only implement the designed surface.
   150	
   151	**Box-D parity note (H3 — do NOT claim full box-D parity):** the box-D parity checklist lists provider/model/**style**. Because Style is descoped v1, **WI-9 flips box D to done ONLY for provider/model/granularity + a descope note** — it does NOT claim full box-D parity. A **follow-up tracker/checklist amendment records the Style descope** (the plan does not silently drop it). If Style is later wanted on Android as a user control, that needs an **updated committed design** (a single sheet showing BOTH Style AND Granularity is not depicted anywhere — the one open design gate below).
   152	
   153	### Other precedents applied
   154	
   155	- **#118 provider seam**: reuse `AiProviderStore.snapshot()` (`snapshot.active`) + `store.apiKey(profile)` + `AiProviderFactory.create` (default of an injected factory param) + `AiClient.chat`. #118's AI files are unchanged; **#136** wires `AiProviderStore` into `AppContainer`; #131's DI WI wires the bilingual services.
   156	- **Room additive-migration pattern** (#122/#123/#127/#128/#135): version bump + `MIGRATION_n_(n+1)` appended to `ALL_MIGRATIONS` + exact-DDL + `VReaderDatabaseMigrationTest` PRAGMA guard. `@PrimaryKey` + `@Upsert` is the project's DAO pattern (`BookDao`). Baseline is **v8** (M4).
   157	- **DataStore JSON-in-Preferences** for `PerBookBilingualStore` (the `ReaderSettingsStore`/`AiProviderStore` pattern).
   158	- **Pure-logic port**: iOS `ChapterSegmenter`/`ChapterTranslationChunker`/`TranslationChunkContract`/`ChapterTranslationService.translatePreSegmented`/`ChapterTranslationPrefetcher.translatedSegmentsDirect`+`cachedSegmentsDirect` are pure/heavily-unit-tested — direct Kotlin ports with the same test vectors (all verified to exist).
   159	- **Entry point via #132/#134 (VERIFIED)**: the More-menu bilingual toggle (`MoreActionId.BILINGUAL` reserved; `MoreRow.Toggle` carries `on`/`onToggle`) + top-chrome pill are the landed integration points; #131 mounts the pill + wires the toggle (§4).
   160	
   161	## 4. Work-item sequencing
   162	
   163	**11 WIs/PRs (round-2 L2):** WI-0 (spike), WI-1..WI-4a (foundation/service), **WI-4b (shared DI/factory)**, WI-5, WI-6, WI-7a (Compose UI), **WI-7b (conditional EPUB render adapter — dropped if WI-0 = no-go)**, WI-8 (TXT/MD host integration), WI-9 (entry wiring + acceptance). Each WI = one PR. Build order (round-2 M3): **foundation/cache → service/direct-block APIs → shared DI/factory → VM state/prefetch → host-specific renderers (TXT/MD + EPUB) → entry wiring.**
   164	
   165	**Dependency notes (round-2 L1 — exact landed integration points):**
   166	- **`Deps: [feat:#136, feat:#132, feat:#134]`.** **#132 (top chrome) and #134 (More menu) are VERIFIED — dependencies satisfied** (the top-chrome host + `MoreActionId.BILINGUAL` toggle row are landed). **#129 (TXT/MD reader) is VERIFIED** — `TxtReaderActivity` is a straight edit, not a blocker. **#136 (AI provider setup made production-reachable) is the NEW hard blocker** for #131's entry-wiring (the "Set up"/"Change…" route) AND the DONE flip; it provides `AiProviderStore` in `AppContainer` and the reachable AI-config sheet. The live More model already reserves `MoreActionId.BILINGUAL` (verified).
   167	- The pipeline + setup sheet + interlinear render (WI-0..WI-7) are built ahead; only the **entry wiring (WI-9)** and the **DI WI (WI-4b, for `AiProviderStore` in `AppContainer`)** wait on #136. The pill mount (WI-9) targets #132's VERIFIED top chrome; the toggle wire (WI-9) targets #134's VERIFIED More menu.
   168	
   169	**WI-0 (spike): Readium EPUB bilingual injection — with enforceable go/no-go + race contract (M1).** The harness + criteria (a)–(e) and the race contract in §3. Output: a **go/no-go on EPUB-in-v1** (no-go if no deterministic production re-apply signal — box D ships TXT/MD-only, tracked) + the concrete `EpubChapterTextProvider` / `EpubBilingualJs` / `EpubBilingualController` surfaces. Deps: none (uses the existing #106 Readium host). Not TDD-gated (throwaway spike); its findings feed WI-7b.
   170	
   171	**WI-1 (foundational): value types + pure segmentation/chunk/contract.** `TranslationUnitId` (document-global TXT/MD kinds — H1), `TranslationGranularity`, `BilingualLanguages`, **`ChapterSegmenter` (with `paragraphRanges`/`sentenceRanges` — H1)**, `TranslationChunker`, `TranslationChunkContract` (no `style` — H3), `ChapterTranslationError`. Pure; ported iOS vectors. Deps: none.
   172	
   173	**WI-2 (foundational): Room translation cache.** `ChapterTranslationEntity` (PK = `lookupKey`, `sourceParagraphCount` column) + `Dao` (`@Upsert`) + `ChapterTranslationStore`; `VReaderDatabase` **8→9 `MIGRATION_8_9`** appended after `MIGRATION_7_8` (M4). Robolectric migration round-trip from **v8** + full-chain + upsert/get/delete-by-lookupKey + FK-CASCADE + exact-DDL guard. Deps: none.
   174	
   175	**WI-3 (foundational): `ChapterTranslationService`** against a fake `AiClient`. `cachedTranslation` (both overloads incl. the **`expectedSegmentCount` divergence restore — H2**) + `translate` + **`translatePreSegmented` (H2: chunk, per-chunk degrade, cancellation, cache-write with the enumerate count on full success only)**. Deps: **WI-1, WI-2**. Tests: cache hit → zero client calls; miss → translate + write; decode fail → per-segment fallback; one-chunk fail → source-only that chunk (others translated, NOT cached); all-chunks fail → throw; cancellation → `Cancelled` (no write); `AiError` mapping incl. `Config`/`InsecureUrl` → `ProviderFailed`; **`translatePreSegmented` full-success caches under the enumerate count; partial degrade NOT cached; all-fail throws; `cachedTranslation(expectedSegmentCount)` returns on stored-count match, null on mismatch, needs no provider**.
   176	
   177	**WI-4a (foundational): `ChapterTextProvider` (TXT/MD) + `ChapterTranslationPrefetcher` + `BilingualAiReadiness`.** `TxtChapterTextProvider` builds the **document-global segment ranges once (H1)**, groups into windows, resolves `unitContaining(charOffsetUTF16)` via segment-start binary search, `sourceSegments(unit)`. Prefetcher: `prefetch` + **`prefetchDirect` + `cachedDirect` (zero-provider cache restore — H2)**; resolves active profile from `snapshot()`, decrypts snapshot-consistent, builds client via the **injected factory param** (default `AiProviderFactory::create`), constructs `AiRequest` from the profile. Readiness = active profile with non-empty decrypted key; **cipher failure → not-ready, never a crash.** Fake store + fake factory. Deps: **WI-1, WI-3**. Tests: unit resolution + clamp + empty; **paragraph spanning a chunk boundary → one segment/one unit; multiple paragraphs in one chunk → distinct segments; a >4000-char paragraph → one segment across chunks; CR/LF/CRLF; MD markers; locator→unit mapping; source-byte parity while disabled**; cache-hit-no-profile still returns (#306); no-profile miss → `ProviderFailed`; `prefetchDirect` 1:1; `cachedDirect` restores with zero provider calls; readiness true/false; cipher-throw → readiness false (no crash).
   178	
   179	**WI-4b (foundational — shared DI/factory, round-2 M3): AppContainer bilingual services.** Extract the DI/factory wiring into this EARLIER shared WI: `AppContainer` provides `ChapterTranslationStore`, `PerBookBilingualStore`, `ChapterTranslationService`, `ChapterTranslationPrefetcher`, and the `BilingualViewModel` factory — **consuming `AiProviderStore` from `AppContainer` (provided by #136).** Both host integrations (WI-7b, WI-8) depend on this. Deps: **WI-4a, feat:#136** (for `AiProviderStore` in `AppContainer`). Tests: container resolves the bilingual graph; the prefetcher's injected factory defaults to `AiProviderFactory::create`.
   180	
   181	**WI-5 (behavioral): `PerBookBilingualStore` + `BilingualViewModel` state core.** Store per book (enabled/targetLanguage/granularity — no style); VM setters (persist + first-enable `needsSetupSheet`), language/granularity change clears cache-shaped state + bumps generation. Turbine tests: first-enable raises sheet; re-enable persisted does not; disable clears; language change resets; granularity change resets + re-keys; round-trip through store; no style field. Deps: **WI-1** (+ store).
   182	
   183	**WI-6 (behavioral): VM prefetch trigger + generation/cancellation.** `onPositionChanged(charOffsetUTF16)` derives current unit, dedupes, prefetches current+next; a **monotonic position-request sequence** checked after every suspension; **per-unit generation tokens**; a **captured language/granularity/provider snapshot per launch**; generation bumps on disable/language/granularity/unit-change discard stale; `CancellationException` handled BEFORE generic error mapping; `Offline`→`unavailableUnits`; transient failure leaves unit unfetched + clears anchor to retry; `retryUnit`. Fake prefetcher. Deps: **WI-4a, WI-4b, WI-5**. Tests: current+next on unit change; same-unit no-op; cancel-mid discards stale; offline→unavailable; failure→retry-able; `retryUnit` re-fetches; granularity change cancels + re-fetches under the new key.
   184	
   185	**WI-7a (behavioral): Compose UI — setup sheet + interlinear body (TXT/MD) + pill.** Reproduce `vreader-bilingual.jsx` (setup sheet: language grid / granularity / preview / engine strip configured+unconfigured; body: translated / loading N%+dimmed / error+Retry / offline source-only; pill). Consumes the **host-neutral `BilingualRenderState` DTO (M2)**. Light+dark. Compose UI tests each state. Deps: **WI-5** (state shape). NO Style control; the unconfigured "Set up" CTA renders and (in WI-9) routes to #136's sheet.
   186	
   187	**WI-7b (behavioral, CONDITIONAL — only if WI-0 = go): EPUB render adapter (DOM injection, NOT Compose — round-2 M2).** `EpubBilingualJs` (enum/inject/clear JS builders, CSP-safe escaping) + `EpubBilingualController` (the serialization actor / session token — M1) + `EpubChapterTextProvider`, wired into `ReaderActivity`, driving DOM from the **shared `BilingualRenderState` DTO**. **Depends on WI-6 (VM prefetch) and WI-4b (DI) — the M3 fix; the WI-7a UI dependency is REMOVED except for the shared `BilingualRenderState`/value types.** Uses `prefetchDirect`/`cachedDirect` for the count-divergence path (H2). Connected test on a real EPUB (seeded cache): enable → interlinear injects; disable → nodes cleared; reflow/href-change/fragment-recreation/activity-recreation → re-applies from cache (zero provider calls); count-divergence handled (direct path). Unit tests: JS escaping/CSP-safe text insertion, RTL/CJK style, empty translations, loading cleanup, idempotent replacement, source-only fallback. Deps: **WI-0, WI-3, WI-4a, WI-4b, WI-6, (shared types from WI-7a)**. (If WI-0 = no-go, this WI is dropped and box D ships TXT/MD-only, tracked.)
   188	
   189	**WI-8 (behavioral): `TxtReaderActivity` integration.** Wire VM into the `items(chunkCount)` loop **keyed by segment-range overlap (H1)** + position-change (`charOffsetUTF16`) + setup-sheet. `originalFormat`-gated (TXT/MD). Uses WI-4b's DI. **#129 is VERIFIED — straight edit.** Connected test (fake `AiClient` seam): enable → setup → confirm → interlinear from seeded cache; disable → source-only byte-parity; reopen persists enabled + renders from cache with zero client calls; paragraph-spanning-chunk-boundary renders one translation. Deps: **WI-6, WI-7a, WI-4b**.
   190	
   191	**WI-9 (behavioral): entry wiring + acceptance.** Mount `BilingualPill` in **#132's VERIFIED top chrome**; wire the **#134 VERIFIED More-menu `MoreActionId.BILINGUAL` toggle** (`MoreRow.Toggle` `on`/`onToggle`) to the VM; **wire the setup sheet's "Set up"/"Change…" affordance → #136's AI-provider-entry sheet.** Full acceptance pass across EPUB (if WI-7b landed) + TXT/MD, including the fresh-user path `unconfigured → Set up (→ #136 sheet) → add provider → return → enable → translate` (the #136-owned reachability verified jointly). **Flip box D to done ONLY for provider/model/granularity + the Style-descope note (H3); file the follow-up checklist amendment; do NOT claim full box-D parity, do NOT flip DONE until #136 is landed.** Update `docs/architecture.md` (bilingual pipeline + the new `chapter_translations` schema + bilingual services in `AppContainer`). → DONE. Deps: **WI-8, WI-7b (if go), feat:#136, feat:#132, feat:#134**.
   192	
   193	## 5. Test catalogue
   194	
   195	JVM/Robolectric (`android/app/src/test/...bilingual/`): `ChapterSegmenterTest` (paragraph blank-line; sentence CJK 。！？ vs Latin; empty→[]; single; **`paragraphRanges`/`sentenceRanges` return correct UTF-16 spans**); `TranslationChunkerTest` (packs to budget; oversize→own chunk+subSplit; empty→[]); `TranslationChunkContractTest` (prompt shape; strict JSON decode; code-fence strip; count mismatch→`CountMismatch`; non-array→`NotAStringArray`); `ChapterTranslationServiceTest` (cache hit 0 calls; miss→translate→write; decode-fail per-segment fallback; one-chunk-fail partial-not-cached; all-fail→throw; cancellation→Cancelled no write; ensureActive-before-write; offline/timeout/429/http/config/insecure→error mapping; very long chapter N-of-M; stale-cache count-mismatch re-translates; **`translatePreSegmented` caches under enumerate count on full success; partial degrade not cached; all-fail throws; `cachedTranslation(expectedSegmentCount)` hit/miss with no provider**); `ChapterTranslationErrorMappingTest`; `TxtChapterTextProviderTest` (**paragraph spanning chunk boundary → one segment/unit; multiple paragraphs in one chunk → distinct segments; >4000-char paragraph → one segment across chunks; CR/LF/CRLF; MD markers; locator→unit mapping; unitAfter end→null; source-byte parity while disabled**); `ChapterTranslationPrefetcherTest` (snapshot-consistent profile+key; injected-factory used; `AiRequest` built from profile; cache-hit-no-profile #306; no-profile miss→ProviderFailed; **`prefetchDirect` 1:1; `cachedDirect` restores with zero provider calls**; CJK↔English + Latin round-trip via fake; cipher-throw→ProviderFailed not crash); `BilingualAiReadinessTest` (active+key→true; no active→false; empty key→false; **cipher-throw→false, no crash**); `PerBookBilingualStoreTest` (enabled/lang/granularity round-trip; no style field); `BilingualViewModelTest` (Turbine: first-enable sheet; re-enable no-sheet; disable clears; language reset; **granularity reset + re-key**; prefetch current+next; same-unit no-op; cancel-mid discards; offline→unavailable; error→errorUnit+retry; `retryUnit`); `EpubBilingualJsTest` (**JS escaping / CSP-safe text insertion; RTL/CJK style; empty translations; clear idempotent; inject idempotent replacement; source-only fallback** — WI-7b, if go).
   213	- **Cost/latency of translating on scroll.** Lazy current+next prefetch + disk cache; N-of-M progress; cancellation on navigate-away/generation-bump.
   214	- **Provider JSON non-compliance.** `TranslationChunkContract.decode` + per-segment fallback — never drops a paragraph.
   215	- **DataStore per-book key growth.** One Preferences entry per book keyed by fingerprint; scales like `ReaderSettingsStore`/`AiProviderStore`.
   216	- **#136 dependency risk.** #131's DONE flip + the "Set up" route + `AiProviderStore` in `AppContainer` all block on #136. #131's pipeline/UI (WI-0..WI-8 except WI-4b's DI) build ahead; WI-4b + WI-9 gate on #136.
   217	
   218	## 7. Backward compat
   219	
   220	- **Room migration additive (round-2 M4).** New `chapter_translations` (FK CASCADE, `lookupKey` PK, `sourceParagraphCount`). Existing rows untouched. Version allocated current→next at the merge slot; against this checkout **8→9, `MIGRATION_8_9`** appended after `MIGRATION_7_8`; migration test extended from **v8** guards it.
   221	- **Reader unchanged when bilingual off** — the TXT/MD `items(chunkCount)` loop is byte-identical unless `enabled && format∈{txt,md} && translation present` (bilingual content is a pure segment-range overlay). `ReaderBottomChrome` is not modified. EPUB render adapter is inert unless bilingual is on.
   222	- **#118 AI provider files unchanged** — the prefetcher/readiness are new consumers. **`AiProviderStore` into `AppContainer` is #136's change, not #131's**; #131's DI WI (WI-4b) wires the bilingual services around it.
   223	- **Backup contract already compatible** — `PerBookSettingsOverride.bilingualEnabled/TargetLanguage/Granularity` exist (verified; no `bilingualStyle`), and there is no translation-cache backup section (the cache is device-local, re-derivable). #131 writes the three fields locally; backup collect/restore is a small additive follow-up (no contract change), out of v1 scope; until then bilingual config is device-local.
   224	- **#132/#134/#129 landed** — the top-chrome pill mount + More-menu toggle + `TxtReaderActivity` edit land on VERIFIED surfaces (rule 48 one-writer-per-file is satisfied; #129 is merged).
   225	
   226	## Design gates (rule 51 — for `needs-design` filing)
   227	
   228	1. **"Bilingual mode" setup sheet with BOTH Style AND Granularity in one Android sheet** — `vreader-bilingual.jsx` depicts Granularity (no Style); `vreader-ai-android.jsx` depicts Style (no Granularity); no committed bundle shows both together. v1 reproduces the granularity-only `vreader-bilingual.jsx` sheet and **DROPS Style (user descope decision — §3/H3)**. If Style is wanted as an Android user control, file `Design needed: bilingual setup sheet (Style + Granularity) for feature #131`. **This is the one open design gate for #131.** The box-D Style parity gap is tracked by the WI-9 follow-up checklist amendment.
   229	2. **#136 dependency (not a #131 design gate)** — the setup sheet's "Set up"/"Change…" affordance routes to #136's AI-provider-entry sheet. #136 owns the sheet + its production reachability + `AiProviderStore` in `AppContainer`; #131 wires the affordance and consumes the store. #131 does not invent the AI-config sheet (rule 51).
   230	
   231	## Revision history
   232	
   233	- v1 (2026-07-10): Gate-1 draft (Plan agent). Gate-2 Codex audit pending.
   234	- v2 (2026-07-11): Gate-2 round-1 REDESIGN resolved — Readium-feasibility corrected, entry-point rebased on box F, setup-sheet design-gated, DI/cache/concurrency fixed.
   235	- v3 (2026-07-12) — Gate-2 round-2 findings resolved: TXT/MD document-global segment model (H1); EPUB translatePreSegmented + count-keyed cache + direct-block prefetch (H2); #136 AI-provider-reachability spun out as a hard dependency (filed GH #1976) + Style descoped v1 (H3, user decision); WI-0 go/no-go + navigator-race contract (M1); EPUB DOM-injection adapter not Compose body (M2); DI/factory WI reordered (M3); Room 8→9 MIGRATION_8_9 (M4); deps/WI-count corrected (L1/L2). Awaiting Gate-2 round-3 audit.
   236	
   237	## Notes on assumptions not fully confirmed against live code
   238	
   239	- The exact iOS `TranslationUnitID.Kind` case names for the TXT/MD variants — the Android `Kind` names (`txtDocSegmentWindow`/`mdDocSegmentWindow`) describe the real document-global unit. Only the `storageKey` string format is load-bearing for the cache contract, and that is preserved.
   240	- The unit-window size constant for TXT/MD sub-batching is left to build time (it does not affect the 1:1 segment↔render contract, only cache-row granularity/prefetch scope).
    80	import com.vreader.app.search.InBookSearchSheet
    81	import com.vreader.app.search.InBookSearchViewModel
    82	import kotlinx.coroutines.flow.MutableStateFlow
    83	import kotlinx.coroutines.flow.debounce
    84	import kotlinx.coroutines.flow.drop
    85	import kotlinx.coroutines.launch
    86	import org.json.JSONObject
    87	import org.readium.r2.navigator.epub.EpubNavigatorFactory
    88	import org.readium.r2.navigator.epub.EpubNavigatorFragment
    89	import org.readium.r2.navigator.epub.EpubPreferences
    90	import org.readium.r2.shared.ExperimentalReadiumApi
    91	import org.readium.r2.shared.publication.Locator
    92	import org.readium.r2.shared.publication.Publication
    93	import org.readium.r2.shared.util.AbsoluteUrl
    94	import java.time.ZoneId
    95	import java.time.format.DateTimeFormatter
    96	import java.util.Locale
    97	import java.io.File
    98	import vreader.contracts.Locator as CanonicalLocator
    99	
   100	@OptIn(ExperimentalReadiumApi::class)
   101	class ReaderActivity : AppCompatActivity() {
   102	
   103	    private val container get() = (application as VReaderApp).container
   104	    private val repository: LibraryRepository get() = container.repository
   105	    private val bridge = ReadiumLocatorBridge()
   106	
   107	    private val annotations: AnnotationsRepository get() = container.annotationsRepository
   108	
   109	    private var containerId: Int = 0
   110	    private var navigator: EpubNavigatorFragment? = null
   111	    private var publication: Publication? = null   // host-owned; closed in onDestroy
   112	    private var book: Book? = null
   113	
   114	    // feature #132 WI-7-EPUB — the persistent chrome model the top/bottom bands + sheet layer collect,
   115	    // populated as the async open completes and updated on every position change. The active Display
   116	    // theme (also read by the chrome bands' colors) is mirrored so the ComposeViews can render immediately.
   117	    private val chromeModel = MutableStateFlow(ReaderChromeModel())
   118	    private val chromeTheme = mutableStateOf(ReaderTheme.Paper)
   119	    // The hoisted top/bottom-visibility + open-sheet state (a Compose snapshot state, so the ComposeViews
   120	    // recompose on change). Kept in-memory for the reader's lifetime (rotation always starts fresh — see
   195	            publication = pub
   196	
   197	            val initial = computeInitialLocator(key)
   198	            // feature #129 WI-5 — open with the user's stored Display settings already applied (so a
   199	            // non-default theme/typography renders on first paint, no flash), keeping the scroll layout.
   200	            val initialPrefs = EpubPreferences(scroll = true) + container.readerSettingsStore.current().toEpubPreferences()
   201	            val factory = EpubNavigatorFactory(pub)
   202	            // Attach only when the activity is at least STARTED AND its fragment state
   203	            // isn't already saved — `commitNow` against a state-saved manager throws
   204	            // IllegalStateException. If we can't commit, abort (the publication is
   205	            // released in onDestroy; the activity recreates fresh on return).
   206	            val nav: EpubNavigatorFragment? = withStarted {
   207	                if (supportFragmentManager.isStateSaved) return@withStarted null
   208	                supportFragmentManager.fragmentFactory = factory.createFragmentFactory(
   209	                    initialLocator = initial,
   210	                    initialPreferences = initialPrefs,
   211	                    listener = object : EpubNavigatorFragment.Listener {
   212	                        override fun onExternalLinkActivated(url: AbsoluteUrl) {}
   213	                    },
   214	                    configuration = EpubNavigatorFragment.Configuration().apply {
   215	                        // intercept the system selection menu → show the designed floating popover instead.
   216	                        selectionActionModeCallback = selectionCallback()
   217	                    },
   218	                )
   219	                supportFragmentManager.commitNow {
   220	                    add(containerId, EpubNavigatorFragment::class.java, Bundle(), READER_TAG)
   221	                }
   222	                supportFragmentManager.findFragmentByTag(READER_TAG) as EpubNavigatorFragment
   223	            }
   224	            if (nav == null) { finish(); return@launch }
   225	            navigator = nav
   226	            val controller = ReaderHighlightController(nav)
   227	            highlightController = controller
   228	            repository.markOpened(key, System.currentTimeMillis())
   229	            // feature #132 WI-7-EPUB — build the chrome model once the publication is open: the flattened
   230	            // TOC (each entry retaining its native Readium locator for the jump), the Notes snapshot, and
   231	            // the initial highlighted-chapter index for the current reading position.
   232	            populateChromeModel(pub, loaded, nav)
   233	            // feature #135 WI-7 — build the bookmark TOC index ONCE from the flattened TOC (WI-4 design),
   234	            // then observe this book's bookmarks (project → rows) + keep the top-bar presence in sync.
   235	            bookmarkTocIndex = BookmarkTocIndex.build(chromeModel.value.tocEntries)
   445	        super.onStop()
   446	        // Synchronous-intent flush: the last movement inside the debounce window would
   447	        // otherwise be lost on back/home/rotation. Launched on the process scope so it
   448	        // completes even as this activity is torn down.
   449	        val nav = navigator ?: return
   450	        val current = book ?: return
   451	        val locator = nav.currentLocator.value
   452	        container.appScope.launch { persist(locator, current) }
   453	    }
   454	
   455	    override fun onDestroy() {
   456	        super.onDestroy()
   457	        // feature #133 WI-11 — dispose the in-book search VM (its onCleared disposes the live Readium
   458	        // SearchIterator via closeAllEpubCursors) BEFORE releasing the publication it searches over — the
   459	        // iterator is a view over the publication, so it must go first (no leak, no use-after-close).
   460	        inBookSearchVm?.onCleared()
   461	        inBookSearchVm = null
   462	        // Host owns the Publication (Readium's navigator does not close it). The
   463	        // fragment is torn down by super.onDestroy() above, then we release it.
   464	        publication?.close()
   465	        publication = null
   466	    }
   467	
   468	    /** Restore precisely from the saved Readium locator; canonical-fallback (progression) is a follow-on. */
   469	    private suspend fun computeInitialLocator(key: String): Locator? {
   470	        val saved = repository.loadPosition(key) ?: return null
   482	    private fun observeDisplaySettings(nav: EpubNavigatorFragment) {
   483	        lifecycleScope.launch {
   484	            container.readerSettingsStore.settings.collect { settings ->
   485	                runCatching { nav.submitPreferences(EpubPreferences(scroll = true) + settings.toEpubPreferences()) }
   486	                    .onFailure { android.util.Log.w("ReaderActivity", "submitPreferences failed; display change not applied", it) }
   487	            }
   488	        }
   489	    }
   490	
   491	    /** Save the current Readium position as a VReaderLocator envelope (debounced steady-state) AND keep the
   492	     *  chrome model's highlighted-chapter index in sync as the reader scrolls (prompt, un-debounced — the
   493	     *  Contents-sheet highlight should track the live position, and tocIndexFor is a cheap pure map). */
   494	    private fun observePosition(nav: EpubNavigatorFragment, current: Book) {
   495	        lifecycleScope.launch {
   496	            nav.currentLocator
   497	                .drop(1)            // skip the initial emission
   498	                .debounce(1_000)
   499	                .collect { locator -> persist(locator, current) }
   500	        }
   501	        lifecycleScope.launch {
   502	            nav.currentLocator.collect { locator ->
   503	                val model = chromeModel.value
   504	                val index = tocIndexFor(locator.href.toString(), locator.locations.progression, tocPositions(model.tocEntries))
   505	                if (index != model.currentTocIndex) {
   506	                    chromeModel.value = chromeModel.value.copy(currentTocIndex = index)
   507	                }
   508	                chromeProgress.value = (locator.locations.totalProgression ?: 0.0).toFloat().coerceIn(0f, 1f)
   509	                // feature #135 WI-7 — map the live Readium position to canonical (the toggle's equality
   510	                // basis) + refresh the top-bar filled/outline presence as the reader scrolls.
   511	                val canonical = canonicalForCurrent(locator, current)
   512	                currentCanonical = canonical
   513	                isCurrentBookmarked.value = canonical != null &&
   514	                    runCatching { annotations.isBookmarked(current.fingerprintKey, canonical) }.getOrDefault(false)
   515	            }
   103	    // feature #116 WI-5 — saved WebDAV server profiles persist in DataStore (URL/user/wifiOnly,
   104	    // password ciphertext); chosen over the deprecated EncryptedSharedPreferences (Gate-2 Low-2).
   105	    implementation("androidx.datastore:datastore-preferences:1.1.1")
   106	
   107	    // feature #106 WI-5/WI-9 — Readium-Kotlin 3.3.0 EPUB open + render. shared +
   108	    // streamer open the publication (WI-5); navigator renders it in the reader host
   109	    // (WI-9). Pinned to the Spike-B-verified set; the navigator needs appcompat +
   110	    // fragment (its EpubNavigatorFragment is an AppCompat-themed Fragment).
   111	    val readium = "3.3.0"
   112	    implementation("org.readium.kotlin-toolkit:readium-shared:$readium")
   113	    implementation("org.readium.kotlin-toolkit:readium-streamer:$readium")
   114	    implementation("org.readium.kotlin-toolkit:readium-navigator:$readium")
   115	    implementation("androidx.appcompat:appcompat:1.7.1")
   116	    implementation("androidx.fragment:fragment-ktx:1.8.9")
   117	

exec
/bin/zsh -lc "nl -ba dev-docs/plans/20260710-feature-131-android-bilingual-interlinear.md | sed -n '117,192p'" in /Users/ll/workspace/vreader
 succeeded in 0ms:
   117	## 3. Prior art / project precedent / rejected alternatives
   118	
   119	### The render-host decision (settled v2, CONFIRMED round-2)
   120	
   121	**How iOS does interlinear:** iOS renders EPUB/AZW3 in a WKWebView it fully controls. `EPUBBilingualOrchestrator` injects JS that (1) enumerates leaf blocks posting `[{bid,text}]` to Swift, (2) after translation injects a translation node after each block. TXT/MD render in a text path where the renderer interleaves translation runs. The mechanism = **the app inserts translation nodes between source nodes.**
   122	
   123	**Android EPUB feasibility (round-2 re-verified):** `javap`/the transformed API JAR on the resolved Readium 3.3.0 AAR expose public `evaluateJavascript(String, Continuation<? super String>)`, `getCurrentLocator()`, `firstVisibleElementLocator(...)`, `submitPreferences(...)`; `ReaderActivity.navigator: EpubNavigatorFragment?` holds the concrete fragment. So EPUB interlinear via JS injection is feasible with the public API — **no Readium fork.** The audit CONFIRMED this correction; it is not reopened.
   124	
   125	**WI-0 — Readium bilingual spike (gates WI-7b; round-2 M1 rewrote its contract into enforceable go/no-go thresholds):** a throwaway harness that, against a real EPUB on the emulator, must PROVE (each is a pass/no-go criterion):
   126	
   127	- **(a) Enumeration is deterministic + idempotent, with stable node IDs.** Enumerating the same current resource twice yields the same block IDs in the same order. Repeated `apply` produces **no duplicate injected nodes** (idempotent replacement).
   128	- **(b) Clear wins over every older inject.** Under a rapid enable→disable / navigate sequence, a late-arriving inject issued before a `clear` must NOT survive the clear — enforced by the serialization mechanism below (a late inject checks the session token and no-ops).
   129	- **(c) Recreation restores from cache** for every case: href away/back, same-href `submitPreferences` reflow, internal page-fragment recreation (the WebView pager recreates fragments), and activity recreation — each must re-apply the interlinear from the disk cache (via `cachedDirect(expectedCount)`, zero provider calls) with **an identified PRODUCTION re-apply signal** (a concrete navigator/lifecycle callback or `currentLocator`/fragment-lifecycle hook) for each case.
   130	- **(d) Locator / visible-source preservation across injection**, with a stated permissible delta (injecting content may shift pagination by ≤ a stated bound; the reader's saved position must map back to the same source block).
   131	- **(e) The enumerated block count vs the segmenter count** is measured; if they diverge (iOS #268), the **direct-block path** (`prefetchDirect` → `translatePreSegmented`, cached by enumerate count, restored by `cachedDirect(expectedCount)` — H2) is the recovery, proven end-to-end in the spike.
   132	
   133	**Race contract (M1):** WI-0 specifies **either a single actor/mutex OR a monotonic navigator-session token**; every suspended JS/AI call is followed by a token/mutex check; cancellation/clear runs BEFORE publication teardown. **If WI-0 cannot find a deterministic production re-apply signal for a recreation case (c), that is an explicit NO-GO:** EPUB drops to a tracked follow-up and box D ships **TXT/MD-only** — with the honest reason (a specific spike finding), never the false "requires a fork."
   134	
   135	**Rejected alternatives:**
   136	1. **Readium interlinear via decorations only** — REJECTED (decorations style existing text; they cannot insert translation paragraphs). `evaluateJavascript` makes injection possible, so EPUB uses the JS seam.
   137	2. **Forking Readium** — REJECTED + unnecessary (public `evaluateJavascript` seam exists).
   138	3. **AZW3 foliate host first** — REJECTED for v1 (deferred, not dead; touches the security-sensitive #126 bridge).
   139	4. **Eager whole-book pre-translation** — REJECTED (cost/latency). Lazily prefetch current+next + cache — port iOS.
   140	5. **One `BilingualInterlinearBody` per chunk (v2)** — REJECTED (round-2 H1): a chunk is not a segment. Replaced by document-global segment ranges (§2).
   141	6. **A Compose body as the EPUB render surface (v2)** — REJECTED (round-2 M2): Compose cannot render inside Readium's WebView. Replaced by `EpubBilingualJs` DOM injection sharing only the `BilingualRenderState` DTO.
   142	
   143	### The setup-sheet resolution (rule 51) + Style descope (round-2 H3, USER DECISION)
   144	
   145	There are **two committed, differently-shaped** `BilingualSetupSheet`s:
   146	- `vreader-bilingual.jsx` → **language grid + Granularity + preview strip + Translation-engine strip (Set up/Change) + Cancel/Translate**. **No Style, no provider/model card, no term-overrides, no cost.**
   147	- `vreader-ai-android.jsx` → **Languages (From/To) + Provider card + Style (Literal/Natural/Literary) + Keep-term-overrides toggle + cost footer.** **No language grid, no Granularity, no preview.**
   148	
   149	**Resolution:** this plan reproduces the **`vreader-bilingual.jsx` sheet EXACTLY** as the authoritative Android-native bilingual sheet. **Style is DESCOPED for v1** (user decision): #131 keeps provider/model/**granularity**, DROPS the bilingual "Style" control. Consequently the store/VM carry no `style`, the chunk contract has no `style` param, and the cache key's `promptVersion` has no `s=` component. Keep rule 51: only implement the designed surface.
   150	
   151	**Box-D parity note (H3 — do NOT claim full box-D parity):** the box-D parity checklist lists provider/model/**style**. Because Style is descoped v1, **WI-9 flips box D to done ONLY for provider/model/granularity + a descope note** — it does NOT claim full box-D parity. A **follow-up tracker/checklist amendment records the Style descope** (the plan does not silently drop it). If Style is later wanted on Android as a user control, that needs an **updated committed design** (a single sheet showing BOTH Style AND Granularity is not depicted anywhere — the one open design gate below).
   152	
   153	### Other precedents applied
   154	
   155	- **#118 provider seam**: reuse `AiProviderStore.snapshot()` (`snapshot.active`) + `store.apiKey(profile)` + `AiProviderFactory.create` (default of an injected factory param) + `AiClient.chat`. #118's AI files are unchanged; **#136** wires `AiProviderStore` into `AppContainer`; #131's DI WI wires the bilingual services.
   156	- **Room additive-migration pattern** (#122/#123/#127/#128/#135): version bump + `MIGRATION_n_(n+1)` appended to `ALL_MIGRATIONS` + exact-DDL + `VReaderDatabaseMigrationTest` PRAGMA guard. `@PrimaryKey` + `@Upsert` is the project's DAO pattern (`BookDao`). Baseline is **v8** (M4).
   157	- **DataStore JSON-in-Preferences** for `PerBookBilingualStore` (the `ReaderSettingsStore`/`AiProviderStore` pattern).
   158	- **Pure-logic port**: iOS `ChapterSegmenter`/`ChapterTranslationChunker`/`TranslationChunkContract`/`ChapterTranslationService.translatePreSegmented`/`ChapterTranslationPrefetcher.translatedSegmentsDirect`+`cachedSegmentsDirect` are pure/heavily-unit-tested — direct Kotlin ports with the same test vectors (all verified to exist).
   159	- **Entry point via #132/#134 (VERIFIED)**: the More-menu bilingual toggle (`MoreActionId.BILINGUAL` reserved; `MoreRow.Toggle` carries `on`/`onToggle`) + top-chrome pill are the landed integration points; #131 mounts the pill + wires the toggle (§4).
   160	
   161	## 4. Work-item sequencing
   162	
   163	**11 WIs/PRs (round-2 L2):** WI-0 (spike), WI-1..WI-4a (foundation/service), **WI-4b (shared DI/factory)**, WI-5, WI-6, WI-7a (Compose UI), **WI-7b (conditional EPUB render adapter — dropped if WI-0 = no-go)**, WI-8 (TXT/MD host integration), WI-9 (entry wiring + acceptance). Each WI = one PR. Build order (round-2 M3): **foundation/cache → service/direct-block APIs → shared DI/factory → VM state/prefetch → host-specific renderers (TXT/MD + EPUB) → entry wiring.**
   164	
   165	**Dependency notes (round-2 L1 — exact landed integration points):**
   166	- **`Deps: [feat:#136, feat:#132, feat:#134]`.** **#132 (top chrome) and #134 (More menu) are VERIFIED — dependencies satisfied** (the top-chrome host + `MoreActionId.BILINGUAL` toggle row are landed). **#129 (TXT/MD reader) is VERIFIED** — `TxtReaderActivity` is a straight edit, not a blocker. **#136 (AI provider setup made production-reachable) is the NEW hard blocker** for #131's entry-wiring (the "Set up"/"Change…" route) AND the DONE flip; it provides `AiProviderStore` in `AppContainer` and the reachable AI-config sheet. The live More model already reserves `MoreActionId.BILINGUAL` (verified).
   167	- The pipeline + setup sheet + interlinear render (WI-0..WI-7) are built ahead; only the **entry wiring (WI-9)** and the **DI WI (WI-4b, for `AiProviderStore` in `AppContainer`)** wait on #136. The pill mount (WI-9) targets #132's VERIFIED top chrome; the toggle wire (WI-9) targets #134's VERIFIED More menu.
   168	
   169	**WI-0 (spike): Readium EPUB bilingual injection — with enforceable go/no-go + race contract (M1).** The harness + criteria (a)–(e) and the race contract in §3. Output: a **go/no-go on EPUB-in-v1** (no-go if no deterministic production re-apply signal — box D ships TXT/MD-only, tracked) + the concrete `EpubChapterTextProvider` / `EpubBilingualJs` / `EpubBilingualController` surfaces. Deps: none (uses the existing #106 Readium host). Not TDD-gated (throwaway spike); its findings feed WI-7b.
   170	
   171	**WI-1 (foundational): value types + pure segmentation/chunk/contract.** `TranslationUnitId` (document-global TXT/MD kinds — H1), `TranslationGranularity`, `BilingualLanguages`, **`ChapterSegmenter` (with `paragraphRanges`/`sentenceRanges` — H1)**, `TranslationChunker`, `TranslationChunkContract` (no `style` — H3), `ChapterTranslationError`. Pure; ported iOS vectors. Deps: none.
   172	
   173	**WI-2 (foundational): Room translation cache.** `ChapterTranslationEntity` (PK = `lookupKey`, `sourceParagraphCount` column) + `Dao` (`@Upsert`) + `ChapterTranslationStore`; `VReaderDatabase` **8→9 `MIGRATION_8_9`** appended after `MIGRATION_7_8` (M4). Robolectric migration round-trip from **v8** + full-chain + upsert/get/delete-by-lookupKey + FK-CASCADE + exact-DDL guard. Deps: none.
   174	
   175	**WI-3 (foundational): `ChapterTranslationService`** against a fake `AiClient`. `cachedTranslation` (both overloads incl. the **`expectedSegmentCount` divergence restore — H2**) + `translate` + **`translatePreSegmented` (H2: chunk, per-chunk degrade, cancellation, cache-write with the enumerate count on full success only)**. Deps: **WI-1, WI-2**. Tests: cache hit → zero client calls; miss → translate + write; decode fail → per-segment fallback; one-chunk fail → source-only that chunk (others translated, NOT cached); all-chunks fail → throw; cancellation → `Cancelled` (no write); `AiError` mapping incl. `Config`/`InsecureUrl` → `ProviderFailed`; **`translatePreSegmented` full-success caches under the enumerate count; partial degrade NOT cached; all-fail throws; `cachedTranslation(expectedSegmentCount)` returns on stored-count match, null on mismatch, needs no provider**.
   176	
   177	**WI-4a (foundational): `ChapterTextProvider` (TXT/MD) + `ChapterTranslationPrefetcher` + `BilingualAiReadiness`.** `TxtChapterTextProvider` builds the **document-global segment ranges once (H1)**, groups into windows, resolves `unitContaining(charOffsetUTF16)` via segment-start binary search, `sourceSegments(unit)`. Prefetcher: `prefetch` + **`prefetchDirect` + `cachedDirect` (zero-provider cache restore — H2)**; resolves active profile from `snapshot()`, decrypts snapshot-consistent, builds client via the **injected factory param** (default `AiProviderFactory::create`), constructs `AiRequest` from the profile. Readiness = active profile with non-empty decrypted key; **cipher failure → not-ready, never a crash.** Fake store + fake factory. Deps: **WI-1, WI-3**. Tests: unit resolution + clamp + empty; **paragraph spanning a chunk boundary → one segment/one unit; multiple paragraphs in one chunk → distinct segments; a >4000-char paragraph → one segment across chunks; CR/LF/CRLF; MD markers; locator→unit mapping; source-byte parity while disabled**; cache-hit-no-profile still returns (#306); no-profile miss → `ProviderFailed`; `prefetchDirect` 1:1; `cachedDirect` restores with zero provider calls; readiness true/false; cipher-throw → readiness false (no crash).
   178	
   179	**WI-4b (foundational — shared DI/factory, round-2 M3): AppContainer bilingual services.** Extract the DI/factory wiring into this EARLIER shared WI: `AppContainer` provides `ChapterTranslationStore`, `PerBookBilingualStore`, `ChapterTranslationService`, `ChapterTranslationPrefetcher`, and the `BilingualViewModel` factory — **consuming `AiProviderStore` from `AppContainer` (provided by #136).** Both host integrations (WI-7b, WI-8) depend on this. Deps: **WI-4a, feat:#136** (for `AiProviderStore` in `AppContainer`). Tests: container resolves the bilingual graph; the prefetcher's injected factory defaults to `AiProviderFactory::create`.
   180	
   181	**WI-5 (behavioral): `PerBookBilingualStore` + `BilingualViewModel` state core.** Store per book (enabled/targetLanguage/granularity — no style); VM setters (persist + first-enable `needsSetupSheet`), language/granularity change clears cache-shaped state + bumps generation. Turbine tests: first-enable raises sheet; re-enable persisted does not; disable clears; language change resets; granularity change resets + re-keys; round-trip through store; no style field. Deps: **WI-1** (+ store).
   182	
   183	**WI-6 (behavioral): VM prefetch trigger + generation/cancellation.** `onPositionChanged(charOffsetUTF16)` derives current unit, dedupes, prefetches current+next; a **monotonic position-request sequence** checked after every suspension; **per-unit generation tokens**; a **captured language/granularity/provider snapshot per launch**; generation bumps on disable/language/granularity/unit-change discard stale; `CancellationException` handled BEFORE generic error mapping; `Offline`→`unavailableUnits`; transient failure leaves unit unfetched + clears anchor to retry; `retryUnit`. Fake prefetcher. Deps: **WI-4a, WI-4b, WI-5**. Tests: current+next on unit change; same-unit no-op; cancel-mid discards stale; offline→unavailable; failure→retry-able; `retryUnit` re-fetches; granularity change cancels + re-fetches under the new key.
   184	
   185	**WI-7a (behavioral): Compose UI — setup sheet + interlinear body (TXT/MD) + pill.** Reproduce `vreader-bilingual.jsx` (setup sheet: language grid / granularity / preview / engine strip configured+unconfigured; body: translated / loading N%+dimmed / error+Retry / offline source-only; pill). Consumes the **host-neutral `BilingualRenderState` DTO (M2)**. Light+dark. Compose UI tests each state. Deps: **WI-5** (state shape). NO Style control; the unconfigured "Set up" CTA renders and (in WI-9) routes to #136's sheet.
   186	
   187	**WI-7b (behavioral, CONDITIONAL — only if WI-0 = go): EPUB render adapter (DOM injection, NOT Compose — round-2 M2).** `EpubBilingualJs` (enum/inject/clear JS builders, CSP-safe escaping) + `EpubBilingualController` (the serialization actor / session token — M1) + `EpubChapterTextProvider`, wired into `ReaderActivity`, driving DOM from the **shared `BilingualRenderState` DTO**. **Depends on WI-6 (VM prefetch) and WI-4b (DI) — the M3 fix; the WI-7a UI dependency is REMOVED except for the shared `BilingualRenderState`/value types.** Uses `prefetchDirect`/`cachedDirect` for the count-divergence path (H2). Connected test on a real EPUB (seeded cache): enable → interlinear injects; disable → nodes cleared; reflow/href-change/fragment-recreation/activity-recreation → re-applies from cache (zero provider calls); count-divergence handled (direct path). Unit tests: JS escaping/CSP-safe text insertion, RTL/CJK style, empty translations, loading cleanup, idempotent replacement, source-only fallback. Deps: **WI-0, WI-3, WI-4a, WI-4b, WI-6, (shared types from WI-7a)**. (If WI-0 = no-go, this WI is dropped and box D ships TXT/MD-only, tracked.)
   188	
   189	**WI-8 (behavioral): `TxtReaderActivity` integration.** Wire VM into the `items(chunkCount)` loop **keyed by segment-range overlap (H1)** + position-change (`charOffsetUTF16`) + setup-sheet. `originalFormat`-gated (TXT/MD). Uses WI-4b's DI. **#129 is VERIFIED — straight edit.** Connected test (fake `AiClient` seam): enable → setup → confirm → interlinear from seeded cache; disable → source-only byte-parity; reopen persists enabled + renders from cache with zero client calls; paragraph-spanning-chunk-boundary renders one translation. Deps: **WI-6, WI-7a, WI-4b**.
   190	
   191	**WI-9 (behavioral): entry wiring + acceptance.** Mount `BilingualPill` in **#132's VERIFIED top chrome**; wire the **#134 VERIFIED More-menu `MoreActionId.BILINGUAL` toggle** (`MoreRow.Toggle` `on`/`onToggle`) to the VM; **wire the setup sheet's "Set up"/"Change…" affordance → #136's AI-provider-entry sheet.** Full acceptance pass across EPUB (if WI-7b landed) + TXT/MD, including the fresh-user path `unconfigured → Set up (→ #136 sheet) → add provider → return → enable → translate` (the #136-owned reachability verified jointly). **Flip box D to done ONLY for provider/model/granularity + the Style-descope note (H3); file the follow-up checklist amendment; do NOT claim full box-D parity, do NOT flip DONE until #136 is landed.** Update `docs/architecture.md` (bilingual pipeline + the new `chapter_translations` schema + bilingual services in `AppContainer`). → DONE. Deps: **WI-8, WI-7b (if go), feat:#136, feat:#132, feat:#134**.
   192	

exec
/bin/zsh -lc "rg -n \"\\| 131 \\||\\| 136 \\||Feature #136|#136\" docs/features.md dev-docs/plans/20260712-feature-136-android-ai-provider-reachable.md android/app/src/main/kotlin/com/vreader/app/VReaderApp.kt android/app/src/main/kotlin/com/vreader/app/MainActivity.kt | head -120 && nl -ba android/app/src/main/kotlin/com/vreader/app/VReaderApp.kt | sed -n '1,125p' && nl -ba android/app/src/main/kotlin/com/vreader/app/MainActivity.kt | sed -n '1,150p'" in /Users/ll/workspace/vreader
 succeeded in 0ms:
dev-docs/plans/20260712-feature-136-android-ai-provider-reachable.md:1:# Gate-1 Plan — Feature #136: AI provider setup made production-reachable (Android)
dev-docs/plans/20260712-feature-136-android-ai-provider-reachable.md:13:**#136 makes the already-designed, already-built AI provider config production-reachable and independently verifiable**, from a designed in-reader entry that does not depend on #131.
dev-docs/plans/20260712-feature-136-android-ai-provider-reachable.md:19:Two designed reader entries exist; #136 uses the one that is **independent of #131**:
dev-docs/plans/20260712-feature-136-android-ai-provider-reachable.md:23:This entry is reachable by a fresh user (open any book → More → "Configure AI provider first") with **no bilingual wiring present** — which is precisely what independent-verifiability requires. #131 will later ADD the *enabled* Bilingual toggle + its own bilingual-Set-up→here route; #136 owns only the `aiUnavailable`/`configure-ai` path.
dev-docs/plans/20260712-feature-136-android-ai-provider-reachable.md:44:- **Provider CRUD internals** — `AiProviderStore.upsert/delete/setActive/apiKey`, `AiSettingsViewModel.test/save`, `AiProviderFactory`, the provider clients, `SseEventReader`, `AiProviderKind`. All shipped and tested by #118; #136 constructs and reaches them, never re-implements them.
dev-docs/plans/20260712-feature-136-android-ai-provider-reachable.md:46:- **The AI-readiness sheet (flag + consent gates)** — `reader-ai-readiness.md`'s `ReaderAIReadinessSheet` (master AI toggle + consent ledger) is **design-landed but implementation-deferred** ("do NOT build without go-ahead"). #136 delivers the provider-list reachability only; the flag/consent capstone is a separate feature.
dev-docs/plans/20260712-feature-136-android-ai-provider-reachable.md:47:- **AI chat panel wiring** — `AiChatPanel`/`AiChatViewModel` are ALSO unwired, but chat's reader entry is #131/a chat feature's surface, not #136.
dev-docs/plans/20260712-feature-136-android-ai-provider-reachable.md:49:- **A Library-level Settings tree / More pill** (`LibraryScreen.kt:95`) — not built; #136 deliberately does NOT depend on it (see §3 rejected alt).
dev-docs/plans/20260712-feature-136-android-ai-provider-reachable.md:55:- `design-notes/reader-ai-provider-entry.md` — Variant **A** (CANONICAL): "a scoped, in-reader 'AI Providers' sheet … reusing the canonical `AIProviderEditSheet`", chosen over B (deep-link the whole SettingsView) and C (inline mini-form). Its stated win: "Keeps the reader context … the user never sees Cloud & Sync, OPDS, TTS." #136 implements A's Android analog.
dev-docs/plans/20260712-feature-136-android-ai-provider-reachable.md:62:- **#129/#132/#134/#135** wired every reader-chrome entry through the exact seams #136 reuses: the `readerMoreRows` assembler, `ReaderChromeState`/`ReaderSheet` + its saver, the `EpubReaderSheets` open-only sheet layer, and the additive-nullable-param "one-writer-coordinate" convention. #134 added Details/Share rows; #136 adds the `configure-ai` row by the same contract.
dev-docs/plans/20260712-feature-136-android-ai-provider-reachable.md:67:2. **Route only from #131's bilingual Set-up.** Rejected by independent-verifiability: it would couple #136 to #131 (still `PLANNED`) and make AI config unreachable until bilingual ships. The `aiUnavailable`/`configure-ai` More-row is reachable with zero bilingual wiring.
dev-docs/plans/20260712-feature-136-android-ai-provider-reachable.md:102:- **AI-key security surface (#118).** Mitigation: #136 constructs `AiProviderStore` with `KeystoreSecretCipher` under `noBackupFilesDir` (the #116 contract) and touches NO CRUD/crypto path. Keys stay device-local; no `contracts/` change.
dev-docs/plans/20260712-feature-136-android-ai-provider-reachable.md:110:- **Older reader-chrome state tokens.** Unknown-token → `None` means a persisted pre-#136 `ReaderChromeState` restores cleanly.
dev-docs/plans/20260712-feature-136-android-ai-provider-reachable.md:115:**#136 is a HARD dependency of #131.** #131's fresh-user AI-config path + its Gate-5 acceptance route both require a reachable AI provider config to land on; that destination is delivered by #136. #131 must not re-implement or inline provider config — it consumes #136's `ReaderSheet.AiProviders` sheet. **#131's bilingual-Set-up → #136 route (the enabled Bilingual `MoreRow.Toggle` + its "Set up"→AI-Providers navigation) is #131's OWN WI, not #136's** — #136 delivers only the independent `aiUnavailable`/`configure-ai` More-menu entry, so AI config is reachable + verifiable before #131 exists.
docs/features.md:133:| 79 | AI provider editor — pre-filled Base URL / Model should behave as placeholders that clear on focus (currently seeded as real editable defaults the user must delete; `AIProviderEditSheet.swift:111-112`). | Settings/AI | Low | VERIFIED | Filed 2026-06-02 via /triage; needs-design #1363 **DESIGN LANDED** (`design-notes/ai-provider-editor-fields.md`, Variant A). Gate-2 Codex audit 3 rounds, converged 3→1→0. **DONE 2026-06-03** (Variant A, add-mode-only): add-mode binds Base URL/Model empty; pure statics `effectiveBaseURLText`/`effectiveModel` (add-mode blank → kind default; edit-mode raw) drive `canSave`/`save()`/`runTest()` + the live `baseURLError` onChange; `placeholderBaseURL`/`placeholderModel` (add-mode → kind default; edit-mode → "") drive the field placeholders; a muted "Default" tag shows beside an empty add-mode field. Edit-mode keeps raw validate/persist/test + no placeholder/tag. **Gate-4 Codex audit** (`/tmp/feat79-implaudit.txt`, 1 round, ship-as-is): Medium — `effectiveModel` trimmed in both modes → would normalize an edit-mode whitespace-padded model on save; fixed (edit-mode returns raw) + regression test. Tests: 7 helper/effective-value tests in `AISettingsViewModelEditorTests`. Audit log `.claude/codex-audits/feat-feature-79-wi1-placeholders-audit.md`. **VERIFIED 2026-06-03** — Gate-5b device pass (v3.48.0, `7b1d471c`): the Add Provider editor shows empty Base URL/Model + a "Default" tag + the kind-default muted placeholder (criteria 1/6 device-verified); blank→default save + edit-mode-raw are unit-pinned (7 tests). Evidence `dev-docs/verification/feature-79-20260603.md`. Sibling #80 (test-before-save) separate. GH: #1436. |
docs/features.md:184:| 131| **Android bilingual interlinear reading** (parity box D) — per-book toggle renders each source paragraph followed by an AI-backed translation (muted, accent border), cached to disk; Android parity of iOS #56/#100, building on the #118 AI foundation. | android/app/.../bilingual/* + reader hosts + ReaderBottomChrome/More-menu entry | Medium | PLANNED | Deps:[feat:#136, feat:#132, feat:#134] (#132 top chrome + #134 More menu VERIFIED; #129 TXT reader VERIFIED = straight edit; **#136 AI-provider-reachability is the NEW hard blocker** for the "Set up" route + AppContainer AiProviderStore + the DONE flip). Plan `dev-docs/plans/20260710-feature-131-android-bilingual-interlinear.md` (Gate-1 v3, 11 WIs: WI-0 Readium JS-injection spike w/ go-no-go + navigator-race contract; WI-1..4a foundation/service; WI-4b shared DI; WI-5/6 VM state+prefetch; WI-7a Compose UI; WI-7b conditional EPUB DOM-injection adapter; WI-8 TXT/MD host; WI-9 entry wiring+acceptance). **Style DESCOPED v1** (user decision 2026-07-12): keep provider/model/granularity, drop the bilingual Style control (box D flips done for provider/model/granularity + a Style-descope follow-up amendment; a Style+Granularity single sheet is not depicted anywhere = the one open design gate). Design authority (landed, rule 51): vreader-bilingual.jsx (granularity-only setup sheet) + vreader-reader.jsx pill + vreader-more.jsx toggle. **Gate-2 round-2 = REDESIGN resolved (v3): TXT/MD document-global segment ranges (H1); EPUB translatePreSegmented + count-keyed cache + direct-block prefetch (H2); #136 spun out + Style descoped (H3); WI-0 go/no-go + race contract (M1); EPUB DOM-injection NOT Compose body (M2); DI/factory WI reordered (M3); Room 8->9 MIGRATION_8_9 (M4). Gate-2 round-3 audit pending.** GH: #1923 |
docs/features.md:189:| 136| **Android AI provider setup made production-reachable** (prerequisite for AI features) — #118 shipped the whole Android AI provider stack (AiProviderStore / AiSettingsViewModel / AiProviderListScreen / AiProviderEditSheet — built + tested) but it is wired into NO production entry (AiProviderStore is never constructed in AppContainer; the screens are referenced only by tests; there is no NavHost/Settings/More route), so a fresh install has ZERO route to configure an AI provider — dead-ending every AI feature (bilingual #131, chat, translate). #136 makes the already-designed, already-built config production-reachable via the designed reader More-menu configure-ai entry ("Configure AI provider first" -> in-reader AI Providers sheet, Variant A). | android/app/.../ai wiring + reader/chrome/{ReaderChromeScaffold,ReaderChromeState} + VReaderApp/AppContainer + reader/ai/ReaderAiProvidersHost (new) | Medium | PLANNED | Deps:[feat:#118] (#118 shipped the AI provider stack; #136 = reachability only). Plan `dev-docs/plans/20260712-feature-136-android-ai-provider-reachable.md` (Gate-1 v1, 3 WIs: WI-1 AppContainer aiProviderStore + aiSettingsViewModel() factory [foundational]; WI-2 ReaderAiProvidersHost + ReaderSheet.AiProviders route + saver [behavioral]; WI-3 reader More-menu aiUnavailable->configure-ai disabled Bilingual row across 5 hosts + readerMoreRows(aiUnconfigured,onConfigureAi) [behavioral final]). Design authority (landed, rule 51): vreader-more.jsx configure-ai row + vreader-ai-android.jsx AiProviderList + vreader-ai-provider-entry.jsx + design-notes reader-ai-provider-entry.md / reader-ai-readiness.md (Variant A in-reader scoped sheet). Reuses #118's AiProviderListScreen/AiProviderEditSheet verbatim. Spun out per user decision (2026-07-12) from #131 Gate-2-round-2 High-3 (AI-config unreachable). **HARD dependency of #131.** Awaiting Gate-2 audit. GH: #1976 |
     1	// Purpose: Application + manual DI container — feature #106 WI-8. Holds the
     2	// process-singleton Room database, repository, and importer so the Library
     3	// ViewModel gets shared instances (a Hilt module is a Phase-3 follow-on; manual
     4	// wiring at the app edge keeps the foundation bar dependency-light — rule 50 §5).
     5	package com.vreader.app
     6	
     7	import android.app.Application
     8	import android.content.Context
     9	import com.vreader.app.data.BookImporter
    10	import com.vreader.app.data.LibraryRepository
    11	import com.vreader.app.data.VReaderDatabase
    12	import com.vreader.app.reader.BookOpener
    13	import com.vreader.app.search.BookTextExtractor
    14	import com.vreader.app.search.EpubTextExtractor
    15	import com.vreader.app.search.asSearcher
    16	import com.vreader.app.search.SearchIndexCoordinator
    17	import com.vreader.app.search.TxtMdTextExtractor
    18	import com.vreader.app.annotations.AnnotationsRepository
    19	import com.vreader.app.stats.ReadingStatsRepository
    20	import com.vreader.app.stats.ReadingTimeTracker
    21	import com.vreader.app.stats.clock.SystemDateClock
    22	import com.vreader.app.stats.clock.SystemElapsedClock
    23	import kotlinx.coroutines.CoroutineScope
    24	import kotlinx.coroutines.Dispatchers
    25	import kotlinx.coroutines.SupervisorJob
    26	import kotlinx.coroutines.flow.map
    27	import vreader.contracts.BookFormat
    28	import java.io.File
    29	
    30	/** Process-wide singletons, lazily built. */
    31	class AppContainer(context: Context) {
    32	    private val appContext = context.applicationContext
    33	
    34	    val database: VReaderDatabase by lazy { VReaderDatabase.build(appContext) }
    35	    val repository: LibraryRepository by lazy {
    36	        LibraryRepository(database.bookDao(), database.readingPositionDao())
    37	    }
    38	    val importer: BookImporter by lazy {
    39	        BookImporter(File(appContext.filesDir, "books"), repository)
    40	    }
    41	
    42	    // feature #122 — reading-stats. The repository + the time tracker are process-singletons so a
    43	    // reading session survives the (shorter-lived) reader ViewModel / rotation. ONE shared DateClock
    44	    // so the dashboard's "today" and the tracker's bucket dates can't drift apart.
    45	    private val dateClock: SystemDateClock by lazy { SystemDateClock() }
    46	    val statsRepository: ReadingStatsRepository by lazy {
    47	        ReadingStatsRepository(database.readingStatsDao(), repository, dateClock)
    48	    }
    49	    val readingTimeTracker: ReadingTimeTracker by lazy {
    50	        ReadingTimeTracker(statsRepository, SystemElapsedClock(), dateClock)
    51	    }
    52	
    53	    // feature #123 — annotations (EPUB highlights & notes). Process-singleton so the reader VM /
    54	    // rotation share one instance (the statsRepository precedent).
    55	    val annotationsRepository: AnnotationsRepository by lazy {
    56	        AnnotationsRepository(database.annotationDao())
    57	    }
    58	
    59	    // feature #127 — library collections. Process-singleton (the annotationsRepository precedent).
    60	    val collectionRepository: com.vreader.app.data.CollectionRepository by lazy {
    61	        com.vreader.app.data.CollectionRepository(database.collectionDao())
    62	    }
    63	
    64	    // feature #129 — reader display settings. A device-local DataStore (the OpdsSourceStore /
    65	    // AiProviderStore precedent), global (not per-book), process-singleton so a settings change
    66	    // propagates to whatever reader is open. Stored under noBackupFilesDir — display prefs are
    67	    // per-device (NOT in the backup contract), so they must be excluded from Android Auto Backup.
    68	    private val readerSettingsDataStore: androidx.datastore.core.DataStore<androidx.datastore.preferences.core.Preferences> by lazy {
    69	        androidx.datastore.preferences.core.PreferenceDataStoreFactory.create {
    70	            File(appContext.noBackupFilesDir, "reader_settings.preferences_pb")
    71	        }
    72	    }
    73	    val readerSettingsStore: com.vreader.app.reader.settings.ReaderSettingsStore by lazy {
    74	        com.vreader.app.reader.settings.ReaderSettingsStore(readerSettingsDataStore)
    75	    }
    76	
    77	    /** Process-lifetime scope for fire-and-forget writes that must outlive a screen
    78	     *  (e.g. the reader's onStop position flush — it must finish even as the activity
    79	     *  is being torn down). */
    80	    val appScope: CoroutineScope = CoroutineScope(SupervisorJob() + Dispatchers.Default)
    81	
    82	    // feature #128 WI-5 — cross-book search index. The coordinator observes the library and
    83	    // streams each indexable book (epub/txt/md) through the WI-3 extractors into WI-4's staging →
    84	    // atomic publish. Eagerly started once from onCreate; pdf/azw3 map to null (never indexable).
    85	    private val bookOpener: BookOpener by lazy { BookOpener(appContext) }
    86	    private val epubTextExtractor: EpubTextExtractor by lazy { EpubTextExtractor(bookOpener) }
    87	    private val txtMdTextExtractor: TxtMdTextExtractor by lazy { TxtMdTextExtractor() }
    88	    val searchIndexCoordinator: SearchIndexCoordinator by lazy {
    89	        SearchIndexCoordinator(
    90	            repository = repository,
    91	            searchDao = database.searchDao(),
    92	            extractorFor = { fmt: BookFormat ->
    93	                when (fmt) {
    94	                    BookFormat.epub -> epubTextExtractor
    95	                    BookFormat.txt, BookFormat.md -> txtMdTextExtractor
    96	                    BookFormat.pdf, BookFormat.azw3 -> null   // metadata-only — never indexed
    97	                }
    98	            },
    99	            scope = appScope,
   100	            ioDispatcher = Dispatchers.IO,
   101	        )
   102	    }
   103	
   104	    /** Idempotent — starts the single search-index collector (the coordinator's own AtomicBoolean
   105	     *  makes a repeat call a no-op). Called once from [VReaderApp.onCreate]. */
   106	    fun startSearchIndexing() = searchIndexCoordinator.startSearchIndexing()
   107	
   108	    // feature #128 WI-6 — the query pipeline. SearchRepository turns a raw query into an observable
   109	    // Flow of first-hit-per-book text hits (grows as indexing completes); RecentSearchesStore is a
   110	    // device-local DataStore under noBackupFilesDir (the readerSettingsStore precedent — recents are
   111	    // per-device, NOT in the backup contract). The SearchViewModel factory wires the metadata filter,
   112	    // the text-hit Flow, the completeness gate, and recent-recording for the WI-7 screen.
   113	    val searchRepository: com.vreader.app.search.SearchRepository by lazy {
   114	        com.vreader.app.search.SearchRepository(database.searchDao())
   115	    }
   116	    private val recentSearchesDataStore: androidx.datastore.core.DataStore<androidx.datastore.preferences.core.Preferences> by lazy {
   117	        androidx.datastore.preferences.core.PreferenceDataStoreFactory.create {
   118	            File(appContext.noBackupFilesDir, "recent_searches.preferences_pb")
   119	        }
   120	    }
   121	    val recentSearchesStore: com.vreader.app.search.RecentSearchesStore by lazy {
   122	        com.vreader.app.search.RecentSearchesStore(recentSearchesDataStore)
   123	    }
   124	
   125	    /**
     1	// Purpose: feature #106 — the vreader Android app's entry Activity. Hosts the
     2	// Library screen (WI-8, the committed vreader-fidelity-v1 design) wired to the
     3	// shipped plumbing: the LibraryViewModel (Room-backed StateFlow) + the SAF
     4	// OpenDocument picker → BookImporter. Opening a book is the reader host (#1745),
     5	// resumed against vreader-reader.jsx.
     6	//
     7	// @coordinates-with: AndroidManifest.xml (the launcher activity), VReaderApp.kt
     8	//   (the DI container), library/LibraryViewModel.kt, library/LibraryScreen.kt
     9	package com.vreader.app
    10	
    11	import android.os.Bundle
    12	import android.widget.Toast
    13	import androidx.activity.ComponentActivity
    14	import androidx.activity.compose.rememberLauncherForActivityResult
    15	import androidx.activity.compose.setContent
    16	import androidx.activity.result.contract.ActivityResultContracts
    17	import androidx.compose.runtime.getValue
    18	import androidx.lifecycle.compose.collectAsStateWithLifecycle
    19	import androidx.lifecycle.viewmodel.compose.viewModel
    20	import androidx.lifecycle.viewmodel.initializer
    21	import androidx.lifecycle.viewmodel.viewModelFactory
    22	import androidx.compose.runtime.mutableStateOf
    23	import androidx.compose.runtime.remember
    24	import androidx.compose.runtime.saveable.rememberSaveable
    25	import androidx.compose.runtime.setValue
    26	import com.vreader.app.library.AssignToCollectionsSheet
    27	import com.vreader.app.library.ManageCollectionsSheet
    28	import com.vreader.app.library.LibraryEvent
    29	import com.vreader.app.library.LibraryScreen
    30	import com.vreader.app.library.LibraryViewModel
    31	import com.vreader.app.library.SheetRoute
    32	import com.vreader.app.library.SheetRouteSaver
    33	import com.vreader.app.reader.Azw3ReaderActivity
    34	import com.vreader.app.reader.ReaderActivity
    35	import com.vreader.app.reader.PdfReaderActivity
    36	import com.vreader.app.reader.TxtReaderActivity
    37	import com.vreader.app.search.SearchScreen
    38	import com.vreader.app.ui.theme.VReaderTheme
    39	import vreader.contracts.BookFormat
    40	import androidx.compose.runtime.LaunchedEffect
    41	
    42	class MainActivity : ComponentActivity() {
    43	    override fun onCreate(savedInstanceState: Bundle?) {
    44	        super.onCreate(savedInstanceState)
    45	        val container = (application as VReaderApp).container
    46	        val factory = viewModelFactory {
    47	            initializer { LibraryViewModel(container.repository, container.importer, container.collectionRepository, contentResolver) }
    48	        }
    49	
    50	        setContent {
    51	            VReaderTheme {
    52	                val viewModel: LibraryViewModel = viewModel(factory = factory)
    53	                val state by viewModel.uiState.collectAsStateWithLifecycle()
    54	                val collections by viewModel.collections.collectAsStateWithLifecycle()
    55	                val selectedCollectionId by viewModel.selectedCollectionId.collectAsStateWithLifecycle()
    56	                // feature #127 WI-4 — which collections sheet is open (survives rotation/process death).
    57	                var sheetRoute by rememberSaveable(stateSaver = SheetRouteSaver) { mutableStateOf<SheetRoute>(SheetRoute.None) }
    58	                // feature #128 WI-7 — the search takeover open/closed flag (the SheetRoute saveable
    59	                // precedent; a Boolean needs no custom Saver, so rememberSaveable survives rotation/death).
    60	                var searchOpen by rememberSaveable { mutableStateOf(false) }
    61	
    62	                val picker = rememberLauncherForActivityResult(
    63	                    ActivityResultContracts.OpenDocument(),
    64	                ) { uri -> uri?.let(viewModel::import) }
    65	
    66	                LaunchedEffect(Unit) {
    67	                    viewModel.events.collect { event ->
    68	                        val message = when (event) {
    69	                            is LibraryEvent.ImportFailed -> event.message
    70	                            is LibraryEvent.CollectionOpFailed -> event.message
    71	                        }
    72	                        Toast.makeText(this@MainActivity, message, Toast.LENGTH_SHORT).show()
    73	                    }
    74	                }
    75	
    76	                // Route by the typed format (exhaustive — never open a format into the wrong host).
    77	                // Shared by the library grid tap and the search result tap (both carry a typed format +
    78	                // fingerprintKey).
    79	                fun openBook(format: BookFormat, key: String) {
    80	                    when (format) {
    81	                        BookFormat.epub ->
    82	                            startActivity(ReaderActivity.intent(this@MainActivity, key))
    83	                        BookFormat.txt, BookFormat.md ->
    84	                            // .md reuses the text reader host (#112): same decode/
    85	                            // document/resume/chrome, MarkdownRenderer per chunk.
    86	                            startActivity(TxtReaderActivity.intent(this@MainActivity, key))
    87	                        BookFormat.pdf ->
    88	                            // #115 — continuous-scroll PdfRenderer reader.
    89	                            startActivity(PdfReaderActivity.intent(this@MainActivity, key))
    90	                        BookFormat.azw3 ->
    91	                            // #126 — foliate-js WebView reader (AZW3/MOBI/KF8).
    92	                            startActivity(Azw3ReaderActivity.intent(this@MainActivity, key))
    93	                    }
    94	                }
    95	
    96	                LibraryScreen(
    97	                    state = state,
    98	                    collections = collections,
    99	                    selectedCollectionId = selectedCollectionId,
   100	                    onSelectCollection = viewModel::selectCollection,
   101	                    onAssignBook = { book -> sheetRoute = SheetRoute.Assign(book.id) },
   102	                    onManageCollections = { sheetRoute = SheetRoute.Manage },
   103	                    onOpenSearch = { searchOpen = true },
   104	                    onOpenBook = { book -> openBook(book.originalFormat, book.id) },
   105	                    // EPUBs are exposed by SAF providers under varied MIME types
   106	                    // (epub+zip, octet-stream, generic); accept broadly and let
   107	                    // BookImporter reject non-EPUBs by extension with a clear toast.
   108	                    onImport = {
   109	                        picker.launch(
   110	                            arrayOf("application/epub+zip", "application/octet-stream", "*/*"),
   111	                        )
   112	                    },
   113	                )
   114	
   115	                // feature #128 WI-7 — the search takeover. Rendered OVER the library when open; fed by
   116	                // the AppContainer's SearchViewModel (WI-6). Obtained through `viewModel(factory=…)` so it's
   117	                // owned by the Activity's ViewModelStore — its viewModelScope is properly cleared on the
   118	                // Activity's destroy (a raw `remember { … }` would leak the coroutine collector forever).
   119	                if (searchOpen) {
   120	                    val searchViewModel: com.vreader.app.search.SearchViewModel = viewModel(
   121	                        key = "search",
   122	                        factory = viewModelFactory { initializer { container.searchViewModel() } },
   123	                    )
   124	                    val searchState by searchViewModel.state.collectAsStateWithLifecycle()
   125	                    SearchScreen(
   126	                        state = searchState,
   127	                        onQueryChange = searchViewModel::onQueryChange,
   128	                        onCancel = { searchOpen = false },
   129	                        onRecentTap = searchViewModel::onQueryChange,
   130	                        onPickCollection = { id ->
   131	                            // Filter the library to the chosen collection and close the takeover.
   132	                            viewModel.selectCollection(id)
   133	                            searchOpen = false
   134	                        },
   135	                        onOpenResult = { row ->
   136	                            // Record the query as recent (WI-6) AND open the book, then dismiss.
   137	                            searchViewModel.recordCurrentQuery()
   138	                            openBook(row.book.originalFormat, row.book.fingerprintKey)
   139	                            searchOpen = false
   140	                        },
   141	                    )
   142	                }
   143	
   144	                // feature #127 WI-4 — the assign-to-collections sheet (long-press a book).
   145	                val route = sheetRoute
   146	                if (route is SheetRoute.Assign) {
   147	                    // resolve from the UNFILTERED library so unassigning from a filtered collection
   148	                    // doesn't drop the book + close the sheet (Gate-4 WI-4 High).
   149	                    val allBooks by viewModel.allBooks.collectAsStateWithLifecycle()
   150	                    val book = allBooks.firstOrNull { it.id == route.bookKey }

exec
/bin/zsh -lc "rg -n \"bilingualEnabled|bilingualTargetLanguage|bilingualGranularity|bilingualStyle\" contracts android vreader --glob '*.kt' --glob '*.swift' --glob '*.json' --glob '*.md' | head -120; rg -n \"MoreActionId\\.BILINGUAL|BILINGUAL|data class Toggle|class Toggle|sealed.*MoreRow\" android/app/src/main/kotlin/com/vreader/app/reader --glob '*.kt' | head -100" in /Users/ll/workspace/vreader
 succeeded in 0ms:
android/identity/src/main/kotlin/vreader/contracts/backup/BackupSectionsExtended.kt:69:    val bilingualEnabled: Boolean? = null,
android/identity/src/main/kotlin/vreader/contracts/backup/BackupSectionsExtended.kt:70:    val bilingualTargetLanguage: String? = null,
android/identity/src/main/kotlin/vreader/contracts/backup/BackupSectionsExtended.kt:71:    val bilingualGranularity: String? = null,
contracts/vectors/backup-sections.json:116:            "bilingualEnabled": true,
contracts/vectors/backup-sections.json:117:            "bilingualTargetLanguage": "Chinese"
android/identity/src/test/kotlin/vreader/contracts/backup/BackupSectionsExtendedTest.kt:86:            override = PerBookSettingsOverride(fontSize = 18.0, bilingualEnabled = true, bilingualTargetLanguage = "Chinese"),
android/identity/src/test/kotlin/vreader/contracts/backup/BackupSectionsExtendedTest.kt:91:        assertTrue(json.contains("\"bilingualEnabled\""))
vreader/ViewModels/BilingualReadingViewModel.swift:154:        self.isEnabled = override?.bilingualEnabled ?? false
vreader/ViewModels/BilingualReadingViewModel.swift:155:        self.targetLanguage = override?.bilingualTargetLanguage ?? Self.defaultTargetLanguage
vreader/ViewModels/BilingualReadingViewModel.swift:157:            rawValue: override?.bilingualGranularity ?? "") ?? .paragraph
vreader/ViewModels/BilingualReadingViewModel.swift:256:        return override?.bilingualEnabled != nil
vreader/ViewModels/BilingualReadingViewModel.swift:257:            || override?.bilingualTargetLanguage != nil
vreader/ViewModels/BilingualReadingViewModel.swift:258:            || override?.bilingualGranularity != nil
vreader/ViewModels/BilingualReadingViewModel.swift:266:        override.bilingualEnabled = isEnabled
vreader/ViewModels/BilingualReadingViewModel.swift:267:        override.bilingualTargetLanguage = targetLanguage
vreader/ViewModels/BilingualReadingViewModel.swift:268:        override.bilingualGranularity = granularity.rawValue
vreader/ViewModels/AIAssistantViewModel.swift:77:    /// seeds the per-book `bilingualTargetLanguage` once on first appear
vreader/Services/PerBookSettings.swift:33:    var bilingualEnabled: Bool?
vreader/Services/PerBookSettings.swift:37:    var bilingualTargetLanguage: String?
vreader/Services/PerBookSettings.swift:41:    var bilingualGranularity: String?
vreader/Services/PerBookSettings.swift:53:        bilingualEnabled: Bool? = nil,
vreader/Services/PerBookSettings.swift:54:        bilingualTargetLanguage: String? = nil,
vreader/Services/PerBookSettings.swift:55:        bilingualGranularity: String? = nil
vreader/Services/PerBookSettings.swift:62:        self.bilingualEnabled = bilingualEnabled
vreader/Services/PerBookSettings.swift:63:        self.bilingualTargetLanguage = bilingualTargetLanguage
vreader/Services/PerBookSettings.swift:64:        self.bilingualGranularity = bilingualGranularity
vreader/Services/AI/ChapterTranslationService.swift:72:/// `bilingualGranularity`).
vreader/Views/Reader/ReaderAICoordinator.swift:274:           let langKey = override.bilingualTargetLanguage {
vreader/Views/Reader/ReaderContainerView+Sheets.swift:405:            rawValue: bilingualGranularity ?? "") ?? .paragraph
vreader/Views/Reader/Bilingual/BilingualSetupSheet.swift:207:                    .accessibilityIdentifier("bilingualGranularity_\(option.rawValue)")
vreader/Views/Reader/Bilingual/BilingualSetupSheet.swift:229:                .accessibilityIdentifier("bilingualGranularityUnavailableFootnote")
vreader/Views/Reader/Bilingual/ReadiumBilingualEvalAdapter.swift:165:        EPUBBilingualJS.bilingualStyleJS(css: css)
vreader/Views/Reader/Bilingual/BilingualLanguage.swift:3:// (`bilingualTargetLanguage`) all key off. Pinned to the design
vreader/Views/Reader/Bilingual/BilingualLanguage.swift:28://   PerBookSettings.swift (`bilingualTargetLanguage`),
vreader/Views/Reader/Bilingual/BilingualLanguage.swift:36:    /// Canonical key persisted in `PerBookSettings.bilingualTargetLanguage`
vreader/Views/Reader/ReadiumEPUBHost+BilingualDriver.swift:248:        await bilingualCommander.setStyle(bilingualStyleCSS())
vreader/Views/Reader/ReadiumEPUBHost+BilingualLoading.swift:62:                await bilingualCommander.setStyle(bilingualStyleCSS())
vreader/Views/Reader/ReadiumEPUBHost+BilingualLoading.swift:78:    func bilingualStyleCSS() -> String {
vreader/Views/Reader/Bilingual/EPUBBilingualJS.swift:393:    static func bilingualStyleJS(css: String) -> String {
vreader/Views/Reader/ReaderTopChrome.swift:48:    /// `PerBookSettings.bilingualTargetLanguage`. `nil` (book never
vreader/Views/Reader/ReadiumEPUBHost+Bilingual.swift:330:                    await bilingualCommander.setStyle(bilingualStyleCSS())
vreader/Views/Reader/ReaderContainerView.swift:223:    @State var bilingualGranularity: String?
vreader/Views/Reader/ReaderContainerView.swift:540:                bilingualGranularity = granularity
android/app/src/main/kotlin/com/vreader/app/reader/more/MoreRow.kt:4:// DETAILS + SHARE (Action rows); TTS/AUTO_TURN/BILINGUAL ids exist so their owning features (#121/#131/
android/app/src/main/kotlin/com/vreader/app/reader/more/MoreRow.kt:24:    BILINGUAL,
android/app/src/main/kotlin/com/vreader/app/reader/more/MoreRow.kt:41:sealed interface MoreRow {
android/app/src/main/kotlin/com/vreader/app/reader/more/MoreRow.kt:56:    data class Toggle(

exec
/bin/zsh -lc "nl -ba android/app/src/main/kotlin/com/vreader/app/reader/more/MoreRow.kt | sed -n '15,70p' && rg -n \"BilingualPill|bilingual\" android/app/src/main/kotlin/com/vreader/app/reader --glob '*.kt' | head -100 && rg -n \"class BilingualParagraphRanges|enum BilingualParagraphRanges|struct BilingualParagraphRanges|scan\\(sourceText\" vreader --glob '*.swift'" in /Users/ll/workspace/vreader
 succeeded in 0ms:
    15	 * #134 supplies none of them and omits any id it is not given a row for. There is deliberately NO
    16	 * `EXPORT` id: Android has no annotation-export subsystem, so the Export row is never rendered (the
    17	 * plan's scoped-out invariant), and absence-by-omission is enforced by there being no id to supply.
    18	 */
    19	enum class MoreActionId {
    20	    DETAILS,
    21	    SHARE,
    22	    TTS,
    23	    AUTO_TURN,
    24	    BILINGUAL,
    25	}
    26	
    27	/** The lowercase stable slug for this id — the testTag / route suffix (e.g. `AUTO_TURN` → `auto_turn`). */
    28	val MoreActionId.slug: String
    29	    get() = name.lowercase()
    30	
    31	/**
    32	 * A single More-menu row. Exactly one of three shapes, mirroring the design's three row treatments:
    33	 *  - [Action]   — a tap row with a trailing chevron (`vreader-more.jsx` `onAction`).
    34	 *  - [Toggle]   — a stateful row with a trailing switch reflecting [Toggle.on] (`onToggle`).
    35	 *  - [Disabled] — the design's disabled state (e.g. Bilingual "Configure AI provider first"):
    36	 *                 non-interactive, dimmed, shows its [Disabled.sub].
    37	 *
    38	 * Every row carries a stable [id] (its testTag key) and its own callback. The OWNER of a row's behavior
    39	 * is the feature that supplies it — never [MorePopup] itself.
    40	 */
    41	sealed interface MoreRow {
    42	    val id: MoreActionId
    43	    val label: String
    44	    val icon: ImageVector
    45	
    46	    /** A tap row: fires [onTap]; renders a trailing chevron accessory. */
    47	    data class Action(
    48	        override val id: MoreActionId,
    49	        override val label: String,
    50	        override val icon: ImageVector,
    51	        val sub: String? = null,
    52	        val onTap: () -> Unit,
    53	    ) : MoreRow
    54	
    55	    /** A toggle row: the trailing switch reflects [on]; tapping the row calls [onToggle] with `!on`. */
    56	    data class Toggle(
    57	        override val id: MoreActionId,
    58	        override val label: String,
    59	        override val icon: ImageVector,
    60	        val sub: String? = null,
    61	        val on: Boolean,
    62	        val onToggle: (Boolean) -> Unit,
    63	    ) : MoreRow
    64	
    65	    /** A disabled row: non-interactive, dimmed, shows [sub] (the design's "Configure AI provider first"). */
    66	    data class Disabled(
    67	        override val id: MoreActionId,
    68	        override val label: String,
    69	        override val icon: ImageVector,
    70	        val sub: String,
vreader/Services/Reader/BilingualParagraphRanges.swift:39:enum BilingualParagraphRanges {
vreader/Services/Reader/BilingualParagraphRanges.swift:49:    static func scan(sourceText: String) -> [Range<Int>] {
vreader/Services/AI/ChapterSegmenter.swift:39:        return BilingualParagraphRanges.scan(sourceText: chapterText).map {
vreader/Views/Reader/Bilingual/BilingualDisplayPipeline.swift:152:            return BilingualParagraphRanges.scan(sourceText: sourceText)

codex
Most round-2 factual corrections check out: Readium 3.3.0’s resolved class exposes the named public methods; `ReaderActivity` holds the concrete fragment; Room is exactly v8 with migrations through 7→8; the #118 seams and named iOS parity APIs exist; and #136 is a real planned hard dependency. I found a concrete last-chunk failure in the new TXT/MD mapping, plus integration/concurrency gaps that prevent clearing this round as written.
exec
/bin/zsh -lc "rg -n \"request\\.model|model = request|AiRequest\\(\" android/app/src/main/kotlin/com/vreader/app/ai/OpenAiCompatibleProvider.kt android/app/src/main/kotlin/com/vreader/app/ai/AnthropicProvider.kt | head -80 && nl -ba android/app/src/main/kotlin/com/vreader/app/ai/OpenAiCompatibleProvider.kt | sed -n '35,75p' && nl -ba android/app/src/main/kotlin/com/vreader/app/ai/AnthropicProvider.kt | sed -n '35,80p'" in /Users/ll/workspace/vreader
 succeeded in 0ms:
android/app/src/main/kotlin/com/vreader/app/ai/OpenAiCompatibleProvider.kt:39:        put("model", request.model)
android/app/src/main/kotlin/com/vreader/app/ai/AnthropicProvider.kt:37:        put("model", request.model)
    35	        conn.setRequestProperty("Authorization", "Bearer $apiKey")  // never logged
    36	    }
    37	
    38	    override fun requestBody(request: AiRequest, stream: Boolean): String = buildJsonObject {
    39	        put("model", request.model)
    40	        put("temperature", request.temperature)
    41	        put("max_tokens", request.maxTokens)
    42	        put("stream", stream)
    43	        putJsonArray("messages") {
    44	            request.system?.let { addJsonObject { put("role", "system"); put("content", it) } }
    45	            request.messages.forEach { m ->
    46	                addJsonObject { put("role", m.role.name); put("content", m.content) }
    47	            }
    48	        }
    49	    }.toString()
    50	
    51	    override fun parseDelta(event: SseEvent): DeltaParse {
    52	        val data = event.data
    53	        if (data == "[DONE]") return DeltaParse(null, done = true)
    54	        val text = runCatching {
    55	            JSON.parseToJsonElement(data).jsonObject["choices"]?.jsonArray
    56	                ?.firstOrNull()?.jsonObject?.get("delta")?.jsonObject?.get("content")?.jsonPrimitive?.content
    57	        }.getOrNull()
    58	        return DeltaParse(text, done = false)
    59	    }
    60	
    61	    override fun parseOneShot(json: String): String =
    62	        runCatching {
    63	            JSON.parseToJsonElement(json).jsonObject["choices"]?.jsonArray
    64	                ?.firstOrNull()?.jsonObject?.get("message")?.jsonObject?.get("content")?.jsonPrimitive?.content
    65	        }.getOrNull() ?: throw AiError.Decode("no choices[0].message.content")
    66	
    67	    private companion object { val JSON = Json { ignoreUnknownKeys = true } }
    68	}
    35	
    36	    override fun requestBody(request: AiRequest, stream: Boolean): String = buildJsonObject {
    37	        put("model", request.model)
    38	        put("max_tokens", request.maxTokens)
    39	        put("temperature", request.temperature)
    40	        put("stream", stream)
    41	        request.system?.let { put("system", it) }  // top-level, not a message
    42	        putJsonArray("messages") {
    43	            request.messages.forEach { m ->
    44	                // Anthropic accepts user/assistant only; a stray system message folds to user.
    45	                val role = if (m.role == AiRole.assistant) "assistant" else "user"
    46	                addJsonObject { put("role", role); put("content", m.content) }
    47	            }
    48	        }
    49	    }.toString()
    50	
    51	    override fun parseDelta(event: SseEvent): DeltaParse {
    52	        // Prefer the event-type line; fall back to the data's own `type` (some servers omit event:).
    53	        val data = runCatching { JSON.parseToJsonElement(event.data).jsonObject }.getOrNull()
    54	        val type = event.event ?: data?.get("type")?.jsonPrimitive?.content
    55	        return when (type) {
    56	            "message_stop" -> DeltaParse(null, done = true)
    57	            "error" -> throw AiError.Stream(data?.get("error")?.jsonObject?.get("message")?.jsonPrimitive?.content ?: "provider error")
    58	            "content_block_delta" -> {
    59	                val text = data?.get("delta")?.jsonObject?.get("text")?.jsonPrimitive?.content
    60	                DeltaParse(text, done = false)
    61	            }
    62	            else -> DeltaParse(null, done = false)  // message_start / ping / content_block_start/stop
    63	        }
    64	    }
    65	
    66	    override fun parseOneShot(json: String): String =
    67	        runCatching {
    68	            JSON.parseToJsonElement(json).jsonObject["content"]?.jsonArray
    69	                ?.firstOrNull()?.jsonObject?.get("text")?.jsonPrimitive?.content
    70	        }.getOrNull() ?: throw AiError.Decode("no content[0].text")
    71	
    72	    private companion object {
    73	        const val ANTHROPIC_VERSION = "2023-06-01"
    74	        val JSON = Json { ignoreUnknownKeys = true }
    75	    }
    76	}

exec
/bin/zsh -lc "rg -n \"AiRequest\\(\" android/app/src/main/kotlin/com/vreader/app/ai/AiChatViewModel.kt -A12 -B3 && rg -n \"model.*ifBlank|defaultModel|model =\" android/app/src/main/kotlin/com/vreader/app/ai/AiSettingsViewModel.kt | head -80" in /Users/ll/workspace/vreader
 succeeded in 0ms:
58-        streamJob = viewModelScope.launch {
59-            val (profile, key) = activeClient() ?: run { _state.update { it.copy(streaming = false, unconfigured = true) }; return@launch }
60-            val history = _state.value.messages.map { AiMessage(if (it.fromUser) AiRole.user else AiRole.assistant, it.text) }
61:            val request = AiRequest(profile.model.ifBlank { profile.kind.defaultModel }, history, profile.temperature, profile.maxTokens, system = CHAT_SYSTEM)
62-            val sb = StringBuilder()
63-            try {
64-                factory(profile, key).streamChat(request).collect { chunk ->
65-                    if (gen != chatGen) return@collect  // superseded by a provider swap / newer send
66-                    sb.append(chunk.deltaText)
67-                    _state.update { it.copy(streamingText = sb.toString()) }
68-                }
69-                if (gen == chatGen) _state.update { it.copy(messages = it.messages + ChatMessage(false, sb.toString()), streaming = false, streamingText = "") }
70-            } catch (e: AiError) {
71-                if (gen == chatGen) _state.update { it.copy(streaming = false, streamingText = "", error = e.message) }
72-            }
73-        }
--
100-            }
101-            _state.update { it.copy(streaming = true, summary = null) }
102-            try {
103:                val req = AiRequest(
104-                    profile.model.ifBlank { profile.kind.defaultModel },
105-                    listOf(AiMessage(AiRole.user, "Summarize this chapter in 4 concise key points (markdown bullet list):\n\n$chapterText")),
106-                    profile.temperature, profile.maxTokens, system = CHAT_SYSTEM,
107-                )
108-                val resp = factory(profile, key).chat(req)
109-                summaryCache[cacheKey] = resp.text
110-                _state.update { it.copy(summary = resp.text, summaryCached = false, streaming = false) }
111-            } catch (e: AiError) {
112-                _state.update { it.copy(streaming = false, error = e.message) }
113-            }
114-        }
115-    }
30:                    AiProviderRow(p.id, p.name, active = p.id == snap.activeId, statusOk = true, detail = p.model.ifBlank { p.kind.defaultModel })
50:            editMode = true, id = p.id, kind = p.kind, name = p.name, baseUrl = p.baseUrl, model = p.model,
70:                    model = s.effectiveModel, temperature = s.temperature, maxTokens = s.maxTokens, encryptedApiKey = "",
91:                name = s.name, kind = s.kind, baseUrl = s.baseUrl, model = s.model,

codex
Critical

None.

High

1. TXT/MD final-chunk translations can be dropped. The plan defines each chunk span as `[offsetForChunk(i), offsetForChunk(i+1))` and anchors a spanning segment in the chunk where its range ends ([plan:40](/Users/ll/workspace/vreader/dev-docs/plans/20260710-feature-131-android-bilingual-interlinear.md:40)). But `offsetForChunk()` clamps out-of-range indices to the last valid chunk ([TxtDocument.kt:17](/Users/ll/workspace/vreader/android/app/src/main/kotlin/com/vreader/app/reader/TxtDocument.kt:17)), whereas `textForChunk()` correctly uses `text.length` for the final end ([TxtDocument.kt:35](/Users/ll/workspace/vreader/android/app/src/main/kotlin/com/vreader/app/reader/TxtDocument.kt:35)). Consequently, for the last chunk, `offsetForChunk(i+1) == offsetForChunk(i)`, producing an empty span. A one-chunk document drops every translation; a long paragraph ending in the final chunk also drops its sole translation. H1 is therefore not sound as written. Specify `endExclusive = if (i + 1 < chunkCount) offsetForChunk(i + 1) else text.length`, use explicit half-open ranges rather than ambiguous Kotlin `IntRange`, and test one-chunk, final-chunk, exact-boundary, and EOF anchors.

2. The enabled TXT/MD render contract does not preserve the live host’s layout/selection/highlight invariants. The plan requires a source `Text` followed by translation `Text` per segment ([plan:92](/Users/ll/workspace/vreader/dev-docs/plans/20260710-feature-131-android-bilingual-interlinear.md:92)), while retaining the chunk-based loop for selection/highlight parity ([plan:40](/Users/ll/workspace/vreader/dev-docs/plans/20260710-feature-131-android-bilingual-interlinear.md:40)). Live code owns exactly one `TextLayoutResult` and one selection registration per chunk ([TxtReaderActivity.kt:1043](/Users/ll/workspace/vreader/android/app/src/main/kotlin/com/vreader/app/reader/TxtReaderActivity.kt:1043), [TxtReaderActivity.kt:1058](/Users/ll/workspace/vreader/android/app/src/main/kotlin/com/vreader/app/reader/TxtReaderActivity.kt:1058), [TxtReaderActivity.kt:1061](/Users/ll/workspace/vreader/android/app/src/main/kotlin/com/vreader/app/reader/TxtReaderActivity.kt:1061)). Sentence granularity commonly puts several segments inside one line/chunk. Splitting that source into several `Text` nodes breaks the one-layout-per-chunk coordinate model; keeping one source `Text` cannot interleave each sentence translation at its segment boundary. The plan needs an explicit offset-preserving render/layout design and enabled-mode tests for selection, highlights, read-aloud wash, annotations, and Markdown mapping.

Medium

1. H2’s service APIs are present in the plan, but the EPUB direct-block control flow is not connected end-to-end. `BilingualViewModel` exposes position-driven state ([plan:75](/Users/ll/workspace/vreader/dev-docs/plans/20260710-feature-131-android-bilingual-interlinear.md:75)); WI-6 only defines `onPositionChanged(charOffsetUTF16)` and ordinary current/next prefetch ([plan:183](/Users/ll/workspace/vreader/dev-docs/plans/20260710-feature-131-android-bilingual-interlinear.md:183)). WI-7b says the controller enumerates DOM blocks and uses `prefetchDirect`/`cachedDirect` ([plan:187](/Users/ll/workspace/vreader/dev-docs/plans/20260710-feature-131-android-bilingual-interlinear.md:187)), but no API says how those results enter `translationsByUnit`, how they are session-guarded, or how regular and direct prefetch are prevented from racing for the same canonical cache row. Define one owner and a concrete `enumeratedBlocks → cachedDirect/translatePreSegmented → guarded render-state commit` API.

2. Cancellation handling is incomplete across the service/VM boundary. The service maps cancellation to `ChapterTranslationError.Cancelled` ([plan:58](/Users/ll/workspace/vreader/dev-docs/plans/20260710-feature-131-android-bilingual-interlinear.md:58)), while WI-6 explicitly special-cases only `CancellationException` before generic error mapping ([plan:183](/Users/ll/workspace/vreader/dev-docs/plans/20260710-feature-131-android-bilingual-interlinear.md:183)). The iOS parity implementation deliberately handles both native cancellation and typed `ChapterTranslationError.cancelled` ([ChapterTranslationService.swift:359](/Users/ll/workspace/vreader/vreader/Services/AI/ChapterTranslationService.swift:359)). Without the same rule, a cancelled stale request can surface as `errorUnit`. Also require a per-unit single-flight job registry so rapid retry/navigation cannot run overlapping translations or writes.

3. The proposed `AiRequest` construction misses the live blank-model fallback. The plan uses `model = profile.model` ([plan:85](/Users/ll/workspace/vreader/dev-docs/plans/20260710-feature-131-android-bilingual-interlinear.md:85)), but both wire clients serialize `request.model` directly ([OpenAiCompatibleProvider.kt:38](/Users/ll/workspace/vreader/android/app/src/main/kotlin/com/vreader/app/ai/OpenAiCompatibleProvider.kt:38), [AnthropicProvider.kt:36](/Users/ll/workspace/vreader/android/app/src/main/kotlin/com/vreader/app/ai/AnthropicProvider.kt:36)). Existing chat code correctly uses `profile.model.ifBlank { profile.kind.defaultModel }` ([AiChatViewModel.kt:61](/Users/ll/workspace/vreader/android/app/src/main/kotlin/com/vreader/app/ai/AiChatViewModel.kt:61)). Match that precedent and add a blank-model regression test.

4. #136 blocks more of the behavioral chain than the plan states. It says only WI-4b and WI-9 wait on #136 ([plan:167](/Users/ll/workspace/vreader/dev-docs/plans/20260710-feature-131-android-bilingual-interlinear.md:167)), but WI-6 depends on WI-4b ([plan:183](/Users/ll/workspace/vreader/dev-docs/plans/20260710-feature-131-android-bilingual-interlinear.md:183)), and both host integrations depend on WI-4b ([plan:187](/Users/ll/workspace/vreader/dev-docs/plans/20260710-feature-131-android-bilingual-interlinear.md:187), [plan:189](/Users/ll/workspace/vreader/dev-docs/plans/20260710-feature-131-android-bilingual-interlinear.md:189)). Thus #136 gates WI-6, WI-7b, and WI-8 transitively. Either state that honestly or move provider/container binding behind a later adapter so VM and host work can proceed with injected seams.

Low

1. The split contains twelve WIs, not eleven: WI-0, WI-1, WI-2, WI-3, WI-4a, WI-4b, WI-5, WI-6, WI-7a, WI-7b, WI-8, and WI-9 ([plan:163](/Users/ll/workspace/vreader/dev-docs/plans/20260710-feature-131-android-bilingual-interlinear.md:163)). The tracker repeats the incorrect count ([features.md:184](/Users/ll/workspace/vreader/docs/features.md:184)).

2. The statement that a live TXT chunk can hold multiple paragraphs is inaccurate ([plan:34](/Users/ll/workspace/vreader/dev-docs/plans/20260710-feature-131-android-bilingual-interlinear.md:34)): `TxtDocument` starts a new chunk after every LF, CR, or CRLF ([TxtDocument.kt:65](/Users/ll/workspace/vreader/android/app/src/main/kotlin/com/vreader/app/reader/TxtDocument.kt:65)). A chunk can contain multiple sentences, and a paragraph can span many chunks; tests and prose should use those real cases.

Verified resolutions

- `TxtDocument` exposes only the stated text/chunk API and has no chapter/section model ([TxtDocument.kt:9](/Users/ll/workspace/vreader/android/app/src/main/kotlin/com/vreader/app/reader/TxtDocument.kt:9)).
- The resolved Readium dependency is 3.3.0 ([build.gradle.kts:111](/Users/ll/workspace/vreader/android/app/build.gradle.kts:111)); binary inspection confirmed public `evaluateJavascript`, `getCurrentLocator`, `firstVisibleElementLocator`, and `submitPreferences`. `ReaderActivity.navigator` is `EpubNavigatorFragment?` ([ReaderActivity.kt:110](/Users/ll/workspace/vreader/android/app/src/main/kotlin/com/vreader/app/reader/ReaderActivity.kt:110)).
- Room is v8 with migrations 1→2 through 7→8 registered ([VReaderDatabase.kt:21](/Users/ll/workspace/vreader/android/app/src/main/kotlin/com/vreader/app/data/VReaderDatabase.kt:21), [VReaderDatabase.kt:223](/Users/ll/workspace/vreader/android/app/src/main/kotlin/com/vreader/app/data/VReaderDatabase.kt:223)); 8→9 is correct. `BookEntity` uses `@PrimaryKey` and `BookDao` uses `@Upsert` ([Entities.kt:22](/Users/ll/workspace/vreader/android/app/src/main/kotlin/com/vreader/app/data/Entities.kt:22), [Daos.kt:16](/Users/ll/workspace/vreader/android/app/src/main/kotlin/com/vreader/app/data/Daos.kt:16)).
- All named #118 seams and `AiError` cases exist ([AiProviderStore.kt:34](/Users/ll/workspace/vreader/android/app/src/main/kotlin/com/vreader/app/ai/AiProviderStore.kt:34), [AiProviderFactory.kt:10](/Users/ll/workspace/vreader/android/app/src/main/kotlin/com/vreader/app/ai/AiProviderFactory.kt:10), [AiClient.kt:25](/Users/ll/workspace/vreader/android/app/src/main/kotlin/com/vreader/app/ai/AiClient.kt:25), [AiTypes.kt:12](/Users/ll/workspace/vreader/android/app/src/main/kotlin/com/vreader/app/ai/AiTypes.kt:12)).
- The named iOS parity symbols exist, including the pre-segmented/direct-cache recovery surface, sentence ranges, strict chunk contract, and grapheme-safe sub-split ([ChapterTranslationService.swift:327](/Users/ll/workspace/vreader/vreader/Services/AI/ChapterTranslationService.swift:327), [ChapterTranslationPrefetcher.swift:197](/Users/ll/workspace/vreader/vreader/Services/AI/ChapterTranslationPrefetcher.swift:197), [ChapterSegmenter.swift:78](/Users/ll/workspace/vreader/vreader/Services/AI/ChapterSegmenter.swift:78), [TranslationChunkContract.swift:24](/Users/ll/workspace/vreader/vreader/Services/AI/TranslationChunkContract.swift:24), [ChapterTranslationChunker.swift:85](/Users/ll/workspace/vreader/vreader/Services/AI/ChapterTranslationChunker.swift:85)).
- M1, M2, M3, M4, #136 reachability spinout, and Style descope are otherwise materially reflected in v3.

FINAL VERDICT: block-recommended
tokens used
114,538
Critical

None.

High

1. TXT/MD final-chunk translations can be dropped. The plan defines each chunk span as `[offsetForChunk(i), offsetForChunk(i+1))` and anchors a spanning segment in the chunk where its range ends ([plan:40](/Users/ll/workspace/vreader/dev-docs/plans/20260710-feature-131-android-bilingual-interlinear.md:40)). But `offsetForChunk()` clamps out-of-range indices to the last valid chunk ([TxtDocument.kt:17](/Users/ll/workspace/vreader/android/app/src/main/kotlin/com/vreader/app/reader/TxtDocument.kt:17)), whereas `textForChunk()` correctly uses `text.length` for the final end ([TxtDocument.kt:35](/Users/ll/workspace/vreader/android/app/src/main/kotlin/com/vreader/app/reader/TxtDocument.kt:35)). Consequently, for the last chunk, `offsetForChunk(i+1) == offsetForChunk(i)`, producing an empty span. A one-chunk document drops every translation; a long paragraph ending in the final chunk also drops its sole translation. H1 is therefore not sound as written. Specify `endExclusive = if (i + 1 < chunkCount) offsetForChunk(i + 1) else text.length`, use explicit half-open ranges rather than ambiguous Kotlin `IntRange`, and test one-chunk, final-chunk, exact-boundary, and EOF anchors.

2. The enabled TXT/MD render contract does not preserve the live host’s layout/selection/highlight invariants. The plan requires a source `Text` followed by translation `Text` per segment ([plan:92](/Users/ll/workspace/vreader/dev-docs/plans/20260710-feature-131-android-bilingual-interlinear.md:92)), while retaining the chunk-based loop for selection/highlight parity ([plan:40](/Users/ll/workspace/vreader/dev-docs/plans/20260710-feature-131-android-bilingual-interlinear.md:40)). Live code owns exactly one `TextLayoutResult` and one selection registration per chunk ([TxtReaderActivity.kt:1043](/Users/ll/workspace/vreader/android/app/src/main/kotlin/com/vreader/app/reader/TxtReaderActivity.kt:1043), [TxtReaderActivity.kt:1058](/Users/ll/workspace/vreader/android/app/src/main/kotlin/com/vreader/app/reader/TxtReaderActivity.kt:1058), [TxtReaderActivity.kt:1061](/Users/ll/workspace/vreader/android/app/src/main/kotlin/com/vreader/app/reader/TxtReaderActivity.kt:1061)). Sentence granularity commonly puts several segments inside one line/chunk. Splitting that source into several `Text` nodes breaks the one-layout-per-chunk coordinate model; keeping one source `Text` cannot interleave each sentence translation at its segment boundary. The plan needs an explicit offset-preserving render/layout design and enabled-mode tests for selection, highlights, read-aloud wash, annotations, and Markdown mapping.

Medium

1. H2’s service APIs are present in the plan, but the EPUB direct-block control flow is not connected end-to-end. `BilingualViewModel` exposes position-driven state ([plan:75](/Users/ll/workspace/vreader/dev-docs/plans/20260710-feature-131-android-bilingual-interlinear.md:75)); WI-6 only defines `onPositionChanged(charOffsetUTF16)` and ordinary current/next prefetch ([plan:183](/Users/ll/workspace/vreader/dev-docs/plans/20260710-feature-131-android-bilingual-interlinear.md:183)). WI-7b says the controller enumerates DOM blocks and uses `prefetchDirect`/`cachedDirect` ([plan:187](/Users/ll/workspace/vreader/dev-docs/plans/20260710-feature-131-android-bilingual-interlinear.md:187)), but no API says how those results enter `translationsByUnit`, how they are session-guarded, or how regular and direct prefetch are prevented from racing for the same canonical cache row. Define one owner and a concrete `enumeratedBlocks → cachedDirect/translatePreSegmented → guarded render-state commit` API.

2. Cancellation handling is incomplete across the service/VM boundary. The service maps cancellation to `ChapterTranslationError.Cancelled` ([plan:58](/Users/ll/workspace/vreader/dev-docs/plans/20260710-feature-131-android-bilingual-interlinear.md:58)), while WI-6 explicitly special-cases only `CancellationException` before generic error mapping ([plan:183](/Users/ll/workspace/vreader/dev-docs/plans/20260710-feature-131-android-bilingual-interlinear.md:183)). The iOS parity implementation deliberately handles both native cancellation and typed `ChapterTranslationError.cancelled` ([ChapterTranslationService.swift:359](/Users/ll/workspace/vreader/vreader/Services/AI/ChapterTranslationService.swift:359)). Without the same rule, a cancelled stale request can surface as `errorUnit`. Also require a per-unit single-flight job registry so rapid retry/navigation cannot run overlapping translations or writes.

3. The proposed `AiRequest` construction misses the live blank-model fallback. The plan uses `model = profile.model` ([plan:85](/Users/ll/workspace/vreader/dev-docs/plans/20260710-feature-131-android-bilingual-interlinear.md:85)), but both wire clients serialize `request.model` directly ([OpenAiCompatibleProvider.kt:38](/Users/ll/workspace/vreader/android/app/src/main/kotlin/com/vreader/app/ai/OpenAiCompatibleProvider.kt:38), [AnthropicProvider.kt:36](/Users/ll/workspace/vreader/android/app/src/main/kotlin/com/vreader/app/ai/AnthropicProvider.kt:36)). Existing chat code correctly uses `profile.model.ifBlank { profile.kind.defaultModel }` ([AiChatViewModel.kt:61](/Users/ll/workspace/vreader/android/app/src/main/kotlin/com/vreader/app/ai/AiChatViewModel.kt:61)). Match that precedent and add a blank-model regression test.

4. #136 blocks more of the behavioral chain than the plan states. It says only WI-4b and WI-9 wait on #136 ([plan:167](/Users/ll/workspace/vreader/dev-docs/plans/20260710-feature-131-android-bilingual-interlinear.md:167)), but WI-6 depends on WI-4b ([plan:183](/Users/ll/workspace/vreader/dev-docs/plans/20260710-feature-131-android-bilingual-interlinear.md:183)), and both host integrations depend on WI-4b ([plan:187](/Users/ll/workspace/vreader/dev-docs/plans/20260710-feature-131-android-bilingual-interlinear.md:187), [plan:189](/Users/ll/workspace/vreader/dev-docs/plans/20260710-feature-131-android-bilingual-interlinear.md:189)). Thus #136 gates WI-6, WI-7b, and WI-8 transitively. Either state that honestly or move provider/container binding behind a later adapter so VM and host work can proceed with injected seams.

Low

1. The split contains twelve WIs, not eleven: WI-0, WI-1, WI-2, WI-3, WI-4a, WI-4b, WI-5, WI-6, WI-7a, WI-7b, WI-8, and WI-9 ([plan:163](/Users/ll/workspace/vreader/dev-docs/plans/20260710-feature-131-android-bilingual-interlinear.md:163)). The tracker repeats the incorrect count ([features.md:184](/Users/ll/workspace/vreader/docs/features.md:184)).

2. The statement that a live TXT chunk can hold multiple paragraphs is inaccurate ([plan:34](/Users/ll/workspace/vreader/dev-docs/plans/20260710-feature-131-android-bilingual-interlinear.md:34)): `TxtDocument` starts a new chunk after every LF, CR, or CRLF ([TxtDocument.kt:65](/Users/ll/workspace/vreader/android/app/src/main/kotlin/com/vreader/app/reader/TxtDocument.kt:65)). A chunk can contain multiple sentences, and a paragraph can span many chunks; tests and prose should use those real cases.

Verified resolutions

- `TxtDocument` exposes only the stated text/chunk API and has no chapter/section model ([TxtDocument.kt:9](/Users/ll/workspace/vreader/android/app/src/main/kotlin/com/vreader/app/reader/TxtDocument.kt:9)).
- The resolved Readium dependency is 3.3.0 ([build.gradle.kts:111](/Users/ll/workspace/vreader/android/app/build.gradle.kts:111)); binary inspection confirmed public `evaluateJavascript`, `getCurrentLocator`, `firstVisibleElementLocator`, and `submitPreferences`. `ReaderActivity.navigator` is `EpubNavigatorFragment?` ([ReaderActivity.kt:110](/Users/ll/workspace/vreader/android/app/src/main/kotlin/com/vreader/app/reader/ReaderActivity.kt:110)).
- Room is v8 with migrations 1→2 through 7→8 registered ([VReaderDatabase.kt:21](/Users/ll/workspace/vreader/android/app/src/main/kotlin/com/vreader/app/data/VReaderDatabase.kt:21), [VReaderDatabase.kt:223](/Users/ll/workspace/vreader/android/app/src/main/kotlin/com/vreader/app/data/VReaderDatabase.kt:223)); 8→9 is correct. `BookEntity` uses `@PrimaryKey` and `BookDao` uses `@Upsert` ([Entities.kt:22](/Users/ll/workspace/vreader/android/app/src/main/kotlin/com/vreader/app/data/Entities.kt:22), [Daos.kt:16](/Users/ll/workspace/vreader/android/app/src/main/kotlin/com/vreader/app/data/Daos.kt:16)).
- All named #118 seams and `AiError` cases exist ([AiProviderStore.kt:34](/Users/ll/workspace/vreader/android/app/src/main/kotlin/com/vreader/app/ai/AiProviderStore.kt:34), [AiProviderFactory.kt:10](/Users/ll/workspace/vreader/android/app/src/main/kotlin/com/vreader/app/ai/AiProviderFactory.kt:10), [AiClient.kt:25](/Users/ll/workspace/vreader/android/app/src/main/kotlin/com/vreader/app/ai/AiClient.kt:25), [AiTypes.kt:12](/Users/ll/workspace/vreader/android/app/src/main/kotlin/com/vreader/app/ai/AiTypes.kt:12)).
- The named iOS parity symbols exist, including the pre-segmented/direct-cache recovery surface, sentence ranges, strict chunk contract, and grapheme-safe sub-split ([ChapterTranslationService.swift:327](/Users/ll/workspace/vreader/vreader/Services/AI/ChapterTranslationService.swift:327), [ChapterTranslationPrefetcher.swift:197](/Users/ll/workspace/vreader/vreader/Services/AI/ChapterTranslationPrefetcher.swift:197), [ChapterSegmenter.swift:78](/Users/ll/workspace/vreader/vreader/Services/AI/ChapterSegmenter.swift:78), [TranslationChunkContract.swift:24](/Users/ll/workspace/vreader/vreader/Services/AI/TranslationChunkContract.swift:24), [ChapterTranslationChunker.swift:85](/Users/ll/workspace/vreader/vreader/Services/AI/ChapterTranslationChunker.swift:85)).
- M1, M2, M3, M4, #136 reachability spinout, and Style descope are otherwise materially reflected in v3.

FINAL VERDICT: block-recommended
