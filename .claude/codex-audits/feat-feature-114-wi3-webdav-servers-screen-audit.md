---
branch: feat/feature-114-wi3-webdav-servers-screen
threadId: 019ee288-8737-71d2-9016-4fd83d0eba27
rounds: 2
final_verdict: ship-as-is
date: 2026-06-20
---

# Gate-4 implementation audit — feature #114 WI-3 surface A (WebDavServersScreen)

Codex (`scripts/run-codex.sh`, gpt-5.5, read-only) audited the WebDAV servers list (design
surface A from `vreader-backup-webdav.jsx` WebDAVServerList): `WebDavServersScreen.kt`,
`WebDavServersScreenTest.kt`, `BackupColorTest.kt`.

## Round 1 — 1 Medium + 4 Low (all fixed)

| file | severity | issue | resolution |
|---|---|---|---|
| `WebDavServersScreen.kt` | **Medium** | a visible `"☷"` text-glyph placeholder for the server icon (design drift + announced by a11y) | **Fixed**: `Icons.Filled.Storage` (`contentDescription = null`) in the row + empty state. |
| `WebDavServersScreen.kt` | Low | chevron rendered as text `"›"` | **Fixed**: `Icons.AutoMirrored.Filled.KeyboardArrowRight` (decorative). |
| `WebDavServersScreen.kt` | Low | top-bar Add clickable was only the 22dp icon | **Fixed**: a 44dp clickable `Box` wraps the icon. |
| `WebDavServersScreenTest.kt` | Low | missed the populated "Add Server" card-row callback | **Fixed**: `populatedAddRow_invokesOnAdd`. |
| `WebDavServersScreenTest.kt` | Low | status-dot color mapping (incl. `unknown→sec`) untested | **Fixed**: extracted a pure `serverStatusColor(status, tokens)` + JVM `BackupColorTest` (ok/error/unknown, light + dark). |

Clean (round 1): stateless; uses the WI-2 scaffold/tokens; renders empty + populated copy
accurately; preserves the EXACT failure string (`401 — authentication failed`); passes the
server id on row tap.

## Round 2 — CLEAN

> "Material icons used for server/empty-state and chevron. Top-bar Add has a 44dp clickable
> target. Populated Add row callback test added. `serverStatusColor` is pure and covered by JVM
> tests … no new Critical/High/Medium issues."

## Verdict

**ship-as-is.** 7 instrumented `WebDavServersScreenTest` (empty/populated/exact-failure/row-tap/
add-callbacks×3/dark) + 2 JVM `BackupColorTest` green. Behavioral WI — emulator Compose-test
verified. (Surface A of the WI-3 server pair; surface B — `ServerEditSheet` — follows.)
