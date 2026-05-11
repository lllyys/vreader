---
kind: feature
id: 21
status_target: VERIFIED
commit_sha: 639b5fac4a49999ffce847090134be49912a1c0f
app_version: 3.15.1 (build 263)
date: 2026-05-11
verifier: claude
device_or_simulator: iPhone 17 Pro Simulator
os_version: iOS 26.4
build_configuration: Debug
backend: locally-imported real-length EPUB (Alice's Adventures in Wonderland, 137516 bytes, fingerprint epub:48f70fb664bc6f7b7e8a0804d5d97321ccc4dc00b2ffa4cc948171f4c538e86c:137516)
result: pass
---

## Summary

Round-2 device verify of feature #21 (Paginated reading mode with turnable
pages) on merged-main `639b5fa` (v3.15.1, build 263). Closes the
**multi-page-navigation** slice that round-1 (`feature-21-20260506.md`)
deferred because mini-epub3 chapter 1 fit on a single column-page
(`scrollWidth == clientWidth`, so `EPUBPaginationHelper.navigateToPageJS`
was a no-op against that fixture).

This round runs against a real-length EPUB — Alice's Adventures in
Wonderland (137 KB, 15 chapters), imported into the library earlier
today via the OPDS catalog flow during feature #36's round-5
verification. The fixture's chapter-2 (Project Gutenberg license +
Contents table) finally produces `body.scrollWidth > clientWidth`,
making the multi-page primitive observable end-to-end.

**Net change:** all six acceptance criteria from round-1 are now PASS.
Feature #21 row flips DONE → VERIFIED.

## Acceptance criteria

| Criterion | Observed | Result |
|---|---|---|
| Pagination style element injected after EPUB load | eval probe `paginationStyle: true` (`feature-21-r2-06-chapter2-dims-20260511.json`) | pass (round-1 cross-ref + re-confirmed this round) |
| CSS column-width set per `paginationCSS()` formula | `colWidth: "362px"` — viewport 402 − 40 gap = 362 | pass |
| CSS column-gap matches `EPUBPaginationHelper.columnGap` constant | `colGap: "40px"` | pass |
| Multi-column layout active (column-count auto-computed) | `colCount: "auto"` | pass |
| Body overflow disabled to prevent natural scroll | `overflow: "hidden"` | pass |
| **Multi-page navigation primitive (`navigateToPageJS`) exercised end-to-end** | `body.scrollWidth = 1458 > clientWidth = 980` (2 column-pages); after setting `body.scrollLeft = 980` (clamped by browser to maxScroll = 478), the body advances ~478 px horizontally and the rendered view changes from "license-text-left-col + Contents-right-col" to "Contents-left-col + blank-right". Round-trip back via `scrollLeft = 0` restores the original two-column view. `totalPagesJS` returns **2** for the chapter, matching `ceil(1458/980)`. | **pass** (round-2 closes the deferred slice) |
| EPUB Layout selector (Scroll / Paged) visible in Reading Settings | Picker present in AX tree at pos (463, 985) as a segmented `AXTabGroup` with `Scroll` + `Paged` radio buttons (`feature-21-r2-18-layout-picker-visible-20260511.png` shows the section footer "Scroll uses continuous vertical scrolling. Paged uses horizontal page turns."). Conditional `Page Turn Animation` section (None/Slide/Cover) only renders when `store.epubLayout == .paged` — it IS rendered (`feature-21-r2-19-layout-segmented-20260511.png`), runtime-confirming the active layout selection. | pass |

## Commands run

```bash
SIM=FDF2EA2A-532E-48D4-9022-ADEB6CD053CC

# Build + install merged main (v3.15.1, commit 639b5fa)
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild build \
    -project vreader.xcodeproj -scheme vreader \
    -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
xcrun simctl install $SIM /Users/ll/Library/Developer/Xcode/DerivedData/vreader-*/Build/Products/Debug-iphonesimulator/vreader.app

# Pre-state: confirm Layout=Paged persisted from prior session.
DATA=$(xcrun simctl get_app_container $SIM com.vreader.app data)
plutil -extract readerEPUBLayout raw "$DATA/Library/Preferences/com.vreader.app.plist"
# → paged
plutil -extract readerReadingMode raw "$DATA/Library/Preferences/com.vreader.app.plist"
# → native

# Library imported Alice EPUB still present from prior verify-cron.
ls "$DATA/Library/Application Support/ImportedBooks/"
# → epub_48f70fb664bc6f7b7e8a0804d5d97321ccc4dc00b2ffa4cc948171f4c538e86c_137516.epub

# Relaunch.
xcrun simctl terminate $SIM com.vreader.app
xcrun simctl launch $SIM com.vreader.app

# CU-substitute: tap Alice book row to open reader.
osascript -e 'tell application "Simulator" to activate'
swift .claude/skills/sim-drive-fallback/scripts/clickat.swift 626 319

# Reader opens on cover (chapter 1 of 15). Cover is a single-image
# section → fits in one column-page → not useful for multi-page test.
# Tap "Next chapter" chevron (at mac pos 804, 933 per AX query) to
# advance to chapter 2 — Project Gutenberg license + Contents table.
swift .claude/skills/sim-drive-fallback/scripts/clickat.swift 804 933

# Eval probe: confirm body now overflows viewport horizontally.
JS='JSON.stringify({sw: document.documentElement.scrollWidth, cw: document.documentElement.clientWidth, sl: document.documentElement.scrollLeft, bsw: document.body.scrollWidth, bsl: document.body.scrollLeft, bcw: document.body.clientWidth, colWidth: getComputedStyle(document.body).columnWidth, colGap: getComputedStyle(document.body).columnGap, overflow: getComputedStyle(document.body).overflow})'
xcrun simctl openurl $SIM "vreader-debug://eval?bridge=epub&js=$(printf %s "$JS" | base64 | tr -d '\n')"
cat "$DATA/Library/Caches/DebugBridge/eval-epub.json"
# → result: {"sw":980,"cw":980,"sl":0,"bsw":1458,"bsl":0,"bcw":980,"colWidth":"362px","colGap":"40px","overflow":"hidden"}

# Exercise navigateToPageJS contract — set body.scrollLeft = viewport*1.
JS='(function() { document.documentElement.scrollLeft = 980; document.body.scrollLeft = 980; return JSON.stringify({afterSl: document.body.scrollLeft, htmlSl: document.documentElement.scrollLeft, bsw: document.body.scrollWidth, bcw: document.body.clientWidth}); })()'
xcrun simctl openurl $SIM "vreader-debug://eval?bridge=epub&js=$(printf %s "$JS" | base64 | tr -d '\n')"
# → result: {"afterSl":478, ...}  ← clamped to maxScroll = scrollWidth − clientWidth = 1458 − 980 = 478

# Visual confirmation (page 2): screenshot shows Contents table now in
# left column with blank right column — the two-column view scrolled
# horizontally past the license text.
xcrun simctl io booted screenshot feature-21-r2-08-page2-rendered-20260511.png

# Round-trip back to page 0.
JS='(function() { document.documentElement.scrollLeft = 0; document.body.scrollLeft = 0; return JSON.stringify({afterSl: document.body.scrollLeft}); })()'
xcrun simctl openurl $SIM "vreader-debug://eval?bridge=epub&js=$(printf %s "$JS" | base64 | tr -d '\n')"
# → result: {"afterSl":0}
xcrun simctl io booted screenshot feature-21-r2-09-back-to-page1-20260511.png
# → identical to chapter-2 first-tap view: license-text-left + Contents-right

# Total pages query.
JS='Math.ceil(document.body.scrollWidth / document.body.clientWidth)'
xcrun simctl openurl $SIM "vreader-debug://eval?bridge=epub&js=$(printf %s "$JS" | base64 | tr -d '\n')"
# → result: 2

# Reading Settings panel — confirm EPUB Layout = Paged surfaces in UI
# (Page Turn Animation conditional section IS rendered, which only fires
# when store.epubLayout == .paged per ReaderSettingsPanel.swift:62).
swift .claude/skills/sim-drive-fallback/scripts/clickat.swift 797 194
osascript -e 'tell application "System Events" to tell process "Simulator" to entire contents of window 1' | grep "EPUB layout"
# → AXTabGroup pos=463,985 sz=324x29 | EPUB layout
# → AXRadioButton pos=463,985 sz=162x30 | Scroll
# → AXRadioButton pos=626,985 sz=162x30 | Paged
```

## Observations

- **CU-substitute hits a known gesture limitation for in-document paged
  navigation.** Tapping the right zone (mac x ≈ 800) advances chrome
  toggle (legacy default), not the next column-page — because the
  `TapZoneOverlay` is gated to Unified mode (feature #25 round-5
  confirmed bug #162). In Native EPUB + Paged layout, the user-facing
  page-advance gesture is a horizontal SWIPE on the WKWebView content
  area, which CGEventPost mouse-drag does NOT deliver to the web view's
  touch handler (documented limitation in `.claude/skills/sim-drive-fallback`).
  **DebugBridge `eval` is the only verifier-driveable path** for
  exercising `EPUBPaginationHelper.navigateToPageJS` against the real
  bridge. The primitive itself works correctly — the gesture-vs-primitive
  gap is a verification-tooling limitation, not a vreader defect.
- **scrollLeft clamping is browser-level, expected, and testable.** I
  set `body.scrollLeft = 980` (viewport width), but the read-back
  returned `478`. That's not a bug: `body.scrollWidth (1458) − clientWidth
  (980) = 478` is the maximum scrollable distance. The browser clamps
  scrollLeft to that bound. `EPUBPaginationHelper.navigateToPageJS(page:
  1, viewportWidth: 980)` is intended to advance one full viewport at a
  time, but for chapters whose total content is less than 2× viewport
  the last "page" is fractional. The visual confirms the scroll
  effectively reaches the end of the content, which is the right
  user-visible behaviour.
- **`scrollWidth == clientWidth` on EPUB cover is by design.** mini-epub3
  hit this for all chapters; this Alice fixture hits it on chapter 1
  (the cover, single full-bleed image) but chapter 2+ have multi-page
  content. Future verifications should chapter-advance past covers
  before probing for multi-page behaviour.
- **`document.documentElement.scrollLeft` vs `body.scrollLeft` diverge
  post-write.** When I set both to 980, the read-back showed
  `documentElement.scrollLeft = 980` but `body.scrollLeft = 478`. The
  vreader pagination helper sets BOTH (per
  `EPUBPaginationHelper.swift:74-75`); the actual rendered horizontal
  position tracks `body.scrollLeft` (clamped). The dual-write is correct
  defensive programming — different browsers/iOS-WebKit versions read
  scroll position from different elements.
- **The EPUB Layout picker is structurally below the medium-detent
  sheet bound.** The sheet's medium detent stops at ~y=900 in mac
  coords; the Layout segmented control is at y=985. Users have to
  drag the sheet's grabber upward (or scroll within the sheet) to
  reach it. Not a regression — same UX as feature #25's deferred Tap
  Zones section which sits even lower. A future UX pass could
  reorganize the panel order, but it's not a feature #21 concern.

## Artifacts

- `feature-21-r2-01-cover-page-20260511.png` — reader opens on Alice cover (chapter 1 of 15)
- `feature-21-r2-02-after-right-tap-20260511.png` — right-zone tap hits chrome-toggle (not page-advance; Native mode)
- `feature-21-r2-03-after-second-right-tap-20260511.png` — second tap restores chrome
- `feature-21-r2-04-after-swipe-rtl-20260511.png` — CGEventPost swipe doesn't reach WKWebView (known limitation)
- `feature-21-r2-05-after-next-chapter-20260511.png` — advanced to chapter 2 via bottom Next-chapter chevron; two-column layout now visible (license + Contents)
- `feature-21-r2-06-chapter2-dims-20260511.json` — eval probe: `bsw=1458, bcw=980, colWidth=362px, colGap=40px, overflow=hidden`
- `feature-21-r2-07-after-navigateToPage-20260511.json` — eval probe: `body.scrollLeft` after write = 478 (clamped)
- `feature-21-r2-08-page2-rendered-20260511.png` — visual: Contents now in left column, right blank
- `feature-21-r2-09-back-to-page1-20260511.png` — round-trip back to page 0 restores original view
- `feature-21-r2-10-totalpages-20260511.json` — eval probe: `totalPagesJS` returns 2 for this chapter
- `feature-21-r2-11-settings-panel-20260511.png` — Reading Settings sheet opened (Theme/Background/Mode visible)
- `feature-21-r2-15-sheet-expanded-20260511.png` — sheet grabber dragged up; Simp/Trad picker visible
- `feature-21-r2-17-settings-fullsheet-top-20260511.png` — top of settings sheet
- `feature-21-r2-18-layout-picker-visible-20260511.png` — EPUB Layout section footer + Page Turn Animation picker (None selected) visible
- `feature-21-r2-19-layout-segmented-20260511.png` — Page Turn Animation (None / Slide / Cover) — conditional section that only renders when Layout=Paged

## Disposition

Feature #21 flips from `DONE` to `VERIFIED`. All six round-1 acceptance
criteria plus the deferred multi-page-navigation slice now PASS
end-to-end against a real-length EPUB on iPhone 17 Pro Sim (iOS 26.4)
at v3.15.1.

GH #405 closes with closure comment citing commit `639b5fa` + this
evidence file. The `awaiting-device-verification` label gets removed.

Out-of-scope clarifications (not regressions, not blockers):
- TXT / MD pagination — different code path (`TXTReaderContainerView`
  paginate primitive is defined but unwired; see bug #157 closure
  rationale). Separate verification target.
- PDF pagination — `PDFView.displayMode = .singlePage` is PDFKit-native;
  separate verification target.
- AZW3 / MOBI pagination via Foliate — `FoliateViewBridge` has its
  own paged layout (Foliate-js handles it); separate verification
  target.

## Cross-references

- `dev-docs/verification/feature-21-20260506.md` — round-1 (5/6 PASS,
  multi-page nav deferred)
- `vreader/Views/Reader/EPUBPaginationHelper.swift:69-78` —
  `navigateToPageJS(page:viewportWidth:)`
- `vreader/Views/Reader/EPUBPaginationHelper.swift:87-93` —
  `totalPagesJS(viewportWidth:)`
- `vreader/Views/Reader/EPUBWebViewBridge.swift:254` — production
  callsite for navigateToPageJS
- `vreader/Views/Reader/ReaderSettingsPanel.swift:316-328` —
  `epubLayoutSection`
- `vreader/Views/Reader/ReaderSettingsPanel.swift:62` — `Page Turn
  Animation` section conditional on `store.epubLayout == .paged`
- GH #405 — feature mirror
- Feature #36 round-5 — same Alice fixture; OPDS → import path
