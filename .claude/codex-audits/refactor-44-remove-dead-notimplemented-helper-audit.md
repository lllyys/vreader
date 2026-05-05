---
branch: refactor/44-remove-dead-notimplemented-helper
threadId: manual-fallback
rounds: 1
final_verdict: ship-as-is
date: 2026-05-06
---

## Manual audit evidence

Tiny dead-code removal. Manual audit performed.

### Files read

- `vreader/Services/DebugBridge/RealDebugBridgeContext.swift` (changed) — full file. Was 247 lines, now 240.
- All references to `notImplemented` across `vreader/` and `vreaderTests/` (5 hits — see grep below).

### What was removed

Lines 129–134 (now removed):

```swift
// MARK: - Stubs (filled in by later WI-5 commits)

private func notImplemented(_ command: String) -> Error {
    log.notice("\(command, privacy: .public): not yet implemented")
    return DebugBridgeContextError.notImplemented(command: command)
}
```

Plus the now-orphaned `// MARK:` heading.

### Why dead

- The helper function was added in feature #44 WI-5 as a placeholder for stubbed commands ("filled in by later WI-5 commits").
- All 7 commands (reset, seed, open, theme, settle, snapshot, eval) shipped without ever calling this helper. Each command directly returned a typed error or wrote a sentinel.
- Cross-module grep confirms zero call sites: 5 hits for `notImplemented` are split between the enum case `.notImplemented(command:)` (still used by error-string mapping in `DebugBridge.swift:99` and the test in `DebugBridgeTests.swift:110-111`) and the now-removed helper. The enum case stays — it's still wire-compatible if a future stubbed command needs to be added.

### What I deliberately did NOT change

- `DebugBridgeContextError.notImplemented(command: String)` enum case — still used by error mapping. Removing it would require updating `DebugBridge.swift` and the test. Out of scope.
- `bridge.notImplemented:` error string format — same reasoning.

### Edge cases checked

- **Test impact**: full DebugBridge test suite (38 tests) still passes post-removal.
- **Build impact**: clean build succeeded.
- **LOC impact**: main file 247 → 240 lines (still under 300, criterion (g) preserved).

### Verdict

**ship-as-is**. 7-line dead-code removal. Behavior unchanged. No new abstractions, no risk.
