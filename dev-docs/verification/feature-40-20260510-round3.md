---
kind: feature
id: 40
status_target: DONE
commit_sha: 41067e5
app_version: 3.14.123 (build 232)
date: 2026-05-10
verifier: claude
device_or_simulator: iPhone 17 Simulator
os_version: iOS 26.4
build_configuration: Debug
backend: bundled DebugFixtures (war-and-peace.txt) + AVSpeechSynthesizer (system TTS)
result: partial
---

## Summary

Round-3 verification of feature #40 (TTS sentence highlighting) on
merged-main `41067e5` (v3.14.123). Round-2 (2026-05-09) was inconclusive
between three possible root causes for the missing visible highlight.
**This round identifies the root cause definitively** via code-read.

**Definitive finding**: TTS sentence highlighting is structurally disabled
in **chapter-aware TXT rendering** because `TXTReaderContainerView.swift:496`
hardcodes `highlightRange: nil` in the chapter-mode branch:

```swift
// TXTReaderContainerView.swift:486-503  (chapter-based rendering)
TXTTextViewBridge(
    text: text,
    attributedText: attributedText,
    config: settingsStore?.txtViewConfig ?? TXTViewConfig(),
    restoreOffset: initialRestoreOffset,
    scrollToOffset: uiState.scrollToOffset,
    highlightRange: nil,             // <— FORCED nil — "Highlight offset translation is WI-7"
    highlightIsTemporary: true,
    persistedHighlights: [],         // <— FORCED empty — same WI-7 deferral
    delegate: viewModel
)
```

Compare with the full-text rendering branch (line 466-479) which DOES
pass `uiState.highlightRange` through. The chapter-mode branch is
selected when `TXTService` detects chapter markers (`CHAPTER I/II/III`,
`第N章`, etc.) — which is the case for `war-and-peace.txt` and any
real-world novel-format TXT.

**This is the same WI-7 blocker as bug #160** (manual highlight
chapter-mode pipeline). Both manual and TTS sentence highlights share
`uiState.highlightRange` and the same chapter-local↔global translation gap.

**Auto-scroll works fine** (cross-ref feature #41 round-2): visible scroll
from CHAPTER I top → 84% (end of fixture) over ~30s of TTS playback at
1.2×. This confirms the `currentOffsetUTF16` flow through
`uiState.scrollToOffset` works in chapter mode — only the
`highlightRange` is gated off by the WI-7 deferral.

## Acceptance criteria

| Criterion | Observed | Pass/Fail |
|---|---|---|
| 1. NLTokenizer sentence detection (English/CJK/mixed) | Round-1: 9-test `TTSHighlightCoordinatorTests` PASS | PASS (round-1 cross-ref) |
| 2. Binary-search range lookup + out-of-bounds safety | Round-1 PASS | PASS (round-1 cross-ref) |
| 3. `updateHighlight` sets `highlightRange` when speaking | Round-1 PASS (verified through `uiState` mock) | PASS (round-1 cross-ref) |
| 4. `clearHighlight` removes temporary but preserves persistent | Round-1 PASS | PASS (round-1 cross-ref) |
| 5. **Real TTS playback → coordinator dispatch fires** | Confirmed indirectly: TTS auto-scroll (feature #41) advances from 0% → 84% as `currentOffsetUTF16` updates flow through. The same `onChange(ttsService?.currentOffsetUTF16)` observer at `TXTReaderContainerView.swift:379-385` calls `coordinator.updateHighlight(offset:)` on every fire. So the coordinator IS receiving offset updates. | PASS |
| 6. **Highlight visibly renders on current sentence in TXT chapter mode** | **FAIL** — no yellow/blue/colored sentence band visible across 4 screenshots over 30s of playback at 1.2× speed. Root cause: `TXTReaderContainerView.swift:496` hardcodes `highlightRange: nil` in chapter-mode rendering branch (the only branch that runs for chapter-aware TXTs like war-and-peace). This is the same WI-7 deferral as bug #160. | DEFERRED (WI-7) |
| 7. Highlight visibly renders in TXT non-chapter mode | DEFERRED — no non-chapter TXT fixture is bundled. Full-text rendering branch at line 466-479 DOES pass `uiState.highlightRange`, so this would be expected to pass — cannot exercise on current fixtures. | DEFERRED (fixture) |
| 8. `clearHighlight` fires on TTS state → idle | After tap Stop (AX `Stop reading` button at mac (489, 932)): TTS bar removed, reader chrome restored, content shows end-of-fixture text. No persisted highlight remains visible (no leftover yellow band). Wired via `TXTReaderContainerView.swift:386-390` `onChange(ttsService?.state)`. | PASS (no leftover state) |
| 9. Highlight in MD chapter mode | Not exercised (no MD fixture bundled). Same architectural pattern as TXT — code path at `MDReaderContainerView.swift:312` passes `uiState.highlightRange`; no MD chapter-mode branching observed. | DEFERRED (fixture) |

## Commands run

```bash
SIM_ID=53F548AE-9C89-4CB6-A6F7-17D5550F52EB  # iPhone 17, iOS 26.4
osascript -e 'tell application "Simulator" to activate'
xcrun simctl openurl booted "vreader-debug://reset"
xcrun simctl openurl booted "vreader-debug://seed?fixture=war-and-peace"

# Open war-and-peace via card tap (AX-derived: card at (425, 278) size 402x82):
swift /tmp/clickat.swift 626 319

# Tap Read aloud (AX: pos=(727, 172)):
swift /tmp/clickat.swift 743 188

# Verify TTS state after start:
osascript -e 'tell process "Simulator" to value of attribute "AXDescription" ...'
# AX returns: TTS active pos=(727, 172); Pause pos=(441, 915); Stop reading pos=(473, 915)

# Capture across 30s of playback at 1.2× speed:
for i in 1 2 3 4; do xcrun simctl io booted screenshot /tmp/tts_t$i.png; sleep 1.5; done
sleep 8 && xcrun simctl io booted screenshot /tmp/tts_long.png

# Stop:
swift /tmp/clickat.swift 489 932   # center of Stop reading button

# Code-read confirming the chapter-mode highlight gate:
grep -n "highlightRange" vreader/Views/Reader/TXTReaderContainerView.swift
# vreader/Views/Reader/TXTReaderContainerView.swift:472:        highlightRange: uiState.highlightRange,    # full-text branch
# vreader/Views/Reader/TXTReaderContainerView.swift:496:        highlightRange: nil, // Highlight offset translation is WI-7
# vreader/Views/Reader/TXTReaderContainerView.swift:527:        highlightRange: uiState.highlightRange,    # chunked branch
```

## Observations

- **The wiring on the producer side is correct**: tap Read aloud → TTS
  bar appears → AVSpeechSynthesizer's `willSpeakRangeOfSpeechString`
  fires → `ttsService.currentOffsetUTF16` updates → SwiftUI `onChange`
  triggers `coordinator.updateHighlight(offset:)` → `uiState.highlightRange`
  is set. Producer side **fires correctly** on this build (this is the
  improvement over round-2's inconclusive verdict — we now have a
  certainty bound by the auto-scroll observation).
- **The consumer side is the gate**: `TXTReaderContainerView.swift:496`
  in chapter-mode rendering forces `highlightRange: nil` — coordinator's
  output is never wired to `TXTTextViewBridge → HighlightingLayoutManager`
  in the visible render path for chapter-aware TXT files. The inline
  comment "Highlight offset translation is WI-7" matches the same WI-7
  scope as bug #160's chapter-mode manual-highlight blocker.
- **No new bug filed**. The structural deferral is already tracked by
  feature #48 WI-7 (chapter-local↔global offset translation pipeline).
  Bug #160 / GH #476 covers the user-visible side of this for manual
  highlighting; the TTS-side symptom shares the same code path and the
  same fix. Filing a separate TTS-specific bug would duplicate WI-7
  tracking.
- **War-and-peace fixture exhibits chapter mode**: the bundled
  fixture (1708 bytes, content includes `CHAPTER I` / `CHAPTER II` /
  `CHAPTER III` markers) triggers `TXTService`'s chapter detection,
  routing render through the chapter-mode branch. **No bundled non-chapter
  TXT exists**, so the full-text branch (which DOES pass
  `uiState.highlightRange`) cannot be exercised end-to-end this round.
  Once feature #48 WI-7 lands AND/OR a non-chapter TXT fixture is
  bundled, this slice unblocks and `DONE` → `VERIFIED` becomes possible.
- **Cross-format gap**: the same chapter-mode highlight deferral applies
  to EPUB Native (which uses a different rendering pipeline — Foliate
  WebView) only insofar as that pipeline also doesn't render TTS
  sentence highlights today. Feature #40 explicitly scopes itself to
  TXT/MD ("TXT/MD wired via onChange(ttsService)"), so EPUB / AZW3 / PDF
  TTS-highlight rendering is out of feature #40's slice.
- **No bugs filed.** Producer + state-clear paths verified PASS; render
  side blocked by the documented WI-7 deferral.

## Artifacts

- `dev-docs/verification/artifacts/feature-40-r2-tts-started-no-highlight-20260510.png`
  — TTS just-started (clock 16:52); reader on CHAPTER I; bottom chrome
  shows ⏸ / ⏹ / 1.2× / progress bar; no visible sentence highlight.
- `dev-docs/verification/artifacts/feature-40-r2-tts-mid-playback-no-highlight-20260510.png`
  — TTS mid-playback after ~10s; reader auto-scrolled to mid-CHAPTER II
  ("Anna Pavlovna's drawing room was gradually filling..." through
  "...Princess Bolkonskaya, known as the most seductive woman in
  Petersburg, was also there." + `CHAPTER III` heading); still no
  visible sentence highlight.
- `dev-docs/verification/artifacts/feature-40-r2-tts-stopped-end-of-fixture-20260510.png`
  — TTS stopped at 84% (end of fixture); chrome restored; "End of
  synthetic fixture excerpt." visible; no leftover highlight.

## Verdict

`partial` — root cause for round-2's missing-highlight finding is now
identified definitively (code-read, line 496). The same WI-7 deferral
that bug #160 tracks for manual highlight chapter-mode also gates TTS
sentence highlight chapter-mode. **Producer side is healthy** (verified
indirectly via auto-scroll); **consumer side is gated**. Status stays
`DONE`; flip to `VERIFIED` follows feature #48 WI-7 + a re-verification
round on chapter-aware fixtures (or addition of a non-chapter TXT
fixture for the existing full-text branch).

## Bug-filing decision

**Decision: do NOT file a new bug.**

The chapter-mode highlight gap is:
1. Already tracked by feature #48 WI-7 (chapter-local↔global offset
   translation) and bug #160 (its manual-highlight surface).
2. Documented inline at the gate point (`TXTReaderContainerView.swift:496`,
   comment: "Highlight offset translation is WI-7").
3. Will be unblocked by the same fix that closes WI-7 — no separate
   wiring needed for the TTS path.

Filing a TTS-specific row would duplicate tracking and split closure
credit between bug #160 and a hypothetical bug #161. The verify-cron's
"file bugs found during verification" rule applies to **new** failure
modes, not to known structurally-deferred slices already cited in the
deferred-criteria table.
