---
kind: feature
id: 31
status_target: VERIFIED
commit_sha: 0eba12b76fc7e0c5cd2cba0c0caf64dcab0e1cc8
app_version: 3.22.11 (build 363)
date: 2026-05-15
verifier: claude
device_or_simulator: iPhone 17 Pro Simulator
os_version: iOS 26.5
build_configuration: Debug
backend: n/a (bundled multi-page MD fixture)
result: partial
---

# Feature #31 round-5 — open-path unblock confirmed (Bug #191 fix), live-advancement render still deferred

## Context

Round-4 (2026-05-15 morning, evidence `feature-31-20260515-round4.md`)
encountered an "open-path blocker": every click on the seeded book
silently terminated the app process, no crash report written. At the
time the cause was ambiguous (computer-use coords vs in-app fatal).
Bug #191 (`AutoPageTurner.interval` infinite-recursive `didSet` under
`@Observable`) shipped its fix in commit `b347dd6` (v3.21.66) a few
hours after round-4 captured its evidence. The fix was on
`awaiting-device-verification` until the bugfix cron round earlier in
this session closed the GH issue with a clean device-verify
(`dev-docs/verification/bug-191-20260515.md`, `result: pass`).

The exact symptom round-4 documented as the open-path blocker — set
`readerAutoPageTurn=true` + `readerAutoPageTurnInterval=3.0` in
defaults, launch with `--uitesting --seed-md-multi-page
--reader-default-layout=paged`, tap the book → process silently
exits — is precisely Bug #191's repro path. Round-4's open-path
blocker was Bug #191, not a tooling or fixture issue.

Round-5 reruns Feature #31's live-advancement slice on the
post-Bug-#191-fix build to confirm: (1) the open path now works,
and (2) what the live-advancement criterion looks like once the
reader can actually open.

## Acceptance criteria

Feature row's contract is: auto-page-turn advances pages over a
configurable interval in paged mode.

| # | Criterion | Round-4 | Round-5 | Pass/fail (this round) |
|---|---|---|---|---|
| 1 | `--seed-md-multi-page` seeds an MD book that paginates to ≥2 pages at 18pt | pass | pass (file `md_…c0c002_9231.md` present, 9231 bytes, library shows "Test Markdown Multi-Page") | **PASS** |
| 2 | Pre-launch UserDefaults for auto-page-turn persist through the seed flow | pass | pass (`defaults read` returns `1` and `3` after launch with `--uitesting --seed-md-multi-page`) | **PASS** |
| 3 | `--reader-default-layout=paged` flag applies to MD readers | deferred | **PASS** — Settings panel after open shows Scroll/Paged segmented control with **Paged** selected; the launch flag took effect on the MD `epubLayout` read path. Confirmed via UI inspection (`artifacts/feature-31-r5-01-...png`). | **PASS** |
| 4 | Opening the book with paged layout shows multiple pages | **BLOCKED (round-4)** | **PASS (open path)** — reader opens cleanly on Chapter 1; AutoPageTurner setter no longer crashes during reader-init (Bug #191 fix verified). DebugBridge snapshot confirms `currentBookId: md:000…c0c002:9231`, `format: "md"`, `fontSize: 18`. | **PASS (open path); render-layout TBD (see below)** |
| 5 | Auto-page-turn timer advances pages over a 3-second interval | **BLOCKED (round-4)** | **deferred** — after dismissing the Settings sheet (`Auto Page Turn: ON, Interval: 3s, Paged: selected`) and waiting 6s with no user interaction, the visible reader content is unchanged (`feature-31-r5-02-after-6s-wait-20260515.png`). The rendered content area shows continuous prose ("A deterministic test fixture..." → "Chapter 1: Opening" → multi-paragraph chapter body) with chrome that reads more like scroll-mode (small "0%" progress markers) than paged-mode (which would show "Page X of Y"). Either (a) the MD reader rendered the book in scroll mode despite Settings showing Paged, (b) auto-page-turn fired but the at-last-page short-circuit triggered, or (c) the chrome rendering for MD-paged-mode differs from EPUB-paged-mode in a way that the casual screenshot inspection can't distinguish. Without a clear visible page-transition, criterion 5 cannot be marked PASS. | **deferred → follow-up** |

**Overall**: `partial` — but the major round-4 blocker is now lifted.
Three criteria (1, 2, 3) PASS unambiguously. Criterion 4's open path
PASSes; criterion 5 needs deeper investigation before it can be
marked.

## Commands run

```bash
SIM_ID="1FAB9493-B97E-48F0-96C7-44A8E5AAA21E"

# Same setup as Bug #191 verify (defaults that pre-fix caused crash)
xcrun simctl spawn booted defaults write com.vreader.app readerAutoPageTurn -bool true
xcrun simctl spawn booted defaults write com.vreader.app readerAutoPageTurnInterval -float 3.0

# Launch with paged layout + seed
xcrun simctl terminate booted com.vreader.app   # benign noop if not running
xcrun simctl launch booted com.vreader.app \
  --uitesting --seed-md-multi-page --reader-default-layout=paged
# → app launches, library shows seeded book

# Open + UI inspection via computer-use:
# 1. tap library row → reader opens on Chapter 1 (NEW vs round-4)
# 2. tap AA icon → Reading Settings sheet appears (sized to small detent)
# 3. drag grabber to expand to large detent
# 4. observe: Scroll/Paged shows Paged; Auto Page Turn: ON; Interval: 3s

# DebugBridge snapshot for state inspection
xcrun simctl openurl booted "vreader-debug://snapshot?dest=f31-r5-after-6s-wait.json"
cat "$(xcrun simctl get_app_container booted com.vreader.app data)/Library/Caches/DebugBridge/f31-r5-after-6s-wait.json"
# → currentBookId set, format=md, renderPhase=idle
```

## Observations

- **The "open-path blocker" diagnosis in round-4 was Bug #191.** The
  ambiguous "process silently dies on book open" round-4 documented
  matches Bug #191's `AutoPageTurner.interval`-via-`@Observable`
  recursive setter — the bug only manifests when those exact
  defaults are pre-set (which round-4 set per its recipe). Round-4's
  prudent "borderline, file as deferred rather than as a Bug row"
  call held up: the cause was a real product bug, not tooling, and
  it shipped a fix the same day.
- **Settings panel state confirms the launch flag works for MD.**
  Round-3 / round-4 documented that `--reader-default-layout=paged`
  sets `readerEPUBLayout` and that `MDReaderContainerView` reads
  `epubLayout` — so the flag should apply to MD too. Round-5's
  Settings-panel screenshot directly confirms it: Paged is the
  selected segment for the MD reader. That's a positive verification
  of the wiring path that round-3 deferred as "in place but not
  directly observable without a working book-open path."
- **Render-layout ambiguity remains for criterion 5.** The reader
  content area shows continuous prose, no visible page boundaries,
  no "Page X of Y" indicator, and a "0%" scrubber at the bottom that
  looks like the scroll-mode progress bar. Either MD's paged-mode
  chrome simply differs from EPUB's, or the layout flag's wiring is
  read by `epubLayout` but the actual render pipeline still goes
  through the scroll-mode path. A follow-up investigation should
  distinguish: tap right-side of viewport in current state — if it
  advances a page, MD-paged-mode is real; if it scrolls or shows
  chrome, render-pipeline is still scroll-mode.

## Artifacts

- `dev-docs/verification/artifacts/feature-31-r5-01-settings-paged-autoturn-on-3s-20260515.png`
  — Reading Settings sheet expanded; **Paged** selected, **Auto
  Page Turn: ON**, **Interval: 3s**. Direct evidence the launch flag
  + pre-launch defaults applied to the MD reader's settings layer.
- `dev-docs/verification/artifacts/feature-31-r5-02-after-6s-wait-20260515.png`
  — Reader 6s after sheet dismissal; content unchanged (same prose
  visible as at t=0). Either at-last-page short-circuit, scroll-mode
  render, or layout chrome mismatch — cannot distinguish from this
  evidence alone.
- `dev-docs/verification/artifacts/feature-31-r5-snapshot-after-6s-wait-20260515.json`
  — DebugBridge snapshot: `currentBookId` set, `format: "md"`,
  `renderPhase: "idle"`, `theme: "dark"`, `fontSize: 18`. Confirms
  the book IS opened and the production reader pipeline is the one
  responsible for what's on screen.

## Verdict

`partial`. Net delta from round-4: the open-path blocker is lifted
(Bug #191 fix landed + verified earlier this session). The MD reader
opens cleanly with `--seed-md-multi-page --reader-default-layout=paged`
+ pre-launch auto-page-turn defaults, and the Settings panel
confirms Paged + Auto Page Turn ON + 3s interval are the active
state. The remaining round-4 deferrals — actual visible page-advance
behavior — are still unobservable in a casual 6s screenshot wait. No
new bug filed: round-5's evidence is consistent with the
already-documented round-3 finding that MD-paged-mode chrome
behavior + at-last-page short-circuit need a more targeted
verification path (right-side-tap probe, or a `vreader-debug://`
extension that snapshots `MDReaderContainerView.isPagedMode` +
`AutoPageTurner.state`). Status stays DONE pending a follow-up round
that can distinguish "auto-turn fired but didn't visibly advance"
from "auto-turn never fired because the page-count is 1".

**Suggested round-6 recipe** (out of scope for this round): same
launch setup, then within the reader (a) tap right side of viewport
and screenshot — if page advances, paged-mode render is real; (b)
fire `vreader-debug://snapshot` mid-3s-interval and inspect a future
`autoPageTurnerState` field (would require a `vreader-debug://`
extension); (c) capture `xcrun simctl spawn booted log stream
--predicate 'process == "vreader"'` during the wait to see if
`AutoPageTurner.fireAdvance` is invoked.
