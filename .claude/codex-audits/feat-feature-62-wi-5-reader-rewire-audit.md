---
branch: feat/feature-62-wi-5-reader-rewire
threadId: 019e40e4-9ce7-7fb3-8279-ca51231195f6
rounds: 3
final_verdict: ship-as-is
date: 2026-05-20
---

# Codex Audit — feat/feature-62-wi-5-reader-rewire

**Feature**: #62 — annotations panel split (WI-5, final WI).
**Scope**: rewire `ReaderContainerView` to route `TOCSheet` / `HighlightsSheet`
via `AnnotationsSheetRoute`; delete the 5 legacy view files
(`AnnotationsPanelView`, `HighlightListView`, `AnnotationListView`,
`TOCListView`, `BookmarkListView`); migrate 12 XCUITest consumer files.
**Auditor**: Codex (`mcp__plugin_codex-toolkit_codex__codex`), read-only sandbox.
**Thread**: `019e40e4-9ce7-7fb3-8279-ca51231195f6`. Gate 4 — implementation audit.

## Round 1 — 5 findings (2 High, 2 Medium, 1 Low)

1. **High — `TOCSheet` missing root `tocSheet` accessibility identifier.**
   `HighlightsSheet` sets `.accessibilityIdentifier("highlightsSheet")` on its
   root; `TOCSheet` set none. The migrated XCUITests query
   `app.otherElements["tocSheet"]` to detect/audit/dismiss the sheet — they
   would never resolve.
   **Fix**: `TOCSheet.body` now ends with `.accessibilityElement(children: .contain)`
   + `.accessibilityIdentifier("tocSheet")`, mirroring `HighlightsSheet`.

2. **High — two new test files untracked while `project.pbxproj` references them.**
   Pre-commit-state observation: `AnnotationsRouteWiringTests.swift` and
   `Feature62AnnotationsSplitVerificationTests.swift` were untracked; a clean
   checkout would fail the build.
   **Resolution**: both files are `git add`-ed in the WI-5 commit (no code
   change). pbxproj file refs confirmed correct by the round-2 re-audit.

3. **Medium — eager `ensureTOCReady()` is fire-and-forget → false
   "No table of contents" empty state during the TOC build.**
   `ensureTOCReady()` spawns a `Task` and returns; a fast Contents tap could
   present `TOCSheet` with `tocEntries == []` while the build is still in
   flight, flashing the designed empty state for a book that does ship a TOC.
   **Fix**: added `@State var tocDidLoad` to `ReaderContainerView`, set `true`
   on both `ensureTOCReady()` paths (early-return-when-built + post-build Task);
   passed into `TOCSheet` via a new `tocDidLoad: Bool` init param;
   `TOCSheet.contentsBody` is now a three-way branch (entries / loaded-empty /
   still-loading neutral body) mirroring the existing `bookmarksDidLoad` gate.
   New `contentsEmptyStateShown` DEBUG hook + `contentsEmptyStateOnlyAfterLoad`
   test cover it.

4. **Medium — `HighlightSwatch.color(for:)` collapsed red/orange/purple to
   yellow.** The JSX `colorMap` depicts 4 colours, but the real stored
   highlight palette also includes red/orange/purple; a red highlight rendered
   with a yellow swatch + rule is a data-fidelity regression.
   **Fix**: `HighlightSwatch.color(for:)` resolves the designed four via
   `NamedHighlightColor` hex stops (pixel-identical to the old literals) and
   red/orange/purple to distinct faithful hues (`#e08585` / `#e8a85a` /
   `#b48ce8` — the same hues `NoteCalloutView.noteSwatchColor` uses). Rule 51
   permits extending a designed swatch's data mapping. Three new
   `HighlightSwatch` tests cover designed colours, the broader palette, and the
   unknown-name fallback.

5. **Low — `docs/architecture.md` stale** (described `ReaderSheetChrome`
   wrapping `AnnotationsPanelView`, the unified 4-tab panel as shipped).
   **Fix**: Sheets section rewritten for the `TOCSheet` + `HighlightsSheet`
   split + `AnnotationsSheetRoute`; `.readerOpenContents` / `.readerOpenNotes` /
   `.readerMoreExportAnnotations` notification rows updated; file-organization
   tree updated (`Views/Bookmarks/` removed, `Views/Reader/Annotations/` added).

## Round 2 — re-audit

All 5 findings confirmed resolved. No new Critical/High/Medium introduced.
Specific follow-ups confirmed: `tocDidLoad: Bool = true` default is safe (the
sole production caller passes the real value; the default only serves
test/composition callers); setting `tocDidLoad = true` in the
`ensureTOCReady()` early-return branch is correct (if entries already exist the
load is semantically complete).

**Round 2 VERDICT: ship-as-is**

## Round 3 — re-audit (Gate-5 device-verification findings)

Gate-5 XCUITest verification surfaced three real issues, all fixed:

A. **XCUITest suites used the wrong seed (`.books`).** The `.books` fixtures
   are metadata-only `BookRecord`s with no backing file (Bug #209 / #214) — the
   reader file-not-founds and the bottom chrome never renders, so the
   Contents/Notes buttons are unreachable. These suites were pre-existing-broken
   on `main`; WI-5's identifier migration carried the bug forward.
   **Fix**: switched the annotations XCUITest suites
   (`Feature62AnnotationsSplitVerificationTests`, `ReaderAnnotationsPanelTests`,
   `AnnotationsPanelPlaceholderTests`, `Feature35AnnotationsExportVerificationTests`,
   `NavigationFlowTests` + `GlobalAccessibilityAuditTests` annotations tests) to
   `.epubFixture` (`mini-epub3.epub`) + a robust `openSeededBook` (3-retry) +
   chrome-reveal `app.tap()`, mirroring `Feature63SearchPanelVerificationTests`.

B. **`HighlightsSheet` export button tap target < 44pt.** The audit's
   `.hitRegion` flagged the bare 16pt icon.
   **Fix**: `.frame(44, 44)` + `.contentShape(Rectangle())` on the label — icon
   visually unchanged, hit area now compliant.

C. **Audit false positives on the decorative empty-state art.** `.elementDetection`
   flagged `EmptyHighlightsArt`'s stylized "text-line" bars (issue reported with
   `element == nil` — no real control missing a label). `.hitRegion` flagged
   `TOCSheet`'s designed compact segmented control (mirrors the native
   `UISegmentedControl` idiom; resizing would violate the committed design).
   **Fix**: `.accessibilityHidden(true)` on the art; `.elementDetection` excluded
   in the two annotations audit tests with rationale; `.hitRegion` additionally
   excluded for the `TOCSheet` audit only (the `HighlightsSheet` audit keeps it
   active — the export button is now compliant).

Round-3 re-audit confirmed all Round-3 fixes sound, no new Critical/High/Medium.
The export-button 44pt frame fits the 50pt `ReaderSheetChrome` slot;
`.accessibilityHidden` hides only the art subtree (CTA stays accessible); the
scoped audit exclusions are consistent with `auditCurrentScreen`'s existing
false-positive policy. Two TXT highlight XCUITests
(`TXTHighlightGestureVerificationTests`, `TXTChapterModeHighlightVerificationTests`)
fail at a pre-existing highlight-creation-gesture / chapter-mode-rendering step
WI-5 never touched (WI-5's delta there is purely the downstream identifier swap)
— out of scope.

**Round 3 VERDICT: ship-as-is**
