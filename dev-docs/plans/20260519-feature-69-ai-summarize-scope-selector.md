# Feature #69 — AI Summarize scope selector — implementation plan

- **Feature row**: `docs/features.md` #69 (TODO → PLANNED on Gate-2 clean)
- **GH issue**: created at Gate-2 row-flip (no GH issue at plan-authoring time)
- **Design source** (committed, rule 51 satisfied):
  `dev-docs/designs/vreader-fidelity-v1/project/vreader-panels.jsx` —
  `SummaryView` (lines ~512-573): the three scope chips (`Section`,
  `Chapter`, `Book so far`) rendered as a pill row above the summary card,
  with the active chip filled in `t.accent`. The chip strip is the only
  new visible surface; the summary card, idle/loading/error states, and
  Share/Regenerate footer are already shipped by feature #65 WI-1.
- **Author**: feature-cron (Gate 1), 2026-05-19
- **Status**: v3 — Gate-2 audit **CLEAN after 3 rounds** (Codex thread
  `019e3e09`). Audit findings + resolutions are in §11; revision history in
  §10. Feature #69 row → `PLANNED`.
- **Lineage**: feature #65 Gate-2 carve-out (Codex thread `019e3b84`).
  #65 re-skinned the AI Summarize tab body but omitted the scope chips
  because making them functional is a behavior change, not a re-skin.

## 1. Problem

The AI Summarize tab summarizes a **fixed ~2500-char window** centered on
the reading position. `AIContextExtractor` (the only context source) always
extracts that window; `AIAssistantViewModel.summarize(locator:textContent:format:)`
takes no scope parameter. A reader who wants "summarize this whole chapter"
or "summarize the book up to where I am" has no control — every summary is
the same narrow slice regardless of intent.

The committed design (`vreader-panels.jsx` `SummaryView`) shows three scope
chips — **Section** (the current behavior), **Chapter** (a chapter-bounded
window), **Book so far** (a token-capped prefix from the start of the book
up to the reading position). #69 makes those chips functional.

User need: choose how much of the book the AI summary covers, without
leaving the reader.

## 2. Surface area

All paths confirmed by codebase read (2026-05-19) and re-verified against
the Gate-2 round-1 audit. The largest risk class — naming a
type/field/method that does not exist — is addressed inline.

### 2.0 — Round-1 audit pivot: the data-source and format-scope reality

The Gate-2 round-1 audit surfaced three facts that reshape the plan; v2 is
built on them (full detail in §11):

1. **`ReaderAICoordinator.currentTextContent` is already a pre-extracted
   ~2500-char section window**, not the full book text
   (`ReaderAICoordinator.swift:41` — it runs `AIContextExtractor` and
   returns the trimmed result). The AI sheet passes *that* into
   `AIReaderPanel` (`ReaderContainerView+Sheets.swift:273`). Running a
   Chapter / Book-so-far extraction on an already-trimmed snippet is
   meaningless. **#69 must extract from the full text** —
   `ReaderAICoordinator.loadedTextContent` (the un-extracted full flattened
   text) is the correct source. v2 threads `loadedTextContent` through as a
   separate `fullTextContent` input for the Summarize tab.
2. **MD locator offsets and MD TOC offsets live in different coordinate
   spaces.** `ReaderAICoordinator.loadBookTextContent(format:"md")` loads
   **raw Markdown source** (`String(contentsOf:encoding:.utf8)`); `TOCBuilder`
   MD entries are computed in raw-source offsets too — but the live MD
   *locator* (`MDReaderViewModel.makeLocator`) carries **rendered-text**
   offsets (`MDDocumentInfo.renderedText` — markdown syntax stripped).
   Slicing raw source by a rendered-text offset is wrong. **v2 scopes real
   Chapter / Book-so-far bounds to TXT only**; MD joins EPUB/PDF/AZW3 in the
   Section-degrade set. (TXT is coordinate-consistent: `loadBookTextContent`
   loads the raw `.txt` and the TXT TOC offsets + the TXT locator are all in
   that same text space.)
3. **The TOC is owned by `ReaderContainerView`, not `ReaderAICoordinator`.**
   `ReaderContainerView` has `@State var tocEntries: [TOCEntry]`
   (`ReaderContainerView.swift:79`) populated by `ensureTOCReady()` →
   `ReaderTOCFactory.buildTOC(...)` (`ReaderContainerView+Sheets.swift:85`).
   **v2 reuses that existing `tocEntries`** — it adds no TOC owner and no
   TOC-extraction code to `ReaderAICoordinator`.

### 2.1 — New type: `SummaryScope`

**New file** `vreader/Services/AI/SummaryScope.swift` (~45 LOC).

```swift
/// The breadth of text an AI summary covers. Drives AIContextExtractor.
enum SummaryScope: String, CaseIterable, Sendable, Equatable {
    case section      // the current ~2500-char window (today's behavior)
    case chapter      // the TOC-chapter-bounded slice around the locator
    case bookSoFar    // a token-capped prefix from book start to the locator

    /// The chip label shown in SummaryView. Matches the design strings.
    var displayName: String {
        switch self {
        case .section:   return "Section"
        case .chapter:   return "Chapter"
        case .bookSoFar: return "Book so far"
        }
    }
}
```

`Sendable`/`Equatable`/`CaseIterable` — `CaseIterable` drives the chip
`ForEach`; `Equatable` drives chip-selection comparison; `Sendable` because
it crosses into `AIAssistantViewModel` (`@MainActor`) and the extractor
(`Sendable` struct). `String` raw value gives a stable key.

### 2.2 — New type: `ChapterBounds`

**New file** `vreader/Services/AI/ChapterBounds.swift` (~30 LOC).

```swift
/// The UTF-16 character span of one chapter in a book's flattened text,
/// used to bound a Chapter-scoped AI summary. UTF-16 offsets to match
/// Locator.charOffsetUTF16 + AIContextExtractor's existing TXT/MD math.
struct ChapterBounds: Sendable, Equatable {
    let startUTF16: Int   // inclusive
    let endUTF16: Int     // exclusive
}
```

UTF-16 because that is the unit `Locator.charOffsetUTF16` and the TXT TOC
entries already use — mixing units is the bug class to avoid.

### 2.3 — `AIContextExtractor` — add scoped extraction with an explicit UTF-16 budget

**Modified file** `vreader/Services/AI/AIContextExtractor.swift`.

Round-1 finding [5]: the extractor today mixes UTF-16 math (TXT/MD
`extractByCharOffset`) with `String.count` *character* math (EPUB/PDF
`extractByPage`/`extractByProgression`). #69's scoped paths slice by UTF-16
offsets, so the budget must be an explicit, named **UTF-16 budget** — not an
ambiguous "character count".

Add a scope-aware entry point; keep the old `extractContext(locator:textContent:format:)`
as a `.section`-scoped delegating shim so existing callers
(`AIAssistantViewModel.performAction`, `ReaderAICoordinator.currentTextContent`)
compile and behave byte-identically:

```swift
func extractContext(
    locator: Locator,
    fullText: String,                 // the FULL flattened text (not a snippet)
    format: BookFormat,
    scope: SummaryScope,
    chapterBounds: ChapterBounds?,     // nil ⇒ chapter scope degrades to section
    maxUTF16: Int = 12_000             // explicit UTF-16-unit budget — see §6 R-1
) -> String
```

- `.section` → existing `extractByCharOffset` / `extractByPage` /
  `extractByProgression` logic, unchanged. (The legacy entry point delegates
  here with `scope: .section`.)
- `.chapter` → new `extractChapter(...)`: take the UTF-16 sub-sequence
  `[chapterBounds.startUTF16 ..< chapterBounds.endUTF16]` of `fullText`
  (`utf16View.index(...)` + `samePosition(in:)` — the exact pattern already
  in `extractByCharOffset`, with the same fallback-to-prefix guard). Clamp
  both bounds to `[0, fullText.utf16.count]`. If the slice exceeds `maxUTF16`
  units, fall back to a `maxUTF16`-wide UTF-16 window centered on the
  locator's offset *within* the chapter. If `chapterBounds == nil`, delegate
  to `.section`.
- `.bookSoFar` → new `extractBookSoFar(...)`: resolve the locator's UTF-16
  offset; take the prefix `[0 ..< offset]`; if longer than `maxUTF16` units,
  take the **last** `maxUTF16` UTF-16 units before the offset (recency-biased
  — the text nearest the reading position is the most relevant; a true
  map-reduce summarizer is explicitly deferred, §6 R-3 / §9). All slicing
  done via `utf16View.index` + `samePosition(in:)` so a surrogate pair is
  never split (the round-1 finding-[5] hazard).

The locator-offset resolution reuses the existing center-offset logic in
`extractByCharOffset` (UTF-16, for TXT). Because v2 scopes real Chapter /
Book-so-far to **TXT only** (§2.0 fact 2), the scoped helpers only ever run
on TXT text — `charOffsetUTF16` is always present and meaningful there.

### 2.4 — New type: `SummaryScopeResolver`

**New file** `vreader/Services/AI/SummaryScopeResolver.swift` (~75 LOC).

Pure, `Sendable`, no I/O — converts `(TOC entries, locator, total UTF-16
length)` into a `ChapterBounds?`:

```swift
enum SummaryScopeResolver {
    /// Returns the chapter span containing `locator`. The span for an offset
    /// BEFORE the first TOC entry is `0 ..< firstEntryOffset` (the book's
    /// preamble — front matter before chapter 1), mirroring how
    /// TOCChapterProgress treats a pre-first-entry offset as chapter 0.
    /// Returns nil only when no usable chapter offsets exist (empty TOC, or
    /// every entry's locator lacks charOffsetUTF16).
    static func chapterBounds(
        for locator: Locator,
        tocEntries: [TOCEntry],
        totalTextLengthUTF16: Int
    ) -> ChapterBounds?
}
```

Round-1 finding [4] resolution: the plan v1 said "preamble → `nil`", which
contradicted the "mirrors `TOCChapterProgress`" claim — `TOCChapterProgress.progress`
(`TOCChapterProgress.swift:47`) treats an offset before the first entry as
*virtual chapter 0*. v2 resolves this **at plan time**: a pre-first-entry
offset maps to `ChapterBounds(0, firstEntryOffset)` — the preamble *is* a
chapter span (front matter). `nil` is returned **only** when no chapter
offsets exist at all (empty TOC, or all entries' locators lack
`charOffsetUTF16`). The "decide in WI-2" hedge in v1's test catalogue is
removed.

Algorithm: extract sorted chapter-start UTF-16 offsets via
`tocEntries.compactMap { $0.locator.charOffsetUTF16 }` (the exact extraction
`TOCChapterProgress.progress` already does); find the chapter whose
`[start, nextStart)` contains the locator's offset; the final chapter ends
at `totalTextLengthUTF16`; a pre-first-entry offset is `[0, firstStart)`.

### 2.5 — `AIContextExtracting` — a protocol seam for the extractor

**New protocol** in `vreader/Services/AI/AIContextExtractor.swift` (~10 LOC).

Round-1 finding [6]: `AIAssistantViewModel` injects a **concrete**
`AIContextExtractor` (`AIAssistantViewModel.swift:54`), so WI-4's "assert
`summarize(scope:)` forwards bounds to the extractor" test has no seam.
Resolution: extract a one-method protocol the view model depends on instead
of the concrete struct (the codebase's standard boundary-protocol move —
`LibraryPersisting`, `BookImporting`, etc.):

```swift
/// The default UTF-16 context budget for scoped extraction. A named
/// constant (not a Swift default argument) because a default argument on a
/// protocol requirement is NOT visible through an existential — see below.
enum AIContextBudget {
    static let defaultMaxUTF16 = 12_000
}

protocol AIContextExtracting: Sendable {
    /// The single required entry point — `maxUTF16` is REQUIRED here (no
    /// default argument), because a protocol-requirement default argument
    /// does not survive through `any AIContextExtracting`.
    func extractContext(
        locator: Locator, fullText: String, format: BookFormat,
        scope: SummaryScope, chapterBounds: ChapterBounds?, maxUTF16: Int
    ) -> String
}

extension AIContextExtracting {
    /// Convenience overload that supplies the default budget. A protocol-
    /// EXTENSION method IS callable through the existential, so callers that
    /// don't care about the budget (`ReaderAICoordinator.currentTextContent`,
    /// the legacy shim) call this 5-arg form; `AIAssistantViewModel`
    /// forwards `AIContextBudget.defaultMaxUTF16` explicitly.
    func extractContext(
        locator: Locator, fullText: String, format: BookFormat,
        scope: SummaryScope, chapterBounds: ChapterBounds?
    ) -> String {
        extractContext(
            locator: locator, fullText: fullText, format: format,
            scope: scope, chapterBounds: chapterBounds,
            maxUTF16: AIContextBudget.defaultMaxUTF16
        )
    }
}
```

Round-2 finding resolution: a Swift **default argument on a protocol
requirement is not visible through an existential** — once
`AIAssistantViewModel.contextExtractor` is `any AIContextExtracting`, a call
that omits `maxUTF16` would not compile. v2 therefore (a) makes `maxUTF16`
**required** on the protocol requirement, (b) adds a **protocol-extension
overload** (the 5-arg form above) that supplies `AIContextBudget.defaultMaxUTF16`
— extension methods *are* dispatched through the existential — and (c) has
`AIAssistantViewModel.performAction` pass `AIContextBudget.defaultMaxUTF16`
**explicitly** as the `maxUTF16` argument (§2.6). The concrete
`AIContextExtractor` keeps a Swift default argument too (for its own direct
callers and tests) — harmless, just unused through the protocol. So every
call site is compile-clean: protocol callers either use the 5-arg extension
overload or pass the constant explicitly; concrete-type callers may use the
struct's default argument.

`AIContextExtractor` conforms (it already has the 6-arg method from §2.3).
`AIAssistantViewModel`'s `contextExtractor` property changes type from
`AIContextExtractor` to `any AIContextExtracting` (defaulted to
`AIContextExtractor()` in the init, so production construction is
unchanged). The protocol is `Sendable`, so `any AIContextExtracting` is
`Sendable` and a `@MainActor` `AIAssistantViewModel` can hold it cleanly.
WI-4 tests inject a recording conformer to assert the `scope` +
`chapterBounds` + `fullText` passed through. (Existing
`AIAssistantViewModelTests` stub `AIService` / provider, not the extractor
— untouched; the new seam is additive.)

### 2.6 — `AIAssistantViewModel` — carry the scope + full text

**Modified file** `vreader/ViewModels/AIAssistantViewModel.swift`.

- `summarize(...)` gains `fullText:`, `scope:`, `chapterBounds:` params.
  `scope`/`chapterBounds` are defaulted; `fullText` is **not** defaulted for
  `summarize` (the Summarize call site must pass the full text explicitly —
  defaulting it would re-introduce the round-1 snippet bug). The
  `explain`/`translate`/`vocabulary`/`askQuestion` siblings keep their
  existing `textContent` param and call `performAction` with `scope:.section`:

  ```swift
  func summarize(
      locator: Locator,
      fullText: String,
      format: BookFormat,
      scope: SummaryScope = .section,
      chapterBounds: ChapterBounds? = nil
  ) async
  ```

- `performAction(...)` already calls the extractor. It gains `scope` +
  `chapterBounds` params and forwards them, plus the `fullText` it now
  receives, to `extractContext`. Because `contextExtractor` is now
  `any AIContextExtracting`, `performAction` calls the **6-arg** requirement
  and passes `AIContextBudget.defaultMaxUTF16` **explicitly** for `maxUTF16`
  (a protocol-requirement default argument is not visible through the
  existential — §2.5). The non-summarize callers pass their existing
  `textContent` as `fullText` with `scope:.section` — for `.section` the
  extractor's behavior is byte-identical whether the input is a snippet or
  full text (it re-extracts the same window), so those paths are unaffected.
  (`explain`/`translate`/etc. are selection-driven and out of #69's scope;
  their `.section` behavior is preserved.)
- New observable: `private(set) var selectedScope: SummaryScope = .section`,
  mutated only via a new `func setScope(_ scope: SummaryScope)` (codebase
  convention — every `AIAssistantViewModel` state change is a method).

### 2.7 — `AISummaryTabView` — render + wire the chip strip; take full text

**Modified file** `vreader/Views/Reader/AISummaryTabView.swift`.

- New input: `fullTextContent: String` — the full flattened book text,
  distinct from the existing `textContent`. (v2 keeps `textContent` only if
  the file still needs the section snippet for anything; if not, `textContent`
  is replaced by `fullTextContent`. WI-5 confirms — current reads show
  `AISummaryTabView` uses `textContent` *only* in `runSummarize`, so it is
  cleanly replaceable.)
- Add a `scopeChipStrip` subview: an `HStack` of three pill buttons over
  `SummaryScope.allCases`, styled to the design (active chip
  `theme.accentColor` fill + white text; inactive chip the neutral
  `chipFillColor` wash already defined in this file). Renders **above** the
  state body so it shows in every state — matching the design.
- Tapping a chip calls `viewModel.setScope(_:)`. Changing scope does NOT
  auto-re-summarize (§6 R-5) — it updates selection; the user taps
  Regenerate / Summarize to run the new scope.
- `runSummarize()` passes `viewModel.selectedScope`, `fullTextContent`, and
  the resolved `chapterBounds` (see §2.8) into `viewModel.summarize(...)`.
- New accessibility identifiers: `aiSummaryScopeChip.section`,
  `aiSummaryScopeChip.chapter`, `aiSummaryScopeChip.bookSoFar`.

### 2.8 — `AIReaderPanel` + `ReaderContainerView+Sheets.swift` — thread full text + bounds

`AISummaryTabView` needs the full text + `ChapterBounds`. Both already
exist in the reader: `ReaderAICoordinator.loadedTextContent` (full text) and
`ReaderContainerView`'s `@State tocEntries` (the TOC).

**Modified file** `vreader/Views/Reader/AIReaderPanel.swift`:

- `AIReaderPanel` gains two params: `fullTextContent: String` and
  `chapterBounds: ChapterBounds?`. Both are forwarded into `AISummaryTabView`.
  The Chat/Translate tabs still receive the existing section `textContent` —
  scope is Summarize-only.

**Modified file** `vreader/Views/Reader/ReaderContainerView+Sheets.swift`
(`aiSheet`):

- Pass `fullTextContent: ai.loadedTextContent ?? ""` into `AIReaderPanel`
  (the un-extracted full text — round-1 finding [1] fix).
- Compute `chapterBounds` from the **existing** `tocEntries` state:
  `SummaryScopeResolver.chapterBounds(for: resolvedLocator, tocEntries: tocEntries, totalTextLengthUTF16: (ai.loadedTextContent ?? "").utf16.count)`.
  Call `ensureTOCReady()` is already invoked by the reader; `aiSheet` reads
  whatever `tocEntries` holds. For non-TXT formats `tocEntries` may be
  empty or non-char-offset-anchored → `chapterBounds` returns `nil` → Chapter
  degrades to Section (§2.0 fact 2, §6 R-2).
- **Decision (§6 R-4)**: `chapterBounds` is snapshotted at sheet-present
  time from the locator captured then. The AI sheet is modal — the reading
  position cannot move while it is open — so a snapshot is correct.

**No change to `ReaderAICoordinator`'s TOC story** — v2 does NOT add
`tocEntries` / `loadTOCIfNeeded` / `chapterBounds(for:)` to the coordinator
(round-1 finding [3]). The coordinator keeps owning `loadedTextContent`
only; the TOC stays owned by `ReaderContainerView`.

### 2.9 — Files OUT of scope

- `AIChatView.swift`, `TranslationPanel.swift`, `AIChatViewModel.swift`,
  `AITranslationViewModel.swift` — Chat/Translate tabs untouched; scope is
  Summarize-only.
- `AIService.swift`, `AnthropicProvider*.swift`, `AIRequest`/`AIResponse`
  in `AITypes.swift` — request contract unchanged. A scoped summary is the
  same `AIRequest` with `actionType == .summarize`; only `contextText`
  differs. **No new `AIActionType` case.**
- `AIResponseCache.swift` — `AIRequest.cacheKey` already hashes `contextText`
  (`ctxHash` — verified `AITypes.swift:45`), so Section/Chapter/Book-so-far
  summaries of the same position naturally cache-separate. No cache change.
- `TOCBuilder.swift`, `TOCProvider.swift`, `ReaderTOCFactory`,
  `TXTChapterIndex*` — #69 reuses the existing TOC; adds no TOC-extraction
  code.
- `ReaderAICoordinator`'s TOC ownership — explicitly NOT added (§2.8).
- `MDReaderViewModel`, `MDDocumentInfo`, the MD rendered-text pipeline —
  #69 does **not** attempt to reconcile MD's raw-source-vs-rendered-text
  coordinate split; MD Chapter/Book-so-far degrades to Section (§2.0 fact 2).
  Fixing MD's coordinate space is a separate, larger change (§9).
- The design's **Suggested questions** list + **Save** chip in `SummaryView`
  — already carved OUT by feature #65 §2.2. Not in #69.
- AZW3/MOBI Foliate-js — no JS/CSS change; AZW3 uses the Section degrade.

## 3. Prior art / project precedent / rejected alternatives

**Project precedent followed:**

- `AISummaryTabView`'s pure `static section(for:)` + `SummarySection` enum
  (re-skin regressions pinned without a render pass — the
  `SearchView.contentState` precedent). #69's `SummaryScope` follows the
  same pure-enum-drives-the-view shape.
- `AIContextExtractor` is a `Sendable` struct with format-branched private
  helpers; #69 adds two more private helpers in the same style.
- `TOCChapterProgress` is the existing, tested precedent for "derive a
  chapter from `tocEntries` + a char offset"; `SummaryScopeResolver` is the
  same computation returning a span (`ChapterBounds`) instead of a fraction.
  Considered extending `TOCChapterProgress` — rejected: it returns a
  *progress fraction*, conflating the two muddies a tested type.
- **Protocol at the boundary** (`AIContextExtracting`) so the view model
  mocks the seam — `LibraryPersisting` / `BookImporting` precedent
  (`00-engineering-principles.md`).
- Per-format degradation rather than a hard block is the project's
  established pattern for partial format support (architecture doc records
  AZW3 highlight restore as a no-op placeholder while other formats work).
  Chapter scope degrading to Section on MD/EPUB/PDF/AZW3 is the same
  honest-partial pattern.

**Industry prior art:**

- Apple Books / Kindle do not expose summary-scope chips, so there is no
  direct UI precedent — the committed design IS the spec. The token-budget
  concern for whole-book context is the standard LLM-context problem; the
  recency-biased prefix truncation (§2.3 `.bookSoFar`) is the conventional
  cheap solution when a full map-reduce summarizer is out of scope.

**Rejected alternatives:**

1. **Add `AIActionType.summarizeChapter` / `.summarizeBook` cases** —
   rejected. The action taxonomy is *what operation*; scope is *how much
   input* — orthogonal. New action cases would fork `AIService` prompt
   handling for no benefit; the prompt is identical, only `contextText`
   changes.
2. **Map-reduce summarization for Book-so-far** — rejected for v1. It is the
   correct long-term answer for very long books but is a multi-request
   orchestration feature (progress UI, partial-failure handling, cost
   model). v1 ships the token-capped recency prefix; map-reduce deferred (§9).
3. **Auto-re-summarize on every chip tap** — rejected (§6 R-5). Burns tokens
   on accidental taps; races the in-flight guard.
4. **Compute `ChapterBounds` lazily inside `AISummaryTabView` per
   Regenerate** — rejected (§6 R-4). Needs the live locator threaded into a
   leaf; a snapshot at modal-present time is correct.
5. **Real Chapter/Book-so-far bounds for MD in v1** — rejected (round-1
   finding [2]). MD's locator is in rendered-text space while its loaded
   text + TOC are in raw-source space; reconciling them is a separate
   change. MD degrades to Section.
6. **Block Chapter scope entirely on non-TXT formats** (hide / disable the
   chip) — flagged as the open Gate-2 question (§6 R-2). Disabling needs a
   design state the bundle does not show (rule 51) → *degrade to Section* is
   the rule-compliant default; all three chips stay tappable.

## 4. Work-item sequencing

Five WIs. WI-1..WI-3 foundational (pure types + extractor logic, no
user-observable behavior, no device verification). WI-4..WI-5 behavioral.

| WI | Tier | Scope | Est. PR size |
|---|---|---|---|
| **WI-1** | Foundational | `SummaryScope` enum + `ChapterBounds` struct (`vreader/Services/AI/`). Pure value types, `Sendable`/`Equatable`/`CaseIterable`. + Swift Testing: `displayName`, `allCases` order `[.section,.chapter,.bookSoFar]`, `Equatable`, raw-value round-trip. | 2 new files + 1 test file, ~120 LOC |
| **WI-2** | Foundational | `SummaryScopeResolver.chapterBounds(...)` — pure TOC→bounds resolver. + Swift Testing: locator in ch.1 / mid-book / final chapter (end == total) / **pre-first-entry → `[0, firstStart)`** / empty-TOC → `nil` / single-chapter / entries with nil `charOffsetUTF16` → `nil` / offset exactly on a boundary / CJK surrogate-pair offsets. | 1 new file + 1 test file, ~150 LOC |
| **WI-3** | Foundational | `AIContextExtracting` protocol + `AIContextExtractor` scoped `extractContext(...:scope:chapterBounds:maxUTF16:)` + `extractChapter`/`extractBookSoFar` UTF-16-safe helpers; legacy entry point becomes a `.section` shim. + tests: `.section` new-path vs old-path byte-identical; chapter slice; chapter over-`maxUTF16` centered fallback; chapter `nil`-bounds degrade; bookSoFar short prefix; bookSoFar over-budget last-N (UTF-16-unit) truncation; empty `fullText` → `""`; locator offset 0; locator offset past `utf16.count` (clamp); CJK / surrogate-pair text (no split pair); zero-length chapter. | ~1 file modified + 1 test file, ~230 LOC |
| **WI-4** | Behavioral | `AIAssistantViewModel` — `contextExtractor` typed to `any AIContextExtracting`; `fullText`/`scope`/`chapterBounds` params on `summarize` + `performAction`; `selectedScope` observable + `setScope`. + ViewModel tests with a recording `AIContextExtracting` conformer: `setScope` updates state; `summarize(scope:.chapter)` forwards `scope`+`chapterBounds`+`fullText`; default `.section` path unchanged; the `explain`/`vocabulary` paths unaffected (regression pin). | ~1 file modified + 1 test file, ~160 LOC |
| **WI-5** | Behavioral (final) | `AISummaryTabView` chip strip + `fullTextContent` input + wiring; `AIReaderPanel` + `ReaderContainerView+Sheets.swift` thread `fullTextContent` (from `loadedTextContent`) + `chapterBounds` (from the existing `tocEntries`). + view-logic tests (chip-strip selection state, `runSummarize` passes `selectedScope`+`fullTextContent`, scope change does NOT auto-fire, in-flight guard holds) + the XCUITest/DebugBridge acceptance pass. Flips the row to DONE. | ~3 files modified + 1 test file, ~210 LOC |

Linear dependency: WI-3 needs WI-1; WI-2 needs WI-1; WI-4 needs WI-1+WI-3;
WI-5 needs WI-1..WI-4. No intra-feature parallelism. (Round-1 finding [+]:
the v1 WI-5 was overloaded with "full-text plumbing + TOC ownership". v2
removes the TOC-ownership work entirely — `tocEntries` already exists — and
the full-text plumbing is a small, mechanical `aiSheet` change; WI-5 is
back to a normal final-WI size.)

## 5. Test catalogue

Concrete files (mirror the source tree per `50-codebase-conventions.md` §8):

- `vreaderTests/Services/AI/SummaryScopeTests.swift` — `displayName` strings
  match the design; `allCases == [.section, .chapter, .bookSoFar]`;
  `Equatable`; raw-value round-trip.
- `vreaderTests/Services/AI/ChapterBoundsTests.swift` — value-type equality;
  constructed bounds preserve `start`/`end`.
- `vreaderTests/Services/AI/SummaryScopeResolverTests.swift` — locator in
  chapter 1; mid-book; final chapter (`end == totalTextLengthUTF16`);
  **pre-first-entry offset → `ChapterBounds(0, firstStart)`** (not `nil`);
  **empty TOC → `nil`**; single-chapter book; TOC entries whose locators
  have `charOffsetUTF16 == nil` (EPUB-shaped) → `nil`; offset exactly on a
  chapter boundary; **CJK text** (UTF-16 offsets where surrogate pairs make
  UTF-16 count ≠ char count).
- `vreaderTests/Services/AI/AIContextExtractorScopedTests.swift` —
  `.section` new-path vs old-path byte-identical (same locator, same text);
  `.chapter` slices to bounds; `.chapter` over-`maxUTF16` → centered UTF-16
  window within the chapter; `.chapter` with `chapterBounds == nil` →
  identical to `.section`; `.bookSoFar` short prefix → `[0..<offset]`;
  `.bookSoFar` over-budget → last `maxUTF16` UTF-16 units; **empty `fullText`
  → `""`**; locator offset `0`; locator offset past `utf16.count` (clamp);
  **CJK / surrogate-pair** text — assert no split surrogate at either slice
  boundary; zero-length chapter (`start == end` → `""`).
- `vreaderTests/ViewModels/AIAssistantViewModelScopeTests.swift` — a
  recording `AIContextExtracting` conformer: `setScope` updates
  `selectedScope`; `summarize(scope:)` forwards `scope` + `chapterBounds` +
  `fullText` to the extractor; `summarize` `.section` default reproduces
  today's behavior; rapid scope changes during `.loading` don't corrupt
  state; the `explain`/`vocabulary` paths unaffected.
- `vreaderTests/Views/Reader/AISummaryTabViewScopeTests.swift` — chip-strip
  selection mirrors `viewModel.selectedScope`; `runSummarize` reads
  `selectedScope` + passes `fullTextContent`; a bare `setScope` does NOT
  transition to `.loading` (no auto-fire); the in-flight guard holds (scope
  change + Regenerate while `.loading` is a no-op).

Audit-driven additions filled after Gate 2 round 2 if any.

## 6. Risks + mitigations

| ID | Risk | Mitigation |
|---|---|---|
| R-1 | `maxUTF16` as a UTF-16-unit budget is still a proxy for provider *token* limits — CJK ≈ 1 token/char, English ≈ 0.25, so 12 000 UTF-16 units is ~3 000 tokens (English) but ~12 000 (CJK), which can exceed a small provider context. | Conservative default (12 000). The extractor caps input; the provider still returns a clean `rateLimited`/`providerError` if the model rejects it — `AIAssistantViewModel` maps those to `.error`. The budget is now an *explicitly named UTF-16 unit* (round-1 finding [5] fix), removing the char-vs-UTF-16 ambiguity. A true token estimator is deferred (§9). |
| R-2 | Chapter scope has real bounds only for TXT — MD/EPUB/PDF/AZW3 lack char-offset-anchored TOC entries (and MD's locator is in a different coordinate space). | Gate-1/round-1 default: **degrade to Section** for all non-TXT formats — the chip is still tappable, just summarizes the section window. **Open Gate-2 question**: degrade silently, or disable the Chapter chip on non-TXT? Disabling needs an undesigned state (rule 51) → degrade is the rule-compliant default. |
| R-3 | "Book so far" for a long book cannot fit the whole prefix in one request. | v1 ships a recency-biased last-`maxUTF16`-units truncation (single request, bounded cost). Map-reduce deferred (§9). The label "Book so far" is honest — it summarizes the book up to the position, within budget. |
| R-4 | The reading position could change between sheet-present and a Regenerate tap, making the snapshot `chapterBounds` stale. | The AI sheet is **modal** (`.sheet` with `.medium`/`.large` detents) — reader content is not interactable while it is open, so the locator cannot move. Snapshot at present time is correct. §2.8. |
| R-5 | Auto-re-summarizing on every chip tap burns tokens / races the in-flight guard. | Chip tap only updates `selectedScope`; the user explicitly taps Regenerate / Summarize. §2.7. |
| R-6 | A larger `contextText` changes `AIRequest.cacheKey`. | **Correct** — Section vs Chapter summaries of the same locator are different results and must cache separately. `cacheKey` already hashes `contextText`. No cache change; called out so it is not mistaken for a regression. |
| R-7 | The Summarize tab now needs the full text (`loadedTextContent`); if `loadBookTextContent` has not finished, `loadedTextContent` is `nil`. | `aiSheet` passes `loadedTextContent ?? ""`. With `""`, `AIContextExtractor` returns `""`, and `AIAssistantViewModel.performAction` already maps an empty context to `.error(contextExtractionFailed)` — a clean, existing error path, not a crash. `loadBookTextContent` is kicked off when the reader sets up the AI coordinator, so it is almost always ready. No undesigned spinner (rule 51). |
| R-8 | `tocEntries` may be empty if `ensureTOCReady()` has not finished when the AI sheet opens. | `chapterBounds` returns `nil` → Chapter degrades to Section — the same safe degrade as a non-TXT format. Transient and self-correcting; the TOC build is fast for TXT. |

## 7. Backward compat

- **No schema change.** `SummaryScope`/`ChapterBounds` are in-memory value
  types; #69 persists nothing. (Per-book *remembered scope* is NOT in v1 —
  every sheet open defaults to `.section`; persisting it would touch
  `PerBookSettings`, deferred to §9.)
- **No request-contract change.** A scoped summary is the same `AIRequest`
  shape; older response-cache entries remain valid (they key on
  `contextText`, which is what changes).
- **Existing callers compile + behave unchanged** — the new extractor entry
  point and the new `summarize` `scope`/`chapterBounds` params are defaulted;
  `explain`/`translate`/`vocabulary`/`askQuestion` pass `scope:.section` and
  keep byte-identical behavior. `contextExtractor` retyped to `any
  AIContextExtracting` with a defaulted `AIContextExtractor()` — production
  construction is unchanged.
- **The legacy `extractContext(locator:textContent:format:)`** stays as a
  `.section`-delegating shim, so `ReaderAICoordinator.currentTextContent`
  (which still calls it for the Chat tab's section context) is unchanged.
- **No older-client / older-backup concern** — reader-session-local UI +
  context shaping.

## 8. Design status (rule 51)

**Designed — Gate 3 is NOT design-gated.** The scope chip strip is depicted
in the committed bundle:
`dev-docs/designs/vreader-fidelity-v1/project/vreader-panels.jsx`,
`SummaryView` (~512-573) renders the three-chip pill row
(`['Section', 'Chapter', 'Book so far'].map(...)`) with the active chip
filled `t.accent`. The summary card, idle/loading/error states, and
Share/Regenerate footer are already shipped (feature #65 WI-1). #69 adds
only the chip strip, which the design shows by name and by visual content.
No undesigned surface — no `needs-design` issue required.

## 9. Known limitations / deferred (accepted at Gate 1, re-confirmed round 1)

- **No map-reduce summarization** — "Book so far" on a very long book
  summarizes the last `maxUTF16` units before the locator, not the whole
  prefix. A chunked map-reduce summarizer is a separate future feature.
- **No real token counting** — `maxUTF16` is a UTF-16-unit proxy. A
  provider-aware token estimator is deferred.
- **Chapter / Book-so-far real bounds are TXT-only** — MD/EPUB/PDF/AZW3
  degrade to Section. For MD specifically, the blocker is the raw-source vs
  rendered-text coordinate-space split (`loadBookTextContent` loads raw `.md`;
  the MD locator carries `renderedText` offsets). Reconciling MD's AI/TOC
  coordinate space (e.g. routing the MD AI path through
  `MDDocumentInfo.renderedText`) is a separate follow-up. Char-offset-
  anchoring EPUB/PDF TOC entries is a larger cross-cutting change, also out
  of #69's scope.
- **Scope is not remembered per book** — every AI-sheet open starts at
  `.section`. Persisting last-used scope is a small `PerBookSettings`
  follow-up, deferred to keep #69 schema-free.

## 10. Revision history

- **v1** (2026-05-19, feature-cron) — initial Gate-1 draft.
- **v2** (2026-05-19, feature-cron) — revised after Gate-2 round-1 Codex
  audit (thread `019e3e09`). Pivots: extract from `loadedTextContent` (full
  text) not `currentTextContent` (a pre-extracted snippet); scope real
  Chapter/Book-so-far to TXT only (MD's locator/TOC coordinate-space split);
  reuse `ReaderContainerView`'s existing `tocEntries` instead of adding a
  TOC owner to `ReaderAICoordinator`; preamble → `ChapterBounds(0,
  firstStart)` not `nil`; explicit `maxUTF16` budget unit; `AIContextExtracting`
  protocol seam for the WI-4 ViewModel test. See §11.
- **v3** (2026-05-19, feature-cron) — revised after Gate-2 round-2 Codex
  audit (same thread `019e3e09`). Round-2 left one Medium: a protocol-
  requirement default argument is not visible through `any
  AIContextExtracting`, so `maxUTF16` had no defined source. v3 §2.5 adds a
  named `AIContextBudget.defaultMaxUTF16` constant + a protocol-extension
  5-arg overload that supplies it, and §2.6 has `performAction` pass the
  constant explicitly. See §11.

## 11. Audit fixes applied — Gate-2 round 1 (Codex thread `019e3e09`)

| # | Severity | Finding | Resolution in v2 |
|---|---|---|---|
| 1 | Critical | Scoped summarize would run on `currentTextContent`, an already-pre-extracted ~2500-char snippet (`ReaderAICoordinator.swift:41`), not the full book — Chapter/Book-so-far would slice a trimmed excerpt while `ChapterBounds` are full-text offsets. | §2.0 fact 1, §2.3, §2.6, §2.7, §2.8: #69 extracts from `loadedTextContent` (the un-extracted full text). New `fullText`/`fullTextContent` input threaded through `summarize` → `AIReaderPanel` → `AISummaryTabView`. `currentTextContent` kept only for the Chat tab. |
| 2 | High | "TXT/MD have real chapter bounds" is false for MD — `loadBookTextContent("md")` loads raw Markdown source, but the live MD locator (`MDReaderViewModel.makeLocator`) carries `renderedText` offsets (`MDDocumentInfo.renderedText`). Raw-source-by-rendered-offset slicing is wrong. | §2.0 fact 2, §2.3, §6 R-2, §9: real Chapter/Book-so-far bounds scoped to **TXT only** for v1; MD joins EPUB/PDF/AZW3 in the Section-degrade set. MD coordinate-space reconciliation is a deferred follow-up. |
| 3 | Medium | The plan invented a TOC owner in `ReaderAICoordinator`; the live TOC is `ReaderContainerView`'s `@State tocEntries` populated by `ensureTOCReady()` → `ReaderTOCFactory.buildTOC`. | §2.0 fact 3, §2.8: v2 reuses the existing `tocEntries`; no `loadTOCIfNeeded`/`chapterBounds(for:)` added to `ReaderAICoordinator`. `aiSheet` reads the existing state. |
| 4 | Medium | "`SummaryScopeResolver` mirrors `TOCChapterProgress`" but the plan said preamble → `nil` while `TOCChapterProgress.progress` (`:47`) treats a pre-first-entry offset as chapter 0; the test catalogue hedged "decide in WI-2". | §2.4: resolved at plan time — a pre-first-entry offset maps to `ChapterBounds(0, firstStart)` (the preamble is a chapter span). `nil` only when no chapter offsets exist at all. Hedge removed from §5. |
| 5 | Medium | `tokenBudget` underspecified and unit-inconsistent — the chapter path is UTF-16, the extractor already mixes UTF-16 (TXT) and `String.count` char math (EPUB/PDF); "last N" truncation was ambiguous. | §2.3: renamed to `maxUTF16`, an explicit UTF-16-unit budget; all scoped slicing uses `utf16View.index` + `samePosition(in:)` so a surrogate pair is never split. Real provider-token estimation deferred (§9). |
| 6 | Low | WI-4 ViewModel tests assume an extractor spy seam; `AIAssistantViewModel` injects a concrete `AIContextExtractor` (`:54`) and existing tests stub `AIService` instead. | §2.5: new `AIContextExtracting` protocol; `contextExtractor` retyped to `any AIContextExtracting` (defaulted to `AIContextExtractor()`). WI-4 injects a recording conformer. Additive — existing `AIAssistantViewModelTests` untouched. |
| + | (cohesion) | WI-5 overloaded with full-text plumbing + TOC ownership. | §4: TOC-ownership work removed entirely (reuse existing `tocEntries`); full-text plumbing is a small mechanical `aiSheet` change. WI-5 back to normal final-WI size. |

**Gate-2 round 2** (Codex thread `019e3e09`) — verified all six round-1
fixes present and technically correct against the codebase; left one new
Medium:

| # | Severity | Finding | Resolution in v3 |
|---|---|---|---|
| 7 | Medium | The `AIContextExtracting` seam is present, but a protocol-requirement default argument is NOT visible through `any AIContextExtracting` — once `contextExtractor` is the existential, a call omitting `maxUTF16` would not compile, and the plan never said where `maxUTF16` comes from. | §2.5: added `AIContextBudget.defaultMaxUTF16` named constant + a protocol-EXTENSION 5-arg overload that supplies it (extension methods dispatch through the existential). §2.6: `performAction` passes `AIContextBudget.defaultMaxUTF16` explicitly. Every call site is now compile-clean. |

**Gate-2 round 3** (Codex thread `019e3e09`) — re-checked the v3 §2.5/§2.6
fix: confirmed a protocol-extension method IS callable through an `any
AIContextExtracting` existential, so the 5-arg convenience overload resolves
cleanly; confirmed all three call sites (`AIAssistantViewModel.performAction`,
the legacy 3-arg shim, `ReaderAICoordinator.currentTextContent`) are
compile-clean; no new Critical/High/Medium issue. **Verdict: CLEAN.**

**Gate-2 outcome: CLEAN after 3 rounds.** Zero open Critical/High/Medium
findings. Feature #69 row → `PLANNED`.
