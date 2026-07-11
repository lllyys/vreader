---
branch: feat/128-wi4-fts-schema
threadId: 019f4f26-96d2-7f51-95e2-c647904af5ef
rounds: 1
final_verdict: follow-up-recommended
date: 2026-07-11
---

# Gate-4 Codex audit — feature #128 WI-4 (Room v7 FTS search schema + SearchDao)

Runner: `scripts/run-codex.sh` (gpt-5.6, reasoning=low, read-only sandbox). Raw
output: `.reports/wi4-audit.txt`.

## Verdict: follow-up-recommended

No blocking Room/SQLite defect found. The v6→v7 migration opens successfully and
Room installs the FTS synchronization triggers in its generated `onPostMigrate()`
hook. Both findings below were **fixed in this WI** (they are cheap correctness
hardenings, not deferred follow-ups).

## Findings (all addressed)

- **Medium — `publishBook` did not enforce `state.bookKey == bookKey`.** A caller
  mismatch could publish book A's sections while writing book B's state row (or
  FK-fail if B were absent). **Fixed**: added
  `require(state.bookKey == bookKey)` at the top of `publishBook`
  (`SearchDao.kt`), plus `publishBook_rejectsStateForADifferentBook` (asserts the
  throw + that no partial write happens).

- **Low — completeness treated any unexpected non-null status as settled.** The
  predicate counted only `NULL`/`failed`, so a typo status (`indexing`, `faild`)
  would be silently counted as settled and wrongly complete. **Fixed**: both the
  suspend and the observable completeness queries now use
  `s.status IS NULL OR s.status NOT IN ('indexed', 'skipped_unsupported')`, so any
  non-settled/unknown status holds `indexComplete` open. Added
  `completeness_unexpectedStatus_isTreatedAsUnsettled`.

## Audit by requested area (all confirmed correct)

1. **Migration DDL matches Room's generated v7 schema** — columns, affinities,
   nullability, PKs, FKs, and both `bookKey` indexes match the exported `7.json`
   for `search_sections`, `search_index_state`, `search_sections_staging`, and the
   `search_sections_fts` FTS4/unicode61 content-table. `MIGRATION_6_7` ships the
   base + virtual tables only; Room's generated code creates the four FTS content
   -sync triggers in `onPostMigrate()`, exercised by the `migrate1To7` FTS-MATCH
   test.
2. **`publishBook` is a genuine Room `@Transaction`** — the `bookExists` guard and
   all subsequent writes share the commit, so a committed delete cannot interleave
   between the guard and the inserts; delete/copy/clear/state/author commit or roll
   back together. Author backfill preserves a non-null existing value.
3. **First-hit-per-book cannot be starved** — the distinct-bookKey query applies
   `LIMIT` after `DISTINCT`, so a heavily matching book cannot consume the
   allowance; the per-book second query returns one deterministic first section by
   the unique `(sectionIndex, chunkOrdinal, id)` order. The N+1 shape is a
   performance tradeoff at the 200-book cap, not a correctness defect.
4. **Settled-completeness** — `indexed`/`skipped_unsupported` complete; missing or
   `failed` (and, after the Low fix, any unexpected status) incomplete.
5. **FK CASCADE** — `search_sections`, `search_index_state`, and
   `search_sections_staging` carry direct `ON DELETE CASCADE`; the external-content
   FTS table cannot carry an FK, so its deletion propagates via Room's `BEFORE_DELETE`
   content-sync trigger (covered by the delete-cascade test's FTS-no-longer-matches
   assertion).
6. **No blocking SQL/Room/coroutine issue.** The two-step search is not one
   snapshot transaction, so a concurrent reindex/delete can make a selected book
   disappear before step two; `mapNotNull` safely drops it — acceptable
   eventual-consistency for a search UI (exact counts are not required).
