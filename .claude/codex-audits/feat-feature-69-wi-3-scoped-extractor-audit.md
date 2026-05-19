---
branch: feat/feature-69-wi-3-scoped-extractor
threadId: 019e3e48-b1a7-7d21-a654-3c9dedd416ad
rounds: 2
final_verdict: ship-as-is
date: 2026-05-19
---

# Gate-4 Implementation Audit — Feature #69 WI-3

WI-3: `AIContextExtracting` protocol + `AIContextBudget` constant +
`AIContextExtractor` scope-aware extraction (`.section` / `.chapter` /
`.bookSoFar`) + surrogate-safe UTF-16 slicing.

## Files audited

- `vreader/Services/AI/AIContextExtractor.swift` (modified)
- `vreader/Services/AI/AIContextExtracting.swift` (new — split out)
- `vreader/Services/AI/UTF16TextSlicer.swift` (new — split out)
- `vreaderTests/Services/AI/AIContextExtractorScopedTests.swift` (new)

## Round 1 — findings

| file:line | severity | issue | resolution |
|---|---|---|---|
| `AIContextExtractor.swift:280` | Medium | The scoped TXT paths read only `locator.charOffsetUTF16`; a selection-anchored locator with `charRangeStartUTF16` but no `charOffsetUTF16` would make `.chapter` anchor to `chapStart` and `.bookSoFar` treat the whole text as "so far" — diverging from the legacy `.section` behavior and plan §2.3. | **Fixed** — added `resolvedOffsetUTF16(for:in:fallback:)`: resolves `charOffsetUTF16 ?? charRangeStartUTF16 ?? fallback`, clamps to `[0, utf16.count]`. Both scoped helpers now use it (`.chapter` window centers on it with `fallback: chapStart`; `.bookSoFar` uses `fallback: totalUTF16`). |
| `AIContextExtractorScopedTests.swift:78` | Low | Over-budget chapter tests used uniform text + length-only assertions; `chapterScopeDoesNotSplitSurrogatePairs` used pre-aligned even bounds — a wrong centered/clamped window or broken snap logic could pass. | **Fixed** — over-budget chapter tests now use distinct marker segments (H/L/M/R/T) and assert the exact slice. Added `chapterScopeOverBudgetWindowClampsToRightEdge`, `chapterScopeOddBoundsOnSurrogateTextSnapToScalars` (odd bounds on emoji text), and `charRangeStartUTF16`-only regressions for both scoped paths. |
| `AIContextExtractor.swift:1` | Low | The file grew to 366 lines, over the ~300-line guideline. | **Fixed** — split into three files: `AIContextExtractor.swift` (285 lines), `AIContextExtracting.swift` (budget constant + protocol + extension overload), `UTF16TextSlicer.swift` (the surrogate-safe slice / `scalarAlignedIndex`). |

No Critical/High findings. The protocol shape matched plan §2.5, the
legacy 3-arg `.section` shim is byte-identical, and the
snap-up-start / snap-down-end slicing is sound (no path yields a lone
surrogate or inverted range after clamping).

## Round 2 — verification

Codex re-reviewed all four files: "No new Critical/High/Medium
findings … The offset handling is now coherent … That fixes the prior
divergence for selection-anchored locators, and the new regression
tests cover both `.bookSoFar` and over-budget `.chapter`. The slicer
split is clean … the strengthened tests now exercise exact
centered/clamped windows plus odd surrogate boundaries, which closes
the main review gap."

## Verdict

**ship-as-is.** Zero open Critical/High/Medium findings after 2
rounds. 40 extractor tests pass + 42 AI viewmodel/integration/chat/
translation tests pass (no regression) under `xcodebuild test`.
