---
branch: fix/issue-976-debugbridge-search-driver
threadId: 019e4434-f286-7351-a71b-60a52e5286a2
rounds: 3
final_verdict: ship-as-is
date: 2026-05-20
---

# Audit log — Bug #238 / GH #976: DebugBridge search-driver

Codex Gate-4 implementation audit (rule 47, max 3 rounds). Author was Claude
Opus 4.7 (1M context) in the worktree
`/Users/ll/workspace/vreader/.claude/worktrees/agent-ac43ada99a6ebcc8f`.
Auditor was Codex (`gpt-5.2-codex`, thread `019e4434-f286-7351-a71b-60a52e5286a2`).

## Files audited

Production:
- `vreader/Services/DebugBridge/DebugCommand.swift` — added `.search(query:index:)` parser case
- `vreader/Services/DebugBridge/DebugBridge.swift` — added `search` to protocol + dispatcher
- `vreader/Services/DebugBridge/DebugBridgeNotifications.swift` — added `.debugBridgeSearchCommand`
- `vreader/Services/DebugBridge/RealDebugBridgeContext.swift` — added `search` handler
- `vreader/Views/Reader/ReaderContainerView.swift` — added observer modifier, `@State debugBridgeSearchTask`, `.onDisappear` cancellation
- `vreader/Views/Reader/ReaderContainerView+DebugBridgeSearch.swift` — NEW (DEBUG-only) — observer modifier + driver helpers

Tests:
- `vreaderTests/Services/DebugBridge/DebugCommandTests.swift` — 12 new parser cases
- `vreaderTests/Services/DebugBridge/DebugBridgeTests.swift` — 2 new routing cases + extends `RecordingDebugBridgeContext` / `SlowDebugBridgeContext` for the new method
- `vreaderTests/Services/DebugBridge/RealDebugBridgeContextTests.swift` — 4 new notification-posting tests

Docs:
- `docs/subsystems/debug-bridge.md` — adds `search` row + parameter notes
- `docs/architecture.md` — appends `search` to the DebugBridge service description
- `docs/bugs.md` — flips row #238 to IN PROGRESS

## Round 1 findings

| File:line | Severity | Issue | Resolution |
|---|---|---|---|
| `ReaderContainerView+DebugBridgeSearch.swift:56-97` + `ReaderSearchCoordinator.swift:99-113` + `SearchViewModel.swift:92-100` | **High** | Cold-open / indexing-in-flight searches return 0 hits and never retrigger. `setup()`'s `retriggerIfNeeded()` fires before our query lands; the bridge would then time out 10s later with no error. | **Fixed**. Added `awaitSearchIndexed(coordinator:fingerprint:timeout:)` static helper that polls `service.isIndexed(fingerprint:)` every 200ms until indexed or 30s timeout. The driver now goes VM-ready → index-ready → set query → wait result. When the query already matches what the VM holds, the handler calls `retriggerIfNeeded()` instead of a no-op assignment. |
| `ReaderContainerView+DebugBridgeSearch.swift:64-117` + `ReaderContainerView.swift:615-617` + `SearchViewModel.swift:104-130, 156-158` | **High** | Search commands not serialized or cancellable. Two URLs racing would let the first tap the second's result; nothing cancelled the task on reader dismiss. | **Fixed**. Added `@State var debugBridgeSearchTask: Task<Void, Never>?` (DEBUG-only) — cancelled at the start of each new `handleDebugBridgeSearchCommand` and in the existing `.onDisappear` (also DEBUG-only). Every step checks `Task.isCancelled`; `awaitSearchResult` takes a new `expectedQuery:` argument and bails (returns nil) if `viewModel.query` is no longer the trimmed match. |
| `ReaderContainerView+DebugBridgeSearch.swift:90-116, 141-164` + `SearchViewModel.swift:61-66, 75-85` | **Medium** | Pagination ignored — `SearchViewModel` defaults to `pageSize = 20`, so `index >= 20` would always time out. The wait was also slow to fail when `results.count <= index && hasMore == false`. | **Fixed** (round 1 partial). Added `loadMore()` trigger inside the poll, plus `!hasMore` fail-fast. Round-2 audit re-flagged the one-page-only cap; round-2 fix replaces the boolean `didRequestMore` with an iterative `lastObservedCount` tracker. |

## Round 2 findings

| File:line | Severity | Issue | Resolution |
|---|---|---|---|
| `ReaderContainerView+DebugBridgeSearch.swift:289-300` | **Medium** | Pagination still only fired once per command — `didRequestMore` never reset, so `index=45` (third page) still failed. | **Fixed**. Replaced `didRequestMore: Bool` with `lastObservedCount: Int` (-1 sentinel). Each loop iteration: if `!isSearching && results.count != lastObservedCount && hasMore`, fire a fresh `loadMore()` and update the tracker. Continues until reach, exhaust, cancel, or timeout. The tracker covers both (a) "loadMore in flight" via `isSearching == true` and (b) "previous loadMore already landed" via the count-change check. |

## Round 3 findings

Clean. No remaining Critical / High / Medium findings.

Verified properties:
- Pagination loop is reach-or-exhaust (no one-page cap).
- `isSearching` blocks re-firing while a page load is in flight.
- `lastObservedCount` blocks duplicate `loadMore()` against the same landed page.
- Query-divergence guard prevents stale taps after a later URL overwrote the VM's query.
- `loadMore()` failure (`errorMessage` set, `results.count` static) does not create an infinite loop — `results.count` stops changing → no further `loadMore()` fires → outer wait exits on timeout.
- `@State` access stays on `@MainActor` (the Task is `Task { @MainActor in ... }` and all observed surface is MainActor-isolated).
- 30s index-wait timeout is reasonable against the existing `ReaderSearchCoordinator` / `BackgroundIndexingCoordinator` flow.

## Final verdict

**ship-as-is**

Audit thread: `019e4434-f286-7351-a71b-60a52e5286a2` (Codex MCP, 3 rounds).

## Test summary

`xcodebuild test -only-testing:vreaderTests/{DebugCommandTests,DebugBridgeTests,RealDebugBridgeContextTests}` → 106 tests, 0 failures.
Full test suite scheduled to run as the Phase 5 gate.
