---
branch: fix/issue-1157-foliate-seek-fraction-debugbridge
threadId: 019e6376-a85c-7731-a7fd-931f5d299549
rounds: 2
final_verdict: ship-as-is
date: 2026-05-26
---

# Codex audit — Bug #267 / GH #1157 (Foliate seek-fraction DebugBridge command)

Independent Gate-4 audit (Codex MCP) of the DEBUG-only `vreader-debug://seek?fraction=`
command that lets the verification harness drive the live AZW3/MOBI Foliate
reader to a distinguishable non-start position (Bug #267 fix-direction b).

Files: `DebugCommand.swift`, `DebugBridge.swift`, `DebugBridgeNotifications.swift`,
`RealDebugBridgeContext+Seek.swift` (new), `FoliateBilingualContainerView.swift`,
`FoliateDebugSeekFractionObserver.swift` (new) + 4 test files.

## Round 1 — 1 Low

| # | Severity | Finding | Resolution |
|---|---|---|---|
| 1 | Low | Tests stopped at `.debugBridgeSeekFraction`; the load-bearing hop (the DEBUG observer re-posting `.foliateRequestSeekFraction` with the injected `fingerprintKey`, which the spike filters on) was unproven — a typo in the name or `"fingerprintKey"` payload would pass the suite. | **Fixed.** Extracted `FoliateDebugSeekFractionObserver.forward(_:fingerprintKey:)` (the `body` `.onReceive` calls it) + added DEBUG-gated `FoliateDebugSeekFractionObserverTests` pinning both the fraction+key re-post and the no-op-when-no-fraction case. |

Codex confirmed clean by inspection in round 1: the production chain is coherent
(handler posts `.debugBridgeSeekFraction` → DEBUG modifier injects the
container's `fingerprintKey` and re-posts `.foliateRequestSeekFraction` →
`FoliateSpikeView` filters on the key → `readerAPI.goToFraction`); injecting the
key in the container is the correct seam (the bridge handler doesn't know the
active book, the container does); Release gating is correct (handler file,
notification def, observer type, AND its call site all `#if DEBUG`); the parser's
required-param + finite-check + 0...1 clamp are correct; both test mocks
implement `seekFraction`.

## Round 2 — clean

No findings. The extraction + new test close the exact gap; the helper stays
DEBUG-gated, the body still forwards from `.onReceive` on `.main`.

## Verification

- Unit: `DebugCommandTests` + `DebugBridgeTests` + `RealDebugBridgeContextTests`
  + `FoliateDebugSeekFractionObserverTests` — **0 failures** (UDID-pinned,
  `-parallel-testing-enabled NO`).
- **Device (CU-free, iPhone 17 Pro Sim)**: seed + open `mini-azw3` → position
  `epubcfi(/6/2!/4,…)` (section 0); `seek?fraction=0.5` → position
  `epubcfi(/6/10!/4,…)` (section 4), `lastError: None` — a distinguishable
  non-start position the prior CFI-only seeks could not reach.

## Verdict

**Ship-as-is.** No open Critical/High/Medium after round 2. The command is the
documented fix-direction-(b) harness capability, device-verified to drive the
live Foliate reader to a distinguishable position.

## Follow-on note (not a finding)

Using this command to verify Bug #265 (AZW3 position restore) revealed the
reopen round-trip lands at start, not the seeked position — but the
`terminate`-based reopen used in the probe is unreliable for un-flushed
debounce-saves (SIGKILL can drop the save before disk commit) and there is no
CU-free "navigate back / close reader" command to trigger the `.onDisappear`
flush first. So #265 stays `awaiting-device-verification` pending a definitive
flush-based method — recorded on GH #1148, not closed.
