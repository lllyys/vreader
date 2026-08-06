# Feature #152 — Android embedded book-cover extraction + display

**Platform**: `android-app` (test lane `scripts/run-android-tests.sh`, verify lane
`scripts/run-android-verify.sh`, `ANDROID_SERIAL=emulator-5554`).
**Parity box**: G5 (library), phase 4. **iOS parity**: #43 (extraction + display) inside #60's
`BookCoverArtView` frame.
**Supersedes**: `dev-docs/plans/20260804-feature-152-android-cover-extraction.md` (v2, stalled at
Gate-2 round 2 with 6 High + 8 Medium + 2 Low open). This is a fresh Gate-1 draft written from the
code, not from that plan; §"What changed vs the 2026-08-04 plan" records where it diverges.

---

## 0. Verification log (what was checked in the codebase, not assumed)

Rule 47 Gate 2 treats an unverified claim about existing code as a High finding. Everything this
plan asserts about the current tree was read at the file:line named here on 2026-08-06.

| Claim | Verdict | Evidence |
|---|---|---|
| Android renders a flat `FallbackCover` for every book | **TRUE** | `android/app/src/main/kotlin/com/vreader/app/library/LibraryScreen.kt:268-287` defines it; call sites are the grid card `:188` and the list row `:235`. (The row cites `:265-287` — off by 3 lines; the function is `:268-287`.) |
| `BookDetailsUiModel` "carries NO `coverPath`" | **TRUE** | `reader/details/BookDetailsUiModel.kt:3-6` states it in the header and the data class `:22-32` has no such field. `BookDetailsSheet.kt:128` renders "No cover art (Design-gate #1)". |
| iOS extracts the cover at import behind a `hasCover` guard | **TRUE** | `vreader/Services/BookImporter.swift:351-355`. |
| iOS `CustomCoverStore` is a *unified* store (extraction + user pick) | **TRUE** | `vreader/Services/CustomCoverStore.swift:39-84` — one `<AppSupport>/CustomCovers/<sanitized>.jpg` path, `saveCover` used by both the importer and the #30 picker; `hasCover` is the ordering guard. |
| iOS `MOBICoverExtractor` is 159 lines of native PDB/MOBI/EXTH parsing, no WebView/NDK | **TRUE** | `vreader/Services/AZW3/MOBICoverExtractor.swift` (159 lines, `import UIKit` only). |
| Readium `Publication.coverFitting(Size)` exists in the pinned version | **TRUE, verified in the artifact** | Pinned `org.readium.kotlin-toolkit:readium-shared:3.3.0` at `android/app/build.gradle.kts:111-114` (there is **no** `libs.versions.toml`; `android/gradle/` holds only `wrapper/`). From `CoverServiceKt.class` in the resolved AAR, the **`Signature:` attribute** (not the erased `descriptor:`, which omits the type argument — corrected per audit L-15): `coverFitting(Lorg/readium/r2/shared/publication/Publication;Landroid/util/Size;Lkotlin/coroutines/Continuation<-Landroid/graphics/Bitmap;>;)Ljava/lang/Object;` → Kotlin `suspend fun Publication.coverFitting(maxSize: android.util.Size): Bitmap?`. Sibling `suspend fun Publication.cover(): Bitmap?`. Import `org.readium.r2.shared.publication.services.coverFitting`. **No `@ExperimentalReadiumApi` on the cover API** — a negative proven sound by finding 31 *other* classes in the same jar that do carry the annotation, so its absence here is a real signal, not a scan miss. The *opener* still needs `@OptIn(ExperimentalReadiumApi::class)` (there is no module-wide opt-in — `android/app/build.gradle.kts:66-73` deliberately omits it). |
| Room schema is at v9, so the new migration is 9→10 | **TRUE** | `data/VReaderDatabase.kt:31` `version = 9`; `MIGRATION_1_2 … MIGRATION_8_9` all present, `ALL_MIGRATIONS` at `:256-260`. |
| PDF page-0 rendering already exists and must be reused | **TRUE** | `reader/PdfDocument.kt:54` `suspend fun renderPage(pageIndex: Int, targetWidthPx: Int): Bitmap` — `withContext(dispatcher)` + `mutex.withLock` + paired `openPage`/`page.close()`; `open()` at `:86` maps `SecurityException → ProtectedOrUnsupported`, everything else → `Corrupt`, and closes the FD on every failure path. |
| The `Bitmap.recycle()` hazard from #115 | **TRUE and bounded** | `reader/PdfReaderScreen.kt:275-279` + `PdfDocument.kt:47-53`: recycling **at the composable boundary** races Compose's draw and crashes; there is **zero** `.recycle()` in `android/app/src/main`. A bitmap that is encoded to a file and never handed to Compose is outside that hazard. |
| Real AZW3/EPUB fixtures exist for Gate 5 | **TRUE** | `test-books/books/azw3/Bei Tao Yan De Yong Qi - Zi Wo.azw3` (6.3 MB) — hexdump confirms a `BOOKMOBI` PDB with `numRecords = 0x0099 = 153` at offset 76 and record 0 at `0x518`. `test-books/books/epub/The Half Second - Li Xiaolai.epub` (`OEBPS/covers/cover-front.png`) and `道诡异仙 - 狐尾的笔.epub` — the latter carries both `OEBPS/Images/cover.jpg` **and** `OEBPS/OEBPS/cover.jpg`, i.e. the double-prefix pathology iOS bug #122 fixed. |

### 0.1 Empirical confirmation of the §4 MOBI spec (Gate-2 round 1, 2026-08-06)

Gate-2 round 1 ran two independent audits in parallel: a broad static one (Codex gpt-5.5/high) and
an **empirical** one that ported this plan's §4 MOBI spec to Kotlin/Java, ran it against 4 real
books and 39 mutated files, and cross-checked every extraction against an independently written
Python reader. Both returned `block-recommended` (findings addressed in §14). What the measurement
**confirmed**, recorded here because it is load-bearing evidence, not flattery:

- Ported faithfully with the two stated Kotlin corrections, the spec extracted the **correct** cover
  from 3/3 cover-bearing real books — the 6.3 MB CJK book resolves to **record 135, a 379,691-byte
  542×800 JPEG**, rendered and visually confirmed as the real jacket — returned `None` for the one
  book that genuinely has none, and **matched the independent Python implementation byte-for-byte**
  (`md5 fa84a175…`).
- 36 of 39 hostile inputs returned cleanly with no hang (the other 3 are finding **C-1**).
- A 300 MB sparse file parses at `-Xmx16m` with a **0 MB heap delta** — the D-6 bounded-read claim
  holds as stated.
- Both Kotlin corrections are real, reproduced in compiled Kotlin: `0xFFFFFFFF` is typed `Long`, so
  an `Int` port yields `co = -1` → `target = 135 + (-1) = 134`, and record 134 is a **non-image
  record** — silently wrong bytes, not an error. And `numRecords` at file offset 76 is `00 99` in
  the real book: unmasked sign extension gives **-103**, so an unmasked port fails on the *first
  field it reads*, on a real book (112 of 153 record offsets are affected).
- Two §4 claims previously asserted from the Swift are now **proven**: `firstImageIndex` at offset
  108 is an **absolute** PDB record index (135), and EXTH-201/202 are **relative to it** —
  discriminated by mutation `06b`, since the happy path cannot tell them apart (`135 + 0 == 135`).

**Three findings that contradict or materially extend the row** (see §"What changed" for the
consequences):

1. **iOS does not extract PDF covers.** `PDFMetadataExtractor` (`MetadataExtractor.swift:261-265`)
   is an explicit stub with no `extractCoverImage` override, so it inherits the protocol default
   `nil` (`:64-66`). Only EPUB (`:92`) and AZW3 (`:294`) override it. The row's PDF-via-`PdfRenderer`
   leg is an **Android-only addition**, not parity. It is cheap (the renderer already exists) and
   kept — but it must not be described as "matching iOS".
2. **iOS does not persist a cover path either.** `BookRecord.coverImagePath` is fed from
   `metadata.coverImagePath` (`BookImporter.swift:390`), and **every** extractor hard-codes
   `coverImagePath: nil`. The live lookup is `CustomCoverStore.loadCover(for: fingerprintKey)` — a
   pure function of the key. So a `coverPath` column is **not** required for parity; it is being
   added for a different, Android-specific reason (Room-`Flow` reactivity), argued in §3.
3. **The DB-layer no-clobber guard the row never mentions.** The import upsert is
   `BookDao.upsertPreservingAuthor` (`data/Daos.kt:83-97`), which falls through to
   `updateImportedColumns` (`:57-77`) — a column-scoped `UPDATE` that deliberately excludes `author`
   and `lastOpenedAt` so a duplicate SAF import cannot clobber them (a #128 Gate-2 Critical). The new
   cover columns **must join that exclusion list**, or re-importing a book would erase a user's #153
   cover pointer. This is the DB-layer half of iOS's `hasCover` ordering.

---

## 1. Problem

Every book on Android's first screen shows the same placeholder: `FallbackCover` picks one of five
hard-coded tints from `book.id.hashCode()` and stamps the title's first character
(`LibraryScreen.kt:268-287`). Publisher artwork embedded in the user's own files is never read. The
Book Details sheet shows no cover at all. iOS extracts the embedded cover once at import and shows
it in the grid, the list row, the continue rail, and the details sheet.

The feature is also structural: #153 (custom covers), #154 (library sort) and #170 (generative
fallback) all build on the store and the render seam introduced here, so their shapes are decided by
this plan.

---

## 2. Rule 51 — design coverage

Committed bundle: `dev-docs/designs/vreader-fidelity-v1/project/`.

**Depicted (build these):**

| Surface | Depiction |
|---|---|
| The physical-book cover frame | `vreader-cover.jsx:3-29` `BookCover` — radius 4, 6px left spine gradient `rgba(0,0,0,0.25)→transparent 60%`, 2px right page-edge `linear-gradient(to left, rgba(255,255,255,0.18), rgba(0,0,0,0.12))`, `boxShadow 0 1px 2px / 0 8px 24px rgba(0,0,0,0.18)`, `inset 0 0 0 1px rgba(0,0,0,0.06)` hairline, `overflow:hidden` (art clipped by the frame). Restated identically in `vreader-generated-cover.jsx:71-88` (`CoverMonogram`). |
| Cover aspect + grid placement | `vreader-library-android.jsx:31-52` `Cover` (`h = round(w * 1.5)`, i.e. 2:3) and `:80-95` `CoverGrid`; list-row thumbnail at `:185`, mini thumb at `:303`. |
| The details-sheet cover slot | `vreader-book-details.jsx:40-46` `DetailsStacked` → `CoverWithSwap` **leads the stacked body, above the title/author block**, 120×180; `:125` renders `<BookCover book …/>` for the cover-present state. |
| The no-art fallback tile | `vreader-generated-cover.jsx` `CoverMonogram` — **owned by #170**, not built here. |

**NOT depicted — two gaps. Both are now filed as `needs-design` #2110 (filed by the orchestrator,
not by this plan). **G1 blocks `WI-7`** (`BLOCKED: needs-design (#2110)`); **G2 was resolved by
moving the whole Book Details cover to #153** in round 2 — see the decision under G2.

> **G1 — how raster artwork fills the designed frame.** No file in the bundle contains an `<img>`,
> a `backgroundImage`, or any raster cover. Every depiction of `BookCover` / `Cover` /
> `CoverMonogram` fills the frame with *typography on a flat tonal ground*. The bundle therefore
> does not say: whether real artwork is **cropped to fill** or **letterboxed to fit** (and on what
> ground colour if letterboxed); whether the spine gradient and page-edge highlight **overlay** real
> artwork or are suppressed under it; and how a non-2:3 source (a square or 3:4 cover) is handled.
>
> **Severity: low, with a same-repo precedent.** iOS already answers G1 inside the same bundle:
> `vreader/Views/BookCoverArtView.swift:60-86` fills the frame with `scaledToFill()` + `.clipped()`
> at a fixed 2:3, then overlays `spineShadow`, `pageEdge`, the hairline and the drop shadow — i.e.
> crop-to-fill, accents on top. That is the answer this plan proposes for #2110 to ratify; the
> render spec in §4 is exactly that behaviour and nothing else.

> **G2 — a cover in Book Details with no swap affordance is not depicted anywhere** (raised as
> audit **H-4**; resolved here against the real files, since the auditor cited a non-existent path
> `dev-docs/designs/android/…` — the real root is `dev-docs/designs/vreader-fidelity-v1/project/`).
> The auditor's substance is **correct** and this plan's earlier dismissal of it was wrong:
> - In `vreader-book-details.jsx`, the pencil `aria-label="Replace cover"` button (`:128-140`) sits
>   **outside** the `missingCover` ternary — it renders in *both* branches. So every depicted
>   details-cover state, art-present included, carries a swap affordance.
> - `vreader-generated-cover.jsx` is indeed a committed **non-interactive** variant, but it depicts
>   only the **monogram (no-art) tile**, and its own text scopes itself explicitly: *"If a cover
>   store ever lands, the tile becomes the fallback and the swap controls return"* (`:31-34`). It
>   therefore does **not** license an art-present details cover without the swap controls; it says
>   the opposite.
>
> So `BookCoverArt` in Book Details minus the pencil and minus the `Add cover…` / `Replace cover…`
> Actions row (`:211-217`) is an undepicted composition. #152 cannot ship those controls either —
> they are #153's capability and would be dead controls (the #129 no-dead-control rule, and the very
> reason `vreader-generated-cover.jsx:5-11` dropped them).
>
> **DECIDED (round 2, audit NEW-1): the Book Details cover moves to #153, and WI-8 is removed from
> this feature.** Round 1 left this as prose while the work stayed wired in — the worst of both. It
> is now applied throughout: no `reader/details/` file appears in any write-set (§6), the details
> test is gone (§7), and the Gate-5 details route is gone (§9). #152 ships the library grid + list;
> the details sheet stays byte-identical to what #134 shipped.
>
> **Why removal rather than widening #2110.** The alternative is to commission a design for a
> details cover *without* swap controls. That composition is **transitional by construction**: the
> moment #153 lands the picker, `CoverWithSwap` — already depicted — replaces it. Rule 51's own
> anti-pattern table names this exactly ("Just a placeholder until v2 … Placeholders are committed
> code that ships in releases"). Asking a designer for a state whose lifetime is bounded by another
> feature in the same backlog is the thing the rule exists to prevent. #153 delivers the depicted
> end state in one step.
>
> **The inconsistency this creates, stated out loud rather than left for a reviewer to find.** Until
> #153 ships, **the library grid and list show real artwork while the Book Details sheet shows no
> cover.** Three things bound it, and one correction to how it is usually described:
> - It is **not** "details shows a fallback". Details shows **no cover block at all**
>   (`BookDetailsSheet.kt:128`, "No cover art (Design-gate #1)"). Nothing wrong or placeholder-ish
>   is rendered; a row is absent.
> - It is **not a regression**. That is precisely the sheet users see today, and it is a *designed,
>   committed* state — `vreader-generated-cover.jsx` was drawn specifically to compose the sheet
>   with no cover store present. #152 changes nothing on that surface.
> - The affected surface is a metadata sheet three taps deep (reader → `⋯` → Book details), not the
>   library the user opens the app into.
>
> **Honest assessment: acceptable, but not indefinitely** — #153 is currently priority **Low**, and
> "temporary" at Low priority can mean quarters. If the orchestrator judges the gap unacceptable,
> **the correct lever is to raise #153's priority, not to widen #2110** — the first buys the
> depicted end state, the second buys a throwaway one. This plan does not raise it (it may not edit
> the tracker); it flags the trade so the decision is made deliberately.

The pipeline WIs (WI-1…WI-6) are untouched by both gaps — zero visible delta — and proceed in
parallel per rule 51's "pause that slice, continue the designed slices".

**Explicitly NOT gaps** (each reuses an already-depicted state rather than inventing one):

- *Decode in flight* and *decode failed / cover file missing* → render **today's `FallbackCover`**,
  the state the app already ships. No new visual state is introduced, so nothing is self-designed.
- *Book Details for a book with no art* → keep the exact composition #134 shipped (no cover block).

---

## 3. Key design decisions

**D-1 — one `CoverStore`, keyed by fingerprint, shared with #153; the `hasCover` ordering is
reproduced at two layers.** iOS's guard is a single filesystem check *before* writing
(`BookImporter.swift:352`). Android reproduces it as:

- **File layer** — extraction never writes over an existing cover. A pre-check alone is a TOCTOU
  race (audit **H-5**: a #153 user pick landing between "extract started" and "save" would be
  silently overwritten, because `save()` overwrites unconditionally and the coordinator's `Mutex`
  only serialises *backfill* emissions, not the user's picker). So extraction uses a distinct,
  **non-replacing** entry point:

  ```kotlin
  /** Extraction-only: writes ONLY if no cover exists. Returns null if one already did. */
  suspend fun saveIfAbsent(key: String, bitmap: Bitmap): String?
  /** #153's user pick: replaces unconditionally. */
  suspend fun saveReplacing(key: String, bitmap: Bitmap): String?
  ```

  Both take the same per-key `Mutex` (a `keyLocks: ConcurrentHashMap<String, Mutex>` held across
  the existence re-check → temp write → `renameTo`), so the check and the rename are atomic with
  respect to each other and to #153. **The map is pruned where the cover is** (audit **NEW-5**):
  `CoverStore.remove(key)` and the orphan sweep both drop the key's entry after releasing it, so it
  is bounded by "books currently in the library", not by "keys ever seen". Not a scale problem at
  library sizes, but an unbounded-by-construction map is worth not shipping. `saveIfAbsent` re-checks existence **immediately before** the
  rename, inside the lock. A #153 user pick therefore wins whether it lands before, during, or
  after an extraction. Only `saveIfAbsent` exists in #152; `saveReplacing` is named here so #153
  extends the store instead of loosening `saveIfAbsent`.
- **DB layer** — `coverPath` / `coverExtractorVersion` join the exclusion list in
  `BookDao.updateImportedColumns` (`data/Daos.kt:63-77`) and are untouched by
  `applyRestoredMetadata` (`:103-113`), so a duplicate SAF import or a restore cannot null out a
  cover pointer. **This layer does not exist on iOS** and is required because Android's import path
  upserts an existing row rather than skipping it.

**D-2 — covers live in `filesDir/covers`, not `cacheDir` and not `noBackupFilesDir`.**
`filesDir/books` is the existing artifact precedent (`VReaderApp.kt:83`) and is iOS-equivalent
(Application Support). `cacheDir` is wrong because #153's user picks are not re-derivable and the OS
may evict it. `noBackupFilesDir` (the repo's convention for *per-device preferences* —
`VReaderApp.kt:69-74`) is wrong for the same #153 reason: the store is shared, so it must not be a
category the platform refuses to preserve. Consequence to record: the app declares no
`android:allowBackup` override, so `filesDir` is inside Android auto-backup's 25 MB quota; at ≤512 px
JPEG-80 a cover is ≈30–60 KB, so a 300-book library adds ≈10–18 MB. **`covers/` must NOT be added to
`res/xml/file_paths.xml`** — that file carries an explicit "do not widen" warning (`:7-8`) and
`filesDir/books` is intentionally the only FileProvider-granted subtree.

**D-3 — a `coverPath` column IS added, for reactivity, not for lookup.** Parity does not require it
(§0 finding 2). Android does, for one concrete reason: the library grid is driven by
`BookDao.observeAll(): Flow<List<BookEntity>>` (`Daos.kt:31-32`). Extraction finishes *after* the
row insert, and the backfill finishes long after first paint. Without a DB write there is no
reactive signal, so a newly extracted cover would appear only after an unrelated recomposition — a
visible "import a book, no cover until you leave and come back" defect. A column gets the repaint for
free and is the idiomatic Room/Compose answer; the alternative (a bespoke `StateFlow<Set<String>>`
cover bus) is more code and a second source of truth.

**D-4 — a second column, `coverExtractorVersion`, memoises the negative and provides the re-run
lever.** Without it, every backfill pass re-parses every art-less book — including opening a 6.3 MB
AZW3 or a whole EPUB — on every app start. This mirrors the strongest in-repo precedent:
`SearchIndexStateEntity.indexerVersion` + `SearchIndexCoordinator.isEligible`
(`search/SearchIndexCoordinator.kt:96-100`, `:213`). Two inline columns are used instead of a
`cover_state` table because the relation is strictly 1:1 with `books` and needs no status enum — the
tri-state falls out:

| `coverExtractorVersion` | `coverPath` | Meaning |
|---|---|---|
| `NULL` | `NULL` | never attempted (or a *transient* failure — retry) |
| `= COVER_EXTRACTOR_VERSION` | `NULL` | attempted, book genuinely has no art — **skip** |
| `= COVER_EXTRACTOR_VERSION` | set | have art |
| `< COVER_EXTRACTOR_VERSION` | either | parser improved — **re-attempt** |

The version is stamped **only on a definite outcome**. Extractors return a sealed
`CoverResult { Art | None | Failed }`; `Failed` leaves the version `NULL` so it is retried, while
`None` is memoised. Conflating the two would permanently blind a book whose file was momentarily
unreadable.

**The classification line is drawn on *content* vs *access*, not on exception type** (audit
**H-2**). This is the correction the `RandomAccessFile` change in D-6 forces and which the first
draft of this plan got wrong: over a memory-mapped `Data`, an out-of-range record is a bounds
*comparison*; over a `RandomAccessFile` it surfaces as `EOFException`, an `IOException`. Measured,
6 of 39 mutations diverged — cases ③ (record table truncated), ① (truncated mid-cover) and ⑨ (index
past EOF) all returned `Failed` where §7 expected `None`. Left as-is, **every truncated book would
be re-opened and re-parsed on every app start, forever** — exactly the cost D-4 exists to prevent,
and §7's test ③ would have failed against §4 as written. The binding rule:

| Outcome | Meaning | Examples |
|---|---|---|
| `None` (memoise) | The file was **reachable and structurally parsed**, and yields no cover — including because it is truncated, malformed, out of range, or its payload is not a decodable image. A re-read cannot change this. | truncated file, `numRecords == 0`, no EXTH, no 201/202, index past EOF, **EOF during a bounded record read**, undecodable payload, `PdfOpenResult.ProtectedOrUnsupported`/`Corrupt` |
| `Failed` (retry) | The file could not be **accessed at all**. A later attempt plausibly succeeds. | `localFilePath == null`, file does not exist, `FileNotFoundException`, `SecurityException`/permission, device I/O error on open |

Concretely: `MobiCoverParser` opens the file in a `try` that maps `FileNotFoundException`/
`SecurityException` → `Failed`, and every *subsequent* read (header, record table, record slice)
runs inside a bounded reader whose `EOFException` maps → `None`.

**D-5 — no image-loading dependency (Coil/Glide); a ~60-line bounded decoder + `LruCache`.** Every
cover is a local, app-written file already bounded to ≤512 px at save time, so a fetcher's main value
(network, cache negotiation, aggressive downsampling of arbitrary remote images) is unused, and the
app currently has **zero** image dependencies. The memory math is the real argument and it is stated
so the auditor can overturn it: a 3-column grid on a 1080p phone shows ≈21 cells; at
512×768 `ARGB_8888` that is 1.57 MB each ≈ **33 MB** if decoded full-size — unacceptable. So the
decoder computes `BitmapFactory.Options.inSampleSize` from the *measured* cell width (≈340 px → no
subsample; a 44 dp list thumb → subsample 4) and caches `ImageBitmap`s in a process-wide `LruCache`
with a byte budget of `Runtime.getRuntime().maxMemory() / 8`. **Overturn trigger, stated up front:**
if the WI-7 connected memory/jank measurement (§8) shows the grid's cover bitmaps exceeding 24 MB or
dropping frames on emulator-5554, adopt Coil instead — that is a plan-level pre-authorisation, not a
new decision to relitigate.

**D-6 — the MOBI parser is pure JVM and returns bytes, not a `Bitmap`.** `MobiCoverParser` has no
Android imports and returns the raw image `ByteArray`; a thin adapter does
`BitmapFactory.decodeByteArray`. This makes the riskiest code in the feature 100 % unit-testable in
the fast JVM lane with no Robolectric and no emulator.

---

## 4. Surface area

All Android paths are under `android/app/src/main/kotlin/com/vreader/app/`.

### New — `data/StorageNaming.kt`

```kotlin
/**
 * The ONE key→filename sanitisation used by every on-disk store (books, covers).
 * PRECONDITION: [key] is a canonical fingerprint key (`Identity.parseCanonicalKey(key) != null`).
 * The mapping is injective on that domain ONLY — it is not a general-purpose escaper.
 */
internal object StorageNaming {
    fun fileNameForKey(key: String): String = key.replace(Regex("[^A-Za-z0-9._-]"), "_")
}
```

Extracted **byte-identically** from `data/BookImporter.kt:155-156` (currently `private`), which then
delegates. Making the two stores *provably* share one scheme was a named Gate-2 finding on the
previous plan; a comment claiming they agree is not the same as calling the same function.

**On audit M-9 (collision) — the finding is right about the function and wrong about the fix, and
this plan takes the third option.** `a:b` and `a/b` do both map to `a_b`, and the earlier §7 test
asserting "sanitised-different keys do not collide" was self-contradictory — it is **deleted**. But
neither proposed remedy is safe here:

- *Changing the mapping* (or appending a hash) is **not** available: `fileNameForKey` already names
  every book file on every user's device, and `BookEntity.localFilePath` points at those names. A
  behaviour change silently orphans every existing library. This is a migration, not a tweak, and
  it is not worth one for a collision that cannot occur.
- *It cannot occur* on the real domain: `Identity.canonicalKey` (`android/identity/.../Identity.kt:22-23`)
  emits `"$format:$sha256:$byteCount"`, and `parseCanonicalKey` (`:33`) enforces a `BookFormat` raw
  value (`epub|pdf|txt|md|azw3`), 64 **lowercase hex**, and a non-negative `Long`. Every character
  is `[a-z0-9]` apart from the two `:` at structurally fixed positions, so the substitution is
  **injective** on that domain — two distinct canonical keys cannot produce one filename.

So: keep the mapping frozen, make the precondition explicit (`CoverPaths` calls
`require(Identity.parseCanonicalKey(key) != null)`; every call site passes `Book.fingerprintKey`,
canonical by construction), and replace the deleted test with (a) an **injectivity property test**
over generated canonical keys, (b) a rejection test for a non-canonical key, and (c) the existing
round-trip assertion. The earlier "unicode / 300-char key" cases are also deleted — those are not
valid keys, and testing a function against inputs its contract excludes is what produced the
contradiction.

### New — `library/covers/CoverPaths.kt` (pure `java.io`, no Android types)

```kotlin
class CoverPaths(private val root: File) {          // root = File(context.filesDir, "covers")
    fun coverFile(fingerprintKey: String): File     // root/<sanitised>.jpg
    fun hasCover(fingerprintKey: String): Boolean   // file exists AND length > 0
    fun remove(fingerprintKey: String)
}
```

Split out from the bitmap I/O so path/guard behaviour is testable in the JVM lane. (Robolectric's
`Bitmap`/`compress` are shadows — encode and downscale assertions are **not** trustworthy there and
belong to the connected lane. This is why the split exists.)

### New — `library/covers/CoverStore.kt`

```kotlin
class CoverStore(
    private val paths: CoverPaths,
    private val ioDispatcher: CoroutineDispatcher = Dispatchers.IO,
) {
    fun coverFile(key: String): File
    fun hasCover(key: String): Boolean
    /**
     * Downscale so max(w,h) <= MAX_EDGE_PX, JPEG-encode at QUALITY, write atomically —
     * ONLY if no cover exists (checked under the per-key lock, immediately before the rename).
     * Returns the absolute path, or null when a cover already existed or encoding failed.
     * BORROWS [bitmap]: it is read, never recycled, never retained after return.
     */
    suspend fun saveIfAbsent(key: String, bitmap: Bitmap): String?
    fun remove(key: String)
    companion object {
        const val MAX_EDGE_PX = 512      // iOS CustomCoverStore.maxDimension
        const val QUALITY = 80           // iOS jpegQuality 0.8
    }
}
```

Writes to `<name>.tmp` then `renameTo` so a kill mid-write cannot leave a truncated JPEG that later
decodes to garbage (`hasCover` additionally requires `length > 0`); the temp file is deleted in a
`finally`. Per-key locking and the `saveIfAbsent`/`saveReplacing` split are specified in D-1.

**The bitmap is BORROWED, never recycled** (audit **H-3** — the first draft said the opposite and
was wrong). The `.recycle()`-in-`save()` idea assumed `save` owned its argument. It does not:

- `Publication.coverFitting` is `cover()?.scaleToFit(maxSize)`, and `BitmapKt.scaleToFit` **returns
  `this` unchanged** when the source already fits (bytecode `34: aload_0 / 35: areturn`).
- `InMemoryCoverService` holds `private final android.graphics.Bitmap cover;` and hands back that
  retained field.

So WI-4's exact call can return the **`Publication`'s own live bitmap**; recycling it would corrupt
the publication's state, and it is only safe today by accident of which cover service the streamer
happens to install. Independently, a second `save` (a retry, or a backfill racing an import) would
hand an already-recycled bitmap to `compress()` → `IllegalStateException`, contradicting the
documented "null on encode failure" contract. Both defects are invisible to the grep that Risk-4
originally proposed as the mitigation. The fix is the codebase's existing posture — **let GC reclaim
it; there is no `.recycle()` anywhere in `android/app/src/main` and this feature adds none.**

### New — `library/covers/CoverResult.kt` (WI-3) and `library/covers/CoverExtractors.kt` (WI-6)

```kotlin
// CoverResult.kt — the shared vocabulary, landed by WI-3 because it lands first.
sealed interface CoverResult {
    @JvmInline value class Art(val bitmap: Bitmap) : CoverResult
    data object None : CoverResult     // reachable + structurally parsed, yields no cover — MEMOISE
    data object Failed : CoverResult   // could not be accessed at all — RETRY  (the D-4 split)
}

fun interface CoverExtractor { suspend fun extract(file: File): CoverResult }

// CoverExtractors.kt — the aggregator, landed by WI-6 once all three extractors exist.
class CoverExtractors(context: Context, bookOpener: BookOpener) {
    fun forFormat(format: BookFormat): CoverExtractor?   // null ⇒ format can never carry art
}
```

Routing (`BookFormat` is `epub | pdf | txt | md | azw3` — `identity/.../Identity.kt:11`; MOBI/AZW/PRC
all canonicalise to `azw3`, `DocumentFingerprint.kt:59-67`): `epub → EpubCoverExtractor`,
`azw3 → MobiCoverExtractor`, `pdf → PdfCoverExtractor`, `txt`/`md → null`. No extractor throws.

### New — `library/covers/EpubCoverExtractor.kt`

```kotlin
@OptIn(ExperimentalReadiumApi::class)                     // required by the OPENER, not by cover()
class EpubCoverExtractor(private val opener: BookOpener) : CoverExtractor {
    override suspend fun extract(file: File): CoverResult  // publication.coverFitting(Size(512, 512))
}
```

Uses the existing `reader/BookOpener.kt:44 open(file): Publication` seam and closes the publication
in a `finally` — the precedent is `search/EpubTextExtractor.kt:50/:68`, which already opens
publications off the reader for background indexing. `coverFitting` returns `null` when the manifest
has no `cover`-rel link (Readium's `ResourceCoverService` resolves it from
`links.firstWithRel("cover")`) → `CoverResult.None`; a thrown open/parse error → `Failed`.

### New — `library/covers/MobiCoverParser.kt` (pure JVM) + `MobiCoverExtractor.kt` (adapter)

A line-for-line port of `vreader/Services/AZW3/MOBICoverExtractor.swift` with three deliberate
Kotlin-specific corrections:

1. **Signed-byte masking.** Kotlin's `ByteArray[i]` is signed. Every big-endian read masks:
   `(b[i].toInt() and 0xFF shl 8) or (b[i+1].toInt() and 0xFF)`. An unmasked port silently corrupts
   any field with a high bit set — the same class as the FNV signed-`Byte` trap flagged on the
   previous plan.
2. **32-bit fields are `Long`, not `Int`.** The MOBI "not set" sentinel is `0xFFFFFFFF`, which is
   `-1` as a Kotlin `Int` — `co < 0xFFFFFFFF` would compare wrong. All offsets/indices are read as
   `Long` via `and 0xFFFFFFFFL` and only narrowed after the sentinel and bounds checks.
3. **Bounded reads instead of whole-file mapping.** iOS uses `Data(contentsOf:, .mappedIfSafe)`.
   Kotlin uses `RandomAccessFile` and reads only the 78-byte PDB header, the `numRecords * 8` offset
   table, record 0, and the single target image record — so a 6.3 MB (or 300 MB) book never lands in
   the heap.

The algorithm, restated so the implementer needs no second source (offsets are byte offsets into
record 0 unless stated):

- PDB header is 78 bytes; `numRecords` = BE `UInt16` at **file** offset 76; each record-table entry is
  8 bytes at `78 + i*8`, of which the first 4 are the record's file offset. A record spans
  `offsets[i] … offsets[i+1]` (or EOF for the last).
- **`sliceRecord` validates the span against the file BEFORE allocating** — three guards, all
  required (audit **C-1**, the one Critical):

  ```kotlin
  private fun sliceRecord(raf: RandomAccessFile, start: Long, end: Long): ByteArray? {
      val len = raf.length()
      if (start < 0 || start > len) return null          // start beyond EOF
      if (end <= start || end > len) return null         // end beyond EOF, or non-monotonic offsets
      if (end - start > MAX_RECORD_BYTES) return null    // 64 MiB — a cover this large is not a cover
      return ByteArray((end - start).toInt()).also { raf.readFully(it) }
  }
  ```

  **Why Critical and not a tidy-up.** Swift guards `end <= data.count` at
  `MOBICoverExtractor.swift:156`; the earlier §4 restatement said only "any bounds violation →
  `None`", and over a `RandomAccessFile` there is no implicit `data.count` ceiling the way there is
  over a mapped `Data`. The record's **end** comes straight from the attacker-controlled record
  table. Measured on a real book with record-table entry 136 set to `0x7FFFFFF0` → a computed length
  of **2,147,138,052 bytes**:

  ```
  -Xmx64m … -Xmx1g   ->  THREW | java.lang.OutOfMemoryError | Java heap space
  IOS_FAITHFUL       ->  None | target record unreadable
  ```

  `OutOfMemoryError` is an **`Error`, not an `Exception`**, so the `catch (e: Exception)` implied by
  this plan's "no extractor throws" contract does **not** catch it: it propagates out of the
  coroutine, kills the app-scope backfill for the entire library, and on a low-memory device can
  take the process — defeating Risk-9's structural "extraction cannot break the app" guarantee. It
  also fires on record 0 and on `end = 0xFFFFFFFF`. The guards above are the fix; §7 tests all three
  (start-past-EOF, end-past-EOF, over-cap). `CoverCoordinator` additionally catches `Throwable`
  (rethrowing `CancellationException`) as defence in depth — but a bounded allocation is the real
  fix, since catching `OutOfMemoryError` after the fact does not make the heap healthy.
- Record 0 = PalmDOC header (16 bytes) + MOBI header. Require `record0.size >= 132`. ASCII `"MOBI"`
  must sit at 16..20; MOBI header length is BE `UInt32` at 20.
- **`firstImageIndex`** = BE `UInt32` at **108** = `16 + 92` — MOBI-header field "First Image index",
  an **absolute PDB record index** (proven, not inferred — §0.1). **It carries the same
  `0xFFFFFFFF` "not set" sentinel as EXTH-201/202 and must be checked for it** (audit **M-8**):
  a real committed fixture, `vreader/Resources/DebugFixtures/divider-azw3.azw3`, has
  `rec0[108..111] = FF FF FF FF` with `exthFlag = 0x50` (bit `0x40` set, so EXTH *is* present) —
  independently confirmed here by parsing the file. `firstImageIndex == 0xFFFFFFFF` → `None`,
  checked **before** the EXTH scan. This is benign today only because that fixture has no usable
  EXTH-201; it is exactly the field the `Long` correction protects — on the `Int` path the sentinel
  reads as `-1` and a valid EXTH-201 would yield `rec[134]`, a non-image record.
- EXTH flag = BE `UInt32` at **128** (`16 + 112`); bit `0x40` must be set or there is no EXTH → `None`.
- EXTH block starts at `16 + mobiHeaderLength`; ASCII `"EXTH"`, then BE `UInt32` length at `+4` and
  BE `UInt32` record count at `+8`; records begin at `+12`, each `{type: u32, length: u32, payload}`
  where `length` counts the 8-byte header, so `length >= 8` and the cursor advances by `length`.
- Type **201** = cover offset, type **202** = thumbnail offset, each a 12-byte record whose 4-byte
  payload is an index **relative to `firstImageIndex`**. Prefer 201; fall through to 202; treat
  `0xFFFFFFFF` as unset; neither present/set → `None`.
- Target record index = `firstImageIndex + relativeIndex`; slice that record and return its bytes.
  Any bounds violation → `None` (a structurally-parsed file that simply doesn't yield an image), an
  `IOException` → `Failed`.
- The adapter's `BitmapFactory.decodeByteArray` returning `null` (payload is not a decodable image,
  e.g. DRM-encrypted) → `None`.

**Known limitation — and it ships UNTESTED, stated plainly** (audit **M-7**). A combined MOBI6+KF8
(`.azw3`) file has two parts; this parser reads record 0 of the **first** part only, exactly as iOS
does. If a book's art lives solely in the KF8 part the result is `None` (a blank fallback, never a
crash). The earlier claim that "the real 6.3 MB CJK AZW3 is the Gate-5 check on whether that
matters" is **false and is withdrawn**: all 153 records of that book — and of both other AZW3
fixtures — were scanned for `BOUNDARY` markers and second MOBI headers, and there are **zero hits**.
Every available fixture is a single-part `mobiType = 2` MOBI6 file *despite the `.azw3` extension*,
so no test in this plan can exercise the dual-part path. Either a genuine KF8 file is sourced (none
is available in the corpus today, and constructing one by hand is disproportionate), or **the
limitation ships untested** — which is the choice this plan makes, on the grounds that iOS ships the
identical limitation against the identical corpus with no field reports. Recorded in the Gate-5
evidence file as a named residual, not silently omitted.

### New — `library/covers/PdfCoverExtractor.kt`

```kotlin
class PdfCoverExtractor(private val ioDispatcher: CoroutineDispatcher = Dispatchers.IO) : CoverExtractor
```

Opens its own short-lived document via the existing `PdfDocument.open(file)` factory
(`reader/PdfDocument.kt:86`), renders page 0 through `renderPage(0, MAX_EDGE_PX)` — which already
holds the `Mutex`, opens/closes the page in a `finally`, and derives height from the page aspect —
then `close()`s in a `finally`. `PdfOpenResult.ProtectedOrUnsupported` / `Corrupt` → `None`
(a password-protected PDF is not a failure to retry); `pageCount == 0` → `None`. **Not iOS parity**
(§0 finding 1) — an Android-only extra justified by the renderer already existing.

### New — `library/covers/CoverCoordinator.kt`

```kotlin
class CoverCoordinator(
    private val repository: LibraryRepository,
    private val store: CoverStore,
    private val extractors: CoverExtractors,
    private val scope: CoroutineScope,
    private val ioDispatcher: CoroutineDispatcher,
) {
    fun start()                          // idempotent: AtomicBoolean, like SearchIndexCoordinator
    fun enqueue(fingerprintKey: String)  // the ONE admission point (import hook + backfill)
    companion object {
        const val COVER_EXTRACTOR_VERSION = 1
        const val EXTRACTION_WORKERS = 1
    }
}
```

`ensureCover` is **private**: nothing outside the coordinator may start an extraction directly, which
is what makes the concurrency bound below an invariant rather than a convention.

Modelled directly on `search/SearchIndexCoordinator.kt:59-100` (the repo's only background-backfill
precedent — a process-scope coroutine on `AppContainer.appScope`, started from
`VReaderApp.onCreate`; **not** WorkManager, which the app does not depend on):

- `start()` guards with `AtomicBoolean.compareAndSet` so a second call is a no-op, and serialises
  books through a `Mutex` so overlapping `observeLibrary()` emissions cannot interleave.
- **Eligibility** (`isEligible`, deliberately mirroring the search gate one-for-one):
  `coverExtractorVersion == null` → run; `!= COVER_EXTRACTOR_VERSION` → run;
  `coverPath != null && !File(coverPath).exists()` → run (self-heal a deleted file); else skip.
- **Book file gone** (`localFilePath == null` or the file does not exist) → `Failed`: leave the
  version `NULL`, write nothing, log at warn. It becomes eligible again if the file returns.
- **Already has a cover file** (`store.hasCover(key)`, i.e. a #153 user pick) → never extract; just
  reconcile the DB pointer to the existing file.
- **Process death mid-backfill** → nothing to recover: state is per-book and only ever written after
  a definite outcome; the next `start()` resumes from the first ineligible book.
- **Concurrent runs** → impossible within a process (the `AtomicBoolean` + `Mutex`); across the
  import path and the backfill, both funnel through `ensureCover`, whose only mutation is the
  version-gated DAO update, which is idempotent.
- **Cheap "already done"**: for a settled book the cost is one integer comparison on a row the flow
  already delivered, plus (only when `coverPath != null`) one `File.exists()`. No file is opened, no
  parser runs.
- **Every `ensureCover` body is wrapped in `catch (e: CancellationException) { throw e }` followed by
  `catch (t: Throwable)`** → `Failed`, so no single book can kill the worker (the defence-in-depth
  half of C-1) while structured concurrency still holds. The order is load-bearing: `Throwable`
  first would swallow cancellation. Same shape as `SearchIndexCoordinator.kt:118-124`.
- **Deletion + orphan cleanup — driven by the flow, not by a call into the repository** (audit
  **M-10**, then **NEW-2**). Round 1 had `LibraryRepository.deleteBook` call
  `coverCoordinator.onBookDeleted`, while the coordinator takes `LibraryRepository`. That is a
  genuine cycle, and it also inverts the module's layering: `LibraryRepository` is a DAO boundary
  whose stated contract is "callers get value-type DTOs, never Room entities"
  (`data/LibraryRepository.kt:1-5`) — it names no coordinators.

  **Neither proposed remedy is taken, because neither is needed.** An orchestrator that owns both,
  or an injected `onBookDeleted` callback, both preserve a delete-time coupling — and, as the
  finding itself warns, a callback wired at the coordinator relocates the cycle into the DI graph.
  Two facts remove the need entirely:

  1. **`deleteBook` has ZERO production call sites.** Grepped across `android/app/src`: the only
     hits are its own definition (`LibraryRepository.kt:87`) and **13 references across 8 test
     files** (count corrected in round 3 — the earlier "13 test files" conflated references with
     files). Android ships no delete-a-book UI today, so wiring cleanup into `deleteBook` would add
     a dependency cycle in order to reach dead code.
  2. **The coordinator already collects the library flow**, and `BookDao.observeAll()`
     (`data/Daos.kt:31-32`) is unfiltered `SELECT * FROM books`. A book disappearing from that flow
     **is** the deletion signal — and because deleting a row makes Room re-emit, it arrives
     immediately, not eventually.

  So cleanup is a **set delta on the stream the coordinator already has**: it holds the previous
  emission's key set; on each emission, `previous − current` is exactly the books deleted, and their
  cover files (and `keyLocks` entries — NEW-5) are removed.

  **The first emission INITIALISES the baseline; it never deletes** (round-3 finding). `previousKeys`
  is `Set<String>?` initialised to **`null`**, not to the empty set, and the delta is computed only
  when it is non-null:

  ```kotlin
  private var previousKeys: Set<String>? = null   // null = "no baseline yet", NOT "library was empty"
  // …per emission:
  val current = books.mapTo(HashSet()) { it.fingerprintKey }
  previousKeys?.let { prev -> (prev - current).forEach { removeCoverFor(it) } }
  previousKeys = current
  ```

  The `null` sentinel makes mass deletion structurally impossible on a cold start, and — more to the
  point — on any *re-collection* of the flow. `start()`'s `AtomicBoolean` already prevents a second
  collector within a process, but a fresh coordinator over the same store (process restart, or a
  future refactor that restarts the collector) must not read its first emission as "everything
  before this was deleted". Distinguishing `null` from `emptySet()` is what guarantees that: an
  empty *library* legitimately deletes the covers of books that just went away, while an absent
  *baseline* deletes nothing. `sweepOrphans()` remains the only path that removes covers without a
  delta, and it decides per file against the current key set rather than against history. This is O(delta), needs no directory
  listing per emission, adds **no** new dependency in either direction, and keeps `LibraryRepository`
  untouched. A **full `sweepOrphans()` runs once per `start()`** — list `covers/`, drop any file
  matching no current key — as the backstop for deletions that happened while the process was dead,
  for a delete that failed, and for covers predating this feature. Deletion of a key takes that key's
  `Mutex`, so it cannot race a save mid-rename. Every delete is idempotent and non-throwing (a
  missing file is a no-op; a failed unlink is logged and swept later).

- **Extraction concurrency is bounded at ONE, at a single admission point** (audit **NEW-3**). Round
  1 wired the import hook as `appScope.launch { ensureCover(book) }` **per import**, while `start()`
  serialised only the *backfill* flow — so `RestoreImporter`'s per-book loop (`RestoreImporter.kt:83`)
  could launch **200 concurrent** extractions on a 200-book restore, each opening a `Publication` or
  a `PdfRenderer` and decoding a bitmap. The finding is right that this is worse than C-1: it arrives
  by design, on the happy path, with no malformed input.

  Both the import hook and the backfill now call **`enqueue(key)`**, which offers the key to a
  `Channel<String>(UNLIMITED)`, drained by **`EXTRACTION_WORKERS = 1`** worker coroutine on the IO
  dispatcher. Keys, not `Book` objects, are queued so the worker re-reads current state rather than
  acting on a stale snapshot.

  **The admission set is concurrent, because the producers are** (round-3 finding). `enqueue` is
  public and non-suspending and is called from the import hook *and* the flow collector, so a plain
  `MutableSet` guarding the dedupe is unsafe:

  ```kotlin
  private val admitted = ConcurrentHashMap.newKeySet<String>()   // NOT a plain MutableSet
  private val queue = Channel<String>(Channel.UNLIMITED)

  fun enqueue(key: String) {
      // add() is an atomic test-and-set: exactly one racing producer wins, the rest drop.
      if (admitted.add(key) && queue.trySend(key).isFailure) admitted.remove(key)
  }

  // the single worker:
  for (key in queue) {
      try { ensureCover(key) } finally { admitted.remove(key) }   // ALWAYS — see below
  }
  ```

  Two ordering details are load-bearing, and the second is why the test must assert *loss*, not just
  duplication:

  - **`admitted.remove` runs in a `finally`, after the work.** Removing before completion reopens the
    double-extraction window; the `trySend`-failure rollback exists for the same reason (a key
    admitted but never queued would be a phantom in-flight forever).
  - **A lost race on the removal side is a silent permanent miss, not a visible duplicate.** If the
    key is never removed from `admitted`, every future `enqueue` for it is dropped and its cover is
    **never** extracted — no error, no retry, nothing in the log. That asymmetry is the reason this
    is worth a dedicated test rather than an eyeball.

  **A dropped duplicate is safe by construction**: the loser of the dedupe race is discarded rather
  than queued, and correctness does not depend on it — the worker re-reads the book by key at
  extraction time (so it always sees current state), the flow collector re-evaluates eligibility on
  every emission, and `sweepOrphans()`/the version gate catch anything missed across a restart.

  **Why 1, and not a larger bound:**
  - **Precedent.** `SearchIndexCoordinator` does exactly this — `collect` (not `collectLatest`) with
    `mutex.withLock { indexIfEligible(book) }`, one book at a time regardless of emission rate
    (`SearchIndexCoordinator.kt:60-83`). Covers are the same class of work: background, best-effort,
    latency-insensitive.
  - **It removes the memory question instead of bounding it.** The transient peak is one decoded
    source bitmap. A large publisher cover (say 2000×3000 `ARGB_8888`) is ≈24 MB *before* the 512 px
    downscale; at K=1 that is the ceiling, at K=4 it is ≈96 MB — back inside the failure mode C-1
    was about, on a mid-range heap.
  - **Nothing waits on it.** No UI blocks on a cover; the grid renders the designed fallback until
    one exists. A 200-book restore finishing its covers over ~a minute of background work costs the
    user nothing.
  - **It makes the bound testable as a bound** — "at most K concurrent" is a clean assertion, and at
    K=1 a spy extractor can assert strict non-overlap rather than a statistical maximum.

  `EXTRACTION_WORKERS` is a named constant precisely so raising it is a one-line change if the
  Gate-5 on-target measurement shows the backfill is unacceptably slow. It is not raised
  speculatively.

**Where extraction is triggered — all four import surfaces, not one** (audit **M-11**). The earlier
plan hooked only `LibraryViewModel`, which is **one of four** callers of `BookImporter.importStream`.
Verified call sites:

| Surface | Call site |
|---|---|
| SAF picker (library `+`) | `library/LibraryViewModel.kt:182` |
| Open-with / inbound share | `imports/IncomingImportCoordinator.kt:364` and `:576` |
| OPDS acquisition | `opds/OpdsAcquisitionService.kt:38` |
| WebDAV restore | `backup/RestoreImporter.kt:168` |

Hooking each separately guarantees the next import surface forgets. Instead the trigger goes where
all four already converge — `BookImporter` gains an injected post-import callback:

```kotlin
class BookImporter(
    …,
    private val onImported: (Book) -> Unit = {},   // tail default: no call site breaks
)
// …at the end of importStream, after the upsert. NON-FATAL by construction, but
// cancellation still propagates — `runCatching` alone would swallow it (NEW-4).
try {
    onImported(book)
} catch (e: CancellationException) {
    throw e
} catch (t: Throwable) {
    log.w("cover hook failed for ${book.fingerprintKey}", t)
}
```

The `runCatching` in round 1 was wrong for the reason the audit gives: it catches `Throwable`,
including `CancellationException`, breaking structured concurrency. The codebase rethrows it
consistently — `LibraryViewModel.kt:183` ("honor structured cancellation — not a real import
failure"), `RestoreImporter.kt:87` ("never swallow coroutine cancellation as a per-book failure"),
`SearchIndexCoordinator.kt:118`. The explicit two-catch form above matches them. (The coordinator's
own broad catch already specified the rethrow in round 1 — only the hook was defective.)

Production wires `onImported = { book -> coverCoordinator.enqueue(book.fingerprintKey) }`. Note the
callback is **non-suspending** and does no work: `enqueue` is a channel offer, so the import path
neither blocks nor spawns. The `appScope.launch`-per-import of round 1 is gone — that was NEW-3's
fan-out — a 200-book restore now enqueues 200 keys that one worker drains. The importer keeps zero
knowledge of `Context`, Readium or `PdfRenderer` (it invokes a plain lambda), so "an import can never
fail on covers" stays structural rather than a `try/catch` a future edit can delete. A test asserts
the callback fires from a restore-shaped call, not just the SAF one.

### New — `library/covers/BookCoverArt.kt` + `CoverImageCache.kt` (Compose)

```kotlin
@Composable
fun BookCoverArt(
    coverPath: String?,
    fallbackSeed: String,       // fingerprintKey — drives today's tint choice, and #170's style later
    title: String,
    modifier: Modifier = Modifier,
    cornerRadius: Dp = 4.dp,
)
```

The single render seam for the grid card, the list row and the details sheet. The 2:3 box is imposed
by the **modifier**, never by the drawn content, so a `LazyVerticalGrid` row keeps a uniform height
regardless of source dimensions (the invariant iOS records at `BookCoverArtView.swift:8-12`).
Content order inside the clip, per §2 G1 / the iOS precedent: bitmap (`ContentScale.Crop`) → 6 dp
spine gradient → 2 dp page-edge gradient → hairline border → drop shadow. `coverPath == null`, a
missing file, or a decode failure all render **today's `FallbackCover` body** unchanged (§2).

`CoverImageCache` (object): `suspend fun load(path: String, targetWidthPx: Int): ImageBitmap?` —
`BitmapFactory` two-pass (`inJustDecodeBounds` → `inSampleSize`) on `Dispatchers.IO`, results in an
`LruCache` keyed by `path + '@' + sampleSize` with `sizeOf` = byte count and
`maxSize = maxMemory()/8`. Decoding is launched from `produceState(coverPath, targetWidthPx)` — the
same shape `PdfReaderScreen.kt:283-287` already uses — and **no bitmap is ever `recycle()`d on the
Compose path** (#115).

### Modified

| File | Change |
|---|---|
| `data/Entities.kt:23-34` | `BookEntity` gains `val coverPath: String? = null` and `val coverExtractorVersion: Int? = null` — **tail defaults**, the `author` v6 pattern, so no positional construction site breaks. |
| `data/VReaderDatabase.kt` | `version = 9` → `10`; add `MIGRATION_9_10` (two `ALTER TABLE books ADD COLUMN`) and append to `ALL_MIGRATIONS`; update the file-header migration ledger (`:1-12`, rule 22). |
| `data/Daos.kt` | Add `@Query("UPDATE books SET coverPath = :path, coverExtractorVersion = :version WHERE fingerprintKey = :key") suspend fun setCoverState(key, path, version)`. **Do not** add the new columns to `updateImportedColumns` (`:63-77`) — the whole point is that they stay excluded — and extend that method's KDoc to say so. Confirm `applyRestoredMetadata` (`:103-113`) also leaves them alone. |
| `data/LibraryRepository.kt:19-30` | `Book` gains the two fields; `toEntity`/`toDomain` map them; add `suspend fun setCoverState(...)` passthrough. |
| `data/BookImporter.kt` | Extract `fileNameForKey` → `StorageNaming` (delegate). Add the `onImported: (Book) -> Unit = {}` constructor param + the tail call guarded by `catch (CancellationException) { throw e }` then `catch (Throwable)` (M-11 + NEW-4 — **not** `runCatching`, which swallows cancellation). The importer still holds **no** cover knowledge — no `Context`, no Readium, no `PdfRenderer`, just a plain lambda. |
| `library/LibraryViewModel.kt:41-51`, `:193-200` | `LibraryBook` gains `val coverPath: String? = null` (tail default); `toUi` maps it. **No import hook here** — the trigger moved into `BookImporter` so all four import surfaces get it (M-11). |
| ~~`data/LibraryRepository.kt`~~ | **Not modified** (NEW-2). Deletion cleanup is a set delta on the library flow the coordinator already collects, plus a `start()` sweep — no cycle, no callback, and no edit to a DAO boundary whose only `deleteBook` callers are tests. |
| `library/LibraryScreen.kt` | Both `FallbackCover(...)` call sites → `BookCoverArt(...)`: grid `:188` (radius 4 dp, `aspectRatio(104f/156f)` unchanged) and list row `:235` (44×62 dp, radius 3 dp). `FallbackCover` itself stays (it is the no-art body) and is moved behind `BookCoverArt`. |
| ~~`reader/details/*`~~ | **Not modified** — the details cover moved to #153 (§2 G2 / NEW-1). `BookDetailsUiModel`, `BookDetailsMapper` and `BookDetailsSheet` are untouched by #152, and their existing "no `coverPath`" / "No cover art (Design-gate #1)" comments stay **accurate** rather than needing a rule-22 rewrite. |
| `VReaderApp.kt` | Wire `coversDir = File(appContext.filesDir, "covers")`, `coverPaths`, `coverStore`, `coverExtractors(bookOpener)`, `coverCoordinator`; pass `onImported` into `BookImporter`; call `coverCoordinator.start()` from `onCreate` next to `startSearchIndexing()` (`:526`). |

### Files explicitly OUT of scope

- **`backup/*`, `contracts/*`, `contracts/vectors/*`** — a cover is a derived local cache,
  re-derivable from the book file. Adding a field would break golden-vector conformance with iOS,
  which also persists nothing (§0 finding 2). Restore re-imports the file, so covers rebuild.
- **The generative typographic fallback** (`vreader-generated-cover.jsx`) → **#170**.
- **User-chosen covers + the pencil/`Add cover…` affordances** → **#153**.
- **The Book Details cover** (`reader/details/*`) → **#153** (NEW-1). #153 inherits both the render
  work and design gap **G2**; landing the picker makes `CoverWithSwap` fully depicted, so #153 ships
  the cover and its swap controls together and G2 dissolves. #153's row should record that it now
  carries this, and that `BookDetailsUiModel`/`Mapper`/`Sheet` are its write-set, not #152's.
- **Library sort** → **#154** (also edits `LibraryScreen.kt`; one writer at a time — never dispatch
  #152, #153, #154, #170 concurrently, per the row).
- **The continue-rail cover** — iOS has `LibraryContinueCard`; Android has no continue rail. Not a
  regression, not in scope.
- **OPDS remote thumbnails** (#120) — a network source, different subsystem.
- **`res/xml/file_paths.xml`** — see D-2.

---

## 5. Prior art / precedent / rejected alternatives

**Prior art (iOS, read in full).** `BookImporter.swift:351-355` (Step 9.5, non-fatal, `hasCover`-
guarded), `MetadataExtractor.swift:54-66` (opt-in `extractCoverImage`, default `nil`),
`:92-117` (EPUB, incl. the bug #122 href cascade), `:294-296` (AZW3 → `MOBICoverExtractor`),
`CustomCoverStore.swift` (512 px / JPEG 0.8 / sanitised filename), `BookCoverArtView.swift`
(the frame + the fixed-ratio invariant).

**In-repo Android precedent.** `SearchIndexCoordinator` (backfill shape, version lever, eligibility
predicate, failure isolation); `MIGRATION_5_6` (nullable column, tail default); `PdfDocument`
(renderer discipline); `EpubTextExtractor` (opening a `Publication` off the reader);
`BookDao.upsertPreservingAuthor` (column-scoped update as a no-clobber guard); `BookMagicSniffer`
(format detection already handles MOBI magic).

**Rejected — extract lazily at render time.** Puts ZIP/PDF/MOBI parsing on the scroll path.
Extraction happens once at import plus one version-gated backfill, as on iOS.

**Rejected — a WebView/foliate-js round-trip for AZW3 covers.** Needs a live WebView per import; the
native parse is synchronous, testable, and already written and proven on iOS.

**Rejected — Coil/Glide.** See D-5, including the explicit pre-authorised overturn trigger.

**Rejected — filesystem-only, no DB column** (the pure iOS shape). Loses Room-`Flow` reactivity
(D-3) and the memoised negative (D-4). Recorded because it is the *closest* parity option and a
reviewer will ask.

**Rejected — a `cover_state` table** mirroring `search_index_state`. Correct shape when the relation
needs a status enum and its own lifecycle; here it is 1:1 with `books` and two nullable columns
express the full state (D-4).

---

## 6. Work-item sequencing

**Eight WIs** (WI-8 removed in round 2; the remaining IDs keep their numbers so every cross-reference
in this document, in #2110 and in the round-1/round-2 audit artifacts stays valid). New Kotlin files
are lane-dispatchable (no `xcodegen` structural regen — the rule-55
"new Swift files are not dispatchable" degrade does not apply to Android). Android dispatches at
width 1 (rule 55 — one emulator).

**Write-sets are exact FILE lists, not directory prefixes** (audit **M-12**). The earlier table gave
five WIs the same `library/covers/` prefix while calling two of them parallelisable — which
`scripts/check-write-set.sh` would have accepted and a real concurrent run would have corrupted. No
two WIs below share a file.

| WI | Tier | Depends | Exact writes (main) | Exact writes (test) |
|---|---|---|---|---|
| **WI-1** | foundational | — | `data/StorageNaming.kt` (new), `data/BookImporter.kt` (delegate only), `library/covers/CoverPaths.kt` (new) | `test/…/data/StorageNamingTest.kt`, `test/…/library/covers/CoverPathsTest.kt` |
| **WI-2** | foundational | — | `data/Entities.kt`, `data/VReaderDatabase.kt`, `data/Daos.kt`, `data/LibraryRepository.kt` | `test/…/data/VReaderDatabaseMigrationTest.kt`, `test/…/data/BookDaoCoverStateTest.kt` |
| **WI-3** | foundational | — | `library/covers/MobiCoverParser.kt`, `library/covers/MobiCoverExtractor.kt`, `library/covers/CoverResult.kt` (the sealed type + `CoverExtractor` interface — WI-3 owns it because it lands first) | `test/…/library/covers/MobiCoverParserTest.kt`, `androidTest/…/library/covers/MobiCoverRealBookTest.kt` |
| **WI-4** | foundational | WI-3 (for `CoverResult`) | `library/covers/EpubCoverExtractor.kt` | `androidTest/…/library/covers/EpubCoverExtractorConnectedTest.kt` |
| **WI-5** | foundational | WI-3 (for `CoverResult`) | `library/covers/PdfCoverExtractor.kt` | `androidTest/…/library/covers/PdfCoverExtractorConnectedTest.kt` |
| **WI-6** | behavioral | WI-1..WI-5 | `library/covers/CoverStore.kt`, `library/covers/CoverExtractors.kt`, `library/covers/CoverCoordinator.kt`, `data/BookImporter.kt` (the `onImported` hook), `VReaderApp.kt`, `library/LibraryViewModel.kt` (`coverPath` on `LibraryBook` only) | `androidTest/…/library/covers/CoverStoreConnectedTest.kt`, `…/CoverStoreUserPickRaceTest.kt`, `…/CoverCoordinatorConnectedTest.kt`, `…/CoverConcurrencyConnectedTest.kt`, `…/CoverDeletionConnectedTest.kt`, `…/BookImporterCoverConnectedTest.kt`, `test/…/library/covers/CoverAdmissionSetConcurrencyTest.kt`, `test/…/data/BookImporterHookSurfacesTest.kt`, `test/…/data/BookImporterHookCancellationTest.kt` |
| **WI-7** | behavioral | WI-6 | `library/covers/CoverImageCache.kt`, `library/covers/BookCoverArt.kt`, `library/LibraryScreen.kt` | `androidTest/…/library/BookCoverArtConnectedTest.kt`, `…/LibraryCoverAdoptionConnectedTest.kt` |
| ~~**WI-8**~~ | — | — | **MOVED TO #153** (NEW-1) — no `reader/details/` file is in #152's write-set | — |
| **WI-9** | behavioral | WI-7 | — | `androidTest/…/library/CoverAcceptanceConnectedTest.kt`, `dev-docs/verification/feature-152-<date>.md` |

**Honest parallelism.** WI-1, WI-2 and WI-3 are mutually disjoint and may run concurrently (subject
to the width-1 emulator constraint — WI-3's connected test needs the device). WI-4 and WI-5 are
disjoint **from each other** but both depend on WI-3 landing `CoverResult.kt`, so they are
*sequential to WI-3, parallel to one another*, and each needs the emulator — in practice they
serialise on the device, so the plan claims **no** parallel speed-up, only isolation. WI-6 onward is
a strict chain (WI-6 rewrites files three earlier WIs created).

**WI-7 is `BLOCKED: needs-design (#2110)`** (§2 G1 — the artwork fill policy). WI-1…WI-6 are
unaffected and ship on their own: the pipeline lands, the pixels wait. **#152 now completes at WI-7
+ WI-9**; G2 and the details render travel with #153.

Per-WI acceptance criteria are the test rows in §7 plus, for every WI: the wrapper's
`RUN-ANDROID-TESTS RESULT: SUCCEEDED` line, a committed Gate-4 audit artifact whose filename is
**branch-derived**, and no write outside the declared prefixes.

---

## 7. Test catalogue

Lane legend: **JVM** = `ANDROID_CMD="./gradlew :app:testDebugUnitTest" scripts/run-android-tests.sh`;
**connected** = `scripts/run-android-verify.sh` with `ANDROID_SERIAL=emulator-5554`, **one test class
per run** (a comma-joined `class=A,B` fast-fails with `tests=0` — #129/#133 precedent), on a
cold-booted emulator, never driving the device while a run is in flight (rule 52 Cause D).

| Test | Lane | Cases |
|---|---|---|
| `StorageNamingTest` | JVM | canonical key → expected name; **asserts `BookImporter` and `CoverPaths` derive the same name for the same key** (one function, not two); no separator survives; **injectivity over generated canonical keys** (all five formats × varied sha/byte-count → all distinct filenames); a non-canonical key is rejected by `CoverPaths`' `require`. *(The old "sanitised-different keys do not collide" and "unicode / 300-char key" cases are deleted — see §4 M-9: they assert behaviour the contract excludes.)* |
| `CoverPathsTest` | JVM | `hasCover` false before / true after a non-empty file / **false for a zero-length file**; `remove` idempotent (missing file is a no-op, never throws). |
| `MobiCoverParserTest` | **JVM, the largest suite** | **Thirteen structural failure modes** (this is the riskiest code, and the three added here are the ones that actually crash): ① truncated file (< 78 bytes) → `None`; ② PDB with `numRecords == 0` → `None`; ③ record table truncated → `None`; ④ record 0 shorter than 132 bytes → `None`; ⑤ missing `"MOBI"` magic → `None`; ⑥ EXTH flag bit `0x40` clear → `None`; ⑦ EXTH present, no 201 and no 202 → `None`; ⑧ 201 = `0xFFFFFFFF` → falls through to 202; both unset → `None`; ⑨ `firstImageIndex + rel` ≥ `numRecords` → `None`; ⑩ target record is not a decodable image (DRM/garbage) → `None` at the adapter; **⑪ record END beyond EOF** (the C-1 case — entry 136 = `0x7FFFFFF0` on a real-book copy; must return `None`, and the test asserts **no `OutOfMemoryError` escapes** at `-Xmx64m`); **⑫ record START beyond EOF** → `None`; **⑬ span exceeding `MAX_RECORD_BYTES` (64 MiB)** → `None` without allocating. Plus: 201 preferred over 202; **high-bit decoding** (`numRecords` ≥ 0x8000 — the real book's `00 99` unmasked is −103 — and a record offset ≥ 0x80000000); non-monotonic offsets (`end <= start`) → `None`; **`firstImageIndex == 0xFFFFFFFF` → `None`** (M-8, using a copy of `divider-azw3.azw3`'s header shape *with* a valid EXTH-201 present, so the sentinel is what decides); EXTH `recordCount` absurdly large → scan terminates, `None`; EXTH `length` overrunning record 0 → `None`; EXTH record with `length < 8` terminates instead of looping; a 300 MB sparse file parses at `-Xmx16m` with no heap growth. |
| `MobiCoverResultClassificationTest` | JVM | **The H-2 contract, tested as a contract, not incidentally**: every one of ⑪…⑬ and ①③⑨ returns **`None`** (content → memoise); a file that does not exist, and one made unreadable, return **`Failed`** (access → retry). Guards the exact regression the `RandomAccessFile` switch introduces. |
| `MobiCoverRealBookTest` | **connected; the fixture MUST be pushed per run** | `androidTest/assets/foliate-spike/book.azw3` yields the correct cover — **record 135, 379,691 bytes, 542×800**, digest-pinned. **ERRATUM (WI-3, 2026-08-06) — audit finding L-13 was WRONG and is withdrawn.** The byte-identity half is true and re-confirmed (`md5 f4ae9259b82cc2a765242bebd015df84`, 6,288,371 B). The conclusion is false: `android/app/src/androidTest/assets/foliate-spike/.gitignore` contains exactly `book.azw3`, `git ls-files` on that directory returns only `.gitignore`, `bundle-patch.md`, `foliate-bundle.js` and `reader.html`, the asset has **never been tracked**, and it is absent from a fresh worktree — six existing `androidTest` files already `assumeTrue`-skip on it. The repo also has **no `.github/workflows`**, so "runs in CI" had no referent. **So no committed test may depend on it, and the per-run `adb push` is REINSTATED** for every connected real-book leg (WI-4, WI-5, WI-9 owners: this is yours too). Caught by the WI-3 implementer trying to use it — the audit checked the file's *bytes* but not its *tracked status*, and both the artifact and this plan propagated the conclusion without re-deriving it. The structural failure modes still cannot come from any real book (a truncated header or an out-of-range EXTH index has to be constructed) → synthetic in-test buffers, AGENTS.md "deterministic tiny structure" exception. |
| `VReaderDatabaseMigrationTest` (extended) | JVM (Robolectric, existing file) | 9→10 runs on a seeded v9 DB; existing rows survive; both new columns read `NULL`; Room's structural PRAGMA validation passes at v10. |
| `BookDaoCoverStateTest` | JVM (Robolectric) | `setCoverState` writes both columns; **a re-import through `upsertPreservingAuthor` leaves `coverPath`/`coverExtractorVersion` untouched** (the D-1 DB-layer guard); `applyRestoredMetadata` likewise. |
| `CoverStoreConnectedTest` | connected | `saveIfAbsent` downscales so `max(w,h) <= 512` (a 2000×3000 source); output is a decodable JPEG; a partial write leaves no `hasCover`-true file and no `.tmp` residue; **`saveIfAbsent` on an existing cover returns `null` and leaves the bytes untouched** (H-5); **calling `saveIfAbsent` twice with the same bitmap succeeds both times and the bitmap is still usable afterwards** — the H-3 borrow contract, which a `recycle()`-ing implementation fails with `IllegalStateException`; encode failure returns `null` without throwing. |
| `CoverStoreUserPickRaceTest` | connected | **H-5 directly**: start an extraction save whose encode is stalled on a test latch, land a `saveReplacing`-shaped user cover mid-flight, release — the final bytes are the **user's**, not the extractor's, and `coverPath` still points at a valid file. Repeated 50× to catch the interleaving. |
| `EpubCoverExtractorConnectedTest` | connected | committed `minimal.epub` / `paged-multipage.epub` behaviour; an EPUB **with** a cover → `Art`; **without** → `None`; a truncated/corrupt EPUB → `Failed` or `None`, never a throw; the `Publication` is closed on every path (no FD growth over 50 iterations via `/proc/self/fd`). |
| `PdfCoverExtractorConnectedTest` | connected | `sample-3page.pdf` page 0 → non-blank bitmap within the size bound; `not-a.pdf` → `None`; a password-protected PDF → `None`; renderer + descriptor closed on every path (50 sequential extractions, no FD growth). |
| `CoverCoordinatorConnectedTest` | connected | **the idempotency suite** — first pass writes N covers; a second `start()` writes **0** and opens **0** files (assert via an extractor spy); a book whose file was deleted → version stays `NULL`, no crash, still eligible next pass; a book with an existing cover FILE but a `NULL` `coverPath` (the #153 user-pick case) → pointer reconciled, extractor **never** invoked; `coverPath` set but file deleted → re-extracted; an art-less TXT book is attempted **once** and skipped thereafter; a cancelled scope mid-book leaves no half state; two `start()` calls run one collector. |
| `BookImporterCoverConnectedTest` | connected | importing a cover-bearing EPUB ends with a non-null `coverPath`; **an `onImported` callback that throws (and one that throws `OutOfMemoryError`) still leaves the import successful** and the book present; a duplicate import of a book that already has a cover does not clobber it (both the file guard and the `updateImportedColumns` exclusion). |
| `BookImporterHookSurfacesTest` | JVM | **M-11**: `onImported` fires exactly once per successful `importStream` regardless of caller shape — including the `expectedKey`-carrying restore-shaped call (`RestoreImporter.kt:168`) and the `format`-override open-with call (`IncomingImportCoordinator.kt:364`) — and does **not** fire when the import throws `UnsupportedFormat`. |
| `CoverDeletionConnectedTest` | connected | **M-10 / NEW-2 + the round-3 baseline guard**: **the first emission removes NOTHING** even though `previousKeys` starts unset and covers already exist on disk; **a fresh coordinator over a populated store removes nothing** on its first emission (the collector-restart case); then deleting a book's row makes the flow re-emit and the **set delta** removes exactly that cover, leaving every other cover intact; the deleted key's `keyLocks` entry is dropped (NEW-5); a book with no cover deletes as a no-op; a re-import after delete re-extracts rather than inheriting a stale file; `sweepOrphans()` at `start()` removes a cover whose row vanished while the process was dead and keeps every live one; a failed unlink is logged, not thrown, and the next sweep cleans it. |
| `CoverConcurrencyConnectedTest` | connected | **NEW-3, the bound as an invariant**: a restore-shaped burst of 200 `enqueue` calls yields **at most `EXTRACTION_WORKERS` (=1) concurrent** extractions — a spy extractor asserts strict non-overlap of its enter/exit intervals — and all 200 are eventually processed exactly once (duplicate `enqueue` of an in-flight key is deduped, not re-run); an import arriving during backfill queues behind it rather than spawning; cancelling the app scope stops the worker without leaving a `.tmp` file. |
| `CoverAdmissionSetConcurrencyTest` | JVM | **The round-3 admission-set race, asserted as LOSS not duplication.** N=16 threads × M=50 `enqueue` calls over a mix of *the same* key and *overlapping* keys: (a) **no key is lost** — every distinct key enqueued is eventually extracted at least once (a key stuck in `admitted` forever would silently never be extracted, the failure mode that motivates this test); (b) **no key is extracted twice concurrently**; (c) each key settles to exactly one completed extraction; (d) after the queue drains, `admitted` is **empty** — the `finally`-removal ran on every path, including a key whose extraction threw. A plain `MutableSet` implementation fails (a) or (d). |
| `BookCoverArtConnectedTest` | connected | the 2:3 box holds for a 1:1 and a 1:3 source (grid-row height invariant); `coverPath == null` → fallback; non-null path with a **missing file** → fallback; an undecodable file → fallback; scrolling a 50-book grid decodes each cover **at most once** (cache-hit assertion) and the cache stays within its byte budget. |
| `LibraryCoverAdoptionConnectedTest` | connected | grid card and list row both render `BookCoverArt`; a seeded book with a real cover file shows art in both view modes; the view-mode toggle does not re-decode. |
| ~~`BookDetailsCoverConnectedTest`~~ | — | **Removed with WI-8 → #153** (NEW-1). #152 does not touch the details sheet, so it asserts nothing about it. |
| `BookImporterHookCancellationTest` | JVM | **NEW-4**: an `onImported` that throws `CancellationException` **propagates** out of `importStream` (structured concurrency preserved); one that throws any other `Throwable`, including `OutOfMemoryError`, is swallowed and the import still succeeds. Guards the exact `runCatching` defect. |
| `CoverAcceptanceConnectedTest` | connected | per-format routing on committed fixtures (EPUB → art, PDF → art, AZW3 → art, TXT/MD → fallback); covers survive an app restart with no re-extraction and no flicker. |

**Fixture policy.** `test-books/` is gitignored, so no automated test may depend on it at CI time —
but the AZW3 case needs no exception at all: `androidTest/assets/foliate-spike/book.azw3` **is** the
real book, byte-for-byte (L-13). Automated tests therefore use committed assets only
(`minimal.epub`, `paged-multipage.epub`, `sample-3page.pdf`, `not-a.pdf`, `foliate-spike/book.azw3`)
plus in-test byte buffers for the MOBI structural modes. The **real** EPUBs are still required at
Gate 5 (WI-9) for the CJK / double-`OEBPS`-prefix and restart legs, and are pushed per run — the
connected task wipes `/sdcard/Android/data/<pkg>/` at run end (#127 precedent).

**A missing fixture must FAIL, never skip.** Any test that consumes a pushed real book asserts the
file's presence **and a pinned byte count / digest** and fails hard if either is wrong. No
`assumeTrue`, no `@Ignore`: a skipped test exits 0 exactly like a pass (bug #369), which would turn
the entire real-book leg into a silent false green — the precise failure mode this feature's Gate 5
exists to prevent.

One connected fixture must be created rather than found: **an EPUB with no cover at all** — no real
book in the corpus lacks one (both real EPUBs have covers), so a minimal cover-less EPUB is built
for the `None` branch (format-coverage exception).

---

## 8. Storage, memory, and measurement

- **Location / naming**: `filesDir/covers/<StorageNaming.fileNameForKey(key)>.jpg`, written via
  `.tmp` + `renameTo` (D-2). One file per book; no directory sharding needed at library scale.
- **Bounds**: max edge 512 px, JPEG quality 80 (iOS parity) ⇒ ≈30–60 KB per cover.
- **Invalidation**: the file is authoritative for *content*; `coverPath` is a pointer that is
  re-derived whenever the file is missing (`isEligible`). Bumping `COVER_EXTRACTOR_VERSION` re-runs
  everything — the documented lever for a parser fix.
- **Uninstall**: `filesDir` is removed with the app; a reinstall re-imports and re-extracts.
  **Restore**: `RestoreImporter` re-imports each book file, which re-triggers extraction — covers
  rebuild without being in the backup contract.
- **Grid decode cost**: 3 columns × ~7 visible rows ≈ 21 cells. Full-size 512×768 `ARGB_8888` =
  1.57 MB each ≈ 33 MB — which is why the decoder subsamples to the measured cell width and the
  `LruCache` is capped at `maxMemory()/8` (D-5).
- **Measurement is on target, never on a desktop JVM.** The #139 precedent (a desktop number ~100×
  off the device) is binding: WI-7's numbers come from emulator-5554 with a 50-book seeded library
  via `adb shell dumpsys meminfo <pkg>` (Graphics/Java heap delta while the grid is fully scrolled)
  and `adb shell dumpsys gfxinfo <pkg> framestats` (janky-frame percentage during a scripted fling),
  both recorded verbatim in the WI-7 PR body and the Gate-5 evidence file. No performance claim in
  this plan is asserted as fact until that measurement exists; the 33 MB figure above is an
  arithmetic upper bound used to justify subsampling, and it is labelled as such.

---

## 9. Gate-5 production reachability

The surface is reachable in a **release-configured build** with no DEBUG launcher and no
DebugBridge; #171 (the Settings hub) is **not** a dependency.

**Library grid / list** — launch the app → `MainActivity` shows `LibraryScreen` (the home screen) →
tap the `+` pill → SAF picker → choose a real EPUB/AZW3/PDF from device storage → the card in the
grid shows the book's real cover; tap the grid/list toggle pill → the list row shows it too. Every
file involved is in `android/app/src/main`.

**There is no second path.** The Book Details route moved to #153 with WI-8 (§2 G2 / NEW-1), so
Gate 5 covers the library only and the details sheet is verified unchanged from what #134 shipped —
i.e. the acceptance pass asserts the details sheet still shows **no** cover block, so a stray
half-landing of #153's work would fail this gate rather than pass it silently.

The WI-9 evidence file (`dev-docs/verification/feature-152-<YYYYMMDD>.md`, per
`dev-docs/verification/SCHEMA.md`) must name the user path(s) in words, record the AVD, and carry:
the real CJK EPUB (`道诡异仙`, the double-`OEBPS`-prefix pathology) rendering its cover; the real
6.3 MB CJK AZW3 rendering its cover; a TXT book still rendering the fallback; the restart
persistence check; the §8 on-target measurements; and — explicitly, in a **Residuals** section —
that the MOBI6+KF8 dual-part path ships untested for want of any KF8 fixture (M-7); that `WI-7` was
unblocked by `needs-design #2110` on a stated date; and that **the Book Details sheet shows no cover
until #153** (§2 G2), so the grid-vs-details asymmetry is a recorded, accepted state rather than an
undiscovered gap.

---

## 10. Risks + mitigations

| # | Risk | Mitigation |
|---|---|---|
| 0 | **An attacker-controlled record span allocates ~2 GiB and throws `OutOfMemoryError`** — an `Error`, so the "no extractor throws" contract does not catch it; kills the app-scope backfill and can take the process. | The three `sliceRecord` guards (start/end vs `raf.length()`, 64 MiB cap) **before** allocating, plus `catch (Throwable)` in `CoverCoordinator` as defence in depth. Tested at `-Xmx64m` (§7 ⑪–⑬). Measured, not hypothesised — see §4 C-1. |
| 1 | **MOBI parse correctness** — the riskiest code in the feature. | Port of a proven iOS implementation with the three Kotlin corrections spelled out (D-6), now **empirically validated**: 3/3 real covers correct, byte-identical to an independent Python reader, 36/39 hostile inputs clean, 300 MB file at `-Xmx16m` (§0.1). Thirteen structural failure modes as JVM tests. **Residual: the MOBI6+KF8 dual-part case ships untested** — every available fixture is single-part MOBI6 (M-7), so no test can reach it; recorded as a named residual in the Gate-5 evidence rather than papered over. |
| 2 | **Signed-byte / `Int`-sentinel port bugs** (`0xFFFFFFFF` == `-1` as an `Int`). | Explicit `and 0xFF` / `and 0xFFFFFFFFL` discipline plus dedicated high-bit regression tests. Both bugs were **reproduced in compiled Kotlin** (§0.1) — an unmasked port fails on the first field of a real book; the `Int` sentinel silently returns a wrong non-image record. Now also covers `firstImageIndex`'s own sentinel (M-8). |
| 3 | **Grid memory** — 21 full-size bitmaps ≈ 33 MB. | Bounded at save (512 px), subsampled at decode to the measured width, `LruCache` at `maxMemory()/8`, single-decode asserted; pre-authorised switch to Coil if the on-target measurement misses (D-5). |
| 4 | **`Bitmap` lifetime** — #115's Compose-boundary recycle crash, *and* recycling a bitmap the caller still owns. | **No `.recycle()` anywhere, full stop** — `CoverStore` borrows (H-3). The earlier "recycle inside `save`, enforced by a grep" mitigation was itself the defect: `coverFitting` can hand back the `Publication`'s own retained bitmap (`scaleToFit` returns `this` when the source already fits; `InMemoryCoverService` returns a retained field), and a grep for `.recycle()` passes while that bug is present. Now enforced by a **behavioural** test (double-`saveIfAbsent`, bitmap still usable) rather than a text search. |
| 5 | **`PdfRenderer` is not thread-safe** and allows one open page. | Reuse `PdfDocument`'s existing `Mutex` + paired open/close rather than opening a raw `PdfRenderer`. |
| 6 | **A re-import or restore wipes a #153 user cover.** | The `updateImportedColumns` exclusion (D-1 DB layer) plus `saveIfAbsent` under a per-key lock (D-1 file layer, H-5) — the pre-check alone was a TOCTOU race. `BookDaoCoverStateTest` + `CoverStoreUserPickRaceTest` assert both. |
| 7 | **A transient read failure permanently blinds a book — or a truncated book is re-parsed forever.** | The content/access split (D-4, H-2): structural outcomes memoise, access failures retry. Without it the `RandomAccessFile` switch silently converts 6 of 39 structural cases into perpetual retries. Pinned by `MobiCoverResultClassificationTest` as a contract test. |
| 8 | **Backfill jank / battery** on a large library at every launch. | Version-gated skip is one integer compare per settled book; work runs on the app scope's IO dispatcher, serialised by a `Mutex`, never blocking first paint — the `SearchIndexCoordinator` shape already shipping in this app. |
| 9 | **An extraction bug breaks importing.** | Extraction is structurally outside `BookImporter` (a post-import call), so an import cannot fail on it; asserted in `BookImporterCoverConnectedTest`. |
| 10 | **Rule-51 G1 not accepted** → the render WIs stall. | The split is pre-planned: WI-1…WI-6 are independent of the gap and ship regardless (§6). |
| 11 | **Write-set collision with #153/#154/#170** (all edit `LibraryScreen.kt`). | Sequence, never fan out — stated in the row and re-stated here; `BookCoverArt` is deliberately the single seam those three extend instead of re-editing the screen. |
| 12 | **Robolectric `Bitmap` shadows** make JVM encode/size assertions meaningless. | The `CoverPaths` / `CoverStore` split puts every bitmap assertion in the connected lane by construction. |
| 13 | **A new import surface forgets to trigger extraction** (there are four today, and the first draft hooked one). | The trigger lives in `BookImporter.importStream` itself, which all four already call (M-11); `BookImporterHookSurfacesTest` pins restore- and open-with-shaped calls, not just the SAF one. |
| 14 | **Orphaned cover files** accumulate, and a re-import inherits a stale cover. | A set delta on the library flow the coordinator already collects + a `sweepOrphans()` backstop at `start()` (M-10, NEW-2) — no repository edit, no dependency cycle; both idempotent and non-throwing, both tested. |
| 15 | **A missing Gate-5 fixture turns the real-book leg into a silent pass.** | Presence + digest assertions that **fail**, never `assumeTrue` (bug #369). |
| 16 | **Unbounded extraction fan-out** — a 200-book restore starting 200 concurrent publication opens / PDF renders / bitmap decodes. Worse than C-1: it arrives on the happy path, by design. | One admission point (`enqueue`) feeding `EXTRACTION_WORKERS = 1` (NEW-3); `ensureCover` is private so nothing can bypass it; `CoverConcurrencyConnectedTest` asserts strict non-overlap under a 200-key burst. |
| 17 | **Swallowed cancellation** breaking structured concurrency (`runCatching` catches `CancellationException`). | Explicit `catch (CancellationException) { throw e }` **before** the broad catch, in both the import hook and the coordinator — the `LibraryViewModel.kt:183` / `RestoreImporter.kt:87` / `SearchIndexCoordinator.kt:118` shape; pinned by `BookImporterHookCancellationTest` (NEW-4). |
| 18 | **Admission-set thread safety** — `enqueue` is public, non-suspending, and has two concurrent producers (the import hook and the flow collector). A lost race on the *removal* side leaves a key marked in-flight forever, so its cover is **never** extracted: a silent permanent miss, with no error and no retry. | `ConcurrentHashMap.newKeySet()` with an atomic `add()` test-and-set, removal in a `finally`, and a rollback if `trySend` fails. `CoverAdmissionSetConcurrencyTest` asserts **no loss** and a drained-empty `admitted`, not merely the absence of duplicates. |
| 19 | **A collector restart wipes every cover** — a set delta against an unset baseline would read the first emission as "everything was deleted". | `previousKeys: Set<String>?` starts `null`, and the delta runs only when non-null: an empty *library* deletes, an absent *baseline* does not. Pinned by two cases in `CoverDeletionConnectedTest` (first emission, and a fresh coordinator over a populated store). |

---

## 11. Backward compatibility

- **Schema**: additive nullable columns with tail defaults; `MIGRATION_9_10` is two `ALTER TABLE`
  statements, no data transform — the `author` (v6) class. Downgrade remains unsupported (unchanged
  policy). The existing round-trip migration test is extended, not replaced.
- **Existing libraries**: every pre-existing book starts `coverPath = NULL` /
  `coverExtractorVersion = NULL` and renders **exactly as today** until the backfill fills it in.
  There is no intermediate state in which a book looks worse than before.
- **Backups**: untouched — no new backup section, no contract-vector change, so iOS↔Android
  conformance is preserved by construction.
- **Restore**: `RestoreImporter` re-imports each file, which re-triggers extraction; covers rebuild
  on the new device with no manifest change.
- **Forward compatibility**: #153 writes user picks into the same `CoverStore` (the `hasCover` guard
  makes a user pick permanently win, iOS's semantics) and adds the depicted pencil/`Add cover…`
  affordances; #170 replaces `BookCoverArt`'s no-art branch with `CoverMonogram` and touches nothing
  else; #154 needs no cover knowledge at all.

---

## 12. What changed vs the 2026-08-04 plan (v2)

| Area | v2 | This plan | Why |
|---|---|---|---|
| Filename sanitisation | "reuse the existing scheme from `BookImporter.fileNameForKey`" | `StorageNaming` object; both callers call **one function**; a test asserts equality | v2's shared-visibility finding — a comment is not a guarantee |
| Extraction outcome | `Bitmap?` | sealed `CoverResult { Art \| None \| Failed }` | `null` conflates "no art" with "couldn't read", which breaks backfill memoisation |
| Persisted state | `coverPath` only | `coverPath` **+** `coverExtractorVersion` | otherwise every backfill re-parses every art-less book; mirrors `search_index_state.indexerVersion` |
| No-clobber guard | file-level `hasCover` only | file-level **+** the `updateImportedColumns` exclusion | v2 missed that Android's import path UPDATEs existing rows |
| MOBI `firstImageIndex` | "resourceStart at offset 108" | offset **108 = 16 + 92**, an absolute PDB record index, plus the signed-byte and `0xFFFFFFFF`-as-`Int` corrections | v2's named Gate-2 High; the `Int` sentinel bug would have shipped |
| MOBI parser I/O | port of `Data(mappedIfSafe)` | `RandomAccessFile`, bounded reads, **pure JVM**, returns bytes | 100 % JVM-testable; no 6.3 MB heap load |
| Cover extraction site | inside `BookImporter` | a post-import `CoverCoordinator.ensureCover` call | keeps "cannot fail an import" structural, and keeps `Context`/Readium out of the importer |
| Store size | 1024 px | **512 px / JPEG 80** | exact iOS parity (`CustomCoverStore` 512 / 0.8) and 4× less decode memory |
| Store location | `filesDir/covers` (asserted) | `filesDir/covers` **with** the `cacheDir` / `noBackupFilesDir` / auto-backup-quota reasoning and the `file_paths.xml` prohibition | the durability question is #153's, and it is decided here |
| Rule 51 | "COMMITTED — rule 51 clean" | one explicit gap **G1** (no bundle depicts raster art in the frame) + the iOS precedent + the WI split if it is not accepted | v2's claim does not survive reading the bundle: there is no `<img>` in it |
| PDF leg | implied parity | flagged **Android-only** — iOS's `PDFMetadataExtractor` is a stub with no cover override | v2 described it as parity |
| WIs | 7 | 9 (parser split from adapter; render split from details; migration split from store) | smaller, independently auditable units |

### 12.1 v2 Gate-2 reconciliation — and its limit (audit H-6)

**The v2 Gate-2 audit artifact does not exist in this repository.** Searched: `.claude/codex-audits/`
(no `*152*` file), all of `dev-docs/`, and the whole tree — the only `152` hits are the two plan
files and an unrelated `fix-issue-1152-…` audit. v2's own §Revision history asserts "6 High + 8
Medium + 2 Low remain open" but enumerates only the round-1 findings it had already applied; **the
16 open items were never written down anywhere retrievable.** So the honest statement, which the
auditor is right to demand rather than let the table above imply otherwise:

- **Reconcilable** — every finding v2 *named* is dispositioned. All are listed in §12 above:
  shared filename sanitisation (M-9 / §4 `StorageNaming`), MOBI `firstImageIndex` derivation (§4,
  now proven), per-WI test write-set gaps (§6, now exact file lists), the `coverPath` requirement
  (D-3), Book Details placement (§4 + §2 G2), the `VReaderFonts` platform-approximation note
  (carried to #170), and the gitignored-fixture policy (§7, now corrected by L-13).
- **Not reconcilable** — the residue of "6 High + 8 Medium + 2 Low" that v2 did not enumerate
  **cannot be shown to have been addressed**, because there is no list to check against. This plan
  does not claim otherwise. Two mitigations, in order of value: (a) this document was written from
  the code, not from v2, so it does not *inherit* v2's defects — it can only coincidentally repeat
  them; (b) Gate-2 round 1 on **this** plan has now run two independent audits (§0.1, §14), which is
  a stronger check than reconstructing a lost list.
- **Process consequence, worth fixing beyond this feature**: a Gate-2 verdict whose findings live
  only in a chat transcript is unauditable at the next gate. Plan audits should land an artifact
  under `.claude/codex-audits/` the way implementation audits do (rule 47 Gate 4 already requires a
  committed file; Gate 2 does not). Flagged for the orchestrator — not fixed here, since this plan's
  only permitted write is itself.

---

## 13. Revision history

- **v3 (2026-08-06)** — rewritten from the code for Gate 1; supersedes the 2026-08-04 v2 (which
  stalled at Gate-2 round 2 with 6 High + 8 Medium + 2 Low open, then was paused for feature #171).
  All v2 Gate-2 findings named in its §Revision history are addressed in §12; three new
  code-verified corrections recorded in §0.
- **v4 (2026-08-06)** — **Gate-2 round 1 on v3**: two independent audits (static Codex gpt-5.5/high;
  empirical — the §4 MOBI spec ported and run against 4 real books + 39 mutated files, cross-checked
  against an independent Python reader, Readium AAR disassembled). Both returned
  `block-recommended`. 1 Critical + 5 High + 6 Medium + 3 Low; **all 15 accepted, none rejected**,
  though three are resolved differently from the fix the auditor proposed (M-9, M-7, and H-4's
  remedy — see §14). Substantive changes: the C-1 allocation guards (an uncatchable ~2 GiB
  `OutOfMemoryError`, measured); the H-2 content-vs-access classification that the
  `RandomAccessFile` design forces; H-3's reversal of the `recycle()`-in-`save` decision (Readium can
  hand back its own retained bitmap); H-5's per-key lock + `saveIfAbsent`; G2, a **second** rule-51
  gap in Book Details that v3 wrongly dismissed; M-11's move of the extraction trigger into
  `BookImporter` so all four import surfaces are covered; M-10's deletion/orphan cleanup; M-12's
  exact per-WI file lists; M-8's `firstImageIndex` sentinel; L-13's discovery that the real AZW3 is
  already committed byte-identically (making that leg CI-safe); and §12.1's plain statement that the
  v2 audit artifact is unrecoverable. §0.1 records what the empirical audit **confirmed** — the
  parser spec extracts 3/3 real covers correctly and matches an independent implementation
  byte-for-byte, and both claimed Kotlin corrections are real. `WI-7`/`WI-8` are now
  `BLOCKED: needs-design (#2110)`.
- **v5 (2026-08-06)** — **Gate-2 round 2** (round 3 of the rule-47 3-round cap). Round 1's Critical
  and all but two findings confirmed resolved at file:line; the M-9 deviation (frozen sanitiser) and
  the H-6 recommendation were **agreed** — the latter is now rule 47, and this feature's Gate-2
  artifact is committed under `.claude/codex-audits/`. Three new High + 1 Medium + 1 Low, all
  addressed (§14.1): **WI-8 removed from #152** and the details cover moved to #153, applied through
  every write-set / test / Gate-5 route rather than left as a prose recommendation (NEW-1), with the
  grid-vs-details asymmetry stated and accepted; the deletion cleanup re-derived as a **set delta on
  the library flow** so the `LibraryRepository` ↔ coordinator cycle disappears rather than moving
  into the DI graph (NEW-2); extraction bounded at **one worker behind a single `enqueue` admission
  point**, closing a 200-concurrent-extraction fan-out on restore (NEW-3); explicit
  `CancellationException` rethrow before the broad catch in the import hook (NEW-4); per-key lock map
  pruned (NEW-5). #152 now completes at **WI-7 + WI-9**; only `WI-7` remains
  `BLOCKED: needs-design (#2110)`.
- **v6 (2026-08-06)** — **Gate-2 round 3: verdict `follow-up-recommended`, Gate 2 SIGNED OFF** (down
  from `block-recommended` in rounds 1 and 2). NEW-1/2/4/5 confirmed resolved; the NEW-2 deviation
  **agreed** after independent verification of both load-bearing facts. Two edits applied (§14.2):
  the admission set is now `ConcurrentHashMap.newKeySet()` with an atomic `add()` test-and-set,
  `finally` removal and a `trySend` rollback — with a concurrency test written around **key loss**,
  since a lost removal is a silent permanent miss rather than a visible duplicate; and the deletion
  delta now distinguishes an **absent baseline** (`previousKeys = null`, deletes nothing) from an
  **empty library** (deletes legitimately), so no collector restart can wipe every cover. Delete
  call-site count corrected to 13 references across 8 test files. No further Gate-2 round.

---

## 14. Gate-2 round 1 — finding index

Every finding, where it is answered, and whether the fix differs from the one proposed.

| # | Sev | Answered in | Fix as proposed? |
|---|---|---|---|
| C-1 | Critical | §4 `sliceRecord` guards; §7 ⑪–⑬; Risk 0 | Yes — plus `catch (Throwable)` in the coordinator as defence in depth, and an explicit note that catching `OutOfMemoryError` is *not* the fix |
| H-2 | High | §3 D-4 content-vs-access table; §7 `MobiCoverResultClassificationTest`; Risk 7 | Yes |
| H-3 | High | §4 `CoverStore` borrow contract; Risk 4 | Yes — take the "don't recycle" option; the grep-based mitigation is replaced by a behavioural test |
| H-4 | High | §2 **G2** (resolved against the real files; the auditor's cited design path did not exist) | Substance accepted; **remedy differs** — move WI-8 to #153 rather than commission a new design, since #153 makes `CoverWithSwap` fully depicted. *(Round 2 NEW-1: the recommendation is now **applied**, not merely recorded.)* |
| H-5 | High | §3 D-1 file layer (`saveIfAbsent` + per-key `Mutex`); §7 `CoverStoreUserPickRaceTest` | Yes |
| H-6 | High | §12.1 | Both options taken: reconcile what is nameable **and** state plainly that the rest is unrecoverable; adds a process fix (Gate-2 artifacts should be committed) |
| M-7 | Medium | §4 KF8 limitation; Risk 1 residual; §9 evidence Residuals | **Second option** — no KF8 fixture exists and hand-building one is disproportionate, so the limitation ships **untested and named** |
| M-8 | Medium | §4 `firstImageIndex` sentinel; §7 | Yes — independently reconfirmed by parsing `divider-azw3.azw3` here |
| M-9 | Medium | §4 `StorageNaming` | Finding accepted, **neither proposed fix taken**: changing the mapping or hashing would orphan every existing book file, and the collision is impossible on the canonical-key domain. Mapping frozen + precondition + injectivity test; the self-contradictory test deleted |
| M-10 | Medium | §4 "Deletion + orphan cleanup"; §7 `CoverDeletionConnectedTest`; Risk 14 | Yes — both deletion cleanup **and** a startup sweep (the *mechanism* was reworked in round 2 by NEW-2) |
| M-11 | Medium | §4 import-surface table + the `onImported` hook; §7 `BookImporterHookSurfacesTest`; Risk 13 | Yes — resolved at the convergence point rather than per surface |
| M-12 | Medium | §6 exact file lists + the honest-parallelism note | Yes — WI-4/WI-5 downgraded to "isolated, not faster" |
| L-13 | Low | §7 `MobiCoverRealBookTest` + fixture policy | Yes — both halves: the AZW3 leg is CI-safe, and fixtures fail hard rather than skip |
| L-14 | Low | §7 (five added cases) | Yes |
| L-15 | Low | §0 Readium row | Yes |

### 14.1 Gate-2 round 2 — finding index

Round 1's C-1, H-2, H-3, H-5, H-6, M-7, M-8, M-9, M-12, L-13, L-14, L-15 were confirmed resolved at
file:line; M-10 and M-11 partially (the analysis verified, the wiring reworked below). Three new High
+ one Medium + one Low:

| # | Sev | Answered in | Fix as proposed? |
|---|---|---|---|
| NEW-1 | High | §2 G2 (decision), §4 out-of-scope + Modified table, §6 WI-8 struck, §7, §9 | Yes — **option one taken**: WI-8 removed from #152 entirely, every write-set / test / Gate-5 route updated, #153 noted as inheriting the details cover **and** G2. The grid-vs-details asymmetry is stated out loud and judged acceptable, with the correct lever named (raise #153's priority, not widen #2110) |
| NEW-2 | High | §4 CoverCoordinator "Deletion + orphan cleanup" | Finding accepted; **neither remedy taken** — `deleteBook` has zero production callers, and the coordinator already collects the unfiltered library flow, so a set delta + `start()` sweep removes the cycle instead of relocating it. `LibraryRepository` is not modified at all |
| NEW-3 | High | §4 "Extraction concurrency", §6 WI-6, §7 `CoverConcurrencyConnectedTest`, Risk 16 | Yes — one admission point (`enqueue`), `EXTRACTION_WORKERS = 1`, `ensureCover` made private so the bound cannot be bypassed; the number is justified by precedent, the memory ceiling, the absence of any latency requirement, and testability |
| NEW-4 | Medium | §4 import hook, §7 `BookImporterHookCancellationTest`, Risk 17 | Yes — and checked the other broad catch as instructed: the coordinator's already specified the rethrow in round 1, so only the hook was defective. Both now state the catch **order** explicitly |
| NEW-5 | Low | §3 D-1 per-key lock map | Yes — pruned where the cover is removed (both the delete delta and the sweep) |

### 14.2 Gate-2 round 3 — finding index (verdict `follow-up-recommended`, Gate 2 signed off)

Round 2's NEW-1, NEW-2, NEW-4, NEW-5 confirmed resolved; NEW-3's *bound* resolved, its admission set
not. The NEW-2 deviation was **agreed** — the auditor independently verified both facts and endorsed
keeping the coupling out ("I do not think the repository callback/cycle should come back"). Two
edits, both applied:

| # | Sev | Answered in | Fix as proposed? |
|---|---|---|---|
| R3-1 | Medium | §4 "Extraction concurrency" (`ConcurrentHashMap.newKeySet()`, `finally` removal, `trySend` rollback); §7 `CoverAdmissionSetConcurrencyTest`; Risk 18 | Yes — and the test is written around **loss**, per the finding's own reasoning that a lost removal is a silent permanent miss rather than a visible double-extraction |
| R3-2 | Low | §4 "Deletion + orphan cleanup" (`previousKeys: Set<String>?` = `null`, delta only when non-null); §7 `CoverDeletionConnectedTest` (first emission + fresh-coordinator cases); Risk 19 | Yes |
| — | — | §4 delete-call-site count | Corrected: **13 references across 8 test files**, not 13 test files |
