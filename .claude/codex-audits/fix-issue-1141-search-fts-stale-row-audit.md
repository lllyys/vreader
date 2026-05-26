---
branch: fix/issue-1141-search-fts-stale-row
threadId: 019e6351-e492-74d0-a426-8cb20a01edd1
rounds: 2
final_verdict: ship-as-is
date: 2026-05-26
---

# Codex audit — Bug #264 / GH #1141 (search driver FTS stale-row stall)

Independent audit (Codex MCP, separate process) of the fix for the DebugBridge
`search` driver stalling when a stale persistent-FTS `search_metadata` row
(empty `segment_base_offsets`) survives `reset`.

Files audited:
- `vreader/Views/Reader/ReaderSearchCoordinator.swift` (4-way persisted-index
  branch + `formatRequiresSegmentOffsets` + `searchIndexDirectoryURL` +
  `wipeSearchIndex(at:)`)
- `vreader/Services/Search/SearchService.swift` (new `markPersistentlyIndexed`)
- `vreader/Services/DebugBridge/RealDebugBridgeContext.swift` (`reset()` wipes FTS)
- `vreaderTests/Views/Reader/ReaderSearchCoordinatorTests.swift` (new)
- `vreaderTests/Services/Search/SearchServiceTests.swift`,
  `vreaderTests/Services/Search/SearchIndexStoreTests.swift` (augmented)

## Round 1 — 1 High + 1 Medium + 1 Low

| # | Severity | Finding | Resolution |
|---|---|---|---|
| 1 | High | The original fix's `shouldReindexStalePersistedRow` was format-agnostic, but `segment_base_offsets` are persisted only for TXT/MD. EPUB/PDF index FTS content with `segmentBaseOffsets: nil`, so a nil-offsets persisted row is NORMAL for them — the fix would re-index every EPUB/PDF book on every reopen. | **Fixed.** `setup()`'s persisted branch is now a 4-way split keyed on `formatRequiresSegmentOffsets(format)` (txt/md only): TXT/MD with offsets → restore; persisted+in-memory → no-op; TXT/MD without offsets → stale → drop + re-index; EPUB/PDF without offsets → `markPersistentlyIndexed` (mark in memory, NO re-index — the FTS content already exists). New `SearchService.markPersistentlyIndexed`. |
| 2 | Medium | The truth-table test only proved a boolean, not production behavior, and didn't cover the format dimension. | **Addressed.** Replaced with a `formatRequiresSegmentOffsets` table (txt/md true; epub/pdf/azw3 false — guards exactly the High regression) + a `SearchService.markPersistentlyIndexed` behavior test + the store precondition (`indexBook` → `isBookIndexed==true && getSegmentBaseOffsets==nil`). Full `setup()` integration coverage needs a store-injection seam — Codex agreed that is a reasonable **follow-up**, not part of this fix. |
| 3 | Low | `wipeSearchIndex(at:)` swallows FS errors; `reset()` logs "wiped" unconditionally. | Accepted as-is for a DEBUG verification reset (best-effort wipe; the product fix already makes the stale-row case self-healing). Noted, not changed — a throwing variant adds ceremony without changing the verification outcome. |

## Round 2 — clean

Codex re-read all files: **no findings.** Confirmed the 4-way split is coherent,
`markPersistentlyIndexed` makes `isIndexed()` honest without re-index, the
in-memory no-op case is correct, and the revised tests cover the contract that
mattered. Residual (not a finding): `setup()` remains un-integration-tested
without an injection seam — a follow-up quality improvement.

## Verification

- Focused gate (UDID-pinned iPhone 17 Pro Sim, `-parallel-testing-enabled NO`):
  `ReaderSearchCoordinatorBug264Tests` + `SearchIndexStoreTests` +
  `SearchServiceTests` — **64 tests, 0 failures**.

## Verdict

**Ship-as-is.** No open Critical/High/Medium after round 2. The product fix
breaks the silent-no-op for stale TXT/MD rows AND fixes EPUB/PDF `isIndexed()`
honesty without wasteful re-indexing; the DEBUG reset now wipes the FTS store
for a true clean slate.
