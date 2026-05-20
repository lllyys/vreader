---
branch: feat/feature-64-wi-8-epub-migration
threadId: 019e40cf-b860-78f2-b398-c0bf7a292ecd
rounds: 2
final_verdict: ship-as-is
date: 2026-05-19
---

# Gate-4 Implementation Audit — Feature #64 WI-8 (EPUB container migration)

## Scope

WI-8 of the unified cross-format highlight-action popover — the third
**behavioral** WI. Migrates the EPUB reader container off feature #55's
`notePreviewPresenterIfAvailable` (the read-only note preview) onto the unified
popover's `unifiedHighlightPopoverPresenterIfAvailable`.

- `EPUBReaderContainerView.swift` (MOD) — swapped the attach to
  `unifiedHighlightPopoverPresenterIfAvailable` passing `highlightCoordinator`
  as the `mutating:` boundary.

WI-8 is the simplest of the container migrations: a pure one-attach swap. The
EPUB highlight tap arrives from a JS `highlightTapHandler` channel;
`EPUBWebViewBridgeCoordinator.handleHighlightTapMessage` posts
`.readerHighlightTapped` — the unified popover's trigger — and that path is
unchanged by WI-8. Unlike WI-6 (TXT/MD) and WI-7 (PDF), there is no feature #53
long-press `UIMenu` wiring to strip: feature #55 already removed it for the web
host, so `EPUBWebViewBridge` never carried `highlightActionPresenter` /
`onHighlightTapAction`.

`Feature64EPUBMigrationTests.swift` (NEW) — 2 source-grep tests fencing the
migration (container attaches `unifiedHighlightPopoverPresenterIfAvailable` with
`mutating: highlightCoordinator`, not `notePreviewPresenterIfAvailable`).

The feature #55 types are NOT deleted in WI-8 — plan §3.9 defers that to WI-10.
`Feature55WebHostWiringTests.swift` was intentionally NOT deleted: it tests
`NotePreviewPresenter`, a live type the still-un-migrated Foliate container
(WI-9) depends on; it retires in WI-10 with the #55 family.

## Round 1 — Codex `019e40cf-b860-78f2-b398-c0bf7a292ecd`

**No blocking findings.** Codex confirmed each category clean:

- **Correctness vs plan** — WI-8 implements §3.8 exactly: the attach swapped
  from `notePreviewPresenterIfAvailable` to
  `unifiedHighlightPopoverPresenterIfAvailable`, and `mutating: highlightCoordinator`
  is the right EPUB mutation boundary (`HighlightCoordinator` is the production
  `HighlightMutating` conformer).
- **Trigger path unchanged** — `EPUBWebViewBridgeCoordinator.handleHighlightTapMessage`
  still posts `.readerHighlightTapped`, and the new modifier still observes it.
- **`highlightCoordinator` lifecycle** — safe. It is populated in `.task`; the
  attach helper is inert when `mutating` is nil; the `@State` flip makes SwiftUI
  recompute `body` and install the live modifier — the same late-assignment
  pattern WI-6 used for TXT/MD.
- **Concurrency / actor safety** — no new `@MainActor` / Sendable hazards.
- **EPUB chapter handling** — omitting `chapter:` is correct; in this presenter
  path `chapter` is only display metadata, and EPUB repaint scoping lives inside
  `HighlightCoordinator.changeColor` via `ChapterScopedHighlightRenderer` /
  `EPUBHighlightRenderer.currentChapterHref`, not via the modifier argument.
- **Test coverage** — adequate for WI-8's narrow scope; keeping
  `Feature55WebHostWiringTests` until WI-10 is the right call (Foliate still
  depends on the #55 presenter).

One finding:

| # | File:line | Severity | Issue | Fix |
|---|-----------|----------|-------|-----|
| F1 | `EPUBReaderContainerView.swift:492` | Low | Stale feature #55 comment drift — the inline comment in `readerContent(...)` still said the EPUB highlight tap is re-homed to `NotePreviewModifier`, but WI-8 changed the attach to `HighlightPopoverModifier`. Code correct; comment misleading (rule-22 violation). | Rewrite the comment for the WI-8 behavior. |

## Resolution

- **F1** — rewrote the `readerContent(...)` comment to describe the current
  feature #64 WI-8 behavior: the EPUB highlight tap still posts
  `.readerHighlightTapped` (JS `highlightTapHandler` →
  `EPUBWebViewBridgeCoordinator.handleHighlightTapMessage`), now observed by the
  unified popover (`HighlightPopoverModifier`); and that there is no
  EPUB-specific action presenter to wire (the web host never carried feature
  #53's long-press inline menu).

## Round 2 — Codex `019e40cf-b860-78f2-b398-c0bf7a292ecd` (re-audit of the fix)

Verdict: **"The Low finding is resolved... There are no remaining open
Critical/High/Medium findings for WI-8. No blocking findings."**

## Verdict

**ship-as-is** — 2 rounds (round 1 found zero production findings + 1 Low
comment-sync; round 2 clean).

## Gate-5a verification note

WI-8 is behavioral. The Gate-5a XCUITest slice (create an EPUB highlight, tap
it, assert the unified popover) depends on creating a highlight first via the
in-app selection flow — blocked by the same pre-existing harness defect that
blocked WI-6/WI-7 (**Bug #237 / GH #986** — a long-press in an XCUITest
surfaces no "Highlight" affordance; reproduces on the repo's own unmodified
gesture-verification tests on `origin/main`, independent of feature #64). WI-8's
behavioral delta is verified by the unit-test layer: the 2
`Feature64EPUBMigrationTests` source-grep fences, plus the unchanged EPUB
highlight regression suites (`EPUBHighlightTapBridge`, `EPUBHighlightActions`,
`EPUBHighlightBridge`, `Feature55WebHostWiringTests` — 38 tests green) and a
clean full app build.
