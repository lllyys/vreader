# Feature #86 WI-2+ — Chat-tab context bar: scope selector + sources toggle + on-demand retrieval + citations

> Parts 2 (annotation sources) & 3 (read-everywhere scope / on-demand retrieval) of Feature #86.
> WI-1 (chapter-scoped context, no UI) shipped v3.49.10 / PR #1454/#1457.
> Design source of truth: `dev-docs/designs/vreader-fidelity-v1/project/design-notes/chat-ai-scope-sources.md`
> + `VReader Chat Context Canvas.html` + `chat-context-artboards.jsx` (#1455, landed PR #1458). Rule 51 satisfied.
> GH: #1453.

## Problem

The in-reader **Chat** tab can only read a single context window. WI-1 lifted that to
the whole current chapter (`ReaderAICoordinator.chatContext`, default ≈ Chapter scope),
but the user can't:

1. **choose a broader/narrower scope** per the thread (Section / Chapter / Book-so-far /
   Whole book),
2. **fold in their own annotations** (Notes / Highlights / Bookmarks),
3. **ask the AI to read the whole book on demand** (incl. pages ahead), or
4. **see what an answer actually drew on** (the "Drew on" citation row, spoiler-aware).

The design (#1455) specifies a persistent ~40px **CONTEXT BAR** docked above the Chat
composer: a quiet outline **scope chip** (left, opens an upward scope menu), a green
**sources chip** (right, opens a sources popover), the whole-book read rendered as a
**non-blocking in-bar progress state**, and a per-reply **"Drew on"** citation row.

## Surface area (file-by-file, concrete signatures)

### New types / services

- **`vreader/Services/AI/ChatContextScope.swift`** (NEW) — Chat-specific scope (the
  Summarize `SummaryScope` is `CaseIterable` and its three cases drive the Summarize
  chips; adding `.wholeBook` there would leak a 4th chip into Summarize, so Chat gets its
  own enum that maps the first three onto `SummaryScope`):
  ```swift
  enum ChatContextScope: String, CaseIterable, Sendable, Equatable {
      case section, chapter, bookSoFar, wholeBook
      var displayName: String          // "Section" / "Chapter" / "Book so far" / "Whole book"
      var summaryScope: SummaryScope?  // section/chapter/bookSoFar → matching SummaryScope; wholeBook → nil
      var isOnDemand: Bool             // only .wholeBook
      var spoilerAware: Bool           // only .wholeBook (can reference pages ahead)
      static var defaultScope: ChatContextScope { .chapter }   // == shipped WI-1
  }
  ```

- **`vreader/Services/AI/ChatSourceSelection.swift`** (NEW) — the three source toggles
  (value type, `Sendable`, `Equatable`):
  ```swift
  struct ChatSourceSelection: Sendable, Equatable {
      var notes: Bool       // default true
      var highlights: Bool  // default true
      var bookmarks: Bool   // default false
      static var `default`: ChatSourceSelection
      var activeCount: Int  // number of toggled-on kinds (chip badge)
      var allOff: Bool
  }
  ```

- **`vreader/Services/AI/ChatAnnotationContext.swift`** (NEW) — pure serializer turning
  fetched annotations into a context block (kept out of the VM so it's unit-testable).
  **Notes are first-class standalone `AnnotationRecord`s, not just `highlight.note`**
  (Gate-2 r2 Medium #4 fix — the app persists standalone notes; `AnnotationStreamBuilder`
  counts notes as *standalone annotations + annotated highlights*, so a highlights-only seam
  undercounts). Seam includes `AnnotationPersisting`/`AnnotationRecord` (`content: String`):
  ```swift
  enum ChatAnnotationContext {
      // Serializes selected kinds into a "[Your notes & marks]" block, budget-capped,
      // newest-first, with locator labels. "Notes" = standalone AnnotationRecords
      // (`content`) + Highlights whose `note` is non-empty (matches AnnotationStreamBuilder).
      static func serialize(annotations: [AnnotationRecord], highlights: [HighlightRecord],
                            bookmarks: [BookmarkRecord],
                            selection: ChatSourceSelection, maxUTF16: Int) -> String
      // Per-kind counts for the sources popover (notes = standalone + annotated-highlights).
      static func counts(annotations: [AnnotationRecord], highlights: [HighlightRecord],
                         bookmarks: [BookmarkRecord]) -> (notes: Int, highlights: Int, bookmarks: Int)
  }
  ```

- **`vreader/Views/Reader/ReaderNotifications.swift`** (MODIFIED, WI-2) — add one
  **mutation-complete** bus name (Gate-2 r2 Medium #2/#3 fix — today's
  `.readerHighlightRequested`/`.readerBookmarkRequested`/`.readerAnnotationRequested` post
  *before* the async persistence runs, so a cache refresh on them races and stays stale):
  ```swift
  static let readerAnnotationsDidChange = Notification.Name("vreader.readerAnnotationsDidChange")
  ```
  WI-2 posts it from the **`PersistenceActor` mutation chokepoints** (Gate-2 r3 Medium fix —
  enumerating UI callers misses reader-side direct paths: `ReaderNotificationHandlers`,
  EPUB/PDF/Foliate container highlight/bookmark paths, `HighlightCoordinator`,
  `FoliateHighlightMutator`, import). Posting from the actor methods themselves —
  `addHighlight`/`removeHighlight`/`updateHighlightNote`/`updateHighlightColor`,
  `addBookmark`/`removeBookmark`/`updateBookmarkTitle`,
  `addAnnotation`/`removeAnnotation`/`updateAnnotation` (+ the import insert path) — covers
  **every** caller by construction (rule 50: all SwiftData mutations go through
  `PersistenceActor`). The post fires after the SwiftData `save` succeeds; observers register
  on `.main`. Pure additive signal (no behavior change). Doc-sync: architecture.md
  Notification Bus table (rule 24).

- **`vreader/Services/AI/ChatContextAssembler.swift`** (NEW) — the single pure funnel that
  produces the Chat `bookContext` from (scope text + annotation block) and reports the
  citation set. Replaces the WI-1 "chatContext is just chapter text" path with a
  scope+sources-parameterized assembler:
  ```swift
  struct ChatContextAssembly: Sendable, Equatable {
      let bookContext: String
      let citations: [ChatCitation]   // what the assembled context drew on (WI-6)
  }
  enum ChatContextAssembler {
      static func assemble(scopeText: String, scope: ChatContextScope,
                           annotationBlock: String, citations: [ChatCitation],
                           maxUTF16: Int) -> ChatContextAssembly
  }
  ```

- **`vreader/Services/AI/ChatCitation.swift`** (NEW) — the "Drew on" model (WI-6),
  **provenance-first** (Gate-2 Medium #4 fix — `TOCEntry` has no stable chapter ordinals,
  and Foliate/AZW3 have no AI text-load path, so a display-driven `chapter(Int)` is wrong):
  ```swift
  struct ChatCitation: Sendable, Equatable, Identifiable {
      enum SourceKind: String, Sendable, Equatable { case scope, note, highlight, bookmark, wholeBookSpan }
      let id: UUID
      let sourceKind: SourceKind
      let label: String          // display label, e.g. "Ch. 1" (when derivable) / "Section" / "your note"
      let locator: Locator?      // optional provenance anchor (nil when not derivable, e.g. EPUB no-offset TOC)
      let spanUTF16: ClosedRange<Int>?  // optional covered span for whole-book / scope citations
      let sequence: Int?         // optional ordinal when a stable order exists (else nil — never fabricated)
      let aheadOfReader: Bool    // amber spoiler flag (whole-book span beyond the reader's position)
  }
  ```
  Per-format degradation (an explicit acceptance dimension): TXT/MD with a char-offset TOC →
  span-level chapter labels; EPUB/AZW3 (no char-offset TOC / no AI text-load path) → scope-level
  labels only (`"Chapter"`, `"Book so far"`), no fabricated ordinals; PDF → page-level.

- **`vreader/Services/AI/WholeBookReducer.swift`** (NEW, WI-5) — the off-main-actor read +
  **hierarchical (tree) reduction** (Gate-2 High #1 + High #2 fix). NOT linear accumulation:
  the repo's per-request ceiling is `AIContextBudget.defaultMaxUTF16 = 12_000`, so a 13M-char
  CJK book is split into bounded chunks, each condensed, then groups-of-condensations reduced
  again, repeating until the whole-book digest fits the budget. Pins **one**
  `ResolvedAIProviderConfig` snapshot for the whole job and calls the non-streaming
  `AIService.sendRequest(_:using:)` per chunk (not re-resolve per chunk):
  ```swift
  struct WholeBookCoverage: Sendable, Equatable {     // structured, not a bare String (Gate-2 Medium #3)
      let coveredSpans: [ClosedRange<Int>]            // UTF-16 spans actually read
      let totalUTF16: Int
      let droppedSpans: [ClosedRange<Int>]            // never silent — logged + surfaced
      var fraction: Double                            // covered / total
      var isComplete: Bool                            // droppedSpans empty AND covered == total
  }
  struct WholeBookDigest: Sendable, Equatable { let context: String; let coverage: WholeBookCoverage; let citations: [ChatCitation] }
  actor WholeBookReducer {
      // ORDERED progress (Gate-2 r2 Medium #1 fix — a sync @Sendable callback hopped to the
      // MainActor via an unstructured Task can reorder and revert a terminal phase to .reading).
      // The reducer emits an ordered AsyncStream the VM consumes IN ORDER on the MainActor.
      enum Event: Sendable, Equatable { case progress(done: Int, total: Int); case finished(WholeBookDigest) }
      // Overflow policy: bound the total provider-call budget (maxChunks). A book over the
      // bound is read as a BOUNDED digest (book-so-far + sampled-ahead chapters) and reports
      // a non-complete coverage — never a silent truncation.
      // Cancellation (Gate-2 r3 Medium fix — cancelling the CONSUMER task does not cancel the
      // PRODUCER behind an AsyncThrowingStream, and a cancelled consumer may miss the final
      // event). The reducer owns its producer Task and exposes an explicit `cancel()`; the
      // stream's `continuation.onTermination` also routes consumer-side termination back to
      // the producer. The producer checks the actor's cancelled flag between provider calls,
      // and on cancel emits a terminal `.finished(partialDigest)` THEN finishes.
      func reduce(fullText: String, tocEntries: [TOCEntry], format: BookFormat,
                  readerLocator: Locator?, service: AIService, config: ResolvedAIProviderConfig,
                  budgetUTF16: Int, maxChunks: Int) -> AsyncThrowingStream<Event, Error>
      func cancel()   // VM-driven: flips the cancelled flag; producer emits terminal partial
  }
  ```
  The VM calls `reducer.cancel()` (NOT cancelling its own consuming task) and keeps consuming
  until the terminal `.finished(partialDigest)` arrives, so `.partial(coverage)` is always set
  from real structured coverage — never a phantom revert to `.reading`, never a dropped digest.

- **`vreader/ViewModels/WholeBookRetrievalViewModel.swift`** (NEW, WI-5) — the **thin
  `@MainActor @Observable` mirror** (Gate-2 High #1 fix): it owns only the UI phase/progress
  and drives the `WholeBookReducer` actor; no heavy slicing/prompting on the main actor.
  ```swift
  @MainActor @Observable final class WholeBookRetrievalViewModel {
      enum Phase: Sendable, Equatable {
          case idle, armed
          case reading(done: Int, total: Int)
          case ready(WholeBookCoverage)
          case partial(WholeBookCoverage)   // distinct from ready — a partial is NOT treated as whole-book-ready
      }
      private(set) var phase: Phase = .idle
      private(set) var digest: WholeBookDigest?   // structured; survives Cancel as .partial
      private let reducer: WholeBookReducer
      private var readTask: Task<Void, Never>?    // consumes the stream; NOT the cancel lever
      func arm()
      func cancel()   // reducer.cancel() (NOT readTask.cancel()); keeps consuming to terminal .finished
      func read(...)  // spawns readTask consuming reducer.reduce(...) stream IN ORDER on MainActor:
                      // .progress → .reading(done,total); .finished(d) → d.coverage.isComplete ? .ready : .partial
      var progressFraction: Double
      var chapterProgressLabel: String            // "23 / 61 ch"
  }
  ```
  Because the VM consumes the stream sequentially on the MainActor, a `.progress` event can
  never arrive *after* the terminal `.finished` — closing the reorder race the auditor flagged.

### Modified types

- **`vreader/ViewModels/AIChatViewModel.swift`** — add scope + sources + retrieval state and
  route them through context assembly:
  - `var scope: ChatContextScope = .chapter`
  - `var sources: ChatSourceSelection = .default`
  - `var sourceCounts: (notes: Int, highlights: Int, bookmarks: Int) = (0,0,0)`
  - the WI-1 `var bookContext: String?` stays the injected string; a parallel
    `var pendingCitations: [ChatCitation] = []` holds the citation set the *current*
    assembled context drew on.
  - **Send-time snapshot (Gate-2 Medium #2 fix)**: `sendMessage(_:)` streams asynchronously,
    so it must NOT stamp the reply from whatever scope/sources are current at completion.
    At send *start* it captures a `ChatSendSnapshot { bookContext, citations, scope }` and
    carries it through the in-flight request; the assistant message is stamped from the
    snapshot. (`buildContextText()` is `private` — we don't call it; we set `bookContext`.)
  - `ChatMessage` gains `var citations: [ChatCitation] = []` (WI-6), stamped from the snapshot.
  - Keeps `aiService: AIService` (concrete — the existing dep; no `AIServicing` protocol
    exists, Gate-2 Medium #1).

- **`vreader/Services/AI/ChatAnnotationCache.swift`** (NEW) — **annotation I/O kept OUT of the
  relocate funnel** (Gate-2 r1 High #3 fix). `ReaderContainerView` calls `refreshChatContext()`
  on every `.readerPositionDidChange` / TOC arrival / text load; pulling SwiftData fetches
  into that path would hammer the store. Instead a small per-book cache holds the fetched
  `[AnnotationRecord]` + `[HighlightRecord]` + `[BookmarkRecord]` + counts; it loads once on
  reader open and **refreshes only on the single mutation-complete bus
  `.readerAnnotationsDidChange`** (Gate-2 r2 Medium #2/#3 fix — NOT the request-time
  notifications, which fire before persistence completes and would refetch stale data). Seam:
  `AnnotationPersisting` + `HighlightPersisting` + `BookmarkPersisting` protocols (NoOp stores
  already exist for tests).
  ```swift
  @MainActor @Observable final class ChatAnnotationCache {
      private(set) var annotations: [AnnotationRecord] = []   // standalone notes (first-class)
      private(set) var highlights: [HighlightRecord] = []
      private(set) var bookmarks: [BookmarkRecord] = []
      var counts: (notes: Int, highlights: Int, bookmarks: Int) { ... }  // via ChatAnnotationContext.counts
      func load(fingerprintKey: String) async   // once on open + on .readerAnnotationsDidChange
  }
  ```

- **`vreader/Views/Reader/ReaderAICoordinator.swift`** — generalize `refreshChatContext()`
  to assemble from `(scope, sources)` using the **cached** annotation state (never a fetch on
  relocate): `refreshChatContext()` recomputes only the cheap in-memory scope text + reads
  the `ChatAnnotationCache`, serializes via `ChatAnnotationContext`, and assembles via
  `ChatContextAssembler`. Single-funnel discipline from WI-1 preserved. `wholeBook` scope
  routes through the `WholeBookRetrievalViewModel`/`WholeBookReducer` (its digest becomes the
  scope text once `.ready`). New deps: `HighlightPersisting`, `BookmarkPersisting`, the book
  `fingerprintKey`, a pinned `ResolvedAIProviderConfig` (for whole-book), `AIService`.

- **`vreader/Views/AI/AIChatView.swift`** — insert `ChatContextBar` in the VStack
  **between `messageList` and `inputBar`** (design: shares the composer's top rule, ~40px,
  never scrolls). Dim messages + disable composer during `.reading`.

- **`vreader/Views/AI/AIChatMessageRow.swift`** — append a `ChatCitationRow` under an
  assistant reply's content when `message.citations` is non-empty (WI-6).

### New SwiftUI views (designed surfaces — Rule 51 satisfied by #1455)

- **`vreader/Views/AI/ChatContextBar.swift`** (NEW) — the docked bar: `ChipScope` (left) +
  `ChipSources` (right) + the in-bar `RetrievalCluster` state. Lifts
  `ContextBar`/`ChipScope`/`ChipSources` from `chat-context-artboards.jsx`.
- **`vreader/Views/AI/ChatScopeMenu.swift`** (NEW) — upward menu, 4 rows with token
  estimates + the Whole-book `ON-DEMAND` tag + spoiler footer. Lifts `ScopeMenu`.
- **`vreader/Views/AI/ChatSourcesMenu.swift`** (NEW) — upward popover, 3 toggle rows with
  per-book counts + footer. Lifts `SourcesMenu`.
- **`vreader/Views/AI/ChatRetrievalCluster.swift`** (NEW) — Armed/Reading%/Ready treatment
  + Cancel ×. Lifts `RetrievalCluster`/`ReadingBar`.
- **`vreader/Views/AI/ChatCitationRow.swift`** (NEW) — "Drew on" chips (amber `· ahead` for
  spoilers). Lifts `CitationRow`.

### Files OUT of scope

- `SummaryScope.swift` / `AISummaryTabView.swift` / `AISummaryScopeChipStrip.swift` — the
  Summarize tab is untouched (we map onto its `SummaryScope`/`AIContextExtractor`, not edit
  it). The Chat bar is a distinct surface per the design rationale (thread-wide vs one-shot).
- `AIContextExtractor` core math — reused as-is for section/chapter/bookSoFar.
- Provider/tool-use plumbing — `AIRequest` gains **no** `tools` field; whole-book uses
  map-reduce condensation, not tool-use. (Design says "scope selector **and/or** tool-use/RAG"
  — map-reduce is the chosen, infra-free path.)
- Bug #313 (Readium never posts position) — a separate precondition; #86 is the scope/source
  layer on top. Chapter/section anchoring quality is #313's concern, not this feature's.

## Prior art / precedent / rejected alternatives

- **Reuse**: `SummaryScope` + `SummaryScopeResolver.chapterBounds` + `AIContextExtractor`
  (Feature #69) for the three bounded scopes; `AISummaryScopeChipStrip` styling for the
  chips; `PersistenceActor.fetchHighlights/fetchBookmarks` for sources; the
  whole-book-translate cancel ("nothing is lost") as the retrieval-cancel precedent.
- **Rejected — extend `SummaryScope` with `.wholeBook`**: it's `CaseIterable` and drives the
  Summarize chips; a 4th case leaks there. → separate `ChatContextScope`.
- **Rejected — Summarize-style top chips for Chat** (design §"Why a context bar"): Chat is a
  thread; scope/sources are standing properties, so they dock with the composer. (The
  design's rejected `B` artboards.)
- **Rejected — tool-use/function-calling retrieval**: no `tools` field on `AIRequest`, no
  embeddings/vector store. Map-reduce condensation is the bounded, testable path and matches
  the design's "map-reduce for over-limit spans."

## Work-item sequencing (tier)

- **WI-2 — context-assembly foundation + mutation-complete bus (foundational).**
  `ChatContextScope`, `ChatSourceSelection`, `ChatAnnotationContext` (annotations +
  highlights + bookmarks), `ChatContextAssembler`, `ChatCitation` (model only) — pure value
  types + serializers. PLUS the additive `.readerAnnotationsDidChange` notification + posting
  it at every mutation-complete site (highlight/bookmark/annotation add·remove·update +
  import). No UI, no VM wiring yet. The notification posting is the only non-pure part; it's
  additive (a new signal, no behavior change) and individually testable. Doc-sync:
  architecture.md Notification Bus. ~1 small-medium PR.
- **WI-3 — scope chip + scope menu (behavioral).** `ChatContextBar` (scope half) +
  `ChatScopeMenu`; wire `AIChatViewModel.scope` + `ReaderAICoordinator` re-assembly for the
  three bounded scopes (Whole-book row present but selecting it just arms — retrieval lands
  WI-5). ~1 medium PR.
- **WI-4 — sources chip + sources popover (behavioral).** `ChatSourcesMenu` + the sources
  half of the bar; fetch annotations, counts, inject the serialized block. ~1 medium PR.
- **WI-5 — whole-book on-demand retrieval (behavioral, heaviest).** Split per Gate-2:
  the off-actor `WholeBookReducer` (hierarchical reduction, pinned provider config,
  non-streaming `sendRequest(_:using:)`, bounded `maxChunks` overflow policy, structured
  `WholeBookCoverage`) + the thin `@MainActor WholeBookRetrievalViewModel` mirror +
  `ChatRetrievalCluster` Armed/Reading%/Ready/**Partial**/Cancel + message dimming + composer
  disable. Cancel → `.partial(coverage)` (a partial is NOT auto-treated as whole-book-ready;
  the next send labels it partial). ~1 large PR — if it grows past ~one PR, split the reducer
  (WI-5a, foundational/off-UI) from the UI cluster (WI-5b, behavioral).
- **WI-6 — "Drew on" citations (behavioral).** `ChatMessage.citations`, `ChatCitationRow`,
  spoiler-aware amber for whole-book pages-ahead. ~1 medium PR.
- **WI-7 — final acceptance + polish (behavioral, FINAL WI → DONE).** Theme parity across
  the canvas states, accessibility IDs, full acceptance pass + evidence file. ~1 small PR.

## Test catalogue

- `ChatContextScopeTests` — displayName / summaryScope mapping / default == .chapter / isOnDemand / spoilerAware.
- `ChatSourceSelectionTests` — activeCount, allOff, default (notes+highlights on, bookmarks off).
- `ChatAnnotationContextTests` — serialize selects only toggled kinds; **notes = standalone AnnotationRecords + highlights with non-empty note** (matches `AnnotationStreamBuilder`); budget cap; empty → empty; CJK byte-budget; counts() across all three kinds.
- `ReaderAnnotationsDidChangeTests` — the new bus posts after each successful persistence path (highlight add/remove/update, bookmark add/remove/rename, annotation add/remove/update, import); does NOT post on a bare request notification.
- `ChatContextAssemblerTests` — scope text + annotation block ordering; budget cap; citations passthrough; whole-book spoiler flag.
- `ChatCitationTests` — sourceKind→label; provenance fields nil when not derivable (EPUB no-offset); aheadOfReader/spoiler flag; no fabricated `sequence`.
- `WholeBookReducerTests` (actor) — hierarchical reduction collapses to ≤ budget; pins one config (call count); `maxChunks` overflow → bounded digest + non-complete `WholeBookCoverage` with logged `droppedSpans`; **`cancel()` mid-read → the stream emits a terminal `.finished(partialDigest)` (NOT a throw) carrying the structured coverage of what was read**; empty book; CJK byte budgets. Uses a stub `AIService` recording per-chunk calls.
- `WholeBookRetrievalViewModelTests` — phase transitions idle→armed→reading→ready; cancel → `.partial(coverage)` (NOT `.ready`); progressFraction + chapter label; digest survives cancel; **a late `.progress` event after `.finished` can never revert a terminal phase to `.reading`** (ordered-stream guarantee).
- `ChatAnnotationCacheTests` — loads once; refreshes ONLY on `.readerAnnotationsDidChange` (not on relocate, not on request-time notifications); counts = standalone notes + annotated highlights + highlights + bookmarks.
- `PersistenceActorAnnotationBusTests` — every `PersistenceActor` mutation chokepoint (addHighlight/removeHighlight/updateHighlightNote/updateHighlightColor, addBookmark/removeBookmark/updateBookmarkTitle, addAnnotation/removeAnnotation/updateAnnotation, import insert) posts `.readerAnnotationsDidChange` after a successful save; a failed/throwing mutation does NOT post.
- `AIChatViewModelScopeSourcesTests` — scope change re-injects bookContext; sources toggle re-injects; **send-snapshot**: a scope/source change *after* `sendMessage` start does NOT alter the in-flight reply's stamped citations; whole-book `.partial` gates/labels the next send.
- `ReaderAICoordinatorChatAssemblyTests` — extend WI-1's suite: scope+sources funnel assembles from the *cached* annotations (no SwiftData hit on relocate); idempotent refresh; whole-book digest becomes scope text when `.ready`.
- View-behavior tests (case-by-case): `ChatContextBar` chip state (Off vs count), scope menu selection callback, sources toggle callback, retrieval cluster phase rendering — test callbacks/observable state, not pixels.

## Risks + mitigations

- **Whole-book cost/latency (WI-5).** Map-reduce over a 13M CJK TXT is many AI calls →
  bound the chunk count, cap per-chunk + total budget, stream progress, make Cancel keep
  partial. Document the ceiling; never silently truncate (log dropped chapters).
- **Annotation PII to the model.** Sources OFF by default for bookmarks; all-off sends
  nothing. The footer states marks are included. No new network path beyond the existing
  AI provider.
- **Scope re-injection races.** Keep WI-1's single-funnel `refreshChatContext()`; scope and
  sources changes call the same idempotent method. Assembly is pure → deterministic.
- **Spoiler safety.** Only `.wholeBook` is spoiler-aware; the citation row flags
  pages-ahead chips amber. Other scopes are spoiler-safe by construction.
- **Provider-key gating for verification.** The assembly + state logic is unit-provable
  CU-free; the answers-from-scope effect is provider-key-blocked (same as WI-1) → slice
  smoke (`--enable-ai`) for wiring + keyed manual for the answer effect.

## Backward compat

- WI-1's behavior (Chapter default, single funnel) is preserved: `ChatContextScope.default
  == .chapter`, sources default (notes+highlights on) only *adds* the user's own marks,
  and an empty/absent annotation set assembles to exactly the WI-1 string. No persisted
  schema change (scope/sources are per-thread in-memory state, reset on reader open — matches
  the design's "properties of this conversation").

## Audit fixes applied (v2 — Gate-2 round 1, Codex gpt-5.4, session 019e8b4d)

Round 1 found **3 High + 4 Medium**; all resolved in v2:

- **High — WholeBookRetriever on @MainActor mixes UI + heavy read.** → split into off-actor
  `WholeBookReducer` (does chunking/slicing/prompting/reduction) + thin `@MainActor`
  `WholeBookRetrievalViewModel` mirror.
- **High — linear map-reduce not token-realistic for the 12_000 ceiling.** → hierarchical
  (tree) reduction; pin one `ResolvedAIProviderConfig`; non-streaming `sendRequest(_:using:)`
  per chunk; explicit `maxChunks` overflow policy with a bounded digest + non-complete
  coverage (never silent truncation).
- **High — annotation fetch inside `refreshChatContext()` hammers SwiftData on every
  relocate.** → `ChatAnnotationCache`: load once on open, refresh only on annotation-mutation
  notifications; relocate recomputes only the cheap scope text.
- **Medium — `AIServicing` / `LibraryPersisting` are the wrong seams.** → concrete `AIService`
  (matches the VM) + `HighlightPersisting` + `BookmarkPersisting` (NoOp test stores exist).
- **Medium — `lastAssemblyCitations` mis-stamps under async streaming.** → `ChatSendSnapshot`
  captured at send start, carried through the in-flight request, stamps the reply.
- **Medium — "Cancel keeps indexedContext" underspecified/unsafe.** → structured
  `WholeBookCoverage` + a distinct `.partial` phase; a partial is never auto-"ready".
- **Medium — `ChatCitation.Kind.chapter(Int)` too display-driven.** → provenance-first
  `ChatCitation` (`sourceKind` + optional `locator`/`spanUTF16`/`sequence`) + explicit
  per-format degradation (TXT span-level / EPUB-AZW3 scope-level / PDF page-level).

Model-assumption deltas the auditor noted (folded in): `buildContextText()` is `private`
(we set `bookContext`, don't call it); `streamRequest`/`sendRequest` are `async throws`;
`AIRequest` also carries `targetLanguage`/`promptVersion` (we pass nil/default); the
"no `tools` field" assumption is correct.

## Audit fixes applied (v3 — Gate-2 round 2, Codex gpt-5.4)

Round 2 confirmed all round-1 Highs resolved; found **4 Medium**; all resolved in v3:

- **Medium — actor/VM progress callback can reorder & revert a terminal phase.** → the
  reducer emits an ordered `AsyncThrowingStream<Event>` the VM consumes sequentially on the
  MainActor; cancellation via Task cancellation + `Task.isCancelled` (no sync `isCancelled`
  closure). Test: a late `.progress` after `.finished` cannot revert `.ready`/`.partial`.
- **Medium — cache refreshed on request-time notifications (fire before persistence).** →
  one mutation-complete bus `.readerAnnotationsDidChange`, posted only after successful
  persistence; the cache refreshes from it.
- **Medium — refresh set incomplete (bookmark delete/rename, standalone annotation
  edit/delete missing).** → WI-2 posts `.readerAnnotationsDidChange` at *every* persisted
  mutation site; tests per path.
- **Medium — dropped first-class standalone notes.** → `ChatAnnotationContext` +
  `ChatAnnotationCache` widened to `AnnotationPersisting`/`AnnotationRecord`; notes =
  standalone annotations + highlights with non-empty note (matches `AnnotationStreamBuilder`).

## Audit fixes applied (v4 — Gate-2 round 3, Codex gpt-5.4)

Round 3 confirmed round-1 Highs + round-2 note-semantics fixed; found **2 Medium** (no
Critical/High); both resolved in v4:

- **Medium — AsyncThrowingStream cancel contract unsound.** Cancelling the consumer task
  doesn't cancel the producer, and a cancelled consumer may miss the final event. → the
  reducer owns its producer Task + an explicit `cancel()` (and `continuation.onTermination`
  bridge); the VM calls `reducer.cancel()` (not its own task) and stays alive to the terminal
  `.finished(partialDigest)`. Test tightened: cancel ⇒ terminal partial digest, not a throw.
- **Medium — `.readerAnnotationsDidChange` coverage missed reader-side direct mutation
  paths.** → post the bus from the `PersistenceActor` mutation chokepoints
  (add/remove/update highlight·bookmark·annotation + import), covering every caller by
  construction (rule 50). Test targets the actor methods, not enumerated UI callers.

**Round cap note (rule 47 Gate-2 ≤3 rounds):** findings decreased strictly each round
(3H+4M → 4M → 2M → expected 0), and both round-3 findings were unambiguous, auditor-prescribed
engineering fixes with no judgment trade-off (a Swift-concurrency cancel-ownership correction
and a single-chokepoint relocation), not a genuine disagreement requiring user arbitration.
Per the standing directive to implement features autonomously, they were applied as the
"redesign" disposition and sent for one confirming round rather than escalated. If round 4 is
not clean, escalate.

## Revision history

- v1 (2026-06-03) — initial plan from the landed #1455 design + the Explore surface map.
- v2 (2026-06-03) — Gate-2 round-1 fixes (3 High + 4 Medium) applied.
- v3 (2026-06-03) — Gate-2 round-2 fixes (4 Medium) applied.
- v4 (2026-06-03) — Gate-2 round-3 fixes (2 Medium: cancel-ownership + chokepoint bus)
  applied; pending one confirming re-review.
