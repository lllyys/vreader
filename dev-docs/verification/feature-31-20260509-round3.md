---
kind: feature
id: 31
status_target: DONE
commit_sha: 729e304475b854353075d928f7ba2e95f7a019f8
app_version: 3.14.107 (build 216)
date: 2026-05-09
verifier: claude
device_or_simulator: iPhone 17 Pro Simulator
os_version: iOS 26.4
build_configuration: Debug
backend: bundled DebugFixtures (war-and-peace.txt) + persisted UserDefaults
result: fail
---

## Summary

Round-3 attempt at the deferred TXT/MD auto-page-turn end-to-end leg
that round-2 (`feature-31-20260509.md`) left UNVERIFIED after filing
bug #156 (EPUB/PDF/AZW3 wiring gap). Bug #156 was FIXED via PR #459
by capability-gating the toggle to TXT/MD only. This round was
intended to close the loop: confirm TXT actually auto-advances pages
when the toggle is ON.

**It does not.** A *second* wiring gap is present — bug #157 / GH
#461 — covering chaptered TXT files specifically. War-and-peace.txt
(the only TXT debug fixture) hits this gap because of its
`CHAPTER I/II/III` markers.

Per verify-cron scope, this round files but does not fix.

Feature #31 row stays **`DONE`**. Do not flip to `VERIFIED` until
bug #157 is fixed and a follow-up round-4 confirms TXT/MD auto-page-
turn actually advances pages on the timer for the canonical chaptered
fixture.

## Acceptance criteria

| Criterion | Slice | Result |
|---|---|---|
| `AutoPageTurner` schedules advancement at configured interval | `AutoPageTurnerTests` (round-1) | PASS (cross-ref) |
| `AutoPageTurner` start/pause/stop state machine | `AutoPageTurnerTests` (round-1) | PASS (cross-ref) |
| `AutoPageTurner` cancels pending advancement on stop | `AutoPageTurnerTests` (round-1) | PASS (cross-ref) |
| `PageTurnAnimator` slide / cover / instant transitions | `PageTurnAnimatorTests` (round-1) | PASS (cross-ref) |
| End-to-end UI: enable auto page turn → EPUB/PDF/AZW3/MOBI pages advance | Capability-gated out by bug #156 fix (PR #459) | OUT OF SCOPE per current capability set |
| End-to-end UI: enable auto page turn → TXT (chaptered) pages advance every N seconds | Round-3 simulator drive against `war-and-peace.txt` | **FAIL — bug #157** |
| End-to-end UI: enable auto page turn → TXT (non-chaptered, non-large) pages advance | No fixture available; `Position Test Book` is `--uitesting` only | DEFERRED |
| End-to-end UI: enable auto page turn → MD pages advance every N seconds | No bundled MD fixture; same chapter-routing risk shape applies | DEFERRED (likely same gap as bug #157) |
| End-to-end UI: pause auto page turn → advancement stops | Cannot exercise (advancement never started) | DEFERRED |
| End-to-end UI: tap during auto-advance → user gesture cancels timer | Cannot exercise (advancement never started) | DEFERRED |

## Commands run

```bash
SIM=61149F0E-DC18-4BE2-BB37-52659F1F4F62

# Capture pre-state: confirm Layout=Paged + Auto Page Turn=ON in
# settings panel via computer-use UI driving (settings sheet scroll).
# Confirmed visually: Native engine, Paged layout, Auto Page Turn ON,
# Interval slider at 5s default.

# Drag scrubber to 19% so reader is NOT on the last page.
# Then tap center to hide chrome. Wait 12s. No advance.

# Cleanest run — fresh launch, no taps:
xcrun simctl terminate $SIM com.vreader.app
xcrun simctl launch $SIM com.vreader.app
# UI: tap war-and-peace card → reader opens at 1%
# DO NOT tap reader content
sleep 2  && xcrun simctl io $SIM screenshot t0.png
sleep 6  && xcrun simctl io $SIM screenshot t8s.png    # past the 5s interval
sleep 6  && xcrun simctl io $SIM screenshot t14s.png   # past two intervals

# Confirm persisted settings:
DATA_DIR=$(xcrun simctl get_app_container $SIM com.vreader.app data)
plutil -extract readerEPUBLayout raw "$DATA_DIR/Library/Preferences/com.vreader.app.plist"
# → paged
plutil -extract readerAutoPageTurn raw "$DATA_DIR/Library/Preferences/com.vreader.app.plist"
# → true
```

Code-read for bug #157:

```bash
# TXT routing branches — ZStack body
sed -n '110,140p' vreader/Views/Reader/TXTReaderContainerView.swift
#   line 117-120: chapter detection → chapterReaderContent (no pageNavigator)
#   line 124-130: large file → chunkedReaderContent (no pageNavigator)
#   line 131-133: small + non-chaptered → readerContent (only path with pageNavigator)

# AutoPageTurner guard
sed -n '113,123p' vreader/Views/Reader/TextReaderUIState.swift
#   guard enabled, isPagedMode, let nav = pageNavigator else { stop(); return }

# resume() never called from production
grep -rn "AutoPageTurner.*resume\|\.resume()" vreader/
#   only ttsService.resume() and URLSessionDownloadTask.resume()
```

## Observations

- **Settings persisted correctly.** `readerEPUBLayout=paged` +
  `readerAutoPageTurn=true` confirmed via `plutil -extract` on the
  simulator's `com.vreader.app.plist`. The settings panel UI also
  reflects this (Native engine, Paged layout, toggle ON, slider 5s).
  The bug is downstream of settings.
- **Three identical screenshots at t=0 / t=8s / t=14s.** No advance
  whatsoever. The visible content, progress bar position (1%), and
  bottom toolbar are pixel-identical across all three timestamps.
  This is unambiguous: timer is not firing.
- **Chaptered routing is the root cause.** `chapterReaderContent`
  (line 486-503) uses `TXTTextViewBridge` directly without any
  pagination setup. `pageNavigator` stays nil for the entire reader
  session, so `updateAutoPageTurner`'s guard `let nav = pageNavigator`
  fails and the turner is `.stop()`ed.
- **War-and-peace.txt always triggers chapter detection** because of
  the literal `CHAPTER I/II/III` markers in the fixture. There is no
  bundled non-chaptered TXT fixture to test the alternate
  (`readerContent`, with-pageNavigator) path on a public-Debug build.
- **Pause-without-resume side observation**. `AutoPageTurner.pause()`
  is called from `.readerContentTapped` / `.readerNextPage` /
  `.readerPreviousPage` in `TXTReaderContainerView.swift:334-356`,
  but `AutoPageTurner.resume()` is never called anywhere in the
  production codebase (only `ttsService.resume()` and
  `URLSessionDownloadTask.resume()` exist). Once paused by any tap,
  the timer stays paused until the user toggles the setting OFF and
  back ON. The settings panel footer says "Pauses on user
  interaction" — but if the design is "permanent pause", the user
  has no way to re-arm without going to settings. Filed inline with
  bug #157 as a side observation; not the root cause of the
  primary failure (the chaptered routing branch never `start()`s
  the timer at all, regardless of pause state).
- **Companion to feature #41 round-2.** `feature-41-20260509.md`
  reported successful TTS auto-scroll against this same fixture. That
  worked because TTS auto-scroll uses `uiState.scrollToOffset` and is
  consumed by the chapter-renderer's `TXTTextViewBridge` directly —
  it doesn't depend on `pageNavigator` at all. So TTS auto-scroll and
  Auto Page Turn live on different code paths; the round-2 success
  there does NOT imply round-3 should pass here.

## Artifacts

- `dev-docs/verification/artifacts/feature-31-r3-reader-open-t0-20260509.png` — fresh reader open, war-and-peace at 1%, post-relaunch.
- `dev-docs/verification/artifacts/feature-31-r3-reader-t8s-no-tap-20260509.png` — t=8s after open, identical to t=0.
- `dev-docs/verification/artifacts/feature-31-r3-reader-t14s-no-tap-20260509.png` — t=14s after open, identical to t=0.
- `dev-docs/verification/artifacts/feature-31-r3-t0-19pct-20260509.png` — earlier capture after slider drag to 19%, also showed no advance.
- `dev-docs/verification/artifacts/feature-31-r3-t8s-20260509.png` — 8s after slider drag (no tap), identical to t=0 capture.
- `dev-docs/verification/artifacts/feature-31-r3-t12s-toolbar-hidden-20260509.png` — 12s after toolbar-hide tap, no advance (note: tap itself paused the turner per Bug #131 wiring).
- `dev-docs/verification/artifacts/feature-31-r3-relaunch-library-20260509.png` — library after force-quit + relaunch.

## Verdict

`fail` for the TXT chaptered end-to-end leg. Round-1's data-layer
verification + round-2's EPUB-failure-class evidence stay
authoritative for `AutoPageTurner` / `PageTurnAnimator` correctness
and the EPUB capability-gate. Feature #31 row stays at **`DONE`**;
do **not** flip to `VERIFIED` until bug #157 (chaptered TXT pageNavigator
gap) is fixed and a follow-up round-4 confirms TXT auto-page-turn
actually advances pages on the timer.

Bug-fix cron will pick up GH #461.
