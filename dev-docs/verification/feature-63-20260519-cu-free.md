---
kind: feature
id: 63
status_target: VERIFIED
commit_sha: edd2d4bcaa29685f5474469c6933e0b70698fcd2
app_version: 3.34.10 (build 497)
date: 2026-05-19
verifier: claude
device_or_simulator: iPhone 17 Pro Simulator
os_version: iOS 26.4.1
build_configuration: Debug
backend: n/a
result: pass
---

# Feature #63 — Search results panel v2 re-skin — final Gate-5 verification

Final Gate-5 verification for feature #63 ("Search results panel v2
re-skin — bring the in-reader `SearchView` onto the visual-identity-v2
chrome", PR #854). The feature row is `DONE`; this file records the
verification that flips it to `VERIFIED`.

**Result: `pass`.** All five user-facing acceptance criteria (C1-C5) are
verified end-to-end, and the search-sheet UITest regression that blocked
the prior pass from `VERIFIED` is now resolved.

## Context — what this run completes

The prior Gate-5b pass (`dev-docs/verification/feature-63-20260519.md`,
`result: partial`) verified all five user-facing criteria (C1-C5) by
**manual device verification** on iPhone 17 Pro Sim. It could not flip
#63 to `VERIFIED` because the re-skin (PR #854) had regressed all 6
search-sheet automated UITests — PR #854 swapped `SearchView`'s
`NavigationStack` root for a `VStack`, so the `searchSheet` accessibility
identifier propagated to leaf views instead of resolving as a queryable
`otherElements` container. That regression was filed as **bug #223 /
GH #891**. A sibling accessibility defect unmasked once the audit test
got past its first assertion — `SearchBar`'s `searchTextField` /
`searchCancelButton` having sub-44 pt touch targets — was filed as
**bug #224 / GH #902**.

Both bugs are now **FIXED and merged**:

- **Bug #223 (PR #905)** — `.accessibilityElement(children: .contain)`
  added to `SearchView`'s root, collapsing the re-skinned `VStack`
  subtree into one `searchSheet` container.
- **Bug #224 (PR #920)** — `.frame(minHeight: 44)` + `.contentShape`
  added to the `searchTextField` and the Cancel `Button`.

The #63 row's explicit exit condition was: "flip to VERIFIED once #223
lands and the 6 UITests pass." This run confirms that condition is met
and closes the remaining XCUITest-coverage gap (see C2/C3/C4 below).

## Acceptance criteria

Feature #63's row has no explicit `Acceptance criteria:` field; the C1-C5
criteria below are the same five derived from the row's Scope
("behavior-preserving visual re-skin only — search itself unchanged")
and the implementation plan
(`dev-docs/plans/20260518-feature-63-search-panel-reskin.md`) that the
prior pass verified manually. This run re-establishes each one with an
**automated XCUITest** so the acceptance contract is fully covered by
automation, and re-runs the 6 previously-regressed search-sheet UITests.

| # | Criterion | Verifying test(s) | Observed | Pass |
|---|-----------|-------------------|----------|------|
| C1 | Custom in-sheet search bar replaces the system `.searchable` bar + `NavigationStack` "Done" — leading glyph, bound `TextField`, trailing clear button, accent "Cancel" | `Feature63SearchPanelVerificationTests.test_verify_feature_63_C1_custom_search_bar_replaces_system_bar`; `ReaderSearchSheetTests.testSearchSheetPresents`; `SearchSheetPlaceholderTests.testSearchSheetAccessibilityAudit` | The re-skinned sheet shows the custom `SearchBar`: `searchTextField` (a SwiftUI `TextField`) + `searchCancelButton` are present, and `app.searchFields` (which matches `XCUIElementTypeSearchField`) is empty — the system `.searchable` UISearchBar is gone. The accessibility audit (`testSearchSheetAccessibilityAudit`) passes with `.hitRegion` covered (bug #224's 44 pt fix). | PASS |
| C2 | Empty-query idle state shows the restyled `SearchPromptView` (section label + FTS5 explainer), not a blank `List` | `Feature63SearchPanelVerificationTests.test_verify_feature_63_C2_idle_prompt_renders_on_empty_query` | With the sheet open and no query typed, the `searchEmptyPromptView` element renders ("SEARCH THIS BOOK" section label + the FTS5 explainer copy). The grouped results list and the no-results state are both absent — the idle state is the prompt, not a "0 matches" list. | PASS |
| C3 | A query with matches shows `SearchResultsGroupedList` — "{N} matches in {M} sections" count line + per-`sourceContext` group cards with serif bolded-match snippet rows | `Feature63SearchPanelVerificationTests.test_verify_feature_63_C3_grouped_results_list_for_matches` | Searched `paragraph` against `mini-epub3.epub`: the `searchResultsList` `ScrollView` mounts, `searchResult_*` result-row buttons render inside it (e.g. `searchResult_epub:…:chapter1.xhtml:42`), and the grouped list's "{N} matches in {M} sections" count line ("3 matches in 1 section") renders — a re-skin element absent from the pre-#63 plain `List`. | PASS |
| C4 | A query with zero matches shows the restyled `SearchNoResultsView` — glyph disc + serif "No matches for …" headline + sub line | `Feature63SearchPanelVerificationTests.test_verify_feature_63_C4_no_results_state_for_zero_match_query` | Searched `zzzznotfoundqqq` (a token absent from the fixture): the `searchNoResultsView` element renders, with the re-skinned "No matches for "zzzznotfoundqqq"" headline. The grouped results list is absent — a zero-match query is the no-results state, not an empty grouped list. | PASS |
| C5 | Behavior preserved — clear button empties the query; result-tap navigates the reader to the result's `Locator`; "Cancel" dismisses | `Feature63SearchPanelVerificationTests.test_verify_feature_63_C5_clear_button_empties_query_to_idle_prompt` (clear); `TXTSearchTapHighlightNavigationTests.testSearchTapNavigatesToPosition` (result-tap navigation); `ReaderSearchSheetTests.testSearchSheetDismiss` + `SearchSheetPlaceholderTests.testSearchSheetDismisses` (Cancel dismiss) | Clear: tapping `searchClearButton` empties the query, the sheet reverts to the idle `searchEmptyPromptView`, and the clear button itself disappears. Result-tap: `testSearchTapNavigatesToPosition` confirms a result tap dismisses the sheet and navigates the reader to a valid position. Cancel: both dismiss tests confirm the accent "Cancel" button closes the sheet and restores reader chrome. | PASS |

All 5 criteria PASS. **5/5** — no documented partials this run.

### Search-sheet UITest regression — the #63 exit condition

The 6 search-sheet UITests that PR #854's re-skin regressed (and that
bug #223 / #224 fixed) were re-run on the current `origin/main`
(`c534e0a`, v3.34.9) and **all 6 pass**:

| Suite | Tests | Result |
|-------|-------|--------|
| `ReaderSearchSheetTests` | `testSearchSheetPresents`, `testSearchSheetDismiss` | 2/2 PASS |
| `SearchSheetPlaceholderTests` | `testSearchSheetOpens`, `testSearchSheetDismisses`, `testSearchSheetAccessibilityAudit` | 3/3 PASS |
| `TXTSearchTapHighlightNavigationTests` | `testSearchTapNavigatesToPosition` | 1/1 PASS |

`Executed 6 tests, with 0 failures` — the #63 row's exit condition
("flip to VERIFIED once #223 lands and the 6 UITests pass") is satisfied.

## Commands run

```bash
# Branch off fresh origin/main.
git fetch origin
git checkout -b test/feature-63-verification origin/main

# 1. Re-run the 6 search-sheet UITests that bug #223/#224 fixed —
#    confirm the #63 exit condition (all 6 green).
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test \
  -project vreader.xcodeproj -scheme vreader \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:vreaderUITests/ReaderSearchSheetTests \
  -only-testing:vreaderUITests/SearchSheetPlaceholderTests \
  -only-testing:vreaderUITests/TXTSearchTapHighlightNavigationTests \
  -derivedDataPath .dd
# → Executed 6 tests, with 0 failures (0 unexpected) in 72.159 seconds
# → ** TEST SUCCEEDED **

# 2. Run the new CU-free verification suite that closes the C2/C3/C4
#    XCUITest-coverage gap (5 tests, all green).
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test \
  -project vreader.xcodeproj -scheme vreader \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:vreaderUITests/Feature63SearchPanelVerificationTests \
  -derivedDataPath .dd
# → Executed 5 tests, with 0 failures (0 unexpected) in 76.664 seconds
# → ** TEST SUCCEEDED **
```

## Observations

- **The 6-search-sheet-UITest regression is fully resolved.** Re-running
  the three suites that bug #223 (`searchSheet` identifier propagation)
  and bug #224 (`SearchBar` 44 pt touch targets) regressed produced
  `Executed 6 tests, with 0 failures` on the current `origin/main`. The
  #63 row's documented exit condition is met.

- **The C2/C3/C4 XCUITest-coverage gap is now closed.** The three
  migrated search-sheet suites cover sheet presentation, dismissal, the
  SearchBar accessibility audit, and result-tap navigation — but none of
  them asserted the re-skinned content states (the idle prompt, the
  grouped results list, the no-results state) by their identifiers. The
  prior pass verified C2/C3/C4 only by manual device inspection +
  pure-function unit tests (`SearchViewReskinTests.contentState`, which
  proves the state *selector* but not that the re-skinned views actually
  mount). The new `Feature63SearchPanelVerificationTests` suite closes
  that gap with end-to-end XCUITest assertions, so feature #63's full
  acceptance contract is now covered by automation.

- **Query by element TYPE, not container identifier — the bug #214 +
  bug #223 lesson.** While building the suite, the first run failed C2/
  C3/C4 because the re-skinned content views were queried as
  `app.otherElements`. An `app.debugDescription` dump of the live search
  sheet showed why: bug #223's fix added
  `.accessibilityElement(children: .contain)` to `SearchView`'s root,
  collapsing `searchSheet` into one `Other` container — and inside it,
  SwiftUI propagates each child view's `.accessibilityIdentifier` ONTO
  that view's leaf elements rather than yielding a wrapping `Other`.
  Concretely: `searchEmptyPromptView` (a `VStack` of two `Text`s)
  surfaces as two `StaticText`s; `searchNoResultsView` (an `Image` + two
  `Text`s) surfaces as an `Image` + two `StaticText`s;
  `searchResultsList` surfaces as a `ScrollView`. The suite was rewritten
  to query each by its actual type — the same lesson the feature #54
  pilot (`Feature54ReadingModeRemovalVerificationTests`) drew from bug
  #214. After the rewrite, all 5 tests pass.

- **EPUB fixture sidesteps the TXT search-pipeline gap.** The suite uses
  the `.epubFixture` seed (`mini-epub3.epub`) — a real, openable EPUB
  whose search hits resolve via `href` with no dependency on the TXT
  `segment_base_offsets` persistence path. The prior pass documented
  that the `war-and-peace.txt` fixture has an empty
  `segment_base_offsets`, so TXT search hits do not resolve — an
  independent pre-existing search-pipeline behavior outside feature
  #63's scope (#63 is a view-layer re-skin; it does not touch
  `SearchService` or the indexing pipeline). Using the EPUB fixture
  keeps this suite a clean test of the #63 re-skin and nothing else;
  no defect is filed against #63.

- **No #63 product code was changed.** This run is verification-only:
  it adds one XCUITest suite (`Feature63SearchPanelVerificationTests`)
  and the evidence file, and flips the `docs/features.md` row. No
  `vreader/` product code was touched.

## Artifacts

- `vreaderUITests/Verification/Feature63SearchPanelVerificationTests.swift`
  — the new CU-free verification suite (5 tests, all green).
- `dev-docs/verification/artifacts/feature-63-verify-01-reader-open-20260519.png`
  … `feature-63-verify-06-result-tap-navigated-20260519.png` — the prior
  pass's manual-verification screenshots of C1-C5 on-device (carried
  forward — the visual re-skin render they show is unchanged at the
  current `main`).
- `.dd/Logs/Test/` — the two `xcresult` bundles: the 6-search-sheet-UITest
  re-run (`Executed 6 tests, with 0 failures`) and the
  `Feature63SearchPanelVerificationTests` run (`Executed 5 tests, with 0
  failures`).
