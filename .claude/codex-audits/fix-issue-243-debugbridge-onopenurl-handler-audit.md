---
branch: fix/issue-243-debugbridge-onopenurl-handler
threadId: 019df63a-bee5-76e2-b842-f37c3223d0e4
rounds: 3
final_verdict: ship-as-is
date: 2026-05-05
---

# Codex audit log — Bug #123 fix (GH #243)

## Round 1 — initial findings

| File | Line | Severity | Issue | Resolution |
|------|------|----------|-------|------------|
| `scripts/grant-debug-scheme-approval.sh` | 71 | High | `python3 -c` fallback embedded `${PREF}` directly into source string. Crafted UDID could break the literal and inject Python code; also allows path traversal outside the simulator data subtree. | Fixed: replaced `python3 -c "..."` with `python3 - "${PREF}" <<'PY'` heredoc passing the path via `sys.argv[1]`. Added strict UUID validator (`^[0-9A-Fa-f]{8}-...{12}$`) that runs for both user-supplied UDIDs (rejects path traversal, shell metachars, empty input) and as defense-in-depth on simctl output. |
| `scripts/grant-debug-scheme-approval.sh` | 57 | Medium | Script never created `Library/Preferences/` before writing the plist. On a partially initialized simulator, both PlistBuddy and Python fallback would fail and the "fresh simulator" path the script is meant to fix could still exit 2. | Fixed: added `mkdir -p "${PREF_DIR}"` before plist creation. Tested by deleting the plist and re-running — script recreates the file cleanly. |
| `scripts/grant-debug-scheme-approval.sh` | 41 | Medium | With multiple booted simulators, no-arg mode silently picked the first JSON entry — caller may grant approval against the wrong simulator. | Fixed: no-arg mode now collects all booted UDIDs, exits 1 if zero or more than one with the explicit list. Single-booted (the common path) still works. |
| `docs/subsystems/debug-bridge.md` | 318 | Low | Section described prompt as "first time on a given simulator" — overgeneralizes; the persisted plist key shows the real scope is `CoreSimulatorBridge` opening this scheme on this sim. | Fixed: reworded to scope the behavior to `simctl openurl`/`CoreSimulatorBridge` opening `vreader-debug://` on a simulator with no prior approval entry, with explicit note that the plist key documents the scope (other source apps would have their own entries). |
| `docs/bugs.md` | 90 | Low | Bug marked FIXED via helper + docs, but no executable verification gate wires the helper in. Operator must remember to run it. | Fixed: extended `scripts/verify-debug-has-debugbridge.sh` to run a per-booted-simulator approval-plist check on top of the existing bundle-level (bug #121) check. Missing approval → exit 1 with `Run: scripts/grant-debug-scheme-approval.sh <UDID>` hint. No booted sim → NOTE (still exit 0) since the runtime gate can't be exercised without a sim. |

## Round 2 — verification re-pass

After Round 1 fixes:

- The Python heredoc + UUID validation closes the High-severity injection vector. No remaining flow of UDID into a command interpreter without quoting.
- `mkdir -p` is adequate — the script already requires the simulator `data` root to exist; `mkdir -p` creates the missing `Library/Preferences` path beneath it.
- Verifier exit-code semantics are correct: 0 only when both gates pass on all booted simulators; 1 on any missing approval; 0 with NOTE when no simulator is booted (best-effort runtime gate layered on deterministic bundle gate).

One Low finding remained:

| File | Line | Severity | Issue | Resolution |
|------|------|----------|-------|------------|
| `docs/bugs.md` | 87 | Low | Bug #123 detail entry still described the root cause as "the first time a custom URL scheme is opened" — overgeneralizes; should narrow to `simctl openurl`/`CoreSimulatorBridge` to match the subsystem doc. | Fixed: reworded the Root cause line to scope the prompt to `simctl openurl` (running as `CoreSimulatorBridge`) opening `vreader-debug://` on a simulator with no prior approval entry. |

## Round 3 — final pass

Codex confirmed: "Clean. The remaining docs-scope issue is resolved, and I don't see any outstanding findings in the audited files. Final verdict: no remaining issues."

## Manual smoke test summary

| Test | Result |
|------|--------|
| Path traversal (`../etc/passwd`) | Rejected, exit 1 |
| Shell metachars (`abc'"; rm -rf /tmp`) | Rejected, exit 1 |
| Empty UDID | Rejected, exit 1 |
| Valid UUID format, non-existent device | Rejected ("device data dir not found"), exit 1 |
| Valid booted (idempotency) | Granted, exit 0 |
| Fresh-simulator path (deleted plist) | Recreated cleanly, exit 0 |
| Verifier with approval present | Both gates PASS, exit 0 |
| Verifier with approval missing | bug #121 OK, bug #123 PARTIAL, exit 1 with hint |
| Verifier after restoring approval | Both gates PASS, exit 0 |

## Final verdict

**ship-as-is**

The fix correctly addresses bug #123 by:
1. Diagnosing the actual root cause (iOS LaunchServices scheme-approval prompt blocking automated URL delivery), reverting an earlier UNVERIFIED hypothesis about conditional `.onOpenURL` placement.
2. Providing a programmatic workaround (`scripts/grant-debug-scheme-approval.sh`) that pre-grants the approval entry directly to the simulator's plist.
3. Documenting the iOS behavior, plist location, persistence semantics, and grant procedure in `docs/subsystems/debug-bridge.md`.
4. Wiring the bug #123 runtime gate into `scripts/verify-debug-has-debugbridge.sh` so regressions surface automatically.

No Swift code change was needed; the `.onOpenURL` handler at `vreader/App/VReaderApp.swift:225` was confirmed correct by streaming logs after the approval was granted.
