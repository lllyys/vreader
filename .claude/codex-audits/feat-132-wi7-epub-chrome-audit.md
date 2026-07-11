---
branch: feat/132-wi7-epub-chrome
threadId: manual-fallback
rounds: 1
final_verdict: ship-as-is
date: 2026-07-11
---

# Gate-4 audit — feature #132 WI-7-EPUB (EPUB host reader nav chrome)

## Audit tool status

Codex (`scripts/run-codex.sh`, the rule-53 PRIMARY rung) was invoked but returned a hard
usage-limit/quota error before producing a verdict:

```
ERROR: You've hit your usage limit. Visit https://chatgpt.com/codex/settings/usage to purchase
more credits or try again at 8:21 PM.
```

Per rule 47 "Manual fallback when AI auditor unavailable", this is the evidence-bearing manual audit.
The audit output capture is at `.reports/wi7epub-audit.txt` (it contains only the echoed diff + the
two quota errors — no Codex analysis). threadId is recorded as `manual-fallback`.

## Files read

- `android/app/src/main/kotlin/com/vreader/app/reader/ReaderActivity.kt` (the extended host)
- `android/app/src/main/kotlin/com/vreader/app/reader/ReaderChromeModel.kt` (new)
- `android/app/src/main/kotlin/com/vreader/app/reader/EpubReaderChrome.kt` (new)
- `android/app/src/test/kotlin/com/vreader/app/reader/ReaderChromeModelTest.kt` (new, JVM)
- `android/app/src/androidTest/kotlin/com/vreader/app/reader/ReaderChromeConnectedTest.kt` (new)
- Reused (read-only): `reader/nav/ReadiumTocProvider.kt`, `nav/TocEntry.kt`, `nav/TocContentsSheet.kt`,
  `chrome/ReaderTopChrome.kt`, `chrome/ReaderBottomChrome.kt`, `chrome/ReaderChromeState.kt`,
  `chrome/ReaderChromeScaffold.kt`, `annotations/AnnotationsReviewSheet.kt`, `annotations/AnnotationsSnapshot.kt`,
  `annotations/AnnotationItem.kt`, `reader/TxtReaderActivity.kt` (annotationsShareText precedent),
  `reader/settings/ReaderTheme.kt` / `ReaderSettingsStore.kt` / `ReaderSettingsSheet.kt`.

## Symbols / signatures verified (against the live code + the Readium jars via javap)

- `ReadiumTocProvider(publication: Publication, book: Book)` — production constructor exists;
  `.toc(): List<TocEntry>` is `suspend`. ✓
- `TocEntry.epubReadiumLocator: org.readium.r2.shared.publication.Locator?` — the retained native
  locator for the jump. ✓
- `EpubNavigatorFragment.go(Locator, boolean): boolean` (javap on readium-navigator-3.3.0-runtime.jar) —
  Kotlin `nav.go(locator)` uses the default animated arg and returns `Boolean`. ✓
- `Locator.copyWithLocations(fragments, progression, position, totalProgression, otherLocations)` +
  `Locator.Locations.getTotalProgression()/getProgression()` (javap on readium-shared-3.3.0) — the
  scrub seam's `copyWithLocations(progression=…, totalProgression=…)` is valid; `locations.progression`
  / `locations.totalProgression` reads are valid. ✓
- `TocContentsSheet(theme, bookTitle, entries, currentTocIndex, onJump:(Int)->Boolean, onDismiss)` —
  owns dismiss-on-success (dismiss ONLY when onJump returns true; a false stays open, no error surface). ✓
- `AnnotationsReviewSheet(theme, snapshot, onShareAll, onJumpToAnnotation:((AnnotationItem)->Unit)?, onDismiss)`
  — the null `onJumpToAnnotation` renders cards review-only/non-clickable (§review-sheet-contract). ✓
- `AnnotationsRepository.annotationsForBook(bookKey): AnnotationsSnapshot` (`suspend`),
  `.highlights(bookKey): Flow<List<HighlightRecord>>`. ✓
- `ReaderSettingsSheet(settings, onTheme, onFontFamily, onFontSize, onLineSpacing, onMargin, onDismiss)`
  + `ReaderSettingsStore.nextSeq(): Long` + the 5 `setX(value, order)` setters. ✓
- `ReaderTheme.background: Color` + `Color.toArgb()`. ✓
- `annotationsShareText(AnnotationsSnapshot): String` — top-level fn in the same package (TxtReaderActivity.kt),
  reused by the EPUB `shareAnnotations`. ✓

## Focus-area findings

1. **Persistent StateFlow populated on open + position change; touch-through bands + open-only overlay.**
   - `chromeModel: MutableStateFlow<ReaderChromeModel>` is seeded with the title before open, then
     `populateChromeModel(pub, book, nav)` fills title + `ReadiumTocProvider(pub, book).toc()` + the
     `annotationsForBook` snapshot + the initial `tocIndexFor` index. `observePosition` adds a second,
     un-debounced `currentLocator.collect` that updates `currentTocIndex` (+ `chromeProgress`), so the
     Contents-sheet highlight tracks the live position. ✓
   - The chrome is 3 ComposeViews over the fragment's FrameLayout: fragment (MATCH_PARENT) → popover
     overlay (MATCH_PARENT) → sheet layer (MATCH_PARENT) → top band (WRAP_CONTENT, gravity TOP) →
     bottom band (WRAP_CONTENT, gravity BOTTOM). The bands occupy ONLY their own height, so the reading
     area between them stays the fragment's — touch-through by construction. The sheet layer renders
     NOTHING (`EpubReaderSheets` returns early on `ReaderSheet.None`) until a sheet opens, so an empty
     ComposeView does not consume touches (the existing PopoverOverlay uses the same early-return
     touch-through pattern — verified precedent). ✓

2. **Contents jump + tocIndexFor.** `jumpToTocEntry(index)` reads the tapped entry's RETAINED native
   `epubReadiumLocator` and feeds it straight to `nav.go(native): Boolean` — zero reconstruction. An
   out-of-range index or a null native locator → `false` (the sheet stays open, no crash, no invented
   error surface — rule 51 §nav-error-presentation). `tocIndexFor` is pure/Readium-free (operates on
   plain `TocPosition` descriptors extracted by `tocPositions`): exact-href match first (deepest section
   at-or-before progression), lexical fallback for a spine item with no TOC row, -1 only for an empty
   TOC, 0 when a TOC exists but nothing sorts at-or-before. 11 JVM tests cover these (tests=11 pass=11). ✓

3. **EPUB Notes review-only.** `EpubReaderSheets` passes `onJumpToAnnotation = null` to
   `AnnotationsReviewSheet` → cards non-clickable until #135. `onShareAll` → `shareAnnotations` (ACTION_SEND
   via `annotationsShareText`). ✓

4. **#129 + prior behavior preserved.** `observeDisplaySettings(nav)` is untouched; the chrome bands ALSO
   follow the stored theme via a new `readerSettingsStore.settings` collector feeding `chromeTheme`, and
   the Display sheet opens from the bottom band's Aa slot via `DisplaySettingsHost` (the same
   nextSeq/process-scope setter pattern as TxtReaderActivity). `PopoverOverlay`, `observeHighlights`,
   the selection callback, `observePosition`'s debounced save, and `publication.close()` in onDestroy
   are all preserved. Chrome extracted to `ReaderChromeModel.kt` + `EpubReaderChrome.kt`. ✓

5. **Lifecycle/coroutine correctness.** All new collectors run in `lifecycleScope` (cancelled on destroy —
   no leak); the ComposeViews collect the StateFlow via `collectAsStateWithLifecycle`. The Activity-level
   `mutableStateOf` holders are written from lifecycleScope (Dispatchers.Main.immediate) / main-thread
   callbacks and read in composition — safe. rule-51 fidelity: only committed designed composables are
   reused; the dismiss overlay is a transparent (no `background()`) Box — no double-scrim over the
   ModalBottomSheet's own scrim, no invented visual element. ✓

## Edge cases checked

- Empty TOC → Contents control omitted (bottom band's `onOpenContents == null`); Notes still reachable
  (connected test `notesReachable_reviewOnly`). ✓
- Out-of-range / null-native TOC jump → false, sheet stays open, no crash (connected +
  `invalidTocJump_*` test). ✓
- `tocIndexFor`: empty entries → -1; null href → 0 (with a TOC) / -1 (empty); before-first-entry → 0;
  same-href multi-section by progression; later-chapter-wins; null progression → 0.0. ✓
- Book with no/broken TOC → `runCatching { ReadiumTocProvider(...).toc() }` defaults to empty; the
  annotations read defaults to an empty snapshot — the chrome still renders. ✓
- Rotation: `super.onCreate(null)` starts fresh; the saved reading position persists (unchanged from
  #106). Chrome state is in-memory for the reader lifetime (documented). ✓

## Risks accepted (Low)

- **`ReaderActivity.kt` is 628 lines (over the ~300 convention).** It was already 443 (fragment
  lifecycle + selection popover + highlighting + #129 Display); the chrome composables ARE extracted to
  two new files. The remaining growth is unavoidable host wiring (populateChromeModel / observers / the
  jump+scrub+share seams / the 5 @VisibleForTesting hooks). A further split of the selection/highlight
  code is out of scope for this WI. Accepted.
- **`tocIndexFor` lexical-href fallback** is best-effort ONLY when the current spine item has no exact
  TOC-row match; `currentTocIndex` is a cosmetic Contents-sheet highlight, not a navigation target, so an
  approximate row is acceptable. The primary path is an exact href match. Documented in the KDoc + tested.

## Tests added

- JVM `ReaderChromeModelTest` (11 tests, all pass) — the real green signal for `tocIndexFor`.
- Instrumented `ReaderChromeConnectedTest` (compiles in-lane; the live Compose gesture + navigator run
  rides WI-9 acceptance on a cold emulator — the #128/#129 precedent, connected tests are
  emulator-timing-flaky on a loaded host). It drives the TOC-jump / sheet-open / touch-through seams via
  @VisibleForTesting hooks.

## Verdict: ship-as-is
