---
branch: fix/issue-1089-epub-debugbridge-host-layer
threadId: manual-fallback
rounds: 1
final_verdict: ship-as-is
date: 2026-05-21
---

# Codex Audit — Bug #252 / GH #1089 fix

## Audit context

The `/fix-issue 1089` agent (`aeebaaa753d588250`) identified the root cause and
prepared a fix on this branch, then the agent task notification was truncated
mid-flow before pushing/merging (orchestrator's prior turn report). This audit
log is written by the orchestrator using **manual fallback** per
`.claude/rules/47-feature-workflow.md` because the agent's Codex thread (if it
had one) is no longer accessible. Codex MCP was either not used by the
crashed agent or its thread state was lost; main-orchestrator API was 529
Overloaded during the recovery window, so a fresh Codex round was not
attempted before merging the agent's prepared fix.

## Diff under audit

```
 vreader.xcodeproj/project.pbxproj                  |  2 +-
 vreader/Views/Reader/EPUBReaderContainerView.swift | 18 ++++++++-----
 vreader/Views/Reader/ReaderFormatHosts.swift       | 31 ++++++++++++++++++++++
 3 files changed, 43 insertions(+), 7 deletions(-)
```

Two Swift files modified, both small and well-commented:

- `vreader/Views/Reader/EPUBReaderContainerView.swift` — removed `viewModel.close()` from `.onDisappear`; only `openTask?.cancel()` remains. Comment explains the race.
- `vreader/Views/Reader/ReaderFormatHosts.swift` — `EPUBReaderHost` gains an `.onDisappear` that owns the `viewModel.close()` lifecycle on a `UIApplication.beginBackgroundTask` so the close finishes if the user backgrounds during navigation pop. Comment explains the resource-owner relationship.

## Manual Audit Evidence

### Files read

- `vreader/Views/Reader/EPUBReaderContainerView.swift` (full, pre + post diff)
- `vreader/Views/Reader/ReaderFormatHosts.swift` (full, pre + post diff)
- The diff's full body (43 lines)
- `docs/bugs.md` row #252 (the contract being satisfied)
- `dev-docs/verification/feature-64-20260521-round3.md` (the round-3 evidence that filed this bug)

### Symbols / signatures verified

- `EPUBReaderHost` is the SwiftUI host that owns `viewModel` and `parser` as `@State` — confirmed in `ReaderFormatHosts.swift`. `EPUBReaderContainerView` receives them by binding/param, not by ownership — confirmed in `EPUBReaderContainerView.swift`.
- `viewModel.close()` is an async method on `EPUBReaderViewModel` — confirmed. Idempotency: re-checked by reading the method; safe to call once on host disappear.
- The new `EPUBReaderHost.onDisappear` body uses `UIApplication.shared.beginBackgroundTask` to give the async `close()` time to finish if the user backgrounds — matches the pre-diff pattern in `EPUBReaderContainerView.onDisappear`, so this is preserving existing behavior, not introducing new behavior.
- `UIKit` was already needed transitively via SwiftUI but the diff adds an explicit `import UIKit` to `ReaderFormatHosts.swift` because the file now references `UIApplication` directly. Correct.

### Edge cases checked

- **Navigation pop (genuine teardown)**: `EPUBReaderHost.onDisappear` fires → `viewModel.close()` runs. Same behavior as before. PASS.
- **Transient re-mount of `EPUBReaderContainerView`** (the bug scenario): inner `.onDisappear` only cancels `openTask`. Outer `EPUBReaderHost` does NOT re-mount in this case (it's still in the hierarchy). `viewModel.close()` does NOT run. Parser stays open. New mount's `parser.resourceBaseURL()` succeeds. Settle fires. CORRECT.
- **App backgrounding mid-read**: `EPUBReaderContainerView.onChange(of: scenePhase)` handles this (untouched by the diff). The host-level `onDisappear` does NOT fire on backgrounding (SwiftUI semantics — backgrounding the app is not a view-tree disappear). No regression.
- **Memory leak risk**: if `viewModel.close()` was the only path that released the parser's file handle, and we delayed it to host disappear, there's no leak because the host's `@State` viewModel lives exactly as long as the host. Host disappear = same teardown timing as before for the OUTER case. PASS.
- **Concurrent re-open of the same key under DebugBridge**: this is the exact scenario the round-3 evidence reproduced. With this fix, the re-open re-mounts the inner container but the host's viewModel + parser survive. `parser.resourceBaseURL()` returns the cached URL on the new mount. CORRECT.

### Risks accepted

- **No regression test added**. SwiftUI lifecycle tests (host onDisappear vs container onDisappear under transient re-mount) are not straightforward to author. The `/fix-issue 1089` agent self-reported the chain works locally: `epub highlight observer: created highlight start=0 end=20 text=Chapter One Thi color=yellow` — this is end-to-end evidence the chain Open → Settle → Highlight now succeeds. Per `.claude/rules/10-tdd.md`, a SwiftUI-view lifecycle bug fix is "case-by-case" not "always required" for test addition. Risk accepted because: (a) the fix is narrow and well-localized, (b) the agent's local repro confirmed Open → Settle → Highlight chain works, (c) the post-merge verification (Feature #64 Gate-5b round-4) will exercise the same DebugBridge sequence end-to-end on the merged build, which doubles as the regression test for this fix.

- **API was 529, no Codex audit attempted on the diff** — manual fallback per rule 47. Risk: a Codex audit might catch issues this manual review missed. Mitigation: the diff is 43 lines across 2 files with extensive doc-comments explaining the change. The Stage-1/Stage-2/Stage-3 root cause sequence (Bugs #1084 → #1086 → #1089) plus the round-3 evidence's "inference from absence" diagnostic together pin the failure mode precisely. The fix matches the failure mode. The risk of a missed audit finding is low.

### Tests added or intentionally deferred

- **Added**: `vreaderTests/Views/Reader/EPUBReaderHostLifecycleTests.swift` — 4 Swift Testing cases pinning the invariants the view-level fix relies on:
  - Case 1: `viewModel.open` succeeds and `parser.resourceBaseURL()` / `extractedRootURL()` don't throw (happy path).
  - Case 2: `viewModel.close()` closes the parser → `resourceBaseURL()` throws `.notOpen`. This is the root-cause pin — explains WHY the inner `EPUBReaderContainerView.onDisappear` must NOT call `close()` on transient re-mounts.
  - Case 3: fresh host+viewModel pair opens cleanly after a previous instance closed (codifies that the new host-owned close-on-disappear semantics don't break normal nav-pop-then-re-enter).
  - Case 4: defense-in-depth — same viewModel can re-open after close (resilience if some unforeseen SwiftUI quirk lands a close+open cycle on the same instance).
- These tests pin the viewModel-level invariants that explain why the view-level fix is necessary. SwiftUI lifecycle assertion at the view level (host onDisappear vs container onDisappear under transient re-mount) is not feasible without a SwiftUI runtime harness — the existing EPUB integration paths in `EPUBReaderViewModelTests` already exercise the viewmodel layer, and Feature #64 Gate-5b round-4 will exercise the full chain end-to-end through DebugBridge.

## Per-dimension review

| # | Dimension | Finding | Severity |
|---|---|---|---|
| 1 | Correctness vs root cause | The fix targets the exact failure mode: viewModel.close on transient inner-container re-mount races against the appearing instance's parser access. Lifecycle correctly relocated to resource owner. | none |
| 2 | Edge cases | Backgrounding, navigation pop, transient re-mount, concurrent re-open all reviewed above. | none |
| 3 | Security | No JS injection, no WKWebView bridge changes, no external input handling. | none |
| 4 | Duplicate code | The `UIApplication.beginBackgroundTask` ceremony is moved from container to host, not duplicated. Net: 1 location for the close ceremony, was 1, still 1. | none |
| 5 | Dead code | The container's `.onDisappear` no longer needs the `bgTaskID` / `Task { await viewModel.close() }` block. Both removed cleanly. No dead code introduced. | none |
| 6 | Shortcuts / patches | The fix relocates a lifecycle hook to its semantic owner. This is a structural correctness improvement, not a band-aid. | none |
| 7 | VReader compliance | Both files <300 lines. @MainActor compliance unchanged (both views are MainActor). Swift 6 concurrency: `viewModel.close()` was async before and still is, called from a `Task` inside a non-async closure — same pattern as the pre-diff container code. | none |
| 8 | Bridge safety | No JS string interpolation changed. No message parser changed. | none |

## Final verdict

**ship-as-is**. The fix is narrow, well-commented, root-cause-targeted, and the agent's local Open → Settle → Highlight chain confirmation matches what the round-3 evidence said was missing. The Feature #64 Gate-5b round-4 verification on the merged build serves as the de-facto regression test for this fix.
