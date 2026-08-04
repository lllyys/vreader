# Feature #152 — Android embedded book-cover extraction + display

**Platform**: `android-app` (test lane `scripts/run-android-tests.sh`, verify lane
`scripts/run-android-verify.sh`).
**iOS parity**: #43 (extraction + display), inside #60's `BookCoverArtView` frame.
**Parity box**: G5 (library), phase 4.
**Design (COMMITTED — rule 51 clean)**:
`dev-docs/designs/vreader-fidelity-v1/project/vreader-cover.jsx` (`BookCover` — the physical-book
frame the art sits in: spine shadow · page-edge highlight · hairline border · drop shadow) and
`.../vreader-book-details.jsx` (the details-sheet cover placement).

> **Split note.** The *generative typographic fallback* for books with no embedded art is feature
> **#170**, split out of this plan at its Gate-2 audit. #152 owns the image pipeline and the
> `BookCoverArt` frame; #170 replaces that frame's no-image branch. Until #170 lands, the no-image
> branch keeps today's flat `FallbackCover` rendering, unchanged.

---

## Problem

Every book in the Android library renders the same placeholder: `FallbackCover`
(`LibraryScreen.kt:265-287`) picks one of 5 hard-coded tints by `book.id.hashCode()` and stamps the
title's first character on it. Real cover art is never extracted or shown, and
`BookDetailsUiModel.kt:3` records that the model deliberately "carries NO `coverPath`". The library
— the app's first screen — looks unfinished next to iOS.

iOS extracts the embedded cover **at import** and displays it everywhere a book appears.

## Gate-1 → Gate-2 scope correction (recorded because it changed the feature)

Gate 1 of this feature concluded that iOS #43 had been *superseded* by #60 WI-10 — that
`BookCardView` feeds `BookCoverArtView(image:)` from `CustomCoverStore`, which was assumed to hold
only user-chosen covers, and therefore that iOS never displays embedded artwork.

**Gate 2 (Codex gpt-5.5/high, 2026-08-04) flagged this Critical, and it was independently verified
as wrong**, at `vreader/Services/BookImporter.swift:351-355`:

```swift
// Step 9.5: Extract and save cover image (non-fatal)
if !CustomCoverStore.hasCover(for: fingerprintKey) {
    if let coverImage = await extractor.extractCoverImage(from: sandboxURL) {
        try? CustomCoverStore.saveCover(coverImage, for: fingerprintKey)
```

`CustomCoverStore` is a **unified** cover store: import-time extraction populates it, and a
user-chosen cover overrides it (the `hasCover` guard is what prevents extraction from clobbering a
user's choice). So iOS *does* display embedded publisher artwork, and this plan is re-scoped to the
image pipeline it originally described. The naming is an iOS legacy quirk worth not copying:
**Android names the type `CoverStore`, not `CustomCoverStore`**, because it serves both roles.

---

## Surface area (file-by-file, with signatures)

Android paths are under `android/app/src/main/kotlin/com/vreader/app/`.

### New — `library/covers/CoverStore.kt`

The single on-disk cover store. Mirrors iOS `CustomCoverStore`, shared with #153 (custom covers).

```kotlin
class CoverStore(private val root: File) {          // root = File(context.filesDir, "covers")
    fun coverFile(fingerprintKey: String): File     // root/<sanitized>.jpg
    fun hasCover(fingerprintKey: String): Boolean
    suspend fun save(fingerprintKey: String, bitmap: Bitmap): String   // → absolute path
    fun remove(fingerprintKey: String)
    companion object { const val MAX_EDGE_PX = 1024 }
}
```

**Filename sanitization is load-bearing**: a `fingerprintKey` is `format:sha256:byteCount` and
contains `:`. Reuse the existing scheme from `data/BookImporter.kt`'s `fileNameForKey` rather than
inventing a second one (Gate-2 will check these agree).

Saves as JPEG quality 85, downscaled so the longest edge ≤ `MAX_EDGE_PX` — bounding memory at the
source so the render path needs no image-loading library.

### New — `library/covers/CoverExtractor.kt`

```kotlin
fun interface CoverExtractor { suspend fun extractCover(file: File): Bitmap? }

object CoverExtractors {
    fun forFormat(format: BookFormat, context: Context): CoverExtractor?   // null ⇒ no art possible
}
```

Every extractor returns `null` on ANY failure (truncated, DRM, corrupt, unsupported) — never throws,
never crashes. TXT/MD map to `null` (no embedded art by definition).

### New — `library/covers/EpubCoverExtractor.kt`

Readium: `publication.coverFitting(Size(MAX_EDGE_PX, MAX_EDGE_PX))`. Signature verified against the
resolved artifact:

```
org.readium.r2.shared.publication.services.CoverServiceKt
  cover(Publication, Continuation<? super Bitmap>)
  coverFitting(Publication, android.util.Size, Continuation<? super Bitmap>)
```

Opens through the existing `reader/BookOpener.kt` seam; closes the publication in a `finally`.

### New — `library/covers/MobiCoverExtractor.kt`

Kotlin port of iOS `vreader/Services/AZW3/MOBICoverExtractor.swift` (159 lines) — pure binary
parsing, **no NDK and no WebView**:

- PDB header (78 bytes) → record count + record-offset table (8 bytes/entry).
- MOBI header → EXTH flag; EXTH records → type **201** (cover offset), **202** (thumbnail offset).
- `0xFFFFFFFF` = not set. Prefer 201 over 202.
- All integers **big-endian**.
- Cover record index = `firstImageIndex + coverOffset`; decode with `BitmapFactory`.
- Any bounds/parse failure → `null`.

### New — `library/covers/PdfCoverExtractor.kt`

Renders page 0 via `PdfRenderer` to a bounded bitmap. **Must reuse `reader/PdfDocument.kt`'s
serialization discipline** — `PdfRenderer` is not thread-safe, allows one open page at a time, and
that file already owns a `Mutex` + paired `openPage`/`close` (`PdfDocument.kt:41-63`). Extraction
opens its own short-lived renderer on an IO dispatcher and closes it deterministically.

### New — `library/covers/CoverBackfill.kt`

```kotlin
class CoverBackfill(store: CoverStore, repo: LibraryRepository, extractors: …) {
    suspend fun runOnce(): Int          // returns how many covers were newly written
}
```

Idempotent: skips any book whose `coverPath` is non-null **and** whose file still exists; re-extracts
when the file is missing (cache eviction). Runs off the main thread, bounded concurrency, and never
blocks first paint.

### New — `library/covers/BookCoverArt.kt` (Compose)

The single render seam every site uses — the design's `BookCover` frame:

```kotlin
@Composable fun BookCoverArt(
    coverPath: String?, fingerprintKey: String, title: String,
    modifier: Modifier = Modifier, cornerRadius: Dp = 4.dp,
)
```

Fixed **2:3 aspect ratio driven by the modifier, never by the drawn content** (so a
`LazyVerticalGrid` row stays uniform regardless of image dimensions — the decision iOS records in
`BookCoverArtView.swift`). Inside the clip: the decoded bitmap (`ContentScale.Crop`), then the spine
gradient (6dp), page-edge highlight (2dp), hairline border, drop shadow.

Decoding: `BitmapFactory.decodeFile` on `Dispatchers.IO` inside a `LaunchedEffect(coverPath)`, held
behind a process-wide `LruCache<String, ImageBitmap>` sized from `Runtime.maxMemory()/8`. No image
library is added — the files are local and pre-bounded at `MAX_EDGE_PX` by `CoverStore`.

**No-image branch**: delegates to today's flat fallback until #170 replaces it.

### Modified — `data/Entities.kt`

```kotlin
val coverPath: String? = null,   // v10 addition (#152) — tail default, matching `author`'s v6 pattern
```

### Modified — `data/VReaderDatabase.kt`

`version = 9` → `10`; add `MIGRATION_9_10` = `ALTER TABLE books ADD COLUMN coverPath TEXT` and append
to `ALL_MIGRATIONS`. (Confirmed current state: `version = 9`, migrations 1→2 … 8→9 present.)

### Modified — `data/BookImporter.kt`

After the atomic promote, mirror iOS's Step 9.5: if `!store.hasCover(key)`, extract → save → persist
`coverPath`. **Non-fatal** — an extraction failure must never fail an import.

### Modified — `library/LibraryViewModel.kt` / `library/LibraryRepository.kt`

`LibraryBook` gains `val coverPath: String? = null` (tail default). Repository maps the new column.

### Modified — `library/LibraryScreen.kt`

Both `FallbackCover(...)` call sites (grid card ~line 188, list row ~line 234) → `BookCoverArt(...)`,
preserving the design's radii (grid 4dp, list row 3dp).

### Modified — `reader/details/BookDetailsSheet.kt` + `reader/details/BookDetailsUiModel.kt`

Add `coverPath`; render `BookCoverArt` **at the top of the sheet body, above title/author**, per
`vreader-book-details.jsx` (Gate-2 High: the earlier "details header" wording was imprecise and the
model's "carries NO coverPath" comment must be updated, not left contradicting the code).

### Files explicitly OUT of scope

- The generative typographic fallback → **#170**.
- User-chosen custom covers → **#153** (extends `CoverStore` + adds the picker).
- Library sort (#154) — also touches `LibraryScreen.kt`; sequenced separately, one writer.
- `backup/*` and `contracts/*` — a cover is a **derived local cache**, re-derivable from the book
  file, so it is deliberately NOT added to the cross-platform backup sections. Adding a field there
  would break golden-vector conformance with iOS.
- OPDS remote thumbnails — a different (network) source, not this feature.

---

## Prior art / project precedent / rejected alternatives

**Prior art.** iOS ships the whole pipeline: `BookImporter` Step 9.5, `MetadataExtractor`'s opt-in
`extractCoverImage` (default `nil`), the native `MOBICoverExtractor`, and `CustomCoverStore`. The
MOBI/EXTH algorithm in particular is proven on this project's own real AZW3 corpus, so porting it
beats re-deriving the format.

**Project precedent.** #126 established that AZW3 needs no NDK; #115 established the `PdfRenderer`
mutex discipline; #128 established the "nullable column with a tail default" migration shape
(`author`, v6).

**Rejected — Coil / Glide.** The standard answer for Compose image loading, and the right call for
*network* images. Here every file is local, app-written, and already downscaled to ≤1024px at save
time, so the library's main value (fetch, cache-negotiation, aggressive downsampling) is unused. The
app currently has zero image dependencies; a bounded `LruCache` + `BitmapFactory` is ~40 lines.
**Explicitly flagged for the auditor to overturn** if it judges the leak/jank risk of a hand-rolled
cache to outweigh the dependency.

**Rejected — extracting covers lazily at render time.** Would put ZIP/PDF parsing on the scroll path.
Extraction happens once at import (+ a one-time backfill), exactly as iOS does.

**Rejected — a WebView/foliate-js round-trip for AZW3 covers.** Requires a live WebView per import;
the native parse is synchronous, testable, and already written on iOS.

---

## Work-item sequencing

Seven WIs. WI-1…WI-4 are foundational (JVM-testable, no visible delta); WI-5…WI-6 behavioral; WI-7
is the acceptance pass.

### WI-1 — CoverStore + schema migration 9→10

```yaml
id: WI-1
tier: foundational
depends: []
writes:
  - android/app/src/main/kotlin/com/vreader/app/library/covers/
  - android/app/src/main/kotlin/com/vreader/app/data/Entities.kt
  - android/app/src/main/kotlin/com/vreader/app/data/VReaderDatabase.kt
  - android/app/src/test/kotlin/com/vreader/app/library/covers/
  - android/app/src/androidTest/kotlin/com/vreader/app/data/
tests:
  - CoverStoreTest                       # JVM (temp dir)
  - VReaderDatabaseMigrationTest         # connected — extend with 9→10
acceptance:
  - save() downscales so max(width,height) <= 1024 and returns a path that exists.
  - Filename sanitization matches BookImporter.fileNameForKey for the same key (asserted directly).
  - hasCover is false before save, true after; remove() makes it false again.
  - Migration 9->10 preserves all existing book rows and leaves coverPath NULL.
  - A round-trip open at version 10 on a v9-populated DB succeeds.
```

### WI-2 — EPUB cover extractor

```yaml
id: WI-2
tier: foundational
depends: [WI-1]
writes:
  - android/app/src/main/kotlin/com/vreader/app/library/covers/
  - android/app/src/androidTest/kotlin/com/vreader/app/library/covers/
tests:
  - EpubCoverExtractorConnectedTest
acceptance:
  - A committed EPUB fixture WITH a cover yields a non-null bitmap within the size bound.
  - A committed EPUB fixture WITHOUT a cover yields null (no throw).
  - A truncated/corrupt EPUB yields null (no throw).
  - The Publication is closed on every path (no leaked file handle across 50 iterations).
```

### WI-3 — MOBI/AZW3 cover extractor (port of iOS MOBICoverExtractor)

```yaml
id: WI-3
tier: foundational
depends: [WI-1]
writes:
  - android/app/src/main/kotlin/com/vreader/app/library/covers/
  - android/app/src/test/kotlin/com/vreader/app/library/covers/
tests:
  - MobiCoverExtractorTest               # JVM — synthetic byte-level fixtures
acceptance:
  - Big-endian PDB/EXTH parse locates EXTH 201; prefers 201 over 202.
  - 0xFFFFFFFF in 201 falls through to 202; both unset yields null.
  - Truncated header, record offset past EOF, and non-image payload all yield null (no throw).
  - Byte-level synthetic fixtures are constructed in-test (no gitignored assets).
```

### WI-4 — PDF cover extractor

```yaml
id: WI-4
tier: foundational
depends: [WI-1]
writes:
  - android/app/src/main/kotlin/com/vreader/app/library/covers/
  - android/app/src/androidTest/kotlin/com/vreader/app/library/covers/
tests:
  - PdfCoverExtractorConnectedTest
acceptance:
  - Page 0 of a committed PDF fixture renders to a bounded, non-blank bitmap.
  - A password-protected PDF yields null (no throw) — the PdfDocument.kt precedent.
  - The renderer and page are closed on every path; 50 sequential extractions do not leak.
```

### WI-5 — import-time extraction + idempotent backfill

```yaml
id: WI-5
tier: behavioral
depends: [WI-2, WI-3, WI-4]
writes:
  - android/app/src/main/kotlin/com/vreader/app/data/BookImporter.kt
  - android/app/src/main/kotlin/com/vreader/app/library/
  - android/app/src/androidTest/kotlin/com/vreader/app/library/
tests:
  - CoverBackfillConnectedTest
  - BookImporterCoverConnectedTest
acceptance:
  - Importing a cover-bearing EPUB persists a non-null coverPath.
  - An extraction failure still completes the import (coverPath stays null, no error surfaced).
  - Import does NOT overwrite an existing cover file (the iOS hasCover guard).
  - Backfill is idempotent — a second runOnce() writes 0 new covers.
  - Backfill re-extracts when the cover file was deleted but coverPath is set.
```

### WI-6 — BookCoverArt + adoption at every render site

```yaml
id: WI-6
tier: behavioral
depends: [WI-5]
writes:
  - android/app/src/main/kotlin/com/vreader/app/library/covers/
  - android/app/src/main/kotlin/com/vreader/app/library/LibraryScreen.kt
  - android/app/src/main/kotlin/com/vreader/app/reader/details/
  - android/app/src/androidTest/kotlin/com/vreader/app/library/
  - android/app/src/androidTest/kotlin/com/vreader/app/reader/details/
tests:
  - BookCoverArtConnectedTest
  - LibraryCoverAdoptionConnectedTest
  - BookDetailsCoverConnectedTest
acceptance:
  - Grid card, list row, and Book Details all render BookCoverArt.
  - The 2:3 ratio holds for a 1:1 and a 1:3 source image (no grid-row height drift).
  - A null coverPath renders the fallback branch; a missing FILE at a non-null path also does.
  - The details cover sits at the top of the sheet body above title/author (vreader-book-details.jsx).
  - Scrolling a 50-book grid decodes each cover at most once (LruCache hit assertion).
```

### WI-7 — Gate-5 acceptance

```yaml
id: WI-7
tier: behavioral
depends: [WI-6]
writes:
  - android/app/src/androidTest/kotlin/com/vreader/app/library/
  - dev-docs/verification/
tests:
  - CoverAcceptanceConnectedTest
acceptance:
  - Automated: committed fixtures for EPUB/PDF/AZW3/TXT each land on the right branch.
  - Manual (scripted, logged in the evidence file): the REAL books in test-books/books/ — incl. the
    6MB CJK AZW3 and a real EPUB — show their true cover art on emulator-5554.
  - Covers survive an app restart (no re-extraction, no flicker).
```

---

## Test catalogue

| Test file | Lane | Covers |
|---|---|---|
| `CoverStoreTest` | JVM | sanitization parity with `BookImporter.fileNameForKey`, downscale bound, save/has/remove lifecycle, unicode + very long keys |
| `MobiCoverExtractorTest` | JVM | big-endian parse, EXTH 201/202 preference, `0xFFFFFFFF` sentinel, truncation, offset-past-EOF, non-image payload |
| `VReaderDatabaseMigrationTest` | connected | 9→10 additive migration, row preservation, NULL default |
| `EpubCoverExtractorConnectedTest` | connected | with-cover, without-cover, corrupt, handle-leak |
| `PdfCoverExtractorConnectedTest` | connected | page-0 render, encrypted → null, handle-leak |
| `BookImporterCoverConnectedTest` | connected | happy path, non-fatal failure, no-overwrite guard |
| `CoverBackfillConnectedTest` | connected | idempotency, missing-file re-extraction, no main-thread block |
| `BookCoverArtConnectedTest` | connected | aspect-ratio invariance, null/missing-file branches, LruCache single-decode |
| `LibraryCoverAdoptionConnectedTest` | connected | grid + list adoption, no `FallbackCover` refs remain in adopted sites |
| `BookDetailsCoverConnectedTest` | connected | details placement above title/author |
| `CoverAcceptanceConnectedTest` | connected | per-format branch routing on committed fixtures; restart stability |

**Fixture policy (Gate-2 Medium).** `test-books/books/` is **gitignored and local-only**, so no
automated test may depend on it. Automated tests use small **committed** fixtures under
`android/app/src/androidTest/assets/` (a minimal cover-bearing EPUB, a 1-page PDF, and byte-level
synthetic MOBI buffers built in-test). The **real** books satisfy AGENTS.md's "real books first" rule
at **Gate 5 verification**, where they are exercised on the emulator and recorded in the evidence
file — the standard split this repo already uses.

**Connected-test discipline** (memory: #133/#125/#127): one test class per connected run
(comma-separated `class=A,B` fast-fails with `tests=0`), cold-booted emulator, `ANDROID_SERIAL=emulator-5554`,
and never drive the emulator while a run is in flight. The connected task wipes
`/sdcard/Android/data/<pkg>/` at run-end, so any pushed fixture must be re-pushed per run.

---

## Risks + mitigations

| # | Risk | Mitigation |
|---|---|---|
| 1 | **AZW3/MOBI parse correctness** on real KF8. | Direct port of a proven iOS implementation; byte-level JVM tests for every failure branch; graceful `null`; Gate-5 on the real 6MB CJK AZW3. |
| 2 | **Memory** — decoding many covers in a grid. | Bounded at the source (`MAX_EDGE_PX` at save), `ContentScale.Crop` into a fixed 2:3 box, process-wide `LruCache` sized from `maxMemory()/8`, single-decode asserted in WI-6. |
| 3 | **Hand-rolled bitmap cache leaks/jank** (the reason Coil exists). | Cache holds `ImageBitmap` keyed by path with a hard byte budget; decode strictly off-main in `LaunchedEffect`; WI-6 asserts single-decode across a 50-book scroll. Flagged for the auditor to overturn in favour of Coil. |
| 4 | **`PdfRenderer` is not thread-safe** and allows one open page. | Follow `PdfDocument.kt`'s existing Mutex + paired open/close discipline; short-lived renderer per extraction on IO. |
| 5 | **Migration on a populated DB.** | Additive `ALTER TABLE … ADD COLUMN` with a tail-default field (the v6 `author` precedent); connected round-trip migration test. |
| 6 | **Backfill jank on a large library.** | Off-main, bounded concurrency, idempotent, never blocks first paint; it is a background pass, not a startup gate. |
| 7 | **Cover file deleted by the OS** (app-private cache pressure) leaving a dangling `coverPath`. | Render falls back when the file is missing (asserted), and backfill re-extracts. |
| 8 | **Import regression** — a cover bug must never break importing. | Extraction is wrapped non-fatally, mirroring iOS's "Step 9.5 (non-fatal)"; asserted in WI-5. |

---

## Backward compatibility

- **Schema**: additive nullable column, migration 9→10, no data transform — the lightest Room
  migration class, matching the v6 `author` precedent. Downgrade is not supported (unchanged policy).
- **Existing libraries**: every pre-existing book starts with `coverPath = NULL` and renders exactly
  as today until the idempotent backfill fills it in. No user-visible regression at any point.
- **Backup/restore**: untouched. A cover is a derived local cache, re-derivable from the book file,
  so it stays out of the cross-platform sections and golden-vector conformance with iOS is preserved.
- **Forward-compatible with #153 and #170**: `CoverStore` is the shared store #153 will write user
  picks into (with the same `hasCover` no-clobber semantics iOS uses), and `BookCoverArt` is the one
  frame whose no-image branch #170 replaces.

---

## Revision history

- **v1 (2026-08-04)** — planned as "generative typographic covers", on the Gate-1 conclusion that
  iOS #43 had been superseded by #60 WI-10.
- **v2 (2026-08-04)** — **re-scoped after Gate-2 round 1** (Codex gpt-5.5/high; 1 Critical, 4 High,
  5 Medium). The Critical was correct and independently verified at `BookImporter.swift:351-355`:
  `CustomCoverStore` is a unified store populated by import-time extraction, so iOS *does* display
  embedded artwork and v1's premise was false. This version restores the image pipeline as the
  feature, splits the generative fallback to **#170**, and additionally applies the round-1 findings
  that survive the re-scope:
  - *High* — persisted cover metadata IS required → `coverPath` column + migration 9→10 + UI model
    plumbing are now in scope.
  - *High* — Book Details currently omits cover art; placement now cites `vreader-book-details.jsx`
    ("top of the sheet body, above title/author") with a named `BookDetailsCoverConnectedTest`, and
    the WI-6 write-set includes `androidTest/.../reader/details/`.
  - *Medium* — `VReaderFonts.Serif`/`.Sans` are **platform approximations**, not bundled Source
    Serif 4 / Inter (`ui/theme/Theme.kt:31-34`); the v1 "already bundled" claim is deleted. (Carried
    to #170, which is where type is drawn.)
  - *Medium* — automated tests must not depend on gitignored `test-books/`; the fixture policy above
    now splits committed fixtures (automated) from real books (Gate-5 evidence).
  - *Medium* — WI write-sets corrected so each lane can write its own tests.
  - The FNV-1a signed-`Byte` trap and the literal cross-platform vector table (round-1 High/High)
    belong to the generative assignment policy and are carried to **#170**'s row and plan.
- **Gate-2 round 2 (2026-08-04)** — Critical **resolved**; the auditor confirmed the re-scope is
  directionally sound (Readium `coverFitting` exists in the pinned 3.3.0 artifact, the DB is at v9
  with 1→2…8→9, the PDF and iOS-MOBI descriptions are faithful, and excluding covers from the
  backup contracts matches both platforms' DTOs). **6 High + 8 Medium + 2 Low remain open** —
  mostly plan-completeness (shared filename-sanitization visibility, MOBI `firstImageIndex`
  derivation, per-WI test-write-set gaps). **This plan is NOT Gate-2 clean and #152 must NOT enter
  Gate 3 until round 3 closes those findings** (rule 47: max 3 rounds, then escalate).
  Work paused here — the session pivoted to the reachability defect (feature #171), which
  supersedes #152 in priority because it makes four already-built features usable.
