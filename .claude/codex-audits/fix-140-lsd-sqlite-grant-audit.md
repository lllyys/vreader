---
branch: fix/140-lsd-sqlite-grant
threadId: manual-fallback
rounds: 1
final_verdict: ship-as-is
date: 2026-05-06
---

## Manual audit evidence

DevTools fix unblocking DebugBridge URL-scheme verification on iOS 26.4. Manual audit performed.

### Files changed

| File | Change |
|---|---|
| `scripts/grant-debug-scheme-approval.sh` | Added SQLite `INSERT OR REPLACE INTO Election (identifier, userElection) VALUES ('vreader-debug', 1)` after the legacy plist write. Glob-discovers the InternalDaemon SQLite path on the device. Replaces the previous "restart simulator" stdout note. |
| `docs/bugs.md` | Updated row #140: Low → Medium → FIXED with verified evidence. Replaces the prior DOCUMENTED state. |
| `dev-docs/verification/artifacts/bug-140-feat31-reader-open-20260506.png` | Screenshot showing war-and-peace open in the reader after running the patched grant script + reset + seed + open. |

### How the fix was found

1. The plist-write approach worked when bug #123 was filed; stopped working after iOS 26.4 (or possibly an earlier 26.x point release).
2. `find` on the device data dir discovered alternate LSD-related paths:
   - `var/db/lsd/com.apple.LaunchServicesAppProtectionStore.plist` (hidden/locked bundles — not relevant to URL schemes)
   - `Containers/Data/InternalDaemon/<id>/Library/Caches/com.apple.LaunchServices.SettingsStore.sql` (Election + LegacyElection tables)
3. Election table was empty. Inserted three candidate rows:
   - `'vreader-debug'` (just the scheme)
   - `'com.vreader.app:vreader-debug'`
   - `'vreader-debug:com.vreader.app'`
4. After simulator restart, `simctl openurl vreader-debug://reset` worked. Removed the two compound keys; only `'vreader-debug'` was needed.
5. `userElection=1` is enough — that's the field that records the user's "Open in <app>?" choice as approve.

### Edge cases checked

- **Glob expansion**: the InternalDaemon UUID changes per simulator and may change between iOS reinstalls. Script globs `${DEVICE_ROOT}/Containers/Data/InternalDaemon/*/Library/Caches/com.apple.LaunchServices.SettingsStore.sql` and uses the first hit. If multiple match, deterministic alphabetical order picks the first. Not an issue in practice (one InternalDaemon per device).
- **Missing SQLite store**: warning message printed; legacy plist remains for older iOS. Script doesn't fail.
- **Existing row** for `vreader-debug`: `INSERT OR REPLACE` overwrites — idempotent.
- **`sqlite3` not available**: the binary ships with macOS by default; if absent, the SQLite write step prints a warning. Plist write still happens.
- **Lock contention**: the SQLite file is normally only written to by `lsd` itself. Direct write while the simulator is running is theoretically risky but worked here without lock errors. The warning path catches sqlite3 failures.
- **Post-restart persistence**: the row survives simulator shutdown + boot. Confirmed by leaving the row in place for the open + seed + snapshot flow that followed the grant.

### What I deliberately did NOT change

- The bash heredoc bumping the version (separate concern).
- `docs/subsystems/debug-bridge.md` — should be updated in a follow-up to document the new SQLite store; out of scope for this fix.
- Bug #123's fix script structure: kept the same flow + variable names so existing callers see the same behavior plus a SQLite step.

### Risks accepted

- Direct SQLite manipulation of `lsd`'s internal store is unsupported. If iOS 27 changes the schema, this script breaks. The risk is bounded: it's a developer-tools script, not user-facing; plist + SQL writes degrade gracefully (warning, not failure) on schema mismatch.
- The InternalDaemon UUID is opaque. If Apple rotates it between iOS versions, the glob still finds it (the parent path is stable).

### Tests added

None. Script-level testing is via end-to-end execution: ran the patched script + verified `simctl openurl` works post-restart. Committing the screenshot artifact captures the verified state.

### Verdict

**ship-as-is**. Real fix for bug #140 (which the prior commit had documented but not solved). Unblocks DebugBridge URL-scheme verification flows on iOS 26.4. Verified end-to-end with screenshot evidence.
