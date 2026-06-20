---
branch: feat/feature-116-wi-3-backup-collector
threadId: 019ee560-wi3
rounds: 2
final_verdict: ship-as-is
date: 2026-06-20
---

# Codex audit — feature #116 WI-3 (BackupCollector + listBooks/listPositions)

Scope: `android/app/.../backup/BackupCollector.kt`, `.../data/LibraryRepository.kt`
(+`ReadingPositionRecord`, `listBooks`, `listPositions`), `.../data/Daos.kt`
(backup `getAll()` queries), and `BackupCollectorTest.kt`. Turns the Room library +
positions into the #113 manifest + positions DTOs and the blob-upload list.

## Round 1 — 4 findings (0 Critical / 0 High / 2 Medium / 2 Low)

| file:line | severity | issue | resolution |
|---|---|---|---|
| BackupCollector.kt | Medium | `listBooks()` + `listPositions()` are two independent snapshots — a book+position inserted between them could put a position in `positions.json` whose book is absent from the manifest (dangling reference). | FIXED — positions are filtered to `collectedKeys` (the collected book fingerprintKeys) before encoding, so every `positions.json` row has a matching manifest entry. |
| BackupCollector.kt | Medium | The default `fileChecker` accepted any existing readable path incl. a directory — a "book" with no regular file could enter the manifest/blob list. | FIXED — default is now `File.isFile && canRead()`. New test: a book pointing at a real directory fails loudly; a regular file collects. |
| Daos.kt (ReadingPositionDao.getAll) | Low | No `ORDER BY` → `positions.json` array order is DB-plan-dependent, breaking repeat-backup determinism. | FIXED — `ORDER BY fingerprintKey`. |
| Daos.kt (BookDao.getAll) | Low | Ordered by `addedAt DESC` (library-display order), not the iOS manifest's `fingerprintKey` order; ties nondeterministic. | FIXED — backup `getAll()` now `ORDER BY fingerprintKey` (byte-stable manifest). |

No findings on the plain-`Locator` extraction, null-legacy loud failure, `lastOpenedAt`
mapping, `totalSizeBytes`, or the whole-envelope `listPositions` decode (match the contract).

## Round 2 — verify pass

Codex confirmed all four resolved: positions filtered to collected keys (valid positions
retained, dangling refs impossible); `isFile && canRead` rejects directories; both backup
queries ordered by `fingerprintKey` (manifest + positions consistently ordered); no
null-safety regression (missing localFilePath + missing legacy locator still fail loudly,
nullable `lastOpenedAt` intentional). **No findings.**

Verdict: **ship-as-is.** (6 JVM `BackupCollectorTest` + full `:app` + `:identity` suites green.)
