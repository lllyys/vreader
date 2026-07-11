# Feature #135 — Android reader bookmarks: create / toggle / list / jump (parity box F, split from #132)

**Numbering:** box F = #132 (chrome shell + TOC/Contents + annotations-review sheet + annotation/bookmark backup wiring), **#135 (this — bookmark create/toggle/list/jump + the four hard problems #132 deferred)**, #133 (find-in-book), #134 (More menu + book details + share). Box F checks `[x]` only when #132 + #133 + #134 + #135 are all VERIFIED. Box B (`docs/parity/android-checklist.md`, row `[~]`) checks `[x]` only when **both** #132's annotations-review sheet **and** #135's bookmark create/list are VERIFIED — #135 clears the bookmark half of box B.

**Deps token (rule 55):** `Deps:[feat:#132]` — #132 ships (a) `ReaderChromeScaffold` + `ReaderTopChrome` with the **nullable `bookmarkSlot`** the top-bar toggle fills, (b) the `AnnotationsReviewSheet` + `All/Highlights/Notes` filter chips that #135 extends with a `Bookmarks` chip + `BookmarkCard`, (c) the single-pane `TocContentsSheet` #135 promotes to the two-tab `TOCSheet`, and (d) the FULL `annotations.json` collect+restore round-trip (highlights + notes + **bookmarks list already wired**). Transitively #129 (the `ReaderBottomChrome` slot #132 extends). **The ONLY semantic feature dependency is #132**; #135 has NO dependency on #128/#131 (its migration is self-contained — a single unique index on an existing table).

**§write-set-serialization (integration ordering, NOT a feature-dependency order):**
- **`AnnotationDao`:** #132 adds `allNotes()`/`allBookmarks()` (collector) + the restore-seam insert paths; #135 adds the atomic **toggle** transaction + `insertBookmarkIfAbsent` / `deleteBookmarkByProfile` / `findBookmarkByProfile` + `isBookmarked`. One-writer-per-file (rule 48): #135's DAO WI lands AFTER #132's DAO members merge, then re-audits on the rebased baseline. All additions are new members (no existing-signature changes) → the later-landing feature keeps the earlier valid by construction.
- **`ReaderChromeScaffold.kt` / `ReaderTopChrome.kt`:** #132 ships these with a nullable `bookmarkSlot`. #135 fills the slot + appends a `ReaderSheet.Bookmarks` route + bookmark-list params as further nullable-default slots. Single-writer → #135's chrome WI rebases onto #132's merged baseline.
- **Migration number allocated at #135's integration slot** against the THEN-current `version` in `VReaderDatabase.kt` (version-at-slot, rule 40). **Do NOT pre-assign.** Base = "current main's schema version + 1" (main is v5 today; if #128/#131 land first, the number floats up).

**Design authority (rule 51):** `vreader-reader.jsx` (`ReaderTopChrome` bookmark toggle — `bookmarked` state, `onToggleBookmark`, `Icons.BookmarkFilled`/`Icons.Bookmark`), `vreader-panels.jsx` (`TOCSheet` **Bookmarks tab**: bookmark icon · italic serif preview · `chapter · p.N · date` · chevron), `vreader-android-annotations.jsx` (`BookmarkCard` + the `Bookmarks` filter chip). Every surface built below is depicted. **Bookmark row DELETION is undesigned on Android (GH #1903 needs-design) — #135 ships create/toggle/jump/list WITHOUT list-deletion.**

**Status:** Gate-1 v1 (2026-07-11). Gate-2 Codex audit pending.

## 1. Problem

#132 shipped the reader chrome shell, the Contents (TOC) sheet, the annotations-review sheet (highlights + notes), and the full `annotations.json` backup round-trip — but **deliberately deferred every bookmark-creation and bookmark-jump capability** because they carry box F's hardest, most coupled problems. Post-#132 a reader can review highlights/notes and browse chapters but **cannot create, toggle, list, or jump to a bookmark** from any host; the top-bar toggle renders omitted (a nullable slot passed null), the `TOCSheet` is single-pane, and the review sheet has `All/Highlights/Notes` chips only.

**Verified persistence + navigation facts:**
- **Bookmark persistence exists (no create/list UI, non-idempotent create):** `AnnotationDao` (`data/Daos.kt`) has `observeBookmarks(bookKey)` / `bookmarksForBook(bookKey)` / `upsertBookmark` (`@Upsert`, UUID-keyed) / `deleteBookmark(id)`. `AnnotationsRepository` exposes `bookmarks(bookKey)` + `addBookmark(bookKey, title, locator)` + `removeBookmark(id)`. **`addBookmark` mints a NEW UUID (`newAnnotationId()`) every call** and `upsertBookmark` is `@Upsert` keyed on `bookmarkId` → two adds at the same position produce two rows. **No presence read** ("is the current position bookmarked?") and **no toggle**.
- **`BookmarkEntity` already carries a `profileKey` column** (`"$bookKey:${sha256(locator.canonicalJson())}"` via `profileKeyFor`) but only a **non-unique** `Index("bookKey")`. No uniqueness on position — the toggle-atomicity + dedupe target. The **highlights table** is the precedent (`upsertHighlight`: transactional insert-if-absent on a unique `(profileKey, anchorKey)`).
- **`BookmarkRecord` holds only `id / bookKey / title? / locator: Locator / createdAt / updatedAt`** — no preview/chapter/page for TXT/PDF (must derive per format).
- **`Locator` is the canonical engine-neutral position**; `canonicalJson()` is the equality basis. A persisted bookmark's `locatorJSON` is a plain round-trippable `Locator` (via `BookmarkRecord.toEntity()`), NOT a `VReaderLocator` envelope — so it holds **no precise Readium locator JSON**.
- **`ReadiumLocatorBridge` is FORWARD-ONLY** (Readium JSON → vreader envelope + canonical fallback); Readium-free (pure-JVM); has NO `toReadium(canonical, publication)`. `ReaderActivity` restores a *position* via the precise `readiumLocatorJSON` in the envelope → `Locator.fromJSON(precise)` → `navigator.go`. A bookmark has no precise JSON → jumping to it after reopen/restore requires **canonical → Readium reconstruction** (Problem 1).
- **AZW3/foliate `goTo` is fire-and-forget with no result:** `FoliateBridge` exposes only `init*/next/prev`, each `evaluateJavascript(js, null)` in a swallowed try/catch; `Azw3Document` applies CFI/fraction only at `restoreOrInit()`; no in-session goTo, no pending-goTo re-issue after `onRenderProcessGone`. The bundle DOES dispatch a `relocate` event (`FoliateMessage.Relocate`) — the ack channel an awaited goTo keys on (Problem 2). Security (#126): `WebViewCompat.addWebMessageListener` allow-listed to the shell origin + `WebViewAssetLoader`; NEVER `addJavascriptInterface`.
- **DB is v5** — the unique-index migration is #135's ONLY schema change (Problem 3).
- **Backup already covers bookmarks (#135 needs NO backup change):** #132 wired `BackupCollector` to emit `annotations.json = BackupAnnotationsEnvelope(schemaVersion, highlights, bookmarks, notes)` with `bookmarks` from `allBookmarks()` + `locatorJSON = canonicalJson()`, and `RestoreImporter` decodes it through the UUID-preserving `restoreAnnotations(env, allowedBookKeys)` seam (bookmark = insert-if-absent by UUID, with a profile-key/position fallback "once #135 adds the `(bookKey, profileKey)` unique index" — that index IS Problem 3). `BackupAnnotationsEnvelope` pre-exists in `contracts/backup/BackupSections.kt` → NO `contracts/` change, NO ADR gate.

**Design inventory — exactly what #135 builds (all depicted):**
- **Top-bar bookmark toggle** (`ReaderTopChrome`): a filled/empty bookmark icon reflecting "is the current position bookmarked?", tapping toggles create/remove. Fills #132's nullable `bookmarkSlot`.
- **`TOCSheet` Bookmarks tab** (`vreader-panels.jsx`): bookmark rows (icon · italic preview · `chapter · p.N · date` · chevron) → tap jumps + dismisses. Promotes #132's single-pane Contents sheet to two-tab.
- **Review-sheet `Bookmarks` filter chip + `BookmarkCard`** (`vreader-android-annotations.jsx`): the chip narrows to bookmarks; `BookmarkCard` = filled icon · serif label · sans meta; tap-to-jump on the card body (capability-gated per host, as #132's `onJumpToAnnotation` established).

**Not depicted / GATED (rule 51):**
- **Bookmark row DELETION** (from list/card) — undesigned (no delete affordance on `TOCSheet` bookmark row or `BookmarkCard`; GH #1903). #135 ships create/toggle/jump/list WITHOUT list-deletion. NOTE: the top-bar toggle's *un-bookmark* (toggle-off at the current position) IS depicted + built (`onToggleBookmark` flips filled→empty) — that's toggle, not list-deletion.
- **Bookmark rename/edit UI** — schema has `title` but no editor drawn; out.

**iOS parity:** `BookmarkListViewModel.swift`, the iOS reader top-bar bookmark toggle, the two-tab TOC sheet.

## 2. Surface area

### New — bookmark locator reconstruction (`reader/` — Problem 1)
- **`reader/ReadiumLocatorReconstructor.kt`** (NEW; kept OUT of the pure-JVM `ReadiumLocatorBridge` so the bridge stays Readium-free): `class ReadiumLocatorReconstructor(publication: Publication)` with `fun toReadium(canonical: Locator): org.readium.r2.shared.publication.Locator?`. Resolves the canonical `href` against the publication (`publication.linkWithHref(href)` → resolved `Link` + its `mediaType`), then builds a Readium `Locator` from that link + canonical `progression`/`cfi`/`textQuote`/`textContext` (Readium `Locator.Locations(progression=…, fragments=cfi?)` + `Locator.Text(highlight=textQuote, …)`). Returns **null** when the href can't be resolved (missing/renamed resource) or the canonical locator is structurally invalid → caller degrades. Precedence: prefer a `publication.locations`-refined position; else raw progression-only. Robolectric-tested against a fixture publication.

### New — awaited AZW3 goTo bridge (`reader/foliate/` — Problem 2)
- **`reader/foliate/FoliateBridge.kt`** (MODIFY): `suspend fun goTo(target): Azw3GoToResult` that (a) mints a request id, (b) evaluates JS calling `readerAPI.goTo(...)`/`goToFraction(...)` **and posts back `{name:'goto-ack', id, ok, cfi?, fraction?}` AFTER the bundle relocate settles** (the bundle patch returns `view.goTo`'s promise + posts the ack on resolve/reject — routed through the SAME `addWebMessageListener` `vreaderHost` allow-listed to the shell origin, JSON-escaped via `jsString`, NEVER `addJavascriptInterface`), (c) suspends on a `CompletableDeferred` keyed by id, resolved when the matching `goto-ack` arrives (a new `FoliateMessage.GoToAck`). **Timeout** (`withTimeoutOrNull` ~3s) → `Timeout`. **Cancellation** (superseding goTo) → complete-cancelled + remove entry. **Render-death:** on `onRenderProcessGone` mid-goTo, recreate WebView + `Azw3Document`, re-issue the goTo ONCE after book-ready (a pending-goTo field applied like `restoreOrInit`).
- **`reader/foliate/FoliateMessage.kt`** (MODIFY): `data class GoToAck(id, ok, cfi?, fraction?)`.
- **`reader/foliate/FoliateMessageParser.kt`** (MODIFY): parse `goto-ack` → `GoToAck`.
- **`reader/foliate/Azw3Document.kt`** (MODIFY): `suspend fun goTo(canonical: Locator): Azw3GoToResult` — derives the foliate target (**CFI first when present, else fraction from `progression`**), calls the bridge's awaited goTo, derives the reached position from the ack; holds the pending target for render-death re-issue.
- **Bundle patch** (the foliate-js `readerAPI` shim): `goTo`/`goToFraction` return `view.goTo(...)`'s promise + post `goto-ack`. Depicted-behavior-only, no UI.

### New/modified — atomic toggle + presence + unique-index migration (Problem 3)
- **`data/Daos.kt` (`AnnotationDao`)** (MODIFY): `insertBookmarkIfAbsent(b): Long` (`@Insert(onConflict=IGNORE)`); `findBookmarkByProfile(bookKey, profileKey)`; `deleteBookmarkByProfile(bookKey, profileKey): Int`; `@Transaction toggleBookmark(entity): BookmarkToggleResult` (insert-if-absent by the `(bookKey, profileKey)` unique index; if ignored → DELETE by profile → `Removed`; else `Added`); `isBookmarked(bookKey, profileKey): Int` (presence for the top-bar toggle). Keep existing `upsertBookmark`/`deleteBookmark(id)` (restore/id-keyed callers).
- **`annotations/AnnotationsRepository.kt`** (MODIFY): `toggleBookmark(bookKey, title, locator): BookmarkToggleResult` (requireSameBook; entity via `BookmarkRecord.toEntity()` which computes `profileKey`; delegate to the DAO transaction) + `isBookmarked(bookKey, locator): Boolean`.
- **`data/VReaderDatabase.kt`** (MODIFY): `MIGRATION_N_(N+1)` at the integration slot (N = then-current version): (1) **dedupe existing duplicates BEFORE the unique index** — delete losers per `(bookKey, profileKey)` keeping the winner by `updatedAt DESC, createdAt DESC, bookmarkId ASC`; (2) `CREATE UNIQUE INDEX index_bookmarks_bookKey_profileKey ON bookmarks (bookKey, profileKey)`. Add the entity index (`BookmarkEntity` gains `Index(["bookKey","profileKey"], unique=true)`, keep `Index("bookKey")`). Bump `version`, append `ALL_MIGRATIONS`, regenerate the exported schema. DDL matches Room's generated schema (migration test PRAGMA-validates).
- **`data/Entities.kt`** (MODIFY): add the composite unique index to `BookmarkEntity.indices`.

### New — per-format bookmark row presentation (Problem 4)
- **`reader/nav/BookmarkPresentation.kt`** (NEW): pure `fun bookmarkRow(record, format, tocEntries?, previewProvider?): BookmarkRowUi(preview?, chapter?, pageLabel?, dateLabel)`:
  - **EPUB:** chapter + page-position via a TOC lookup (nearest `TocEntry` at/above the bookmark, reusing #132's `TocEntry`); preview = the bookmark `title` (chapter-derived), no arbitrary EPUB body extraction.
  - **PDF:** `pageLabel = "p. ${locator.page?.plus(1)}"`, no chapter/preview.
  - **TXT/MD:** preview = a bounded snippet around `locator.charOffsetUTF16` (via a `BookmarkPreviewProvider` the TXT host supplies), clamped ≤120 chars single-line ellipsized; no chapter/page.
  - **date:** locale/timezone-stable relative label; deterministic for tests.
  - **No-preview / no-chapter hosts degrade gracefully** (null fields, never a crash).
- **`reader/nav/BookmarkPreviewProvider.kt`** (NEW): `fun interface { fun snippet(charOffsetUTF16: Int, maxLen: Int): String? }` — TXT/MD host supplies it; others pass null.

### New/modified — surfaces (Problems 5 + 6)
- **`reader/chrome/ReaderTopChrome.kt`** (MODIFY — fills #132's nullable slot via the host); new **`reader/chrome/BookmarkToggleButton.kt`** (`@Composable` filled/empty bookmark icon reflecting `isBookmarked`, `onClick`; ≥48dp; a11y desc).
- **`reader/chrome/ReaderChromeState.kt` / `ReaderChromeScaffold.kt`** (MODIFY): add `ReaderSheet.Bookmarks` to the sealed route (the `ReaderChromeStateSaver` string-encoding gains the token; invalid-token→None preserved). Add nullable-default params: `currentLocator?`, `isCurrentBookmarked`, `onToggleBookmark?`, `bookmarks: List<BookmarkRowUi>`, `onJumpBookmark: ((BookmarkRecord) -> JumpResult)?`. All nullable/defaulted → #132 callers stay valid.
- **`reader/nav/TocBookmarksSheet.kt`** (promote #132's `TocContentsSheet` → two-tab `TOCSheet`): tab bar (`Contents`|`Bookmarks`), Contents unchanged, **Bookmarks tab** = rows (icon · preview · `chapter · p.N · date` · chevron) → tap `onJumpBookmark` + dismiss-on-success; empty-state; NO delete affordance (gated).
- **`reader/nav/AnnotationsReviewSheet.kt` / `AnnotationCards.kt`** (MODIFY of #132): add the `Bookmarks` filter chip + `BookmarkCard`; tap-to-jump on card body (capability-gated via #132's `onJumpToAnnotation`); no per-card delete (gated).

### Modified — host wiring (light up create/toggle/jump per host)
- **`reader/ReaderActivity.kt` (EPUB)** (MODIFY): (a) feed `isCurrentBookmarked` + `onToggleBookmark` (presence from `nav.currentLocator` → canonical → `repository.isBookmarked`); (b) **bookmark jump = `ReadiumLocatorReconstructor(publication).toReadium(bookmark.locator)` → `navigator.go`** (Problem 1); on null reconstruction / false `go`, the sheet stays open. The **process-restart / backup-restored bookmark jump** exercises exactly this (canonical-only).
- **`reader/TxtReaderActivity.kt` / `reader/PdfReaderActivity.kt`** (MODIFY): toggle presence + create via the current plain `Locator` (`charOffsetUTF16` / `page`); jump via scroll-to-offset / page. TXT supplies the `BookmarkPreviewProvider`.
- **`reader/Azw3ReaderActivity.kt`** (MODIFY): toggle presence + create via the relocate-derived canonical `Locator`; **jump = `Azw3Document.goTo(bookmark.locator)`** (Problem 2) — CFI-first/fraction-fallback, awaited, render-death re-issue.

### OUT of scope (gated / owned elsewhere)
- **Bookmark row DELETION** (list/card) — undesigned (GH #1903); NOT built. (Top-bar toggle-off IS built.)
- **Bookmark rename/edit UI** — out.
- **`BackupCollector` / `RestoreImporter` change** — NONE. #132 wired the full `annotations.json` round-trip with the bookmarks list populated + restored (UUID-preserving, profile-key fallback written to expect #135's index). #135 adds ONLY the create path (fills the list) + the unique index.

### §nav-error-presentation — failed bookmark jump (rule 51)
A jump can fail: EPUB `toReadium` null / `navigator.go` false; AZW3 goTo `Timeout`/`ok=false`; TXT/PDF offset/page out of range. In every case the sheet **stays open, no invented error surface** (matches #132's §navigation-outcome). Jump returns `JumpResult` (`Succeeded`/`Failed`); dismiss only on `Succeeded`.

## 3. Prior art / project precedent / rejected alternatives

**Prior art:** `AnnotationDao.upsertHighlight` (transactional insert-if-absent on a unique index) → the toggle template; the highlights unique-index migration + `VReaderDatabaseMigrationTest` PRAGMA harness → the bookmark migration template (with dedupe-before-index added); `ResumeResolver.Precise` → `Locator.fromJSON(readiumLocatorJSON)` → `navigator.go` (the *position*-restore precedent; bookmark differs — no precise JSON → `toReadium`); `ReadiumLocatorBridge` forward path (Readium-free) → keep `toReadium` in a separate reconstructor; `Azw3Document.restoreOrInit` (CFI-first→fraction) + `FoliateMessage.Relocate` + `onRenderProcessGone` recovery → the awaited-goTo template; #127 `SheetRouteSaver` + #132's `ReaderChromeStateSaver` → the `Bookmarks` route token; `profileKeyFor`/`BookmarkRecord.toEntity()` → the equality basis; #132's `BackupCollector`/`RestoreImporter` wiring → why #135 touches neither.

**Rejected alternatives:**
1. *Put `toReadium` in `ReadiumLocatorBridge`* — pulls a Readium dependency into the pure-JVM bridge. Use a separate `ReadiumLocatorReconstructor(publication)`.
2. *Reuse the position `readiumLocatorJSON` for bookmark jump* — a bookmark has no precise Readium JSON (only a canonical `Locator`). Reconstruct.
3. *Fire-and-forget AZW3 goTo* — a failed/no-op jump would be invisible + the sheet couldn't decide dismiss-vs-stay. Build the awaited, ack'd, request-ID bridge.
4. *`addJavascriptInterface` for the goTo ack* — banned (#126). Route through `addWebMessageListener`.
5. *UUID-keyed `@Upsert` for toggle* — mints a new UUID each call → duplicates. Use the `(bookKey, profileKey)` unique index + transactional toggle.
6. *Add the unique index without dedupe* — `CREATE UNIQUE INDEX` fails on existing duplicates. Dedupe (delete losers, deterministic order) BEFORE the index.
7. *Store preview/chapter on `BookmarkEntity`* — schema bloat + staleness. Derive at read time from the TOC + a preview provider.
8. *Build bookmark list-row deletion from the iOS design* — no Android depiction (GH #1903). Gate it.
9. *Change `BackupCollector`/`RestoreImporter`* — #132 already wired the full envelope incl. bookmarks. No change.

## 4. Work-item sequencing (each 1 PR)

**Tiers:** Foundational (unit/Robolectric, no device) = WI-1, WI-3, WI-4. Behavioral (emulator slice) = WI-2, WI-5..WI-8. Tail = WI-9.

**WI-1 (foundational) — EPUB canonical→Readium reconstruction (`toReadium`).** `ReadiumLocatorReconstructor(publication).toReadium(canonical): Locator?` via `linkWithHref` + canonical progression/cfi/text. Tests (Robolectric, fixture pub): resolvable href+progression → valid Readium locator (href/progression match); cfi→fragments; textQuote→text.highlight; **unresolvable href → null**; **structurally-invalid → null**; fingerprint-mismatch → null; canonical↔Readium round-trip.

**WI-2 (behavioral) — awaited AZW3 `goTo` bridge.** `FoliateBridge.goTo` (request-ID, ack'd via `goto-ack` over `addWebMessageListener`, JSON-escaped) + `FoliateMessage.GoToAck` + parser + `Azw3Document.goTo` (CFI-first→fraction, pending-target for render-death re-issue) + the bundle patch. Tests: unit (fake message flow + `runTest` virtual time for timeout) + an emulator slice (real WebView relocate ack + forced `onRenderProcessGone`). Security: ack only from the shell origin, never `addJavascriptInterface`.

**WI-3 (foundational) — atomic toggle + unique-index migration + dedupe.** DAO members + `@Transaction toggleBookmark`; repo `toggleBookmark`/`isBookmarked`; `BookmarkEntity` composite unique index; `MIGRATION_N_(N+1)` (dedupe-losers-then-`CREATE UNIQUE INDEX`, number version-at-slot); bump version, append `ALL_MIGRATIONS`, regenerate exported schema. Tests (in-memory Room + `runTest`): toggle add→one row; toggle again→zero; **concurrent/repeat add → exactly one (idempotent)**; **toggle race → single deterministic state**; `isBookmarked` presence; **migration with duplicates → deterministic winner survives, losers deleted, other data preserved, index rejects new dup**. **Do NOT pre-assign the migration number.**

**WI-4 (foundational) — per-format bookmark presentation projection.** `BookmarkPresentation.bookmarkRow` + `BookmarkPreviewProvider`. Tests (JVM): EPUB chapter/page from TOC; PDF `p.N`; TXT/MD bounded ellipsized preview; no-preview/no-chapter → null fields no crash; huge book (bounded); offset-out-of-range clamped; deterministic date.

**WI-5 (behavioral) — top-bar toggle + current-locator state.** `BookmarkToggleButton` filling #132's slot; `ReaderChromeState`/`Scaffold` gain `isCurrentBookmarked`/`onToggleBookmark`/`currentLocator` + the `Bookmarks` route + Saver token. Tests (Compose): filled/empty; tap→toggle; a11y flips; ≥48dp; route survives process death (Saver) + invalid-token→None; **#132 Contents/Notes-only caller back-compat**. Emulator slice.

**WI-6 (behavioral) — Bookmarks surface: `TOCSheet` tab + review chip/card.** Promote to two-tab `TOCSheet` (Bookmarks tab: rows + tap-jump + empty-state, no delete); add the `Bookmarks` filter chip + `BookmarkCard`. Tests (Compose): tab switch → rows; `bookmarks-empty`; tap → `onJumpBookmark` + dismiss-on-success; failed jump → sheet stays open; chip narrows; card renders; **no delete affordance (absence assertion)**. Emulator slice.

**WI-7 (behavioral) — host wiring: create/toggle/jump per host.** EPUB (toggle from `nav.currentLocator`→canonical; **jump via `toReadium`→`navigator.go`**); AZW3 (toggle from relocate-derived canonical; **jump via `Azw3Document.goTo`** incl. render-death re-issue); TXT/MD + PDF (plain `Locator` offset/page; TXT supplies preview provider). Tests (androidTest per host): toggle→filled→row→jump; **EPUB reopen (fresh process) → jump to persisted bookmark reconstructs + lands**; AZW3 render-death mid-jump recovers; TXT scroll-to-offset; empty host no crash.

**WI-8 (behavioral) — restored/backup-restored bookmark jump + no-backup-change verification.** Verify (no code change) that #132's collector/importer round-trips bookmarks; then the process-restart / backup-restored EPUB bookmark-jump end-to-end (back up a book with a bookmark → wipe → restore over the #132 path, ideally live WebDAV → reopen → **jump reconstructs a Readium locator + lands**); restored UUID preserved; **re-restore doesn't duplicate (unique index + profile-key fallback active)**; renamed-resource bookmark → sheet stays open, no crash.

**WI-9 (tail) — acceptance + device verification + trackers.** End-to-end across all 5 formats; `docs/features.md` #135 → DONE; `docs/parity/android-checklist.md` box B → `[x]` (bookmark half complete alongside #132's review sheet); box-F partial note updated. Evidence file. Gate-4/5.

## 5. Test catalogue

| File | Cases (edge cases in bold) |
|---|---|
| `test/.../reader/ReadiumLocatorReconstructorTest.kt` (Robolectric) | resolvable href+progression → valid; cfi→fragments; textQuote→text; **unresolvable/renamed href → null**; **structurally-invalid → null**; fingerprint-mismatch → null; round-trip |
| `test/.../reader/foliate/FoliateGoToBridgeTest.kt` (unit, `runTest`) | ack ok → Succeeded(cfi/fraction); reject → Failed; **no ack → Timeout (virtual time)**; superseding goTo cancels prior; **invalid CFI → fraction fallback**; ack only from shell origin |
| `androidTest/.../reader/foliate/Azw3GoToSliceTest.kt` (emulator) | real relocate ack resolves; **render-death mid-jump → recreate + re-issue → reaches target**; timeout on dead bundle |
| `test/.../data/BookmarkToggleMigrationTest.kt` (in-memory Room + migration) | toggle add→one; again→zero; **repeat/concurrent add → exactly one**; **toggle race → single deterministic state**; presence; **migration with duplicates → winner survives, losers deleted, data preserved, unique index rejects new dup**; DDL PRAGMA-valid |
| `test/.../reader/nav/BookmarkPresentationTest.kt` (JVM) | EPUB chapter/page from TOC; PDF p.N; **TXT bounded ellipsized preview**; **no-preview/no-chapter → null, no crash**; **huge book → bounded**; offset-out-of-range clamped; deterministic date |
| `androidTest/.../reader/chrome/BookmarkToggleButtonTest.kt` (Compose) | filled/empty; tap→toggle; a11y flips; ≥48dp; **#132 Contents/Notes-only back-compat** |
| `androidTest/.../reader/nav/TocBookmarksTabTest.kt` (Compose) | tab switch → rows; **`bookmarks-empty`**; tap→jump+dismiss-on-success; **failed jump → sheet stays open**; **no delete affordance** |
| `androidTest/.../reader/nav/BookmarkReviewChipTest.kt` (Compose) | chip narrows; `BookmarkCard` renders; tap-jump capability-gated; no per-card delete |
| `androidTest/.../reader/EpubBookmarkNavTest.kt` (fixture EPUB) | toggle→filled; row in sheet; tap→href change; **reopen (fresh process) → jump reconstructs + lands**; unresolvable → sheet open |
| `androidTest/.../reader/Azw3BookmarkNavTest.kt` | toggle+list+jump; **render-death mid-jump recovers**; timeout → sheet open |
| `androidTest/.../reader/TxtPdfBookmarkTest.kt` | toggle+list+tap-jump offset/page; empty host no crash; TXT preview present |
| `androidTest/.../backup/BookmarkBackupRestoreJumpTest.kt` | **backup→wipe→restore (WebDAV) → reopen → jump to restored bookmark (canonical reconstruction) lands**; restored UUID preserved; **re-restore doesn't duplicate**; renamed-resource → sheet open |

Edge cases: restored-bookmark jump (canonical-only reconstruction); EPUB reopen fresh process; AZW3 render-death mid-jump; invalid/unresolvable CFI/href; duplicate-toggle race; migration with duplicates + data preservation; no-preview/no-chapter hosts; huge book; goTo timeout; superseding goTo cancellation.

## 6. Risks + mitigations

1. **`toReadium` reconstruction fidelity (WI-1, highest correctness risk).** A canonical `Locator` may not round-trip byte-identically. Mitigation: resolve `href` via `linkWithHref` (authoritative media-type), carry progression/cfi/text, accept progression-precision as the floor (same posture as `ResumeResolver`'s canonical fallback); null on unresolvable → sheet stays open.
2. **Awaited AZW3 goTo — the bundle doesn't return its promise (WI-2).** Patch the `readerAPI.goTo` shim to return the promise + post `goto-ack` after relocate; key by request id; timeout + cancellation + render-death re-issue; route through `addWebMessageListener`, JSON-escape, never `addJavascriptInterface`. Emulator slice covers real relocate + forced render-death.
3. **Migration on existing duplicates (WI-3).** Dedupe-losers (deterministic order) BEFORE the index; migration test seeds duplicates + asserts winner-survives + data-preserved + index-created. Number version-at-slot, never pre-assigned.
4. **Write-set overlap with #132 on `AnnotationDao` + chrome files (integration serialization, NOT a Deps edge).** #135's DAO/chrome WIs land after #132 merges + re-audit; all additions are new members / nullable-default slots.
5. **Backup ownership confusion.** #135 must NOT touch `BackupCollector`/`RestoreImporter` (#132 wired the full envelope incl. bookmarks + the profile-key-fallback restore that expects #135's index). #135 only fills the list + adds the index. WI-8 verifies the round-trip without a code change.
6. **Toggle-off vs list-deletion (rule 51).** Toggle-off (top-bar) IS depicted + built; **arbitrary list/card deletion is undesigned (GH #1903) → gated.** No delete affordance on the row/card without a committed depiction.
7. **Per-format presentation staleness / cost (WI-4).** Derive at read time from the TOC + a bounded preview provider; never store preview/chapter; clamp TXT snippet; O(log n) TOC lookup for huge books.

## 7. Backward compat

- **One DB migration** (additive unique index preceded by an in-migration dedupe). Existing bookmark rows preserved (only duplicate losers deleted, deterministically); version bumped; `ALL_MIGRATIONS` appended; exported schema regenerated; migration test guards it.
- **`AnnotationDao`** gains new members; existing `upsertBookmark`/`deleteBookmark(id)`/`observeBookmarks`/`bookmarksForBook` unchanged.
- **`ReaderChromeScaffold`/`ReaderTopChrome`/`ReaderChromeState`** gain nullable-default params + a `Bookmarks` route/token → #132's Contents/Notes-only call sites compile unchanged; the Saver tolerates the new token + falls back to `None` on any unrecognized token.
- **`FoliateBridge`/`FoliateMessage`/`Azw3Document`** gain an additive awaited goTo + `GoToAck`; existing `init*/next/prev`/relocate behavior byte-unchanged; the bundle patch only returns an already-called promise + posts an ack.
- **Backup/restore** is byte-unchanged code (#132 owns it); the bookmarks list simply becomes non-empty once users create bookmarks. A pre-#135 backup restores its bookmarks through the same UUID-preserving seam; the new unique index makes the profile-key fallback active (re-restore idempotent).
- **Dormant → live:** `toggleBookmark`/`isBookmarked`, `ReadiumLocatorReconstructor.toReadium`, `Azw3Document.goTo`, `BookmarkPresentation`, the top-bar toggle, the `TOCSheet` Bookmarks tab, the review `Bookmarks` chip/card. Bookmark list-row deletion stays gated (GH #1903).

## Revision history
- v1 (2026-07-11): Gate-1 draft (split from #132 v4; owns the four deferred bookmark hard problems + create/toggle/list/jump). Gate-2 Codex audit pending.
