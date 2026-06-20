# Feature #115 — Android PDF reader (base page-view)

Status: Gate-2 audited (2026-06-20, Codex round 1 → revised; see Revision history). The fourth reader capability under the #110 Android Phase-3
driver (EPUB ✓ → TXT ✓ → MD ✓ → **PDF**), implementing the committed design
`dev-docs/designs/vreader-fidelity-v1/project/vreader-pdf-reader.jsx` + `design-notes/
android-phase3-issues.md` (#1766, landed in #1771).

## Problem

The Android app reads EPUB/TXT/MD; `pdf` currently routes to a "not available yet" toast. iOS
reads PDF via PDFKit's `PDFView` (a system component). Android's `android.graphics.pdf
.PdfRenderer` hands back one **Bitmap per page** — so the page-display + navigation UI must be
built. Bring **PDF reading** to Android: import a `.pdf` → Library → open in the designed
**continuous-scroll** reader (the canonical layout) with the shared chrome → pages render as
bitmaps on a neutral viewer backdrop → a floating "Page N of M" pill → resume by page index.

## Decision: continuous vertical scroll (canonical), per the design

The design note's #1766 decision is **continuous vertical scroll is canonical** (matches every
mainstream Android PDF surface; keeps figures + captions legible), with paged single-page as a
secondary Display-panel toggle. v1 implements the **canonical continuous-scroll path only**;
the paged-mode toggle is an explicit follow-on (out of scope below).

## Platform constraints (stock `PdfRenderer`) — scoping decisions

- **Encrypted PDFs (Gate-2 Medium — corrected)**: the legacy `PdfRenderer(fileDescriptor)`
  constructor (API 21+) throws `SecurityException` when a password is required and has **no
  password API**; API 35+ adds `PdfRenderer(fd, LoadParams)` with a password — but **minSdk 26**
  means a stock-only unlock flow is **not available across all supported devices**, so v1 does
  not implement unlock. Also, `SecurityException` can mean an **unsupported security scheme**,
  not only "password-protected" (Gate-2 Medium). So v1 **detects** the protected case as a
  `ProtectedOrUnsupported` result and shows a terminal "this PDF is protected or uses an
  unsupported security scheme" state; the design's full password-field-+-Unlock flow is a
  **deferred follow-on** (it's already DESIGNED in `vreader-pdf-reader.jsx` — `PdfEncrypted` —
  so resuming it later is implement-the-design, not invent-UI; it's deferred on the platform/API
  constraint, not rule 51). The detection + a clear message is shipped now.
- **Large-PDF bitmap memory (Gate-2 High)**: a 600-page PDF can't hold every page bitmap in
  memory. v1 renders page bitmaps **lazily per visible item** in a `LazyColumn`. Each page
  composable **owns exactly one `Bitmap`** and **recycles it** on disposal / width-change
  replacement (a `DisposableEffect`); if a render completes after its coroutine was cancelled,
  the late bitmap is **recycled, not published**; stable item `key = pageIndex`; **never render
  at width 0** (skip until the measured width is > 0).
- **`PdfRenderer` lifecycle: not thread-safe, single-page-open, close-must-not-race (Gate-2
  High)**: only one `Page` may be open at a time; `PdfRenderer.close()` throws if a page is
  open, and a `close()` racing an in-flight render corrupts the renderer. v1 serializes
  **`renderPage` AND `close`** through the **same `Mutex`** on an IO dispatcher; every
  `openPage()` is paired with `Page.close()` in `finally`; the document is closed from the
  reader's `DisposableEffect` / `onDestroy` (so a render in flight when the Activity leaves
  composition completes-or-cancels before close acquires the mutex).

## Surface area

All new, under `android/app/.../reader/`:

- **`PdfDocument.kt`** — a `PdfRenderer` wrapper: `open(File): PdfOpenResult`
  (`Ok(doc)` / `ProtectedOrUnsupported` / `Corrupt`), `pageCount` (≥ 0), `suspend
  renderPage(index, targetWidthPx): Bitmap` and `suspend close()` — **both serialized through
  ONE `Mutex`** on an IO dispatcher; `renderPage` opens the `Page`, renders, and closes it in
  `finally`. Opens via `ParcelFileDescriptor.open(file, MODE_READ_ONLY)`; maps
  `SecurityException`→`ProtectedOrUnsupported`, `IOException`/`IllegalArgumentException`→`Corrupt`
  (Gate-2 Low), any unexpected exception logged + treated as `Corrupt`.
- **`PdfReaderActivity.kt`** — Compose `ComponentActivity`: `produceState` opens the doc off the
  main thread → `Loading` / `ProtectedOrUnsupported` / `Corrupt` / `Empty` (pageCount == 0,
  Gate-2 Low) / `Loaded`. `Loaded` renders a `LazyColumn` of page items (each lazily renders its
  one bitmap via `produceState` keyed on page index + measured width, with the recycle-on-dispose
  discipline above), on the neutral viewer backdrop; a floating "Page N of M" pill bound to
  `firstVisibleItemIndex`; the shared reader chrome (back "Library" + serif title + "PDF" tag).
  The `PdfDocument` is closed in a `DisposableEffect`/`onDestroy` (serialized via its mutex).
  Resume: save the top-visible **page index** as a LEGACY `VReaderLocator.wrapLegacy(Locator(
  page=...))` (same conflated-channel + save pattern as `TxtReaderActivity`); restore via
  `ResumeResolver → Canonical → page`, **clamped to `0 until pageCount`** (Gate-2), →
  `rememberLazyListState(initialFirstVisibleItemIndex=clampedPage)`.
- **`VReaderApp.kt`** — add a **PDF-specific page cache** `cachePage(key, page)` / `cachedPage(
  key): Int?` (Gate-2 Medium — do NOT store page indices through the char-offset-named
  `cacheOffset`/`cachedOffset` API; a separate typed cache keeps the semantics honest).
- **`MainActivity.kt`** — route `BookFormat.pdf` → `PdfReaderActivity` (the exhaustive `when`:
  epub→Readium, txt/md→text reader, **pdf→PdfReaderActivity**, azw3→"not available yet").
- **`AndroidManifest.xml`** — register `PdfReaderActivity`.

**Files OUT of scope** (explicit follow-ons): the **paged-mode** Display toggle; the
**encrypted-unlock** password flow (needs a password-capable PDF lib); the **page-jump**
thumbnail/scrubber overlay (the "Pages" toolbar item — a navigation enhancement, not core
read); selection / translation / bilingual on PDF; AZW3. (Page-jump + paged + encrypted-unlock
each get a follow-on feature row if/when prioritized.)

## Prior art / project precedent / rejected alternatives

- **Precedent**: `TxtReaderActivity` (Compose `ComponentActivity` + the cream scaffold + the
  conflated-channel save + in-memory offset cache + legacy-locator resume) is the direct
  template — PDF reuses the resume machinery with `page` swapped for `charOffsetUTF16`.
  `MarkdownRenderer`/`TxtDocument` showed the decode→document→render→resume→route shape.
- **Design source**: `vreader-pdf-reader.jsx` (`PdfContinuousReader`, `PdfPaper`, the chrome,
  `PdfRendering`/`PdfCorrupt`/`PdfEncrypted` state surfaces) + the design note.
- **Rejected — bundling PdfiumAndroid for encrypted/paged in v1**: a 3rd-party native lib is a
  large dep + ADR-scope decision; stock `PdfRenderer` covers the canonical unencrypted read.
  Encrypted-unlock + the richer paged mode are follow-ons.
- **Rejected — rendering all pages eagerly**: OOM on large PDFs; lazy per-visible-item render is
  the standard approach.
- **Rejected — paged-first**: the design's canonical layout is continuous-scroll.

## Work items

| WI | Scope | Tier |
|---|---|---|
| WI-1 | `PdfDocument` (`PdfRenderer` wrapper: open → `Ok`/`ProtectedOrUnsupported`/`Corrupt`; `pageCount`≥0; `renderPage` + `close` serialized via ONE `Mutex`, `Page.close()` in finally) + the `VReaderApp` page cache (`cachePage`/`cachedPage`) + **instrumented** `androidTest` (PdfRenderer is device-only): a bundled synthetic multi-page PDF opens (`pageCount==N`); `renderPage(0,w)` returns a non-blank Bitmap of width w; concurrent `renderPage` calls + a `close()` during render don't crash; a garbage file → `Corrupt` | foundational |
| WI-2 | `PdfReaderActivity` continuous-scroll render (lazy per-page bitmaps, each owning + recycling one bitmap; never width-0; viewer backdrop) + reader chrome + "Page N of M" pill + Loading/`ProtectedOrUnsupported`/Corrupt/`Empty` state surfaces + `DisposableEffect` doc close + route `pdf`. Instrumented render test (open a synthetic PDF through the library path → a page + the "Page 1 of N" pill render; a corrupt file → the "Couldn't open this PDF" state) | behavioral |
| WI-3 | resume by page index (legacy `Locator(page=…)` save/restore via the conflated channel + the `cachePage` cache, clamped to `0 until pageCount`) + final acceptance. Instrumented resume test (seed page N → reopen lands on page N, page 1 not visible) + a Robolectric `pdf` legacy-envelope→`Canonical` resolver test (mirrors `TxtResumeTest`) | behavioral (final WI) |

## Test catalogue

- WI-1 `PdfDocumentTest` (**instrumented `androidTest`** — `PdfRenderer` is device-only): a
  bundled synthetic multi-page `.pdf` opens (`pageCount == N`); `renderPage(0, w)` returns a
  Bitmap of width `w` with non-uniform pixels (actually rendered, not blank); two concurrent
  `renderPage` calls both succeed (mutex serialization, no crash); `close()` invoked while a
  render is in flight does not throw; a garbage/empty file → `Corrupt`. (An encrypted PDF is
  hard to synthesize without a tool; the `ProtectedOrUnsupported` mapping is covered by the
  exception-mapping unit logic + the UI-state test in WI-2.)
- WI-2 `PdfReaderActivityTest` (instrumented): a synthetic `.pdf` imported + opened **through
  the library/routing path** (`MainActivity` tap) renders the reader chrome + the "Page 1 of N"
  pill + at least one page bitmap node; a corrupt file shows the "Couldn't open this PDF" state;
  a 0-page document shows the `Empty` state.
- WI-3 `PdfResumeTest`: seed a legacy `Locator(format="pdf", page=N)` → reopen lands with page N
  visible (page 1 not visible); a restored page > pageCount clamps to the last page (no crash);
  a Robolectric `pdf` legacy-envelope→`Canonical` resolver test (mirrors `TxtResumeTest`).

## Risks + mitigations

- **R1 — no real PDF fixture** (documented real-books-first exception: "no real PDF today"). Use
  a **synthetic** multi-page PDF asset, hand-built as a minimal valid PDF (a few pages with
  distinct text) in `src/androidTest/assets/`. The render/scroll/resume paths are exercised
  against it; large-file performance stays unverified until a real PDF exists (noted).
- **R2 — `PdfRenderer` thread-safety / single-open-page**: serialize all renders through a
  `Mutex` on an IO dispatcher; never open two pages concurrently. Tested by concurrent
  `renderPage` calls not crashing.
- **R3 — bitmap memory on large PDFs**: lazy per-visible-item render + width cap; off-screen
  bitmaps are GC'd with their composables. Unverified at 600-page scale (no real fixture) — a
  noted limitation, not a v1 blocker.
- **R4 — encrypted scoping** (see Platform constraints): v1 detects + shows a terminal protected
  state; the unlock flow is a filed follow-on. Gate-2 to confirm.

## Backward compat

Additive — a new reader for a format the importer already accepts (`DocumentFingerprint
.formatForFilename` maps `pdf`→`BookFormat.pdf`); no schema change; EPUB/TXT/MD unaffected; the
`pdf`→toast routing is replaced by the real reader.

## Acceptance criteria

1. A `.pdf` imports, appears in the Library (`PDF` chip), opens in the continuous-scroll reader
   with pages rendered as bitmaps on the viewer backdrop + a "Page N of M" pill + reader chrome.
2. Scroll renders pages lazily (no OOM on the synthetic fixture); a corrupt PDF shows the
   "Couldn't open this PDF" state; an encrypted PDF shows the protected state.
3. Close → reopen resumes to the saved page index.
4. `PdfDocumentTest` + instrumented render + resume tests pass on the emulator.
5. EPUB/TXT/MD unaffected; routing opens `pdf` → `PdfReaderActivity`. Paged-mode toggle,
   encrypted-unlock, and the page-jump overlay are explicit **designed** follow-ons (deferred on
   platform/API constraints, not invented in v1 — their surfaces already exist in
   `vreader-pdf-reader.jsx`).

## Revision history

- **v1** (2026-06-20) — Gate-1 draft.
- **v2** (2026-06-20) — Gate-2 audit round 1 (Codex). Findings addressed:
  - *(High)* `PdfDocument.close()` lifecycle → `close` serialized through the SAME `Mutex` as
    `renderPage`, `Page.close()` in `finally`, doc closed from `DisposableEffect`/`onDestroy`;
    concurrent-render + close-during-render tests added.
  - *(High)* bitmap disposal → each page composable owns + recycles exactly one bitmap
    (DisposableEffect), late-after-cancel bitmaps recycled-not-published, stable keys, never
    width-0.
  - *(Medium)* password claim corrected → API 35 `LoadParams` exists but minSdk-26 means no
    stock cross-device unlock; deferral re-justified on that, not "no API at all".
  - *(Medium)* `SecurityException` ≠ only password → result renamed `ProtectedOrUnsupported`,
    UI copy broadened.
  - *(Medium)* page cache naming → a NEW typed `cachePage`/`cachedPage` on `VReaderApp` (not the
    char-offset-named `cacheOffset`).
  - *(Low)* added the `Empty` (pageCount==0) state + test.
  - *(Low)* `Corrupt` also maps `IllegalArgumentException` + unexpected exceptions.
  - *(Low)* WI-1 tests are instrumented `androidTest` (PdfRenderer is device-only), Robolectric
    only for the pure resolver test.
  - Confirmed sound: continuous-scroll-only v1, Mutex serialization, resume-by-`Locator(page)`,
    the 3-WI split (auditor "None"/clean rows). Restored page clamped to `0 until pageCount`.
