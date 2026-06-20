---
branch: feat/feature-116-wi-5b-backup-service
threadId: 019ee5a0-wi5b
rounds: 2
final_verdict: ship-as-is
date: 2026-06-20
---

# Codex audit — feature #116 WI-5b (WebDavBackupService)

Scope: `android/app/.../backup/WebDavBackupService.kt` (new — implements the #114 `BackupService`
seam), `.../backup/net/WebDavClient.kt` (`WebDavTransport` interface + `move` + streaming `putFile`),
`.../backup/RestoreImporter.kt` (suspend progress), and `WebDavBackupServiceTest.kt`.

## Round 1 — 5 findings (0 Critical / 1 High / 3 Medium / 1 Low)

| file:line | severity | issue | resolution |
|---|---|---|---|
| WebDavBackupService (startBackup ZIP) | High | The backup ZIP was published with a direct `PUT` to the final path — a failed/interrupted upload could leave a malformed `*.vreader.zip` listed as a backup. | FIXED — both blobs AND the ZIP publish through `publishAtomically` (`PUT .tmp` → `MOVE`). `listBackups` filters `.vreader.zip`, so a `*.vreader.zip.tmp` is never listed. |
| WebDavBackupService (.tmp) | Medium | A blob `.tmp` was orphaned if `put` succeeded but cancellation / `move` failed before publish. | FIXED — `publishAtomically` wraps in try/finally and deletes the `.tmp` under `withContext(NonCancellable)` on any non-moved exit (incl. cancellation). |
| WebDavBackupService (blob read) | Medium | `File(...).readBytes()` loaded each blob fully into heap → OOM risk for large books. | FIXED — added streaming `WebDavClient.putFile(path, file)` (`setFixedLengthStreamingMode` + buffered copy, handles closed via `use`/`finally`); the service streams blobs. The small ZIP stays in-memory. |
| WebDavBackupService (listBackups) | Medium | `runCatching` around the GET-each-ZIP suppressed `WebDavException` (auth/offline/timeout), so a broken connection became `Ok(emptyList())`. | FIXED — `client.get` is now OUTSIDE `runCatching` (its `WebDavException` escapes to the outer catch → `Error(toUiError)`); only the archive PARSE is tolerated (a corrupt ZIP is skipped). |
| WebDavBackupService (restore) | Low | `trySend` from the non-suspend progress callback could drop per-book progress on a full buffer. | FIXED — `RestoreImporter.restore`'s progress is now `suspend`; the service uses suspending `send`. No existing caller breaks (others omit it / call from a suspend context). |

## Round 2 — verify pass

Codex confirmed all five resolved + no new defects: the `finally` cleanup fires on
`CancellationException` and `NonCancellable` is the right shape; `putFile` closes handles; the
suspend-progress change breaks no caller; `.vreader.zip.tmp` is excluded by the `.vreader.zip`
suffix filter. **No findings.**

Verdict: **ship-as-is.** A full import→backup→wipe→list→restore round-trip (books + positions),
dedupe, and `retryBook` are unit-tested against an in-memory `WebDavTransport`; the LIVE rclone
WebDAV round-trip is WI-6. 6 `WebDavBackupServiceTest` + 7 `RestoreImporterTest` + 9
`WebDavClientTest` + full `:app` suite green.
