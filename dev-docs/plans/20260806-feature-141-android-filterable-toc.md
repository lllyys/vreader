# Feature #141 — Android filterable TOC (parity phase 4, box G1)

**Gate 1 plan.** Status on write: `TODO` → `PLANNED` once Gate 2 (independent audit) is clean.
Platform: `android-app`. iOS parity: feature #94 (`VERIFIED` 2026-06-06, v3.59.0).
Deps `feat:#139` (TXT/MD TOC providers) and `feat:#140` (AZW3 TOC) are both `VERIFIED` — checked in
`docs/features.md:191-192`.

Design bundle (committed, rule-51 clean):
`dev-docs/designs/vreader-fidelity-v1/project/toc-filter-artboards.jsx` (667 lines) +
`VReader TOC Filter Canvas.html` (a 59-line loader shell — all substance is in the `.jsx`).

---

## 1. Problem

A book's Contents sheet is a flat scroll. On Android that list is now long for real books: #139's TXT
heading detector yields **1 859 entries** on the repo's real 14 MB CJK fixture `黑暗血时代.txt`
(`dev-docs/plans/20260804-feature-139-android-txt-md-toc.md:676`), and the large-TOC connected test
already exercises 2 000 rows (`TocContentsLargeTocTest.kt:329 LARGE_COUNT = 2_000`). Finding
"第一千二百章" in that list means scrolling past a thousand rows. The user needs to type a few
characters and have the list narrow.

iOS solved this in #94. Android has no filter affordance at all: `TocContentsSheetContent`
(`android/app/src/main/kotlin/com/vreader/app/reader/nav/TocContentsSheet.kt:97`) renders header →
rule → `LazyColumn` of rows, with no text field anywhere in the `nav/` package.

Non-goal: full-text content search. That is #133's `InBookSearchSheet`, reached from the top-bar
Search icon. This feature filters **already-loaded TOC titles only**.

---

## 2. Rule 51 — design coverage

The artboards are a *binding contract* (§9 "Implementation notes" spec card). Per-surface mapping:

| # | Design surface / state | Artboard | Built by | Notes |
|---|---|---|---|---|
| 1 | Filter field at rest (filled pill, 38pt tall, 11pt radius, leading magnifier, placeholder "Filter chapters") | `state-default`, `canonical-default`; `TOCFilterField` L270-313 | WI-2 | dp on Android; the pill fill is `ink @ 0.045 light / 0.07 dark` (L278) |
| 2 | Focused field (accent ring `0 0 0 2px accent`, accent magnifier, caret) | `canonical-filtering`, `theme-*` (all four `focused`) | WI-2 | ring = 2dp accent border |
| 3 | Clear (✕) affordance, shown only when non-empty | `TOCFilterField` L290-298 | WI-2 | filled circular chip; Android wraps it in a 48dp target (the #133 `inbook-search-clear` precedent) |
| 4 | "Cancel" text button, shown on focus | `TOCFilterField` L300-302, post-it L411 | WI-2 | clears the query + drops focus (iOS `TOCFilterField.swift:47-50`) |
| 5 | Live count line: "N of M chapters" / "No chapters match" | `TOCFilterField` L304-310 | WI-2 | hidden when query empty |
| 6 | Placement: **below** the Contents/Bookmarks segmented control, inside the header stack, pinned (does not scroll) | §7 `place-chosen`, `place-pinned`; rejected alternative `place-rejected` | WI-4 | Android already satisfies this structurally — see §4 |
| 7 | Matched-run tinting: accent @ 15 % background + accent @ 40 % underline, **all** occurrences | §3 `match-single`, `match-short`, `match-detail`; spec card L648 | WI-3 | one accepted deviation, §2.1 |
| 8 | Current-chapter row keeps accent ink + weight-600; the match tint composes on top | §3 subtitle, `MatchDetailCard` | WI-3 | Android's `TocContentsRow` already does accent+SemiBold |
| 9 | Pinned "READING" row when the query filters the current chapter out | §5 `current-pinned`; `PinnedCurrentRow` L317-331 | WI-4 | accent tint bg, uppercase READING badge, title, `p.N`, hairline below |
| 10 | Current chapter survives the filter → no pinned row, normal highlight | §5 `current-visible` | WI-4 | |
| 11 | No-match empty state: dashed-frame + magnifier art, "No chapters match", body quoting the query, outlined **"Search full text"** CTA | §2 `state-nomatch`; `NoMatchEmpty` L333-356 | WI-4 (state) + WI-5 (CTA wiring) | |
| 12 | No-TOC book → filter field **suppressed** (not disabled) | §6 `notoc`, spec card L656 | WI-4 | already structurally true — §4 |
| 13 | Long-CJK motivating case (142-chapter novel, single-char 剑 query, two-char 故人, 第十 chapter-number query) | §4 `cjk-*` | WI-1 tests + WI-6 | |
| 14 | Reader themes (the artboards show paper / sepia / dark / OLED) | §8 `theme-*` | WI-2/WI-3 | **`ReaderTheme` has FIVE cases** — `Paper, Sepia, Dark, Oled, Photo` (`reader/settings/ReaderTheme.kt:22-26`); #129 added `Photo` for iOS `ReaderThemeV2` parity. Tests iterate `ReaderTheme.entries`, never a hardcoded four. (Corrected at Gate-2 r1 — the v1 plan said "4-case enum".) |
| 15 | Accessibility: field labelled "Filter chapters", count announced as a value, clear button labelled | spec card L660 | WI-2 | `contentDescription` + `semantics` |

### 2.1 Accepted deviations (documented, not invented UI)

1. **Underline colour.** The design wants the matched run underlined in `accent @ 40 %`,
   independent of the run's foreground. Compose's `SpanStyle` has no per-span underline colour —
   `TextDecoration.Underline` inherits the span's `color`. We render
   `SpanStyle(background = accent.copy(alpha = 0.15f), textDecoration = TextDecoration.Underline)`,
   so the underline is ink on normal rows and accent on the current row. The design's *rationale*
   (a colour+underline treatment that does not collide with the current-chapter weight) is
   preserved; only the underline's alpha/hue differs. Do **not** hand-draw an underline to close
   this — that would be inventing a treatment.
2. **Sheet header extras present in this bundle but absent from Android's #132 sheet** — a close
   (✕) button in the header (`ContentsSheet` L195-202), per-tab count badges on the segmented
   control (L218-221), and an inline uppercase "Reading" label on the active row (L255). Android's
   sheet was transcribed from a *different* bundle (`vreader-panels.jsx` `TOCSheet`), which has
   none of these. They are **out of #141's scope** (they change the non-filtering sheet too) and
   are recorded here as a cross-bundle discrepancy, not built.

### 2.2 Design coverage — no #141-blocking gap, but one pre-existing fidelity gap

Every surface **this feature builds** is depicted, so **no `needs-design` issue is required for
#141.** That is a narrower claim than v1's "nothing is missing" (Gate-2 r1 finding 10b): the bundle
does depict something Android does not have.

- **Pre-existing fidelity gap (not #141's to close, not filed here).** The bundle's `NoTocEmpty`
  (§6, `toc-filter-artboards.jsx:358-376`) shows a full "No table of contents" empty state — dashed
  frame art, explanatory body copy, and a filled **"Open Search"** CTA. Android renders
  `TocEmptyState` = a plain centered "No contents" string (`TocSheetRows.kt:126-144`). This is a
  #132-era transcription gap, unchanged by #141 (the filter field is suppressed in that branch
  either way, which is what the design asks for). Recorded here for the orchestrator to route; per
  the brief this plan files nothing.
- **Not a design gap:** per-format search availability means the §2 no-match CTA cannot always be
  offered (WI-5). That is a capability gate — the repo's established "no dead controls" posture —
  not missing design.

---

## 3. Prior art / project precedent / rejected alternatives

### iOS #94 (`vreader/Views/Reader/Annotations/`) — the parity reference

| iOS file | What it does | Android counterpart |
|---|---|---|
| `TOCTitleFilter.swift` (152 lines) | pure `matchRanges` / `matches` / `filtered` / `isActiveFilteredOut` + `TOCFilterCountLabel` + `TOCFilterState` | new `nav/TocTitleFilter.kt` (WI-1) |
| `TOCFilterField.swift` (123) | the pinned pill + count line + focused Cancel | new `nav/TocFilterField.kt` (WI-2) |
| `TOCSheet+Filter.swift` (191) | derivations, scroll ladder, no-match body, filtered list | wiring inside `TocContentsSheet.kt` (WI-4) |
| `TOCSheetRows.swift` | `TOCContentsRow(matchRanges:)` + `PinnedCurrentRow` | `TocSheetRows.kt` edit (WI-3) + new `nav/TocFilterRows.kt` (WI-4) |

**Matching — match iOS's *observable* semantics, not its API.** iOS uses
`String.range(of:options:[.caseInsensitive, .diacriticInsensitive], range:, locale: nil)` iterated
to exhaustion (`TOCTitleFilter.swift:52-74`), giving ranges in the **original** string. Kotlin/Java
has no `.diacriticInsensitive` compare option, so Android must fold explicitly and map back.

**v1 of this plan claimed the contract was "copied verbatim" and that "use NFD, never NFKC
reproduces iOS exactly". That claim was false and is retracted** (Gate-2 r1 finding 2). It was
verified only on the JDK side. Foundation's option pair is **ICU collation at a reduced strength**,
not "lowercase then NFD minus non-spacing marks", and the two disagree on three of the four
exclusions v1 named. Measured by the Gate-2 empirical auditor, running real `TOCTitleFilter.swift`
and v1's §5.1 algorithm over identical inputs:

| Title + query | iOS | v1 §5.1 (`lowercase()` + NFD − Mn) | This plan (§5.1 rev2, ICU `foldCase`) |
|---|---|---|---|
| `Straße des Lichts` + `strasse` | MATCH | no match | **MATCH** — closed |
| `Οδός Ονείρων` + `ΟΔΟΣ` | MATCH | no match | **MATCH** — closed |
| `The ﬁrst Chapter` + `fi` | MATCH `[4..4]` | no match | no match — **accepted divergence** |
| `الأول` + `الاول` | no match | MATCH (over-match) | MATCH — **accepted divergence** |
| `ＣＡＦＥ Royale` + `cafe` | no match | no match | no match — agrees |

The Greek row is the user-facing one: per-code-point `lowercase()` maps `Σ`→`σ` but leaves final
sigma `ς` alone, so a Greek chapter ending in `ς` is unreachable by the word's uppercase or medial
spelling. That is a defect of *lowercasing*, which is context-sensitive by design; **case folding is
not** — Unicode case folding maps `ς`, `σ`, and `Σ` all to `σ` unconditionally, and folds `ß`→`ss`.

**Decision — Gate-2 r1 option (b): close the ß/ς gap with ICU full case folding, do NOT adopt
NFKC.** §5.1 swaps per-code-point `String.lowercase()` for per-code-point ICU
`UCharacter.foldCase(…, FOLD_CASE_DEFAULT)`. This is still per-code-point, so the `starts`/`ends`
index map — which the empirical audit measured as correct across ~90 hostile inputs — is untouched.
Costs and residuals, stated plainly:

- **~~Residual 1 — ligatures (`ﬁ`) still do not fold.~~ WITHDRAWN — ERRATUM (WI-1, 2026-08-06).**
  This prediction was **wrong**, and the fix that produced it is what made it wrong. Unicode **full**
  case folding maps U+FB01 → `"fi"` (CaseFolding.txt `F` mapping), so the moment §5.1 swapped
  `String.lowercase()` for ICU `foldCase(…, FOLD_CASE_DEFAULT)` to close ß and final sigma, **it
  closed the ligature too — without NFKC and without touching the index map.** Android therefore
  **AGREES with iOS** here. Orchestrator-verified independently: `"ﬁ".casefold() == "fi"` under the
  same Unicode full-case-folding table ICU uses, while `NFD("ﬁ")` leaves it unchanged (so this is
  the fold, not the normalizer). The shipped test is `ligature_foldsLikeIcuFullCaseFolding`.
  **How it survived**: the residual was written in the same round that chose full folding, carried
  over from the *previous* algorithm's measured table, and no round re-derived it — the empirical
  audit measured the pre-ICU algorithm, and every later round read the residual as settled. Found by
  the WI-1 implementer running it. The auditor confirmed that following the plan's **normative
  algorithm** over its **predicted table** was the correct call.
- **Residual 2 — Arabic `أ`/`ا` over-matches** (Android matches, iOS does not), because NFD+strip-Mn
  removes the hamza (U+0654, category Mn) while ICU collation at Foundation's strength keeps it. For
  a *title narrower* over-matching is the benign direction — the user sees a superset of candidate
  chapters and never loses a row they were looking for. Accepted and pinned by a test.
- **Cost — `TocTitleFilter`'s JVM tests must run under Robolectric.** `android.icu` is a framework
  class; the stub `android.jar` throws "not mocked". Precedent exists and is exact:
  `SearchTextNormalizerTest.kt:16-17` is `@RunWith(RobolectricTestRunner::class)` for this reason,
  and `robolectric:4.13` is already a `testImplementation` dependency
  (`android/app/build.gradle.kts:126`) with `unitTests.isIncludeAndroidResources = true` (`:49-50`).
- **Bonus — the Turkish-I risk disappears.** Case folding is locale-independent *by construction*,
  so there is no locale to pass wrong. The `turkishLocale_doesNotChangeMatching` test stays as a
  regression pin, not as the primary defence.

**Explicitly NOT reused: `search/SearchTextNormalizer.kt`.** It is the right file to cite — same
problem, same ICU `UCharacter.foldCase`, written to mirror iOS — but it is **not a drop-in** for
three reasons: (1) it is NFKC-first (`:38`), which iOS's *TOC filter* deliberately is not, so it
would fold full-width and diverge in the one place Android currently agrees; (2) it recomposes to
NFC at the end (`:64`) and is length-changing overall, which destroys the index map this feature
depends on; (3) it segments CJK by inserting spaces (`segmentCJK`) for FTS tokenization, which is
meaningless for substring matching. `TocTitleFilter` borrows its *technique* (per-code-point
`foldCase` + NFD + drop category `Mn`) and its Robolectric test posture, not its pipeline.

**Deliberate divergences from iOS, declared (a Gate-2 auditor should not read these as drift):**

1. **The no-match CTA carries the query.** iOS calls `onOpenSearch()` with no argument
   (`TOCSheet+Filter.swift:116`) even though the design's §2 post-it and spec card say the query
   should be carried over. Android carries it (`(String) -> Unit`) — the design's behavior.
2. **Ligature and Arabic-hamza matching** — the two residuals in the table above.
3. **The empty-query gate is the TRIMMED query, matching iOS** (this is *removal* of a v1
   divergence — Gate-2 r1 finding 4). v1 gated on the *folded* query, so a lone combining acute
   U+0301 (a dead key, or pasted text) folded to `""` and showed the full 1 859-row list with the
   count line hidden, where iOS shows "No chapters match". Two different screens for one keystroke.
   §5.1/§5.2 rev2 gate on `trimmedQuery`, so a query that survives trimming but folds away is
   "filtering, zero matches" — iOS's behavior exactly.

### Android #133 (in-book search) — the local widget precedent

`search/InBookSearchField.kt:58-150` is the existing reader search field: a rounded pill with
`Icons.Filled.Search`, a `BasicTextField` with a `decorationBox` placeholder, a 48dp-target clear
box, and a "Cancel" whose clickable box is ≥48×48dp. **`TocFilterField` follows this file's
structure** (BasicTextField + decorationBox + 48dp targets + `testTag`/`semantics`) but must NOT
reuse it verbatim: `InBookSearchField` autofocuses on composition (`LaunchedEffect(Unit)
{ focusRequester.requestFocus() }`, L72-75), takes a `bookTitle` placeholder ("Search <title>"),
renders Cancel unconditionally, and has no count line and no focus ring. The TOC filter must not
autofocus (it is the *secondary* affordance in a sheet whose primary job is showing the list, and
an IME popping over the list on every Contents open would be hostile) and must show the accent focus
ring, the "Filter chapters" placeholder, and the count line. So: same idiom, separate composable.

**Debounce precedent:** `InBookSearchViewModel.DEFAULT_DEBOUNCE_MILLIS = 250L` (`:296`) and
`SearchViewModel.DEFAULT_DEBOUNCE_MILLIS = 300L` (`:214`). Both debounce a **database/FTS** round
trip. See §6 for why this feature does not start with one.

### Rejected alternatives

| Rejected | Why |
|---|---|
| **Pre-filter the `entries` list and pass the short list into `TocContentsSheetContent`** | Breaks three things at once: the row ordinal is `index + 1` off the list position (`TocSheetRows.kt:92`), the highlight is `index == currentTocIndex` (`TocContentsSheet.kt:193`), and the lazy list's identity key is `key(tocIdentity, entries.size)` (`:162`) — a shrinking list re-creates `LazyListState` with `initialFirstVisibleItemIndex = currentTocIndex`, an index that no longer exists in the filtered list. iOS hit exactly this at Gate 2 (row #94 notes: "filtered rows would renumber + the current-row marker would land wrong"). We carry the original index instead. |
| **Reuse `search/InBookSearchField` directly** | Autofocus + no count line + no focus ring + "Search <title>" placeholder are all wrong here, and bending it with flags would degrade #133's surface. |
| **Route the filter through a ViewModel with a `StateFlow`** | The sheet has no VM; `TocContentsSheetContent` is a pure function of state (rule 50 §4) and the data is already in memory. A VM adds a lifecycle and a process-death story for a transient field. `rememberSaveable` covers rotation. |
| **Fuzzy / ranked matching** | Spec card L658: "exact substring only, so results stay in chapter order and are predictable on a 500-chapter TOC." |
| **NFKC folding (reuse `SearchTextNormalizer`-style normalization)** | Not length-preserving ⇒ ranges would tint the wrong characters; and it diverges from iOS's documented contract. |
| **Match against the *displayed* fallback string ("Untitled")** | Would make typing "untitled" surface every untitled entry — inventing behavior the design does not describe. A null/blank title simply never matches a non-empty query. |

---

## 4. Verified facts about the current Android code (do not re-derive)

Everything below was read, not assumed.

1. **The production Contents surface is `TocBookmarksSheet`, not `TocContentsSheet`.** The four
   production call sites are `reader/EpubReaderChrome.kt:258` and `:288`, and
   `reader/chrome/ReaderChromeScaffold.kt:231` and `:260` — all `TocBookmarksSheet`. The standalone
   `TocContentsSheet(...)` wrapper (`TocContentsSheet.kt:57`) has **zero** production call sites; it
   survives only in `androidTest`. The tracker row's file pointer ("TocContentsSheet.kt +
   TocSheetRows.kt") is right about where the *body* lives —
   `TocBookmarksSheetContent` composes `TocContentsSheetContent` unchanged for the Contents tab
   (`TocBookmarksSheet.kt:158-165`) — but the sheet a user actually opens is the two-tab one.
2. **The design's placement requirement (§7) is already structurally satisfied.** Because the filter
   field goes inside `TocContentsSheetContent`, and that function is composed *below* `TocTabBar`
   (`TocBookmarksSheet.kt:155-158`) and *outside* the `LazyColumn` (which starts at `:167`), the
   field is automatically (a) below the segmented control, (b) scoped to the Contents tab only —
   the Bookmarks tab body is a different branch of the `when` — and (c) pinned, not scrolling.
3. **The no-TOC branch already suppresses everything below the header**:
   `if (entries.isEmpty()) { TocEmptyState(theme); return@Column }`
   (`TocContentsSheet.kt:136-139`). Placing the field after that guard gives design §6 ("suppress,
   don't disable") for free. Additionally, the scaffold hides the Contents control entirely for an
   empty TOC (`ReaderChromeScaffold.kt:160-162`), so this branch is near-unreachable in production.
4. **Titles are normalized at render time, per visible row**:
   `val row = remember(entry) { entry.withoutEmbeddedLineBreaks() }` (`TocContentsSheet.kt:188`),
   backed by `private fun String.collapseLineBreaks()` (`:241-261`), which collapses whitespace runs
   spanning a line break and trims the ends. **This is load-bearing for #141**: a TXT rule can match
   across a line terminator, so the raw title and the displayed title differ. If the filter matched
   the *raw* title, its ranges would be offset against the *displayed* string and tint the wrong
   characters. WI-1 therefore normalizes **once**, up front, and both the predicate and the renderer
   consume the normalized title. (`collapseLineBreaks` becomes `internal`; no behavior change.)
5. **`TocEntry.title` is `String?`** (`nav/TocEntry.kt:24-30`); the row falls back to `"Untitled"`
   for display (`TocSheetRows.kt:61`).
6. **The lazy list is positioned once per (book, TOC)** via
   `key(tocIdentity, entries.size) { rememberLazyListState(initialFirstVisibleItemIndex = …) }`
   (`TocContentsSheet.kt:161-166`), with an explicit contract comment that it deliberately does not
   follow later `currentTocIndex` changes. Keeping `entries` as the **full** list preserves that
   identity through filtering; the filter must drive scrolling explicitly (WI-4).
7. **The reader hosts.** `ReaderChromeScaffold` has three call sites —
   `Azw3ReaderChrome.kt:161`, `PdfReaderScreen.kt:169`, `TxtReaderActivity.kt:1593` — plus EPUB's
   bespoke `EpubReaderChrome.kt` (a Readium fragment sits under the chrome, so it cannot use the
   scaffold; `ReaderChromeModel.kt` header). **PDF passes `tocEntries = emptyList()`**
   (`PdfReaderScreen.kt:174`, with the comment "no TOC → the scaffold hides the Contents control"),
   so the filter is reachable on **EPUB, TXT, MD, AZW3 — not PDF**.
8. **In-book search is not available on every format**: `InBookIndexState.Unsupported.hidesSearchEntry
   = true` for PDF/AZW3 (`search/IndexStateGate.kt:66-70`), and hosts omit the Search icon when set
   (`TxtReaderActivity.kt:787`, `ReaderActivity.kt:1002`). The search sheet is **host-owned state**
   (`ReaderActivity.showSearchSheet`, `TxtReaderActivity.showSearch`), not a `ReaderSheet` route
   (`chrome/ReaderChromeState.kt:19-25`) — so the no-match CTA needs a threaded callback, not a
   route change.
9. **Debounce hazard, from this repo's own history.** #133 shipped connected tests that were RED
   when first actually run because `compose.waitForIdle()` does **not** await a `debounce()` window;
   the fix was `waitUntil` polling. Any debounce added here inherits that trap.

---

## 5. Surface area

### New files (Android has no xcodegen — a new Kotlin file is dispatchable)

| File | Contents |
|---|---|
| `android/app/src/main/kotlin/com/vreader/app/reader/nav/TocTitleFilter.kt` | the pure core (§5.1) |
| `android/app/src/main/kotlin/com/vreader/app/reader/nav/TocFilterField.kt` | `TocFilterField` composable + count line |
| `android/app/src/main/kotlin/com/vreader/app/reader/nav/TocFilterRows.kt` | `TocPinnedCurrentRow` + `TocNoMatchState` |

### Modified files

| File | Change |
|---|---|
| `nav/TocContentsSheet.kt` | filter state + derivations + field/pinned-row/no-match wiring; `collapseLineBreaks` → `internal` (so `TocTitleFilter.matchTitle` is its single caller); the per-row `withoutEmbeddedLineBreaks` `remember` is replaced by `TocTitleFilter.matchTitle(entry)` — same normalization, same result |
| `nav/TocSheetRows.kt` | `TocContentsRow` gains `text: TocRowText` (**required**, one value carrying the title *and* its ranges — §5.2.1/§5.2.2), renders an `AnnotatedString` when ranges are non-empty, and **stops deriving the title from `entry.title`**; the "Untitled" fallback moves into `TocTitleFilter.rowText`'s untitled branch (**not** into the match string — r2 NEW-1) |
| `nav/TocBookmarksSheet.kt` | hoists `filterQuery` so it survives a Contents↔Bookmarks tab switch; passes `onOpenFullTextSearch` through |
| `reader/chrome/ReaderChromeScaffold.kt` | new `onOpenFullTextSearch: ((String) -> Unit)? = null` param, forwarded to both `TocBookmarksSheet` call sites |
| `reader/EpubReaderChrome.kt` | same param, forwarded at `:258` and `:288` |
| `reader/TxtReaderActivity.kt`, `reader/Azw3ReaderChrome.kt` (+ `Azw3ReaderActivity.kt` if it owns the flag), `reader/ReaderActivity.kt` | supply the callback (or `null` where search is `Unsupported`) |

### 5.1 `TocTitleFilter.kt` — concrete signatures

```kotlin
package com.vreader.app.reader.nav

/**
 * A folded title plus the maps that carry a folded range back to the MATCH title it was built from.
 * `starts`/`ends` are indices into that match string and nothing else.
 *
 * **PRIVATE TO [TocFoldedToc] (r3 edit 1).** This type is never a parameter, a return value, or a
 * public property anywhere in the feature. That is the whole point: v3 passed a `FoldedTitle` into
 * `rowText` as an independent argument, which let a caller supply the fold of a DIFFERENT row — the
 * finding-1 mismatch hazard relocated rather than removed. There is now no seam through which a
 * foreign fold can enter, because there is no seam that accepts one.
 */
private class FoldedTitle private constructor(
    val folded: String,
    private val starts: IntArray,   // starts[i] = display index of the char that produced folded[i]
    private val ends: IntArray,     // ends[i]   = display END (exclusive) of that source code point,
                                    //             extended over any immediately-following stripped marks
) {
    /**
     * The display-string range for the folded slice `[foldedFirst..foldedLast]`.
     * BOTH parameters and the result are INCLUSIVE (see "Range convention" below).
     */
    fun originalRange(foldedFirst: Int, foldedLast: Int): IntRange
    companion object { fun of(matchTitle: String): FoldedTitle }
}

/**
 * What a row renders: a title string and the INCLUSIVE ranges that index THAT string.
 *
 * NOT a `data class` and NOT publicly constructible (r3 edit 1): no synthesised `copy`, no
 * caller-supplied instances. The only two producers are [TocTitleFilter.plainRowText] (unfiltered —
 * no range source exists) and [TocFoldedToc.rowText] (filtered — the corpus looks up its OWN fold by
 * index). A title and a set of ranges therefore cannot be paired by anyone but the code that
 * guarantees they describe the same string.
 */
class TocRowText private constructor(val title: String, val matchRanges: List<IntRange>)

/**
 * The folded corpus for ONE TOC — match titles and their folds, index-aligned with the entries it
 * was built from. Constructing it IS cost B (§6); it is built lazily, on the first query that can
 * actually match, and never on a Contents open.
 *
 * It is the sole owner of [FoldedTitle]. Every operation takes an INDEX into its own arrays, so
 * there is no parameter through which a fold from another row (or another book) can be supplied.
 */
class TocFoldedToc private constructor(
    private val entries: List<TocEntry>,
    private val matchTitles: List<String>,   // matchTitles[i] == TocTitleFilter.matchTitle(entries[i])
    private val folds: List<FoldedTitle>,    // folds[i] == FoldedTitle.of(matchTitles[i])
) {
    /** The ORIGINAL indices whose match title contains [foldedQuery], ascending. */
    fun filter(foldedQuery: String): IntArray

    /**
     * The rendered text for the entry at ORIGINAL index [index]. Looks up `folds[index]` itself —
     * the caller supplies an index, never a fold. An entry with a blank match title returns
     * `(UNTITLED_LABEL, emptyList())` **without reading `folds` at all** (r2 NEW-1), so the
     * presentational label can never carry ranges.
     */
    fun rowText(index: Int, foldedQuery: String): TocRowText

    companion object { fun of(entries: List<TocEntry>): TocFoldedToc }
}

/**
 * Which rows the Contents list shows. Deliberately NOT a `List<row-projection>` (r3 edit 2): the
 * unfiltered case must materialise nothing per row, because that is the cost §6 removed.
 */
sealed interface TocFilterResult {
    /**
     * Not filtering. Carries NO per-row data — no match titles are normalized, no folds are built,
     * and no list is allocated (it is a singleton). The composable iterates `entries` directly, so
     * the unfiltered path costs exactly what `TocContentsSheet.kt:182` costs today.
     */
    data object Unfiltered : TocFilterResult

    /** Filtering: the surviving ORIGINAL indices, ascending. One small array per keystroke. */
    class Matched(val indices: IntArray) : TocFilterResult
}

object TocTitleFilter {
    /** The presentational fallback for an entry with no title. NOT matchable — see [TocFoldedToc.rowText]. */
    const val UNTITLED_LABEL = "Untitled"

    /**
     * THE single producer of a row's MATCH string: `entry.title` collapsed
     * ([String.collapseLineBreaks]), or `""` when null/blank. Deliberately NOT the "Untitled"
     * fallback (r2 NEW-1) — a presentational label must never be matchable.
     */
    fun matchTitle(entry: TocEntry): String

    /** The canonical query form: `query.trim()`, then folded by the algorithm below. */
    fun foldQuery(query: String): String

    /**
     * The rendered text for an UNFILTERED row: `matchTitle(entry)` (or [UNTITLED_LABEL]) with
     * **empty ranges by type** — this function has no range source, so it cannot mispair.
     * Called per VISIBLE row, exactly like today's `remember(entry) { … }` at `TocContentsSheet.kt:188`.
     */
    fun plainRowText(entry: TocEntry): TocRowText

    /**
     * The filter pass. Returns [TocFilterResult.Unfiltered] — **without reading `foldedToc.value`** —
     * when [trimmedQuery] is blank, so a Contents open never pays cost B. Also returns an empty
     * [TocFilterResult.Matched] without forcing the fold when [foldedQuery] is empty but
     * [trimmedQuery] is not (the lone-combining-mark case: zero matches regardless — r1 finding 4).
     */
    fun filter(
        trimmedQuery: String,
        foldedQuery: String,
        foldedToc: Lazy<TocFoldedToc>,   // Lazy, NOT TocFoldedToc — see the two early returns above
    ): TocFilterResult

    /**
     * True when a filtering query has filtered the active chapter OUT (⇒ pin the "Reading" row).
     * [TocFilterResult.Matched.indices] is ascending, so this is a binary search — O(log n), the
     * same posture as #139 WI-5's `txtTocIndexFor`, because it runs on every composition.
     */
    fun isActiveFilteredOut(result: TocFilterResult, activeIndex: Int): Boolean
}

object TocFilterCountLabel {
    /** "N of M chapters" / "N of M chapter" / "No chapters match" / null when [trimmedQuery] is blank. */
    fun text(result: TocFilterResult, totalCount: Int, trimmedQuery: String): String?
}
```

**Range convention (normative — Gate-2 r1 finding 5).** Every `IntRange` this feature produces or
consumes is **inclusive on both ends**, in UTF-16 `Char` units, relative to the **match** title.
This matches #133, whose match ranges are documented "inclusive UTF-16 `IntRange`s"
(`search/InBookSearchRows.kt:172`), so the two reader-side highlighters share one convention. The
`… , foldedEndExclusive)` signature in v1 mixed conventions inside a single call and is gone:
`originalRange(foldedFirst, foldedLast)` is inclusive on both parameters. The exclusive conversion
happens once, at the `AnnotatedString` boundary (`addStyle(style, r.first, r.last + 1)`), and WI-3
reuses the hardened walk in `search/InBookSearchRows.kt:179-205` (`boldedSnippet`), which already
clamps to bounds, guards `r.last + 1` overflow, tolerates out-of-order input, and snaps every
boundary off a surrogate-pair interior. §8.1 asserts exact `(first, last)` pairs against
hand-computed expectations, not just range counts.

**Folding algorithm (normative — revised at Gate-2 r1 finding 2).** Iterate the **display** title by
**code point**. For each code point:

1. **Full Unicode case fold** it with ICU:
   `UCharacter.foldCase(String(Character.toChars(cp)), UCharacter.FOLD_CASE_DEFAULT)`.
   **Use the `String` overload.** The `UCharacter.foldCase(int, boolean)` overload returns an `int`
   and can therefore only do *simple* folding — it leaves `ß` as `ß`, silently reopening the gap
   this change exists to close. Full folding gives `ß`→`ss`, `ς`/`Σ`→`σ`, `İ`→`i` + U+0307, and is
   locale-independent by construction.
2. `java.text.Normalizer.normalize(folded, Form.NFD)` — **never NFKC** (§3).
3. Append every char whose `Character.getType(c) != Character.NON_SPACING_MARK`, recording
   `starts[i]` = the source code point's display offset and `ends[i]` = its display end, **extended
   over any immediately-following stripped marks** so a match ending just before a combining mark
   still tints the mark with its base character.

Length is not preserved and that is expected — verified on JDK 17: `"İ".toLowerCase(ROOT)` is 2
chars, `NFD("각")` is 3 chars (Hangul jamo, none of them category `Mn`), `NFD("Café")` is 5 chars
folding to 4, and `ß`→`ss` is 1→2. The maps exist precisely for these. **The Gate-2 empirical
auditor implemented this scheme and measured ~90 hostile inputs — `İ` at position 0 and mid-title,
Hangul NFD expansion before/after/inside a match, jamo-decomposed vs precomposed in both directions,
decomposed `e`+U+0301 with the match ending on and spanning the mark, stacked marks, surrogate pairs
before/inside/as-query, Arabic harakat, Hebrew niqqud, orphan combining marks, partial-expansion
jamo queries, CJK substring, `"aa"` in `"aaaa"` → exactly 2 ranges — with zero wrong ranges.** The
static auditor's contrary claim (that Hangul, emoji ZWJ sequences, and combining marks would
mis-highlight) is **disproven by measurement and is not actioned**; §10 keeps it as the top-rated
risk because the mechanism is subtle, but the mechanism itself is sound.

**Matching.** `folded.indexOf(foldedQuery, from)`, advancing `from` by `foldedQuery.length`
(non-overlapping), converting each hit via `originalRange`. Returns `emptyList()` when
`foldedQuery` is empty — which also guards the `indexOf("")` infinite loop.

**Empty-query gating (revised — Gate-2 r1 finding 4).** There are two distinct predicates and v1
conflated them:

- `trimmedQuery = query.trim()` — **this** decides whether we are filtering at all, and drives the
  count line, the no-match branch, and the pinned row. iOS gates the same way
  (`TOCTitleFilter.swift:53-54`; `TOCFilterCountLabel.text(…, trimmedQuery:)`).
- `foldedQuery` — decides only whether any row *matches*.

So a query that survives trimming but folds to `""` (a lone combining acute U+0301) is **filtering
with zero matches** ⇒ the no-match state, exactly as iOS does. v1 gated on the folded query and
would have shown the full list with the count line hidden.

**Query trimming (rationale corrected — Gate-2 r1 finding 8).** A plain Kotlin `String.trim()` is
sufficient and matches iOS. v1 claimed "(verified)" that Kotlin's `trim()` leaves U+00A0 NBSP; that
is **false**. Kotlin's `Char.isWhitespace()` is `Character.isWhitespace(c) || Character.isSpaceChar(c)`,
and NBSP is `isSpaceChar=true`, so `trim()` does strip it — as it strips U+3000 IDEOGRAPHIC SPACE
(`isWhitespace=true`). v1's proposed `trim { it.isWhitespace() || Character.isSpaceChar(it) }`
predicate is a harmless no-op and is dropped for the plain `trim()`. The one real trap stands and is
worth keeping in the KDoc: **do not use Java's `String.trim()`**, which strips only chars ≤ U+0020
and would leave U+3000 — verified.

### 5.2 `TocContentsSheet.kt` wiring

```kotlin
fun TocContentsSheetContent(
    theme: ReaderTheme,
    bookTitle: String,
    entries: List<TocEntry>,
    currentTocIndex: Int,
    onJump: (Int) -> Boolean,
    onDismiss: () -> Unit = {},
    // #141 — hoisted filter query. Null (the default) makes the composable own its own
    // rememberSaveable state, so existing direct callers still get a working field.
    filterQuery: String? = null,
    onFilterQueryChange: ((String) -> Unit)? = null,
    // #141 — the no-match "Search full text" escape hatch, capability-gated (null → CTA omitted).
    onOpenFullTextSearch: ((String) -> Unit)? = null,
)
```

Derivation order inside the function (all after the `entries.isEmpty()` guard):

1. `val trimmedQuery = query.trim()`; `val isFiltering = trimmedQuery.isNotEmpty()`;
   `val foldedQuery = remember(trimmedQuery) { TocTitleFilter.foldQuery(trimmedQuery) }`.
2. **No eager corpus map, and no per-row projection list either (r3 edit 2).** v1 had a
   `remember(entries) { entries.map { … } }` of titles; the Gate-2 empirical audit measured that at
   **2.94 ms over 1 859 titles on every Contents open**, replacing today's ~12-row cost, for a user
   who may never type (finding 3). v3 removed the map but still returned `List<TocFilterRow>` from
   the blank branch — and every row carried a `matchTitle`, so opening Contents would have
   materialised all 1 859 normalized titles anyway. Both are gone: the blank branch returns
   `TocFilterResult.Unfiltered`, a **singleton carrying no rows at all**.
3. `val foldedToc = remember(entries) { lazy(NONE) { TocFoldedToc.of(entries) } }`
   — built **only when a query that can match arrives**, so an open-and-scroll costs nothing. This
   is the single >100 ms-class risk in the feature; see §6 for its budget and off-thread fallback.
4. `val result = remember(entries, trimmedQuery, foldedQuery) { TocTitleFilter.filter(trimmedQuery, foldedQuery, foldedToc) }`
   — **`filter` takes the `Lazy<TocFoldedToc>`, not a `TocFoldedToc`, and returns from BOTH early
   branches before reading `.value`** (blank trimmed query → `Unfiltered`; empty folded query →
   `Matched(empty)`). Passing `foldedToc.value` at the call site would force the fold on every sheet
   open and silently reinstate exactly the cost step 3 exists to defer. Two JVM tests
   (`blankQuery_neverForcesTheFold`, `foldAwayQuery_neverForcesTheFold`) assert the `Lazy` is still
   uninitialised afterwards, so this cannot regress unnoticed.
5. **Two row paths, because the two modes genuinely differ** — forcing them into one list is what
   produced both the eager-title cost and the pairing hazard:

   ```kotlin
   LazyColumn(state = listState, …) {
       when (result) {
           // UNFILTERED — iterate `entries` itself. No list is allocated, no titles are
           // materialised: identical in shape to today's TocContentsSheet.kt:182/:188.
           TocFilterResult.Unfiltered -> itemsIndexed(entries) { index, entry ->
               val text = remember(entry) { TocTitleFilter.plainRowText(entry) }
               TocContentsRow(text = text, entry = entry, index = index,
                              isCurrent = index == currentTocIndex, …)
           }
           // FILTERED — iterate the surviving ORIGINAL indices.
           is TocFilterResult.Matched -> items(result.indices.size) { i ->
               val index = result.indices[i]
               val text = remember(index, foldedQuery) { foldedToc.value.rowText(index, foldedQuery) }
               TocContentsRow(text = text, entry = entries[index], index = index,
                              isCurrent = index == currentTocIndex, …)
           }
       }
   }
   ```

   Ranges are computed **per visible row only**, and the corpus resolves its own fold from the index
   it is handed (finding 9: one fold per title, ever; r3 edit 1: no fold ever crosses an API
   boundary). `TocContentsRow` receives the title and its ranges as **one `TocRowText` value** it
   cannot take apart, substitute, or `copy` — the structural fix for finding 1, sharpened by r2
   NEW-1 and r3 edit 1 (§5.2.1). `entry` is passed separately for `depth`/`pageLabel` only, and the
   row still never reads `entry.title`.
6. Scroll transitions (finding 7 + **r2 NEW-3**): key the effect on the **query string**, not on
   emptiness, so refining `Chapter` → `Chapter 1999` still re-scrolls instead of leaving a one-row
   result at a stale offset — **and record the intent BEFORE the first suspension point**, so a
   cancelled effect still leaves the memo correct:

   ```kotlin
   // A PLAIN holder, not snapshot state: this is effect-local bookkeeping, never read during
   // composition, and a MutableState write here would invalidate for no reader.
   class FilterScrollMemo { var wasFiltering = false }
   val memo = remember(tocIdentity) { FilterScrollMemo() }

   LaunchedEffect(tocIdentity, trimmedQuery) {
       val filtering = trimmedQuery.isNotEmpty()
       val shouldRestore = !filtering && memo.wasFiltering
       memo.wasFiltering = filtering        // BEFORE any suspend — survives cancellation
       if (filtering) listState.scrollToItem(0)
       else if (shouldRestore) listState.scrollToItem(currentTocIndex.coerceIn(entries.indices))
   }
   ```

   **Why the ordering is load-bearing (r2 NEW-3).** Keying on `trimmedQuery` means every keystroke
   *cancels* the previous effect. In v2 the assignment sat *after* `scrollToItem`, so a fast
   type-then-clear cancelled the non-empty effect before it recorded that filtering had begun; the
   clear branch then read `wasFiltering == false` and skipped the restore, dumping the user at the
   top of a 1 859-row list instead of back at their chapter — destroying exactly the position
   `TocContentsSheet.kt:161` deliberately retains by identity. Recording intent first makes the
   memo describe *what the user did*, not *what the scroll finished doing*.

   This is the Android form of iOS's `TOCFilterState.didClear` / `scrollLadderKey` re-fire
   (`TOCSheet+Filter.swift:67-97`). Without it the retained `LazyListState` sits at a stale offset —
   the repo has a recorded case of `rememberLazyListState(initial = N)` silently clamping to 0.
7. Branches: `result is Matched && result.indices.isEmpty()` → `TocNoMatchState` (a fold-to-nothing
   query reaches `Matched(empty)`, so it lands here — finding 4); else the pinned row (when
   `isActiveFilteredOut(result, currentTocIndex)`) + the list.

### 5.2.1 One string, one owner (Gate-2 r1 finding 1 — the High)

v1 had `TocFilterRow` carrying **both** `entry` (raw title) and `displayTitle` (collapsed) with no
invariant binding them, while WI-4 *removed* `TocContentsSheet.kt:188`'s per-row normalization and
`TocSheetRows.kt:61` kept deriving the rendered string from `entry.title`. Ranges would then be
computed on one string and applied to another. Measured by the Gate-2 auditor:

```
raw "   Chapter One"   / display "Chapter One"   query "chapter"
  range [0..6]  on display -> "Chapter"    on raw -> "   Chap"    WRONG
raw "第一章 \n  黎明前" / display "第一章 黎明前"  query "黎明"
  range [4..5]  on display -> "黎明"       on raw -> "\n "        WRONG
```

Critically this is **not** confined to titles containing line breaks: `collapseLineBreaks` trims the
ends of *every* title (`TocContentsSheet.kt:241-261` — deliberate, matching iOS's TXT rules), so a
plain EPUB title with one leading space shifts every index. The mirror case — ranges from a longer
string applied to a shorter one — is an `AnnotatedString` bounds **crash**, not a silent defect.

The fix is structural, not a test:

1. `TocTitleFilter.matchTitle(entry)` is the **only** producer of a row's match string.
2. `FoldedTitle.of` is fed that same string, so `starts`/`ends` are by construction indices into it.
3. Exactly two functions produce a rendered title, and each returns it *bundled with* the ranges
   that index it (`TocRowText`): `TocTitleFilter.plainRowText(entry)` (unfiltered — has no range
   source at all) and `TocFoldedToc.rowText(index, foldedQuery)` (filtered).
4. `TocContentsRow` takes `text: TocRowText` — one value, not two parameters — so it is not merely
   *discouraged* from mismatching the pair, it is **unable to**. It never reads `entry.title`. Its
   only production caller is `TocContentsSheetContent`.
5. **`TocRowText` cannot be built or `copy`ed by a caller (r3 edit 1)**: it is not a `data class`
   (no synthesised `copy`) and its constructor is `private`. A mismatched pair is not merely
   discouraged at the call site — it is unconstructible.
6. **`FoldedTitle` is private to `TocFoldedToc` and is never a parameter (r3 edit 1)**. v3's
   `rowText(row, folded, foldedQuery)` accepted a fold as an independent argument, which relocated
   the finding-1 hazard into the very seam introduced to close it: a caller could hand it row 5's
   text and row 900's fold. The corpus now resolves `folds[index]` itself from the index it is
   given, so a foreign fold has no way in.
7. WI-3's `AnnotatedString` walk clamps to bounds anyway (the `boldedSnippet` precedent), so even a
   future regression degrades to a wrong tint rather than a crash.
8. §8.1 asserts the pairing directly, for a leading-space title **and** an embedded-`\n` title, and
   §8.2 adds a connected assertion that the rendered row text equals the row's match title. v1's
   `titleWithEmbeddedLineBreak_matchesNormalizedForm` covered the matching half only — the rendering
   half was the hole.

**The remaining seam, and why it cannot be misused.** `TocFoldedToc.rowText(index, foldedQuery)`
still takes an `index`, so a caller could in principle pass the wrong one. That is a different and
strictly weaker failure than the one this section exists to prevent: a wrong index yields a
*consistent* pair — the wrong row's title **with that same row's ranges** — so the rendered text and
its tint always describe the same string. It is a visible "wrong row" bug, not the silent
tint-lands-on-the-wrong-characters or `AnnotatedString`-bounds-crash class. It is also confined to a
single expression in one composable (§5.2 step 5), where the index comes straight from
`result.indices[i]` and is the same value passed to `entries[index]` and `isCurrent` — so a wrong
index would misrender the whole row identically and be obvious on sight. Removing it entirely would
mean materialising a per-row object, which is exactly the cost r3 edit 2 forbids.

### 5.2.2 The "Untitled" fallback — reverting half of v2's fix (r2 NEW-1)

**v2 moved the `"Untitled"` fallback into the producer. That was the wrong half of the fix, and it
is reverted here.** The correct half was making the row take its string explicitly instead of
deriving it from `entry.title`; the incorrect half was making the *producer* emit a presentational
label. `TocEntry.title` is nullable (`TocEntry.kt:24`), so under v2's spec a blank-titled row folded
to `untitled` and **typing "untitled" would have matched every blank row** — contradicting §3's
rejected-alternatives entry, and making v2's own
`nullOrBlankTitle_neverMatchesNonEmptyQuery_butCountsInTotal` a test that fails against the
algorithm it ships with. Good catch; it is the finding-1 hazard arriving from the opposite side.

**Resolution chosen: the third option — `matchTitle` returns the normalized title (`""` for a blank
row) and the fallback is applied at render time — but the fallback is applied *inside* `rowText`,
not by the row.** That keeps the fallback where it belongs (presentation) without handing it back to
`TocSheetRows.kt:61`'s self-derivation, which is what caused finding 1 in the first place.

**What stops finding 1 recurring under it**, given there are now two strings in play:

| Guard | Mechanism |
|---|---|
| The two strings can never be *chosen independently* | Both producers return `TocRowText(title, matchRanges)` as one value, and `TocContentsRow` accepts only that value. There is no code path that yields a title without its ranges. v2's two-parameter shape (`title` + `matchRanges`) *could* be mismatched by a caller; this cannot. |
| The pair cannot be forged or edited (r3 edit 1) | `TocRowText` is **not** a `data class` (no synthesised `copy`) and its constructor is `private`. Callers can obtain instances only from `plainRowText` / `TocFoldedToc.rowText`. |
| The fallback branch cannot carry ranges | The untitled branch returns `emptyList()` **without reading `folds` at all**. It is not "empty because nothing matched" — it is empty because that branch has no access to a range source. `plainRowText` likewise has none, for any row. |
| The fallback is unreachable by matching | `FoldedTitle.of` is fed `matchTitle`, never `UNTITLED_LABEL`. A blank row folds to `""`, and `"".indexOf(nonEmpty)` is always `-1`. |
| The names stop lying | `displayTitle` → `matchTitle`; the string that is matched is the one whose name says so, and the presentational one is a `const val UNTITLED_LABEL` that appears in exactly one branch of one function. |
| Regression is caught, not argued | `queryUntitled_matchesZeroRows_inTocWithBlankTitles` **fails against the v2 spec** (v2 would match every blank row), and `rowText_untitledRow_hasEmptyRangesEvenWhenQueryMatchesTheLabel` pins the branch directly. |

Cost, stated: there are two strings again rather than one, which is a weaker starting invariant than
v2's. It is bought back by making the pairing a *type* — private constructor, no `copy`, no
independently-supplied fold — rather than a *convention*. That is strictly stronger than v2's
arrangement, where a caller could still pass a title from one row and ranges from another.

### 5.3 Files explicitly OUT of scope

`nav/TocProvider.kt`, `nav/TxtMdTocProvider.kt`, `nav/ReadiumTocProvider.kt`,
`nav/FoliateTocProvider.kt`, `nav/TxtTocIndex.kt`, `nav/FoliateTocIndex.kt`, `nav/MdTocScanner.kt`,
`nav/TxtTocRule*.kt` (#139/#140 territory — the filter consumes their output and must not touch
detection); `search/*` (except reading `IndexStateGate` to decide the CTA gate — no edits);
`reader/PdfReaderScreen.kt` (no TOC); the Bookmarks tab body and `nav/BookmarkPresentation.kt`;
`annotations/*`; anything under `android/app/src/debug/`; every iOS path; `contracts/`;
`docs/features.md` and `android/version.properties` (orchestrator-owned).

---

## 6. Performance — three distinct costs, one real risk, and the debounce decision

Gate-2 r1's empirical audit measured v1's algorithm on a desktop JVM over 1 859 realistic CJK
titles. Those numbers settle nothing on their own — #139 saw a **~100× desktop-to-device miss**
(46–102 ms desktop → 8.3–11.4 s on device), which is exactly why this section budgets on-target
assertions rather than quoting a desktop figure. What they *do* settle is **where the risk lives**,
and it is not where v1 put it. Three separate costs, budgeted separately (finding 3):

| Cost | When | Desktop measurement | On-target budget (WI-1 assertion) |
|---|---|---|---|
| **A — visible-row titles** | every Contents open | v1's eager 1 859-title map cost **2.94 ms**; **removed** in §5.2 step 2, back to today's ~12 rows | no regression vs. today's per-row `remember` (assert the sheet composes ≤ `MAX_ENTRY_READS`, reusing `TocContentsLargeTocTest`'s counters) |
| **B — corpus fold** (`FoldedTitle.of` × 1 859) | **first keystroke only** | **18.66 ms** cold, total | **≤ 120 ms** |
| **C — filter pass** (fold query + `indexOf` × 1 859 pre-folded) | every keystroke | **0.035 ms** warm median | **≤ 8 ms** (half a 60 Hz frame) |

Cost **C** has ~200× desktop headroom; even a 100× device factor leaves it at ~3.5 ms, inside
budget. Cost **B** is the one that matters: a 100× factor puts it at **1.87 s**, and even a modest
5–10× puts it at **93–187 ms** — over budget, **on the main thread, at the instant of the first
keystroke**, because §5.2's `lazy(NONE)` defers it *into* that keystroke.

**A debounce does not fix cost B.** It delays the fold; it does not make it cheaper. Saying so
explicitly because the tracker row's "debounced" wording invites exactly that mistake.

### The blank-query path is where this feature's costs keep hiding — a standing note

Three separate times now, cost has re-entered through the *not-filtering* branch, each time one edit
after it was removed:

1. **v1** materialised all 1 859 display titles in a `remember(entries)` — paid on every Contents
   open, by users who never type (r1 finding 3).
2. **v2** deleted that map and then, one step below, passed `foldedCorpus.value` into `filtered(...)`,
   forcing the lazy fold on every open (self-caught during the r1 revision).
3. **v3** returned `List<TocFilterRow>` from the blank branch, and every row carried a `matchTitle` —
   so all 1 859 titles were normalized on open again, by a different route (r3 edit 2).

The pattern is that each fix removed one *expression* while leaving a *shape* that still demanded
per-row data. **Binding instruction for the implementer, not a description:** the not-filtering path
must allocate no per-row object and normalize no title it does not display. Concretely — the blank
branch returns the `TocFilterResult.Unfiltered` **singleton**; the `LazyColumn` iterates `entries`
directly (`itemsIndexed(entries)`), never a projection; titles come from `plainRowText(entry)` inside
a per-item `remember`; and `TocTitleFilter.filter` returns before touching `foldedToc.value`. **Any
change that makes the blank branch produce a `List` of anything is a regression of this instruction,
whether or not the cost-A counter test happens to catch it** — a test that catches a violation is
weaker than a shape that cannot express one.

### The debounce decision (unchanged from v1, and Gate-2 r1 endorsed keeping it)

**Ship with no debounce.** The tracker row says "debounced title match"; both references disagree.
iOS #94 has none — `visibleEntries` is a plain computed property recomputed synchronously
(`TOCSheet+Filter.swift:34-36`), confirmed by the Gate-2 auditor reading the whole file. The design
bundle says "debounce not required below ~2k entries" (`toc-filter-artboards.jsx:662`) — which
**supports "probably fine", not "measured fine"** (finding 10a): the real corpus is 1 859, only 7 %
under that ceiling, and the existing connected test already runs 2 000. Adding a debounce has a
concrete cost here: it makes every connected assertion racy against `waitForIdle` (§4.9, the #133
regression). If cost C ever exceeds its budget, the fallback is a `filterDebounceMillis: Long`
parameter defaulting to `0`, applied as `snapshotFlow { query }.debounce(…)`, with every connected
filter assertion converted to `waitUntil { … }` polling in the same WI. Do not add it speculatively.

### The cost-B mitigation, pre-designed (built only if WI-1's measurement demands it)

Move the fold off the composition thread — which the design bundle itself sanctions: "for
pathological TOCs, filter on a background actor and diff into the `LazyVStack`"
(`toc-filter-artboards.jsx:662`). Concretely: start the corpus fold in a `LaunchedEffect` at **sheet
open** (not first keystroke) on an injected `CoroutineDispatcher` (`dispatcher: CoroutineDispatcher
= Dispatchers.Default` — rule 50 §1 forbids hardcoding one), exposed as
`State<List<FoldedTitle>?>`. Until it lands, `filtered(...)` returns every row unchanged.

**Rule-51 check on that fallback:** the pre-ready window renders the *unfiltered list* — a state the
design already depicts (`state-default`) — with the count line suppressed. No spinner, no "indexing"
copy, no new surface is invented. In practice the window is sub-second and only reachable by typing
within ~100 ms of the sheet opening. This is a transient, not a designed state.

### Sequencing consequence (changed from v1)

v1 put the cost measurement in WI-6, the *last* WI — which would have forced a structural decision
after the wiring was already built. **`TocFilterCostTest` moves to WI-1**, where `TocTitleFilter`
first exists, so WI-4 knows before it wires anything whether it must build the off-thread path. WI-6
re-measures on the finished surface as part of the acceptance pass.

Measured on a booted emulator against the **real** 1 859-entry `黑暗血时代.txt` (titles obtained by
running the shipped `TxtMdTocProvider` on the pushed book — real books first, no synthetic corpus),
modelled on the existing `androidTest/.../nav/TxtTocScanCostTest.kt`. **The connected task wipes
`/sdcard/Android/data/<pkg>/` at run end, so the book must be re-pushed on every run** (#138's
durable lesson).

---

## 7. Work-item sequencing

Each WI is one PR. Tier per rule 47 Gate 5.

| WI | Title | Tier | New files | PR size |
|---|---|---|---|---|
| **WI-1** | `TocTitleFilter` — ICU full-case-fold + NFD folding, the `TocFoldedToc` corpus (owning a private `FoldedTitle`), `matchTitle`, `plainRowText` + `TocFoldedToc.rowText` → `TocRowText` (private ctor, no `copy`), `filter` → `TocFilterResult`, count label, `isActiveFilteredOut`; `collapseLineBreaks` → `internal`. **Plus `TocFilterCostTest`** (moved up from WI-6 — §6 "Sequencing consequence") so the cost-B number exists before WI-4 wires anything | **foundational** (pure Kotlin, no user-observable change — the tier is unchanged by the cost test, which asserts budgets, not behavior) | `nav/TocTitleFilter.kt` | ~270 lines + ~420 test |
| **WI-2** | `TocFilterField` — the designed pill (rest/focus/clear/Cancel) + count line, not yet wired into the sheet | **behavioral** (new visible composable; slice-verified by rendering it in a connected test host across **`ReaderTheme.entries`**, all five) | `nav/TocFilterField.kt` | ~160 + ~180 test |
| **WI-3** | `TocContentsRow(title = …, matchRanges = …)` — required `title`, accent-tinted matched runs via `AnnotatedString` reusing the `boldedSnippet` clamping/surrogate-snapping walk | **behavioral** | — (edits `nav/TocSheetRows.kt`) | ~60 + ~140 test |
| **WI-4** | Wire it up: filter state (hoisted through `TocBookmarksSheetContent`), derivations, scroll-on-every-query-change / restore-on-clear, pinned "READING" row, no-match state. **Builds the §6 off-thread fold iff WI-1's cost-B measurement exceeded 120 ms** | **behavioral** | `nav/TocFilterRows.kt` | ~220 + ~300 test |
| **WI-5** | The no-match **"Search full text"** CTA: thread `onOpenFullTextSearch: ((String) -> Unit)?` sheet → scaffold/EPUB chrome → hosts; omit the CTA where search is `Unsupported`. **Each host's implementation must SEED the search VM, not just open the sheet** — §7.1 | **behavioral** | — | ~140 + ~160 test |
| **WI-6** | Gate-5b acceptance pass on real books + re-measure costs A/B/C on the finished surface; record the debounce decision in the evidence file | **behavioral** (final WI — full acceptance) | — | ~80 test |

Dependencies are linear: WI-1 → {WI-2, WI-3} → WI-4 → WI-5 → WI-6. WI-2 and WI-3 are the only pair
that could run in parallel (disjoint files), and only if WI-1 has merged.

### 7.1 WI-5 — how the query actually reaches the search field (r2 NEW-2)

v2 promised the CTA carries the query (§3) but specified only that `onOpenFullTextSearch(query)` is
invoked. **That is a boundary assertion, and it would have passed while the user landed on an empty
search field** — the same defect shape the r1 empirical audit caught. Verified why, at real lines:

- EPUB — `ReaderActivity.kt:1138-1142` renders `InBookSearchSheet(state = screen, query = screen.query, …)`,
  where `screen` is `vm.state.collectAsStateWithLifecycle()`. The field shows **VM state**.
- TXT/MD — `TxtReaderActivity.kt:790-794` renders `InBookSearchSheet(state = inBookSearchState, query = inBookSearchState.query, …)`.
  Same shape.
- Setting `showSearchSheet.value = true` / `showSearch = true` therefore opens a sheet bound to
  whatever the VM's query already is — an empty string on a fresh session.

So each host's `onOpenFullTextSearch` must be **seed-then-open**:

```kotlin
onOpenFullTextSearch = { q -> inBookSearchVm?.onQueryChange(q); showSearchSheet.value = true }
```

`InBookSearchViewModel.onQueryChange(text)` (`InBookSearchViewModel.kt:214-220`) is the right seam
and is already used this way: it "immediately reflects the raw text (so the field is responsive)",
sets `_state.value.copy(query = text, …)` synchronously, and begins a new session — and
`onPickRecent` is literally `= onQueryChange`, i.e. programmatic seeding is an existing, supported
pattern, not a new affordance. The 250 ms debounce delays only the *results*, never the field text.

Two capability details: EPUB's `inBookSearchVm` is **nullable** (`ReaderActivity.kt:1136`
`val vm = inBookSearchVm ?: return`), so a null VM omits the CTA exactly like `Unsupported` does;
and the CTA passes the **trimmed** query, matching what the count line and the no-match copy show.

**WI-1 needs an emulator** even though it is foundational — for `TocFilterCostTest` only. Its
`TocTitleFilterTest` JVM suite additionally runs under **Robolectric** (`@RunWith(RobolectricTestRunner::class)`),
because `android.icu.lang.UCharacter` is a framework class the stub `android.jar` will not mock;
`SearchTextNormalizerTest.kt:16-17` is the exact precedent and `robolectric:4.13` is already a
`testImplementation` dependency.

---

## 8. Test catalogue

Every edge case below is a named test. **JVM** = `android/app/src/test/kotlin/...`, runs anywhere.
**Connected** = `android/app/src/androidTest/kotlin/...`, requires a booted emulator.

### 8.1 JVM — `test/kotlin/com/vreader/app/reader/nav/TocTitleFilterTest.kt` (WI-1)

`@RunWith(RobolectricTestRunner::class)` — required for `android.icu` (§7).

| Test | Covers |
|---|---|
| `emptyQuery_returnsAllEntriesWithOriginalIndices` | empty query ⇒ identity |
| `whitespaceOnlyQuery_treatedAsEmpty` | `" "`, `"\t"`, `"　"` U+3000, `" "` U+00A0. **Rationale corrected (finding 8):** Kotlin's `Char.isWhitespace()` is `Character.isWhitespace \|\| Character.isSpaceChar`, so a plain `trim()` strips **both** U+3000 and NBSP. v1's comment claiming NBSP survives was false |
| `javaTrimWouldLeaveIdeographicSpace` | pins the one real trap: `java.lang.String.trim()` strips only chars ≤ U+0020, so under Java's `trim` a U+3000-padded query keeps its padding — verified. Guards a future "simplification" back to it |
| `queryFoldingToNothing_showsNoMatchNotFullList` | query = a lone combining acute U+0301: trims non-empty, folds to `""` ⇒ **filtering with zero matches** (iOS parity — finding 4), and **no infinite `indexOf("")` loop** |
| `caseInsensitive_ascii` / `caseInsensitive_nonAscii` | "STREET" ↔ "The Street"; "Ä" ↔ "ä" |
| `caseFold_sharpS` | **"strasse" matches "Straße des Lichts"** — closed by ICU full folding; fails under `lowercase()` (finding 2) |
| `caseFold_greekFinalAndMedialSigma` | **"ΟΔΟΣ" matches "Οδός Ονείρων"**, and `ς`/`σ`/`Σ` are interchangeable in query and title, both directions — the user-facing gap `lowercase()` cannot close |
| `caseFold_usesFullFoldingNotSimple` | asserts `ß`→`ss`, so a refactor to the `UCharacter.foldCase(int, boolean)` overload — which only does *simple* folding — fails loudly instead of silently reopening the gap |
| `diacriticInsensitive_precomposed` | "cafe" matches "Café" (U+00E9) |
| `diacriticInsensitive_decomposed` | "cafe" matches "Café" — the case the design's JS mock gets wrong (it slices the *original* with *folded* indices, `toc-filter-artboards.jsx:99-108`) |
| `matchRanges_mapBackToDisplay_afterLengthChangingFold` | titles containing `İ` (folds to `i`+U+0307 ⇒ 1 char after strip), `각` (NFD ⇒ 3 jamo, none category `Mn`), and `ß` (⇒ 2 chars) — before, inside, and after the match |
| `matchRanges_exactBounds` | **asserts exact inclusive `(first, last)` pairs** against hand-computed expectations, not just range counts (finding 5) — e.g. "street" in "The Street" ⇒ `4..9` |
| `matchRanges_endExtendsOverTrailingCombiningMark` | a match ending immediately before a stripped mark tints the mark with its base char (the `ends`-extension rule) |
| `turkishLocale_doesNotChangeMatching` | `Locale.setDefault(Locale("tr"))`; "I" still matches "Inn". Now a regression pin rather than the primary defence — case folding is locale-independent by construction |
| `cjk_singleCharacterSubstring` | 剑 narrows `WUXIA`-shaped titles; no word boundaries |
| `cjk_multiCharacterAndChapterNumber` | 故人; 第十 matches 第十/第十一…第十九 and **not** 第一 |
| `noWordPrefixRule` | "inn" matches "Spouter-Inn" mid-word |
| `queryLongerThanEveryTitle_returnsEmpty` | drives the no-match branch |
| `multipleOccurrences_allRangesNonOverlapping` | "aa" in "aaaa" ⇒ exactly 2 ranges, at `0..1` and `2..3`; "the" in "The Theatre" ⇒ 2 |
| `surrogatePairBeforeMatch_rangesAreCharIndices` | an astral emoji before the match — `AnnotatedString` spans are Char indices |
| `fullWidthLatin_doesNotMatch` | ＣＡＦＥ + "cafe" ⇒ no match. **The one exclusion that genuinely agrees with iOS** |
| `ligature_foldsLikeIcuFullCaseFolding` | ﬁ + "fi" ⇒ **match**. **ERRATUM (WI-1): the earlier `ligature_doesNotMatch_divergesFromIos` row was wrong.** Unicode full case folding maps U+FB01 → `"fi"`, so the ICU switch that closed ß and final sigma closed this too — Android **agrees** with iOS, no NFKC and no index-map change. See §3 Residual 1 (withdrawn). Twice-renamed, and the reason is the lesson: v1's name taught a false rationale, v2's name taught a false *result* |
| `arabicHamza_overMatchesVsIos` | `الأول` + `الاول` ⇒ match, where iOS does not. Pins the accepted over-match so any future change to the strip rule is deliberate |
| `nullOrBlankTitle_neverMatchesNonEmptyQuery_butCountsInTotal` | `TocEntry.title: String?` — a blank row folds to `""` and matches nothing, but still counts in the "of M" denominator |
| `queryUntitled_matchesZeroRows_inTocWithBlankTitles` | **r2 NEW-1** — a TOC containing blank-titled entries, query `untitled` ⇒ **zero** rows. **Written to fail against the v2 spec**, under which `displayTitle` returned the label, folded to `untitled`, and matched every blank row |
| `rowText_untitledRow_hasEmptyRangesEvenWhenQueryMatchesTheLabel` | pins `rowText`'s untitled branch: title == `UNTITLED_LABEL`, `matchRanges` == `emptyList()`, and the branch never consults `folded` |
| `rowText_pairsTitleWithRangesThatIndexIt` | **finding 1, sharpened** — for a leading-space title and an embedded-`\n` title, the string `rowText` returns, the string `FoldedTitle.of` consumed, and the string the returned ranges index are all identical |
| `titleWithEmbeddedLineBreak_matchesNormalizedForm` | the matching half of the same case (kept from v1) |
| `filter_preservesOriginalIndices` | a survivor at original position 1 500 appears in `Matched.indices` as `1500`, and `indices` is strictly ascending (the precondition `isActiveFilteredOut`'s binary search relies on) |
| `blankQuery_neverForcesTheFold` | after `filter(trimmedQuery = "", …)` the `Lazy<TocFoldedToc>` reports `isInitialized() == false` — pins §5.2 step 4's cost-A guarantee |
| `foldAwayQuery_neverForcesTheFold` | a query that trims non-empty but folds to `""` returns `Matched(empty)` **and** leaves the `Lazy` uninitialised — a dead-key keystroke pays no cost B |
| `blankQuery_returnsUnfilteredSingleton_notAList` | **r3 edit 2** — `filter(trimmedQuery = "", …) === TocFilterResult.Unfiltered`; pins that the not-filtering path produces no per-row object. Fails against the v3 spec, which returned `List<TocFilterRow>` with a `matchTitle` per row |
| `rowText_cannotBeConstructedOrCopiedByCallers` | **r3 edit 1** — a compile-level guard expressed as a test-source comment plus an API-shape assertion: `TocRowText` has no public constructor and no `copy` (it is not a `data class`). If a future edit adds `data`, this test's rationale block is the tripwire |
| `isActiveFilteredOut_*` (3 cases) | not filtering / active survives / active filtered out |
| `countLabel_*` (4 cases) | null when the **trimmed** query is blank, "1 of 16 chapter", "5 of 16 chapters", "No chapters match" |

### 8.2 Connected — WI-1/2/3/4/5

| File | Tests |
|---|---|
| `androidTest/.../nav/TocFilterCostTest.kt` (**WI-1**, moved up — §6) | cost **B** (corpus fold, 1 859 entries) ≤ 120 ms; cost **C** (per-keystroke pass) ≤ 8 ms; cost **A** no regression in composed-row / entry-read counters. Titles come from the shipped `TxtMdTocProvider` run on the **real** pushed `黑暗血时代.txt` — re-push the book every run, the connected task wipes `/sdcard/Android/data/<pkg>/` at run end |
| `androidTest/.../nav/TocFilterFieldTest.kt` (WI-2) | resting placeholder "Filter chapters"; typing updates the hoisted state; clear (✕) appears only when non-empty and empties the query; Cancel clears + drops focus; count line hidden when the trimmed query is blank / shows "N of M chapters" / "No chapters match"; **renders across `ReaderTheme.entries`** (five, not four — finding 6; iterate, never hardcode a count); `contentDescription` on field + clear; **no** autofocus (the IME must not open on sheet open) |
| `androidTest/.../nav/TocContentsRowMatchTest.kt` (WI-3) | matched run carries the accent-tinted `SpanStyle` (asserted via the row's `AnnotatedString`/semantics text, not pixels); empty `matchRanges` renders a plain `Text`; a match on the current row composes with accent+SemiBold; **the rendered row text equals the row's `matchTitle`** for a leading-space title and an embedded-`\n` title (finding 1's rendering half); **a blank-titled row renders "Untitled" with no tint** (r2 NEW-1); an out-of-bounds range clamps instead of crashing (the `boldedSnippet` guarantee) |
| `androidTest/.../nav/TocContentsFilterTest.kt` (WI-4) | field is present on the Contents tab and **absent** on the Bookmarks tab; filtering narrows rows; a surviving row keeps its original ordinal and `toc-row-<originalIndex>` tag; the `toc-current-marker` stays on the right row; tapping a filtered row calls `onJump(originalIndex)`; no-match state (`toc-filter-no-match`) replaces the list — **including for a query that folds away entirely** (finding 4); pinned `toc-pinned-current` appears only when the active chapter is filtered out and jumps to it; **refining a non-empty query (`Chapter` → `Chapter 1999`) re-scrolls to the top** (finding 7); clearing restores the full list **and** re-scrolls to the current chapter; **`fastTypeThenClear_stillRestoresCurrentChapter`** — with `mainClock.autoAdvance = false`, type a query, advance a single frame so the effect launches but `scrollToItem` has not completed, then clear and resume the clock; assert `listState.firstVisibleItemIndex` is back at the current chapter (**r2 NEW-3** — deterministic mid-scroll cancellation; this test fails against the v2 flag ordering); the query survives a Contents→Bookmarks→Contents tab switch; the query survives rotation (`rememberSaveable`); a book with no TOC shows `toc-empty` and **no** field |
| `androidTest/.../nav/TocFilterSearchHandoffTest.kt` (WI-5) | **boundary:** CTA invokes `onOpenFullTextSearch(query)` with the trimmed query when the callback is non-null; CTA **absent** when null (AZW3/`Unsupported`, or a null `inBookSearchVm`) — no dead control. **Observable (r2 NEW-2, the one that matters):** `ctaOpensSearchSheetPrefilledWithTheTocQuery` — drive the real host composition, open Contents, type a query that matches nothing, tap **Search full text**, and assert the node `inbook-search-field` **displays that trimmed query**. Not that a lambda fired |

**These connected tests are compile-only until Gate 5 actually runs them.** This repo has shipped
compile-only connected tests twice (#135's `setContent`-twice, #133's 6/14 RED-on-first-run because
`waitForIdle` did not await a debounce). **Budget a test-hardening pass inside WI-1, WI-4 and WI-6**: run
each connected class **one at a time on a cold-booted emulator** (a comma-separated `class=A,B`
fast-fails with `tests=0`), and never drive the emulator while a `connectedDebugAndroidTest` is in
flight. The field's text-entry tests use `performTextInput`, not long-press/selection gestures, so
they are in the *render/click* family the repo has measured as non-flaky.

---

## 9. Gate-5 production reachability

Every file on the path is in `android/app/src/main/kotlin/` — none in `src/debug/`.

**User-visible path (TXT/MD, the motivating case):**
app launch → Library (`MainActivity` → `LibraryScreen`) → tap **黑暗血时代.txt** →
`TxtReaderActivity` → tap the page centre to show chrome → bottom toolbar **"Contents"**
(`ReaderBottomChrome.kt:132-135`, `testTag = "chrome-contents"`) → the two-tab TOC sheet opens on
**Contents** → **the filter field is directly below the segmented control** → type `第十`.

**EPUB:** Library → **道诡异仙 - 狐尾的笔.epub** → `ReaderActivity` → centre tap → **Contents**
(routed through `EpubReaderChrome.kt:258`) → same field.

**AZW3:** Library → an `.azw3` fixture → `Azw3ReaderActivity` → `Azw3ReaderChrome.kt:161` scaffold →
**Contents** → same field (with the WI-5 CTA omitted, since in-book search is `Unsupported` there).

**PDF is out of reach by design** — `PdfReaderScreen.kt:174` passes `tocEntries = emptyList()`, so
the Contents control itself is hidden. The Gate-5 evidence file must say so rather than claim
five-format coverage.

Gate-5b (WI-6) exercises the acceptance criteria on **real books first** (`test-books/books/`):
`黑暗血时代.txt` for the 1 859-entry CJK case and `道诡异仙 - 狐尾的笔.epub` for EPUB. Evidence goes
to `dev-docs/verification/feature-141-<YYYYMMDD>.md` per `dev-docs/verification/SCHEMA.md`.

---

## 10. Risks + mitigations

| Risk | Severity | Mitigation |
|---|---|---|
| **Ranges computed on one string, rendered against another** | High | *The defect Gate-2 r1 actually found* (finding 1) — measured wrong on a plain leading-space title, not just on line-break titles, and a crash in the mirror direction. Fixed structurally in §5.2.1: one match-string producer (`TocTitleFilter.matchTitle`), one rendered-text producer (`rowText`) that returns title **and** ranges as a single `TocRowText`, `TocContentsRow` accepting only that value, plus clamping and dedicated tests. |
| **A presentational fallback becomes matchable** | High | *r2 NEW-1* — v2's `displayTitle` emitted `"Untitled"`, so typing "untitled" would have matched every blank-titled row, contradicting §3 and failing v2's own named test. Resolved in §5.2.2 by reverting that half: the fallback lives in `rowText`'s untitled branch, which cannot reach a range source. Pinned by a test written to fail against the v2 spec. |
| **The title/ranges pairing is bound by a seam that can itself mispair** | Medium | *r3 edit 1* — v3's `rowText(row, folded, foldedQuery)` took the fold as an independent argument, relocating the finding-1 hazard into the seam built to close it. Closed by making `FoldedTitle` private to `TocFoldedToc` (never a parameter anywhere), and `TocRowText` non-`data` with a private constructor. The residual index parameter yields a *consistent* pair and is analysed in §5.2.1. |
| **Cost re-enters through the not-filtering branch** | Medium | *r3 edit 2, and the third occurrence of this shape* — see §6's standing note. Closed by the blank branch returning a singleton that carries no rows, and the `LazyColumn` iterating `entries` directly. Binding instruction, plus `blankQuery_returnsUnfilteredSingleton_notAList` written to fail against the v3 spec. |
| **A CTA test that asserts the callback instead of the outcome** | Medium | *r2 NEW-2* — the search field renders VM state (`ReaderActivity.kt:1142`, `TxtReaderActivity.kt:794`), so "the lambda fired" is compatible with the user seeing an empty field. §7.1 makes each host seed via `vm.onQueryChange` and WI-5 adds an observable assertion on the rendered field text. |
| **Effect-cancellation loses the restore-scroll memo** | Medium | *r2 NEW-3* — keying on `trimmedQuery` cancels the prior effect, so a fast type-then-clear skipped the restore and dumped the user at row 0. Fixed by recording intent before the first suspension point and by using a plain (non-snapshot) memo; pinned by a `mainClock.autoAdvance = false` connected test that fails against the v2 ordering. |
| Folded↔display index mapping is subtly wrong ⇒ the tint lands on the wrong characters | High | The `starts`/`ends` maps are WI-1's core. **Gate-2 r1's empirical auditor implemented this scheme and measured ~90 hostile inputs (Hangul, `İ`, stacked marks, surrogate pairs, Arabic/Hebrew marks, orphan marks, jamo queries) with zero wrong ranges** — so the mechanism is validated, not merely hoped for. The static auditor's contrary claim was disproven by that measurement and is not actioned. Kept top-rated anyway because the mechanism is subtle and the failure is silent; JVM tests pin every verified length-changing fold plus exact `(first, last)` bounds. |
| Matching diverges from iOS in a user-visible way | Medium | v1 asserted verbatim parity and was wrong on 3 of 4 exclusions (finding 2). Rev2 replaces the claim with the measured table in §3, closes the two user-facing gaps (ß, final sigma) via ICU full case folding, and pins the two accepted residuals (ligature, Arabic hamza) with named tests so neither can drift silently. |
| Filtering breaks the row ordinal / current-row marker / lazy-list identity | High | `entries` stays the FULL list and is what the lazy list iterates when unfiltered; when filtering, `TocFilterResult.Matched.indices` carries ORIGINAL indices and every derived value (`index + 1`, `isCurrent`, `entries[index]`, `onJump(index)`) reads that index. `key(tocIdentity, entries.size)` is untouched. Asserted by `filter_preservesOriginalIndices` + the connected ordinal/marker tests. |
| Retained `LazyListState` leaves the list at a stale offset after filter/clear | Medium | Explicit `scrollToItem` on both transitions (§5.2 step 6), asserted in `TocContentsFilterTest`. |
| **The one-time corpus fold hitches the first keystroke on device** | Medium-High | *The re-aimed perf risk* (finding 3). Desktop 18.66 ms; a 100× device factor is 1.87 s and even 5–10× is 93–187 ms, on the main thread, at the first keystroke. **A debounce cannot fix this** — it delays the fold, not its cost. Measured on target in **WI-1** (moved up from WI-6) so WI-4 knows before wiring whether to build §6's off-thread fold, which the design bundle sanctions and which invents no new UI state. |
| Per-keystroke cost is worse on device than on the JVM | Low | Desktop 0.035 ms vs an 8 ms budget — ~200× headroom, so even a 100× device factor lands at ~3.5 ms. Asserted on target in WI-1; the debounce fallback is pre-designed but not shipped speculatively (§6). |
| Sheet-open cost regresses for users who never filter | Low | v1's eager 1 859-title map (2.94 ms desktop) is removed; display titles stay per-visible-row as today. Pinned by the cost-A counter assertion. |
| ICU (`android.icu`) is unavailable under plain JVM unit tests | Low | Known and solved: `TocTitleFilterTest` runs under Robolectric, exactly as `SearchTextNormalizerTest.kt:16-17` already does; `robolectric:4.13` is already a `testImplementation` dep. Cost is slower JVM tests, not a blocked lane. |
| Adding a debounce later makes connected tests racy | Medium | If WI-6 forces a debounce, the same WI converts every filter assertion to `waitUntil` polling (#133 precedent). |
| `TocContentsSheetContent`'s 20+ existing `androidTest` call sites break | Low | All new parameters are defaulted; the null-query default keeps the composable self-owning its state, so legacy callers get a working field with no signature churn. |
| `TocContentsSheet.kt` grows past the ~300-line guideline | Low | It is 261 lines today. The field, the pinned row, and the no-match state all live in new files; only the derivations (~50 lines) land in it, and the existing per-row normalization block shrinks. Re-check at WI-4 and split into `TocContentsSheet+Filter.kt` if it crosses 300. |
| WI-5's callback threads through 5 host files at once | Low | One nullable, defaulted param per file; every host that cannot offer search passes `null` (no dead control). |

---

## 11. Backward compatibility

Nothing persisted changes. No Room migration, no `contracts/` change, no backup-format change, no
new `Notification`/DI binding. `TocEntry` is unchanged. The filter query is transient UI state
(`rememberSaveable`, discarded when the sheet closes), so there is no restore path and no older-client
concern. Every new public/internal parameter is defaulted, so no existing caller — production or test
— changes behavior until it opts in. An older backup restored into a build with this feature behaves
identically; a book opened in an older build after this ships is likewise unaffected.

---

## 12. Docs sync (rule 24)

`docs/architecture.md` — the Android reader-nav section gains `TocTitleFilter` if it enumerates
`nav/` components; check at WI-4. `README.md` — the Android features list gains "filterable Contents"
under the reader bullet at WI-6 (user-visible capability). Both are orchestrator-owned surfaces.

---

## 13. Revision history

> Gate-2 audit trail for this feature is committed at
> `.claude/codex-audits/plan-feature-141-gate2-audit.md`, including the round-1
> disproven-by-measurement section (the Hangul / emoji-ZWJ / combining-mark claim), so a later round
> cannot re-raise it without new evidence.


| Rev | Date | Change |
|---|---|---|
| v1 | 2026-08-06 | Initial Gate-1 draft. |
| v2 | 2026-08-06 | **Gate-2 round 1** — two independent audits (a broad static one; an empirical one that implemented §5.1 in Java, ran ~90 hostile inputs on JDK 17, and ran real `TOCTitleFilter.swift` over the same inputs). Both returned `block-recommended`. All 10 findings addressed: **(1 High)** §5.2.1 — one string, one owner: `TocTitleFilter.displayTitle` is the sole producer, `TocContentsRow.title` is required, ranges and rendering can no longer index different strings. **(2 High)** §3 — retracted v1's false "copied verbatim from iOS" claim, replaced with the measured iOS-vs-Android table, adopted option (b): per-code-point ICU `UCharacter.foldCase` (closes ß and Greek final sigma), NFKC still rejected, ligature + Arabic-hamza residuals declared and test-pinned, `SearchTextNormalizer` cited but explicitly not reused. **(3 Medium)** §6 rebuilt around three separately budgeted costs; the eager display-title map is deleted; the corpus fold is named as the sole >100 ms-class risk; noted that a debounce cannot fix it; off-thread fallback pre-designed with a rule-51 check; `TocFilterCostTest` moved from WI-6 to **WI-1** so the structural decision precedes the wiring. **(4 Medium)** empty-query gating moved from the folded to the trimmed query (iOS parity) and declared. **(5 Medium)** inclusive-`IntRange` convention stated, `originalRange` no longer mixes conventions, exact-bounds test added, `boldedSnippet` reuse named. **(6 Medium)** `ReaderTheme` is five cases, not four — tests iterate `entries`. **(7 Medium)** scroll effect keyed on the query string, so refining a non-empty query re-scrolls. **(8 Low)** NBSP rationale corrected (Kotlin `trim()` does strip it); the redundant predicate dropped, the Java-`trim()` trap kept and test-pinned. **(9 Low)** `matchRanges` takes a `FoldedTitle`. **(10 Low)** softened the design's "~2k entries" corroboration and the "nothing is missing" design-coverage claim. **Pushed back (recorded, not actioned):** the static auditor's claim that the index map mis-highlights Hangul, emoji ZWJ, and combining marks — the empirical auditor measured exactly those cases as correct, so §5.1's map is kept intact and §10 records why. |
| v3 | 2026-08-06 | **Gate-2 round 2** (findings 1–6, 8–10 resolved at file:line; 7 partial; 3 new; `block-recommended`). **NEW-1 (High)** — v2's `"Untitled"` fallback made the blank-title contract self-contradictory (typing "untitled" would match every blank row, failing v2's own named test). **Reverted that half of the v2 fix**, plainly: `displayTitle` → `matchTitle` returning `""` for a blank row, the fallback moved into `TocTitleFilter.rowText`'s untitled branch, and the title+ranges pairing promoted from a convention (two parameters) to a **type** (`TocRowText`, the only way to obtain either) — strictly stronger than v2, since v2 still permitted mismatching a title from one row with ranges from another. New §5.2.2 documents the choice, the five guards, and the cost; `queryUntitled_matchesZeroRows_inTocWithBlankTitles` is written to fail against the v2 spec. **NEW-2 (Medium)** — WI-5 asserted the callback, not the outcome; verified that both search sheets render VM state (`ReaderActivity.kt:1142`, `TxtReaderActivity.kt:794`) so the CTA could fire while the user saw an empty field. New §7.1 specifies seed-then-open via `InBookSearchViewModel.onQueryChange` (`:214-220` — already the `onPickRecent` pattern), covers the nullable EPUB VM as a capability gate, and adds an observable connected assertion on the rendered field text. **NEW-3 (Medium)** — `wasFiltering` was assigned after the suspend `scrollToItem`, so a fast type-then-clear cancelled the effect before it recorded intent and skipped the restore. Intent is now recorded **before** the first suspension point, in a plain non-snapshot memo, with a `mainClock.autoAdvance = false` connected test that fails against the v2 ordering. **Pushed back:** nothing new; the r1 push-back stands and is now backed by the committed audit artifact. |
| v4 | 2026-08-06 | **Gate-2 round 3** — NEW-1/2/3 resolved, verdict moved to `follow-up-recommended`; two tightening edits, closed without a fourth round (rule 47 caps at three) and verified directly by the orchestrator. **Edit 1 (Medium)** — the `TocRowText` invariant was under-enforced: the type was arbitrarily constructible/`copy`able and `rowText` took `folded` as an independent argument, so a caller could pair one row's title with another row's fold — the finding-1 hazard *relocated* into the seam built to close it. Closed structurally: `FoldedTitle` is now **private to a new `TocFoldedToc` corpus** and is never a parameter, return value, or property anywhere; the corpus resolves `folds[index]` itself; `TocRowText` is **not** a `data class` and has a **private constructor**, obtainable only from `plainRowText` (no range source) or `TocFoldedToc.rowText`. §5.2.1 adds an explicit analysis of the one residual seam (the index) showing it yields a *consistent* pair — a visible wrong-row bug, not the silent mis-tint/crash class. **Edit 2 (Medium)** — the blank-query path still materialised 1 859 titles because `filtered` returned `List<TocFilterRow>` and every row carried a `matchTitle`, reinstating the cost §6 had just deleted. Closed by replacing the projection list with `TocFilterResult` (`Unfiltered` **singleton**, carrying no rows, vs `Matched(IntArray)`), and by the `LazyColumn` iterating `entries` directly on the unfiltered path — identical in shape to today's `TocContentsSheet.kt:182/:188`. `TocFilterRow` is deleted. §6 gains a **standing note** recording that this is the *third* time cost re-entered through the not-filtering branch (v1's eager map, v2's forced `Lazy`, v3's per-row titles), each time one edit after removal, with a binding instruction that the not-filtering path allocate no per-row object — and the explicit statement that a test which catches a violation is weaker than a shape that cannot express one. **Pushed back:** nothing; both edits were correct as framed. |
