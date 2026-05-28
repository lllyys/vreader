---
kind: feature
id: 71
status_target: IN PROGRESS
commit_sha: 600166b7793b10de1bf1eb906619ff317aead301
app_version: 3.39.59 (build 680)
date: 2026-05-27
verifier: claude
device_or_simulator: iPhone 17 Pro Simulator
os_version: iOS 26.4
build_configuration: Debug
backend: n/a
result: pass
---

# Feature #71 — real-touch-scroll rAF observer FIRING device verification

Records device verification of the **single remaining unverified link** named in the
`docs/features.md` #71 row:

> **The ONLY remaining unverified link is the production rAF `continuousScrollObserverJS`
> FIRING on a real touch scroll** (everything downstream of the boundary signal is now
> device-verified) — that JS-listener layer is real-device/CU-only.

That link is now verified, end-to-end, with **real computer-use touch gestures** on the
iPhone 17 Pro Simulator. Computer-use became available this session (a real 4K display was
attached; the WKWebView is `document.visibilityState === "visible"`, so `requestAnimationFrame`
is no longer paused as it was in the prior virtual-display cron context).

`result: pass` for this slice. The feature row's terminal step (flip
`FeatureFlags.epubContinuousScroll` default-ON + full acceptance) is a separate ship
decision — see "Remaining" below.

## Acceptance criteria (this slice)

| # | Criterion | Observed | Pass |
|---|---|---|---|
| 1 | A real touch drag scrolls the continuous `#vreader-scroll-root` WebView | swipe-up drags moved `scrollTop` 0 → 393 → 2946 → … → 29057 (programmatic `scroll`-wheel did NOT; `left_click_drag` swipe does) | ✅ |
| 2 | Chapters flow continuously in ONE scroll document (no chapter-stop / reload flash) | scrolled ALPHA → BRAVO → CHARLIE → DELTA seamlessly; chapter indicator advanced "Chapter 1 of 4" → "2 of 4" → … → "4 of 4"; `sectionsInDOM` stitched (e.g. `[0,1]`, `[0,1,2]`) in a single document | ✅ |
| 3 | rAF `requestAnimationFrame` actually runs (was the blocker on virtual display) | self-loop rAF probe ticked 175× in ~1.5 s; `document.visibilityState === "visible"`, `document.hidden === false` | ✅ |
| 4 | The scroll observer `report()` fires on a real scroll event and posts the boundary signal | hooked `continuousScrollHandler.postMessage`: a real scroll near the bottom recorded `{visibleSpineIndex:1, intraFraction:0.899, nearTopBoundary:false, nearBottomBoundary:true}` | ✅ |
| 5 | A real touch scroll across the nearBottom (800 px `PREFETCH_PX`) threshold MATERIALIZES the next chapter | pristine page, window `[0,1,2]`, positioned in CHARLIE (`roomBelow` 3080 px) → ~9 real swipe-up drags → window became `[1,2,3]`, `visibleSection:3` (DELTA), reached "Chapter 4 of 4" | ✅ |
| 6 | Forward extension also EVICTS the far chapter (maxSpan-3 window slide) | `[0,1,2]` → real scroll → `[1,2,3]` — spine 0 evicted as spine 3 materialized; `maxScroll` grew 19087 → 29057 | ✅ |

## Commands run

```bash
UDID=61149F0E-DC18-4BE2-BB37-52659F1F4F62
# launched with: simctl launch ... -com.vreader.featureFlags.epubContinuousScroll YES -readerEPUBLayout scroll
# reset → seed multi-chapter-epub → open epub:426da955…:4270 → settle

# rAF liveness probe (proves the prior blocker is gone):
#   arm:  (function(){window.__rafCount=0;(function f(){window.__rafCount++;requestAnimationFrame(f);})();return 'armed';})()
#   read after ~1.5s → {"rafCount":175}

# observer message probe (proves report() fires + posts the boundary flag on real scroll):
#   hook continuousScrollHandler.postMessage to record → real scroll near bottom →
#   recorded {visibleSpineIndex:1, intraFraction:0.899, nearBottomBoundary:true}

# clean live-path test (pristine re-open, no hook, no navigate spam):
#   vreader-debug://navigate?spine=2&fraction=0.6   → scrollTop 25977, roomBelow 3080, window [0,1,2]
#   ~9 × computer-use left_click_drag [210,560]→[210,220]  (real swipe-up)
#   → {"scrollTop":29057,"sectionsInDOM":[1,2,3],"visibleSection":3}   (DELTA materialized, spine 0 evicted)

# window-state eval probe (per step):
#   #vreader-scroll-root → {scrollTop, maxScroll, roomBelow, sectionsInDOM[], visibleSection}
```

The DOM-state reads were driven CU-free via `vreader-debug://eval?bridge=epub&js=<base64>`
(result in `<data-container>/Library/Caches/DebugBridge/eval-epub.json`); the *gestures*
were real computer-use `left_click_drag` swipes on the booted Simulator window.

## Observations

- **The earlier "no extension" observations were environment/state artifacts, not a defect.**
  Two false negatives were ruled out: (a) the first attempt was pinned at `scrollTop == maxScroll`,
  where a swipe produces no scroll delta → no `scroll` event → no `report()`; (b) a later attempt
  ran from a state polluted by rapid `navigate` calls. From a **pristine re-open** (which clears the
  JS context + calls `coordinator.invalidate()` resetting `isExtending`/`generation`), a clean real
  scroll across the threshold extends + evicts exactly as the unit tests and the scroll-boundary
  driver predicted.
- **`scroll`-wheel ≠ touch scroll** on the iOS Simulator WKWebView: the computer-use `scroll`
  action left `scrollTop` at 0; only a `left_click_drag` swipe drives the inner scroller. Drag
  START must stay inside the content area (y ≈ 200–590); a drag starting on the bottom-chrome /
  progress-slider row (y ≈ 640) does not touch the WebView.
- Continuous flow is genuinely one document: BRAVO's "Paragraph 1…" rendered directly under
  ALPHA's tail, DELTA reached by pure scrolling, progress + "Chapter N of 4" updating live with
  no reload flash.

## Artifacts

- `dev-docs/verification/artifacts/feature-71-realscroll-delta-20260527.png` — reader at DELTA
  ("Paragraph 38/39/40 of the DELTA chapter", sentinel `delta-38/39`, "Chapter 4 of 4",
  progress slider at far right) reached by continuous real-touch scroll.

## Remaining (terminal ship decision — NOT a regression risk anymore)

The row's terminal step is: flip `FeatureFlags.epubContinuousScroll` default-ON + a full
end-to-end acceptance pass, which flips #71 `IN PROGRESS` → `DONE`/`VERIFIED`. The specific
risk the row cited for deferring that flip ("flipping default-ON **without confirming
real-scroll extension** would risk a regression for all EPUB scroll-mode users") is now
**retired** — real-scroll extension IS confirmed (this file). The flip itself is a code change
that still needs its own Gate-3→6 cycle (a test asserting the new default, Codex audit, version
bump, PR) and is a deliberate product decision (it changes the default EPUB scroll-mode reading
experience for all users). Other edge-case polish noted in the row (bottom-clip, seam highlights,
very-large-chapter memory) remains pending and is independent of this link.
