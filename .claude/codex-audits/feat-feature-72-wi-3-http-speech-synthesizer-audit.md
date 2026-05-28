---
branch: feat/feature-72-wi-3-http-speech-synthesizer
threadId: 019e63b4-7677-79e3-a846-9fcce57ebb78
rounds: 3
final_verdict: ship-as-is
date: 2026-05-26
---

# Codex audit — Feature #72 WI-3 (HTTPSpeechSynthesizer adapter)

Gate-4 audit (Codex MCP, 3 rounds) of the adapter wiring HTTPTTSProvider into the
SpeechSynthesizing/TTSService path + the `defaultSynthesizer` selection.
Files: `HTTPSpeechSynthesizer.swift` (new), `TTSService.swift`, `HTTPSpeechSynthesizerTests.swift` (new).

## Round 1 — 1 High + 1 Medium
| # | Sev | Finding | Resolution |
|---|---|---|---|
| 1 | High | Pause during the initial network-synthesis window (before the first chunk plays): `performPause` returned false (player not yet playing) but TTSService flips `.paused` unconditionally → synthesis continues + the first chunk auto-plays while UI says "paused". | Adapter now tracks `wantsPaused` + buffers synthesized chunks while paused (`acceptSynthesizedChunk`/`markSynthesisComplete` deferral); `performPause` succeeds whenever an utterance is in flight; `continueSpeaking` flushes buffered chunks. |
| 2 | Med | Main async test too weak (only "≥1 willSpeak"); no exact ranges, no precedence, no pause-before-first-chunk. | `willSpeakLocations == chunkRanges(...).map(\.location)` exact; added `pauseBeforeFirstChunk_buffersUntilResume` + mock>config>system precedence test. |

## Round 2 — 1 Medium (new)
| 3 | Med | `synthTask` never cleared on terminal paths → after completion `synthTask != nil` faked an "active" adapter (pause/stop misbehave). | `synthGeneration` token + `clearSynthTask(gen:)` on every terminal path (success/cancel/error), bumped on speak/stop so a stale task can't clobber a newer one; `afterCompletion_isIdle_pauseReturnsFalse` test. |

## Round 3 — clean
No new issue. Stop/restart ordering sound (generation bumped before cancel); pause/resume + deferred markInputComplete preserves chunk order + terminal didFinish.

## Confirmations (round 1)
- `MainActor.assumeIsolated` is defensible — TTSService (@MainActor) is the only caller; no off-main call sites.
- The @MainActor Task inherits isolation; `Task.checkCancellation` + the chunk player's generation token cover stale-enqueue after stop.
- `chunkRanges` forward-scan is correct for repeated sentences + CJK (NSString UTF-16) + whitespace.
- No `didCancel` double-fire (`fireDidCancel` nils currentUtterance).
- `defaultSynthesizer` precedence: mock > valid config > system.

## Verification
`HTTPSpeechSynthesizerTests` — 10 tests pass (UDID-pinned, `-parallel-testing-enabled NO`): exact willSpeak locations, didFinish, synthesis-failure→didCancel, stop→didCancel+provider.cancel, pause-buffering, idle-after-completion, chunkRanges (incl. unlocatable), defaultSynthesizer selection + mock precedence.

## Verdict
**Ship-as-is.** No open findings after round 3. This WI makes cloud TTS functional; device-verify against a real endpoint is WI-4.
