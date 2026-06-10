---
branch: fix/issue-1568-epub-1px-scroll-jumps
threadId: 019eb187-f75e-7502-ac7e-975729a88efb
rounds: 1
final_verdict: ship-as-is
date: 2026-06-10
---

# Gate-4 Codex audit — Bug #329 round 3 (EPUB 1px continuous-scroll jumps, GH #1568)

Independent audit via `scripts/run-codex.sh` (gpt-5.4), read-only, explicitly
briefed as adversarial (two prior fixes for this bug regressed). The audit was
given the full root-cause history + the new px-aware eviction-deferral design.

## Round 1

| file:line | severity | issue | resolution |
|---|---|---|---|
| EPUBContinuousScrollJS.swift:264 | High | The ResizeObserver compensation gated "entirely above" on the POST-resize bottom (`offsetTop + newH`): a growth that crosses the viewport top would skip compensation (and a shrink of a previously-straddling section could over-compensate). | **Fixed** — gate on the PRE-resize bottom (`offsetTop + oldH <= scrollTop`), which is also geometrically self-consistent (after `scrollTop += delta`, the grown section is still entirely above). JS-shape test updated to pin `oldH`. |
| EPUBContinuousScrollCoordinator.swift:376 | Medium | The eviction guard consumes the signal's px snapshot after two awaits (provider + insert eval). The margin covers same-direction drift, but a REVERSAL during that window leaves a stale-large `pxAbove` → a wrong eviction (not just an over-deferral). | **Mitigated + accepted with rationale** — margin raised 64→128px (the exposure window is milliseconds — provider + one eval — so 128px covers realistic reversal velocity within it). The residual (a violent flick reversing >128px within ms) costs at most ONE evict→prepend-reload of a single section in the reader's NEW travel direction: the prepend's in-eval compensation keeps the viewport stable, so it is a wasted round-trip, not a visible jump, and it cannot oscillate (the reload direction matches travel). Rationale documented at the constant. |

Audit also explicitly confirmed: no compile/bridge issue with the optional
geometry defaults (`EPUBReaderContainerView+DebugBridgeScrollBoundary.swift`
builds geometry-less signals fine), and the parser's `NSNumber` handling for
`sectionHeights` is compatible with the live WKScriptMessage bridge.

## Verification matrix (the re-close bar is 1px granularity)

- **Unit (87 tests, 5 suites green)** — incl. the new guard suite + the
  `StitchSimulator` 1px physics sim whose CONTROL case (geometry withheld →
  legacy eviction) reproduces the device oscillation (backward jumps + window
  collapse + trapped progress), proving the sim detects the bug class; the
  guarded case is monotonic to chapter 6 with zero jumps/regressions/desync.
- **Device baseline (main, pre-fix)** — 1px DebugBridge sweep on "The Half
  Second": **25 backward jumps, 7 window-collapse cycles, trapped at spine 2**
  after 4557 ticks (`/tmp/b329-baseline.json`).
- **Device fix build** — same sweep: **0 jumps, 0 stalls, 0 thrash, 6 monotonic
  window transitions, reached spine 6** in 3678 ticks (`/tmp/b329-fixed.json`).

## Verdict

**ship-as-is.** The High fixed exactly as recommended; the Medium mitigated
(margin) with the bounded residual documented and accepted. The fix is
geometric (granularity-independent) rather than temporal — the class of the two
prior regressions (time-domain patches on a space-domain problem) is closed.
