---
branch: refactor/44-debug-bridge-loc-split
threadId: manual-fallback
rounds: 1
final_verdict: ship-as-is
date: 2026-05-05
---

## Manual audit evidence

Codex MCP not invoked for this pure-refactor change. Manual audit performed
across the 8 dimensions defined in `/fix-issue` Phase 4b.

### Files read

- `vreader/Services/DebugBridge/RealDebugBridgeContext.swift` (changed) — was 506 lines (491 + 15 of bug-#125 changes), now 247 lines.
- `vreader/Services/DebugBridge/RealDebugBridgeContext+Settle.swift` (new) — 137 lines.
- `vreader/Services/DebugBridge/RealDebugBridgeContext+Snapshot.swift` (new) — 91 lines.
- `vreader/Services/DebugBridge/RealDebugBridgeContext+Eval.swift` (new) — 106 lines.
- Test file: `vreaderTests/Services/DebugBridge/RealDebugBridgeContextTests.swift` — unchanged, exercised against split.

### What moved

| Symbol | From → To | Access change |
|---|---|---|
| `settle(token:)` | main → +Settle | unchanged (`func`) |
| `settleWithTimeout(token:timeoutSeconds:)` | main → +Settle | unchanged (`func`) |
| `writeReadySentinel(...)` | main → +Settle | `private` → `fileprivate` (still file-scoped within +Settle) |
| `withTimeout(seconds:operation:)` | main → +Settle | `private` → `fileprivate`; renamed to `withSettleTimeout` to disambiguate from any future +Eval/+Snapshot helpers |
| `SettleTimeoutSentinel` enum | main → +Settle | `private enum` → `fileprivate enum` (top-level in +Settle) |
| `settleTimeoutSeconds` | main → +Settle | `static let` → `static var ... { 30.0 }` (computed; semantically identical) |
| `snapshot(dest:lastErrorMessage:)` | main → +Snapshot | unchanged (`func`) |
| `snapshotsDirectory()` (static) | main → +Snapshot | unchanged (default `internal`) |
| `themeName(from:)` | main → +Snapshot | `private` → `fileprivate` |
| `totalHighlightCount()` | main → +Snapshot | `private` → `fileprivate` |
| `eval(bridge:js:)` | main → +Eval | unchanged (`func`) |
| `writeEvalError(...)` (static) | main → +Eval | `private` → `fileprivate` |

### What changed access in main file (to enable cross-file extension reads)

- `private let persistence: PersistenceActor` → `let persistence: PersistenceActor` (read by +Snapshot.totalHighlightCount).
- `private let userDefaults: UserDefaults` → `let userDefaults: UserDefaults` (read by +Snapshot.snapshot).
- `private let log = Logger(...)` → `let log = Logger(...)` (used by all three extensions).

`fixtureBundle` and `importer` remain `private` — only used in the main file's seed/reset/open paths.

### Symbols / signatures verified

- All public-API method signatures (`settle`, `snapshot`, `eval`) unchanged. Tests exercising the public surface continue to pass.
- `DebugBridgeContext` protocol conformance (`reset`, `seed`, `open`, `theme`, `settle`, `snapshot`, `eval`) is preserved across the split (Swift permits protocol method requirements to be satisfied by methods in extensions of the same module).
- `DebugReaderRegistry.shared.current`, `DebugReaderProbe.evaluateJavaScript`, `DebugReaderProbeError.evalUnsupported`, `DebugSnapshot.encoder` — same call sites, same arguments.

### Edge cases checked

- **Behavior preservation**: 37/37 previously-passing DebugBridge tests still pass. The single failure (`test_snapshot_withoutActiveReader_listsReaderFieldsAsPartial` — asserts `schemaVersion == 1` while production has `currentSchemaVersion == 2`) is **pre-existing on `main`** (commit 70ed861, before the split). Confirmed by `git stash` + re-run — the same assertion failure reproduces without the split.
- **Release leakage**: re-ran `scripts/verify-release-no-debugbridge.sh` against a clean Release build of the post-split code. All six sub-checks PASS — the new files are `#if DEBUG`-gated, no symbols leak.
- **Logger category drift**: explicitly avoided creating per-extension Loggers. The class's `let log = Logger(subsystem: "com.vreader.app", category: "DebugBridge")` is `internal` so all extensions log under the same category. Pre-split `log.info(...)` calls remain identical post-split — the os_log output is byte-for-byte the same.
- **`Self.snapshotsDirectory()` cross-file access**: `snapshotsDirectory()` is `static func` with default access (`internal`), so +Settle and +Eval can call it via `Self.snapshotsDirectory()` even though it's declared in +Snapshot.
- **`SettleTimeoutSentinel` scoping**: declared `fileprivate enum` outside the extension in +Settle.swift, so the catch block in `settleWithTimeout` can match it without escaping the file. No behavior change.
- **`withTimeout` rename to `withSettleTimeout`**: avoids future ambiguity if other extensions add their own timeout helpers; private to +Settle so no public-API impact.
- **MainActor isolation**: extension methods inherit the class's `@MainActor` isolation. No isolation hops introduced. `nonisolated static let fixtureBundleSubdirectory` (in main file) unchanged.

### Risks accepted

- **Access-modifier widening** for `persistence`, `userDefaults`, `log` (private → internal). These were all internal-by-effective-use already (only used within DebugBridge subsystem); the change just makes that explicit so extensions can read them. No new external consumers gain visibility.
- **Static `let` → static `var { ... }`** for `settleTimeoutSeconds`. Computed properties cost is negligible (constant-folded by the optimizer); semantics identical.

### Tests added

None. This is a pure-refactor PR; behavior is unchanged so no new tests were warranted. The 38 existing DebugBridge tests act as the regression suite — 37 pass, 1 has a pre-existing schema-version assertion bug unrelated to the split.

### Verdict

**ship-as-is**. Pure structural change. Behavior preserved by the 37 passing tests; Release leakage prevented by `#if DEBUG` gating + verified by absence-gate script. LOC reduction: main file 506 → 247 (under 300). Closes feature #44 acceptance criterion (g).
