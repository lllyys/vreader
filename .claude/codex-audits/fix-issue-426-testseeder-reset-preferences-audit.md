---
branch: fix/issue-426-testseeder-reset-preferences
threadId: manual-fallback
rounds: 1
final_verdict: ship-as-is
date: 2026-05-08
---

## Manual audit evidence

Codex MCP returned `stream disconnected before completion: error sending
request for url (https://chatgpt.com/backend-api/codex/responses)` on
two attempts (full + minimal prompt). Falling back to a manual mini-audit
per `/fix-issue` Phase 4f and `.claude/rules/47-feature-workflow.md`'s
manual-fallback procedure.

### Files read

- `vreader/App/TestSeeder.swift` (full file, before + after)
- `vreader/App/VReaderApp.swift` (init() block, TestLaunchConfig struct, TestLaunchConfig.parse, TestLaunchConfig.none)
- `vreader/Services/Backup/BackupSectionDTOs.swift` (BackupSettingsKeys.all)
- `vreaderUITests/Helpers/LaunchHelper.swift` (full file)
- `vreaderTests/App/TestSeederPreferencesTests.swift` (full file)
- `vreaderUITests/Library/OPDSCatalogListTests.swift` (full file, esp. testOPDSEmptyStateWithResetPreferences)

### Symbols / signatures verified

For each subsystem grep'd for `forKey: "..."` / `static let *Key = "..."`
and confirmed presence in `TestSeeder.knownPreferenceKeys`:

| Subsystem | Key constant | In wipe list? |
|---|---|---|
| `LibraryViewModel.sortOrderKey` | `library.sortOrder` | yes |
| `LibraryViewModel.viewModeKey` | `library.viewMode` | yes |
| `ReaderSettingsStore.themeKey` | `readerTheme` | yes |
| `ReaderSettingsStore.typographyKey` | `readerTypography` | yes |
| `ReaderSettingsStore.readingModeKey` | `readerReadingMode` | yes |
| `ReaderSettingsStore.useCustomBackgroundKey` | `readerUseCustomBackground` | yes |
| `ReaderSettingsStore.backgroundOpacityKey` | `readerBackgroundOpacity` | yes |
| `ReaderSettingsStore.epubLayoutKey` | `readerEPUBLayout` | yes |
| `ReaderSettingsStore.autoPageTurnKey` | `readerAutoPageTurn` | yes |
| `ReaderSettingsStore.autoPageTurnIntervalKey` | `readerAutoPageTurnInterval` | yes |
| `ReaderSettingsStore.pageTurnAnimationKey` | `readerPageTurnAnimation` | yes |
| `ReaderSettingsStore.chineseConversionKey` | `readerChineseConversion` | yes |
| `TapZoneConfig.key` | `readerTapZoneConfig` | yes |
| `OPDSCatalogListView.storageKey` | `opds.savedCatalogs` | yes |
| `HTTPTTSSettingsView.configKey` | `httpTTSConfig` | yes |
| `AIConfigurationStore.storageKey` | `com.vreader.ai.configuration` | yes |
| `AIConsentManager.consentKey` | `com.vreader.ai.consentGranted` | yes |
| `AIConsentManager.consentDateKey` | `com.vreader.ai.consentDate` | yes |
| `WebDAVNetworkPolicy.wifiOnlyKey` | `com.vreader.webdav.wifiOnly` | yes |

### Findings

| Severity | File | Issue | Resolution |
|---|---|---|---|
| Low | `vreader/App/TestSeeder.swift::knownPreferenceKeys` | The list covers every concrete key constant in production today, but does NOT cover prefix-based stores: `FeatureFlags.persistenceKeyPrefix = "com.vreader.featureFlags."` (per-flag overrides) and `Sync/ChangeTokenStore.keyPrefix = "ck_changeToken_"` (per-zone CloudKit change tokens). Future tests for #15 (AI chat with feature-flag overrides) or sync-related features may flake similarly. | **Accepted with rationale**: bug #152's stated scope is the explicit-key set that breaks the OPDS / theme / AI / library empty-state tests. Prefix-based wipe is feasible (`UserDefaults.dictionaryRepresentation()` filtered by prefix) but adds surface area beyond the bug's repro. The drift gate `keysListCoversBackupSettingsKeys` catches new backup keys; if a future test needs prefix-based wipe, extend `knownPreferenceKeys` semantics or file a follow-up. Documented in code via the doc-comment on `knownPreferenceKeys`. |

### Edge cases checked

- **Concurrency / read race**: `clearKnownPreferences()` runs synchronously on main BEFORE the seeding `Task.detached`. Production view-init reads (`LibraryViewModel.init` reading `sortOrder`/`viewMode`, `ReaderSettingsStore.init` reading reader keys) happen at view-mount time, which is downstream of `VReaderApp.init()`. The wipe is fully ordered with respect to those reads. **No race**.
- **DEBUG-only gating**: `TestSeeder` is wrapped in `#if DEBUG ... #endif` at file scope; the new symbols inherit it. The `seedResetPreferences` field on `TestLaunchConfig` lives inside the `#if DEBUG` block that wraps the entire struct. The `clearKnownPreferences()` call site in `VReaderApp.init` is inside the `#if DEBUG ... if config.isUITesting ...` block. Release builds: untouched. The `verify-release-no-debugbridge.sh`-class gates are not affected (no new DEBUG-only symbols leaked into Release).
- **Idempotency**: tested via `isIdempotent` — second call is a no-op (`removeObject` is silently safe on absent keys).
- **Test isolation in production**: `clearKnownPreferences(in:)` defaults to `UserDefaults.standard`. Unit tests pass `UserDefaults(suiteName:)` so they don't touch the host's preferences. The default parameter means production callers (only `VReaderApp.init` with the launch flag) hit `.standard`, which is the correct production target.
- **Drift gate symmetry**: `keysListCoversBackupSettingsKeys` is asymmetric — catches "new backup key, not in wipe list" but not "new production key, not in wipe list AND not in backup list." Documented as a known gap; partial protection is better than none.
- **Scope creep**: changes are confined to (1) one new helper + key list in `TestSeeder.swift`, (2) one field + one parse + one wipe call in `VReaderApp.swift`, (3) one parameter in `LaunchHelper.swift`, (4) two new test files. No production behavior change outside the explicit launch flag path. Bugs #150 and #151 unaffected.

### Risks accepted

- Prefix-based UserDefaults stores (FeatureFlags, Sync change tokens) are not wiped. Acceptable for bug #152's repro scope; flagged in code for future extension.

### Tests added

- 8 unit tests in `TestSeederPreferencesTests` — per-subsystem clear, leaves-unrelated-untouched, idempotency, drift gate vs `BackupSettingsKeys.all`. **8/8 passing**, 0.090 s.
- 1 end-to-end XCUITest `OPDSCatalogListTests.testOPDSEmptyStateWithResetPreferences` exercising the production wiring through `--reset-preferences`. Asserts empty-state heading, descriptive copy, and Add Catalog button (queried by label rather than identifier — same iOS 26.4 SwiftUI parent-id propagation pattern as bug #150's `txtReaderContainer`). **1/1 passing**, 12.5 s.
- Full OPDS suite re-run: **5/5 passing**.

## Verdict

**ship-as-is** — manual fallback. One Low finding accepted with rationale (prefix-based stores out of scope for bug #152's repro). No Critical/High/Medium findings. All audited keys are in the wipe list; concurrency and DEBUG gating are correct; the drift gate provides one-direction protection.

Test suite verified GREEN at v3.14.81:

```
TestSeederPreferencesTests:  8/8 passed (0.090 s)
OPDSCatalogListTests:        5/5 passed (43.6 s)
** TEST SUCCEEDED **
```
