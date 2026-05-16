---
branch: feat/feature-60-wi-9-library-container
threadId: 019e306e-45b9-7d71-956c-4b69c8f27f75
rounds: 3
final_verdict: ship-as-is
date: 2026-05-16
---

# Codex Gate 4 audit — feature #60 WI-9 (Library container re-skin)

Independent implementation audit (Codex MCP, `read-only` sandbox,
`model_reasoning_effort: high`) of the WI-9 Library-container re-skin.
WI-9 re-skins `LibraryView`'s container chrome to the committed design
`dev-docs/designs/vreader-fidelity-v1/project/vreader-library.jsx`
(`LibraryScreen`): warm-paper shell, pill-button nav bar, 36pt Source
Serif 4 title + subtitle, toggleable search bar, filter-chip row,
Continue-reading rail, grid/list bodies.

## Round 1 — initial audit

0 Critical, 2 High, 2 Medium, 1 Low.

- **High #1 — list-mode swipe-to-delete dropped.** The new `listBody`
  used `LazyVStack` (`Button` + `contextMenu` only); the pre-#60
  `List`-based list had `.swipeActions(edge: .trailing)`. Swipe-delete
  was a real behavior regression.
- **High #2 — sort UI vanished.** The pre-#60 toolbar's `sortPicker`
  (bound to `viewModel.sortOrder`) had no replacement; `viewModel.sortOrder`
  still existed but no user path could change it. The design's
  `GridView` "All books / Recent ⌄" header was also missing.
- **Medium #3 — empty-library state lost the nav actions.** The empty
  branch bypassed `libraryContent`, so Settings / OPDS / Collections /
  AI / Import / view-toggle were unreachable when the library was empty
  (the pre-#60 toolbar stayed visible when empty).
- **Medium #4 — bug #72 `isPushingReader` dead.** Nothing in the new
  render tree read `isPushingReader`; the pre-#60 code hid the toolbar
  during a reader push via `.toolbar(isPushingReader ? .hidden : .visible)`.
- **Low #5 — file size.** `LibraryView.swift` ~394 lines, over the
  repo's ~300-line target; `LibraryCardTokens.swift` ~301 (borderline).

Confirmed intact in round 1: notification-observer chain still mounted,
lazy-download row-tap path present, sheets/importer/cover-picker wiring
survived the split, `LibraryContainerModel` derivations correct for nil
author / CJK / whitespace-only search / the 5-card rail cap.

### Round 1 fixes applied

- **High #1** — `listBody` rebuilt on a native `List` +
  `.listStyle(.insetGrouped)` + `.scrollContentBackground(.hidden)`
  (insetGrouped gives the design's 20pt rounded white card + hairline
  dividers natively). Each row carries `.swipeActions(edge: .trailing,
  allowsFullSwipe: false)` with a destructive Delete. `List` cannot nest
  inside `ScrollView`, so list mode is now the root scroll: the
  Continue-reading rail + sort header ride as leading `List` rows. Grid
  mode keeps `ScrollView` + `LazyVGrid`. `scrollableBody` switches on
  `viewModel.viewMode`.
- **High #2** — new file `LibrarySectionHeader.swift` restores the
  design `GridView` "All books" header: 18pt Source Serif 4 title + a
  `Menu` (label `{activeSort} ⌄`, mirroring the design `Recent ⌄`)
  wrapping a `Picker` bound to `viewModel.sortOrder`. Carries
  `accessibilityIdentifier("sortPicker")`. Rendered above both grid and
  list bodies (the pre-#60 toolbar sort worked in both modes; reusing a
  designed component above the list is designed UI, not invented).
- **Medium #3** — `libraryContent` always mounts `navBar` + `titleBlock`;
  the empty-state CTA replaces only the grid/list body region.
- **Medium #4** — `navBar` gains `.opacity(isPushingReader ? 0 : 1)`,
  the re-skin's equivalent of the pre-#60 push-hide.
- **Low #5** — accepted: `LibraryView.swift` ~394 lines is the
  irreducible container core after splitting ~395 lines into
  `LibraryView+Body.swift` / `LibraryViewSheets.swift` /
  `LibraryViewObservers.swift` (was 791 pre-#60). `LibraryCardTokens.swift`
  301 is a flat token-constant namespace whose own header documents
  "one home for the design spec" — splitting it is an anti-pattern.

## Round 2 — verify fixes

0 Critical, 0 High, 1 Medium.

- **Medium #1 — dead Search pill on empty library.** The empty-state
  fix kept the nav bar mounted but the empty branch suppressed the
  search bar; tapping the Search pill on an empty library did nothing
  visible yet still flipped `isSearchVisible`, so a re-import in the
  same session could return with the search bar unexpectedly open.

High #1/#2 + Medium #3/#4 confirmed fixed.

### Round 2 fix applied

- `LibraryNavBar` gains an `isSearchEnabled: Bool` param; the Search
  pill is `if isSearchEnabled { ... }` — omitted for an empty library.
- `navBar` passes `isSearchEnabled: !viewModel.isEmpty`.
- `LibraryView` adds `.onChange(of: viewModel.isEmpty)` clearing
  `isSearchVisible` / `searchQuery` when the library becomes empty.
- New test `navBarBuildsForEmptyLibrary`; the two existing nav-bar
  tests updated for the new param.

## Round 3 — verify round-2 fix

**0 Critical, 0 High, 0 Medium.** Final verdict: **ship-as-is**.

Round 3 confirmed: Search-pill gating correct, empty-state search-state
clearing correct, `isSearchEnabled` call site correct, test coverage
added. All earlier fixes still hold (swipe-to-delete, sort UI in both
modes, empty-state nav actions, bug #72 push-hide).

Non-blocking note: `LibrarySectionHeader.swift` was untracked at audit
time — staged before the PR.

## Tests

64→65 new WI-9 tests (`LibraryContainerModelTests`,
`LibraryShellTokensTests`, `LibraryContainerCompositionTests`) + 100
adjacent library suites — all pass. Build succeeds on iPhone 17 Pro Sim.
