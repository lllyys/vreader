---
branch: feat/feature-121-wi-4-tts-control-bar
threadId: 019f0405-f121wi4
rounds: 1
final_verdict: ship-as-is
date: 2026-06-27
---

# Feature #121 WI-4 — Codex audit (TTS control bar + voice/speed sheets)

Files: `tts/TtsControlBar.kt`, `tts/TtsSpeedSheet.kt`, `tts/TtsVoiceSheet.kt`, instrumented
`TtsControlBarTest.kt` (4) + `TtsSheetsTest.kt` (3).

## Round 1 — 1 Medium, 2 Low (all fixed)

| file | severity | issue | resolution |
|---|---|---|---|
| TtsControlBar Chip | Medium | unbounded chip text — a long voice label / invalid rate label could overflow / push transport controls | FIXED — `Chip` Text is `maxLines=1` + `TextOverflow.Ellipsis`; the voice chip is `widthIn(max=240.dp)` |
| TtsSpeedSheet FlowRow | Low | preset pills wrapped start-biased, design centers them | FIXED — `Arrangement.spacedBy(8.dp, Alignment.CenterHorizontally)` |
| TtsControlBar play/pause + icon btns | Low | the action label was only on the child Icon, not the clickable node | FIXED — `clickable(onClickLabel = …)` on the play/pause + IconBtn nodes; the child icons are now decorative (`contentDescription = null`) |

Codex confirmed: no statelessness/recomposition issue (the composables hold no local mutable state,
render as pure functions of inputs + callbacks), and the not-installed voice row correctly routes to
`onInstall` (not `onVoice`).

## Summary

1 Medium + 2 Low, all fixed; 7 instrumented Compose tests green on emulator-5554. **Verdict: ship-as-is.**
