---
branch: feat/feature-129-wi-1-settings-store
threadId: bfp4j84th
rounds: 1
final_verdict: ship-as-is
date: 2026-06-29
---

# Gate-4 audit — feature #129 WI-1 (reader settings store + 5 themes, foundational)

WI-1 adds the device-local reader display-settings foundation: `ReaderTheme` (5 themes, exact design
RGB + `isDark`), `ReaderSettings` (value type + ranges/clamp helpers — no layout), `ReaderSettingsStore`
(DataStore JSON-in-Preferences, the OpdsSourceStore/AiProviderStore precedent), and the VReaderApp DI
singleton. Tests: `ReaderSettingsStoreTest`, `ReaderThemeTest` (JVM/Robolectric).

## Round 1 (Codex `bfp4j84th`, gpt-5.5/high) — 1 Medium, 2 Low

| file:line | severity | issue | resolution |
|---|---|---|---|
| `VReaderApp.kt` (DI) | Medium | The DataStore file under `filesDir` is eligible for **Android Auto Backup**, violating the WI-1 "device-local, NOT backed up" contract. | **FIXED** — moved the file to `appContext.noBackupFilesDir` (excluded from Auto Backup), matching the device-local contract (iOS keeps reader settings in UserDefaults, also out of the backup). |
| `ReaderSettingsStore.kt:45` | Low | Writes clamped only the field being set, so a previously hand-edited/older out-of-range numeric field would survive an unrelated setter — not truly "clamped on write." | **FIXED** — `update` now `.normalized()`s ALL numeric fields before encoding, so any stale out-of-range value is healed on the next write. |
| `ReaderSettings.kt:36` | Low | `Float.coerceIn` does not sanitize `NaN`/±Inf — a non-finite setter input could reach JSON encoding and fail. | **FIXED** — the clamp helpers are now total: a non-finite input falls back to the field default before coercing. New test `clamp_sanitizesNonFinite`. |

The auditor confirmed: no DataStore single-instance-per-file hazard (the store is a lazy process
singleton; no second factory for the same file), no Flow-concurrency issue, no dead code.

## Verdict

**ship-as-is.** One round, 1 Medium + 2 Low — all fixed. Tests green (ReaderSettingsStoreTest 5/0 incl.
the new NaN case, ReaderThemeTest 3/0). Foundational WI — no device verification required (Gate-5a: unit
tests + audit sufficient for a DTO/store with no user-observable behavior yet).
