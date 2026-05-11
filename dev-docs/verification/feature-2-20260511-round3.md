---
kind: feature
id: 2
status_target: VERIFIED
commit_sha: fcb1ff5ff1d95da2f97481b4c6e53ccf1f2674f6
app_version: 3.14.145 (build 254)
date: 2026-05-11
verifier: claude
device_or_simulator: iPhone 17 Simulator
os_version: iOS 26.4
build_configuration: Debug
backend: n/a
result: partial
---

## Summary

Round-3 device verify of feature #2 (highlight search result at destination)
against the bug #154 PARTIAL FIX shipped after round-2. Result: **partial,
same WI-7 blocker as bug #154 documented**. Navigation half passes; render
half blocked by the chapter-mode `highlightRange: nil` hardcode at
`TXTReaderContainerView.swift:496`.

This round used the CU-substitute toolkit
(`.claude/skills/sim-drive-fallback`) — CU MCP is still returning
`CU display unavailable` on this host. Single-tap + clipboard-paste +
sequential screenshot capture covered the entire flow.

## Acceptance criteria

| Criterion | Round-3 result | Notes |
|---|---|---|
| Search → tap result → reader scrolls so match lands inside viewport | **pass** | Bug #153 fix verified — landed at "...the visitors began taking leave..." showing the matched "Pierre" paragraph. |
| Yellow highlight visible on matched range immediately after tap | **fail** | Captured at t+0.4s, t+1.2s, t+4.2s — no `UIColor.systemYellow` background on "Pierre" in any frame. |
| Highlight auto-clears after 3 seconds | **n/a** | No highlight appeared, so auto-clear is unobservable. |
| Bidirectional navigation preserved (chrome / Previous / Next still work) | **pass** | "1/1" pager + scrubber + "0%" indicator render correctly. |

## Why render still fails after bug #154 PARTIAL FIX

Bug #154 PR rewired `readerContent` (line 472) + `chunkedReaderContent`
(line 527) from the orphan `@State highlightRange` to `uiState.highlightRange`.
`chapterReaderContent` (line 496) was deliberately left at
`highlightRange: nil // Highlight offset translation is WI-7` because
chapter-mode renders a per-chapter substring, and `uiState.highlightRange`
holds a GLOBAL UTF-16 offset — feeding it raw would point past the
chapter's substring length.

The only TXT fixture in the DebugBridge catalog
(`DebugFixtureCatalog.swift:41`) is `war-and-peace.txt`. The TXT chapter
detector treats this fixture as 1 detected chapter (visible in the chrome:
"Chapter 1" + "1/1" pager + "0%" progress), so `currentChapterText != nil`
at `TXTReaderContainerView.swift:115`, and the body dispatches to
`chapterReaderContent` (line 118). Search results label the match as
"Section 8", confirming the chapter index is populated.

Bug #154's own note already anticipated this: "no fixture yet exercises
the non-chapter paths to runtime-verify (a) directly". This round
confirms that statement empirically against a fresh build.

## What unblocks feature #2 flipping to VERIFIED

Either:
1. **WI-7 lands** (global→chapter-local UTF-16 offset translation in
   `chapterReaderContent`). This is the proper fix and unblocks every
   TXT chapter-mode highlight, not just search.
2. **A chapter-less TXT fixture is added** to
   `DebugFixtureCatalog.swift`. Any plain TXT with no Legado-rule-matching
   chapter markers would route through `readerContent` (line 472) where
   the bug #154 wiring already works. Examples: a short single-section
   excerpt without "CHAPTER N" / "Section N" / "第N章" / Roman-numeral
   headers, or with all heading lines stripped.

Option 2 is the cheaper path purely for verification; option 1 is the
real fix. Feature #2 stays at status DONE pending either.

## Commands run

```bash
# Boot + seed
xcrun simctl openurl booted "vreader-debug://reset"
xcrun simctl openurl booted "vreader-debug://seed?fixture=war-and-peace"

# Dismiss leftover Reading Settings sheet (drag-down on grabber)
swift .claude/skills/sim-drive-fallback/scripts/dragat.swift 625 600 625 950

# Open Search ("Search in book" button at mac (557, 194))
swift .claude/skills/sim-drive-fallback/scripts/clickat.swift 557 194

# Focus search field + paste "Pierre"
swift .claude/skills/sim-drive-fallback/scripts/clickat.swift 625 932
osascript -e 'set the clipboard to "Pierre"'
swift .claude/skills/sim-drive-fallback/scripts/pastekey.swift

# Tap the one result ("Section 8")
swift .claude/skills/sim-drive-fallback/scripts/clickat.swift 626 248

# Capture immediately, mid (1.2s), after auto-clear window (4.2s)
xcrun simctl io booted screenshot dev-docs/verification/artifacts/feature-2-r3-06-immediate-after-tap-20260511.png
xcrun simctl io booted screenshot dev-docs/verification/artifacts/feature-2-r3-07-mid-highlight-20260511.png
xcrun simctl io booted screenshot dev-docs/verification/artifacts/feature-2-r3-08-after-clear-20260511.png
```

## Observations

- **No new bug filed**. The render gap is fully tracked by:
  - Bug #154 PARTIAL FIX note ("runtime symptom on Position Test Book
    NOT yet gone")
  - WI-7 (global→chapter-local offset translation) in the TXT feature
    plan
  - Bug #160 (manual highlight chapter-mode, same root cause)
  - Feature #40 round-3 (TTS sentence highlight, same root cause —
    `TXTReaderContainerView:496` hardcodes nil)
  All four of these share one fix path; whichever lands first unblocks
  the others.

- **CU-substitute toolkit performed cleanly.** Single-tap +
  clipboard-paste hit every interaction this slice needed. No fallback
  to manual driving, no flake. Capability bounds held: this slice
  required no long-press, multi-touch, WKWebView drag, or rubber-band —
  all of which would have failed.

- **Search engine bug #153 fix is durable.** The matched-paragraph
  scroll lands the match inside the viewport (visible in the
  immediate-after-tap screenshot at the top of the visible text region).
  This was the round-2 finding and continues to hold on v3.14.145.

- **Section 8 vs CHAPTER I**: the chapter detector enables a different
  rule on this build than feature #23 round-2 had assumed — it now
  yields "Section 8" labels for war-and-peace search results (round-2
  reported 1/1 pager with `CHAPTER I` heading). Doesn't change the
  conclusion (still chapter-mode rendering), but worth noting for the
  next #23 verification round.

## Artifacts

- `feature-2-r3-01-library-20260511.png` — post-seed state (book auto-opened with leftover Reading Settings sheet)
- `feature-2-r3-02-current-20260511.png` — pre-dismissal state
- `feature-2-r3-03-postdismiss-20260511.png` — reader chrome visible, sheet dismissed
- `feature-2-r3-04-search-open-20260511.png` — Search panel empty state ("Enter a search term to find text in this book")
- `feature-2-r3-05-search-results-20260511.png` — one result for "Pierre" under Section 8
- `feature-2-r3-06-immediate-after-tap-20260511.png` — scrolled to match, **no yellow highlight**
- `feature-2-r3-07-mid-highlight-20260511.png` — t+1.2s, still **no yellow highlight**
- `feature-2-r3-08-after-clear-20260511.png` — t+4.2s, post-auto-clear window, **no yellow highlight ever appeared**

## Cross-references

- `dev-docs/verification/feature-2-20260507.md` — round-1 (no display, deferred)
- `dev-docs/verification/feature-2-20260508.md` — round-2 (filed bug #154)
- Bug #154 GH #443 — PARTIAL FIX (non-chapter paths wired; chapter-mode deferred to WI-7)
- Bug #160 GH #471 — manual highlight chapter-mode, same WI-7 deferral
- Feature #40 round-3 `feature-40-20260510-round3.md` — TTS sentence highlight, same WI-7 deferral
- Feature #23 (TXT auto-TOC) — chapter detection on war-and-peace
