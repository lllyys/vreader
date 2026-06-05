---
branch: feat/feature-85-wi-2-highlight-requote
threadId: 019e95d9-2f67-7682-bc11-120cddc646fa
rounds: 2
final_verdict: ship-as-is
date: 2026-06-05
---

# Gate-4 Implementation Audit — Feature #85 WI-2 (cross-engine highlight quote re-anchor)

Codex `gpt-5.4` / high, read-only. Author = claude; auditor = Codex (separate
context). Approach C: when EPUB scroll renders the legacy #71 stitch, a
Readium-created highlight (empty `serializedRange`, but a persisted quote +
context) must still paint. Changed source: `EPUBHighlightJS.swift` (the new
`__vreader_createHighlightInSectionByQuote` + `findQuoteRangeInRoot`),
`EPUBHighlightBridge.swift` (generator branch on empty range),
`EPUBHighlightActions.swift` (thread the quote + context).

## Round 1 — session `019e95d5-29c3-78c2-a511-de9eb60a1fe6` → block-recommended

| file:line | severity | issue | resolution |
|---|---|---|---|
| EPUBHighlightJS.swift:340 | Medium | `findQuoteRangeInRoot` used only `contextBefore + quote` then the first raw match; `contextAfter` was threaded but unused → a repeated quote (same leading context) or a stale `contextBefore` could silently mis-anchor. | **Fixed** — mirror Swift `QuoteRecovery`: `allIndexes` enumerates ALL occurrences; `choose()` scores BOTH preceding (`contextBefore` suffix) AND following (`contextAfter` prefix) context and picks the best. |
| EPUBHighlightJS.swift:341 | Low | Exact-only matching → cross-engine whitespace/case drift = silent no-op. | **Partially fixed / accepted** — added a case-insensitive fallback (lowercased flat + quote + contexts). Whitespace-normalized matching is NOT ported (the offset re-mapping is complex in JS); a quote matching neither degrades to a NO-OP (no paint), never a WRONG anchor — accepted with rationale. |

## Round 2 — session `019e95d9-2f67-7682-bc11-120cddc646fa` → ship-as-is

> Medium resolved; no new Critical/High/Medium. The updated `choose()` uses
> both `contextBefore` and `contextAfter`; the accepted whitespace-normalization
> omission still degrades to no-op rather than wrong-anchor; no new
> `allIndexes`/`locate()` off-by-one.

## Verdict

**ship-as-is.** The quote re-anchor routes through the existing
`applyHighlightRange` pipeline (so tap/delete keep working) and excludes
`data-vreader-decoration` bilingual subtrees. Generator unit tests green
(empty-range → byQuote call; non-empty → path call; mixed → both). The JS DOM
behavior (the find-and-paint in the stitched section) + WI-1's seam-removal +
bidirectional position are the feature's Gate-5b on-device acceptance.
