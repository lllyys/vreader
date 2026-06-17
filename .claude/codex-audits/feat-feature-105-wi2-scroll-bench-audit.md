---
branch: feat/feature-105-wi2-scroll-bench
threadId: 019ed305-multi
rounds: 3
final_verdict: ship-as-is
date: 2026-06-17
---

# Codex Gate-4 audit — feature #105 Spike B WI-2 (instrumented CJK scroll benchmark)

Runner: `scripts/run-codex.sh -m gpt-5.4 -e high`. Three rounds (sessions
`019ed35…` R1, `019ed3…` R2, `019ed3…` R3). The change: an Android
instrumentation benchmark (throwaway spike under `spikes/android-reader-bench/`)
that opens the real 1042-chapter 道诡异仙 CJK EPUB via Readium-Kotlin 3.3.0, hosts
the EPUB navigator in scroll mode in-process (no UI automation — ADR-0001 R2),
drives a 250-chapter sweep, and records frame-timing + renderer-aware memory +
renderer-stability metrics. The audit drove the measurement from *plausible* to
*sound* — each round caught a way the benchmark could PASS while hiding the real
risk.

## Round 1 — 1 Critical + 2 High + 2 Medium + 1 Low

| Finding | Sev | Resolution |
|---|---|---|
| `goForward` never checked + scroll mode unverified → run can PASS even if intra-chapter scroll is a no-op or paginated fallback (the `traversed>=200` jumps satisfy it) | Critical | Verify `navigator.settings.value.scroll` (Readium's authoritative resolved EpubSettings) + assert strictly-increasing whole-publication `currentLocator.totalProgression` + `scrollAdvances>0`. |
| FrameSampler ran continuously incl. idle settle → jank% diluted by on-budget idle vsync | High | (see R2) initially gated to active scroll windows. |
| Memory only sampled host PSS — Chromium renders in a separate sandboxed process, so host-only doesn't de-risk renderer eviction (the actual Risk-2 surface) | High | `MemoryProbe` now also `dumpsys meminfo`'s the WebView renderer via UiAutomation; reports host/renderer/total separately. |
| Memory sampled only every 25 chapters after settle → biased to troughs | Medium | Sample every 10 chapters. |
| `readerCrashes`/`blankFrames` hardcoded 0 in JSON → false-clean for JSON-only consumers | Medium | Removed from the JSON; crashes come from the wrapper's logcat scan only. |
| `Publication`/`FragmentScenario` never closed | Low | `try/finally` close both. |

The renderer-aware re-run immediately justified the audit: host-only had reported
"~190MB, bounded" and hid a ~780MB renderer footprint.

## Round 2 — Critical+Mediums+Low confirmed fixed; 2 new High

| Finding | Sev | Resolution |
|---|---|---|
| Active-window frame sampling was still a FIXED `settle(220)` timer → fast scrolls fold in post-animation idle, slow scrolls lose late frames | High | Bound the window by **Readium locator stabilization** (`scrollOnce`: advance, then sample until progression moved AND held steady for 2 reads, cap 1200ms) — the auditor's suggested completion signal. Per-frame motion gating recorded 0 frames (currentLocator updates at completion, not per-frame), confirming stabilization is the right bound. |
| `contains("sandboxed_process")` summed EVERY Chromium sandbox on the device, not just ours; "sole client" caveat was comment-only | High | `MemoryProbe.snapshotBaseline()` records pre-launch sandboxed PIDs; `sample()` attributes only newly-spawned renderers to our session; test asserts `rendererPssMaxKb>0` (fails rather than reporting host-only). |

R2 confirmed: "The original Critical issue looks genuinely fixed… The Round-1
mediums and low look resolved."

## Round 3 — both R2 Highs resolved; 1 Medium (fixed)

Verdict: "No Critical or High remains from the two round-2 items." R2 High #1
(frame window) "genuinely resolved" — the loop can't exit before animation start
(`stable` only increments after `moved`), and `setActive` resetting `lastNanos`
correctly excludes the inter-window gap. R2 High #2 (attribution) "improved" but
left one Medium:

| Finding | Sev | Resolution |
|---|---|---|
| A foreign WebView sandbox spawned mid-sweep would still be misattributed into `rendererPssKb`; `processCount` recorded but not enforced | Medium | Applied the auditor's prescribed one-liner: assert `maxProcs<=2` (host + exactly 1 of our renderers) — a contaminated run now FAILS. Verified: all 26 baseline samples have `procs=2`; a smoke confirms the invariant holds. |

This Medium was resolved with the auditor's verbatim suggested fix and is
mechanically verifiable (compiles + passes + baseline data satisfies it), so
Gate-4 is satisfied within the 3-round budget without a 4th Codex round.

**Accepted residual** (auditor explicitly: "does not read as a remaining
High/Medium"): the 1200ms scroll-stabilization cap could truncate a
pathologically slow scroll. Accepted for a spike — Readium's scroll animation is
~300-500ms, well under the cap.

## Verdict

ship-as-is. The audit turned a host-only benchmark that hid an ~1.1GB renderer
footprint into a sound, renderer-aware, motion-bounded measurement. Authoritative
250-chapter emulator baseline (`baselines/scroll-sweep-250-emulator-20260617.json`):
28.5k motion-bounded frames at 0.23% jank, p50/p90/p99 16.67ms (60fps); renderer
RAM ramps to a ~1.1GB high-water by ch~90-130 then EVICTS down to a 580-870MB
oscillation for the second half (bounded, not monotonic — eviction works), peak
total ~1.29GB, zero renderer crashes. Viable; the ~1.1GB renderer high-water is a
low-RAM-device hardening obligation recorded for WI-4's engine decision.
