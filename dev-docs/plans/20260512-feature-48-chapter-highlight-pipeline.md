# Feature #48 — TXT Chapter-Mode Highlight Pipeline (WI-7) — Implementation Plan

> **NOTE on the dev-docs/plans naming collision**: An earlier file
> `20260503-feature-48-debugbridge-probe-completion.md` exists for the
> *old* #48 (DebugBridge probe completion, since split into #49 + #50
> and archived as DUPLICATE). Today's #48 was re-filed against a
> different problem. This 2026-05-12 file is the plan for the current
> row.

**Source row**: `docs/features.md` #48 (TODO → PLANNED on Gate 1 acceptance)
**Priority**: Medium
**Author**: Claude (feature-cron 2026-05-12)
**GH issue**: not yet filed
**Status**: v4 — Round-3 audit clarifications applied; plan clean for Gate 3 entry. See revision history at bottom.

## Problem

When a TXT file has detected chapter markers, `TXTReaderContainerView`
switches to **chapter mode**: the body renders the current chapter only
(~5-50KB), and the bridge's textView contains chapter text only. This
is by-design for performance.

Three highlight-related paths are unimplemented in chapter mode (all
share root cause: chapter-mode bridge owns chapter coordinates while
state carriers and locators speak global coordinates):

1. **Render-side persisted/temp highlight** — `chapterReaderContent`
   (TXTReaderContainerView.swift:486) hardcodes `highlightRange: nil`
   and `persistedHighlights: []` with comments "Highlight offset
   translation is WI-7".
2. **Navigation scroll** — `ReaderNotificationModifier.swift:38`
   writes `uiState.scrollToOffset = global` from
   `locator.charOffsetUTF16`. The chapter-mode bridge consumes it as
   chapter-local (TXTTextViewBridge.swift:187+), so search-tap +
   bookmark-navigate + persisted-highlight navigate all land wrong in
   chapter mode.
3. **Gesture-create locator** — `ReaderNotificationModifier.swift:51`
   builds a Locator via `deps.locatorFactory` (which routes to
   `LocatorFactory.txtRange`). In chapter mode the bridge reports
   chapter-local offsets and `deps.sourceText()` returns
   `viewModel.textContent` which IS the chapter text
   (TXTReaderViewModel.swift:306 sets `textContent = chapter text` in
   chapter mode). So quote/context extraction is already correct for
   chapter-local offsets, but the offsets get stored on the Locator as
   if global, producing a locator that points at the wrong place on
   reopen.

### User-visible consequences (already filed)

- **Feature #2** stuck `DONE` — search-tap in chapter mode no yellow
  paint (`feature-2-20260511-round3.md` evidence). Concern (1) + (2).
- **Feature #3** EPUB-only VERIFIED — TXT chapter-mode excluded with
  pointer to #48. Concern (1) + (3).
- **Bug #154** partial-fix WI-7-deferred. Concern (1) + (2).
- **Bug #160** partial-fix WI-7-deferred. Concern (3).

Affects every chapter-mode TXT file (any TXT with detected `Section N`
/ `Chapter N` markers — Position Test Book, war-and-peace, most
chaptered novels).

## Why it's a feature, not a bug

The three placeholder defaults in chapter mode are intentional. Chapter-mode
display was shipped (WI-6) ahead of the offset-translation work (WI-7).
This is feature work to lift the existing helper into production, not
a defect.

## Surface area (file-by-file)

### Production changes

| File | Lines (now) | Change |
|---|---|---|
| `vreader/Views/Reader/TXTChapterHighlightHelper.swift` | 80 | **Unchanged** — three pure functions already exist with 24 existing tests. |
| `vreader/Views/Reader/TXTReaderContainerView.swift` | 621 | **WI-1**: replace `highlightRange: nil` and `persistedHighlights: []` (lines 496+498) with `TXTChapterHighlightHelper.highlightsForChapter(...)` calls plus a wrapped single-range translation for `uiState.highlightRange`. **WI-2**: introduce a `chapterLocalScrollOffset` computed property that translates `uiState.scrollToOffset` from global to chapter-local for `chapterReaderContent`. **WI-3**: rebuild `makeNotificationDeps()` (lines 402-434) to use a new `txtChapterRange` factory variant when in chapter mode (passes chapter text + chapter globalStart). |
| `vreader/Views/Reader/ReaderNotificationHandlers.swift` | 190 (not 191 — plan v1 typo) | **WI-3 isolation fix**: change `locatorFactory: @Sendable (...) -> Locator?` to `@MainActor (...) -> Locator?`. All call sites (`ReaderNotificationModifier.swift:51`, `:101`, and the test helpers in `ReaderNotificationHandlers.swift:122`, `:168`) are already `@MainActor`. The `@Sendable` was over-restrictive; main-actor isolation lets the closure safely capture `viewModel` (which is itself `@MainActor`). MD container's `makeNotificationDeps` (line 233) gets the same one-line annotation change. |
| `vreader/Services/Locator/LocatorFactory.swift` | 280 | **WI-3 addition**: add `txtChapterRange(fingerprint:, chapterLocalStart:, chapterLocalEnd:, chapterText:, chapterGlobalStart:)`. Internally extracts quote/context from chapter text at chapter-local offsets (re-using `extractContext`), then computes globals via `chapterGlobalStart + local` and constructs the Locator. Doc-comments + 3 unit tests. |
| `vreader/Views/Reader/MDReaderContainerView.swift` | (unchanged behavior) | Touched only by the `locatorFactory` annotation change in `ReaderNotificationHandlers.swift`; no MD-specific logic changes (MD has no chapter mode). |

### Files OUT of scope (explicit)

- **`TTSHighlightCoordinator` / TTS chapter-mode** — TTS in chapter
  mode is also broken (TTSHighlightCoordinator.swift:54 writes
  `uiState.scrollToOffset` from its own sentence ranges; chapter-mode
  configuration is incoherent — coordinator is `configure(text:)`'d
  with chapter text in the container at line 224 area, but TTSService
  receives global offsets from `startTTS`). This is a SEPARATE problem
  with its own subsystem (TTS service, sentence tokenizer, source-text
  binding to chapters). Out of scope here; will file as follow-up
  feature/bug if it isn't already tracked under feature #40/#41 round
  notes. The WI-2 navigation translation does fix the *symptom*
  (`scrollToOffset` is now chapter-local-aware) so TTS auto-scroll
  will work in chapter 0 (`globalStart=0` makes the translation a
  no-op) but remain broken in non-zero chapters until the TTS source
  binding is fixed.
- `TXTChunkedReaderBridge` — large-file chunked path (>500K UTF-16
  files) does not use chapter mode; unaffected.
- `EPUBWebViewBridge` / Foliate bridges — non-TXT formats.
- `HighlightCoordinator` / `TextHighlightRenderer` — these consume
  the already-translated values from `uiState`; no change.
- `TXTChapter` / `TXTChapterIndex` data shapes — already populated
  with `globalStartUTF16` + `textLengthUTF16`.
- Schema / `@Model` changes — none.

## Prior art / project precedent / rejected alternatives

### Prior art (vreader)

- **`TXTChapterHighlightHelper` already exists** (3 pure functions, 24 tests at `vreaderTests/Services/TXT/TXTChapterHighlightHelperTests.swift`):
  - `highlightsForChapter(chapterIndex:chapters:persistedGlobalRanges:)` — global → chapter-local filtered + clipped list.
  - `toGlobalRange(localRange:chapterIndex:chapters:)` — chapter-local → global.
  - `toChapterLocalOffset(globalUTF16:chapterIndex:chapters:)` — single-offset translation.
- **`TXTOffsetTranslator`** populates `TXTChapter.globalStartUTF16` + `textLengthUTF16` on open.
- **`LocatorFactory.extractContext`** already centralises quote/context extraction; `txtChapterRange` re-uses it for chapter-local extraction.
- **Display-time clipping pattern** mirrors `TOCChapterProgress` clamping.

### Rejected alternatives

1. **Store chapter-local offsets in the database (schema fork).**
   Rejected. Breaks cross-format `Locator` invariants; any tool reading the DB (Backup, CloudKit sync, search index, future export tooling) would need a TXT-chapter-mode branch.
2. **Reload full text into the bridge whenever a highlight gesture starts.**
   Rejected. Defeats chapter mode.
3. **Translate inside `Locator`.**
   Rejected. `Locator` is cross-format; TXT-mode concern would leak everywhere.
4. **Single-WI implementation.**
   Rejected after round-1 audit: the navigation/scrollToOffset concern is genuinely separate from display rendering and from gesture creation. Combining them in one PR makes review and audit harder; the three concerns also touch different files. See "Work-item sequencing" below.

### Decision

Translation lives at the container boundary in three directions:
- **Out (DB → render)**: `uiState.persistedHighlightRanges` + `uiState.highlightRange` (globals) → chapter-local via `TXTChapterHighlightHelper.highlightsForChapter`. [WI-1]
- **Out (notification → scroll)**: `uiState.scrollToOffset` (global) → chapter-local via `TXTChapterHighlightHelper.toChapterLocalOffset`. [WI-2]
- **In (selection → DB)**: chapter-local offsets + chapter text → chapter-local quote/context extraction → globals on the Locator via new `LocatorFactory.txtChapterRange`. [WI-3]

## Work-item sequencing

Three WIs, each one PR with its own audit.

### WI-1 — Display side: render persisted + temp highlight in chapter mode

**Scope**: `chapterReaderContent` reads `viewModel.chapterIndex?.chapters` + `viewModel.currentChapterIdx`, and computes:
- `chapterLocalPersisted` = `TXTChapterHighlightHelper.highlightsForChapter(chapterIndex: idx, chapters: chs, persistedGlobalRanges: uiState.persistedHighlightRanges)`.
- `chapterLocalTempRange` = wrap `uiState.highlightRange` as `[NSRange]`, pass through `highlightsForChapter` (same clipping/filter), unwrap `.first`.
- Pass these to `TXTTextViewBridge` instead of `nil`/`[]`.

**Tests** (RED first), file `vreaderTests/Views/Reader/TXTChapterHighlightRenderingTests.swift`:
- `chapterModePassesTranslatedPersistedHighlights` — fixture: 3 chapters at globalStart [0, 1000, 2500]; persisted globals [1100, 1200], [2600, 2700]; current chapter 1 → bridge receives `[NSRange(100,100)]` only.
- `chapterModePassesTranslatedTempHighlight` — `uiState.highlightRange = NSRange(1100, 100)`, currentChapterIdx=1 → bridge receives `NSRange(100, 100)`.
- `chapterModeDropsOutOfChapterHighlights` — global from chapter 0, currentChapterIdx=2 → empty.
- `chapterModeClipsStraddlingBoundary` — global `[2400, 2700]` (50 into ch1 + 200 into ch2), currentChapterIdx=1 → only `[NSRange(900, 100)]` (the ch1 portion).
- `chapterModeNilHighlightWhenChapterIndexNil` — `viewModel.chapterIndex == nil` → still nil/empty (helper guard).

**Acceptance bar**: bug #154 acceptance reproduced (search-tap in chapter mode → yellow appears) *after* WI-2 lands. In isolation WI-1 covers persisted highlights restoring with paint; search-tap render gets the highlightRange translated correctly but won't visually paint until the scroll lands the user at the matched chapter, which is WI-2.

PR size: ~60 LOC production + ~140 LOC tests.

### WI-2 — Navigation translation: chapter-local scrollToOffset

**Round-2 audit reframe**: Plan v2 incorrectly assumed `uiState.scrollToOffset` was always written as global. In fact `TXTReaderContainerView.swift:159-161` (chapter-mode scrubber `onSeek`) ALREADY writes chapter-local values into `uiState.scrollToOffset` today. Translating a chapter-local 150 as if global against ch1 `[1000, 1150)` would fail the containment check and silently drop the scrubber seek. v3 fixes this by **canonicalising all writes to global** rather than introducing a parallel local channel.

**Scope (3-part)**:

**Part 2a — normalize writes to global (one writer change)**:
- `TXTReaderContainerView.swift:158-162` (chapter-mode scrubber `onSeek`): change `uiState.scrollToOffset = charOffset` (chapter-local) to compute global as `chapter.globalStartUTF16 + Int(seekValue * Double(chLen))`. Guard on `viewModel.chapterIndex?.chapters[viewModel.currentChapterIdx]` being well-formed.
- All other writers already write global: `ReaderNotificationModifier.swift:38` (search-tap/navigate), continuous-mode scrubber at `:184-188` (no-chapter writes its full-text global). No other writers found via grep.

**Part 2b — translate global→local at the chapter-mode bridge edge**:
- `chapterReaderContent` derives `chapterLocalScrollOffset` from `uiState.scrollToOffset` via `TXTChapterHighlightHelper.toChapterLocalOffset` ONLY when the global falls within the current chapter's `[globalStartUTF16, globalStartUTF16 + textLengthUTF16)`; otherwise pass `nil`. A cross-chapter target is handled by the `onNavigate` path which fires the actual chapter swap; after the swap, the new render cycle's containment check evaluates against the new current chapter and passes the in-range translated local.

**Part 2c — disambiguate bridge dedupe by source-text identity**:
- `TXTTextViewBridge.updateUIView` dedupes via `context.coordinator.lastScrollToTarget: Int?` at line 188. Two different chapters can share the same chapter-local Int target (chapter A local 50 == chapter B local 50), so a chapter swap with the same local target would dedupe-as-equal and skip the scroll.
- Fix: `TXTTextViewBridge.updateUIView` already computes a `sourceChanged` / `textChanged` signal earlier in the same function (around line 122 — checks the incoming `text` against the coordinator's stored prior text). **Reuse that existing signal**: when `sourceChanged` is true, set `context.coordinator.lastScrollToTarget = nil` BEFORE the dedupe check at line 188. No new `lastTextHash` field — that was the round-3 audit's correction over plan v3's duplicative design.
- This is a 2-line addition in `updateUIView` (reset `lastScrollToTarget` inside the existing `sourceChanged` block). No coordinator field additions.
- Symmetric for `TXTChunkedReaderBridge` if it has the same dedupe — verify during implementation; chunked path doesn't have chapter mode so any change there is no-op safety, not bug fix.

**Tests** (RED first), file `vreaderTests/Views/Reader/TXTChapterScrollOffsetTests.swift`:
- `chapterScrubberWritesGlobalScrollOffset` — exercise an extracted `private static func chapterScrubberGlobalOffset(seekValue: Double, chapter: TXTChapter) -> Int` on `TXTReaderContainerView` with `seekValue=0.5`, `chapter.globalStartUTF16=1000`, `chapter.textLengthUTF16=200` → returns `1100`. The helper has a single call site (the scrubber `onSeek` closure) but is extracted so the test is a direct pure-function call. Placement: same file as `TXTReaderContainerView.chunkIndex(for:in:)` (already a private static helper at line 536), mirroring that pattern.
- `chapterModeTranslatesScrollOffsetWithinChapter` — global=1150, ch1 globalStart=1000 → `toChapterLocalOffset` returns 150.
- `chapterModeDropsScrollOffsetForOtherChapter` — global=2700 (ch2), currentChapterIdx=1 → containment fails → bridge receives `nil`.
- `continuousModePassesScrollOffsetUntranslated` — `chapterIndex == nil` → bridge receives global verbatim.
- `chapterModeZeroChapterGlobalStartIsNoOpTranslation` — ch0 globalStart=0, global=50 → local=50.
- `bridgeResetsScrollDedupeOnSourceTextChange` — coordinator with `lastScrollToTarget=50` and an existing text "A"; update with `text="B"` and `scrollToOffset=50` → coordinator's `sourceChanged` branch nulls `lastScrollToTarget`, the scroll is NOT deduped, and the scroll path runs. Drives the existing `sourceChanged` field that round-3 audit identified — no new coordinator field.

**Acceptance bar**: bug #154 acceptance — search-tap on Position Test Book → reader scrolls to chapter that contains the match → yellow paint appears at the matched chapter-local range for 3s before auto-clear. Scrubber within a chapter still works (regression check). Scrubber → chapter-swap (if any) hands off cleanly.

PR size: ~60 LOC production (1 writer normalization + chapter-mode-render derivation + bridge dedupe identity) + ~140 LOC tests.

### WI-3 — Creation translation: chapter-local selection → global locator

**Round-2 audit reframe**: WI-3's `locatorFactory` seam is shared by BOTH the Highlight flow AND the Add Note flow (`ReaderNotificationModifier.swift:51-53` for `.readerHighlightRequested`, `:101-103` for the Add Note Sheet's save callback). Bug #160's mention of "persisted highlights" is a subset; chapter-mode notes created post-fix flow through the same closure and were affected by the same chapter-local-stored-as-global bug. WI-3 fixes both at once via the shared seam; tests cover both paths.

**Scope**:
1. **`ReaderNotificationHandlers.swift`**: change `locatorFactory` annotation from `@Sendable` to `@MainActor`. Mechanical one-line change, propagates to call sites in `ReaderNotificationModifier.swift`. (Round-1 audit named the wrong test path; the actual test file is `vreaderTests/Views/Reader/ReaderNotificationHandlerTests.swift` — singular — and the test must exercise `ReaderNotificationModifier` end-to-end through the `.onReceive` blocks, since the live highlight + Add Note paths are inlined into the modifier rather than delegated to the pure handler statics.)
2. **`LocatorFactory.swift`**: add `txtChapterRange(fingerprint:, chapterLocalStart:, chapterLocalEnd:, chapterText:, chapterGlobalStart:)` that:
   - **Validates bounds up front** (closing round-2 finding on underspecified contract): require `chapterLocalStart >= 0`, `chapterLocalEnd >= chapterLocalStart`, `chapterLocalEnd <= chapterText.utf16.count`, `chapterGlobalStart >= 0`. Out-of-bounds → return `nil` rather than build a Locator whose offsets exceed chapter-text reality. (Mirrors `txtRange`'s inverted-range nil semantics and adds the chapter-text upper bound.)
   - Extracts quote/context from `chapterText` at chapter-local offsets via `extractContext`.
   - Constructs `Locator.validated(...)` with global offsets (`chapterGlobalStart + chapterLocalStart`, similarly for end) and the extracted quote/context.
   - **Out of scope: `totalProgression` parameter** is left to the existing `txtRange` for now (chapter mode doesn't currently compute totalProgression from the closure; it's not used by the in-chapter highlight flow). If added later, document at the call site, not blindly threaded.
3. **`TXTReaderContainerView.makeNotificationDeps`**: rebuild the `locatorFactory` closure to:
   ```swift
   locatorFactory: { fp, start, end, _ in
       if let chIdx = viewModel.chapterIndex,
          viewModel.isChapterMode,
          let chapterText = viewModel.currentChapterText,
          viewModel.currentChapterIdx < chIdx.chapters.count {
           let chapter = chIdx.chapters[viewModel.currentChapterIdx]
           guard chapter.globalStartUTF16 >= 0 else { return nil }
           return LocatorFactory.txtChapterRange(
               fingerprint: fp,
               chapterLocalStart: start, chapterLocalEnd: end,
               chapterText: chapterText,
               chapterGlobalStart: chapter.globalStartUTF16
           )
       }
       return LocatorFactory.txtRange(
           fingerprint: fp,
           charRangeStartUTF16: start, charRangeEndUTF16: end,
           sourceText: viewModel.textContent
       )
   }
   ```
   The `sourceText` closure passed to the modifier becomes the input the closure ignores in chapter mode (kept for compatibility — passes `viewModel.textContent` which is chapter text anyway; continuous-mode branch still uses it). Capturing `viewModel` directly is now safe with `@MainActor` annotation.

**Tests** (RED first), files:
- `vreaderTests/Services/Locator/LocatorFactoryTXTChapterTests.swift` (factory unit):
  - `txtChapterRange.extractsQuoteFromChapterText` — chapterText="abcdefghij" (10 UTF-16), local [3,7), globalStart=1000 → quote="def", globals charRangeStart=1003 charRangeEnd=1007.
  - `txtChapterRange.handlesInvertedRange` — local [5,3) → nil.
  - `txtChapterRange.zeroGlobalStartIsIdentity` — globalStart=0 → quote + offsets identical to `txtRange` for the same input.
  - `txtChapterRange.rejectsNegativeStart` — chapterLocalStart=-1 → nil.
  - `txtChapterRange.rejectsEndBeyondChapterText` — chapterText.utf16.count=10, end=11 → nil.
- `vreaderTests/Views/Reader/TXTChapterHighlightCreationTests.swift` (closure unit + modifier integration):
  - `chapterModeNotificationDepsLocatorIsGlobal_highlightPath` — invoke the closure in chapter mode (currentChapterIdx=1, ch1 globalStart=1000) with start=50/end=60 + chapter text containing "selected word" at local [50,60) → Locator with charRangeStartUTF16=1050/End=1060 and quote="selected w".
  - `continuousModeNotificationDepsLocatorIsPassthrough` — chapter index nil → identical Locator to `LocatorFactory.txtRange` (same offsets, same quote).
  - `chapterModeNotificationDepsLocatorIsGlobal_addNotePath` — drive the **modifier's Add Note Sheet save closure** (same `deps.locatorFactory` seam at line 101-103) with chapter-local offsets and assert the produced `Locator.charRangeStartUTF16` equals global. This catches the round-2 finding that Add Note shares the seam.
  - (Optional) `modifierIntegrationTestChapterModeRoundTrip` through `ReaderNotificationHandlerTests.swift` if the modifier's `.onReceive` block is reachable as test fixture — drives `NotificationCenter.default.post(name: .readerHighlightRequested, object: TextSelectionInfo(start: 50, end: 60, ...))` and asserts the resulting persistence call carried a global-offset Locator.

**Acceptance bar**: bug #160 acceptance — long-press in war-and-peace.txt Chapter I → tap Highlight → yellow paint visible (WI-1 dependency) AND close + reopen → yellow paint re-renders at the same word in the same chapter (WI-3 makes the persisted Locator correct).

PR size: ~80 LOC production (closure rebuild + factory addition + isolation change) + ~140 LOC tests.

## Test catalogue (combined)

| Suite | File | Count | Purpose |
|---|---|---|---|
| Display translation | `TXTChapterHighlightRenderingTests.swift` (new) | 5 | WI-1 |
| Scroll translation + scrubber writer + bridge dedupe reset | `TXTChapterScrollOffsetTests.swift` (new) | 6 | WI-2 (parts 2a + 2b + 2c) |
| Factory variant | `LocatorFactoryTXTChapterTests.swift` (new) | 5 | WI-3 (locator unit — extracts, inverted, identity, neg-start, end-beyond) |
| Creation translation | `TXTChapterHighlightCreationTests.swift` (new) | 3 | WI-3 (closure unit — highlight path, continuous-mode passthrough, Add Note path) |
| Notification modifier (integration) | new method in `vreaderTests/Views/Reader/ReaderNotificationHandlerTests.swift` (file is singular per round-2 audit) | 1 | Post `.readerHighlightRequested` with `TextSelectionInfo(start: 50, end: 60)` to the modifier in chapter mode (currentChapterIdx=1, globalStart=1000) → assert resulting `Locator.charRangeStartUTF16 == 1050` after the modifier's `Task { ... }` completes (use `await Task.sleep(nanoseconds: 100_000_000)` only if no `XCTestExpectation` fulfillment surface exists; otherwise drive via persistence mock fulfilling). |
| Helper invariants | `TXTChapterHighlightHelperTests.swift` (existing) | 24 | Already passing |

**Regression check**: continuous-mode TXT highlighting (the no-chapter-marker fixture path) — both render and create paths must keep working. WI-1's `chapterModeNilHighlightWhenChapterIndexNil`, WI-2's `continuousModePassesScrollOffsetUntranslated`, and WI-3's `continuousModeNotificationDepsLocatorIsPassthrough` cover this.

## Risks + mitigations

| Risk | Likelihood | Mitigation |
|---|---|---|
| Chapter-boundary-straddling highlight only paints partial range | Medium | Acceptance: this is correct behavior — render only the in-chapter portion. Document in helper doc-comment + WI-1 test. |
| `viewModel.chapterIndex == nil` at render time | Medium | `highlightsForChapter` guards; returns empty. Continuous-mode path remains unchanged. |
| Bridge reports global offsets in chapter mode (future-bridge change) | Low | DEBUG assertion in the chapter-mode closure: input offsets in `[0, chapter.textLengthUTF16)`; in Release a leaked global to a non-zero chapter would produce an out-of-range Locator that `Locator.validated(...)` rejects (returns nil). Loud-fail in dev/test, silent-skip in Release. |
| Capture-time staleness (chapter change between user gesture and offset capture inside `locatorFactory` closure) | Medium | The closure reads `viewModel.isChapterMode` / `currentChapterIdx` / `currentChapterText` SYNCHRONOUSLY on the `@MainActor` thread that delivers `.readerHighlightRequested` (modifier line 48-53). Persistence latency cannot make the already-built locator stale because the locator is built BEFORE the `Task { await persistence.addHighlight(...) }` starts. The actual risk window is between the user's tap and the modifier's `onReceive` firing — sub-millisecond on a same-actor notification; not a credible chapter-swap window. (Round-1 audit noted plan v1 framed this incorrectly as a persistence-latency race; corrected here.) |
| Quote/context still wrong despite chapter-text source | Low | WI-3's `LocatorFactoryTXTChapterTests` directly assert quote == chapter-local substring + globals = chapter-translated. |
| Round-trip after close + reopen lands at wrong offset | Low (with all 3 WIs merged) | Acceptance criterion (b) directly tests close-reopen-restore in war-and-peace.txt. |
| TOC navigation pathway (modifier-line-46 `deps.onNavigate(global)` route) interaction with WI-2's `chapterLocalScrollOffset` derivation | Low | `onNavigate` triggers `viewModel.navigateToChapterByTitle` (which sets the new chapter) or `navigateToGlobalOffset`. After the chapter swap, the new render cycle's `chapterLocalScrollOffset` is computed against the new current chapter; the local-scroll happens after the chapter content is loaded. WI-2 test `chapterModeDropsScrollOffsetForOtherChapter` covers the stale-from-previous-chapter case. |
| MD container regression from `@MainActor` annotation change | Low | Mechanical annotation change; MD's `makeNotificationDeps` closure body already runs on `@MainActor`. Build the change locally; confirm no warnings. |

## Backward compatibility (revised from plan v1; expanded after round-2 for notes)

The locator-storage propagation surfaces are NOT export/import (those flatten quote/note/color, not offsets). Three propagation paths carry the wrong-coordinate locators **for both highlights AND notes** (notes share the same `locatorFactory` seam):

| Surface | File | Behavior |
|---|---|---|
| **Backup** | `vreader/Services/Backup/BackupDataCollector.swift:55, :68, :79` (`locatorJSON(...)` for highlights / bookmarks / annotations) | Full Locator JSON is emitted into the backup blob. Pre-WI-3 chapter-mode highlights AND notes stored with chapter-local-as-global offsets WILL round-trip through backup with the bug intact. |
| **CloudKit sync** | `vreader/Services/Sync/CloudKitRecordMapper.swift:69` | Same — Locator offsets propagate for highlights, notes, bookmarks. |
| **In-app navigation from saved annotations** | `ReaderNotificationModifier.swift:34` (`readerNavigateToLocator`) | Reading a saved highlight or note Locator + tapping "go to" navigates to the global offset stored on the Locator. Pre-WI-3 wrong-coordinate locators navigate to the wrong place. (Same code path; same handler.) |

**Decision: do NOT auto-migrate.** Justification:
- Affected highlights AND notes are from the pre-WI-7-era partial fix shipped in v3.14.119+; users with chapter-mode highlights or notes created during that window have wrong-coordinate locators.
- We can't reliably distinguish "chapter-N local stored as global" from "chapter-0 global" — both look like small integers.
- After WI-3, *new* highlights AND notes are correct. Existing wrong ones can be deleted + recreated by the user. **Recovery path**: the Highlights tab lists wrong-coordinate highlights by ID + selected text; the Notes/Annotations tab lists wrong-coordinate notes by ID + selected text + note content — both surfaces let the user identify and delete entries that navigate to the wrong place after this fix lands.
- A follow-up bug can ship a one-time migration if production volume warrants it (heuristic: any Locator whose `charRangeStartUTF16 < chapters[1].globalStartUTF16` AND whose `textQuote` does not match the substring at that global → flag for re-creation prompt).

**Backup data**: any pre-WI-7 backups taken from a chapter-mode-using device carry the bug; restoring them will produce wrong-coordinate locators on the restoring device. Acceptable — backups taken from buggy devices reproduce the bug; backups taken post-WI-3 from chapter-mode use are correct.

## Acceptance criteria (mirror of row, end-to-end)

(a) **Search-tap render** — Open Position Test Book → search "Paragraph 50" → tap result → reader scrolls to the chapter containing paragraph 50 → the matched range renders with `UIColor.systemYellow.withAlphaComponent(0.4)` for 3s before auto-clear. Driven by WI-1 + WI-2.

(b) **Gesture creation + persistence** — Open war-and-peace.txt → navigate to Chapter I → long-press a word → tap Highlight → yellow paint visible immediately AND Highlights tab shows the entry AND close (back chevron) + reopen the same book → yellow paint re-renders on the same word in Chapter I. Driven by WI-1 + WI-3 (and WI-2 for the restore-then-search sub-flow if exercised).

## Gate 5 verification plan

Per rule 47 Gate 5, each WI verifies its slice end-to-end before merge.

- **WI-1 slice verify**: seed war-and-peace, persist a highlight in chapter 1 (via DebugBridge or by gesturing then restarting), reopen, confirm yellow paint on the chapter-1 render. CU-driven on iPhone 17 Pro Sim.
- **WI-2 slice verify**: seed Position Test Book, search a term in chapter 2, tap result, confirm reader navigates AND yellow paint appears.
- **WI-3 slice verify** = final WI verification = full acceptance (a) + (b). Long-press in war-and-peace chapter 1, tap Highlight, snapshot `highlightCount` 0 → 1, close + reopen, snapshot stays at 1 AND visual paint re-renders.
- **Evidence file**: `dev-docs/verification/feature-48-YYYYMMDD.md` per `dev-docs/verification/SCHEMA.md`.

## Sequencing for this cron iteration

1. Plan v1 written.
2. Codex Gate 2 round 1 audit → `block` (4 High, 3 Medium, 1 Low).
3. Plan v2 written (this revision).
4. Gate 2 round 2 audit. Iterate up to 3 rounds.
5. If Gate 2 clean: write RED tests for WI-1, ship WI-1 PR, then stop. WI-2 + WI-3 are subsequent cron iterations.

## Revision history

### v3 → v4 (2026-05-12, after round-3 Codex audit)

Round-3 verdict was `revise` (downgraded from `block`). All 4 remaining findings (1 Medium, 3 Low) were clarifications rather than architecture blockers; applied inline:

| # | Severity | Round-3 finding | Resolution |
|---|---|---|---|
| 1 | Medium | `lastTextHash` was a duplicative new field; the bridge already computes a `sourceChanged`/`textChanged` signal in `updateUIView`. | WI-2c rewritten to reuse the existing `sourceChanged` branch; no new coordinator field. Test renamed `bridgeResetsScrollDedupeOnSourceTextChange` and asserts via the existing signal. |
| 2 | Low | "Top-level static helper" placement was ambiguous. | `chapterScrubberGlobalOffset` placement specified: `private static func` on `TXTReaderContainerView`, same shape as the existing `chunkIndex(for:in:)` at line 536. |
| 3 | Low | Test catalogue table stale relative to WI sections; modifier integration row left `TBD`. | Catalogue counts now match WI tests (5/6/5/3/1/24); modifier integration row made concrete with the `NotificationCenter.default.post(name: .readerHighlightRequested, ...)` shape. |
| 4 | Low | BC recovery prose said "Highlights tab" while the section now covers notes too. | Recovery path now names Highlights tab AND Notes/Annotations tab separately. |

**Plan is now clean for Gate 3 entry.** Round-3 explicitly: "the remaining findings are not architecture blockers. They can be fixed in the plan quickly, or handled during implementation if the audit log explicitly records [...]. If those are clarified, the plan is clean enough to proceed." — clarified.

### v2 → v3 (2026-05-12, after round-2 Codex audit)

| # | Severity | Round-2 finding | Resolution |
|---|---|---|---|
| 1 | High | WI-2 assumed `uiState.scrollToOffset` always written as global; but chapter-mode scrubber at `TXTReaderContainerView.swift:159-161` writes chapter-local today. v2 plan would have broken scrubber seeks (treating 150 as global, failing containment, dropping to nil). | WI-2 split into 3 parts: (2a) normalize scrubber writer to write global; (2b) translate global→local in chapter-render path with containment guard; (2c) bridge dedupe identity. All writers canonical-global; reads translate at the bridge edge. |
| 2 | High | Bridge dedupes `lastScrollToTarget: Int` only — chapter A local 50 == chapter B local 50 would dedupe-as-equal and skip the scroll on chapter swap. | Added Part 2c: coordinator gains `lastTextHash`; when text changes, `lastScrollToTarget` reset before dedupe check. Test `bridgeResetsScrollDedupeOnTextChange` added. |
| 3 | Medium | `txtChapterRange` contract underspecified — negative locals or locals beyond chapter text length would pass `extractContext` (which clamps) but produce Locators with offsets exceeding the chapter text reality. | `txtChapterRange` now validates bounds up front: returns nil on negative start, inverted range, or end > `chapterText.utf16.count`. Added 2 boundary tests. |
| 4 | Medium | WI-3's `locatorFactory` seam serves BOTH Highlight AND Add Note flows; v2 plan discussed only highlights. Chapter-mode notes affected by same bug. | WI-3 scope description now names Add Note explicitly. Test plan adds `chapterModeNotificationDepsLocatorIsGlobal_addNotePath` driving the modifier's Add Note Sheet save closure. BC section expanded to mention notes alongside highlights. |
| 5 | Low | Plan still referenced test path nits + had `TBD` for modifier integration test. | Test path corrected to `ReaderNotificationHandlerTests.swift` (singular). Modifier integration test made concrete (optional row in WI-3 test list with explicit `NotificationCenter.default.post(name: .readerHighlightRequested, ...)` shape). |

**Confirmed resolved from round 1**: `@MainActor` annotation change is safe; TTS scope-out does NOT create a chapter-0 regression (global == local at chapter 0, so behavior unchanged in ch0; ch1+ TTS remains broken on the orthogonal sentence-lookup axis, which is the TTS scope-out reason); 3-WI split is the right granularity after the round-2 reframe.

### v1 → v2 (2026-05-12, after round-1 Codex audit)

| # | Severity | Round-1 finding | Resolution |
|---|---|---|---|
| 1 | High | `scrollToOffset` translation missing from WI-1 | Created WI-2 dedicated to scroll translation; WI-1 narrowed to render-side translation only. |
| 2 | High | `LocatorFactory.txtRange` called with global offsets + chapter sourceText → wrong quote | Added new `LocatorFactory.txtChapterRange` variant that extracts quote/context in chapter-local space then constructs Locator with globals. WI-3 uses the new variant. |
| 3 | High | `locatorFactory: @Sendable` incompatible with capturing `@MainActor` viewModel | Change annotation to `@MainActor`. Mechanical one-line; verified all call sites already on main. Folded into WI-3. |
| 4 | High | TTS chapter-mode path also broken — coordinator writes `scrollToOffset` from sentence ranges, TTSService feeds globals; sentence lookup wrong coordinate space in non-zero chapters | Explicitly scoped OUT of #48. WI-2 partially mitigates (scroll now chapter-aware) but TTS source-text binding is a separate subsystem. Will file as follow-up bug if not already tracked. |
| 5 | Medium | 2-WI split underspecified — `onNavigate` reduces nav to `Int`, hides chapter state | Split into 3 WIs; WI-2 explicitly owns the navigation/scroll concern; closure layout for `makeNotificationDeps` redesigned in WI-3 to read viewModel state directly. |
| 6 | Medium | Concurrency risk misnamed in plan v1 — persistence latency cannot stale an already-built Locator | Rewrote the "capture-time staleness" risk row; persistence-latency framing dropped. |
| 7 | Medium | BC section named wrong consumers (Export/Import don't roundtrip offsets) | Rewrote BC section to name Backup (`BackupDataCollector`), CloudKit sync (`CloudKitRecordMapper`), and in-app navigation from saved annotations as the actual propagation surfaces. |
| 8 | Low | Plan named test file `ReaderNotificationHandlersTests.swift`; actual is `ReaderNotificationHandlerTests.swift`. `ReaderNotificationHandlers.swift` is 190 lines not 191. Live nav/highlight path duplicated in modifier rather than delegated to handlers. | Fixed references throughout. Plan now treats the modifier as the integration test surface (not the pure-handler helpers, which only matter for unit-level coverage). |
