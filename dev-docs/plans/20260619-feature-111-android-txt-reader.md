# Feature #111 — Android TXT reader (Phase 3, capability parity)

Status: Gate-1 draft (2026-06-19). The first per-capability feature filed under the
#110 Android Phase-3 driver, in reuse-leverage order after EPUB (done). Source of
truth for the program: `docs/decisions/0001-android-port-strategy.md` (steady-state,
iOS-leads-Android-follows) + `docs/parity/README.md`.

## Problem

The Android app (foundation bar #106, `android/v0.3.0`) reads EPUB only. iOS reads
TXT (among other formats) via a native text stack. Bring **plain-text reading** to
Android at parity: import a `.txt` book → it appears in the Library (already works —
`DocumentFingerprint.formatForFilename` maps `txt` (consumed by `BookImporter`), the
Library shows the `TXT` chip) → open
it → read the decoded text in a scrollable reader with the shared chrome → resume to
the saved character offset.

Scope is the **core TXT read**: encoding-detected decode + scroll render + resume.
The rich iOS TXT features (paged mode, bilingual, highlights, TTS, chapter index) are
**out of scope** here — each is its own later Phase-3 capability under #110.

## Verified constraints / prior art

- **Real fixture**: `test-books/books/txt/黑暗血时代.txt` is **13MB, UTF-16LE, CJK** —
  exactly the hard case (large file + non-UTF-8 encoding + CJK). Encoding detection is
  mandatory (a naive UTF-8 read corrupts it).
- iOS prior art: `vreader/Utils/EncodingDetector.swift` (BOM + heuristic charset
  detection), the `TXTChunked*` stack (a 13MB file can't go into one view). The
  Android analog: detect charset → decode → render in a `LazyColumn` of line/paragraph
  chunks (the chunked-UITableView analog), addressed by UTF-16 char offset.
- `.txt` is mapped to `BookFormat.txt` by **`DocumentFingerprint.formatForFilename`**
  (in `:identity`), already consumed by `BookImporter` — so a `.txt` already imports +
  shows the `TXT` chip.
- `Locator.charOffsetUTF16` already exists in the shared `:identity` module (the TXT
  resume anchor). **TXT resume uses the LEGACY-locator path, NOT the Readium bridge**
  (Gate-2 High): a TXT position has no Readium JSON, so it is carried by
  `VReaderLocator.wrapLegacy(Locator(charOffsetUTF16 = …))` (engine `epubWKWebView`,
  `readiumLocatorJSON = null`), persisted by Room (WI-3), and restored via
  `ResumeResolver.resolve(...) → ResumeTarget.Canonical(locator)` (NOT `Precise`).
  `ReadiumLocatorBridge.toEnvelope`/`ReaderActivity.computeInitialLocator` are
  Readium-JSON / `Precise`-only and are NOT used by the TXT reader.
- **Verified fixture facts** (Gate-2): `黑暗血时代.txt` = **14,059,220 bytes,
  UTF-16LE with BOM, mixed CRLF/CR line endings**. Offsets MUST index UTF-16 code
  units against the RAW decoded string (no line-ending normalization), or
  `charOffsetUTF16` drifts and resume breaks on the real book.
- The reader **chrome** (back + title) is the same committed `vreader-reader.jsx`
  surface already reused for the EPUB `ReaderActivity` (rule-51-compliant reuse).

## Surface area (file-by-file)

- `android/app/.../reader/TxtDecoder.kt` (NEW) — charset detection: **BOM-first**
  (UTF-8 BOM, UTF-16 LE/BE BOM — deterministic) → decode. BOM-less fallback is
  explicit + low-confidence: try strict UTF-8 (no replacement) first; on decode
  failure, a single heuristic guess (GBK for CJK byte patterns) else default UTF-8
  with replacement. Returns `(charset, decodedText)`. The detection result records
  confidence so the caller/tests can assert the deterministic BOM cases. Pure JVM.
- `android/app/.../reader/TxtDocument.kt` (NEW) — **range-based over ONE backing
  decoded `String`** (no per-chunk substrings held; visible text materialized on
  demand). Splits into chunks at line boundaries WITHOUT normalizing separators
  (CRLF/CR/LF kept), each chunk = a `[startUtf16, endUtf16)` range into the original
  string. `offsetForChunk(i)` / `chunkForOffset(off)` (binary search) map scroll index
  ↔ `charOffsetUTF16`. A no-newline / huge-line file is bounded by a max chunk size
  (hard-split mid-line) so addressing + render stay sane. EOF-clamps an out-of-range
  offset.
- `android/app/.../reader/TxtReaderActivity.kt` (NEW) — Compose `LazyColumn` over the
  chunk ranges with the shared chrome; opens the stored `.txt` from app-private
  storage (off the main thread); lifecycle-safe like `ReaderActivity` (`onStop` flush).
- `android/app/.../reader/TxtResume.kt` (or in the activity) — save: `VReaderLocator
  .wrapLegacy(Locator(contentSHA256/fileByteCount/format from the book, charOffsetUTF16
  = offsetForChunk(topVisibleIndex)))` → `LibraryRepository.savePosition`. Restore:
  `ResumeResolver.resolve(loadPosition) → ResumeTarget.Canonical(locator)` →
  `chunkForOffset(locator.charOffsetUTF16)` → initial scroll index. (NOT the Readium
  bridge / `Precise`.)
- `android/app/.../library/LibraryViewModel.kt` — add `originalFormat: BookFormat` to
  `LibraryBook` (keep the upper-case `format` chip label derived from it), so routing
  dispatches on the typed format, not a display string.
- `android/app/.../MainActivity.kt` — route `onOpenBook` by `book.originalFormat`:
  `epub` → `ReaderActivity`, `txt` → `TxtReaderActivity`; other formats no-op for now.
- Tests: `TxtDecoderTest` + `TxtDocumentTest` (JVM, WI-1 — incl. the contract edge
  cases below), `TxtReaderActivityTest` (instrumented: open the TXT fixture, render,
  resume).
- **Files OUT of scope**: paged mode, bilingual, highlights, TTS, chapter index/TOC,
  AZW3/PDF/MD (separate #110 capabilities).

## Work items

| WI | Scope | Tier |
|---|---|---|
| WI-1 | `TxtDecoder` (BOM-first detection + explicit fallback) + `TxtDocument` (range-based chunking over one backing string, offset↔chunk addressing, EOF clamp, max-chunk bound). **The offset/resume CONTRACT is foundational — all of it lands + is tested here** (Gate-2 Low): mixed CRLF/CR/LF separator-width preservation, surrogate-pair UTF-16 offsets, empty file, offset-past-EOF clamp, no-newline/huge-line, ambiguous BOM-less charset. Pure-JVM. | foundational |
| WI-2 | `TxtReaderActivity` (Compose `LazyColumn` render + shared chrome + open from storage, lifecycle-safe) + `LibraryBook.originalFormat` + format routing in `MainActivity`. Instrumented render test on the emulator. | behavioral |
| WI-3 | Resume **via the legacy path** (Gate-2 High): save `VReaderLocator.wrapLegacy(Locator(charOffsetUTF16 = offsetForChunk(topVisible)))` (debounced + onStop flush, mirroring `ReaderActivity`) → `savePosition`; restore via `ResumeResolver.resolve → Canonical` → `chunkForOffset`. Instrumented resume test + a real-book (14MB UTF-16LE CJK) verification. | behavioral (final) |

## Test catalogue

- `TxtDecoderTest`: UTF-8 (with/without BOM), UTF-16LE BOM, UTF-16BE BOM, a GBK
  BOM-less CJK case, an unknown/ambiguous charset → documented low-confidence
  fallback, empty file, invalid bytes → replacement; the real-file first line decodes
  to legible CJK.
- `TxtDocumentTest`: chunk boundaries with **mixed CRLF/CR/LF preserved**,
  `offsetForChunk`/`chunkForOffset` round-trip, **surrogate-pair (UTF-16 code-unit)
  offsets**, EOF clamp (offset past end), no-newline/huge-line hard-split, empty doc.
- `TxtResumeTest` (JVM): a `txt` `wrapLegacy` envelope round-trips through the
  repository; `ResumeResolver.resolve` returns `Canonical` for it (NOT `Precise`/`None`).
- `TxtReaderActivityTest` (instrumented): open the fixture → first chunk visible;
  resume → reopen lands at the saved chunk.

## Risks + mitigations

- **R1 — 13MB in memory / render jank.** Decode once to a `String` (13MB ~ fine for a
  book); render via `LazyColumn` (lazy chunk composition, not all-at-once). If memory
  is a concern on low-RAM devices, a follow-on chunked-file loader (the iOS
  `TXTChunkedLoader` analog) — not needed for v1.
- **R2 — charset misdetection.** BOM-first (deterministic for the real fixture's
  UTF-16LE); heuristic only as fallback, with UTF-8 the default. Test the real first
  line decodes correctly.
- **R3 — offset addressing drift** (UTF-16 vs code points for CJK). Use UTF-16 code
  units consistently (matches `charOffsetUTF16`'s contract + Swift `String.utf16`).

## Backward compat

Additive: a new reader for a format the importer already accepts; no schema change
(the `VReaderLocator` envelope + Room already carry `charOffsetUTF16`). EPUB reading
unaffected.

## Acceptance criteria

1. A real `.txt` (the 13MB UTF-16LE CJK fixture) imports, appears in the Library, and
   opens in `TxtReaderActivity` with its text **correctly decoded** (CJK legible).
2. Scroll render is smooth (LazyColumn, no full-file jank).
3. Close → reopen resumes to the saved character offset (within a chunk).
4. JVM unit tests (decoder + document) + an instrumented render/resume test pass.
5. EPUB reading is unaffected; format routing opens TXT → TxtReaderActivity, EPUB →
   ReaderActivity.

## Revision history

- v1 (2026-06-19) — Gate-1 draft.
- v2 (2026-06-19) — Gate-2 round 1 (Codex) applied. **High** — TXT resume uses the
  LEGACY path (`VReaderLocator.wrapLegacy` + `ResumeResolver → Canonical`), NOT the
  Readium bridge / `Precise` (which are Readium-JSON-only). **High** — `TxtDocument`
  indexes UTF-16 offsets against the RAW decoded string with separator widths
  preserved (the real fixture is UTF-16LE + mixed CRLF/CR). **Medium** — typed
  `LibraryBook.originalFormat` for routing (not the display string); range-based
  document model (one backing string + ranges, on-demand visible text, bounded
  chunks); explicit low-confidence encoding fallback. **Low** — offset/resume contract
  tests moved into WI-1; corrected `DocumentFingerprint.formatForFilename` reference.
- v3 (2026-06-19) — Gate-2 round 2: all round-1 High/Medium confirmed resolved
  (resume legacy-path + raw-string offsets + typed routing + range-model + encoding
  fallback all verified against code); corrected the last stale
  `BookImporter.formatForFilename` → `DocumentFingerprint.formatForFilename` reference.
  **Gate-2 CLEAN.**
