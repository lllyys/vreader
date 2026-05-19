---
branch: feat/feature-64-wi-3-coordinator-mutations
threadId: 019e4069-65e1-7701-b5e8-f6cdc18d0307
rounds: 2
final_verdict: ship-as-is
date: 2026-05-19
---

# Gate-4 Implementation Audit — Feature #64 WI-3 (HighlightCoordinator color/note mutations)

## Scope

WI-3 of the unified cross-format highlight-action popover. Adds the two highlight mutations the popover drives:

- `vreader/Views/Reader/HighlightCoordinator.swift` (MOD) — `changeColor(highlightID:to:)` + `updateNote(highlightID:note:)`, both returning the typed `HighlightMutationOutcome`. Plus the static `normalizedNote(_:)`. Existing methods untouched.
- `vreader/Views/Reader/HighlightRenderer.swift` (MOD) — new refinement protocol `ChapterScopedHighlightRenderer: HighlightRenderer` with `var currentChapterHref: String? { get }`.
- `vreader/Views/Reader/EPUBHighlightRenderer.swift` (MOD) — conforms `EPUBHighlightRenderer` to `ChapterScopedHighlightRenderer`.
- `vreaderTests/Views/Reader/HighlightCoordinatorMutationTests.swift` (NEW) — 15 tests.

## Round 1 — Codex `019e4069-65e1-7701-b5e8-f6cdc18d0307`

Three findings — all the same root cause (the post-mutation re-fetch swallowing errors):

| # | File:line | Severity | Issue | Fix |
|---|-----------|----------|-------|-----|
| F1 | `HighlightCoordinator.swift:159` (changeColor) + `:188` (updateNote) | **Medium** | The post-mutation `refetchHighlight(_:)` helper used `try?` over `fetchHighlights`, so a *generic fetch failure* after a *successful write* returned `nil` → mapped to `.notFound`. Violates R1-5: a read failure after a successful write must be `.failed`, not "record deleted, dismiss the popover". | Fetch explicitly in a do/catch; map `throw` → `.failed`; map only "fetched OK but no matching id" → `.notFound`. |
| F2 | `HighlightCoordinator.swift:164` (changeColor) | **Medium** | `changeColor` repainted via `restoreAll(forHref:)`, which swallows its *own* `fetchHighlights` failure and no-ops — so `changeColor` could return `.success(record)` while the page repaint silently never happened. Breaks §3.4's "persist, then repaint" contract. | Repaint from the already-fetched `records` directly via `renderer.restore(records:forHref:using:)` — the re-fetch already carries the new color. |
| F3 | `HighlightCoordinatorMutationTests.swift:171` | Low | The mock could not fail `fetchHighlights`, so the F1/F2 paths were untested. | Add a mock mode where `fetchHighlights` throws after a successful mutation; assert `.failed` + no repaint. |

The auditor confirmed everything else clean in round 1: `ChapterScopedHighlightRenderer` is the right abstraction (narrow, read-only, exposes existing renderer state, makes the href-capture fix testable without binding the coordinator to `EPUBHighlightRenderer`); the EPUB race test is meaningful and deterministic (mutates `currentHref` during the awaited persistence call, asserts the value actually threaded into `restore(...forHref:)`, proving pre-await capture).

## Resolution

- **F1 + F2** — removed the `refetchHighlight(_:)` helper. Both `changeColor` and `updateNote` now fetch explicitly inside a do/catch: a `fetchHighlights` throw → `.failed`; only a clean fetch with no matching id → `.notFound`. `changeColor` repaints from the already-fetched `records` directly via `renderer.restore(records:forHref: capturedHref, using: nil)` — the repaint is only reached on a successful fetch, so a `.success` return always implies a repaint was driven.
- **F3** — added a `fetchThrowsAfterMutation` mock mode + 4 new tests: `changeColor_refetchThrowsAfterSuccess_returnsFailed` (asserts `.failed` + `renderer.restoreCalls == 0`), `changeColor_recordGoneOnCleanRefetch_returnsNotFound`, `updateNote_refetchThrowsAfterSuccess_returnsFailed`, `updateNote_recordGoneOnCleanRefetch_returnsNotFound`.

WI-3 test gate re-ran: 23 tests pass (15 mutation + 8 coordinator).

## Round 2 — Codex `019e4069-65e1-7701-b5e8-f6cdc18d0307` (re-audit of the fixes)

Verdict: **"No findings. The three prior findings are resolved."** Codex verified the explicit do/catch fetch with correct `.failed`/`.notFound` mapping, the direct repaint from fetched records, and the 4 new failure-split tests. **No remaining open Critical/High/Medium findings.**

## Verdict

**ship-as-is** — 2 rounds (round 1 caught the re-fetch error-swallowing bug, fixed by an explicit do/catch + a direct repaint; round 2 clean).
