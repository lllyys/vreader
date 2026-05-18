# Feature #63 — Search results panel v2 re-skin — implementation plan

- **Feature row**: `docs/features.md` #63 (TODO)
- **GH issue**: #802
- **Design source** (committed, rule 51 satisfied):
  `dev-docs/designs/vreader-fidelity-v1/project/vreader-search.jsx`
  + `.../design-notes/reader-search-and-more-menu.md`
- **Author**: feature-cron (Gate 1), 2026-05-18
- **Lineage**: v2 follow-on of feature #60 (VERIFIED). New feature per the
  close gate.

## 1. Problem

`SearchView.swift` (the in-reader full-text search sheet) still uses
pre-v2 chrome — a `NavigationStack` + `.searchable` + a plain `List`.
Feature #60's plan listed "search results panel" as out-of-scope-for-v1;
no row picked it up; #60 reached `VERIFIED` without it. The committed
design (`vreader-search.jsx`) brings the surface onto the v2 visual
language: a custom search bar, results grouped by location with serif
snippets, and styled empty / no-results states.

## 2. Scope reconciliation — design exceeds the row (read first)

The committed design depicts items the #63 row's scope
("behavior-preserving visual re-skin only — search itself unchanged")
excludes:

1. **"All books" scope toggle** — library-wide FTS. `SearchViewModel`
   searches one book; there is no cross-book search surface. **Out of
   scope** — recommended as a separate `IDEA` row: "Library-wide
   full-text search". The re-skinned bar **omits** the scope toggle (a
   single-scope, in-book bar) — not a disabled control, which would
   advertise an unimplemented feature.
2. **"Recent searches"** — query-history persistence does not exist.
   **Out of scope** — recommended as a separate `IDEA` row.
3. **FTS5 syntax-hint chips** (`chapter:1`, `highlighted:yellow`,
   `note:` …) — the design's chips imply query operators that may not
   exist. **WI-2 ships hint chips only for syntax the current FTS5
   query path actually supports** (WI-2 confirms which; if none beyond
   plain terms + quoted phrases, ship just those two or omit the
   chips). No operator is invented to match the design.
4. **`p.{page}` per-result badge** — most formats have no page number
   (see §3 / the data model). Dropped; the group header carries the
   location instead.

The authoritative scope is the **#63 row**, not the fuller design.
This stays a **pure view-layer re-skin** — no `SearchService` /
`SearchViewModel` / `SearchResult` change (see §3).

## 3. Data model — what the re-skin can actually render

Production `SearchResult` (`vreader/Services/Search/SearchService.swift`)
is `{ id, snippet, locator, sourceContext }`:

- **`sourceContext`** is a single pre-formatted location string —
  chapter-ish text for EPUB, `"Page N"` for PDF, `"Section N"` for
  TXT/MD. **It is already the per-result group label.** The re-skin
  **groups results by `sourceContext`** — that yields the design's
  "grouped by chapter" for EPUB and the equivalent per-format grouping
  elsewhere, with **zero data-model change**.
- There is **no separate page field**; the design's `p.{page}` badge is
  a prototype detail and is dropped (§2.4).
- `snippet` carries FTS5 match markup; highlighting is already handled —
  see §4.

This is the audit-driven correction (Gate-2 round 1): the v1 plan
assumed structured chapter/page fields that do not exist. v2 groups by
the string that does exist, keeping #63 a true behavior-preserving
re-skin with no foundational data WI.

## 4. Surface area

### Modified files

- `vreader/Views/Search/SearchView.swift` (142 lines today) — replace
  `NavigationStack` + `.searchable` with the design's custom in-sheet
  search bar (search glyph + text field + clear button + "Cancel");
  replace the plain `List` with the grouped results view; restyle the
  loading / no-results / empty states. Inputs (`@Bindable viewModel:
  SearchViewModel`, `onNavigate: (Locator) -> Void`, `onDismiss: () ->
  Void`) unchanged — that is why the re-skin is behavior-preserving.
- `vreader/Views/Search/SearchResultRow.swift` — restyle to the design's
  serif snippet treatment. **Keeps using `HighlightedSnippet.highlight(…)`**
  (`vreader/Utils/HighlightedSnippet.swift`) for match emphasis — that
  utility already strips FTS5 `<b>…</b>` tags and handles CJK / multi-word
  matches and has existing tests. The v1 plan's invented `**match**`
  renderer is dropped (Gate-2 round-1 finding 3).

### New files

- `vreader/Views/Search/SearchResultsGroupedList.swift` — the
  grouped-by-`sourceContext` results list, extracted so `SearchView.swift`
  stays under the ~300-line guideline.

### Modified test files (existing UITests the re-skin breaks)

The current UITests assert a system `XCUIElementTypeSearchField` (from
`.searchable`) and a `"Done"` dismiss button. Removing `.searchable`
breaks them — they must migrate to the custom text field + `"Cancel"`:

- `vreaderUITests/Reader/TXTSearchTapHighlightNavigationTests.swift`
- `vreaderUITests/Reader/ReaderSearchSheetTests.swift`
- `vreaderUITests/Search/SearchSheetPlaceholderTests.swift`

WI-1 owns this migration (the bar + dismiss change is WI-1's).

### Unchanged (behavior-preserving — explicitly OUT of scope)

- `SearchService`, `SearchViewModel`, `SearchResult` — the FTS5 query,
  debounce, pagination (`loadMore()`/`hasMore`), error handling, and the
  result DTO: untouched.
- Result-tap → `Locator` navigation — untouched.
- "All books" scope, "Recent searches", new query operators — see §2.

## 5. Prior art / project precedent / rejected alternatives

- **Precedent — feature #60 re-skins** (`LibraryView`, etc.): match the
  committed `.jsx`, preserve behavior, extract sub-views.
- **Precedent — `HighlightedSnippet`**: the existing FTS5-match
  emphasiser; reused, not replaced.
- **Rejected — keep `.searchable`**: cannot host the design's in-sheet
  bar with a custom Cancel.
- **Rejected — add structured chapter/page fields to `SearchResult`**:
  that is a `SearchService` change — outside the row's
  "search unchanged" scope. Grouping by the existing `sourceContext`
  string achieves the design's intent without it (§3).
- **Rejected — implement the full design** (scope toggle / recent /
  page badge): contradicts the row's scope; see §2.

## 6. Work-item sequencing

| WI | Title | Tier | PR size |
|----|-------|------|---------|
| WI-1 | Custom search bar + sheet chrome re-skin + existing-UITest migration | **behavioral** | medium |
| WI-2 | Grouped-by-`sourceContext` results list + restyled empty / no-results states | **behavioral** (final WI) | medium |

- **WI-1** — replace `NavigationStack`/`.searchable` with the custom bar;
  migrate the three existing UITests' search-field + dismiss assertions.
  The results area renders the old list until WI-2. RED:
  `SearchViewReskinTests` — the clear button empties `viewModel.query`,
  "Cancel" invokes `onDismiss`. Behavioral, not final → `patch`.
- **WI-2** — `SearchResultsGroupedList` (group by `sourceContext`,
  preserve result order), restyled empty / no-results states. Completes
  the visible re-skin. RED: grouping a fixture `[SearchResult]` by
  `sourceContext` preserves order + group count. Final WI → `minor`.
- 2 WIs — small, sequential, reviewable PRs. WI-1 (chrome/input) and
  WI-2 (results/states) both touch `SearchView.swift`, so they land in
  sequence, not in parallel.

## 7. Test catalogue

- `vreaderTests/Views/Search/SearchResultsGroupedListTests.swift` (WI-2):
  grouping a fixture result set by `sourceContext` preserves document
  order; single-group, many-groups, one-result-per-group; the
  match-count-per-group label; empty `sourceContext` fallback.
- `vreaderTests/Views/Search/SearchViewReskinTests.swift` (WI-1): the
  custom bar's clear button empties `viewModel.query`; "Cancel" invokes
  `onDismiss`; a result tap still invokes `onNavigate` with the result's
  `Locator` (the behavior-preserving guard).
- **Existing-UITest migration** (WI-1, finding 4): update
  `TXTSearchTapHighlightNavigationTests`, `ReaderSearchSheetTests`,
  `SearchSheetPlaceholderTests` to the custom text field's a11y id +
  the `"Cancel"` dismiss path; they must stay green in the WI-1 PR.
- Gate 5 — `vreaderUITests/Verification/Feature63SearchReskinVerificationTests.swift`:
  open a seeded book → Search → assert the custom bar + grouped results
  resolve and a result tap navigates. DebugBridge-drivable, CU-free.
- `HighlightedSnippet` keeps its existing tests — no new snippet
  renderer is introduced.

## 8. Risks + mitigations

1. **`sourceContext` granularity varies by format.** EPUB groups by
   chapter-ish text, PDF by `"Page N"`, TXT/MD by `"Section N"`. The
   grouped list is correct for all — the group header is whatever
   `sourceContext` says — but the design's chapter-specific copy
   ("N matches in N chapters") must be format-neutral ("N matches in N
   sections"). WI-2 uses neutral copy.
2. **`.searchable` removal changes focus behavior.** The system bar
   auto-focuses. *Mitigation*: WI-1 replicates auto-focus with
   `@FocusState`; `SearchViewReskinTests` + the migrated UITests pin
   the query-binding and dismiss behavior.
3. **Empty/no-results copy referenced the scope toggle.** With the
   toggle omitted (§2.1), WI-2 ships copy that does not mention
   switching scope.
4. **Hint-chip overpromise.** §2.3 — WI-2 confirms supported FTS5
   syntax and ships chips only for it.

## 9. Backward compatibility

- No schema change, no migration, no persisted state. Pure view-layer
  re-skin; `SearchService` / `SearchViewModel` / `SearchResult` and the
  FTS5 index untouched. No older-client / older-backup impact. The only
  externally observable changes are visual + the search-field /
  dismiss-button identity (handled by the WI-1 UITest migration).

## 10. Revision history / Gate-2 audit trail

| Version | Date | Change |
|---|---|---|
| v1 | 2026-05-18 | Initial draft (feature-cron, Gate 1). |
| v2 | 2026-05-18 | Gate-2 round-1 (Codex `019e39f1`): 5 findings applied — WI-2 re-based on the real `SearchResult` model (group by the existing `sourceContext` string; no chapter/page fields exist) (High ×2); reuse `HighlightedSnippet`, drop the invented `**match**` renderer (Medium); add explicit migration of 3 existing UITests off `.searchable`/"Done" (Medium); omit the scope toggle + fix no-results copy + gate hint chips to supported syntax (Medium). Still 2 WIs — the audit confirmed no foundational data WI is needed once grouping uses `sourceContext`. |
| v3 | 2026-05-18 | Gate-2 round-2 (Codex `019e39f1`): 1 Low applied — §6 "disjoint write sets" corrected (WI-1 and WI-2 both touch `SearchView.swift`; they are sequential, not parallel). |

### Gate 2 — Independent plan audit

**Round 1** — Codex MCP, thread `019e39f1-8293-7c91-b545-00279aa2bc61`,
2026-05-18. 2 High + 3 Medium — all legitimate, all applied in v2. Codex
confirmed `SearchView`/`SearchViewModel`/`SearchResultRow` exist with
the named signatures, `SearchViewModel` exposes the named observable
surface, and the view layer is already `@MainActor` (a pure re-skin is
low concurrency risk). The core round-1 issue — WI-2 designed against
non-existent structured data — is resolved in v2 by grouping on the
`sourceContext` string that does exist.

**Round 2** — Codex MCP, same thread, 2026-05-18. Verdict: **"Gate-2
clean: zero open Critical/High/Medium findings"** — strict verdict
**pass**. All 5 round-1 findings genuinely resolved; grouping by
`sourceContext` confirmed sound against the real `SearchService`
formatter; the 2-WI split confirmed. One Low nit (the "disjoint write
sets" wording) — fixed in v3.

**Gate 2 PASSED** (2 rounds — within the rule-47 cap). Zero open
Critical/High/Medium findings; the single Low was fixed. Plan ready for
Gate 3 (TDD implementation), starting at WI-1.
