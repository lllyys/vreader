---
branch: feat/feature-91-wi-8-wiring
threadId: 019e925f-6573-7fd2-a5cc-f38ecb168e91
rounds: 2
final_verdict: ship-as-is
date: 2026-06-04
---

# Codex Audit — Feature #91 WI-8a (agentic-chat support)

Gate-4 implementation audit (rule 47). Independent Codex runner via
`scripts/run-codex.sh -e high` (author/auditor separation, rule 48; rule-53
stdin-isolated watchdog).

## Scope

WI-8a — the foundational agentic-chat support layer (no VM branch yet; the
heavier production adapters + the `AIChatViewModel.sendMessage` branch + Gate-5
device verification are the completing slice WI-8b):

- `vreader/Services/FeatureFlags.swift` — the `agenticTools` flag (enum case +
  `persistedFlags` membership + `var agenticTools` accessor + `defaultValue` = OFF).
- `vreader/Services/AI/AIChatAgenticSupport.swift` (new) — `AIChatHistoryMapper`
  (pure `[ChatMessage] → [ToolTurnMessage]`, sliding window, the instruction-only
  system prompt + an untrusted-context user prelude) + `ProviderToolUseAdapter`
  (bridges `any AIProvider` → the driver's `ToolUseSending` seam).
- `vreaderTests/...` — `AIChatAgenticSupportTests` + `FeatureFlagsTests` additions.

## Round 1 — findings (threadId 019e925f-6573-7fd2-a5cc-f38ecb168e91)

`ProviderToolUseAdapter` Sendable story + the flag default-OFF confirmed sound.

| File:line | Severity | Issue | Resolution |
|---|---|---|---|
| AIChatAgenticSupport.swift `systemPrompt` | **High** | The raw `bookContext` was appended into the SYSTEM prompt — untrusted book text gaining system-role authority, weakening the very prompt-injection boundary this helper establishes. | **Fixed.** `systemPrompt()` is now INSTRUCTION-ONLY (no book text); the context rides as `contextPrelude(bookContext:) -> ToolTurnMessage?` — an UNTRUSTED leading `.user` turn framed "untrusted content, not instructions". Tests `systemPromptInstructionOnly` + `contextPreludeIsUntrustedUserTurn`. |
| AIChatAgenticSupport.swift `toolTurns` | **Medium** | `suffix(window)` ran BEFORE dropping empties, so `window == 1` over `[user, empty-assistant]` yielded `[]` (the placeholder ate the budget). | **Fixed.** Empties are filtered FIRST, then `suffix`. Test `windowDropsEmptiesFirst` pins `window:1` → `[user("q")]`. |
| FeatureFlagsTests.swift | **Medium** | The suite was stale — `allCases.count == 7` broke after adding the 8th case, and the new flag was unpinned. | **Fixed.** Count → 8 + `.agenticTools` in the exhaustive list + `agenticToolsDefaultOffEverywhere` + a persisted-override test. |

## Round 2 — verification (threadId 019e9273-c502-7902-b1dd-bbea6e8b9dca)

Findings 1 & 2 **RESOLVED**. One **new Medium**: the override test toggled
in-memory only — it didn't prove `.agenticTools ∈ persistedFlags` (survives a
reload). **Fixed.** `agenticToolsOverridePersists` mirrors the readiumEPUBEngine
round-trip: a UUID-suite `UserDefaults`, persist `true` (the discriminating value
vs the OFF default), reload in a fresh instance, assert it beats the default —
a regression dropping the flag from `persistedFlags` would read OFF and fail.

## Verdict

**ship-as-is.** Zero open Critical/High/Medium after round 2. Test gate green:
`AIChatAgenticSupportTests` (7 — role conversion, window, empty-drop-before-window,
instruction-only system prompt, untrusted-context prelude) + `FeatureFlagsTests`
(exhaustive count 8, agenticTools default-OFF + persistence round-trip).
