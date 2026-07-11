---
branch: feat/128-wi7-search-screen
threadId: 019f4f74-8791-71d1-9bd5-9430b4d92a6b
rounds: 3
final_verdict: ship-as-is
date: 2026-07-11
---

# Gate-4 audit — feature #128 WI-7 (Android SearchScreen UI + Library search entry)

Independent Codex audit (rule 53 / rule 47 Gate 4) of the WI-7 diff:
`SearchScreen.kt` (new), `LibraryScreen.kt` (Search pill + grid author subtitle),
`MainActivity.kt` (saveable search route), + instrumented UI tests.

Scope focus: rule-51 fidelity to the committed `vreader-library-android.jsx`
section C; the honest no-results gate (`searched && indexComplete && empty`);
sections hidden when empty; pure-function composable + hoisted state; ViewModel
lifecycle; result-tap open + `recordCurrentQuery`; bounds-safe wash highlighting.

## Round 1 — findings + fixes

- **High — search field unusable (static `Text`, not an input).** The field
  rendered the query as a `Text`; `onQueryChange` was reachable only via clear /
  recent-tap. **Fixed:** replaced with a `BasicTextField` bound to the query
  (IME `Search` action, accent caret, accent focus-ring while a query is present,
  placeholder in the `decorationBox`). Added typing + clear tests.
- **High — `SearchViewModel` leaked after close.** Built via raw
  `remember { container.searchViewModel() }` — Compose forgets it on disposal but
  never calls `ViewModel.clear()`, so its `viewModelScope` collector runs forever
  (a new instance each reopen). **Fixed:** obtained via
  `viewModel(key = "search", factory = …)` so the Activity's `ViewModelStore`
  owns + clears it.
- **Medium — result cover 44×62 vs design 62×93; missing row rules; section
  labels not uppercased.** **Fixed:** 62×93 (2:3) cover; a 0.5dp bottom rule per
  result row; uppercased section labels (`RECENT` / `BROWSE COLLECTIONS`) per the
  design's `textTransform`.
- **Medium — saveable `SearchRoute`.** Kept a `rememberSaveable` Boolean for the
  takeover open/closed (survives process death — the SheetRoute-precedent pattern
  applied to a full-screen route). Query re-entry across process death is
  ViewModel/SavedStateHandle state (WI-6 concern), out of this WI's scope.

## Round 2 — findings + fixes

- **High — `highlightMatch()` Unicode case-fold crash.** It searched
  `title.lowercase()` then indexed back into the original `title`; a case-fold
  that changes length (Turkish `İ`→`i̇`, `ß`→`ss`) makes the index out of bounds
  → `IndexOutOfBoundsException`. **Fixed:** match the ORIGINAL string via
  `indexOf(q, ignoreCase = true)` with defensive `coerceIn` clamps. Added a
  Unicode-expanding-title render test.
- **Medium — `snippetWithAttribution()` overlapping ranges duplicated text.** A
  range starting before `cursor` was re-appended and moved `cursor` backward.
  **Fixed:** clamp each start to `>= cursor` and keep `cursor` monotonic
  non-decreasing (safe for overlap / nested / reversed / negative / past-end).
  Added a hostile-ranges test.
- **Minor fidelity:** added the recent-row 0.5px bottom rule + the 12px gap below
  each result row.

## Round 3 — final

Both round-2 correctness fixes confirmed correct; no remaining Critical/High/
Medium findings. Re-checks pass: rule-51 fidelity, no-results gating,
composable purity, VM lifecycle, result-tap open + record + dismiss, search
entry / collection selection / recent-query / author subtitle wiring.

One minor test-quality note (NOT a finding): the hostile-range UI assertion
proves no-crash but not strictly the absence of duplicated text; the
implementation invariant does prove it.

**Final verdict: ship-as-is.**
