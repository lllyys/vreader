---
branch: feat/feature-54-wi-5-remove-readingmode-field-v2
threadId: 019e3e07-65fb-7591-b73e-bf194ae435f7
rounds: 2
final_verdict: ship-as-is
date: 2026-05-19
---

# Codex audit — feature #54 WI-5 (retire ReadingMode field/key + one-shot migration)

Gate-4 implementation audit of commit `2334c79` (parent `fd96f93`), plus the
follow-up working-tree edits applied to resolve round-1 findings.

## Scope audited

WI-5 — the field/key-removal slice of feature #54:

- Deleted `vreader/Models/ReadingMode.swift` (the `ReadingMode` enum) + its test file.
- `ReaderSettingsStore`: dropped `readingModeKey`, the `readingMode` property +
  didSet, `loadReadingMode`, and the lines in init / reconcileFromDefaults /
  applyResolvedSettings.
- `PerBookSettings`: dropped `readingMode` from `PerBookSettingsOverride` and
  `ResolvedSettings`, and from both `resolve()` branches.
- `BackupSettingsKeys.all` + `TestSeeder.knownPreferenceKeys`: dropped the
  retired `readerReadingMode` UserDefaults key.
- `VReaderApp`: calls `ReadingModeMigration.run(...)` synchronously at launch.
- Test files updated; new backward-compat tolerance tests added.

## Round 1 — findings

**Medium — `BackupDataCollectorRestorerTests.swift` `settingsRestore_oldBackupWithReadingMode_doesNotCrash`**
The test built its fixture through the *new* `collector.collectSettings()`,
which can no longer emit `readerReadingMode` (WI-5 removed it from
`BackupSettingsKeys.all`). So the backward-compat restore path
(`BackupDataRestorer.restoreSettings` replaying a stale key) was never
exercised — the test only proved new backups omit the key.

**Low — `docs/architecture.md` reader-dispatcher section**
Stale parenthetical still said the `readerReadingMode` key + `ReadingMode`
enum "are removed in a later feature-#54 work item." WI-5 *is* that work item;
the doc missed the required docs-sync.

No production-code correctness bugs found. Codex confirmed: `PerBookSettingsOverride`
uses synthesized `Codable` with no custom `CodingKeys`/`init(from:)`, so an
older per-book JSON file carrying a stray `readingMode` key decodes harmlessly;
old backup settings payloads remain tolerated because `restoreSettings` iterates
a `[String: BackupDefaultsValue]` dictionary; the synchronous migration call in
`VReaderApp` is correctly placed before `ContentView` / `ReaderSettingsStore`
creation and before `DebugBridge`, using the valid static
`ReaderContainerView.perBookSettingsBaseURL`. Tree-wide grep found no live
production references to the deleted type or removed properties/keys.

## Round 1 fixes applied

- **Medium**: rewrote `settingsRestore_oldBackupWithReadingMode_doesNotCrash` to
  hand-build a pre-#54 `BackupSettingsEnvelope` (`defaults` dict containing
  `readerReadingMode: .string("unified")`), encode it, and feed it straight to
  `BackupDataRestorer.restoreSettings`. The test now asserts the restore does
  not throw and that the retired key faithfully lands in UserDefaults — proving
  the restorer tolerates the stale key (`ReadingModeMigration` is what clears
  it on next launch). Verified: both WI-5 backup tests pass
  (`settingsKeys_doNotIncludeRetiredReadingModeKey()`,
  `settingsRestore_oldBackupWithReadingMode_doesNotCrash()`).
- **Low**: updated the `docs/architecture.md` dispatcher paragraph to state the
  key + enum are already removed and that `ReadingModeMigration` (run
  synchronously at launch from `VReaderApp`) handles the retired persisted state.

## Round 2 — re-verification

Codex re-reviewed both edits. Verdict: no remaining Critical/High/Medium
findings. The Medium is genuinely resolved (the test now drives the real
`restoreSettings` orphan-key path); the Low doc claim is now accurate.

## Final verdict

**ship-as-is** — zero open Critical/High/Medium findings after 2 rounds.
