---
branch: feat/feature-127-wi-6-collections-backup
threadId: b9jp13ska
rounds: 2
final_verdict: ship-as-is
date: 2026-06-29
---

# Gate-4 audit — feature #127 WI-6 (collections backup + restore)

Adds a `collections.json` section to the Android backup format and restores it. `BackupCollector`
emits a deterministic collections envelope (sorted by `nameKey`, keys filtered-to-backed-up + sorted →
byte-stable); `RestoreImporter` merges by `nameKey` after books (FK holds) via a transactional
`CollectionDao.restoreCollection` + FK-safe `addMembershipIfBookExists`. Files: `CollectionDao.kt`,
`BackupCollector.kt`, `RestoreImporter.kt`, `WebDavBackupService.kt`, `CollectionBackupTest.kt`.

## Round 1 (Codex `b9jp13ska`, gpt-5.5/high) — 1 High, 1 Medium

| file:line | severity | issue | resolution |
|---|---|---|---|
| `RestoreImporter.kt:93` | High | Selective restore / `retryBook` restored the ENTIRE `collections.json`: an unselected-but-locally-existing book would still be added to backed-up collections, and a single-book `retryBook()` could materialize unrelated collections from the archive. | **FIXED** — thread `selection` into `restoreCollections(reader, eligible)`. Full restore (`eligible == null`) restores every collection + membership; a SELECTIVE restore filters each collection's keys to `eligible` and **skips a collection with no eligible member** (so a single-book retry can't create unrelated collections). New test `restore_selective_restoresOnlySelectedMembership_andSkipsUnrelatedCollections`. |
| `RestoreImporter.kt:104` | Medium | `nameKey` was `c.name.lowercase(Locale.ROOT)` but creation uses `name.trim().lowercase(Locale.ROOT)` — a backup name with surrounding whitespace would fail to merge with an existing collection and create a semantic duplicate. | **FIXED** — `name = c.name.trim()` before keying (parity with `CollectionRepository`); skip an all-whitespace (empty-after-trim) name. New test `restore_whitespaceName_mergesWithTrimmedExisting`. |

### Round-1 note (risk, not a finding)

The auditor flagged a *wiring-gap risk*: the collector/service accept a `CollectionDao` but the app
container doesn't yet construct them with it. This is **intentional + correct for WI-6**: the live
Backup UI (#114) uses `PreviewBackupService` (DEBUG-reachable, no real WebDAV wired to the UI yet), so
the only real `WebDavBackupService`/`BackupCollector` construction is the connected round-trip test.
WI-6 makes the collector/importer *capable* (proven by JVM tests + threaded through
`WebDavBackupService`); **WI-7 wires the `CollectionDao` into the connected round-trip and asserts
collections survive end-to-end** (the feature's acceptance gate). The nullable-default keeps every
existing caller compiling and behavior-identical.

## Round 2 (Codex `bs1s31wcf`, gpt-5.5/high) — confirm the fixes

**No findings.** The auditor confirmed: the round-1 High (selective restore now filters each
collection's keys to `selection` and skips collections with no selected member; the DAO only receives
filtered `bookKeys`) and Medium (name trimmed before display/nameKey, empty-after-trim skipped) are
resolved, with no new issue — full-restore behavior unchanged, no dead code.

## Verdict

**ship-as-is.** Two rounds: round 1 (1 High selective-restore scope + 1 Medium whitespace nameKey) →
round 2 clean. Zero open Critical/High/Medium/Low. Tests: CollectionBackupTest 7/0 (collect-determinism,
byte-stability, full round-trip, merge-collision, unknown-key-dropped, selective-scope, whitespace-merge,
absent-section), RestoreImporterTest 7/0 (no regression). The live app-container wiring of the
`CollectionDao` into the real `WebDavBackupService`/`BackupCollector` is WI-7's acceptance (the live UI
uses `PreviewBackupService` today; the only real construction is the connected round-trip test).
