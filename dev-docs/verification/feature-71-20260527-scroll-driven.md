---
kind: feature
id: 71
status_target: IN PROGRESS
commit_sha: 04aca0175b1990c8b8f1a61f4d8cf6a1865ee794
app_version: 3.39.56 (build 677)
date: 2026-05-27
verifier: claude
device_or_simulator: iPhone 17 Pro Simulator
os_version: iOS 26.4
build_configuration: Debug
backend: n/a
result: partial
---

# Feature #71 — scroll-driven extend/evict device verification (via the scroll-boundary driver)

Records the device verification of #71's CORE acceptance behavior — scroll-driven
continuous extension + eviction + reverse-scroll prepend — using the new
`vreader-debug://scroll-boundary` driver (v3.39.56) that posts an
`EPUBScrollBoundarySignal` directly to `EPUBContinuousScrollCoordinator.handleBoundarySignal`,
bypassing the rAF-throttled `continuousScrollObserverJS` (which a real touch scroll drives
but synthetic scroll on the virtual-display environment cannot — proven earlier this session).

`result: partial` — #71 stays `IN PROGRESS`. This closes the largest verification gap (the
extend/evict RESPONSE); the residual is the rAF observer FIRING on a real touch scroll
(real-device/CU-only) + the flag-flip ship decision.

## Acceptance criteria (the scroll-driven slice)

| Criterion | Driver | Observed (`sectionsInDOM`) | Result |
|---|---|---|---|
| Scroll toward a chapter bottom → next chapter materializes (no manual tap) | `scroll-boundary?spine=1&near=bottom` | `[0,1]` → `[0,1,2]` | pass |
| Continue forward → window slides + far section evicted (bounded memory, maxSpan 3) | `scroll-boundary?spine=2&near=bottom` | `[0,1,2]` → `[1,2,3]` (section 0 evicted) | pass |
| Reverse scroll near a chapter top → previous chapter prepended, no position jump | `scroll-boundary?spine=1&near=top` | `[1,2,3]` → `[0,1,2]`; scrollTop compensated to 9971 (prepend scroll-anchor) | pass |

## Commands run

```bash
UDID=61149F0E-DC18-4BE2-BB37-52659F1F4F62
xcrun simctl launch "$UDID" com.vreader.app -com.vreader.featureFlags.epubContinuousScroll YES -readerEPUBLayout scroll
xcrun simctl openurl "$UDID" "vreader-debug://reset"
xcrun simctl openurl "$UDID" "vreader-debug://seed?fixture=multi-chapter-epub"
xcrun simctl openurl "$UDID" "vreader-debug://open?bookId=epub:426da955270547674786150e93e8dd79e7b1babc8aed29ae21a5ffde871d34af:4270"
xcrun simctl openurl "$UDID" "vreader-debug://settle"
xcrun simctl openurl "$UDID" "vreader-debug://scroll-boundary?spine=1&near=bottom"   # → [0,1,2]
xcrun simctl openurl "$UDID" "vreader-debug://scroll-boundary?spine=2&near=bottom"   # → [1,2,3]
xcrun simctl openurl "$UDID" "vreader-debug://scroll-boundary?spine=1&near=top"      # → [0,1,2]
# probe sectionsInDOM via eval?bridge=epub&js=<base64> → eval-epub.json
```

## Observations

- The extend/evict primitives were already device-verified via the WI-8 navigate rebuild
  (`[0,1]`→`[2,3]`); this verifies the SCROLL entry point (`handleBoundarySignal`) drives them
  live — the feature's actual core trigger.
- Reverse-scroll prepend correctly compensated scrollTop (→9971) so the viewport doesn't jump
  when a section is inserted above — the `prependChapterSectionJS` scroll-offset compensation
  works live.

## Residual (CU / real-device only)

- The production `continuousScrollObserverJS` FIRING on a real touch scroll → posting the
  boundary signal. The observer is attached + threshold-correct (verified), but rAF is paused
  on the virtual display, so the real-scroll→signal link can only be confirmed on a real
  device with CU. Everything DOWNSTREAM of the signal is now device-verified.
- The flag-flip to default-ON remains a ship decision (a CU-equipped/human session) — see the
  `docs/features.md` #71 terminal-gate note.

## Artifacts

- `dev-docs/verification/artifacts/feature-71-scroll-driven-extend-20260527.png`
- Driver: `.claude/codex-audits/feat-debugbridge-scroll-boundary-driver-audit.md` (v3.39.56).
