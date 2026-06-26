---
branch: feat/feature-121-wi-2-android-tts-engine
threadId: 019f0405-f121wi2
rounds: 3
final_verdict: ship-as-is
date: 2026-06-26
---

# Feature #121 WI-2 — Codex audit (AndroidTtsEngine TextToSpeech wrapper)

Files: `tts/AndroidTtsEngine.kt` (+ `AndroidTtsEngineFactory`), `tts/TtsVoiceFilter.kt` (new pure
helper), `AndroidManifest.xml` (`<queries>` TTS_SERVICE), `tts/AndroidTtsEngineTest.kt` (instrumented,
3), `tts/TtsVoiceFilterTest.kt` (JVM, 6).

## Round 1 — 3 High, 4 Medium, 2 Low (all fixed)

| severity | issue | resolution |
|---|---|---|
| High | init could resurrect a cancelled/shut-down engine (callback published after cancel) | FIXED — `synchronized(lifecycle)` + `closed` flag; the init callback publishes only when `!closed` |
| High | double init leaked (second `awaitInit` constructed a second TextToSpeech) | FIXED — single-flight (round 2 hardened to a CompletableDeferred) |
| High | `voices()` could drop EVERY voice (`all.size<=1` heuristic) | FIXED — extracted pure `TtsVoiceFilter`: deprioritize very-low but never drop all; JVM-tested |
| Medium | re-entrant init (`var engine` self-ref) could publish null | FIXED (round 2 — earlyStatus defer) |
| Medium | `tryEmit` silently lossy | FIXED (round 2/3 — type-aware split) |
| Medium | `emitFailed` fabricated generation 0 on a malformed id | FIXED — drops unparseable ids |
| Medium | smoke tests too shallow | FIXED — added double-init + shutdown-then-speak instrumented + the JVM voice-filter suite |
| Low×2 | `setVoice(null)` no-op contract unclear | FIXED — documented as "leave current/default" |

## Round 2 — 3 High (all fixed)

| severity | issue | resolution |
|---|---|---|
| High | concurrent `awaitInit()` could construct two engines | FIXED — single-flight `CompletableDeferred` under `lifecycle`; first caller constructs, others join |
| High | re-entrant init (`OnInitListener` before `holder[0]` assigned) could orphan the engine | FIXED — `constructEngine` stashes `earlyStatus` and processes it after assignment via `finishInit` (idempotent complete) |
| High | `DROP_OLDEST` could evict a terminal event | FIXED — split `_terminal` (1024) + `_range` (64, DROP_OLDEST), merged; a range burst can't evict a terminal |

## Round 3 — 1 High (resolved by documented consumer contract)

| severity | issue | resolution |
|---|---|---|
| High | `merge(_terminal,_range)` doesn't guarantee cross-flow ordering (a Range could land before Started / after Done) | RESOLVED-BY-CONTRACT — the engine documents, and the VM (WI-3) enforces, that Range is gated by the CURRENT sentence: applied only while `currentSentence.index == range.index` (the Started→Done window), so an out-of-order/stale Range is ignored. Range is highlight-refinement only; sentence advance is Started-keyed, so reordering/loss is harmless. WI-3 implements + tests the gate (`range-before-started ignored`, `range-after-done ignored`, `range-for-stale-index ignored`). This is the correct layer for the contract (mirrors the iOS TTSHighlightCoordinator). |

Round 3 confirmed the three round-2 lifecycle fixes resolved (single-flight init, no re-entrant orphan,
shutdown completes the deferred outside the lock), no deadlock, no cancelled-await leak beyond the
VM-owned engine that `shutdown()` tears down.

## Summary

3 High + 4 Medium + 2 Low across 3 rounds; all fixed or resolved-by-contract. 6 JVM + 3 instrumented
tests green on emulator-5554. The one round-3 finding is a consumer contract the VM owns (WI-3), not an
engine bug. **Verdict: ship-as-is.**
