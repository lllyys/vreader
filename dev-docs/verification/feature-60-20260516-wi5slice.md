---
kind: feature
id: 60
status_target: IN PROGRESS
commit_sha: b2b1f985f0b1cf85eb74717d6e7c1d35ed7ea6c5
app_version: 3.23.12 (build 389)
date: 2026-05-16
verifier: claude (verify-cron)
device_or_simulator: iPhone 17 Pro Simulator
os_version: iOS 26.5
build_configuration: Debug
backend: n/a (DebugBridge + bundled war-and-peace.txt fixture)
result: partial
---

# Feature #60 WI-4 + WI-5 slice verify (3 reachable themes on TXT)

Slice verification picked up by verify-cron after WI-4 (EPUB CSS,
PR #753) and WI-5 (TXT + MD theme injection, PR #754) shipped today.
WI-4's PR Gate 5a covered Paper only; WI-5's PR Gate 5a covered
Paper only — sepia + dark deferred. This round closes the sepia +
dark TXT slices on a fresh post-WI-5 build.

OLED + Photo themes are NOT reachable from `ReaderSettingsStore.theme`
(still the legacy 3-case enum); they become reachable only after a
later WI migrates the settings type. Out of slice scope here.

## Acceptance criteria (subset under test — partial slice toward (c))

The row's full acceptance criterion (c) is "All 5 themes render
correctly including Photo". This slice closes 3 of the 5 (paper /
sepia / dark) by verifying the V2 token routing through the legacy
projection works end-to-end on TXT.

| Criterion | Observed | Pass/Fail |
|---|---|---|
| (c.1) Paper theme renders with V2 paper tokens on TXT | `vreader-debug://theme?mode=light` → outer bg = warm cream `rgb(244,238,224)`, ink = warm dark `rgb(29,26,20)` per `feature-60-wi-4-paper-rendered-20260516.png` (from WI-4 slice). Distinct from legacy `light` (255,255,255 / 25,25,25). | **PASS** |
| (c.2) Sepia theme renders with V2 sepia tokens on TXT | `vreader-debug://theme?mode=sepia` → outer bg = tan `rgb(230,214,182)`, ink = brown `rgb(58,41,19)` per `feature-60-wi5slice-sepia-20260516.png`. Visibly warmer/tanner than paper. | **PASS** |
| (c.3) Dark theme renders with V2 dark tokens on TXT | `vreader-debug://theme?mode=dark` → outer bg = warm dark `rgb(26,24,21)`, ink = warm light `rgb(216,210,197)` per `feature-60-wi5slice-dark-20260516.png`. Visibly warmer than legacy dark (28,28,30 / 234,234,237). | **PASS** |
| (c.4) OLED theme | NOT reachable — `ReaderSettingsStore.theme` still 3-case enum; deferred to a later WI that migrates settings type. | **DEFERRED** |
| (c.5) Photo theme | Same as OLED — not reachable + needs ThemeBackgroundStore plumbing for WKWebView access scope (also deferred per WI-4 plan). | **DEFERRED** |

## Commands run

```bash
# v3.23.12 build 389 already installed from WI-5 Gate 5a.
xcrun simctl listapps booted | grep -A 3 "com.vreader.app\"" | grep -E "CFBundle(Version|ShortVersionString)"
# → CFBundleVersion = 389

# Drive theme switches via DebugBridge — TXT reader already open
# (war-and-peace from prior WI-4/WI-5 verify sessions).
xcrun simctl openurl booted "vreader-debug://theme?mode=light"
# (already paper from prior session — confirmed via screenshot)
xcrun simctl openurl booted "vreader-debug://theme?mode=sepia"
xcrun simctl io booted screenshot /tmp/verify-feature60-sepia.png
xcrun simctl openurl booted "vreader-debug://theme?mode=dark"
xcrun simctl io booted screenshot /tmp/verify-feature60-dark.png
```

## Observations

- All 3 reachable themes flip correctly via `vreader-debug://theme`
  with no observable lag — confirms the V2 token routing in
  `ReaderSettingsStore.txtViewConfig` propagates through to the
  UITextView's `backgroundColor` and the attributed-string
  `foregroundColor` instantly on theme change.
- The persisted yellow `Prince` highlight from prior WI-4 verify
  sessions survives all theme flips. Its rendering matches the
  legacy yellow (NOT a V2-themed accent) — this is expected; named
  highlight colors (Feature #60 WI-3 `NamedHighlightColor.yellow` =
  `#f0d25a`) ship in WI-7 when the SelectionPopover replaces the
  current 4-item UIMenu.
- Sepia's bg (rgb 230,214,182) is visibly warmer/tanner than
  paper's (244,238,224) — distinct enough for users to recognise
  the theme switch end-to-end.
- Dark's bg (rgb 26,24,21) is visibly warmer than the legacy dark
  (28,28,30) by a small amount — the chroma shift from neutral-grey
  to warm-dark is subtle but matches the design's "warm-dark" intent.

## Artifacts

- `dev-docs/verification/artifacts/feature-60-wi-4-paper-rendered-20260516.png` — paper theme on TXT (from WI-4 Gate 5a)
- `dev-docs/verification/artifacts/feature-60-wi-5-txt-paper-rendered-20260516.png` — paper theme on TXT (from WI-5 Gate 5a, same fixture)
- `dev-docs/verification/artifacts/feature-60-wi5slice-sepia-20260516.png` — sepia theme on TXT (this slice)
- `dev-docs/verification/artifacts/feature-60-wi5slice-dark-20260516.png` — dark theme on TXT (this slice)

## Verdict

- **Acceptance criterion (c)**: 3/5 themes (paper/sepia/dark) verified
  end-to-end on TXT. OLED + Photo deferred — not reachable from the
  current `ReaderSettingsStore.theme` 3-case enum + `Photo` also
  needs the deferred ThemeBackgroundStore plumbing.
- Feature #60 row stays at **IN PROGRESS** (5 of 10 WIs shipped).
- This slice does NOT change row status; just documents 3/5 of (c).
- A later WI that migrates `ReaderSettingsStore.theme` to V2 will
  unblock OLED + Photo verification; final acceptance pass (Gate 5b)
  happens after the final WI ships.

No bugs filed — all 3 reachable themes pass.
