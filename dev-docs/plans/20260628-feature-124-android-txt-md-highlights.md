# Feature #124 — Android TXT highlights & notes (Phase 3, #110 driver)

> One of the features making up checklist item **B** (`docs/parity/android-checklist.md`).
> #123 shipped EPUB highlighting + the whole annotation domain; this brings it to
> the **TXT** reader. Design: `vreader-android-annotations.jsx` `SelectionPopover`
> (already implemented in #123). iOS parity: #62/#74.

> **Scope narrowed at Gate-2 (v2).** The Codex audit split off the MD path: MD needs
> a `MarkdownRenderer` recursive-parser refactor to carry source offsets through
> nested emphasis/escapes/inline-code (3 of the 6 Highs were MD-specific: the
> rendered↔source offset map, the visible-vs-source `textQuote` ambiguity, and
> `renderWithMap`). **#124 = TXT only** (render == source, so no offset map and no
> visible/source split). **MD highlighting → follow-on #125.** Checklist box B then
> needs #125 (MD) + the review-sheet/bookmark entry (item F) too.

## Problem

The Android TXT reader renders a chunked `LazyColumn` of plain `Text` with no
selection, so it can't be highlighted/annotated. #123 built the format-agnostic
annotation domain (Room v4 tables, `AnnotationsRepository`, `AnnotationColor`,
`AnnotationAnchor.Text`, `SelectionPopover`/VM). This feature adds the TXT
selection → highlight/note/copy/share flow + re-render of stored highlights as
colored washes, reusing that domain.

## Surface area

### BINDING — TXT gate (Gate-2 r2 High)

`TxtReaderActivity` hosts BOTH `.txt` and `.md` (the shared `TxtBody`). All #124 annotation paths —
`TxtAnnotationController` construction, the gesture modifier, the wash recompute, the hit-tester, and
the popover — are installed **only when `book.originalFormat == BookFormat.txt`**. MD keeps its current
render-only behavior (its highlighting is #125, which adds the source-offset map). A `BookFormat.txt`
assertion guards `addHighlight`'s `locator.format`. Regression: an instrumented test opens an `.md`
book and asserts NO selection popover / highlight-persistence path is active.

### Range type (Gate-2 r2 Medium)

All TXT highlight ranges are **half-open `[startInclusive, endExclusive)`**, represented by an explicit
`Utf16Range(startInclusive: Int, endExclusive: Int)` value type (NOT Kotlin's closed `IntRange`) —
`getPathForRange(start, end)` and `String.substring(start, end)` are exclusive-end, so a closed
`IntRange` would off-by-one at chunk/doc EOF. Any interop with `IntRange` uses `until` / `last + 1`
explicitly. Boundary tests: one-char selection, selection ending at chunk EOF, doc EOF, surrogate-pair end.

### New — pure logic (`com.vreader.app.reader`, separate files — keep `TxtReaderActivity` thin)

- `TxtSelection.kt` — `Utf16Range(startInclusive: Int, endExclusive: Int)` in **SOURCE** UTF-16
  (= `TxtDocument` raw-source index space = the resume/anchor space; for TXT render == source).
  `TxtSelectionState` (`@Stable` holder: current range + anchor rect). Plus `validateRange(doc): Boolean`
  rejecting zero-length / inverted / negative / out-of-document / **mid-surrogate** ranges.
- `TxtSourceOffsets.kt` — `sourceOffset(chunkIndex, offsetInChunk, doc) = doc.offsetForChunk(chunkIndex) + offsetInChunk`
  (TXT identity) and the inverse `chunkRanges(sourceRange, doc): List<ChunkRange(chunkIndex, IntRange)>`
  splitting a source range across the chunks it spans (for per-chunk wash rendering). Pure, unit-tested.
- `TxtHighlightHitTester.kt` — `highlightAt(sourceOffset, highlights): HighlightRecord?` with explicit
  overlap precedence (newest-createdAt wins). Pure.

### New — rendering (`com.vreader.app.reader`)

- `TxtHighlightWash.kt` — render washes with `Modifier.drawBehind` + `TextLayoutResult.getPathForRange(start, end)`
  drawn BEHIND the `Text` (NOT `SpanStyle(background=)`, which doesn't compose for overlaps — Gate-2 High).
  Input: the chunk's `TextLayoutResult` + a list of `(IntRange /*rendered=source for TXT*/, Color)`. The
  in-progress selection is one accent-colored wash; stored highlights are color washes; both layer under
  the existing read-aloud span (explicit precedence: read-aloud on top).

### New — selection gesture

- `TxtSelectionGesture.kt` — a `Modifier.pointerInput` (`detectDragGesturesAfterLongPress`) on `TxtBody`'s
  `LazyColumn`. Per visible chunk: capture `TextLayoutResult` (`onTextLayout`) **and** `LayoutCoordinates`
  (`onGloballyPositioned`). On long-press: convert the root touch point → the hit chunk's local coords →
  `getOffsetForPosition` → `getWordBoundary` for the initial word selection. On drag: extend one endpoint;
  **auto-scroll** when dragging near the viewport top/bottom. All offsets are UTF-16 (matches
  `TxtDocument` + `Locator.charRange*UTF16`). Release → finalize → show the popover at the end rect.

### Modified — `TxtReaderActivity` (wiring only; new logic in the files above)

- A `TxtAnnotationController` (new file) owns: the highlights Flow → recomputed per-chunk washes; the
  selection state; the popover VM; create/edit/remove side effects. `TxtReaderActivity` installs the
  gesture + wash modifiers on `TxtBody`, hosts the `SelectionPopover` over a `Box` overlay (the #123
  `ReaderActivity` precedent), and routes popover actions to the controller.
- Create: `repo.addHighlight(bookKey, color, visibleText, locator, AnnotationAnchor.Text(sourceUnitId =
  "text-document:$fingerprintKey", startUtf16, endUtf16))` where `locator = Locator(contentSHA256,
  fileByteCount, "txt", charRangeStartUTF16 = start, charRangeEndUTF16 = end, textQuote = visibleText)`.
  For TXT `visibleText == sourceText` (no markers), so no visible/source split needed.
- Edit/remove: tap a wash → `TxtHighlightHitTester` → EDIT popover (recolor/note/remove); copy/share use
  the highlight/selection text.

### Files OUT of scope

- **MD highlighting → #125** (needs the parser refactor). EPUB (#123, done). PDF (no text layer). The
  review sheet + bookmark creation (item F). Live translate (#119). iOS code (rule 48).

## Prior art / precedent / rejected alternatives

- **Reuse #123's annotation domain wholesale** — repo/color/anchor(`Text`)/popover/VM are format-agnostic.
- **Custom long-press-drag selection** with `getOffsetForPosition` + `getWordBoundary` + per-chunk
  `LayoutCoordinates` — rejected `SelectionContainer` (no durable source offsets across the chunked
  LazyColumn — the #123 + this audit's finding).
- **`drawBehind` + `getPathForRange` for washes** — rejected `SpanStyle(background=)` (overlapping
  backgrounds override, don't compose — Gate-2 High).
- **Range validation before persist** (zero-length/inverted/negative/mid-surrogate/out-of-doc) — the
  repo only checks same-book; the mapper guards the rest.

## Work-item sequencing

| WI | Tier | Scope | PR size |
|---|---|---|---|
| WI-1 | foundational | `TxtSourceOffsets` (source↔chunk range split) + `TxtSelection`/`validateRange` + `TxtHighlightHitTester`. Tests: chunk-boundary split, surrogate-pair/CJK/emoji, validation rejects, hit-test overlap precedence. | M |
| WI-2 | behavioral | `TxtHighlightWash` (`drawBehind`+`getPathForRange`) + recompute stored highlights → per-chunk washes in `TxtBody`; `TxtAnnotationController` highlights-Flow observation. Tests: split→wash (instrumented render), JVM recompute; emulator slice (seed highlight → wash renders on the live reader). | M-L |
| WI-3 | behavioral | `TxtSelectionGesture` (long-press word select + drag extend + auto-scroll, per-chunk layout/coords) + selection wash + popover create (highlight/note/copy/share). Tests: gesture mapper (instrumented), popover wiring; emulator slice — real long-press-drag creates a highlight. | L |
| WI-4 | behavioral (final) | Tap-existing-wash → EDIT popover (recolor/note/remove) + full acceptance + evidence. Tests: hit-test→edit/remove; emulator acceptance incl. a REAL gesture. | M |

## Test catalogue

- `TxtSourceOffsetsTest` (JVM): source↔chunk range split across boundaries; CJK/emoji surrogate pairs; empty doc.
- `TxtSelectionValidateTest` (JVM): reject zero-length/inverted/negative/out-of-doc/mid-surrogate.
- `TxtHighlightHitTesterTest` (JVM): point→highlight; overlap precedence; no-hit.
- `TxtHighlightWashRenderTest` (instrumented): washes draw for a seeded highlight; overlap layering.
- `TxtHighlightConnectedTest` (emulator): select→addHighlight→persist→reload→wash recompute; dedupe; edit/remove through real Room.
- `TxtReaderHighlightUiTest` (instrumented): popover on selection; tap-to-edit. **Real long-press-drag gesture is a REQUIRED acceptance item (not optional)** — driven via the emulator (`scripts/run-android-verify.sh`); if a raw `adb`/`idb` drag can't finalize a Compose selection, fall back to a documented manual on-device pass, NOT a skip.

All Android tests run through `scripts/run-android-tests.sh` (JVM) / `scripts/run-android-verify.sh` (emulator).

## Risks + mitigations

- **R1 — gesture coordinate mapping** across a scrolling LazyColumn (Gate-2 High): per-chunk `TextLayoutResult` + `LayoutCoordinates` via `onGloballyPositioned`; convert root→local before `getOffsetForPosition`; auto-scroll near edges. Keep the pure offset math in `TxtSourceOffsets` (unit-tested); the gesture stays thin.
- **R2 — wash composition** (Gate-2 High): `drawBehind`+`getPathForRange`, not `SpanStyle` background; explicit precedence (read-aloud > annotation; selection accent distinct).
- **R3 — gesture reliability headlessly**: gesture is a REQUIRED acceptance item; if `adb` drag can't finalize a Compose selection, a manual on-device pass is the fallback (NOT skipped). Substance (mapper/wash/persist/edit) stays unit+connected-verified.
- **R4 — surrogate pairs / CJK**: UTF-16 end-to-end; `getWordBoundary` then clamp to non-mid-surrogate; exhaustive tests.
- **R5 — file size** (Gate-2 Medium): all new logic in separate files; `TxtReaderActivity` stays wiring.

## Backward compat

Additive: no schema change (reuses #123's v4 tables + `AnnotationAnchor.Text`). `sourceUnitId` scheme
fixed now as `text-document:<fingerprintKey>` (feeds `anchorHash`/dedupe — Gate-2 Medium). No change to
the read-aloud wash path beyond layering annotation washes beneath it.

## Revision history

- v1 (2026-06-28) — initial plan (TXT+MD).
- v3 (2026-06-28) — **Gate-2 round-2 fixes** (Codex gpt-5.5/high; 1H/1M; verdict fix-then-proceed →
  clean): added the BINDING TXT gate (all annotation paths gated on `BookFormat.txt`; MD render-only +
  an MD-regression test — TXT/MD share `TxtReaderActivity`); ranges are an explicit half-open
  `Utf16Range(startInclusive, endExclusive)` (not closed `IntRange`) with EOF/surrogate boundary tests.
  **Gate-2 clean.**
- v2 (2026-06-28) — **Gate-2 round-1 fixes** (Codex gpt-5.5/high; verdict split, 6H/5M/2L): scoped to
  TXT-only (MD → #125, removing the offset-map / `renderWithMap` / visible-vs-source Highs); washes via
  `drawBehind`+`getPathForRange` (not `SpanStyle`); gesture coords via per-chunk `LayoutCoordinates` +
  root→local + auto-scroll; `getWordBoundary` long-press; range validation (incl. mid-surrogate);
  `TxtHighlightHitTester` with overlap precedence; `sourceUnitId = text-document:<key>`; split the
  oversized WI-3 into WI-1..4 across separate files; gesture reliability is a REQUIRED acceptance item;
  runner discipline. Pending Gate-2 round-2 re-audit.
