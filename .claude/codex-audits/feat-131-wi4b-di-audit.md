---
branch: feat/131-wi4b-di
threadId: 019f551c-bb78-7bf2-87c5-118782d04d1b
rounds: 2
final_verdict: ship-as-is
---

# Gate-4 audit — feature #131 WI-4b (Android AppContainer bilingual + AI-config DI wiring)

Independent Codex audit (rule 53 `scripts/run-codex.sh`, `gpt-5.6-sol`, effort=high, read-only sandbox).

## Scope

- `android/app/src/main/kotlin/com/vreader/app/VReaderApp.kt` — `AppContainer` now
  constructs `AiProviderStore` (previously only named in a comment) via an injectable
  `SecretCipher` (production default `KeystoreSecretCipher("vreader.ai.password")`) + an
  injectable `prefsStoreFactory` (default `noBackupFilesDir` Preferences), plus the
  process-singleton bilingual stores + per-session prefetcher/VM/AiSettingsViewModel factories.
- `android/app/src/main/kotlin/com/vreader/app/bilingual/BilingualServices.kt` — new DI holder
  (translation cache store, readiness gate, per-session prefetcher/VM factories; `promptVersion`
  pinned `bilingual-v1|g=paragraph`).
- `android/app/src/test/kotlin/com/vreader/app/AppContainerBilingualWiringTest.kt` — Robolectric
  wiring test (fake cipher, recording prefs factory).

## Round 1 — thread `019f5513-d71a-7340-b078-5787d0960d30`

No Critical or High findings. Production wiring confirmed correct (distinct cipher alias, four
distinct prefs filenames, safe field-init order, correct singleton vs per-session lifetimes,
injectable IO dispatcher, prefetcher default `AiProviderFactory::create`).

- **Medium** — the DataStore-clash test used `assertNotSame` on objects (couldn't catch a
  same-file collision) and omitted `bilingual_per_book.preferences_pb`.
- **Medium** — the default-clientFactory test only called `cachedDirect` (contractually never
  touches `clientFactory`), so it passed with any factory; `assertNotNull(AiProviderFactory)` added
  no coverage.
- **Medium** — `aiSettingsViewModel_observesTheWiredStore` never observed `vm.listState`.
- **Low** — `VReaderApp.kt` grew to 361 lines, over the ~300-line convention.

### Fixes applied

- Added an injectable `prefsStoreFactory` seam to `AppContainer` (default unchanged:
  `File(noBackupFilesDir, fileName)`). The test injects a recording factory and asserts all FOUR
  distinct prefs file names are requested exactly once (real clash detection).
- The default-clientFactory test now drives the REAL resolve path: `prefetch()` with no active
  provider maps to `ChapterTranslationError.ProviderFailed`, proving the real `AiProviderStore` is
  wired and the default `AiProviderFactory::create` seam is in place (a stub store would not reach
  the typed failure). The WI-4a `ChapterTranslationPrefetcherTest` independently covers that
  omitting `clientFactory` selects `AiProviderFactory::create`.
- The AiSettingsViewModel-factory test now subscribes to `vm.listState` (StandardTestDispatcher +
  `Dispatchers.setMain` + `advanceUntilIdle`, the `AiSettingsViewModelTest` precedent) and asserts
  the saved provider appears and is active — proving the factory shares the container's store.
- **Low (file-size) — ACCEPTED with rationale.** The clean fix (an `AppContainer` extension file)
  requires package `com.vreader.app`, i.e. a new production file OUTSIDE this lane's write-set
  (`.../com/vreader/app/bilingual/` only). `VReaderApp.kt` was already ~280 lines as a per-feature
  manual-DI aggregation point; the bilingual LOGIC is extracted into `BilingualServices.kt` (the
  sanctioned holder). The `prefsStoreFactory` refactor also DRY'd the four DataStore blocks. First-
  class extraction of the AppContainer public bilingual surface into a dedicated app-DI file is a
  named follow-up for the orchestrator to weigh.

## Round 2 — thread `019f551c-bb78-7bf2-87c5-118782d04d1b`

**No remaining Critical/High/Medium findings.** Confirmed: all four DataStore names distinct and
each requested once; the production factory still resolves to `File(noBackupFilesDir, fileName)`
(injection does not alter default behavior); the prefetch test exercises the real
`AiProviderStore` resolution path with `AiProviderFactory::create` retained as the default; the
AiSettingsViewModel test actively collects `listState` and verifies the shared provider; singleton
vs per-session lifetimes match the DI graph. All 6 tests pass (0 failures).

## Verdict

**ship-as-is** — zero open Critical/High/Medium after 2 rounds; the one Low (file size) is
accepted with rationale (write-set constraint) and a named follow-up.

## Test evidence

`RUN-ANDROID-TESTS RESULT: SUCCEEDED` — `:app:testDebugUnitTest --tests
com.vreader.app.AppContainerBilingualWiringTest --tests com.vreader.app.VersionWiringTest`
(6 wiring tests + version-wiring smoke, 0 failures).
