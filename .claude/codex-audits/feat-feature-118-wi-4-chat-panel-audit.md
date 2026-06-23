---
branch: feat/feature-118-wi-4-chat-panel
threadId: 019eec98-f118wi4
rounds: 1
final_verdict: ship-as-is
date: 2026-06-22
---

# Codex audit — feature #118 WI-4 (chat panel + AiChatViewModel + AiMarkdownRenderer)

Scope: `android/app/.../ai/{AiChatUiState,AiChatViewModel,AiMarkdownRenderer,AiChatPanel}.kt` +
tests. The AI chat + summary panel (streaming answer, suggested prompts, per-chapter summary cache,
unconfigured gate). Instrumented panel tests + VM tests pass on emulator-5554.

## Round 1 — 2 findings (2 Medium)

| file:line | severity | issue | resolution |
|---|---|---|---|
| AiChatViewModel.summarize | Medium | The summary cache key used `chapterText.hashCode()` — a 32-bit String hash that collides easily, so two different chapters could share a cached summary (stale, no network call). | FIXED — key uses `sha256(chapterText)` over UTF-8 + the EFFECTIVE model (`model.ifBlank { kind.defaultModel }`). |
| AiChatViewModel.send | Medium | A stream started under provider A wasn't invalidated if the active provider changed mid-flight — the old collect kept writing `streamingText` and appended the final assistant message. | FIXED — a `chatGen` generation token (bumped on `send` and on an active-provider change in `refreshProvider`, which also cancels the in-flight `streamJob`); chunk updates + the final append are applied only if `gen == chatGen`. |

Codex found NO defect in `AiMarkdownRenderer` (partial/malformed crash-safety + newline assembly
sound); the full-history resend per turn is an accepted v1 token tradeoff, not a correctness bug.
Both fixes are mechanical and match the prescribed remedy; 8 JVM tests green after.

Verdict: **ship-as-is.** 5 `AiMarkdownRendererTest` + 3 `AiChatViewModelTest` (JVM) + 4 instrumented
`AiChatPanelTest` green on emulator-5554 + full `:app` suite green. Slice-verified (Gate-5a); the
live end-to-end acceptance (streamed answer against a real provider stub) is WI-5.
