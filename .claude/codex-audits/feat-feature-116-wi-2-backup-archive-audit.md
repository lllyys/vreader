---
branch: feat/feature-116-wi-2-backup-archive
threadId: 019ee54e-wi2
rounds: 2
final_verdict: ship-as-is
date: 2026-06-20
---

# Codex audit — feature #116 WI-2 (BlobPath + BackupArchive)

Scope: `android/app/.../backup/archive/BlobPath.kt`, `.../archive/BackupArchive.kt`, and
`BackupArchiveTest.kt`. The content-addressed blob path (iOS-layout parity) + the
`*.vreader.zip` writer/reader (metadata + section JSONs + manifest, NO book bytes).

## Round 1 — 3 findings (0 Critical / 1 High / 2 Medium / 0 Low)

| file:line | severity | issue | resolution |
|---|---|---|---|
| BackupArchive.kt (reader) | High | Unbounded `zin.readBytes()` → large-entry / ZIP-bomb OOM from an attacker-controlled archive. | FIXED — `readBounded()` streams each entry in 64KB chunks with a hard cap = `minOf(MAX_ENTRY_BYTES 64MB, remaining of MAX_TOTAL_BYTES 256MB)`; exceeding throws `BackupArchiveException`. Far above any real blob-less backup. |
| BackupArchive.kt (reader) | Medium | Duplicate ZIP entry names silently overwrote (a crafted archive with two `metadata.json`/`library-manifest.json` → ambiguous, last-wins). | FIXED — `if (out.containsKey(entry.name)) throw BackupArchiveException(...)` before insert. `BackupArchiveException` is caught + re-thrown ahead of the generic `Exception` so it isn't masked as "not a readable ZIP". Test builds a real dup-entry ZIP via equal-length byte rename. |
| BlobPath.kt (parse) | Medium | `parse()` required an extension but never checked it equals the format's canonical ext, accepting `books/epub/<sha>_10.pdf` / `books/azw3/<sha>_10.mobi` — weakening the AZW3 canonical-ext collapse. | FIXED — `if (filename.substring(dot + 1) != format.name) return null`. Tests assert ext≠format and azw3-dir-with-.mobi are rejected. |

## Round 2 — verify pass

Codex confirmed all three resolved and checked for new defects: bounded-read cap math
(`minOf`) allows a legitimate multi-section backup up to the 256MB aggregate and accepts
exact-cap entries with no off-by-one; the `BackupArchiveException`-before-`Exception` catch
order does not swallow the dup/size failures; `BlobPath.parse` ext check exact. **No findings.**

Verdict: **ship-as-is.** (11 JVM `BackupArchiveTest` + full `:app:testDebugUnitTest` green.)
