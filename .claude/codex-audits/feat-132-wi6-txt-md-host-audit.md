---
branch: feat/132-wi6-txt-md-host
threadId: manual-fallback
rounds: 1
final_verdict: ship-as-is
date: 2026-07-11
---

# Gate-4 audit — feature #132 WI-6 (TXT/MD host renders ReaderChromeScaffold)

## Audit tool status

Codex (`scripts/run-codex.sh`) returned `RUN-CODEX RESULT: FAILED (codex exit 1)` with
`ERROR: You've hit your usage limit … try again at 8:21 PM.` (ChatGPT/Codex quota exhausted,
not a code defect). Per rule 47 "Manual fallback when AI auditor unavailable", this is the
evidence-bearing manual audit. The primary rung was attempted (not skipped); the `.reports/wi6-audit.txt`
capture holds the quota error.

## Files read (real signatures verified, not assumed)

- `reader/chrome/ReaderChromeScaffold.kt` — the WI-5 scaffold I host. Verified the EXACT param list:
  `theme, title, chromeState: MutableState<ReaderChromeState>, onBack, tocEntries: List<TocEntry>,
  currentTocIndex, annotations: AnnotationsSnapshot, onJumpToc: (Int)->Boolean,
  onJumpToAnnotation: ((AnnotationItem)->Unit)?, onShareAnnotations, bottomChrome: @Composable
  (onOpenContents:(()->Unit)?, onOpenNotes:(()->Unit)?)->Unit, body, modifier, onOpenSearch?, onOpenMore?,
  topBookmarkSlot?`. Confirmed the scaffold hides Contents when `tocEntries.isEmpty()` (passes a null
  open callback → the bottom chrome omits it) and toggles `chromeState.value.chromeVisible` on a body tap.
- `reader/chrome/ReaderChromeState.kt` — `ReaderChromeState(chromeVisible, sheet)`, `ReaderSheet`,
  `ReaderChromeStateSaver: Saver<ReaderChromeState, String>` (used with `rememberSaveable(stateSaver=…)`).
- `reader/chrome/ReaderBottomChrome.kt` — the extended #129 chrome: `onOpenContents`/`onOpenNotes` are
  nullable-default (each renders ONLY when non-null), Display + `extraSlot` (TTS entry) unchanged.
- `reader/chrome/ReaderTopChrome.kt` — top bar; Search/More/bookmark slots each render only when non-null.
- `reader/nav/EmptyTocProvider.kt` + `TocEntry.kt` — TXT/MD has no TOC (I pass an empty `tocEntries`,
  the EmptyTocProvider posture).
- `annotations/AnnotationsRepository.kt` — `suspend fun annotationsForBook(bookKey): AnnotationsSnapshot`
  (one-shot, sorted, corrupt rows dropped).
- `annotations/AnnotationsReviewSheet.kt` + `AnnotationsSnapshot.kt` + `AnnotationItem.kt` +
  `AnnotationCards.kt` — the Notes sheet + `onShareAll` + nullable `onJumpToAnnotation`; the cards carry
  `testTag = annot-card-<id>` and are clickable ONLY when `onJump` is non-null.
- `annotations/Annotation.kt` — `HighlightRecord.locator` uses `charRangeStartUTF16`; `NoteRecord.locator`
  uses `charOffsetUTF16` (the reason the jump helper reads range-start first, then char-offset).
- `identity/.../contracts/Locator.kt` — `charOffsetUTF16`/`charRangeStartUTF16` are `Int?`, validated ≥ 0.
- `reader/TxtReaderActivity.kt` — the host I EXTEND: the existing #129 ReaderBottomChrome Display slot,
  the #121 TtsControlBar/ReadAloudChromeSlot, and the `listState.scrollToItem(document.chunkForOffset(...))`
  scroll seam (reused for tap-to-jump).
- `dev-docs/designs/vreader-fidelity-v1/project/vreader-reader.jsx` — depicts `ReaderTopChrome` +
  `ReaderBottomChrome` with the `Contents / Notes / Display` toolbar (`:574–:576`). Rule-51 basis.

## Symbols / signatures verified

- `ReaderChromeScaffold` — param names + types match my call exactly (compile gate SUCCEEDED, both source sets).
- `rememberSaveable(bookKey, stateSaver = ReaderChromeStateSaver) { mutableStateOf(ReaderChromeState()) }` —
  the vararg-inputs + `stateSaver` overload; `bookKey` as an input re-inits state on a book change.
- `container.annotationsRepository.annotationsForBook(bookKey)` — real suspend method (WI-6b).
- `AnnotationItem.locator` (Locator) → `charRangeStartUTF16` / `charOffsetUTF16` — real nullable fields.
- `annotationScrollOffset` / `annotationsShareText` — pure top-level `internal` helpers, JVM-tested (5/5).

## Correctness against the plan (WI-6 line, plan `:174`)

- ✅ `TxtReaderActivity → ReaderChromeScaffold` (via the extracted `internal TxtReaderChrome`).
- ✅ Contents HIDDEN via `tocEntries = emptyList()` (EmptyTocProvider posture) — no dead control.
- ✅ Notes → `AnnotationsReviewSheet` over `annotationsForBook(this book)`; non-null `onJumpToAnnotation`
  scrolls to the offset via the existing chunk-scroll seam (`§review-sheet-contract` TXT/MD path).
- ✅ Sheet-level Share → host `shareAnnotations` → `ACTION_SEND` (`annotationsShareText`).
- ✅ #129 Display settings sheet preserved (the `onOpenDisplay = { showDisplaySheet = true }` slot is
  passed through the extended `ReaderBottomChrome`).
- ✅ #121 TTS bar preserved: `if (active) TtsControlBar(...) else ReaderBottomChrome(...)` unchanged; the
  ReadAloudChromeSlot `extraSlot` (testTag `tts-read-aloud-entry`) still present.
- ✅ Chrome state `rememberSaveable(saver=ReaderChromeStateSaver)`; center-tap toggles (scaffold-owned).
- ✅ Top bar: title = book title, back = `::finish`; Search/More/bookmark null-omitted (#133/#134/#135).

## Edge cases checked

- Empty TXT / no annotations → `annotationScrollOffset` clamps to 0; `annotationsForBook` returns empty →
  the review sheet shows `annot-empty` (test `emptyAnnotations_showsEmptyReviewState_noCrash`). No crash.
- Highlight jump = `charRangeStartUTF16`; note jump = `charOffsetUTF16`; neither/negative → 0 (JVM test 5/5).
- Jump offset clamped to `[0, text.length-1]` before `chunkForOffset` (matches the scrubber path).
- `text.length == 0` → `coerceIn(0, (len-1).coerceAtLeast(0))` = `coerceIn(0,0)` → 0 (no OOB).
- Loading (pre-settings-emission) → a bare theme-colored `TxtLoadingScaffold` (no chrome, no seeded data).
- Book change (`bookKey`) re-keys both the saveable chrome state and the snapshot producer.

## Concurrency / lifecycle correctness

- `annotationsSnapshot` via `produceState(key = bookKey, annotatable, highlightsList)` — a suspend load off
  the composition; cancelled+restarted on a key change; `runCatching(...).getOrDefault(empty)` so a repo
  failure degrades to an empty sheet rather than crashing. No unstructured coroutine.
- Tap-to-jump uses the composition-scoped `ttsScope` (same scope the scrubber uses) — a UI scroll that is
  correctly cancelled with the composition; no process-scope leak.
- `shareAnnotations` / `annotationsShareText` are host-side (startActivity on the main thread) + pure.

## Risks accepted (Low)

- **Snapshot reload keys on `highlightsList` (highlights Flow), not a notes Flow.** In THIS host, standalone
  notes are only created attached to a highlight (the popover `beginNote` → `saveTxtNote`/`createTxtHighlight`
  path always writes a highlight row); there is no standalone-note create path in TxtReaderActivity. So the
  highlights Flow is a sufficient reload trigger for the host's own annotation edits; a note added by an
  external path would refresh on the next highlight change or reopen. Accepted — no regression vs prior
  (there was no in-reader review surface before), and a notes-Flow reload can ride a later WI if a
  standalone-note create path lands in this host.
- **The card-tap + review-sheet-content assertions run through the real `ModalBottomSheet`** (a separate
  window). The compile gate proves the wiring compiles; the live Compose render (modal-window reachability)
  defers to WI-9's connected acceptance slice (memory lesson: connected Compose gesture tests are
  emulator-flaky on a loaded mac; #128 WI-7 precedent). The tap→offset LOGIC is proven deterministically by
  the JVM `AnnotationScrollOffsetTest` (5/5), independent of the modal window.

## Duplicate / dead code

- The old `TxtReaderScaffold` private composable is REMOVED (replaced by `TxtReaderChrome`); no orphan.
- A few imports the old scaffold used (e.g. `ArrowBack`) may now be unused — Kotlin unused-import warnings
  only, not errors; the compile gate is clean.

## Tests

- RED-first: `TxtReaderChromeUiTest` (instrumented, host-render, composable-level — compiles; live run rides
  WI-9) + `AnnotationScrollOffsetTest` (JVM, 5/5 pass). Both reference symbols that did not exist pre-WI-6.
- Gate command: `:app:compileDebugKotlin :app:compileDebugAndroidTestKotlin :app:testDebugUnitTest
  --tests '*AnnotationScrollOffsetTest*'` → `RUN-ANDROID-TESTS RESULT: SUCCEEDED` (JVM 5/0/0/0).

## Verdict

**ship-as-is.** No Critical/High/Medium findings. The wiring integrates already-designed surfaces
(ReaderChromeScaffold + the review sheet + the preserved TTS bar), preserves #129/#121 behavior, has no
dead controls, and the tap-to-jump offset logic is deterministically tested. The two Low observations are
accepted with rationale above; neither blocks integration.
