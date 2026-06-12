---
branch: fix/issue-1687-first-selection-card
threadId: 019ebb20-f028-7842-bac0-9d3c6c01b498
rounds: 3
final_verdict: ship-as-is
date: 2026-06-12
---

# Codex audit — bug #350 (GH #1687) first word-selection card

Runner: `scripts/run-codex.sh` (codex exec, stdin-isolated). Sessions:
round 1 `019ebb20-f028-7842-bac0-9d3c6c01b498`, round 2
`019ebb29-96de-7993-9ab1-e15c47c23af6`, round 3
`019ebb2d-cdd4-7f83-b110-064ef3719d17`.

## Round 1 — 3 findings

| Finding | Severity | Resolution |
|---|---|---|
| `SelectionCardFallback.swift:32` — dedup keys on chunk-LOCAL `NSRange`, but one fallback instance serves every chunk cell; same local range in two chunks aliases (second card suppressed) | High | **Fixed**: both chunked sites (`textViewDidChangeSelection`, `editMenuForTextIn`) now key dedup on the document-GLOBAL range (`chunkOffset + local`); the fallback post re-derives the local range from the live `textView.tag` at fire time and re-validates against `textView.selectedRange`. Regression test `sameLocalRangeInTwoChunksDoesNotAlias` (TXTChunkedReaderBridgeEditMenuTests). |
| `SelectionCardFallback.swift:75` — `cancel()` had no production caller; stale dedup state / pending post could survive content reloads + teardown | Medium | **Fixed**: `cancel()` wired into both `dismantleUIView` implementations AND both content-reload branches (`sourceChanged` in TXTTextViewBridge, `chunksChanged` in TXTChunkedReaderBridge). |
| `TXTBridgeShared.swift:1` — file grew to 330 lines (>~300 guideline) | Low | **Fixed**: selection-notification routing + WI-12b mapping + #350 projection moved to `TXTBridgeShared+SelectionMapping.swift`; both files now well under 300. |

## Round 2 — 2 findings (round-1 fixes verified correct)

| Finding | Severity | Resolution |
|---|---|---|
| `TXTBridgeShared+SelectionMapping.swift:66` — the projection path posted display-domain `selectedText` (translation-row text) with source-domain offsets | Medium | **Fixed**: projection path rebuilds `selectedText` from the projected source span via new `displayText(forSourceRange:map:displayText:)` (per-`.source`-segment linear display slices; synthetic runs skipped). Tests assert `"AAA"` / `"BB"`. |
| `TXTChunkedReaderBridge.swift:352` — `chunksChanged` compares only `count`; same-count chunk rebuild missed the new cancel (and the pre-existing cache invalidation) | Low | **Fixed**: predicate widened to also compare `chunkStartOffsets`. Residual: a same-count same-offsets rebuild is still undetected — accepted (pathological; pre-existing detection design). |

## Round 3 — 1 finding (round-2 fixes verified correct; no new issues in `displayText` bounds or the widened predicate)

| Finding | Severity | Resolution |
|---|---|---|
| `TXTBridgeShared+SelectionMapping.swift:130` — the `selectedText` rebuild ran only on the synthetic-START branch; a selection starting in source text and spanning ACROSS a synthetic row still posted display text (incl. translation content) with source offsets (pre-existing WI-12b behavior, same defect class) | Medium | **Fixed** (post-round-3, with test evidence in lieu of a 4th round): all non-identity bilingual posts now route through one `mapDisplayToSource` + `displayText(forSourceRange:)` tail, so offsets and text always describe the same source span. Regression test `test_bug350_sourceStartSpanningIntoTranslationRow_postsSourceTextOnly` (expects `"AA"`, not `"AA[T"`). |

## Verdict

ship-as-is. All Critical/High/Medium findings fixed; the one Low residual
(same-count same-offsets chunk rebuild) accepted with rationale. Test gate
(TXTBridgeSharedBilingualTests, SelectionCardFallbackTests,
TXTBridgeSharedTests, TXTChunkedReaderBridgeEditMenuTests,
TXTTextViewBridgeEditMenuTests) green after every round. Device
verification: long-press on a `[MOCK译]` synthetic row in dark-blood-age
TXT raises the card (artifact
`dev-docs/verification/artifacts/bug-350-synthetic-row-card-20260612.png`).
