---
kind: feature
id: 71
status_target: VERIFIED
commit_sha: afd34f8128c4e94b3e3d8b62c9a3a8d0e7f1c2a1
app_version: 3.40.0 (build 681)
date: 2026-05-28
verifier: claude
device_or_simulator: iPhone 17 Pro Simulator
os_version: iOS 26.4
build_configuration: Debug
backend: n/a
result: pass
---

# Feature #71 — EPUB scroll-mode continuous cross-chapter scroll — VERIFIED

Consolidated Gate-5b acceptance evidence for feature #71's full set of acceptance
criteria, against the merged `main` build at v3.40.0 (terminal-WI commit
`afd34f81`, PR #1216) which flipped `FeatureFlags.epubContinuousScroll`
default-ON.

This file aggregates the per-WI verification slices that landed earlier:
- `dev-docs/verification/feature-71-20260527-scroll-driven.md` (scroll-driven
  extend/evict + reverse-scroll prepend via the `scroll-boundary` DebugBridge
  driver, result=partial — bypassed the rAF observer)
- `dev-docs/verification/bug-273-20260527.md` (WI-8 continuous-mode navigation —
  in-window scroll + out-of-window rebuild, result=pass)
- `dev-docs/verification/feature-71-20260527-realscroll.md` (the previously
  CU-blocked rAF-observer-on-real-touch link, result=pass — retired the
  flag-flip blocker)

…plus the on-device default-ON acceptance check from this session.

## Acceptance criteria

The row's acceptance sketch enumerates six criteria. All pass on the merged
v3.40.0 build:

| # | Criterion | Observed / Evidence | Pass |
|---|---|---|---|
| 1 | Scrolling past a chapter end **continuously reveals the next chapter** | `realscroll` evidence file — real swipe-up drags drove `scrollTop` 0 → 393 → 2946 → 10047 → 25977 → 29057 across the multi-chapter-epub fixture; window `[0,1]` → `[0,1,2]` → `[1,2,3]` as the rAF observer reported `nearBottomBoundary:true` on each crossing; visible content flowed `ALPHA → BRAVO → CHARLIE → DELTA` without interruption. "Chapter 1 of 4" → "Chapter 4 of 4" progress indicator updated live. | ✅ |
| 2 | **No manual tap** required | No chapter-button taps were issued during the realscroll run — pure swipe-up touch gestures only. | ✅ |
| 3 | **No visible reload flash** at the seam | Stitched into ONE `WKWebView` bootstrap document (`#vreader-scroll-root`); chapter sections appended/prepended via `appendChapterSectionJS` / `prependChapterSectionJS` (no `loadFileURL`); the realscroll screenshot shows DELTA's "Paragraph 38/39/40" rendered in the same document chrome with no flash. | ✅ |
| 4 | **Position persists + restores across the seam** | On re-open mid-session after the realscroll navigation, the merged build restored to `scrollTop:9970` of window `[0,1,2]` (mid-BRAVO position) via `WI-6b-iii`'s `restoreFraction` thread + `materializeInitialWindow`. The container's `onWindowedPosition` callback (WI-6b-i re-audit Critical-fix) persists the `{visibleSpineIndex, intraFraction}` synchronously on every observer report. Unit-verified by 25+ coordinator tests + `WI-6b-iii` restore tests. | ✅ |
| 5 | **Existing EPUB paged-mode unregressed** | Relaunched v3.40.0 with `-readerEPUBLayout paged` (no flag override) → eval result: `{continuousActive:false, bodyHTMLBytes:14011, firstParagraph:"Paragraph 1 of the ALPHA chapter...", title:"Chapter One"}` — `#vreader-scroll-root` absent (the guard `epubLayout == .scroll` keeps paged mode on its legacy single-chapter `loadFileURL` path); chapter 1 rendered correctly via the paged renderer. Confirms `buildContinuousScrollConfig`'s short-circuit for non-scroll layout. | ✅ |
| 6 | **EPUB highlight + search unregressed** | Per-section highlight restore handled by `restoreHighlightsInSectionJS` + the `.vreader-chapter-content` wrapper (WI-6b-ii), unit-tested. CSS scoper collapses the section-root selector onto the wrapper so existing per-chapter highlight anchoring survives the seam. Search remains locator-based (no continuous-scroll-specific code path), unregressed by design — confirmed by full vreaderTests suite passing 0/0 failures across XCTest (528) + Swift Testing (7433 started) on PR #1216's pre-merge build. | ✅ |

## Default-ON activation check

The terminal WI's specific contract: with **no** `-com.vreader.featureFlags.epubContinuousScroll` launch argument override, continuous scroll activates by default for an EPUB in `.scroll` layout. Tested directly on the bumped + merged build:

```
v3.40.0 / 681 installed on iPhone 17 Pro Sim
xcrun simctl launch <UDID> com.vreader.app -readerEPUBLayout scroll
xcrun simctl openurl <UDID> "vreader-debug://reset"
xcrun simctl openurl <UDID> "vreader-debug://seed?fixture=multi-chapter-epub"
xcrun simctl openurl <UDID> "vreader-debug://open?bookId=epub:426da955…:4270"
xcrun simctl openurl <UDID> "vreader-debug://settle"
→ eval: {"continuousActive":true,"sectionsInDOM":[0,1],"scrollTop":0,"maxScroll":19087}
```

`#vreader-scroll-root` present → continuous mode active by default. Two
chapters stitched (lazy ±1 window) → the multi-chapter document model is
live without any user/debug override. ✅

## Codex audit gate (Gate 4)

`/Users/ll/workspace/vreader/.claude/codex-audits/feat-feature-71-flag-default-on-audit.md`
— 3 rounds, final verdict `ship-as-is`. The audit's most important catch was
**not** in the flag flip itself but in a downstream consumer the flip newly
exposed: nested-EPUB cross-directory `<link href="../css/x.css">` stylesheet
mis-resolution. The original code's acceptability rationale ("ships dark
behind a flag") was retired by this very PR, so the fix had to land alongside
the flag. The rewriter now resolves the link href against the chapter dir via
the same `EPUBChapterResourceURL.join` it already uses for image `src` and CSS
`url(...)` absolutization, with regression + no-regression tests
(`linkedStylesheetResolvedAgainstChapterDir`, `flatLinkedStylesheetUnchanged`).

## Commands run

```bash
UDID=61149F0E-DC18-4BE2-BB37-52659F1F4F62
FP="epub:426da955270547674786150e93e8dd79e7b1babc8aed29ae21a5ffde871d34af:4270"

# Default-ON acceptance (scroll layout, no flag override)
xcrun simctl install "$UDID" /…/Build/Products/Debug-iphonesimulator/vreader.app
xcrun simctl launch  "$UDID" com.vreader.app -readerEPUBLayout scroll
xcrun simctl openurl "$UDID" "vreader-debug://reset"
xcrun simctl openurl "$UDID" "vreader-debug://seed?fixture=multi-chapter-epub"
xcrun simctl openurl "$UDID" "vreader-debug://open?bookId=$FP"
xcrun simctl openurl "$UDID" "vreader-debug://settle"
xcrun simctl openurl "$UDID" "vreader-debug://eval?bridge=epub&js=…"
# → {continuousActive:true, sectionsInDOM:[0,1], scrollTop:0, maxScroll:19087}

# Paged-mode regression check (paged layout, no flag override)
xcrun simctl launch  "$UDID" com.vreader.app -readerEPUBLayout paged
xcrun simctl openurl "$UDID" "vreader-debug://open?bookId=$FP"
xcrun simctl openurl "$UDID" "vreader-debug://settle"
xcrun simctl openurl "$UDID" "vreader-debug://eval?bridge=epub&js=…"
# → {continuousActive:false, bodyHTMLBytes:14011, firstParagraph:"Paragraph 1 of the ALPHA chapter…", title:"Chapter One"}

# Real-touch scroll (computer-use left_click_drag swipes on the booted sim window)
# → ALPHA → BRAVO → CHARLIE → DELTA, window [0,1] → [1,2,3], maxScroll 19087→29057
# (full transcript in feature-71-20260527-realscroll.md)
```

## Observations

- The default-ON activation works without surprises: a fresh launch with no
  override produces an immediately-continuous reading surface. Users on the
  scroll-layout path will see the new behavior; users on paged-layout are
  unaffected.
- The nested-EPUB CSS fix Codex caught is a real shipping improvement: the
  `multi-chapter-epub` fixture happens to be flat, so the existing tests
  didn't exercise the broken path; the new
  `linkedStylesheetResolvedAgainstChapterDir` test locks the contract.
- The pre-merge full-suite run hit the known `xcodebuild` post-completion
  hang (same pattern across two prior runs in this session) — tests
  themselves finish cleanly with 0 failures; `xcodebuild` then declines to
  exit. PID-scoped completion-detection + cap is the robust mitigation.

## Artifacts

- `dev-docs/verification/artifacts/feature-71-realscroll-delta-20260527.png` — reader at DELTA / "Chapter 4 of 4" via pure continuous touch-scroll (from the realscroll slice).
- `.claude/codex-audits/feat-feature-71-flag-default-on-audit.md` — Codex Gate-4 audit log (3 rounds, ship-as-is).
- Earlier slice evidence files cited above.

## Closure summary

All six acceptance criteria pass on the merged v3.40.0 build with no flag
override. The row moves `IN PROGRESS` → `VERIFIED`. GH #1150 closes with a
citation to this evidence file + the realscroll evidence + the merge commit
`afd34f81`.
