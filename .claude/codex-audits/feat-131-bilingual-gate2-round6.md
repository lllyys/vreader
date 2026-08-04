Reading additional input from stdin...
OpenAI Codex v0.144.1
--------
workdir: /Users/ll/workspace/vreader
model: gpt-5.6-sol
provider: openai
approval: never
sandbox: read-only
reasoning effort: high
reasoning summaries: none
session id: 019f549b-0a35-7e51-8599-a276d74a5557
--------
user
Gate-2 plan audit ROUND 6 (MICRO-CONFIRM, DECISIVE) for feature #131 (Android bilingual interlinear reading). Read the v6 plan at dev-docs/plans/20260710-feature-131-android-bilingual-interlinear.md. Round 5 was block-recommended with EXACTLY ONE residual High (all other items — H1 Utf16Span, H3 Paragraph-only, H4 WI-AIP split, Gap A DDL, Gap B backup flag, and H2's index/layout core — were confirmed RESOLVED and must NOT be re-audited). v6 is a MICRO-PATCH resolving only that one residual.

The residual (round-5 High): the in-item Column render contract (round-4 H2 fix) makes each TXT/MD lazy item taller than its source line (source Text + translation children), so the TTS auto-scroll guard's item-level visibility check (listState.layoutInfo.visibleItemsInfo item index equals spokenChunk, reader/TxtReaderActivity.kt ~252/256) no longer proves SOURCE visibility: when spokenChunk's source Text has scrolled above the viewport but its translation sibling is still visible, visibleItemsInfo still contains the item index, so the guard falsely suppresses animateScrollToItem(spokenChunk) and leaves the spoken source off-screen.

v6 fix (audit ONLY this): the plan's new section-2 H2 TTS-visibility bullet + WI-8 now require the TTS-visibility predicate to key off the registered SOURCE Text bounds instead of visibleItemsInfo item index — spokenChunk is visible iff its registered source bounds intersect the list viewport, else animateScrollToItem(spokenChunk) scrolls the source into view; a translation-only-visible connected test is added; the fix is inert when bilingual is OFF (item height equals source height).

Verify against live code:
1. Does the selection controller actually track each source chunk's LayoutCoordinates / boundsInWindow that the TTS predicate can consult? Check reader/TxtSelectionController.kt (registerChunk signature and what it stores — coordinates/bounds) and reader/TxtReaderActivity.kt (registerChunk call site ~1062, the current TTS guard ~252/256). Confirm the registered source bounds are available and sufficient to compute source-in-viewport for spokenChunk.
2. Does keying TTS visibility off the source bounds correctly resolve the translation-only-visible case (source above viewport, translation visible) AND all prior cases (source fully visible -> no scroll; source below viewport -> scroll)?
3. Is the fix genuinely inert when bilingual is OFF (item height equals source height, so source-bounds visibility equals item-index visibility)?
4. Any NEW issue introduced by this micro-patch (e.g. the source bounds being stale/null before first layout, or a chunk not yet registered)? If so, is it bounded/handled?

Do NOT re-audit anything else. Output findings by severity (Critical/High/Medium/Low) with file:line evidence, then a FINAL VERDICT line exactly one of: ship-as-is | follow-up-recommended | block-recommended. ship-as-is or follow-up-recommended clears Gate-2.
codex
I’ll perform the requested micro-audit only: the new v6 TTS source-bounds contract, its WI-8 coverage, and the live selection/reader plumbing it depends on. I’ll first capture repository state, then read the plan and only the cited code paths.
exec
/bin/zsh -lc "git status -sb && sed -n '1,240p' dev-docs/plans/20260710-feature-131-android-bilingual-interlinear.md && rg -n \"registerChunk|visibleItemsInfo|animateScrollToItem|spokenChunk|boundsInWindow|LayoutCoordinates\" android reader . 2>/dev/null" in /Users/ll/workspace/vreader
 exited 2 in 941ms:
git: warning: confstr() failed with code 5: couldn't get path of DARWIN_USER_TEMP_DIR; using /tmp instead
git: error: couldn't create cache file '/tmp/xcrun_db-DRPjDRgd' (errno=Operation not permitted)
## main...origin/main
 M dev-docs/plans/20260710-feature-131-android-bilingual-interlinear.md
 M docs/features.md
?? .claude/codex-audits/feat-131-bilingual-gate2-round2.md
?? .claude/codex-audits/feat-131-bilingual-gate2-round3.md
?? .claude/codex-audits/feat-131-bilingual-gate2-round4.md
?? .claude/codex-audits/feat-131-bilingual-gate2-round5.md
?? .claude/codex-audits/feat-131-bilingual-gate2-round6.md
?? .claude/codex-audits/feat-136-ai-provider-reachable-gate2.md
?? android/2026-06-29-223908-this-session-is-being-continued-from-a-previous-c.txt
?? dev-docs/security/
# Feature #131 — Android Bilingual Interlinear Reading (parity-checklist box D)

**Feature number assumption:** highest active row in `docs/features.md` is `#136` (now CLOSED, see below); `#131` is a landed `PLANNED` row (`GH: #1923`). The orchestrator adjusts if a row is claimed first.

**Design authority (rule 51):** the **authoritative** bilingual surfaces are:
- `dev-docs/designs/vreader-fidelity-v1/project/vreader-bilingual.jsx` (`BilingualSetupSheet` / `BilingualPageContent` / `BilingualPill` / `BILINGUAL_LANGS`) — the setup sheet, the **paragraph-interlinear** renderer, and the top-chrome pill.
- `.../vreader-reader.jsx` (`ReaderTopChrome` renders `BilingualPill`; the bilingual toggle is a More-menu row via `onMoreAction`) and `.../vreader-more.jsx` (the "Bilingual mode" More-menu Row toggle).
- **The in-reader AI-config surface (folded in from the closed #136):** `dev-docs/designs/vreader-fidelity-v1/project/design-notes/reader-ai-provider-entry.md` (the CANONICAL **Variant A** decision + navigation model, lines ~39–76, ~110–134) and `.../vreader-ai-provider-entry.jsx` (`AIProvidersSheet`, `AIProvidersSheetBody`, `ProviderRow`, `NavSheet`, `BilingualEngineStrip`). `reader-ai-readiness.md` (iOS #82) is **informational only** — its 4-gate readiness (feature flag + consent manager + provider + key) is iOS-specific and **implementation-deferred**; Android #118 has no feature flag and no consent manager, so the Android readiness gate is provider+key only (see §"AI-config reachability").

`.../vreader-ai-android.jsx` contains a SECOND, differently-shaped `BilingualSetupSheet` — see §3's setup-sheet resolution for why this plan reproduces the `vreader-bilingual.jsx` sheet and design-gates the divergence. Where a surface is NOT depicted it is scoped out and flagged.

**Status:** Gate-1 draft **v6** (2026-07-12) — Gate-2 round-4 (block-recommended) findings resolved (4 High + 2 gaps; targeted patch of v4). Round-4 CONFIRMED M1/M2/M3/M4 (EPUB single-owner flow, dual-cancellation + single-flight, blank-model fallback, DI sequencing) RESOLVED — those are UNCHANGED. Round-4 CONFIRMED the Lows (AppContainer has no `AiProviderStore`, `aiConfigured` semantics, upsert-first-activate, deps/WI-count) correct — those are KEPT. Round-5 (focused) CONFIRMED H1/H3/H4 + gaps A/B resolved and H2's index/layout core resolved, but found ONE narrow NEW High: the in-item `Column` (the round-4 H2 fix) makes each item taller than its source line (source + translation), so the TTS auto-scroll guard's item-index visibility check no longer proves SOURCE visibility — **fixed in v6** (TTS visibility keys off the registered source `Text` bounds). Awaiting Gate-2 round-6 (micro-confirm of the TTS fix).

## 1. Problem

iOS ships bilingual interlinear reading (#56/#100): a per-book toggle renders each source paragraph followed by its translation in a muted style, backed by an AI provider, cached to disk. Android shipped the #118 AI provider foundation (provider store, OpenAI-compat + Anthropic SSE clients, chat/summary) but has **no bilingual capability**, and — as the Gate-2 audits proved — **no production-reachable AI-provider config surface** either. Box D of the parity checklist requires the interlinear renderer + the bilingual setup sheet + the AI-config entry, all building on #118.

The engineering questions are (a) **which render host(s)** get true interlinear, (b) **what the real TXT/MD segmentation unit is** (there is no chapter model — round-2 H1), (c) **how the enabled render preserves the live per-chunk layout/selection model AND the live lazy-index↔chunk-index identity** (round-3 H2 + round-4 H2), and (d) **where the entry point AND the AI-config path live**. The render-host feasibility was settled in v2 (EPUB-primary via Readium `EpubNavigatorFragment.evaluateJavascript`; TXT/MD Compose; AZW3/PDF deferred) and was **CONFIRMED correct by the Gate-2 round-2 audit** — it is not revisited here. This v5 resolves the round-4 findings that concern *how the render maps to real code* and preserves everything round-4 confirmed correct:

- **Host** — EPUB is the **primary** target via `EpubNavigatorFragment.evaluateJavascript(script): String?` (public suspend method in the shipped Readium 3.3.0 AAR — round-2 re-verified; `ReaderActivity.navigator: EpubNavigatorFragment?` is the concrete field, `ReaderActivity.kt:110`). TXT/MD (Compose) are built alongside as the deterministic pipeline proof.
- **TXT/MD unit (round-2 H1)** — `TxtDocument` has NO chapter model; it is line-based ≤4000-char chunks addressed by UTF-16 offset. v5 defines **document-global units with segment UTF-16 spans produced ONCE by the segmenter** and renders source/translation pairs from those same spans, with the **round-3 H1 final-chunk math fix**, the new **round-4 H1 `Utf16Span` value type** (§2, replacing `IntRange`), and the **round-4 H2 one-lazy-item-per-chunk `Column` render contract** (§2, §3).
- **Entry point** — the design puts the toggle in the **More-menu** (`vreader-more.jsx`; the live `MoreActionId.BILINGUAL` id is already reserved, and `MoreRow.Toggle` carries `on`/`onToggle` — `reader/more/MoreRow.kt:24,56–63`) + a **top-chrome pill** (`vreader-reader.jsx`). Both landed as box-F sub-features **#132 (top chrome) and #134 (More menu), now VERIFIED** — the entry wiring targets them directly (§4).
- **AI-config path (folded in — #136 CLOSED)** — the ONLY designed Android AI-config reader surface is the **Variant A scoped "AI Providers" sheet pushed inside the bilingual flow**, reached from the bilingual engine strip's "Set up"/"Change…" button (`reader-ai-provider-entry.md`). #131 now owns it end-to-end (§"AI-config reachability", WI-4b + WI-AIP + WI-9).

## 2. Surface area

### Render-host decision (settled in v2, CONFIRMED by round-2 — not reopened)

**Two hosts, in dependency order:**

1. **EPUB (Readium `EpubNavigatorFragment`) — PRIMARY.** Interlinear via `evaluateJavascript` (enumerate leaf blocks → inject translation DOM nodes → clear on teardown/reflow), mirroring iOS `EPUBBilingualOrchestrator`. Gated by **WI-0 (a Readium bilingual spike with enforceable go/no-go thresholds + a navigator-race contract — round-2 M1)** before the EPUB render WI (WI-7b) is built.
2. **TXT/MD (Compose `TxtReaderActivity`) — INCLUDED.** No WebView; deterministically Compose-testable. Renders translations **inside the SAME lazy item as their anchor source chunk** (round-4 H2 — one lazy item per chunk, a wrapping `Column`), from **document-global segment `Utf16Span`s** (round-2 H1 + round-4 H1).

**AZW3 (foliate WebView)** and **PDF** remain follow-ups / out (§"Files OUT of scope").

**Why both, not TXT/MD-only:** the *pipeline* (segment → chunk → translate → cache → interleave) is host-agnostic; only the *render injection* is host-specific. EPUB is the format most users read, so shipping box D without it would under-deliver. TXT/MD are included because the Compose host is the cheapest, most testable place to prove the pipeline end-to-end (deterministic tree assertions), de-risking the EPUB adapter. **Box D cannot be checked on a false "EPUB requires a fork" rationale** — that rationale is discarded and stays discarded.

### The TXT/MD segmentation unit + render mapping (round-2 H1 + round-3 H1 + round-4 H1/H2 — the core corrections)

**Verified against live code:** `TxtDocument` (`reader/TxtDocument.kt`) exposes only `text: String`, `chunkCount` (`starts.size`, TxtDocument.kt:14), `offsetForChunk(index)` (TxtDocument.kt:17), `chunkForOffset(offsetUtf16)` (TxtDocument.kt:23), `textForChunk(index)` (TxtDocument.kt:36) — line-based ≤4000-char chunks over UTF-16 offsets against the RAW text (no line-ending normalization). It has **no chapter/section concept**.

**Chunk semantics (round-3 Low-2 correction — the real cases):** a chunk is **ONE LINE** — `TxtDocument.of` starts a new chunk after every `\n`, `\r`, or `\r\n` (TxtDocument.kt:65–86; a runaway line >4000 chars is additionally hard-split, never mid-surrogate-pair). Therefore:
- A **chunk can hold multiple SENTENCES** (one line, several `。！？`/`. ! ?` sentences).
- A **paragraph spans MANY chunks** (blank-line-delimited paragraph = several physical lines = several chunks).
- The old v3 claim "a chunk can hold multiple **paragraphs**" is **WRONG and removed.** (A single chunk cannot straddle a line terminator, and paragraph boundaries are blank lines, i.e. chunk boundaries — so a chunk holds *part of one* paragraph, never a whole extra paragraph.)

**v5 model — document-global units with segment spans produced ONCE:**

- The whole `.txt`/`.md` is treated as **one translation document**. The **segmenter runs once over `TxtDocument.text`** (the full raw backing string) and emits, per segment, its **UTF-16 span as a `Utf16Span(start, endExclusive)`** (half-open) against that same backing string (the segmenter's `paragraphRanges(text): List<Utf16Span>` / `sentenceRanges(text): List<Utf16Span>` — the span-returning peers of `paragraphs`/`sentences`; iOS precedent `ChapterSegmenter.sentenceRanges(in:)` at `ChapterSegmenter.swift:78`, returns `[Range<Int>]`). These spans are the SINGLE source of truth used by BOTH the translate side and the render side, so the two segment identically **by construction** (they read the same array). Spans are stored/compared as the explicit `Utf16Span` value type (see the H1 fix below), NOT re-derived on the render side.
- **Unit granularity for TXT/MD is the whole document, sub-batched for cache/prefetch by a deterministic "unit window."** To avoid translating a 14 MB book at once (and to keep cache rows bounded), segment spans are grouped into fixed **unit windows** of contiguous segments (window size a build-time constant; it does not change the 1:1 contract). Each window is a `TranslationUnitId(kind = txtDocSegmentWindow, value = windowIndex)` — a document-global index, NOT a chunk index. `unitContaining(charOffsetUTF16)` maps the reader's saved offset → the segment whose span contains it → its window index (via a precomputed segment-start binary search, the same shape as `TxtDocument.chunkForOffset`, TxtDocument.kt:23–33). `unitAfter(unit)` = next window index or null at document end.

#### H1 fix (round-3 High-1 math + round-4 High-1 type) — final-chunk source span + the `Utf16Span` value type (BINDING)

**The math (round-3 High-1 — CONFIRMED correct by round-4, UNCHANGED):** `offsetForChunk()` **CLAMPS** an out-of-range index to the last valid chunk (`starts[index.coerceIn(0, starts.size - 1)]`, TxtDocument.kt:17–20). So for the LAST chunk `i`, `offsetForChunk(i + 1) == offsetForChunk(i)` → an **empty span** → a one-chunk document drops EVERY translation and a paragraph ending in the final chunk drops its sole translation. `textForChunk()` avoids this by using `text.length` for the final end (TxtDocument.kt:39). The render side MUST do the same. **Binding rule:**

```
val endExclusive = if (i + 1 < document.chunkCount) document.offsetForChunk(i + 1) else document.text.length
// chunk i source span is the HALF-OPEN Utf16Span(document.offsetForChunk(i), endExclusive)
```

**The type (round-4 High-1 — THE fix this round):** v4 declared `paragraphRanges`/`sentenceRanges` as `List<IntRange>` while treating them as half-open `[start, endExclusive)`. That is a **type contradiction** — Kotlin `IntRange` is inclusive-inclusive (`range.last` is the last *included* index, and `range.last` for an empty/at-EOF span is a footgun). The half-open contract and the `IntRange` type are incompatible. **Resolution — a dedicated value type, replacing `IntRange` EVERYWHERE:**

```
// bilingual/Utf16Span.kt  (NEW FILE — rides WI-1)
data class Utf16Span(val start: Int, val endExclusive: Int) {
    init { require(endExclusive >= start) }
    val isEmpty: Boolean get() = endExclusive == start
    val length: Int get() = endExclusive - start
}
```

- `ChapterSegmenter.paragraphRanges(text): List<Utf16Span>` / `sentenceRanges(text): List<Utf16Span>` return `Utf16Span`s (half-open, against the input string). `TxtChapterTextProvider` and the TXT/MD render path consume `Utf16Span` — there is **no `IntRange`** anywhere in the segment/span contracts. (`TxtSelectionController`'s own `Utf16Range` type is a *separate*, unrelated selection type and is untouched — see H2's gesture-exclusion note.)
- A segment's "end offset" for anchoring (below) is its `endExclusive`; the chunk that "contains a segment's end" is `document.chunkForOffset(span.endExclusive - 1)` when `!span.isEmpty`, clamped to `[0, chunkCount-1]` (an empty segment is dropped by the segmenter and never anchored).
- **Tests (WI-1 / WI-4a / WI-8):** `paragraphRanges`/`sentenceRanges` return correct half-open `Utf16Span(start, endExclusive)` spans (unit — WI-1); one-chunk document (no trailing newline) → its single paragraph/sentence translation renders (not dropped); final-chunk anchor (a paragraph whose last line is the final chunk) → translation renders after the last chunk; exact-boundary (a segment ending exactly at a chunk `start`) → anchored to the correct chunk, not off-by-one; EOF anchor (`span.endExclusive == text.length`) → resolves to the last chunk, no clamp-collapse.

#### H2 fix (round-3 High-2 layout/selection + round-4 High-2 lazy-index identity) — the enabled render contract (BINDING; preserves BOTH the per-chunk model AND lazy-index==chunk-index)

**Live invariant #1 — per-chunk layout/selection (round-3 High-2, verified TxtReaderActivity.kt:1043–1085):** the TXT/MD body iterates `items(count = document.chunkCount, key = { it })` (TxtReaderActivity.kt:1043). For **each chunk `i`** it owns **exactly ONE `TextLayoutResult`** (`var layout by remember(i) { … }`, set in `onTextLayout`, TxtReaderActivity.kt:1059/1075) and **exactly ONE selection registration** (`selectionController.registerChunk(i, l, c)` / `unregisterChunk(i)`, TxtReaderActivity.kt:1062–1066). Highlights (`highlightSpan(i)`, :1047), annotation washes (`washesForChunk(i)`, :1058), the read-aloud span wash (`addStyle(SpanStyle(background = wash), …)`, :1050–1054), and selection accents (`selectionForChunk(i)` → `drawRangeFill`, :1069/1081) all key off that **per-chunk** layout and the chunk-local UTF-16 offsets. **Splitting a chunk's source `Text` into multiple `Text` nodes would break every one of these** (two `Text` nodes = two `TextLayoutResult`s = broken selection coordinates, misplaced highlight/wash/annotation ranges, a shifted read-aloud wash).

**Live invariant #2 — lazy-index == chunk-index (round-4 High-2 — THE key fix this round; verified):** the live reader treats `LazyListState` item indices as `TxtDocument` chunk indices EVERYWHERE:
- **Position save** converts `firstVisibleItemIndex` → offset via `offsetForChunk` (`savePosition(...) { val offset = document.offsetForChunk(topIndex) }`, TxtReaderActivity.kt:623–624), and the steady-state/onStop save both pass `listState.firstVisibleItemIndex` directly (TxtReaderActivity.kt:220–223, :227–230). Resume converts back via `chunkForOffset` (`initialFirstVisibleItemIndex = s.initialIndex`, :220; `s.initialIndex` = `document.chunkForOffset(offset)`, :619). The bottom-chrome progress fraction reads `document.offsetForChunk(listState.firstVisibleItemIndex)` (:473).
- **Bookmark / annotation / search / scrubber / TTS jumps** all call `listState.scrollToItem(document.chunkForOffset(target))` (bookmark :411, annotation :421, search :454, scrubber :481; TTS auto-scroll `animateScrollToItem(spokenChunk)` where `spokenChunk = document.chunkForOffset(tts.charStart)` — :252/:257).
- **TTS visibility** compares lazy-item indices with the chunk directly: `listState.layoutInfo.visibleItemsInfo.none { it.index == spokenChunk }` (:256).

**Therefore inserting SEPARATE translation `LazyColumn` items (the v4 "additive items after the anchor chunk" contract) is NOT implementable:** every separate translation item inserted before a given source chunk shifts that chunk's lazy index, so `offsetForChunk(firstVisibleItemIndex)` reads the wrong chunk's offset (corrupts position save + progress), `scrollToItem(chunkForOffset(target))` lands on the wrong item (corrupts every jump), and `visibleItemsInfo.index == spokenChunk` never matches (corrupts TTS auto-scroll). The v4 contract is **rejected**.

**v5 binding render contract (one lazy item per chunk — a wrapping `Column`):**

> **Keep EXACTLY ONE lazy item per chunk.** The existing `items(count = document.chunkCount, key = { it })` loop is **UNCHANGED** — so lazy-index == chunk-index is preserved and NO position/jump/TTS consumer breaks. INSIDE each item's lambda, wrap the content in a `Column`:
> 1. the **UNCHANGED source `Text`** — one `TextLayoutResult`, one `registerChunk(i, …)`/`unregisterChunk(i)`, byte-identical to today (the exact code at TxtReaderActivity.kt:1044–1084 is unchanged, now nested in a `Column`);
> 2. **below it, still inside the SAME lazy item**, the translation(s) **anchored** to chunk `i` (`chunkForOffset(span.endExclusive - 1) == i`) as **muted, non-registered** `Text`(s) (accent left-border, `fontSize*0.88`, CJK/RTL styling per `BilingualPageContent`).

A paragraph spanning chunks `j..i` renders its ONE translation inside chunk `i`'s `Column` (after the paragraph's last source line). This preserves BOTH invariants: the per-chunk one-layout/one-registration model (the source `Text` is never split, the translation is a *sibling* `Text` in the `Column`, not a re-layout of the source) AND the lazy-index↔chunk-index identity (the translation lives inside the anchor's lazy item, adds no lazy item, shifts no index).

Concretely the body becomes, per chunk `i` (in the same single `items(count = document.chunkCount, key = { it })` loop):

1. Open a `Column` for item `i`.
2. Render the source chunk `i` **EXACTLY as today** (the unchanged `Text` + its `remember(i)` layout/coords + `registerChunk(i, …)`/`unregisterChunk(i)` + `highlightSpan(i)`/`washesForChunk(i)`/`selectionForChunk(i)` — TxtReaderActivity.kt:1044–1084, now the first child of the `Column`).
3. Look up the translations **anchored** to chunk `i` = every segment whose end resolves to `chunkForOffset(span.endExclusive - 1) == i`, in segment order, from the shared span array. For **paragraph** granularity (the only v1 granularity — see the granularity subsection) there is at most one such translation per anchor chunk in the common case (a paragraph's translation renders after the paragraph's last line-chunk).
4. Emit each anchored translation as a muted, non-registered `Text` sibling **inside the same `Column`**, keyed by the segment's `Utf16Span` so a language change re-keys cleanly.

When bilingual is **OFF**, no translation children are emitted → each item's `Column` holds only the unchanged source `Text`, so the tree is **behaviorally identical to today** (translations are additive in-item children only; this is asserted by a source-selection-parity test, since a single-child `Column` does not perturb the source `Text`'s layout/registration/offsets).

- **Explicit translation gesture exclusion (round-4 High-2 — BINDING):** `TxtSelectionController.hitAt` (`reader/TxtSelectionController.kt:47`) falls back to the **nearest registered source chunk** when the pointer is outside all source-chunk bounds (`chunks.entries.minByOrNull { verticalDistance(...) }` when no chunk's `boundsInWindow()` contains the point, :51–53). So merely omitting `registerChunk` for the translation does **NOT** make it non-selectable — a long-press *on the translation text* would fall through to the nearest source chunk and select source. **WI-8 must add an explicit hit-test / gesture exclusion for the translation composable's bounds** so a long-press whose pointer lands inside a translation `Text`'s bounds is consumed (no selection begun) rather than routed to `hitAt`'s nearest-chunk fallback. (Options: the translation `Text` consumes the long-press gesture in its own `pointerInput`; or the selection gesture root records the translation composables' window bounds and short-circuits `beginAt` when the point is inside one. WI-8 picks and tests one.)

- **TTS auto-scroll visibility must key off the SOURCE `Text` bounds, NOT the item index (round-5 High — a NEW consequence of the in-item `Column`):** the TTS auto-scroll guard (TxtReaderActivity.kt:252/256) currently keeps the spoken chunk on screen via `listState.layoutInfo.visibleItemsInfo.none { it.index == spokenChunk }` — item-level visibility. With the in-item `Column`, an item is now taller than its source line (source + translation children), so when `spokenChunk`'s SOURCE `Text` has scrolled above the viewport but its translation sibling is still visible, `visibleItemsInfo` still contains the item's index → the guard falsely suppresses `animateScrollToItem(spokenChunk)` and leaves the spoken SOURCE off-screen. **WI-8 must redefine the TTS-visibility predicate to test the registered SOURCE `Text` bounds** — the selection controller already tracks each source chunk's `LayoutCoordinates`/`boundsInWindow()` via `registerChunk(i, layout, coordinates)` (TxtSelectionController.kt): `spokenChunk` is visible iff its registered source bounds intersect the list viewport; otherwise `animateScrollToItem(spokenChunk)` scrolls the item's top (the source) into view. This is **inert when bilingual is OFF** (no translation child → item height == source height → item-index visibility already equals source visibility), so the disabled path is byte-identical.

- **Enabled-mode tests (WI-8 connected + WI-7a Compose, BINDING):** with bilingual ON —
  - (a) each source chunk's **selection registration is UNCHANGED** (same `registerChunk(i, …)` count and coordinates as OFF; a translation child registers nothing);
  - (b) **highlights/annotation washes/read-aloud wash still key off the source chunks** at the correct offsets (a translation child in the anchor's `Column` does not shift them);
  - (c) **lazy-index == chunk-index preserved:** with bilingual ON — **position-save round-trips to the same chunk** (`offsetForChunk(firstVisibleItemIndex)` → save → reopen → `chunkForOffset(offset)` lands on the same chunk); **bookmark/annotation/search/scrubber jumps land on the correct chunk** (`scrollToItem(chunkForOffset(target))` scrolls to the right item); **TTS auto-scroll keeps the spoken SOURCE on screen — visibility keyed off the registered source `Text` bounds, NOT `visibleItemsInfo.index` (round-5 High)**, INCLUDING the case where only `spokenChunk`'s translation portion is visible (its source scrolled above the viewport) → TTS brings the SOURCE back on-screen; (assert the index-identity behaviors above are identical to the OFF baseline — no lazy index shift);
  - (d) a **long-press on translation text does NOT select** (gesture exclusion — the nearest-source-chunk fallback is not reached);
  - (e) a **translation child is non-selectable** and does not perturb source offsets (selecting across the source/translation boundary selects source only);
  - (f) **MD source mapping** — the markdown renderer (`mapper.renderedText(i)`, TxtReaderActivity.kt:1049) still owns the source chunk render; the translation child is plain muted text;
  - (g) **paragraph-spanning-many-chunks** renders exactly ONE translation (inside the paragraph's last chunk's `Column`), never per-line;
  - (h) final-chunk/one-chunk anchors render (H1).

- **Granularity — Paragraph ONLY in v1 (round-4 High-3):** `vreader-bilingual.jsx` `BilingualPageContent` (lines ~195–277) is a **paragraph-interlinear** renderer: it maps `page.paragraphs.map(...)` and renders **one source `<p>` followed by ONE translation `<p>`** per paragraph. **Sentence-granularity interlinear is depicted NOWHERE** — Sentence appears ONLY as an option in the `BilingualSetupSheet` Granularity segmented control (`vreader-bilingual.jsx:77`), never in the renderer, AND v4's "Sentence selectable + sentence cache identity active + paragraph-render fallback" was underspecified (no defined sentence→paragraph aggregation, so it would either render undesigned sentence items or serve paragraph content under a sentence cache key). **Resolution — v1 segments + caches + renders Paragraph ONLY:**
  - The `TranslationGranularity` enum + `ChapterSegmenter.sentenceRanges` API **stay as reserved FOUNDATIONAL code** (WI-1, with unit tests) so the future sentence-render is a render-only follow-up.
  - The v1 **render/cache/VM/setup-sheet path uses paragraph exclusively:** `promptVersion`'s granularity component is **always `paragraph` in v1**; there is **no `sentenceRanges` in the v1 render path**; the setup sheet's Granularity control is **descoped to Paragraph-only in v1** (a documented divergence, tracked by the sentence design gate below — the same treatment as the Style descope).
  - This keeps rule 51 (implement only what is depicted — paragraph interlinear) while shipping the depicted paragraph parity. The one-lazy-item-per-chunk `Column` render contract already accommodates a future per-line sentence grouping (several translation children stacked in one chunk's `Column`), so the sentence gate, once designed, is render-only.

- **MD source** = raw markdown segment text (translation renders as plain muted text, not re-markdown-rendered — matches the muted-secondary design line). Segmentation runs over the raw markdown string; MD markers are treated as ordinary characters by the paragraph splitter (blank-line delimited), consistent with `TxtMdTextExtractor` shipping raw markdown to search.

This closes round-3 H1 (no dropped final-chunk translations), round-3 H2 (per-chunk layout/selection preserved; source `Text` never split), round-4 H1 (the `Utf16Span` type replaces the incompatible `IntRange`), round-4 H2 (one lazy item per chunk preserves lazy-index==chunk-index; translation gesture exclusion), round-4 H3 (Paragraph-only v1 granularity), and round-3 Low-2 (correct chunk semantics).

### AI-config reachability — FOLDED IN (#136 CLOSED; Variant A owned by #131)

**Verified against live code:** `AppContainer` (`VReaderApp.kt:31–268`) constructs **NO `AiProviderStore`** — the only reference is a *comment* naming "the OpdsSourceStore / AiProviderStore precedent" (VReaderApp.kt:64/66), no actual instance/provision. There is **no live navigation route to `AiProviderListScreen`** (the #118 `AiProviderListScreen` / `AiProviderStore` / `AiSettingsViewModel` exist and are exercised only by instrumented/round-trip tests). A fresh-install user therefore cannot reach provider config today.

The Gate-2 audits + the two design-notes proved the ONLY designed Android AI-config reader surface is **Variant A** (`reader-ai-provider-entry.md`, CANONICAL): a **scoped "AI Providers" sheet pushed _inside_ the bilingual sheet**, reached from the bilingual engine-strip's "Set up"/"Change…" button. The design explicitly **rejected** a standalone entry (there is NO designed standalone More-menu "Configure AI" row), a full-Settings deep-link (alternative B), and inline expansion (alternative C). So AI-config reachability is **NOT separable** from the bilingual flow — the #136 spin-out is **CLOSED (GH #1976, not-planned)** and **#131 now owns it end-to-end** (user decision 2026-07-12).

**Navigation model (reproduced EXACTLY from `reader-ai-provider-entry.md`:110–134, invent nothing):**

```
More ▸ Bilingual mode (first toggle on)
  └─ BilingualSetupSheet   [bottom sheet]
       engine strip: "No AI provider configured"  [ Set up ]
                             │  onOpenSettings
                             ▼  (push, slide-left, same sheet frame)
     ReaderAiProvidersSheet  [nav bar: ‹ Bilingual · "AI Providers"]
       ├─ empty  → [ Add provider ] ─┐
       └─ list   → tap a row SELECTS it (setActive) │  (present the canonical editor, full height)
                             ▼        ▼
                    AiProviderEditSheet   [reused VERBATIM from #118]
                             │  Save
                             ▼  (saved provider becomes the bilingual engine,
                                  pop the whole stack)
     BilingualSetupSheet  ← engine strip now "Claude · configured" / Change…
```

- **`‹ Bilingual` without adding** returns to the bilingual sheet **still unconfigured — no state mutated.**
- **"Change…"** (already-configured strip) opens the **SAME** `ReaderAiProvidersSheet`, populated, **current provider checked**; tapping a row **selects** it (`setActive`).
- The AI Providers view is a **push within the bilingual sheet**, NOT a modal over the reader and NOT the full app Settings.

**Android readiness gate (BINDING — round-3/round-2 H3 + the #136-audit High-3 lesson; round-4 CONFIRMED correct, UNCHANGED):** `aiConfigured` on the engine strip is derived by `BilingualAiReadiness.resolve(snapshot)` = **an ACTIVE profile exists AND its API key decrypts to non-empty.** Deriving from `profiles.isEmpty()` alone is **WRONG**: the store keeps a separate `activeId` that can be **null with profiles present** (`AiProviderSnapshot.active = profiles.firstOrNull { it.id == activeId }`, AiProviderStore.kt:34–36), and key usability depends on **decrypting the active profile's token** (`apiKey(profile) = cipher.decrypt(profile.encryptedApiKey)`, AiProviderStore.kt:108). A cipher/keystore failure maps to **not-ready, never a crash** (the resolve wraps the decrypt in `runCatching`). **Note:** the iOS Variant A design-note (`reader-ai-provider-entry.md:172–174`) derives `aiConfigured` from `providers.isEmpty == false`, and iOS #82 (`reader-ai-readiness.md`) adds a 4-gate readiness (flag + consent + provider + key). **Android has NO consent manager and NO feature flag** (#118 has neither — confirm during build); the Android gate is exactly what #118 enforces = **provider (active) + key (decrypts non-empty)**. We do NOT invent a consent/flag gate.

### New files

**Pipeline / domain (host-agnostic, pure or coroutine — JVM-testable):**

- `bilingual/Utf16Span.kt` — **NEW (round-4 H1).** `data class Utf16Span(val start: Int, val endExclusive: Int)` (half-open UTF-16 span; `require(endExclusive >= start)`; `isEmpty`, `length`). The single span type shared by the segmenter and the TXT/MD render path, replacing the incompatible `IntRange`. Rides WI-1. (Distinct from `TxtSelectionController.Utf16Range`, the selection type, which is untouched.)
- `bilingual/TranslationUnitId.kt` — `data class TranslationUnitId(kind, value)` with `enum Kind { epubHref, foliateHref, txtDocSegmentWindow, mdDocSegmentWindow, pdfPageRange }`; `storageKey = "${kind.name}:$value"`. TXT/MD kinds are **document-global segment-window indices** (H1), NOT chunk indices. v5 uses `epubHref` + `txtDocSegmentWindow`/`mdDocSegmentWindow`; others reserved so the cache-key format never breaks. *(Assumption: iOS's exact Kind case names for the TXT/MD variants; only the `storageKey` string format is load-bearing for the cache contract, and that is preserved.)*
- `bilingual/TranslationGranularity.kt` — `enum { paragraph, sentence }`. **Reserved foundational code** (WI-1, unit-tested); the v1 render/cache/VM/setup-sheet path uses `paragraph` exclusively (round-4 H3). `sentence` is design-gated.
- `bilingual/BilingualLanguages.kt` — `BilingualLanguage(key, glyph, script)`; `BILINGUAL_LANGS` = the exact set from `vreader-bilingual.jsx:15–25` (Chinese/Japanese/Korean cjk, Spanish/French/German/Italian latin, Arabic rtl, Russian cyrillic) + `findOrDefault(key)`. Default `Chinese`.
- `bilingual/ChapterSegmenter.kt` — **NEW file (no existing Android segmenter — verified).** Port of iOS `ChapterSegmenter`: `paragraphs(text)` / `sentences(text)` **plus the span-returning peers `paragraphRanges(text): List<Utf16Span>` / `sentenceRanges(text): List<Utf16Span>`** (half-open UTF-16 spans against the input string, as `Utf16Span` — round-4 H1; iOS `sentenceRanges(in:)` precedent). CJK-aware sentence enumeration (`。！？` vs Latin). Pure. (`sentenceRanges` is reserved-foundational; the v1 render path calls only `paragraphRanges` — round-4 H3.)
- `bilingual/TranslationChunker.kt` — `chunk(segments, maxCharsPerChunk)` + `subSplit(text, maxChars)`. Port of iOS `ChapterTranslationChunker.chunk(...)` (`ChapterTranslationChunker.swift:85`) + `subSplit(...)` (returns index groups, oversize segment gets its own chunk; `subSplit` is the Bug #330 grapheme-safe over-budget splitter).
- `bilingual/TranslationChunkContract.kt` — `userPrompt(segments, targetLanguage)`; `decode(raw, expectedCount)` (strict JSON-array + code-fence strip); `sealed class DecodeError { NotAStringArray; CountMismatch(expected, actual) }`. Port of iOS `TranslationChunkContract` (`TranslationChunkContract.swift:24`). No `style` param — Style descoped v1 (§3).
- `bilingual/ChapterTextProvider.kt` — `interface { units(); sourceSegments(unit); sourceText(unit); unitContaining(charOffsetUTF16); unitAfter(unit) }`. `sourceSegments(unit)` returns the exact segment strings (from the shared span array). Resolution is host-specific: TXT/MD key on `charOffsetUTF16` → segment-window; EPUB keys on the current-resource `href`. Honest divergence from iOS's uniform Readium `Locator`, documented.
- `bilingual/TxtChapterTextProvider.kt` — provider over `TxtDocument` + the segmenter's `Utf16Span` array (H1). Builds the document-global segment `Utf16Span`s once (via `paragraphRanges` — paragraph only in v1), groups them into windows, resolves `unitContaining` via a segment-start binary search over `charOffsetUTF16`. MD source = raw markdown segment text.
- `bilingual/EpubChapterTextProvider.kt` (WI-0-gated shape) — provider over the Readium `Publication` reading order; `units()` = spine hrefs, `unitContaining` = the locator's href (from `EpubNavigatorFragment.getCurrentLocator()`), `sourceSegments(unit)` = the DOM-enumerated block texts (the render's OWN enumeration, for direct-block 1:1 — H2). Its render-side collaborator is `EpubBilingualJs`.
- `bilingual/ChapterTranslationError.kt` — `sealed { Offline; TimedOut; ProviderFailed(msg); Cancelled }`. Maps from `AiError` (verified cases `Auth401`, `RateLimited429`, `Offline`, `Timeout`, `Http(code)`, `Decode`, `Stream`, `InsecureUrl`, `Config`, AiTypes.kt).
- `bilingual/ChapterTranslationService.kt` — the iOS-parity service (full divergence-recovery surface, round-2 H2):
  - `cachedTranslation(bookKey, unit, sourceText, targetLanguage, granularity, acceptCountMismatch=false)` — cache-only; serves a row only when `sourceParagraphCount == segments.size` (or `acceptCountMismatch`). No provider (#306 parity).
  - `cachedTranslation(bookKey, unit, expectedSegmentCount, targetLanguage)` — the divergence-fallback cache-only restore (iOS Bug #343): serves the canonical row only when its STORED `sourceParagraphCount == expectedSegmentCount`. Needs no source text and no provider → a cache-hit toggle/reopen restores with **zero provider calls**.
  - `translate(bookKey, unit, sourceText, targetLanguage, providerProfile, granularity, bypassCacheRead=false)` — segment → chunk → per-chunk `AiClient.chat` one-shot → `decode` → per-segment fallback → per-chunk graceful degrade (Bug #330) → cache-write only on full success (`sourceParagraphCount = segments.size`). **Cancellation:** maps BOTH native `CancellationException` AND typed `ChapterTranslationError.Cancelled` to `Cancelled` (mirrors iOS `ChapterTranslationService.swift:359–364`); `ensureActive()` between chunks AND immediately before the Room write.
  - `translatePreSegmented(bookKey, unit, segments, targetLanguage, providerProfile)` — the count-divergence recovery (iOS Bugs #268/#330/#343). Takes the render's OWN enumerated block texts as `segments` (1:1), chunks them, translates with the same per-chunk graceful-degrade + dual-cancellation contract, and — on full success only — caches under the canonical key with the ENUMERATE's count as `sourceParagraphCount`. A partial degrade is NOT cached; a cache-write failure does not fail the translation (iOS `ChapterTranslationService.swift:374–384`).
  - Uses `AiClient.chat(AiRequest)` (one-shot, verified — NOT `streamChat`).
- `bilingual/ChapterTranslationPrefetcher.kt` — resolves the active profile from one `AiProviderStore.snapshot()` (`snapshot.active`), decrypts via `store.apiKey(profile)` (snapshot-consistent, AiProviderStore.kt:108), builds an `AiClient` via an **injected factory param** (below), cache-first then translate. Adds the direct-block peers (H2):
  - `prefetch(unit)` — the plain-text path.
  - `prefetchDirect(unit, sourceSegments, targetLanguage)` — the divergence path (iOS `translatedSegmentsDirect`, `ChapterTranslationPrefetcher.swift:197`).
  - `cachedDirect(unit, expectedCount, targetLanguage)` — the **zero-provider cache-only restore** (iOS `cachedSegmentsDirect` → `cachedTranslation(expectedSegmentCount:)`, `ChapterTranslationPrefetcher.swift:236`): returns a cached translation on a hit WITHOUT requiring an active provider (#306 pre-gate precedent). Backs the EPUB cache-restore path.
  - **`AiRequest` construction (round-3 M3 fix, BINDING; round-4 CONFIRMED correct):** `model = profile.model.ifBlank { profile.kind.defaultModel }` — matches `AiChatViewModel.kt:61`; both wire clients serialize `request.model` **directly** (`put("model", request.model)` in `OpenAiCompatibleProvider.kt:38` and `AnthropicProvider.kt:36`), so a blank `profile.model` would send an empty model. Full request: `AiRequest(model = profile.model.ifBlank { profile.kind.defaultModel }, messages = …, temperature = profile.temperature, maxTokens = profile.maxTokens, system = …)`. A **blank-model regression test** asserts the fallback is applied.
  - Throws `ChapterTranslationError`. Mirrors iOS `ChapterTranslationPrefetcher`.
- `bilingual/BilingualAiReadiness.kt` — `resolve(snapshot: AiProviderSnapshot): Boolean` — active profile exists (`snapshot.active != null`) AND `runCatching { store.apiKey(snapshot.active).isNotEmpty() }.getOrDefault(false)` (cipher/decryption failure → **not-ready**, never crashes). Drives the setup-sheet engine-strip configured/unconfigured state. Exactly the #118 gate (no consent manager / feature flag on Android — confirm during build).

**State / persistence:**

- `bilingual/PerBookBilingualStore.kt` — DataStore-Preferences, keyed by `bookFingerprintKey`, holding `{ enabled, targetLanguage, granularity }` (`granularity` is persisted but pinned to `paragraph` in v1 — round-4 H3). The Android `PerBookSettingsOverride` bilingual slice — the backup contract declares exactly `bilingualEnabled` / `bilingualTargetLanguage` / `bilingualGranularity` and **NO `bilingualStyle`** (verified). Wiring into backup collect/restore is scoped OUT (§7); until then bilingual config is device-local.
- `bilingual/BilingualViewModel.kt` — `StateFlow<BilingualUiState>` with `enabled`, `targetLanguage`, `granularity`, `needsSetupSheet`, `aiConfigured`, `translationsByUnit`, `inFlightUnits`, `unavailableUnits`, `errorUnit`. Setters + `dismissSetupSheet`, `onPositionChanged(charOffsetUTF16)`, `retryUnit(unit)`, and the EPUB direct-block entry `onEpubBlocksEnumerated(unit, blocks)` (M1, below). Generation/epoch-guarded prefetch (current + next unit); a **per-unit single-flight job registry** (M2); dual-cancellation handling (M2). Port of iOS `BilingualReadingViewModel` (`prefetchTasks: [TranslationUnitID: Task]`, `BilingualReadingViewModel.swift:141`) + `+Prefetch`. Split to `BilingualPrefetchController.kt` if it nears ~300 lines. No `style` field.

**Room (translation cache):**

- `data/ChapterTranslationEntity.kt` — `@Entity(tableName="chapter_translations", indices=[Index("bookKey")], foreignKeys=[FK→books.fingerprintKey ON DELETE CASCADE])`. **`@PrimaryKey val lookupKey: String`** (Room requires a PK; project pattern `@PrimaryKey` + `@Upsert`, verified `BookEntity` `@PrimaryKey val fingerprintKey`, Entities.kt:24). `lookupKey` = `bookKey|unitStorageKey|targetLanguage|promptVersion`. Columns: `lookupKey` (PK), `bookKey`, `unitStorageKey`, `targetLanguage`, `promptVersion`, `translatedJson`, `sourceParagraphCount`, `createdAt`. Mirrors iOS `ChapterTranslationRecord.lookupKey` (`book|unit|lang|prompt`, profile-agnostic — Bug #342). `sourceParagraphCount` is load-bearing for H2 (stores the enumerate's count on the `translatePreSegmented` path so `cachedTranslation(expectedSegmentCount:)` restores). **The exact `MIGRATION_8_9` DDL is authored in WI-2 — see below.**
- `data/ChapterTranslationDao.kt` — `getByLookupKey(key)`, `@Upsert suspend fun upsert(row)`, `deleteByLookupKey(key)`.
- `bilingual/ChapterTranslationStore.kt` — coroutine wrapper returning a `CachedTranslation` (segments decoded from JSON), keeping Room entities off the boundary (iOS `ChapterTranslationStore` precedent).

**Cache-identity (reconciled with iOS parity):** the 4-part key `book|unit|lang|promptVersion` is profile-AGNOSTIC / style-agnostic (Bug #342). Style is descoped (§3) so no `s=` component. **Granularity is paragraph-only in v1** (round-4 H3): `promptVersion = "bilingual-v1|g=paragraph"` in v1 (the `g=` component is always `paragraph`). The composite `g=` slot is retained in the key format so a future granularity is a different cache row by construction (closes the iOS #344 "sentence silently ignored" class ahead of time), but v1 never emits `g=sentence`. A language change cancels in-flight jobs, bumps the VM generation, clears shaped `translationsByUnit`, and forces a correctly-keyed re-fetch (WI-6).

**DI / factory (verified live):** `AiProviderFactory` is an `object` with `create(profile, apiKey, dispatcher = Dispatchers.IO): AiClient` (verified, `AiProviderFactory.kt:10`). `ChapterTranslationPrefetcher` takes its OWN injected `clientFactory: (AiProviderProfile, String) -> AiClient` param **defaulting to `AiProviderFactory::create`**, overridden with a fake in tests.

**UI (Compose — every state depicted, reproducing `vreader-bilingual.jsx` + `vreader-ai-provider-entry.jsx`):**

- `bilingual/BilingualSetupSheet.kt` — reproduces `vreader-bilingual.jsx`'s `BilingualSetupSheet` (lines 27–156) EXACTLY, with the granularity divergence: header; a preview strip (`BilingualPreview`); a language grid over `BILINGUAL_LANGS` (glyph tiles, selected accent); a **Granularity** segmented control **descoped to Paragraph-only in v1** ("Translate after each ¶"; the Sentence option is not rendered in v1 — round-4 H3, tracked by the sentence design gate); a **Translation engine** strip (configured: "Claude · with this book's context" + "Change…"; unconfigured: "No AI provider configured" + "Bilingual mode needs an AI provider to translate." + "Set up"); the "Turn on bilingual mode" CTA. **No Style control, no provider/model card, no term-overrides toggle, no cost footer** (those belong to the `vreader-ai-android.jsx` sheet, not reproduced — §3). The `aiConfigured` flag comes from `BilingualAiReadiness.resolve`. The "Set up"/"Change…" CTA routes to `ReaderAiProvidersSheet` (wired in WI-9).
- `bilingual/ReaderAiProvidersSheet.kt` — **NEW (folded in; the Android analog of iOS `ReaderAIProvidersView`; round-4 High-4 rewritten).** The Variant A scoped in-reader AI Providers sheet, reproducing `vreader-ai-provider-entry.jsx` `AIProvidersSheet` + `AIProvidersSheetBody` + `NavSheet` (nav bar `‹ Bilingual` leading + centered "AI Providers" title, `vreader-ai-provider-entry.jsx:247`). **Round-4 High-4: the fold-in CANNOT be "reuse `AiProviderListScreen` verbatim."** `AiProviderListScreen` owns its OWN full `NavScreen(title="AI Providers", onBack)` (`AiProviderListScreen.kt:59`), a generic `AiEmptyState` ("Connect an AI provider" / "One key unlocks…", :84/:87), and **row-tap-as-EDIT** (`ProviderRow` → `onEdit(p.id)`, :105) with **no checked-active-tap-to-select** — it cannot reproduce the designed reader-scoped `‹ Bilingual` nav, the bilingual-context empty state, the checked-active row, or tap-to-SELECT. So the fold-in splits into **(a)/(b)/(c)**:
  - **(a) EDITOR reused VERBATIM.** `AiProviderEditSheet` (the canonical add/edit modal, Kind / Name / Endpoint / Sampling / API Key / Test Connection) is presented UNCHANGED from the #118 Library path — that reuse is confirmed fine (`reader-ai-provider-entry.md:49–52`, :63–65).
  - **(b) The scoped LIST is a NEW reader-specific presentation** (`ReaderAiProvidersList`, in this file) built over the **SHARED `AiSettingsViewModel` state** (`listState`, verified `AiSettingsViewModel.kt:26`) + shared row/cell components, reproducing: the reader-scoped nav (`‹ Bilingual` back label, "AI Providers" title — `NavSheet` at jsx:247, NOT `AiProviderListScreen`'s own `NavScreen`); the **bilingual-context empty state** ("Choose the provider bilingual mode will use to translate this book." context strip + "No providers yet" + "Add provider" CTA — jsx:180–209); the **checked-active row** (`selected={p.id === selectedId}` — jsx:221; the live `AiProviderListState`/`AiProviderRow` already carries `active` per row, `AiSettingsViewModel.kt:30`); and **tap-to-SELECT** (`onSelect(p.id)` → `vm.setActive(id)` — jsx:221/237). It does **NOT** reuse `AiProviderListScreen`'s `NavScreen`/chrome/`AiEmptyState`/`ProviderRow`-tap-edit.
  - **(c) A save-result seam** (round-4 High-4): `AiSettingsViewModel.save()` today returns Unit and upserts async (generates `s.id ?: UUID.randomUUID().toString()` *inside* the launched coroutine, then `_edit.value = null`, no saved ID — `AiSettingsViewModel.kt:85–97`), so WI-AIP cannot deterministically `setActive(savedId)` + pop-on-success by reusing it verbatim (popping immediately races the async upsert; observing list state can't distinguish the new profile). **Note:** `AiProviderStore.upsert` ALREADY returns the saved profile (`suspend fun upsert(...): AiProviderProfile`, "Returns the saved profile", `AiProviderStore.kt:58/70/84`) — the ID is present at the store layer; only the VM discards it. So the seam is an **additive completion/result signal on `AiSettingsViewModel.save()`** (or a thin WI-AIP wrapper) returning the saved provider ID (from `store.upsert(...).id`), so WI-AIP can `setActive(savedId)` + pop-on-success **after** the upsert commits — no race. The #118 VM is currently production-UNWIRED (only test-referenced — verified), and this feature wires it to production for the FIRST time, so an additive save-result seam is safe and appropriate.
  - **Behavior per the nav model:** empty → "Add provider" → `AiProviderEditSheet` → Save → `save()` returns the saved ID → `store.setActive(savedId)` (first-provider-active is already the store's default `activeId = cur.activeId ?: id`, AiProviderStore.kt:81; the explicit `setActive(savedId)` guarantees the freshly-saved provider is the engine even if others existed) → **pop the whole stack** back to the bilingual sheet, engine strip now "Claude · configured / Change…". `‹ Bilingual` without adding → unconfigured, **no state mutated**. "Change…" → the SAME sheet, populated, current provider checked, tap a row → `setActive`. No consent card, no feature-flag toggle, no readiness tracker (iOS #82, deferred).
- `bilingual/BilingualInterlinearBody.kt` — the Compose render surface for the **TXT/MD host ONLY** (round-2 M2). Renders per the **one-lazy-item-per-chunk `Column`** H2 render contract (source chunk unchanged as the first `Column` child; translation(s) anchored to chunk `i` as muted non-registered `Text` siblings in the SAME `Column`): muted `Text`, accent left-border, `fontSize*0.88`, CJK font for cjk scripts, RTL handling for Arabic (per `BilingualPageContent`, `vreader-bilingual.jsx:200–277`). Consumes the host-neutral `BilingualRenderState` DTO. Loading state ("Translating chapter… N%" + per-segment dim), error state ("Couldn't translate" + Retry), partial/offline (`unavailableUnits`): source-only silent fallback (iOS Decision 2). Includes the **translation gesture-exclusion** (round-4 H2) so a long-press on a translation child does not route to `hitAt`'s nearest-source-chunk fallback. **NOT the EPUB render surface.**
- `bilingual/BilingualRenderState.kt` — the host-neutral state DTO shared by the Compose body and the EPUB adapter (round-2 M2): per-unit `{ segments: List<String>?, phase: Loaded|Loading(fraction)|Error|SourceOnly }`. Compose and EPUB share the state/value types, NOT the composable body.
- `bilingual/EpubBilingualJs.kt` (WI-0-gated) — the EPUB render surface (round-2 M2). Pure Kotlin builder producing JS strings for `navigator.evaluateJavascript(...)`: `enumScript` (enumerate current-resource leaf blocks → JSON `[{id,text}]`), `injectScript(blockId, translationText)` (translation DOM node after the block; CSP-safe: `textContent`/`createTextNode`, never `innerHTML` string-concat; RTL/CJK via class + injected `<style>`), `clearScript()` (idempotent removal). Escaping done in Kotlin (JSON-encode every interpolated string). No Compose. Consumes `BilingualRenderState`.
- `bilingual/EpubBilingualController.kt` (WI-0-gated) — **the single owner of EPUB units (M1, below).** The runtime actor that serializes enumerate→(cache-restore|translate)→inject/clear against the navigator using WI-0's chosen mechanism (a single mutex OR a monotonic navigator-session token); checks the session token after every suspended JS/AI call; clears BEFORE publication teardown; re-applies on the identified production re-apply signal.
- `bilingual/BilingualPill.kt` — the `EN ↔ 中` reader-top-chrome pill (per `vreader-reader.jsx` + `vreader-bilingual.jsx` `BilingualPill`:282–305). Rendered by #132's top chrome; #131 provides the composable, #132's surface hosts it (§4).

### EPUB direct-block flow — one owner + concrete API (round-3 Medium-1, BINDING; round-4 CONFIRMED RESOLVED — UNCHANGED)

The **`EpubBilingualController` is the SINGLE OWNER of EPUB units**; the VM's position-driven regular `prefetch` path is **TXT/MD-only**. Concretely, an EPUB position change routes THROUGH the controller (the VM does not run `prefetch(unit)` for `epubHref` units), so the **controller is the sole writer** of an EPUB unit's canonical cache row and its `BilingualRenderState`/`translationsByUnit` entry — the position-driven regular prefetch and the direct-block path can never both write the same canonical cache row. The control flow (every suspended step session-token-guarded):

```
enumeratedBlocks = navigator.evaluateJavascript(EpubBilingualJs.enumScript)   // [{id,text}] for current resource
        │  (session token S captured before the call; re-checked after)
        ▼
count = enumeratedBlocks.size
restore = prefetcher.cachedDirect(unit, expectedCount = count, targetLanguage)  // zero-provider cache restore
        │
        ├─ hit  → segments = restore
        └─ miss → segments = prefetcher.prefetchDirect(unit, sourceSegments = enumeratedBlocks.texts, targetLanguage)
        │  (token re-checked after each suspension; a stale token → discard, no commit, no error surfaced)
        ▼
if token S still current:  commit segments → BilingualRenderState[unit] / translationsByUnit[unit]  (single writer)
        ▼
EpubBilingualJs.injectScript per (blockId, translation)  via navigator.evaluateJavascript   // token-guarded
```

- The VM exposes `onEpubBlocksEnumerated(unit, blocks)` as the controller's entry into VM render state, but the **controller owns the enumerate→cachedDirect/prefetchDirect→guarded-commit sequence**; the VM never initiates an EPUB prefetch itself (its position-driven `prefetch` dispatches only `txtDocSegmentWindow`/`mdDocSegmentWindow` units). A stale session token at any commit point discards silently (no `errorUnit`).
- WI-7b's connected test asserts: enable → inject; disable → clear; reflow/href-change/fragment-recreation/activity-recreation → re-apply from cache via `cachedDirect` (zero provider calls); count-divergence handled via `prefetchDirect`; and that the regular TXT/MD prefetch path is never invoked for an EPUB unit.

### Cancellation + single-flight (round-3 Medium-2, BINDING; round-4 CONFIRMED RESOLVED — UNCHANGED)

android/2026-06-29-223908-this-session-is-being-continued-from-a-previous-c.txt:3320:           chunk `LayoutCoordinates`+root→local+auto-scroll+`getWordBound
android/2026-06-29-223908-this-session-is-being-continued-from-a-previous-c.txt:3818:           chunk `LayoutCoordinates`+root→local+auto-scroll+`getWordBound
android/2026-06-29-223908-this-session-is-being-continued-from-a-previous-c.txt:5156:           chunk `LayoutCoordinates`+root→local+auto-scroll+`getWordBound
./android/2026-06-29-223908-this-session-is-being-continued-from-a-previous-c.txt:3320:           chunk `LayoutCoordinates`+root→local+auto-scroll+`getWordBound
./android/2026-06-29-223908-this-session-is-being-continued-from-a-previous-c.txt:3818:           chunk `LayoutCoordinates`+root→local+auto-scroll+`getWordBound
./android/2026-06-29-223908-this-session-is-being-continued-from-a-previous-c.txt:5156:           chunk `LayoutCoordinates`+root→local+auto-scroll+`getWordBound
./docs/features.md:177:| 124| **Android TXT highlights & notes** (Phase 3, #110 driver; part of checklist B). Custom Compose long-press-drag selection in the TXT reader → 5-color highlight / note / copy / share (reuses #123's annotation domain); washes via `drawBehind`+`getPathForRange`; persists + re-renders + tap-to-edit/remove. | android/app/.../reader/Txt*selection/wash/* + TxtReaderActivity | Medium | VERIFIED | **VERIFIED 2026-06-28 (Gate-5b) — `dev-docs/verification/feature-124-20260628.md` (`result: pass`), merge `a325493b` (`android/v0.12.0`).** All acceptance criteria on emulator API 35: a real long-press selects + popovers, long-press→tap-color creates+persists, tap-existing→edit→Remove deletes, wash render on the live reader, JVM offset/validate/hit-test/wash suites, the binding TXT gate (MD inert). The TXT gesture is automatable via the Compose harness (unlike #123's WebView). GH #1841 closed. **DONE 2026-06-28 (WI-4, final WI — all 4 WIs merged on main).** WI-1 offsets/validate/hit-test (`android/v0.11.1`), WI-2 wash render (`v0.11.2`), WI-3 gesture+popover create (`v0.11.3`), WI-4 tap-edit/remove (`v0.12.0`). Each Gate-4 Codex-audited ship-as-is. On emulator API 35 (`TxtReaderActivityTest`): a REAL long-press selects a word + shows the popover, long-press→tap-color creates+persists a highlight, tap-existing→edit popover→Remove deletes it; the gesture is automatable via the Compose harness. Plan `dev-docs/plans/20260628-feature-124-android-txt-md-highlights.md` v3. Gate-2 Codex audit 2 rounds (gpt-5.5/high; R1 verdict split 6H/5M/2L → R2 1H/1M, all fixed): **scoped to TXT-only** (MD → follow-on #125 — needs a MarkdownRenderer source-offset map; the visible-vs-source `textQuote` + `renderWithMap` Highs are MD-specific); washes via `drawBehind`+`getPathForRange` (not `SpanStyle` background — overlaps don't compose); gesture coords via per-chunk `LayoutCoordinates`+root→local+auto-scroll+`getWordBoundary`; **binding TXT gate** (all annotation paths gated on `BookFormat.txt`; MD render-only + regression — TXT/MD share `TxtReaderActivity`); half-open `Utf16Range`; range validation incl. mid-surrogate; `sourceUnitId=text-document:<key>`; hit-tester overlap precedence. 4 WIs: WI-1 offsets/validate/hit-test; WI-2 wash render; WI-3 gesture+popover create; WI-4 edit/remove+accept. **Box B then needs #125 (MD) + review-sheet/bookmark (item F).** GH: #1841 |
./dev-docs/plans/20260628-feature-124-android-txt-md-highlights.md:67:  `LazyColumn`. Per visible chunk: capture `TextLayoutResult` (`onTextLayout`) **and** `LayoutCoordinates`
./dev-docs/plans/20260628-feature-124-android-txt-md-highlights.md:95:  `LayoutCoordinates` — rejected `SelectionContainer` (no durable source offsets across the chunked
./dev-docs/plans/20260628-feature-124-android-txt-md-highlights.md:124:- **R1 — gesture coordinate mapping** across a scrolling LazyColumn (Gate-2 High): per-chunk `TextLayoutResult` + `LayoutCoordinates` via `onGloballyPositioned`; convert root→local before `getOffsetForPosition`; auto-scroll near edges. Keep the pure offset math in `TxtSourceOffsets` (unit-tested); the gesture stays thin.
./dev-docs/plans/20260628-feature-124-android-txt-md-highlights.md:146:  `drawBehind`+`getPathForRange` (not `SpanStyle`); gesture coords via per-chunk `LayoutCoordinates` +
./docs/architecture.md:681:visible chunk's `TextLayoutResult` + `LayoutCoordinates`; one `awaitEachGesture` distinguishes a tap
./dev-docs/plans/20260710-feature-131-android-bilingual-interlinear.md:78:**Live invariant #1 — per-chunk layout/selection (round-3 High-2, verified TxtReaderActivity.kt:1043–1085):** the TXT/MD body iterates `items(count = document.chunkCount, key = { it })` (TxtReaderActivity.kt:1043). For **each chunk `i`** it owns **exactly ONE `TextLayoutResult`** (`var layout by remember(i) { … }`, set in `onTextLayout`, TxtReaderActivity.kt:1059/1075) and **exactly ONE selection registration** (`selectionController.registerChunk(i, l, c)` / `unregisterChunk(i)`, TxtReaderActivity.kt:1062–1066). Highlights (`highlightSpan(i)`, :1047), annotation washes (`washesForChunk(i)`, :1058), the read-aloud span wash (`addStyle(SpanStyle(background = wash), …)`, :1050–1054), and selection accents (`selectionForChunk(i)` → `drawRangeFill`, :1069/1081) all key off that **per-chunk** layout and the chunk-local UTF-16 offsets. **Splitting a chunk's source `Text` into multiple `Text` nodes would break every one of these** (two `Text` nodes = two `TextLayoutResult`s = broken selection coordinates, misplaced highlight/wash/annotation ranges, a shifted read-aloud wash).
./dev-docs/plans/20260710-feature-131-android-bilingual-interlinear.md:82:- **Bookmark / annotation / search / scrubber / TTS jumps** all call `listState.scrollToItem(document.chunkForOffset(target))` (bookmark :411, annotation :421, search :454, scrubber :481; TTS auto-scroll `animateScrollToItem(spokenChunk)` where `spokenChunk = document.chunkForOffset(tts.charStart)` — :252/:257).
./dev-docs/plans/20260710-feature-131-android-bilingual-interlinear.md:83:- **TTS visibility** compares lazy-item indices with the chunk directly: `listState.layoutInfo.visibleItemsInfo.none { it.index == spokenChunk }` (:256).
./dev-docs/plans/20260710-feature-131-android-bilingual-interlinear.md:85:**Therefore inserting SEPARATE translation `LazyColumn` items (the v4 "additive items after the anchor chunk" contract) is NOT implementable:** every separate translation item inserted before a given source chunk shifts that chunk's lazy index, so `offsetForChunk(firstVisibleItemIndex)` reads the wrong chunk's offset (corrupts position save + progress), `scrollToItem(chunkForOffset(target))` lands on the wrong item (corrupts every jump), and `visibleItemsInfo.index == spokenChunk` never matches (corrupts TTS auto-scroll). The v4 contract is **rejected**.
./dev-docs/plans/20260710-feature-131-android-bilingual-interlinear.md:90:> 1. the **UNCHANGED source `Text`** — one `TextLayoutResult`, one `registerChunk(i, …)`/`unregisterChunk(i)`, byte-identical to today (the exact code at TxtReaderActivity.kt:1044–1084 is unchanged, now nested in a `Column`);
./dev-docs/plans/20260710-feature-131-android-bilingual-interlinear.md:98:2. Render the source chunk `i` **EXACTLY as today** (the unchanged `Text` + its `remember(i)` layout/coords + `registerChunk(i, …)`/`unregisterChunk(i)` + `highlightSpan(i)`/`washesForChunk(i)`/`selectionForChunk(i)` — TxtReaderActivity.kt:1044–1084, now the first child of the `Column`).
./dev-docs/plans/20260710-feature-131-android-bilingual-interlinear.md:104:- **Explicit translation gesture exclusion (round-4 High-2 — BINDING):** `TxtSelectionController.hitAt` (`reader/TxtSelectionController.kt:47`) falls back to the **nearest registered source chunk** when the pointer is outside all source-chunk bounds (`chunks.entries.minByOrNull { verticalDistance(...) }` when no chunk's `boundsInWindow()` contains the point, :51–53). So merely omitting `registerChunk` for the translation does **NOT** make it non-selectable — a long-press *on the translation text* would fall through to the nearest source chunk and select source. **WI-8 must add an explicit hit-test / gesture exclusion for the translation composable's bounds** so a long-press whose pointer lands inside a translation `Text`'s bounds is consumed (no selection begun) rather than routed to `hitAt`'s nearest-chunk fallback. (Options: the translation `Text` consumes the long-press gesture in its own `pointerInput`; or the selection gesture root records the translation composables' window bounds and short-circuits `beginAt` when the point is inside one. WI-8 picks and tests one.)
./dev-docs/plans/20260710-feature-131-android-bilingual-interlinear.md:106:- **TTS auto-scroll visibility must key off the SOURCE `Text` bounds, NOT the item index (round-5 High — a NEW consequence of the in-item `Column`):** the TTS auto-scroll guard (TxtReaderActivity.kt:252/256) currently keeps the spoken chunk on screen via `listState.layoutInfo.visibleItemsInfo.none { it.index == spokenChunk }` — item-level visibility. With the in-item `Column`, an item is now taller than its source line (source + translation children), so when `spokenChunk`'s SOURCE `Text` has scrolled above the viewport but its translation sibling is still visible, `visibleItemsInfo` still contains the item's index → the guard falsely suppresses `animateScrollToItem(spokenChunk)` and leaves the spoken SOURCE off-screen. **WI-8 must redefine the TTS-visibility predicate to test the registered SOURCE `Text` bounds** — the selection controller already tracks each source chunk's `LayoutCoordinates`/`boundsInWindow()` via `registerChunk(i, layout, coordinates)` (TxtSelectionController.kt): `spokenChunk` is visible iff its registered source bounds intersect the list viewport; otherwise `animateScrollToItem(spokenChunk)` scrolls the item's top (the source) into view. This is **inert when bilingual is OFF** (no translation child → item height == source height → item-index visibility already equals source visibility), so the disabled path is byte-identical.
./dev-docs/plans/20260710-feature-131-android-bilingual-interlinear.md:109:  - (a) each source chunk's **selection registration is UNCHANGED** (same `registerChunk(i, …)` count and coordinates as OFF; a translation child registers nothing);
./dev-docs/plans/20260710-feature-131-android-bilingual-interlinear.md:111:  - (c) **lazy-index == chunk-index preserved:** with bilingual ON — **position-save round-trips to the same chunk** (`offsetForChunk(firstVisibleItemIndex)` → save → reopen → `chunkForOffset(offset)` lands on the same chunk); **bookmark/annotation/search/scrubber jumps land on the correct chunk** (`scrollToItem(chunkForOffset(target))` scrolls to the right item); **TTS auto-scroll keeps the spoken SOURCE on screen — visibility keyed off the registered source `Text` bounds, NOT `visibleItemsInfo.index` (round-5 High)**, INCLUDING the case where only `spokenChunk`'s translation portion is visible (its source scrolled above the viewport) → TTS brings the SOURCE back on-screen; (assert the index-identity behaviors above are identical to the OFF baseline — no lazy index shift);
./dev-docs/plans/20260710-feature-131-android-bilingual-interlinear.md:314:8. **SEPARATE additive `LazyColumn` items per translation, after the anchor chunk (v4)** — REJECTED (round-4 H2): separate lazy items shift every following lazy index, and the live reader treats lazy-item indices AS `TxtDocument` chunk indices (`offsetForChunk(firstVisibleItemIndex)` for position save/progress — TxtReaderActivity.kt:220/473/623; `scrollToItem(chunkForOffset(target))` for every bookmark/annotation/search/scrubber/TTS jump — :411/:421/:454/:481/:257; `visibleItemsInfo.index == spokenChunk` for TTS visibility — :256). Replaced by the **one-lazy-item-per-chunk `Column`** contract (source `Text` unchanged as the first child, translations as sibling children in the SAME lazy item — no lazy item added, no index shifted).
./dev-docs/plans/20260710-feature-131-android-bilingual-interlinear.md:377:**WI-8 (behavioral): `TxtReaderActivity` integration.** Wire VM into the `items(count = document.chunkCount, key = { it })` loop as **muted non-registered translation `Text` children inside each anchor chunk's wrapping `Column`, source chunk byte-unchanged, the loop + keys UNCHANGED so lazy-index==chunk-index is preserved (round-4 H2)** + the translation **gesture-exclusion** (round-4 H2) + the **TTS source-bounds visibility fix** (round-5 H: the TTS auto-scroll predicate keys off the registered source `Text` bounds, not `visibleItemsInfo.index`, so a translation-only-visible item does not falsely suppress the auto-scroll) + position-change (`charOffsetUTF16`) + setup-sheet. `originalFormat`-gated (TXT/MD). Uses WI-4b's DI. **#129 VERIFIED — straight edit.** Connected test (fake `AiClient` seam): enable → setup → confirm → interlinear from seeded cache; **enabled-mode source-chunk selection registrations UNCHANGED vs disabled (H2)**; **highlights/annotation-washes/read-aloud-wash still key off source chunks (H2)**; **with bilingual ON — position-save round-trips to the same chunk; bookmark/search/scrubber/TTS jumps land on the correct chunk (lazy-index==chunk-index preserved — round-4 H2); TTS auto-scroll brings the spoken SOURCE on-screen even when only its translation portion is visible (source-bounds visibility — round-5 H)**; **a long-press on translation text does NOT select (gesture exclusion — round-4 H2)**; a translation child is non-selectable, does not perturb source offsets (H2); disable → source-selection byte-parity; reopen persists enabled + renders from cache with zero client calls; **paragraph-spanning-many-chunks renders exactly one translation inside its last chunk's `Column` (H1/Low-2)**; **one-chunk/final-chunk anchors render (H1)**; MD source mapping. Deps: WI-6, WI-7a, WI-4b.
./dev-docs/plans/20260710-feature-131-android-bilingual-interlinear.md:397:- **Enabled render breaking the per-chunk layout/selection model AND the lazy-index↔chunk-index identity (round-3 H2 + round-4 H2).** Fixed by the **one-lazy-item-per-chunk `Column`** render contract: the `items(count = chunkCount, key = { it })` loop + keys are UNCHANGED (lazy-index==chunk-index preserved, so position-save/progress/every jump/TTS visibility — TxtReaderActivity.kt:220/252/256/411/421/454/481/623 — stay correct); inside each item a `Column` holds the UNCHANGED source `Text` (one `TextLayoutResult`, one `registerChunk(i)`) then the muted non-registered translation child(ren); an explicit **gesture-exclusion** stops a long-press on translation text from routing to `hitAt`'s nearest-source-chunk fallback (TxtSelectionController.kt:47–53). Enabled-mode tests assert selection/highlight/wash/annotation parity AND lazy-index==chunk-index parity with disabled, plus translation-not-selectable.
./dev-docs/plans/20260710-feature-131-android-bilingual-interlinear.md:438:  - **H2 (round-4 High-2) — one-lazy-item-per-chunk `Column` (THE key fix):** the v4 "separate additive `LazyColumn` items after the anchor chunk" contract is NOT implementable — the live reader treats lazy-item indices AS `TxtDocument` chunk indices (position-save via `offsetForChunk(firstVisibleItemIndex)`, TxtReaderActivity.kt:220/473/623; every bookmark/annotation/search/scrubber/TTS jump via `scrollToItem(chunkForOffset(...))`, :411/:421/:454/:481/:257; TTS visibility via `visibleItemsInfo.index == spokenChunk`, :256), so inserting separate translation items shifts every following lazy index and corrupts all of these. New binding contract: keep EXACTLY ONE lazy item per chunk (the `items(count=chunkCount, key={it})` loop + keys UNCHANGED → lazy-index==chunk-index preserved); INSIDE each item wrap the content in a `Column` — the UNCHANGED source `Text` (one `TextLayoutResult`, one `registerChunk(i)`) then the muted non-registered translation child(ren) anchored to chunk `i`. ADDED explicit translation **gesture exclusion** (TxtSelectionController.hitAt falls back to the nearest source chunk when the pointer is past source bounds, :47–53, so omitting `registerChunk` is not enough). Updated §2 H2, the `BilingualInterlinearBody` file entry, the rejected-alternatives list (added the separate-lazy-items rejection), WI-7a, WI-8, and the enabled-mode tests (position-save round-trips to the same chunk; jumps/TTS land on the correct chunk; long-press on translation does NOT select).
./dev-docs/plans/20260710-feature-131-android-bilingual-interlinear.md:444:- **v6 (2026-07-12): Gate-2 round-5's one residual High resolved — TTS source-bounds visibility.** The in-item `Column` (round-4 H2 fix) makes each item taller than its source line, so the TTS auto-scroll guard's item-index visibility check (`visibleItemsInfo.index == spokenChunk`, TxtReaderActivity.kt:252/256) no longer proves SOURCE visibility: when the spoken source has scrolled above the viewport but its translation sibling is still visible, the guard falsely suppresses the auto-scroll and leaves the source off-screen. Fix: WI-8 redefines the TTS-visibility predicate to test the registered SOURCE `Text` bounds (the selection controller already tracks each source chunk's `LayoutCoordinates` via `registerChunk`), + a translation-only-visible connected test. Inert when bilingual is OFF (item height == source height → item-index visibility already equals source visibility). Updated §2 H2 (new TTS-visibility bullet + enabled-mode test (c)), WI-8 (scope + test), and the connected-test list. WI count UNCHANGED at 13. Awaiting Gate-2 round-6 (micro-confirm).
./android/app/src/main/kotlin/com/vreader/app/search/InBookSearchSheet.kt:194:            listState.layoutInfo.visibleItemsInfo.lastOrNull()?.key == "group-$lastGroupIndex"
android/app/src/main/kotlin/com/vreader/app/search/InBookSearchSheet.kt:194:            listState.layoutInfo.visibleItemsInfo.lastOrNull()?.key == "group-$lastGroupIndex"
./android/app/src/main/kotlin/com/vreader/app/reader/TxtSelectionController.kt:2:// TextLayoutResult + LayoutCoordinates; the controller converts a pointer (LazyColumn-local) → window
./android/app/src/main/kotlin/com/vreader/app/reader/TxtSelectionController.kt:11:import androidx.compose.ui.layout.LayoutCoordinates
./android/app/src/main/kotlin/com/vreader/app/reader/TxtSelectionController.kt:12:import androidx.compose.ui.layout.boundsInWindow
./android/app/src/main/kotlin/com/vreader/app/reader/TxtSelectionController.kt:26:    private data class ChunkInfo(val layout: TextLayoutResult, val coords: LayoutCoordinates)
./android/app/src/main/kotlin/com/vreader/app/reader/TxtSelectionController.kt:30:    private var lazyCoords: LayoutCoordinates? = null
./android/app/src/main/kotlin/com/vreader/app/reader/TxtSelectionController.kt:37:    fun setLazyCoords(coords: LayoutCoordinates) { lazyCoords = coords }
./android/app/src/main/kotlin/com/vreader/app/reader/TxtSelectionController.kt:38:    fun registerChunk(index: Int, layout: TextLayoutResult, coords: LayoutCoordinates) {
./android/app/src/main/kotlin/com/vreader/app/reader/TxtSelectionController.kt:41:    fun unregisterChunk(index: Int) { chunks.remove(index) }
./android/app/src/main/kotlin/com/vreader/app/reader/TxtSelectionController.kt:51:        val hit = chunks.entries.firstOrNull { it.value.coords.boundsInWindow().contains(windowPoint) }
./android/app/src/main/kotlin/com/vreader/app/reader/TxtSelectionController.kt:52:            ?: (if (allowNearest) chunks.entries.minByOrNull { verticalDistance(it.value.coords.boundsInWindow(), windowPoint) } else null)
android/app/src/main/kotlin/com/vreader/app/reader/TxtSelectionController.kt:2:// TextLayoutResult + LayoutCoordinates; the controller converts a pointer (LazyColumn-local) → window
android/app/src/main/kotlin/com/vreader/app/reader/TxtSelectionController.kt:11:import androidx.compose.ui.layout.LayoutCoordinates
android/app/src/main/kotlin/com/vreader/app/reader/TxtSelectionController.kt:12:import androidx.compose.ui.layout.boundsInWindow
android/app/src/main/kotlin/com/vreader/app/reader/TxtSelectionController.kt:26:    private data class ChunkInfo(val layout: TextLayoutResult, val coords: LayoutCoordinates)
android/app/src/main/kotlin/com/vreader/app/reader/TxtSelectionController.kt:30:    private var lazyCoords: LayoutCoordinates? = null
android/app/src/main/kotlin/com/vreader/app/reader/TxtSelectionController.kt:37:    fun setLazyCoords(coords: LayoutCoordinates) { lazyCoords = coords }
android/app/src/main/kotlin/com/vreader/app/reader/TxtSelectionController.kt:38:    fun registerChunk(index: Int, layout: TextLayoutResult, coords: LayoutCoordinates) {
android/app/src/main/kotlin/com/vreader/app/reader/TxtSelectionController.kt:41:    fun unregisterChunk(index: Int) { chunks.remove(index) }
android/app/src/main/kotlin/com/vreader/app/reader/TxtSelectionController.kt:51:        val hit = chunks.entries.firstOrNull { it.value.coords.boundsInWindow().contains(windowPoint) }
android/app/src/main/kotlin/com/vreader/app/reader/TxtSelectionController.kt:52:            ?: (if (allowNearest) chunks.entries.minByOrNull { verticalDistance(it.value.coords.boundsInWindow(), windowPoint) } else null)
android/app/src/main/kotlin/com/vreader/app/reader/TxtReaderActivity.kt:252:                        val spokenChunk = if (tts.phase == TtsPhase.speaking) s.document.chunkForOffset(tts.charStart) else -1
android/app/src/main/kotlin/com/vreader/app/reader/TxtReaderActivity.kt:255:                        LaunchedEffect(spokenChunk) {
android/app/src/main/kotlin/com/vreader/app/reader/TxtReaderActivity.kt:256:                            if (spokenChunk >= 0 && listState.layoutInfo.visibleItemsInfo.none { it.index == spokenChunk }) {
android/app/src/main/kotlin/com/vreader/app/reader/TxtReaderActivity.kt:257:                                runCatching { listState.animateScrollToItem(spokenChunk) }
android/app/src/main/kotlin/com/vreader/app/reader/TxtReaderActivity.kt:1060:            var coords by remember(i) { mutableStateOf<androidx.compose.ui.layout.LayoutCoordinates?>(null) }
android/app/src/main/kotlin/com/vreader/app/reader/TxtReaderActivity.kt:1064:                    if (l != null && c != null) selectionController.registerChunk(i, l, c)
android/app/src/main/kotlin/com/vreader/app/reader/TxtReaderActivity.kt:1066:                DisposableEffect(selectionController, i) { onDispose { selectionController.unregisterChunk(i) } }
./android/app/src/main/kotlin/com/vreader/app/reader/TxtReaderActivity.kt:252:                        val spokenChunk = if (tts.phase == TtsPhase.speaking) s.document.chunkForOffset(tts.charStart) else -1
./android/app/src/main/kotlin/com/vreader/app/reader/TxtReaderActivity.kt:255:                        LaunchedEffect(spokenChunk) {
./android/app/src/main/kotlin/com/vreader/app/reader/TxtReaderActivity.kt:256:                            if (spokenChunk >= 0 && listState.layoutInfo.visibleItemsInfo.none { it.index == spokenChunk }) {
./android/app/src/main/kotlin/com/vreader/app/reader/TxtReaderActivity.kt:257:                                runCatching { listState.animateScrollToItem(spokenChunk) }
./android/app/src/main/kotlin/com/vreader/app/reader/TxtReaderActivity.kt:1060:            var coords by remember(i) { mutableStateOf<androidx.compose.ui.layout.LayoutCoordinates?>(null) }
./android/app/src/main/kotlin/com/vreader/app/reader/TxtReaderActivity.kt:1064:                    if (l != null && c != null) selectionController.registerChunk(i, l, c)
./android/app/src/main/kotlin/com/vreader/app/reader/TxtReaderActivity.kt:1066:                DisposableEffect(selectionController, i) { onDispose { selectionController.unregisterChunk(i) } }

codex
The live code confirms the essential raw data exists, but I’m checking one important implementation detail before deciding: whether the controller exposes enough viewport geometry (and how detached/unregistered chunks behave), since the plan’s “bounds intersect list viewport” predicate needs both source bounds and a reliable list viewport in the same coordinate space.
exec
/bin/zsh -lc "nl -ba android/app/src/main/kotlin/com/vreader/app/reader/TxtSelectionController.kt | sed -n '1,150p'
nl -ba android/app/src/main/kotlin/com/vreader/app/reader/TxtReaderActivity.kt | sed -n '205,270p'
nl -ba android/app/src/main/kotlin/com/vreader/app/reader/TxtReaderActivity.kt | sed -n '1025,1095p'
rg -n -C 5 \"setLazyCoords|TxtSelectionController\\(\" android/app/src/main/kotlin/com/vreader/app/reader/TxtReaderActivity.kt
nl -ba dev-docs/plans/20260710-feature-131-android-bilingual-interlinear.md | sed -n '96,116p'
nl -ba dev-docs/plans/20260710-feature-131-android-bilingual-interlinear.md | sed -n '366,384p'" in /Users/ll/workspace/vreader
 succeeded in 0ms:
     1	// Purpose: feature #124 WI-3 — drives the TXT custom selection. Each visible chunk registers its
     2	// TextLayoutResult + LayoutCoordinates; the controller converts a pointer (LazyColumn-local) → window
     3	// space → the hit chunk's local space → rendered offset → SOURCE offset (TxtSourceOffsets), and resolves
     4	// a word boundary at long-press. Selection is a SOURCE Utf16Range; the in-progress range renders as an
     5	// accent wash. Kept off the Activity so the geometry is isolated; the Activity wires the gesture +
     6	// popover + persistence.
     7	package com.vreader.app.reader
     8	
     9	import androidx.compose.runtime.Stable
    10	import androidx.compose.ui.geometry.Offset
    11	import androidx.compose.ui.layout.LayoutCoordinates
    12	import androidx.compose.ui.layout.boundsInWindow
    13	import androidx.compose.ui.text.TextLayoutResult
    14	import kotlinx.coroutines.flow.MutableStateFlow
    15	import kotlinx.coroutines.flow.StateFlow
    16	import kotlinx.coroutines.flow.asStateFlow
    17	
    18	@Stable
    19	class TxtSelectionController(
    20	    private val doc: TxtDocument,
    21	    // feature #125 — format-aware rendered↔source bridge. The chunk TextLayoutResults are built from the
    22	    // RENDERED text, so getOffsetForPosition/getWordBoundary/getCursorRect speak rendered coords; the
    23	    // mapper converts them to/from the SOURCE coords selections + highlights are stored in. TXT = identity.
    24	    private val mapper: ChunkTextMapper,
    25	) {
    26	    private data class ChunkInfo(val layout: TextLayoutResult, val coords: LayoutCoordinates)
    27	    /** A resolved hit: the chunk index/info + the chunk-local rendered offset + the absolute source offset. */
    28	    private data class Hit(val chunkIndex: Int, val info: ChunkInfo, val rendered: Int, val source: Int)
    29	    private val chunks = HashMap<Int, ChunkInfo>()
    30	    private var lazyCoords: LayoutCoordinates? = null
    31	    // the initial word selected at long-press — the FIXED anchor; drags extend relative to it (never drop it).
    32	    private var anchorRange: Utf16Range? = null
    33	
    34	    private val _selection = MutableStateFlow<Utf16Range?>(null)
    35	    val selection: StateFlow<Utf16Range?> = _selection.asStateFlow()
    36	
    37	    fun setLazyCoords(coords: LayoutCoordinates) { lazyCoords = coords }
    38	    fun registerChunk(index: Int, layout: TextLayoutResult, coords: LayoutCoordinates) {
    39	        chunks[index] = ChunkInfo(layout, coords)
    40	    }
    41	    fun unregisterChunk(index: Int) { chunks.remove(index) }
    42	
    43	    /** Pointer (LazyColumn-local) → the hit chunk + chunk-local rendered offset + source offset. The hit
    44	     *  chunk is used for BOTH the source mapping AND word-boundary lookup (avoids a chunk-boundary shift).
    45	     *  [allowNearest]: for a DRAG, fall back to the nearest chunk when the point is past the text; for a
    46	     *  TAP-to-edit, require the point to actually be inside a text chunk (else a margin tap could edit). */
    47	    private fun hitAt(localPoint: Offset, allowNearest: Boolean = true): Hit? {
    48	        val lz = lazyCoords ?: return null
    49	        if (chunks.isEmpty()) return null
    50	        val windowPoint = lz.localToWindow(localPoint)
    51	        val hit = chunks.entries.firstOrNull { it.value.coords.boundsInWindow().contains(windowPoint) }
    52	            ?: (if (allowNearest) chunks.entries.minByOrNull { verticalDistance(it.value.coords.boundsInWindow(), windowPoint) } else null)
    53	            ?: return null
    54	        val chunkLocal = hit.value.coords.windowToLocal(windowPoint)
    55	        val rendered = hit.value.layout.getOffsetForPosition(chunkLocal).coerceIn(0, hit.value.layout.layoutInput.text.length)
    56	        // rendered cursor → chunk-local source (empty rendered range maps to the source edge) → global source.
    57	        val localSource = mapper.renderedRangeToSource(hit.key, Utf16Range(rendered, rendered)).startInclusive
    58	        return Hit(hit.key, hit.value, rendered, doc.offsetForChunk(hit.key) + localSource)
    59	    }
    60	
    61	    /** Long-press: select the word under [localPoint] (word boundary in the HIT chunk, mapped to source). */
    62	    fun beginAt(localPoint: Offset) {
    63	        val hit = hitAt(localPoint) ?: return
    64	        val word = hit.info.layout.getWordBoundary(hit.rendered)   // RENDERED coords in the hit chunk
    65	        val base = doc.offsetForChunk(hit.chunkIndex)
    66	        // rendered word → chunk-local source span → global source (markers stripped for MD).
    67	        val src = mapper.renderedRangeToSource(hit.chunkIndex, Utf16Range(word.start, word.end))
    68	        val start = base + src.startInclusive
    69	        val end = base + src.endExclusive
    70	        val range = if (end > start) Utf16Range(start, end) else Utf16Range(hit.source, (hit.source + 1).coerceAtMost(doc.text.length))
    71	        anchorRange = range
    72	        _selection.value = range
    73	    }
    74	
    75	    /** Drag: extend relative to the FIXED [anchorRange] (the initial word) — extending before it grows the
    76	     *  start, after it grows the end, inside it keeps the word. The anchor word is never dropped. */
    77	    fun extendTo(localPoint: Offset) {
    78	        val anchor = anchorRange ?: return
    79	        val off = (hitAt(localPoint) ?: return).source.coerceIn(0, doc.text.length)
    80	        _selection.value = when {
    81	            off <= anchor.startInclusive -> Utf16Range(off, anchor.endExclusive)
    82	            off >= anchor.endExclusive -> Utf16Range(anchor.startInclusive, off)
    83	            else -> anchor
    84	        }
    85	    }
    86	
    87	    fun clear() { _selection.value = null; anchorRange = null }
    88	
    89	    /** The current selection range, or null. */
    90	    fun currentRange(): Utf16Range? = _selection.value
    91	
    92	    /** Resolve a tap (LazyColumn-local) to a SOURCE offset, for hit-testing an existing highlight. Strict
    93	     *  (no nearest-chunk fallback) so a tap in the margin/blank space doesn't edit a nearby highlight. */
    94	    fun resolveSourceOffset(localPoint: Offset): Int? = hitAt(localPoint, allowNearest = false)?.source
    95	
    96	    /** Convert a LazyColumn-local point to window coords (to anchor the edit popover at a tap). */
    97	    fun toWindow(localPoint: Offset): Offset? = lazyCoords?.localToWindow(localPoint)
    98	
    99	    /** Whether the current selection is a persist-worthy range (in-bounds, non-empty, surrogate-safe). */
   100	    fun isCurrentSelectionValid(): Boolean = _selection.value?.let { TxtSelection.isValid(it, doc.text) } ?: false
   101	
   102	    /** The VISIBLE (rendered) substring of the current selection — for the popover / copy / share / UI.
   103	     *  For TXT this equals the source; for MD it's the marker-stripped rendered text the user sees. */
   104	    fun selectedVisibleText(): String? {
   105	        val r = _selection.value ?: return null
   106	        if (r.isEmpty || r.endExclusive > doc.text.length) return null
   107	        val sb = StringBuilder()
   108	        for (cr in TxtSourceOffsets.chunkRanges(doc, r)) {
   109	            sb.append(mapper.visibleText(cr.chunkIndex, mapper.sourceRangeToRendered(cr.chunkIndex, cr.local)))
   110	        }
   111	        return sb.toString().ifEmpty { null }
   112	    }
   113	
   114	    /** The SOURCE (markdown/raw) substring of the current selection — for the locator textQuote + anchor. */
   115	    fun selectedSourceText(): String? {
   116	        val r = _selection.value ?: return null
   117	        if (r.isEmpty || r.endExclusive > doc.text.length) return null
   118	        return doc.text.substring(r.startInclusive, r.endExclusive)
   119	    }
   120	
   121	    /** The in-progress selection projected onto [chunkIndex] as a chunk-local RENDERED range, for the
   122	     *  accent wash (`getPathForRange` speaks rendered coords). Source→rendered via the mapper (MD). */
   123	    fun selectionForChunk(chunkIndex: Int): Utf16Range? {
   124	        val r = _selection.value ?: return null
   125	        val localSource = TxtSourceOffsets.chunkRanges(doc, r).firstOrNull { it.chunkIndex == chunkIndex }?.local ?: return null
   126	        return mapper.sourceRangeToRendered(chunkIndex, localSource)
   127	    }
   128	
   129	    /** The window-space point just below the selection's end, to anchor the popover. */
   130	    fun selectionEndAnchorWindow(): Offset? {
   131	        val r = _selection.value ?: return null
   132	        val endChunk = doc.chunkForOffset((r.endExclusive - 1).coerceAtLeast(0)).coerceIn(0, doc.chunkCount - 1)
   133	        val info = chunks[endChunk] ?: return null
   134	        val base = doc.offsetForChunk(endChunk)
   135	        // source end → chunk-local source → rendered cursor (end-affinity) for getCursorRect.
   136	        val localSourceEnd = (r.endExclusive - base).coerceAtLeast(0)
   137	        val renderedEnd = mapper.renderedCursorForSourceEnd(endChunk, localSourceEnd).coerceIn(0, info.layout.layoutInput.text.length)
   138	        val rect = info.layout.getCursorRect(renderedEnd)
   139	        return info.coords.localToWindow(Offset(rect.left, rect.bottom))
   140	    }
   141	
   142	    private fun verticalDistance(bounds: androidx.compose.ui.geometry.Rect, p: Offset): Float = when {
   143	        p.y < bounds.top -> bounds.top - p.y
   144	        p.y > bounds.bottom -> p.y - bounds.bottom
   145	        else -> 0f
   146	    }
   147	}
   205	                    }
   206	                }
   207	                // feature #129 — the live Display settings (theme/font/size/spacing/margin). NULL until
   208	                // the DataStore's first emission; the reader body is withheld until then (Gate-4 Medium:
   209	                // rendering defaults first would flash the wrong theme/typography for a user with stored
   210	                // non-default settings). The empty loading scaffold is the only pre-emission surface.
   211	                val settingsOrNull by container.readerSettingsStore.settings
   212	                    .collectAsStateWithLifecycle(initialValue = null)
   213	                val gated = if (settingsOrNull == null && state !is TxtUiState.Failed) TxtUiState.Loading else state
   214	                when (val s = gated) {
   215	                    is TxtUiState.Failed -> LaunchedEffect(Unit) { finish() }
   216	                    is TxtUiState.Loading -> TxtLoadingScaffold((settingsOrNull ?: ReaderSettings()).theme)
   217	                    is TxtUiState.Loaded -> {
   218	                        // non-null by the gate above (Loaded is unreachable pre-emission).
   219	                        val displaySettings = checkNotNull(settingsOrNull)
   220	                        val listState = rememberLazyListState(initialFirstVisibleItemIndex = s.initialIndex)
   221	                        // onStop flush — captures the live list state + book/document.
   222	                        SideEffect {
   223	                            flushPosition = { savePosition(s.book, s.document, listState.firstVisibleItemIndex) }
   224	                        }
   225	                        // Debounced steady-state save as the user scrolls.
   226	                        LaunchedEffect(listState, s.document) {
   227	                            snapshotFlow { listState.firstVisibleItemIndex }
   228	                                .drop(1)
   229	                                .debounce(1_000)
   230	                                .collect { savePosition(s.book, s.document, it) }
   231	                        }
   232	                        // feature #121 — read-aloud. The VM drives the designed control bar; the spoken
   233	                        // sentence is washed + auto-scrolled (TXT). Chunking is LAZY + off-main (only
   234	                        // on Read aloud) so a large book never scans the whole text on composition.
   235	                        val ttsVm: TtsViewModel = viewModel(factory = viewModelFactory {
   236	                            initializer { TtsViewModel(AndroidTtsEngine(applicationContext)) }
   237	                        })
   238	                        val tts by ttsVm.state.collectAsStateWithLifecycle()
   239	                        val ttsScope = rememberCoroutineScope()
   240	                        LaunchedEffect(ttsVm) { ttsVm.intents.collect { launchTtsIntent(it) } }
   241	                        // pause read-aloud when the reader is backgrounded (no MediaSession by design —
   242	                        // plan §OOS); the engine is shut down on Activity finish via the VM's onCleared.
   243	                        val lifecycleOwner = LocalLifecycleOwner.current
   244	                        DisposableEffect(lifecycleOwner) {
   245	                            // guard against ON_STOP firing on a rotation (config change) — the VM is
   246	                            // retained across rotation, so don't pause when we're just reconfiguring.
   247	                            val obs = LifecycleEventObserver { _, e -> if (e == Lifecycle.Event.ON_STOP && !isChangingConfigurations) ttsVm.pause() }
   248	                            lifecycleOwner.lifecycle.addObserver(obs)
   249	                            onDispose { lifecycleOwner.lifecycle.removeObserver(obs) }
   250	                        }
   251	                        val active = tts.phase != TtsPhase.idle
   252	                        val spokenChunk = if (tts.phase == TtsPhase.speaking) s.document.chunkForOffset(tts.charStart) else -1
   253	                        // auto-scroll ONLY when the spoken chunk is off-screen — so a small manual scroll
   254	                        // while listening isn't fought on every sentence.
   255	                        LaunchedEffect(spokenChunk) {
   256	                            if (spokenChunk >= 0 && listState.layoutInfo.visibleItemsInfo.none { it.index == spokenChunk }) {
   257	                                runCatching { listState.animateScrollToItem(spokenChunk) }
   258	                            }
   259	                        }
   260	                        var showSpeed by remember { mutableStateOf(false) }
   261	                        var showVoice by remember { mutableStateOf(false) }
   262	                        var starting by remember { mutableStateOf(false) }   // guards double-tap → double-chunk
   263	                        // snapshot the voice options once when the sheet opens (not every recomposition).
   264	                        val voiceList = remember(showVoice) { if (showVoice) ttsVm.voiceListState() else com.vreader.app.tts.TtsVoiceListState() }
   265	
   266	                        // feature #122 — reading-stats: track this session (the process-singleton tracker
   267	                        // survives rotation) + show the auto-fading session pill.
   268	                        val tracker = container.readingTimeTracker
   269	                        val bookKey = s.book.fingerprintKey
   270	                        val sessionSeconds by tracker.sessionSeconds.collectAsStateWithLifecycle()
  1025	                                selectionController.beginAt(longPress.position)
  1026	                                val completed = drag(longPress.id) { change -> selectionController.extendTo(change.position); change.consume() }
  1027	                                if (completed) currentOnFinalize() else selectionController.clear()
  1028	                            } else if (!down.isConsumed) {
  1029	                                // null also means cancel (e.g. a scroll won) — only a TAP leaves the down
  1030	                                // unconsumed; a scroll consumes it, so it won't be misread as tap-to-edit.
  1031	                                currentOnTap(down.position)
  1032	                            }
  1033	                        }
  1034	                    }
  1035	                } else {
  1036	                    Modifier
  1037	                },
  1038	            ),
  1039	        state = listState,
  1040	        contentPadding = PaddingValues(horizontal = marginDp.dp, vertical = 16.dp),
  1041	    ) {
  1042	        // Count-based: indices on demand (a newline-dense 14MB file can be 100k+ chunks).
  1043	        items(count = document.chunkCount, key = { it }) { i ->
  1044	            val raw = document.textForChunk(i).toString()
  1045	            // .md → styled markdown spans (no read-aloud span wash — markers shift offsets, plan §OOS).
  1046	            // .txt → raw verbatim, with the spoken-sentence span washed when read-aloud is active.
  1047	            val span = if (isMarkdown) null else highlightSpan(i)
  1048	            val text = when {
  1049	                isMarkdown -> mapper.renderedText(i)   // #125: the mapper is the single render owner
  1050	                span != null -> buildAnnotatedString {
  1051	                    append(raw)
  1052	                    val a = span.first.coerceIn(0, raw.length); val b = (span.last + 1).coerceIn(a, raw.length)
  1053	                    if (b > a) addStyle(SpanStyle(background = wash), a, b)
  1054	                }
  1055	                else -> AnnotatedString(raw)
  1056	            }
  1057	            // annotation washes drawn BEHIND the text (getPathForRange) — separate from the read-aloud span.
  1058	            val washes = washesForChunk(i)
  1059	            var layout by remember(i) { mutableStateOf<TextLayoutResult?>(null) }
  1060	            var coords by remember(i) { mutableStateOf<androidx.compose.ui.layout.LayoutCoordinates?>(null) }
  1061	            if (selectionController != null) {
  1062	                LaunchedEffect(i, layout, coords) {
  1063	                    val l = layout; val c = coords
  1064	                    if (l != null && c != null) selectionController.registerChunk(i, l, c)
  1065	                }
  1066	                DisposableEffect(selectionController, i) { onDispose { selectionController.unregisterChunk(i) } }
  1067	            }
  1068	            // read `selection` (a State) so a selection change recomposes + redraws the accent.
  1069	            val selRange = if (selection != null) selectionController?.selectionForChunk(i) else null
  1070	            Text(
  1071	                text = text,
  1072	                // merge over the material default (the pre-#129 explicit-param behavior) so platform
  1073	                // text defaults (letterSpacing etc.) are kept — only the Display settings change.
  1074	                style = androidx.compose.material3.LocalTextStyle.current.merge(textStyle),
  1075	                onTextLayout = { layout = it },
  1076	                modifier = Modifier
  1077	                    .onGloballyPositioned { coords = it }
  1078	                    .drawBehind {
  1079	                        layout?.let { l ->
  1080	                            drawWashes(l, washes)
  1081	                            selRange?.let { drawRangeFill(l, it, selectionAccent) }
  1082	                        }
  1083	                    },
  1084	            )
  1085	        }
  1086	    }
  1087	}
282-                            if (annotatable) container.annotationsRepository.highlights(bookKey) else flowOf(emptyList())
283-                        }.collectAsStateWithLifecycle(emptyList())
284-                        val washMap = remember(highlightsList, s.document, chunkMapper) { TxtWashMapper.washesByChunk(s.document, highlightsList, chunkMapper) }
285-
286-                        // feature #124/#125 — custom selection + popover (TXT + MD).
287:                        val selectionController = remember(s.document, chunkMapper) { if (annotatable) TxtSelectionController(s.document, chunkMapper) else null }
288-                        val popoverVm = remember(bookKey) { com.vreader.app.annotations.SelectionPopoverViewModel() }
289-                        val popoverState by popoverVm.state.collectAsStateWithLifecycle()
290-                        DisposableEffect(lifecycleOwner, bookKey) {
291-                            val obs = LifecycleEventObserver { _, e ->
292-                                when (e) {
--
1009-    val currentOnTap by androidx.compose.runtime.rememberUpdatedState(onTapAt)
1010-    val currentOnFinalize by androidx.compose.runtime.rememberUpdatedState(onSelectionFinalized)
1011-    LazyColumn(
1012-        Modifier
1013-            .fillMaxSize()
1014:            .onGloballyPositioned { selectionController?.setLazyCoords(it) }
1015-            .then(
1016-                if (selectionController != null) {
1017-                    // ONE detector distinguishes a TAP (edit an existing highlight) from a LONG-PRESS+drag
1018-                    // (new selection) — two separate pointerInput detectors conflict over the same down event.
1019-                    Modifier.pointerInput(selectionController) {
    96	
    97	1. Open a `Column` for item `i`.
    98	2. Render the source chunk `i` **EXACTLY as today** (the unchanged `Text` + its `remember(i)` layout/coords + `registerChunk(i, …)`/`unregisterChunk(i)` + `highlightSpan(i)`/`washesForChunk(i)`/`selectionForChunk(i)` — TxtReaderActivity.kt:1044–1084, now the first child of the `Column`).
    99	3. Look up the translations **anchored** to chunk `i` = every segment whose end resolves to `chunkForOffset(span.endExclusive - 1) == i`, in segment order, from the shared span array. For **paragraph** granularity (the only v1 granularity — see the granularity subsection) there is at most one such translation per anchor chunk in the common case (a paragraph's translation renders after the paragraph's last line-chunk).
   100	4. Emit each anchored translation as a muted, non-registered `Text` sibling **inside the same `Column`**, keyed by the segment's `Utf16Span` so a language change re-keys cleanly.
   101	
   102	When bilingual is **OFF**, no translation children are emitted → each item's `Column` holds only the unchanged source `Text`, so the tree is **behaviorally identical to today** (translations are additive in-item children only; this is asserted by a source-selection-parity test, since a single-child `Column` does not perturb the source `Text`'s layout/registration/offsets).
   103	
   104	- **Explicit translation gesture exclusion (round-4 High-2 — BINDING):** `TxtSelectionController.hitAt` (`reader/TxtSelectionController.kt:47`) falls back to the **nearest registered source chunk** when the pointer is outside all source-chunk bounds (`chunks.entries.minByOrNull { verticalDistance(...) }` when no chunk's `boundsInWindow()` contains the point, :51–53). So merely omitting `registerChunk` for the translation does **NOT** make it non-selectable — a long-press *on the translation text* would fall through to the nearest source chunk and select source. **WI-8 must add an explicit hit-test / gesture exclusion for the translation composable's bounds** so a long-press whose pointer lands inside a translation `Text`'s bounds is consumed (no selection begun) rather than routed to `hitAt`'s nearest-chunk fallback. (Options: the translation `Text` consumes the long-press gesture in its own `pointerInput`; or the selection gesture root records the translation composables' window bounds and short-circuits `beginAt` when the point is inside one. WI-8 picks and tests one.)
   105	
   106	- **TTS auto-scroll visibility must key off the SOURCE `Text` bounds, NOT the item index (round-5 High — a NEW consequence of the in-item `Column`):** the TTS auto-scroll guard (TxtReaderActivity.kt:252/256) currently keeps the spoken chunk on screen via `listState.layoutInfo.visibleItemsInfo.none { it.index == spokenChunk }` — item-level visibility. With the in-item `Column`, an item is now taller than its source line (source + translation children), so when `spokenChunk`'s SOURCE `Text` has scrolled above the viewport but its translation sibling is still visible, `visibleItemsInfo` still contains the item's index → the guard falsely suppresses `animateScrollToItem(spokenChunk)` and leaves the spoken SOURCE off-screen. **WI-8 must redefine the TTS-visibility predicate to test the registered SOURCE `Text` bounds** — the selection controller already tracks each source chunk's `LayoutCoordinates`/`boundsInWindow()` via `registerChunk(i, layout, coordinates)` (TxtSelectionController.kt): `spokenChunk` is visible iff its registered source bounds intersect the list viewport; otherwise `animateScrollToItem(spokenChunk)` scrolls the item's top (the source) into view. This is **inert when bilingual is OFF** (no translation child → item height == source height → item-index visibility already equals source visibility), so the disabled path is byte-identical.
   107	
   108	- **Enabled-mode tests (WI-8 connected + WI-7a Compose, BINDING):** with bilingual ON —
   109	  - (a) each source chunk's **selection registration is UNCHANGED** (same `registerChunk(i, …)` count and coordinates as OFF; a translation child registers nothing);
   110	  - (b) **highlights/annotation washes/read-aloud wash still key off the source chunks** at the correct offsets (a translation child in the anchor's `Column` does not shift them);
   111	  - (c) **lazy-index == chunk-index preserved:** with bilingual ON — **position-save round-trips to the same chunk** (`offsetForChunk(firstVisibleItemIndex)` → save → reopen → `chunkForOffset(offset)` lands on the same chunk); **bookmark/annotation/search/scrubber jumps land on the correct chunk** (`scrollToItem(chunkForOffset(target))` scrolls to the right item); **TTS auto-scroll keeps the spoken SOURCE on screen — visibility keyed off the registered source `Text` bounds, NOT `visibleItemsInfo.index` (round-5 High)**, INCLUDING the case where only `spokenChunk`'s translation portion is visible (its source scrolled above the viewport) → TTS brings the SOURCE back on-screen; (assert the index-identity behaviors above are identical to the OFF baseline — no lazy index shift);
   112	  - (d) a **long-press on translation text does NOT select** (gesture exclusion — the nearest-source-chunk fallback is not reached);
   113	  - (e) a **translation child is non-selectable** and does not perturb source offsets (selecting across the source/translation boundary selects source only);
   114	  - (f) **MD source mapping** — the markdown renderer (`mapper.renderedText(i)`, TxtReaderActivity.kt:1049) still owns the source chunk render; the translation child is plain muted text;
   115	  - (g) **paragraph-spanning-many-chunks** renders exactly ONE translation (inside the paragraph's last chunk's `Column`), never per-line;
   116	  - (h) final-chunk/one-chunk anchors render (H1).
   366	
   367	**WI-7a (behavioral): Compose UI — setup sheet + interlinear body (TXT/MD) + pill.** Reproduce `vreader-bilingual.jsx` (setup sheet: language grid / **Paragraph-only Granularity control (round-4 H3)** / preview / engine strip configured+unconfigured; body: the translation rendered **inside the anchor chunk's `Column` as a muted non-registered `Text` child** per the round-4 H2 render contract — translated / loading N%+dimmed / error+Retry / offline source-only; pill). Consumes the host-neutral `BilingualRenderState` DTO. Light+dark. Compose UI tests each state, incl. **paragraph interlinear renders a translation child after a paragraph's last source chunk (depicted)**; **the setup-sheet Granularity control shows Paragraph only, no Sentence option (H3)**. Deps: WI-5 (state shape). NO Style control; the unconfigured "Set up" CTA renders and (in WI-9) routes to the Variant A sheet.
   368	
   369	**WI-7b (behavioral, CONDITIONAL — only if WI-0 = go): EPUB render adapter (DOM injection, NOT Compose — M2) + direct-block ownership (M1).** `EpubBilingualJs` (enum/inject/clear JS builders, CSP-safe escaping) + `EpubBilingualController` (the serialization actor / session token AND the **single-owner enumerate→cachedDirect/prefetchDirect→guarded-commit sequence — Medium-1**) + `EpubChapterTextProvider`, wired into `ReaderActivity`, driving DOM from the shared `BilingualRenderState` DTO. Uses `prefetchDirect`/`cachedDirect` for the count-divergence path (H2). Depends on WI-6 (VM state) and WI-4b (DI); the WI-7a UI dependency is only the shared `BilingualRenderState`/value types. Connected test on a real EPUB (seeded cache): enable → injects; disable → cleared; reflow/href-change/fragment-recreation/activity-recreation → re-applies from cache (zero provider calls) via `cachedDirect`; count-divergence handled (direct path); **the regular TXT/MD prefetch path is never invoked for an EPUB unit (Medium-1)**. Unit tests: JS escaping/CSP-safe insertion, RTL/CJK style, empty translations, loading cleanup, idempotent replacement, source-only fallback, stale-session-token commit discarded (no `errorUnit`). Deps: WI-0, WI-3, WI-4a, WI-4b, WI-6, (shared types from WI-7a). (If WI-0 = no-go, dropped; box D ships TXT/MD-only, tracked.)
   370	
   371	**WI-AIP (behavioral — the folded-in Variant A AI Providers sheet; round-4 H4 rewritten): `ReaderAiProvidersSheet`.** The scoped in-reader "AI Providers" push sheet (nav bar `‹ Bilingual` + "AI Providers" title) reproducing `vreader-ai-provider-entry.jsx` `AIProvidersSheet`/`AIProvidersSheetBody`/`NavSheet`. Per round-4 H4:
   372	  - **(a)** present `AiProviderEditSheet` VERBATIM from #118 (Kind/Name/Endpoint/Sampling/API Key/Test Connection unchanged).
   373	  - **(b)** a NEW `ReaderAiProvidersList` presentation over the SHARED `AiSettingsViewModel.listState` (verified `AiSettingsViewModel.kt:26`; each `AiProviderRow` already carries `active`, :30) + shared row/cell components — reproducing the reader-scoped `‹ Bilingual` nav (`NavSheet`, jsx:247, NOT `AiProviderListScreen`'s `NavScreen`), the bilingual-context empty state ("Choose the provider bilingual mode will use to translate this book." + "No providers yet" + "Add provider" — jsx:180–209), the **checked-active row** (`selected = row.active` — jsx:221), and **tap-to-SELECT** (`onSelect(id) → vm.setActive(id)` — jsx:221/237). It does NOT reuse `AiProviderListScreen`'s NavScreen/chrome/`AiEmptyState`/`ProviderRow`-tap-edit.
   374	  - **(c)** the **save-result seam**: `AiSettingsViewModel.save()` (or a thin WI-AIP wrapper) is extended to return the saved provider ID (from `store.upsert(...).id`, which the store already returns — `AiProviderStore.kt:58/84`), so on first Save → `store.setActive(savedId)` → pop the whole stack back to the bilingual sheet (engine strip now "configured / Change…"), **deterministically, after the upsert commits (no race)**.
   375	  `‹ Bilingual` without adding → unconfigured, no state mutated. "Change…" → populated list, current provider checked, tap row → `setActive`. No consent/flag surface (Android has none). Deps: WI-4b (for `AiProviderStore` + `AiSettingsViewModel` in `AppContainer`), WI-7a (bilingual sheet host). Tests (Compose + connected): the scoped list renders **`‹ Bilingual` back label** + **bilingual-context empty copy** + **checked active row** + **tap-selects (`setActive`)**; empty → Add → Save → **save→result-id→`setActive`→pop deterministic (no race)** → bilingual strip configured; `‹ Bilingual` without adding → strip unconfigured, snapshot unchanged; "Change…" → populated, current checked; editor reused verbatim (no divergent form).
   376	
   377	**WI-8 (behavioral): `TxtReaderActivity` integration.** Wire VM into the `items(count = document.chunkCount, key = { it })` loop as **muted non-registered translation `Text` children inside each anchor chunk's wrapping `Column`, source chunk byte-unchanged, the loop + keys UNCHANGED so lazy-index==chunk-index is preserved (round-4 H2)** + the translation **gesture-exclusion** (round-4 H2) + the **TTS source-bounds visibility fix** (round-5 H: the TTS auto-scroll predicate keys off the registered source `Text` bounds, not `visibleItemsInfo.index`, so a translation-only-visible item does not falsely suppress the auto-scroll) + position-change (`charOffsetUTF16`) + setup-sheet. `originalFormat`-gated (TXT/MD). Uses WI-4b's DI. **#129 VERIFIED — straight edit.** Connected test (fake `AiClient` seam): enable → setup → confirm → interlinear from seeded cache; **enabled-mode source-chunk selection registrations UNCHANGED vs disabled (H2)**; **highlights/annotation-washes/read-aloud-wash still key off source chunks (H2)**; **with bilingual ON — position-save round-trips to the same chunk; bookmark/search/scrubber/TTS jumps land on the correct chunk (lazy-index==chunk-index preserved — round-4 H2); TTS auto-scroll brings the spoken SOURCE on-screen even when only its translation portion is visible (source-bounds visibility — round-5 H)**; **a long-press on translation text does NOT select (gesture exclusion — round-4 H2)**; a translation child is non-selectable, does not perturb source offsets (H2); disable → source-selection byte-parity; reopen persists enabled + renders from cache with zero client calls; **paragraph-spanning-many-chunks renders exactly one translation inside its last chunk's `Column` (H1/Low-2)**; **one-chunk/final-chunk anchors render (H1)**; MD source mapping. Deps: WI-6, WI-7a, WI-4b.
   378	
   379	**WI-9 (behavioral): entry wiring + acceptance.** Mount `BilingualPill` in #132's VERIFIED top chrome; extend `readerMoreRows(...)` to supply the #134 VERIFIED More-menu `MoreActionId.BILINGUAL` toggle (`MoreRow.Toggle` `on`/`onToggle`, or `MoreRow.Disabled` "Configure AI provider first" when not configured) wired to the VM; **wire the setup sheet's "Set up"/"Change…" affordance → the #131-owned `ReaderAiProvidersSheet` (Variant A)**. Full acceptance across EPUB (if WI-7b landed) + TXT/MD, including the fresh-user path `unconfigured → Set up (→ Variant A AI Providers sheet) → add provider → Save → return → enable → translate` (now #131-owned end-to-end). **Flip box D to done ONLY for provider/model/granularity(paragraph) + the Style-descope AND Sentence-descope notes; file the follow-up checklist amendment; do NOT claim full box-D parity.** The DONE flip **no longer waits on #136** (closed). Update `docs/architecture.md` (bilingual pipeline + the new `chapter_translations` schema + `AiProviderStore` + bilingual services in `AppContainer` + the Variant A AI Providers sheet). → DONE. Deps: WI-8, WI-AIP, WI-7b (if go), feat:#132, feat:#134.
   380	
   381	## 5. Test catalogue
   382	
   383	JVM/Robolectric (`android/app/src/test/...bilingual/`): `Utf16SpanTest` (**half-open invariants: `endExclusive >= start`, `isEmpty`, `length`; round-4 H1**); `ChapterSegmenterTest` (paragraph blank-line; sentence CJK `。！？` vs Latin; empty→[]; single; **`paragraphRanges`/`sentenceRanges` return correct half-open `Utf16Span(start, endExclusive)` spans — both APIs covered even though only `paragraphRanges` ships in the v1 render path**); `TranslationChunkerTest` (packs to budget; oversize→own chunk+subSplit; empty→[]); `TranslationChunkContractTest` (prompt shape; strict JSON decode; code-fence strip; count mismatch→`CountMismatch`; non-array→`NotAStringArray`); `ChapterTranslationServiceTest` (cache hit 0 calls; miss→translate→write; decode-fail per-segment fallback; one-chunk-fail partial-not-cached; all-fail→throw; **native-cancel→Cancelled no write; typed-`Cancelled`→Cancelled no write (M2)**; ensureActive-before-write; offline/timeout/429/http/config/insecure→error mapping; very long chapter N-of-M; stale-cache count-mismatch re-translates; `translatePreSegmented` caches under enumerate count on full success; partial degrade not cached; all-fail throws; `cachedTranslation(expectedSegmentCount)` hit/miss with no provider); `ChapterTranslationErrorMappingTest`; `TxtChapterTextProviderTest` (**one-chunk document → renders (H1); final-chunk anchor → renders (H1); exact-boundary → correct anchor (H1); EOF anchor → last chunk, no clamp-collapse (H1)**; paragraph spanning MANY chunks → one segment/unit anchored to last chunk (Low-2); >4000-char paragraph → one segment across hard-split chunks; CR/LF/CRLF; MD markers; locator→unit mapping; `unitAfter` end→null; source-byte parity while disabled; **provider uses `paragraphRanges` only — H3**); `ChapterTranslationPrefetcherTest` (snapshot-consistent profile+key; injected-factory used; `AiRequest` built from profile; **blank `profile.model` → `kind.defaultModel` (M3 regression)**; cache-hit-no-profile #306; no-profile miss→ProviderFailed; `prefetchDirect` 1:1; `cachedDirect` restores with zero provider calls; CJK↔English + Latin round-trip via fake; cipher-throw→ProviderFailed not crash); `BilingualAiReadinessTest` (active+key→true; **no-active-with-profiles-present→false (H3); activeId-null→false (H3)**; empty key→false; cipher-throw→false, no crash); `PerBookBilingualStoreTest` (enabled/lang/granularity round-trip; granularity pinned paragraph; no style field); `BilingualViewModelTest` (Turbine: first-enable sheet; re-enable no-sheet; disable clears; language reset; `aiConfigured` from readiness; prefetch current+next; same-unit no-op; **cancel-mid discards (no errorUnit); typed-Cancelled discards (M2); rapid re-trigger same unit single-flight, no double-write (M2)**; offline→unavailable; error→errorUnit+retry; `retryUnit`); `AiSettingsViewModelSaveResultTest` (**`save()` returns the saved provider ID after the upsert commits — round-4 H4c seam; the returned ID matches `store.upsert(...).id`**); `EpubBilingualJsTest` (JS escaping / CSP-safe insertion; RTL/CJK style; empty translations; clear idempotent; inject idempotent replacement; source-only fallback — WI-7b if go); `EpubBilingualControllerTest` (**enumerate→cachedDirect/prefetchDirect→guarded commit; stale-session-token commit discarded, no errorUnit; single-owner (regular TXT/MD prefetch never runs for EPUB unit) — Medium-1** — WI-7b if go).
   384	

exec
/bin/zsh -lc "nl -ba android/app/src/main/kotlin/com/vreader/app/reader/TxtReaderActivity.kt | sed -n '270,310p'
rg -n \"val annotatable|annotatable =|originalFormat\" android/app/src/main/kotlin/com/vreader/app/reader/TxtReaderActivity.kt | head -30
rg -n \"fun boundsInWindow|boundsInWindow\\(\" \""'$HOME/.gradle/caches" 2>/dev/null | head -20' in /Users/ll/workspace/vreader
 succeeded in 433ms:
codex
Critical

None.

High

None.

Medium

None.

Low

- Detached-coordinate handling should be explicit. The controller stores each source chunk’s `LayoutCoordinates`, but disposal and scrolling can briefly leave detached coordinates before `unregisterChunk()` completes ([TxtSelectionController.kt](/Users/ll/workspace/vreader/android/app/src/main/kotlin/com/vreader/app/reader/TxtSelectionController.kt:26), [TxtReaderActivity.kt](/Users/ll/workspace/vreader/android/app/src/main/kotlin/com/vreader/app/reader/TxtReaderActivity.kt:1060)). WI-8 should define `null`, missing, or `!coords.isAttached` as “not visible,” causing `animateScrollToItem(spokenChunk)`, and ideally test the unregistered/pre-layout case. This is bounded and does not undermine the fix.

Confirmation:

- `registerChunk()` stores the source `TextLayoutResult` and `LayoutCoordinates`; the `LazyColumn` coordinates are also stored, providing source and viewport geometry in window coordinates ([TxtSelectionController.kt](/Users/ll/workspace/vreader/android/app/src/main/kotlin/com/vreader/app/reader/TxtSelectionController.kt:26), [TxtSelectionController.kt](/Users/ll/workspace/vreader/android/app/src/main/kotlin/com/vreader/app/reader/TxtSelectionController.kt:37), [TxtReaderActivity.kt](/Users/ll/workspace/vreader/android/app/src/main/kotlin/com/vreader/app/reader/TxtReaderActivity.kt:1011), [TxtReaderActivity.kt](/Users/ll/workspace/vreader/android/app/src/main/kotlin/com/vreader/app/reader/TxtReaderActivity.kt:1064)). The map is private, so WI-8 must add a controller query rather than access it directly.
- Source-bounds intersection correctly distinguishes translation-only visibility: source above viewport → scroll; source intersecting viewport → no scroll; source below or unregistered → scroll. This directly replaces the insufficient item-index guard ([TxtReaderActivity.kt](/Users/ll/workspace/vreader/android/app/src/main/kotlin/com/vreader/app/reader/TxtReaderActivity.kt:252)).
- With bilingual OFF, the single-child item has the same extent as its source `Text`, so steady-state source visibility and item visibility are equivalent. The patch is behaviorally inert apart from the harmless missing/pre-layout fallback noted above.
- The plan includes the decisive translation-only-visible connected regression test ([20260710-feature-131-android-bilingual-interlinear.md](/Users/ll/workspace/vreader/dev-docs/plans/20260710-feature-131-android-bilingual-interlinear.md:377)).

FINAL VERDICT: follow-up-recommended
tokens used
33,630
Critical

None.

High

None.

Medium

None.

Low

- Detached-coordinate handling should be explicit. The controller stores each source chunk’s `LayoutCoordinates`, but disposal and scrolling can briefly leave detached coordinates before `unregisterChunk()` completes ([TxtSelectionController.kt](/Users/ll/workspace/vreader/android/app/src/main/kotlin/com/vreader/app/reader/TxtSelectionController.kt:26), [TxtReaderActivity.kt](/Users/ll/workspace/vreader/android/app/src/main/kotlin/com/vreader/app/reader/TxtReaderActivity.kt:1060)). WI-8 should define `null`, missing, or `!coords.isAttached` as “not visible,” causing `animateScrollToItem(spokenChunk)`, and ideally test the unregistered/pre-layout case. This is bounded and does not undermine the fix.

Confirmation:

- `registerChunk()` stores the source `TextLayoutResult` and `LayoutCoordinates`; the `LazyColumn` coordinates are also stored, providing source and viewport geometry in window coordinates ([TxtSelectionController.kt](/Users/ll/workspace/vreader/android/app/src/main/kotlin/com/vreader/app/reader/TxtSelectionController.kt:26), [TxtSelectionController.kt](/Users/ll/workspace/vreader/android/app/src/main/kotlin/com/vreader/app/reader/TxtSelectionController.kt:37), [TxtReaderActivity.kt](/Users/ll/workspace/vreader/android/app/src/main/kotlin/com/vreader/app/reader/TxtReaderActivity.kt:1011), [TxtReaderActivity.kt](/Users/ll/workspace/vreader/android/app/src/main/kotlin/com/vreader/app/reader/TxtReaderActivity.kt:1064)). The map is private, so WI-8 must add a controller query rather than access it directly.
- Source-bounds intersection correctly distinguishes translation-only visibility: source above viewport → scroll; source intersecting viewport → no scroll; source below or unregistered → scroll. This directly replaces the insufficient item-index guard ([TxtReaderActivity.kt](/Users/ll/workspace/vreader/android/app/src/main/kotlin/com/vreader/app/reader/TxtReaderActivity.kt:252)).
- With bilingual OFF, the single-child item has the same extent as its source `Text`, so steady-state source visibility and item visibility are equivalent. The patch is behaviorally inert apart from the harmless missing/pre-layout fallback noted above.
- The plan includes the decisive translation-only-visible connected regression test ([20260710-feature-131-android-bilingual-interlinear.md](/Users/ll/workspace/vreader/dev-docs/plans/20260710-feature-131-android-bilingual-interlinear.md:377)).

FINAL VERDICT: follow-up-recommended
