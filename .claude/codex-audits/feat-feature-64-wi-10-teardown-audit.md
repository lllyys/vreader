---
branch: feat/feature-64-wi-10-teardown
threadId: 019e4112-1c9e-7302-bbd0-a945f280638f
rounds: 2
final_verdict: ship-as-is
date: 2026-05-20
---

# Gate-4 Implementation Audit — Feature #64 WI-10 (teardown of the superseded #55/#53 surfaces)

## Scope

WI-10 — the **final WI** of the unified cross-format highlight-action popover.
WI-6..9 (all merged) migrated the five reader containers onto the unified
popover; WI-10 deletes the now-superseded feature #55 (`NotePreview*` /
`NoteCallout*` — the read-only note callout) and feature #53
(`HighlightActionPresenter` / `HighlightTapAction` — the long-press delete
`UIMenu`) families, plus the doc-sync. Plan §3.9.

**21 files deleted** (11 production + 10 test):
- Production: `NotePreviewPresenter`, `NotePreviewContent`, `NotePreviewModifier`,
  `NotePreviewContainerSupport`, `NoteCalloutView`, `NoteCalloutAction`,
  `NotePreviewSheetView`, `UIKitNotePreviewPresenter`, `HighlightActionPresenter`,
  `NotePreviewViewModel`, `HighlightTapAction`.
- Tests: the matching `*Tests.swift` for each, plus `Feature55WebHostWiringTests`
  (tested `NotePreviewPresenter.resolvedForm`), `HighlightCoordinatorTapHandlerTests`
  (tested the removed `handleTapAction`), `TXTBridgeHighlightTapSubscriberTests`
  (a feature #53 WI-2b test of the TXT bridge's removed `highlightActionPresenter`
  subscriber path — slipped past WI-6's deletion because of its name),
  `Feature55NotePreviewVerificationTests` (the #55 XCUITest).

**Code edits** (~146 insertions, the deletions are ~4301 lines):
- `HighlightCoordinator.swift` — removed the feature-#53 `handleTapAction(_:highlightID:)`
  method (its only callers were the `onHighlightTapAction` wirings removed in
  WI-6/WI-7); 2 doc comments updated. `handleRemoval` (the Annotations-panel
  delete path) stays.
- `UIKitHighlightPopoverPresenter.swift` (+20) — the `extension UIView { var
  nearestViewController }` was re-homed here from the deleted
  `UIKitNotePreviewPresenter.swift` (`UIKitHighlightPopoverPresenter`, a
  surviving WI-4 file, is its sole caller).
- `HighlightPopoverPresenterTests.swift` — removed the
  `resolvedForm_parityWithNotePreviewPresenter` test (its cross-check subject
  is deleted; the file's own comment said WI-10 removes it).
- Comment-sync (rule 22) in 8 surviving files whose `@coordinates-with` / doc
  comments named deleted files.
- `docs/architecture.md` + `README.md` — doc-sync (new "Unified
  highlight-action popover" subsection, `.readerHighlightTapped` /
  `.foliateRequestAnnotationJS*` Notification Bus rows, the README
  "Tap-to-edit highlights" bullet).

## Round 1 — Codex `019e4112-1c9e-7302-bbd0-a945f280638f`

**No blocking findings.** Codex verified:

- **Teardown completeness** — exactly the right files deleted; no missed
  #53/#55 family member; `project.pbxproj` no longer references them.
- **`handleTapAction` removal** — genuinely dead (no surviving caller);
  `handleRemoval` remains; the unified popover's `confirmDelete` still routes
  through `HighlightCoordinator.deleteHighlight` via
  `HighlightPopoverActionRouter`.
- **`nearestViewController` re-home** — correct home (`UIKitHighlightPopoverPresenter`
  is the sole surviving caller); the implementation matches the deleted
  original; the file stays under the guideline at 281 lines.
- **No dangling references** — no live production/test reference to a deleted
  symbol beyond intentional historical comments + the `Feature64*MigrationTests`
  negative source-grep assertions.
- The 8 comment-synced files are in sync, `@coordinates-with` lines clean,
  `HighlightPopoverPresenterTests` still covers the presenter's own
  `resolvedForm` axes, `docs/architecture.md`'s new section + notification rows
  accurate.

Three findings (all comment/doc accuracy):

| # | File:line | Severity | Issue | Fix |
|---|-----------|----------|-------|-----|
| F1 | `README.md:48,50` | Low | The new "Tap-to-edit highlights" bullet is accurate, but the surrounding AZW3 annotation bullets are now stale + self-contradictory ("AZW3 in progress" / "overlay restoration deferred to WI-7" vs "AZW3 highlights can be edited via the shipped popover"). | Rewrite the AZW3 bullets for post-WI-9/10 consistency. |
| F2 | `ReaderContainerView.swift:684` | Low | Stale `.foliateWeb` comment — says the AZW3/MOBI tap was "re-homed to the #55 note preview" (deleted in WI-10). | Update to the feature #64 WI-9 unified popover path. |
| F3 | `HighlightPopoverPresenterTests.swift:5` | Low | The file header still claims the `NotePreviewPresenter` parity fence is active coverage; that test was removed later in the file. | Trim the header to the surviving coverage. |

## Resolution

- **F1** — README AZW3 bullets rewritten: "Full CRUD across all five formats";
  "SVG-overlay rendering via the Foliate-js bridge". The Annotations section is
  now internally consistent.
- **F2** — `ReaderContainerView.swift:684` `.foliateWeb` comment rewritten to
  describe the feature #64 WI-9 unified popover path.
- **F3** — `HighlightPopoverPresenterTests` header rewritten to past tense (the
  parity fence "was removed in WI-10").

## Round 2 — Codex `019e4112-1c9e-7302-bbd0-a945f280638f` (re-audit of the fixes)

Verdict: **"All 3 Low findings are resolved... There are no remaining open
Critical, High, or Medium findings for WI-10."**

## Verdict

**ship-as-is** — 2 rounds (round 1 found zero production correctness findings +
3 Low comment/doc-accuracy; round 2 clean).

## Gate-3 verification

The 21-file deletion is regression-free:
- The production app builds clean (`BUILD SUCCEEDED`) after the deletions + the
  `nearestViewController` re-home.
- The test target builds clean (`TEST BUILD SUCCEEDED`) — proving no dangling
  symbol reference anywhere in `vreaderTests` / `vreaderUITests`.
- A focused regression gate of **158 tests across 19 suites** passes — the full
  feature-#64 popover surface, all 5 reader-container migration suites, the
  PDF/EPUB highlight regression suites, and `HighlightCoordinatorTests`. (A full
  `vreaderTests` run was attempted but the shared simulator was wedged under
  concurrent sibling-agent contention; the 19-suite gate covers WI-10's entire
  deletion blast radius — the test-target compile-clean already proves no
  dangling reference app-wide.)

## Gate-5 — final-WI acceptance

WI-10 is the final WI; per plan §10 the feature reaches `VERIFIED` only after a
full 8-criterion acceptance pass. All 8 criteria require creating then tapping a
highlight in the running app. This is blocked CU-free by **Bug #237 / GH #986**
(an XCUITest synthesized long-press surfaces no "Highlight" affordance —
reproduces on the repo's own unmodified gesture-verification tests on
`origin/main`) and there is no DebugBridge highlight-seed command. The
acceptance pass is therefore run manually on the iPhone 17 Pro Simulator and
recorded in `dev-docs/verification/feature-64-<YYYYMMDD>.md`; the feature row
flips to `DONE` on merge (the merge gate) and to `VERIFIED` once that evidence
file lands.
