---
branch: feat/132-wi7-pdf-azw3-hosts
threadId: manual-fallback
rounds: 1
final_verdict: ship-as-is
date: 2026-07-11
---

# Gate-4 audit — feature #132 WI-7-hosts (PDF + AZW3 reader hosts render the chrome scaffold)

## Auditor note

Codex (`scripts/run-codex.sh`, rule 53) returned `RUN-CODEX RESULT: FAILED` with
`ERROR: You've hit your usage limit … try again at 8:21 PM` (session
`019f5098-53e3-7982-87a1-ab47fe775a7c`, gpt-5.6-sol). Per rule-47 manual-fallback,
this is an evidence-bearing self-audit. No Codex ghost remained (`pgrep -x codex`
= 0).

## Scope

Diff `origin/main..HEAD` (one commit, `d8cc04fa`): 3 modified sources
(`PdfReaderActivity.kt`, `PdfReaderScreen.kt`, `Azw3ReaderActivity.kt`), 3 new
tests (`PdfReaderChromeUiTest.kt`, `Azw3ReaderChromeUiTest.kt` androidTest;
`PdfAnnotationPageTest.kt` JVM). No file outside the declared write-set touched;
main checkout clean.

## Files read (for signature/symbol verification)

- `reader/TxtReaderActivity.kt` (WI-6 template — extracted `TxtReaderChrome`,
  `annotationsShareText`, `shareAnnotations`, `produceState` snapshot pattern)
- `reader/chrome/ReaderChromeScaffold.kt` (slot signature `bottomChrome:
  (onOpenContents?, onOpenNotes?) -> Unit`; empty `tocEntries` ⇒ null Contents
  callback; center-tap toggle; `AnnotationsReviewSheet(onJumpToAnnotation)` route)
- `reader/chrome/ReaderChromeState.kt` (`ReaderChromeState`, `ReaderChromeStateSaver`)
- `reader/chrome/ReaderBottomChrome.kt` + `ReaderTopChrome.kt` (designed toolbar +
  `chrome-notes`/`reader-top-chrome` testTags; toolbar = conditional per-callback
  Contents·Notes·Display·AI)
- `annotations/AnnotationsRepository.kt` (`annotationsForBook(bookKey):
  AnnotationsSnapshot`, suspend)
- `annotations/AnnotationsReviewSheet.kt` + `AnnotationCards.kt` (null
  `onJumpToAnnotation` ⇒ `onClick == null` ⇒ card non-clickable; testTag
  `annot-card-${id}`, `annot-empty`, `annotations-sheet`)
- `annotations/AnnotationItem.kt` (`.locator`, `.id`), `Annotation.kt`
  (`HighlightRecord`/`NoteRecord`)
- `reader/PdfReaderScreen.kt` + `PdfReaderActivity.kt` (page-scroll seam =
  `listState.scrollToItem`; `pdfBackdrop()` theme-only; #129 PDF = NO Display)
- `reader/Azw3ReaderActivity.kt` + `Azw3DisplayCss.kt` (MATCH_PARENT WebView bug
  #357; foliate `setStyles` CSS applied live from store; no Display control surface)
- `identity/.../Locator.kt` (`page: Int? = null`), `AnnotationScrollOffsetTest.kt`
  + `AnnotationsReviewSheetTest.kt` (`assertHasNoClickAction` precedent) +
  `TxtReaderChromeUiTest.kt` (scaffold-hosted review-sheet reachable via
  `createComposeRule` + `useUnmergedTree`)

## Findings by focus area

1. **Both hosts render `ReaderChromeScaffold` like WI-6.** `PdfReaderChrome` /
   `Azw3ReaderChrome` are extracted `internal` composables mirroring
   `TxtReaderChrome` exactly: `systemBarsPadding()` Column → `ReaderChromeScaffold`
   with `tocEntries = emptyList()` (Contents hidden), `onJumpToc = { false }`
   (unreachable), Search/More/bookmark null, `bottomChrome` slot rendering a
   Notes-only bar. **PDF `onJumpToAnnotation` NON-null** → `listState.scrollToItem(
   pdfAnnotationPage(item, pageCount))` on the existing page-scroll seam.
   **AZW3 `onJumpToAnnotation` NULL** (hardcoded in `Azw3ReaderChrome`; no param) →
   the card is non-clickable (verified: `AnnotationCards` `onClick =
   onJump?.let{…}`). PASS.

2. **FoliateBridge/Azw3Document/foliate-js UNTOUCHED; WebView sizing undisturbed.**
   The diff does not touch `FoliateBridge`, `Azw3Document`, or the JS bundle. The
   `WebView(context){ layoutParams = MATCH_PARENT,MATCH_PARENT }` block (bug #357)
   is byte-identical; `AndroidView(factory){ holder.webView }.fillMaxSize()` +
   the prev/reserved-centre/next `TapZone` Row are unchanged. Only the enclosing
   `ReaderScaffold(...)` wrapper was removed from `Azw3ReaderHost` (the shared
   scaffold now owns the top bar); the body Box is otherwise identical. PASS.

3. **#129 Display affordance preserved; Contents hidden; Notes → review sheet;
   share → ACTION_SEND.** PDF still gates on the store's first emission and threads
   `settings.pdfBackdrop()` to `PdfReaderBody` (theme-only, NO Display control —
   the bottom chrome omits Display). AZW3 still collects the store live and applies
   `foliateDisplayCss()` via `setStyles` on every change (`LaunchedEffect(holder,
   displaySettings)` untouched); its bottom chrome omits Display too. Both hosts'
   Notes → `AnnotationsReviewSheet` over `annotationsForBook(bookKey)`;
   `onShareAnnotations` → `annotationsShareText` → `ACTION_SEND` chooser (reusing
   the WI-6 shared formatter). Contents hidden via empty `tocEntries`. PASS.

4. **No reading-surface regression; no dead controls; rule-51 fidelity.** PDF page
   list + "Page N of M" pill preserved in `PdfReaderBody`; AZW3 WebView + tap zones
   preserved. Bottom chrome renders ONLY the Notes control (the design's toolbar is
   a conditional per-callback set Contents·Notes·Display·AI; a host that supports
   only Notes shows only Notes — same icon-above-label treatment + `chrome-notes`
   testTag as `ReaderBottomChrome`'s Notes slot). No invented surface. PASS.

5. **Lifecycle/coroutine correctness.** `rememberSaveable(bookKey, stateSaver =
   ReaderChromeStateSaver)` persists chrome across rotation/process death;
   `produceState(…, bookKey)` reads the snapshot off-main (repo suspend fn) with
   `runCatching{…}.getOrDefault(empty)` (no crash on read failure);
   `rememberCoroutineScope()` (PDF jump) is composition-scoped and only launches a
   non-suspending `scrollToItem`. Position-save channels, `onStop`/`onDestroy`
   flush, and the WebView reload/render-death paths are untouched. PASS.

## Edge cases checked

- Empty snapshot → `annot-empty` empty state (tested, PDF + AZW3).
- 0-page PDF → `PdfUiState.Empty` never reaches `PdfReaderChrome` (bare
  `PdfScaffold` message); `pdfAnnotationPage(item, pageCount = 0)` clamps to 0
  (JVM-tested).
- Page past end / negative / null page → clamp to last / 0 / 0 (JVM-tested).
- AZW3 null tap-to-jump → card non-clickable (`assertHasNoClickAction`,
  precedented by `AnnotationsReviewSheetTest`).
- Empty/blank share text → `shareAnnotations` no-ops (no empty intent).
- CJK/long text → passes through unchanged (rendered by the review sheet cards).

## Risks accepted (Low / informational)

- **One-shot annotations snapshot (keyed on `bookKey` only, not a live Flow).**
  WI-6's TXT host re-keys on the live `highlightsList` because TXT/MD support
  in-session highlight creation. Neither PDF (no text selection) nor AZW3 (foliate
  selection deferred to a future WI — see the tap-zone comment) can create an
  annotation in-session today, so the snapshot cannot go stale during a session.
  A one-shot read is correct for these hosts and avoids an unnecessary Flow
  collector. Accepted; revisit when AZW3 selection lands.

## Tests

- New: `PdfReaderChromeUiTest` (top bar + Notes bottom chrome, no Contents/Display;
  Notes → review sheet lists this book's annotations; card tap invokes jump with
  the page-bearing item; empty → empty state; center-tap toggles chrome),
  `Azw3ReaderChromeUiTest` (same + the AZW3 card-non-clickable capability gate),
  `PdfAnnotationPageTest` (JVM, 6 clamp cases).
- Gate: `:app:compileDebugKotlin :app:compileDebugAndroidTestKotlin
  :app:testDebugUnitTest --tests '*PdfAnnotationPageTest*'` →
  `RUN-ANDROID-TESTS RESULT: SUCCEEDED`. The live Compose/full-Activity render
  rides WI-9 acceptance (per the plan).

## Verdict

**ship-as-is.** Zero Critical/High/Medium findings; one accepted Low
(informational one-shot-snapshot note). The change faithfully mirrors WI-6,
respects the AZW3 no-goTo constraint (#135), leaves the foliate stack + bug-#357
sizing untouched, and preserves each host's #129 Display affordance.
