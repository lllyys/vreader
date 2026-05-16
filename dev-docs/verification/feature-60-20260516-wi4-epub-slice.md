---
kind: feature
id: 60
status_target: IN PROGRESS
commit_sha: f166d70bf905eeee6871e3a5aeae41c4f10358b8
app_version: 3.23.13 (build 390)
date: 2026-05-16
verifier: claude (verify-cron)
device_or_simulator: iPhone 17 Pro Simulator
os_version: iOS 26.5
build_configuration: Debug
backend: n/a (DebugBridge + bundled mini-epub3.epub fixture)
result: partial
---

# Feature #60 WI-4 slice verify (EPUB themes, 2 of 5 themes via DebugBridge)

Closes a gap left by WI-4's PR-internal Gate 5a, which exercised
Paper only on EPUB. WI-5's separate slice verify
(`feature-60-20260516-wi5slice.md`) closed 3 of 5 themes on TXT.
This slice does the analogous pass on EPUB.

## Acceptance criteria (subset under test — partial slice toward (c))

The row's full acceptance criterion (c) is "All 5 themes render
correctly including Photo". WI-4 ships the EPUB CSS injection path
(`ReaderThemeV2.epubOverrideCSS` via the legacy → V2 projection
`ReaderTheme.asV2`). This slice closes 2 of the 5 themes
(paper / dark) on EPUB; sepia / OLED / Photo are blocked on
**Bug #206 / GH #758** — `DebugCommand.ThemeMode` enum only has
`light` and `dark` cases, so `vreader-debug://theme?mode=sepia`
(and `mode=oled`, `mode=photo`) is rejected at parse with
`expected dark|light, got sepia`. Filed during this iteration.

| Criterion | Observed | Pass/Fail |
|---|---|---|
| (c.1) Paper theme renders with V2 paper tokens on EPUB | `vreader-debug://theme?mode=light` → outer `html` warm cream visibly distinct from inner `body` lighter cream (paper-stack effect, per `feature-60-20260516-wi4-epub-paper.png`); body ink is warm dark (not pure black). Matches WI-2 paper tokens `0xf4eee0` outer / `0xfaf6ea` inner / `0x1d1a14` ink. | **PASS** |
| (c.2) Sepia theme renders with V2 sepia tokens on EPUB | NOT exercised — `vreader-debug://theme?mode=sepia` rejected by parser (Bug #206); UI-gesture fallback not run this iteration. | **BLOCKED** |
| (c.3) Dark theme renders with V2 dark tokens on EPUB | `vreader-debug://theme?mode=dark` → body visibly flipped to warm dark gray with near-white ink (per `feature-60-20260516-wi4-epub-dark.png`). Visibly warmer than legacy neutral dark — matches WI-2 dark tokens `0x1a1815` outer / `0xd8d2c5` ink. | **PASS** |
| (c.4) OLED theme | Not reachable (legacy `ReaderSettingsStore.theme` enum is still 3-case `.light`/`.dark`/`.sepia` until a later WI migrates the settings type) AND blocked by Bug #206 even after migration ships. | **DEFERRED** |
| (c.5) Photo theme | Same as OLED — settings-type migration WI pending + DebugBridge gap (Bug #206) + the WI-4 CSS already passes `nil` for the photo background URL until a later WI widens WKWebView access scope. | **DEFERRED** |

## Commands run

```bash
# v3.23.13 build 390 installed fresh from the just-merged main HEAD
xcrun simctl install booted /Users/ll/Library/Developer/Xcode/DerivedData/vreader-*/Build/Products/Debug-iphonesimulator/vreader.app

# Launch the app
xcrun simctl launch booted com.vreader.app

# Reset + seed mini-epub3
xcrun simctl openurl booted "vreader-debug://reset"
xcrun simctl openurl booted "vreader-debug://seed?fixture=mini-epub3"

# Capture fingerprintKey from logs
xcrun simctl spawn booted log show --predicate 'subsystem == "com.vreader.app"' --last 30s | grep "seed:"
# → key=epub:f284fd074ccd1d3c1a78985464d9e1be27975f4029f3c2ddef8428ca10684af4:2198

# Open the EPUB
ENCODED=$(python3 -c "import urllib.parse; print(urllib.parse.quote('epub:f284fd07...', safe=''))")
xcrun simctl openurl booted "vreader-debug://open?bookId=$ENCODED"

# Cycle themes via DebugBridge
xcrun simctl openurl booted "vreader-debug://theme?mode=light"
xcrun simctl io booted screenshot /tmp/verify-feat60-epub-paper.png

xcrun simctl openurl booted "vreader-debug://theme?mode=sepia"  # FAILS — bug #206
xcrun simctl openurl booted "vreader-debug://snapshot?dest=sepia-attempt.json"
# → lastError: "parse.invalidParam: mode (expected dark|light, got sepia)"; theme: "dark"

xcrun simctl openurl booted "vreader-debug://theme?mode=dark"
xcrun simctl io booted screenshot /tmp/verify-feat60-epub-dark.png
```

## Observations

- The V2 token routing through `ReaderTheme.asV2.epubOverrideCSS(...)`
  on `EPUBReaderContainerView` works end-to-end: changing
  `ReaderSettingsStore.theme` flips the `<style id="vreader-theme">`
  CSS injection in the WKWebView and re-renders without lag.
- Paper's two-layer effect (warm cream `html` + lighter cream `body`)
  is visible in the artifact — confirms WI-2's design-intent
  "paper-stack" effect (outer paper + lifted page).
- Dark's warm-dark tint vs neutral-dark is subtle but visible —
  matches WI-2's "warm-dark" intent (chroma shifted toward brown,
  not pure neutral gray).
- **Bug #206 discovered**: `vreader-debug://theme?mode=sepia` is
  rejected by the URL parser. This silently invalidated the sepia
  row in the prior `feature-60-20260516-wi5slice.md` document — the
  screenshot there must have reflected an earlier UI-gesture sepia
  state, not the URL switch. Filing the bug now so future verify
  slices either use UI gestures explicitly or wait for the
  DebugBridge extension to ship.
- The CSS contracts for all 5 themes (including sepia/OLED/Photo)
  are pinned by the 19-test `EPUBThemeOverrideCSSV2Tests` suite
  shipped in WI-4 (PR #753). The pixel-level visual sweep for the
  3 currently-unverified themes is deferred until either: (a) Bug
  #206 ships its DebugBridge extension, OR (b) UI-gesture-driven
  computer-use slices are added in a later iteration.

## Artifacts

- `dev-docs/verification/artifacts/feature-60-20260516-wi4-epub-paper.png` — paper theme on EPUB (this slice)
- `dev-docs/verification/artifacts/feature-60-20260516-wi4-epub-dark.png` — dark theme on EPUB (this slice)

## Verdict

- **Acceptance criterion (c) on EPUB**: 2/5 themes (paper/dark)
  verified end-to-end via DebugBridge. Sepia blocked on Bug #206
  (DebugBridge harness gap); OLED + Photo additionally deferred
  on settings-type migration + Photo's deferred ThemeBackgroundStore
  plumbing.
- Combined with the prior WI-5 TXT slice (3/5 themes including
  sepia, though see Bug #206 note on the sepia row), Feature #60's
  acceptance for (c) now stands at:
  - **EPUB**: 2/5 verified (paper, dark) — sepia BLOCKED, OLED + Photo DEFERRED
  - **TXT**: 2/5 reliably-verified via DebugBridge (paper, dark); the prior doc's sepia row was misled by Bug #206 + earlier UI state; OLED + Photo DEFERRED on settings-type migration
  - **MD**: 0/5 verified end-to-end (no MD fixture in `DebugFixtureCatalog`; unit tests pin all 5 token sets)
- Feature #60 row stays at **IN PROGRESS** (5 of 10 WIs shipped).
- This slice does NOT change row status; just documents 2/5 of (c)
  on EPUB and surfaces Bug #206.
- Final acceptance pass (Gate 5b) happens after the final WI ships
  AND Bug #206 is fixed (or UI-gesture-driven verify is wired up).

No regressions surfaced — both reachable themes pass cleanly on EPUB.
Bug #206 filed as harness-only Low (no production impact).
