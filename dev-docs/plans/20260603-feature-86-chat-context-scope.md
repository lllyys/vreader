# Feature #86 — Expand AI reading scope & sources (Chat tab)

Plan for the first, implementable slice. Status entry-gate: row `TODO` + no
prior plan → this is Gate 1.

## Problem

The in-reader AI Chat reads only a fixed ~2500-char `.section` window around the
current reading position (`ReaderAICoordinator.currentTextContent` → the chat's
`bookContext`). Questions about "this chapter" fail when the relevant text is
outside that window. The feature row asks for three escalating capabilities:

1. **current chapter at least** — chat context covers the whole current chapter.
2. **annotation sources** — the AI can read notes / highlights / bookmarks.
3. **read everywhere on demand** — pull any chapter / the whole book (scope
   selector and/or tool-use/RAG) with a map-reduce token strategy.

## Scope of THIS plan (WI-1 only)

**WI-1 — Chapter-scoped chat context (part 1).** Route the Chat tab's
`bookContext` through the existing `.chapter` scope instead of the `.section`
window. Pure logic, **no new UI** (Rule 51: nothing to design — the Chat tab is
visually unchanged; only the context text it reads expands).

### Files OUT of scope (deferred)

- **Part 2 (annotation sources)** and **Part 3 (scope selector / RAG)** — these
  add user-facing controls (a scope selector chip row on the Chat tab, a sources
  toggle). Those are **new UI surfaces**; per Rule 51 they require a committed
  `dev-docs/designs/...` bundle before implementation. They are split into
  follow-up WIs and, when reached, each files a `needs-design` issue if no design
  exists. NOT in WI-1.
- `AISummaryTabView` / the #69 summary scope chips — unchanged.
- `AIContextExtractor` / `SummaryScopeResolver` — **reused as-is**, not modified.

## Surface area (WI-1) — v2: single-refresh path (Gate-2 round-1 fix)

Gate-2 round 1 found the v1 "rewire 2 of N `bookContext` writes" approach broken:
there are **four** live `chatViewModel.bookContext = …currentTextContent` writes
(coordinator `setupIfNeeded` ~L90, coordinator `loadText` ~L148,
`ReaderContainerView+Sheets.swift:152`, `ReaderContainerView.swift:556`), and the
locator-change write at `:556` would **revert chat to section after every
scroll**. And `tocEntries` arrives on independent host paths that can land
**after** text loads. Both are fixed by funnelling through one idempotent method.

- `vreader/Views/Reader/ReaderAICoordinator.swift`
  - Add `var tocEntries: [TOCEntry] = []` — the host's TOC, synced by the
    container.
  - Add a computed `var chatContext: String` — like `currentTextContent`, but
    resolves the current chapter via
    `SummaryScopeResolver.chapterBounds(for: currentLocator, tocEntries:,
    totalTextLengthUTF16: loadedTextContent?.utf16.count ?? 0)` and extracts at
    `scope: .chapter` with `maxUTF16: AIContextBudget.defaultMaxUTF16` (12_000).
    A `nil` chapterBounds (EPUB / non-char-offset TOC, or no locator) **degrades
    to `currentTextContent` (`.section`)** — EPUB chat unchanged, no regression.
  - Add `func refreshChatContext() { chatViewModel?.bookContext = chatContext }`
    — idempotent; recomputes from current `loadedTextContent` / `currentLocator`
    / `tocEntries`. This is the SINGLE place chat `bookContext` is assigned.
  - **Replace ALL four** scattered `bookContext = …currentTextContent` writes
    with a `refreshChatContext()` call (`setupIfNeeded`, `loadText`,
    `+Sheets:152`, `ReaderContainerView:556`).
  - `currentTextContent` (`.section`) is **unchanged** — used by the Translate
    "section" path and as the degrade target.
- `vreader/Views/Reader/ReaderContainerView{,+Sheets}.swift` — wherever the
  container sets `tocEntries` (`ReaderContainerView.swift:547`,
  `+Sheets.swift:~189`) AND the Foliate TOC callback
  (`FoliateTOCAvailableObserver`), also `resolvedAICoordinator.tocEntries =
  entries` then `resolvedAICoordinator.refreshChatContext()` — so a TOC that
  lands AFTER text upgrades the chat context immediately. Likewise after the
  locator update at `:554` (call `refreshChatContext()` instead of the inline
  bookContext write at `:556`), and after each `loadedTextContent` set
  (`+Sheets:125` cache-hit + `:151`).

## Prior art / precedent

Feature #69 (summary scope chips) already built the entire scoped-extraction
stack: `SummaryScopeResolver.chapterBounds(...)`, `AIContextExtractor`'s
`scope: .chapter` path (clamps an over-budget chapter to a `maxUTF16` window
centered on the locator, snapping to scalar boundaries), and `ChapterBounds`.
WI-1 is pure reuse — it routes the chat's context through that stack. No new
extraction logic.

## Work-item sequencing

- **WI-1 (this PR, behavioral)** — chapter-scoped chat context. ~1 small PR.
- WI-2+ (future, needs-design) — annotation sources; scope selector; on-demand
  retrieval / RAG + map-reduce. Each files `needs-design` per Rule 51 if the
  Chat-tab control isn't yet in a committed design bundle.

## Test catalogue (WI-1)

`vreaderTests/Views/Reader/ReaderAICoordinatorChatContextTests.swift` (or extend
an existing coordinator test):

- `chatContext_withChapterBounds_returnsChapterNotSectionWindow` — a TXT/MD-shaped
  TOC (char-offset locators) + a long chapter → `chatContext` returns the chapter
  span (longer than / different from the 2500 `.section` window).
- `chatContext_nilChapterBounds_degradesToSection` — empty TOC (EPUB-shaped) →
  `chatContext == currentTextContent` (the section).
- `chatContext_noLocator_degradesToSection` — `currentLocator == nil` → section.
- `chatContext_overBudgetChapter_clampsToBudget` — a chapter longer than 12_000
  UTF-16 → result length ≤ budget (the extractor's centered-window clamp).
- `chatContext_noLoadedText_returnsFallback` — empty `loadedTextContent` → the
  same fallback string `currentTextContent` returns.

## Risks + mitigations

- **Larger token usage** — a 12_000-UTF16 chapter vs 2500 raises per-request
  tokens. Mitigation: the extractor already clamps `.chapter` to
  `AIContextBudget.defaultMaxUTF16`; reuse that same cap (no unbounded growth).
- **EPUB chapter bounds unresolvable** — EPUB TOC entries lack `charOffsetUTF16`,
  so `chapterBounds` returns nil. Mitigation: degrade to `.section` (today's
  behavior) — no regression, and the feature still lands for TXT/MD.
- **`tocEntries` arrives after text (ordering)** — Gate-2 round-1 High: text
  often loads before the TOC arrives via independent host paths, so a single
  setup/load-time assignment would never upgrade. Fixed by the v2 single-refresh
  design: the container calls `refreshChatContext()` on EVERY state change —
  text load, locator change, AND `tocEntries` arrival (incl. the Foliate TOC
  callback) — so a late TOC upgrades the chat context the moment it lands, and a
  scroll never reverts it (every locator change re-resolves the chapter, not a
  section snapshot).

## Backward compat

- EPUB chat: unchanged (degrades to `.section`).
- Translate "section" context: unchanged (`currentTextContent`). (Summarize uses
  `fullTextContent` + scoped extraction, not `currentTextContent` — Gate-2
  round-1 Low correction.)
- No schema, no persistence, no notification changes. No migration.

## Revision history

- **v1** (2026-06-03) — initial plan.
- **v2** (2026-06-03) — Gate-2 Codex audit round 1 (`/tmp/feat86-planaudit.txt`):
  confirmed all model assumptions (`SummaryScopeResolver.chapterBounds`,
  `.chapter` clamp, `AIContextBudget.defaultMaxUTF16 = 12000`, `TOCEntry`).
  Found 2 High + 1 Low — all fixed in v2:
  - **High (incomplete rewiring)** → single idempotent `refreshChatContext()`
    replaces all four `bookContext` writes; the locator-change site now
    re-resolves the chapter instead of reverting to a section snapshot.
  - **High (TOC ordering)** → explicit host→coordinator `tocEntries` sync +
    `refreshChatContext()` on TOC arrival (incl. the Foliate callback), so a TOC
    that lands after text upgrades the chat context immediately.
  - **Low (rationale)** → corrected: `currentTextContent` is kept section-scoped
    for Translate + the degrade target, not "Summarize".
