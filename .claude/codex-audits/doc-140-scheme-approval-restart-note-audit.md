---
branch: doc/140-scheme-approval-restart-note
threadId: manual-fallback
rounds: 1
final_verdict: ship-as-is
date: 2026-05-06
---

## Manual audit evidence

7-line documentation addition + tracker row. Manual audit performed.

### Files changed

| File | Change |
|---|---|
| `scripts/grant-debug-scheme-approval.sh` | Appended a NOTE block at script-end stdout instructing the user to restart the simulator if openurl returns 115. |
| `docs/bugs.md` | New row #140 (DOCUMENTED, Low, GH: #300). |

### Why this is just documentation

The proper fix (auto-detect + auto-restart, or find a daemon-refresh approach) requires more investigation. This iteration just makes the gap discoverable to the developer who hits it.

### Edge cases checked

- **Script's exit codes**: unchanged. Documentation is appended after the existing successful-grant message; doesn't affect failure paths.
- **`${UDID}` interpolation in the new echo block**: the variable is already validated upstream as a UUID (the existing UUID-validation check). Safe to re-use.
- **No production code touched**: 0 risk to the app.

### Verdict

**ship-as-is**. 8-line stdout note. Closes the discoverability gap that was tripping me up just now.
