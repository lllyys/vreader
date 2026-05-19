# Bug #180 — Continuous-Scroll TXT Reader (GH #614, re-scoped)

## 1. Problem

### Symptom

In the VReader iOS TXT reader, Scroll layout on a multi-chapter TXT file does not scroll continuously. The current build (post PR #681 / commit `5f75fde`) renders **one chapter at a time** in a single `UITextView` (`TXTTextViewBridge`), and "advances" chapters by swapping the `UITextView`'s entire text when the user scrolls to the content edge. The user-visible failures:

- Scrolling to the bottom of Chapter 1 does not flow into Chapter 2 — it triggers a discrete swap.
- After the swap, the `UITextView` keeps the *old* `contentOffset.y` (≈ `maxOffset`), so the user sees the **end** of Chapter 2, not its top.
- That stale near-`maxOffset` offset re-satisfies the bottom-boundary predicate on the next scroll-settle, firing `didScrollPastBottomBoundary()` again → `goToNextChapter()` again → a **cascading multi-chapter skip**.
- Net effect: reading is discontinuous, jumps to wrong positions, and cascades.

### The rejected PR #681 design (boundary-detect-then-swap)

PR #681 added, and this plan **rips out**:

- `didScrollPastBottomBoundary()` / `didScrollPastTopBoundary()` on `TXTTextViewBridgeDelegate` (`TXTViewConfig.swift:43-47`, plus the default-impl extension at lines 50-53).
- Boundary detection inside `TXTTextViewBridgeCoordinator.sendScrollPosition` (`TXTTextViewBridgeCoordinator.swift:409-442` — the `boundarySlack` / `maxOffset` block at lines 423-432).
- The `TXTReaderViewModel: TXTTextViewBridgeDelegate` callback bodies `didScrollPastBottomBoundary()` / `didScrollPastTopBoundary()` (`TXTReaderViewModel.swift:649-660`).
- `TXTReaderViewModel.goToNextChapter()` / `goToPreviousChapter()` as the *scroll-mode advance mechanism* (`TXTReaderViewModel.swift:161-162`).
- `isChapterNavInFlight` as a band-aid serializer (`TXTReaderViewModel.swift:125`, used at `:364-368`).
- `TXTScrollBoundaryChapterNavTests.swift` (7 tests pinning the rejected behavior).

The user's binding directive in `docs/bugs.md` Bug #180: *"The discrete chapter-SWAP approach is rejected outright — not patched."* The boundary-detect-then-swap design is the wrong model. The fix stays under bug #180 (not split into a feature).

### What "continuous surface" means here

A single scrollable view whose content is the **entire book's text**, laid out end-to-end with **no gap, no relayout hitch, and no `contentOffset` discontinuity** at any chapter boundary. The user scrolls from the last line of Chapter 1 straight into the first line of Chapter 2 the same way they scroll within a chapter. "Chapter" stops being a render unit and becomes **metadata layered over a continuous offset space**: `currentChapterIdx` is *derived* from the live scroll offset, not a state that drives which text is rendered.

The project already has a whole-document continuous renderer that lazily windows rows for huge books: `TXTChunkedReaderBridge` — a `UITableView` where each row is a 16 KB text chunk. The tracker explicitly directs reuse of that windowing as the continuous surface. This plan routes **chaptered TXT in Scroll layout** through that table, with a chapter-offset index layered on top so chapter awareness (TOC jumps, per-chapter progress, feature #48 highlights) survives.

---

## 2. Surface area

The strategy: **chaptered TXT in Scroll layout renders through the existing `TXTChunkedReaderBridge` `UITableView`** with the whole book split into chunks, and a `TXTChapterOffsetIndex` mapping every chunk-global UTF-16 offset to a chapter. Paged layout and the legacy small-file single-`UITextView` path are unchanged.

### DELETED

- **`vreaderTests/Views/Reader/TXTScrollBoundaryChapterNavTests.swift`** — entire file. Pins the rejected boundary-swap behavior; the behavior is removed so the tests cannot be kept.

### MODIFIED

**`vreader/Views/Reader/TXTViewConfig.swift`**
- Remove `didScrollPastBottomBoundary()` / `didScrollPastTopBoundary()` from the `TXTTextViewBridgeDelegate` protocol (lines 43-47).
- Remove the default-impl `extension TXTTextViewBridgeDelegate` (lines 50-53).
- Final protocol surface: `selectionDidChange(utf16Range:)` and `scrollPositionDidChange(topCharOffsetUTF16:)` only.

**`vreader/Views/Reader/TXTTextViewBridgeCoordinator.swift`**
- In `sendScrollPosition` (lines 409-442), delete the boundary-detection block (lines 423-432: `boundarySlack`, `maxOffset`, the `delegate?.didScrollPastBottomBoundary()` / `…TopBoundary()` calls). The method reverts to its pre-#681 form: guard suppression, compute `topOffset`, call `scrollPositionDidChange`.

**`vreader/ViewModels/TXTReaderViewModel.swift`**
- Delete the `didScrollPastBottomBoundary()` / `didScrollPastTopBoundary()` conformance methods (lines 649-660) and the `#if canImport(UIKit)` extension trims to `scrollPositionDidChange` + `selectionDidChange` only.
- Delete `isChapterNavInFlight` (line 125) and its guard in `navigateToChapter` (lines 364-368). `navigateToChapter` is retained for **TOC / chrome-button** jumps (which under continuous scroll become "scroll the table to chapter N's offset"), but no longer races against scroll-settles, so the serializer is dead weight.
- `goToNextChapter()` / `goToPreviousChapter()` (lines 161-162): retained ONLY for the Contents-toolbar chapter prev/next buttons; remove the doc comment claiming they are the scroll-advance mechanism.
- **New** computed/stored state for the continuous surface:
  - `private(set) var chapterOffsetIndex: TXTChapterOffsetIndex?` — built at open time from `chapterIndex`.
  - `currentChapterIdx` becomes **derived**: a new method `func updateChapterIndexFromOffset(_ globalUTF16: Int)` (called from `updateScrollPosition`) does `chapterOffsetIndex?.chapterContaining(globalUTF16)` and assigns `currentChapterIdx`. Keep the stored property (observers + overlay read it) but it is now write-only-from-offset.
- **New** open path (see below): `openContinuous(url:)` replaces `openChapterBased` for chaptered files in Scroll layout — it builds the whole-book chunk array + the chapter-offset index, instead of loading a single chapter.
- `updateScrollPosition(charOffsetUTF16:)` (lines 494-529): in continuous mode, the incoming offset is **already global** (the table reports document-global offsets via `chunkStartOffsets`). Simplify: `currentOffsetUTF16 = clamped`; `currentChapterLocalUTF16 = clamped - chapter.globalStartUTF16`; derive `currentChapterIdx`. The current chapter-mode branch (lines 500-509) that treats the bridge offset as chapter-local is replaced.
- `makeLocator()` (lines 571-595): in continuous mode, the `txtchapter:idx:local` href is still emitted — derive `idx`/`local` from the global offset via `chapterOffsetIndex`. The href format is unchanged so existing saved positions stay loadable (see §8).

**`vreader/Views/Reader/TXTReaderContainerView.swift`**
- The `body` rendering decision (lines 138-166) gets a new branch: when `viewModel.isContinuousMode` (chaptered TXT in Scroll layout) is true, render the new `continuousChapteredReaderContent(...)` via `TXTChunkedReaderBridge` over the whole-book chunks. The single-chapter `chapterReaderContent` path (lines 144-147) is kept only as a fallback for Paged layout / when continuous build fails.
- Add a `continuousChapteredReaderContent(chunks:offsets:chapterOffsetIndex:)` `@ViewBuilder` mirroring `chunkedReaderContent` but wiring the chapter-offset index for progress + chapter-derivation.
- `.task` (lines 243-276): call `viewModel.openContinuous(url:)` for chaptered TXT in Scroll layout; keep `openChapterBased` for Paged.
- Highlight wiring: in continuous mode, the bridge receives **document-global** highlight ranges directly (`uiState.persistedHighlightRanges`, `uiState.persistedHighlightLookup`) — no chapter-local translation needed because the table's chunk offsets ARE document-global. The chapter-local translation helpers (`chapterLocalHighlightRanges`, `chapterLocalScrollOffset`, `chapterScrubberGlobalOffset`) stay for the Paged single-chapter path.
- The scrubber `onSeek` for continuous mode seeks within the **whole document** (`uiState.scrollToOffset = globalTarget`); the leading label "Chapter N of M" is driven by the derived `currentChapterIdx`.
- `updateChapterScrollFraction()` (lines 849-860): in continuous mode, compute per-chapter fraction from `(currentOffsetUTF16 - chapterStart) / chapterLength` using `chapterOffsetIndex`.

**`vreader/Views/Reader/TXTChunkedReaderBridge.swift`**
- Add an optional `chapterOffsetIndex: TXTChapterOffsetIndex?` parameter (default `nil` — preserves the existing large-file caller). When non-nil, `reportScrollPosition` still reports document-global offsets exactly as today; the **container** derives the chapter. No change to the table's offset math — its `chunkStartOffsets` are already document-global, which is precisely the continuous-surface contract.
- `scrollToGlobalOffset` (in `TXTChunkedHighlightHelper.swift`) is already a whole-document offset→chunk seek — it is the TOC-jump primitive. No change.
- One real fix needed: `restoreChunkIndex` / `restoreIntraChunkOffset` restore is currently fraction-based (lines 104-115, `attemptChunkRestore`). For accurate cross-chapter restore the container will pass a document-global `restoreOffset` instead; add a `restoreGlobalOffset: Int?` param and have `makeUIView` route it through `scrollToGlobalOffset` after layout settles. (The fraction path stays for the legacy large-file caller.)

### ADDED

**`vreader/Services/TXT/TXTChapterOffsetIndex.swift`** (new, ~70 LOC)
- `struct TXTChapterOffsetIndex: Sendable, Equatable` — the chapter-awareness layer over the continuous surface.
  - `let chapters: [TXTChapter]` (carries `globalStartUTF16` + `textLengthUTF16`, already populated by the builder).
  - `let totalTextLengthUTF16: Int`.
  - `func chapterContaining(_ globalUTF16: Int) -> Int` — binary search over `globalStartUTF16`, clamped to `[0, count-1]`.
  - `func globalStart(ofChapter idx: Int) -> Int` and `func chapterLength(_ idx: Int) -> Int`.
  - `func chapterLocalFraction(globalUTF16: Int) -> (chapterIdx: Int, fraction: Double)` — for the per-chapter scrubber.
  - `static func build(from index: TXTChapterIndex) -> TXTChapterOffsetIndex`.
- Pure value type, no `@MainActor`, fully unit-testable. This is the single source of truth for "which chapter is offset X in".

**`vreader/Services/TXT/TXTContinuousChunkBuilder.swift`** (new, ~60 LOC)
- `enum TXTContinuousChunkBuilder` — turns a full decoded book string into `(chunks: [String], chunkStartOffsets: [Int])` for the `UITableView`, reusing `TXTTextChunker.split`. This is what `openContinuous` calls. Extracted as a pure function so chunk-offset math is unit-tested independent of the view model.
- Decodes once via the existing `TXTChapterContentLoader`'s full-text decode (the loader already does a lazy full-file decode at `TXTChapterContentLoader.swift:34-39`); add an actor method `func fullDecodedText() throws -> String` to expose it without slicing.

### Files OUT of scope

- **`vreader/Views/Reader/NativeTextPagedView.swift`** and its paginator — the **Paged** layout path. Bug #180 is explicitly about *Scroll* layout. Paged stays single-chapter.
- **`vreader/Views/Reader/MDReaderContainerView.swift`** / MD reader stack — MD shares `TXTTextViewBridge` but is not chaptered the same way; Bug #180's repro and directive are TXT-specific. MD scroll mode is untouched. (Cross-ref bug #179 noted MD shares the bridge — but #180's chapter model is TXT-only.)
- **EPUB reader stack** — bug #165 tracks the EPUB discrete-vs-continuous question separately; explicitly cross-referenced as a *different* bug.
- **`TXTChapterIndexBuilder.swift`**, **`TXTTocRule*.swift`**, **`TXTChapterIndexStore.swift`** — chapter detection / persistence is unchanged; the continuous surface consumes the *same* `TXTChapterIndex`.
- **`TXTOffsetTranslator.swift`** — used only by the saved-position resolver in `TXTFileLoader`; its global↔local math is still correct and reused.
- **Search indexing** (`ReaderSearchCoordinator` etc.) — TXT search already operates in document-global UTF-16 offsets; continuous scroll makes search-tap navigation *simpler* (no chapter swap), no code change required.
- **`ReaderSafeAreaResolver`** / bug #179 inset machinery — already applied to `TXTChunkedReaderBridge.contentInset.top`; continuous mode inherits it for free.
- Position persistence schema (`Locator`, `ReaderPositionService`, `ReadingPositionPersisting`) — no schema change; the `txtchapter:idx:local` href format is preserved.

---

## 3. Design

### 3.1 Chaptered TXT renders as one continuous scrollable surface

The continuous surface **is** the existing `TXTChunkedReaderBridge` `UITableView`, but fed the **entire book** instead of one chapter:

1. `openContinuous(url:)` opens via `service.openChapterBased` → gets the `TXTChapterIndex` (with `globalStartUTF16` / `textLengthUTF16` populated) + the `TXTChapterContentLoader`.
2. It calls the loader's new `fullDecodedText()` to get the whole book string once.
3. `TXTContinuousChunkBuilder.build` splits that into `[String]` chunks (16 KB target — same `TXTTextChunker.split` the large-file path uses) and computes `chunkStartOffsets` (cumulative document-global UTF-16 offsets).
4. `TXTChapterOffsetIndex.build(from:)` produces the chapter-awareness layer.
5. `TXTReaderContainerView` renders `TXTChunkedReaderBridge(chunks:, chunkStartOffsets:, chapterOffsetIndex:, …)`.

Result: every chapter's text is concatenated into one scroll surface. The `UITableView` lazily instantiates only on-screen rows (its existing behavior + 20-entry LRU attributed-string cache at `TXTChunkedReaderBridge.swift:235`). Crossing a chapter boundary is just scrolling from row K into row K+1 — **no text swap, no relayout, no `contentOffset` jump**. There is no chapter boundary in the render tree at all; chapter boundaries exist only as offsets in `TXTChapterOffsetIndex`.

Smoothness: the table already uses `UITableView.automaticDimension` with `estimatedRowHeight = 800` and self-sizing cells. Chunk boundaries are mid-document and produce no visible seam (each cell's `UITextView` has `lineFragmentPadding = 0`, zero top/bottom inset — `TXTChunkedReaderBridge.swift:192`). This is already proven for >500 K-UTF-16 books; chaptered books are routed through the identical path.

### 3.2 `currentChapterIdx` derived from scroll offset

`currentChapterIdx` stops being an open-time/render-mode value. The flow:

1. The table's `reportScrollPosition` (`TXTChunkedReaderBridge.swift:608-625`) computes the top-visible **document-global** UTF-16 offset (`chunkStartOffsets[chunkIndex] + intraOffset`) and calls `delegate?.scrollPositionDidChange(topCharOffsetUTF16:)`.
2. `TXTReaderViewModel.updateScrollPosition` receives that global offset. In continuous mode it calls `updateChapterIndexFromOffset(global)`:
   ```
   currentChapterIdx = chapterOffsetIndex.chapterContaining(global)
   currentChapterLocalUTF16 = global - chapterOffsetIndex.globalStart(ofChapter: currentChapterIdx)
   currentOffsetUTF16 = global
   ```
3. `currentChapterIdx` is now a pure function of scroll position. The chapter-title overlay (`ChapterTitleOverlay`, fed by `viewModel.currentChapterTitle` at `TXTReaderContainerView.swift:172`) updates live as the user scrolls across a boundary — exactly the "chapter awareness preserved" requirement.

`@Observable` propagation already handles the overlay re-render on `currentChapterIdx` change.

### 3.3 TOC jumps scroll within the surface

A TOC tap or Contents-toolbar chapter button currently calls `navigateToChapterByTitle` / `navigateToGlobalOffset` → `navigateToChapter` → swap text. Under continuous scroll:

- `navigateToChapter(idx)` no longer loads/swaps text. It computes the chapter's document-global start (`chapterOffsetIndex.globalStart(ofChapter: idx)`) and publishes it as a **scroll target**: `uiState.scrollToOffset = globalStart`.
- `TXTChunkedReaderBridge.updateUIView` already watches `scrollToOffset` (lines 154-158) and calls `scrollToGlobalOffset` — which binary-searches `chunkStartOffsets` for the containing chunk and `scrollToRow`s to it. The table scrolls smoothly to the chapter's first row.
- Because the surface is continuous, the jump lands at the chapter's true top (chunk start ≈ chapter start) — no stale-offset bug, no cascade.
- `navigateToChapterByTitle` / `navigateToGlobalOffset` keep their title-match / offset-search logic but their terminal action becomes "set `scrollToOffset`" instead of "swap chapter text". The `onNavigate` closure in `makeNotificationDeps` (`TXTReaderContainerView.swift:476-493`) is simplified: in continuous mode every navigation target is a document-global offset → `uiState.scrollToOffset = offset`. No `navigateToChapterByTitle` round-trip needed (chapter is derived afterward from where the scroll lands).

### 3.4 Per-chapter progress

Two progress consumers:

- **Per-chapter scrubber fraction** (the bottom-chrome progress bar): `chapterScrollFraction` becomes `chapterOffsetIndex.chapterLocalFraction(globalUTF16: currentOffsetUTF16).fraction`. The `onSeek` handler maps `seekValue` (0–1 within the current chapter) to a document-global offset: `chapterStart + Int(seekValue * chapterLength)` → `uiState.scrollToOffset`.
- **Book-level progression** (`totalProgression`, `chapterBasedProgression`): unchanged formula — `Double(currentOffsetUTF16) / Double(totalTextLengthUTF16)`. Now genuinely continuous because `currentOffsetUTF16` moves continuously, not in chapter-sized steps.

`ChapterProgressCalculator.bookProgress` stays usable: `bookProgress(currentChapterIdx:, scrollFraction:, totalChapters:)` with the derived `currentChapterIdx` and the per-chapter `scrollFraction`.

### 3.5 Feature #48's chapter-scoped highlight pipeline over a continuous surface

This is the subtle part. Feature #48's pipeline (`HighlightCoordinator`, `TXTChapterHighlightHelper`, `LocatorFactory.txtChapterRange`) was built for the **single-chapter `UITextView`**, where the bridge needs **chapter-local** ranges (the `UITextView` only contains one chapter's text). The translation helpers (`TXTChapterHighlightHelper.highlightsForChapter`, `lookupForChapter`, `chapterLocalHighlightRanges` in the container) convert global↔chapter-local.

Under the continuous `UITableView`, the surface is document-global — and `TXTChunkedReaderBridge` **already** consumes document-global highlight ranges. Its `chunkLocalHighlightRanges(forChunk:)` (`TXTChunkedHighlightHelper.swift:171-211`) translates document-global → chunk-local internally; `resolveChunkedHighlightTap` (`TXTChunkedReaderBridge.swift:441-497`) converts chunk-local tap → document-global before hit-testing. So:

- **Persisted highlights**: passed to the bridge as document-global `uiState.persistedHighlightRanges` / `persistedHighlightLookup` directly. **No chapter-local translation.** The chunked bridge's existing chunk-offset math handles cross-chunk (and therefore cross-chapter) highlights — it already clips ranges that straddle chunk boundaries.
- **Highlight creation**: a long-press selection in continuous mode reports a document-global `UTF16Range` (the table's `textViewDidChangeSelection` at `TXTChunkedReaderBridge.swift:509-526` already adds `chunkStartOffsets[chunkIndex]`). So `makeLocatorForTXT` in continuous mode takes the **`txtRange` branch** (document-global), not the `txtChapterRange` branch. `LocatorFactory.txtChapterRange` is still used by the Paged single-chapter path; continuous mode uses `LocatorFactory.txtRange` with global offsets.
- **Chapter-scoped semantics preserved**: feature #48's *intent* — a highlight belongs to a chapter — is recovered cheaply by deriving the chapter from the highlight's global start offset via `TXTChapterOffsetIndex.chapterContaining(range.location)`. Nothing in the persistence layer needs the chapter to be baked into the range; the `Locator` already stores `charRangeStartUTF16` (global) and the `href`. So the highlight's chapter is *derivable*, exactly like `currentChapterIdx`.
- **`makeNotificationDeps.locatorFactory`** (`TXTReaderContainerView.swift:461-473`): in continuous mode, drop the chapter lookup and call `LocatorFactory.txtRange(fingerprint:, charRangeStartUTF16: start, charRangeEndUTF16: end)` with the already-global offsets. `sourceText` for context extraction becomes the whole-book text (available — the continuous path decoded it).

Net: feature #48 keeps working because the continuous surface speaks the **same document-global UTF-16 coordinate space** the persistence layer always used. The chapter-local hop existed *only* because the single-`UITextView` render unit was a chapter; remove that render unit and the hop is unnecessary. `TXTChapterHighlightHelper` is retained unchanged for the Paged path.

### 3.6 Saved-position restore

- **Restore**: `openContinuous` resolves the saved `Locator` to a **document-global** offset. The existing `TXTFileLoader.resolveChapterPosition` already parses `txtchapter:idx:local` hrefs and legacy global offsets; reuse it, then convert `(chapterIdx, localOffset)` → global via `chapterOffsetIndex.globalStart(ofChapter: idx) + localOffset`. Pass that global offset to `TXTChunkedReaderBridge` as the new `restoreGlobalOffset` param. The bridge routes it through `scrollToGlobalOffset` once the table has a valid frame (reusing the existing `attemptChunkRestore` retry-on-zero-bounds logic at `TXTChunkedReaderBridge.swift:272-302`).
- **Save**: `makeLocator()` in continuous mode emits `href = "txtchapter:\(currentChapterIdx):\(currentChapterLocalUTF16)"` with the derived idx/local, plus `charOffsetUTF16 = currentOffsetUTF16` (global). Format identical to today → forward/backward compatible.
- The post-restore `restoreSuppressUntil` window (`TXTReaderViewModel.swift:103-106`, `:511-515`) stays — it still guards against TextKit relayout storms during the table's initial layout.

---

## 4. Prior art / project precedent / rejected alternatives

**Existing chunked `UITableView` windowing (the chosen foundation).** `TXTChunkedReaderBridge` already renders books >500 K UTF-16 as a continuous `UITableView` of 16 KB text-chunk cells, with lazy row instantiation, a 20-entry LRU attributed-string cache, document-global `chunkStartOffsets`, `scrollToGlobalOffset` for jump navigation, and document-global highlight support (`TXTChunkedHighlightHelper`). It is a *proven, shipping continuous renderer*. The tracker explicitly says "reuse it rather than swapping `UITextView` text" and "build on that windowing, not load every chapter's full attributed string at once." This plan extends it from "large-file fallback" to "the continuous surface for all chaptered TXT in Scroll layout," adding only a `TXTChapterOffsetIndex` overlay.

**Discrete chapter-swap (PR #681 — rejected).** Render one chapter in a single `UITextView`, detect scroll-to-edge, swap the whole text. Rejected by the user as the wrong model: it produces visible jumps, lands at the wrong position (stale `contentOffset`), and cascades chapters. Ripped out by this plan.

**Single giant `UITextView` for the whole book (rejected).** Concatenate all chapters into one `NSAttributedString` in one `UITextView`. Rejected: TextKit 1 glyph storage blows up for large books — the *exact* reason `TXTChunkedReaderBridge` exists (`largeFileThreshold = 500_000`, `TXTReaderContainerView.swift:44`). A 5 MB CJK novel would be unscrollable.

**TextKit 2 / `UICollectionView` compositional rewrite (rejected for this bug).** A from-scratch TextKit 2 viewport-based renderer would be the "ideal" continuous engine, but it is a multi-month rewrite touching every reader format. Bug #180 is feature-sized-on-a-bug-row by explicit user choice; reusing the working chunked table is the proportionate move. (Could be a future feature; out of scope here.)

**`UIScrollView` + manually stacked per-chapter `UITextView`s (rejected).** Reproduces TextKit-per-chapter relayout cost and re-introduces chapter-as-render-unit seams; offers nothing the `UITableView` lazy windowing doesn't already give for free.

---

## 5. Work-item sequencing

Each WI is ≈ one PR. Foundational WIs land pure, testable seams before behavioral wiring.

**WI-1 — Rip out PR #681 boundary-swap machinery.** *(Foundational, small PR ~150 LOC removed.)*
Delete `didScrollPast{Bottom,Top}Boundary` from `TXTViewConfig.swift` (protocol + default extension); delete the boundary block in `TXTTextViewBridgeCoordinator.sendScrollPosition`; delete the two conformance methods + `isChapterNavInFlight` from `TXTReaderViewModel.swift`; delete `TXTScrollBoundaryChapterNavTests.swift`. Build + full test gate green (no behavior depends on it post-deletion — chapter swap still works via chrome button until WI-5). Pure subtraction; no continuous scroll yet.

**WI-2 — `TXTChapterOffsetIndex` value type.** *(Foundational, small PR ~70 LOC + tests.)*
New `vreader/Services/TXT/TXTChapterOffsetIndex.swift` with `build`, `chapterContaining`, `globalStart`, `chapterLength`, `chapterLocalFraction`. Pure, no UIKit. Fully unit-tested in isolation. Nothing consumes it yet.

**WI-3 — `TXTContinuousChunkBuilder` + full-text decode seam.** *(Foundational, small PR ~80 LOC + tests.)*
New `TXTContinuousChunkBuilder.swift` (`build(fullText:) -> (chunks, offsets)`); add `TXTChapterContentLoader.fullDecodedText()`. Pure chunk-offset math, unit-tested.

**WI-4 — `TXTChunkedReaderBridge` accepts `chapterOffsetIndex` + `restoreGlobalOffset`.** *(Behavioral, medium PR ~120 LOC + tests.)*
Add the two optional params (default `nil` — large-file caller unaffected). Route `restoreGlobalOffset` through `scrollToGlobalOffset` in `makeUIView` with the existing retry logic. No container wiring yet; verified via bridge-level unit tests for the restore path.

**WI-5 — `openContinuous` + continuous render path in the container.** *(Behavioral, the largest PR ~250 LOC + tests.)*
Add `TXTReaderViewModel.openContinuous(url:)`, `chapterOffsetIndex` state, `updateChapterIndexFromOffset`, and the continuous branch of `updateScrollPosition` / `makeLocator`. Add `TXTReaderContainerView.continuousChapteredReaderContent` + the `body` branch + the `.task` call. This is where chaptered TXT in Scroll layout first renders as a continuous surface. Behavioral; covered by ViewModel unit tests + the rendering-decision tests.

**WI-6 — TOC jumps + chapter-nav buttons retargeted to scroll.** *(Behavioral, medium PR ~120 LOC + tests.)*
Rewrite `navigateToChapter` / `navigateToChapterByTitle` / `navigateToGlobalOffset` so their terminal action in continuous mode is "publish `scrollToOffset`" not "swap text". Simplify `makeNotificationDeps.onNavigate`. Wire the per-chapter scrubber `onSeek` to document-global offsets.

**WI-7 — Highlight pipeline over the continuous surface.** *(Behavioral, medium PR ~100 LOC + tests.)*
Switch `makeLocatorForTXT` / `makeNotificationDeps.locatorFactory` to the document-global `txtRange` branch in continuous mode; pass document-global highlight ranges/lookup straight to the bridge (no chapter-local translation). Per-highlight chapter derived via `TXTChapterOffsetIndex`. Verify feature #48 create/restore/tap-edit/delete all work.

**WI-8 — Saved-position restore + per-chapter progress integration.** *(Behavioral, small-medium PR ~90 LOC + tests.)*
`openContinuous` resolves saved `Locator` → document-global offset via reused `resolveChapterPosition`; feeds `restoreGlobalOffset`. `updateChapterScrollFraction` continuous branch. Backward-compat tests for old-version `txtchapter:` and legacy global-offset locators.

Sequencing rationale: WI-1 removes the rejected design first so it cannot interfere. WI-2/3/4 are pure-and-foundational — they add testable seams with zero behavior change. WI-5 is the one big behavioral landing. WI-6/7/8 each restore one chapter-awareness facet (TOC, highlights, restore+progress) on top of the working continuous surface, so a regression in any one is isolated to its PR.

---

## 6. Test catalogue

**`vreaderTests/Services/TXT/TXTChapterOffsetIndexTests.swift`** (new — WI-2)
- `build` populates `chapters` + `totalTextLengthUTF16` from a `TXTChapterIndex`.
- `chapterContaining` returns correct index at: offset 0, exact chapter starts, mid-chapter, last offset, beyond-end (clamps to last), negative (clamps to 0).
- `chapterContaining` on a single-chapter book always returns 0.
- `globalStart` / `chapterLength` for first / middle / last chapter; out-of-bounds → safe defaults.
- `chapterLocalFraction`: 0.0 at chapter start, ~1.0 at chapter end, monotonic within a chapter.
- Binary-search correctness on a 1000-chapter synthetic index.

**`vreaderTests/Services/TXT/TXTContinuousChunkBuilderTests.swift`** (new — WI-3)
- `build` produces chunks whose concatenation equals the input text.
- `chunkStartOffsets` are cumulative UTF-16 lengths, strictly increasing, first = 0.
- Empty text → empty chunks, empty offsets.
- CJK / surrogate-pair text: chunk boundaries do not split a surrogate pair (offset math stays UTF-16-consistent).
- `TXTChapterContentLoader.fullDecodedText()` returns the same string the slicing path decodes.

**`vreaderTests/Views/Reader/TXTChunkedReaderBridgeRestoreTests.swift`** (new — WI-4)
- `restoreGlobalOffset` routes through `scrollToGlobalOffset` to the correct chunk.
- `restoreGlobalOffset = nil` leaves the table at top (no-op).
- Restore retries when `tableView.bounds.width == 0` then succeeds (reuses `attemptChunkRestore` retry).
- `chapterOffsetIndex` param defaulting `nil` does not change large-file-caller behavior (regression guard).

**`vreaderTests/ViewModels/TXTReaderViewModelContinuousTests.swift`** (new — WI-5/6/8)
- `openContinuous` builds `chapterOffsetIndex`, whole-book chunks, sets `isContinuousMode`.
- `updateScrollPosition` with a global offset derives the correct `currentChapterIdx` (boundary, mid-chapter, last chapter).
- Scrolling across a chapter boundary flips `currentChapterIdx` by exactly 1 and updates `currentChapterTitle`.
- `currentChapterLocalUTF16` = global − chapter start; `currentOffsetUTF16` = global.
- `makeLocator` in continuous mode emits `txtchapter:idx:local` with derived idx/local AND `charOffsetUTF16` = global.
- `navigateToChapter(idx)` publishes `scrollToOffset = chapter global start` and does NOT swap `currentChapterText`.
- `navigateToGlobalOffset` / `navigateToChapterByTitle` resolve to the right document-global `scrollToOffset`.
- Restore: a saved `txtchapter:3:120` locator → `restoreGlobalOffset` = chapter-3 start + 120.
- `chapterScrollFraction` continuous branch: 0 at chapter start, ~1 at chapter end.

**`vreaderTests/Views/Reader/TXTContinuousRenderingDecisionTests.swift`** (new — WI-5)
- Chaptered TXT + Scroll layout → continuous branch chosen.
- Chaptered TXT + Paged layout → single-chapter path (continuous NOT chosen).
- Non-chaptered TXT → existing flat / large-file paths unchanged.
- Continuous-build failure → falls back to single-chapter `chapterReaderContent` (no crash).

**`vreaderTests/Views/Reader/TXTContinuousHighlightTests.swift`** (new — WI-7)
- `makeLocatorForTXT` in continuous mode takes the `txtRange` (global) branch; chapter mode takes `txtChapterRange`.
- A document-global persisted highlight spanning a chapter boundary survives translation through the chunked bridge's chunk-local math (no clipping loss across the boundary).
- A long-press selection in continuous mode yields a document-global `UTF16Range`.
- Per-highlight chapter derivation: `chapterContaining(highlight.range.location)` returns the expected chapter.
- Tap-on-highlight in continuous mode resolves to the correct highlight UUID via the chunked `resolveChunkedHighlightTap` path.

**`vreaderTests/ViewModels/TXTReaderPositionBackCompatTests.swift`** (new — WI-8)
- Old `txtchapter:N:M` href from a pre-fix version restores to the correct continuous offset.
- Legacy bare-`charOffsetUTF16` locator (no href) restores via `resolveChapterPosition`'s fallback.
- A position saved by the new continuous build re-loads identically.

**Modified existing suites**
- `TXTReaderViewModelTests` / `TXTReaderViewModel*ChapterNav*Tests`: remove assertions on `didScrollPast*` / `isChapterNavInFlight`; keep chrome-button chapter-nav assertions, updated to expect `scrollToOffset` publication instead of text swap.
- `TXTChapterHighlightRenderingTests`: unchanged — still exercises the Paged single-chapter translation path.
- Full `vreaderTests` Swift Testing run green after each WI (project gate).

**Device verification (per the bug's Verify step):** iPhone 17 Pro Sim — open a multi-chapter TXT (`war-and-peace.txt`), Layout = Scroll, scroll from Chapter 1 into Chapter 2: confirm (a) no jump / no cascade, (b) chapter-title overlay updates as the boundary passes, (c) TOC tap lands at a chapter top, (d) create a highlight that straddles a boundary and reopen the book to confirm it restores, (e) reopen mid-chapter and confirm saved position restores.

---

## 7. Risks + mitigations

| Risk | Mitigation |
|---|---|
| **Offset/position correctness across chapter boundaries.** The continuous surface must keep `currentChapterIdx`, `currentChapterLocalUTF16`, and `currentOffsetUTF16` mutually consistent as the user scrolls. | The single source of truth is `TXTChapterOffsetIndex.chapterContaining` over **document-global** offsets — the same space the `UITableView`'s `chunkStartOffsets` and the persistence layer already use. No chapter-local↔global round-trip happens during scroll (the rejected design's failure mode). WI-2's unit suite pins boundary, mid-chapter, last-offset, and clamp cases. |
| **Highlight-range correctness.** Feature #48 highlights must render and hit-test correctly, including ranges that straddle a chapter (now chunk) boundary. | Highlights stay document-global end-to-end; the chunked bridge's `chunkLocalHighlightRanges` already clips cross-chunk ranges correctly (shipping code). WI-7 tests a boundary-straddling highlight explicitly. The chapter is *derived* for display labels, never used to clip the range. |
| **TOC-jump accuracy.** A TOC tap must land at the chapter's true top, not mid-chunk. | Chapter starts come from `TXTChapterIndex.globalStartUTF16` (builder-populated); `scrollToGlobalOffset` binary-searches the containing chunk and `scrollToRow`s with intra-chunk fraction. Because chunks are 16 KB and chapter starts are exact UTF-16 offsets, the landing is precise. WI-6 tests resolution to the right offset. |
| **Large-file performance.** A 5 MB CJK novel as one continuous surface must not stall. | This is *exactly* what `TXTChunkedReaderBridge` was built for (>500 K UTF-16 large-file path). Lazy row instantiation + 20-entry LRU attributed-string cache + `automaticDimension` self-sizing already proven in production. Continuous chaptered TXT is routed through the identical mechanism — no new perf surface. The whole-book decode happens once at open (the chapter-mode loader already does a lazy full-file decode). |
| **Memory.** Concatenating all chapters could balloon memory if attributed strings are all built eagerly. | Chunks are stored as plain `String` (`[String]`); `NSAttributedString` is built **per visible cell** and LRU-evicted (`TXTChunkedReaderBridge.swift:235`, `maxCacheSize = 20`). Only the whole-book plain-text string + the chunk array are resident — same footprint as the existing large-file path. The tracker's explicit instruction ("not load every chapter's full attributed string at once") is satisfied by reusing the windowing. |
| **Initial-layout `contentOffset` race on restore.** The table needs a valid frame before restore-scroll. | Reuse `attemptChunkRestore`'s existing zero-bounds retry loop (5 retries, 0.1 s). The `restoreSuppressUntil` window in the ViewModel still drops relayout-storm scroll callbacks. Bug #179's `ReaderSafeAreaResolver` inset feed is already wired to the chunked bridge. |
| **Chrome-button chapter nav vs scroll-derived `currentChapterIdx` fighting.** A button tap sets `scrollToOffset`; the resulting programmatic scroll then re-derives `currentChapterIdx`. | This is *correct convergence*, not a fight: the button publishes a target, the scroll lands, the derivation confirms the chapter. No `isChapterNavInFlight` serializer needed — there is no text swap to race. The `suppressScrollCallbacks` / programmatic-scroll guards in the bridge already prevent spurious mid-animation callbacks. |
| **Scroll-position-save thrash during fast scrolling.** Continuous scroll generates more `scrollPositionDidChange` calls. | The bridge already throttles (`scrollThrottleInterval = 0.1`, `TXTChunkedReaderBridge.swift:239`); `ReaderPositionService` debounces saves (2 s default). No change. |
| **Behavioral regression in the existing large-file path** (it shares `TXTChunkedReaderBridge`). | New bridge params (`chapterOffsetIndex`, `restoreGlobalOffset`) default to `nil`; WI-4 includes an explicit regression-guard test that `nil` preserves large-file-caller behavior. |

---

## 8. Backward compatibility

**Saved TXT positions.** The position `Locator` schema is **unchanged**. The new continuous path emits the *same* `href = "txtchapter:\(idx):\(local)"` format and the same global `charOffsetUTF16`:

- A position **saved by an older (pre-fix or PR #681) version** — either a `txtchapter:N:M` href or a legacy bare global offset — is restored by reusing `TXTFileLoader.resolveChapterPosition` (`TXTFileLoader.swift:136-172`), which already handles both forms. The resolved `(chapterIdx, localOffset)` is converted to a document-global offset via `chapterOffsetIndex` and fed to the table. No migration, no data loss.
- A position **saved by the new continuous build** uses the identical format, so a user who later downgrades (or whose device runs the Paged path) still loads it: the Paged single-chapter resolver parses `txtchapter:N:M` exactly as before.

**Highlights.** `HighlightRecord` / `Locator` for TXT highlights store **document-global** `charRangeStartUTF16` / `charRangeEndUTF16` (feature #48 — `LocatorFactory.txtChapterRange` translates chapter-local→global *before* persisting, `LocatorFactory.swift:172-173`). Persisted highlights are therefore *already* in the document-global coordinate space the continuous surface uses. Old highlights render and hit-test on the continuous surface with **no migration** — the continuous path passes them straight to the bridge; only the *display-time* chapter-local translation (used by the Paged path) is skipped. Highlights created on the continuous surface persist in the same global space, so they remain valid for the Paged path and for any older version.

**Bookmarks.** TXT bookmarks store a `Locator` with a global `charOffsetUTF16` (and optionally the `txtchapter:` href). Bookmark navigation in continuous mode routes the bookmark's global offset through `scrollToOffset` → `scrollToGlobalOffset`. Old bookmarks resolve unchanged.

**Net:** zero schema change, zero migration, fully bidirectional with older versions and with the Paged path. The continuous surface is a *rendering-mechanism* change; the persisted coordinate space (document-global UTF-16 + `txtchapter:` href) is the stable contract that makes this clean.

---

## 9. Rule 51 (no self-designed UI) status

**Status: PASS — no `needs-design` blocker. This is a pure rendering-mechanism change with no new visible UI element.**

The continuous-scroll change introduces **no new chrome, no new control, no new visible surface**:

- The scrollable surface is the existing `TXTChunkedReaderBridge` `UITableView` — already shipping for large files; visually identical text rendering (same fonts, insets, `lineFragmentPadding = 0`, theme background).
- The chapter-title overlay (`ChapterTitleOverlay`), bottom chrome (`ReaderBottomChrome` — scrubber + labels + Contents/Notes/Display/AI toolbar), and TOC are **all reused unchanged**. They now read a *derived* `currentChapterIdx` instead of a render-mode value — a data-source change behind an existing component, not a new component.
- The Contents-toolbar chapter prev/next buttons are reused (feature #60's design already placed chapter nav there); they retarget from "swap text" to "scroll to offset" — same buttons, same placement.
- No new Scroll-vs-Paged toggle, no new boundary indicator, no new affordance. The Scroll/Paged layout picker already exists (`EPUBLayoutPreference`, `ReaderSettingsPanel`).

Per the bug's own scope note: *"behavior-only continuous scroll reusing existing chrome does not [require a design]."* This change is exactly that — it removes a jarring discrete-swap behavior and replaces it with smooth continuous scroll using the existing renderer and existing chrome. No `Design needed:` row is required.

(If, during implementation, a *new* visible element were found necessary — e.g. a chapter-boundary separator line in the continuous flow — that would be a rule-51 `needs-design` blocker and must be filed before merge. The plan as designed introduces none: chapter boundaries are invisible in the continuous flow, which is the desired "no jump at all" outcome.)

---

### Critical Files for Implementation

- /Users/ll/workspace/vreader/vreader/ViewModels/TXTReaderViewModel.swift
- /Users/ll/workspace/vreader/vreader/Views/Reader/TXTReaderContainerView.swift
- /Users/ll/workspace/vreader/vreader/Views/Reader/TXTChunkedReaderBridge.swift
- /Users/ll/workspace/vreader/vreader/Views/Reader/TXTViewConfig.swift
- /Users/ll/workspace/vreader/vreader/Services/TXT/TXTFileLoader.swift

(New files to be created: `/Users/ll/workspace/vreader/vreader/Services/TXT/TXTChapterOffsetIndex.swift` and `/Users/ll/workspace/vreader/vreader/Services/TXT/TXTContinuousChunkBuilder.swift`. File to be deleted: `/Users/ll/workspace/vreader/vreaderTests/Views/Reader/TXTScrollBoundaryChapterNavTests.swift`.)