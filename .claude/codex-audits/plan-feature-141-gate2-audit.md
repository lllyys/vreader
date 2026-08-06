---
gate: 2
kind: plan-audit
feature: 141
plan: dev-docs/plans/20260806-feature-141-android-filterable-toc.md
rounds: 2
final_verdict: pending-round-2
---

# Gate-2 plan audit — feature #141 (Android filterable TOC)

Rule 47 Gate 2 requires an independent audit. This artifact exists because feature #152's
round 1 found that a *previous* Gate-2 audit's findings were unrecoverable — the plan said
"6 High + 8 Medium + 2 Low remain open" and the list existed nowhere in the repo, so no one
could tell whether a later draft had addressed them or silently dropped them. Gate 4 already
commits its audit log; Gate 2 now does too.

## Method — two independent auditors, deliberately different

- **Static**: Codex `gpt-5.5`, effort `high`, read-only, via `scripts/run-codex.sh` (rule 53).
- **Empirical**: a separate agent that implemented the plan's §5.1 algorithm in Java, ran ~90
  hostile inputs on JDK 17, **and ran the real iOS `TOCTitleFilter.swift` against the same
  inputs**, plus a desktop benchmark over 1 859 realistic CJK titles.

The split earned its cost: they **disagreed**, and the disagreement was the most useful output
(see "Disproven by measurement").

## Round 1 — `block-recommended`

| # | Sev | Finding | Disposition in v2 |
|---|---|---|---|
| 1 | High | Match ranges computed on the collapsed title, rendered from the raw one. Measured: `range [0..6]` selects `"Chapter"` on display, `"   Chap"` on raw. Not limited to line-break titles — `collapseLineBreaks` trims *every* title. Mirror case is an `AnnotatedString` bounds **crash**. | Fixed structurally: `TocTitleFilter.displayTitle(entry)` is the sole producer, owns the `"Untitled"` fallback; `TocContentsRow` takes `title: String` **required**; `boldedSnippet` clamping so the mirror case degrades to a wrong tint, not a crash. |
| 2 | High | The "copied verbatim from iOS" folding contract is **false on 3 of the 4 exclusions it names** — measured against real iOS: `ﬁ`→`fi` MATCH, `Straße`→`strasse` MATCH, `ΟΔΟΣ`→`οδός` MATCH, all no-match on the plan's algorithm; Arabic hamza **over**-matches. Full-width exclusion is the one true claim. | Claim retracted in §3, measured table inserted. Algorithm → per-code-point ICU `UCharacter.foldCase(String, FOLD_CASE_DEFAULT)`, closing ß + final sigma with the index map intact. Residuals pinned as named tests; added `caseFold_usesFullFoldingNotSimple` because the `foldCase(int, boolean)` overload does *simple* folding. |
| 3 | Med | Perf budget aimed at the wrong risk. Desktop: keystroke **0.035 ms** warm vs an 8 ms budget (~200×); one-time fold **18.66 ms** vs 50 ms (~2.7×) — and `lazy(NONE)` defers it *into* the first keystroke. `displayTitles` eager map (2.94 ms × every sheet open) unbudgeted. | Three separate budgets (A visible rows / B corpus fold ≤120 ms / C keystroke ≤8 ms); eager map deleted; explicit note that **a debounce delays the fold, it does not reduce it**; off-thread fallback pre-designed; cost test moved WI-6 → WI-1. |
| 4 | Med | `foldedQuery.isEmpty()` diverges from iOS, which gates on the **trimmed** query. Measured: a lone combining acute → iOS "No chapters match", plan → full unfiltered list. | Gating moved to `trimmedQuery`. |
| 5 | Med | `IntRange` inclusivity never stated; `originalRange(foldedStart, foldedEndExclusive): IntRange` mixes conventions; tests assert range **count**, not bounds. | Convention stated (inclusive, matching #133); signature → `originalRange(foldedFirst, foldedLast)`; a test asserts hand-computed exact `(first, last)`. |
| 6 | Med | Stale model fact: `ReaderTheme` called a 4-case enum; it has **five** (`Paper, Sepia, Dark, Oled, Photo`). Orchestrator-confirmed at `ReaderTheme.kt:14-26`. | Corrected; tests iterate `ReaderTheme.entries`. |
| 7 | Med | Scroll-on-filter keyed only empty/non-empty → refining `Chapter` → `Chapter 1999` leaves a one-row result at a stale offset. | Keyed on `trimmedQuery` + a `wasFiltering` flag; connected test added. |
| 8 | Low | False "(verified)" claim that Kotlin `trim()` does not strip NBSP. It does — `Char.isWhitespace()` is `isWhitespace \|\| isSpaceChar`, proven by disassembling the shipped stdlib. | Rationale corrected, redundant predicate dropped, the Java-`trim()` trap kept and pinned. |
| 9 | Low | Two folding paths (`filtered` consumes pre-folded; `matchRanges` re-folds per row) that must never disagree. | `matchRanges(folded: FoldedTitle, …)` — exactly one fold per title. |
| 10 | Low | Two overstated citations: the design's "~2k entries" ceiling presented as corroboration (real corpus 1 859; existing connected test already runs 2 000), and "Design gaps — nothing is missing" (the design's no-TOC state has copy + an "Open Search" CTA; Android renders plain "No contents"). | Both softened; §2.2 → "no #141-blocking gap", `NoTocEmpty` fidelity gap recorded and routed to the orchestrator. |

### Disproven by measurement — recorded so it is not re-raised

The **static** auditor claimed the folded→original index map would mis-highlight Hangul, emoji
modifiers/ZWJ, and combining marks. The **empirical** auditor implemented the scheme and measured
exactly those cases across ~90 inputs with **zero wrong ranges** — `İ` at position 0 and mid-title,
Hangul NFD expansion before/after/inside a match, jamo vs precomposed both directions, decomposed
`e`+U+0301 with the match ending on and spanning the mark, stacked marks, surrogate pairs
before/inside/as-query, Arabic harakat, Hebrew niqqud, orphan combining marks, partial-expansion
jamo queries, CJK substrings with no word boundaries, `"aa"` in `"aaaa"` → exactly 2 ranges.

The `starts`/`ends` scheme including "extend `ends` over immediately-following stripped marks" is
sound. **Not actioned**, by decision. Re-raising it requires a concrete input and the exact wrong
indices it produces.

### Rejected remedy

The static auditor recommended reusing `SearchTextNormalizer` (NFKC → ICU `foldCase` → diacritic
strip). **Not a drop-in**: it is length-changing (destroys the index map the measurement just
validated), recomposes to NFC, CJK-segments, and NFKC-folds full-width — which iOS's TOC filter
does **not**. Cited in the plan with those three reasons.

### Verified TRUE in round 1 — all seven wiring claims

Production surface is `TocBookmarksSheet`; `TocContentsSheet(...)`'s only caller is
`androidTest/.../TocContentsSheetTest.kt:185`; the four production call sites are exact;
ordinal-from-position, highlight-from-position, the `LazyListState` key, and render-time line-break
collapsing all confirmed; iOS #94's `visibleEntries` is a plain computed property with **no**
debounce anywhere in the file. Largest real TOC corroborated at **1 859** (`黑暗血时代.txt`);
`道诡异仙` counts 1 042 navPoints; #138's ~30 695 is a **page** count and was correctly not used.

### Author-found defect during revision

Not from either auditor: `filtered(...)` took `foldedCorpus.value`, which would have forced the
lazy fold on **every sheet open** — reinstating the cost-A regression one line below its deletion.
Now takes `Lazy<List<FoldedTitle>>` and returns from the blank-query branch before touching
`.value`, with `blankQuery_neverForcesTheFold` asserting `isInitialized() == false`.

## Round 2 — in progress

Prompt: verify each round-1 finding resolved; evaluate the ICU switch (does `android.icu` exist at
this minSdk, does Robolectric provide it, does per-code-point full folding preserve the index map
when a fold expands); confirm the `Lazy` change has no other force site; confirm every
`TocContentsRow` call site is updated and that moving the `"Untitled"` fallback breaks no consumer.
Result appended on completion.
