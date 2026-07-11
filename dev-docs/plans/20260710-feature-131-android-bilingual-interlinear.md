# Feature #131 — Android Bilingual Interlinear Reading (parity-checklist box D)

**Feature number assumption:** highest active row in `docs/features.md` is `#130`; `#131` is the next free number. The orchestrator adjusts if a row is claimed first.

**Design authority (rule 51):** the **authoritative** bilingual surfaces are in `dev-docs/designs/vreader-fidelity-v1/project/vreader-bilingual.jsx` (`BilingualSetupSheet` / `BilingualPageContent` / `BilingualPill` / `BILINGUAL_LANGS`) and `.../vreader-reader.jsx` (`ReaderTopChrome` renders `BilingualPill`; the bilingual toggle is a More-menu row via `onMoreAction`) and `.../vreader-more.jsx` (the "Bilingual mode" More-menu Row toggle). `.../vreader-ai-android.jsx` contains a SECOND, differently-shaped `BilingualSetupSheet` — see §3's setup-sheet resolution for why this plan reproduces the `vreader-bilingual.jsx` sheet and design-gates the divergence. Where a surface is NOT depicted it is scoped out and flagged.

**Status:** Gate-1 draft v2 (2026-07-11) — Gate-2 round-1 REDESIGN resolved. Awaiting Gate-2 round-2 audit.

## 1. Problem

iOS ships bilingual interlinear reading (#56/#100): a per-book toggle renders each source paragraph followed by its translation in a muted style, backed by an AI provider, cached to disk. Android shipped the #118 AI provider foundation (provider store, OpenAI-compat + Anthropic SSE clients, chat/summary) but has **no bilingual capability**. Box D of the parity checklist requires the interlinear renderer + the bilingual setup sheet, building on #118.

The engineering questions are (a) **which render host(s)** get true interlinear, and (b) **where the entry point lives**. Both were mis-analysed in v1 and are corrected here:

- **Host** — v1 claimed EPUB interlinear is "infeasible inside Readium's navigator." **That is FALSE** (§3): `EpubNavigatorFragment.evaluateJavascript(script): String?` is a public suspend method in the shipped Readium 3.3.0 AAR (verified via `javap` — see §3), so the app CAN inject and clear translation DOM nodes in Readium's WebView. EPUB is therefore the **primary** target (it is the app's main reading format). TXT/MD are still built but as a phased choice, not because EPUB requires a fork.
- **Entry point** — v1 put the toggle in the bottom chrome. **The design puts it in the More-menu + a top-chrome pill** (`vreader-more.jsx`, `vreader-reader.jsx`), which are box-F surfaces — so #131's UI *entry wiring* depends on box F (§2, §4).

## 2. Surface area

### Render-host decision (corrected — see §3 for the full analysis)

**v1 targets TWO hosts, in dependency order:**

1. **EPUB (Readium `EpubNavigatorFragment`) — PRIMARY.** Interlinear IS feasible via `evaluateJavascript` (enumerate leaf blocks → inject translation nodes → clear on teardown/reflow), exactly mirroring iOS `EPUBBilingualOrchestrator`. This is validated first by **WI-0 (a Readium bilingual spike)** before the render WI is planned in detail, because JS injection into a navigator the app does not own has real unknowns (reflow, href changes, fragment recreation, pagination interaction).
2. **TXT/MD (Compose `TxtReaderActivity`) — INCLUDED.** Trivially injectable (a translation `Text` after each source chunk in the confirmed `items(count = document.chunkCount)` loop, which already interleaves highlight + TTS spans). No WebView; deterministically Compose-testable.

**AZW3 (foliate WebView)** and **PDF** remain follow-ups / out (§"Files OUT of scope").

**Why both, not TXT/MD-only:** the honest thesis is that the *pipeline* (segment → chunk → translate → cache → interleave) is host-agnostic and fully built in v1; only the *render injection* is host-specific. EPUB is the format most users read, so shipping box D without it would under-deliver on the visible capability. TXT/MD are included because the Compose host is the cheapest, most testable place to prove the pipeline end-to-end (no WebView, deterministic tree assertions) — it de-risks the EPUB render adapter. This is not the box-B/E "one host and check the box" split; box D ships EPUB + TXT/MD together, with AZW3/PDF as tracked follow-ups. **Box D cannot be checked on the false "EPUB requires a fork" rationale** — that rationale is discarded.

### New files

**Pipeline / domain (host-agnostic, pure or coroutine — JVM-testable):**

- `bilingual/TranslationUnitId.kt` — `data class TranslationUnitId(kind, value)` with `enum Kind { epubHref, foliateHref, txtChapterIndex, mdChapterIndex, pdfPageRange }`; `storageKey = "${kind.name}:$value"`. Mirrors iOS `TranslationUnitID.Kind` (verified: same five cases). v1 uses `epubHref` + `txtChapterIndex`/`mdChapterIndex`; others reserved so the cache-key format never breaks.
- `bilingual/TranslationGranularity.kt` — `enum { paragraph, sentence }`. (Design's Granularity segment.)
- `bilingual/BilingualLanguages.kt` — `BilingualLanguage(key, glyph, script)`; `BILINGUAL_LANGS` = the set from `vreader-bilingual.jsx` (`BILINGUAL_LANGS`) + `findOrDefault(key)`. Default `Chinese`.
- `bilingual/ChapterSegmenter.kt` — `paragraphs(text)` / `sentences(text)`. Port of iOS `ChapterSegmenter.paragraphs(in:)`/`sentences(in:)` (verified exists, CJK-aware via sentence enumeration).
- `bilingual/TranslationChunker.kt` — `chunk(segments, maxCharsPerChunk)` + `subSplit(text, maxChars)`. Port of iOS `ChapterTranslationChunker.chunk(...)` + `subSplit(...)` (verified: `chunk` returns `[[Int]]` index groups, oversize segment gets its own chunk; `subSplit` is the Bug #330 grapheme-safe over-budget splitter).
- `bilingual/TranslationChunkContract.kt` — `userPrompt(segments, targetLanguage, style)`; `decode(raw, expectedCount)` (strict JSON-array + code-fence strip); `sealed class DecodeError { NotAStringArray; CountMismatch(expected, actual) }`. Port of iOS `TranslationChunkContract` (verified: same `userPrompt`/`decode` shape, same two DecodeError cases).
- `bilingual/ChapterTextProvider.kt` — `interface { units(); sourceText(unit); unitContaining(locator); unitAfter(unit) }`. Resolution key is host-specific: TXT/MD key on `charOffsetUtf16` (Android `Locator` is offset-based there); EPUB keys on the current-resource `href` from `EpubNavigatorFragment.currentLocator`. Honest divergence from iOS's uniform Readium `Locator`, documented.
- `bilingual/TxtChapterTextProvider.kt` — provider over `TxtDocument` + chapter model. MD source = raw markdown chapter (translation renders as plain muted text, not re-markdown-rendered — matches the muted-secondary design line).
- `bilingual/EpubChapterTextProvider.kt` (WI-0-gated shape) — provider over the Readium `Publication` reading order; `units()` = spine hrefs, `unitContaining(locator)` = the locator's href. Its render-side collaborator (the JS enumerate/inject adapter) is defined by WI-0's findings, not pre-committed here.
- `bilingual/ChapterTranslationError.kt` — `sealed { Offline; TimedOut; ProviderFailed(msg); Cancelled }`. Maps from `AiError` (verified cases: `Auth401`, `RateLimited429`, `Offline`, `Timeout`, `Http(code)`, `Decode`, `Stream`, `InsecureUrl`, `Config`).
- `bilingual/ChapterTranslationService.kt` — `cachedTranslation(...)` (cache-only, no provider — #306 parity: a cached chapter renders even when AI is later unconfigured); `translate(...)` (segment → chunk → per-chunk `AiClient.chat` one-shot → `decode` → per-segment fallback → graceful per-chunk degrade (Bug #330 parity: a single failed chunk renders source-only and is NOT cached; all-chunks-fail throws) → cache-write only on full success). Uses `AiClient.chat(AiRequest)` (one-shot, NOT `streamChat`). Cancellation: `ensureActive()` between chunks AND immediately before the Room write (§6).
- `bilingual/ChapterTranslationPrefetcher.kt` — resolves the active profile from one `AiProviderStore.snapshot()` (`snapshot.active`), decrypts via `store.apiKey(profile)` (snapshot-consistent), builds an `AiClient` via an **injected factory param** (see the DI correction below), cache-first then translate. Throws `ChapterTranslationError`. Mirrors iOS `ChapterTranslationPrefetcher` (verified: iOS snapshots the active profile after a cache miss and is a Sendable struct capturing its collaborators).
- `bilingual/BilingualAiReadiness.kt` — `resolve(snapshot): Boolean` (active profile exists AND its decrypted key is non-empty). A cipher/decryption failure maps to **not-ready** (never crashes — §6), not to a thrown error. Drives the setup-sheet engine-strip configured/unconfigured state. Keep the gate to exactly what #118 enforces (no separate consent manager on Android — #118 has none; confirm during build).

**State / persistence:**

- `bilingual/PerBookBilingualStore.kt` — DataStore-Preferences, keyed by `bookFingerprintKey`, holding `{ enabled, targetLanguage, granularity }`. This is the Android `PerBookSettingsOverride` bilingual slice — the backup contract declares exactly `bilingualEnabled` / `bilingualTargetLanguage` / `bilingualGranularity` (verified in `PerBookSettings.swift` and the Android `BackupSectionsExtended.kt`), and **NO `bilingualStyle`** (verified — style is not a persisted per-book field on iOS either). So this store writes exactly those three fields. Wiring into backup collect/restore is scoped OUT (§7) — additive later, fields already in the contract; until then bilingual config is device-local.
- `bilingual/BilingualViewModel.kt` — `StateFlow<BilingualUiState>` with `enabled`, `targetLanguage`, `granularity`, `needsSetupSheet`, `aiConfigured`, `translationsByUnit`, `inFlightUnits`, `unavailableUnits`, `errorUnit`. Setters + `dismissSetupSheet`, `onPositionChanged(locator)`, `retryUnit(unit)`. Generation/epoch-guarded prefetch (current + next unit), cancellation on disable / language / granularity change — port of iOS `BilingualReadingViewModel` + `+Prefetch` (verified both exist). Split to `BilingualPrefetchController.kt` if it nears ~300 lines. (No `style` field — the authoritative sheet has no Style control; see §3.)

**Room (translation cache):**

- `data/ChapterTranslationEntity.kt` — `@Entity(tableName="chapter_translations", indices=[Index("bookKey")], foreignKeys=[FK→books.fingerprintKey ON DELETE CASCADE])`. **`@PrimaryKey val lookupKey: String`** (Room REQUIRES a primary key; a "unique index without a PK" does not compile — verified against `HighlightEntity`, which pairs a `@PrimaryKey` with a separate unique index). `lookupKey` = `bookKey|unitStorageKey|targetLanguage|promptVersion` (see the cache-identity correction below). Other columns: `bookKey`, `unitStorageKey`, `targetLanguage`, `promptVersion`, `translatedJson`, `sourceParagraphCount`, `createdAt`. Mirrors iOS `ChapterTranslationRecord.lookupKey` (verified: iOS key is `book|unit|lang|prompt`, profile-agnostic — Bug #342).
- `data/ChapterTranslationDao.kt` — `getByLookupKey(key)`, `@Upsert suspend fun upsert(row)` (Upsert identifies by PK = `lookupKey`, so it is a correct insert-or-replace by the cache identity), `deleteByLookupKey(key)`. The project's Room pattern is `@PrimaryKey` + `@Upsert` (verified: `BookDao.upsert`); making `lookupKey` the PK is exactly that pattern.
- `bilingual/ChapterTranslationStore.kt` — coroutine wrapper returning a Sendable `CachedTranslation` (segments decoded from JSON), keeping Room entities off the boundary (the `AnnotationsRepository`/`HighlightRecord`/iOS `ChapterTranslationStore` precedent).

**Cache-identity correction (audit HIGH — reconciled with iOS parity):** the audit asked to add granularity + style as key columns. iOS deliberately does the opposite — `ChapterTranslationRecord.lookupKey` is `book|unit|lang|promptVersion` and is profile-AGNOSTIC / granularity-AGNOSTIC / style-agnostic (Bug #342's fix was to *remove* dimensions from the key). Style is folded into the prompt content; granularity is a read-time count-check. **Resolution honoring both the audit's concern and iOS parity:** keep the 4-part key, but make `promptVersion` an **effective composite** that encodes the result-shaping inputs, e.g. `promptVersion = "bilingual-v1|g=${granularity}|s=${style}"` (iOS uses the literal `"bilingual-v1"` today because iOS forces `.paragraph` for bilingual and pins one style; Android carries granularity/style in the promptVersion string so a change re-keys correctly). Style is not a v1 user control (the authoritative sheet has none — §3), so `s=` is a constant this version; granularity IS user-selectable, so `g=` is load-bearing (a paragraph vs sentence translation is a different cache row — this also closes the iOS #344 "sentence silently ignored" class by construction). **Additionally** (audit's cancellation half): a granularity change must cancel in-flight jobs, bump the VM generation, clear shaped in-memory `translationsByUnit`, and force a correctly-keyed re-fetch — specified in WI-6.

**DI / factory correction (audit HIGH):** the audit is right that `AiProviderFactory` is NOT a lambda — verified it is an `object` with `create(profile: AiProviderProfile, apiKey: String, dispatcher: CoroutineDispatcher = Dispatchers.IO): AiClient`. So `ChapterTranslationPrefetcher` takes its OWN injected `clientFactory: (AiProviderProfile, String) -> AiClient` param **defaulting to `AiProviderFactory::create`** (production) and overridden with a fake in tests. The prefetcher builds the exact `AiRequest(model = profile.model, messages = …, temperature = profile.temperature, maxTokens = profile.maxTokens, system = …)` from the resolved profile (verified `AiRequest` fields).

**AppContainer / navigation correction (audit HIGH — genuine gap, NOT stale state):** verified against the real code — `AppContainer` does **NOT** provide `AiProviderStore` today, and there is **NO live navigation route to `AiProviderListScreen`** (MainActivity has no NavHost; the screen + store + `AiSettingsViewModel` exist from #118 but are only exercised by instrumented/round-trip tests — #118 was VERIFIED via component tests + a live SSE socket round-trip, not an in-app nav route). There is no `#119` row. Consequences for #131:
- #131 **adds `AiProviderStore` to `AppContainer`** (lazy singleton: DataStore + `KeystoreSecretCipher`, the #116/#118 pattern) — the prefetcher + readiness need it and nothing provides it yet.
- The setup-sheet unconfigured engine strip's **"Set up" CTA target does not exist in the running app.** #131 does NOT invent an AI-provider settings screen or its navigation (that is box-F chrome / a #118 follow-on, and inventing it violates rule 51). Until a live route to `AiProviderListScreen` ships, the "Set up" affordance is **design-gated** — see §3's design-gate list. #131 can ship the bilingual sheet's *configured* path (a provider already set via the tested path) end-to-end; the *unconfigured → Set up* nav is a stated dependency, not #131 scope.

**UI (Compose — every state depicted, reproducing `vreader-bilingual.jsx`):**

- `bilingual/BilingualSetupSheet.kt` — reproduces `vreader-bilingual.jsx`'s `BilingualSetupSheet` EXACTLY: header Cancel / Translate; a **preview strip**; a **language grid** over `BILINGUAL_LANGS` (glyph tiles, selected accent); a **Granularity** segmented control (Paragraph "Translate after each ¶" / Sentence "Translate after each sentence"); a **Translation engine** strip (configured: "Claude · with this book's context" + "Change…"; unconfigured: "No AI provider configured" + "Set up"). **No Style control, no provider/model card, no term-overrides toggle, no cost footer** — those belong to the *other* (`vreader-ai-android.jsx`) sheet, which this plan does not reproduce (§3).
- `bilingual/BilingualInterlinearBody.kt` — per source chunk/paragraph: source `Text` then translation `Text` muted with accent left-border, `fontSize*0.88`, CJK font for cjk scripts, RTL handling for Arabic script. Consumes `translationsByUnit`. Loading state ("Translating chapter… N%" + per-paragraph dim — matches the design's chapter-level "38%"). Error state ("Couldn't translate" + Retry). Partial/offline (`unavailableUnits`): source-only silent fallback (design's original-always-kept guarantee — iOS Decision 2). This is the render surface for BOTH the TXT/MD Compose loop and (via the WI-0 adapter) the EPUB injection payload's Kotlin-side state.
- `bilingual/BilingualPill.kt` — the `EN ↔ 中` reader-**top-chrome** pill (per `vreader-reader.jsx` `ReaderTopChrome` + `vreader-bilingual.jsx` `BilingualPill`). Rendered by box F's top chrome; #131 provides the composable, box F wires it in (§4).

### Modified files

- `data/VReaderDatabase.kt` — add `ChapterTranslationEntity`, bump `version` (allocated version-at-slot; **v5 today** — verified, so v5→v6, but the number is set at the merge slot, not pre-assigned), add `MIGRATION_5_6` (CREATE TABLE + `bookKey` index + FK CASCADE, DDL exactly matching Room's generated schema), append `ALL_MIGRATIONS`, add `abstract fun chapterTranslationDao()`.
- `reader/TxtReaderActivity.kt` — own a `BilingualViewModel`; collect state; pass into `TxtBody`; on position change call `vm.onPositionChanged(...)`; render `BilingualInterlinearBody` output in the `items(count = document.chunkCount)` loop when bilingual is on and a translation exists (the confirmed injection point — verified it already interleaves highlight washes + TTS spans per chunk). Strictly gated to `originalFormat ∈ {txt, md}`; disabled = body byte-unchanged. **This file overlaps #129's TXT/MD WIs → gated on #129's FINAL merge (§4).**
- `reader/ReaderActivity.kt` (Readium EPUB) — WI-0-gated: attach the JS enumerate/inject adapter to `navigator.evaluateJavascript`, re-apply on href change / reflow, clear on teardown. Concrete surface defined by WI-0's spike output.
- `VReaderApp.kt` / `AppContainer` — **provide `AiProviderStore`** (new — see the AppContainer correction), `ChapterTranslationStore`, `PerBookBilingualStore`, and a `BilingualViewModel` factory. Mirrors #116/#118/#122 DI.

**NOT modified (audit HIGH — Translate slot removed):** `reader/chrome/ReaderBottomChrome.kt` gets **no** bilingual/Translate slot. v1 wrongly added `onOpenBilingual` there; the design's entry is the More-menu toggle + the top-chrome pill (box F), NOT a bottom-chrome slot. `ReaderBottomChrome`'s existing `extraSlot` (the #129/#121 read-aloud entry) is untouched.

### Files OUT of scope for v1

- **`Azw3ReaderActivity.kt` / `reader/foliate/`** — foliate WebView interlinear IS feasible (JS enumerate+inject in the pinned bundle, mirroring iOS `FoliateBilingualOrchestrator`) but deferred to a follow-up (bundle-patch JS + secure-bridge additions touching the security-sensitive #126 surface). Once WI-0 proves the EPUB JS pipeline, the foliate host reuses it with a bundle adapter.
- **`PdfReaderActivity.kt`** — no reflowable text layer. Out (the `pdfPageRange` Kind is reserved only).
- **Live AI-provider settings navigation / the "Set up" destination screen** — box-F chrome / #118 follow-on; #131 does not invent it (rule 51). Design-gated dependency (§3).
- **Backup collect/restore of `PerBookSettingsOverride` bilingual fields** — contract fields exist; wiring is a small additive follow-up (§7). Bilingual config is device-local until then.
- **"Translate entire book…" batch, re-translate/style-swap picker, cost/token estimation, term-overrides** — iOS/`vreader-ai-android.jsx` extras not in the authoritative `vreader-bilingual.jsx` sheet. Out.
- **Streaming translation progress** — the design's "38%" is chapter-level N-of-M chunk progress (from the chunker count), not token streaming. v1 shows N-of-M.

## 3. Prior art / project precedent / rejected alternatives

### The render-host decision (analysis — CORRECTED from v1)

**How iOS does interlinear:** iOS renders EPUB/AZW3 in a WKWebView it fully controls. `EPUBBilingualOrchestrator` injects JS that (1) enumerates leaf blocks (`<p>/<li>/<blockquote>`) posting `[{bid,text}]` to Swift, (2) after translation injects a translation node after each block. TXT/MD render in a `UITextView`/attributed-string path where the renderer interleaves translation runs. The mechanism = **the app inserts translation nodes between source nodes.**

**Android host-by-host injectability — the v1 verdict was WRONG for EPUB:**

| Host | Layout tree owner | Content-insertion API | Interlinear feasible? |
|---|---|---|---|
| **Readium EPUB** (`EpubNavigatorFragment`) | Readium (internal WebView) | **`evaluateJavascript(script): String?`** is PUBLIC on the fragment (shipped 3.3.0 AAR) → arbitrary DOM read/write. Plus `currentLocator` (href), `firstVisibleElementLocator`, decorations (Highlight/Underline over existing text). | **YES — via JS injection** (not just decorations) |
| **TXT/MD Compose** (`TxtReaderActivity`) | The app (`LazyColumn` over chunks) | Trivial — a translation `Text` after each source `Text` in the confirmed `items{}` loop | **YES** |
| **AZW3 foliate** (`FoliateBridge` WebView) | The app (pinned foliate-js bundle) | Full DOM control via the bridge (same as iOS) | YES, but needs bundle-JS → follow-up |

**Verification of the CRITICAL correction:** `javap -public org.readium.r2.navigator.epub.EpubNavigatorFragment` against the resolved AAR (`~/.gradle/caches/.../readium-navigator/3.3.0/.../readium-navigator-3.3.0.aar`) prints:
```
public final java.lang.Object evaluateJavascript(java.lang.String, kotlin.coroutines.Continuation<? super java.lang.String>);
public kotlinx.coroutines.flow.StateFlow<org.readium.r2.shared.publication.Locator> getCurrentLocator();
public java.lang.Object firstVisibleElementLocator(kotlin.coroutines.Continuation<...>);
```
i.e. `suspend fun evaluateJavascript(String): String?` exists. The app already holds the concrete fragment as `ReaderActivity.navigator` (it uses it for decorations/selection in #123). So EPUB interlinear via JS injection is feasible with the public API — **no Readium fork.** The v1 "infeasible inside Readium's navigator" rationale is discarded.

**Chosen: EPUB (Readium JS-injection) as the PRIMARY host + TXT/MD (Compose) included.** WI-0 spikes the EPUB path first (it has the real unknowns); the Compose host is built alongside as the deterministic pipeline proof. AZW3/PDF deferred.

**WI-0 — Readium bilingual spike (new, gates the EPUB render WI):** a throwaway harness that, against a real EPUB on the emulator, proves:
- (a) **enumerate** current-resource leaf blocks via `navigator.evaluateJavascript(enumScript)` returning a JSON `[{id,text}]` array (parse the `String?` result);
- (b) **inject** translation DOM nodes after each block, and **clear** them, via `evaluateJavascript`;
- (c) **re-apply** after `currentLocator` href changes / reflow / page-fragment recreation (the WebView pager recreates fragments — injection must survive or re-fire);
- (d) measure effects on **pagination/scroll** (does injecting content re-paginate? does it shift the reader's position?) and whether the **enumerated block count** diverges from `ChapterSegmenter` (the iOS #268 divergence class — if it diverges, adopt iOS's `translatePreSegmented` direct-block path).

If WI-0 shows injection is stable → the EPUB render WI proceeds. If WI-0 surfaces a blocker (e.g. fragment recreation wipes injected nodes with no re-fire hook) → EPUB drops to a tracked follow-up and box D ships on TXT/MD (the phasing fallback), with the honest reason (a specific spike finding), never the false "requires a fork" claim.

**Rejected alternatives:**
1. **Readium interlinear via decorations only** — REJECTED (insufficient). Decorations style existing text; they cannot insert translation paragraphs. But `evaluateJavascript` (above) makes injection possible without decorations, so EPUB is feasible — it just uses the JS seam, not the decoration seam.
2. **Forking Readium** — REJECTED + unnecessary (the public `evaluateJavascript` seam exists).
3. **AZW3 foliate host first** — REJECTED for v1 (deferred, not dead). Feasible + design-aligned, but touches the security-sensitive #126 bridge; EPUB via the same JS-injection mechanism is the higher-value primary.
4. **Eager whole-book pre-translation** — REJECTED (cost/latency). iOS lazily prefetches current+next + caches — port that.

### The setup-sheet resolution (audit HIGH — rule 51)

There are **two committed, differently-shaped** `BilingualSetupSheet`s:
- `vreader-bilingual.jsx` → **language grid + Granularity (Paragraph/Sentence) + preview strip + Translation-engine strip (Set up/Change) + Cancel/Translate** header. **No Style, no provider/model card, no term-overrides, no cost.**
- `vreader-ai-android.jsx` → **Languages (From/To) + Provider (provider/model card) + Style (Literal/Natural/Literary) + Keep-term-overrides toggle + cost footer.** **No language grid, no Granularity, no preview.**

v1 merged both into a **third layout** — a rule-51 violation (self-designed UI). **Resolution:** this plan reproduces the **`vreader-bilingual.jsx` sheet EXACTLY** as the authoritative Android-native bilingual sheet (its language grid + granularity + preview + engine strip + CTA is the coherent bilingual-config surface, and its `BilingualPill`/`BilingualPageContent` are the matching reader surfaces). **Style is dropped from v1** (it is not in the authoritative sheet, and — verified — `bilingualStyle` is not a persisted contract field on either platform). Consequently the store/VM carry no `style`, and `promptVersion`'s `s=` component is a constant (§2 cache-identity correction).

**Remaining design gate (rule 51):** a single Android sheet that offers **BOTH Style AND Granularity** (the union the `vreader-ai-android.jsx` "Style" and `vreader-bilingual.jsx` "Granularity" controls imply) is **not depicted anywhere** — no committed bundle shows both in one sheet. If style is wanted on Android as a user control, that needs an **updated committed design**. This plan does NOT invent it; it files a `needs-design` gate (see the §"Design gates" list) and ships the authoritative granularity-only sheet meanwhile.

### Other precedents applied

- **#118 provider seam**: reuse `AiProviderStore.snapshot()` (`snapshot.active`) + `store.apiKey(profile)` + `AiProviderFactory.create` (as the default of an injected factory param) + `AiClient.chat`. Prefetcher + readiness are the only new consumers; #118's AI files are unchanged; #131 additionally *wires* `AiProviderStore` into `AppContainer` (which #118 never did).
- **Room additive-migration pattern** (#122/#123/#127): version bump + `MIGRATION_n_(n+1)` + exact-DDL + `VReaderDatabaseMigrationTest` PRAGMA guard. `@PrimaryKey` + `@Upsert` is the project's DAO pattern (`BookDao`).
- **DataStore JSON-in-Preferences** for `PerBookBilingualStore` (the `ReaderSettingsStore`/`AiProviderStore` pattern).
- **Pure-logic port**: iOS `ChapterSegmenter`/`ChapterTranslationChunker`/`TranslationChunkContract` are pure + heavily unit-tested — direct Kotlin ports with the same test vectors (all verified to exist).
- **Entry point via box F**: the More-menu bilingual toggle + top-chrome pill are box-F surfaces; #131 depends on them (§4), mirroring how box B's annotations-review-sheet + bookmark "ride with item F."

## 4. Work-item sequencing

Foundational WI-1..4 (no UI, JVM-testable); a spike WI-0 (EPUB); behavioral WI-5..9. Each WI = one PR.

**Dependency notes (audit HIGH — v1's graph was wrong):**
- WI-3 depends on WI-1 (+2). WI-4 depends on WI-1+WI-3. WI-6 depends on WI-5. So WI-1..4 are NOT all independent — the graph below states the real edges.
- **`Deps: [feat:#134, feat:#132]`** (transitively #129, #118) — box F is not yet decomposed (per `docs/parity/android-checklist.md`, box F "likely splits into ≥2 features: TOC/bookmarks; find-in-book; more-menu/details/share"); **#132 = the top-chrome sub-feature, #134 = the More-menu sub-feature** are the prospective box-F IDs this plan reserves. **#131's UI entry-point WIs (the pill mount + the More-menu toggle wiring) cannot ship until box F provides those surfaces.** The pipeline + setup sheet + interlinear render (WI-0..7) are built ahead; only the entry wiring (part of WI-9) waits on box F.
- **Host-integration WIs are gated on #129's FINAL merge** — #129 owns `TxtReaderActivity`/`ReaderBottomChrome`; #131's `TxtReaderActivity` edit must land on top of #129's TXT/MD typography WIs (rule 48 one-writer-per-file).

**WI-0 (spike): Readium EPUB bilingual injection.** The harness in §3 (enumerate / inject+clear / re-apply on reflow / pagination + count-divergence measurement). Output: a go/no-go on EPUB-in-v1 + the concrete `EpubChapterTextProvider` + injection-adapter surface. Deps: none (uses the existing #106 Readium host). Not TDD-gated (throwaway spike); its findings feed WI-7b's plan.

**WI-1 (foundational): value types + pure segmentation/chunk/contract.** `TranslationUnitId`, `TranslationGranularity`, `BilingualLanguages`, `ChapterSegmenter`, `TranslationChunker`, `TranslationChunkContract`, `ChapterTranslationError`. Pure; ported iOS vectors. No Android deps. Deps: none.

**WI-2 (foundational): Room translation cache.** `ChapterTranslationEntity` (PK = `lookupKey`) + `Dao` (`@Upsert`) + `ChapterTranslationStore`; `VReaderDatabase` migration (number at slot). Robolectric migration round-trip + upsert/get/delete-by-lookupKey + FK-CASCADE + exact-DDL guard. Deps: none.

**WI-3 (foundational): `ChapterTranslationService`** against a fake `AiClient`. `cachedTranslation` (cache-only) + `translate` (per-chunk `chat`, per-segment decode-fail fallback, per-chunk graceful degrade, cancellation between chunks + before write, cache-write only on full success). Deps: **WI-1, WI-2**. Tests: cache hit → zero client calls; miss → translate + write; decode fail → per-segment fallback; one-chunk fail → source-only that chunk (others translated, NOT cached); all-chunks fail → throw; cancellation → `Cancelled` (no write); `AiError` mapping incl. `Config`/`InsecureUrl` → `ProviderFailed`.

**WI-4 (foundational): `ChapterTextProvider` (TXT/MD) + `ChapterTranslationPrefetcher` + `BilingualAiReadiness`.** Provider slices per chapter from `TxtDocument`; `unitContaining`/`unitAfter`. Prefetcher resolves active profile from `snapshot()`, decrypts snapshot-consistent, builds client via the **injected factory param** (default `AiProviderFactory::create`), constructs `AiRequest` from the profile, cache-first then translate. Readiness = active profile with non-empty decrypted key; **cipher failure → not-ready, never a crash.** Fake store + fake factory. Deps: **WI-1, WI-3**. Tests: unit resolution + clamp + empty; cache-hit-no-profile still returns (#306); no-profile miss → `ProviderFailed`; readiness true/false; cipher-throw → readiness false (no crash).

**WI-5 (behavioral): `PerBookBilingualStore` + `BilingualViewModel` state core.** Store per book (enabled/targetLanguage/granularity — no style); VM setters (persist + first-enable `needsSetupSheet`), language/granularity change clears cache-shaped state + bumps generation, the state fields. Turbine tests: first-enable raises sheet; re-enable persisted does not; disable clears; language change resets; granularity change resets + re-keys; round-trip through store. Deps: **WI-1** (+ store).

**WI-6 (behavioral): VM prefetch trigger + generation/cancellation.** `onPositionChanged` derives current unit, dedupes, prefetches current+next; a **monotonic position-request sequence** checked after every suspension; **per-unit generation tokens**; a **captured language/granularity/provider snapshot per launch**; generation bumps on disable/language/granularity/unit-change discard stale; `CancellationException` handled BEFORE generic error mapping; `Offline`→`unavailableUnits`; transient failure leaves unit unfetched + clears anchor to retry; `retryUnit`. Fake prefetcher. Deps: **WI-4, WI-5**. Tests: current+next on unit change; same-unit no-op; cancel-mid discards stale; offline→unavailable; failure→retry-able; `retryUnit` re-fetches; granularity change cancels + re-fetches under the new key.

**WI-7a (behavioral): Compose UI — setup sheet + interlinear body + pill.** Reproduce `vreader-bilingual.jsx` (setup sheet: language grid / granularity / preview / engine strip configured+unconfigured; body: translated / loading N%+dimmed / error+Retry / offline source-only; pill). Light+dark. Compose UI tests each state. Deps: **WI-5** (state shape). NO Style control; the unconfigured "Set up" CTA renders but its nav target is design-gated (§3).

**WI-7b (behavioral): EPUB render adapter** (only if WI-0 = go). The JS enumerate/inject adapter + `EpubChapterTextProvider`, wired into `ReaderActivity`, driving `BilingualInterlinearBody` state from injected content. Deps: **WI-0, WI-3, WI-4, WI-7a**. Connected test on a real EPUB (seeded cache): enable → interlinear injects; disable → nodes cleared; reflow/href-change re-applies. (If WI-0 = no-go, this WI is dropped and box D ships TXT/MD-only, tracked.)

**WI-8 (behavioral): `TxtReaderActivity` integration.** Wire VM into `TxtBody` loop + position-change + setup-sheet + DI (incl. adding `AiProviderStore` to `AppContainer`). `originalFormat`-gated (TXT/MD). **Gated on #129's final merge.** Connected test (fake `AiClient` seam): enable → setup → confirm → interlinear from seeded cache; disable → source-only byte-parity; reopen persists enabled + renders from cache with zero client calls. Deps: **WI-6, WI-7a, #129 final**.

**WI-9 (behavioral): entry wiring + acceptance.** Mount `BilingualPill` in box F's top chrome; wire the More-menu bilingual toggle (box F) to the VM. **Gated on `feat:#132` (top chrome) + `feat:#134` (More menu).** Full acceptance pass across EPUB (if WI-7b landed) + TXT/MD. Flip box D note; update `docs/architecture.md` (bilingual pipeline + the new `chapter_translations` schema + `AiProviderStore` now in `AppContainer`). → DONE. Deps: **WI-8, WI-7b (if go), feat:#132, feat:#134**.

## 5. Test catalogue

JVM/Robolectric (`android/app/src/test/...bilingual/`): `ChapterSegmenterTest` (paragraph blank-line; sentence CJK 。！？ vs Latin; empty→[]; single); `TranslationChunkerTest` (packs to budget; oversize→own chunk+subSplit; empty→[]); `TranslationChunkContractTest` (prompt per style-constant; strict JSON decode; code-fence strip; count mismatch→`CountMismatch`; non-array→`NotAStringArray`); `ChapterTranslationServiceTest` (cache hit 0 calls; miss→translate→write; decode-fail per-segment fallback; one-chunk-fail partial-not-cached; all-fail→throw; cancellation→Cancelled no write; ensureActive-before-write; offline/timeout/429/http/config/insecure→error mapping; very long chapter N-of-M; stale-cache count-mismatch re-translates); `ChapterTranslationErrorMappingTest`; `TxtChapterTextProviderTest` (resolution; clamp-past-end; empty; unitAfter end→null); `ChapterTranslationPrefetcherTest` (snapshot-consistent profile+key; injected-factory used; `AiRequest` built from profile; cache-hit-no-profile #306; no-profile miss→ProviderFailed; CJK↔English + Latin round-trip via fake; cipher-throw→ProviderFailed not crash); `BilingualAiReadinessTest` (active+key→true; no active→false; empty key→false; **cipher-throw→false, no crash**); `PerBookBilingualStoreTest` (enabled/lang/granularity round-trip; no style field); `BilingualViewModelTest` (Turbine: first-enable sheet; re-enable no-sheet; disable clears; language reset; **granularity reset + re-key**; prefetch current+next; same-unit no-op; cancel-mid discards; offline→unavailable; error→errorUnit+retry; `retryUnit`; generation bump on style-N/A—granularity change).

Room migration: `VReaderDatabaseMigrationTest` (extend) vPrev→vNext + full-chain + FK-CASCADE + `lookupKey`-as-PK; `ChapterTranslationDaoTest` (upsert-by-PK replaces; get/delete-by-lookupKey).

Compose UI (`androidTest/...bilingual/`): `BilingualSetupSheetUiTest` (language grid, granularity, preview, engine configured vs unconfigured; **no Style control present**; light+dark); `BilingualInterlinearBodyUiTest` (translated incl. CJK font + RTL Arabic; loading N%+dimmed; error+Retry; offline source-only; empty translation→source-only no crash); `BilingualPillUiTest`.

Connected (`androidTest/...reader/`): `TxtReaderBilingualConnectedTest` (API 35, fake `AiClient` via injected factory): enable→setup→confirm→interlinear from seeded Room cache; disable→source-only byte-parity; reopen persists enabled + renders from cache with zero client calls; TXT/MD gated (PDF inert); very long chapter scroll responsive; cancellation leaves no partial cache row. `EpubReaderBilingualConnectedTest` (only if WI-0=go): enable→inject on a real EPUB; disable→clear; href-change→re-apply; count-divergence handled.

Edge cases: empty translation, failed, partial per-chunk, CJK↔English + Latin + RTL, provider error/timeout/429/config/insecure, cancellation mid-translation + before-write, very long chapters, offline (cache-first + silent source-only), cipher-decrypt failure → not-ready (no crash).

## 6. Risks + mitigations

- **Live-translation verification is AI-credential-gated (the box-D caveat).** The whole pipeline is verified without live creds via a deterministic **fake `AiClient`** injected through the prefetcher's `clientFactory` param (default `AiProviderFactory::create`; tests override). WI-3/4/8 prove segment→chunk→decode→cache→interleave end-to-end incl. every error/edge path. The connected test seeds the Room cache directly and asserts render-from-cache with zero client calls (render path proven offline). **This mock/integration path is the box-D-required verification path** (the checklist states live translation is credential-gated); an optional live smoke confirms wire format but is NOT a gate.
- **Acceptance proves BOTH cache-render AND the live pipeline path (via the fake).** WI-8's connected test drives the full enable→translate(fake)→cache→render→reopen cycle, not just cache rendering — the fake stands in only for the network leaf.
- **EPUB JS-injection unknowns.** WI-0 de-risks before the render WI: pagination shift, fragment recreation wiping nodes, enumerate-vs-`ChapterSegmenter` count divergence (iOS #268). If a hard blocker appears, EPUB drops to a tracked follow-up (phasing fallback) with the specific spike reason — never the false "requires a fork."
- **Concurrency (audit HIGH — was under-specified).** WI-6 adds: a monotonic position-request sequence checked after every suspension; per-unit generation tokens; a captured language/granularity/provider snapshot per launch; cancellation on granularity change; `CancellationException` handled BEFORE generic error mapping; `ensureActive()` immediately before the Room write; cipher/decrypt failures mapped to unconfigured/provider-failure (never a crash). Snapshot-consistent profile+key pairing (from one `snapshot()`) is preserved.
- **Segment↔render count divergence** (iOS Bugs #268/#330/#344). TXT/MD segment through the SAME `ChapterSegmenter` on translate + render sides, so 1:1 pairing holds by construction; granularity is in the cache key so a paragraph row is never read as sentences. EPUB uses WI-0's finding (direct-block path if enumerate diverges — iOS `translatePreSegmented` parity).
- **Cost/latency of translating on scroll.** Lazy current+next prefetch + disk cache; N-of-M progress; cancellation on navigate-away/generation-bump.
- **Provider JSON non-compliance.** `TranslationChunkContract.decode` + per-segment fallback (iOS parity) — never drops a paragraph.
- **DataStore per-book key growth.** One Preferences entry per book keyed by fingerprint; scales like `ReaderSettingsStore`/`AiProviderStore`.

## 7. Backward compat

- **Room migration additive** (new `chapter_translations`, FK CASCADE, `lookupKey` PK). Existing rows untouched; migration + structural test guard it. Version number allocated at the merge slot (v5 today → v6).
- **Reader unchanged when bilingual off** — `TxtBody` render loop byte-identical unless `enabled && format∈{txt,md} && translation present`. `ReaderBottomChrome` is **not modified** (v1's Translate slot removed), so #129's chrome is unaffected. EPUB render adapter is inert unless bilingual is on.
- **#118 AI provider files unchanged** — the prefetcher/readiness are new consumers; the only #118-adjacent change is *wiring* `AiProviderStore` into `AppContainer` (which #118 left unwired — it was component/round-trip-verified, not nav-integrated).
- **Backup contract already compatible** — `PerBookSettingsOverride.bilingualEnabled/TargetLanguage/Granularity` exist (verified; **no `bilingualStyle`**), and there is **no translation-cache section** in `contracts/vectors/backup-sections.json` (verified — the cache is device-local, re-derivable). v1 introduces the store that writes the three fields locally; backup collect/restore of them is a small additive follow-up (no contract change), out of v1 scope; until then bilingual config is device-local (safe default). The `PerBookBilingualStore` is confirmed device-local; backup-collect/restore is the scoped-out follow-up.

## Design gates (rule 51 — for `needs-design` filing)

1. **"Bilingual mode" setup sheet with BOTH Style AND Granularity in one Android sheet** — `vreader-bilingual.jsx` depicts Granularity (no Style); `vreader-ai-android.jsx` depicts Style (no Granularity); no committed bundle shows both together. v1 reproduces the granularity-only `vreader-bilingual.jsx` sheet and DROPS Style. If Style is wanted as an Android user control, file `Design needed: bilingual setup sheet (Style + Granularity) for feature #131`. **This is the one open design gate for #131.**
2. **Dependency gate (not a #131 design gate, but blocks the "Set up" affordance)** — the setup sheet's unconfigured "Set up" CTA has no live nav destination (`AiProviderListScreen` is unreachable in-app today; no `#119`). #131 does not invent it (box-F chrome / #118 follow-on); the CTA renders but is wired only once that route ships.

## Revision history

- v1 (2026-07-10): Gate-1 draft (Plan agent). Gate-2 Codex audit pending.
- v2 (2026-07-11): Gate-2 round-1 REDESIGN resolved — Readium-feasibility corrected, entry-point rebased on box F, setup-sheet design-gated, DI/cache/concurrency fixed.
