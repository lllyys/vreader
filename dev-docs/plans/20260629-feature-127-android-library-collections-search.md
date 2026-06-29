# Feature #127 — Android library collections (Phase 3, #110 driver)

> Parity-checklist item **C** (the *collections* half; the *search* half is split out to a separate
> feature **#128** — see "Scope" / the Gate-2 audit). iOS parity: #60 collections + the shared backup
> contract `BackupCollection`. Reuses the committed design
> `dev-docs/designs/vreader-fidelity-v1/project/vreader-library-android.jsx` (rule 51).

## Problem

The Android library is a flat grid of all imported books with no way to **organize** them into
collections/shelves. iOS has user collections (`BookCollection` @Model + `PersistenceActor+Collections`)
that round-trip through the shared backup contract (`BackupCollection { name, createdAt,
bookFingerprintKeys }`). Android has neither the collections feature nor the backup wiring for it
(`BackupCollector` emits only `positions.json` today). This feature brings Android collections to that
parity: the shelf-bar + manage/assign sheets **and** backup/restore of collections.

## Scope

**In scope (this feature, #127):**
- **Collections data model** aligned with iOS + the backup contract: a collection is identified by
  `name` (trimmed, ≤100 chars, **case-insensitive unique**) + `createdAt`; membership is a many-to-many
  to books by `fingerprintKey`. No ordering / no system collections (the contract + iOS have neither).
- **UI** (the committed design): a horizontal collections shelf-bar over the grid ("All" + each
  collection, selecting filters the grid), an **assign-to-collections** sheet (checklist + inline
  new-collection), and a **manage-collections** sheet (create / rename / delete).
- **Backup/restore parity** (the Gate-2 **Critical**): `BackupCollector` emits a `collections.json`
  section (`BackupCollectionsEnvelope`) and `RestoreImporter` restores it — byte-compatible with the
  iOS contract so an iOS backup's collections restore on Android and vice-versa.

**Out of scope / deferred (with rationale — all from the Gate-2 audit):**
- **Library search** → split to a **separate feature #128** (the Android `Book` DTO has **no author
  field** and there is **no cross-format full-text index**, so the committed search design's
  "title · author · N in-text matches" surface can't be honestly built here; #128 owns the
  author-field + FTS + any needed design update). Filing search separately keeps #127 clean and avoids
  shipping a half-implemented designed surface (rule 51).
- **Collection reordering** (the design's drag-handles): the cross-platform contract + iOS have **no
  ordering field**, so an Android-only `sortOrder` would diverge from parity. Deferred pending a
  cross-platform ordering decision; #127's manage sheet ships create/rename/delete (display order =
  createdAt). Noted, not invented.
- **iOS auto-collections ("Currently Reading" / "Finished")** — iOS auto-manages these from reading
  progress; not in the contract's `BackupCollection`; deferred.
- iOS code (rule 48 write isolation).

## Surface area

### New — data layer (`com.vreader.app.data`)

- **`CollectionEntity`** (`@Entity tableName = "collections"`): `id: String` (UUID PK — an internal
  impl detail for FK efficiency, **not** part of the backup identity), `name: String`, `nameKey: String`
  (the normalized `name.trim().lowercase(Locale.ROOT)` — **locale-invariant**, so Turkish-I / CJK
  normalize consistently — for the **case-insensitive unique index**), `createdAt: Long`.
  `@Index(value = ["nameKey"], unique = true)`.
- **`BookCollectionCrossRef`** (`@Entity tableName = "book_collection", primaryKeys = ["bookKey",
  "collectionId"]`): `bookKey: String` (FK → `books.fingerprintKey`, `onDelete = CASCADE`),
  `collectionId: String` (FK → `collections.id`, `onDelete = CASCADE`); `@Index("collectionId")` (the
  composite PK already indexes `bookKey`-first).
- **`CollectionDao`**: `observeCollectionsWithCount(): Flow<List<CollectionWithCount>>` (LEFT JOIN +
  `COUNT` so empty collections show 0), `insert`, `rename(id, name, nameKey)`, `delete(id)`,
  `findByNameKey(nameKey): CollectionEntity?` (the transactional dedup check), `addMembership` /
  `removeMembership` (`OnConflict.IGNORE`), `observeBooksInCollection(id): Flow<List<String>>`,
  `observeCollectionIdsForBook(bookKey): Flow<List<String>>`. `@Transaction` on create/rename so the
  dedup check + write are atomic.
- **`CollectionRepository`** (DTO boundary): the value type `Collection(id, name, createdAt, bookCount)`;
  `createCollection(rawName): Result<Collection>` (trim → reject empty → **truncate to 100 chars** (iOS
  parity — iOS truncates, has no length error; truncating also guarantees restore never drops a valid
  long-name backup collection) → case-insensitive (`nameKey`) dedup → insert, all in one `@Transaction`),
  `rename`, `delete`, `assign`/`unassign`, `observeCollections`, `observeBookKeysInCollection`,
  `observeCollectionIdsForBook`. Errors: `CollectionError { EmptyName, DuplicateName, NotFound }`
  (mirrors iOS `CollectionError`; **no `NameTooLong`** — names are truncated, not rejected, per iOS).
- **`VReaderDatabase`** — `@Database(version = 5)`; add `MIGRATION_4_5` (create both tables + the unique
  `nameKey` index + the `collectionId` index, FK CASCADE, **no data transform** — mirrors the v3→v4
  annotations migration); append to `ALL_MIGRATIONS`; add `abstract fun collectionDao()`. `room.schemaLocation`
  is **already configured** (schemas 2–4 are committed) — so WI-1 commits the generated **`5.json`** and
  verifies the `MIGRATION_4_5` DDL matches it exactly (not "add schemaLocation").

### New — backup (`com.vreader.app.backup`)

- **`BackupCollector`** — add a `collections.json` section built from `CollectionRepository` →
  `BackupCollectionsEnvelope(schemaVersion = BackupSchema.CURRENT_SCHEMA_VERSION, collections = …)`.
  Only book keys present in the backup are included (no dangling refs, mirroring the positions filter).
  **Deterministic ordering for byte-stable backups** (Gate-2 High — the archive writer sorts section
  *filenames*, not JSON array contents): the `collections` list is sorted by `(nameKey, createdAt)` and
  each `bookFingerprintKeys` list is sorted ascending — so the same logical DB with a different insert
  order produces an identical `collections.json` (a byte-stability test guards this).
- **`RestoreImporter`** — restore `collections.json`, mirroring `decodePositions`' tolerance (Gate-2
  Medium): an **absent** section is OK; a malformed / unsupported-schema section is skipped/reported per
  the existing restore policy; accepted schema versions are checked. **Merge semantics** (Gate-2 Medium —
  ids don't match across devices, so never key on UUID): for each `BackupCollection`, look up by
  `nameKey`; if absent, create a new row with the backup's `createdAt`; if present, keep the existing
  row's `createdAt` (a name collision keeps the local `createdAt`) and **union** the membership for book
  keys that resolve to a known/restored book. Each collection's restore is **one `@Transaction`** (upsert
  + membership union) so a partial write / concurrent assign can't leave counts inconsistent.

### Modified — UI (`com.vreader.app.library`)

- **`LibraryViewModel`** — `collections: StateFlow<List<Collection>>` (from `observeCollections`),
  `selectedCollectionId: StateFlow<String?>` ("All" = null), and a **`flatMapLatest`** filtered book
  list (`selectedCollectionId.flatMapLatest { id -> if null observeLibrary else
  observeBooksInCollection(id) ∩ library }`) so a stale previous-selection membership can't filter the
  new selection; **reset selection to All when the selected collection is deleted**. Plus
  `createCollection` / `rename` / `delete` / `assign` / `unassign`, surfacing `CollectionError` as events.
- **`LibraryScreen`** — insert `CollectionShelfBar` between the title and the grid; a **sheet route
  state** (`SheetRoute { None, Manage, Assign(bookKey) }` via `rememberSaveable`/`SavedStateHandle`,
  handling deletion of the open collection/book) drives `CollectionsManageSheet` (from the shelf "edit")
  + `AssignToCollectionsSheet` (from a book long-press).
- **New Compose**: `CollectionShelfBar`, `AssignToCollectionsSheet`, `CollectionsManageSheet`.

### Files OUT of scope

iOS (`vreader/`); library/in-reader search (#128 / #F); reorder; the Android `Book` author field (#128).

## Prior art / project precedent / rejected alternatives

- **The backup contract `BackupCollection`** (`android/identity/.../backup/BackupSections.kt:83`) is the
  source-of-truth model identity (name + createdAt + bookFingerprintKeys) — the Room model serializes
  to/from it. iOS `BookCollection` + `PersistenceActor+Collections` + `CollectionError` are the parity
  reference.
- **Room migration precedent**: the v3→v4 annotations migration (#123) in `VReaderDatabase.kt` + the
  **JVM/Robolectric** `VReaderDatabaseMigrationTest` (the migration-test style — NOT a connected test,
  per the Gate-2 Low).
- **Backup-section precedent**: #116's `BackupCollector` (`positions.json`) + #113's `BackupJson` +
  the cross-platform golden-vector conformance (#113 WI-3) — the collections section mirrors it.
- **Repository/DAO precedent**: `LibraryRepository`/`BookDao` (DTO boundary, `@Upsert`, Flow observers).
- **Rejected**: (a) `name` as the PK (rename churns FKs) → internal UUID id + a unique `nameKey`;
  (b) case-sensitive unique index on `name` (Gate-2 High — diverges from iOS case-insensitive) →
  normalized `nameKey`; (c) Android-only `sortOrder` (Gate-2 High — diverges from the contract) →
  dropped; (d) in-memory N×M membership filtering → a Room join Flow; (e) keeping search in #127
  (Gate-2 High — design/data gap) → split to #128.

## Work-item sequencing (split per Gate-2)

| WI | Tier | Scope | PR size |
|---|---|---|---|
| WI-1 | foundational | `CollectionEntity` + `BookCollectionCrossRef` + `MIGRATION_4_5` + `@Database(version=5)` + **exported `5.json`** + `CollectionDao` skeleton + `collectionDao()`. Tests: a **Robolectric** `VReaderDatabaseMigrationTest` v4→v5 (opens + both tables + indices present + FK cascade via `PRAGMA foreign_key_check`) + entity insert/query | M |
| WI-2 | foundational | `CollectionDao` full + `CollectionRepository` (transactional create with trim/≤100/case-insensitive dedup; rename; delete; membership). Tests: CRUD + dedup goldens (case variants, whitespace, CJK, >100, empty) + cascade-on-book-delete + `observeCollectionsWithCount` correctness | L |
| WI-3 | behavioral | `LibraryViewModel` collections state + **`flatMapLatest`** membership filter (+ reset-to-All on delete) + `CollectionShelfBar` Compose. Tests: VM filter (JVM, incl. the stale-selection race) + a shelf-bar UI test | L |
| WI-4 | behavioral | `AssignToCollectionsSheet` (checklist + inline create) + the sheet route state, wired VM→repo. Tests: assign/unassign persists + the chip count updates (connected) | M |
| WI-5 | behavioral | `CollectionsManageSheet` (list + inline rename + inline create — no reorder; **delete UI deferred to needs-design #1875**, Gate-4 round-2 rule-51) opened from the DESIGNED scoped-collection "edit collection" header. Wired VM→repo with `CollectionError` surfacing. Tests: manage list/rename/create (connected) | M |
| WI-6 | behavioral | Backup/restore: `BackupCollector` emits `collections.json` (`BackupCollectionsEnvelope`) + `RestoreImporter` restores it (case-insensitive merge, membership union). Tests: collect→restore round-trip + (if a shared golden vector exists) cross-platform conformance | M-L |
| WI-7 | behavioral (final) | Acceptance on the emulator: import → create collection → assign → filter by chip → manage rename → **backup → wipe → restore** preserves collections + membership. (Delete UI is needs-design #1875 — out of this acceptance pass.) Evidence file → VERIFIED | M |

## Test catalogue

- `VReaderDatabaseMigrationTest` v4→v5 (Robolectric/JVM, WI-1): opens; `collections` + `book_collection`
  present; the unique `nameKey` index + `collectionId` index exist; `PRAGMA foreign_key_check` clean;
  deleting a book cascades the cross-ref.
- `CollectionDaoTest` / `CollectionRepositoryTest` (JVM in-memory Room, WI-2): create/rename/delete;
  dedup goldens — `"Fiction"` vs `"  fiction  "` vs `"FICTION"` → `DuplicateName`; `""`/whitespace →
  `EmptyName`; >100 chars → **truncated to 100** (not an error); Turkish-I (`"İ"`/`"ı"`) + CJK `nameKey`
  via `Locale.ROOT`; membership add/remove/idempotent; cascade; count.
- `LibraryViewModelCollectionsTest` (JVM, WI-3): chip select filters; "All" resets; deleting the
  selected collection resets to All; the `flatMapLatest` doesn't leak the previous selection's membership.
- `CollectionShelfBarUiTest` / `AssignSheetUiTest` / `ManageSheetUiTest` (connected, WI-3/4/5):
  chip select, checklist toggle persists, inline create, inline rename. (Manage delete UI deferred —
  needs-design #1875; the delete capability stays repo/VM-tested.)
- `CollectionBackupRoundTripTest` (JVM/connected, WI-6): collect → `BackupCollectionsEnvelope` →
  restore → collections + membership preserved; **byte-stability** (same logical DB, different insert
  order → identical `collections.json`); restore merge goldens — same name / different case / different
  `createdAt` (existing `createdAt` kept on collision); absent section OK; malformed/unsupported-schema
  skipped; unknown book keys dropped; a concurrent-assign-during-restore stays consistent (transactional).
- `LibraryCollectionsAcceptanceTest` (connected, WI-7): the full flow incl. backup→restore.

## Risks + mitigations

- **R1 — backup contract drift** (Gate-2 Critical): the Android `collections.json` MUST decode/encode
  byte-compatibly with the iOS `BackupCollection`. Use the shared `BackupSections`/`BackupJson` types
  (already in `:identity`); a round-trip + (if available) golden-vector conformance test guards it.
- **R2 — case-insensitive uniqueness** (Gate-2 High): a normalized `nameKey` unique index + a
  transactional dedup check (`@Transaction` create/rename). Goldens for case/whitespace/CJK/length.
- **R3 — migration correctness**: export `5.json`; write the DDL to match it exactly; Robolectric
  migration test with `foreign_key_check`. Additive only — existing tables untouched.
- **R4 — VM membership race** (Gate-2 Medium): `flatMapLatest`; reset-to-All on delete; a single DAO
  join Flow `observeBooksInCollection`.
- **R5 — sheet route state across rotation/deletion** (Gate-2 Medium): an explicit `SheetRoute` model in
  `rememberSaveable`/`SavedStateHandle`; close the sheet if its book/collection is deleted underneath.
- **R6 — reorder divergence** (Gate-2 High + round-2 Low): dropped from #127 (no contract order field);
  display order = createdAt; reorder deferred pending a cross-platform decision. **The manage sheet ships
  NO drag handles / no reorder affordance** — inert reorder UI is not acceptable (rule 51); reorder is
  tracked as a separate cross-platform feature/design decision, not a placeholder here.
- **R7 — manage delete affordance is undesigned** (Gate-4 WI-5 round-2, rule 51): the committed
  `CollectionsManageSheet` depicts list/create/rename + an Edit-mode chevron disclosure, but the
  per-collection detail screen where **delete** lives is NOT depicted. The first WI-5 cut invented an
  inline trash button (+ an invented nav-bar manage entry); both were removed. The manage sheet now
  opens from the DESIGNED scoped-collection "edit collection" header and ships list + rename + create
  only. Delete UI is deferred to **needs-design #1875**; the capability stays repo/VM-backed + tested.

## Backward compat

Additive Room migration (v4→v5, two new tables only) — books/positions/annotations untouched; older DBs
upgrade cleanly; an empty library renders as today (shelf-bar shows only "All", or is hidden at zero
collections). The backup gains a `collections.json` section that older clients (which ignore unknown
sections per the manifest model) tolerate; restoring an iOS backup's collections now works on Android.

## Revision history

- v5 (2026-06-29) — **WI-5 merged** (`android/v0.13.6`, PR #1876, Gate-4 ship-as-is): the manage sheet
  rule-51 rework — removed the invented nav-pill + trash button; reach the manage sheet from the designed
  scoped-collection "edit collection" header; delete UI deferred to **needs-design #1875**; split the
  manage sheet + scoped header into `CollectionManageSheet.kt` (file-size). Gate-5 `ManageSheetUiTest`
  3/3 connected. **WI-6 in progress** — `BackupCollector` emits a deterministic `collections.json`
  (collections sorted by `nameKey`, each `bookFingerprintKeys` filtered to backed-up books + sorted →
  byte-stable); `RestoreImporter` merges by `nameKey` (create-with-backup-`createdAt` if absent, else keep
  existing + its `createdAt`) and unions membership for existing books only (unknown keys dropped) via a
  transactional `CollectionDao.restoreCollection` + FK-safe `addMembershipIfBookExists`. JVM
  `CollectionBackupTest` covers collect-determinism + byte-stability + round-trip + merge-collision +
  unknown-key-dropped + absent-section.

- v3 (2026-06-29) — **Gate-2 round-2 fixes** (Codex `019f1296`, gpt-5.5/high; round-1's 1C/4H structural
  findings confirmed resolved; round-2 raised 1H/4M/3L on the backup design): **(High)** `collections.json`
  determinism — sort collections by `(nameKey, createdAt)` + sort each `bookFingerprintKeys`; byte-stability
  test; **(Medium)** restore merge by `nameKey` (never UUID), create-with-backup-`createdAt`, keep existing
  `createdAt` on collision; **(Medium)** per-collection restore is one `@Transaction` (upsert + membership
  union) + a concurrent-assign test; **(Medium)** restore tolerance mirrors `decodePositions` (absent OK,
  malformed/wrong-schema skipped, emit `BackupSchema.CURRENT_SCHEMA_VERSION`); **(Medium)** name length —
  **truncate to 100 (iOS parity), drop `NameTooLong`**; **(Low)** `nameKey` = `lowercase(Locale.ROOT)`
  + Turkish-I/CJK tests; **(Low)** the manage sheet ships NO inert reorder UI; **(Low)** `5.json` is
  committed + DDL-verified (schemaLocation already configured). All round-2 findings are the auditor's
  own recommended fixes, applied verbatim → Gate-2 clean to proceed; the backup specifics (determinism,
  merge, transactional restore) are WI-6 implementation details its per-WI Gate-4 audit will verify.
- v2 (2026-06-29) — **Gate-2 round-1 fixes** (Codex `019f128f`, gpt-5.5/high; 1C/4H/5M/2L → FIX-THEN-PROCEED):
  **(Critical)** collections are backup-contract-bound (`BackupCollectionsEnvelope` exists; Android only
  backs up positions) → added backup/restore wiring (WI-6) instead of "local-only"; **(High)** search
  removed from #127 → split to feature **#128** (no Android author field, no FTS, reduced-surface design
  gap); **(High)** all new Android types phrased as new + a WI-1 verification step; **(High)**
  case-insensitive uniqueness via a normalized `nameKey` + trim + ≤100; **(High)** model aligned to the
  contract — dropped `sortOrder`/`isSystem`/reorder; **(Medium)** export `5.json` + exact DDL,
  transactional create/rename, `flatMapLatest` filter, explicit `SheetRoute` state, split the oversized
  WI-4/WI-5/search WIs; **(Low)** the migration test is Robolectric/JVM (not connected). Pending Gate-2
  round-2 re-audit.
- v1 (2026-06-29) — initial plan (collections + search in one). Superseded by v2.
