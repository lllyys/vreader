---
branch: feat/feature-62-wi-2-annotations-empty-state
threadId: 019e40a1-b13c-71a2-895f-df1f74878a7d
rounds: 2
final_verdict: ship-as-is
date: 2026-05-19
---

# Gate 4 — Implementation Audit — feature #62 WI-2

The reusable annotations empty-state component + the three SVG art views.

## Files audited

- `vreader/Views/Reader/Annotations/AnnotationsEmptyStateArt.swift` (new)
- `vreader/Views/Reader/Annotations/AnnotationsEmptyStateView.swift` (new)
- `vreaderTests/Views/Reader/Annotations/AnnotationsEmptyStateArtTests.swift` (new)
- `vreaderTests/Views/Reader/Annotations/AnnotationsEmptyStateViewTests.swift` (new)

## Round 1 — findings

| # | file:line | Severity | Issue | Resolution |
|---|---|---|---|---|
| 1 | AnnotationsEmptyStateView.swift title | Medium | Title used `.system(design: .serif)` instead of the repo's `ReaderTypography.body(for: .sourceSerif4, ...)` path — a design-fidelity miss vs the design's explicit "Source Serif 4" (rule 51). | **Fixed** — title now uses `Font(ReaderTypography.body(for: .sourceSerif4, size: 18))` + `.fontWeight(.semibold)`, the same path `ReaderSheetChrome` (17pt) and `ReaderSettingsPanel` (20pt) use. |
| 2 | AnnotationsEmptyStateViewTests | Low | The suite did not assert `title`/`body` wiring; `accessibilityIdentifierRetained` only re-read the stored arg. | **Partially fixed** — added `titleAndBodyWired` (asserts `title`/`body_` carry the init args). The accessibility-modifier-application half is accepted — see Round 2. |
| 3 | AnnotationsEmptyStateView.swift `invokeCTAForTesting` | Low | The hook bypassed the `cta &&` guard — would fire with `onCTA` non-nil but `ctaLabel` nil, when no button renders. | **Fixed** — hook now `guard hasCTA else { return }`; `invokeCTANoOpsWithoutLabel` test pins it. |

No Critical or High findings.

## Round 2 — verification + one accepted Low

Codex re-read the fixes: Medium **complete** (Source Serif 4 path), CTA-hook
Low **complete** (faithful `hasCTA`-gated proxy), title/body assertion
**complete**.

**One Low accepted with rationale:** `accessibilityIdentifierRetained` re-reads
the stored `accessibilityIdentifier` property but does not prove the
`.accessibilityIdentifier(...)` modifier is applied in `body` — if that
modifier were removed, the test would still pass.

- **Why accepted, not fixed**: asserting modifier application from a unit
  test requires a view-inspection library (e.g. ViewInspector). The project
  has **no third-party Swift packages** (`.claude/rules/50-codebase-conventions.md`
  §10) — adding one for this single assertion is out of scope for a
  foundational WI. The codebase precedent for view-construction tests is
  `_ = view.body` + storing identifiers as configurable inputs (the
  `BookDetailsSheet` / `SheetReSkinSnapshotTests` pattern), which this WI
  follows.
- **Where the gap closes**: the plan §5 already specifies a WI-5 XCUITest
  (`Feature62AnnotationsSplitVerificationTests`) that resolves each
  `*EmptyState` accessibility identifier end-to-end on the simulator —
  that is the real assertion the modifier is applied. WI-2's job is the
  component definition; WI-5 verifies it in situ.

## Verdict

**ship-as-is.** Two audit rounds. Round 1: 1 Medium + 2 Low. Round 2: Medium
+ both addressable Lows fixed; one Low accepted with rationale (no
view-inspection library in the project; the modifier-application assertion
lands in WI-5's XCUITest per plan §5). Zero open Critical/High/Medium. 12
tests pass.
