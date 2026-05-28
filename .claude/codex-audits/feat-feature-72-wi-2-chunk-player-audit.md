---
branch: feat/feature-72-wi-2-chunk-player
threadId: 019e63a1-d7f6-7641-8f3a-dba79360273c
rounds: 3
final_verdict: ship-as-is
date: 2026-05-26
---

# Codex audit — Feature #72 WI-2 (HTTPTTSChunkPlayer)

Gate-4 audit (Codex MCP, 3 rounds) of the sequential audio-chunk playback queue.
Files: `HTTPTTSChunkPlayer.swift` (new), `HTTPTTSChunkPlayerTests.swift` (new).

## Round 1 — 2 High + 2 Medium
| # | Sev | Finding | Resolution |
|---|---|---|---|
| 1 | High | Stale `onFinish` after `stop()`/`play()`-replace advances the queue / fires `onFinished` spuriously / skips chunk 0 of a new queue. | **Generation token** bumped on stop/play; `handleFinish(gen:)`/`handleFailure(gen:)` ignore stale gens; `detachCurrent()` nils old callbacks + stops. |
| 2 | High | `onFinished` fired on drain even mid-stream (a short chunk finishing before the next arrives → premature finish). | **`inputComplete` flag + `markInputComplete()`**; `onFinished` only when drained AND input complete; `play(chunks:inputComplete:)`. |
| 3 | Med | Stop/stale-finish test didn't assert `onFinished` stayed suppressed. | Test now asserts `finished == false` + added a replacement-queue stale-finish case. |
| 4 | Med | `successfully: false` advanced as success (masks playback failure). | `SpeechAudioPlaying.onFailure`; `AVAudioPlayerBox` routes `flag==false` → onFailure → onError (no advance) + test. |

## Round 2 — 1 Medium (new)
| 5 | Med | `markInputComplete()` not idempotent — re-fires `onFinished` on repeated calls when already drained. | One-shot `completionDelivered` guard + `deliverCompletion()` at all 3 completion sites; reset on play/stop; idempotency test. |

## Round 3 — clean
No new issue. Generation-token stale protection holds; completion is one-shot.

## Verification
`HTTPTTSChunkPlayerTests` — 10 tests pass (UDID-pinned, `-parallel-testing-enabled NO`): sequential play, pause/resume, stop-then-stale-finish (no advance/finish), replacement-queue stale-finish, streaming drain-before-complete, markInputComplete-while-playing, idempotent completion, empty queue, build failure, unsuccessful-finish→onError.

## Verdict
**Ship-as-is.** No open findings after round 3. Does NOT manage AVAudioSession (TTSService owns it).
