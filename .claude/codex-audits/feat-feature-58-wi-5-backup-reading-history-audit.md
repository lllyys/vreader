---
branch: feat/feature-58-wi-5-backup-reading-history
threadId: 019e40db-fca3-7ad1-bf46-eaee4a77a6f6
rounds: 2
final_verdict: ship-as-is
date: 2026-05-19
---

# Gate 4 — Implementation Audit: feature #58 WI-5 (WebDAV backup reading-history section)

Codex MCP (read-only sandbox), thread `019e40db-fca3-7ad1-bf46-eaee4a77a6f6`.
Author/auditor separation per rule 48: Codex is a separate process.

Changed production files:
- `vreader/Services/Backup/BackupReadingHistory.swift` (NEW) — section DTOs
- `vreader/Services/Backup/BackupSectionDTOs.swift` (MODIFIED) — `kBackupCurrentSchemaVersion` 1→2, `kBackupAcceptedSchemaVersions` {1,2}
- `vreader/Services/Backup/BackupDataRestorer.swift` (MODIFIED) — accepted-set validation + `restoreReadingHistory`
- `vreader/Services/Backup/BackupDataCollector.swift` (MODIFIED) — `collectReadingHistory`
- `vreader/Services/Backup/WebDAVProvider.swift` (MODIFIED) — protocol additions + default impls, collect tuple + restore loop
- `vreader/Services/PersistenceActor+ReadingHistory.swift` (NEW) — `restoreReadingHistory` upsert
- `docs/architecture.md` (doc-sync)
- `vreaderTests/Services/Backup/BackupReadingHistoryTests.swift` (NEW)
- `vreaderTests/Services/Backup/BackupDataCollectorRestorerTests.swift` (MODIFIED — schema-version test updated for the v2 bump)

## Round 1 — findings (0 Critical / 1 High / 1 Medium / 1 Low)

| # | Severity | Issue | Resolution |
|---|---|---|---|
| 1 | High | `collectReadingHistory` used `try? ?? []` for the persistence fetches — a read failure would silently emit an empty `reading-history.json`, discarding the user's entire reading history on the next restore. | **Fixed.** Removed the `try?` fallbacks; both fetches are `try await`, so a failure propagates and fails `WebDAVProvider.backup()` loudly. (The collector consumes a concrete `PersistenceActor`, so a deterministic failure-path test would need a new protocol seam — out of WI-5 scope; Codex agreed this is not a blocker.) |
| 2 | Medium | The suite never exercised `startLocatorJSON`/`endLocatorJSON` (the F2 shape change) nor the malformed-locator degradation path. | **Fixed.** Added `restoreRoundTripPreservesStartAndEndLocators` and `malformedLocatorJSONDegradesToNilSessionStillRestores`. |
| 3 | Low | F9 was only partially asserted — `lastReadAt`-not-recomputed was tested, but the other `ReadingStats` scalars weren't verified verbatim. | **Fixed.** Added `restoreReproducesEveryReadingStatsScalarVerbatim` — seeds all scalars with non-default values, asserts verbatim after restore AND after a second restore. |

Round-1 confirmation: `decodeAndValidate` correctly accepts v1 + v2 and rejects
v3+ via `kBackupAcceptedSchemaVersions`. `collectReadingHistory` carries every
persisted `ReadingSession` field (pagesRead, wordsRead, deviceId, isRecovered,
locator JSON strings). `restoreReadingHistory` uses the correct idempotent
upsert keyed by both `@Attribute(.unique)` columns and does NOT call
`recomputeStats` (F9). A v1 archive without `reading-history.json` restores
cleanly (WebDAVProvider's per-section `try?` extraction). The protocol default
impls are correct and keep existing mock collectors/restorers source-compatible.

Note from Codex: the accepted-set logic covers the seven metadata sections
restored through `BackupDataRestorer`; `library-manifest.json` keeps its literal
`schemaVersion: 1` on its own decode path (unchanged, intentional per the plan).

## Round 2 — verification

Codex confirmed all three findings resolved, zero open findings at any severity,
and explicitly agreed the failure-path test seam is not a merge gate for WI-5.
The implementing session ran the gate: **16 tests in `BackupReadingHistoryTests`
pass**; the updated `BackupCollectorRestorerSuite` schema test passes.

## Verdict

**ship-as-is** (round 2). 0 open Critical/High/Medium/Low findings after 2
rounds (rule-47 max is 3). WI-5 is a BEHAVIORAL WI (changes backup format) —
Gate 5a requires a slice verification, recorded in the PR description.
