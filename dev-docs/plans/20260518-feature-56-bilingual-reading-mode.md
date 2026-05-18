# Feature #56 — Bilingual reading mode (EPUB interlinear)

> Plan doc — Gate 1 artifact for `.claude/rules/47-feature-workflow.md`.
> Feature row: `docs/features.md` #56. GH: #629.
> Design source: `dev-docs/designs/vreader-fidelity-v1/project/design-notes/feature-60-followups.md` §2 (+ `vreader-bilingual.jsx`).
> Status: TODO → (PLANNED after Gate 2).

## Problem

Feature #18 translates a *selected passage* inside the AI panel — point-in-time,
in-memory, one tap at a time. Users reading a foreign-language book want the
whole text translated as they read, without asking paragraph by paragraph.

Bilingual reading mode is a per-book toggle: when on, every source paragraph in
the **EPUB** reader is followed inline by its AI translation in a smaller, muted
style (paragraph-interlinear, design §2.1). Translations are cached to disk so
they survive app restarts and cost no repeat API calls.

## Scope decisions (read first — these changed after the Gate 2 audit)

The #56 feature row (`docs/features.md`) predates the design and scopes four
parts across five formats. The Gate 2 audit (round 1, Codex `019e37c5`) found
that (a) TXT/MD interlinear is a far deeper change than a "modest offset-map
extension" — the text readers assume source-UTF16-offset invariants through
bridge delegates, chapter-local helpers, chunked TXT, paged MD, persisted-
highlight hit-testing, and TTS; and (b) the plan's completion semantics
conflicted with the row's full scope. The plan is therefore **narrowed and
re-scoped**:

1. **Interlinear, not chapter-block.** Design §2.1 supersedes the row's
   "chapter-block" sketch: translation after *each* source paragraph,
   `~0.88×` font-size, color `sub`, upright, indented `1×`. Chapter headings
   not translated; drop-cap stays on the source.

2. **EPUB only.** This feature ships interlinear bilingual reading for **EPUB**.
   EPUB is the one format whose source paragraphs are genuine discrete DOM nodes
   (`<p>`), so translation can be injected without disturbing the text model.
   - **TXT / MD** — moved to a follow-up feature. Their flat single-run
     `NSAttributedString` has no paragraph model and every highlight / reading
     position / TTS offset is a source-UTF16 index; interleaving translation
     shifts all of them. That is a feature-sized subsystem change (a proper
     source↔display *segment* map distinguishing source-backed vs synthetic
     ranges), not a WI of this feature.
   - **AZW3/MOBI (Foliate)** — follow-up. Needs new JS in the vendored
     `foliate-bundle.js` `readerAPI`; foliate-js owns CFI/pagination.
   - **PDF** — out of scope permanently for interlinear (fixed-layout glyphs,
     no reflowable paragraph). Any PDF treatment needs its own design.

3. **Core only.** Parts (3) "translate entire book" and (4) per-chapter
   re-translation + provider override are follow-up scope. #56 delivers the
   per-book toggle + on-demand current/next-chapter translation + cache +
   setup sheet + More-menu row + pill.

**Tracker narrowing — done atomically with the PLANNED flip** (Gate 2 finding
F6). The `docs/features.md` #56 row currently carries the old broad
5-format/4-part scope. Narrowing it to this EPUB-interlinear-core scope, and
filing the follow-up row for the carve-outs, is performed **in the same
`docs/features.md` write that flips #56 TODO→PLANNED** — one atomic changeset.
The narrowing cannot precede Gate 2 (the plan's scope is exactly what Gate 2
ratifies, so an earlier edit would narrow against an unratified plan); binding
it to the PLANNED-flip edit is the earliest point the gate model permits and
leaves **no interval** where a ratified (PLANNED) plan and an un-narrowed #56
row coexist. #56 is never marked complete against the broader row text — WI-9
flips a row that, by then, already reads EPUB-interlinear-core.

## Surface area

### New files

| File | What |
|---|---|
| `vreader/Models/Migration/SchemaV7.swift` | `enum SchemaV7: VersionedSchema`, `Version(7,0,0)`, `models` = SchemaV6's 10 + `BilingualTranslation`. |
| `vreader/Models/BilingualTranslation.swift` | New `@Model final class BilingualTranslation` — the disk cache entry. Fields: `lookupKey: String` (`@Attribute(.unique)` — the persisted, indexed dedupe key), `bookFingerprintKey: String`, `paragraphHash: String`, `targetLanguage: String`, `providerProfileID: UUID` (matches `ProviderProfile.id`'s type — Gate 2 F-medium; SwiftData stores `UUID` natively), `promptVersion: String`, `translatedText: String`, `createdAt: Date`. `lookupKey` is a **stored** primitive joined at insert time from the 5 identity fields (`providerProfileID` contributes its `.uuidString`), not a computed property — fetched/deduped by `lookupKey` directly. Cache is **per-book** (`bookFingerprintKey` is part of the identity), so `deleteTranslations(forBookWithKey:)` is correct and unambiguous. No relationship to `Book` — independent entity (SchemaV4 `ContentReplacementRule` precedent → lightweight migration, no `MigrationStage`). |
| `vreader/Services/PersistenceActor+Translations.swift` | `extension PersistenceActor` — `fetchTranslations(lookupKeys:) async -> [String: BilingualTranslationRecord]` (batch), `upsertTranslations(_:) async throws`, `deleteTranslations(forBookWithKey:) async throws`. Returns value-type `BilingualTranslationRecord` DTOs (`providerProfileID: UUID`), never the `@Model`. |
| `vreader/Services/AI/BilingualChunker.swift` | Pure utility — `static func chunk(paragraphs:maxCharsPerChunk:) -> [[Int]]` grouping paragraph indices into chunks under the provider char budget; never splits a paragraph across chunks. Pure → parameterized tests. |
| `vreader/Services/AI/BilingualTranslationService.swift` | `actor BilingualTranslationService` — input: an ordered `[BilingualParagraph]` (`id`, `sourceText`) for a chapter. Reads the cache (`PersistenceActor`, batch by `lookupKey`); for cache misses: pins the provider **once** via `AIService.pinActiveProvider()` (see the `AIService` row below — this is a real one-snapshot seam, not a re-check), chunks the misses (`BilingualChunker`), and issues one `AIService.sendRequest(_:using: pinned)` per chunk. The chunk request's `userPrompt` instructs the model to return **only a JSON array of N translated strings, same order**; the service strictly `JSONDecoder`-decodes `AIResponse.content` into `[String]` and asserts `count == chunk.count` — on any decode/count mismatch it falls back to one-paragraph-per-request (still under the same `pinned`). Writes results to the cache as each chunk lands (partial failure leaves prior chunks cached). Returns `[paragraphID: String]`. |
| `vreader/ViewModels/BilingualReadingViewModel.swift` | `@Observable @MainActor final class` — owns bilingual state for the open EPUB: `isEnabled`, `targetLanguage`, `translationsByParagraphID` (id == the stamped `data-vreader-bid`), `isFetching`, `needsSetupSheet`, and an injected ordered `chapterHrefs: [String]` (WI-8's EPUB host supplies the real list). Drives the EPUB renderer. **Chapter-aware trigger** (Gate 2 F-medium — `.readerPositionDidChange` fires continuously *within* a chapter): the VM derives the current chapter `href` from the position `Locator`, dedupes via `lastTriggerHref: String?` + `inFlightHrefs: Set<String>`, and prefetches the current + next chapter only when the chapter actually changes — same-chapter scroll posts are no-ops. **Epoch-guarded**: an `epoch` counter increments on disable / book-change / chapter-change / `onDisappear`; every prefetch `Task` captures its epoch, is cancelled on those events, and discards stale-epoch results. An epoch bump for disable/book-change also clears `lastTriggerHref` + `inFlightHrefs`. |
| `vreader/Views/Reader/BilingualSetupSheet.swift` | SwiftUI half-sheet (design §2.2): target-language picker (9 languages), Paragraph/Sentence segmented control (Sentence rendered disabled + "Coming soon" — follow-up), read-only AI-provider chip linking to Settings. |
| `vreader/Views/Reader/BilingualPill.swift` | The `EN ↔ 中` reader-top-chrome pill subview (design §2.1). |
| `vreader/Views/Reader/EPUBBilingualJS.swift` | `extension EPUBWebViewBridge` static JS, **alongside `EPUBWebViewBridge.swift` in `Views/Reader/`** — (1) `bilingualEnumerateJS()` walks the spine document's translatable block nodes, stamps each with a stable `data-vreader-bid` attribute, and returns `[{bid, text}]` to Swift; (2) `bilingualInjectJS(translationsByBid:)` appends a styled, **non-selectable, CFI-excluded** `<div class="vreader-bilingual" data-vreader-decoration>` after each stamped block; (3) `bilingualClearJS()` removes them. All interpolation via `FoliateJSEscaper.escapeForJSString`. |

### Modified files

| File | Change |
|---|---|
| `vreader/App/VReaderApp.swift:84` | `Schema(SchemaV6.models)` → `Schema(SchemaV7.models)`. |
| `vreader/Models/Migration/SchemaV1.swift` (`VReaderMigrationPlan`) | Append `SchemaV7.self` to `schemas`. |
| `vreader/Services/AI/AIService.swift` | **New provider-pin seam** (Gate 2 round-2 finding F8 — the round-1 "re-check before each chunk" was a TOCTOU race because `resolveProvider()` re-snapshots per request). Add: `struct PinnedAIProvider: Sendable { let profile: ProviderProfile; let apiKey: String }` — pins **both** the profile and its resolved credential (Gate 2 round-3: pinning only the profile would let a mid-operation Keychain key rotation change credentials across chunks); the struct is `AIService`-internal (built by `pinActiveProvider()`, consumed only by `sendRequest(_:using:)`), never exposed to UI or persisted. `func pinActiveProvider() async throws -> PinnedAIProvider` — runs the feature-flag + consent gates, snapshots the active `ProviderProfile` **and** reads its Keychain key **once** (throws `providerError`/`apiKeyMissing` early), honors the existing `provider`/`providerFactory` test-injection precedence. `func sendRequest(_ request: AIRequest, using pinned: PinnedAIProvider) async throws -> AIResponse` — runs the feature-flag + consent gates and builds the concrete provider from `pinned.profile`/`pinned.apiKey` (same dispatch switch as `resolveProvider()`) with no re-resolve; it **deliberately does not consult `AIResponseCache`** (Gate 2 round-3: `AIRequest.cacheKey` carries no provider identity, so a pinned-provider request could be served a cross-provider cached response — and bilingual translation already has its own provider-aware disk cache via `BilingualTranslation.lookupKey`, making the in-memory cache redundant here). `resolveProvider()` and the existing `sendRequest(_:)`/`streamRequest(_:)` are unchanged — all current callers keep per-request snapshotting and the in-memory cache. |
| `vreader/Services/PerBookSettings.swift` | `PerBookSettingsOverride` += `bilingualEnabled: Bool?`, `bilingualTargetLanguage: String?`, `bilingualGranularity: String?` — all optional, additive (older JSON decodes). |
| `vreader/Views/Reader/ReaderMoreMenuRow.swift` | Add `case bilingual` (3rd, after `autoTurnPages`); move `dividerAfter` to `.bilingual` per design §2.3. **Extend the row presentation model** beyond today's `isToggle: Bool` to a 3-way presentation (`toggleOff` / `toggleOn` / `unavailable`) — the `unavailable` state has no toggle, a chevron, and sub-detail "Configure AI provider first". New `.readerMoreBilingual` notification. |
| `vreader/Views/Reader/ReaderMorePopover.swift` | Render the 3-state bilingual row (extend the trailing-accessory switch); `unavailable` tap routes to AI Settings. |
| `vreader/Views/Reader/ReaderNotifications.swift` | New `.readerMoreBilingual`, `.readerBilingualDidChange`. |
| `vreader/Views/Reader/ReaderTopChrome.swift` | New `bilingualActive: Bool` param; insert `BilingualPill` into the `HStack` next to `titleLabel` (this is a real layout change, not purely additive — WI-9 owns it with layout + accessibility-identifier tests). |
| `vreader/Views/Reader/EPUBWebViewBridge.swift` + `EPUBWebViewBridgeJS.swift` | Run enumerate / inject / clear via the existing `pendingJS` seam; re-run on chapter `didFinish` (Bug #182 pattern). |
| `vreader/Views/Reader/EPUBReaderContainerView.swift` (+ host) | Own a `BilingualReadingViewModel`; supply it the ordered spine `chapterHrefs`; present `BilingualSetupSheet` on first enable; wire the More-menu + pill. |
| `docs/architecture.md` | New `@Model` `BilingualTranslation` + SchemaV7 + `BilingualTranslationService` + the `AIService` pin seam (rule 24). |

### Files OUT of scope

- `vreader/Views/Reader/BilingualView.swift` — the existing AI-Translate-tab
  side-by-side panel. **Not reused** (design §2.1's explicitly *rejected*
  side-by-side layout; the name collision is a hazard — new code uses
  `BilingualReading*` / `BilingualInterlinear*` naming, never `BilingualView`).
- `TXT`/`MD`/`Foliate`/`PDF` reader containers — see Scope decision 2.
- A per-request **arbitrary-provider override** (choosing a *non-active*
  provider for a one-off request) — follow-up. `pinActiveProvider()` pins the
  **active** profile only; #56 needs no more than that.

## Prior art / project precedent / rejected alternatives

- **Precedent — `@Model` + schema version**: `SchemaV4` added two independent
  entities with lightweight migration (no `MigrationStage`). `BilingualTranslation`
  follows it.
- **Precedent — JS injection**: the EPUB highlight API + `ReplacementTransform`
  show the `pendingJS` + `FoliateJSEscaper` pattern; bilingual EPUB JS copies it.
- **Precedent — value-type DTOs across the actor boundary**: `BookmarkRecord` →
  `BilingualTranslationRecord`.
- **Precedent — single provider snapshot**: `AIService.resolveProvider()`
  already snapshots the active `ProviderProfile` once per request to insulate an
  in-flight request from a mid-stream profile swap. `pinActiveProvider()`
  extends the *same* idea to one snapshot per multi-request *operation*.
- **Rejected — side-by-side columns**: design §2.1 — unreadable at 402px.
- **Rejected — per-tap overlay**: that is feature #18's existing AI Translate tab.
- **Rejected — raw `querySelectorAll('p')` order keying** (Gate 2 finding F3):
  fragile and order-dependent. Replaced with a stamped stable-ID enumeration
  seam (`data-vreader-bid`).
- **Rejected — rare-delimiter splitting of AI output** (Gate 2 finding F5): the
  model can reproduce any delimiter. Replaced with a strict JSON-array decode
  contract (enforced via the request prompt; `AIRequest` has no API-level
  response-format field, so the contract is prompt-level + strict decode) and a
  per-paragraph fallback on mismatch.
- **Rejected — per-chunk active-provider re-check** (Gate 2 round-2 F8): a
  re-check between chunks still races `AIService`'s per-request resolution.
  Replaced with a real one-snapshot pin seam (`pinActiveProvider()`).
- **Rejected — cross-book paragraph-cache reuse**: keeps the cache identity
  simple and `deleteTranslations(forBookWithKey:)` unambiguous (Gate 2 F4). The
  cache is per-book.
- **Rejected — TXT/MD/AZW3/PDF in this feature, and parts (3)/(4)**: split to a
  follow-up feature (rule 47 10-WI rule + Gate 2 findings F2/F6/F7).

## Work-item sequencing

| WI | Title | Tier | PR size |
|---|---|---|---|
| WI-1 | `BilingualTranslation` `@Model` (persisted unique `lookupKey`, `providerProfileID: UUID`) + SchemaV7 + `PersistenceActor+Translations` + DTO | foundational | S |
| WI-2 | `PerBookSettingsOverride` bilingual fields | foundational | XS |
| WI-3 | `BilingualChunker` (paragraph-boundary chunking) + the strict-JSON-array translation prompt/decode contract | foundational | S |
| WI-4 | `BilingualTranslationService` actor + the `AIService` provider-pin seam (`PinnedAIProvider` / `pinActiveProvider()` / `sendRequest(_:using:)`) it requires — cache batch-read → pin → chunk → `sendRequest(_:using:)` → strict JSON decode + per-paragraph fallback → cache-write | foundational | L |
| WI-5 | `BilingualReadingViewModel` — toggle persistence, chapter-aware prefetch trigger (`lastTriggerHref`/`inFlightHrefs`), epoch/cancellation, `.readerBilingualDidChange` | foundational | M |
| WI-6 | More-menu `bilingual` row — 3-way presentation model (`toggleOff`/`toggleOn`/`unavailable`) + `ReaderMorePopover` render + row tests | behavioral | M |
| WI-7 | `BilingualSetupSheet` (first-enable half-sheet) | behavioral | M |
| WI-8 | EPUB interlinear — `EPUBBilingualJS` enumerate/inject/clear (stable IDs, CFI-excluded decorative divs) + `EPUBReaderContainerView` wiring (supplies the VM its `chapterHrefs`) | behavioral | L |
| WI-9 | `BilingualPill` in `ReaderTopChrome` + layout/identifier tests — **final WI** | behavioral | M |

9 WIs. WI-1..5 foundational (no user-observable behavior). WI-6..9 behavioral.
WI-4 folds in the small `AIService` pin seam because that seam exists solely to
serve `BilingualTranslationService` (shipping it as a standalone WI would land
an unused API) — sized `L` for the two cohesive deliverables. WI-8 (the EPUB
interlinear render) is the meat and is sized `L` for the CFI-exclusion work
(see R-EPUB-CFI). WI-9 completes the designed surface → row flips `DONE`.

WI-5's chapter-aware trigger is **designed up front here**, not retrofitted
after WI-8 (Gate 2 round-2 sequencing note): the VM consumes an injected
ordered `chapterHrefs: [String]` and derives the current chapter from the
position `Locator`; WI-8 only *supplies* the real list. WI-5 is therefore
fully unit-testable before WI-8 lands.

## Test catalogue

| Test file | Covers |
|---|---|
| `BilingualTranslationStoreTests` | In-memory `ModelContainer`; insert/fetch/dedupe by `lookupKey` (unique); batch fetch; `deleteTranslations(forBookWithKey:)`; `providerProfileID` round-trips as `UUID`; SchemaV6→V7 lightweight migration opens an existing store. |
| `BilingualChunkerTests` | `@Test(arguments:)` — empty, one over-budget paragraph alone, many tiny, exact-boundary, CJK char-vs-byte counting. |
| `AIServiceTests` (extend) | `pinActiveProvider()` runs the feature-flag/consent gates and throws `apiKeyMissing` when no key; `sendRequest(_:using:)` uses the pinned profile's provider with no re-resolve (swap the active profile mid-test → pinned output stays on the original); it does **not** serve an `AIResponseCache` entry left by a different provider for the same `cacheKey` (cross-provider cache hole — Gate 2 round-3); the credential is pinned (a Keychain key change after `pinActiveProvider()` does not affect in-flight chunks); test-injection (`provider`/`providerFactory`) precedence preserved. |
| `BilingualTranslationServiceTests` | Mock `AIService` + in-memory persistence — cache hit skips the API call; miss calls once + writes back; **JSON-array decode**: well-formed array maps back to paragraph IDs; malformed/short array → per-paragraph fallback; provider pinned (active-profile change mid-op does not change the provider used); partial-failure leaves prior chunks cached. |
| `BilingualReadingViewModelTests` | `@MainActor` — toggle persists to `PerBookSettings`; first-enable raises `needsSetupSheet`; **repeated `.readerPositionDidChange` within one chapter triggers exactly one prefetch** (chapter-href dedupe); a real chapter change cancels the old epoch and starts a new prefetch; a stale-epoch result is discarded; disable clears translations + resets `lastTriggerHref`/`inFlightHrefs`. |
| `ReaderMoreMenuRowTests` (extend) | The 3-way bilingual row presentation — `toggleOff`/`toggleOn`/`unavailable`; `visibleRows` includes `bilingual`; divider position. |
| `PerBookSettingsTests` (extend) | Older JSON (no bilingual fields) decodes; round-trip with the new fields. |
| `EPUBBilingualJSTests` | The generated JS strings escape correctly via `FoliateJSEscaper`; enumerate output shape; inject/clear are idempotent. |
| EPUB highlight regression (extend Feature #11 coverage) | With bilingual divs injected, existing EPUB highlight create/restore still anchors correctly — proves the decorative divs are CFI-excluded (R-EPUB-CFI). |

Audit-driven additions expected: corruption (cache row with stale `promptVersion`),
idempotency (double-enable), concurrent prefetch + manual toggle.

## Risks + mitigations

- **R-EPUB-CFI (highest) — injected divs vs EPUB CFI/highlight anchoring.**
  Injecting a translation `<div>` as a sibling after each `<p>` shifts the DOM
  sibling indices of subsequent nodes; EPUB CFIs and highlight anchoring are
  DOM-path-based, so naive injection could mis-anchor existing highlights
  (feature #11). *Mitigation*: the injected divs carry `data-vreader-decoration`
  and `user-select: none`; WI-8 must make the EPUB highlight/CFI/selection JS
  **skip decoration nodes** in every DOM traversal (or clear bilingual divs
  during a highlight operation and re-inject after). The test catalogue's EPUB
  highlight regression test gates WI-8's merge — bilingual mode must not move
  or drop existing highlights.
- **R-translate-mapping — chunk response ↔ source paragraph mapping.**
  *Mitigation* (Gate 2 F5): the chunk request prompt instructs the model to
  return only a JSON array of translated strings; the service strictly
  `JSONDecoder`-decodes `AIResponse.content` and asserts the array length
  equals the chunk's paragraph count; on any decode/count mismatch it falls
  back to one-paragraph-per-request.
- **R-provider-pin — mixed-provider output across a multi-chunk operation.**
  `AIService.sendRequest(_:)`/`resolveProvider()` snapshot the active provider
  **per request**, so a chunked operation issuing N requests can straddle a
  mid-operation profile swap. *Mitigation* (Gate 2 round-2 F8 + round-3):
  `AIService` gains a real pin seam — `pinActiveProvider()` snapshots the
  active `ProviderProfile` **and its Keychain credential** exactly once into a
  `PinnedAIProvider`, and `BilingualTranslationService` routes every chunk (and
  every fallback per-paragraph request) through `sendRequest(_:using: pinned)`.
  `sendRequest(_:using:)` bypasses `AIResponseCache` because `AIRequest.cacheKey`
  is not provider-aware (a cached response from a different provider could
  otherwise be returned). The pinned profile id is stamped into every disk
  cache `lookupKey`. A true per-request *arbitrary-provider* override is
  follow-up scope.
- **R-cancellation — stale prefetch results + same-chapter scroll churn.**
  `.readerPositionDidChange` posts continuously *within* a chapter, not only on
  chapter transitions. *Mitigation* (Gate 2 F9 + round-2 medium):
  `BilingualReadingViewModel` (a) dedupes the trigger to chapter-`href`
  transitions via `lastTriggerHref` + `inFlightHrefs` — same-chapter posts are
  no-ops; (b) is epoch-guarded — tasks capture their epoch, are cancelled on
  disable/book-change/chapter-change/disappear, and late results from a
  superseded epoch are dropped. The prefetch identity tuple is
  `(bookFingerprintKey, targetLanguage, providerProfileID, promptVersion, href)`;
  a pair already requested under that tuple is not re-requested.
- **R-cache-key — persisted lookup.** *Mitigation* (Gate 2 F4): `lookupKey` is
  a **stored, unique** `String` column (not a computed property); fetch/dedupe
  operate on it directly. Cache is per-book.
- **R-cost — prefetch token spend.** *Mitigation*: translate only the current
  chapter on enable + the next on chapter-change; never the whole book (that is
  the deferred global-translate feature). Cache makes re-visits free.
- **R-offline.** *Mitigation*: serve from cache if present; otherwise render
  source-only with a quiet inline "translation unavailable offline" affordance.
- **R-row-model — More-menu is 2-state today.** *Mitigation* (Gate 2 F10): WI-6
  extends `ReaderMoreMenuRow`'s presentation model to 3-way **before** adding
  the case, with row tests.

## Backward compat

- **Schema**: V6→V7 adds one independent `@Model`, all fields defaulted →
  lightweight migration, existing stores open unchanged. No `MigrationStage`.
- **`PerBookSettings`**: new fields optional; pre-#56 per-book JSON decodes
  (missing keys → `nil` → bilingual off).
- **`AIService`**: the pin seam is purely additive — new struct + two new
  methods; `resolveProvider()`, `sendRequest(_:)`, `streamRequest(_:)` and all
  their existing callers are untouched. `sendRequest(_:using:)` deliberately
  skips `AIResponseCache` (see R-provider-pin) — no change to the cache's
  behavior for existing callers.
- **Backups**: the translation cache is a derived, re-fetchable artifact —
  excluded from WebDAV backup; restore-to-fresh-device re-fetches on demand.
  No backup-format bump.
- **Setup sheet Sentence option** ships disabled ("Coming soon") so the surface
  matches design §2.2 without implementing CJK sentence segmentation (follow-up).
  Default Paragraph is fully functional.

## Deferred / follow-up feature (file with the PLANNED flip)

A new `docs/features.md` row, filed in the **same changeset** that narrows #56
and flips it to PLANNED (Gate 2 finding F6 — #56's row narrows to EPUB-core and
these carve-outs move out):
- TXT / MD interlinear — requires a source↔display *segment* map distinguishing
  source-backed vs synthetic display ranges, threaded through every text-reader
  touchpoint (bridge scroll callbacks, selection, search/highlight navigation,
  chapter-local helpers, chunked TXT, paged MD, persisted-highlight hit-testing,
  TTS highlight + auto-scroll). Feature-sized.
- AZW3/MOBI interlinear — new `readerAPI` JS in the vendored `foliate-bundle.js`.
- Global "translate entire book" — cancellable background job + progress.
- Per-chapter re-translation + per-request **arbitrary-provider** override
  (needs a non-active-provider override seam in `AIService.sendRequest`, beyond
  this feature's active-profile `pinActiveProvider()`).
- Sentence granularity — needs a CJK-aware sentence segmenter.

## Revision history

- **v1 (2026-05-18)** — initial plan (5-format, 12 WIs). Feature-cron Gate 1.
- **v2 (2026-05-18)** — Gate 2 audit round 1 (Codex thread `019e37c5`): 1
  Critical, 6 High, 3 Medium, 1 Low. Rewritten EPUB-first (9 WIs). Resolutions:
  - **F1 (Critical, OffsetMap unsound for synthetic insertion)** — fixed:
    TXT/MD removed from scope; for EPUB the translation divs are decorative,
    non-selectable, CFI-excluded (R-EPUB-CFI) — no `OffsetMap` is used.
  - **F2 (High, WI-10/11 under-scope TXT/MD)** — fixed: TXT/MD moved to a
    follow-up feature.
  - **F3 (High, no EPUB extraction contract)** — fixed: WI-8 ships a stamped
    stable-ID enumeration seam (`data-vreader-bid`), not raw `querySelectorAll`.
  - **F4 (High, contradictory cache key / computed-property lookup)** — fixed:
    per-book cache; `lookupKey` is a stored unique column; cross-book-reuse
    claim dropped.
  - **F5 (High, brittle delimiter splitting)** — fixed: strict JSON-array
    decode contract + per-paragraph fallback.
  - **F6 (High, plan vs features.md #56 row scope mismatch)** — fixed (wording
    tightened in v3): the PLANNED flip narrows the #56 row to EPUB-core and
    files a follow-up row; #56 is not marked complete against the broader row.
  - **F7 (High, incoherent EPUB-only fallback vs final-WI)** — fixed: #56 is
    EPUB-only by construction; the final WI (WI-9) is an EPUB WI; no fallback.
  - **F8 (Medium→re-opened High, provider consistency)** — see v3.
  - **F9 (Medium, no cancellation/epoch)** — fixed: epoch-guarded
    `BilingualReadingViewModel` (R-cancellation).
  - **F10 (Medium, row/chrome changes understated)** — fixed: WI-6 does the
    3-way row presentation model + tests; WI-9 does the chrome layout change.
  - **F11 (Low, wrong file path)** — fixed: `EPUBBilingualJS.swift` lives in
    `vreader/Views/Reader/`.
- **v3 (2026-05-18)** — Gate 2 audit round 2 (same Codex thread): 2 High +
  2 Medium remaining. Resolutions:
  - **F8 (High, re-opened — provider-pin TOCTOU)** — fixed: round-2 showed a
    per-chunk *re-check* still races `AIService`'s per-request resolution.
    `AIService` now gains a real one-snapshot pin seam (`PinnedAIProvider`,
    `pinActiveProvider()`, `sendRequest(_:using:)`); `AIService.swift` moved
    from "OUT of scope" into Modified files; folded into WI-4.
  - **F6 (High, re-opened — narrowing deferred, not done)** — fixed: the
    Scope-decisions section now states the #56 row narrowing + follow-up-row
    filing happen **atomically, in the same `docs/features.md` write as the
    TODO→PLANNED flip** — no window where a ratified plan and an un-narrowed
    row coexist; the gate model permits no earlier point.
  - **Medium (scroll churn)** — fixed: `.readerPositionDidChange` fires within a
    chapter; `BilingualReadingViewModel` now has an explicit chapter-aware
    trigger (`lastTriggerHref` + `inFlightHrefs`, designed up front in WI-5,
    consuming an injected `chapterHrefs` list). Test added.
  - **Medium (UUID vs String drift)** — fixed: `BilingualTranslation` /
    `BilingualTranslationRecord` store `providerProfileID: UUID` (matching
    `ProviderProfile.id`); only the persisted `lookupKey` joins its `.uuidString`.
  - Pending Gate 2 round 3 re-audit.
- **v4 (2026-05-18)** — Gate 2 audit round 3 (same Codex thread): 0 Critical,
  1 High, 1 Medium — both *new*, both fallout of v3's pin seam. Resolutions:
  - **High (cross-provider cache hole)** — fixed: `sendRequest(_:using:)` no
    longer consults `AIResponseCache` (`AIRequest.cacheKey` carries no provider
    identity, so a pinned request could be served another provider's cached
    response). Bilingual has its own provider-aware disk cache.
  - **Medium (credential not pinned)** — fixed: `PinnedAIProvider` now pins the
    resolved API key too (`{ profile, apiKey }`), so a mid-operation Keychain
    rotation cannot change credentials across chunks.
  - **Gate 2 status — round cap reached.** Three audit rounds are the rule-47 /
    feature-workflow maximum; the finding count converged monotonically
    (11 → 4 → 2) and round-3's two findings were trivial, uncontested fallout
    of one v3 addition. v4 incorporates both fixes but has **not** been
    re-audited (a round 4 would exceed the cap). Per rule 47 Gate 2, this
    **escalates to the user**: ratify v4 as Gate-2-clean (the two fixes are
    mechanical and self-evidently resolve the findings), or authorize one
    confirmation audit pass. **#56 stays `TODO` — no PLANNED flip — until that
    ratification.** The row-narrowing + follow-up-row filing (F6) are bound to
    the PLANNED flip and therefore also pending.
