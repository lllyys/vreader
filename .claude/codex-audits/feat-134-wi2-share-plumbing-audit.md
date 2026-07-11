---
branch: feat/134-wi2-share-plumbing
threadId: manual-fallback
rounds: 1
final_verdict: ship-as-is
date: 2026-07-11
---

# Gate-4 audit — feature #134 WI-2 (FileProvider + book-share plumbing)

## Auditor availability

Codex (`scripts/run-codex.sh`, rule 53) was invoked on the full
`git diff origin/main..HEAD` (29,227 bytes) but returned
`ERROR: You've hit your usage limit … try again at 8:21 PM` — a quota
exhaustion, not a transient failure. No verdict was produced. Per
rule 47 "Manual fallback when AI auditor unavailable", this is a
manual audit with recorded evidence. No Codex ghost remained
(`pgrep -x codex` = 0).

## Files read

- `android/app/src/main/kotlin/com/vreader/app/reader/share/BookShareIntent.kt` (new)
- `android/app/src/main/kotlin/com/vreader/app/reader/share/BookFileProvider.kt` (new)
- `android/app/src/main/res/xml/file_paths.xml` (new)
- `android/app/src/main/AndroidManifest.xml` (extended — `<provider>` only)
- `android/app/src/test/kotlin/com/vreader/app/reader/share/BookShareIntentTest.kt` (new)
- `android/app/src/test/kotlin/com/vreader/app/reader/share/BookFileProviderDisplayNameTest.kt` (new)
- Baselines: `data/BookImporter.kt` (fileNameForKey / booksDir), `data/LibraryRepository.kt`
  (`Book` DTO), `identity/.../Identity.kt` (`BookFormat`), `VReaderApp.kt` (booksDir),
  the merged debug manifest under `build/intermediates/merged_manifests/`.

## Symbols / signatures verified against live code

- `Book` DTO fields used: `fingerprintKey`, `title`, `originalFormat: BookFormat`,
  `localFilePath: String?` — all present (`LibraryRepository.kt:19-30`).
- `BookFormat { epub, pdf, txt, md, azw3 }` — exact 5-case enum
  (`identity/.../Identity.kt:11`); both `mimeFor` and `extensionFor` are exhaustive over it.
- Books dir = `File(filesDir, "books")` (`VReaderApp.kt:38`), on-disk name = the sanitized
  fingerprint key (`BookImporter.fileNameForKey`); the FileProvider `<files-path path="books/">`
  and `isInsideBooksDir` both target that dir. `BookImporter` NOT edited (write-set respected).
- `applicationId = "com.vreader.app"` (no `applicationIdSuffix`) → `context.packageName` == the
  manifest `${applicationId}` → authority `com.vreader.app.fileprovider` is consistent between
  code and the merged manifest (verified in `merged_manifests/debug/.../AndroidManifest.xml`:
  `android:name="com.vreader.app.reader.share.BookFileProvider"`,
  `authorities="com.vreader.app.fileprovider"`, `exported="false"`, `grantUriPermissions="true"`,
  `@xml/file_paths`).

## Findings (focus areas from the brief)

### (1) Security — grant scope / path-traversal — PASS
- `file_paths.xml` grants ONLY `<files-path name="books" path="books/"/>` — not all of filesDir.
- Defense in depth: `shareBookFileIntent` calls `isInsideBooksDir` (canonical-path prefix check
  with a trailing `File.separator`, so a sibling like `booksX/` cannot match) BEFORE
  `FileProvider.getUriForFile`, AND catches the provider's `IllegalArgumentException` (thrown for
  any path outside the configured root) → `null`. Test `pathOutsideBooksDir_isRejected_returnsNull`
  proves a real file under `filesDir/` but outside `books/` yields no intent.
- `exported=false` + `grantUriPermissions=true` + `FLAG_GRANT_READ_URI_PERMISSION` + a matching
  `ClipData.newRawUri` (so the grant sticks on receivers that read the clip). Tests
  `setsReadGrantFlag_andMatchingClipData` (flag + ClipData URI == EXTRA_STREAM URI) confirm.
- Canonical-path comparison neutralizes `../` traversal and symlink escapes.

### (2) DISPLAY_NAME override — PASS
- `BookFileProvider.query()` returns non-null `Cursor` (matches the FileProvider platform-type
  supertype), rebuilds the row overriding only `OpenableColumns.DISPLAY_NAME`, preserving all other
  columns/types via `valueAt`. Falls through to the base cursor for an unregistered file.
- `safeDisplayName`: reserved chars `\ / : * ? " < > |` → `_`, control chars dropped, whitespace
  runs collapsed, trimmed of `_`/`.`/space, capped at 120, and `.ifBlank { "book" }` so an
  empty/all-illegal title yields `book.ext` (never a bare `.ext` dotfile). Tests cover
  Unicode/CJK (preserved), illegal-char, all-illegal, and blank titles + every format's extension.
- `displayNameOverride_doesNotRenameOnDiskFile` proves the on-disk file keeps its sanitized-key
  name — only the reported label changes.

### (3) ACTION_SEND per-format MIME + no-crash — PASS
- `mimeFor` exhaustive: epub→application/epub+zip, pdf→application/pdf, txt→text/plain,
  md→text/markdown, azw3→application/vnd.amazon.ebook. Test `perFormatMime_coversEveryBookFormat`.
- `shareBook` guards `ActivityNotFoundException` (no-receiver) → logged no-op, no crash, no invented
  UI (rule 51). `FLAG_ACTIVITY_NEW_TASK` added for launches from a non-Activity Context. Tests
  `shareBook_startActivity_noReceiver_isSilentNoOp` + `shareBook_withMissingFile_isSilentNoOp`.
- Missing/null/deleted local file → `null` intent (silent no-op); tests
  `missingLocalFilePath_returnsNull_noCrash`, `deletedFileRace_returnsNull_noCrash`.

### (4) Write-set / authority — PASS
- No `BookImporter` edit; the sanitized-name convention is only READ (mirrored in test seeding),
  not duplicated in production (production resolves the file via the `Book.localFilePath` seam).
- Authority derived from `context.packageName` matches the manifest exactly.

## Low findings — fixed in this round

- **Comment rot (rule 22):** `mimeFor`'s KDoc said "unknown falls back to a generic binary type,"
  but the `when` is exhaustive over the closed enum (no `else`, no octet-stream fallback). Corrected
  the comment to state exhaustiveness (a new format is a compile error until it gets a MIME). The
  plan's §share-hardening "unknown → octet-stream" is a non-issue: `BookFormat` has no unknown case.
- Tightened `displayNameFor`'s comment to describe the actual filename-match (not "canonical paths").

## Edge cases checked

Path outside books/, sibling `booksX/` false-prefix, `../` traversal (canonical-path defeats),
symlink escape (canonicalPath), null/deleted/unreadable file, no share receiver, non-Activity
context launch, Unicode/CJK title, all-illegal title, blank title, over-long title (120-cap), every
`BookFormat`'s MIME + extension, on-disk file not renamed, Robolectric FileProvider `sCache`
cross-test leak (reset in `@Before`).

## Risks accepted

None. Foundational plumbing; no chrome/UI; write-set respected.

## Tests

Robolectric `BookShareIntentTest` (8) + `BookFileProviderDisplayNameTest` (6) — all green via
`scripts/run-android-tests.sh` (`RUN-ANDROID-TESTS RESULT: SUCCEEDED`).

## Verdict

**ship-as-is.** Zero Critical/High/Medium. The two Low comment-rot items were fixed in this round.
