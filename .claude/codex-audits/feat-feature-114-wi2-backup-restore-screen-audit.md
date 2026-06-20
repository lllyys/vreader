---
branch: feat/feature-114-wi2-backup-restore-screen
threadId: 019ee283-5f8c-71b3-92ab-0be46724f1eb
rounds: 2
final_verdict: ship-as-is
date: 2026-06-20
---

# Gate-4 implementation audit — feature #114 WI-2 (BackupRestoreScreen + tokens + scaffold)

Codex (`scripts/run-codex.sh`, gpt-5.5, read-only) audited the WI-2 diff against the committed
design (`vreader-backup-webdav.jsx` + `vreader-ai-provider-fields.jsx`): `BackupTokens.kt`,
`BackupScaffold.kt`, `BackupRestoreScreen.kt`, `BackupRestoreScreenTest.kt`, +
`src/debug/{PreviewBackupService,BackupDebugActivity}.kt` + the debug manifest.

## Round 1 — 2 Medium + 3 Low (all fixed)

| file:line | severity | issue | resolution |
|---|---|---|---|
| `BackupRestoreScreen.kt` | **Medium** | offline/timeout error copy was generic, not the design's server-specific ("reach Home NAS" / "request to nas.local timed out") | **Fixed**: `errorMeta(cause, server)` renders `reach $name` + `request to $host` (`host = url.substringBefore('/')`). |
| `BackupRestoreScreen.kt` | **Medium** | idle omitted the designed right-side active-server name beside "Available Backups" | **Fixed**: a `SpaceBetween` row renders the server name on the right when idle. |
| `BackupRestoreScreen.kt` | Low | error-CTA `clickable` was after `padding` (only the inner area clickable) | **Fixed**: `clickableRow` before `padding`. |
| `BackupDebugActivity.kt` | Low | debug launcher wired every error CTA to `loadBackups` | **Fixed**: `when (cause)` → auth401 `openServerSettings`, notFound404 `backUpNow`, offline/timeout `loadBackups`. |
| `BackupRestoreScreenTest.kt` | Low | content-smoke only; missed CTA-click routing + 404/timeout CTA | **Fixed**: added `performClick` callback tests (Back-Up-Now fires; Restore passes `b1`; error401 CTA passes the cause) + 404/timeout CTA + server-specific copy assertions. |

Clean (round 1): `BackupTokens` ARGB conversions match the jsx `UI.light`/`UI.dark` exactly;
`BackupRestoreScreen` is genuinely stateless (no `remember`/VM/side-effects); `LocalBackupTokens`
correctly scoped by `BackupSurface`; DEBUG files are `src/debug`-only (no release leak),
`exported=true` acceptable for the adb-only launcher.

## Round 2 — CLEAN

> "Confirmed the Round-1 items are addressed … no remaining Critical/High/Medium issues."

## Verdict

**ship-as-is.** 12 instrumented `BackupRestoreScreenTest` green on emulator-5554 (9 designed
states incl. dark + 3 CTA-routing tests); emulator-verified visually light + dark
(`feature-114-wi2-backup-restore-{idle,dark}-20260620.png`). Behavioral WI — emulator
Compose-test verified (rule 47 Gate-5 tier).
