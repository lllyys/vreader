---
branch: fix/issue-1604-ai-chat-markdown
threadId: bug335-r1-and-r2-run-codex
rounds: 2
final_verdict: ship-as-is
date: 2026-06-10
---

# Gate-4 Codex audit — Bug #335 (AI chat + summary render raw markdown)

Independent audit via `scripts/run-codex.sh` (gpt-5.4), read-only.

## Round 1

| file:line | severity | issue | resolution |
|---|---|---|---|
| ChatMarkdownRenderer.swift | Medium | `.inlineOnlyPreservingWhitespace` leaves `- item` as literal hyphens (no block list layout) — the bug's "literal `-` lists" case stays open. | **Fixed** — `normaliseListMarkers()` converts a leading `-`/`*`/`+ ` (indent-preserving) to a `• ` bullet before parsing. Tests: `unorderedListMarkersBecomeBullets`, `indentedListMarkerKeepsIndentAndBullets`, `nonListHyphenIsNotTouched`. |
| ChatMarkdownRenderer.swift | Medium (security) | Markdown links from attacker-influenced LLM output pass through with arbitrary schemes (`tel:`, custom deep-link, `javascript:`) into a selectable surface — phishing / deep-link surface. | **Fixed** — `stripUnsafeLinks()` removes `.link` from any run whose scheme ∉ {http, https, mailto}, keeping the text. Tests: `unsafeSchemeLinkIsStrippedButTextKept` (vreader-debug://), `telAndJavascriptSchemesStripped`, `httpsLinkIsPreserved`. |
| ChatMarkdownRenderer.swift | Low | Per-`body`-render reparse of the full string. | **Accepted** with rationale (documented in the file header): #323 coalesces streaming to ~one flush per 96 chars and chat/summary messages are short, so the O(n) reparse is not a hot path. |

**Note (not a finding):** the auditor flagged legacy `AIAssistantView.swift` as having the same `Text(String)` shape. Confirmed **dead code** — `AIAssistantView(` is never constructed anywhere (active surfaces are `AIChatView` / `AISummaryTabView`). No action.

Round-1 also confirmed correct: the inline-markup fix, newline preservation, malformed-streaming graceful degradation, empty-string handling, literal `*` (e.g. `5 * 3`) left alone, `TranslationResultCard` correctly left plain, user bubbles correctly left plain, `nonisolated static` Swift-6 safe.

## Round 2

All 3 round-1 findings confirmed **RESOLVED**; no open issues. Auditor specifically verified the `^(\s*)[-*+]\s+` regex matches only line-start unordered markers (numbered lists + mid-line hyphens untouched), and `stripUnsafeLinks` rejects uppercase schemes (normalised) and scheme-relative `//evil` (no allowed scheme).

## Verdict

**ship-as-is.** Both Medium findings fixed + pinned by tests (13 tests green); Low accepted with documented rationale; round-2 clean.
