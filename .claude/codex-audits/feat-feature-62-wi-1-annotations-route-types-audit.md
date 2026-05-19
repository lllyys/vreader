---
branch: feat/feature-62-wi-1-annotations-route-types
threadId: 019e4055-0bfd-7412-b3e5-6a1b73752a7e
rounds: 2
final_verdict: ship-as-is
date: 2026-05-19
---

# Gate 4 — Implementation Audit — feature #62 WI-1

Pure routing/segment/stream types for the annotations-panel split.

## Files audited

- `vreader/Views/Reader/Annotations/AnnotationsSheetRoute.swift` (new)
- `vreader/Views/Reader/Annotations/AnnotationStreamItem.swift` (new)
- `vreader/Views/Reader/Annotations/AnnotationStreamBuilder.swift` (new)
- `vreaderTests/Views/Reader/Annotations/AnnotationsSheetRouteTests.swift` (new)
- `vreaderTests/Views/Reader/Annotations/AnnotationStreamBuilderTests.swift` (new)

## Round 1 — findings

| # | file:line | Severity | Issue | Resolution |
|---|---|---|---|---|
| 1 | AnnotationStreamBuilderTests.swift `countsLargeSet` | Medium | Plan §5 large-set edge requires the `.all` stream to also prove 1000 items; the test only checked `counts`, so a `stream()` cap bug would pass unnoticed. | **Fixed** — `countsLargeSet` renamed "counts + stream: large set"; now asserts `stream(.all).count == 1000`, `stream(.highlights).count == 500`, `stream(.notes).count == 750`. |
| 2 | AnnotationStreamBuilderTests.swift tie-break test | Medium | The tie-break test only compared two identical calls — an implementation preserving input order on ties would still pass; it did not pin "order by id". | **Fixed** — now seeds 3 records sharing one timestamp with fixed UUIDs A/B/C, asserts `[idA,idB,idC]`, and re-runs with reversed input arrays asserting the same — proving id-driven, not source-order. |
| 3 | AnnotationsSheetRouteTests.swift route helpers | Low | The route-helper non-route branches (`.display`/`.ai`, the four non-export More-menu effects) were implemented coherently but unpinned by tests — future branch drift would go uncaught. | **Fixed** — added `displayAndAIButtonsYieldNil` + `nonExportMoreMenuEffectsYieldNil` negative tests. |
| 4 | AnnotationStreamBuilder.swift comparator | Low | The `createdAt DESC → id` comparator was not a total order in the pathological case where a highlight + standalone share both timestamp and UUID. | **Fixed** — added `AnnotationStreamItem.kindRank` (highlight=0, standalone=1); comparator now tie-breaks `createdAt DESC → id → kindRank`. `streamItemKindRank` test pins it. |

No Critical or High findings.

## Round 2 — verification

Codex re-read the four fixes against the worktree files: all four confirmed
closed. "No Critical/High/Medium findings remain." Full-payload route ids,
exact #860 count math, correct `Sendable` value types, no dead branches /
import issues, all files under the 300-line cap.

## Verdict

**ship-as-is.** Two audit rounds, zero open Critical/High/Medium. 36 tests
pass under `xcodebuild test -only-testing:vreaderTests`. Within the rule-47
3-round cap.
