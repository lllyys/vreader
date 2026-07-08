---
branch: feat/feature-130-wi-1-hygiene
threadId: 019f4237-4852-7853-923b-3dc82ed74c74
rounds: 3
final_verdict: ship-as-is
---

# Gate-4 audit — feature #130 WI-1 (hygiene)

Auditor: cc-suite runner, gpt-5.5 / high effort, read-only sandbox.
Scope: full `main...HEAD` diff — skills single-sourcing, command stubs, agent
contracts, `check_audit_debt.sh` scan window, `scripts/lib/lock.sh` +
`scripts/reserve-id.sh` + their test suites.

## Round 1 — block-recommended

- **High**: stale-lock stealing not atomic — two contenders could both judge
  the owner stale; the slower one `rm -rf`'d the winner's FRESH lock (mutual
  exclusion break; empirically reproduced: 2 winners in 4/5 race rounds).
  → Fixed (commit `176c280f`): steal serialized behind `<dir>.steal.d` mutex
  with staleness re-validated while holding it.
- **Medium**: `lock_release` authorized by pid only (PID-reuse deletion)
  → start-time verified when pid alive; dead recorded pid stays releasable.
- **Medium**: hook `cd` could kill the Stop hook under `set -e` → guarded
  `|| exit 0`. **Medium**: audit-artifact lookup used `$PROJECT_DIR` not
  `$REPO_ROOT` → fixed. **Lows**: stale-race test coverage, origin/main
  fetch coverage, literal `xcodebuild test` in prose → all fixed.

## Round 2 — block-recommended

- **High**: torn-owner window wider than empty-file — `pid=` line landed
  before `start=` was computed; a live-pid/no-start record read as stealable.
  → Fixed (commit `cca898d8`): atomic publish (`owner.tmp.$$` + `mv -f`);
  live-pid/no-start records conservatively LIVE.
- **High**: waiter-side reaping of a dead stealer's mutex re-opened the
  non-holder-rm race one level down. → Fixed: inline mutex reaping removed
  entirely; no non-holder removes anything; sweep-ghosts (WI-3) is the
  single reaper; acquire fails fast (exit 2 + stderr pointer) meanwhile.
- **Low**: targeted tests for both paths → added (16-case suite).

## Round 3 — ship-as-is

Both R2 Highs verified resolved; same-dir rename confirmed the right
APFS/POSIX atomicity primitive; bash-3.2 compatible by inspection.

- **Low**: `_lock_publish_owner` failure ignored (acquire could return 0
  holding an ownerless, later-stealable lock). → Fixed post-verdict rather
  than accepted: publish checked on both the lock and the steal mutex, own
  dir removed on failure, + fault-injection test (case 17).

## Test evidence

`scripts/__tests__/lock.test.sh` (17 cases: contention, no-TTL-steal,
dead-pid + PID-reuse steal, 8-way fresh race, 5×8-process stale race with
holding winners, partial-record conservatism, dead-steal-mutex safety,
publish-failure fault path), `scripts/__tests__/reserve-id.test.sh`
(seeding, monotonicity, manual-row reconcile, 10-way race, kind isolation),
`.claude/hooks/__tests__/check_audit_debt.test.sh` (7-merge batch,
audited-branch exclusion, tagless floor, tag-at-HEAD zero-since, no-remote,
origin-only merge) — ALL PASS.
