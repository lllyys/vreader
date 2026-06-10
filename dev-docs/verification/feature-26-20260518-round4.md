---
kind: feature
id: 26
status_target: VERIFIED
commit_sha: 8cab12a4574304831666decf343ffc477943ae31
app_version: 3.27.25 (build 439)
date: 2026-05-18
verifier: claude
device_or_simulator: iPhone 17 Pro Simulator
os_version: iOS 26.4.1
build_configuration: Debug
backend: n/a
result: partial
---

# Feature #26 — Text-to-Speech read aloud — round-4 verify

Feature #26 is `DONE`. Round-2 (2026-05-09, `result: pass`) verified the **TXT**
TTS UI-gesture cycle at v3.14.111. Since then feature #60 re-skinned the reader
chrome — the TTS control moved out of a dedicated speaker button into the
`ReaderMorePopover` "Read aloud" row (bug #602). This round (a) regression-
re-verifies the TXT cycle through the new control surface on current main
v3.27.25, and (b) adds the **EPUB** UI-gesture cycle, which no prior round
covered.

## Acceptance criteria

| # | Criterion | Observed | Result |
|---|---|---|---|
| 1 | TTS start — the More popover "Read aloud" row starts text-to-speech (TXT) | war-and-peace.txt → More (⋯) → "Read aloud" → TTS control bar appears (⏸ / ◾ / 1.2× speed). DebugBridge snapshot: `ttsState: speaking`, `ttsOffsetUTF16: 425`. | pass |
| 2 | TTS state machine `idle → speaking → paused → speaking → idle` traverses via the UI controls (TXT) | Pause → `ttsState: paused` (offset 772); Resume → `ttsState: speaking` (offset 941); Stop → `ttsState: idle` (offset null), TTS bar dismissed, reader chrome restored. | pass |
| 3 | TTS start + full state cycle for **EPUB** | mini-epub3 → More → "Read aloud" → `ttsState: speaking` (`format: epub`, offset 198); Pause → `paused` (394); Resume → `speaking` (599); Stop → `idle` (null). | pass |
| 4 | Audio playback is genuinely running (not just a UI state flag) | `ttsOffsetUTF16` advances monotonically across every speaking phase — TXT 425→772→941, EPUB 198→394→599. The offset only advances on real `AVSpeechSynthesizerDelegate.willSpeakRange` callbacks, so the system synthesizer is actually speaking. | pass (inferred) |
| 5 | AZW3/MOBI TTS | Out of scope — Bug #176 / GH #602 removed `.tts` from `FormatCapabilities.azw3`; the AZW3/MOBI "Read aloud" row is capability-gated out by design. Not a #26 criterion. | n/a |
| 6 | HTTP cloud TTS provider | Not verified — requires a live HTTP TTS server (third-party endpoint). No server available. Remains deferred. | deferred |

`result: partial` — criteria 1-4 pass; criterion 6 (HTTP cloud TTS) is genuinely
blocked on an external server and stays deferred. Feature #26 stays `DONE`;
the `VERIFIED` flip is gated only on the HTTP-cloud-TTS slice.

## Commands run

```bash
SIM=61149F0E-DC18-4BE2-BB37-52659F1F4F62

# merged-main v3.27.25 build (8cab12a) already installed (preserve data)
xcrun simctl launch $SIM com.vreader.app

# TXT slice
xcrun simctl openurl $SIM "vreader-debug://reset"
xcrun simctl openurl $SIM "vreader-debug://seed?fixture=war-and-peace"
# UI (computer-use): open the book → More (⋯) → "Read aloud" → ⏸ → ▶ → ◾
# state captured at each step:
xcrun simctl openurl $SIM "vreader-debug://snapshot?dest=v26-tts-speaking"   # speaking, 425
xcrun simctl openurl $SIM "vreader-debug://snapshot?dest=v26-tts-paused"     # paused,   772
xcrun simctl openurl $SIM "vreader-debug://snapshot?dest=v26-tts-resumed"    # speaking, 941
xcrun simctl openurl $SIM "vreader-debug://snapshot?dest=v26-tts-stopped"    # idle,     null

# EPUB slice
xcrun simctl openurl $SIM "vreader-debug://reset"
xcrun simctl openurl $SIM "vreader-debug://seed?fixture=mini-epub3"
# UI (computer-use): open → More → "Read aloud" → ⏸ → ▶ → ◾
xcrun simctl openurl $SIM "vreader-debug://snapshot?dest=v26-epub-tts-start"    # speaking, 198
xcrun simctl openurl $SIM "vreader-debug://snapshot?dest=v26-epub-tts-paused"   # paused,   394
xcrun simctl openurl $SIM "vreader-debug://snapshot?dest=v26-epub-tts-resumed"  # speaking, 599
xcrun simctl openurl $SIM "vreader-debug://snapshot?dest=v26-epub-tts-stopped"  # idle,     null
```

## Observations

- The round-2 TXT evidence is now stale at the UI level: the speaker button it
  drove no longer exists — feature #60 relocated TTS start into the
  `ReaderMorePopover` "Read aloud" row. The post-#60 control surface works
  correctly for both TXT and EPUB; no regression from the re-skin.
- The TTS control bar (⏸ / ◾ / speed slider) is a shared component — identical
  layout and behaviour across the TXT and EPUB readers.
- `ttsOffsetUTF16` is a clean playback proxy: it advances only on real
  `willSpeakRange` callbacks, so a monotonically-increasing offset across a
  speaking phase is direct evidence the synthesizer is producing speech. The
  simulator cannot expose an audio waveform to capture, so this is the
  strongest available signal — consistent with round-2's auto-scroll-progress
  inference.
- mini-epub3 is short; TTS was paused/stopped well before end-of-book, so the
  full cycle was observable.
- The EPUB book carried the regex content-replacement rule from the feature-#27
  round-4 verification (rendered "REPLACED_LOREM") — irrelevant to TTS, which
  reads the book text independently of the render pipeline.

## Artifacts

- `dev-docs/verification/artifacts/feature-26-r4-tts-speaking-20260518.png` — TXT, TTS bar active (⏸ / ◾ / 1.2×).
- `dev-docs/verification/artifacts/feature-26-r4-tts-stopped-20260518.png` — TXT, after Stop; TTS bar gone, reader chrome restored ("1m read").
- `dev-docs/verification/artifacts/feature-26-r4-epub-tts-speaking-20260518.png` — EPUB (mini-epub3), TTS bar active.
- `dev-docs/verification/artifacts/feature-26-r4-epub-tts-stopped-20260518.png` — EPUB, after Stop.
