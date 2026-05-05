---
branch: fix/44-snapshot-schema-version-test
threadId: manual-fallback
rounds: 1
final_verdict: ship-as-is
date: 2026-05-05
---

## Manual audit evidence

Codex MCP not invoked for this trivial test fix. Manual audit performed.

### Files read

- `vreader/Services/DebugBridge/DebugSnapshot.swift` line 63: `static let currentSchemaVersion = 2`.
- `vreaderTests/Services/DebugBridge/RealDebugBridgeContextTests.swift:298` (changed): hardcoded `XCTAssertEqual(snap.schemaVersion, 1)` against the schema-v2-emitting production code.
- `git log --oneline --all -S "currentSchemaVersion" -- vreader/Services/DebugBridge/DebugSnapshot.swift` shows the bump landed in commit 74a5443 (feature #49 WI-1) — the test wasn't updated then.

### What changed

Test assertion changed from a hardcoded `1` to a reference to the production constant `DebugSnapshot.currentSchemaVersion`. Comment notes the history.

```diff
- XCTAssertEqual(snap.schemaVersion, 1)
+ // Stays in sync with `DebugSnapshot.currentSchemaVersion` so a
+ // future bump fails this test loudly. Bumped to 2 by feature #49
+ // WI-1 (commit 74a5443); the test wasn't updated then.
+ XCTAssertEqual(snap.schemaVersion, DebugSnapshot.currentSchemaVersion)
```

### Edge cases checked

- **Why reference the constant instead of hardcoding `2`?** A future schema bump should fail the next-level test (e.g., a schema-migration test asserting decoded behavior on a v1 fixture), not a snapshot-emit test that's just confirming "what we encode matches the constant." Referencing `currentSchemaVersion` here means the test stays correct under a future bump and the developer's attention goes to the schema-migration path, which is where the meaningful breakage would be.
- **Compile-time accessibility**: `DebugSnapshot.currentSchemaVersion` is `static let` with default access (internal), accessible from `vreaderTests` via `@testable import vreader`. Confirmed by clean build.
- **Test count**: 29 → 30 RealDebugBridgeContextTests pass post-change (was 29 passing + 1 failing).

### Tracker update

`docs/features.md` row #44 updated to (1) drop criterion (g) from "VERIFIED gated on" — closed by PR #268 v3.13.22 — and (2) append round 7 noting the LOC-split refactor.

### Verdict

**ship-as-is**. 1-line behavior-preserving test fix matching the actual production constant. No new test infrastructure, no behavior change. Closes 1 of the 19 unrelated test failures noted by feature #44 acceptance criterion (e).
