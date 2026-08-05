# Feature #165 — Android export / import annotations (parity box G8)

**Gate 1 plan.** Status of the row: `TODO` (`docs/features.md:218`). Platform: `android-app`.
Design bundle: `dev-docs/designs/vreader-fidelity-v1/`. iOS parity row: #35 (`docs/features.md:90`,
`VERIFIED`).

> **Reading note for the Gate-2 auditor.** Every claim in §2 ("Verified wiring claims") carries a
> `file:line`. Nothing in this plan asserts that a surface "is wired" without a call site. Three
> facts that will feel surprising are stated up front, because the rest of the plan depends on
> them:
>
> 1. **There is no production import or export entry point for annotations on Android today** —
>    `grep -rn "importAnnotation\|annotationImport\|exportAnnotation\|annotationExport" android/app/src/`
>    returns **zero** hits.
> 2. **`AnnotationsRepository.restoreAnnotations` — the UUID-preserving merge seam this feature
>    needs — already exists and is already tested**, but its ONLY caller is the WebDAV restore path
>    (`RestoreImporter.kt:105`), whose screen has **no production call site**: `BackupRestoreScreen`
>    is referenced only from `android/app/src/debug/kotlin/com/vreader/app/backup/BackupDebugActivity.kt:27`.
>    #165 will therefore be the **first production-reachable path into annotation merge on Android**.
> 3. **iOS #35's file format is NOT the backup `annotations.json` shape.** They are different
>    formats with different information content. A file exported by iOS #35 will not import here,
>    and vice versa. See §7 (D-8) — this is named as a real, unresolved parity gap, not papered over.

---

## 1. Problem

Android can share a book's annotations as a **plain-text blob** (`Intent.ACTION_SEND`,
`ReaderActivity.kt:1054-1059` and its three siblings) — human-readable, but not re-importable.
There is no way to:

- write a machine-readable annotations file a user owns and can move between devices/apps, or
- read such a file back into the library.

iOS has both (#35). The gap is box **G8** of the phase-4 parity sweep.

**What this feature delivers.** For one book, from a production surface a user can reach:

- **Export** → a `annotations.json`-shaped file written through SAF `ACTION_CREATE_DOCUMENT`.
- **Import** → an `annotations.json`-shaped file read through SAF `ACTION_OPEN_DOCUMENT`, previewed,
  then merged **non-destructively** into that book.

**What it deliberately does not deliver** (each with a reason in §7): Markdown/plain-JSON export
variants, Readwise/Apple-Books importers, library-wide (all-books) import, iOS-#35-file interop, and
a bidirectional sync.

---

## 2. Verified wiring claims (every claim has a call site)

Rule 47 Gate-2 treats an unverified wiring claim as a **High**. These were each checked by reading
the file at the cited line, not inferred.

| # | Claim | Evidence |
|---|---|---|
| W1 | **No annotation import/export code exists on Android.** | `grep -rn "importAnnotation\|annotationImport\|exportAnnotation\|annotationExport" android/app/src/` → 0 hits |
| W2 | The annotations **review sheet** is production-reachable from the reader chrome (two hosts). | `EpubReaderChrome.kt:250`, `chrome/ReaderChromeScaffold.kt:223` → `AnnotationsReviewSheet(` |
| W3 | The **Book Details sheet** is production-reachable: reader top bar → `⋯` More → *Details*. | `chrome/ReaderChromeScaffold.kt:196` (`onDetails = { … openSheet(ReaderSheet.Details) }`) → `:232` renders `BookDetailsSheet`; EPUB twin at `EpubReaderChrome.kt:128` → `:260` |
| W4 | The Book Details sheet already renders an **`ActionList` card**, and it currently holds **Share only — Export was deliberately omitted**. | `details/BookDetailsRows.kt:228` (`/** The ActionList card (Share ONLY — Export + cover-edit omitted) …`), rendered from `details/BookDetailsSheet.kt:124` |
| W5 | The committed **design depicts an "Export annotations…" row in exactly that `ActionList`**. | `dev-docs/designs/vreader-fidelity-v1/project/vreader-book-details.jsx:215` |
| W6 | The committed **design depicts an "Import annotations…" row paired with Export in the same Actions card** (variant `B1-paired`), with an explanatory merge-policy footnote. | `…/vreader-annotation-import.jsx:317-325` (rows) and `:338` (footnote copy) |
| W7 | The committed design depicts a **post-pick preview/confirm sheet** with a file header, count chips, a sample list, merge copy, Cancel / "Import N items", **and an error variant**. | `…/vreader-annotation-import.jsx:425-558`; error branch at `:477-484`; disabled primary at `:548-554` |
| W8 | The **Android** annotations-sheet design pins its trailing slot to a **bare Share icon** and its empty state carries **no import CTA**. | `…/vreader-android-annotations.jsx:242` (trailing), `:254-263` (empty state) |
| W9 | The shipped Android annotations sheet matches W8: one Share box, `testTag("annot-share")`. | `annotations/AnnotationsReviewSheet.kt:189-199`; empty state `:239-263` |
| W10 | `AnnotationsRepository.restoreAnnotations(env, allowedBookKeys)` exists: **UUID- and timestamp-preserving**, drops out-of-scope books, drops locator-invalid rows, one `@Transaction`, insert-if-absent. | `annotations/AnnotationsRepository.kt:163-219`; DAO at `data/Daos.kt:340-350`; conflict strategy at `data/Daos.kt:327-334` |
| W11 | Its only caller is the WebDAV restore path. | `backup/RestoreImporter.kt:105` (sole hit) |
| W12 | That path's screen has **no production call site** — DEBUG only. | `BackupRestoreScreen(` appears at its own definition (`backup/BackupRestoreScreen.kt:32`) and at `android/app/src/debug/kotlin/com/vreader/app/backup/BackupDebugActivity.kt:27` |
| W13 | The record→wire mappers this feature must reuse are **`private` inside `BackupCollector`**. | `backup/BackupCollector.kt:212`, `:223`, `:232` |
| W14 | The on-wire `locatorJSON` is the **PLAIN `Locator` JSON** (`BackupJson.encode(locator)`), *not* `canonicalJson()`. | `backup/BackupCollector.kt:186-188` + `:215`; decode side `AnnotationsRepository.kt:230` |
| W15 | `Annotation.kt`'s header KDoc **contradicts W14**, claiming the backup collector converts to `canonicalJson()`. It is stale. | `annotations/Annotation.kt:8-9` vs `backup/BackupCollector.kt:186-188`. Also repeated in `data/Entities.kt:112`, `:120-121`. Handled in §9 R-6. |
| W16 | Annotation tables carry a **FK to `books.fingerprintKey` with `CASCADE`** — an insert for a book not in the library **fails the constraint**. | `data/Entities.kt:94-101` (highlights), `:126-133` (notes), `:159-166` (bookmarks) |
| W17 | Highlights dedupe on unique `(profileKey, anchorKey)`; bookmarks on unique `(bookKey, profileKey)`; **notes have no unique index beyond the PK**. | `data/Entities.kt:102`, `:167`, `:134` |
| W18 | `restoreAnnotations` validates *decode* + *fingerprintKey match* but **never calls `Locator.validate()`**. | `annotations/AnnotationsRepository.kt:228-234` vs `identity/.../Locator.kt:51-67` |
| W19 | Row ids are **`String`**, not a typed UUID — no format validation anywhere on the restore path. | `data/Entities.kt:105`, `:137`, `:170`; `annotations/Annotation.kt:132` |
| W20 | SAF precedent in this app: `rememberLauncherForActivityResult(ActivityResultContracts.OpenDocument())`. | `MainActivity.kt:86-88` |
| W21 | `material-icons-extended` is a dependency, so `Icons.*.FileUpload` / `.Download` exist. | `android/app/build.gradle.kts:79` |
| W22 | `container.annotationsRepository` is a process singleton reachable from every reader activity. | `VReaderApp.kt:100`; used at `reader/ReaderActivity.kt:116`, `reader/PdfReaderActivity.kt:157`, `reader/Azw3ReaderActivity.kt:138`, `reader/TxtReaderActivity.kt:355` |
| W23 | `BackupJson.DEFAULT` is `encodeDefaults=true, explicitNulls=false, ignoreUnknownKeys=true`. | `android/identity/.../backup/BackupJson.kt` (`object BackupJson`) |
| W24 | The `annotations` section vector exists and pins field names/types. | `contracts/vectors/backup-sections.json` → `sections.annotations` |
| W25 | The backup-format contract states cross-book references are by `fingerprintKey` and annotation locators are plain `Locator` JSON. | `contracts/identity/backup-format.md:18`, `:42-49` |

**Non-claims.** This plan does **not** claim the WebDAV Backup screen is user-reachable (W12 says it
is not), does not claim any annotations import UI exists (W1), and does not claim the `⋯` More menu
currently offers anything annotation-file-related.

---

## 3. Rule-51 verdict (design gate) — checked, not assumed

**Verdict: PROCEED. No `needs-design` filing is required for the scope in §5.** Every *state* the
feature needs is depicted. Three secondary-text omissions are recorded in §3.3 as **absences**
(never inventions) with rationale, and one judgement call is escalated in §11 (Q-3).

### 3.1 State-by-state evidence

| Required state | Depicted? | Artboard |
|---|---|---|
| Export entry (a row in a card the user can reach) | **yes** | `vreader-book-details.jsx:215` — `{ icon: Icons.Download, label: 'Export annotations…' }` inside `ActionList`, the same card Android ships at `BookDetailsRows.kt:228` |
| Import entry | **yes** | `vreader-annotation-import.jsx:317-325` — `BookDetailsActionsCard variant='B1-paired'` puts `Import annotations…` (accent, `IconUpload`) directly under `Export annotations…` in the Actions card |
| Post-pick preview / confirm | **yes** | `vreader-annotation-import.jsx:425-558` `ImportPreviewSheet` — file header + source badge, `Highlights` / `Notes` / `Skipped` count chips, "Preview · first three" sample list, merge copy, `Cancel` / `Import N items` |
| Import failure (unreadable / wrong-shape / empty file) | **yes** | same sheet, `error` branch `:477-484` (tinted error blob) + the disabled primary `Import 0 items` at `:548-554` |
| Conflict / merge choice | **not needed** | the design **states the policy in copy instead of asking the user**: "Imports merge into *Pride and Prejudice* by passage match. **Existing notes are not overwritten**" (`:531-533`), echoed at `:338`. A non-interactive, non-destructive merge is the designed behaviour — see §6 |
| In-progress | **not needed** | see §3.2 |
| Success | **not needed** | see §3.2 |

### 3.2 Why "in-progress" and "success" need no new surface

- **In-progress.** The only unbounded step is reading + parsing the picked file, and it is bounded
  hard (§8: ≤ 2 MiB, ≤ 10 000 rows). It happens *between* the SAF picker returning and the preview
  sheet appearing — during that window the screen shows the **already-shipped Book Details sheet,
  unchanged**. No new pixels. The apply step is one Room `@Transaction` over ≤ 10 000 pre-validated
  entities (`Daos.kt:340-350`), sub-frame in practice; WI-7's Gate-5 measures it on-device and this
  plan's acceptance criterion A-9 pins a ceiling rather than asserting one (memory:
  *measure perf ON TARGET, not on a desktop JVM*).
- **Success.** Tapping `Import N items` dismisses the preview sheet. The **observable result is the
  designed annotations list itself** — the user opens the Notes sheet and the merged rows are
  there. Introducing a "42 imported!" banner would be inventing a surface the design chose not to
  draw. The pre-import `Skipped` chip already discloses what will not land, *before* the user
  commits, which is precisely why the design front-loads that number.
- **Apply-time failure** (a Room write that throws) re-renders the **same designed error branch**
  (`:477-484`) with the failure text; the transaction is atomic, so the choice is genuinely "all or
  the error blob".

### 3.3 Design-fidelity ledger — three omissions, all absences

Rule 51 prohibits **inventing**. Omitting depicted decorative/secondary text where the underlying
data does not exist is the same class of absence #134 WI-4 already exercised
(`BookDetailsSheet.kt:5-7`: "NO cover art, NO 'Tap to add cover' placeholder, NO Export, no
author-when-null"). Each omission below is recorded so the Gate-2 auditor can overrule it.

| # | Depicted element | Shipped as | Why |
|---|---|---|---|
| A-1 | Export row `sub`: `Markdown · JSON · VReader JSON` (`vreader-book-details.jsx:215`) | row label only, **no sub-line** | Android exports exactly one format. Rendering a three-format subtitle would be a **false affordance** — strictly worse than omitting decoration. Android's shipped `ActionList` row already renders label + chevron with no sub (`BookDetailsRows.kt:264-278`). |
| A-2 | Import row `sub`: `VReader JSON · Readwise · Apple Books` (`vreader-annotation-import.jsx:322`) | row label only, **no sub-line** | Same reason: no Readwise/Apple-Books importer is in scope, and advertising one is a lie. |
| A-3 | Preview sample-row meta line: `<chapter> · p. <page>` (`vreader-annotation-import.jsx:510-520`) | color dot + quoted text (highlights) / note content (notes); **no chapter·page line** | The wire row carries only `locatorJSON` (`BackupSections.kt:26-35`). Chapter titles are not derivable for an arbitrary book at import time, and `page` exists only for PDF. Rendering a fabricated or blank meta line is worse than omitting it. |

The **error blob**, the **count chips** (including `Skipped`), the **merge-policy copy**, the
**Cancel / Import N items** button pair and the **file-name header** are all built as depicted.

### 3.4 Rejected: the design's own "canonical pick" (A1 + C1)

`vreader-annotation-import.jsx:25-31` names **A1** (an overflow `⋯` menu in the *annotations sheet's*
trailing slot, holding Share + Import) + **C1** (an "Import annotations from file…" CTA in the
annotations empty state) as the canonical pick, with **B1** (the paired Book-Details Actions rows)
explicitly allowed as "a backstop, not a primary home".

**This plan takes B1 and rejects A1 + C1 on Android.** Reason, and it is a rule-51 reason rather
than a taste one:

- `vreader-annotation-import.jsx` is an **iOS-framed** exploration (its host is `HighlightsSheetV3`
  / `BookDetailsSheet`, iOS chrome). For the *annotations sheet* specifically, a **committed Android
  artboard already exists and disagrees**: `vreader-android-annotations.jsx:242` pins the trailing
  slot to a bare Share icon and `:254-263` draws the empty state with no CTA.
- Choosing the iOS artboard's decision over a committed **Android** artboard for the **same Android
  surface** is exactly the self-directed design substitution rule 51 exists to stop. Reusing an iOS
  bundle is legitimate where no Android artboard competes (the #106 precedent); it is not
  legitimate where one does.
- **B1 has no such conflict**: the Actions card is depicted for Android in `vreader-book-details.jsx`
  (which #134 implemented from), and the Export row is already drawn there. Import joins it exactly
  as `variant='B1-paired'` draws it.
- Operational bonus: both actions land on **one** surface already proven reachable (W3), so the
  Gate-5 production path is a single, short, already-verified navigation.

This is the one design decision an auditor should push on — escalated as **Q-3** in §11.

---

## 4. Prior art, precedent, rejected alternatives

**Reused wholesale (no reinvention):**

- `AnnotationsRepository.restoreAnnotations` (W10) — the merge engine. #165 adds a second caller,
  not a second implementation.
- `BackupAnnotationsEnvelope` / `BackupHighlight` / `BackupNote` / `BackupBookmark`
  (`android/identity/.../backup/BackupSections.kt:18-55`) — the file schema. Cross-platform,
  golden-vector-pinned (W24).
- `BackupJson` (W23) — the exact encoder settings that give Swift `Codable` parity (omit-nils,
  ISO-8601 second precision).
- #155's untrusted-input doctrine — `D7` (bounded, library-free sniffing, never trust a declared
  type) and `D8` (size preflight before opening + a counting guard after, because declared sizes
  lie and a blocking `InputStream.read` is uninterruptible). `dev-docs/plans/20260804-feature-155-android-document-handler.md:240-268`, `:272-340`.
- `MainActivity.kt:86-88` — the `ActivityResultContracts` launcher shape.
- #134's **capability-based nullable callback** pattern (`ReaderChromeScaffold.kt:106-122`: every
  post-#132 parameter is nullable/defaulted so older callers stay valid).

**Rejected alternatives:**

| Rejected | Why |
|---|---|
| A bespoke export JSON shape ("simpler for one book") | The row's scope names the backup shape, and it is a **versioned cross-platform contract** (`contracts/identity/backup-format.md`). A divergent shape is a compatibility break, not a formatting preference. It would also forfeit `restoreAnnotations` and its whole test suite. |
| Reusing iOS #35's `AnnotationExportPayload` shape | It carries **no locator and no book fingerprint** (`vreader/Models/ExportedAnnotation.swift:23-41`). iOS's own importer therefore anchors every imported row at a synthetic locator whose `textQuote` is the annotation's UUID (`vreader/Services/Import/AnnotationImporter.swift:90-96`). Adopting that would ship unanchorable annotations. See §7 D-8. |
| Duplicating the record→wire mappers into the exporter | Two copies of a contract mapping drift. WI-1 extracts the single copy instead. |
| Adding a unique index on notes to dedupe same-position notes | A Room migration that could delete legitimate user data. `Entities.kt:121-122` explicitly documents "a reader may keep several notes at one spot" as intended. See §6 case C-4. |
| Library-wide import (apply every book's rows in one pass) | Contradicts the designed copy ("merge into *Pride and Prejudice*"), and the FK (W16) makes a foreign-book row a hard constraint failure rather than a soft skip. Per-book keeps the blast radius at one book. |
| `takePersistableUriPermission` on the picked/created URI | Nothing here needs post-session access. Persisting a grant is durable attack surface for zero benefit (#155 D6's stream-lifetime lesson). |
| Wiring import into the DEBUG `BackupDebugActivity` and calling it verified | This is precisely the #114/#118/#120/#122 failure (rule 47 Gate-5 "Production reachability"): a DEBUG-source-set launcher is a setup mechanism, not an entry point. |

---

## 5. Surface area — file by file

All paths are Android-only (`android/…`). **iOS files are OUT of scope** (rule 48 cross-platform
write isolation) — this plan reads `vreader/Services/Import/*.swift` for parity but writes nothing
there.

> **Dispatchability note.** Rule 55's "new files are not dispatchable" degrade is **Swift/xcodegen
> specific** (a new Swift file needs a `project.pbxproj` regen). Kotlin source sets are glob-based —
> Gradle compiles a new `.kt` with no project regeneration — and #133/#155 lanes added new Kotlin
> files routinely. The new files below are lane-safe.

### 5.1 New

**`android/app/src/main/kotlin/com/vreader/app/annotations/AnnotationBackupMapper.kt`** (~90 lines)

```kotlin
internal object AnnotationBackupMapper {
    fun toWire(r: HighlightRecord): BackupHighlight
    fun toWire(r: NoteRecord): BackupNote
    fun toWire(r: BookmarkRecord): BackupBookmark
    /** Deterministic: each kind sorted by (bookKey, id) — byte-stable regardless of Room row order. */
    fun envelope(
        highlights: List<HighlightRecord>,
        notes: List<NoteRecord>,
        bookmarks: List<BookmarkRecord>,
    ): BackupAnnotationsEnvelope
}
```

Lifted verbatim from `BackupCollector.kt:212-239` + the sort at `:193-204`. `BackupCollector`
delegates; its existing byte-stability tests are the behaviour-preservation proof.

**`.../annotations/AnnotationsExportWriter.kt`** (~110 lines)

```kotlin
class AnnotationsExportWriter(private val repo: AnnotationsRepository) {
    /** The full annotations.json text for ONE book (highlights + notes + bookmarks). */
    suspend fun exportJson(bookKey: String): String
    /** Writes exportJson(bookKey) as UTF-8 to [sink]; returns the row count written. Does NOT close [sink]. */
    suspend fun writeTo(sink: OutputStream, bookKey: String): Int

    companion object {
        /** "<sanitized title> annotations.json"; CJK/RTL letters preserved, path separators and
         *  control chars stripped, capped at MAX_NAME_CHARS, falls back to the fingerprint's sha
         *  prefix when the title is null/blank/all-stripped. (#155's MAX_NAME_CHARS=200 precedent.) */
        fun suggestedFileName(bookTitle: String?, bookKey: String): String
        const val MAX_NAME_CHARS = 200
    }
}
```

**`.../annotations/AnnotationImportModels.kt`** (~110 lines) — pure value types, no Android deps:

```kotlin
/** One preview row (design's "Preview · first three"): the dot color + the text we actually have. */
data class ImportPreviewRow(val colorKey: String?, val text: String)

data class ImportPreview(
    val fileName: String,
    val bookKey: String,
    val bookTitle: String,
    val highlights: Int,          // in-scope, valid, not-already-present
    val notes: Int,
    val bookmarks: Int,
    val skipped: Int,             // out-of-scope book + already-present + row-level invalid
    val sample: List<ImportPreviewRow>,   // ≤ 3
    internal val envelope: BackupAnnotationsEnvelope,  // the filtered, validated payload to apply
) { val importable: Int get() = highlights + notes + bookmarks }

enum class ImportFailure {
    Empty, TooLarge, NotJson, NotAnAnnotationsFile, NewerSchema, TooManyRows, Unreadable, Timeout;
    /** rule 50 §6 — a user-facing message that leaks no path and no provider detail. */
    val userMessage: String get() = …
}

sealed interface ImportParseResult {
    data class Ok(val preview: ImportPreview) : ImportParseResult
    data class Failed(val reason: ImportFailure) : ImportParseResult
}
```

**`.../annotations/AnnotationsImportReader.kt`** (~180 lines) — the untrusted-input boundary (§8):

```kotlin
object AnnotationsImportReader {
    /** Reads AT MOST MAX_IMPORT_JSON_BYTES from [input] (aborting past it — never trusting a
     *  declared size), decodes as BackupAnnotationsEnvelope, then row-validates against
     *  [targetBookKey]. Never throws for hostile input; every failure is an ImportFailure. */
    fun parse(input: InputStream, fileName: String, targetBookKey: String, bookTitle: String): ImportParseResult

    const val MAX_IMPORT_JSON_BYTES = 2L * 1024 * 1024   // 2 MiB
    const val MAX_IMPORT_ROWS = 10_000                    // summed across the three kinds
    const val MAX_FIELD_CHARS = 10_000                    // selectedText / content / title
    const val MAX_LOCATOR_JSON_CHARS = 4_096              // bounds nesting depth of the inner JSON
}
```

**`.../annotations/AnnotationsImportApplier.kt`** (~80 lines):

```kotlin
class AnnotationsImportApplier(private val repo: AnnotationsRepository) {
    /** Applies [preview]'s already-validated envelope scoped to setOf(preview.bookKey) via
     *  AnnotationsRepository.restoreAnnotations — UUID-preserving, insert-if-absent, one
     *  @Transaction. Returns the per-kind report. */
    suspend fun apply(preview: ImportPreview): RestoreAnnotationsReport
}
```

**`.../annotations/AnnotationImportPreviewSheet.kt`** (~220 lines) — the designed sheet
(`vreader-annotation-import.jsx:425-558`) as a `ModalBottomSheet`, split into
`AnnotationImportPreviewSheet` (modal wrapper) + `AnnotationImportPreviewSheetContent` (directly
composable) — the `AnnotationsReviewSheetContent` / `TocContentsSheetContent` precedent
(`AnnotationsReviewSheet.kt:104-111`: a modal's content renders in a separate window that
instrumented clicks reach unreliably). Pure function of state (rule 50 §4); `ReaderTheme` tokens.
Test tags: `annot-import-sheet`, `annot-import-cancel`, `annot-import-confirm`,
`annot-import-error`, `annot-import-chip-{highlights,notes,skipped}`.

**`.../annotations/AnnotationsIoController.kt`** (~120 lines) — the one place the four reader
activities share:

```kotlin
class AnnotationsIoController(
    private val resolver: ContentResolver,
    private val writer: AnnotationsExportWriter,
    private val applier: AnnotationsImportApplier,
    private val io: CoroutineDispatcher,     // injected — rule 50 §12.1, never hardcode Dispatchers.IO
) {
    suspend fun export(uri: Uri, bookKey: String): Result<Int>
    suspend fun preview(uri: Uri, bookKey: String, bookTitle: String): ImportParseResult
    suspend fun apply(preview: ImportPreview): RestoreAnnotationsReport
}
```

### 5.2 Modified

| File | Change |
|---|---|
| `backup/BackupCollector.kt` | `collectAnnotationsJson` delegates to `AnnotationBackupMapper.envelope(...)`; the three private mappers (`:212-239`) are deleted. **Behaviour-identical.** |
| `reader/details/BookDetailsRows.kt` | `BookActionList` gains two **nullable** callbacks `onExportAnnotations: (() -> Unit)? = null`, `onImportAnnotations: (() -> Unit)? = null`; a null one renders **no row** (capability pattern, no dead no-op — the `onJumpToAnnotation` precedent at `AnnotationsReviewSheet.kt:117`). Rows follow the shipped Share row's geometry (`:240-279`). Tags `details-export-annotations`, `details-import-annotations`. Update the file's KDoc at `:228` (rule 22 — it currently says "Share ONLY"). |
| `reader/details/BookDetailsSheet.kt` | Threads the two callbacks to `BookActionList`; header KDoc `:5-7` updated (the "NO Export" absence invariant no longer holds). |
| `reader/chrome/ReaderChromeScaffold.kt` | Two new defaulted-null params + hosts `AnnotationImportPreviewSheet` above the Details sheet. |
| `reader/EpubReaderChrome.kt` | Same, for the EPUB host. |
| `reader/ReaderActivity.kt`, `reader/TxtReaderActivity.kt`, `reader/PdfReaderActivity.kt` (+ `PdfReaderScreen.kt`), `reader/Azw3ReaderActivity.kt` (+ `Azw3ReaderChrome.kt`) | Register `ActivityResultContracts.CreateDocument("application/json")` and `ActivityResultContracts.OpenDocument()`; wire to `AnnotationsIoController`. |
| `VReaderApp.kt` | Add `annotationsExportWriter` / `annotationsImportApplier` lazies beside `annotationsRepository` (`:100`). |
| `annotations/Annotation.kt`, `data/Entities.kt` | Rule-22 comment repair for W15 only (the stale `canonicalJson()` claim). Comment-only. |

### 5.3 Explicitly OUT of scope

`vreader/**`, `vreaderTests/**`, `project.yml`, `*.xcodeproj` (rule 48 write isolation);
`docs/features.md`, `docs/architecture.md`, `README.md` (orchestrator-owned, rule 55);
`android/identity/**` (the wire DTOs need **no** change — that is the point of reusing them);
`contracts/**` (nothing about the contract changes; #165 is a new *consumer*);
`backup/BackupRestoreScreen.kt` and its DEBUG host (W12's reachability gap is a separate,
pre-existing problem — see §11 Q-4);
`android/app/src/debug/**` (no DEBUG launcher — deliberately, per rule 47 Gate-5).

---

## 6. The conflict / merge policy — the whole feature

Export is mechanical. Import must answer every collision. Each row below says **who decided it**.

### 6.1 Inherited from iOS #35 (do not re-derive)

| # | Decision | iOS evidence |
|---|---|---|
| I-1 | Dedupe key is the annotation's **own id**; an id already present is **skipped**, never overwritten. | `AnnotationImporter.swift:65-70` |
| I-2 | Import is **purely additive** — nothing existing is deleted or mutated. | `AnnotationImporter.swift:82-122` (only `add*` calls) |
| I-3 | The result is reported as **(imported, skipped)** counts. | `AnnotationImporter.swift:11-14` |
| I-4 | A **parse** failure aborts the whole import; nothing is applied. | `AnnotationImporter.swift:47` (`try` before any write); `VReaderAnnotationParser.swift:16-33` |
| I-5 | The **caller** supplies the target book; the file does not choose it. | `AnnotationImporter.swift:42-46` (`bookFingerprintKey` parameter) |

### 6.2 Inherited from Android's own restore seam (#132 WI-6b / #135)

| # | Decision | Evidence |
|---|---|---|
| R-1 | Row **UUIDs and both timestamps are preserved**, never re-minted. | `AnnotationsRepository.kt:173-179` |
| R-2 | A row whose book ∉ `allowedBookKeys` is **skipped** (soft, not an error). | `AnnotationsRepository.kt:229` |
| R-3 | A row whose `locatorJSON` won't decode, or whose `locator.fingerprintKey ≠ bookFingerprintKey`, is **failed and dropped** — "poisoning the persistence boundary is worse than dropping one row". | `AnnotationsRepository.kt:230-232` |
| R-4 | Every insert runs in **one `@Transaction`**, insert-if-absent (`OnConflictStrategy.IGNORE`). | `Daos.kt:327-350` |
| R-5 | Highlights additionally collapse on unique `(profileKey, anchorKey)`; bookmarks on `(bookKey, profileKey)`. `anchor` is **null** on a restored row, so `anchorKey = NIL_ANCHOR` and highlights effectively dedupe **by position**. | `Entities.kt:102`, `:167`; `Annotation.kt:20,27`; `AnnotationsRepository.kt:177` |

### 6.3 Decided here (#165) — the cases nobody had to answer before

| # | Case | Decision | Rationale |
|---|---|---|---|
| C-1 | **Which books may a file target?** | **Only the book whose Details sheet launched the import.** `allowedBookKeys = setOf(thatBookKey)`. Rows for any other book are counted **skipped**, never applied, never a hard error. | The designed copy names one book (`vreader-annotation-import.jsx:531-533`). It also matches I-5, and it keeps the FK (W16) safe by construction. A library-wide annotations file can still be imported book-by-book with no data loss. |
| C-2 | **Same UUID, different content.** | **Skipped — the existing row wins.** Never overwritten, never merged field-wise. | I-1 + R-4 + the design's "Existing notes are not overwritten". Last-write-wins would silently destroy edits the user made after exporting. |
| C-3 | **Same content, different UUID — highlights & bookmarks.** | **Skipped** — the unique index collapses them (R-5). The `IGNORE` insert returns `-1`, so it lands in `skipped`, not `applied`. | Re-importing your own export must not double every highlight. |
| C-4 | **Same content, different UUID — notes.** | **A duplicate note row is created.** Accepted, documented as a known limitation. **No new index, no migration.** | Notes have no unique index by design: `Entities.kt:121-122` — "No range-dedupe (a reader may keep several notes at one spot)". Adding one would be a data-destroying migration to fix a rarer problem than it creates. §10 K-1. |
| C-5 | **An annotation whose book is not in the library at all.** | **Skipped** (same path as C-1). Never triggers a book import, never a partial insert. | Without C-1's gate this is a hard `SQLiteConstraintException` (W16) — the "FK-unseeded-parent-row" defect class this repo already hit in #135. |
| C-6 | **File from a NEWER app/schema version.** | `schemaVersion > BackupSchema.CURRENT_SCHEMA_VERSION` → **refuse the whole file** with `ImportFailure.NewerSchema` in the designed error blob. `schemaVersion` in `1..CURRENT` → accept (unknown keys ignored, W23). Missing/non-integer `schemaVersion` → `NotAnAnnotationsFile`. | The contract promises **backward** compatibility only ("Pre-v3 sections are byte-identical across v1/v2/v3", `backup-format.md:32-36`). Silently importing a future shape risks dropping fields the user believes were preserved. |
| C-7 | **Partially corrupt file.** | Two tiers. **File-level** (not JSON / not an annotations envelope / over the byte or row cap) → whole-file refusal, **zero rows applied** (I-4). **Row-level** (decodes but fails validation) → that row counted in `skipped`, the rest applied. | A file whose *structure* is broken cannot be reasoned about; a *row* that is broken is one row. Matches R-3. |
| C-8 | **Empty file / empty envelope / everything skipped.** | Preview renders with `importable == 0`: the designed **disabled** primary reading `Import 0 items` (`:548-554`) plus the designed error blob explaining why. The user cannot commit a no-op. | Entirely design-specified. |
| C-9 | **Locator that decodes but is structurally invalid** (negative page/offset, inverted range). | **Row-level failure** → skipped. #165 adds `locator.validate() != null → INVALID` to the validation gate. | **This is a real gap**: `restoreAnnotations` today checks decode + fingerprint match only (W18), while `Locator.validate()` exists and is contract-pinned (`Locator.kt:51-67`). Backup restore reads your own archive; import reads an attacker-influenced file. Implemented as a **pre-filter in `AnnotationsImportReader`**, not by changing `restoreAnnotations` — that seam's semantics are shared with restore and must not shift under it. |
| C-10 | **Non-UUID row id.** | **Row-level failure** → skipped. `UUID.fromString` must parse. | iOS gets this free (typed `UUID`); Kotlin's ids are `String` with no validation anywhere (W19). Without it a hostile file sets a primary key to an arbitrary 10 000-char string. |
| C-11 | **Re-importing the same file twice.** | Second run applies **0**, skips everything, mutates nothing. | R-1 + R-4 idempotency. This is acceptance criterion **A-4** and its assertion is a full row-by-row snapshot equality, not a count (§9.2). |
| C-12 | **Export scope.** | One book: its highlights **+ notes + bookmarks**, deterministically sorted, `schemaVersion = CURRENT`. | The envelope has three kinds and #135 ships bookmarks; omitting them would make export lossy relative to the very restore path it feeds. |
| C-13 | **Export of a book with zero annotations.** | The row is still tappable; it writes a **valid empty envelope** (`highlights: [], bookmarks: [], notes: []`). No new "nothing to export" UI. | An empty-but-valid file round-trips (C-8 then refuses it on the way back in, via the designed disabled state). The alternative — a silent no-op like `shareAnnotations`' `if (text.isBlank()) return` (`ReaderActivity.kt:1056`) — leaves the user staring at a picker that produced nothing. |

---

## 7. Design decisions (numbered, for audit reference)

- **D-1 — File shape = `BackupAnnotationsEnvelope`, byte-compatible with `annotations.json`.**
  Not a new format. Pinned by `contracts/vectors/backup-sections.json` and asserted in WI-2's test.
- **D-2 — One book per file, chosen by the launching surface** (C-1, I-5).
- **D-3 — Encoding is `BackupJson.DEFAULT`** (W23) — not a fresh `Json {}`. Anything else silently
  breaks Swift parity on nils and dates.
- **D-4 — MIME is a hint, never a gate.** The picker filters `application/json`, but the declared
  type is provider-supplied and therefore attacker-influenced (#155's D7 doctrine). Validation is
  by **content**, always.
- **D-5 — No persisted URI grant.** One-shot read / one-shot write inside the activity's lifetime
  (#155 D6).
- **D-6 — Parse is bounded before it is trusted** (§8).
- **D-7 — Validation lives in the reader, not in `restoreAnnotations`.** The repository seam is
  shared with WebDAV restore; #165 must not tighten it underneath that caller. The importer hands
  `restoreAnnotations` an envelope that is **already** row-validated, so the repository's own gate
  becomes a redundant second line rather than the only one.
- **D-8 — iOS-#35 file interop is NOT delivered, and this is a real gap.** iOS #35's file is
  `AnnotationExportPayload { bookTitle, bookAuthor, exportedAt, annotations[] }`
  (`vreader/Models/ExportedAnnotation.swift:36-41`) where each row is
  `{ id, type, chapter?, selectedText?, note?, color?, title?, createdAt, updatedAt }` — **no
  locator, no book fingerprint**. Consequences, both directions:
  - *iOS file → Android*: every row would have to be anchored at a synthesized locator. iOS itself
    does this (`AnnotationImporter.swift:90-96` — a `Locator` whose only populated field is
    `textQuote = annotation.id.uuidString`). On Android such a row is unjumpable, renders nowhere,
    and its `profileKey` is a hash of a meaningless locator, so dedupe becomes nonsense.
  - *Android file → iOS*: `VReaderAnnotationParser.parse` would fail the decode outright
    (`VReaderAnnotationParser.swift:23`) — different top-level shape.

  Supporting it would mean either shipping unanchorable rows or building a locator-inference pass,
  neither of which the row's scope asks for. **Recommendation: file a follow-up feature to converge
  iOS #35's file format onto the backup envelope on both platforms** — that is the change that
  actually makes "iOS parity: #35" true at the *file* level. Escalated as **Q-1** (§11): the
  orchestrator owns tracker writes, so this plan proposes rather than files.
- **D-9 — Export/import rows are capability-gated.** A null callback renders **no row** (not a
  disabled one). Keeps every existing `BookDetailsSheet` caller and its 44 shipped connected
  assertions valid, and guarantees no dead affordance if a host forgets to wire it.
- **D-10 — Export failure surfaces as a `Toast`.** Judgement call, escalated as **Q-3b** (§11).
  Rationale: (i) an Android `Toast` is OS-rendered system chrome, the class rule 51 exempts;
  (ii) this repo already ships exactly this pattern for the sibling failure — `MainActivity.kt:97`
  and `:108` toast an import failure; (iii) silently swallowing an IO error violates rule 50 §6.
  The alternative is to file a `needs-design` for an "export result" surface; the auditor may
  prefer that and this plan will not resist it.

---

## 8. Untrusted input (rule 54) — the import file is attacker-influenced

An imported file arrives through SAF from **anywhere** — a messaging app, a download, a malicious
document provider. It gets the #155 treatment.

### 8.1 Bounds

| Bound | Value | Where |
|---|---|---|
| Size **preflight**, before opening | `OpenableColumns.SIZE > MAX_IMPORT_JSON_BYTES` → refuse, never open | `AnnotationsIoController.preview` (cursor query only — #155 D8's "before opening anything") |
| Size **guard**, after opening | a **counting** read that aborts past `MAX_IMPORT_JSON_BYTES` **regardless of the declared size** | `AnnotationsImportReader.parse` — covers absent sizes, lying sizes, and infinite streams |
| `MAX_IMPORT_JSON_BYTES` | **2 MiB** | ≈ 10 000 richly-annotated rows with headroom; two orders of magnitude below #155's 512 MiB book cap, because this is text metadata, not a book |
| `MAX_IMPORT_ROWS` | **10 000** summed across kinds | over it → `TooManyRows`, whole-file refusal (a caps-hit file is structurally suspect, C-7 tier 1) |
| `MAX_FIELD_CHARS` | **10 000** per `selectedText` / `content` / `title` / `color` | over it → **row-level failure, never truncation**. Truncating silently mutates user content. |
| `MAX_LOCATOR_JSON_CHARS` | **4 096** | bounds the *nesting depth* of the inner `locatorJSON` string before it is handed to a second decode pass — a deeply-nested payload cannot reach the recursive decoder |
| Wall-clock | `withTimeoutOrNull` on a **dedicated thread**, `close()` from the timeout path | #155 D8's honest split: the **liveness guarantee** is that the UI never wedges; unblocking a parked `read` is **best-effort**, because a blocking `InputStream.read` is not interruptible and coroutine cancellation is cooperative |

### 8.2 Per-row validation gate (all must hold; any failure → that row is `skipped`)

1. Every id parses as a `UUID` (C-10, W19).
2. `bookFingerprintKey` is syntactically a canonical key **and** equals the target book's key (C-1).
3. `locatorJSON.length ≤ MAX_LOCATOR_JSON_CHARS`, decodes as `Locator` via `BackupJson.decode`
   (R-3), and `locator.fingerprintKey == bookFingerprintKey` (R-3).
4. `locator.validate() == null` (C-9, W18).
5. Every text field within `MAX_FIELD_CHARS`.
6. `color` resolves through `AnnotationColor.from(...)`, falling back to `DEFAULT` — already the
   restore behaviour (`AnnotationsRepository.kt:175`).

### 8.3 What is explicitly forbidden in the implementation

- `inputStream.readBytes()` / `bufferedReader().readText()` on the picked URI — unbounded.
- A custom `Json { isLenient = true; allowSpecialFloatingPointValues = true }` — that reopens the
  NaN-progression canonicalization collision `Locator.repairedForCanonicalization()` exists to
  close (`Locator.kt:71-80`).
- Echoing the provider's display name or any file-system path into an error message — `ImportFailure`
  messages are fixed strings (rule 50 §6 "sanitizes paths and internal details").
- Any network access on either path.
- Writing anything to disk on the import path other than the Room transaction.

---

## 9. Test plan

### 9.1 What could pass while wrong (per acceptance criterion)

Round-trip features false-green easily: "the file was written" and "no exception was thrown" both
pass with **zero annotations surviving**. For each criterion: the naive test that would go green on
a broken build, and the assertion that discriminates.

| # | Acceptance criterion | A test that passes while broken | The discriminating assertion |
|---|---|---|---|
| A-1 | Export writes a valid `annotations.json` for the current book | `assertTrue(file.exists())` / `assertTrue(json.isNotEmpty())` — passes for `{}` and for `{"schemaVersion":3,"highlights":[],"bookmarks":[],"notes":[]}` on a book with 12 highlights | Decode the written bytes back into `BackupAnnotationsEnvelope` and assert **set equality of `(highlightId, locatorJSON, selectedText, color, note, createdAt, updatedAt)` tuples** against the repository's own rows. Counts alone are insufficient — a mapper that writes every row's `selectedText` as `""` keeps the count. |
| A-2 | The exported file is **contract-shaped** | round-tripping through our own encoder+decoder — passes even if we invented `highlight_id` | Parse the export as a raw `JsonObject` and assert its **key set and value types equal** `contracts/vectors/backup-sections.json → sections.annotations` (via `BackupJson.canonicalElement`). This is what makes an iOS-written file importable. |
| A-3 | Import merges rows into the target book | `assertEquals(12, report.highlights.applied)` — passes if all 12 landed with a garbage locator, wrong color, or on the wrong book | Assert the **post-import repository snapshot equals the pre-export snapshot**, field by field including `id`, `createdAt`, `updatedAt` and the decoded `Locator`. |
| A-4 | Import is idempotent (C-11) | `assertEquals(0, second.highlights.applied)` — passes if the second run *deleted* everything and re-inserted nothing | Snapshot the whole table **before and after** run 2 and assert **deep equality**, plus `applied == 0` **and** total row count unchanged. |
| A-5 | Existing annotations are never overwritten (C-2) | importing a file with fresh UUIDs — nothing collides, so nothing proves the rule | Seed a row, then import a file with **the same UUID and different `selectedText`/`note`/`color`**; assert the stored row still has the **original** field values and `updatedAt`. |
| A-6 | Foreign-book rows are skipped, not applied (C-1/C-5) | asserting no exception — passes if the whole import silently no-opped | Import a two-book file into book A; assert **A's rows applied**, `skipped ≥ B's row count`, **and B's table is still empty**, and that no `SQLiteConstraintException` was thrown. |
| A-7 | A hostile/malformed file is refused with nothing applied (C-7 tier 1) | `assertThrows(...)` — passes if the parser threw *after* writing half the rows | Assert the repository snapshot is **byte-identical before and after** the refused import, and that the failure is a typed `ImportFailure`, not a leaked `SerializationException`. |
| A-8 | Row-level invalid rows are skipped, valid siblings apply (C-7 tier 2, C-9, C-10) | count-only assertions | A file with 5 rows — 1 bad UUID, 1 negative `charOffsetUTF16`, 1 locator/book mismatch, 2 good — asserts `applied == 2`, `skipped == 3`, and **exactly the two good UUIDs** present. |
| A-9 | Import of a max-size file stays responsive | a JVM timing assertion | Measured **on the emulator** in WI-7's Gate-5 with a real book; the evidence file records the number. Ceiling: preview ≤ **2 s**, apply ≤ **1 s** for a 10 000-row file. (memory: *measure perf ON TARGET, not on a desktop JVM* — #139's §5 was 100× off.) |
| A-10 | Both rows are reachable by a real user | an instrumented test that composes `BookDetailsSheet` directly — this is exactly the #114/#118/#120/#122 hole | Gate-5b navigates from **app launch**: Library → tap book → reader → top-bar `⋯` → *Details* → *Export annotations…*, in a **release-configured** build, and the evidence file names that path. |

### 9.2 Test catalogue

**JVM unit (`android/app/src/test/kotlin/com/vreader/app/annotations/`)**

| File | Covers |
|---|---|
| `AnnotationBackupMapperTest.kt` | field-by-field wire mapping for all three kinds; deterministic sort; plain-`Locator` `locatorJSON` (W14, **not** `canonicalJson()`); nil-note omission (`explicitNulls=false`) |
| `AnnotationsExportWriterTest.kt` | A-1, A-2 (contract-vector key/type equality), C-12 (all three kinds), C-13 (empty envelope is valid), `suggestedFileName`: CJK title preserved, path separators + control chars stripped, `MAX_NAME_CHARS` cap, null/blank/all-stripped fallback, `.json` always |
| `AnnotationsImportReaderTest.kt` | the largest suite. Byte cap (declared-size lie **and** unknown size); row cap; field cap; locator-JSON cap; `NotJson`; `NotAnAnnotationsFile` (valid JSON, wrong shape); `NewerSchema` (C-6) + missing/non-integer `schemaVersion`; `Empty`; UTF-8 BOM; UTF-16-encoded file; truncated mid-array; CJK `selectedText` survives byte-for-byte; every row-gate in §8.2 individually; preview counts and the ≤3 sample |
| `AnnotationsImportApplierTest.kt` | in-memory Room (`Room.inMemoryDatabaseBuilder`) with a **seeded parent `BookEntity`** (the #135 FK-unseeded-parent defect class): A-3, A-4, A-5, A-6, A-8; C-3 (same-position highlight different UUID → skipped); C-4 (duplicate note **is** created — the documented limitation, asserted so a future index change trips it) |
| `BackupCollectorTest` (existing) | must stay green unmodified — the WI-1 behaviour-preservation proof |

**Connected (`android/app/src/androidTest/kotlin/com/vreader/app/annotations/`)**

| File | Covers |
|---|---|
| `AnnotationImportPreviewSheetTest.kt` | render + click. Populated (chips show H/N/Skipped, sample rows, `Import N items` enabled); error variant (blob shown, primary disabled, tapping it does nothing); zero-importable (C-8); Cancel dismisses and applies nothing; CJK text renders |
| `AnnotationsIoEntryTest.kt` | the two Details rows render, carry their tags, invoke their callbacks; **and the absence assertions** — no third row, no sub-line under either (A-1/A-2 of §3.3), Share row unchanged |
| `AnnotationsRoundTripConnectedTest.kt` | WI-7 acceptance: export → read the file back through `ContentResolver` → wipe rows → import → assert the snapshot equals the original |

> **Binding lesson from #133 and #135** (memory: *Android connected tests merged compile-only during
> host WIs are UNVERIFIED until the Gate-5 connected run*): connected tests written in WI-5/WI-6 are
> **not** trusted until they have actually run on the emulator. WI-7 budgets a test-hardening pass
> for the RED-when-run set (`waitForIdle` does not await a debounce; `compose.waitUntil` polls),
> and that pass completes **before** anything flips to `VERIFIED`. Run **one test class per
> connected invocation** — a comma-joined `class=A,B` fast-fails with `tests=0`.

### 9.3 Fixtures — real books first (inventory **verified**, not assumed)

`ls -R test-books/books/` on 2026-08-05 returns **exactly four** books:

| Path | Size | Character |
|---|---|---|
| `test-books/books/txt/黑暗血时代.txt` | 13 M | CJK TXT |
| `test-books/books/epub/道诡异仙 - 狐尾的笔.epub` | 18 M | CJK EPUB |
| `test-books/books/epub/The Half Second - Li Xiaolai.epub` | 1.2 M | Latin-titled EPUB |
| `test-books/books/azw3/Bei Tao Yan De Yong Qi - Zi Wo.azw3` | 6.0 M | CJK AZW3 |

**There is no real MD and no real PDF book.** No acceptance criterion in this plan is written
against a fixture that does not exist.

- **Gate-5 (WI-7)** uses `The Half Second - Li Xiaolai.epub` (small ⇒ fast import/open) for the
  primary round-trip, and `黑暗血时代.txt` for the **CJK payload** leg — CJK `selectedText` must
  survive UTF-8 encode → SAF write → SAF read → decode → Room byte-for-byte, which a Latin fixture
  cannot prove.
- **JVM unit tests** use synthetic JSON fixtures. Stated exception (AGENTS.md "Real books first"):
  these are **CI unit tests**, which cannot read the gitignored `test-books/`; and the hostile-input
  cases (truncated arrays, 3 MiB payloads, non-UUID ids) have no real-book equivalent **by
  construction** — a real book cannot produce a malformed annotations file.
- The AZW3 and the 18 M CJK EPUB are **not** required: format does not participate in the annotation
  wire shape, and the two chosen fixtures already cover Latin + CJK across the two chrome hosts.

### 9.4 Test-gate commands (rule 52 — wrappers only, targeted suites only)

```bash
# JVM, per WI
ANDROID_CMD="./gradlew :app:testDebugUnitTest --tests '*AnnotationsImportReaderTest*' --rerun-tasks" \
  scripts/run-android-tests.sh

# Connected, ONE class per invocation
ANDROID_SERIAL=emulator-5554 \
ANDROID_CMD="./gradlew :app:connectedDebugAndroidTest --rerun-tasks \
  -Pandroid.testInstrumentationRunnerArguments.class=com.vreader.app.annotations.AnnotationImportPreviewSheetTest" \
  scripts/run-android-tests.sh
```

`--rerun-tasks` is mandatory (memory: without it Gradle reports up-to-date and you verified
nothing). Never a bare `./gradlew`.

---

## 10. Work-item sequencing

| WI | Tier | Scope | PR size | Gate-5 |
|---|---|---|---|---|
| **WI-1** | foundational | Extract `AnnotationBackupMapper`; `BackupCollector` delegates; its byte-stability tests unchanged | S (~150 ± tests) | none |
| **WI-2** | foundational | `AnnotationsExportWriter` + `suggestedFileName` + the contract-vector conformance test (A-2) | S–M | none |
| **WI-3** | foundational | `AnnotationImportModels` + `AnnotationsImportReader`: every bound in §8, every row gate in §8.2, the whole failure taxonomy | **M–L** (largest test surface) | none |
| **WI-4** | foundational | `AnnotationsImportApplier` over `restoreAnnotations`; in-memory-Room merge tests A-3/4/5/6/8, C-3, C-4 | M | none |
| **WI-5** | behavioral | `AnnotationImportPreviewSheet` (+ `…Content` split) exactly as designed, incl. the error + zero-importable states | M | slice: connected render/click on the emulator |
| **WI-6** | behavioral | The two designed `ActionList` rows; threading through `BookDetailsSheet` / `ReaderChromeScaffold` / `EpubReaderChrome`; rule-22 KDoc repairs (incl. W15) | M | slice: rows visible + tappable via **⋯ More → Details** on a real book |
| **WI-7** | behavioral, **final** | SAF launchers in the 4 reader activities + `AnnotationsIoController` + `VReaderApp` wiring; the connected round-trip; the test-hardening pass for any RED-when-run connected test from WI-5/6 | M–L | **full acceptance**: A-1…A-10, real EPUB + real CJK TXT, release-configured build, production path named in the evidence file |

Rationale for the split: WI-1…WI-4 are pure JVM and need no emulator, so they can be gated fast and
audited independently; the untrusted-input boundary (WI-3) is deliberately isolated from the
persistence boundary (WI-4) so an audit of either is focused. WI-5/6 are the two designed surfaces.
WI-7 is the only WI that touches all four reader activities, so the fan-out risk is concentrated in
one reviewable place.

**Dependencies:** WI-2 → WI-1; WI-4 → WI-3; WI-5 → WI-3; WI-6 → (nothing hard, but ships after
WI-5 so the row it launches has a destination); WI-7 → WI-2, WI-4, WI-5, WI-6.
No dependency on any other feature row. The tracker records #165 as disjoint from #164.

---

## 11. Risks, backward compat, known limitations, open questions

### Risks + mitigations

| # | Risk | Mitigation |
|---|---|---|
| R-1 | Extracting `BackupCollector`'s mappers silently changes the backup wire bytes | WI-1 is behaviour-preserving-by-construction (lift, don't rewrite) and the collector's existing byte-stability tests run **unmodified** as the proof. |
| R-2 | Export diverges from the contract → an iOS-written archive stops importing | A-2 asserts against `contracts/vectors/backup-sections.json` directly, not against our own round-trip. (memory: *verify cross-platform contract fields against iOS + the vectors + the real decoder, not just the Gate-2 plan* — #132's `locatorJSON` = plain, not canonical.) |
| R-3 | A hostile file wedges the UI thread | §8's dedicated-thread + `withTimeoutOrNull` liveness guarantee, with the honest #155 caveat that unblocking the parked read is best-effort. |
| R-4 | Four reader activities × two launchers = copy-paste drift | All logic in `AnnotationsIoController`; the activities hold only the two `rememberLauncherForActivityResult` registrations. |
| R-5 | Connected tests written in WI-5/6 are RED when first actually run | Budgeted explicitly in WI-7 (§9.2 note) — a recurrence in both #133 and #135. |
| R-6 | Stale comments (W15) mislead the next implementer into using `canonicalJson()` for the wire | Fixed in WI-6's rule-22 pass — `Annotation.kt:8-9`, `Entities.kt:112`, `:120-121`. Comment-only, no behaviour change. **Not** filed as a bug row (tracker writes are orchestrator-owned); flagged as Q-5. |
| R-7 | An `application/json` MIME filter hides legitimate files (some providers report `text/plain` or `application/octet-stream`) | The picker passes `arrayOf("application/json", "*/*")` so nothing is unreachable; content validation is the real gate (D-4). |
| R-8 | Emulator contention wedges the connected run | Rule 52 Cause D: never drive the emulator during an in-flight connected run; cold-boot before gesture-ish tests; `adb kill-server/start-server` if stale `getprop` procs congest adbd. |

### Backward compatibility

- **Existing data:** untouched. No Room migration, no schema version bump, no entity change.
- **Existing backups:** untouched. The wire shape is unchanged; #165 adds a *reader/writer*, not a
  format.
- **Older Android clients:** a file written by this build is `schemaVersion = 3` — decodable by any
  build that already restores schema-3 archives.
- **Newer files on this build:** refused with a typed message (C-6) rather than partially applied.
- **Existing callers of `BookDetailsSheet` / `ReaderChromeScaffold`:** unchanged — every new
  parameter is nullable and defaulted (D-9), so #132/#134/#135's shipped connected assertions stay
  valid.

### Known limitations (accepted, to be restated in the PR body)

- **K-1** — Importing an annotation whose *content and position* match an existing **note** under a
  different UUID creates a duplicate note (C-4). Highlights and bookmarks do not have this
  behaviour.
- **K-2** — No iOS-#35 file interop in either direction (D-8).
- **K-3** — Import is per-book. A library-wide annotations file must be imported once per book.
- **K-4** — Export offers one format. The design's "Markdown · JSON · VReader JSON" subtitle is not
  shipped (§3.3 A-1).
- **K-5** — The imported row's `anchor` is null (inherited from `restoreAnnotations`,
  `AnnotationsRepository.kt:177`), so a highlight re-anchors by locator rather than by its precise
  engine anchor. Identical to the behaviour a WebDAV restore already has.

### Open questions for the orchestrator — resolve **before** Gate 2

- **Q-1 (scope, needs an owner).** D-8's iOS↔Android **file** interop gap. Recommendation: file a
  follow-up feature "converge iOS #35's annotation file format onto the backup `annotations.json`
  envelope (both platforms)" and cross-reference it from #165's row. Tracker writes are
  orchestrator-owned, so this plan proposes only. **If the orchestrator instead considers file
  interop in scope for #165, this plan needs a Gate-1 revision, not a Gate-3 patch** — it changes
  the parser, the merge policy, and the WI list.
- **Q-2 (scope).** Is exporting **bookmarks** alongside highlights and notes correct (C-12)? The
  row's title says "annotations"; the envelope has three kinds and #135 ships bookmarks. This plan
  says yes (omitting them makes export lossy relative to restore). Cheap to reverse if the answer
  is no.
- **Q-3 (rule 51 — the two judgement calls the auditor should press on).**
  **(a)** §3.4's choice of **B1** (Book Details Actions rows) over the import bundle's stated
  canonical **A1 + C1**, on the grounds that A1/C1 contradict a committed *Android* artboard
  (W8/W9). If the auditor disagrees, the correct outcome is a `needs-design` filing for
  "annotations-sheet overflow menu + empty-state import CTA, **Android**" — not building A1
  from the iOS artboard.
  **(b)** D-10's `Toast` for export failure. Alternative: file `needs-design` for an export-result
  surface.
  Also worth a second opinion: §3.3's three absences (A-1/A-2/A-3).
- **Q-4 (pre-existing, out of scope but should be tracked).** W12: `BackupRestoreScreen` — the whole
  WebDAV backup/restore UI — has **no production call site**; its only host is
  `android/app/src/debug/.../BackupDebugActivity.kt:27`. That is the #114 reachability class still
  open. #165 does not fix it and does not depend on it, but a reader of this plan should not infer
  that backup/restore is user-reachable today.
- **Q-5 (housekeeping).** W15's stale KDoc contradiction (`Annotation.kt:8-9` and `Entities.kt:112`
  claim the backup collector converts `locatorJSON` to `canonicalJson()`; `BackupCollector.kt:186-188`
  does the opposite). This plan repairs the comments in WI-6 under rule 22. Should it also get a bug
  row (the bug-#362 "KDoc contradiction" precedent)? Orchestrator's call.

---

## 12. Revision history

| Rev | Date | Change |
|---|---|---|
| v1 | 2026-08-05 | Gate-1 draft. Awaiting Gate-2 independent audit. |
