---
branch: feat/feature-60-wi-8-library-card-tokens
threadId: 019e2ff2-a9b2-7e93-ab2f-92e23f4033bd
rounds: 3
final_verdict: ship-as-is
date: 2026-05-16
---

# Codex Audit — Feature #60 WI-8 (Library card / row visual tokens)

Gate 4 implementation audit for feature #60 (visual identity v2),
work item WI-8. Author: implementing Claude Code session. Auditor:
Codex MCP (`gpt-5`-class), independent process — author/auditor
separation per rule 48.

WI-8 ships the Library grid-card (`BookCardView`) and list-row
(`BookRowView`) re-skin: design typography / palette / cover
treatment, plus the per-book reading-progress UI.

## Round 1 — audit of the WI-8 Gate 3 deliverable (commit `79d8ee2`)

| # | file | severity | issue | resolution |
|---|------|----------|-------|------------|
| 1 | `BookCardView.swift` | High | Omits the design `GridView`'s in-cover progress strip + finished checkmark — the card shipped typography/palette/cover only. | **Fixed** — fix round added `progressStrip` + `finishedBadge` overlays driven by `LibraryBookItem.readingProgressState`. |
| 2 | `BookRowView.swift` | High | Omits the design `ListView`'s progress metadata span (`X% · last-read` / `Finished`) and the trailing progress ring. | **Fixed** — fix round added the `metadataLine` progress span + the `progressRing` (`LibraryProgressRing`). |
| 3 | plan v11 note | Medium | The progress-UI deferral was avoidable: it was recorded as "data-model-blocked", but `Locator.totalProgression` (`Double?`) already carries the per-book fraction. | **Fixed** — fix round added `progressFraction: Double?` to `LibraryBookItem` and projects it in `PersistenceActor+Library.fetchAllLibraryBooks()` from `book.readingPosition?.locator.totalProgression`. Plan v12 records the reversal. |
| 4 | `BookCoverArtView.swift` | Medium | The flat format-colour fallback is not the design's generative cover. | **Accepted with rationale** — generative covers are WI-10 scope (plan's `GenerativeCoverViewStyleTests`). The flat fallback is the pre-existing placeholder carried forward, not a WI-8 invention; WI-10 replaces it. |
| 5 | `LibraryCardTokens.swift` | Medium | `listCardBackground`, `listRowDivider`, `listCardCornerRadius` are referenced only by tests — no production consumer. | **Accepted with rationale** — these are the list-*container* tokens consumed by WI-9's Library-container re-skin. The file header now documents the WI-9 dependency. Splitting the shared `vreader-library.jsx` spec across two PRs would be worse churn. `accent` is now a live production token (the ring's swept arc). |
| 6 | `BookCardViewVisualTests.swift` / `BookRowViewVisualTests.swift` | Low | Tests are largely tautological — they pin design constants and would not catch real visual regressions. | **Accepted with rationale** — the token-pinning tests are intentional design tripwires (a token edit fails them). The fix round adds genuinely behavioral tests: `LibraryBookItemProgressStateTests` (10 boundary cases), `ReadingTimeFormatterRelativeTests` (10 buckets), and progress-state / metadata-text tests. Render-level pixel geometry is verified at Gate 5; see Round 2 #2. |

## Round 2 — audit of the fix round

| # | file | severity | issue | resolution |
|---|------|----------|-------|------------|
| 1 | `BookCardView.swift` `progressStrip` | Medium | Concern that the in-cover strip's 6pt horizontal inset relied on a `.padding` applied *outside* a `GeometryReader`, which is fragile to modifier-order edits. | **Fixed** — `progressStrip` restructured: the `GeometryReader` is now the full-cover overlay content, `trackWidth = max(0, geo.size.width - inset * 2)` is computed explicitly in the measured space, and the strip is placed with `.position`. The inset no longer depends on proposal order. |
| 2 | `BookCardViewVisualTests.swift` | Low | New tests assert derived state/text, not render-level overlay geometry; they would not catch a strip-inset or badge-placement regression. | **Accepted with rationale** — the WI-8 plan specifies "snapshot-free visual assertions"; `.claude/rules/10-tdd.md` directs SwiftUI view tests to test behaviour, not pixel rendering. Strip/badge/ring geometry is verified end-to-end at Gate 5 device verification. Adding `ImageRenderer` geometry assertions would contradict both the plan and the TDD rule. |

## Round 3 — verification

Codex confirmed the restructured `progressStrip` resolves the Round-2
Medium and that the Low render-test deferral is a valid scoped Gate-4
decision (consistent with the plan and rule 10-tdd).

**Open findings: none.** No open Critical, High, or Medium.

## Summary verdict

`ship-as-is`. The Round-1 High gap (missing per-book progress UI on
the card and row) is fully closed; the data path is sound end-to-end
(`Locator.totalProgression` → `PersistenceActor+Library` →
`LibraryBookItem.progressFraction` → `readingProgressState` → card /
row). No Swift 6 concurrency or `@MainActor` issues; all touched
production files are under the 300-line guideline. The two
`accepted-with-rationale` items (WI-10 generative cover; WI-9
list-container tokens) are scope boundaries, not defects. The one Low
deferral (render-backed visual assertions) is consistent with the
WI-8 plan and `.claude/rules/10-tdd.md`.
