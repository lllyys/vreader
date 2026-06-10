---
kind: feature
id: 26
status_target: VERIFIED
commit_sha: 8cab12a4574304831666decf343ffc477943ae31
app_version: 3.27.25 (build 439)
date: 2026-05-18
verifier: claude (verify-cron)
device_or_simulator: iPhone 17 Pro Simulator
os_version: iOS 26.4
build_configuration: Debug
backend: n/a (DebugBridge tts command + --seed-md-multi-page fixture)
result: partial
---

# Feature #26 round-5 — Markdown TTS slice (CU-free, DebugBridge `tts`)

Feature #26 is `DONE`. Round-2 (2026-05-09) verified the **TXT** TTS
cycle; round-4 (2026-05-18, `feature-26-20260518-round4.md`) added the
**EPUB** cycle and concluded the `VERIFIED` flip is "gated only on the
HTTP-cloud-TTS slice." No round has covered the **Markdown** reader.

This round verifies the **MD format slice** of feature #26. The CU MCP
display has been unavailable for 4 consecutive cron iterations
(`CU display unavailable` — diagnosed this iteration as a
Screen-Sharing-virtual-display issue, not a transient stall), so the
round is driven entirely by the DebugBridge `tts?action=start|stop`
command + `snapshot` — no gestures. The `tts` command was added for
exactly this purpose (DebugBridge doc: *"XCUITest's gesture path cannot
reliably activate AVSpeechSynthesizer's audio session, so verification
tests fire this URL"*).

## Scope

The Markdown format slice of feature #26 — TTS service start /
genuine-speech / stop, on the MD reader. Verification only; no code
changed. Driven against the `--seed-md-multi-page` fixture (9231-byte
"Test Markdown Multi-Page" MD book).

## Acceptance criteria

| # | Criterion | Result | Observed |
|---|-----------|--------|----------|
| 1 | TTS starts for the MD reader | **PASS** | Opened the MD book via `vreader-debug://open` (`format: md`, `renderPhase: idle`, `ttsState: idle`). `vreader-debug://tts?action=start` → snapshot: `ttsState: speaking`, `ttsOffsetUTF16: 0`, `lastError: null`. |
| 2 | TTS audio is genuinely running for MD (not just a UI state flag) | **PASS** | `ttsOffsetUTF16` advances **monotonically 0 → 176 → 302** across the speaking phase (3 snapshots). The offset only advances on real `AVSpeechSynthesizerDelegate.willSpeakRange` callbacks (round-4 criterion 4), so the system synthesizer is genuinely producing speech for the MD reader — not merely a state flag. |
| 3 | TTS stops cleanly for MD | **PASS** | `vreader-debug://tts?action=stop` → snapshot: `ttsState: idle`, `ttsOffsetUTF16: null`. Clean `idle → speaking → idle` traversal. |
| 4 | MD reader More-popover "Read aloud" row + TTS control bar (⏸/◾/speed) | **not verified this round** | The UI-affordance leg needs a gesture (More ⋯ → "Read aloud"); CU is unavailable. Round-4 established the TTS control surface is a **shared component** — the `ReaderMorePopover` "Read aloud" row + the ⏸/◾/speed control bar are identical across readers (feature #60 unified the reader chrome; MD uses the same `ReaderMorePopover`). The MD-specific risk was the *service integration* — does TTS start and genuinely speak for the MD reader — and that is what criteria 1-3 verify. A MD-specific UI confirmation is deferred to a CU-available round. |

`result: partial` — the MD TTS **service slice PASSES** (start /
genuine-speech / stop); criterion 4 (MD-specific UI affordance) is
deferred on the CU outage. Feature #26 stays `DONE`; the `VERIFIED`
flip remains gated on the HTTP-cloud-TTS slice (round-4's gate —
unchanged this round; still needs an external HTTP TTS server).

## Commands run

```bash
SIM=61149F0E-DC18-4BE2-BB37-52659F1F4F62   # iPhone 17 Pro, iOS 26.4

# clean main 8cab12a (v3.27.25 build 439) already installed
xcrun simctl launch  "$SIM" com.vreader.app --uitesting --seed-md-multi-page
xcrun simctl openurl "$SIM" "vreader-debug://open?bookId=md%3A0000…c0c002%3A9231"
xcrun simctl openurl "$SIM" "vreader-debug://settle?token=mdttsopen"
xcrun simctl openurl "$SIM" "vreader-debug://snapshot?dest=v26r5-baseline.json"
#   → format: md, ttsState: idle, ttsOffsetUTF16: null

xcrun simctl openurl "$SIM" "vreader-debug://tts?action=start"
xcrun simctl openurl "$SIM" "vreader-debug://snapshot?dest=v26r5-tts-A.json"
#   → ttsState: speaking, ttsOffsetUTF16: 0
xcrun simctl openurl "$SIM" "vreader-debug://snapshot?dest=v26r5-tts-B.json"
#   → ttsState: speaking, ttsOffsetUTF16: 176
xcrun simctl openurl "$SIM" "vreader-debug://snapshot?dest=v26r5-tts-B2.json"
#   → ttsState: speaking, ttsOffsetUTF16: 302   (monotonic advance — genuine speech)

xcrun simctl openurl "$SIM" "vreader-debug://tts?action=stop"
xcrun simctl openurl "$SIM" "vreader-debug://snapshot?dest=v26r5-tts-C.json"
#   → ttsState: idle, ttsOffsetUTF16: null

xcrun simctl io "$SIM" screenshot \
  dev-docs/verification/artifacts/feature-26-r5-md-tts-speaking-20260518.png
```

## Observations

- `ttsOffsetUTF16` drops out of the snapshot's `partial` array exactly
  while TTS is speaking (it is `partial`+`null` at idle, authoritative
  while speaking) — a clean signal that the offset is a real,
  TTS-driven value, not a placeholder.
- The `tts?action=start` DebugBridge command drives `TTSService`
  directly (the production audio path), bypassing the UI "Read aloud"
  button — so the artifact screenshot shows the MD reader with content
  rendered but **no TTS control bar**. That is expected: the command
  exercises the service, not the chrome. The service is the same one
  the UI "Read aloud" row drives; criteria 1-3 confirm the MD reader's
  service integration is sound.
- MD's paged-mode defect (Bug #215 — `pageNavigator` nil) does **not**
  affect TTS: TTS reads the book text independently of the render
  pipeline (consistent with round-4's note for the EPUB slice). The
  book opened in MD's default scroll mode here; TTS spoke regardless.
- Verification-only round: no bug discovered, no code changed.

## Artifacts

- `dev-docs/verification/artifacts/feature-26-r5-md-tts-speaking-20260518.png`
  — the MD reader ("Test Markdown Multi-Page") with content rendered
  while the TTS service was speaking (captured between snapshots A and
  C). The TTS control bar is absent because `tts?action=start` drives
  the service, not the UI — see Observations.

## Outcome

Feature #26 stays **DONE**. Round-5 verifies the previously-uncovered
**Markdown** TTS slice at the service level — start → genuine speech
(`ttsOffsetUTF16` 0→176→302) → stop — entirely CU-free via the
DebugBridge `tts` command. Combined with round-2 (TXT), round-4
(EPUB), and the AZW3 capability-gate (`n/a`), the only TTS format not
device-exercised is **PDF** (blocked on the long-standing
no-PDF-fixture harness gap). The `VERIFIED` flip remains gated on the
HTTP-cloud-TTS slice (external server) — unchanged from round-4.
