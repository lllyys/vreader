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
>    (`RestoreImporter.kt:119`, inside the private `restoreAnnotations` wrapper that
>    `RestoreImporter.kt:105` invokes), whose screen has **no `main`/release production call site**.
>    `grep -rn "BackupRestoreScreen(" android/` returns four `androidTest` hits, the definition
>    (`backup/BackupRestoreScreen.kt:32`), and one DEBUG host
>    (`android/app/src/debug/kotlin/com/vreader/app/backup/BackupDebugActivity.kt:27`);
>    `grep -rn "BackupRestoreScreen(" android/app/src/main/kotlin/` returns **only the definition**.
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

**What this feature delivers — and the two halves ship on different schedules.** Both operate on
one book. Only the import half is user-reachable in the first pass.

- **Import — production-reachable now.** An `annotations.json`-shaped file read through SAF
  `ACTION_OPEN_DOCUMENT`, previewed, then merged **non-destructively** into that book, from a
  production surface a user can reach (reader top bar → `⋯` More → **Details** → *Import
  annotations…*). Fully designed; ships WI-3…WI-7.
- **Export — FOUNDATION ONLY until `needs-design` #2085 clears.** The writer
  (`AnnotationsExportWriter`, WI-2) and its bounded SAF I/O path (WI-4b) ship and are fully tested
  on the JVM, but **no user-reachable entry point is built**: the designed `Export annotations…`
  row and its result wiring are `BLOCKED: needs-design (#2085)` and land as **WI-8**. Until then
  the export half has **no production surface**, cannot be exercised end-to-end, and the feature
  row is **capped at `DONE`** (rule 47 Gate 5). See §3, §7 D-10, §10.

> Consequence worth stating once, plainly: **in the first pass a user can import a file but cannot
> produce one from the app.** The only source of an importable file is a WebDAV backup archive's
> `annotations.json`. That is a filed, labelled, WI-attached blocker (#2085) — not a deferral, and
> not something a reader of this plan should discover in §10.

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
| W11 | Its only caller is the WebDAV restore path — the repository seam is invoked at `RestoreImporter.kt:119`, inside the private wrapper that `RestoreImporter.kt:105` calls. | `backup/RestoreImporter.kt:105` (wrapper call), `:114-121` (wrapper body, seam at `:119`) |
| W12 | That path's screen has **no `main`/release production call site**. | `grep -rn "BackupRestoreScreen(" android/app/src/main/kotlin/` → **one hit, the definition** (`backup/BackupRestoreScreen.kt:32`). The repo-wide grep additionally returns 4 `androidTest` hits (`androidTest/.../BackupRestoreScreenTest.kt:30,86,95,104`) and one DEBUG host (`android/app/src/debug/.../BackupDebugActivity.kt:27`) — neither ships in a release APK. |
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
| **W26** | **`BoundedCallGate` — the bounded-execution primitive #155's D8 gap needed — is SHIPPED on main**, not a plan proposal. It puts a hard bound on how long the *caller* waits for `ContentResolver.query` / `openInputStream` / a blocking `read`, returns `Completed`/`Failed`/`TimedOut`, disposes late results, and counts abandoned calls with self-healing admission. | `imports/IncomingImportCoordinator.kt:167-257` (class), `:133-140` (`BoundedCall`), `:142-166` (the doc that names exactly this hazard) |
| W27 | It is reachable from the app container as `container.incomingImportCoordinator.boundedCalls`. | `imports/IncomingImportCoordinator.kt:381`; container at `VReaderApp.kt:386` |
| W28 | The shipped caller pattern is: admission check → bounded `peek` → pre-open preflight → re-check admission → bounded `open` with a **mandatory** `dispose = { it?.stream?.close() }`. | `imports/ImportActivity.kt:223`, `:225-229`, `:231-239`, `:243`, `:245-255` |
| W29 | `MAX_ABANDONED_CALLS = 20`; the private elastic lane is `inboundBlockingLane()`; `CountingGuardStream` + `ImportSizeCapExceeded` are the post-open byte backstop. | `imports/IncomingImportCoordinator.kt:714`, `:269-272`, `:288-300` |
| W30 | `IncomingBookResolver.sanitizeDisplayName(raw, format)` is **public** on a public class and already handles: leaf-only (path traversal), a raw pre-normalization bound, NFC, `Character.CONTROL` strip, the **enumerated full `Bidi_Control` set**, unpaired-surrogate strip, and a length cap that never splits a surrogate pair. | `imports/IncomingBookResolver.kt:79` (public class), `:236-239` (public companion, `MAX_NAME_CHARS = 200`, `FALLBACK_NAME`), `:294-334`, `:253` (the Bidi comment) |
| W31 | `BackupSchema.ACCEPTED_SCHEMA_VERSIONS = setOf(1, 2, 3)` exists and is already the restore path's version gate — so C-6 must use it, not a hand-rolled range. | `android/identity/.../backup/BackupSchema.kt:11,14`; used at `backup/RestoreImporter.kt:118` |
| W32 | `LibraryRepository.findBook(fingerprintKey): Book?` exists — the pre-apply parent-row check C-5b needs. | `data/LibraryRepository.kt:85` |

**Non-claims.** This plan does **not** claim the WebDAV Backup screen is user-reachable (W12 says it
is not), does not claim any annotations import UI exists (W1), and does not claim the `⋯` More menu
currently offers anything annotation-file-related.

---

## 3. Rule-51 verdict (design gate) — checked, not assumed

**Verdict: PROCEED on the IMPORT half; the EXPORT half is BLOCKED on `needs-design` #2085.**

- **Import** — every state is depicted (§3.1). Proceeds in full.
- **Export** — the entry row and the (system) picker are designed; **failure feedback is not**.
  Filed as `needs-design` **#2085** (2026-08-05, this session). WI-6's Export row and WI-7's
  export result wiring are `BLOCKED: needs-design (#2085)` — §10. The export *writer* (WI-2) and
  its bounded I/O path (WI-4b) are foundational and still ship; they are simply not user-reachable
  until #2085 lands, and per rule 47 Gate 5 the export half is **capped at `DONE`** until then.

Three secondary-text omissions are recorded in §3.3 as **absences** (never inventions); one
candidate omission (A-4) was rejected and is built; one (A-5) became the #2085 filing.

### 3.1 State-by-state evidence

| Required state | Depicted? | Artboard |
|---|---|---|
| Export entry (a row in a card the user can reach) | **yes** | `vreader-book-details.jsx:215` — `{ icon: Icons.Download, label: 'Export annotations…' }` inside `ActionList`, the same card Android ships at `BookDetailsRows.kt:228` |
| **Export result — failure** | **NO → filed** | Nothing depicts it; no shipped string fits verbatim (`MainActivity.kt:59-64` is all import copy). **`needs-design` #2085**, §7 D-10. Export success stays silent by the #155 precedent (D-10a). |
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

### 3.3 Design-fidelity ledger — three absences, one rejected omission (built), one filing

Rule 51 prohibits **inventing**. Omitting depicted decorative/secondary text where the underlying
data does not exist is the same class of absence #134 WI-4 already exercised
(`BookDetailsSheet.kt:5-7`: "NO cover art, NO 'Tap to add cover' placeholder, NO Export, no
author-when-null"). Each omission below is recorded so the Gate-2 auditor can overrule it.

| # | Depicted element | Shipped as | Why |
|---|---|---|---|
| A-1 | Export row `sub`: `Markdown · JSON · VReader JSON` (`vreader-book-details.jsx:215`) | row label only, **no sub-line** | Android exports exactly one format. Rendering a three-format subtitle would be a **false affordance** — strictly worse than omitting decoration. Android's shipped `ActionList` row already renders label + chevron with no sub (`BookDetailsRows.kt:264-278`). |
| A-2 | Import row `sub`: `VReader JSON · Readwise · Apple Books` (`vreader-annotation-import.jsx:322`) | row label only, **no sub-line** | Same reason: no Readwise/Apple-Books importer is in scope, and advertising one is a lie. |
| A-3 | Preview sample-row meta line: `<chapter> · p. <page>` (`vreader-annotation-import.jsx:510-520`) | color dot + quoted text (highlights) / note content (notes); **no chapter·page line** | The wire row carries only `locatorJSON` (`BackupSections.kt:26-35`). Chapter titles are not derivable for an arbitrary book at import time, and `page` exists only for PDF. Rendering a fabricated or blank meta line is worse than omitting it. |

**A-4 was a candidate omission and is REJECTED — the element is BUILT.** Gate-2 round 1 (Medium)
caught that §3.4 cites B1's merge-policy footnote as design justification while WI-6 shipped only
the two rows. Citing a depicted element as the reason a policy needs no UI, and then not drawing
it, is having it both ways. **WI-6 renders the footnote verbatim** as a caption under the Actions
card: *"Imports merge into this book by passage match; existing notes are not overwritten."*
(`vreader-annotation-import.jsx:332-339`, which the artboard renders **only** for
`variant === 'B1-paired'` — the variant this plan selected, so it is part of what B1 *is*, not an
optional extra). Test tag `details-annotations-footnote`; asserted present in
`AnnotationsIoEntryTest`. Copy accuracy: "by passage match" is exact for highlights and bookmarks
(`profileKey` is a hash of the canonical locator, i.e. the position) and approximate for notes,
which dedupe by id only — recorded as **K-1**, not silently glossed.

**A-5 is NOT an omission either — it is a FILING.** Export-failure feedback has no depicted
surface and no reusable shipped string, so it is not an absence to rationalize away: it is
`needs-design` **#2085**, filed unconditionally in this session, with WI-6's Export row and WI-7's
export wiring marked `BLOCKED: needs-design (#2085)` (§10). The distinction from A-1/A-2/A-3
matters and is the line this ledger exists to hold: **omitting a decorative sub-line whose data
does not exist is an absence; omitting a required state is a design gap.** A-1/A-2/A-3 remove
text; A-5 would have had to *invent* a notification. Round 2 got this wrong by reaching for a
`Toast` — see D-10.

The **error blob**, the **count chips** (including `Skipped`), the **merge-policy copy** (both the
in-sheet line and the Actions-card footnote), the **Cancel / Import N items** button pair and the
**file-name header** are all built as depicted.

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
  **Note the plan text is now behind the code**: D8's "OPEN GAP" was closed and
  **`BoundedCallGate` is shipped on main** (W26) — #165 reuses the *implementation*, not the
  plan's prose. §8.1 is the application of it; round 1 of this plan cited D8 and then reproduced
  its defect, which is the concrete reason "cite the precedent" and "apply the precedent" are
  tracked as different things here.
- The shipped primitives it brings with it: `CountingGuardStream` + `ImportSizeCapExceeded` (the
  post-open byte backstop), `inboundBlockingLane()` (the private elastic pool — never
  `Dispatchers.IO`), and `IncomingBookResolver.sanitizeDisplayName` (W30) for provider-supplied text.
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

**`.../annotations/AnnotationImportModels.kt`** (~130 lines) — pure value types, no Android deps:

```kotlin
/** One preview row (design's "Preview · first three"): the dot color + the text we actually have. */
data class ImportPreviewRow(val colorKey: String?, val text: String)

data class ImportPreview(
    /** ALWAYS sanitized via IncomingBookResolver.sanitizeDisplayName — provider-controlled (§8.4). */
    val fileName: String,
    val bookKey: String,
    val bookTitle: String,
    val highlights: Int,          // what apply WILL insert — see §6.4
    val notes: Int,
    val bookmarks: Int,
    val skipped: Int,             // every row that will NOT insert, whatever the reason
    val sample: List<ImportPreviewRow>,   // ≤ 3
    /** The COLLAPSED, validated, already-present-filtered payload. `restoreAnnotations` over this
     *  envelope inserts exactly `importable` rows on an unchanged DB (§6.4's preview==apply rule). */
    internal val envelope: BackupAnnotationsEnvelope,
) { val importable: Int get() = highlights + notes + bookmarks }

enum class ImportFailure {
    Empty, TooLarge, NotJson, NotAnAnnotationsFile, UnsupportedSchema, TooManyRows,
    Unreadable, Timeout, Busy, BookMissing;
    /** rule 50 §6 — a fixed user-facing string; never echoes a path, provider detail, or file name. */
    val userMessage: String get() = …
}

sealed interface ImportParseResult {
    data class Ok(val preview: ImportPreview) : ImportParseResult
    data class Failed(val reason: ImportFailure) : ImportParseResult
}
```

**`.../annotations/AnnotationsImportReader.kt`** (~230 lines) — the untrusted-input boundary (§8).
Pure: it is handed an already-open stream and the target book's current annotation state, so it has
**no Android dependency and no blocking-call surface of its own** — every `ContentResolver` touch
lives in `AnnotationsIoController` behind the gate (§8.1).

```kotlin
/** The target book's current annotation identity state — what "already present" means (§6.4). */
data class ExistingAnnotationState(
    val ids: Set<String>,                 // every id across all three kinds (cross-kind, iOS-global semantics)
    val highlightProfileKeys: Set<String>,
    val bookmarkProfileKeys: Set<String>,
)

object AnnotationsImportReader {
    /**
     * Reads AT MOST MAX_IMPORT_JSON_BYTES from [input] (aborting past it — never trusting a declared
     * size), decodes as BackupAnnotationsEnvelope, row-validates against [targetBookKey], collapses
     * INTRA-FILE duplicates (§6.4), and drops rows [existing] already has. Never throws for hostile
     * input; every failure is an ImportFailure. [fileName] must already be sanitized by the caller.
     */
    fun parse(
        input: InputStream,
        fileName: String,
        targetBookKey: String,
        bookTitle: String,
        existing: ExistingAnnotationState,
    ): ImportParseResult

    const val MAX_IMPORT_JSON_BYTES = 2L * 1024 * 1024   // 2 MiB
    const val MAX_IMPORT_ROWS = 10_000                    // summed across the three kinds
    const val MAX_FIELD_CHARS = 10_000                    // selectedText / content / title / color
    const val MAX_LOCATOR_JSON_CHARS = 4_096              // bounds nesting depth of the inner JSON
}
```

**`.../annotations/AnnotationsImportApplier.kt`** (~110 lines):

```kotlin
class AnnotationsImportApplier(
    private val repo: AnnotationsRepository,
    private val library: LibraryRepository,
) {
    /** Reads the target book's current annotation identity state — the preview's `existing` input. */
    suspend fun existingState(bookKey: String): ExistingAnnotationState

    /**
     * Applies [preview]'s collapsed envelope scoped to `setOf(preview.bookKey)` via
     * `AnnotationsRepository.restoreAnnotations` (UUID-preserving, insert-if-absent, one
     * @Transaction). Re-checks the parent BookEntity immediately before applying (C-5b) and maps a
     * lost-parent FK violation to `ImportFailure.BookMissing` rather than letting it escape.
     */
    suspend fun apply(preview: ImportPreview): Result<RestoreAnnotationsReport>
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

**`.../annotations/AnnotationsIoController.kt`** (~190 lines) — **the only place in this feature that
touches `ContentResolver`, and every touch goes through the gate** (§8.1). Shared by the four reader
activities:

```kotlin
class AnnotationsIoController(
    private val resolver: ContentResolver,
    private val writer: AnnotationsExportWriter,
    private val applier: AnnotationsImportApplier,
    /** The SHIPPED BoundedCallGate instance (W26/W27) — `container.incomingImportCoordinator.boundedCalls`.
     *  Injected, not constructed: the abandoned-call budget must be ONE ledger app-wide, or two
     *  independent gates each admit MAX_ABANDONED_CALLS parked provider threads. */
    private val gate: BoundedCallGate,
    private val timeoutMillis: Long = DEFAULT_IO_TIMEOUT_MILLIS,
) {
    /** Open (bounded) → write (bounded) → close. Returns the row count, or a typed failure. */
    suspend fun export(uri: Uri, bookKey: String): Result<Int>

    /** Metadata query (bounded) → size preflight → open (bounded, `dispose` closes a late stream)
     *  → bounded read+parse. Name sanitized before it can reach the sheet. */
    suspend fun preview(uri: Uri, bookKey: String, bookTitle: String): ImportParseResult

    suspend fun apply(preview: ImportPreview): Result<RestoreAnnotationsReport>

    companion object { const val DEFAULT_IO_TIMEOUT_MILLIS = 10_000L }
}
```

> **`imports/` is READ-ONLY for #165.** We *call* `BoundedCallGate` / `CountingGuardStream` /
> `IncomingBookResolver.sanitizeDisplayName`; we do not edit, move, or re-declare them. They are
> `public`/`internal` inside `:app`, so a call from `com.vreader.app.annotations` compiles as-is.
> This keeps #165's write-set disjoint from any in-flight #155 work. Relocating the three shared
> primitives into a neutral `com.vreader.app.io` package is a **named follow-up** (§11 Q-6), not
> this feature's job — doing it here would collide with #155's files for no behavioural gain.

### 5.2 Modified

**Every UI/plumbing edit below is scoped to a WI**, because the export entry point is
`BLOCKED: needs-design (#2085)` (§3, §7 D-10, §10). The rule is uniform: **an edit that makes the
export row or its result reachable is WI-8; everything else is WI-6/WI-7.** No file gets its export
half "while we're in there".

| File | Change | WI |
|---|---|---|
| `backup/BackupCollector.kt` | `collectAnnotationsJson` delegates to `AnnotationBackupMapper.envelope(...)`; the three private mappers (`:212-239`) are deleted. **Behaviour-identical.** | WI-1 |
| `reader/details/BookDetailsRows.kt` | `BookActionList` gains **one** nullable callback `onImportAnnotations: (() -> Unit)? = null`; null renders **no row** (capability pattern, no dead no-op — the `onJumpToAnnotation` precedent at `AnnotationsReviewSheet.kt:117`). The row follows the shipped Share row's geometry (`:240-279`). **Plus B1's merge-policy footnote caption** under the card when it is non-null (§3.3 A-4). Tags `details-import-annotations`, `details-annotations-footnote`. KDoc at `:228` updated (rule 22 — it currently says "Share ONLY"; it becomes "Share + Import — **Export still omitted, blocked on needs-design #2085**"). | **WI-6** |
| `reader/details/BookDetailsRows.kt` | Adds the second callback `onExportAnnotations: (() -> Unit)? = null`, the **`Export annotations…` row** above Import per `vreader-annotation-import.jsx:317-325`, and tag `details-export-annotations`. KDoc updated again to drop the #2085 note. | **WI-8** |
| `reader/details/BookDetailsSheet.kt` | Threads `onImportAnnotations` to `BookActionList`. **The header KDoc's "NO Export" absence invariant (`:5-7`) STILL HOLDS and is left standing** — round 3 said it "no longer holds", which was true only for a plan that shipped the export row. Its wording is refreshed to cite #2085 as the reason, not #134's scope call. | **WI-6** |
| `reader/details/BookDetailsSheet.kt` | Threads `onExportAnnotations`; **now** the "NO Export" invariant is retired from the KDoc. | **WI-8** |
| `reader/chrome/ReaderChromeScaffold.kt` | **One** new defaulted-null param (`onImportAnnotations`) + hosts `AnnotationImportPreviewSheet` above the Details sheet. | **WI-6/WI-7** |
| `reader/chrome/ReaderChromeScaffold.kt` | Adds `onExportAnnotations`. | **WI-8** |
| `reader/EpubReaderChrome.kt` | Same split, for the EPUB host. | **WI-6/WI-7**, then **WI-8** |
| `reader/ReaderActivity.kt`, `reader/TxtReaderActivity.kt`, `reader/PdfReaderActivity.kt` (+ `PdfReaderScreen.kt`), `reader/Azw3ReaderActivity.kt` (+ `Azw3ReaderChrome.kt`) | Register **`ActivityResultContracts.OpenDocument()`** only, wired to `AnnotationsIoController.preview`/`apply`. | **WI-7** |
| the same four activities | Register **`ActivityResultContracts.CreateDocument("application/json")`**, wired to `AnnotationsIoController.export`, plus the #2085-designed result surface. | **WI-8** |
| `VReaderApp.kt` | Add `annotationsExportWriter` / `annotationsImportApplier` lazies beside `annotationsRepository` (`:100`). The controller is built per-activity from those plus `contentResolver` and `incomingImportCoordinator.boundedCalls` (`:386`) — **the existing gate instance, never a fresh one** (one abandoned-call ledger app-wide). **Both** lazies land here: `AnnotationsIoController` takes the writer as a constructor param, so it is *constructed* at WI-7 while `export()` stays unreachable until WI-8 — consistent with WI-4b shipping the bounded export path in full (§10). | **WI-7** |
| `annotations/Annotation.kt`, `data/Entities.kt` | Rule-22 comment repair for W15 only (the stale `canonicalJson()` claim). Comment-only. | WI-6 |

### 5.3 Explicitly OUT of scope

`vreader/**`, `vreaderTests/**`, `project.yml`, `*.xcodeproj` (rule 48 write isolation);
`docs/features.md`, `docs/architecture.md`, `README.md` (orchestrator-owned, rule 55);
`android/identity/**` (the wire DTOs need **no** change — that is the point of reusing them);
`android/app/src/main/kotlin/com/vreader/app/imports/**` (**read-only** — called, never edited;
keeps #165 disjoint from #155);
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
| C-5a | **An annotation whose book is not in the library at all** (a foreign `bookFingerprintKey`). | **Skipped** (same path as C-1). Never triggers a book import, never a partial insert. | Without C-1's gate this is a hard `SQLiteConstraintException` (W16) — the "FK-unseeded-parent-row" defect class this repo already hit in #135. |
| **C-5b** | **The TARGET book itself is absent or stale** — the row's key equals `targetBookKey`, so C-1/C-5a pass it, but the parent `BookEntity` was deleted (or the reader was launched with a key that no longer resolves) while the sheet was open. **Gate-2 round 1 (Medium): C-1 does not cover this.** | Two layers, and the second is the one that actually holds. **(1)** `AnnotationsImportApplier.apply` calls `library.findBook(preview.bookKey)` (W32) immediately before applying; null → `ImportFailure.BookMissing`, nothing attempted. **(2)** The apply is wrapped so a lost-parent `SQLiteConstraintException` from the transaction maps to the same typed `BookMissing` instead of escaping. | Layer 1 alone is **check-then-act** and races a concurrent delete; naming it as sufficient would be exactly the kind of false assurance this gate exists to catch. Layer 2 is what makes the outcome typed in every interleaving. The transaction is atomic, so a violation leaves zero rows applied — the failure is total and reportable, never partial. Surfaced through the designed error blob. |
| C-6 | **File from an unsupported schema version.** | `schemaVersion !in BackupSchema.ACCEPTED_SCHEMA_VERSIONS` (`= setOf(1, 2, 3)`, W31) → **refuse the whole file** with `ImportFailure.UnsupportedSchema` in the designed error blob. In-set → accept (unknown keys ignored, W23). Missing/non-integer `schemaVersion` → `NotAnAnnotationsFile`. | Reuses the **same constant the restore path already gates on** (`RestoreImporter.kt:118`) rather than a hand-rolled `1..CURRENT` — one version policy, not two that can drift. The contract promises **backward** compatibility only (`backup-format.md:32-36`); silently importing a future shape risks dropping fields the user believes were preserved. |
| C-7 | **Partially corrupt file.** | Two tiers. **File-level** (not JSON / not an annotations envelope / over the byte or row cap) → whole-file refusal, **zero rows applied** (I-4). **Row-level** (decodes but fails validation) → that row counted in `skipped`, the rest applied. | A file whose *structure* is broken cannot be reasoned about; a *row* that is broken is one row. Matches R-3. |
| C-8 | **Empty file / empty envelope / everything skipped.** | Preview renders with `importable == 0`: the designed **disabled** primary reading `Import 0 items` (`:548-554`) plus the designed error blob explaining why. The user cannot commit a no-op. | Entirely design-specified. |
| C-9 | **Locator that decodes but is structurally invalid** (negative page/offset, inverted range). | **Row-level failure** → skipped. #165 adds `locator.validate() != null → INVALID` to the validation gate. | **This is a real gap**: `restoreAnnotations` today checks decode + fingerprint match only (W18), while `Locator.validate()` exists and is contract-pinned (`Locator.kt:51-67`). Backup restore reads your own archive; import reads an attacker-influenced file. Implemented as a **pre-filter in `AnnotationsImportReader`**, not by changing `restoreAnnotations` — that seam's semantics are shared with restore and must not shift under it. |
| C-10 | **Non-UUID row id.** | **Row-level failure** → skipped. `UUID.fromString` must parse. | iOS gets this free (typed `UUID`); Kotlin's ids are `String` with no validation anywhere (W19). Without it a hostile file sets a primary key to an arbitrary 10 000-char string. |
| C-11 | **Re-importing the same file twice.** | Second run applies **0**, skips everything, mutates nothing. | R-1 + R-4 idempotency. This is acceptance criterion **A-4** and its assertion is a full row-by-row snapshot equality, not a count (§9.2). |
| C-12 | **Export scope.** | One book: its highlights **+ notes + bookmarks**, deterministically sorted, `schemaVersion = CURRENT`. | The envelope has three kinds and #135 ships bookmarks; omitting them would make export lossy relative to the very restore path it feeds. |
| C-13 | **Export of a book with zero annotations.** | The row is still tappable; it writes a **valid empty envelope** (`highlights: [], bookmarks: [], notes: []`). No new "nothing to export" UI. | An empty-but-valid file round-trips (C-8 then refuses it on the way back in, via the designed disabled state). The alternative — a silent no-op like `shareAnnotations`' `if (text.isBlank()) return` (`ReaderActivity.kt:1056`) — leaves the user staring at a picker that produced nothing. |

### 6.4 Intra-file collisions — duplicates INSIDE one file (Gate-2 round 1, HIGH)

**What round 1 missed.** C-1…C-13 are all *file versus database*. A hostile — or merely
sloppily-concatenated — file can collide **with itself**, and the database layer silently absorbs
those collisions with `OnConflictStrategy.IGNORE` (`Daos.kt:327-334`). Two concrete consequences the
auditor named:

1. **Preview lies.** `restoreAnnotationEntities` counts `applied` as `count { insert(it) != -1L }`
   (`Daos.kt:346-348`). Two rows in one file sharing an id — or two highlights sharing a position —
   produce **one** insert. A preview that counted rows would show `Import 12 items` and the user
   would get 9. **The number the user approves must be the number they get.**
2. **Cross-kind id reuse applies twice.** iOS dedupes against ONE global
   `existingAnnotationIds: Set<UUID>` (`AnnotationImporter.swift:21`, `:65-70`). Android has three
   tables with **table-local** primary keys (`Entities.kt:105`, `:137`, `:170`), so the same UUID as
   both a `highlightId` and an `annotationId` inserts into both tables. Nothing in the schema stops
   it.

**The rule: the importer COLLAPSES the file to exactly what apply will insert, before the preview
is built.** `AnnotationsImportReader.parse` performs this in a fixed order, and every dropped row
increments `skipped`:

| # | Intra-file collision | Policy | Key used |
|---|---|---|---|
| F-1 | Same id twice **within one kind** | keep the **first** occurrence in file order; drop the rest | the row id |
| F-2 | Same id across **different kinds** | keep the first in the fixed kind order **highlights → notes → bookmarks**; drop the rest | the row id, in ONE global set — restoring iOS's global-uniqueness semantics on a schema that cannot enforce it |
| F-3 | Two **highlights** at the same position (different ids) | keep the first; drop the rest | `profileKey` (`= "$bookKey:${sha256(locator.canonicalJson())}"`, `Annotation.kt:24-25`). `anchor` is null on every imported row (`AnnotationsRepository.kt:177`), so `anchorKey` is the constant `NIL_ANCHOR` and the unique `(profileKey, anchorKey)` index (`Entities.kt:102`) reduces to `profileKey` |
| F-4 | Two **bookmarks** at the same position (different ids) | keep the first; drop the rest | `profileKey` — mirrors the unique `(bookKey, profileKey)` index (`Entities.kt:167`) |
| F-5 | Two **notes** at the same position (different ids) | **both kept** — genuinely two rows | no unique index by design (`Entities.kt:134`, `:121-122`). Consistent with C-4. |

**Then, in the same pass, rows the DATABASE already has are dropped too** — by the same three keys,
against `ExistingAnnotationState` (ids across all kinds, highlight `profileKey`s, bookmark
`profileKey`s), read via `AnnotationsImportApplier.existingState(bookKey)`.

**Determinism.** "First occurrence in file order" makes the collapse a pure function of the file —
two previews of the same bytes produce the same counts and the same sample rows. F-2's kind order is
fixed for the same reason.

**Why collapse rather than let Room absorb it.** Three payoffs: (a) the preview count is exact by
construction, not by hope; (b) it is testable on the JVM with no database; (c) `skipped` becomes a
single honest number covering every reason a row will not land — which is what the designed chip
already promises.

**The invariant this establishes (asserted, not assumed) — `preview.importable == applied`.**
On an unchanged database, applying a preview's collapsed envelope inserts *exactly*
`preview.importable` rows. Acceptance criterion **A-11** asserts equality against the real
`RestoreAnnotationsReport` for the hostile-duplicate fixture, which is the only test that can catch
a regression in this whole subsection.

**Honest residual — TOCTOU.** The database can change between `existingState` and `apply` (the
sheet is modal and the user is not annotating concurrently, but "unlikely" is not "impossible").
The **authoritative** count is always the `RestoreAnnotationsReport` the apply returns, never the
preview. On divergence the applier logs both numbers at `warn`; the user-visible outcome is the
merged list itself (§3.2), which shows the truth regardless. We do **not** hold a transaction open
across the user's decision — that would block every other annotation write for as long as the sheet
is up.

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
- **D-6 — Every `ContentResolver` call runs through the SHIPPED `BoundedCallGate`, not just the
  read.** Round-1 bounded the bytes after a stream existed and cited #155 as precedent — but #155's
  actual finding is that `query` / `openInputStream` / `openOutputStream` **park before your read
  guard is ever reached**, that `withContext(Dispatchers.IO)` relocates the block without bounding
  it, and that coroutine cancellation cannot interrupt a blocking `read`. Citing the precedent is
  not applying it. §8.1 now puts the metadata query, the open, and the transfer behind
  `container.incomingImportCoordinator.boundedCalls` (W26/W27) with the caller pattern
  `ImportActivity.kt:223-255` already proves out — including the **mandatory `dispose`** that closes
  a stream produced after the deadline. **Reuse, do not re-derive**: a second gate would mean a
  second `MAX_ABANDONED_CALLS` budget, i.e. double the parked-thread ceiling.
- **D-11 — The importer collapses intra-file duplicates so the preview count is the apply count**
  (§6.4). `preview.importable == applied` is an asserted invariant (A-11), not a hope.
- **D-12 — Cross-kind id uniqueness is enforced in the importer** (§6.4 F-2), restoring iOS's
  single global `existingAnnotationIds` semantics on a three-table schema that cannot express it.
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
  neither of which the row's scope asks for. **RESOLVED at Gate-2 round 1**: the orchestrator ruled
  interop **out of scope for #165** and filed the convergence work — "converge iOS #35's file format
  onto the backup envelope on both platforms" — as **feature #173 / GH #2082**. #165 exports the
  versioned contract shape. The gap is tracked (K-2), not deferred conditionally.
- **D-9 — Export/import rows are capability-gated.** A null callback renders **no row** (not a
  disabled one). Keeps every existing `BookDetailsSheet` caller and its 44 shipped connected
  assertions valid, and guarantees no dead affordance if a host forgets to wire it.
- **D-10 — Export failure is DESIGN-BLOCKED on `needs-design` #2085; the export entry point does
  not ship until it lands.** *(Supersedes round 2's "surface it as a `Toast`" — that was an
  invented surface wearing system-chrome clothing.)* The orchestrator's Gate-2 round-2 ruling was
  **reuse a shipped designed string verbatim, or file — no third option.** Both alternatives were
  checked against the code, and both fail:
  1. **Reuse.** The complete shipped Android failure copy is `MainActivity.kt:59-64`:
     `"Unsupported format: <name>"`, `"Couldn't open the file"`, `"Import failed"`. All three
     describe **import**. `"Couldn't open the file"` is *factually wrong* for a write failure, and
     `"Import failed"` names the wrong operation. **Nothing fits verbatim.**
  2. **Silence.** Violates rule 50 §6 and tells the user a file was saved when it was not.
  Nor does the neighbouring **#2030** ("Android book-**import** feedback … for feature #155")
  absorb it — different operation, different feature. Its own KDoc
  (`MainActivity.kt:49-58`) is the precedent shape for this decision: *"every string here is the
  ALREADY-SHIPPED SAF-import copy … reused verbatim; nothing new is introduced. The designed …
  treatments are BLOCKED on needs-design #2030 and are not invented here."*
  **Filed 2026-08-05, unconditionally, in this session: `needs-design` #2085** — *"Design needed:
  Android annotations-export result feedback for feature #165"*, labels `enhancement` +
  `needs-design`, listing three required failure states (write failure, timeout/unresponsive
  destination, book-no-longer-available) with line-cited current chrome. Verified open via
  `gh issue list --label needs-design --state open`. **Consequence** in §10 and §3.3 A-5. No
  "if/when" phrasing appears anywhere in this plan.
- **D-10a — Export SUCCESS stays silent, and that is not a design gap.** #155 shipped silent
  success deliberately ("Success is SILENT for a new book AND for a duplicate, matching iOS" —
  `MainActivity.kt:53-54`), and the file appearing at the location the user chose in the system
  picker is self-evidencing. #2085 asks the designer whether Android wants a save confirmation,
  but silence needs no design to ship.
- **D-10b — Import failure needs nothing new.** Every import failure — including `Busy`,
  `Timeout` and `BookMissing` — renders in the **committed** `ImportPreviewSheet` error branch
  (`vreader-annotation-import.jsx:477-484`) with the disabled primary (`:548-554`). The import
  half is unblocked.

---

## 8. Untrusted input (rule 54) — the file AND the provider are attacker-influenced

An imported file arrives through SAF from **anywhere** — a messaging app, a download, a malicious
document provider. It gets the #155 treatment — **applied, not merely cited**.

### 8.1 The blocking-call boundary (HIGH-1's fix)

**The hazard, stated precisely.** `ContentResolver.query`, `openInputStream`, `openOutputStream`
and a blocking `InputStream.read`/`OutputStream.write` are **synchronous and uninterruptible**, and
they run **inside a provider process the attacker may control**. A provider that simply never
returns from `openInputStream` parks the calling thread forever. `withContext(Dispatchers.IO)`
relocates that block onto the shared pool without bounding it; coroutine cancellation cannot
interrupt it (the caller unwinds while the thread stays parked). A byte cap on the *read* is
therefore irrelevant — the code never reaches it. This is the exact defect #155 spent six Gate-4
rounds closing, and round 1 of this plan reproduced it while citing #155 as its precedent.

**The fix: reuse the shipped primitive.** Every one of those calls goes through
`container.incomingImportCoordinator.boundedCalls` — the `BoundedCallGate` already on main
(W26/W27), on its private elastic `inboundBlockingLane()` (W29), following the shipped caller
pattern at `ImportActivity.kt:223-255` (W28). **Reuse, not re-derivation**: an independent gate
would carry an independent `MAX_ABANDONED_CALLS` budget, doubling the ceiling on parked provider
threads — the opposite of the guarantee.

**Import — `AnnotationsIoController.preview(uri, …)`:**

| Step | Bounded? | Notes |
|---|---|---|
| 0. Admission | — | `if (gate.abandonedCalls >= MAX_ABANDONED_CALLS) return Failed(Busy)`. Re-checked after step 1 — a concurrent activity may have exhausted the budget meanwhile (`ImportActivity.kt:243`). |
| 1. Metadata query (`OpenableColumns.SIZE` + `DISPLAY_NAME`) | **`gate.call`** | A cursor query is a provider call and parks like any other. No stream exists yet. |
| 2. Size preflight | pure | declared `> MAX_IMPORT_JSON_BYTES` → `TooLarge`, **never open**. Free-space is irrelevant (nothing is written). |
| 3. `openInputStream` | **`gate.call`**, `dispose = { it?.close() }` | **`dispose` is mandatory, not optional.** A stream produced after the deadline owns an fd with no other owner — that is an fd leak on an attacker-triggerable path. `onExpiry` additionally attempts a best-effort `close()`. |
| 4. Read + parse | **`gate.call`**, through `CountingGuardStream(stream, MAX_IMPORT_JSON_BYTES)` (W29) | `ImportSizeCapExceeded` → `TooLarge`. Covers absent sizes, **lying** sizes, and infinite streams. |
| 5. Close | `use`/`closeQuietly` | Close-once discipline — an attacker-supplied stream need not tolerate a second `close()` (`IncomingImportCoordinator.kt:296-299`). |

**Export — `AnnotationsIoController.export(uri, …)`:** identical treatment, and **both** of its
blocking calls are bounded independently. `openOutputStream` runs through `gate.call` with
`dispose = { it?.close() }`; the **write** runs through its own `gate.call`, because a destination
can accept the open promptly and then park mid-`write` — `OutputStream.write` is as synchronous and
uninterruptible as `read`. A `TimedOut` on either maps to a typed failure. Round 1 did not bound
the export path at all — a hostile provider could park the reader activity on a *save*, which is if
anything the easier attack to trigger (the user chose "Export"). **A-12 cases 4 and 5 are the proof
that both are bounded; without case 5 the write claim is assertion, not evidence.**

**What is guaranteed vs best-effort (stated separately — conflating them is what #155's round 3
flagged):**

- **Guaranteed — the caller always proceeds.** `gate.call` returns `TimedOut` at the deadline and
  the controller returns a typed `ImportFailure` unconditionally, whether or not the provider call
  ever finishes. The UI never wedges. The price is at most one parked thread per abandoned call,
  and `abandonedCalls` bounds how many can accumulate; it self-heals the moment a call returns
  (`IncomingImportCoordinator.kt:248-251`).
- **Best-effort — releasing the parked thread.** `onExpiry`'s `close()` reliably unblocks a
  provider-backed `ParcelFileDescriptor`/pipe, but not every stream shape (a regular-file fd can sit
  in an uninterruptible kernel read). **Correctness never depends on it.**

### 8.2 Value bounds

| Bound | Value | Rationale |
|---|---|---|
| `MAX_IMPORT_JSON_BYTES` | **2 MiB** | ≈ 10 000 richly-annotated rows with headroom; two orders of magnitude below #155's 512 MiB book cap, because this is text metadata, not a book |
| `MAX_IMPORT_ROWS` | **10 000** summed across kinds | over it → `TooManyRows`, whole-file refusal (a caps-hit file is structurally suspect, C-7 tier 1) |
| `MAX_FIELD_CHARS` | **10 000** per `selectedText` / `content` / `title` / `color` | over it → **row-level failure, never truncation**. Truncating silently mutates user content. |
| `MAX_LOCATOR_JSON_CHARS` | **4 096** | bounds the *nesting depth* of the inner `locatorJSON` string before it is handed to a second decode pass — a deeply-nested payload cannot reach the recursive decoder |
| `DEFAULT_IO_TIMEOUT_MILLIS` | **10 000 ms** | per bounded call, not per operation |

### 8.3 Per-row validation gate (all must hold; any failure → that row is `skipped`)

1. Every id parses as a `UUID` (C-10, W19).
2. `bookFingerprintKey` is syntactically a canonical key **and** equals the target book's key (C-1).
3. `locatorJSON.length ≤ MAX_LOCATOR_JSON_CHARS`, decodes as `Locator` via `BackupJson.decode`
   (R-3), and `locator.fingerprintKey == bookFingerprintKey` (R-3).
4. `locator.validate() == null` (C-9, W18).
5. Every text field within `MAX_FIELD_CHARS`.
6. `color` resolves through `AnnotationColor.from(...)`, falling back to `DEFAULT` — already the
   restore behaviour (`AnnotationsRepository.kt:175`).

Rows surviving this gate then go through §6.4's intra-file collapse and the already-present filter.

### 8.4 Provider-supplied display text is sanitized before it can reach a pixel

**Gate-2 round 1 (Medium).** Round 1 forbade echoing provider names in *error* messages but let
`ImportPreview.fileName` — read straight from `OpenableColumns.DISPLAY_NAME`, i.e. fully
attacker-controlled — reach the designed sheet header (`vreader-annotation-import.jsx:463-467`)
unbounded and unfiltered. A 50 000-character name, embedded `\n`/` `, or RLO/LRO bidi
overrides that reverse the surrounding UI are all reachable from a hostile provider.

**Fix: reuse `IncomingBookResolver.sanitizeDisplayName(raw, format = null)`** (W30) — public, on a
public class, already the repo's answer to this exact input. It gives, in one call: leaf-only
extraction (so `../../etc/passwd` becomes `passwd` and no traversal survives), a raw bound applied
*before* normalization, NFC, `Character.CONTROL` removal (NUL/CR/LF/TAB/DEL/NEL), the **enumerated
full `Bidi_Control` set** (deliberately enumerated rather than "strip category Cf",
`IncomingBookResolver.kt:253`), unpaired-surrogate removal, and a `MAX_NAME_CHARS = 200` cap that
never splits a surrogate pair. Null/blank/fully-stripped → `FALLBACK_NAME` (`"Untitled"`).

Sanitization happens in `AnnotationsIoController.preview`, at the boundary — **`ImportPreview`
carries only the sanitized value**, so no later code path can leak the raw one. Rebuilding any of
this locally would be re-deriving a solved problem with a worse Bidi story.

Tested (`AnnotationsImportReaderTest` + `AnnotationImportPreviewSheetTest`): a 50 000-char name,
embedded control characters, an RLO/LRO override pair, a lone surrogate, a `../../` traversal name,
a CJK name (must survive intact), an empty name, and a null cursor value.

### 8.5 What is explicitly forbidden in the implementation

- `inputStream.readBytes()` / `bufferedReader().readText()` on the picked URI — unbounded.
- A custom `Json { isLenient = true; allowSpecialFloatingPointValues = true }` — that reopens the
  NaN-progression canonicalization collision `Locator.repairedForCanonicalization()` exists to
  close (`Locator.kt:71-80`).
- Echoing the provider's display name or any file-system path into an error message — `ImportFailure`
  messages are fixed strings (rule 50 §6 "sanitizes paths and internal details").
- Any network access on either path.
- Writing anything to disk on the import path other than the Room transaction.
- **A bare `contentResolver.query` / `openInputStream` / `openOutputStream` anywhere in this
  feature** — every call site goes through the gate (§8.1). A grep for
  `contentResolver\.\(query\|openInputStream\|openOutputStream\)` inside
  `annotations/` must return hits **only** inside a `gate.call { … }` block; WI-7's audit checks this
  explicitly.
- **Constructing a second `BoundedCallGate`** — the injected instance is the single app-wide
  abandoned-call ledger.
- A `gate.call` that yields a `Closeable` **without a `dispose`** — that is the fd-leak shape
  `ImportActivity.kt:248-249` calls "MANDATORY".

---

## 9. Test plan

### 9.1 What could pass while wrong (per acceptance criterion)

Round-trip features false-green easily: "the file was written" and "no exception was thrown" both
pass with **zero annotations surviving**. For each criterion: the naive test that would go green on
a broken build, and the assertion that discriminates.

> **A-1 and A-2 are the EXPORT criteria.** Their *unit* assertions ship with WI-2 (the writer is
> testable without any UI). Their **end-to-end leg** — writing through a real SAF destination from
> a production entry point — is blocked with WI-8 on `needs-design` #2085, which is precisely why
> the export half is capped at `DONE` (§10). A-3…A-12 are unaffected.

| # | Acceptance criterion | A test that passes while broken | The discriminating assertion |
|---|---|---|---|
| A-1 | Export writes a valid `annotations.json` for the current book | `assertTrue(file.exists())` / `assertTrue(json.isNotEmpty())` — passes for `{}` and for `{"schemaVersion":3,"highlights":[],"bookmarks":[],"notes":[]}` on a book with 12 highlights | Decode the written bytes back into `BackupAnnotationsEnvelope` and assert **set equality of `(highlightId, locatorJSON, selectedText, color, note, createdAt, updatedAt)` tuples** against the repository's own rows. Counts alone are insufficient — a mapper that writes every row's `selectedText` as `""` keeps the count. |
| A-2 | The exported file is **contract-shaped** | round-tripping through our own encoder+decoder — passes even if we invented `highlight_id`. **And (Gate-2 round 1, Medium) a key-set-and-types check alone still passes an export that emits `schemaVersion = 1`, violating C-12** — the types match, the value is wrong, and a v1 file silently loses whatever v2/v3 added. | Two assertions, both required: (a) parse the export as a raw `JsonObject` and assert its **key set and value types equal** `contracts/vectors/backup-sections.json → sections.annotations` (via `BackupJson.canonicalElement`); **(b) assert `envelope.schemaVersion == BackupSchema.CURRENT_SCHEMA_VERSION` explicitly** (`== 3`, W31), as a distinct assertion so its failure names the version, not the shape. |
| A-3 | Import merges rows into the target book | `assertEquals(12, report.highlights.applied)` — passes if all 12 landed with a garbage locator, wrong color, or on the wrong book | Assert the **post-import repository snapshot equals the pre-export snapshot**, field by field including `id`, `createdAt`, `updatedAt` and the decoded `Locator`. |
| A-4 | Import is idempotent (C-11) | `assertEquals(0, second.highlights.applied)` — passes if the second run *deleted* everything and re-inserted nothing | Snapshot the whole table **before and after** run 2 and assert **deep equality**, plus `applied == 0` **and** total row count unchanged. |
| A-5 | Existing annotations are never overwritten (C-2) | importing a file with fresh UUIDs — nothing collides, so nothing proves the rule | Seed a row, then import a file with **the same UUID and different `selectedText`/`note`/`color`**; assert the stored row still has the **original** field values and `updatedAt`. |
| A-6 | Foreign-book rows are skipped, not applied (C-1/C-5a) | asserting no exception — passes if the whole import silently no-opped | Import a two-book file into book A; assert **A's rows applied**, `skipped ≥ B's row count`, **and B's table is still empty**, and that no `SQLiteConstraintException` was thrown. |
| A-7 | A hostile/malformed file is refused with nothing applied (C-7 tier 1) | `assertThrows(...)` — passes if the parser threw *after* writing half the rows | Assert the repository snapshot is **byte-identical before and after** the refused import, and that the failure is a typed `ImportFailure`, not a leaked `SerializationException`. |
| A-8 | Row-level invalid rows are skipped, valid siblings apply (C-7 tier 2, C-9, C-10) | count-only assertions | A file with 5 rows — 1 bad UUID, 1 negative `charOffsetUTF16`, 1 locator/book mismatch, 2 good — asserts `applied == 2`, `skipped == 3`, and **exactly the two good UUIDs** present. |
| A-9 | Import of a max-size file stays responsive | a JVM timing assertion | Measured **on the emulator** in WI-7's Gate-5 with a real book; the evidence file records the number. Ceiling: preview ≤ **2 s**, apply ≤ **1 s** for a 10 000-row file. (memory: *measure perf ON TARGET, not on a desktop JVM* — #139's §5 was 100× off.) |
| **A-10a** (WI-7) | The **Import** row is reachable by a real user | an instrumented test that composes `BookDetailsSheet` directly — this is exactly the #114/#118/#120/#122 hole | Gate-5b navigates from **app launch**: Library → tap book → reader → top-bar `⋯` → *Details* → ***Import annotations…***, in a **release-configured** build, and the evidence file names that path. |
| **A-10b** (WI-8 — **blocked on #2085**) | The **Export** row is reachable by a real user | asserting A-10a and calling the feature reachable — the export row does not exist yet, so nothing fails | The same app-launch navigation ending at ***Export annotations…***. **Cannot be run before #2085 lands**, which is exactly why the export half is capped at `DONE` and this criterion belongs to WI-8, not WI-7. Round 3 left A-10 demanding "both rows" during WI-7 — a criterion no honest WI-7 run could satisfy. |
| **A-11** | **The number the user approves is the number they get** (§6.4) | asserting `applied > 0`, or asserting the preview against itself | For the hostile-duplicate fixture (intra-kind dup ids, cross-kind dup ids, two same-position highlights, two same-position bookmarks, two same-position notes), assert **`preview.importable == report.applied.sum()`** — comparing the preview to the **real `RestoreAnnotationsReport` from a real in-memory Room apply**. Plus `preview.skipped ==` the exact count of collapsed rows, and the surviving row set equals the expected first-occurrence set. |
| **A-12** | **A hostile provider cannot wedge the reader** (§8.1) — on **both** directions | a test with a fake resolver that returns promptly — it never exercises the parked path at all. **And (Gate-2 round 3, Medium) round 2's "same three cases for `export`'s `openOutputStream`" left the write itself untested** — yet §8.1 names `OutputStream.write` as synchronous and uninterruptible, and bounding the export direction was this plan's own unprompted addition. Untested, it is the strongest claim with the least evidence. | **Five parked call sites, each its own case.** *Import*: (1) `query` blocks forever; (2) `openInputStream` blocks forever; (3) the returned stream's `read` blocks forever. *Export*: (4) `openOutputStream` blocks forever; (5) **`openOutputStream` returns promptly but the stream's `write` blocks forever** — the case a hostile destination triggers *after* the user committed to a save. For each: the controller **returns a typed failure within the timeout budget**, `gate.abandonedCalls` incremented, and — after the fake is released — the count returns to 0 (self-heal). Plus **late-result disposal** on both directions: the fake yields the stream *after* the deadline; assert `close()` was called on it (no fd leak). |

### 9.2 Test catalogue

**JVM unit (`android/app/src/test/kotlin/com/vreader/app/annotations/`)**

| File | Covers |
|---|---|
| `AnnotationBackupMapperTest.kt` | field-by-field wire mapping for all three kinds; deterministic sort; plain-`Locator` `locatorJSON` (W14, **not** `canonicalJson()`); nil-note omission (`explicitNulls=false`) |
| `AnnotationsExportWriterTest.kt` | A-1, A-2 (contract-vector key/type equality), C-12 (all three kinds), C-13 (empty envelope is valid), `suggestedFileName`: CJK title preserved, path separators + control chars stripped, `MAX_NAME_CHARS` cap, null/blank/all-stripped fallback, `.json` always |
| `AnnotationsImportReaderTest.kt` | the largest suite. Byte cap (declared-size lie **and** unknown size); row cap; field cap; locator-JSON cap; `NotJson`; `NotAnAnnotationsFile` (valid JSON, wrong shape); `UnsupportedSchema` (C-6, `schemaVersion` 0 / 4 / missing / non-integer, gated on `ACCEPTED_SCHEMA_VERSIONS`); `Empty`; UTF-8 BOM; UTF-16-encoded file; truncated mid-array; CJK `selectedText` survives byte-for-byte; every row-gate in §8.3 individually; **all five §6.4 intra-file collapse cases F-1…F-5, each asserted on the surviving row set (not just counts) and on file-order determinism**; the already-present filter against a populated `ExistingAnnotationState`; §8.4's eight display-name cases; preview counts and the ≤3 sample |
| `AnnotationsImportApplierTest.kt` | in-memory Room (`Room.inMemoryDatabaseBuilder`) with a **seeded parent `BookEntity`** (the #135 FK-unseeded-parent defect class): A-3, A-4, A-5, A-6, A-8, **A-11**; C-3 (same-position highlight different UUID → skipped); C-4 (duplicate note **is** created — the documented limitation, asserted so a future index change trips it); **C-5b both layers** — (i) parent deleted before `apply` → `BookMissing`, nothing written; (ii) an injected FK violation at transaction time → `BookMissing`, **zero rows applied** (the atomicity claim), never an escaping `SQLiteConstraintException` |
| `AnnotationsIoControllerTest.kt` | **A-12** — the hostile-provider suite, JVM, no emulator. **Five parked call sites**, one case each: import `query` / `openInputStream` / `InputStream.read`, export `openOutputStream` / **`OutputStream.write`**. Each asserts a typed failure within budget, `abandonedCalls` increments then self-heals, and the late-arriving stream is `close()`d. Plus `Busy` when the admission budget is exhausted. **The export cases are not symmetry decoration** — export is the direction the user explicitly initiated, so a park there is the easier attack and the one that most needs proof (§8.1). |
| `BackupCollectorTest` (existing) | must stay green unmodified — the WI-1 behaviour-preservation proof |

**Connected (`android/app/src/androidTest/kotlin/com/vreader/app/annotations/`)**

| File | Covers |
|---|---|
| `AnnotationImportPreviewSheetTest.kt` | render + click. Populated (chips show H/N/Skipped, sample rows, `Import N items` enabled); error variant (blob shown, primary disabled, tapping it does nothing); zero-importable (C-8); Cancel dismisses and applies nothing; CJK text renders |
| `AnnotationsIoEntryTest.kt` **(WI-6 — the pre-#2085 shape)** | the **Import** row renders, carries `details-import-annotations`, invokes its callback; **B1's merge-policy footnote renders** (§3.3 A-4, tag `details-annotations-footnote`); and the absence assertions — **`assertDoesNotExist` on `details-export-annotations`**, no sub-line under the Import row (A-2 of §3.3), Share row unchanged. **The "no export row" assertion is load-bearing, not filler**: it is the only mechanical thing that pins the #2085-blocked surface as genuinely absent, so a stray re-add during WI-7 wiring goes RED instead of quietly shipping undesigned UI. |
| `AnnotationsIoEntryTest.kt` **(WI-8 — after #2085)** | the assertion set **flips**: the Export row renders, carries `details-export-annotations`, invokes its callback, has no sub-line (A-1 of §3.3), and sits **above** Import per `vreader-annotation-import.jsx:317-325`; the `assertDoesNotExist` above is deleted in the same commit that adds the row — never left behind to be `@Ignore`d. |
| `AnnotationsRoundTripConnectedTest.kt` | **WI-7 (import leg)**: seed a fixture `annotations.json` on the device → import it through the production path → wipe → re-import → assert the snapshot equals the original and the second run applies 0. The **export→import** round trip needs a user-reachable export, so that variant lands with **WI-8** (blocked on #2085). Writing it against a *file the test wrote itself* would be a round trip that never touches the export entry point — the false-green this table exists to prevent. |

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
| **WI-3** | foundational | `AnnotationImportModels` + `AnnotationsImportReader`: every bound in §8.2, every row gate in §8.3, **all five §6.4 intra-file collapse rules**, the already-present filter, the whole failure taxonomy. Pure JVM — no `ContentResolver`, no Android. | **L** (largest test surface) | none |
| **WI-4** | foundational | `AnnotationsImportApplier` over `restoreAnnotations`: `existingState`, C-5b's two layers, A-11's `preview.importable == applied` invariant; in-memory-Room merge tests | M | none |
| **WI-4b** | foundational | **`AnnotationsIoController` — the whole blocking-call boundary** (§8.1): a bounded `gate.call` around **each of the five** blocking sites (import `query` / `openInputStream` / `read`; export `openOutputStream` / `write`), mandatory `dispose`, admission checks, §8.4 name sanitization, and A-12's five-case hostile-provider suite. **Ships in full even though the export UI is #2085-blocked** — the export path is foundational code with unit coverage, and leaving it unbounded "until the row lands" would be the exact deferral that produces an unbounded call the day the row *does* land. | **M–L** | none (JVM fakes reach the parked path; the emulator cannot) |
| **WI-5** | behavioral | `AnnotationImportPreviewSheet` (+ `…Content` split) exactly as designed, incl. the error + zero-importable states | M | slice: connected render/click on the emulator |
| **WI-6** | behavioral | The **Import** `ActionList` row **+ B1's merge-policy footnote**; threading through `BookDetailsSheet` / `ReaderChromeScaffold` / `EpubReaderChrome`; rule-22 KDoc repairs (incl. W15). **The Export row is `BLOCKED: needs-design (#2085)` and is NOT built** — the capability-gate (D-9) means passing a null `onExportAnnotations` renders no row, so the block costs one null argument, not a code branch. | M | slice: Import row + footnote visible, row tappable via **⋯ More → Details** on a real book |
| **WI-7** | behavioral, **final for the import half** | The **import** SAF launcher in the 4 reader activities + `VReaderApp` wiring (injecting the **existing** gate); the connected import round-trip; the audit grep from §8.5 (no bare resolver call in `annotations/`); the test-hardening pass for any RED-when-run connected test from WI-5/6. **The export result wiring is `BLOCKED: needs-design (#2085)` → WI-8.** | M | **acceptance for the import half**: **A-10a** + A-3…A-9, A-11, A-12, real EPUB + real CJK TXT, release-configured build, production path named in the evidence file. **A-1/A-2 end-to-end and A-10b belong to WI-8** — WI-7 is not "final" for the feature. |
| **WI-8** | behavioral | **BLOCKED: `needs-design` (#2085).** The Export row + export result wiring, once the design lands. Flips `AnnotationsIoEntryTest`'s assertion set (deleting the `assertDoesNotExist`, adding the row assertions — same commit, never an `@Ignore`), and unblocks **A-10b** and A-1/A-2's end-to-end leg plus the real export→import round trip. | S | full export acceptance: **A-10b**, A-1/A-2 end-to-end, and the real round-trip |

Rationale for the split: WI-1…WI-4b are pure JVM and need no emulator, so they can be gated fast and
audited independently. Three boundaries, three WIs, each auditable alone: **parse** (untrusted bytes,
WI-3), **persist** (Room + FK, WI-4), and **call** (blocking provider I/O, WI-4b). Round 1 folded the
third into WI-7's wiring, which is precisely how its liveness hole stayed invisible — a security
boundary buried in an activity-wiring WI gets reviewed as wiring. WI-4b makes it a first-class,
independently-audited unit with its own hostile-provider suite, and shrinks WI-7 back to wiring.
WI-5/6 are the two designed surfaces.

**Dependencies:** WI-2 → WI-1; WI-4 → WI-3; WI-4b → WI-3, WI-4; WI-5 → WI-3; WI-6 → (nothing hard,
but ships after WI-5 so the row it launches has a destination); WI-7 → WI-2, WI-4b, WI-5, WI-6;
**WI-8 → `needs-design` #2085 (design blocker) + WI-7**.
No dependency on any other feature row. The tracker records #165 as disjoint from #164. **#165 must
not run in a lane concurrent with any #155 lane that writes `imports/`** — #165 only reads it, but a
concurrent refactor there would break #165's call sites mid-flight. **This is the constraint the
orchestrator is most likely to trip over, because the orchestrator is the one who dispatches both.**

### What the #2085 block does and does not stop

| | Status |
|---|---|
| WI-1, WI-2 (export writer), WI-4b's export path | **ship** — foundational, fully tested on the JVM, no UI |
| WI-3, WI-4, WI-4b, WI-5, WI-6, WI-7 (import) | **ship** — the import half is fully designed |
| The `Export annotations…` row + export result wiring | **blocked** (WI-8) |
| Feature row status | reaches `DONE` for the import half; **cannot reach `VERIFIED` until WI-8 lands** (rule 47 Gate 5 "capped at `DONE`" — the export acceptance criteria A-1/A-2 have no production entry point until then) |

**Deliberate consequence, stated rather than hidden:** WI-2 ships an `AnnotationsExportWriter`
with **no production call site** until WI-8. That is the orphan-surface shape
`scripts/check-orphan-surfaces.sh` detects (it flags composables, so a plain class will not trip
it — which is exactly why it is written down here instead). It is accepted because the alternative
is either inventing #2085's surface or stalling the whole feature over one notification. **The
tracker row must carry `BLOCKED: needs-design (#2085)` against WI-8** — an orchestrator-owned
edit; this plan proposes the exact text and does not make it.

---

## 11. Risks, backward compat, known limitations, open questions

### Risks + mitigations

| # | Risk | Mitigation |
|---|---|---|
| R-1 | Extracting `BackupCollector`'s mappers silently changes the backup wire bytes | WI-1 is behaviour-preserving-by-construction (lift, don't rewrite) and the collector's existing byte-stability tests run **unmodified** as the proof. |
| R-2 | Export diverges from the contract → an iOS-written archive stops importing | A-2 asserts against `contracts/vectors/backup-sections.json` directly, not against our own round-trip. (memory: *verify cross-platform contract fields against iOS + the vectors + the real decoder, not just the Gate-2 plan* — #132's `locatorJSON` = plain, not canonical.) |
| R-3 | A hostile **provider** parks the reader activity — not just a hostile *file* | §8.1: every `ContentResolver` call (query, open, transfer, **both directions**) goes through the shipped `BoundedCallGate` with mandatory late-result disposal; A-12 proves it with a fake that parks in each of the **five** call sites — including `OutputStream.write`, the one round 2 bounded but did not test. Honest caveat preserved: caller-liveness is **guaranteed**, unparking the thread is **best-effort**. |
| **R-3b** | The team re-derives a bounding mechanism instead of reusing the shipped one, ending up with two abandoned-call budgets (double the parked-thread ceiling) | §5.1 injects the gate; §8.5 forbids constructing a second one; WI-4b's audit checks the injection site. |
| **R-3c** | A future edit adds a bare `contentResolver` call to `annotations/` and quietly reopens the hole | §8.5's grep is an explicit WI-7 audit step, and `AnnotationsImportReader` is deliberately **pure** so there is no Android surface there to regress. |
| R-4 | Four reader activities × two launchers = copy-paste drift | All logic in `AnnotationsIoController`; the activities hold only the two `rememberLauncherForActivityResult` registrations. |
| R-5 | Connected tests written in WI-5/6 are RED when first actually run | Budgeted explicitly in WI-7 (§9.2 note) — a recurrence in both #133 and #135. |
| R-6 | Stale comments (W15) mislead the next implementer into using `canonicalJson()` for the wire | Fixed in WI-6's rule-22 pass — `Annotation.kt:8-9`, `Entities.kt:112`, `:120-121`. Comment-only, no behaviour change. **Not** filed as a bug row (tracker writes are orchestrator-owned); flagged as Q-5. |
| R-7 | An `application/json` MIME filter hides legitimate files (some providers report `text/plain` or `application/octet-stream`) | The picker passes `arrayOf("application/json", "*/*")` so nothing is unreachable; content validation is the real gate (D-4). |
| R-8 | Emulator contention wedges the connected run | Rule 52 Cause D: never drive the emulator during an in-flight connected run; cold-boot before gesture-ish tests; `adb kill-server/start-server` if stale `getprop` procs congest adbd. |
| **R-9** | The preview promises N and the apply delivers fewer — the user silently loses annotations they approved | §6.4's collapse makes the two equal by construction; **A-11 asserts it against a real Room apply** on the hostile-duplicate fixture. Residual TOCTOU is bounded and stated: the report is authoritative, the merged list is what the user sees. |
| **R-10** | A concurrent #155 lane refactors `imports/` and breaks #165's call sites | `imports/` is read-only for #165 (§5.3) and §10 forbids concurrent lanes over it. The relocation of the shared primitives is deferred to Q-6, after both features settle. |

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
  different UUID creates a duplicate note (C-4), and two such notes inside one file both land
  (§6.4 F-5). Highlights and bookmarks do not have this behaviour. Consequence for copy: B1's
  designed footnote says "merge … **by passage match**", which is exact for highlights and bookmarks
  (`profileKey` is a position hash) and approximate for notes. The footnote ships verbatim (§3.3
  A-4) — rewriting committed design copy to match an implementation detail would be the
  self-designed-UI move rule 51 forbids; the nuance is recorded here instead.
- **K-2** — No iOS-#35 file interop in either direction (D-8). Tracked as **feature #173 / GH #2082**
  (orchestrator ruling, Gate-2 round 1) — a filed follow-up, not an untracked gap.
- **K-3** — Import is per-book. A library-wide annotations file must be imported once per book.
- **K-4** — Export offers one format. The design's "Markdown · JSON · VReader JSON" subtitle is not
  shipped (§3.3 A-1).
- **K-6** — **The export half does not ship in the first pass.** `needs-design` #2085 blocks the
  `Export annotations…` row and its result wiring (WI-8). Until it lands: the export writer exists
  and is tested but is not user-reachable, the feature row is capped at `DONE`, and the only way to
  produce an importable file is a WebDAV backup archive's `annotations.json`. Not a deferral — a
  filed, labelled, open blocker with a WI attached.
- **K-5** — The imported row's `anchor` is null (inherited from `restoreAnnotations`,
  `AnnotationsRepository.kt:177`), so a highlight re-anchors by locator rather than by its precise
  engine anchor. Identical to the behaviour a WebDAV restore already has.

### Open questions — status after Gate-2 round 1

- **Q-1 — RESOLVED by the orchestrator.** iOS↔Android **file** interop (D-8) is **out of scope for
  #165**; the convergence work is filed as **feature #173 / GH #2082**. #165 exports the versioned
  contract shape. D-8's analysis stands as the *reason*, and K-2 records the resulting limitation.
- **Q-2 (open).** Is exporting **bookmarks** alongside highlights and notes correct (C-12)? The
  row's title says "annotations"; the envelope has three kinds and #135 ships bookmarks. This plan
  says yes (omitting them makes export lossy relative to restore). Cheap to reverse if the answer
  is no.
- **Q-3a — RESOLVED.** §3.4's choice of **B1** (Book Details Actions rows) over the import bundle's
  canonical **A1 + C1** was **not challenged in Gate-2 round 1 and stands**. Round 2 additionally
  builds B1's merge-policy footnote (§3.3 A-4), so B1 now ships complete rather than partially
  cited.
- **Q-3b — RESOLVED by filing.** The orchestrator's round-2 ruling was *reuse a shipped designed
  string verbatim, or file — no third option.* Reuse was checked against `MainActivity.kt:59-64`
  and **fails** (all three shipped strings describe import; `"Couldn't open the file"` is false for
  a write failure). **`needs-design` #2085 filed 2026-08-05, verified open**; WI-8 carries the
  block. Round 2's `Toast` answer is **withdrawn** — an OS-rendered widget carrying app-authored
  copy is still an invented notification, and calling it "system chrome" was the move rule 51's
  anti-pattern table names ("it's a small dialog, an Apple HIG default works fine"). Details in
  §7 D-10 / D-10a / D-10b.
  Still worth a second opinion: §3.3's three remaining absences (A-1/A-2/A-3).
- **Q-4 (pre-existing, out of scope but should be tracked).** W12: `BackupRestoreScreen` — the whole
  WebDAV backup/restore UI — has **no production call site**; its only host is
  `android/app/src/debug/.../BackupDebugActivity.kt:27`. That is the #114 reachability class still
  open. #165 does not fix it and does not depend on it, but a reader of this plan should not infer
  that backup/restore is user-reachable today.
- **Q-5 (housekeeping).** W15's stale KDoc contradiction (`Annotation.kt:8-9` and `Entities.kt:112`
  claim the backup collector converts `locatorJSON` to `canonicalJson()`; `BackupCollector.kt:186-188`
  does the opposite). This plan repairs the comments in WI-6 under rule 22. Should it also get a bug
  row (the bug-#362 "KDoc contradiction" precedent)? Orchestrator's call.
- **Q-6 (new, follow-up — not this feature).** `BoundedCallGate`, `CountingGuardStream` and
  `IncomingBookResolver.sanitizeDisplayName` are general I/O-hardening primitives that now have a
  second consumer outside `com.vreader.app.imports`. #165 calls them **in place** to keep its
  write-set disjoint from #155 (§5.1, R-10). Once both features settle, relocating them to a neutral
  `com.vreader.app.io` package would remove the cross-feature import (rule 00) — worth a chore row,
  but doing it *inside* #165 would collide with #155's files for zero behavioural gain.

---

## 12. Revision history

| Rev | Date | Change |
|---|---|---|
| **v5** | **2026-08-05** | **Gate-2 final round — the last un-carved location.** §5.2's Modified table still carried pre-#2085 export UI/plumbing instructions. Rewritten with a **WI column** and a uniform rule ("an edit that makes the export row or its result reachable is WI-8; everything else is WI-6/WI-7"): `BookDetailsRows` splits into an Import-row row (WI-6) and an Export-row row (WI-8); `BookDetailsSheet` likewise, and **its "NO Export" KDoc invariant is now kept standing at WI-6** — round 3's "no longer holds" was true only of a plan that shipped the export row, so the wording is merely re-attributed to #2085 and retired at WI-8; both chrome hosts take `onImportAnnotations` at WI-6/WI-7 and `onExportAnnotations` at WI-8; the four reader activities register `OpenDocument()` at WI-7 and `CreateDocument()` at WI-8. `VReaderApp.kt` keeps **both** lazies at WI-7 (the controller takes the writer as a constructor param and is constructed there; `export()` stays unreachable until WI-8), consistent with WI-4b shipping the bounded export path in full. Nothing else touched. |
| **v4** | **2026-08-05** | **Gate-2 round 4 — consistency pass, scoped to the four findings that were downstream of round 3's WI-8 carve-out.** Round 3 correctly filed #2085 late in the cycle and left lines elsewhere still assuming a shippable Export surface. **H1 (§1 scope line):** rewritten to state the two halves ship on different schedules — import production-reachable now, export foundation-only — with the blunt consequence spelled out at the top ("a user can import a file but cannot produce one from the app"), not buried in §10. **H2 (A-10):** split into **A-10a** (Import-row reachability, WI-7) and **A-10b** (Export-row reachability, WI-8, blocked) — round 3's A-10 demanded "both rows" during WI-7, a criterion no honest run could satisfy. **M1 (`AnnotationsIoEntryTest`):** split into a WI-6 shape (Import row + footnote + **`assertDoesNotExist` on the export tag**) and a WI-8 shape that flips the assertions in the same commit that adds the row; the negative assertion is recorded as load-bearing — it is what mechanically pins the blocked surface as absent. **M2 (A-12):** now **five** parked call sites, adding **`OutputStream.write` blocks forever** (open succeeds, write parks) — the case that actually proves round 2's self-initiated export bounding; §8.1's export paragraph, R-3 and WI-4b updated to five. Rounds 2 and 3 otherwise untouched. |
| **v3** | **2026-08-05** | **Q-3b folded in (orchestrator's round-2 ruling: reuse verbatim or file, no third option).** Reuse checked against the complete shipped failure copy (`MainActivity.kt:59-64`) — all three strings describe *import*, and `"Couldn't open the file"` is factually wrong for a write failure, so **nothing fits**. #2030 covers book-**import** feedback for #155, a different operation, so it does not absorb the ask. **Filed `needs-design` #2085** ("Android annotations-export result feedback for feature #165", `enhancement` + `needs-design`, three required failure states, line-cited chrome), verified open. **D-10 rewritten** — round 2's `Toast` answer is withdrawn as an invented notification wearing system-chrome clothing; **D-10a** records that silent success needs no design (#155 precedent); **D-10b** records that import failure is fully covered by the committed `ImportPreviewSheet` error state. **§3 verdict split**: import PROCEEDS, export BLOCKED. **§3.3 gains A-5** and the absence-vs-gap line ("omitting a decorative sub-line whose data does not exist is an absence; omitting a required state is a design gap"). **§10 gains WI-8** (blocked) and a table of exactly what the block does and does not stop, incl. the accepted orphan `AnnotationsExportWriter` and the `BLOCKED: needs-design (#2085)` row text the orchestrator must apply. New **K-6**. Nothing else reopened. |
| v1 | 2026-08-05 | Gate-1 draft. |
| **v2** | **2026-08-05** | **Gate-2 round 1 (Codex gpt-5.5/high) — 2 High, 4 Medium, 2 Low, all addressed.** **H1 (SAF liveness — #155's defect repeated while citing #155):** §8.1 rewritten — every `ContentResolver` call on **both** the import and export paths now runs through the **shipped** `BoundedCallGate` (W26–W29) with admission checks, mandatory late-result `dispose`, and the guaranteed-vs-best-effort split stated separately; new **WI-4b** makes this an independently-audited boundary instead of activity wiring; new **A-12** hostile-provider suite; new **D-6**, R-3/R-3b/R-3c, §8.5 prohibitions incl. an audit grep. **H2 (intra-file collisions):** new **§6.4** — five collapse rules (F-1…F-5) with a fixed, deterministic order, a cross-kind global id set restoring iOS semantics, the already-present filter, and the asserted invariant `preview.importable == applied` (new **A-11**); new D-11/D-12; `AnnotationsImportReader` signature gains `ExistingAnnotationState`. **M1:** new **C-5b** (target book absent/stale) with a two-layer fix and an explicit check-then-act caveat. **M2:** new **§8.4** — `ImportPreview.fileName` sanitized via `IncomingBookResolver.sanitizeDisplayName` (W30), 8 test cases. **M3:** B1's merge-policy footnote is now **built**, not just cited (§3.3 A-4 rejects it as an absence); K-1 records the notes-vs-"passage match" copy nuance. **M4:** A-2 gains an explicit `schemaVersion == CURRENT_SCHEMA_VERSION` assertion; C-6 now gates on the shipped `BackupSchema.ACCEPTED_SCHEMA_VERSIONS` (W31) instead of a hand-rolled range. **L1/L2:** citation fixes — `RestoreImporter.kt:119` is the seam (`:105` is the wrapper call); W12 restated as "no `main`/release call site" with the `androidTest`-excluding grep shown. Orchestrator rulings recorded: Q-1 resolved (interop → feature #173 / GH #2082), Q-3a resolved (B1 stands). New Q-6. |
