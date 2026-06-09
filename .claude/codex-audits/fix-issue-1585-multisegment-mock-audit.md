---
branch: fix/issue-1585-multisegment-mock
threadId: 019eab1e-6d77-7c13-95fa-25858e277a7e
rounds: 1
final_verdict: ship-as-is
date: 2026-06-09
---

# Codex Audit — MockAIProvider chunk-contract JSON-array reply (#1585)

DEBUG-only change: `MockAIProvider.reply(for:)` now returns a strict JSON array
of N `[MOCK译] …` strings for a `TranslationChunkContract.userPrompt` (so the
bilingual chunk translate decodes on the first attempt instead of the slow
per-segment fallback).

## Round 1 findings

| file:line | severity | issue | resolution |
|---|---|---|---|
| MockAIProvider.swift (chunkContractArrayReply) | Medium | Splitting the body on every `\n\n` over-splits a source segment that itself contains a blank line (`[0] a\n\nb\n\n[1] c` → 3 parts) → wrong array length → decode falls back. | **Fixed** — parse by numbered headers via regex `(?:\A\|\n\n)\[\d+\]\s?([\s\S]*?)(?=\n\n\[\d+\]\s\|\z)`; a header only counts at start or after a blank line, so internal blank lines stay inside the segment. Test: `reply_chunkContract_segmentWithInternalBlankLine_keepsCount`. |
| MockAIProvider.swift (chunkContractArrayReply) | Low | Filtering out empty/whitespace segments dropped valid empty numbered segments → fewer than N elements → decode fails. | **Fixed** — emit exactly one element per matched header, including empty bodies. Test: `reply_chunkContract_emptySegment_stillEmitsElement`. |

Codex confirmed (no finding): the legacy single-segment translate path is
unchanged (`reply_translateActionProducesInterlinearMarker` still passes — the
array path only triggers when the prompt contains BOTH `JSON array of exactly`
AND `Source segments:`); returning `nil` to fall through is correct for
non-contract prompts.

## Verdict

ship-as-is — both findings fixed + covered by tests. Build SUCCEEDED.

## Note

This enhancement was built to close the Feature #77 Foliate Gate-5b gap; it does
NOT (the Foliate translation-replace stays stuck even with a valid multi-segment
reply — a real Foliate bilingual-inject defect, filed as bug #334 / GH #1586).
It still removes the per-segment fallback for the EPUB engines and was the
diagnostic that isolated the Foliate bug from the mock.
