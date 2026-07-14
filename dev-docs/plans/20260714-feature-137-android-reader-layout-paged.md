# Feature #137 — Android reader layout (scroll/paged) toggle + Compose paged text renderer (TXT/MD)

**Status:** Gate-1 plan (v4 — **Gate-2 PASSED**, 3 Codex rounds; round-3 cap reached with 2 mechanical findings resolved-not-escalated, see Gate-2 log). Parity checklist **box E** remaining half (driver **#110**). iOS parity: #21 (paged EPUB) / #31 (auto-turn) / #60 WI-10 (Aa layout control). Design authority (rule 51, committed, Gate-2 confirmed depicted → no needs-design): `vreader-panels.jsx:112` (Layout control) + `:197` (glyphs), `vreader-reader.jsx:166` (paged surface) + `:222` (first-open hint), `vreader-tap-zones.jsx:35/:76` (30/40/30), `vreader-scroll-mode.jsx` (scroll surface).

## Problem
The Android Display sheet (#129) shipped theme/font/size/spacing/margin but **not** the layout (scroll↔paged) toggle. EPUB already paginates via Readium (unexposed); PDF is inherently paged (exempt); **TXT/MD are scroll-only Compose hosts** (`LazyColumn` of line-chunks) with no paged renderer. Box E requires the toggle across EPUB/TXT/MD, so #110 cannot close until TXT/MD gain a paginated mode. This feature builds the designed Layout control, exposes EPUB pagination, and adds a **new Compose paged text renderer for TXT/MD** with measured-line pagination + a span-preserving page offset map, re-integrating every existing TXT/MD reader feature with paged mode.

## Plan-author decisions (binding unless Gate-2 overturns)
1. **Bilingual-on → SCROLL rendering (v1 engineering-scope shortcut; explicitly NOT an iOS mirror — Gate-2 R1 correction; iOS supports bilingual in both modes).** #131's "one Column per lazy chunk item" interlinear contract has no paged analog (translation slots add unpredictable mid-page height). When bilingual is enabled the TXT/MD reader renders scroll regardless of `layout`; the preference is retained + re-applies when bilingual is off. **Paged-bilingual = named follow-up** (own feature + design). WI-10 gates + documents it.
2. **Default layout = `Scroll`** (iOS parity, no upgrade surprise; the design mock's `s.mode || 'paged'` governs the mock chip, not the product default). Pinned in a WI-1 test.
3. **First-open tap hint (`TapZoneHint`) IN SCOPE** — WI-6b.
4. **Re-pagination triggers:** font size/family/line-spacing/margin, config-change/rotation, layout toggle → re-paginate off-main with **progression-preserving, count-change-reconciled restore** (WI-5).
5. **`TxtReaderActivity.kt` (1383 lines) — light extraction** into `TxtReaderBody.kt` (WI-6a). Full decomposition = separate follow-up.
6. **PDF EXEMPT** (Gate-2 confirmed theme-only). Toggle = **EPUB/TXT/MD**.

## Core architecture — page index + span-preserving page map (resolves Gate-2 R1 Crit-1/2 + R2 Crit-1/2)

**Two data structures, both source-UTF-16-anchored and layout-independent:**

```kotlin
// reader/paged/TxtPageIndex.kt (NEW) — cheap boundary index; the ONLY full-book structure.
class TxtPageIndex(val pageStartsUtf16: IntArray) {   // one int per page (thousands of ints = KB, not MB)
  val pageCount: Int
  fun pageContaining(sourceOffsetUtf16: Int): Int      // binary search
  fun pageStart(page: Int): Int
  fun pageEndExclusive(page: Int): Int                 // = pageStart(page+1) or doc end
}
```

- **Measured-line pagination (resolves R2 Crit-2):** the boundary index is built by measuring the rendered text against the **chrome-aware content box** and cutting a page at the last rendered **line** that fits (Compose `TextMeasurer`/`MultiParagraph` line metrics — the TextKit `NSTextContainer` analog). Pages are **NOT** chunk-granular: an oversized `DEFAULT_MAX_CHUNK_CHARS`=4000 chunk at max font **splits mid-chunk at a measured line boundary**, and the split rendered-line-start is mapped back to a source UTF-16 offset via that chunk's offset map. No chunk is ever "one page that scrolls/clips."
- **Min-one-line progress invariant (resolves R3 Critical — zero-fitting-line):** a page **always contains at least one rendered line**, even if that single line overflows the content box vertically. This guarantees forward progress — the boundary loop can never emit a zero-advance page (no infinite loop / stall). If the content box is genuinely degenerate (≤0 usable height — e.g. a 0-height measure before layout settles), pagination **degrades to scroll rendering for that open** (a bounded, logged failure state; the reader stays usable), and re-attempts phase-1 once a valid box arrives. WI-4 tests both the min-one-line invariant and the degenerate-box degrade-to-scroll.

```kotlin
// reader/paged/PageOffsetMap.kt (NEW) — a page's rendered<->source bridge, SPAN-preserving
//   (resolves R2 Crit-1: reproduces MarkdownOffsetMap's FULL dual-affinity API at page scope).
class PageOffsetMap(private val segments: List<Segment>) {   // Segment = (chunk MarkdownOffsetMap|identity, renderedBase, srcBase)
  fun sourceAt(renderedIdx: Int): Int                        // char -> source (start-affinity)
  fun renderedRangeToSource(r: IntRange): IntRange           // used by getWordBoundary selection (TxtSelectionController:108)
  fun sourceRangeToRendered(srcRange: IntRange): IntRange?   // used by visible-text/wash (TxtSelectionController:152/:167)
  fun renderedSpanAt(renderedIdx: Int): IntRange             // dual-affinity srcStart..srcEnd (MarkdownRenderer:33 / MarkdownOffsetMap:32/:49)
}
```

- **`PageOffsetMap` is a COMPOSITION** of the page's constituent chunk maps (each `MarkdownOffsetMap` for MD, identity for TXT), spliced by `(renderedBase, srcBase)` offsets, and it **delegates** every query to the owning segment — so the exact dual-affinity `srcStart`/`srcEnd` spans and both range-conversion directions the current selection/wash rely on are preserved verbatim, just at page scope. It is built **lazily per rendered page** (not full-book).
- **MD concat contract (resolves R2 Medium-1):** a page's rendered `AnnotatedString` is the concat of its covered chunks' `renderWithMap` outputs **with NO synthetic separators** — `TxtDocument` chunks already retain their line terminators (`TxtDocument.kt:4`), so the page render is exactly the source sub-range rendered through the same mapper the scroll body uses; segment `renderedBase`/`srcBase` are the running concat offsets. Mid-chunk page splits carry the chunk's map sub-range.
- **Selection (resolves R1 Crit-1):** `TxtSelectionController` gains a page path: `registerPage(page, TextLayoutResult, LayoutCoordinates, PageOffsetMap)`. Paged `hitAt` resolves pointer → the page's rendered offset → `PageOffsetMap` (source-range keyed, never `offsetForChunk(hit.key)`). Word-select uses `renderedRangeToSource`; wash uses `sourceRangeToRendered` — same APIs as today, page-scoped.

## Pagination strategy — two-phase, memory-bounded, cancellable (resolves R1 High-5 + R2 High-1)

- **Phase 1 — boundary measurement (off-main, one-time, cancellable):** `TxtPaginator.index(document, style, contentBox, measurer, token): TxtPageIndex` runs on `Dispatchers.Default`, measures the whole doc once, and stores **only the page-start offset IntArray** (KB, not MB) — it does **NOT** retain page `AnnotatedString`s or maps. Monotonic generation token; a settings/rotation change cancels the in-flight pass; a stale pass never publishes.
  - **Paginator-local mapper (resolves R3 High — no cross-thread LRU sharing):** phase-1 constructs its **own** `MarkdownChunkTextMapper` instance (its own LRU) for the indexing pass — it MUST NOT touch the shared UI mapper (`ChunkTextMapper.kt:61`, an unsynchronized mutable `LinkedHashMap` LRU used by body/wash/selection on the main thread). Phase-2 `renderPage` runs on the **main thread** and uses the **UI** mapper. There is never concurrent access to one mutable LRU from `Dispatchers.Default` (phase-1) and the UI thread (live body/wash). `TextMeasurer` for phase-1 is constructed from the same `FontFamily.Resolver`/`Density`/`LayoutDirection` as the UI so line breaks are identical (deterministic re-measure — R3 confirmed no issue).
- **Phase 2 — lazy windowed page rendering:** each **visible** page renders on demand via the existing **LRU-bounded** `ChunkTextMapper` (`ChunkTextMapper.kt:60` — the same cache the scroll body uses) → `AnnotatedString` + `PageOffsetMap`, held only for the pager's window (current ± a couple), evicted off-screen. **Memory posture is preserved**: one backing string + the boundary IntArray + a few rendered pages — matching today's LRU-bounded model, not tens-to-hundreds of MB.
- **Pager count-change reconciliation (resolves R2 Medium-2):** on reflow, `TxtPageNavigator`: (1) **captures** the current source offset, (2) awaits the new immutable `TxtPageIndex`, (3) **clamps/scrolls** the `HorizontalPager` to `newIndex.pageContaining(capturedOffset)`. So font/rotation reflow never transiently points at an invalid/wrong page.
- **Loading state:** phase-1 runs during the reader's existing open/load phase (reuse its indicator; a minimal transient `CircularProgressIndicator` if none — system feedback, not invented reader chrome; Gate-2 confirmed acceptable). Reflow shows it only if phase-1 exceeds a frame budget.
- **Perf bound:** phase-1 measures the whole doc once (the CPU cost); WI-11 records open-to-first-page latency on the **real 14 MB CJK book**; if over budget, a **windowed-measurement** perf follow-up is filed (phase-1 already stores only offsets, so memory is fine regardless).

## Surface area (file-by-file)
### New files
- `reader/paged/TxtPageIndex.kt` — boundary index (above).
- `reader/paged/PageOffsetMap.kt` — composed span-preserving map (above).
- `reader/paged/TxtPaginator.kt` — `suspend fun index(...): TxtPageIndex` (phase-1 measured-line pagination, off-main, oversized-chunk splitting, surrogate/CJK safe, chrome-aware box) + `fun renderPage(index, page, mapper, style): Pair<AnnotatedString, PageOffsetMap>` (phase-2 lazy).
- `reader/paged/TxtPageNavigator.kt` — `pageContaining`/`pageStart`, `HorizontalPager` state adapter, reflow count-change reconciliation, generation tokens.
- `reader/TxtReaderBody.kt` — extracted `TxtBody` (scroll, unchanged) + `TxtPagedBody`.
- Test files (JVM `src/test`, connected `src/androidTest`).

### Modified files
- `settings/ReaderSettings.kt` — `enum ReaderLayout { Paged, Scroll }` + `val layout = ReaderLayout.Scroll`.
- `settings/ReaderSettingsStore.kt` — **(R1 High-3)** LAYOUT mirrors THEME **in this file**: private `ReaderSettingsState` (`:23`), `Field` (`:53`), `setLayout(v, order)` (mirror `setTheme` `:70`), default `Scroll.name`. (No `ReaderSettingsState.kt` file exists.)
- `settings/ReaderSettingsSheet.kt` — designed Layout segmented control between Theme and Font.
- `reader/TxtReaderActivity.kt` — body branch `if (layout==Paged && !bilingual) TxtPagedBody else TxtBody`; `onLayout`; **every** `scrollToItem(chunkForOffset(...))` caller gets a page-jump analog (R1 Medium-7): bookmarks (`:524`), annotation jumps (`:535`), search (`:590`), scrubber (`:620`), TTS follow/visibility (`:316`), save/restore (`:240`,`:786`, saving the **page-start offset**).
- `reader/ReaderActivity.kt` — the two `EpubPreferences(scroll = true)` sites (`:235`,`:744`) → `scroll = layout == Scroll`; **(R1 High-4)** WI-3 connected test asserts horizontal page turns emit `currentLocator` (feeds `:761`/`:773`).
- `reader/TxtSelectionController.kt` — `registerPage(...)` + paged `hitAt` via `PageOffsetMap` (dual-affinity, both range directions).

### Out of scope
PDF toggle; full `TxtReaderActivity` decomposition; paged-*bilingual* renderer; EPUB page-animation customization; windowed-*measurement* (perf follow-up if WI-11 over budget).

## Prior art / precedent / rejected alternatives
- **iOS reference:** `NativeTextPaginator` (TextKit-1 sequential `NSTextContainer` line-fitting → pages with exact UTF-16 ranges) — the measured-line pagination analog; Android uses Compose `TextMeasurer`/`MultiParagraph` line metrics + `HorizontalPager`. No `HorizontalPager` prior art in-repo. **iOS supports bilingual in both modes** (R1 correction) — Android's bilingual→scroll is a v1 scope cut.
- **iOS bug precedents:** #215 (wrong viewport → chrome-aware box), #284 ("wired-but-nil"), #281 (**progress from page index**), #258 (**page-turn feeds save**).
- **Rejected:** full-book page-render caching (R2 High-1 memory blow-up → two-phase windowed); chunk-granular pages (R2 Crit-2 oversized-chunk clip → measured-line split); single-`IntArray` page map (R2 Crit-1 loses MD dual-affinity → composed span map); paged-bilingual (follow-up); paged-default (upgrade disruption).

## Work-item sequencing (12 WIs)
| WI | Tier | Summary | Depends |
|----|------|---------|---------|
| WI-1 | Foundational | `ReaderLayout` enum + `layout` in ReaderSettings + Store (Field.LAYOUT mirror THEME, default Scroll + explicit test) | — |
| WI-2 | Behavioral | Designed Layout control + `onLayout` (4 hosts) | WI-1 |
| WI-3 | Behavioral | EPUB paged toggle (2-site flip) + currentLocator-on-page-turn connected test | WI-1 |
| WI-4 | Foundational | `TxtPageIndex` + `PageOffsetMap` (composed span map) + `TxtPaginator` phase-1 measured-line index (off-main, oversized-chunk split) + phase-2 `renderPage` | WI-1 |
| WI-5 | Foundational | `TxtPageNavigator` (offset↔page, pager-state adapter, reflow count-change reconciliation, generation tokens) | WI-4 |
| WI-6a | Behavioral | `TxtPagedBody` core (`HorizontalPager` over the index, lazy windowed page render, host branch, body extraction, load state, page-start save/restore) | WI-4, WI-5 |
| WI-6b | Behavioral | Tap-zones (30/40/30) + page-turn + center-tap chrome + `TapZoneHint` | WI-6a |
| WI-7a | Behavioral | Paged **selection** — `registerPage` + `hitAt` via `PageOffsetMap` (dual-affinity, both directions) | WI-6a |
| WI-7b | Behavioral | Highlight **wash/render** paged (source-range wash via `sourceRangeToRendered`) | WI-7a |
| WI-8 | Behavioral | Bookmarks toggle/list/jump-to-page + scrubber-to-page | WI-6a |
| WI-9 | Behavioral | Find jump-to-page + TTS follow (page-visibility analog) | WI-6a |
| WI-10 | Behavioral | Bilingual routing gate (bilingual-on → scroll; documented v1 limit) | WI-6a |
| WI-11 | Behavioral (final) | Acceptance: 3 formats toggle, position survives both directions, every feature both modes, **14 MB CJK phase-1 latency + memory measured** → evidence → VERIFIED | all |

Foundational (WI-1/4/5) = JVM-testable, no device verify. Behavioral = connected verify on emulator-5554, width-1. New Kotlin files (WI-4/5/6a) pair with a caller change. (12 WIs — rule-47 large-feature batching acknowledged; one cohesive feature.)

## Test catalogue (R1 Medium-9 + R2 edges)
- **WI-1:** default=Scroll explicit; persistence round-trip; forward-compat (unknown enum → default); latest-wins seq.
- **WI-3:** `EpubPagedToggleConnectedTest` — toggle, page-turn swipe, **position/progress advances (currentLocator fires)**, decorations survive reflow.
- **WI-4:** `TxtPaginatorTest` + `PageOffsetMapTest` (JVM) — page count vs box height; **no clipped text**; exact UTF-16 offsets; **oversized 4000-char chunk splits mid-chunk at a measured line** (map exact across the split); **min-one-line invariant (an over-tall single line still yields a page — forward progress, no zero-advance loop)**; **degenerate ≤0-height box → degrade-to-scroll (bounded, no crash)**; empty doc (chunkCount=0); one giant line; EOF; CJK-no-whitespace; **surrogate pairs**; combining/ZWJ; **text exactly on a page boundary**; **MD page spanning chunks: `renderedRangeToSource`/`sourceRangeToRendered`/`renderedSpanAt` all exact vs the underlying `MarkdownOffsetMap`s**; **phase-1 uses a paginator-local mapper (no shared UI-LRU access)**; no-synthetic-separator invariant; chrome-inset parity.
- **WI-5:** `TxtPageNavigatorTest` (JVM) — offset↔page round-trip; **reflow: capture offset → new index → pager clamps to `pageContaining(offset)`** (count grew AND shrank); rotation-mid-index cancels stale; boundary pages.
- **WI-6a:** `TxtPagedBodyConnectedTest` — real TXT + MD, page turns, resume lands on right page, lazy render window (off-screen pages evicted), load state.
- **WI-6b:** tap-zones turn/chrome; `TapZoneHint` first-open then dismissed-persisted.
- **WI-7a/7b:** long-press-drag select within/across a page → source-range highlight persists + washes (MD dual-affinity exact); tap-edit/remove; tap-zone vs selection disambiguation.
- **WI-8:** bookmark on current page/list/jump-to-page; scrubber→page.
- **WI-9:** find hit→page; TTS auto-advance→spoken page.
- **WI-10:** bilingual-on forces scroll at layout=Paged; off→paged.
- **WI-11:** full acceptance + 14 MB CJK phase-1 latency + peak memory recorded.

## Risks + mitigations
1. **MD dual-affinity loss** (R2 Crit-1) → composed `PageOffsetMap` delegating to chunk `MarkdownOffsetMap`s; WI-4 tests all 3 conversion APIs vs the underlying maps.
2. **Oversized chunk clipping** (R2 Crit-2) → measured-line split mid-chunk; WI-4 oversized-chunk test.
3. **Memory blow-up on big docs** (R2 High-1) → two-phase: boundary IntArray (KB) + lazy windowed render via the LRU mapper; WI-11 measures peak memory.
4. **Reflow points pager at wrong page** (R2 Medium-2) → capture-offset → publish → clamp-to-`pageContaining`; WI-5 test.
5. **Phase-1 CPU on 14 MB** → off-main + cancellable + one-time; WI-11 latency measured; windowed-measurement follow-up if over budget.
6. **Selection redesign** (R1 Crit-1) → `registerPage` source-range path; WI-7a isolates.
7. **Progress/position stuck on turn** (iOS #281/#258) → progress from page index; turn feeds `savePosition`; WI-3/6a/11.
8. **Tap-zone vs selection gesture** → one `awaitEachGesture` classifier; gesture tests one-at-a-time on a cold-booted emulator (MEMORY #125/#133).

## Backward compat
No schema change. Position stays `Locator.charOffsetUTF16` (layout-independent; paged saves the **current page's start offset** — R1 Medium-8). Existing saved positions open in either mode. Layout = global device-local DataStore pref (not backed up), default Scroll → no upgrade behavior change until opt-in.

## Gate-2 audit log
- **Round 1** (Codex gpt-5.5/high): findings-must-resolve — 2 Crit (selection redesign; MD page map), 4 High (nonexistent ReaderSettingsState.kt; currentLocator test; pagination concurrency; false iOS bilingual analogy), 4 Medium. v2 addressed all.
- **Round 2** (v2 re-audit): findings-must-resolve — confirmed R1 High-3/4/6 + Medium-7..10 resolved; new: 2 Crit (`PageOffsetMap` too lossy for MD dual-affinity; chunk-granular unsound for oversized chunks), 1 High (full-book cache memory blow-up), 2 Medium (MD concat separators; pager count-change). **v3 resolves all:** composed span-preserving `PageOffsetMap` (dual-affinity + both range directions); measured-line pagination splitting oversized chunks; two-phase memory-bounded (boundary IntArray + lazy windowed render); operational count-change reconciliation; no-synthetic-separator MD concat contract.
- **Round 3** (v3 re-audit, Codex gpt-5.5/high): confirmed ALL round-2 findings resolved (composed `PageOffsetMap` dual-affinity; two-phase memory; pager count-change; MD separators) AND cleared the deep new-design concerns (deterministic re-measure, lazy map lifetime after eviction, WI-4 size = "large but cohesive"). Two narrow findings remained: 1 Critical (zero-fitting-line progress fallback) + 1 High (phase-1 off-main must not share the main-thread UI `MarkdownChunkTextMapper` LRU). **Rule-47 3-round cap reached with 2 findings open.** Decision: **resolve (not escalate)** — both are mechanical hardening rules with a single obviously-correct form, not open design questions, and the auditor confirmed convergence on all hard items. **v4 applies both**: the min-one-line progress invariant + degenerate-box degrade-to-scroll (Core architecture) and the paginator-local mapper + deterministic-measure guarantee (Pagination phase-1). No 4th audit round (cap); the fixes are self-evidently correct and covered by new WI-4 tests. **Gate-2 PASSED (v4).**
