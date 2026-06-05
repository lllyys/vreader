# Feature #94 — Filterable TOC (Contents-tab filter field)

**GH:** #1529 · **Design:** `dev-docs/designs/vreader-fidelity-v1/project/design-notes/toc-filter-94.md` + `toc-filter-artboards.jsx` (landed via #1517).
**Status:** Gate 1 (plan) — 2026-06-05.

## Problem

Long-TOC books (multi-hundred-chapter CJK novels especially) are unnavigable in the Contents tab without endless scrolling. The user asked: "toc should be able to search." A client-side **filter** over the already-loaded TOC entries — narrow by title as you type — makes a 142-chapter list usable. This is NOT full-text content search (#2/#63); the existing "Open Search" CTA still owns that.

## Surface area (file-by-file)

### NEW `vreader/Views/Reader/Annotations/TOCTitleFilter.swift` (pure logic — the testable core)
A stateless namespace, pure + `Sendable`:
- `static func matchRanges(in title: String, query: String) -> [Range<String.Index>]` — ALL non-overlapping occurrences of `query` in `title`, **case-insensitive + diacritic-insensitive**, via Foundation `title.range(of:options:[.caseInsensitive, .diacriticInsensitive], range:)` iterated to exhaustion. Returns ranges in the ORIGINAL `title` (so the highlight maps correctly — see Rejected alternatives). Empty/whitespace query → `[]`.
- `static func matches(_ title: String, query: String) -> Bool` — `!matchRanges(in:query:).isEmpty` for a non-empty trimmed query, else `true` (empty query matches all).
- **`static func filtered(_ entries: [TOCEntry], query: String) -> [(index: Int, entry: TOCEntry)]`** — enumerates FIRST, then filters, so each surviving row carries its ORIGINAL list index: `Array(entries.enumerated()).filter { matches($0.element.title, query:) }.map { (index: $0.offset, entry: $0.element) }`. Empty query → all entries with their identity indices. **(Gate-2 H1 fix — the row's chapter ordinal `index+1` and `isCurrent` (`originalIndex == activeEntryIndex`) MUST use the original index, never the filtered position, or filtered rows renumber + the current-row marker lands on the wrong row.)**

### NEW `vreader/Views/Reader/Annotations/TOCFilterField.swift` (the field + count, designed surface)
- `struct TOCFilterField: View` — a pinned search field (magnifier glyph + `TextField` + clear button) styled per the artboard, themed via `ReaderThemeV2`. Binds `@Binding var query: String`. Below/in it: the live count label — `"N of M chapters"` (filtering) or `"No matches"` (no result) or hidden (empty query). Accessibility id `tocFilterField` / `tocFilterCount`.

### MODIFY `vreader/Views/Reader/Annotations/TOCSheet.swift`
- Add `@State var filterQuery = ""` — **`internal`, NOT `private`** (Gate-2 r2 Medium): the existing extension-read `@State` (`selectedTab` / `bookmarkVM` at `:51-63`) is non-private exactly so `TOCSheet+Support.swift` can reach it; a `TOCSheet+Filter.swift` extension cannot read a `private` stored property.
- **Pinned field (Gate-2 H2 fix — corrected r2)**: the REAL scroll container is the SINGLE outer `ScrollView` at `TOCSheet.swift:100-105` that wraps BOTH tabs (`switch selectedTab { contents / bookmarks }`); `tocEntryList`'s `ScrollViewReader` does NOT scroll by itself — it relies on that outer scroll. So the field cannot just go above `tocEntryList` inside the outer scroll. **Split the outer scroll by tab**: remove the shared `ScrollView` (`:100-105`); the body `VStack` holds `segmentedControl` then the per-tab content directly:
  - `.contents` → `VStack(spacing: 0) { TOCFilterField(query: $filterQuery, ...); contentsScrollList }` where `contentsScrollList = ScrollViewReader { proxy in ScrollView { LazyVStack { rows } } }` (the field is pinned OUTSIDE this inner `ScrollView`; the list scrolls within it; the `ScrollViewReader` proxy now drives the inner `ScrollView` for the auto-scroll-to-current `.task`). The no-TOC / pre-load branches keep their current non-scrolling form.
  - `.bookmarks` → `ScrollView { bookmarksBody }` (its own scroll; unchanged behavior).
- Drive the list off `let visible = TOCTitleFilter.filtered(tocEntries, query: filterQuery)` (computed once per body eval). `ForEach(visible, id: \.entry.id)` and render each row with **`chapterOrdinal: pair.index + 1`** and **`isCurrent: pair.index == activeEntryIndex`** — the ORIGINAL index (Gate-2 H1).
- No-match state (`visible.isEmpty` + non-empty trimmed query): reuse `AnnotationsEmptyStateView` (the same component the no-TOC state uses) with the **"Open Search"** CTA wired to `onOpenSearch` — NOT the "No table of contents" copy; a filter-specific "No chapters match" message.
- **Clear-filter re-scroll (Gate-2 M2 fix)**: the existing `.task(id: currentChapterScrollTarget)` will NOT re-fire when `filterQuery` returns to empty (the id is unchanged). Add `.onChange(of: filterQuery)` → when the trimmed query transitions to empty, re-issue the scroll-to-current (call the same scroll helper the `.task` uses, or include `filterQuery.isEmpty` in the scroll `.task(id:)` key). Auto-scroll-to-active applies only in the unfiltered default; while filtering, no auto-scroll (the list is short).
- Keep the Contents/Bookmarks toggle + the bookmark count badge.
- **File-size (Gate-2)**: TOCSheet is 313 lines — extract the filter wiring (the `visible` computation + the no-match branch + the `TOCFilterField` placement helper) into a new `TOCSheet+Filter.swift` extension to stay under ~300.

### MODIFY `vreader/Views/Reader/Annotations/TOCSheetRows.swift` (or wherever `TOCContentsRow` lives)
- `TOCContentsRow` renders the title as an `AttributedString` with the matched runs styled: **15% accent tint background + 40%-opacity accent underline** (the in-text-highlight vocabulary, scaled to inline type), applied to EVERY matched range. The current-chapter row keeps its accent ink + bold; the match tint composes on top. Pass the `matchRanges` (or the query) into the row so it can build the attributed title. Empty query → plain title (no attributed overhead).

### Files OUT of scope
- Full-text content search (#2/#63) — unchanged; "Open Search" still routes to it.
- Bookmarks tab — no filter (only Contents).
- TOC building / `TOCProvider` — unchanged (the filter is pure over loaded `tocEntries`).
- Foliate/AZW3 TOC source — unchanged (the filter is format-agnostic over `[TOCEntry]`).

## Prior art / precedent / rejected alternatives

- **Precedent**: `SearchTextNormalizer.normalize` (diacritic-fold + CJK segmentation) + `SearchTokenizer` already exist for FTS.
- **Rejected — reuse `SearchTextNormalizer.normalize` for the highlight**: `normalize` is NOT length-preserving (NFKC compatibility mapping + ligature expansion "ﬁ"→"fi"; CJK segmentation inserts spaces), so match ranges computed on the normalized string do NOT map back to the original title — the highlight would tint the wrong characters. Foundation `range(of:options:[.caseInsensitive,.diacriticInsensitive], range:, locale: nil)` returns ranges in the ORIGINAL string and is the idiomatic, mapping-safe choice. The plan uses it for BOTH the predicate and the highlight so they never disagree.
- **Matching-contract narrowing (Gate-2 M1)**: Foundation case+diacritic-insensitive substring is NOT identical to `SearchTextNormalizer`, which additionally does **NFKC compatibility mapping** — so full-width Latin (`ＣＡＦＥ`) and ligatures (`ﬁ`) fold under the FTS search path but NOT under this filter. **This divergence is ACCEPTED and in the contract**: the TOC filter is a lightweight title narrower, and its load-bearing case (the *why* of #94) is **CJK exact-substring** (剑 → exact, works identically), plus ASCII case + Latin diacritics (Café/cafe, works). Full-width/ligature normalization is explicitly **out of scope** for the title filter (rare in chapter titles; a user can fall back to "Open Search" for FTS). Documented in the `TOCTitleFilter` header + this plan; the design note intent (case-insensitive, diacritic-folded, CJK substring) is met. `locale: nil` is passed to avoid Turkish-I-style locale surprises.
- **Precedent — designed surface**: `TOCSheetV2` artboard + the in-text-highlight tint/underline vocabulary (feature #68 / #60).

## Work items

Single WI (Small feature, 1 PR):
- **WI-1 (behavioral)** — `TOCTitleFilter` (pure) + `TOCFilterField` + TOCSheet wiring + the row match-highlight. Est. PR size: ~M (one pure-logic file + one field view + two view edits + tests).

## Test catalogue

- **NEW `vreaderTests/Views/Reader/Annotations/TOCTitleFilterTests.swift`** (Swift Testing, pure):
  - `matches`: empty query → all; case-insensitive ("DARCY" matches "Mr. Darcy"); diacritic-insensitive ("cafe" matches "Café"); CJK single-char ("剑" matches "天劍" only if it contains 剑 — use a real CJK fixture); no-match.
  - `matchRanges`: single occurrence; MULTIPLE occurrences ("the" in "The other theory" → all 2+, non-overlapping); CJK occurrence; empty/whitespace query → []; query longer than title → [].
  - `filtered`: narrows a list; preserves order; empty query → identity; no-match → [].
  - Edge: query with leading/trailing whitespace (trim); a title shorter than the query; an empty-title entry; mixed Latin+CJK title.
- **View-behavior / wiring (Gate-2 M3 — these are the codebase-likely regressions)**: make the filtered model + derivations PURE so they are unit-testable without rendering:
  - `TOCTitleFilter.filtered` returns `(index, entry)` pairs — test that the **original index is preserved** under filtering (filter out earlier entries, assert surviving pairs keep their original indices → chapter ordinals + current-row stay correct).
  - **Current-row under filter**: a pure helper/derivation `isCurrent = (pair.index == activeEntryIndex)` — test that filtering does not move the current marker (the active entry, when it survives the filter, still reports current by its original index).
  - **Count label derivation** (`N of M chapters` / `No matches` / hidden) — a pure helper, tested.
  - **No-match CTA**: assert the no-match branch surfaces the `onOpenSearch` CTA (testable via the branch predicate `visible.isEmpty && !trimmedQuery.isEmpty`).
  - **Clear-filter restore**: the `filterQuery → ""` transition predicate that re-triggers the scroll — a pure check, tested.
- The TextField focus + the `AttributedString` highlight RENDERING are not pixel-tested (rule 10); the match-range INPUT to the highlight (`TOCTitleFilter.matchRanges`) is fully tested.

## Risks + mitigations

- **R1 — highlight range mapping** (the main risk): covered by using Foundation original-string ranges (above). Test multi-occurrence + diacritic + CJK explicitly.
- **R2 — performance on a 142-chapter (or larger) list**: the filter is O(N·title-length) per keystroke; trivial for hundreds of entries. No debounce needed at this scale; if a >1000-entry book stutters, add a tiny debounce (out of scope unless measured).
- **R3 — TOCSheet 300-line guard**: extract the filter wiring to a support file.
- **R4 — `.diacriticInsensitive` locale quirks**: chapter titles are short; acceptable. Note the CJK path is exact substring (no folding), which is the design intent.

## Backward compat

Pure additive UI on the Contents tab. Empty query = today's behavior exactly (all entries, current-row pinned, auto-scroll). No persistence, no data/schema change. Older books with no/short TOC: the field shows; filtering a 1-entry TOC is a no-op but harmless.

## Acceptance criteria

1. Typing in the Contents filter narrows the chapter list to title-matching entries, live, case/diacritic-insensitive, CJK substring (剑 narrows a CJK TOC).
2. The live count reads "N of M chapters" while filtering, "No matches" on empty result.
3. Matched substring is tinted (all occurrences) in each visible row; the current-chapter row keeps accent+bold under the tint.
4. No-match offers the "Open Search" escape hatch to full-text search.
5. Clearing the field restores the full list + the default current-row pin/auto-scroll.
6. Bookmarks tab unaffected; no regression to TOC navigation (tap a filtered row → navigates).

## Revision history / Audit fixes applied

- **Gate-2 round 1** (Codex `019e980c`, verdict NEEDS REVISION — 2 High + 3 Medium):
  - **H1** filtered rows would renumber + `isCurrent` would land wrong → `TOCTitleFilter.filtered` now returns `(index, entry)` carrying the ORIGINAL index; rows derive ordinal + current-state from it.
  - **H2** filter field would scroll away inside the single outer scroll → restructured to `VStack { TOCFilterField; ScrollViewReader{list} }` (field pinned outside the scrolling list).
  - **M1** Foundation matching diverges from `SearchTextNormalizer` NFKC (full-width/ligatures) → divergence ACCEPTED + documented; contract narrowed (CJK exact + ASCII case + Latin diacritics in scope; NFKC out of scope; `locale: nil`).
  - **M2** clearing the filter would not re-fire the current-row auto-scroll → added explicit re-scroll on the `filterQuery → ""` transition.
  - **M3** tests missed view-level regressions → added pure-testable derivations (original-index preservation, current-row-under-filter, count label, no-match CTA predicate, clear-restore predicate).
- **Gate-2 round 2** (Codex `019e9811` — H1/M1/M2/M3 confirmed resolved; 1 High + 1 Medium remained):
  - **H2 (still)** plan misidentified the scroll container → corrected: the real scroll is the SINGLE outer `ScrollView` (`:100-105`) wrapping both tabs; fix is to SPLIT it by tab (Contents = pinned field + its own `ScrollViewReader{ScrollView{list}}`; Bookmarks = its own `ScrollView`).
  - **Medium (new)** `private filterQuery` is unreadable from a `TOCSheet+Filter.swift` extension → made `@State var filterQuery` non-private, matching the existing `selectedTab`/`bookmarkVM` extension-read pattern.
