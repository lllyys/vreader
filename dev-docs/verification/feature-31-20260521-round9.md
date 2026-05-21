---
kind: feature
id: 31
status_target: VERIFIED
commit_sha: aedcee234ed87fd3a2c5e41ab639a7addf2c11c9
app_version: 3.39.1 (build 622)
date: 2026-05-21
verifier: claude (verify-cron, CU-free DebugBridge position-delta)
device_or_simulator: iPhone 17 Pro Simulator (1FAB9493-B97E-48F0-96C7-44A8E5AAA21E)
os_version: iOS 26.x
build_configuration: Debug
backend: n/a (DebugBridge + --seed-md-multi-page fixture)
result: partial
---

# Feature #31 round-9 — round-8 blockers lifted, NEW root cause found: auto-turn timer advance never reaches the MD paged view

## Context

Rounds 4-8 all returned `partial`. The round-8 (2026-05-20) blocker was
**Bug #215 Cause 2** (MD paged-mode ReaderBottomChrome occlusion + missing
TapZoneOverlay producer) intersecting **Bug #239** (paged side-tap dead
across all native readers — feature #54 WI-3 deleted the `TapZoneOverlay`
page-turn producer). Both are now **FIXED on main** at v3.39.1:

- **Bug #215 / GH #837** → FIXED in PR #1100 (`d278163a`, v3.38.35): MD paged
  layout engages — pagination viewport parity (Cause 1), chrome-aware content
  inset (Cause 2a), de-duplicated page indicator (Cause 2b), tap-zone routing
  via `ReaderTapZoneRouter` (Cause 2c).
- **Bug #239 / GH #988** → FIXED in PR #1098 (`bd7564c7`, v3.38.33): paged
  side-tap producer restored via `ReaderTapZoneRouter`.

Round-9 re-runs the core criterion-5 check at v3.39.1 to determine whether the
`VERIFIED` flip is now unblocked.

**Auto page turning is timer-driven** (`AutoPageTurner.scheduleTimer` calls
`navigator.nextPage()` on a `Task.sleep` loop — no gesture needed), so this
round verifies it **CU-free** via `snapshot.position` deltas over time +
`simctl io` screenshots. CU was not used (and not needed).

## Acceptance criteria

Feature row contract: *auto-page-turn advances pages over a configurable
interval in paged mode.* (`FormatCapabilities.autoPageTurn` is unioned into
the `.md` branch ONLY — round-7 established MD is the entire feature; TXT lost
the capability via bug #157's gate and has no `NativeTextPagedView` branch at
all, EPUB/PDF/AZW3 never had `AutoPageTurner` wiring.)

| # | Criterion | Result | Observed |
|---|-----------|--------|----------|
| 1 | Settings UI surface: Auto Page Turn toggle exposed in MD paged mode (via `FormatCapabilities.autoPageTurn`) | **PASS (unchanged, round-2)** | Capability + UI plumbing unchanged. MD-only by `FormatCapabilities` (round-7 confirmed). |
| 2 | Toggle reveal: sustained-press toggle reveals/hides Interval slider | **PASS (unchanged, round-2)** | UI behavioral surface unchanged. |
| 3 | Toggle persistence: settings persist across reader panel re-open | **PASS (unchanged, round-2)** | `UserDefaults`-backed; verified pre-launch persist via `defaults write` (`readerAutoPageTurn=1`, `readerAutoPageTurnInterval=2`, `readerEPUBLayout=paged` all read back correctly). |
| 4 | `AutoPageTurner` unit logic: timer state machine, interval reschedule, animation primitives, NaN/recursion guards | **PASS (unchanged)** | 24 tests in `AutoPageTurnerTests.swift` + `PageTurnAnimatorTests.swift`. **Note**: these use a `MockNavigator` and assert `nextPageCallCount` / `currentPage` on the mock — they verify the timer FIRES `nextPage()`, but do NOT exercise the `NativeTextPagedView` / `pagedCurrentPage` view-sync (the gap criterion 5 fails on). |
| 5 | **Live multi-page advancement**: auto-page-turn timer advances pages over the configured interval in MD paged mode (the feature's core behavior) | **FAIL (new root cause; previously blocked by #215/#239)** | At v3.39.1 with `readerEPUBLayout=paged` + `readerAutoPageTurn=true` + interval=2.0 pre-launched, opened the seeded MD multi-page book ("Test Markdown Multi-Page", paginates to **6 pages** — indicator reads "Page 1 of 6", confirming Bug #215 is fixed and pagination engages). Two independent runs: (a) snapshots at open / +10s / +20s → `position` = **"0" / "0" / "0"** (10× the 2s interval, no gesture); (b) clean re-launch, open, **16s fully untouched** (no intervening `openurl`) → `position` = **"0"**, screenshot still **"Page 1 of 6"**. **Zero advancement.** This is NOT the round-8 chrome-occlusion symptom — the page renders cleanly above the chrome and the indicator is visible; the page simply never turns. NEW root cause filed as **Bug #258 / GH #1125** (see below). |

`result: partial` — criteria 1-4 PASS; criterion 5 **FAIL** with a newly
root-caused defect distinct from the round-8 blockers (which are now fixed).
Feature #31 stays `DONE`. A bug was filed (verification-only — not fixed here).

## Root cause (newly identified — Bug #258 / GH #1125)

`AutoPageTurner.scheduleTimer()` (`vreader/Services/AutoPageTurner.swift:130`)
advances pages by calling `navigator.nextPage()` **directly** on the
`NativeTextPageNavigator` (mutating its internal `base.currentPage`). It does
NOT post `.readerNextPage` and does NOT call `syncPagedState()`.

But the MD paged view renders from the **explicit `currentPage: Int` parameter**
bound to `uiState.pagedCurrentPage`, not from `navigator.currentPage`:

- `MDReaderContainerView.swift:394` → `NativeTextPagedView(... currentPage: uiState.pagedCurrentPage ...)`.
- `NativeTextPagedView.swift:34-35` comment: *"Explicit page index so SwiftUI detects page changes and triggers updateUIView."* `updateUIView` only fires when this param changes (`NativeTextPagedView.swift:55-73`).
- `uiState.pagedCurrentPage` is copied from `navigator.currentPage` **only** inside `TextReaderUIState.syncPagedState()` (`TextReaderUIState.swift:78-85`), which is called **only** from the `.readerNextPage` / `.readerPreviousPage` notification observers (`MDReaderContainerView.swift:247-262`) and `updatePaginationIfNeeded` — paths that auto-turn bypasses entirely.

So the timer mutates navigator state the view does not observe:
1. View never re-renders (`updateUIView` not triggered → page text unchanged).
2. `viewModel.totalProgression` never updates → `.readerPositionDidChange`
   never posts → `snapshot.position` stays flat.

The fix is a one-liner-class change (have `AutoPageTurner` post `.readerNextPage`
instead of calling `nav.nextPage()` directly, OR have the container observe the
navigator's page and re-sync `pagedCurrentPage` on each tick) — but **this round
is verification-only; the bug is filed, not fixed.**

This finally root-causes the "deferred live-advancement" thread that has run
since round-1 (2026-05-07) and was variously masked by Bug #191 (AutoPageTurner
recursion crash, FIXED), the fixture-size blocker (rounds 2-3), Bug #215 (paged
layout, FIXED PR #1100), and Bug #239 (side-tap producer, FIXED PR #1098). With
all of those resolved, the residual failure is this AutoPageTurner→view sync gap.

## What this round settles

- Round-8's two blockers (Bug #215, Bug #239) are **confirmed fixed** at
  v3.39.1: MD paged mode engages, renders 6 clean pages, shows "Page 1 of 6",
  no chrome occlusion. The round-8 disposition ("VERIFIED gated on Bug #215")
  is now obsolete.
- The criterion-5 failure is **no longer a layout/chrome/tap-producer problem**
  — it is a distinct AutoPageTurner→`pagedCurrentPage` view-sync defect that
  was previously hidden behind the layout bug.
- PR #1100's commit message explicitly deferred "the design's §3.4
  auto-page-turn ribbon ... Feature #31's verification needs the ribbon; that
  round can resume independently once this lands." This round finds the gap is
  **deeper than the ribbon UI** — the timer's advance never reaches the view at
  all, so even with a ribbon the page would not turn. The bug is the wiring,
  not a missing affordance.

## Commands run

```bash
SIM=1FAB9493-B97E-48F0-96C7-44A8E5AAA21E   # iPhone 17 Pro Simulator, booted

# Build at main HEAD aedcee23 (v3.39.1) into worktree-local DerivedData
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild build \
  -project vreader.xcodeproj -scheme vreader \
  -destination "platform=iOS Simulator,id=$SIM" \
  -derivedDataPath build/verify-31

# Resolve app via BUILT_PRODUCTS_DIR (NOT a global find), install
APP=build/verify-31/Build/Products/Debug-iphonesimulator/vreader.app
xcrun simctl install "$SIM" "$APP"   # /usr/libexec/PlistBuddy confirmed CFBundleShortVersionString=3.39.1

# Pre-launch defaults (persist auto-page-turn + interval + paged layout;
# NO --reset-preferences so they survive the seed)
xcrun simctl spawn "$SIM" defaults write com.vreader.app readerEPUBLayout paged
xcrun simctl spawn "$SIM" defaults write com.vreader.app readerAutoPageTurn -bool true
xcrun simctl spawn "$SIM" defaults write com.vreader.app readerAutoPageTurnInterval -float 2.0
# read-back: readerAutoPageTurn=1, readerAutoPageTurnInterval=2, readerEPUBLayout=paged ✓

# Launch with the multi-page MD seed (Feature #45 WI-5 fixture)
xcrun simctl launch "$SIM" com.vreader.app \
  --uitesting --seed-md-multi-page --reader-default-layout=paged

# Seeded book fingerprintKey (from on-disk ImportedBooks filename, 9231 bytes):
KEY="md:0000000000000000000000000000000000000000000000000000000000c0c002:9231"

# Open via DebugBridge (URL-encoded), snapshot the position over time
xcrun simctl openurl "$SIM" "vreader-debug://open?bookId=<urlencoded KEY>"
xcrun simctl openurl "$SIM" "vreader-debug://snapshot?dest=s1.json"   # position: "0"
sleep 10
xcrun simctl openurl "$SIM" "vreader-debug://snapshot?dest=s2.json"   # position: "0"
sleep 10
xcrun simctl openurl "$SIM" "vreader-debug://snapshot?dest=s3.json"   # position: "0"

# Clean re-test: relaunch, open, 16s UNTOUCHED (no intervening openurl), single snapshot
xcrun simctl openurl "$SIM" "vreader-debug://snapshot?dest=sclean.json"  # position: "0"
xcrun simctl io "$SIM" screenshot <artifact>.png   # still "Page 1 of 6"

# Snapshot read-back path:
CONTAINER=$(xcrun simctl get_app_container "$SIM" com.vreader.app data)
cat "$CONTAINER/Library/Caches/DebugBridge/<dest>.json"
```

## Observations

- **Pagination engages correctly now** (`position: "0"` is authoritative — no
  longer in the snapshot's `partial` array, unlike pre-#215 builds; the indicator
  shows 6 pages). Bug #215's Cause 1 (viewport parity) is genuinely fixed — the
  prose renders cleanly with no mid-line clip.
- **The timer demonstrably started**: `settingsStore.autoPageTurn=true` (pre-launched
  default confirmed) + `pageNavigator` non-nil (pagination ran, `totalPages=6`) means
  `TextReaderUIState.updateAutoPageTurner`'s guard (`enabled, isPagedMode, pageNavigator != nil`)
  passes → `turner.start(navigator: nav)` is called. Nothing on the open/settle path posts
  `.readerContentTapped` (the only thing that would `pause()` the turner), so the timer runs.
- The defect is purely the **AutoPageTurner→view observable-state bridge**. The
  `AutoPageTurnerTests` MockNavigator approach is exactly why criterion 4 passes while
  criterion 5 fails: the unit tests prove `nextPage()` fires; nothing tests that a
  timer-driven `nextPage()` re-renders `NativeTextPagedView` or moves `snapshot.position`.
- This is a **timer-driven CU-free verification success** for the harness: the
  position-delta + screenshot method cleanly distinguished "advances" from "doesn't"
  without computer-use. CU was not needed and not used.
- **Disposition**: criterion 5 FAILS with a genuine product defect (auto page turning
  is non-functional end-to-end), so this is `partial` (criteria 1-4 still pass) and a
  bug is filed. Per the brief + rule (verification-only), the bug is NOT fixed here.

## Artifacts

- `dev-docs/verification/artifacts/feature-31-r9-md-paged-after-20s-autoturn-20260521.png`
  — MD paged mode engaged, "Page 1 of 6", clean content above chrome; after 20s
  (10× the 2s interval) the page has NOT advanced.
- `dev-docs/verification/artifacts/feature-31-r9-md-paged-clean-16s-untouched-20260521.png`
  — clean re-run: 16s fully untouched (no intervening DebugBridge calls), still
  "Page 1 of 6". Rules out any interference from the snapshot `openurl` calls.

## Outcome

Feature #31 stays **DONE**. Round-9 confirms the round-8 blockers (Bug #215,
Bug #239) are fixed and MD paged mode now engages cleanly, but finds that the
**core auto-page-turn behavior is still non-functional**: `AutoPageTurner`
advances the navigator's internal page on its timer, but that advance never
syncs to the observable `uiState.pagedCurrentPage` that drives both the view
render and `snapshot.position`. Filed as **Bug #258 / GH #1125**. The
`VERIFIED` flip is now gated on Bug #258's fix (a code-only change — the design
for MD paged-mode chrome/indicator already landed in PR #1100). No code changed
in this verification round.
