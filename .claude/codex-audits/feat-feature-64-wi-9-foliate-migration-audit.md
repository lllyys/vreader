---
branch: feat/feature-64-wi-9-foliate-migration
threadId: 019e40dc-f938-70a3-adc5-b1454ac8afc9
rounds: 2
final_verdict: ship-as-is
date: 2026-05-19
---

# Gate-4 Implementation Audit — Feature #64 WI-9 (Foliate / AZW3-MOBI container migration)

## Scope

WI-9 of the unified cross-format highlight-action popover — the fourth (and
highest-risk) **behavioral** WI. Migrates the Foliate (AZW3/MOBI) reader
container off feature #55's `notePreviewPresenterIfAvailable` (the read-only
note preview) onto the unified popover's `unifiedHighlightPopoverPresenterIfAvailable`.

- `FoliateHighlightMutator.swift` (NEW) — the Foliate-specific `HighlightMutating`
  conformer (`@MainActor final class`), composing `HighlightPersisting` (persist)
  + `FoliateHighlightJSBridge` (live SVG-overlay repaint via the CFI-keyed
  `.foliateRequestAnnotationJS*` notification pair).
- `FoliateSpikeView.swift` (MOD) — added a `@State highlightMutator`, built in a
  new `.task`; swapped the attach to `unifiedHighlightPopoverPresenterIfAvailable`
  passing `highlightMutator` as the `mutating:` boundary.

`Feature64FoliateMigrationTests.swift` (NEW, 2 source-grep fences) +
`FoliateHighlightMutatorTests.swift` (NEW, 12 tests).

### Plan / implementation divergence (audited + accepted)

Plan §3.7 originally specified the unified popover's modifier with TWO
parameters — `coordinator: HighlightCoordinator?` + `foliateBridge:
FoliateHighlightJSBridge?`. WI-4 (shipped) made a deliberate refinement: the
modifier/router is format-agnostic over ONE `HighlightMutating` protocol
(`mutating: (any HighlightMutating)?`). TXT/MD/PDF/EPUB pass `HighlightCoordinator`
(a conformer). `FoliateHighlightJSBridge` is NOT a conformer (it only posts JS
notifications — it does not persist), so the WI-4 refinement pushed the
"compose persistence + JS bridge into one `HighlightMutating` conformer"
responsibility into WI-9. WI-9 therefore adds `FoliateHighlightMutator` — more
than the plan's literal "~60 LOC, `FoliateSpikeView.swift` only" scope, but the
direct downstream consequence of the WI-4 single-protocol refinement.

Codex round 1 explicitly assessed and **accepted** this: *"The design
divergence is sound and faithful to the plan's intent. The WI-4 refinement to a
single `HighlightMutating` boundary makes `FoliateHighlightMutator` the right
composition point; it preserves the plan's rejection of routing Foliate through
`HighlightCoordinator`"* (plan §5 R1-3/R2-2 — `HighlightCoordinator` requires a
`HighlightRenderer` Foliate lacks).

## Round 1 — Codex `019e40dc-f938-70a3-adc5-b1454ac8afc9`

**No blocking findings** — Critical / High / Medium all none. Codex verified:

- The divergence is sound and faithful to the plan's intent (see above).
- `FoliateHighlightMutator` matches `HighlightCoordinator`'s outcome mapping,
  including the R1-5 fetch discipline in code.
- `deleteHighlight` does NOT double-post `.readerHighlightRemoved` — the bridge
  owns that post.
- `updateNote` triggers no Foliate JS notification (a note is not drawn).
- The Foliate JS path stays notification-driven and escapes at the unchanged
  `FoliateHighlightRenderer` / `FoliateJSEscaper` boundary.
- `FoliateSpikeView` wiring is lifecycle-safe for the production case (the
  modifier is inert until `highlightMutator` is set; the `@State` flip reattaches
  the live popover path).
- Concurrency shape acceptable: `@MainActor` mutator, `Sendable` `HighlightPersisting`,
  expected actor hops.

Two findings:

| # | File:line | Severity | Issue | Fix |
|---|-----------|----------|-------|-----|
| F1 | `FoliateHighlightMutator.swift:102` | Low | `changeColor` repainted via `jsBridge.recolor` passing the caller's `color` argument, not the re-fetched `record.color` — weakened the "repaint from post-mutation state" invariant (equal in normal use). | Pass `record.color`. |
| F2 | `FoliateHighlightMutatorTests.swift` | Low | The tests did not directly fence the plan-critical R1-5 branches for the new mutator — write-succeeds-then-fetch-throws (`.failed`), write-succeeds-then-clean-fetch-misses (`.notFound`), delete remove-failure after a successful up-front fetch. Highest-risk WI — exactly the regressions to fence. | Add explicit R1-5 branch tests. |

## Resolution

- **F1** — `changeColor` now passes `record.color` (the re-fetched persisted
  color) to `jsBridge.recolor`; the invariant is explicit in the code comment.
- **F2** — `FoliateHighlightMutatorTests` grew 7 → 12 tests. The `FakePersistence`
  fake gained two independent knobs — `setFetchThrowsAfterMutation` (mutation
  succeeds, post-mutation `fetchHighlights` throws) and `dropFromFetch` (mutation
  writes the record but `fetchHighlights` excludes its id — a concurrent-deletion
  race). 5 new tests fence the R1-5 branches across `changeColor` / `updateNote`
  / `deleteHighlight`, including the "write landed but refetch failed → `.failed`,
  not `.notFound`" distinction and the delete-sequencing races.

## Round 2 — Codex `019e40dc-f938-70a3-adc5-b1454ac8afc9` (re-audit of the fixes)

Verdict: **"Both Low findings are resolved... No remaining open Critical/High/Medium
findings for WI-9. No blocking findings."**

## Verdict

**ship-as-is** — 2 rounds (round 1 found zero production correctness findings +
2 Lows; round 2 clean).

## Cross-test NotificationCenter pollution — fixed during implementation

The first draft of `FoliateHighlightMutatorTests` spied on
`NotificationCenter.default`. Under Swift Testing's parallel execution, one
test's `recolor`/`delete` posts leaked into another test's spy (3 tests failed
with foreign captures — the Bug #225 class). Fixed before the audit: the test
injects an isolated `NotificationCenter()` per test into the
`FoliateHighlightJSBridge` (via `FoliateHighlightMutator(... jsBridge:)`) and
spies on that same isolated center — so a test sees ONLY its own mutator's posts.

## Gate-5a verification note

WI-9 is behavioral. The Gate-5a XCUITest slice (create an AZW3/MOBI highlight,
tap it, recolor → confirm the overlay color changes; delete → confirm the
overlay clears) depends on creating a highlight first. The same pre-existing
XCUITest harness defect that blocked WI-6/7/8 (**Bug #237 / GH #986** — a
long-press in an XCUITest surfaces no "Highlight" affordance; reproduces on the
repo's own unmodified gesture-verification tests on `origin/main`, independent
of feature #64) applies. WI-9's behavioral delta is verified by the unit-test
layer: the 12 `FoliateHighlightMutatorTests` (the full `changeColor` /
`updateNote` / `deleteHighlight` outcome matrix including the R1-5 races, with a
`NotificationCenter` spy proving the recolor / delete JS-overlay pairs fire
correctly), the 2 `Feature64FoliateMigrationTests` source-grep fences, the
unchanged `FoliateHighlightJSBridge` / `FoliateSpikeViewTap` regression suites,
and a clean full app build.
