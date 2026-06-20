# Feature #116 — Android WebDAV backup/restore backend

Status: Gate-2 audited (2026-06-20, Codex round 1 → revised; see Revision history). The non-UI backend behind the #114 `BackupService` seam — the
WebDAV client + backup collector (Room→ZIP) + restore importer (ZIP→Room) that make the Android
backup/restore real. Under the #110 Phase-3 driver. Codex-selected as the most
autonomously-completable next capability (non-UI → no rule-51 gate; builds on #113 DTOs + #114
seam; verifiable against a LOCAL WebDAV with no paid service).

## Problem

#113 shipped the cross-platform backup-format DTOs (`:identity`, conformance-green). #114
shipped the backup/restore UI behind a UI-oriented `BackupService` interface
(`listServers`/`testConnection`/`listBackups`/`startBackup:Flow`/`loadManifest`/`restore:Flow`/
`retryBook`), DEBUG-reachable with a `PreviewBackupService`. The MISSING piece is the **real**
`BackupService`: a WebDAV client, a backup collector (Room + book files → a ZIP of the #113
section JSONs + a content-addressed blob store), and a restore importer (ZIP → DTOs → Room +
materialized book files). iOS has the full subsystem (`WebDAVClient`, `WebDAVProvider`,
`BackupDataCollector`, `BackupDataRestorer`, `BackupBlobStore`, `ZIPWriter`, …).

## Scope (v1 — Codex-guided)

The first verified slice covers **Android-supported data**: books (the `library-manifest` +
content-addressed blobs) + reading positions, with **valid-but-empty** sections for the
iOS-only tables Android doesn't have yet (annotations/collections/settings/book-sources/
per-book-settings/replacement-rules/reading-history/ai-conversations). This proves the real
cross-platform contract path (a backup written by Android restores on iOS and vice-versa for
books + positions) while staying finishable. Annotations/etc. become follow-ons as Android
gains those features.

## Key design decisions (Gate-2 round 1)

- **Remote layout = EXACTLY the iOS materializing-restore layout** (Gate-2 round-2 High — the
  cross-platform interop point). Verified against `vreader/Services/Backup/{WebDAVProvider,
  BlobPath}.swift`:
  - **Backups**: `VReader/backups/<ts>_<id>.vreader.zip` — a single ZIP file (NOT a directory)
    containing `metadata.json` + the section JSONs + `library-manifest.json`, **NO book bytes**.
    Because the ZIP carries no blobs it is KB-sized, so `listBackups` (PROPFIND `VReader/backups/`
    for `*.vreader.zip`, GET each ZIP, read `metadata.json`) is cheap — resolving the round-1
    High-1 concern.
  - **Blob store**: `VReader/books/<format>/<sha256>_<byteCount>.<canonical-ext>` (= iOS
    `BlobPath.make`, `booksRoot = "VReader/books"`; the canonical ext, NOT `originalExtension` —
    that travels in the manifest). Content-addressed + deduped + shared across backups.
  - **Backup** publishes each book blob to the blob store **atomically** (PUT to a `.tmp` →
    PROPFIND-verify → MOVE), **PROPFIND-dedupe** so a repeat backup only transfers NEW books;
    then writes the small ZIP. **Restore** reads `library-manifest.json` from the ZIP, then GETs
    each `blobPath` from the blob store and materializes it.
  - `backupId` is an **opaque composite** `serverId + "/" + "VReader/backups/<ts>_<id>.vreader.zip"`
    (Gate-2 Medium-4) so `loadManifest`/`restore` resolve the server + ZIP path without hidden
    state. This is byte-for-byte the iOS layout ⇒ a backup written by Android restores on iOS and
    vice-versa (the #110 contract).
- **Position contract = plain `Locator`, not the `VReaderLocator` envelope** (Gate-2 High-2):
  `BackupPosition.locatorJSON` is a plain `Locator` (the #113 contract). COLLECT encodes
  `VReaderLocator.legacyLocator` (the canonical engine-neutral half) as `Locator` JSON; a Readium
  envelope with a **null `legacyLocator` is a loud per-position failure** (no canonical anchor to
  back up). RESTORE decodes `Locator`, validates it, `VReaderLocator.wrapLegacy(...)`, then saves.
- **Restore order = book first, then position** (Gate-2 Medium-6): `reading_positions
  .fingerprintKey` is an FK to `books`; import/verify/upsert the book, THEN save its position. An
  import failure records that book's position as skipped/failed (never an FK-violating upsert).
- **Book metadata preserved from the manifest** (Gate-2 Medium-2): `BookImporter` derives title
  from the display name + sets `addedAt=now`; after import, verify the computed `fingerprintKey`
  equals the manifest entry, then upsert a corrected `Book` carrying the manifest's
  `title`/`addedAt`/`lastOpenedAt`.
- **`originalExtension`** (Gate-2 Medium-3): Android `Book` doesn't store it → derive from
  `originalFormat` (epub/txt/md/pdf → the obvious ext; Kindle-family → `azw3`); a distinct
  `.mobi`/`.prc` round-trip is a follow-on if Android gains Kindle import.
- **Credential storage** (Gate-2 Low-2): server metadata (URL/user) in **DataStore**; the
  password via a small **Android Keystore AES-GCM** wrapper — NOT `EncryptedSharedPreferences`
  (not a current dep; its AndroidX Security-Crypto APIs are deprecated/problematic).

## Surface area

All new, under `android/app/.../backup/net/` + `.../backup/archive/` + `.../backup/`:

- **`net/WebDavClient.kt`** — `suspend` `propfind(path)` (Depth:1 multistatus → entries),
  `mkcol(path)`, `put(path, bytes)`, `get(path): ByteArray`, `delete(path)`, with Basic auth,
  timeouts, and error mapping: HTTP 401→`auth401`, 404→`notFound404`, `SocketTimeoutException`→
  `timeout`, `IOException`/`UnknownHostException`/`ConnectException`→`offline`. Backed by
  `java.net.HttpURLConnection` (no new dep). **A namespace-aware `XmlPullParser` multistatus
  parser** (Gate-2 Medium-5; NOT string-matching), XXE disabled, collection detected via
  `<resourcetype><collection/>` (not a bare tag), `href` URL-decoded, trailing-slash collections,
  per-resource non-2xx statuses skipped; PROPFIND **follows 301/302/307/308 manually** (HUC
  doesn't auto-follow for non-GET). Depth:1 only.
- **`archive/BackupArchive.kt`** — `BackupArchiveWriter` (writes `metadata.json` +
  `library-manifest.json` + the section JSONs into a ZIP via `java.util.zip.ZipOutputStream` —
  **NO book bytes**; blobs go to the separate blob store) and `BackupArchiveReader` (reads +
  validates: missing metadata → error, unknown future section tolerated, malformed ZIP → error).
  Uses the #113 `BackupJson` + DTOs. `BlobPath.make(format, sha, bytes)` mirrors the iOS path
  builder (`VReader/books/<format>/<sha>_<bytes>.<canonicalExt>`).
- **`LibraryRepository`** — add `listPositions(): List<ReadingPositionRecord>` (Gate-2 Medium-1)
  where `ReadingPositionRecord(fingerprintKey, locator: VReaderLocator, updatedAt: Long)` — the
  collector needs `updatedAt` (for `BackupPosition`) and an all-positions API, not a per-key
  `loadPosition`. (The `reading_positions` row already has `updatedAt`.)
- **`BackupCollector.kt`** — Room books (a one-shot list) + `listPositions` → the contract DTOs
  (the `library-manifest` with each book's `blobPath` = `BlobPath.make(...)` + the positions
  section, with the `legacyLocator`→plain-`Locator` conversion); the small ZIP carries the
  sections + manifest + metadata only. The **blob upload** (each book's bytes → the blob store,
  atomic + PROPFIND-deduped) is driven by `WebDavBackupService` (it needs the client). Fails
  loudly on a missing/unreadable local file or a positionless-Readium envelope (never a
  silently-destructive empty/partial backup).
- **`RestoreImporter.kt`** — read `library-manifest.json` from the ZIP → for each (selected)
  manifest book: **GET its `blobPath` from the blob store** → materialize to a temp file →
  `BookImporter.importStream` (re-fingerprints → canonical identity, idempotent `@Upsert`) →
  **verify the computed `fingerprintKey` == the manifest entry** → upsert a corrected `Book`
  carrying the manifest `title`/`addedAt`/`lastOpenedAt` → THEN save the book's position (decode
  `Locator` → validate → `wrapLegacy` → `savePosition`). Idempotent (same bytes ⇒ same key, no
  dup); a per-book failure (blob 404 / fingerprint mismatch / import error) is collected and its
  position skipped — the others restore. (Takes the `WebDavClient` to fetch blobs.)
- **`WebDavBackupService.kt`** — the real `BackupService` impl:
  - `listBackups` = PROPFIND `VReader/backups/` (Depth:1) for `*.vreader.zip` → GET each (small)
    ZIP → read `metadata.json`.
  - `startBackup` = collect manifest+sections → for each book atomic-PUT its blob to the blob
    store (PROPFIND-dedupe) emitting per-book `BackupProgress` → PUT the ZIP to
    `VReader/backups/<ts>_<id>.vreader.zip`.
  - `loadManifest` = GET the ZIP → parse the manifest.
  - `restore` = GET the ZIP → `RestoreImporter` (which GETs blobs) → emit `RestoreProgress`.
  - `retryBook`; `testConnection` = PROPFIND the root. `backupId` = opaque `serverId/<zipPath>`.
- **`WebDavServerStore.kt`** — saved server profiles: URL/user in **DataStore**, the password via
  a small **Android Keystore AES-GCM** wrapper (Gate-2 Low-2).
- **`AndroidManifest.xml`** (main) — add `android.permission.INTERNET`. **`src/debug/res/xml/
  network_security_config.xml`** + the `src/debug/AndroidManifest.xml` `application` references it
  (Gate-2 Low-1) allowing cleartext **only to `10.0.2.2`**; the main/release manifest sets no
  cleartext config (HTTPS-only).
- **`scripts/run-webdav-roundtrip.sh`** — the verification harness: allocate a port, `rclone
  serve webdav --addr 127.0.0.1:$PORT --user … --pass … <tmpdir>`, wait for readiness, run the
  connected round-trip test with `webdavBaseUrl=http://10.0.2.2:$PORT/`, kill the server by exact
  PID, emit evidence. (Rule 49: server lifecycle owned by the script, killed by exact PID — never
  a `pgrep` waiter.)
- **`AppContainer`** — exposes the real `WebDavBackupService` (still NOT wired into a production
  user path until the #114 UI's production entry exists; the round-trip test + a debug entry
  drive it).

**Files OUT of scope**: annotations/collections/settings/book-sources/per-book/reading-history/
ai-conversations COLLECTION + RESTORE (valid-empty sections only in v1 — Android lacks those
tables); the production Settings entry point (design-gated, #114 note); the iOS side
(unchanged); lazy/selective on-tap download policy beyond the manifest (the #47-style picker is
the UI's; the backend supports `restore(selection)`).

## Prior art / project precedent / rejected alternatives

- **Precedent**: iOS `Services/Backup/*` is the reference shape. #113 DTOs + `BackupJson`
  (`BackupArchive` uses them). #114 `BackupService` is the seam this implements. `BookImporter`
  (the restore importer reuses it for canonical-identity idempotent import). The identity/locator
  conformance lane is the cross-platform contract this round-trips.
- **Rejected — a 3rd-party WebDAV/Sardine lib**: `HttpURLConnection` + a tiny multistatus parser
  covers PROPFIND/PUT/GET/MKCOL/DELETE; no large dep.
- **Rejected — restoring the iOS-only sections in v1**: Android lacks those tables; valid-empty
  is the honest contract slice (Codex).
- **Rejected — weakening release cleartext**: the cleartext-to-10.0.2.2 allowance is `src/debug`
  only; release WebDAV is HTTPS-only.

## Work items (Codex 6-WI decomposition)

| WI | Scope | Tier |
|---|---|---|
| WI-1 | `WebDavClient` (PROPFIND/MKCOL/PUT/GET/DELETE + Basic auth + timeout + `WebDavError` mapping + the namespace-aware `XmlPullParser` multistatus parser, XXE off, manual redirect) + `INTERNET` perm + the `src/debug` cleartext config. JVM tests vs a `com.sun.net.httpserver.HttpServer` fake | foundational |
| WI-2 | `BackupArchive` writer/reader (the `*.vreader.zip` = metadata + section JSONs + manifest, **NO blobs**) + `BlobPath.make` (= the iOS path). JVM tests: round-trip, malformed ZIP, missing metadata, unknown future section, Unicode titles, the ZIP carries no book bytes, `BlobPath` matches the iOS format | foundational |
| WI-3 | `LibraryRepository.listPositions` + `BackupCollector` (books+positions → manifest [w/ `blobPath`] + positions DTOs; `legacyLocator`→plain-`Locator`; fail-loud on missing file or null-legacy Readium envelope). Robolectric tests (in-memory Room) | behavioral |
| WI-4 | `RestoreImporter` (manifest from ZIP → GET each `blobPath` from the blob store → BookImporter → fingerprint-verify → manifest-metadata upsert → THEN position; **idempotent**; partial-failure-tolerant). Robolectric tests (fake `WebDavClient` serving blobs): fresh restore, repeated restore (no dup), partial failure, position restore, book-first-FK order | behavioral |
| WI-5 | `WebDavBackupService` (the real seam impl, opaque `backupId`) + `WebDavServerStore` (DataStore + Keystore AES-GCM). JVM/Robolectric tests with a fake `WebDavClient` | behavioral |
| WI-6 | `scripts/run-webdav-roundtrip.sh` (rclone host server + 10.0.2.2, exact-PID lifecycle) + the connected round-trip test (import a real TXT + real EPUB → backup → wipe → restore → assert books+blobs+positions+title+addedAt) + final acceptance | behavioral (final WI) |

## Test catalogue

- WI-1 `WebDavClientTest` (JVM, `com.sun.net.httpserver.HttpServer` fake): PROPFIND parses a
  multistatus into entries incl. **namespace prefixes** (`D:` / `d:` / a custom prefix),
  `resourcetype/collection` detection, **URL-decoded + trailing-slash** hrefs, a per-resource
  non-2xx entry skipped, a chunked body; PUT/GET round-trips bytes; a **307 redirect** is
  followed; 401→auth401, 404→notFound404, a connect failure→offline, a slow response→timeout;
  MKCOL idempotent (405-on-exists tolerated). XXE: a DOCTYPE/external-entity body does not resolve.
- WI-2 `BackupArchiveTest` (JVM): write→read round-trips `metadata.json` + the section JSONs +
  `library-manifest.json`; **the ZIP carries NO book bytes** (no blob entries — assert the entry
  names are only the JSONs); missing `metadata.json`→error; a truncated ZIP→error; an unknown
  extra section is ignored on read; CJK title. `BlobPathTest`: `BlobPath.make(epub, sha, bytes)`
  == `VReader/books/epub/<sha>_<bytes>.epub` (matches the iOS format; Kindle-family → `azw3`).
- WI-3 `LibraryRepositoryTest` (`listPositions`) + `BackupCollectorTest` (Robolectric, in-memory
  Room + temp book files): collects 2 books + their positions into a manifest + blobs with correct
  content-addressed paths + SHA/byteCount; the position's `locatorJSON` is a plain `Locator`
  (decodes as `Locator`, carries `page`/`charOffsetUTF16`); a missing local file → a loud error;
  a Readium envelope with null `legacyLocator` → a loud per-position failure.
- WI-4 `RestoreImporterTest` (Robolectric): a fresh restore creates the books + files + positions
  (book upserted BEFORE its position — no FK violation); the restored `Book` carries the manifest
  `title`/`addedAt`/`lastOpenedAt` (not the importer's display-name/now); a repeated restore is
  idempotent (same fingerprintKey, no dup, position replaced); one corrupt blob / fingerprint
  mismatch → that book fails + its position skipped, the others restore.
- WI-5 `WebDavBackupServiceTest` (Robolectric + fake `WebDavClient`): `startBackup` emits
  monotonic progress then completes + PUTs the ZIP; `listBackups` parses the dir; `restore`
  drives the importer + emits a terminal result; `testConnection` ok/401.
- WI-6 `BackupRoundTripTest` (**connected**, via `run-webdav-roundtrip.sh`): import a **real TXT +
  a real EPUB** (both exist under `test-books/books/`; a synthetic PDF is acceptable with the
  "no real PDF fixture" exception stated — Gate-2 Low-3), save a position, real backup to the live
  rclone WebDAV at 10.0.2.2, wipe Room + files, restore, assert every book's Room row + local file
  (SHA/byteCount) + format + title + addedAt + reading position. The end-to-end acceptance.

## Risks + mitigations

- **R1 — restore/materialization idempotency (Codex: the biggest risk).** Restore crosses ZIP
  validation → blob materialization → `BookImporter` (canonical fingerprint) → Room upsert →
  position restore. Mitigate: reuse `BookImporter`'s proven idempotent `@Upsert` (same bytes ⇒
  same `fingerprintKey`); WI-4 tests repeated-restore-no-dup + partial-failure explicitly.
- **R2 — cleartext HTTP on Android (API 28+ blocks it).** A `src/debug` network-security config
  allows cleartext **only to 10.0.2.2**; release is HTTPS-only. The round-trip test is debug.
- **R3 — emulator↔host networking.** The emulator reaches the Mac host at `10.0.2.2` (not
  `localhost`); the rclone server binds `127.0.0.1:$PORT` on the host; the test uses
  `http://10.0.2.2:$PORT/`.
- **R4 — server lifecycle (rule 49).** `run-webdav-roundtrip.sh` owns the rclone process, waits
  on readiness (a PROPFIND probe), and kills it by **exact PID** — never a `pgrep` waiter, never
  a detached unbounded capture.
- **R5 — WebDAV server quirks.** Some servers MOVE/return 207/redirect differently; v1 targets
  rclone's WebDAV (the iOS test backend too) + standard verbs; PROPFIND Depth:1 only.

## Backward compat

Additive — a new backend behind the existing #114 seam; no schema change; the UI's
`PreviewBackupService` stays for design/debug. Production wiring of `WebDavBackupService` waits
on the #114 production entry point (design-gated); v1 is verified via the round-trip test + a
debug entry.

## Acceptance criteria

1. `WebDavClient` does PROPFIND/MKCOL/PUT/GET/DELETE with auth + typed errors (JVM-tested).
2. `BackupArchive` round-trips the #113 sections + manifest in the `*.vreader.zip` (NO book
   bytes — blobs live in the separate `VReader/books/...` store); `BlobPath` matches iOS (JVM-tested).
3. `BackupCollector` + `RestoreImporter` produce + consume a backup idempotently (Robolectric).
4. `WebDavBackupService` implements the #114 seam (tested with a fake client).
5. **The connected round-trip** (`run-webdav-roundtrip.sh`): import → backup to a live local
   WebDAV → wipe → restore → every book + blob + position restored exactly. Evidence file.
6. No production user path yet (the #114 production entry is design-gated); release stays
   HTTPS-only (cleartext-to-10.0.2.2 is debug-only); EPUB/TXT/MD/PDF reading unaffected.

## Revision history

- **v1** (2026-06-20) — Gate-1 draft.
- **v2** (2026-06-20) — Gate-2 audit round 1 (Codex). No Critical; all 2 High + 6 Medium + 3 Low
  addressed (model assumptions verified correct):
  - *(High)* archive layout inconsistent → **one collection per backup** (`backups/<id>/
    metadata.json` + `archive.zip`); `listBackups` GETs the small metadata, not every ZIP.
  - *(High)* position `VReaderLocator`↔plain-`Locator` → collect encodes `legacyLocator` as
    `Locator`; null-legacy Readium envelope = loud failure; restore decodes→validates→`wrapLegacy`.
  - *(Medium)* repo can't collect positions → add `listPositions(): List<ReadingPositionRecord>`
    (with `updatedAt`).
  - *(Medium)* book metadata not preserved → after import, fingerprint-verify + upsert a corrected
    `Book` with the manifest's title/addedAt/lastOpenedAt.
  - *(Medium)* `originalExtension` not stored → derive from `originalFormat` (Kindle-family→azw3).
  - *(Medium)* `backupId` lacks serverId → opaque composite `serverId/<id>`.
  - *(Medium)* multistatus parsing → namespace-aware `XmlPullParser` (XXE off), resourcetype/
    collection, URL-decoded hrefs, manual redirects; edge tests added.
  - *(Medium)* restore FK order → book first, then position; import-fail → position skipped.
  - *(Low)* cleartext wiring → `INTERNET` in main + `src/debug` network-security-config; release
    HTTPS-only.
  - *(Low)* credential store → DataStore + Keystore AES-GCM (not deprecated `EncryptedSharedPreferences`).
  - *(Low)* WI-6 uses a real TXT + real EPUB (both in `test-books/`); synthetic PDF with the
    stated exception.
- **v3** (2026-06-20) — Gate-2 audit round 2 (Codex). 2 NEW High (cross-platform interop — the
  v2 layout broke it), both addressed:
  - *(High)* the remote layout must be **byte-for-byte the iOS layout** (verified against
    `WebDAVProvider.swift`/`BlobPath.swift`): backups are single `VReader/backups/<ts>_<id>.vreader.zip`
    files (NOT directories), and book blobs live SEPARATELY in `VReader/books/<format>/<sha>_<bytes>.<ext>`
    (the content-addressed store), NOT inside the ZIP. The ZIP holds metadata + section JSONs +
    manifest only.
  - *(High)* blobs published separately to the blob store (atomic PUT→PROPFIND→MOVE, deduped);
    restore reads the manifest from the ZIP then GETs each `blobPath`. Tests assert the server
    has the blob paths and the ZIP carries no book bytes. This makes Android↔iOS restore actually
    interoperate (the #110 contract).
