---
branch: feat/feature-72-wi-4-cloud-tts-verify
threadId: 019e63c5-95bb-7bd0-a475-382ffadd2809
rounds: 4
final_verdict: ship-as-is
date: 2026-05-26
---

# Codex Audit — Feature #72 WI-4 (verification) + WI-5 (failure-to-idle fix)

This branch began as WI-4 (the final/verification work item of feature #72:
"wire the orphaned HTTP cloud-TTS provider into live read-aloud"). The
high-fidelity integration test uncovered a real end-to-end defect, so the branch
also carries WI-5 — a production state-machine fix in `TTSService`.

Files audited:
- `vreaderTests/Integration/Feature72CloudTTSIntegrationTests.swift` (new)
- `vreader/Services/TTS/TTSService.swift` (WI-5 fix)
- `vreaderTests/Services/TTSServiceTests.swift` (WI-5 regression tests + mock fix)
- `docs/architecture.md` (Services Layer rows for the TTS cloud path)
- grounded against `HTTPSpeechSynthesizer`, `HTTPTTSChunkPlayer`,
  `HTTPTTSProvider`, `HTTPTTSConfigStore`, `HTTPTTSConfig`, `SpeechSynthesizing`.

## Part A — WI-4 integration test (rounds 1-2)

### Round 1
| # | file:line | severity | issue | resolution |
|---|---|---|---|---|
| A1 | Feature72CloudTTSIntegrationTests.swift:28 | High | Test inferred (rather than observed) the `URLSessionProtocol` seam — `audio.built.count == chunkCount` only proved `makePlayer` ran N times. Surfaced a latent gap: the test `bodyTemplate` used lowercase `{{text}}` while `buildCustomRequest` only expands uppercase `{{TEXT}}`/`{{VOICE}}`, so the stub passed by ignoring the body. | **Fixed.** Added a thread-safe `RequestRecorder` (`@unchecked Sendable`, NSLock) wired into `StubURLSession`; switched to `{{TEXT}}`/`{{VOICE}}` + a custom header; added direct transport-contract assertions (`requests.count == chunkCount`, all `POST`, all to the endpoint, all carry the custom header, each chunk's text in some recorded body). |

Codex also affirmed `maxOffset > 0` is meaningful (only the real delegate
plumbing moves `currentOffsetUTF16` above its initial 0), the `pump` loops are
bounded, and found no real-network reliance, global-state coupling, doc
mismatch, or Swift 6 isolation issues.

### Round 2 — **No findings.** Transport-observation gap closed; assertions
reflect the real `buildRequest`/`buildCustomRequest` contract; `RequestRecorder`
NSLock makes `@unchecked Sendable` defensible (`data(for:)` may run off-main from
the adapter's synthesis task); no sampling race (all transport calls recorded
before `state == .idle`).

## Part B — WI-5 production fix (rounds 1-2 within the same thread)

**Defect found by WI-4's failure-path test**: a cloud synthesis error fires
`didCancel` while `state == .speaking`; `TTSService`'s old delegate handler used
`if state == .speaking { return }` (meant to ignore the OUTGOING utterance's
cancel during a restart) and SWALLOWED the failure cancel → state machine wedged
in `.speaking` with no audio. Violated feature #72 acceptance criterion C5
("failure stops cleanly to idle"). Fixed by a `pendingRestartCancels` counter:
a restart arms one expected cancel; a `didCancel` with no pending restart is
terminal → idle.

### Round 1
| # | file:line | severity | issue | resolution |
|---|---|---|---|---|
| B1 | TTSService.swift:148 | High | Counter armed from `state` (the `@Observable` proxy), which lags the backend (didFinish/didCancel hop through a Task). A restart issued just after natural completion sees `state == .speaking` yet `stopSpeaking()` stops nothing and emits no cancel → counter leaks positive → next terminal cancel swallowed, recreating the wedge. | **Fixed.** Arm from the `stopSpeaking()` RESULT (`true` iff an active utterance was stopped and a cancel will follow), not from `state`. Corrected `MockSpeechSynthesizer.stopSpeaking()` to return `isSpeaking \|\| isPaused` (matching the real synthesizers' contract). Added regression test `restartAfterBackendQuietlyFinished_doesNotLeakRestartCancel`. |

Codex confirmed (round 1) no underflow risk and that `pendingRestartCancels` is
only mutated on the main actor (no Swift 6 data race), and that `stop()` needs
no reset — the real problem was the false-positive arm.

### Round 2 — **No findings. Ship as-is.** Arming from `stopSpeaking()`'s Bool is
the right predicate across all three backends (on-device forwards AVFoundation's
Bool; adapter `performStop` returns `wasActive` and fires `didCancel` iff
`wasActive`; corrected mock returns `isSpeaking || isPaused`). Ordering is safe:
the adapter fires `didCancel` synchronously (scheduling a `@MainActor` Task), but
that Task cannot run until the synchronous `startSpeaking` body — including the
post-stop increment — finishes its turn, so the consume side always sees
`pendingRestartCancels >= 1` for a real restart cancel.

## Verdict

**ship-as-is.** The integration test is a genuine high-fidelity verification of
the cloud read-aloud path through real subsystem boundaries (TTSService →
HTTPSpeechSynthesizer → HTTPTTSProvider), with only the network transport and
audio hardware stubbed — satisfying the AGENTS.md close-gate verification-exception
bar for feature #72. The WI-5 fix closes feature #72 acceptance criterion C5
(failure stops cleanly to idle) end-to-end while preserving the restart-cancel
race guard (regression tests green).
