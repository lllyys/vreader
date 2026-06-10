---
kind: feature
id: 53
status_target: VERIFIED
commit_sha: 6936ccf848c75770b0ea1801477e7c0e49ca48fa
app_version: 3.27.23 (build 437)
date: 2026-05-18
verifier: claude (verify-cron)
device_or_simulator: iPhone 17 Pro Simulator
os_version: iOS 26.4
build_configuration: Debug
backend: n/a (DebugBridge + bundled mini-epub3 fixture)
result: partial
---

# Feature #53 round-6 EPUB device verification (post Bug #211 / #212 fix)

Round-5 (`feature-53-20260517-round5.md`, result=partial) device-verified
the **EPUB** tap-on-highlight path and found **criterion (a) FAILING**:
tapping a yellow EPUB highlight surfaced no inline menu. Two EPUB-path
defects were filed and have since shipped:

- **Bug #211 / GH #820** — the WI-4 `click`-listener hit-test in
  `EPUBHighlightJS.swift` used `Range.END_TO_START` where it needed
  `Range.START_TO_END`, so every in-range tap missed. Fixed, merged,
  CLOSED (GH #820 still carries `awaiting-device-verification`).
- **Bug #212 / GH #828** — EPUB tap-Delete cleared persistence + JS
  state but left the on-screen highlight paint stale. Fixed, merged,
  CLOSED.

This round re-runs the round-5 repro against current `main`
(v3.27.23 build 437, commit `6936ccf`) to confirm the EPUB path and
serves as the close-gate device verification for Bug #211 and #212.

## Scope

EPUB format only, using the bundled `mini-epub3` DebugBridge fixture.
Criteria (a), (b), (d) for EPUB. Criterion (c) (consistency across all
5 formats) is **not** closed this round — see "Deferred / out of scope".
Verification only: no code was changed.

## Acceptance criteria

| # | Criterion | Result | Observed |
|---|-----------|--------|----------|
| (a) | Tapping a highlighted word shows a menu with at minimum a Delete option | **PASS** (EPUB) | Created a yellow highlight on the word "incididunt" (long-press → SelectionPopover → yellow swatch; DebugBridge `highlightCount` 0→1). Tapping the highlighted word surfaced an inline **"Delete Highlight"** menu anchored below the word. Reproduced 2× this round. This is the exact path round-5 found failing — the Bug #211 fix works. |
| (b) | Delete removes the highlight visually and from persistence | **PASS** (EPUB) | Tapped "Delete Highlight" → the yellow paint disappeared from "incididunt" (zoom-confirmed, no stale paint — the Bug #212 fix works) AND DebugBridge `highlightCount` went 1→0. Reproduced 2×. |
| (c) | Consistent across all 5 formats | **NOT VERIFIED** | TXT passes (round-4); EPUB passes (this round); MD/PDF/Foliate not exercised. See "Deferred / out of scope". |
| (d) | Tapping non-highlighted text preserves existing scroll/chrome-toggle behavior | **PASS** (EPUB) | Tapped a non-highlighted word ("dolor") and blank content area → the reader chrome toggled (top bar + bottom toolbar showed/hid), no menu appeared. The pre-existing EPUB content-tap → chrome-toggle behavior is intact. |

## Commands run

```bash
SIM=61149F0E-DC18-4BE2-BB37-52659F1F4F62   # iPhone 17 Pro, iOS 26.4

# Clean main build (commit 6936ccf, v3.27.23/437) installed (no uninstall — install replaces)
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild build \
  -project vreader.xcodeproj -scheme vreader \
  -destination 'id=61149F0E-DC18-4BE2-BB37-52659F1F4F62'
xcrun simctl install "$SIM" .../Debug-iphonesimulator/vreader.app

# Launch with DebugBridge, reset, seed the EPUB fixture
xcrun simctl launch "$SIM" com.vreader.app --uitesting
xcrun simctl openurl "$SIM" "vreader-debug://reset"
xcrun simctl openurl "$SIM" "vreader-debug://seed?fixture=mini-epub3"
xcrun simctl openurl "$SIM" "vreader-debug://theme?mode=light&fontSize=34"

# State assertions
xcrun simctl openurl "$SIM" "vreader-debug://snapshot?dest=f53r6-after-highlight.json"  # highlightCount: 1
xcrun simctl openurl "$SIM" "vreader-debug://snapshot?dest=f53r6-after-delete.json"     # highlightCount: 0
xcrun simctl openurl "$SIM" "vreader-debug://snapshot?dest=f53r6-final.json"            # highlightCount: 0
```

Gestures (long-press to create the highlight, tap-on-highlight,
tap "Delete Highlight", tap-on-non-highlighted-word) were driven via
the computer-use MCP against the Simulator window. The installed
binary is a clean `main` build at commit `6936ccf` — version-verified
3.27.23 (build 437) from the bundle `Info.plist`.

## Observations

- The round-5 failure is fully cleared. The EPUB tap-on-highlight path
  now behaves identically to the TXT path verified in round-4: a single
  tap on a painted highlight surfaces the red "Delete Highlight" pill.
- One test-procedure note: immediately after creating a highlight via
  the SelectionPopover, the WKWebView's *native* text selection of the
  word remains active. Tapping the just-highlighted word while that
  native selection is live re-shows the iOS system edit menu
  (Copy / Look Up / Translate) instead of the feature-#53 menu. Tapping
  anywhere else once (clearing the native selection) and then tapping
  the highlight surfaces the "Delete Highlight" menu correctly. This is
  the realistic user flow (selection naturally clears between
  highlighting and a later revisit), so it is not a feature-#53 defect —
  but it is a minor UX seam worth noting for a future polish pass.
- The Bug #212 fix is visibly effective: the highlight paint refreshes
  off-screen the instant Delete is tapped, with no stale residue.

## Deferred / out of scope (criterion c)

- **TXT**: passed in round-4 (`feature-53-20260517-round4.md`).
- **EPUB**: passed this round.
- **MD**: shares the TXT `HighlightableTextView` bridge; not separately
  exercised — `DebugFixtureCatalog` ships no MD fixture (txt, epub,
  azw3 only). MD scroll-mode would need the `--seed-md-multi-page`
  TestSeeder path. Deferred.
- **PDF**: separate PDFKit renderer path; `DebugFixtureCatalog` has no
  PDF fixture. Not exercised — harness gap.
- **AZW3/MOBI (Foliate)**: inline-menu consumer wiring is a known gap
  tracked as **Bug #199 / GH #733**. Foliate cannot pass criterion (a)
  until that lands.
- Criterion (c) cannot close until MD, PDF, and Foliate (Bug #199) are
  all verified.

## Outcome

Feature #53 row stays **DONE**. Round-6 confirms **EPUB criteria (a),
(b), (d) all PASS** — round-5's PARTIAL is reversed. This run also
serves as the close-gate device verification for **Bug #211 / GH #820**
and **Bug #212 / GH #828** (both EPUB tap-on-highlight defects, both
already merged + CLOSED). The `VERIFIED` flip remains gated on MD, PDF,
and Foliate (Bug #199) device verification.

This round is verification-only: no bug was discovered, no code changed.

## Artifacts

- `artifacts/feature-53-r6-epub-highlight-present-20260518.png` — the
  EPUB reader with the yellow highlight painted on "incididunt".
- `artifacts/feature-53-r6-epub-delete-menu-20260518.png` — after
  tapping the highlight: the inline "Delete Highlight" menu (criterion
  (a) PASS).
- `artifacts/feature-53-r6-epub-after-delete-20260518.png` — after
  tapping "Delete Highlight": the highlight paint is gone (criterion
  (b) PASS).
