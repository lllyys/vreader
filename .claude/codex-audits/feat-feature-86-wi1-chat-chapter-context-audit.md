---
branch: feat/feature-86-wi1-chat-chapter-context
threadId: codex-exec (run-codex.sh)
rounds: 1
final_verdict: ship-as-is
date: 2026-06-03
---

# Codex audit — Feature #86 WI-1: chapter-scoped chat context (Gate 4)

## Implementation summary

The Chat tab's `bookContext` now covers the WHOLE current chapter (not the fixed
~2500-char `.section` window), bounded by `AIContextBudget.defaultMaxUTF16`
(12_000). `ReaderAICoordinator` gains `tocEntries`, a computed `chatContext`
(reuses the #69 `SummaryScopeResolver` + `AIContextExtractor` `.chapter` path;
degrades to `.section` for nil bounds / no locator / no text), and a single
idempotent `refreshChatContext()` that is the ONLY chat-`bookContext` writer. The
host calls it on every state change (text load, locator relocate, TOC arrival).

Plan: `dev-docs/plans/20260603-feature-86-chat-context-scope.md` (Gate-2 audited,
2 rounds, READY TO BUILD).

## Round 1 findings

| file:line | severity | issue | resolution |
|---|---|---|---|
| ReaderContainerView+Sheets.swift:125 | Medium | The AZW3/Foliate TTS path (`startAZW3TTS`) set `ai.loadedTextContent = text` WITHOUT `refreshChatContext()`. In the "start TTS first, then open Chat" Foliate flow, the chat VM already exists, so `bookContext` stayed on the stale fallback until a later locator/TOC event. The one remaining text-state mutation not funnelled. | **Fixed.** Added `ai.refreshChatContext()` immediately after the `loadedTextContent = text` write in that path. |
| ReaderAICoordinatorChatContextTests.swift | Low | The 5 tests validate `chatContext` (pure value) but don't exercise `refreshChatContext()` with a live `chatViewModel`. | **Accepted with rationale.** `refreshChatContext()` is the trivial guarded one-liner `chatViewModel?.bookContext = chatContext`; the substantive logic (the chapter-vs-section computation + the degrade/clamp branches) is fully covered by the 5 `chatContext` tests. A behavior test would require relaxing `chatViewModel`'s `private(set)` + full `AIService` construction across the test boundary — disproportionate for a one-line assignment. The call-site wiring (every state change funnels through `refreshChatContext`) is Codex-audited here, and the AZW3 gap it would have motivated is fixed above. |

Codex confirmed sound: `chatContext` matches the plan (whole chapter / section
fallback); `refreshChatContext()` is the only remaining `bookContext` writer; the
unconditional locator-change refresh is safe (no-text reuses the fallback); the
budget clamp / CJK / surrogate handling is correct via `AIContextExtractor` +
`UTF16TextSlicer`.

## Verdict

`ship-as-is` — zero open Critical/High/Medium after the AZW3 Medium fix; the one
Low is accepted with rationale.

## Verification

- Unit: `ReaderAICoordinatorChatContextTests` (5 — chapter-not-section,
  empty-TOC-degrade, no-locator-degrade, no-text-fallback, over-budget-clamp).
- Device (Gate-5): the chapter-context LOGIC is unit-proven; the end-to-end
  (the chat ANSWERS using the whole chapter) needs a configured AI provider key
  (entering API keys on-device is prohibited here) and there is no CU-free probe
  for `chatViewModel.bookContext`'s value — so this WI's user-facing slice is
  `awaiting-device-verification` (a keyed pass confirms the chat answers from
  the chapter, not the 2500 window). Intermediate WI — the feature stays
  IN PROGRESS (parts 2/3 are needs-design).
