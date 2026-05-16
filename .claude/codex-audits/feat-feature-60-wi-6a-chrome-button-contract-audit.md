---
branch: feat/feature-60-wi-6a-chrome-button-contract
threadId: 019e2e46-ce51-75a3-abf4-1a17fdca5049
rounds: 2
final_verdict: ship-as-is
date: 2026-05-16
---

# Codex Audit — Feature #60 WI-6a (foundational button-slot enum contract)

Scope: declare `ReaderTopChromeSlot` + `ReaderBottomChromeButton`
enums consumed by the future WI-6b chrome view restructure and by
test harnesses. No UI change. WI-6b is `BLOCKED: needs-design (#760)`
because the committed design bundle leaves in-Reader Search unreachable.

Files audited:
- `vreader/Views/Reader/ReaderChromeButton.swift` (NEW, ~63 LOC)
- `vreaderTests/Views/Reader/ReaderChromeButtonContractTests.swift` (NEW, 7 tests)
- `docs/features.md` (row #60 BLOCKED note + plan-version reference)
- `dev-docs/plans/20260515-feature-60-visual-identity-v2.md` (revision history v4)

## Round 1 findings

| File:Line | Severity | Issue | Fix |
|---|---|---|---|
| `dev-docs/plans/20260515-feature-60-visual-identity-v2.md:110` | Medium | Plan text described the bottom chrome as `TOC / Display / Highlights / AI` but the committed design JSX and the WI-6a enum contract are `Contents / Notes / Display / AI` — drift would weaken WI-6b's source-of-truth. | Updated plan's "Modified views" section to match the design bundle and WI-6a enums exactly: `Contents / Notes / Display / AI`, with note that `Notes` maps to the highlights/annotations panel and AI is the accent slot. |
| `dev-docs/plans/20260515-feature-60-visual-identity-v2.md:294` | Medium | WI-6 test catalogue pinned stale `TOC / Display / Highlights / AI` wording, conflicting with the enum + design. | Rewrote test-plan wording to match the design + enum contract (`Contents / Notes / Display / AI`); added an explicit WI-6a subsection documenting the foundational contract test set; clarified Gate 5a device verification applies to WI-6b only (WI-6a has no user-visible delta). |
| `docs/features.md:101` | Low | Row pointed to plan as `v3` but the WI-6a/6b split is a v4 revision — internally inconsistent tracker note. | Updated row to reference plan `v4` and explain v4 introduced the WI-6a/6b split + needs-design #760. |

No code-level findings in `ReaderChromeButton.swift` or
`ReaderChromeButtonContractTests.swift`. Codex confirmed WI-6a
delivers the promised foundational contract: slot/button enums,
stable accessibility IDs, order pinned to the design bundle, and
the accent-slot predicate for `.ai`. Identifier search found no
new collisions — `readerBackButton` / `readerBookmarkButton` /
`readerAIButton` are deliberately the same strings the existing
`ReaderChromeBar.swift:38-60` already uses, preserving continuity
for XCUITest harnesses and verify-cron snapshots.

## Round 2 findings

No findings. Codex Round 2 verdict (verbatim):

> All 3 Round 1 findings are cleanly resolved... On drift: I did
> not find any remaining stale TOC / Highlights wording in the
> chrome-bar context. Remaining TOC / Highlights references in
> the plan are in legitimate non-chrome contexts, like sheet
> re-skins or file paths such as TOC*.swift, so they are not
> regressions. WI-6a is ready to ship.

## WI-6/6a/6b split judgement

Codex explicitly affirmed the split was the right call:

> WI-6a is a no-UI, design-safe foundational slice; WI-6b should
> stay blocked until Search placement is designed, because
> otherwise the redesign would regress an existing reader
> affordance.

## Summary

Ship-as-is. Foundational button-slot enum contract pinned by
7 contract tests; no UI change; WI-6b correctly blocked on GH
#760 (needs-design); plan v4 documents the split.
