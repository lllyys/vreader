---
branch: feat/feature-69-wi-1-summary-scope-types
threadId: 019e3e34-c37f-74a3-abb3-8d73743d093e
rounds: 2
final_verdict: ship-as-is
date: 2026-05-19
---

# Gate-4 Implementation Audit — Feature #69 WI-1

WI-1: `SummaryScope` enum + `ChapterBounds` struct — pure value types
for the AI Summarize scope selector.

## Files audited

- `vreader/Services/AI/SummaryScope.swift` (new)
- `vreader/Services/AI/ChapterBounds.swift` (new)
- `vreaderTests/Services/AI/SummaryScopeTests.swift` (new)
- `vreaderTests/Services/AI/ChapterBoundsTests.swift` (new)

## Round 1 — findings

| file:line | severity | issue | resolution |
|---|---|---|---|
| `ChapterBounds.swift:19` | Medium | `ChapterBounds` documented a half-open UTF-16 span but the synthesized memberwise init allowed impossible values (negative offsets, `end < start`). Later WIs could construct invalid bounds. | **Fixed** — replaced the synthesized init with an explicit init that clamps: `startUTF16` raised to `0` if negative, `endUTF16` raised to `startUTF16` if smaller. Chose clamping over a failable init so WI-2/WI-3 callers don't carry an optional; an invalid span is unrepresentable. Header + doc comment updated. |
| `ChapterBoundsTests.swift:13` | Low | Tests pinned only synthesized storage/equality, never the invalid-input policy. | **Fixed** — added `negativeStartIsClampedToZero`, `endBelowStartIsRaisedToStart`, `negativeStartWithNegativeEndCollapsesToZero`, and `invariantHoldsAfterClamping` (parameterized matrix asserting `start >= 0 && end >= start`). |

`SummaryScope` was clean in round 1 — three cases correct, `allCases`
order matches the design chip order, `displayName` strings match the
plan, appropriate `Sendable`, no unnecessary `@MainActor`, under the
file-size limit, no duplicate/dead code.

## Round 2 — verification

Codex re-reviewed `ChapterBounds.swift` + `ChapterBoundsTests.swift`:
"No new Critical/High/Medium issues. The invariant is now enforced …
every constructed value satisfies the documented half-open-span
contract. Zero-length spans remain representable … The tests now pin
that behavior adequately … That closes the earlier gap."

## Verdict

**ship-as-is.** Zero open Critical/High/Medium findings after 2
rounds. 21 tests pass (`xcodebuild test -only-testing:vreaderTests/SummaryScopeTests
-only-testing:vreaderTests/ChapterBoundsTests`).
