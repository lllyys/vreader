---
branch: feat/feature-64-wi-7-pdf-migration
threadId: 019e40c4-1d94-7c02-86c0-83c9861d5a5a
rounds: 2
final_verdict: ship-as-is
date: 2026-05-19
---

# Gate-4 Implementation Audit — Feature #64 WI-7 (PDF container migration)

## Scope

WI-7 of the unified cross-format highlight-action popover — the second
**behavioral** WI. Migrates the PDF reader container off feature #55's
`notePreviewPresenterIfAvailable` (the read-only note preview) onto the unified
popover's `unifiedHighlightPopoverPresenterIfAvailable`, and removes the
feature #53 highlight long-press `UIMenu` from `PDFViewBridge`. Mirrors WI-6
(TXT/MD), one PR later.

- `PDFReaderContainerView.swift` (MOD) — swapped the attach to
  `unifiedHighlightPopoverPresenterIfAvailable` passing `highlightCoordinator`
  as the `mutating:` boundary; removed the `highlightActionPresenter:` /
  `onHighlightTapAction:` args from the `PDFViewBridge(...)` call.
- `PDFViewBridge.swift` (MOD) — removed the `highlightActionPresenter` /
  `onHighlightTapAction` stored properties (struct + Coordinator),
  `handleHighlightLongPress`, the named highlight `UILongPressGestureRecognizer`
  registration, and the now-dead `gestureRecognizerShouldBegin` (it only gated
  that long-press). `shouldRecognizeSimultaneouslyWith` is kept but simplified
  to a plain `true` — the chrome-toggle tap is now the only recognizer the
  coordinator owns (bug #32), so the `TXTBridgeShared` name indirection is no
  longer needed.
- The `handleTap` → `resolveHighlightTapEvent` → `.readerHighlightTapped` tap
  path is KEPT — the unified popover's trigger.
- `PDFHighlightLongPressGateTests.swift` (DEL) — guarded the now-removed PDF
  long-press gate; its own header (written in WI-6) documented WI-7 retires it.
- `Feature64PDFMigrationTests.swift` (NEW) — source-grep fences for the
  container + bridge migration.

The feature #53/#55 types are NOT deleted in WI-7 — plan §3.9 defers that to
WI-10. `TXTBridgeShared.highlightLongPressName` / `simultaneousRecognitionAllowed`
are now orphaned (PDF was their last production caller) — flagged for the WI-10
sweep, out of WI-7's planned 2-file surface.

## Round 1 — Codex `019e40c4-1d94-7c02-86c0-83c9861d5a5a`

**No blocking findings.** Codex confirmed each category clean:

- **Correctness vs plan** — `PDFReaderContainerView` attaches
  `unifiedHighlightPopoverPresenterIfAvailable(modelContainer:, bookFingerprintKey:, mutating: highlightCoordinator, theme:)`
  exactly as scoped; `PDFViewBridge` has the long-press `UIMenu` machinery
  fully removed and the `.readerHighlightTapped` tap path preserved.
- **Gesture-recognizer correctness** — after removing the named highlight
  long-press recognizer, `gestureRecognizerShouldBegin` is genuinely dead; the
  surviving owned recognizer is the chrome-toggle tap, and
  `shouldRecognizeSimultaneouslyWith` returning `true` is the correct bug-#32
  behavior.
- **Concurrency / `@MainActor`** — the diff removes async callback plumbing
  rather than adding cross-actor edges; remaining coordinator state stays
  `@MainActor`, the `nonisolated` delegate returns a constant.
- **Dead code / orphaned references** — repo grep found no live references to
  the removed PDF symbols; the leftover `TXTBridgeShared` helpers +
  `HighlightCoordinator.handleTapAction` are dead-but-benign and explicitly
  deferred to WI-10 — not a build or runtime risk for this WI.
- **Test deletion** — deleting `PDFHighlightLongPressGateTests` is correct; its
  subject code was removed, no still-live coverage gap.
- **VReader compliance** — comment headers in sync; the two touched files are
  over the ~300-line guideline (`PDFReaderContainerView.swift` 306,
  `PDFViewBridge.swift` 480) but that is pre-existing structural debt, not a
  WI-7 regression.

One test-coverage finding:

| # | File:line | Severity | Issue | Fix |
|---|-----------|----------|-------|-----|
| F1 | `Feature64PDFMigrationTests.swift:61` | Low | The migration fence did not assert the plan-critical `mutating: highlightCoordinator` wiring — a regression to `mutating: nil` would still pass (the test only checks the helper name exists). | Add a source assertion for `mutating: highlightCoordinator`. |

## Resolution

- **F1** — added a third `#expect` to `pdfAttachesUnifiedHighlightPopoverPresenter`
  asserting the PDF container source contains `mutating: highlightCoordinator`,
  pinning the `HighlightMutating` boundary. This matches the WI-6 precedent
  (`Feature64TXTMDMigrationTests`'s MD guards already pin the wiring). All 4
  tests in `Feature64PDFMigrationTests` pass.

## Round 2 — Codex `019e40c4-1d94-7c02-86c0-83c9861d5a5a` (re-audit of the fix)

Verdict: **"The Low is resolved... There are no remaining open Critical, High,
or Medium findings for WI-7."** Codex verified the added assertion is the
correct concrete check for the plan-critical boundary and closes the only fence
gap.

## Verdict

**ship-as-is** — 2 rounds (round 1 found zero production findings + 1 Low
test-coverage; round 2 clean).

## Gate-5a verification note

WI-7 is behavioral. The intended Gate-5a XCUITest slice — create a PDF
highlight, tap it, assert the unified popover appears — depends on creating a
highlight first via the in-app selection flow. The same pre-existing XCUITest
harness defect that blocked WI-6's TXT slice (**Bug #237 / GH #986** — a
long-press in an XCUITest surfaces no "Highlight" affordance; reproduces on the
repo's own unmodified gesture-verification tests on `origin/main`) applies to
the PDF text-selection path as well. WI-7's behavioral delta is verified by the
unit-test layer: the 4 `Feature64PDFMigrationTests` source-grep fences (PDF
container attaches the unified popover with `mutating: highlightCoordinator`,
not #55's preview; `PDFViewBridge` has no #53 long-press machinery; the
`.readerHighlightTapped` trigger is kept), plus the unchanged
`PDFHighlightTapResolver` / `PDFHighlightIntegration` / `PDFViewBridgeTheme`
regression suites (30 tests green) and a clean full app build.
