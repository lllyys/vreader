---
kind: feature
id: 31
status_target: VERIFIED
commit_sha: 8cab12a4574304831666decf343ffc477943ae31
app_version: 3.27.25 (build 439)
date: 2026-05-18
verifier: claude (verify-cron)
device_or_simulator: iPhone 17 Pro Simulator
os_version: iOS 26.4
build_configuration: Debug
backend: n/a (DebugBridge + mini-epub3 fixture)
result: partial
---

# Feature #31 round-7 — scope settled: Auto Page Turn is MD-only by design; EPUB confirmed by-design no-op

## Context

Round-6 (`feature-31-20260517-round6.md`) found criterion 5 (live
auto-page-turn advancement) **FAIL** for the **MD** reader and filed
Bug #215 / GH #837 (MD paged mode never engages — `pageNavigator`
stays nil). Round-6's verdict was "VERIFIED blocked on Bug #215."

Rounds 2-6 were all MD-focused; the feature row's history also
mentions TXT (Bug #157). That left an open question this round
settles: **which formats is Auto Page Turn actually supposed to
cover, and is there any non-MD slice that could give #31 partial
verification credit?** Round-7 answers it with a CU-free EPUB
runtime probe + a `FormatCapabilities` code read.

(CU MCP display was unavailable this iteration — `screenshot`
returns `CU display unavailable`. The whole round is driven by
`defaults` + DebugBridge + `simctl io screenshot`, no gestures.)

## Scope

The EPUB format slice of feature #31, plus the per-format capability
contract. Verification only; no code changed.

## Acceptance criteria

Feature row contract: *auto-page-turn advances pages over a
configurable interval in paged mode.*

| # | Criterion | Result | Observed |
|---|-----------|--------|----------|
| A | Determine which formats Auto Page Turn covers | **PASS** | `FormatCapabilities.swift` is authoritative: `.autoPageTurn` (`rawValue 1 << 9`) is added to **MD only** (`capabilities(for:)` — the `.md` branch unions `[.toc, .autoPageTurn, .unifiedReflow]`; `.txt`/`.epub`/`.azw3`/`.pdf` branches do not). The `reflowableBase` doc comment states it verbatim: *".autoPageTurn is intentionally excluded — only MD has end-to-end AutoPageTurner wiring (bug #157 / GH #461)."* `ReaderSettingsPanel.autoPageTurnSection` (`:103`) gates the toggle on `formatCapabilities.contains(.autoPageTurn)` — so the Auto Page Turn toggle is **hidden** for every non-MD format. |
| B | EPUB in paged layout does NOT auto-advance (capability-gated out) | **PASS (by design)** | With `readerAutoPageTurn=true` + `interval=3` forced into `UserDefaults` (bypassing the hidden toggle) and `--reader-default-layout=paged`, opened mini-epub3. EPUB rendered in **paged** mode (content paginated — chapter-1 page 1 clips mid-text at "…Sed do" with blank space below; "Chapter 1 of 2" + 0% scrubber). Over **90 `simctl io` frames spanning ~15 s of steady state (≈5× the 3 s interval)** the rendered page was **byte-identical** (frames 16-90 all 305460 bytes) — **zero advancement**. This is correct: the EPUB reader contains no `AutoPageTurner` wiring at all (`grep` for `autoPageTurner`/`AutoPageTurner` across `vreader/Views` + `vreader/Services` returns MD + TXT + shared files, **never an EPUB reader file**). The capability gate is deep, not just UI-hiding. |
| 5 | Auto-page-turn timer advances pages over the interval (the feature's core behavior) | **FAIL (unchanged from round-6)** | MD is the *only* format with the capability, and MD's paged path is broken — `pageNavigator` stays nil, renders scroll content (round-6 / Bug #215 / GH #837, `BLOCKED: needs-design #842`). |

`result: partial` — criteria A and B PASS (the format-scope contract
is verified and the EPUB slice behaves exactly as designed); the
feature's core criterion 5 stays FAIL. Feature #31 stays `DONE`.

## What this round settles

Round-6 left "VERIFIED blocked on Bug #215" but did not establish
whether other formats could contribute partial credit. They cannot:

- **Auto Page Turn is MD-only by design.** Bug #157 / GH #461 found
  `TXTReaderContainerView.updatePaginationIfNeeded()` is
  defined-but-never-called and TXT has no paged renderer observing
  `pageNavigator.currentPage`, so the toggle silently no-op'd for
  every TXT file — #157's fix **removed** `.autoPageTurn` from the
  TXT capability set. EPUB / PDF / AZW3 never had it.
- Therefore the **`VERIFIED` flip is 100 % gated on Bug #215** — there
  is no TXT/EPUB/PDF/AZW3 slice to verify. MD is the whole feature.
- Bug #215 is `BLOCKED: needs-design (#842)` (MD paged-mode layout
  needs a design bundle). So feature #31 cannot reach `VERIFIED`
  until #842 design + #215 fix land.
- **No new bug filed** — the EPUB (and TXT) non-advancement is the
  intended capability-gated behavior, not a defect. Same disposition
  shape as feature #26 round-4's AZW3-TTS-capability-gated-out `n/a`.

## Commands run

```bash
SIM=61149F0E-DC18-4BE2-BB37-52659F1F4F62   # iPhone 17 Pro, iOS 26.4

# clean main 8cab12a built + installed (sim previously held an
# instrumented build from a bugfix iteration)
xcodebuild build -project vreader.xcodeproj -scheme vreader \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -derivedDataPath /tmp/v31-dd
xcrun simctl install "$SIM" /tmp/v31-dd/Build/Products/Debug-iphonesimulator/vreader.app

# force auto-page-turn ON (bypasses the EPUB-hidden toggle)
xcrun simctl spawn "$SIM" defaults write com.vreader.app readerAutoPageTurn -bool true
xcrun simctl spawn "$SIM" defaults write com.vreader.app readerAutoPageTurnInterval -float 3.0
xcrun simctl launch  "$SIM" com.vreader.app --uitesting --reader-default-layout=paged

xcrun simctl openurl "$SIM" "vreader-debug://reset"
xcrun simctl openurl "$SIM" "vreader-debug://seed?fixture=mini-epub3"
xcrun simctl openurl "$SIM" "vreader-debug://theme?mode=paper&fontSize=48"  # large font → multi-page
xcrun simctl openurl "$SIM" "vreader-debug://open?bookId=epub%3Af284fd07…10684af4%3A2198"
xcrun simctl openurl "$SIM" "vreader-debug://settle?token=open"
xcrun simctl openurl "$SIM" "vreader-debug://snapshot?dest=v31r7-baseline.json"
#   → format: epub, fontSize: 48, theme: paper, renderPhase: idle

# 90-frame simctl io screenshot loop (~15 s steady state, ≈5× interval)
for i in $(seq -w 1 90); do xcrun simctl io "$SIM" screenshot /tmp/v31-shot-$i.png; done
#   → frames 04-15: reader chrome up, content blank (WebView rendering)
#   → frames 16-90: chapter-1 page 1, ALL byte-identical (305460 B) — no advancement
```

## Observations

- mini-epub3 chapter 1 is ~550 chars of body text — at the default
  font it is ~1 page (the round-2/3 fixture-size blocker). Forcing
  `fontSize=48` paginated it to ≥2 pages (page 1 clips at "…Sed do";
  "Chapter 1 of 2"), so a working auto-turn *would* have had a page
  to advance to. It did not, because EPUB has no auto-turn wiring.
- The EPUB result is a *positive* confirmation of the capability
  gate, not a failure: forcing the `UserDefaults` flag on (which a
  real user cannot do — the toggle is hidden for EPUB) still produced
  zero advancement, proving the gate is structural (no `AutoPageTurner`
  in the EPUB reader) rather than a cosmetic toggle-hide.
- Possible follow-up (NOT filed — outside #31's row contract, not
  verified): `ReaderSettingsPanel.swift:103` uses
  `formatCapabilities?.contains(.autoPageTurn) ?? true` — the `?? true`
  fallback would *show* the Auto Page Turn toggle if a reader passed
  `nil` capabilities. Whether any reader does is unverified here;
  noting it for a future settings-panel verification round.
- Verification-only round: no code changed, no bug discovered.

## Artifacts

- `dev-docs/verification/artifacts/feature-31-r7-epub-paged-no-autoturn-20260518.png`
  — mini-epub3 in EPUB paged mode (chapter-1 page 1, content clipped
  mid-text, "Chapter 1 of 2", 0% scrubber); representative of frames
  16-90, all byte-identical → no auto-advance.
- `dev-docs/verification/artifacts/feature-31-r7-epub-loading-20260518.png`
  — frames 04-15: reader chrome up, content area still blank (EPUB
  WebView mid-render); the 127387→305460 transition at frame ~16 is
  render-completion, not a page turn.

## Outcome

Feature #31 stays **DONE**. Round-7 settles the format scope: Auto
Page Turn is **MD-only by design** (`FormatCapabilities` — bug #157),
the EPUB slice is verified to behave exactly as designed (no
auto-advance — capability-gated), and there is therefore **no non-MD
slice** that can contribute to a `VERIFIED` flip. The `VERIFIED` flip
is **entirely gated on Bug #215 / GH #837** (MD paged mode), itself
`BLOCKED: needs-design (#842)`. No new bug filed.
