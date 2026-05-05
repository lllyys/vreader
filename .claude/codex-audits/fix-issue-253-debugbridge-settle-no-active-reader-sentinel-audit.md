---
branch: fix/issue-253-debugbridge-settle-no-active-reader-sentinel
threadId: 019df733-a4fa-7ff3-9d93-de2e8d1c6a6a
rounds: 2
final_verdict: ship-as-is
date: 2026-05-05
---

# Codex audit log — Bug #125 fix (GH #253)

## Round 1 — initial findings

| File | Line | Severity | Issue | Resolution |
|------|------|----------|-------|------------|
| `docs/subsystems/debug-bridge.md` | 175 | Low | The DebugBridge doc still claimed `bridge.noActiveReader` covers both `settle` and `eval`, and the `ready-<token>.json` error-value table at line 184 only listed `"settle timeout"`. After this fix, URL-driven `settle` no longer fails through `DebugBridge.lastError` for the no-probe case; it succeeds by writing the sentinel file with `error: "no active reader"`. The documentation gap left verification consumers pinning on the wrong surface. | Fixed: stable-error table now scopes `bridge.noActiveReader` to `eval` only with a "see below" cross-reference; `ready-<token>.json` error-values table now lists `"no active reader"` with `phase: "unknown"` and notes probe-shaped field absence; new paragraph explicitly states settle reports via the sentinel, not `lastError`, and harnesses must poll the file regardless of reader state. |

## Round 2 — verification re-pass

Codex confirmed:

> Final verdict: clean. The implementation matches the intended contract change, the test covers the regression surface that matters, and the documentation gap is now closed. `settle` without an active reader is correctly observable via `ready-<token>.json`, while infrastructure failures still throw, and I don't see a caller-compatibility problem in the current bridge flow.

## Final verdict

**ship-as-is**

The fix:
- `RealDebugBridgeContext.settleWithTimeout` writes `ready-<token>.json` with `error: "no active reader"` and `phase: "unknown"` (mirroring the existing timeout-path payload shape) when no probe is registered, and returns without throwing.
- Sentinel-writing factored into a private `writeReadySentinel(token:probe:error:)` helper shared between the no-probe and with-probe-result paths.
- Probe-shaped fields (`fingerprintKey`, `format`, `position`) are only included when a probe is registered; absent on the no-active-reader path, matching `DebugSnapshot`'s "field is partial / unavailable" convention.
- Header comment + subsystem doc both updated to document the new contract.
- Existing test that asserted the old throw contract (`test_settle_withoutActiveReader_throwsNoActiveReader`) replaced by `test_settle_withoutActiveReader_writesNoActiveReaderSentinelButDoesNotThrow`. RED→GREEN proven against pre-fix code.

Pre-existing test failure (`test_snapshot_withoutActiveReader_listsReaderFieldsAsPartial` asserts `schemaVersion == 1`, actual 2) is orthogonal to this fix and exists unchanged on main.

Backwards compat:
- `func settle(token: String) async throws` still throws — but only on infrastructure failures (file-write errors). The throw surface is narrower than before.
- `DebugBridge.dispatch` wraps in try-catch and stores `lastError`. The dispatch flow still works; for the no-probe `settle` path, `lastError` stays nil (the sentinel file is the observable surface, mirroring eval).
- `bridge.noActiveReader` stable error string remains in `stableErrorMessage` for `eval`'s noActiveReader path. Not dead.
