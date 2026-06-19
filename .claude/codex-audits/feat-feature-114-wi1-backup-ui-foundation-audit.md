---
branch: feat/feature-114-wi1-backup-ui-foundation
threadId: 019ee121-b670-71b3-99ad-f8e7862e279a
rounds: 2
final_verdict: ship-as-is
date: 2026-06-20
---

# Gate-4 implementation audit — feature #114 WI-1 (Android backup/restore UI foundation)

Codex (`scripts/run-codex.sh`, gpt-5.5, read-only) audited the WI-1 foundation (the UI-oriented
service seam + state models + ViewModel; no Compose UI yet): `BackupService.kt`,
`BackupUiState.kt`, `BackupViewModel.kt`, `BackupViewModelTest.kt`.

## Round 1 — 4 Medium (all fixed)

| file:line | severity | issue | resolution |
|---|---|---|---|
| `BackupViewModel.kt` loadBackups | Medium | no request-id guard — a non-cooperatively-cancelled load's terminal `_state.update` could overwrite newer state | **Fixed**: monotonic `loadRequestId`; `ensureActive()` + `requestId == loadRequestId` checked before the terminal write. |
| `BackupViewModel.kt` backUpNow | Medium | no try/finally — a `startBackup` flow that emits then throws leaves the UI stuck in `syncing` | **Fixed**: `try`/`catch(CancellationException→rethrow)`/`catch(Throwable→Toast event)`/`finally(clear syncing)`; reloads only if not failed. |
| `BackupService.kt` TestResult.Fail | Medium | `Fail` carried only a String; the designed server-test states need the exact cause | **Fixed**: `Fail(cause: WebDavError, message: String)` — typed cause. |
| `BackupViewModelTest.kt` | Medium | concurrency tests only proved same-tick double-tap; not the stale-load-cancel rule | **Fixed**: added `loadBackups_staleResult_doesNotOverwriteNewer` (gated load A→B cancels A→B wins) + `backUpNow_whileFirstSuspended_coalesces` (suspended flow, second tap coalesced). |

Clean otherwise (round 1): the seam is UI-shaped (no WebDAV/ZIP/blob leak), one-shot events use
`Channel.BUFFERED + receiveAsFlow`, `viewModelScope` + injected dispatcher correct.

## Round 2 — CLEAN

> "All 4 Medium findings are resolved … Stale load terminal writes are guarded by
> `loadRequestId` plus `ensureActive()`. Backup failures clear `syncing`, emit a toast, rethrow
> cancellation, and skip reload. `TestResult.Fail` now carries typed `WebDavError`. The two
> added gated tests cover stale-load/coalesced-backup behavior." — no new Critical/High/Medium.

## Verdict

**ship-as-is.** 9 JVM `BackupViewModelTest` green (incl. the two deterministic gated
concurrency tests). Foundational WI (service seam + state + VM, no Compose UI / no device) →
unit-only, no device verification (rule 47 tier). The Compose surfaces (`BackupTokens` +
scaffold + `BackupRestoreScreen`) land in WI-2 (where the exact jsx `UI.light`/`UI.dark` token
values are fetched from the design's primitives file).
