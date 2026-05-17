---
branch: fix/issue-804-verification-xcuitest-identifiers
threadId: 019e33fe-d4cb-71c0-a662-b2b21aee9db9
rounds: 1
final_verdict: ship-as-is
date: 2026-05-17
---

## Gate 4 — Codex implementation audit, Bug #209 / GH #804

Feature #60's WI-6b reader-chrome re-skin renamed the bottom-toolbar
buttons; the legacy `readerSettingsButton` / `readerAnnotationsButton`
accessibility identifiers were dropped, so 8 of the 25 Verification
XCUITests failed at their first assertion ("Reader settings/annotations
button should be hittable").

Fix: re-point the two `AccessibilityID` constants in
`vreaderUITests/Helpers/TestConstants.swift` to the v2
`ReaderBottomChromeButton` identifiers — `readerSettingsButton` →
`readerDisplayButton`, `readerAnnotationsButton` → `readerNotesButton`.
One change fixes all 17 constant-based call sites.

Codex MCP, read-only sandbox. Thread `019e33fe-d4cb-71c0-a662-b2b21aee9db9`.

## Round 1

**Audit result on GH #804: clean.**

- **Correctness** — the mapping is right. `readerNotesButton` /
  `readerDisplayButton` are the live production identifiers
  (`ReaderChromeButton.swift`). The Notes tap routes through
  `ReaderBottomChrome` → `ReaderContainerView` → `showAnnotationsPanel`
  (`AnnotationsPanelView`, id `annotationsPanelSheet`); the Display tap
  → `showSettings` (`ReaderSettingsPanel`, id `readerSettingsPanel`).
  Both downstream panel identifiers are still wired.
- **Completeness** — `rg` found no live raw-string
  `"readerSettingsButton"` / `"readerAnnotationsButton"` usages; the old
  strings survive only as symbol names / comments.
- **8 tests unblocked** — Feature21/23×2/28/31×2/37×2 all fail at the
  button assertion; no other dropped identifier sits on their paths.
- **Feature34 correctly separate** — `collectionsToolbarButton` is still
  wired (`LibraryNavBar.swift:84`); Feature34's failure is a distinct
  non-identifier regression. Split to **Bug #210 / GH #809**.
- **Shared-constant risk low** — fixing the constant fixes every
  call site in one place.

- **Low (accepted with rationale)** — Codex noted
  `ReaderNavigationTests.testToolbarButtonAccessibilityLabels()`
  (`vreaderUITests/Reader/ReaderNavigationTests.swift:92`) still
  asserts pre-feature-60 accessibility *labels* (`"Bookmarks and
  annotations"`, `"Reading settings"`). **Accepted, not fixed in this
  PR**: that test is (a) not in the Verification test plan and not one
  of #804's 9 tests, (b) a label-copy assertion, a different failure
  mode from #804's identifier-lookup regression, (c) pre-existing drift
  on `main` — this PR neither introduces nor worsens it. Folding a
  separate non-Verification test's label-copy repair into #804's
  identifier fix would expand scope past the bug's contract. Left for a
  follow-up harness-drift cleanup.

## Resolution summary

Zero Critical/High/Medium findings. The single Low is a separate
out-of-scope test's pre-existing drift, accepted with rationale.
`xcodebuild build-for-testing` compiles clean.

**Verdict: ship-as-is.**
