---
branch: feat/feature-121-wi-5-txt-tts-integration
threadId: 019f0405-f121wi5
rounds: 2
final_verdict: ship-as-is
date: 2026-06-27
---

# Feature #121 WI-5 — Codex audit (TxtReader read-aloud integration)

Files: `reader/TxtReaderActivity.kt` (integration), `tts/TtsHighlight.kt` + `TtsHighlightTest.kt` (5),
`tts/TtsViewModel.kt` (`voiceListState()`), `tts/TxtTtsConnectedTest.kt` (live pipeline).

## Round 1 — 1 High, 4 Medium, 1 Low (all fixed)

| severity | issue | resolution |
|---|---|---|
| High | eager whole-book `TtsChunker.chunk` ran on composition (jank/memory on large books) | FIXED — chunking is LAZY + off-main (`withContext(Dispatchers.Default)`), only when Read aloud is tapped |
| Medium | auto-scroll fought manual scroll every sentence | FIXED — auto-scroll only when the spoken chunk is NOT in `visibleItemsInfo` |
| Medium | background playback unmanaged (kept speaking on Home) | FIXED — a `LifecycleEventObserver` pauses on `ON_STOP` (no MediaSession by design; engine shut down on Activity finish via VM `onCleared`) |
| Medium | `Install voice data` `resolveActivity` false-negative on API 30+ | FIXED — `launchTtsIntent` try/catch `startActivity(ActivityNotFoundException)` with fallbacks, no `resolveActivity` preflight |
| Low | `voiceListState()` ran every recomposition | FIXED — `remember(showVoice)` snapshot |

Codex confirmed the pure TXT span math (`TtsHighlight.localSpan`, half-open + clamped) and the
md-vs-txt highlight gating are correct.

## Round 2 — 2 Medium (fixed)

| severity | issue | resolution |
|---|---|---|
| Medium | double-tap could launch two full-book chunk coroutines → restart from sentence 0 | FIXED — a `starting` flag disables the entry while chunking, cleared in `finally` |
| Medium | `ON_STOP` fires on rotation too → would pause TTS on a config change (VM is retained) | FIXED — the pause is gated by `!isChangingConfigurations` |

Round 2 confirmed `launchTtsIntent`, the voice-list snapshot, and the auto-scroll visibility check are
clean; TTS-driven position-save is acceptable (spoken progress IS the reader's visible position).

## Summary

1 High + 4 Medium + 1 Low (R1) + 2 Medium (R2), all fixed. 5 `TtsHighlightTest` + the live
`TxtTtsConnectedTest` + the WI-4 Compose suite green on emulator-5554. **Verdict: ship-as-is.**
