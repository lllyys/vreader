---
branch: feat/feature-69-wi-2-summary-scope-resolver
threadId: 019e3e3e-1c0f-7571-886b-f2dcfd0a5c34
rounds: 2
final_verdict: ship-as-is
date: 2026-05-19
---

# Gate-4 Implementation Audit — Feature #69 WI-2

WI-2: `SummaryScopeResolver` — the pure TOC→`ChapterBounds` resolver
behind the Chapter scope of the AI Summarize selector.

## Files audited

- `vreader/Services/AI/SummaryScopeResolver.swift` (new)
- `vreaderTests/Services/AI/SummaryScopeResolverTests.swift` (new)

## Round 1 — findings

| file:line | severity | issue | resolution |
|---|---|---|---|
| `SummaryScopeResolver.swift:56` | Medium | The resolver returned `nil` when `totalTextLengthUTF16 <= 0`, but plan §2.4 reserves `nil` for "no usable chapter offsets" only — so Chapter scope degraded to Section in a case the plan says should still resolve. | **Fixed** — removed the total-length check from the `nil` gate. Non-final chapters resolve from the next chapter's start (unaffected by the total); the final chapter's end is the total, and `ChapterBounds`' clamping init collapses a degenerate total to an empty final-chapter span. Header + doc comment updated. |
| `SummaryScopeResolverTests.swift:201` | Medium | `zeroTotalLengthReturnsNil` locked in the contract drift. | **Fixed** — replaced with `zeroTotalLengthStillResolvesFromAnchoredTOC` (zero total + anchored TOC → non-nil `ChapterBounds(3000,3000)`) and `shortTotalLengthResolvesNonFinalChapterNormally` (short total leaves non-final chapters unaffected). |
| `SummaryScopeResolverTests.swift:212` | Low | The "CJK / surrogate-pair" test used hard-coded numbers + CJK titles — no real surrogate-pair exercise; false confidence about UTF-16. | **Fixed** — replaced with `surrogatePairOffsetsLandInExpectedChapter`: builds a real string of `😀` emoji (2-UTF-16-unit supplementary-plane pairs), derives every offset from `.utf16.count` on actual substrings, proves the locator lands in the expected span, sanity-asserts the offsets are even. |

Clean in round 1: pre-first-entry → preamble span matches the plan,
exact-boundary behavior correct, mixed anchored/unanchored TOC handling
correct, the deliberate duplication of `TOCChapterProgress`'s loop is
justified for a bounds-returning resolver (plan §3 rejected extending
`TOCChapterProgress`), file size / concurrency / style fine.

## Round 2 — verification

Codex re-reviewed both files: "No new Critical/High/Medium issues. The
nil contract now matches plan §2.4 … A zero or short
`totalTextLengthUTF16` no longer degrades to `nil` … The tests now pin
that behavior correctly … The surrogate-pair test is now materially
better as well."

## Verdict

**ship-as-is.** Zero open Critical/High/Medium findings after 2
rounds. 17 tests pass (`xcodebuild test
-only-testing:vreaderTests/SummaryScopeResolverTests`).
