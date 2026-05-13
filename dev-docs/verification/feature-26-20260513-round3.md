---
kind: feature
id: 26
status_target: VERIFIED
commit_sha: a0ec073b1bfaaa3e9e8e83b3f5e7ffeb6e8a3e3a
app_version: 3.21.17 (build 294)
date: 2026-05-13
verifier: claude
device_or_simulator: iPhone 17 Pro Simulator
os_version: iOS 26.5
build_configuration: Debug
backend: n/a
result: partial
---

# Feature #26 — Text-to-Speech read aloud — round-3 (Foliate slice → FAIL, bug filed)

Round-3 attempted to close the deferred **Foliate WebView TTS** slice
(AZW3/MOBI) — the last remaining slice keeping feature #26 from
flipping to `VERIFIED` per the row's history (round-1 partial unit
tests; round-2 pass on TXT UI gestures).

The attempt failed end-to-end: `vreader-debug://tts?action=start`
against an open AZW3 book leaves `ttsState` at `"idle"`. **Root cause
identified via code-read**; **bug #176 filed** (GH #602). Feature #26
stays `DONE`; the Foliate slice is now blocked on bug #176's fix
rather than on a missing test fixture.

## Acceptance criteria

| # | Criterion | Observed | Pass/Fail |
|---|-----------|----------|-----------|
| 1 | AVSpeechSynthesizer pipeline starts speaking when user triggers TTS on AZW3 book | Speaker button + `vreader-debug://tts?action=start` both no-op on AZW3. Snapshot post-start: `ttsState: "idle"`, `ttsOffsetUTF16: null`. No TTS control bar appears. | **FAIL** (bug #176) |
| 2 | TTSService state machine transitions `.idle → .speaking → .paused → .speaking → .idle` | TXT verified round-2 pass. AZW3 cannot transition past `.idle` because the producer is unwired (bug #176). | **PASS** (TXT) / **FAIL** (AZW3) |
| 3 | HTTP TTS provider live driver | Out of scope this round (third-party endpoint unavailable). Covered by unit tests round-1. | DEFERRED |
| 4 | Foliate webview-side TTS via `FoliateTTSAdapter` JS API | `FoliateTTSAdapter` exists with `startTTSJS()` / `nextTTSJS()` / `initTTSJS(granularity:)`, but no production code path evaluates these against a live Foliate webview. | DEFERRED (one of the two fix paths in bug #176 wires this) |

## Commands run

```bash
SIMID=1FAB9493-B97E-48F0-96C7-44A8E5AAA21E
APP_PATH=/Users/ll/Library/Developer/Xcode/DerivedData/vreader-hdhlhcqmxppsadhececcxeadpkvz/Build/Products/Debug-iphonesimulator/vreader.app

xcrun simctl terminate $SIMID com.vreader.app
xcrun simctl install $SIMID "$APP_PATH"
xcrun simctl launch $SIMID com.vreader.app --uitesting --seed-empty --reset-preferences

# Seed mini-azw3 via DebugBridge (TestSeeder doesn't have an AZW3 seed flag)
xcrun simctl openurl $SIMID "vreader-debug://reset"
xcrun simctl openurl $SIMID "vreader-debug://seed?fixture=mini-azw3"

# Open the seeded AZW3
AZW3_KEY="azw3:fadbaa44ae1f5130992b0c9fa795b90796900c6b56b9d19af4d49c5dccf27d33:128650"
xcrun simctl openurl $SIMID "vreader-debug://open?bookId=$AZW3_KEY"
sleep 5  # Foliate WKWebView load + render

# Baseline snapshot — confirm format=azw3, ttsState=idle
xcrun simctl openurl $SIMID "vreader-debug://snapshot?dest=f26-after-open-azw3.json"

# Attempt TTS start
xcrun simctl openurl $SIMID "vreader-debug://tts?action=start"
sleep 3
xcrun simctl openurl $SIMID "vreader-debug://snapshot?dest=f26-after-tts-start-azw3.json"
xcrun simctl io $SIMID screenshot feature-26-r3-02-azw3-tts-start-20260513.png
```

After-open snapshot (PASS — book loaded, format detected):

```json
{
  "currentBookId": "azw3:fadbaa44...:128650",
  "format": "azw3",
  "ttsState": "idle",
  "ttsOffsetUTF16": null,
  "lastError": null
}
```

After-tts-start snapshot (FAIL — TTS didn't transition):

```json
{
  "currentBookId": "azw3:fadbaa44...:128650",
  "format": "azw3",
  "ttsState": "idle",       // expected: "speaking"
  "ttsOffsetUTF16": null,   // expected: non-null
  "lastError": null
}
```

## Observations

- **WI-4c-c's snapshot wiring was the diagnostic unlock.** Before WI-4c-c (PR #599, v3.21.15), `ttsState` would have stayed `null` regardless of whether TTS started — indistinguishable from the silent failure observed here. With WI-4c-c, the failure mode is unambiguous: `ttsState: "idle"` post-start means the producer didn't fire, not "snapshot doesn't know."
- **Root cause code-read** (filed in bug #176): `ReaderAICoordinator.loadBookTextContent(fileURL:format:)`'s `switch format` has cases for `txt`/`md`/`pdf`/`epub` but no `azw3`/`mobi` case → falls through to `default: return nil` → `loadedTextContent` stays nil → `startTTS()`'s guards skip the `ttsService.startSpeaking` call entirely. The capability is advertised (`FormatCapabilities.azw3` includes `.tts`, so the speaker button is shown) but the wire-up is missing.
- **`FoliateTTSAdapter` exists** at `vreader/Services/Foliate/FoliateTTSAdapter.swift` with the JS-side adapter functions (`startTTSJS`, `nextTTSJS`, `initTTSJS(granularity:)`). Production code never evaluates these — second fix path in bug #176 wires them.
- **Not a fixture/CU/timing issue** — bridge URL fires successfully (`lastError: null`), `currentBookId` confirms the AZW3 book is registered as the active reader, but `ttsService.state` never moves. Diagnosis isolated entirely via code-read + DebugBridge snapshot; no need for computer-use.
- **No regression** — the TXT slice (round-2 pass) still works, exercised earlier this session via feature #40 round-4 verification (`feature-40-20260513.md`). This is discovery of an existing never-wired-up gap, not a degradation.

## Artifacts

- `dev-docs/verification/artifacts/feature-26-r3-01-azw3-open-20260513.png` — AZW3 book rendered by Foliate, "The Masque of the Red Death" by Edgar Allan Poe (PG #1064), Title/Author/Release Date metadata block, no TTS control bar (correct baseline — TTS not started yet).
- `dev-docs/verification/artifacts/feature-26-r3-02-azw3-tts-start-20260513.png` — Same screen after firing `vreader-debug://tts?action=start`. **No TTS control bar appears** — silent failure visually confirms the snapshot's `ttsState: "idle"`.

## Verdict

**PARTIAL** — Foliate (AZW3/MOBI) TTS slice does not pass. Bug #176 (GH #602) filed for the production wire-up gap. Feature #26 status stays `DONE`. The deferred slice is now reframed: was "needs Foliate-slice verification," now "blocked on bug #176 fix." Once bug #176 lands, re-run this exact recipe to confirm TTS starts; if `ttsState` transitions to `"speaking"` and the TTS control bar appears, feature #26 flips to `VERIFIED`.

HTTP cloud TTS slice remains deferred (third-party endpoint dependency).
