---
branch: feat/feature-116-wi-4-restore-importer
threadId: 019ee575-wi4
rounds: 3
final_verdict: ship-as-is
date: 2026-06-20
---

# Codex audit — feature #116 WI-4 (RestoreImporter)

Scope: `android/app/.../backup/RestoreImporter.kt` (new), `.../data/BookImporter.kt`
(`expectedKey` verify-before-mutate + `FingerprintMismatch`), `.../backup/net/WebDavClient.kt`
(streaming `getStream`), and the tests. The RESTORE half: blob fetch → import (re-fingerprint) →
identity verify → manifest-metadata restore → position restore, with per-book failure isolation.

## Round 1 — 5 findings (0 Critical / 2 High / 2 Medium / 1 Low)

| file:line | severity | issue | resolution |
|---|---|---|---|
| RestoreImporter.kt (import→verify) | High | `BookImporter.importStream` upserted the computed key BEFORE the verify; on a fingerprint mismatch the rollback could delete a *different* legit pre-existing book (and cascade its position). | FIXED — added `expectedKey` to `importStream`: it verifies the computed key BEFORE any artifact promotion / DB write and throws `FingerprintMismatch`, so a mismatched blob never mutates the library. Restore passes `expectedKey = entry.fingerprintKey` and the rollback block is gone. |
| RestoreImporter.kt:67 | High | `catch (e: Exception)` swallowed `CancellationException`, turning coroutine cancellation into a per-book failure and continuing. | FIXED — `catch (e: CancellationException) { throw e }` before the broad catch. |
| RestoreImporter.kt (restorePosition) | Medium | `runCatching` around the suspend `savePosition` also swallowed `CancellationException`. | FIXED (round 3) — explicit try/catch rethrowing `CancellationException`; other failures degrade to "position skipped". |
| RestoreImporter.kt (blob fetch) | Medium | Blobs were fully buffered in a `ByteArray` before importing → heap spike / OOM risk for large books. | FIXED — added streaming `WebDavClient.getStream` (redirect-follow, error-mapped, the returned stream owns + disconnects the connection); `fetchBlob` is now `suspend (String) -> InputStream` fed straight into the streaming `importStream`. |
| RestoreImporter.kt (rollback delete) | Low | Best-effort file delete ignored failures → potential orphan file. | MOOT — verify-before-mutate removes the rollback path entirely. |

## Round 2 — verify pass

Confirmed findings 1, 2, 4, 5 resolved; `importStream` still closes the input on the
`FingerprintMismatch` early-throw (inside `input.use`) + temp cleanup in `finally`; `getStream`
disconnects on every non-handoff path. **Found finding 3 still open** (runCatching in
`restorePosition` still swallowed cancellation).

## Round 3 — finding 3 fix

Replaced the `runCatching` with explicit try/catch that rethrows `CancellationException` (same
shape as the round-1 loop fix). **All 5 findings resolved.**

Verdict: **ship-as-is.** (7 `RestoreImporterTest` + 9 `WebDavClientTest` [+getStream] + 10
`BookImporterTest` + full `:app` suite green.)
