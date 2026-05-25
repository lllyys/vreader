---
branch: feat/feature-71-wi-1-spine-window
threadId: 019e5fac-f489-7432-aeee-df81e22bacb2
rounds: 2
final_verdict: ship-as-is
date: 2026-05-25
---

# Gate-4 implementation audit — Feature #71 WI-1 (`EPUBSpineWindow`)

Foundational first WI of feature #71 (EPUB scroll-mode continuous cross-chapter scroll). Pure value type modeling the materialized chapter window for continuous scroll — integer-range arithmetic, no UIKit, no I/O.

Files audited:
- `vreader/Views/Reader/EPUBSpineWindow.swift` (new)
- `vreaderTests/Views/Reader/EPUBSpineWindowTests.swift` (new, 20 Swift Testing cases, all passing)
- `vreader.xcodeproj/project.pbxproj` (xcodegen-regenerated registration)

## Round 1 findings (Codex thread `019e5fac`)

No Critical/High/Medium. 3 Low:

| # | file:line | severity | issue | resolution |
|---|---|---|---|---|
| 1 | EPUBSpineWindow.swift `evictFarFromAnchor` | Low | Final `else { newLo += 1 }` unreachable under the invariant + `cap >= 1`; made the termination proof harder, left misleading dead code in the most delicate function | **Fixed** — collapsed to a true two-branch loop (`if newHi > anchor, distanceToHi >= distanceToLo \|\| newLo >= anchor { newHi -= 1 } else { newLo += 1 }`) with a comment proving each iteration shrinks the span by exactly one and never drops the anchor |
| 2 | EPUBSpineWindowTests.swift | Low | Tie-break behind `distanceToHi >= distanceToLo` not pinned — a `>=`→`>` regression would still pass (maxSpan==1 collapses regardless) | **Fixed** — added `symmetric window evicting by one trims hi` (anchor 4, 3...5, maxSpan 2 → 3...4); a `>` regression would produce 4...5 and fail |
| 3 | EPUBSpineWindowTests.swift | Low | Synthesized `Equatable` includes private `spineCount`; semantics undocumented/unpinned | **Fixed** — added `windows with the same visible range but different spineCount are unequal` pinning full-state equality (spineCount is load-bearing — it drives future `canExtendForward`/edge-clamp behavior) |

## Round 2 (verification)

All 3 fixes confirmed by Codex. Termination + invariant preservation re-verified for anchor at lo edge, hi edge, middle, and maxSpan==1. **Still-open findings: none.**

## Verdict

**ship-as-is.** No correctness bug against the WI-1 contract; the eviction loop preserves `0 <= lo <= anchor <= hi < spineCount` and terminates for all anchor positions. 20 unit tests green. Author/auditor separation satisfied (Codex is a separate process).
