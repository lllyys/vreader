---
branch: feat/feature-121-wi-1-tts-core
threadId: 019f0405-f121wi1
rounds: 1
final_verdict: ship-as-is
date: 2026-06-26
---

# Feature #121 WI-1 — Codex audit (TTS models + chunker + engine interface, pure)

Files: `tts/TtsModels.kt`, `tts/TtsEngine.kt`, `tts/TtsChunker.kt`, `tts/TtsChunkerTest.kt` (10),
`tts/TtsModelsTest.kt` (2).

## Round 1 — 1 High, 2 Medium (all fixed, covered by tests)

| file | severity | issue | resolution |
|---|---|---|---|
| TtsChunker.kt capSpan | High | a degenerate `maxUtteranceChars` (≤0, or 1 with a leading surrogate) could leave `cut == s` → no progress → infinite loop / negative index | FIXED — `chunk` coerces the cap to a `MIN_UTTERANCE_CHARS=16` floor, and capSpan's fallback now advances by one whole code point (`Character.charCount(codePointAt(s))`) so the loop ALWAYS progresses. Test `tinyCapNeverHangsAndMakesProgress` (cap=1) |
| TtsModels.kt parse | Medium | `TtsUtterance.parse` accepted negative generation/index (a hostile `"-1:-3"` callback id) | FIXED — `parse` rejects non-`>=0` halves; `TtsUtterance` has an `init { require(generation>=0 && index>=0) }`. Test `rejectsMalformedIds` |
| TtsEngine.kt | Medium | `isLanguageAvailable` returned the raw Android `TextToSpeech` int → leaked platform constants into the VM seam | FIXED — added `TtsLanguageAvailability { available, missingData, notSupported }`; the interface returns it, the production engine (WI-2) maps the raw codes |

Codex confirmed no offset-round-trip / terminator-at-EOF / nested-closer / abbreviation-at-EOF
correctness bug, and file sizes within convention. The fixes are mechanical + test-covered.

**Verdict: ship-as-is.**
