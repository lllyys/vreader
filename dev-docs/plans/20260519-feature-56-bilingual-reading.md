# Feature #56 — Full bilingual reading

> Plan doc — Gate 1 artifact for `.claude/rules/47-feature-workflow.md`.
> Feature row: `docs/features.md` #56. GH: #629.
> Status: TODO → (PLANNED after Gate 2).
>
> **Supersedes** `dev-docs/plans/20260518-feature-56-bilingual-reading-mode.md` (v4).
> That earlier plan was a narrowed escape-hatch written *before* the
> 2026-05-18 issue-canvas design handoff landed: it dropped scope items (3)
> "translate entire book" and (4) per-chapter re-translate because their UI
> was `needs-design`-blocked (#863/#864), and dropped TXT/MD/AZW3/PDF
> interlinear. The 2026-05-18 handoff committed `vreader-translate-book.jsx`
> (resolves #863) and `vreader-retranslate.jsx` (resolves #864), so the
> blocked slices are now designed. The #56 row was updated 2026-05-18 to
> confirm "The core bilingual-reading slices are designed; the
> global-translate + re-translate slices are blocked" — this plan is the
> full-scope replacement now that the blockers are cleared. v4's Gate-2
> findings (F1–F11) are retained below as prior art and re-applied.

## Design coverage confirmation (all 4 scope items)

| Scope item | Design source | Surfaces depicted |
|---|---|---|
| (1) Chapter bilingual mode | `vreader-bilingual.jsx` + `feature-60-followups.md §2.1`/`§2.3` | `BilingualPageContent` interlinear renderer; `BilingualPill` reader-chrome pill; `MoreBilingualRow` 3-state (off/on/unavailable) |
| (2) Persistent translation cache | (no UI — backing store) | n/a — derived data, no designed surface |
| (1) setup sheet | `vreader-bilingual.jsx` + `feature-60-followups.md §2.2` | `BilingualSetupSheet` half-sheet (target language ×9, granularity, provider chip) |
| (3) Global book translation | `vreader-translate-book.jsx` (resolves #863) | `TranslateBookActionRow` (Book Details + library long-press); `TranslateBookConfirmAlert`; `LibraryCardTranslateBadge`; `ReaderTranslateBanner`; `TranslateStatusSheet` (per-chapter list); `TranslateCancelAlert` |
| (4) Per-chapter re-translate + provider override | `vreader-retranslate.jsx` (resolves #864) | `ReTranslateMoreRow` (More popover, conditional on `bilingualOn`); `ChapterSwipeAction` (TOC swipe); `ReTranslatePickerSheet` (provider/model/style override); `ReTranslateProgress` half-sheet |

All four scope items have committed design bundles **at the top level** — the
core surfaces (interlinear renderer, setup sheet, pill, More-menu rows,
translate-book, re-translate) are designed and the feature can plan in full.
**Two derived states remain design-blocked** and are handled per rule 51
(Decision 2): (i) the PDF below-page translation panel — fixed-layout PDF gets
no interlinear and no committed bundle depicts its alternative; (ii) the
bilingual offline / "translation unavailable" inline state — no bundle depicts
it. Each gets a `Design needed:` GH issue; neither blocks the 15 designed WIs.

## Problem

Feature #18 translates a *selected passage* inside the AI panel — point-in-time,
in-memory (`AIResponseCache` is session-only), one tap at a time. Users reading a
foreign-language book want a full bilingual reading experience:

1. **Chapter bilingual mode** — a per-book toggle that, when on, renders every
   source paragraph followed inline by its AI translation in a smaller, muted
   style (paragraph-interlinear, design §2.1) across every reader format.
2. **Persistent translation cache** — translations cached to disk so they
   survive app restarts and cost no repeat API calls.
3. **Global book translation** — a one-tap "Translate entire book" action that
   pre-translates every chapter as a cancellable background job.
4. **Per-chapter re-translation** — re-run one chapter's translation, optionally
   with a *different* AI provider, without changing the global active provider.

## Scope decisions (read first)

### Decision 1 — Interlinear rendering, all formats, but format-tiered

The #56 row's original scope text sketched a "chapter-block" treatment
("append translation in a styled `UITextView` section below the chapter").
**Design §2.1 supersedes that**: translation follows *each* source paragraph,
`~0.88×` font-size, color `sub`, upright, indented `1×`; chapter headings are
not translated; the source paragraph keeps its drop-cap.

The five formats divide into three implementation tiers by how hard
paragraph-interlinear is given that format's text model:

- **Tier A — EPUB** (genuine reflowable DOM). Source paragraphs are discrete
  `<p>`/block nodes. Translation injected as a sibling decorative `<div>` after
  each stamped block. Hardest *risk* (CFI/highlight anchoring — R-EPUB-CFI) but
  cleanest *model*.
- **Tier A — AZW3/MOBI (Foliate)**. Foliate-js renders reflowable HTML in a
  `WKWebView` exactly like EPUB; the same stamped-block + sibling-div technique
  applies, but the JS lives in the vendored `foliate-bundle.js` reader context
  and is reached via a Foliate message rather than `EPUBWebViewBridge.pendingJS`.
- **Tier B — TXT/MD** (flat `NSAttributedString`, no paragraph model). The text
  readers assume **source-UTF16-offset invariants** end-to-end: bridge scroll
  callbacks, selection, search/highlight navigation, chapter-local helpers,
  chunked TXT (`UITableView` >500K UTF-16), paged MD, persisted-highlight
  hit-testing, TTS highlight + auto-scroll. Interleaving translation text shifts
  every one of those offsets. **The mitigation is a source↔display segment map**
  (`BilingualDisplaySegmentMap`) — a value type that records, per display range,
  whether it is *source-backed* (offset maps back to a source UTF-16 index) or
  *synthetic* (a translation block, no source preimage). Every text-reader
  touchpoint that today consumes a raw display offset is routed through the map
  when bilingual mode is on, and is a **no-op pass-through** (identity map) when
  it is off — so the non-bilingual path is provably unchanged.
- **Tier C — PDF**. Fixed-layout glyphs, no reflowable paragraph: true
  interlinear is impossible. Design has no PDF interlinear surface. **PDF gets
  the `feature-60-followups.md`-absent treatment**: bilingual mode renders a
  *per-page translation panel below the page* (the row's original scope item (1)
  PDF clause — "overlay translation panel below the page"). This is a distinct,
  non-interlinear surface. Because no design bundle depicts a PDF
  below-page translation panel, **the PDF slice is `needs-design`-blocked**
  (rule 51) — see WI-13 and "Design gap" below.

### Decision 2 — `needs-design` gap: PDF below-page panel

`feature-60-followups.md §2.1` explicitly says interlinear is rejected for
fixed-layout, and **no committed bundle depicts the PDF below-page translation
panel** the row's scope item (1) calls for. Per rule 51 this surface is
**not designed**. Decision:

- WI-13 (PDF bilingual) is filed as **`BLOCKED: needs-design`**. A GitHub
  issue `Design needed: PDF below-page translation panel for feature #56` is
  filed (labels `enhancement` + `needs-design`, `Refs #629`) — the orchestrator
  files it when staging Gate 3, or this plan's owner files it at PLANNED-flip
  time. WI-13 does not enter Gate 3 until a bundle lands.
- **All other WIs (EPUB, AZW3/MOBI, TXT/MD, global translate, re-translate,
  cache, setup sheet, More-menu rows, pill) proceed** — they are fully designed.
  Per rule 48 parallel-execution, a `needs-design` block on one slice does not
  pause designed slices.
- This is *not* a scope cut: PDF stays in feature #56's scope; only its
  *implementation* is gated on a design bundle. The feature row reaches `DONE`
  only when WI-13 also merges (or PDF is explicitly de-scoped by the user after
  reviewing the design cost — that decision is theirs, not this plan's).

**A second `needs-design` gap — the offline empty/error state** (Gate-2
round-1 Medium). Edge case (c) requires bilingual mode to show *something* when
a chapter is not cached and the device is offline. The committed design
bundles cover the interlinear renderer, setup sheet, pill, translate-book, and
re-translate surfaces — **none depicts an offline / translation-unavailable
inline state**. Per rule 51 this is undesigned. Decision: the offline state is
**`needs-design`-blocked** — a GH issue `Design needed: bilingual offline /
translation-unavailable state for feature #56` is filed (labels `enhancement` +
`needs-design`, `Refs #629`). Until it lands, the bilingual renderer's
offline-miss behavior is **purely non-visual**: it renders the source text
exactly as non-bilingual mode would (no synthetic block, no inline message) and
the VM records the miss so a later online prefetch fills it. This is *not* an
invented surface — it is the absence of one (source-only render is the existing
designed reading experience). The visible "unavailable" affordance ships only
once designed. WI-7/WI-10..12 implement the silent-source-fallback path; the
visible affordance is a follow-up WI gated on the design.

### Decision 2.5 — `TranslationUnitID`, not `chapterHref` (Gate-2 round-1 Critical)

The Gate-2 round-1 audit (Codex `019e4029`) found that `chapterHref` is **not a
valid cross-format identity** — verified against the live code:

- **EPUB / AZW3 / MOBI** — a spine-document `href` exists and is stable.
- **TXT** — `TXTReaderViewModel.makeLocator()` only synthesizes a
  persistence-only `href` (`txtchapter:<idx>:<offset>`) *and only in chapter
  mode* (`isChapterMode`-gated); in continuous mode there is no chapter href at
  all.
- **MD** — `MDReaderViewModel.makeLocator()` produces an **offset-based**
  locator via `LocatorFactory.mdPosition` with **no `href`**.
- **PDF** — page-based; no `href`.

So a single `chapterHref` string cannot key the cache, the VM state, or the
coordinator APIs across all five formats. **Resolution**: introduce a
format-agnostic value type `TranslationUnitID` and define its per-format
derivation explicitly up front.

```
struct TranslationUnitID: Sendable, Equatable, Hashable, Codable {
    enum Kind: String, Codable { case epubHref, foliateHref, txtChapterIndex, mdChapterIndex, pdfPageRange }
    let kind: Kind
    let value: String   // EPUB/Foliate: the spine href. TXT/MD: the chapter index. PDF: "start-end" page range.
    var storageKey: String { "\(kind.rawValue):\(value)" }   // goes into ChapterTranslation.lookupKey
}
```

Per-format derivation (each format host owns its mapping; defined here so the
WIs are unambiguous):

| Format | `TranslationUnitID` derivation |
|---|---|
| EPUB | `Kind.epubHref`, `value` = spine-item href (from `ReaderTOCBuilder`'s spine list — verified: EPUB TOC is built from **spine items**, not nav chapters). |
| AZW3/MOBI | `Kind.foliateHref`, `value` = the Foliate section href / index reported by `foliate-bundle.js`. |
| TXT | `Kind.txtChapterIndex`, `value` = the chapter index from `TXTChapterIndex`. **Continuous-mode TXT** still has a chapter index (the index exists independent of render mode) — bilingual mode keys on it; the *render* in continuous mode interleaves per the segment map. |
| MD | `Kind.mdChapterIndex`, `value` = the MD chapter index from `MDChapterStartScanner`. |
| PDF | `Kind.pdfPageRange`, `value` = the page range translated as one unit (the PDF surface is `needs-design`-blocked anyway — WI-13). |

Everywhere the plan previously said `chapterHref` it now means
`TranslationUnitID` (the disk-cache identity field is renamed `unitStorageKey`;
the VM dictionary is `translationsByUnit: [TranslationUnitID: [String]]`).

### Decision 2.6 — chapter-text source abstraction (Gate-2 round-1 Critical)

The Gate-2 round-1 audit found there is **no shared API that supplies "the
plain text of chapter N" across formats** — verified: `ReaderAICoordinator`
extracts a windowed ~2500-char slice (`AIContextExtractor`), TXT/MD
`ReflowableTextSource` adapters are whole-document, and `FoliateSpikeView`'s
live extraction seam is whole-book `extractPlainText()`. Both chapter bilingual
mode (translate the *current* chapter) and global translate (translate *every*
chapter) need per-unit text.

**Resolution**: a foundational boundary protocol — it carries **both** the
ordered-unit / per-unit-text contract **and** the `Locator → unit` resolution
the VM's prefetch trigger needs (Gate-2 round-2 N6 — without this the VM has no
named way to map a position `Locator` to its `TranslationUnitID` or find the
next unit to prefetch):

```
protocol ChapterTextProviding: Sendable {
    /// Ordered translation units for the open book, in reading order.
    func translationUnits() async throws -> [TranslationUnitID]
    /// The plain source text of one unit (already HTML-stripped for EPUB/Foliate).
    func sourceText(for unit: TranslationUnitID) async throws -> String
    /// The unit containing a given reading position. nil if the locator
    /// predates the book's units (e.g. an empty book). Each format already
    /// knows how to map its own Locator → chapter; this surfaces it.
    func unit(containing locator: Locator) async -> TranslationUnitID?
    /// The unit immediately after `unit` in reading order, or nil at the end —
    /// used by the prefetch trigger to fetch current + next.
    func unit(after unit: TranslationUnitID) async -> TranslationUnitID?
}
```

`BilingualReadingViewModel` calls `unit(containing:)` on every
`.readerPositionDidChange` and `unit(after:)` to pick the prefetch target — no
separate resolver type is needed; the format adapter already owns the
`Locator`-to-chapter knowledge and this is the named seam for it.

With a concrete per-format adapter:

- `EPUBChapterTextProvider` — reads each spine document's HTML, strips to text.
- `FoliateChapterTextProvider` — adds a *per-section* extraction JS to
  `foliate-bundle.js` (today only whole-book `extractPlainText()` exists — this
  is new JS, scoped into WI-11).
- `TXTChapterTextProvider` — slices the full text by `TXTChapterIndex` bounds.
- `MDChapterTextProvider` — slices by `MDChapterStartScanner` chapter bounds.
- `PDFChapterTextProvider` — extracts text per page range (used only once the
  PDF surface is designed — WI-13).

`ChapterTranslationService` and `BookTranslationCoordinator` consume
`ChapterTextProviding`, never a format-specific extractor. This boundary is
WI-2.5 (a new foundational WI — see the revised sequencing).

### Decision 2.7 — translation unit = spine document (Gate-2 round-1 High)

The Gate-2 audit noted EPUB TOC entries are not 1:1 with spine documents — one
logical TOC chapter can span multiple spine docs, and multiple TOC entries can
share one href. **Resolution**: the *translation unit* is the **spine
document** (EPUB/Foliate), the **`TXTChapterIndex` chapter** (TXT), the
**`MDChapterStartScanner` chapter** (MD) — i.e. the format's natural rendering
segment, **not** the logical TOC chapter. This makes progress counts in global
translate exact (one unit = one progress tick), avoids the
many-TOC-entries-to-one-href ambiguity, and matches what each renderer can
inject into. The `TranslateStatusSheet`'s per-chapter list shows units; where a
unit has a friendly TOC title it is shown, otherwise the unit ordinal. The
re-translate affordance (More-menu row + TOC swipe) re-translates the unit
containing the current reading position.

### Decision 3 — feature stays whole; no follow-up carve-out

v4 carved TXT/MD/AZW3/PDF and scope items (3)/(4) into a follow-up feature.
This plan **does not** — the design now covers everything, and the #56 row's
contract is all four items. The feature is large (16 WIs) but rule 47 permits
5+ WIs as "Large"; it does not exceed the "consider splitting at genuinely
10+ WIs" line in a way that warrants splitting, because the WIs share one
coherent subsystem (the translation cache + service) and splitting would force
an artificial dependency seam. The WI sequence is staged so the foundational
cache/service WIs land first and the per-format render WIs are independent
leaves — that *is* the natural decomposition.

## Surface area

### New files

| File | What |
|---|---|
| `vreader/Models/Migration/SchemaV7.swift` | `enum SchemaV7: VersionedSchema` — `versionIdentifier = Schema.Version(7, 0, 0)`, `models` = SchemaV6's 10 + `ChapterTranslation`. |
| `vreader/Models/TranslationUnitID.swift` | The format-agnostic translation-unit identity value type (Decision 2.5) — `struct TranslationUnitID: Sendable, Equatable, Hashable, Codable` with the nested `Kind` enum and a `storageKey: String`. |
| `vreader/Models/ChapterTranslation.swift` | New `@Model final class ChapterTranslation` — the disk cache entry. Fields: `lookupKey: String` (`@Attribute(.unique)` — the persisted, indexed dedupe key, a **stored** primitive joined at insert time from the identity fields, *not* a computed property), `bookFingerprintKey: String`, `unitStorageKey: String` (the `TranslationUnitID.storageKey` — Decision 2.5, replaces the old `chapterHref` since 3 of 5 formats have no href), `targetLanguage: String`, `providerProfileID: UUID` (matches `ProviderProfile.id`'s `UUID` type — SwiftData stores `UUID` natively), `promptVersion: String`, `translatedJSON: String` (a JSON-encoded `[String]` — one translated segment per source paragraph/sentence, preserving order; storing the array not a blob lets the renderer interleave without re-segmenting), `sourceParagraphCount: Int` (lets a consumer detect a stale entry whose source has since changed), `createdAt: Date`. No `@Relationship` to `Book` — independent entity (SchemaV4 `ContentReplacementRule` precedent). |
| `vreader/Services/ChapterTranslationStore.swift` | `actor ChapterTranslationStore` — the named store from the row's scope item (2). Wraps a `ModelContainer`-backed `ModelContext`. **App-scoped single instance** (Gate-2 round-1 High — multiple instances over the same container would let same-`lookupKey` inserts race SwiftData's unique constraint): exposes a `static let shared` constructed at app init over the main container, exactly as `ProviderProfileStore.shared` does; production callers MUST use `.shared`, tests inject a non-shared instance over an in-memory container. API: `func translation(forKey lookupKey: String) async -> ChapterTranslationRecord?`, `func translations(forKeys keys: [String]) async -> [String: ChapterTranslationRecord]` (batch), `func upsert(_ record: ChapterTranslationRecord) async throws` — **idempotent**: fetches the existing row by `lookupKey` first and updates it in place, else inserts; never relies on the unique constraint to throw, `func upsert(_ records: [ChapterTranslationRecord]) async throws` (batch), `func deleteTranslation(forKey lookupKey: String) async throws` (single-unit clear — scope item (4)), `func deleteTranslations(forBookWithKey bookFingerprintKey: String) async throws` (book delete — edge case (g)), `func cachedUnits(forBookWithKey:targetLanguage:providerProfileID:promptVersion:) async -> Set<String>` (returns covered `unitStorageKey`s — lets global translate skip already-cached units). Returns value-type `ChapterTranslationRecord` DTOs, never the `@Model`. **Separate actor, not a `PersistenceActor` extension** — the row names it `ChapterTranslationStore` explicitly, the cache is a derived re-fetchable artifact (excluded from backup), and keeping it off `PersistenceActor` avoids contending the main store's serialization queue with bulk translation writes during a global-translate run. |
| `vreader/Models/ChapterTranslationRecord.swift` | `struct ChapterTranslationRecord: Sendable, Equatable` — the value-type DTO crossing the `ChapterTranslationStore` actor boundary. Fields mirror the `@Model` (`lookupKey`, `bookFingerprintKey`, `unitStorageKey`, `targetLanguage`, `providerProfileID: UUID`, `promptVersion`, `translatedSegments: [String]` (decoded from `translatedJSON`), `sourceParagraphCount`, `createdAt`). A `static func lookupKey(bookFingerprintKey:unitStorageKey:targetLanguage:providerProfileID:promptVersion:) -> String` builds the canonical key (joins `providerProfileID.uuidString`) — the single source of truth for key construction, used by both the store and the service. |
| `vreader/Services/Reader/ChapterTextProviding.swift` | The chapter-text source boundary (Decision 2.6) — `protocol ChapterTextProviding: Sendable` with `translationUnits()`, `sourceText(for:)`, `unit(containing: Locator)`, and `unit(after:)` (the last two are the `Locator → unit` resolution seam — Gate-2 round-2 N6). The codebase precedent is `LibraryPersisting`/`BookImporting` boundary protocols. Conformers: `EPUB`/`TXT`/`MD`/`PDF` adapters are `struct`s (they hold only `Sendable` value state — file URLs, indices); `FoliateChapterTextProvider` is an `actor` (it bridges the `@MainActor` Foliate coordinator — see its row). All conform to the same `Sendable` protocol. |
| `vreader/Services/Reader/EPUBChapterTextProvider.swift` | `struct EPUBChapterTextProvider: ChapterTextProviding` — units = spine documents (from the same spine list `ReaderTOCBuilder` uses); `sourceText` reads each spine document's HTML and strips to plain text. |
| `vreader/Services/Reader/FoliateChapterTextProvider.swift` | `actor FoliateChapterTextProvider: ChapterTextProviding` — units + per-section text come from a **new per-section extraction JS** added to `foliate-bundle.js` (today only whole-book `extractPlainText()` exists on the `FoliateSpikeView` coordinator — verified; this is genuinely new JS, scoped into WI-11). **Sendable bridge** (Gate-2 round-2 N2 + round-3 follow-up): the live Foliate extraction seam (`FoliateSpikeView.Coordinator` / `FoliateCoordinatorBox` / `WKWebView`) is `@MainActor` (verified — `FoliateCoordinatorBox` is `@MainActor`), so the provider cannot store an unconstrained `any FoliateSectionExtracting` existential and still be `Sendable`. **Resolution — the provider is an `actor`** (the other 4 adapters are `struct`s; the Foliate one is an `actor` because it bridges a `@MainActor` boundary): an `actor` is `Sendable` by construction, so it satisfies `ChapterTextProviding: Sendable` without an unsafe escape hatch. The facade seam is declared `@MainActor protocol FoliateSectionExtracting: AnyObject, Sendable` (a `@MainActor`-isolated `AnyObject` existential **is** safely `Sendable` — its members are main-actor-isolated), with `@MainActor func extractSections() async -> [TranslationUnitID]` / `@MainActor func extractSectionText(_:) async -> String`, implemented by an extension on the existing `FoliateSpikeView.Coordinator`. The actor's `ChapterTextProviding` methods `await` the `@MainActor` facade — the hop from the actor's executor to the main actor is the bridge. WI-11 owns this facade + the actor. |
| `vreader/Services/Reader/TXTChapterTextProvider.swift` | `TXTChapterTextProvider: ChapterTextProviding` — units = `TXTChapterIndex` chapters (the index exists independent of render mode, so continuous-mode TXT still has units); `sourceText` slices the full text by chapter UTF-16 bounds. |
| `vreader/Services/Reader/MDChapterTextProvider.swift` | `MDChapterTextProvider: ChapterTextProviding` — units = `MDChapterStartScanner` chapters; `sourceText` slices by chapter bounds. |
| `vreader/Services/Reader/PDFChapterTextProvider.swift` | `PDFChapterTextProvider: ChapterTextProviding` — units = page ranges; `sourceText` extracts text per range via PDFKit; `unit(containing:)` maps a page `Locator` to its range. **Foundational and fully built in WI-2.5** (JS-free, no UI) — it is the design-blocked PDF *panel* that waits (WI-13), not this extractor. |
| `vreader/Services/AI/ChapterTranslationChunker.swift` | Pure utility — `static func chunk(segments: [String], maxCharsPerChunk: Int) -> [[Int]]` grouping segment indices into chunks under the provider char budget; never splits one segment across chunks; one over-budget segment occupies its own chunk (edge case (a) — recombination is then the caller's job). Pure → parameterized tests. |
| `vreader/Services/AI/ResolvedAIProviderConfig.swift` | `struct ResolvedAIProviderConfig: Sendable, Equatable { let kind: ProviderKind; let baseURL: URL; let apiKey: String; let model: String; let maxTokens: Int }` — the fully-resolved, immutable provider snapshot built once per multi-request operation (Gate-2 round-1 H2 + round-2 N1). **Module-internal in its own file** (not file-private to `AIService`) because `ChapterTranslationService` / `BookTranslationCoordinator` / `ChapterReTranslateViewModel` reference it. `ProviderKind` is verified to exist as a `String, Codable, Sendable` enum, so `ResolvedAIProviderConfig` is straightforwardly `Sendable`. Carries the credential (no mid-op Keychain drift) and `model` (re-translate override) — but **not** `style` (see the `AIService` row). |
| `vreader/Services/AI/TranslationStyle.swift` | `enum TranslationStyle: String, Sendable, CaseIterable, Codable { case literal, natural, literary }` — the re-translate style from `vreader-retranslate.jsx`. A pure prompt-construction input consumed by `ChapterTranslationService`'s prompt builder; never a wire field. |
| `vreader/Services/AI/ChapterSegmenter.swift` | Pure utility — `static func paragraphs(in chapterText: String) -> [String]` and `static func sentences(in chapterText: String) -> [String]`. Paragraph split is blank-line / block-boundary based. Sentence split uses `NSLinguisticTagger`/`String.enumerateSubstrings(in:options:.bySentences)` (CJK-aware — `bySentences` handles `。！？` and Latin punctuation). The `granularity` setting (design §2.2) selects which one the service calls. |
| `vreader/Services/AI/ChapterTranslationService.swift` | `actor ChapterTranslationService` — translates one unit. Input: `bookFingerprintKey`, a `TranslationUnitID`, the unit's source text (the service segments it via `ChapterSegmenter` per the book's granularity — or accepts pre-segmented `segments: [String]`), `targetLanguage`, a `ResolvedAIProviderConfig` (the provider/credential/model — see `AIService` row), and a `translationStyle: TranslationStyle` (defaults to `.natural` for chapter bilingual mode; the re-translate path passes the picker's choice). Reads `ChapterTranslationStore` by `lookupKey`; on a hit returns cached segments; on a miss chunks via `ChapterTranslationChunker`, builds each chunk's `userPrompt` via an internal prompt builder that **folds in `translationStyle`** (this is the *only* place `style` is consumed — Gate-2 round-2 N4), instructing the model to return **only a JSON array of N translated strings, same order**, issues one `AIService.sendRequest(_:using: config)` per chunk, strictly `JSONDecoder`-decodes `AIResponse.content` into `[String]`, asserts every element is a string and `count == chunk.count` — on any decode / non-string-element / count mismatch falls back to one-segment-per-request (still under the same `config` + `style`), writes the recombined ordered `[String]` to the store. Returns `ChapterTranslationResult { segments: [String], fromCache: Bool }`. Throws a typed `ChapterTranslationError` on offline / provider / cancellation. `Task.checkCancellation()` between chunks so a cancelled prefetch / cancelled global job stops promptly (edge case (b)). |
| `vreader/Services/AI/BookTranslationCoordinator.swift` | `actor BookTranslationCoordinator` — drives scope item (3) "translate entire book". Consumes a `ChapterTextProviding` (Decision 2.6) — never a format-specific extractor. API: `func estimate(bookFingerprintKey:textProvider:targetLanguage:) async throws -> BookTranslationEstimate` (unit count + rough token estimate for the confirm alert), `func start(bookFingerprintKey:textProvider:targetLanguage:config:) -> Void` (spawns the background job), `func cancel(bookFingerprintKey:) async`, and an `AsyncStream<BookTranslationProgress>` (`progressUpdates(forBookWithKey:)`) the UI observes for the badge / banner / status sheet. The job calls `textProvider.translationUnits()`, skips units `ChapterTranslationStore.cachedUnits` already covers, fetches each unit's text via `textProvider.sourceText(for:)`, calls `ChapterTranslationService` per unit, posts progress (one unit = one tick — exact because the unit is the spine doc, not the logical TOC chapter, Decision 2.7), honors cancellation between units (edge case (g) — book delete cancels + the store's `deleteTranslations(forBookWithKey:)` cleans up). A book with **zero units** completes immediately with a 0/0 progress and no error. At most **one** running job per book (a `[bookFingerprintKey: Task]` map serializes; edge case (f) — a single-unit re-translate racing the global job both go through `ChapterTranslationStore`'s idempotent-upsert actor, last-writer-wins). |
| `vreader/ViewModels/BilingualReadingViewModel.swift` | `@Observable @MainActor final class` — owns bilingual state for the open book (any format): `isEnabled`, `targetLanguage`, `granularity`, `translationsByUnit: [TranslationUnitID: [String]]`, `isFetching`, `needsSetupSheet`, an injected `ChapterTextProviding` (each format host supplies the concrete adapter — Decision 2.6). **Unit-aware trigger**: `.readerPositionDidChange` fires continuously *within* a unit, so the VM derives the current `TranslationUnitID` from the position `Locator` by calling `ChapterTextProviding.unit(containing:)` on its injected provider — and picks the prefetch target via `unit(after:)` (the single `Locator → unit` seam, Gate-2 round-2 N6; no separate format-host call). It dedupes via `lastTriggerUnit: TranslationUnitID?` + `inFlightUnits: Set<TranslationUnitID>`, and prefetches current + next unit only on an actual unit change. **Epoch-guarded**: an `epoch` counter increments on disable / book-change / unit-change / `onDisappear`; every prefetch `Task` captures its epoch, is cancelled on those events, discards stale-epoch results; disable/book-change also clears `lastTriggerUnit` + `inFlightUnits`. On an offline cache-miss (edge case (c)) records the miss and renders source-only (Decision 2 — no invented affordance). Posts `.readerBilingualDidChange` so each format renderer reacts. |
| `vreader/ViewModels/BookTranslationViewModel.swift` | `@Observable @MainActor final class` — UI-facing state for scope item (3): drives the confirm alert (`estimate`), the status badge / banner / status sheet (subscribes to `BookTranslationCoordinator.progressUpdates`), and the cancel alert. One per book; created lazily by the Book Details sheet / library card / reader. |
| `vreader/ViewModels/ChapterReTranslateViewModel.swift` | `@Observable @MainActor final class` — UI-facing state for scope item (4): holds the provider-override picker selection (`providerProfileID`, `model`, `style: TranslationStyle`, `keepGlossary` per `vreader-retranslate.jsx`), the per-unit re-translate progress, and runs the re-translate. Clears the cache entry via `ChapterTranslationStore.deleteTranslation(forKey:)`, resolves a `ResolvedAIProviderConfig` for the *chosen* profile via `AIService.resolveProviderConfig(profileID:modelOverride:)` (the **`model`** override rides in the config), and calls `ChapterTranslationService` passing the picker's **`style`** as the separate `translationStyle` argument (style is not a config field — Gate-2 round-2 N4). The picker selection never mutates `ProviderProfileStore`'s saved profiles or active id (acceptance criterion (f)). |
| `vreader/Views/Reader/Bilingual/BilingualSetupSheet.swift` | SwiftUI half-sheet — design §2.2 / `BilingualSetupSheet` in `vreader-bilingual.jsx`. Target-language picker (9 languages — the `BILINGUAL_LANGS` set), Paragraph/Sentence segmented control, read-only AI-provider chip linking to Settings when unconfigured. |
| `vreader/Views/Reader/Bilingual/BilingualPill.swift` | The `EN ↔ 中` reader-top-chrome pill subview — `BilingualPill` in `vreader-bilingual.jsx`. |
| `vreader/Views/Reader/Bilingual/EPUBBilingualJS.swift` | `extension EPUBWebViewBridge` static JS (alongside `EPUBHighlightJS.swift` in `Views/Reader/`): (1) `bilingualEnumerateJS()` walks translatable block nodes, stamps each with a stable `data-vreader-bid` attribute, returns `[{bid, text}]`; (2) `bilingualInjectJS(translationsByBid:)` appends a styled, **non-selectable, XPath-excluded** `<div class="vreader-bilingual" data-vreader-decoration>` after each stamped block; (3) `bilingualClearJS()` removes them. All interpolation via `FoliateJSEscaper.escapeForJSString`. |
| `vreader/Views/Reader/Bilingual/FoliateBilingualJS.swift` | The AZW3/MOBI counterpart — JS that runs inside the Foliate reader context. Same enumerate/inject/clear contract; reached via a new `FoliateMessageParser` message kind + a `FoliateSpikeView.Coordinator` send method (the live Foliate path — see the `FoliateSpikeView` modified-file row), not `EPUBWebViewBridge.pendingJS`. |
| `vreader/Services/Reader/BilingualDisplaySegmentMap.swift` | `struct BilingualDisplaySegmentMap: Sendable, Equatable` — the TXT/MD source↔display segment map (Decision 1, Tier B). Records ordered display ranges each tagged `.source(sourceRange: Range<Int>)` or `.synthetic` (a translation block). API: `func sourceOffset(forDisplayOffset:) -> Int?` (nil for synthetic), `func displayOffset(forSourceOffset:) -> Int`, `static var identity: ...` constructor producing a 1:1 pass-through map for the bilingual-off path. Pure → exhaustively unit-testable. |
| `vreader/Views/Reader/Bilingual/BilingualTextRenderer.swift` | TXT/MD interlinear builder — takes the unit's source `NSAttributedString` + segmentation + the unit's `translatedSegments: [String]` (looked up from the VM's `translationsByUnit` by `TranslationUnitID`) and produces (a) the interleaved display `NSAttributedString` (source paragraph runs + synthetic translation runs at `0.88×`, `sub` color) and (b) the matching `BilingualDisplaySegmentMap`. Used by both `TXTReaderContainerView` and `MDReaderContainerView`. |
| `vreader/Views/Reader/Bilingual/PDFBilingualPanel.swift` | **`BLOCKED: needs-design`** (Decision 2). The PDF per-page below-page translation panel. File listed for surface-area completeness; not built in Gate 3 until a design bundle lands. |
| `vreader/Views/Reader/TranslateBook/TranslateBookActionRow.swift` | The Book-Details "Translate entire book…" action row — `TranslateBookActionRow` in `vreader-translate-book.jsx` (idle / running / paused / translated states). |
| `vreader/Views/Reader/TranslateBook/TranslateBookConfirmAlert.swift` | The confirm alert with chapter count + token/cost/time estimate + a "Change provider" path — `TranslateBookConfirmAlert`. |
| `vreader/Views/Reader/TranslateBook/TranslateStatusSheet.swift` | The per-chapter status sheet (queued/translating/done/failed list, throughput, ETA, cancel CTA) — `TranslateStatusSheet` + `ChapterStatusRow`. |
| `vreader/Views/Reader/TranslateBook/TranslateCancelAlert.swift` | The cancel-confirmation alert ("N of M chapters already cached, stay cached") — `TranslateCancelAlert`. |
| `vreader/Views/Reader/TranslateBook/ReaderTranslateBanner.swift` | The reader top-of-page "Translating to X · n/m" banner — `ReaderTranslateBanner`. |
| `vreader/Views/Library/LibraryCardTranslateBadge.swift` | The library-card cover badge (running progress chip / done check) — `LibraryCardTranslateBadge`. |
| `vreader/Views/Reader/ReTranslate/ReTranslatePickerSheet.swift` | The provider-override picker half-sheet (provider list, model chips, style segmented, keep-glossary toggle, cost estimate) — `ReTranslatePickerSheet` + the in-progress `ReTranslateProgress` sheet. |
| `vreader/Views/Reader/ReTranslate/ChapterReTranslateSwipeAction.swift` | The TOC-row swipe action "Re-translate" — `ChapterSwipeAction`. |

### Modified files

| File | Change |
|---|---|
| `vreader/App/VReaderApp.swift` | The `Schema(SchemaV6.models)` constructor call → `Schema(SchemaV7.models)`. (v4's plan cited line 84; the line is verified to be the live-`Schema` constructor — Gate 2 should confirm the exact current line.) |
| `vreader/Models/Migration/SchemaV1.swift` | `VReaderMigrationPlan` — append `SchemaV7.self` to `schemas`. **`stages` stays empty** (Gate-2 round-1 Medium — verified: the live `VReaderMigrationPlan.stages` is empty and the app relies on SwiftData's *implicit* lightweight migration for purely-additive schema changes; adding one independent all-defaulted `@Model` is exactly that case, so no explicit `.lightweight(...)` stage is needed and adding one would diverge from the V1→…→V6 precedent). The earlier plan text that said "append a `.lightweight(...)` stage" is corrected: V7 is implicit-lightweight like every prior bump. |
| `vreader/Services/AI/AIService.swift` | **New resolved-provider seam.** The seam is a full runtime config object, not a bare profile pin (Gate-2 round-1 High — scope item (4)'s override exposes a transient *model* the user picks for one re-translation; a `{profile, apiKey}` pin has nowhere to carry it without mutating saved state). `AIService` gains three methods that produce / consume `ResolvedAIProviderConfig` (the type itself lives in its own file — see the new-files table — because `ChapterTranslationService` / `BookTranslationCoordinator` / `ChapterReTranslateViewModel` all pass it; it is **module-internal**, not file-private to `AIService`). `func resolveActiveProviderConfig() async throws -> ResolvedAIProviderConfig` — runs the feature-flag + consent gates, snapshots the *active* `ProviderProfile`, reads its Keychain key **once** (throws `providerError`/`apiKeyMissing` early), honors `provider`/`providerFactory` test-injection precedence. `func resolveProviderConfig(profileID: UUID, modelOverride: String?) async throws -> ResolvedAIProviderConfig` — resolves a *named* profile from `ProviderProfileStore.loadSnapshot().profiles` (throws `providerError` for an unknown id — Gate-2 round-1 edge case) and applies an optional `modelOverride` (scope item (4)). `func sendRequest(_ request: AIRequest, using config: ResolvedAIProviderConfig) async throws -> AIResponse` — runs the feature-flag + consent gates, builds the concrete provider from `config` (same dispatch switch as `resolveProvider()`), **deliberately does not consult `AIResponseCache`** (`AIRequest.cacheKey` carries no provider identity — verified: the key is `{fpKey}:{locHash}:{action}:{promptVersion}:{promptHash}:{langHash}:{ctxHash}` — so a config-pinned request could be served a cross-provider cached response; and chapter translation has its own provider-aware disk cache via `ChapterTranslation.lookupKey`). `resolveProvider()`, `sendRequest(_:)`, `streamRequest(_:)` and all current callers are **unchanged**. **Where `style` lives**: the re-translate `style` (Literal/Natural/Literary) is **not** on `ResolvedAIProviderConfig` and **not** a wire field — it is a pure prompt-construction input. `ChapterTranslationService` takes a separate `translationStyle: TranslationStyle` parameter and folds it into the chunk `userPrompt`. This is stated once here and is the single source of truth — no other plan row may say the config carries `style`. |
| `vreader/Services/FeatureFlags.swift` | Add `case bilingualReading` to `FeatureFlagKey`; add `var bilingualReading: Bool { isEnabled(.bilingualReading) }`. Bilingual mode is gated behind a flag (consistent with `aiAssistant`) so it can ship dark and be enabled progressively. Default-on or default-off per `FeatureFlags`' environment defaults — Gate 3 WI-1 decides. |
| `vreader/Services/PerBookSettings.swift` | `PerBookSettingsOverride` += `bilingualEnabled: Bool?`, `bilingualTargetLanguage: String?`, `bilingualGranularity: String?` — all optional, additive; the synthesized `Codable init(from:)` already ignores unknown keys, so older per-book JSON decodes (missing keys → `nil` → bilingual off). The new `init` parameters are appended with `nil` defaults. |
| `vreader/Views/Reader/ReaderMoreMenuRow.swift` | Add `case bilingual` (3rd, after `autoTurnPages`, before `bookDetails` — design §2.3); add `case reTranslateChapter` (conditional, see below). **Replace the 2-state `isToggle: Bool`** with a richer presentation: a new `enum TrailingControl { case toggle(Bool); case chevron; case none }` and a `func trailingControl(...)` that returns `.toggle` for `autoTurnPages`, the 3-way bilingual presentation (`toggle(off)` / `toggle(on)` / for the AI-unavailable state `.none` + a chevron-style "Configure AI provider first" sub-detail), and `.chevron` for the rest. The `reTranslateChapter` row is **only** in `visibleRows(...)` when bilingual mode is on for the book (design §4: "a NEW row in the More popover, conditional on `bilingualOn`") — `visibleRows(for:)` gains a `bilingualOn: Bool` parameter. New notifications: `.readerMoreBilingual`, `.readerMoreReTranslateChapter`. Update `dividerAfter` to keep the design's cluster boundary. The deferred-row scope note in the file header is removed (the row is no longer deferred). |
| `vreader/Views/Reader/ReaderMorePopover.swift` | Render the 3-state bilingual row and the conditional re-translate row; extend `trailingAccessory(for:)` to switch on the new `TrailingControl`; the bilingual `unavailable` tap routes to AI Settings; the bilingual on/off toggle posts `.readerMoreBilingual`; the re-translate row opens `ReTranslatePickerSheet`. Thread `bilingualOn` into `resolvedRows`. |
| `vreader/Views/Reader/ReaderNotifications.swift` | Add `.readerMoreBilingual`, `.readerMoreReTranslateChapter`, `.readerBilingualDidChange`, `.readerBookTranslationProgressDidChange` (the last so a reader open on a book being globally-translated can drive its `ReaderTranslateBanner`). Names namespaced `vreader.reader.*`. |
| `vreader/Views/Reader/ReaderTopChrome.swift` | Add a `bilingualActive: Bool` + `bilingualLanguage: String?` param; insert `BilingualPill` into the title `HStack` next to `titleLabel` (a real layout change — WI owns it with layout + accessibility-identifier tests). |
| `vreader/Views/Reader/EPUBWebViewBridge.swift` + `EPUBWebViewBridgeJS.swift` | Run enumerate / inject / clear via the existing `pendingJS` seam; re-run on chapter `didFinish` (the Bug #182 same-cycle-`pendingJS` pattern is already handled — verified at `EPUBWebViewBridge.swift:253`). |
| `vreader/Views/Reader/EPUBHighlightJS.swift` | The XPath serializer (`getXPath`) walks `parent.childNodes` and counts text/element siblings (verified). Injected bilingual `<div data-vreader-decoration>` siblings WOULD shift those counts. **Mitigation**: `getXPath` (and any sibling-index traversal in the highlight/selection JS) skips nodes carrying `data-vreader-decoration`. This is the R-EPUB-CFI fix and is the riskiest single change — it has its own regression test. |
| `vreader/Views/Reader/EPUBReaderContainerView.swift` | Own a `BilingualReadingViewModel`; supply it an `EPUBChapterTextProvider` (so the VM resolves units + per-unit text); present `BilingualSetupSheet` on first enable; wire the More-menu rows + pill; run the EPUB enumerate→translate→inject pipeline. |
| `vreader/Views/Reader/FoliateSpikeView.swift` (+ its `Coordinator`) + `FoliateMessageParser.swift` + `Services/Foliate/JS/foliate-bundle.js` | AZW3/MOBI counterpart. **Gate-2 round-1 High correction**: the live AZW3/MOBI reader dispatch in `ReaderContainerView` (`.foliateWeb` case) renders **`FoliateSpikeView`** — `FoliateReaderContainerView`/`FoliateReaderHost` is not the live path (verified). The bilingual wiring therefore targets `FoliateSpikeView` + its `Coordinator` (which already owns the WKWebView and the whole-book `extractPlainText()` seam). `foliate-bundle.js` gains: (a) per-section text extraction (for `FoliateChapterTextProvider`), (b) enumerate/inject/clear JS in the reader context; `FoliateMessageParser` gains the new message kinds; `FoliateSpikeView` owns a `BilingualReadingViewModel`. |
| `vreader/Views/Reader/TXTReaderContainerView.swift` + `TXTReaderContainerView`'s chunked-table path | Consume `BilingualTextRenderer` output; route every display-offset touchpoint (selection, search/highlight nav, persisted-highlight hit-test, TTS highlight + auto-scroll) through `BilingualDisplaySegmentMap`; pass-through identity map when bilingual off. |
| `vreader/Views/Reader/MDReaderContainerView.swift` | Same as TXT — paged-MD path consumes `BilingualTextRenderer` + `BilingualDisplaySegmentMap`. |
| `vreader/Views/Reader/PDFReaderContainerView.swift` | **`BLOCKED: needs-design`** — owns the `PDFBilingualPanel` once designed. Listed for completeness. |
| `vreader/Views/Reader/BookDetails/BookDetailsActionRow.swift` + `BookDetailsSheet+Actions.swift` + `BookDetailsSheet.swift` | Add `BookDetailsActionRow.Model.Kind.translateBook`; render the `TranslateBookActionRow`; `handleAction(.translateBook)` presents `TranslateBookConfirmAlert`. (Verified: `BookDetailsActionRow.Model.Kind` is a `String` enum with `cover`/`share`/`exportAnnotations` — additive.) |
| `vreader/Views/BookCardView.swift` | Add the long-press `contextMenu` "Translate entire book…" entry + render `LibraryCardTranslateBadge` overlay when a job is running/done for that book. |
| `vreader/Views/Bookmarks/TOCListView.swift` | Add the `ChapterReTranslateSwipeAction` trailing swipe action on chapter rows (design §4 secondary path), gated on bilingual mode being on. |
| `docs/architecture.md` | New `@Model` `ChapterTranslation` + SchemaV7 in the Data Layer + system diagram; new `ChapterTranslationStore` / `ChapterTranslationService` / `BookTranslationCoordinator` actors + the `ChapterTextProviding` boundary in the Services Layer table; the `AIService` resolved-provider seam; new `Notification.Name`s in the Notification Bus table; new `bilingualReading` feature flag (rule 24). |
| `README.md` | Features section — add bilingual reading mode under the AI/reader features (rule 24, user-visible feature). |

### Files OUT of scope

- `vreader/ViewModels/AITranslationViewModel.swift` — the existing AI-Translate-tab
  per-selection translator. **Not reused and not modified.** Design §2.1 explicitly
  *rejects* its per-tap model for bilingual mode. (Note: there is **no
  `BilingualView.swift`** file in the codebase — v4's plan named one in its OUT
  list; that was an error. The translate tab is `AITranslationViewModel` +
  its tab view; this plan leaves it untouched.)
- `vreader/Services/AI/AIResponseCache.swift` — the session-only in-memory cache.
  Bilingual translation uses its own disk store (`ChapterTranslationStore`);
  `AIResponseCache` behavior is unchanged for existing callers.
- `vreader/Services/PersistenceActor*.swift` — the main store. The translation
  cache is a **separate** actor + container (rationale in the
  `ChapterTranslationStore` row); `PersistenceActor` is not modified.
- WebDAV backup format — the translation cache is derived, re-fetchable data,
  **excluded from backup**; no backup-format bump (consistent with how
  `AIResponseCache` is not backed up).

## Prior art / project precedent / rejected alternatives

### Precedent built on

- **`@Model` + schema version** — every prior schema bump (V1→…→V6) is a
  purely-additive change handled by SwiftData's *implicit* lightweight
  migration; `VReaderMigrationPlan.stages` is empty (verified). `ChapterTranslation`
  follows it exactly: one new independent entity, all fields defaulted, no
  explicit `MigrationStage`.
- **Separate actor for a derived store** — the codebase already separates
  concerns by actor (`PersistenceActor` for the durable library;
  `AIResponseCache` as its own type for transient AI data).
  `ChapterTranslationStore` extends that: a durable-but-derived cache gets its
  own actor + container so bulk writes during a global-translate run never
  block library reads.
- **Value-type DTOs across the actor boundary** — `BookRecord`,
  `BookmarkRecord`, `HighlightRecord` are returned instead of `@Model`
  instances. `ChapterTranslationRecord` is the same move.
- **Single provider snapshot per request** — `AIService.resolveProvider()`
  already snapshots the active `ProviderProfile` once per request (verified —
  the code comment cites a prior Gate-2 finding). `resolveActiveProviderConfig()` /
  `resolveProviderConfig(profileID:modelOverride:)` extend the *same* idea to
  one snapshot per multi-request *operation*, into a fully-resolved
  `ResolvedAIProviderConfig`.
- **App-scoped singleton store** — `ProviderProfileStore.shared` is the
  codebase precedent for a store actor that MUST be a single instance in
  production (its source documents exactly this). `ChapterTranslationStore.shared`
  follows it.
- **JS injection via `pendingJS` + `FoliateJSEscaper`** — the EPUB highlight
  API (`EPUBHighlightJS`) and content-replacement transform already use the
  `pendingJS` seam with `FoliateJSEscaper.escapeForJSString` for every
  interpolation; the bilingual EPUB JS copies it.
- **Bug #182 same-cycle `pendingJS`** — `EPUBWebViewBridge.swift:253` already
  handles the case where the container sets `pendingJS` in the same update
  cycle; the bilingual re-inject-on-chapter-change rides that.
- **Capability-gated More-menu rows** — `ReaderMoreMenuRow.visibleRows(for:)`
  already filters rows by `FormatCapabilities`; the conditional
  `reTranslateChapter` row extends the same `visibleRows` filter with a
  `bilingualOn` parameter.
- **`AsyncStream` progress channel** — used elsewhere for long-running
  operations; `BookTranslationCoordinator.progressUpdates` follows that shape.

### Rejected alternatives

- **Side-by-side columns** — design §2.1: at 402px two columns of 17pt serif
  leave <10 chars/line. Rejected.
- **Per-tap inline overlay** — that is feature #18's existing AI Translate tab
  (`AITranslationViewModel`). Bilingual mode's whole point is the user does not
  ask paragraph-by-paragraph. Rejected.
- **Raw `querySelectorAll('p')` order-keyed enumeration** (v4 Gate-2 finding
  F3) — fragile, order-dependent, breaks if a chapter re-renders. Replaced with
  a stamped stable-`data-vreader-bid` enumeration seam.
- **Rare-delimiter splitting of AI output** (v4 F5) — the model can reproduce
  any delimiter. Replaced with a strict JSON-array decode contract (enforced
  via the request prompt — `AIRequest` has no API-level `response_format`
  field, verified — so the contract is prompt-level + strict `JSONDecoder`) and
  a per-segment fallback on count/decode mismatch.
- **Per-chunk active-provider re-check** (v4 round-2 F8) — a re-check between
  chunks still races `AIService`'s per-request resolution. Replaced with a
  one-snapshot resolved-config seam (`ResolvedAIProviderConfig`,
  `resolveActiveProviderConfig()`).
- **A bare `{profile, apiKey}` provider pin** (Gate-2 round-1 High) — cannot
  carry scope item (4)'s transient *model* override without mutating
  `ProviderProfileStore`'s saved profile. Replaced with `ResolvedAIProviderConfig`,
  which carries `model` explicitly; the credential is pinned in it too (a
  mid-operation Keychain rotation cannot change it across chunks).
- **`sendRequest(_:using:)` consulting `AIResponseCache`** (v4 round-3) —
  `AIRequest.cacheKey` is not provider-aware (verified above), so a config-pinned
  request could be served another provider's cached response. The
  `sendRequest(_:using:)` path bypasses the in-memory cache; chapter
  translation has its own provider-aware disk cache.
- **`ChapterTranslation` keyed by `(fingerprint, chapterHref, targetLanguage)`
  only** — drops `providerProfileID`/`promptVersion`, so a provider change
  (edge case (d)) or prompt-version bump would silently serve stale text; and
  `chapterHref` is not even a valid cross-format key (Decision 2.5). Rejected:
  the key includes all five identity fields (`bookFingerprintKey`,
  `unitStorageKey`, `targetLanguage`, `providerProfileID`, `promptVersion`); a
  provider change produces a different `lookupKey` → cache miss → stale entry
  naturally bypassed.
- **Cross-book paragraph-cache reuse** — keeps the cache identity simple and
  `deleteTranslations(forBookWithKey:)` unambiguous. The cache is per-book
  (`bookFingerprintKey` is part of the identity).
- **TXT/MD interlinear via a raw offset shift** (v4 Critical finding F1 —
  `OffsetMap` unsound for synthetic insertion) — a single monotonic offset map
  cannot distinguish a source-backed display offset from a synthetic one, so
  selection/highlight/TTS on a translation block would mis-map to a source
  index. Replaced with `BilingualDisplaySegmentMap` which **tags each display
  range** source-vs-synthetic; synthetic ranges return `nil` for
  `sourceOffset(forDisplayOffset:)` and are simply skipped by every consumer.
- **Carving TXT/MD/AZW3/PDF + scope items (3)/(4) into a follow-up feature**
  (v4 Decision) — v4 did this because the global-translate and re-translate UI
  were `needs-design`-blocked and TXT/MD interlinear looked unbounded. Both
  premises are now false: the 2026-05-18 handoff committed the missing design
  bundles, and `BilingualDisplaySegmentMap` bounds the TXT/MD change. The
  feature stays whole (Decision 3); only the PDF *implementation* is gated on a
  still-missing PDF design bundle (Decision 2), with PDF staying in scope.

## Work-item sequencing

16 WIs. Foundational WIs (no user-observable behavior) land first; per-format
render WIs are independent behavioral leaves.

| WI | Title | Tier | PR size |
|---|---|---|---|
| WI-1 | `TranslationUnitID` value type + `ChapterTranslation` `@Model` (unique stored `lookupKey`, `unitStorageKey`, `providerProfileID: UUID`, `translatedJSON`) + `SchemaV7` + `VReaderMigrationPlan` schema append (no explicit stage) + `bilingualReading` feature flag | foundational | S |
| WI-2 | `ChapterTranslationRecord` DTO (+ canonical `lookupKey` builder) + `ChapterTranslationStore` actor (`.shared` single-instance, single/batch fetch, **idempotent** upsert, single + per-book delete, `cachedUnits`) | foundational | M |
| WI-2.5 | `ChapterTextProviding` boundary protocol + 4 fully-concrete per-format adapters — `EPUBChapterTextProvider`, `TXTChapterTextProvider`, `MDChapterTextProvider`, `PDFChapterTextProvider` (PDF text extraction is JS-free PDFKit + page-range units — entirely foundational, *not* design-blocked, so it lands complete here; only the PDF *render panel* is design-blocked). The `FoliateChapterTextProvider` *Swift shell* lands here too, but its `FoliateSectionExtracting` facade + the new `foliate-bundle.js` per-section JS land in WI-11. | foundational | M |
| WI-3 | `PerBookSettingsOverride` bilingual fields (`bilingualEnabled`/`bilingualTargetLanguage`/`bilingualGranularity`) | foundational | XS |
| WI-4 | `ChapterSegmenter` (paragraph + CJK-aware sentence split) + `ChapterTranslationChunker` (segment-boundary chunking) + the strict-JSON-array translation prompt/decode contract | foundational | M |
| WI-5 | `AIService` resolved-provider seam — `ResolvedAIProviderConfig`, `resolveActiveProviderConfig()`, `resolveProviderConfig(profileID:modelOverride:)`, `sendRequest(_:using:)` (no `AIResponseCache`, no re-resolve) | foundational | M |
| WI-6 | `ChapterTranslationService` actor — cache batch-read → resolve config → chunk → `sendRequest(_:using:)` → strict JSON decode (string-element + count check) + per-segment fallback → cache-write; `Task.checkCancellation()` between chunks | foundational | L |
| WI-7a | `BilingualReadingViewModel` **persistence + state core** — toggle reads/writes `PerBookSettings`, holds `translationsByUnit`, exposes `isEnabled`/`targetLanguage`/`granularity`. No notification, no prefetch. | foundational | S |
| WI-7b | `BilingualReadingViewModel` **behavior** — unit-aware prefetch trigger (`lastTriggerUnit`/`inFlightUnits`), epoch/cancellation, `.readerBilingualDidChange` posting, offline silent-source-fallback | behavioral | M |
| WI-8 | More-menu `bilingual` row (3-way `TrailingControl` presentation) + conditional `reTranslateChapter` row + `ReaderMorePopover` render + row tests | behavioral | M |
| WI-9 | `BilingualSetupSheet` (first-enable half-sheet) + `BilingualPill` in `ReaderTopChrome` (layout + identifier tests) | behavioral | M |
| WI-10 | EPUB interlinear — `EPUBBilingualJS` enumerate/inject/clear (stable IDs, decoration-excluded) + `EPUBHighlightJS` XPath decoration-skip (R-EPUB-CFI) + `EPUBChapterTextProvider` HTML-strip + `EPUBReaderContainerView` wiring | behavioral | L |
| WI-11 | AZW3/MOBI interlinear — `FoliateBilingualJS` + `foliate-bundle.js` per-section extraction **and** enumerate/inject/clear JS + `FoliateMessageParser` message kinds + `FoliateSpikeView` (the live path) wiring | behavioral | L |
| WI-12 | TXT/MD interlinear — `BilingualDisplaySegmentMap` + `BilingualTextRenderer` + `TXT`/`MD` container offset-routing (selection/search/highlight/TTS through the map; identity pass-through when off) | behavioral | L |
| WI-13 | **`BLOCKED: needs-design`** — PDF below-page translation **panel** only (`PDFBilingualPanel` + `PDFReaderContainerView` wiring). `PDFChapterTextProvider` is NOT here — it is foundational and lands complete in WI-2.5. WI-13 does not enter Gate 3 until a design bundle lands; a `Design needed:` GH issue is filed. | behavioral | M |
| WI-14 | Global book translation — `BookTranslationCoordinator` actor + `BookTranslationViewModel` + `TranslateBookActionRow`/`ConfirmAlert`/`StatusSheet`/`CancelAlert` + `ReaderTranslateBanner` + `LibraryCardTranslateBadge` + Book-Details / library-card / reader wiring | behavioral | L |
| WI-15 | Per-chapter re-translation — `ChapterReTranslateViewModel` + `ReTranslatePickerSheet`/`ReTranslateProgress` + `ChapterReTranslateSwipeAction` in `TOCListView` + wiring the More-menu re-translate row to the picker — **final WI** | behavioral | L |

Notes:

- **Foundational WIs**: WI-1, WI-2, WI-2.5, WI-3, WI-4, WI-5, WI-6, WI-7a — a
  value type, a new `@Model`/schema, pure utilities, two service actors, a
  boundary protocol + adapters, and the VM's **persistence/state core**. None
  changes user-observable behavior — unit + integration tests + audit suffice
  (Gate 5).
- **Behavioral WIs**: WI-7b, WI-8..15. Each is verified end-to-end (Gate 5
  slice verification on iPhone 17 Pro Simulator with the `vreader-debug://`
  harness + a fixture book per format). WI-15 is the **final WI** — full
  acceptance pass, evidence file `dev-docs/verification/feature-56-<YYYYMMDD>.md`.
- **WI-7 is split** (Gate-2 round-1 Medium — the original single WI-7 was
  misclassified foundational: a VM that persists settings, posts
  `.readerBilingualDidChange`, and drives prefetch/cancellation produces
  user-observable behavior the moment a format wires it). **WI-7a** is the pure
  persistence/state core (foundational — genuinely no observable behavior, just
  reads/writes `PerBookSettings` and holds a dictionary). **WI-7b** adds the
  trigger + notification + prefetch (behavioral — slice-verified). WI-7b's
  unit-aware trigger is still designed up front: the VM derives the current
  `TranslationUnitID` from the position `Locator` via its injected
  `ChapterTextProviding`; WI-10..13 only *supply* the concrete adapter, so
  WI-7b is fully unit-testable with a mock provider before any format WI lands.
- **WI-13 (PDF)** carries a hard `needs-design` block (Decision 2) — sequenced
  so the other 15 WIs proceed and merge while the PDF design is produced.
- **Parallelism** (rule 48): WI-10 / WI-11 / WI-12 are mutually independent
  (different format containers, disjoint files) — eligible for parallel Gate-3
  execution, one writer per file. WI-14 and WI-15 both touch the More popover /
  TOC list and depend on WI-7b's VM + WI-6's service, so they serialize after
  the behavioral-format WIs.
- WI count is 16 (15 numbered + the WI-2.5 / WI-7a-7b split). Rule 47 permits
  5+ WIs as "Large" and notes "consider whether the plan should split into
  multiple features" at "genuinely 10+ WIs". Considered — and **rejected**:
  the WIs share one coherent subsystem (the `ChapterTranslation` cache + the
  translation service + the `ChapterTextProviding` boundary). Splitting would
  force the format-render WIs into a second feature that hard-depends on the
  first's cache/service — an artificial seam. The foundational/behavioral split
  + the independent per-format leaves *is* the natural decomposition; the
  feature ships as a sequence of small PRs, not one mega-PR.

## Test catalogue

| Test file | Covers |
|---|---|
| `ChapterTranslationStoreTests` | In-memory `ModelContainer`; insert/fetch/dedupe by `lookupKey`; **idempotent upsert** — upserting the same `lookupKey` twice updates in place and never throws a unique-constraint error; batch fetch returns the right subset; single `deleteTranslation(forKey:)`; `deleteTranslations(forBookWithKey:)`; `cachedUnits(...)` returns exactly the covered `unitStorageKey`s; `providerProfileID` round-trips as `UUID`; `translatedSegments` round-trips through `translatedJSON`; SchemaV6→V7 implicit-lightweight migration opens an existing store unchanged. |
| `TranslationUnitIDTests` | `storageKey` is stable and distinct per `Kind`; `Codable` round-trips; `Hashable`/`Equatable` correct so it can key a dictionary and a `Set`. |
| `ChapterTranslationRecordTests` | `lookupKey(...)` is deterministic and changes when **any** identity field changes (incl. `unitStorageKey`, `providerProfileID`, `promptVersion` — pins edge case (d)); two records with different providers produce different keys. |
| `ChapterTextProviderTests` | Per adapter (`EPUB`/`TXT`/`MD`/`PDF`) with a fixture book — `translationUnits()` returns the units in reading order; `sourceText(for:)` returns the unit's plain text; an out-of-book `TranslationUnitID` throws; a book with zero units returns `[]`; `unit(containing:)` maps a mid-book `Locator` to the right unit and returns `nil` for a pre-book locator; `unit(after:)` returns the next unit and `nil` at the last unit; EPUB units = spine documents (not TOC entries — a fixture with a multi-spine logical chapter proves the unit is the spine doc). |
| `ChapterSegmenterTests` | `@Test(arguments:)` — empty text; single paragraph; blank-line-separated paragraphs; CJK sentence split (`。！？`); Latin sentence split; mixed CJK/Latin; trailing whitespace; a paragraph with no terminal punctuation. |
| `ChapterTranslationChunkerTests` | `@Test(arguments:)` — empty; one over-budget segment alone (own chunk); many tiny segments; exact-boundary; CJK char-vs-byte counting; never splits a segment across chunks. |
| `AIServiceTests` (extend) | `resolveActiveProviderConfig()` runs the feature-flag/consent gates and throws `apiKeyMissing` with no key; `resolveProviderConfig(profileID:modelOverride:)` resolves a *named* (non-active) profile, applies the `modelOverride`, and throws `providerError` for an unknown id; `sendRequest(_:using:)` uses the config's provider with no re-resolve (swap the active profile mid-test → the config output stays on the original); `sendRequest(_:using:)` does **not** serve an `AIResponseCache` entry left by a different provider for the same `cacheKey`; the credential is pinned in the config (a Keychain key change after `resolveActiveProviderConfig()` does not affect in-flight requests); `provider`/`providerFactory` test-injection precedence preserved; `resolveProvider()`/`sendRequest(_:)` unchanged. |
| `ChapterTranslationServiceTests` | Mock `AIService` + in-memory `ChapterTranslationStore` — cache hit skips the API call (`fromCache == true`); miss calls once + writes back; **JSON-array decode**: well-formed N-element array maps back in order; malformed / short / long array / **non-string elements / nested arrays** → per-segment fallback; config-pinned (active-profile change mid-op does not change the provider used); the `style` override appears in the chunk `userPrompt`; partial-failure leaves prior chunks cached; `Task.checkCancellation()` between chunks stops a cancelled translate promptly. |
| `BookTranslationCoordinatorTests` | Mock `ChapterTextProviding` + service + store — `estimate(...)` returns the unit count; `start(...)` iterates units and skips `cachedUnits`-covered ones; **a zero-unit book completes immediately at 0/0 with no error**; `progressUpdates` emits monotonic progress; `cancel(...)` stops the job between units and emits a cancelled state; at most one job per book (a second `start` for the same book is a no-op or replaces); book delete cancels + cleans up (edge case (g)); the **active provider deleted mid-job** — the job keeps using its pinned `ResolvedAIProviderConfig` and finishes (the config was resolved once at `start`); concurrent single-unit re-translate + global job on the same unit both go through the store's idempotent upsert — last-writer-wins, no corruption (edge case (f)). |
| `BilingualReadingViewModelTests` | `@MainActor`, mock `ChapterTextProviding` — (WI-7a) toggle persists to `PerBookSettings`; first-enable raises `needsSetupSheet`, subsequent enables do not; (WI-7b) **repeated `.readerPositionDidChange` within one unit triggers exactly one prefetch** (unit dedupe via `lastTriggerUnit`/`inFlightUnits`); a real unit change cancels the old epoch and starts a new prefetch (current + next); a stale-epoch result is discarded; disable clears `translationsByUnit` + resets `lastTriggerUnit`/`inFlightUnits`; book-change bumps the epoch; an offline cache-miss records the miss and produces source-only state (no synthetic block). |
| `ChapterReTranslateViewModelTests` | `@MainActor` — re-translate clears the cache entry (`deleteTranslation(forKey:)`) then re-fetches; selecting a provider override builds a `ResolvedAIProviderConfig` for the *chosen* profile with the picker's `model` override applied, and does **not** mutate `ProviderProfileStore`'s saved profiles or active id (acceptance criterion (f)); the picker's `style` flows into the translation prompt; progress updates surface; an error surfaces the retry state. |
| `BilingualDisplaySegmentMapTests` | `@Test(arguments:)` — identity map is a 1:1 pass-through; a map with one synthetic block: `sourceOffset` is `nil` inside the synthetic range, correct on either side; `displayOffset(forSourceOffset:)` shifts past synthetic blocks; multiple interleaved blocks; empty chapter; boundary offsets (0, end). |
| `ReaderMoreMenuRowTests` (extend) | The 3-way bilingual `TrailingControl` (`toggle(off)`/`toggle(on)`/`none`+chevron for unavailable); `visibleRows(for:bilingualOn:)` includes `bilingual` always and `reTranslateChapter` only when `bilingualOn`; divider position; new notification round-trips via `init?(notification:)`. |
| `PerBookSettingsTests` (extend) | Older per-book JSON (no bilingual keys) decodes with `nil` bilingual fields; round-trip with the new fields; resolve is unaffected (bilingual fields are not part of `ResolvedSettings`). |
| `EPUBBilingualJSTests` | The generated JS strings escape correctly via `FoliateJSEscaper`; enumerate output shape (`[{bid,text}]`); inject/clear idempotent; injected divs carry `data-vreader-decoration` + `user-select:none`. |
| `EPUBHighlightAnchoringRegressionTests` (extend Feature #11 coverage) | With bilingual divs injected, EPUB highlight create/restore still anchors to the correct source range — proves the `getXPath` decoration-skip works (R-EPUB-CFI). Gates WI-10's merge. |
| `FoliateBilingualJSTests` | Foliate enumerate/inject/clear JS shape + escaping; the new `FoliateMessageParser` message kind parses. |
| `BilingualTextRendererTests` | TXT/MD: interleaving N source paragraphs + N translations produces the expected display `NSAttributedString` run structure and a `BilingualDisplaySegmentMap` whose source ranges round-trip; off-mode produces the source string + identity map unchanged. |
| TXT/MD reader regression (extend existing TXT/MD container coverage) | With bilingual on, selection / search-highlight navigation / persisted-highlight hit-test / TTS highlight all resolve to the correct *source* offsets via the segment map; with bilingual off, every offset path is byte-identical to today (proves the pass-through). |

Audit-driven additions expected (per rule 47 Gate 2 — corruption / partial
failure / idempotency): a cache row with a stale `promptVersion` is bypassed;
a cache row whose `sourceParagraphCount` no longer matches the live chapter is
treated as stale; double-enable is idempotent; a global-translate job
interrupted by app backgrounding resumes (cached chapters skipped); an EPUB
chapter that re-renders mid-translation does not double-inject.

## Risks + mitigations

- **R-EPUB-CFI (highest) — injected divs vs EPUB CFI / highlight anchoring.**
  Verified: `EPUBHighlightJS.getXPath` serializes a node path by counting
  `parent.childNodes` text/element siblings. Injecting a translation `<div>`
  after each `<p>` shifts those sibling counts → existing highlights (feature
  #11) could mis-anchor. *Mitigation*: injected divs carry
  `data-vreader-decoration` + `user-select:none`; WI-10 makes `getXPath` and
  every sibling-index traversal in the highlight/selection JS **skip
  decoration nodes**. `EPUBHighlightAnchoringRegressionTests` gates WI-10's
  merge — bilingual mode must not move or drop existing highlights.
- **R-TXT-offsets — interleaved translation shifts every TXT/MD display
  offset.** Verified: TXT/MD readers consume raw source-UTF16 offsets in
  selection, search, highlight nav, persisted-highlight hit-test, TTS. *Mitigation*:
  `BilingualDisplaySegmentMap` tags each display range source-vs-synthetic;
  every offset-consuming touchpoint routes through it; the off-path uses an
  identity map proven byte-identical by the regression test. This is the v4
  Critical-finding fix done properly (a *segment* map, not a monotonic offset
  shift).
- **R-translate-mapping — chunk response ↔ source segment mapping.**
  *Mitigation*: the chunk prompt instructs the model to return only a JSON
  array of N translated strings; the service strictly `JSONDecoder`-decodes
  `AIResponse.content`, asserts the count equals the chunk's segment count, and
  on any mismatch falls back to one-segment-per-request.
- **R-unit-identity (high — Gate-2 round-1 Critical) — `chapterHref` is not a
  cross-format identity.** Verified: TXT's chapter href is synthetic + chapter-
  mode-gated, MD has no href, PDF is page-based. *Mitigation*: Decision 2.5 —
  the cache, VM, and coordinator all key on `TranslationUnitID` (a format-
  tagged value type) with explicit per-format derivation; the disk field is
  `unitStorageKey`. Decision 2.7 fixes the *unit* as the spine document (not
  the logical TOC chapter) so progress counts are exact and the
  many-TOC-entries-to-one-href ambiguity is avoided.
- **R-chapter-text (high — Gate-2 round-1 Critical) — no per-unit text API.**
  Verified: `ReaderAICoordinator` windows ~2500 chars, Foliate's seam is
  whole-book `extractPlainText()`. *Mitigation*: Decision 2.6 — a foundational
  `ChapterTextProviding` boundary (WI-2.5) with per-format adapters; the
  Foliate adapter requires genuinely new per-section JS in `foliate-bundle.js`
  (scoped into WI-11). `ChapterTranslationService` / `BookTranslationCoordinator`
  consume the boundary, never a format-specific extractor.
- **R-foliate-live-path (high — Gate-2 round-1 High) — AZW3/MOBI live reader
  is `FoliateSpikeView`.** Verified: `ReaderContainerView`'s `.foliateWeb` case
  renders `FoliateSpikeView`, not `FoliateReaderContainerView`. *Mitigation*:
  WI-11 targets `FoliateSpikeView` + its `Coordinator` (the live path);
  `FoliateReaderContainerView` is not touched.
- **R-provider-config — mixed-provider output across a multi-chunk operation +
  provider-override expressiveness.** `AIService.sendRequest(_:)`/`resolveProvider()`
  snapshot the active provider *per request* (verified), so a chunked operation
  can straddle a mid-operation profile swap; and (Gate-2 round-1 High) a bare
  `{profile, apiKey}` pin cannot carry the re-translate UI's transient *model*
  override. *Mitigation*: the seam is `ResolvedAIProviderConfig` — a full
  runtime config (`kind`, `baseURL`, `apiKey`, `model`, `maxTokens`) resolved
  **once per operation**, carrying the credential (no mid-op Keychain drift)
  and the model (re-translate override without mutating saved state).
  `ChapterTranslationService` routes every chunk + fallback through
  `sendRequest(_:using: config)`, which bypasses `AIResponseCache` (the
  in-memory key is not provider-aware). `style` is folded into the prompt by
  the service, not a wire field.
- **R-store-ownership (Gate-2 round-1 High) — concurrent same-`lookupKey`
  inserts.** Last-writer-wins via actor serialization only holds if there is
  ONE store instance. *Mitigation*: `ChapterTranslationStore.shared` is an
  app-scoped single instance (the `ProviderProfileStore.shared` precedent);
  production callers use `.shared`. Defense in depth: `upsert` is *idempotent*
  — it fetches by `lookupKey` and updates in place rather than relying on the
  unique constraint to throw.
- **R-cancellation — stale prefetch results + same-unit scroll churn.**
  `.readerPositionDidChange` posts continuously *within* a unit.
  *Mitigation*: `BilingualReadingViewModel` (a) dedupes the trigger to
  `TranslationUnitID` transitions via `lastTriggerUnit` + `inFlightUnits`;
  (b) is epoch-guarded — tasks capture their epoch, are cancelled on
  disable/book-change/unit-change/disappear, late results from a superseded
  epoch are dropped.
- **R-global-cost — whole-book token spend.** *Mitigation*: the confirm alert
  (`TranslateBookConfirmAlert`) shows chapter count + token/cost/time estimate
  before the user commits (acceptance criterion (d)); already-cached chapters
  are skipped; the job is cancellable and the cancel alert disabuses the user
  that cached work is lost.
- **R-global-lifecycle — book deleted / app backgrounded mid-job.**
  *Mitigation*: `BookTranslationCoordinator` honors cancellation between
  chapters; book delete cancels the job and the store's
  `deleteTranslations(forBookWithKey:)` cleans up (edge case (g)); a
  backgrounded job resumes from cache (no chapter is re-translated).
- **R-offline (edge case (c)).** *Mitigation*: `ChapterTranslationService`
  serves from `ChapterTranslationStore` if present; otherwise the renderer
  shows **source-only** text (identical to non-bilingual mode — no synthetic
  block) and the VM records the miss for a later online prefetch. The *visible*
  "translation unavailable" affordance is **`needs-design`-blocked** (Decision
  2 — no committed bundle depicts it; inventing it violates rule 51). A
  `Design needed:` GH issue is filed; the affordance ships in a follow-up WI
  once designed. No crash, no partial render in the meantime.
- **R-row-model — More-menu is 2-state (`isToggle: Bool`) today.** Verified.
  *Mitigation*: WI-8 replaces `isToggle` with the `TrailingControl` enum
  **before** adding the bilingual case, with row tests; the conditional
  `reTranslateChapter` row threads a `bilingualOn` flag through `visibleRows`.
- **R-foliate-bundle — vendored `foliate-bundle.js` edit regression risk.**
  Verified: no per-section extraction and no paragraph-injection seam exist in
  Foliate today — both are new JS. *Mitigation*: WI-11 adds the per-section
  extraction + enumerate/inject/clear JS to the reader context of
  `foliate-bundle.js` and new `FoliateMessageParser` message kinds; scoped as
  its own `L` WI because vendored-bundle edits carry regression risk (covered
  by `FoliateBilingualJSTests` + a slice verification with an AZW3 **and** a
  MOBI fixture — AZW3 and MOBI can differ in how foliate-js segments sections,
  so both are exercised).
- **R-pdf-design — PDF below-page panel is undesigned.** *Mitigation*:
  Decision 2 — WI-13 is `needs-design`-blocked, a `Design needed:` GH issue is
  filed, the other 15 WIs proceed; PDF stays in scope but its implementation
  waits for a bundle.
- **R-offline-design — the offline "unavailable" affordance is undesigned.**
  *Mitigation*: Decision 2 — bilingual offline-miss renders source-only (no
  invented affordance); the visible state is `needs-design`-blocked with its
  own `Design needed:` GH issue and ships in a follow-up WI.
- **R-schema-current-line — `VReaderApp.swift` `Schema(...)` line.** A prior
  plan cited a hard-coded line; line numbers drift. *Mitigation*: WI-1 locates
  the live `Schema(SchemaV6.models)` constructor by content, not line number.

## Backward compat

- **Schema**: V6→V7 adds one independent `@Model` (`ChapterTranslation`), every
  field defaulted → SwiftData *implicit* lightweight migration; existing stores
  open unchanged. `VReaderMigrationPlan.stages` stays empty (verified — every
  prior bump did the same); no explicit `MigrationStage`. (Note:
  `ChapterTranslation` is stored in the **main** SwiftData container so it
  participates in the schema version, even
  though `ChapterTranslationStore` is a *separate actor* — the actor wraps its
  own `ModelContext` over the same container. SchemaV7's `models` list includes
  it; the migration plan covers it.)
- **`PerBookSettings`**: the 3 new fields are optional; the synthesized
  `Codable init(from:)` ignores missing keys (verified — the file header states
  this and it already survived feature #54 dropping `readingMode`). Pre-#56
  per-book JSON decodes with `nil` bilingual fields → bilingual off.
- **`AIService`**: the resolved-provider seam is purely additive — one new
  struct (`ResolvedAIProviderConfig`), three new methods; `resolveProvider()`,
  `sendRequest(_:)`, `streamRequest(_:)` and all their existing callers are
  untouched. `sendRequest(_:using:)` deliberately skips `AIResponseCache` — no
  change to the cache's behavior for existing callers.
- **`FeatureFlags`**: `bilingualReading` is a new `case`; existing flags
  unaffected. Whether it persists / defaults-on is decided in WI-1 consistent
  with how `aiAssistant` is handled.
- **`ReaderMoreMenuRow`**: replacing `isToggle: Bool` with `TrailingControl`
  changes the row contract — but `ReaderMoreMenuRow` is internal; the only
  consumer is `ReaderMorePopover` (modified in WI-8) and the row tests
  (extended in WI-8). No persisted data depends on it.
- **Backups**: the translation cache is derived, re-fetchable data — excluded
  from WebDAV backup; a restore-to-fresh-device re-fetches translations on
  demand. No backup-format bump.
- **Existing AI Translate tab** (`AITranslationViewModel`): untouched —
  per-selection translation keeps working exactly as today; bilingual mode is a
  separate, additive surface.

## Revision history

- **v1 (2026-05-19)** — full-scope plan, all 4 scope items × 5 formats, 15
  numbered WIs. Supersedes `20260518-feature-56-bilingual-reading-mode.md` v4
  (the narrowed escape-hatch written before the 2026-05-18 design handoff).
  v4's Gate-2 findings F1–F11 carried forward as prior art. Author: feature
  Gate 1.
- **v2 (2026-05-19)** — Gate 2 audit **round 1** (Codex thread `019e4029`,
  read-only against the live codebase): 2 Critical, 4 High, 3 Medium. All real;
  verdict "reject as-is". Resolutions, all incorporated:
  - **C1 (Critical — `chapterHref` not a cross-format identity)** — fixed:
    Decision 2.5 introduces `TranslationUnitID` (format-tagged value type) with
    explicit per-format derivation; the disk field is `unitStorageKey`; VM
    state is `translationsByUnit`. New WI-1 deliverable.
  - **C2 (Critical — no per-unit chapter-text API)** — fixed: Decision 2.6
    introduces the `ChapterTextProviding` boundary + 5 per-format adapters as a
    new foundational WI-2.5; the service + coordinator consume the boundary.
  - **H1 (High — WI-11 targets a non-live Foliate path)** — fixed: verified
    `ReaderContainerView`'s `.foliateWeb` case renders `FoliateSpikeView`; WI-11
    + the modified-files table + R-foliate-live-path now target `FoliateSpikeView`.
  - **H2 (High — provider override can't be a bare `{profile,apiKey}` pin)** —
    fixed: the seam is `ResolvedAIProviderConfig` (full runtime config carrying
    `model`); `style` folds into the prompt.
  - **H3 (High — EPUB TOC ≠ spine, "chapter" underspecified)** — fixed:
    Decision 2.7 fixes the translation *unit* = spine document (EPUB/Foliate) /
    `TXTChapterIndex` / `MDChapterStartScanner` chapter — the format's natural
    render segment, not the logical TOC chapter.
  - **H4 (High — `ChapterTranslationStore` concurrency depends on single
    instance)** — fixed: `ChapterTranslationStore.shared` app-scoped single
    instance (`ProviderProfileStore.shared` precedent) + idempotent `upsert`
    that never relies on the unique constraint to throw.
  - **M1 (Medium — WI-7 misclassified foundational)** — fixed: WI-7 split into
    WI-7a (persistence/state core — foundational) + WI-7b (trigger + notification
    + prefetch — behavioral).
  - **M2 (Medium — invented offline affordance violates rule 51)** — fixed:
    Decision 2 — the offline "unavailable" affordance is `needs-design`-blocked
    (its own GH issue); offline-miss renders source-only meanwhile.
  - **M3 (Medium — migration-stage contradiction)** — fixed: `VReaderMigrationPlan.stages`
    stays **empty** (verified — every prior bump used implicit lightweight
    migration); the earlier ".lightweight stage" text is corrected throughout.
  - WI count after fixes: 16 (15 numbered + the WI-2.5 insertion and the
    WI-7a/7b split).
- **v3 (2026-05-19)** — Gate 2 audit **round 2** (same Codex thread `019e4029`):
  C2/H1/H3/H4/M1/M3 confirmed fully resolved; C1/H2/M2 found *partially*
  resolved (residual document-consistency gaps), plus new issues — total 2
  High + 5 Medium. All real; verdict "not Gate-2-clean". Resolutions, all
  incorporated:
  - **N1 (High — `ResolvedAIProviderConfig` cannot be `AIService`-internal)** —
    fixed: the type moves to its own file `ResolvedAIProviderConfig.swift` as a
    **module-internal** type (3 non-`AIService` types reference it).
  - **N2 (High — Foliate provider not actually Sendable-safe)** — fixed:
    verified `FoliateCoordinatorBox` is `@MainActor`; `FoliateChapterTextProvider`
    holds no UI-bound state and bridges via a `@MainActor` `FoliateSectionExtracting`
    facade (the `async` actor hop is the bridge), so the provider struct stays
    trivially `Sendable`.
  - **N3 (Medium — stale `translationsByChapterHref` in the renderer row)** —
    fixed: `BilingualTextRenderer` row rewritten to the unit-based contract.
  - **N4 (Medium — `style` specified inconsistently)** — fixed: a single
    source-of-truth statement — `style` is `TranslationStyle`, NOT a
    `ResolvedAIProviderConfig` field, consumed only by `ChapterTranslationService`'s
    prompt builder; the `AIService`, service, and re-translate-VM rows all
    aligned.
  - **N5 (Medium — WI-13/WI-2.5 PDF duplicate ownership)** — fixed:
    `PDFChapterTextProvider` (JS-free, foundational) lands **complete in
    WI-2.5**; WI-13 is the design-blocked *panel* only.
  - **N6 (Medium — no named `Locator → unit` resolution seam)** — fixed:
    `ChapterTextProviding` extended with `unit(containing: Locator)` +
    `unit(after:)`; the VM uses them, no separate resolver type.
  - **N7 (Medium — "No `needs-design` block remains" summary contradicts the
    body)** — fixed: the design-coverage summary now states the top-level
    surfaces are designed and two derived states (PDF panel, offline
    affordance) are design-blocked.
- **v4 (2026-05-19)** — Gate 2 audit **round 3** (same Codex thread `019e4029`,
  the rule-47 maximum): all 7 round-2 findings (N1–N7) confirmed resolved; 1
  High + 1 Low remained, both *new*, both mechanical type-level fallout of v3's
  N2 fix. Resolutions, both incorporated:
  - **High (`FoliateSectionExtracting` existential not `Sendable`-constrained)**
    — fixed: `FoliateChapterTextProvider` becomes an **`actor`** (an actor is
    `Sendable` by construction — the other 4 adapters stay `struct`s); the
    facade protocol is declared `@MainActor protocol FoliateSectionExtracting:
    AnyObject, Sendable` (a `@MainActor`-isolated `AnyObject` existential is
    safely `Sendable`). Codex spelled out this exact resolution.
  - **Low (VM "via the format host" wording drift)** — fixed: the
    `BilingualReadingViewModel` row now states locator→unit resolution goes
    through the injected `ChapterTextProviding.unit(containing:)` /
    `unit(after:)` — the single N6 seam.
  - **Gate 2 status — round cap reached, disposition = fix-and-accept.**
    Three audit rounds are the rule-47 / feature-workflow maximum. The finding
    count converged monotonically (9 → 7 → 2) and round-3's two findings were
    trivial, uncontested fallout of one v3 addition — Codex itself stated the
    exact fix for the High. v4 incorporates both fixes but has **not** been
    re-audited (a round 4 would exceed the cap). Per rule 47 Gate 2 this is
    recorded as the author applying the round-3 fixes and **accepting** the
    plan as Gate-2-clean: the two fixes are mechanical and self-evidently
    resolve the findings (the precedent is the prior `20260518-...-mode.md` v4,
    which took the same fix-and-accept disposition at its round-3 cap). No open
    Critical/High/Medium remain after the v4 fixes; no Low findings are left
    unaddressed (the one Low was fixed, not accepted-as-is). The plan is
    **Gate-2-clean** and ready for Gate 3 staging.
