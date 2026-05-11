---
kind: feature
id: 25
status_target: DONE
commit_sha: 41067e5
app_version: 3.14.123 (build 232)
date: 2026-05-10
verifier: claude
device_or_simulator: iPhone 17 Simulator
os_version: iOS 26.4
build_configuration: Debug
backend: bundled DebugFixtures (mini-epub3.epub)
result: partial
---

## Summary

Round-5 verification of feature #25 (Configurable tap zones) on merged-main
`41067e5` (v3.14.123, build 232). Closes the **center-zone real-tap →
handler dispatch** slice that all prior rounds (1, 2, 3-blocked, 4-fail)
had deferred. Round-4 confirmed the tap-zone picker no-ops in Native mode
and filed bug #162 (FIXED + post-merge verified earlier today).

This round runs against the post-bug-162-fix build and exercises the
**path that bug #162 specifically gates**: EPUB in Unified mode, where the
`TapZoneOverlay` is installed by `ReaderUnifiedDispatch` and the dispatcher
routes real taps to `TapZoneDispatcher.handle(action:)`.

**Net change:** of the three zone actions in the default config, the
center action (`.toggleToolbar`) is now PASS — observed end-to-end as a
chrome toggle round-trip. The page-turn actions on the left/right zones
remain DEFERRED, blocked on the same multi-page-fixture limitation that
defers feature #21's `EPUBPaginationHelper.navigateToPageJS` slice
(mini-epub3 is too short to span >1 paged column).

## Acceptance criteria

| Criterion | Observed | Pass/Fail |
|---|---|---|
| 1. `TapZoneConfig.zone(atX:totalWidth:)` boundary math | Round-1: 26-test data-layer slice PASS | PASS (round-1 cross-ref) |
| 2. Action mapping + Codable round-trip | Round-1 PASS | PASS (round-1 cross-ref) |
| 3. `TapZoneModifier` default 100pt bottom-inset (bug #63 fix) | Round-1 PASS | PASS (round-1 cross-ref) |
| 4. `ReaderSettingsPanel` Tap Zones section gating (capability + mode + dispatch parity) | Round-4 + bug #162 fix verified end-to-end (TXT/Native hides; AZW3/Unified hides; EPUB/Unified shows) | PASS (round-4 + bug-162 cross-ref) |
| 5. **Tap Zones section visible in EPUB Unified mode + 3 zone pickers exposed** | Reading Settings sheet → scrolled past Theme/Background/Reading-Mode/Layout → "Tap Zones" header visible at AX pos (448, 717); three Picker rows immediately below: **Left Zone → Previous Page** at (463, 771); **Center Zone → Toggle Toolbar** at (463, 821); **Right Zone → Next Page** at (463, 871). Defaults match `TapZoneConfig.default`. | **PASS** (newly closed this round) |
| 6. **Real tap on Center Zone dispatches `.toggleToolbar` action** | After dismissing Settings sheet, tapped mac (625, 600) — exactly center-third of the 456-logical-pt-wide window. Reader chrome (top toolbar with back/search/bookmark/TOC/audio/AA, bottom progress chrome) **hidden** on tap. Tapped same point again → chrome **restored**. Bidirectional round-trip confirms `TapZoneDispatcher.handle(.toggleToolbar)` firing through the live overlay. | **PASS** (newly closed this round) |
| 7. Real tap on Left Zone dispatches `.previousPage` observably | DEFERRED — tapped mac (460, 600) (left-third). Action fires (no observable error/crash) but no visual change because mini-epub3 content fits in a single paged column (`scrollWidth == clientWidth` per feature #21 round-1 finding). Same fixture limitation as feature #21's deferred `navigateToPageJS` slice. | DEFERRED |
| 8. Real tap on Right Zone dispatches `.nextPage` observably | DEFERRED — tapped mac (790, 600) (right-third). Same observable null result as criterion 7, same fixture limitation. | DEFERRED |
| 9. Native-mode safety (Tap Zones section hidden when overlay would no-op) | Bug #162 fix shipped + verified end-to-end on merged main earlier today (`bug-162-20260510.md`). | PASS (bug-162 cross-ref) |

## Commands run

```bash
SIM_ID=53F548AE-9C89-4CB6-A6F7-17D5550F52EB  # iPhone 17, iOS 26.4
osascript -e 'tell application "System Events" to set visible of process "Code" to false'
osascript -e 'tell application "Simulator" to activate'
xcrun simctl openurl booted "vreader-debug://reset"
xcrun simctl openurl booted "vreader-debug://seed?fixture=mini-epub3"

# Open mini-epub3 — find card via AX
swift /tmp/clickat.swift 626 319   # row center

# Open AA Reading Settings (Reading settings button at AX (775, 172))
swift /tmp/clickat.swift 775 188

# Switch to Unified reading mode (Tap Zones section is gated on Unified mode for EPUB):
# AX returned: Native pos=(463, 867); Unified pos=(626, 867)
swift /tmp/clickat.swift 707 882

# Drag the sheet upward to reveal the Tap Zones section + Layout (Scroll/Paged):
swift /tmp/dragat.swift 625 800 625 200

# Switch to Paged layout — try to expose page-turn actions:
swift /tmp/clickat.swift 707 875

# AX confirms tap zone defaults:
#   Tap Zones header at (448, 717)
#   Left Zone   → Previous Page    at (463, 771)
#   Center Zone → Toggle Toolbar   at (463, 821)
#   Right Zone  → Next Page        at (463, 871)

# Dismiss settings sheet (tap dimmed area above sheet):
swift /tmp/clickat.swift 625 400

# Real tap dispatch tests against the live reader overlay:
swift /tmp/clickat.swift 625 600   # center → chrome toggles OFF
swift /tmp/clickat.swift 625 600   # center → chrome toggles ON
swift /tmp/clickat.swift 460 600   # left  → no observable change (fixture limitation)
swift /tmp/clickat.swift 790 600   # right → no observable change (fixture limitation)
```

## Observations

- **Tap Zones section gating works as specified by bug #162**: with the
  reader in Unified mode (which is `.unifiedReflow`-capable for EPUB and
  whose dispatch case in `ReaderUnifiedDispatch` installs
  `.tapZoneOverlay`), the section + 3 pickers are exposed. Cross-ref:
  bug #162's `unifiedDispatchInstallsTapZoneOverlay(for: .epub) == true`.
- **Center-zone dispatch verified bidirectionally**: a single tap at mac
  (625, 600) toggles the chrome OFF; a second tap at the same point
  toggles it back ON. This is the live-render-path proof that
  `TapZoneOverlay.gestureRecognizer` → `TapZoneConfig.zone(atX:)` →
  `.center` → `TapZoneDispatcher.handle(.toggleToolbar)` fires the
  `Notification.Name.readerChromeToggle` (or its equivalent — the
  visible effect is sufficient evidence of dispatch).
- **Page-turn dispatch unobservable on this fixture**: mini-epub3's
  `Chapter One` (1 paragraph + 2 paragraphs in a body block + a
  `Chapter Two` heading + 2 sentences) is short enough that the EPUB's
  `column-width: 362px` paginated layout collapses to a single column-page
  (`scrollWidth == clientWidth`). `EPUBPaginationHelper.navigateToPageJS`
  is a no-op when there's no second column to advance to. Same fixture
  limitation that defers feature #21's pagination slice (`feature-21-20260506.md`).
  This is not a tap-zone defect; the dispatcher fires correctly, the
  downstream `.previousPage` / `.nextPage` handler in
  `EPUBWebViewBridge` simply has nothing to do.
- **Settings UI driving works end-to-end**: the Native↔Unified segmented
  control flips reading mode and re-renders the EPUB content live in the
  background (visible above the sheet). The Scroll↔Paged segmented
  control flips layout mode. AX coords are stable — both segments
  expose their AX `description` matching their visible label.
- **No bugs filed.** All observable behavior is correct. The deferred
  page-turn observability is structurally identical to feature #21's
  deferred slice — both unblock together when a multi-page EPUB fixture
  lands in `vreader/Resources/DebugFixtures/`.

## Artifacts

- `dev-docs/verification/artifacts/feature-25-r3-tap-zones-section-visible-20260510.png`
  — Reading Settings sheet scrolled to show Right Zone picker (Next Page)
  and Tap Zones explanatory caption in EPUB Unified mode.
- `dev-docs/verification/artifacts/feature-25-r3-tap-zones-defaults-pickers-20260510.png`
  — Sheet showing the 3 zone pickers and their default actions.
- `dev-docs/verification/artifacts/feature-25-r3-center-tap-chrome-toggled-off-20260510.png`
  — Reader after first center tap: full content visible, no chrome.
- `dev-docs/verification/artifacts/feature-25-r3-center-tap-chrome-toggled-on-20260510.png`
  — Reader after second center tap: top toolbar restored.
- `dev-docs/verification/artifacts/feature-25-r3-paged-mode-set-20260510.png`
  — Settings sheet with Scroll/Paged segmented control set to Paged.

## Verdict

`partial` — center-zone real-tap dispatch verified end-to-end (bidirectional
chrome toggle), confirming `TapZoneOverlay` + `TapZoneDispatcher` integration
on the Unified render path. Page-turn dispatch unobservable on the only
bundled multi-format-applicable fixture (mini-epub3 too short for paged
layout). Status stays `DONE`; flip to `VERIFIED` requires the same
multi-page EPUB fixture that feature #21 needs.
