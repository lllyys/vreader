---
branch: feat/feature-130-wi-3-primitives
threadId: 019f4455-a277-7431-9028-f7e1e783e6e9
rounds: 2
final_verdict: ship-as-is
---

# Gate-4 audit — feature #130 WI-3 (resource primitives)

Auditor: cc-suite runner, gpt-5.5, read-only. Round 1 on thread
`019f4455-a277-7431-9028-f7e1e783e6e9` (a first attempt died on a transient
DNS failure and was retried once after a connectivity check); round 2 as a
fresh focused verification on thread `019f445d-bb17-79a3-b593-54da7395a224`.

## Round 1 — block-recommended

- **High**: sim-lease capacity was check-then-acquire — 3 concurrent
  `acquire test` could all observe `<2` and lease 3 UDIDs. → Fixed
  (`1327ca06`): the whole `held_count → select → acquire → purpose` section
  runs under a select mutex; 6-way race test asserts exactly 2 winners.
- **High**: `held_count` counted dead/PID-reused stale leases — a stale
  verify lease BUSY-blocked verify forever. → live-only counting
  (`_lock_owner_live_matching`); stale dirs stolen by the fresh acquire;
  seeded-stale test.
- **High**: sweep-ghosts snapshot-then-rm could delete a FRESH mid-publish
  lock. → reap revalidates at removal: `*.lock.d` via
  `lock_acquire`+`lock_release` (the helper's serialized steal + grace),
  `*.steal.d` revalidated inline dead-only; two-concurrent-sweepers residual
  explicitly documented; sweep-locks.test.sh (6 cases).
- **High**: check-write-set was fail-OPEN on git-diff errors (bogus base →
  CLEAN). → diff captured first, any git error = `RESULT: ERROR` exit 1.
- **Medium**: no cross-platform gate → `CHECK_LANE_PLATFORM` +
  `code_paths_platform`, both directions rejected, missing classifier fails
  closed. **Medium**: worktree cap check-then-add race → setup mutex; 8-way
  race test asserts exactly 2 created. **Medium**: race/staleness test
  matrix gaps → the above races + stale-lease case added (PID-reuse and
  live-long-held were already pinned at the lib layer in lock.test.sh).
- **Low**: default sibling shape untested → PATH-stubbed pgrep asserts the
  unset-env path invokes `pgrep -x xcodebuild`. **Low**: timeout-sentinel
  leak on abnormal exit → EXIT trap.

## Round 2 — ship-as-is

All nine findings verified resolved with citations; targeted sweep of the
new code (select-mutex trap release paths, live-only counting vs sweeper
revalidation, classifier sourcing, cap-exit trap) found no new
Critical/High. Two Lows, both FIXED post-verdict rather than accepted:
reciprocal android-lane→iOS-paths platform test added; classifier sourcing
guarded so a malformed classifier prints the standard `RESULT: ERROR` line.

## Test evidence

10 suites ALL PASS: lock (17 cases incl. 5×8-process stale race),
reserve-id, deps-check (23), agent-lock, sim-lease (incl. 6-way capacity
race + seeded stale lease), worktree (incl. 8-way cap race),
check-write-set (incl. fail-closed diff, both platform directions, lane
worktree from main cwd, standing codex-audits allowance),
run-tests-watchdog (incl. default-pgrep shape), sweep-locks,
check_audit_debt.
