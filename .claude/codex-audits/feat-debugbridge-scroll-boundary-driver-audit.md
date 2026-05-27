---
branch: feat/debugbridge-scroll-boundary-driver
threadId: 019e6979-08bc-7651-bc43-a70079dd1253
rounds: 1
final_verdict: ship-as-is
date: 2026-05-27
---

# Codex Audit — scroll-boundary DebugBridge driver (feature #71 verification harness)

Gate-4 audit for `vreader-debug://scroll-boundary?spine=<N>&near=<top|bottom>` — posts
an `EPUBScrollBoundarySignal` directly to `EPUBContinuousScrollCoordinator.handleBoundarySignal`,
bypassing the rAF-throttled `continuousScrollObserverJS` (unverifiable CU-free on the
virtual-display environment) so feature #71's scroll-driven extend/evict RESPONSE can be
device-verified. Mirrors the Bug #273 `navigate` driver.

Files: `DebugCommand.swift` (`ScrollBoundaryEdge` enum + `scrollBoundary` case + parser),
`DebugBridge.swift` (protocol + dispatch), `RealDebugBridgeContext+ScrollBoundary.swift`
(new, posts `.debugBridgeScrollBoundaryCommand`), `DebugBridgeNotifications.swift`,
`EPUBReaderContainerView+DebugBridgeScrollBoundary.swift` (new, DEBUG observer modifier +
Release `EmptyModifier` stub; no-op outside continuous mode), + tests + debug-bridge.md.

## Round 1 — findings

| file:line | severity | issue | resolution |
|---|---|---|---|
| project.pbxproj:5960,6245 | High | The two new Swift files were untracked but referenced in pbxproj → a commit with the pbxproj change but without the files would fail to build on a clean checkout (the rule-48 clean-clone hazard). | Fixed — both new files are `git add`-ed atomically with the pbxproj + other changes in the same commit. |
| docs/architecture.md:173 | Low | DebugBridge command row omitted `scroll-boundary`. | Fixed — added to the slash-list + a sentence describing the direct `handleBoundarySignal` injection. |

Codex confirmed the implementation clean: "parser validation is consistent with `navigate`
for `spine >= 0`, and `near` is properly allowlisted… The observer correctly no-ops when
`continuousScrollConfig == nil`, and the signal fields match the intended top/bottom mapping…
I don't see a blocking concurrency or retain issue in `Task { await config.coordinator.handleBoundarySignal(signal) }`… The ViewModifier split is fine and matches the existing DebugBridgeHighlight pattern."

## Verdict

**ship-as-is.** Zero open Critical/High/Medium after the staging fix; the one Low (architecture
doc) is fixed. Full `vreaderTests` (7333) passes; `verify-release-no-debugbridge.sh` passes
(all new code `#if DEBUG`-gated + Release `EmptyModifier` stub).

## Purpose (device verification it unblocks)

Lets a host-side `xcrun simctl openurl "vreader-debug://scroll-boundary?spine=N&near=bottom"`
drive the continuous coordinator's forward/backward extension + eviction without a real
touch scroll. Verifies feature #71's core acceptance behavior ("approach chapter boundary →
next chapter materializes; further → far section evicted") at the `handleBoundarySignal`
RESPONSE level. The remaining residual — the production rAF observer FIRING on a real touch
scroll — stays real-device/CU-only (the thin JS listener layer).
