# #1517 · TOC filter field (Feature #94)

> Resolves needs-design [#1517](https://github.com/lllyys/vreader/issues/1517) — the visible affordance for **Feature #94** (Filterable TOC).
> Source of truth: `VReader TOC Filter Canvas.html` (every state × themes). Components in `toc-filter-artboards.jsx`. Transcript: `chats/chat21-toc-filter-1517.md`. Companion to `vreader-annotations.jsx → TOCSheetV2`.
> Status: **design landed — implementation deferred** (recorded, not built; Swift held for a separate go-ahead).

## Decision (binding) — a filter field pinned at the top of the Contents tab

A search/filter field pinned above the chapter list in the **Contents** tab of the TOC sheet (`TOCSheet`). As the user types, the already-loaded TOC entries narrow to titles that match — **case-insensitive, diacritic-folded, CJK-aware substring**. Pure **client-side** filter over the loaded entries; it does **not** hit the full-text content search (#2/#63), which the existing **"Open Search"** CTA still owns.

- **Live result count** in/under the field — `"N of M chapters"`, or `"No matches"` — so the user knows the filter is working before scrolling.
- **Match highlighting**: the matched run inside each title gets a **15% accent tint + 40% accent underline** (the in-text-highlight vocabulary, scaled to inline type). **All** occurrences in a title are marked, not just the first. The current-chapter row keeps its accent ink + bold, and the match tint composes on top of it.
- **Pinned current row** + the Contents/Bookmarks tab toggle are preserved.

## States covered (per the issue)

1. **Default** — empty query, all entries.
2. **Filtering · results** — narrowed list, matched substring tinted (single occurrence, and short query like "the" marking every occurrence).
3. **No-match** — empty state + a full-text **escape hatch** ("Open Search" → the content search).
- **CJK unlock** — typing one character (剑 "sword") narrows 142 chapters to the handful containing it: no spaces, no word boundaries, no romanization. This is *why* #94 exists.

## Production wiring (deferred — do NOT build without go-ahead)

- Add the filter field + live count to `TOCSheet` (Contents tab). The filter is a pure client-side predicate over the loaded `tocEntries`; reuse `SearchTextNormalizer`/`SearchTokenizer` for diacritic-folding + CJK substring matching (no FTS).
- Title rows render the matched-substring tint (all occurrences); current-chapter accent + bold composes underneath. No-match state offers the existing "Open Search" CTA. Rule 51 satisfied by this note + canvas.
