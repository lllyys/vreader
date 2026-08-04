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
session id: 019f5489-08ac-7270-bd38-7a77afd2ef54
--------
user
Gate-2 plan audit ROUND 5 (FOCUSED, DECISIVE) for feature #131 (Android bilingual interlinear reading). Read the v5 plan at dev-docs/plans/20260710-feature-131-android-bilingual-interlinear.md. Round 4 was block-recommended with 4 High and it CONFIRMED M1/M2/M3/M4 and the Lows resolved. v5 is a TARGETED PATCH resolving ONLY the 4 round-4 High findings plus 2 gaps. Audit ONLY these six items (do NOT re-audit M1/M2/M3/M4 or the Lows — round-4 already cleared them). Be DECISIVE: is each resolved, and is any NEW blocker introduced by the patch?

1. H1 (round-4 High-1, type): v5 introduces a dedicated value type Utf16Span with fields start and endExclusive (new file bilingual/Utf16Span.kt, section 2 H1) replacing List of IntRange EVERYWHERE in the segment/span contracts (ChapterSegmenter.paragraphRanges/sentenceRanges now return List of Utf16Span). Confirm no IntRange remains in the segment/render contract and that Utf16Span (half-open, require endExclusive >= start) is a sound half-open type. Verify against reader/TxtDocument.kt that the final-chunk math (endExclusive = if i+1 less-than chunkCount then offsetForChunk(i+1) else text.length) plus chunkForOffset(span.endExclusive - 1) anchoring is still correct for one-chunk/final-chunk/exact-boundary/EOF.

2. H2 (round-4 High-2, THE key fix, lazy-index identity): v5's binding render contract is now ONE lazy item per chunk — the items(count=chunkCount, key it) loop plus keys UNCHANGED, and INSIDE each item a Column holds the UNCHANGED source Text (one TextLayoutResult, one registerChunk(i)) followed by muted non-registered translation Text children anchored to chunk i. Verify against reader/TxtReaderActivity.kt that this preserves BOTH (a) the per-chunk one-TextLayoutResult/one-selection-registration invariant (~1043-1085) AND (b) the lazy-index equals chunk-index identity the reader relies on for position-save (~220/473/623 offsetForChunk of firstVisibleItemIndex), every jump (~411/421/454/481 scrollToItem of chunkForOffset), and TTS visibility (~252/256 visibleItemsInfo index equals spokenChunk). Confirm a Column child adds NO lazy item and shifts NO index. Verify the translation gesture-exclusion is required plus sound (reader/TxtSelectionController.kt ~47-53 hitAt nearest-chunk fallback means omitting registerChunk is NOT enough to make translation non-selectable). Look for ANY remaining way the in-item Column could still break selection/highlight/wash/position/jump/TTS.

3. H3 (round-4 High-3, Paragraph-only v1): v5 constrains v1 to Paragraph granularity only (segments/caches/renders paragraph; promptVersion g=paragraph always; no sentenceRanges in the v1 render path; setup-sheet Granularity control Paragraph-only; TranslationGranularity.sentence plus ChapterSegmenter.sentenceRanges kept as reserved-foundational WI-1 code). Confirm this removes the underspecified sentence-to-paragraph aggregation AND the wrong-shape-cache-row risk, and is rule-51-clean (verify vreader-bilingual.jsx BilingualPageContent depicts only paragraph interlinear). Is descoping the Sentence CONTROL option (not just the render) sound?

4. H4 (round-4 High-4, WI-AIP fold-in): v5 splits WI-AIP into (a) reuse AiProviderEditSheet VERBATIM, (b) a NEW ReaderAiProvidersList over the shared AiSettingsViewModel.listState reproducing the designed back-to-Bilingual nav plus bilingual-context empty state plus checked-active row plus tap-to-SELECT (NOT reusing AiProviderListScreen's NavScreen/chrome/AiEmptyState/row-tap-edit), (c) a save-result seam on AiSettingsViewModel.save() returning the saved id (from store.upsert result id which the store already returns — AiProviderStore.kt ~58/84) so setActive(savedId) plus pop is race-free. Verify against ai/AiProviderListScreen.kt (owns own NavScreen ~59, generic empty ~84, row-tap-edit ~105), ai/AiSettingsViewModel.kt (save ~85-97 discards id; listState ~26; row.active ~30), ai/AiProviderStore.kt (upsert returns saved profile ~58/84; setActive; activeId = cur.activeId or id ~81), and vreader-ai-provider-entry.jsx (NavSheet backLabel Bilingual ~247; selected/onSelect ~221; empty copy ~180-209). Is the split rule-51-clean plus race-free? Any NEW issue (e.g. the additive save seam touching #118 code)?

5. Gap A (MIGRATION_8_9 DDL): section 2/WI-2 now spell out the exact CREATE TABLE chapter_translations DDL (all NOT NULL cols, PK lookupKey, index_chapter_translations_bookKey, FK to books fingerprintKey ON DELETE CASCADE, modeled on MIGRATION_6_7) plus require the migration test to validate against Room's generated 9.json. Verify the DDL shape matches the entity plus the other child tables in data/VReaderDatabase.kt, and that the exact-DDL-vs-generated-schema guard is the right approach.

6. Gap B (backup granularity flag): v5 flags (sections 6/7) that the backup bilingualGranularity field's cross-platform conformance vector plus iOS parity are UNCONFIRMED, safe for v1 (backup descoped/device-local), follow-up when backup wiring lands. Confirm this is an adequate flag (not a v1 blocker).

Output findings grouped by severity (Critical/High/Medium/Low), each with file:line evidence, then a FINAL VERDICT line exactly one of: ship-as-is | follow-up-recommended | block-recommended. ship-as-is or follow-up-recommended clears Gate-2.
codex
I’ll perform the narrowly scoped six-item audit only. I’ll first inspect repository status, the complete v5 plan, architecture context, design artifacts, and the cited Android implementation lines, then report only unresolved or newly introduced findings with precise evidence.
exec
/bin/zsh -lc "git status -sb && wc -l docs/architecture.md dev-docs/plans/20260710-feature-131-android-bilingual-interlinear.md && rg --files | rg '("'^|/)(TxtDocument|TxtReaderActivity|TxtSelectionController|AiProviderListScreen|AiSettingsViewModel|AiProviderStore|VReaderDatabase)'"\\.kt"'$|vreader-(bilingual|ai-provider-entry)'"\\.jsx"'$'"'" in /Users/ll/workspace/vreader
 succeeded in 1100ms:
git: warning: confstr() failed with code 5: couldn't get path of DARWIN_USER_TEMP_DIR; using /tmp instead
git: error: couldn't create cache file '/tmp/xcrun_db-dxUlxcxy' (errno=Operation not permitted)
## main...origin/main
 M dev-docs/plans/20260710-feature-131-android-bilingual-interlinear.md
 M docs/features.md
?? .claude/codex-audits/feat-131-bilingual-gate2-round2.md
?? .claude/codex-audits/feat-131-bilingual-gate2-round3.md
?? .claude/codex-audits/feat-131-bilingual-gate2-round4.md
?? .claude/codex-audits/feat-131-bilingual-gate2-round5.md
?? .claude/codex-audits/feat-136-ai-provider-reachable-gate2.md
?? android/2026-06-29-223908-this-session-is-being-continued-from-a-previous-c.txt
?? dev-docs/security/
     726 docs/architecture.md
     441 dev-docs/plans/20260710-feature-131-android-bilingual-interlinear.md
    1167 total
dev-docs/designs/vreader-fidelity-v1/project/vreader-ai-provider-entry.jsx
dev-docs/designs/vreader-fidelity-v1/project/vreader-bilingual.jsx
android/app/src/main/kotlin/com/vreader/app/data/VReaderDatabase.kt
android/app/src/main/kotlin/com/vreader/app/reader/TxtDocument.kt
android/app/src/main/kotlin/com/vreader/app/reader/TxtSelectionController.kt
android/app/src/main/kotlin/com/vreader/app/reader/TxtReaderActivity.kt
android/app/src/main/kotlin/com/vreader/app/ai/AiProviderListScreen.kt
android/app/src/main/kotlin/com/vreader/app/ai/AiProviderStore.kt
android/app/src/main/kotlin/com/vreader/app/ai/AiSettingsViewModel.kt

exec
/bin/zsh -lc "sed -n '1,500p' dev-docs/plans/20260710-feature-131-android-bilingual-interlinear.md" in /Users/ll/workspace/vreader
 succeeded in 0ms:
# Feature #131 — Android Bilingual Interlinear Reading (parity-checklist box D)

**Feature number assumption:** highest active row in `docs/features.md` is `#136` (now CLOSED, see below); `#131` is a landed `PLANNED` row (`GH: #1923`). The orchestrator adjusts if a row is claimed first.

**Design authority (rule 51):** the **authoritative** bilingual surfaces are:
- `dev-docs/designs/vreader-fidelity-v1/project/vreader-bilingual.jsx` (`BilingualSetupSheet` / `BilingualPageContent` / `BilingualPill` / `BILINGUAL_LANGS`) — the setup sheet, the **paragraph-interlinear** renderer, and the top-chrome pill.
- `.../vreader-reader.jsx` (`ReaderTopChrome` renders `BilingualPill`; the bilingual toggle is a More-menu row via `onMoreAction`) and `.../vreader-more.jsx` (the "Bilingual mode" More-menu Row toggle).
- **The in-reader AI-config surface (folded in from the closed #136):** `dev-docs/designs/vreader-fidelity-v1/project/design-notes/reader-ai-provider-entry.md` (the CANONICAL **Variant A** decision + navigation model, lines ~39–76, ~110–134) and `.../vreader-ai-provider-entry.jsx` (`AIProvidersSheet`, `AIProvidersSheetBody`, `ProviderRow`, `NavSheet`, `BilingualEngineStrip`). `reader-ai-readiness.md` (iOS #82) is **informational only** — its 4-gate readiness (feature flag + consent manager + provider + key) is iOS-specific and **implementation-deferred**; Android #118 has no feature flag and no consent manager, so the Android readiness gate is provider+key only (see §"AI-config reachability").

`.../vreader-ai-android.jsx` contains a SECOND, differently-shaped `BilingualSetupSheet` — see §3's setup-sheet resolution for why this plan reproduces the `vreader-bilingual.jsx` sheet and design-gates the divergence. Where a surface is NOT depicted it is scoped out and flagged.

**Status:** Gate-1 draft **v5** (2026-07-12) — Gate-2 round-4 (block-recommended) findings resolved (4 High + 2 gaps; targeted patch of v4). Round-4 CONFIRMED M1/M2/M3/M4 (EPUB single-owner flow, dual-cancellation + single-flight, blank-model fallback, DI sequencing) RESOLVED — those are UNCHANGED. Round-4 CONFIRMED the Lows (AppContainer has no `AiProviderStore`, `aiConfigured` semantics, upsert-first-activate, deps/WI-count) correct — those are KEPT. Awaiting Gate-2 round-5 audit.

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

- **Enabled-mode tests (WI-8 connected + WI-7a Compose, BINDING):** with bilingual ON —
  - (a) each source chunk's **selection registration is UNCHANGED** (same `registerChunk(i, …)` count and coordinates as OFF; a translation child registers nothing);
  - (b) **highlights/annotation washes/read-aloud wash still key off the source chunks** at the correct offsets (a translation child in the anchor's `Column` does not shift them);
  - (c) **lazy-index == chunk-index preserved:** with bilingual ON — **position-save round-trips to the same chunk** (`offsetForChunk(firstVisibleItemIndex)` → save → reopen → `chunkForOffset(offset)` lands on the same chunk); **bookmark/annotation/search/scrubber jumps land on the correct chunk** (`scrollToItem(chunkForOffset(target))` scrolls to the right item); **TTS auto-scroll targets the correct chunk** (`visibleItemsInfo.index == spokenChunk` matches); (assert these are identical to the OFF baseline — no lazy index shift);
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

- **Dual-cancellation across the service/VM boundary:** both the service AND the VM handle **BOTH** native `CancellationException` **AND** the typed `ChapterTranslationError.Cancelled` **before** generic error mapping — matching iOS `ChapterTranslationService.swift:359–364` (which catches `is CancellationError` and `ChapterTranslationError.cancelled` separately, both re-throwing `cancelled`). A cancelled stale request MUST NOT surface as `errorUnit` (it is discarded).
- **Per-unit single-flight job registry (VM):** a `prefetchTasks: MutableMap<TranslationUnitId, Job>` (iOS `prefetchTasks: [TranslationUnitID: Task]`, `BilingualReadingViewModel.swift:141`, cancelled/removed on disable/unit-change at :165). A NEW request for a unit **cancels-or-joins** the prior job (a stale prior is cancelled and awaited so it cannot run overlapping translations or Room writes), keyed by unit. Rapid retry/navigation cannot run overlapping translations for the same unit. `retryUnit(unit)` goes through the same registry. Tests: a mid-flight cancel discards (no `errorUnit`, no partial cache row); a rapid re-trigger for the same unit does not double-write.

### Modified files

- `data/VReaderDatabase.kt` — add `ChapterTranslationEntity` to `@Database entities`, bump `version` **8 → 9** (the live DB is v8, migrations `MIGRATION_1_2`..`MIGRATION_7_8`, `ALL_MIGRATIONS` ends at `MIGRATION_7_8` — verified VReaderDatabase.kt:29,224–228), add **`MIGRATION_8_9`** (exact DDL below — gap A), **append `MIGRATION_8_9` to `ALL_MIGRATIONS` after `MIGRATION_7_8`**, add `abstract fun chapterTranslationDao()`. Purely additive.

  **`MIGRATION_8_9` exact DDL (gap A — BINDING; modeled on the verified `MIGRATION_6_7` `search_index_state` shape at VReaderDatabase.kt:154–169, whose DDL Room's PRAGMA validation already accepts):**

  ```
  val MIGRATION_8_9: Migration = object : Migration(8, 9) {
      override fun migrate(db: SupportSQLiteDatabase) {
          db.execSQL(
              "CREATE TABLE IF NOT EXISTS `chapter_translations` (" +
                  "`lookupKey` TEXT NOT NULL, " +
                  "`bookKey` TEXT NOT NULL, " +
                  "`unitStorageKey` TEXT NOT NULL, " +
                  "`targetLanguage` TEXT NOT NULL, " +
                  "`promptVersion` TEXT NOT NULL, " +
                  "`translatedJson` TEXT NOT NULL, " +
                  "`sourceParagraphCount` INTEGER NOT NULL, " +
                  "`createdAt` INTEGER NOT NULL, " +
                  "PRIMARY KEY(`lookupKey`), " +
                  "FOREIGN KEY(`bookKey`) REFERENCES `books`(`fingerprintKey`) " +
                  "ON UPDATE NO ACTION ON DELETE CASCADE )"
          )
          db.execSQL(
              "CREATE INDEX IF NOT EXISTS `index_chapter_translations_bookKey` " +
                  "ON `chapter_translations` (`bookKey`)"
          )
      }
  }
  ```

  The `ChapterTranslationEntity` column types/order MUST match this DDL exactly (all columns `NOT NULL`; PK `lookupKey`; the `Index("bookKey")` produces `index_chapter_translations_bookKey`; the FK is `bookKey → books(fingerprintKey) ON DELETE CASCADE` — the same shape as every other child table, VReaderDatabase.kt:75–76/88–89/100–101/157–158/168–169). **The migration test MUST diff this DDL against Room's GENERATED `9.json` schema** (`exportSchema = true` at VReaderDatabase.kt:30 emits `schemas/…/9.json`), NOT a hand-written approximation — the exact-DDL guard opens the real Room DB after the v8→v9 migration and lets Room's structural PRAGMA validation catch any drift (the recurring Android migration failure mode, cf. #135's stale-version finding; the `MIGRATION_6_7` comment at VReaderDatabase.kt:148–150 documents this exact "DDL matches Room's generated schema, validated by the migration test opening the real Room DB" contract).

- `reader/TxtReaderActivity.kt` — own a `BilingualViewModel`; collect state; render translations **inside each chunk `i`'s lazy item as muted non-registered `Text` children of a wrapping `Column`, source chunk byte-unchanged, the `items(count = document.chunkCount, key = { it })` loop and its keys UNCHANGED so lazy-index==chunk-index is preserved (H2, TxtReaderActivity.kt:1043–1085)**; add the translation gesture-exclusion (H2); on position change call `vm.onPositionChanged(charOffsetUTF16)`. Strictly gated to `originalFormat ∈ {txt, md}`; disabled = each item's `Column` holds only the unchanged source `Text` (source-selection-parity preserved). **Owned by #129 (VERIFIED, merged) — a straight edit, rule 48 one-writer-per-file satisfied.**
- `reader/ReaderActivity.kt` (Readium EPUB) — WI-0-gated: attach `EpubBilingualController` to `navigator.evaluateJavascript`; re-apply on the identified production re-apply signal; clear on teardown BEFORE publication teardown. `navigator: EpubNavigatorFragment?` is the verified live field (ReaderActivity.kt:110).
- `reader/chrome/ReaderChromeScaffold.kt` — extend `readerMoreRows(...)` (currently supplies only `MoreActionId.DETAILS` + `SHARE`, ReaderChromeScaffold.kt:255–258) to ALSO supply the **`MoreRow.Toggle(id = MoreActionId.BILINGUAL, on = enabled, onToggle = …)`** row (or `MoreRow.Disabled` "Configure AI provider first" when not configured — `MoreRow.Disabled` exists for exactly this, MoreRow.kt:65–72). Threaded via new nullable params so #132/#134-only callers stay valid (the scaffold's established nullable-default pattern). This is the WI-9 entry-wiring edit.
- `reader/TxtSelectionController.kt` — **may gain a small additive seam for the translation gesture-exclusion** (H2) IF WI-8's chosen exclusion approach records translation-composable bounds at the selection root (e.g. an optional "excluded bounds" setter the body populates). If WI-8 instead consumes the long-press in the translation `Text`'s own `pointerInput`, this file is untouched. WI-8 picks one; the `hitAt` nearest-chunk fallback (`reader/TxtSelectionController.kt:47–53`) is the reason an exclusion is required at all.
- `VReaderApp.kt` / `AppContainer` — **provide `AiProviderStore` INTO `AppContainer` itself** (it is NOT provided today — verified, only a comment names it at VReaderApp.kt:64/66) using the #116 `KeystoreSecretCipher` + a DataStore under the same convention as `readerSettingsStore`, PLUS provide `ChapterTranslationStore`, `PerBookBilingualStore`, `ChapterTranslationService`, `ChapterTranslationPrefetcher`, an `AiSettingsViewModel` factory (for the Variant A sheet), and a `BilingualViewModel` factory. **Extracted into the shared DI WI (WI-4b).** No `feat:#136` dependency remains — #131 owns the `AiProviderStore`-into-`AppContainer` wiring.

**NOT modified:** `reader/chrome/ReaderBottomChrome.kt` gets **no** bilingual/Translate slot — the design's entry is the More-menu toggle (#134) + the top-chrome pill (#132), NOT a bottom-chrome slot. `ReaderBottomChrome`'s existing `extraSlot` is untouched.

### Files OUT of scope for v1

- **`Azw3ReaderActivity.kt` / `reader/foliate/`** — foliate WebView interlinear IS feasible but deferred (bundle-patch JS + secure-bridge additions touch the security-sensitive #126 surface). Once WI-0 proves the EPUB JS pipeline, the foliate host reuses `EpubBilingualJs` with a bundle adapter.
- **`PdfReaderActivity.kt`** — no reflowable text layer. Out (`pdfPageRange` Kind reserved only).
- **Backup collect/restore of `PerBookSettingsOverride` bilingual fields** — contract fields exist; wiring is a small additive follow-up (§7). Device-local until then. **The `bilingualGranularity` field's cross-platform conformance vector + iOS parity are UNCONFIRMED (gap B, §6/§7) — a follow-up when the backup-wiring WI lands.**
- **Style control** — descoped v1 (user decision, §3). Keep provider/model/**granularity (paragraph)**, DROP the bilingual "Style" control.
- **Sentence granularity (both the setup-sheet Sentence control AND the sentence-interlinear RENDER)** — not depicted (round-4 H3); design-gated together (§Design gates). v1 renders + caches + offers **paragraph only**; `sentenceRanges`/`TranslationGranularity.sentence` remain reserved-foundational code (WI-1, unit-tested) but are absent from the v1 render/cache/VM/setup-sheet path.
- **The iOS #82 readiness sheet (feature-flag + consent gates)** — `reader-ai-readiness.md` is iOS-specific and implementation-deferred; Android has no flag/consent, so the Variant A provider-list sheet is the whole AI-config surface. Out.
- **"Translate entire book…" batch, re-translate/style-swap picker, cost/token estimation, term-overrides** — iOS/`vreader-ai-android.jsx` extras not in the authoritative sheet. Out.
- **Streaming translation progress** — the design's "38%" is chapter-level N-of-M chunk progress, not token streaming. v1 shows N-of-M.

## 3. Prior art / project precedent / rejected alternatives

### The render-host decision (settled v2, CONFIRMED round-2)

**How iOS does interlinear:** iOS renders EPUB/AZW3 in a WKWebView it fully controls. `EPUBBilingualOrchestrator` injects JS that (1) enumerates leaf blocks posting `[{bid,text}]` to Swift, (2) after translation injects a translation node after each block. TXT/MD render in a text path where the renderer interleaves translation runs. The mechanism = **the app inserts translation nodes between source nodes** — which is exactly the Android in-item `Column` contract (H2) for TXT/MD and the DOM-inject contract for EPUB.

**Android EPUB feasibility (round-2 re-verified):** the transformed API JAR on the resolved Readium 3.3.0 AAR (build.gradle.kts:111) exposes public `evaluateJavascript`, `getCurrentLocator()`, `firstVisibleElementLocator(...)`, `submitPreferences(...)`; `ReaderActivity.navigator: EpubNavigatorFragment?` holds the concrete fragment (ReaderActivity.kt:110). EPUB interlinear via JS injection is feasible with the public API — **no Readium fork.** Not reopened.

**WI-0 — Readium bilingual spike (gates WI-7b; round-2 M1):** a throwaway harness that, against a real EPUB on the emulator, must PROVE each go/no-go criterion: (a) enumeration deterministic + idempotent with stable node IDs (repeat apply = no duplicate nodes); (b) clear wins over every older inject (a late inject checks the session token and no-ops); (c) recreation restores from cache for every case (href away/back, same-href `submitPreferences` reflow, internal page-fragment recreation, activity recreation) via `cachedDirect(expectedCount)` (zero provider calls) with an identified PRODUCTION re-apply signal per case; (d) locator/visible-source preservation across injection (stated permissible pagination delta); (e) enumerated block count vs segmenter count measured — divergence → the direct-block path (`prefetchDirect`/`cachedDirect`, H2) is the recovery, proven end-to-end. **Race contract:** single actor/mutex OR monotonic navigator-session token; token/mutex check after every suspended JS/AI call; clear before publication teardown. **No deterministic re-apply signal for a recreation case (c) = explicit NO-GO** → EPUB drops to a tracked follow-up, box D ships **TXT/MD-only** with the honest reason (a specific spike finding), never the false "requires a fork."

**Rejected alternatives:**
1. **Readium interlinear via decorations only** — REJECTED (decorations style existing text; they cannot insert translation paragraphs).
2. **Forking Readium** — REJECTED + unnecessary (public `evaluateJavascript` seam exists).
3. **AZW3 foliate host first** — REJECTED for v1 (deferred; touches the security-sensitive #126 bridge).
4. **Eager whole-book pre-translation** — REJECTED (cost/latency). Lazily prefetch current+next + cache.
5. **One `BilingualInterlinearBody` per chunk (v2)** — REJECTED (round-2 H1): a chunk is not a segment.
6. **A Compose body as the EPUB render surface (v2)** — REJECTED (round-2 M2): Compose cannot render inside Readium's WebView.
7. **Splitting a chunk's source `Text` into per-segment `Text` nodes to interleave translations (v3)** — REJECTED (round-3 H2): breaks the live one-`TextLayoutResult` + one-selection-registration-per-chunk model.
8. **SEPARATE additive `LazyColumn` items per translation, after the anchor chunk (v4)** — REJECTED (round-4 H2): separate lazy items shift every following lazy index, and the live reader treats lazy-item indices AS `TxtDocument` chunk indices (`offsetForChunk(firstVisibleItemIndex)` for position save/progress — TxtReaderActivity.kt:220/473/623; `scrollToItem(chunkForOffset(target))` for every bookmark/annotation/search/scrubber/TTS jump — :411/:421/:454/:481/:257; `visibleItemsInfo.index == spokenChunk` for TTS visibility — :256). Replaced by the **one-lazy-item-per-chunk `Column`** contract (source `Text` unchanged as the first child, translations as sibling children in the SAME lazy item — no lazy item added, no index shifted).
9. **Deriving `aiConfigured` from `profiles.isEmpty()` (the iOS Variant A note's derivation)** — REJECTED for Android: `activeId` can be null with profiles present, and key usability needs the active profile's token to decrypt (H3). Android uses `BilingualAiReadiness.resolve` = active-profile + decrypts-non-empty.
10. **Spinning AI-config reachability out as a separate feature #136** — REJECTED / CLOSED (2026-07-12): the design proved the ONLY designed Android AI-config reader surface is bilingual-coupled Variant A; there is no designed standalone entry, so it is not separable. #131 owns it.
11. **Reusing `AiProviderListScreen` VERBATIM for the Variant A scoped list (v4)** — REJECTED (round-4 H4): `AiProviderListScreen` owns its own `NavScreen`/chrome (AiProviderListScreen.kt:59), a generic empty state (:84/:87), and row-tap-as-EDIT (:105), so it cannot reproduce the designed `‹ Bilingual` nav + bilingual-context empty state + checked-active row + tap-to-SELECT. Replaced by (a) reuse the EDITOR verbatim + (b) a NEW `ReaderAiProvidersList` over the shared `AiSettingsViewModel` state + (c) a save-result seam returning the saved ID.

### The setup-sheet resolution (rule 51) + Style descope (round-2 H3, USER DECISION)

There are **two committed, differently-shaped** `BilingualSetupSheet`s:
- `vreader-bilingual.jsx` → **language grid + Granularity + preview strip + Translation-engine strip (Set up/Change) + Cancel/Translate**. No Style, no provider/model card, no term-overrides, no cost.
- `vreader-ai-android.jsx` → **Languages (From/To) + Provider card + Style (Literal/Natural/Literary) + Keep-term-overrides toggle + cost footer**. No language grid, no Granularity, no preview.

**Resolution:** this plan reproduces the **`vreader-bilingual.jsx` sheet EXACTLY**, with the round-4 H3 granularity divergence (Paragraph-only in v1). **Style is DESCOPED for v1** (user decision): keep provider/model/**granularity (paragraph)**, DROP the bilingual "Style" control. Consequently store/VM carry no `style`, the chunk contract has no `style` param, and the cache key's `promptVersion` has no `s=` component.

**Box-D parity note (do NOT claim full box-D parity):** the box-D checklist lists provider/model/**style**. Because Style is descoped, **WI-9 flips box D to done ONLY for provider/model/granularity(paragraph) + a descope note**; a follow-up tracker/checklist amendment records the Style descope AND the Sentence-granularity descope. If Style is later wanted, that needs an updated committed design (a single sheet showing BOTH Style AND Granularity is not depicted anywhere — the one Style design gate below).

### The AI-config path (rule 51) — Variant A is the committed design

The canonical decision (`reader-ai-provider-entry.md`, Variant A) + its component canvas (`vreader-ai-provider-entry.jsx`) ARE the committed design; #131 reproduces only what they depict (a `‹ Bilingual`-titled push sheet hosting the provider list + the canonical editor, pop-back-on-first-save, checked-active row, tap-to-select). The scoped list is a NEW reader-specific presentation over the shared #118 VM state (round-4 H4) — it does not reuse `AiProviderListScreen`'s chrome/empty-state/row-tap-edit — but it invents no new AI-config sheet or nav beyond what the Variant A canvas depicts. The editor (`AiProviderEditSheet`) IS reused verbatim. The iOS #82 readiness additions (flag/consent) are explicitly **out** on Android (no such subsystems exist). This is a designed surface — it is NOT a design gate.

### Other precedents applied

- **#118 provider seam**: reuse `AiProviderStore.snapshot()` (`snapshot.active`) + `store.apiKey(profile)` + `AiProviderFactory.create` (default of an injected factory param) + `AiClient.chat`. #118's AI files are unchanged EXCEPT the additive save-result seam on `AiSettingsViewModel.save()` (round-4 H4c — returns the saved ID, which `AiProviderStore.upsert` already produces, AiProviderStore.kt:58/84); #131 wires `AiProviderStore` into `AppContainer` and reuses `AiProviderEditSheet`/`AiSettingsViewModel` for the Variant A sheet (the scoped list is new — H4b).
- **Room additive-migration pattern** (#122/#123/#127/#128/#135): version bump + `MIGRATION_n_(n+1)` appended to `ALL_MIGRATIONS` + exact-DDL + `VReaderDatabaseMigrationTest` PRAGMA guard against Room's generated schema (gap A). `@PrimaryKey` + `@Upsert` is the project DAO pattern (`BookDao`). Baseline v8.
- **DataStore JSON-in-Preferences** for `PerBookBilingualStore` (the `ReaderSettingsStore`/`AiProviderStore` pattern).
- **Pure-logic port**: iOS `ChapterSegmenter`/`ChapterTranslationChunker`/`TranslationChunkContract`/`ChapterTranslationService.translatePreSegmented`/`ChapterTranslationPrefetcher.translatedSegmentsDirect`+`cachedSegmentsDirect` are pure/heavily-unit-tested — direct Kotlin ports with the same test vectors (all verified to exist).
- **Single-flight job registry**: iOS `prefetchTasks: [TranslationUnitID: Task]` (`BilingualReadingViewModel.swift:141`) — ported as `prefetchTasks: Map<TranslationUnitId, Job>` (M2).
- **Entry point via #132/#134 (VERIFIED)**: the More-menu bilingual toggle (`MoreActionId.BILINGUAL` reserved; `MoreRow.Toggle`/`MoreRow.Disabled`) + top-chrome pill are landed; #131 mounts the pill + wires the toggle (§4).

## 4. Work-item sequencing

**13 WIs/PRs (round-3 Low-1 fix — corrected count; UNCHANGED in v5):** the list is exactly **WI-0, WI-1, WI-2, WI-3, WI-4a, WI-4b, WI-5, WI-6, WI-7a, WI-7b, WI-AIP, WI-8, WI-9** = **13 WIs**. `Utf16Span` (round-4 H1) is a NEW file but **rides WI-1** (the foundational value-types + pure-segmentation WI) — it does not add a WI. Each WI = one PR. Build order: **foundation/cache → service/direct-block APIs → shared DI/factory (incl. `AiProviderStore` in `AppContainer`) → VM state/prefetch → host-specific renderers (TXT/MD + EPUB) + the Variant A AI Providers sheet → entry wiring.**

**Dependencies (round-3 Medium-4 — dependency honesty; #136 folded in; round-4 CONFIRMED correct):**

- **`Deps: [feat:#132, feat:#134]`.** **#132 (top chrome) and #134 (More menu) are VERIFIED.** **#129 (TXT/MD reader) is VERIFIED** — `TxtReaderActivity` is a straight edit, not a blocker. **There is NO external AI-reachability blocker** — the former #136 is CLOSED (GH #1976, not-planned) and its scope is #131-owned.
- **WI-4b is foundational and gates the behavioral chain.** WI-4b provides `AiProviderStore` into `AppContainer` PLUS the bilingual services + factories. Per the audit's Medium-4, WI-4b transitively gates WI-6 (needs the prefetcher/DI), WI-7b (needs DI), WI-AIP (needs `AiProviderStore` + `AiSettingsViewModel` from `AppContainer`), and WI-8 (needs DI). **Chosen resolution: injected seams so the behavioral work proceeds against fakes before WI-4b lands, AND WI-4b is sequenced early.** Concretely: the VM (WI-5/WI-6) takes an injected `ChapterTranslationPrefetcher` (fake in tests) and an injected `AiProviderSnapshot` provider (fake); the TXT/MD host Compose/unit work (WI-8) and the Variant A sheet (WI-AIP) take injected VM/store/`AiSettingsViewModel` seams — so unit/Compose tests do not wait on `AppContainer`. **WI-4b is built right after WI-4a (before WI-6/WI-7b/WI-AIP/WI-8) so the production wiring lands before the host integrations that mount it.** This is stated honestly: the *production run-through* of WI-6/WI-7b/WI-AIP/WI-8 depends on WI-4b; their *unit/Compose gates* depend only on the injected seams. No external feature gates any of this.

**WI-0 (spike): Readium EPUB bilingual injection — go/no-go + race contract (M1).** Harness + criteria (a)–(e) and the race contract in §3. Output: a go/no-go on EPUB-in-v1 (no-go = box D ships TXT/MD-only, tracked) + the concrete `EpubChapterTextProvider` / `EpubBilingualJs` / `EpubBilingualController` surfaces + the EPUB direct-block ownership sequence (Medium-1). Deps: none (uses the existing #106 Readium host). Not TDD-gated (throwaway spike); feeds WI-7b.

**WI-1 (foundational): value types + pure segmentation/chunk/contract.** **`Utf16Span` (round-4 H1 — the half-open span value type replacing `IntRange`)**, `TranslationUnitId`, `TranslationGranularity` (reserved; v1 uses `paragraph` only — round-4 H3), `BilingualLanguages`, **`ChapterSegmenter` (with `paragraphRanges`/`sentenceRanges` returning `List<Utf16Span>` — H1; `sentenceRanges` is reserved-foundational, not in the v1 render path — H3)**, `TranslationChunker`, `TranslationChunkContract` (no `style`), `ChapterTranslationError`. Pure; ported iOS vectors. Deps: none. Tests: `paragraphRanges`/`sentenceRanges` return correct half-open `Utf16Span(start, endExclusive)` spans (both APIs unit-tested even though only `paragraphRanges` ships in the v1 render path — `sentenceRanges` stays covered as reserved-foundational code); chunker packs-to-budget/oversize/empty; contract prompt/decode/fence/mismatch; error mapping.

**WI-2 (foundational): Room translation cache.** `ChapterTranslationEntity` (PK = `lookupKey`, all-`NOT NULL` columns matching the DDL, `sourceParagraphCount` column) + `Dao` (`@Upsert`) + `ChapterTranslationStore`; `VReaderDatabase` **8→9 `MIGRATION_8_9`** with the **exact DDL authored in §2 (gap A)**, appended after `MIGRATION_7_8`. Robolectric migration round-trip from v8 + full-chain + upsert/get/delete-by-lookupKey + FK-CASCADE + **exact-DDL guard validated against Room's GENERATED `9.json` schema (not a hand-written approximation — gap A)**. Deps: none.

**WI-3 (foundational): `ChapterTranslationService`** against a fake `AiClient`. Both `cachedTranslation` overloads (incl. the `expectedSegmentCount` divergence restore — H2) + `translate` + `translatePreSegmented`. **Dual-cancellation (native + typed `Cancelled`) BEFORE generic mapping (M2).** Deps: WI-1, WI-2. Tests: cache hit → zero client calls; miss → translate + write; decode fail → per-segment fallback; one-chunk fail → source-only that chunk (others translated, NOT cached); all-chunks fail → throw; native-cancel → `Cancelled` (no write); typed-`Cancelled`-from-chunk → `Cancelled` (no write); ensureActive-before-write; `AiError` mapping incl. `Config`/`InsecureUrl` → `ProviderFailed`; `translatePreSegmented` full-success caches under the enumerate count; partial degrade NOT cached; all-fail throws; `cachedTranslation(expectedSegmentCount)` returns on stored-count match, null on mismatch, needs no provider.

**WI-4a (foundational): `ChapterTextProvider` (TXT/MD) + `ChapterTranslationPrefetcher` + `BilingualAiReadiness`.** `TxtChapterTextProvider` builds the document-global segment `Utf16Span`s once (via `paragraphRanges` — paragraph only, H1/H3), groups into windows, resolves `unitContaining(charOffsetUTF16)` via segment-start binary search, `sourceSegments(unit)`. Prefetcher: `prefetch` + `prefetchDirect` + `cachedDirect`; resolves active profile from `snapshot()`, decrypts snapshot-consistent, builds client via the injected factory param (default `AiProviderFactory::create`), constructs `AiRequest` with **`model = profile.model.ifBlank { profile.kind.defaultModel }` (M3)**. Readiness = active profile with non-empty decrypted key; **cipher failure → not-ready, never a crash.** Fake store + fake factory. Deps: WI-1, WI-3. Tests (all `Utf16Span`-based): unit resolution + clamp + empty; **one-chunk document (no trailing newline) → its segment translation renders, not dropped (H1)**; **final-chunk anchor → renders (H1)**; **exact-boundary → correct anchor (H1)**; **EOF anchor (`span.endExclusive == text.length`) → last chunk, no clamp-collapse (H1)**; paragraph spanning MANY chunks → one segment/one unit, anchored to the last chunk (Low-2); a >4000-char paragraph hard-split across chunks → one segment; CR/LF/CRLF; MD markers; locator→unit mapping; `unitAfter` end→null; **source-byte parity while disabled**; cache-hit-no-profile still returns (#306); no-profile miss → `ProviderFailed`; `prefetchDirect` 1:1; `cachedDirect` restores with zero provider calls; **blank `profile.model` → `AiRequest.model == kind.defaultModel` (M3 regression)**; readiness true/false; empty-key → false; no-active-with-profiles-present → false (H3); cipher-throw → readiness false (no crash). (Sentence-multi-in-one-chunk is NOT a v1 render test — the v1 provider uses `paragraphRanges` only; `sentenceRanges` behavior is covered in WI-1's reserved-foundational unit tests.)

**WI-4b (foundational — shared DI/factory, incl. `AiProviderStore` in `AppContainer`): AppContainer bilingual + AI-config graph.** `AppContainer` **now constructs `AiProviderStore`** (DataStore + #116 `KeystoreSecretCipher`, following the `readerSettingsStore` convention — this is #131's change, not an external feature's) and provides `ChapterTranslationStore`, `PerBookBilingualStore`, `ChapterTranslationService`, `ChapterTranslationPrefetcher`, an `AiSettingsViewModel` factory (for WI-AIP), and the `BilingualViewModel` factory. Deps: **WI-4a** (no external dep — #136 closed). Tests: container resolves the bilingual + AI-config graph; `AiProviderStore` resolves and round-trips a profile; the prefetcher's injected factory defaults to `AiProviderFactory::create`.

**WI-5 (behavioral): `PerBookBilingualStore` + `BilingualViewModel` state core.** Store per book (enabled/targetLanguage/granularity — granularity pinned `paragraph` in v1, no style); VM setters (persist + first-enable `needsSetupSheet`); `aiConfigured` from `BilingualAiReadiness.resolve` over an injected snapshot; language change clears cache-shaped state + bumps generation. Injected prefetcher/snapshot seams (Medium-4). Turbine tests: first-enable raises sheet; re-enable persisted does not; disable clears; language change resets; `aiConfigured` true/false from readiness; round-trip through store; no style field; granularity persists as `paragraph`. Deps: WI-1 (+ store).

**WI-6 (behavioral): VM prefetch trigger + generation/cancellation + single-flight (M2).** `onPositionChanged(charOffsetUTF16)` derives current unit (TXT/MD only), dedupes, prefetches current+next; a monotonic position-request sequence checked after every suspension; **per-unit single-flight `prefetchTasks: Map<TranslationUnitId, Job>` (a new request cancels/joins the prior — M2)**; a captured language/provider snapshot per launch; generation bumps on disable/language/unit-change discard stale; **BOTH `CancellationException` AND typed `ChapterTranslationError.Cancelled` handled BEFORE generic error mapping (M2)**; a cancelled stale request does NOT surface as `errorUnit`; `Offline`→`unavailableUnits`; transient failure leaves unit unfetched + clears anchor to retry; `retryUnit` routes through the registry. The EPUB `onEpubBlocksEnumerated` entry is present but EPUB prefetch is owned by the controller (Medium-1); the VM's position-driven `prefetch` dispatches TXT/MD units only. Fake prefetcher (Medium-4 seam). Deps: WI-4a, WI-4b, WI-5. Tests: current+next on unit change; same-unit no-op; cancel-mid discards stale (no `errorUnit`); typed-`Cancelled` discards (not `errorUnit`); rapid re-trigger same unit → single-flight, no double-write; offline→unavailable; failure→retry-able; `retryUnit` re-fetches.

**WI-7a (behavioral): Compose UI — setup sheet + interlinear body (TXT/MD) + pill.** Reproduce `vreader-bilingual.jsx` (setup sheet: language grid / **Paragraph-only Granularity control (round-4 H3)** / preview / engine strip configured+unconfigured; body: the translation rendered **inside the anchor chunk's `Column` as a muted non-registered `Text` child** per the round-4 H2 render contract — translated / loading N%+dimmed / error+Retry / offline source-only; pill). Consumes the host-neutral `BilingualRenderState` DTO. Light+dark. Compose UI tests each state, incl. **paragraph interlinear renders a translation child after a paragraph's last source chunk (depicted)**; **the setup-sheet Granularity control shows Paragraph only, no Sentence option (H3)**. Deps: WI-5 (state shape). NO Style control; the unconfigured "Set up" CTA renders and (in WI-9) routes to the Variant A sheet.

**WI-7b (behavioral, CONDITIONAL — only if WI-0 = go): EPUB render adapter (DOM injection, NOT Compose — M2) + direct-block ownership (M1).** `EpubBilingualJs` (enum/inject/clear JS builders, CSP-safe escaping) + `EpubBilingualController` (the serialization actor / session token AND the **single-owner enumerate→cachedDirect/prefetchDirect→guarded-commit sequence — Medium-1**) + `EpubChapterTextProvider`, wired into `ReaderActivity`, driving DOM from the shared `BilingualRenderState` DTO. Uses `prefetchDirect`/`cachedDirect` for the count-divergence path (H2). Depends on WI-6 (VM state) and WI-4b (DI); the WI-7a UI dependency is only the shared `BilingualRenderState`/value types. Connected test on a real EPUB (seeded cache): enable → injects; disable → cleared; reflow/href-change/fragment-recreation/activity-recreation → re-applies from cache (zero provider calls) via `cachedDirect`; count-divergence handled (direct path); **the regular TXT/MD prefetch path is never invoked for an EPUB unit (Medium-1)**. Unit tests: JS escaping/CSP-safe insertion, RTL/CJK style, empty translations, loading cleanup, idempotent replacement, source-only fallback, stale-session-token commit discarded (no `errorUnit`). Deps: WI-0, WI-3, WI-4a, WI-4b, WI-6, (shared types from WI-7a). (If WI-0 = no-go, dropped; box D ships TXT/MD-only, tracked.)

**WI-AIP (behavioral — the folded-in Variant A AI Providers sheet; round-4 H4 rewritten): `ReaderAiProvidersSheet`.** The scoped in-reader "AI Providers" push sheet (nav bar `‹ Bilingual` + "AI Providers" title) reproducing `vreader-ai-provider-entry.jsx` `AIProvidersSheet`/`AIProvidersSheetBody`/`NavSheet`. Per round-4 H4:
  - **(a)** present `AiProviderEditSheet` VERBATIM from #118 (Kind/Name/Endpoint/Sampling/API Key/Test Connection unchanged).
  - **(b)** a NEW `ReaderAiProvidersList` presentation over the SHARED `AiSettingsViewModel.listState` (verified `AiSettingsViewModel.kt:26`; each `AiProviderRow` already carries `active`, :30) + shared row/cell components — reproducing the reader-scoped `‹ Bilingual` nav (`NavSheet`, jsx:247, NOT `AiProviderListScreen`'s `NavScreen`), the bilingual-context empty state ("Choose the provider bilingual mode will use to translate this book." + "No providers yet" + "Add provider" — jsx:180–209), the **checked-active row** (`selected = row.active` — jsx:221), and **tap-to-SELECT** (`onSelect(id) → vm.setActive(id)` — jsx:221/237). It does NOT reuse `AiProviderListScreen`'s NavScreen/chrome/`AiEmptyState`/`ProviderRow`-tap-edit.
  - **(c)** the **save-result seam**: `AiSettingsViewModel.save()` (or a thin WI-AIP wrapper) is extended to return the saved provider ID (from `store.upsert(...).id`, which the store already returns — `AiProviderStore.kt:58/84`), so on first Save → `store.setActive(savedId)` → pop the whole stack back to the bilingual sheet (engine strip now "configured / Change…"), **deterministically, after the upsert commits (no race)**.
  `‹ Bilingual` without adding → unconfigured, no state mutated. "Change…" → populated list, current provider checked, tap row → `setActive`. No consent/flag surface (Android has none). Deps: WI-4b (for `AiProviderStore` + `AiSettingsViewModel` in `AppContainer`), WI-7a (bilingual sheet host). Tests (Compose + connected): the scoped list renders **`‹ Bilingual` back label** + **bilingual-context empty copy** + **checked active row** + **tap-selects (`setActive`)**; empty → Add → Save → **save→result-id→`setActive`→pop deterministic (no race)** → bilingual strip configured; `‹ Bilingual` without adding → strip unconfigured, snapshot unchanged; "Change…" → populated, current checked; editor reused verbatim (no divergent form).

**WI-8 (behavioral): `TxtReaderActivity` integration.** Wire VM into the `items(count = document.chunkCount, key = { it })` loop as **muted non-registered translation `Text` children inside each anchor chunk's wrapping `Column`, source chunk byte-unchanged, the loop + keys UNCHANGED so lazy-index==chunk-index is preserved (round-4 H2)** + the translation **gesture-exclusion** (round-4 H2) + position-change (`charOffsetUTF16`) + setup-sheet. `originalFormat`-gated (TXT/MD). Uses WI-4b's DI. **#129 VERIFIED — straight edit.** Connected test (fake `AiClient` seam): enable → setup → confirm → interlinear from seeded cache; **enabled-mode source-chunk selection registrations UNCHANGED vs disabled (H2)**; **highlights/annotation-washes/read-aloud-wash still key off source chunks (H2)**; **with bilingual ON — position-save round-trips to the same chunk; bookmark/search/scrubber/TTS jumps land on the correct chunk (lazy-index==chunk-index preserved — round-4 H2)**; **a long-press on translation text does NOT select (gesture exclusion — round-4 H2)**; a translation child is non-selectable, does not perturb source offsets (H2); disable → source-selection byte-parity; reopen persists enabled + renders from cache with zero client calls; **paragraph-spanning-many-chunks renders exactly one translation inside its last chunk's `Column` (H1/Low-2)**; **one-chunk/final-chunk anchors render (H1)**; MD source mapping. Deps: WI-6, WI-7a, WI-4b.

**WI-9 (behavioral): entry wiring + acceptance.** Mount `BilingualPill` in #132's VERIFIED top chrome; extend `readerMoreRows(...)` to supply the #134 VERIFIED More-menu `MoreActionId.BILINGUAL` toggle (`MoreRow.Toggle` `on`/`onToggle`, or `MoreRow.Disabled` "Configure AI provider first" when not configured) wired to the VM; **wire the setup sheet's "Set up"/"Change…" affordance → the #131-owned `ReaderAiProvidersSheet` (Variant A)**. Full acceptance across EPUB (if WI-7b landed) + TXT/MD, including the fresh-user path `unconfigured → Set up (→ Variant A AI Providers sheet) → add provider → Save → return → enable → translate` (now #131-owned end-to-end). **Flip box D to done ONLY for provider/model/granularity(paragraph) + the Style-descope AND Sentence-descope notes; file the follow-up checklist amendment; do NOT claim full box-D parity.** The DONE flip **no longer waits on #136** (closed). Update `docs/architecture.md` (bilingual pipeline + the new `chapter_translations` schema + `AiProviderStore` + bilingual services in `AppContainer` + the Variant A AI Providers sheet). → DONE. Deps: WI-8, WI-AIP, WI-7b (if go), feat:#132, feat:#134.

## 5. Test catalogue

JVM/Robolectric (`android/app/src/test/...bilingual/`): `Utf16SpanTest` (**half-open invariants: `endExclusive >= start`, `isEmpty`, `length`; round-4 H1**); `ChapterSegmenterTest` (paragraph blank-line; sentence CJK `。！？` vs Latin; empty→[]; single; **`paragraphRanges`/`sentenceRanges` return correct half-open `Utf16Span(start, endExclusive)` spans — both APIs covered even though only `paragraphRanges` ships in the v1 render path**); `TranslationChunkerTest` (packs to budget; oversize→own chunk+subSplit; empty→[]); `TranslationChunkContractTest` (prompt shape; strict JSON decode; code-fence strip; count mismatch→`CountMismatch`; non-array→`NotAStringArray`); `ChapterTranslationServiceTest` (cache hit 0 calls; miss→translate→write; decode-fail per-segment fallback; one-chunk-fail partial-not-cached; all-fail→throw; **native-cancel→Cancelled no write; typed-`Cancelled`→Cancelled no write (M2)**; ensureActive-before-write; offline/timeout/429/http/config/insecure→error mapping; very long chapter N-of-M; stale-cache count-mismatch re-translates; `translatePreSegmented` caches under enumerate count on full success; partial degrade not cached; all-fail throws; `cachedTranslation(expectedSegmentCount)` hit/miss with no provider); `ChapterTranslationErrorMappingTest`; `TxtChapterTextProviderTest` (**one-chunk document → renders (H1); final-chunk anchor → renders (H1); exact-boundary → correct anchor (H1); EOF anchor → last chunk, no clamp-collapse (H1)**; paragraph spanning MANY chunks → one segment/unit anchored to last chunk (Low-2); >4000-char paragraph → one segment across hard-split chunks; CR/LF/CRLF; MD markers; locator→unit mapping; `unitAfter` end→null; source-byte parity while disabled; **provider uses `paragraphRanges` only — H3**); `ChapterTranslationPrefetcherTest` (snapshot-consistent profile+key; injected-factory used; `AiRequest` built from profile; **blank `profile.model` → `kind.defaultModel` (M3 regression)**; cache-hit-no-profile #306; no-profile miss→ProviderFailed; `prefetchDirect` 1:1; `cachedDirect` restores with zero provider calls; CJK↔English + Latin round-trip via fake; cipher-throw→ProviderFailed not crash); `BilingualAiReadinessTest` (active+key→true; **no-active-with-profiles-present→false (H3); activeId-null→false (H3)**; empty key→false; cipher-throw→false, no crash); `PerBookBilingualStoreTest` (enabled/lang/granularity round-trip; granularity pinned paragraph; no style field); `BilingualViewModelTest` (Turbine: first-enable sheet; re-enable no-sheet; disable clears; language reset; `aiConfigured` from readiness; prefetch current+next; same-unit no-op; **cancel-mid discards (no errorUnit); typed-Cancelled discards (M2); rapid re-trigger same unit single-flight, no double-write (M2)**; offline→unavailable; error→errorUnit+retry; `retryUnit`); `AiSettingsViewModelSaveResultTest` (**`save()` returns the saved provider ID after the upsert commits — round-4 H4c seam; the returned ID matches `store.upsert(...).id`**); `EpubBilingualJsTest` (JS escaping / CSP-safe insertion; RTL/CJK style; empty translations; clear idempotent; inject idempotent replacement; source-only fallback — WI-7b if go); `EpubBilingualControllerTest` (**enumerate→cachedDirect/prefetchDirect→guarded commit; stale-session-token commit discarded, no errorUnit; single-owner (regular TXT/MD prefetch never runs for EPUB unit) — Medium-1** — WI-7b if go).

Room migration: `VReaderDatabaseMigrationTest` (extend) **v8→v9 + full-chain from v8** + FK-CASCADE + `lookupKey`-as-PK + **exact-DDL validated against Room's generated `9.json` schema, not a hand-written approximation (gap A)**; `ChapterTranslationDaoTest` (upsert-by-PK replaces; get/delete-by-lookupKey).

Compose UI (`androidTest/...bilingual/`): `BilingualSetupSheetUiTest` (language grid, **Granularity control shows Paragraph only — no Sentence option (H3)**, preview, engine configured vs unconfigured driven by `aiConfigured`; no Style control present; light+dark); `BilingualInterlinearBodyUiTest` (**translation rendered as a muted `Text` child inside the anchor chunk's `Column` (round-4 H2 render contract); paragraph interlinear translated incl. CJK font + RTL Arabic**; loading N%+dimmed; error+Retry; offline source-only; empty translation→source-only no crash); `ReaderAiProvidersSheetUiTest` (**the scoped list renders `‹ Bilingual` back label + bilingual-context empty copy + checked active row + tap-selects (`setActive`) — round-4 H4b; editor (`AiProviderEditSheet`) reused verbatim (H4a)**); `BilingualPillUiTest`.

Connected (`androidTest/...reader/`): `TxtReaderBilingualConnectedTest` (API 35, fake `AiClient` via injected factory): enable→setup→confirm→interlinear from seeded Room cache; **enabled-mode source-chunk selection registrations UNCHANGED vs disabled (H2); highlights/annotation-washes/read-aloud-wash still key off source chunks (H2)**; **with bilingual ON — position-save round-trips to the same chunk; bookmark/search/scrubber/TTS jumps land on the correct chunk (lazy-index==chunk-index preserved — round-4 H2)**; **long-press on translation text does NOT select (gesture exclusion — round-4 H2)**; translation child non-selectable + no source-offset perturbation (H2); disable→source-selection byte-parity; reopen persists enabled + renders from cache with zero client calls; **paragraph-spanning-many-chunks renders one translation (H1/Low-2); one-chunk/final-chunk anchors render (H1)**; TXT/MD gated (PDF inert); very long chapter scroll responsive; cancellation leaves no partial cache row. `ReaderAiProvidersConnectedTest` (WI-AIP + WI-9): `unconfigured → Set up → Variant A sheet → add provider → Save → save-result-id → setActive → pop-to-bilingual configured (deterministic, no race — round-4 H4c) → enable → translate`; `‹ Bilingual` without adding → unconfigured, snapshot unchanged; "Change…" → populated, current checked, tap → setActive. `EpubReaderBilingualConnectedTest` (only if WI-0=go): enable→inject on a real EPUB; disable→clear; href-change/fragment-recreation/activity-recreation→re-apply from cache (zero provider calls); count-divergence handled via `prefetchDirect`/`cachedDirect`; regular prefetch never runs for EPUB unit (Medium-1).

Edge cases: empty translation, failed, partial per-chunk, CJK↔English + Latin + RTL, provider error/timeout/429/config/insecure, native + typed cancellation mid-translation + before-write, single-flight overlap, very long chapters, offline (cache-first + silent source-only), cipher-decrypt failure → not-ready (no crash), enumerate↔segment count divergence (direct path), one-chunk/final-chunk/EOF anchors (H1), blank model (M3), lazy-index==chunk-index parity with bilingual on (round-4 H2), translation-text long-press excluded (round-4 H2), save-result-id determinism (round-4 H4).

## 6. Risks + mitigations

- **Live-translation verification is AI-credential-gated (the box-D caveat).** The whole pipeline is verified without live creds via a deterministic **fake `AiClient`** injected through the prefetcher's `clientFactory` param (default `AiProviderFactory::create`; tests override). WI-3/4a/8 prove segment→chunk→decode→cache→interleave end-to-end incl. every error/edge path. Connected tests seed the Room cache and assert render-from-cache with zero client calls. An optional live smoke confirms wire format but is NOT a gate. The fresh-user `unconfigured → Set up → add provider` reachability leg is now #131-owned (WI-AIP + WI-9) and verified by `ReaderAiProvidersConnectedTest`.
- **Final-chunk translation drop + span type (round-3 H1 + round-4 H1).** Fixed by `endExclusive = if (i+1<chunkCount) offsetForChunk(i+1) else text.length` + the dedicated **`Utf16Span(start, endExclusive)`** half-open value type replacing the incompatible `IntRange` everywhere in the segment/render contracts; one-chunk/final-chunk/exact-boundary/EOF tests. `offsetForChunk`'s clamp (TxtDocument.kt:17) is never relied on for the final end.
- **Enabled render breaking the per-chunk layout/selection model AND the lazy-index↔chunk-index identity (round-3 H2 + round-4 H2).** Fixed by the **one-lazy-item-per-chunk `Column`** render contract: the `items(count = chunkCount, key = { it })` loop + keys are UNCHANGED (lazy-index==chunk-index preserved, so position-save/progress/every jump/TTS visibility — TxtReaderActivity.kt:220/252/256/411/421/454/481/623 — stay correct); inside each item a `Column` holds the UNCHANGED source `Text` (one `TextLayoutResult`, one `registerChunk(i)`) then the muted non-registered translation child(ren); an explicit **gesture-exclusion** stops a long-press on translation text from routing to `hitAt`'s nearest-source-chunk fallback (TxtSelectionController.kt:47–53). Enabled-mode tests assert selection/highlight/wash/annotation parity AND lazy-index==chunk-index parity with disabled, plus translation-not-selectable.
- **TXT/MD segment↔render pairing (round-2 H1).** Both sides read the SAME segment `Utf16Span` array over `TxtDocument.text`, so 1:1 holds by construction — no chapter model invented; a paragraph split across many chunks is translated + rendered once (inside its last chunk's `Column`). Granularity is paragraph-only in v1; the `g=` cache slot is retained for a future granularity.
- **Undesigned sentence render (round-4 H3).** v1 segments + caches + renders + offers **paragraph only** — the only depicted interlinear pattern. `TranslationGranularity.sentence` + `ChapterSegmenter.sentenceRanges` stay as reserved-foundational code (WI-1, unit-tested) but never appear in the v1 render/cache/VM/setup-sheet path. The Sentence control AND its render are design-gated together (§Design gates).
- **Variant A fold-in not wireable verbatim (round-4 H4).** The EDITOR (`AiProviderEditSheet`) is reused verbatim (a); the scoped LIST is a NEW `ReaderAiProvidersList` over the shared `AiSettingsViewModel` state reproducing the designed `‹ Bilingual` nav + bilingual empty state + checked-active row + tap-to-select (b); a save-result seam returns the saved ID (which `AiProviderStore.upsert` already produces, AiProviderStore.kt:58/84) so `setActive(savedId)` + pop-on-success is deterministic and race-free (c). No "reuse `AiProviderListScreen` verbatim" claim remains anywhere.
- **EPUB direct-block flow (round-3 Medium-1 — CONFIRMED RESOLVED).** The `EpubBilingualController` is the single owner: `enumeratedBlocks → cachedDirect (zero-provider restore) else prefetchDirect → session-token-guarded commit into BilingualRenderState/translationsByUnit`. The VM's position-driven regular prefetch is TXT/MD-only, so the two paths never write the same canonical cache row. Every suspended step is token-guarded; a stale token discards silently.
- **EPUB count divergence (round-2 H2).** The direct-block path (`prefetchDirect` → `translatePreSegmented`, cached by enumerate count, restored by `cachedDirect(expectedCount)` with zero provider calls) — iOS Bugs #268/#330/#343 parity.
- **EPUB JS-injection race (round-2 M1).** WI-0's contract (single actor/mutex OR monotonic navigator-session token; token check after every suspended call; clear before publication teardown; identified production re-apply signal per recreation case). No deterministic re-apply signal = explicit NO-GO → TXT/MD-only ship.
- **Cancellation + single-flight (round-3 Medium-2 — CONFIRMED RESOLVED).** Both service and VM handle native `CancellationException` AND typed `ChapterTranslationError.Cancelled` before generic mapping (iOS `ChapterTranslationService.swift:359–364`); a per-unit `prefetchTasks: Map<TranslationUnitId, Job>` cancels/joins a prior request so rapid retry/navigation can't run overlapping translations or Room writes; a cancelled stale request never surfaces as `errorUnit`. `ensureActive()` before the Room write.
- **Blank model (round-3 Medium-3 — CONFIRMED RESOLVED).** The prefetcher builds `model = profile.model.ifBlank { profile.kind.defaultModel }` (matches `AiChatViewModel.kt:61`; both wire clients serialize `request.model` directly, `OpenAiCompatibleProvider.kt:38`/`AnthropicProvider.kt:36`). Blank-model regression test.
- **AI-config readiness (H3 — CONFIRMED correct).** `BilingualAiReadiness.resolve` = active profile + decrypts-non-empty; `activeId` can be null with profiles present; cipher failure → not-ready (no crash). No consent/flag gate (Android has none).
- **Migration schema drift (gap A).** `MIGRATION_8_9`'s exact DDL is authored in §2 and validated against Room's GENERATED `9.json` schema (not a hand-written approximation) by the extended `VReaderDatabaseMigrationTest` opening the real Room DB — the recurring Android migration failure mode (cf. #135's stale-version finding).
- **Backup `bilingualGranularity` cross-platform parity UNCONFIRMED (gap B).** The backup-contract `bilingualGranularity` field's cross-platform conformance vector + iOS parity are UNCONFIRMED. Safe for v1 (backup collect/restore is descoped / device-local — §7), but flagged as a follow-up: **when the backup-wiring WI lands, add a conformance vector under `contracts/vectors/` and confirm iOS parity before shipping backup of the field.**
- **Cost/latency of translating on scroll.** Lazy current+next prefetch + disk cache; N-of-M progress; cancellation on navigate-away/generation-bump/single-flight supersede.
- **Provider JSON non-compliance.** `TranslationChunkContract.decode` + per-segment fallback — never drops a paragraph.
- **DataStore per-book key growth.** One Preferences entry per book keyed by fingerprint; scales like `ReaderSettingsStore`/`AiProviderStore`.
- **Dependency honesty (round-3 Medium-4 — CONFIRMED RESOLVED).** WI-4b (DI, incl. `AiProviderStore` in `AppContainer`) is foundational and gates the production run-through of WI-6/WI-7b/WI-AIP/WI-8; those WIs' unit/Compose gates proceed against injected fakes, and WI-4b is sequenced before them. No external feature gates the chain (#136 closed).

## 7. Backward compat

- **Room migration additive.** New `chapter_translations` (FK CASCADE, `lookupKey` PK, `sourceParagraphCount`, all columns `NOT NULL`). Existing rows untouched. Against this checkout **8→9, `MIGRATION_8_9`** with the **exact DDL in §2** appended after `MIGRATION_7_8` (VReaderDatabase.kt:224–228); the migration test extended from v8 validates it against Room's generated `9.json` schema (gap A).
- **Reader unchanged when bilingual off** — the TXT/MD `items(count = document.chunkCount, key = { it })` source loop + keys are **unchanged** (lazy-index==chunk-index preserved); each item's `Column` holds only the unchanged source `Text` unless `enabled && format∈{txt,md} && translation present` (translations are additive in-item children, non-registered, non-selectable — round-4 H2). `ReaderBottomChrome` is not modified. EPUB render adapter inert unless bilingual is on.
- **`AppContainer` gains `AiProviderStore`** (previously not provided — VReaderApp.kt:64/66 comment only) plus the bilingual services + `AiSettingsViewModel` factory; all additive lazy singletons following the `readerSettingsStore` pattern. #118 AI files are consumed unchanged **except** the additive save-result seam on `AiSettingsViewModel.save()` (returns the saved ID — round-4 H4c; the underlying `AiProviderStore.upsert` already returns the saved profile, so this exposes existing information without changing persistence behavior).
- **#118 AI provider files otherwise unchanged** — the prefetcher/readiness/Variant A sheet are new consumers; the scoped list is a new presentation over the shared VM state (round-4 H4b), not an edit to `AiProviderListScreen`.
- **Backup contract already compatible** — `PerBookSettingsOverride.bilingualEnabled/TargetLanguage/Granularity` exist (no `bilingualStyle`), no translation-cache backup section (device-local, re-derivable). #131 writes the three fields locally; backup collect/restore is a small additive follow-up (no contract change), out of v1; config device-local until then. **`bilingualGranularity` cross-platform conformance vector + iOS parity are UNCONFIRMED (gap B) — a follow-up when the backup-wiring WI lands: add a `contracts/vectors/` conformance vector + confirm iOS parity before shipping backup of the field.**
- **#132/#134/#129 landed** — the top-chrome pill mount + More-menu toggle (`readerMoreRows` extension) + `TxtReaderActivity` edit land on VERIFIED surfaces (rule 48 one-writer-per-file satisfied).

## Design gates (rule 51 — for `needs-design` filing)

1. **"Bilingual mode" setup sheet with BOTH Style AND Granularity in one Android sheet** (unchanged — Style stays descoped v1) — `vreader-bilingual.jsx` depicts Granularity (no Style); `vreader-ai-android.jsx` depicts Style (no Granularity); no committed bundle shows both together. v1 reproduces the granularity-only `vreader-bilingual.jsx` sheet and DROPS Style (user descope, §3). If Style is wanted as an Android user control, file `Design needed: bilingual setup sheet (Style + Granularity) for feature #131`. The box-D Style parity gap is tracked by the WI-9 follow-up checklist amendment.
2. **`Design needed: sentence-granularity bilingual interlinear — BOTH the setup-sheet Sentence control AND its render — for feature #131`** (round-4 H3 — broadened to cover both, filed together) — `vreader-bilingual.jsx` `BilingualPageContent` (lines ~195–277) depicts ONLY paragraph interlinear (one translation `<p>` per source paragraph), and a translation-after-each-sentence render (grouped when several sentences share a line-chunk) is depicted nowhere; the Sentence option appears only in the setup control (`vreader-bilingual.jsx:77`) with no matching renderer. v1 ships the depicted **paragraph** interlinear render + a **Paragraph-only** setup-sheet Granularity control; **Sentence is descoped from BOTH the control and the render in v1** (no undesigned surface, no paragraph-content-under-a-sentence-key). `TranslationGranularity.sentence` + `ChapterSegmenter.sentenceRanges` remain reserved-foundational code (WI-1). When the sentence-interlinear render (and its control option) is designed, it is a render-only follow-up (the one-lazy-item-per-chunk `Column` contract already accommodates several stacked sentence translation children per anchor chunk). The box-D Sentence gap is tracked by the WI-9 follow-up checklist amendment.

*(REMOVED in v4: the v3 "#136 dependency" design-gate line — #136 is closed and the Variant A AI Providers sheet IS the committed design, reproduced by WI-AIP, not a gate.)*

## Revision history

- v1 (2026-07-10): Gate-1 draft (Plan agent). Gate-2 Codex audit pending.
- v2 (2026-07-11): Gate-2 round-1 REDESIGN resolved — Readium-feasibility corrected, entry-point rebased on box F, setup-sheet design-gated, DI/cache/concurrency fixed.
- v3 (2026-07-12): Gate-2 round-2 findings resolved — TXT/MD document-global segment model (H1); EPUB translatePreSegmented + count-keyed cache + direct-block prefetch (H2); #136 AI-provider-reachability spun out as a hard dependency (GH #1976) + Style descoped v1 (H3); WI-0 go/no-go + navigator-race contract (M1); EPUB DOM-injection adapter not Compose body (M2); DI/factory WI reordered (M3); Room 8→9 MIGRATION_8_9 (M4); deps/WI-count corrected (L1/L2). Gate-2 round-3 = block-recommended.
- v4 (2026-07-12): Gate-2 round-3 (block-recommended) findings resolved AND the AI-config path folded in — AI-config FOLDED IN (#136 CLOSED); WI-AIP added; WI-4b provides `AiProviderStore` into `AppContainer`; H1 final-chunk math; H2 additive-item render contract; M1 EPUB single-owner; M2 dual-cancellation + single-flight; M3 blank-model fallback; M4 dependency honesty; WI count corrected to 13; chunk semantics corrected. Gate-2 round-4 = block-recommended.
- **v5 (2026-07-12): Gate-2 round-4 (block-recommended) findings resolved — 4 High + 2 gaps; a TARGETED PATCH of v4. Round-4 CONFIRMED M1/M2/M3/M4 RESOLVED and the Lows correct — those are UNCHANGED/KEPT.**
  - **H1 (round-4 High-1) — `Utf16Span` value type:** the final-chunk MATH stays (confirmed correct); the ONLY problem was the type contradiction — v4 declared `paragraphRanges`/`sentenceRanges` as `List<IntRange>` while treating them half-open, but Kotlin `IntRange` is inclusive-inclusive. Replaced `IntRange` EVERYWHERE with a dedicated `Utf16Span(start, endExclusive)` value type (NEW file `bilingual/Utf16Span.kt`, rides WI-1). `ChapterSegmenter.paragraphRanges`/`sentenceRanges` return `List<Utf16Span>`; `TxtChapterTextProvider` + the render path consume `Utf16Span`. Updated §2 H1, the segmenter/provider file entries, WI-1, and every test-catalogue "half-open UTF-16 (start,endExclusive)" mention.
  - **H2 (round-4 High-2) — one-lazy-item-per-chunk `Column` (THE key fix):** the v4 "separate additive `LazyColumn` items after the anchor chunk" contract is NOT implementable — the live reader treats lazy-item indices AS `TxtDocument` chunk indices (position-save via `offsetForChunk(firstVisibleItemIndex)`, TxtReaderActivity.kt:220/473/623; every bookmark/annotation/search/scrubber/TTS jump via `scrollToItem(chunkForOffset(...))`, :411/:421/:454/:481/:257; TTS visibility via `visibleItemsInfo.index == spokenChunk`, :256), so inserting separate translation items shifts every following lazy index and corrupts all of these. New binding contract: keep EXACTLY ONE lazy item per chunk (the `items(count=chunkCount, key={it})` loop + keys UNCHANGED → lazy-index==chunk-index preserved); INSIDE each item wrap the content in a `Column` — the UNCHANGED source `Text` (one `TextLayoutResult`, one `registerChunk(i)`) then the muted non-registered translation child(ren) anchored to chunk `i`. ADDED explicit translation **gesture exclusion** (TxtSelectionController.hitAt falls back to the nearest source chunk when the pointer is past source bounds, :47–53, so omitting `registerChunk` is not enough). Updated §2 H2, the `BilingualInterlinearBody` file entry, the rejected-alternatives list (added the separate-lazy-items rejection), WI-7a, WI-8, and the enabled-mode tests (position-save round-trips to the same chunk; jumps/TTS land on the correct chunk; long-press on translation does NOT select).
  - **H3 (round-4 High-3) — Paragraph-only v1 granularity:** v4's "Sentence selectable + sentence cache identity active + paragraph-render fallback" was underspecified (no sentence→paragraph aggregation) and would render undesigned sentence items or serve paragraph content under a sentence key. Resolution: v1 segments + caches + renders **Paragraph ONLY**. `TranslationGranularity` + `ChapterSegmenter.sentenceRanges` stay as reserved-foundational code (WI-1, unit-tested) but the v1 render/cache/VM/setup-sheet path is paragraph-exclusive (`promptVersion` `g=paragraph` always; no `sentenceRanges` in the v1 render path; the setup-sheet Granularity control is Paragraph-only). Broadened the sentence design gate to cover BOTH the control option AND its render (filed together). Updated §2 H2 granularity subsection, the cache-identity section, WI-5/WI-7a, and the tests.
  - **H4 (round-4 High-4) — WI-AIP editor-verbatim + new scoped list + save-result seam:** `AiProviderListScreen` owns its own `NavScreen`/chrome + generic empty state + row-tap-as-EDIT (AiProviderListScreen.kt:45/59/84/101/105), so it CANNOT be reused verbatim to reproduce the designed `‹ Bilingual` nav + bilingual empty state + checked-active row + tap-to-SELECT; AND `AiSettingsViewModel.save()` returns no ID and upserts async (:85–97), so a verbatim reuse can't deterministically `setActive(savedId)` + pop-on-success without racing the upsert. Resolution: (a) reuse the EDITOR (`AiProviderEditSheet`) VERBATIM; (b) the scoped LIST is a NEW `ReaderAiProvidersList` over the SHARED `AiSettingsViewModel` state reproducing the designed nav/empty-state/checked-row/tap-to-select; (c) an additive **save-result seam** on `save()` returning the saved provider ID (which `AiProviderStore.upsert` already produces, AiProviderStore.kt:58/84 — the #118 VM is production-unwired, wired for the first time here, so the seam is safe). Removed every "reuse `AiProviderListScreen` VERBATIM" claim. Updated the `ReaderAiProvidersSheet` file entry, §AI-config reachability, the rejected-alternatives list, WI-AIP, and its tests.
  - **Gap A (workflow completeness) — MIGRATION_8_9 exact DDL:** authored the exact `CREATE TABLE chapter_translations (...)` DDL (all `NOT NULL` columns + PK `lookupKey` + `index_chapter_translations_bookKey` + FK→`books(fingerprintKey)` ON DELETE CASCADE, modeled on the verified `MIGRATION_6_7` shape) in §2/WI-2 as a build-time contract, and required the migration test to validate it against Room's GENERATED `9.json` schema (not a hand-written approximation — cf. #135's stale-version finding).
  - **Gap B (workflow completeness) — backup granularity parity flag:** flagged (§6 Risks + §7 Backward compat) that the backup-contract `bilingualGranularity` field's cross-platform conformance vector + iOS parity are UNCONFIRMED — safe for v1 (backup collect/restore descoped / device-local), but a follow-up: when the backup-wiring WI lands, add a `contracts/vectors/` conformance vector + confirm iOS parity before shipping backup of the field.
  - WI count UNCHANGED at **13** (`Utf16Span` rides WI-1). Awaiting Gate-2 round-5 audit.

exec
/bin/zsh -lc 'rg -n "IntRange|Utf16Span|sentenceRanges|Paragraph-only|paragraph-only|promptVersion|MIGRATION_8_9|CREATE TABLE chapter_translations|ReaderAiProvidersList|save-result|AiProviderEditSheet|bilingualGranularity|backup|WI-AIP|WI-2|WI-8" dev-docs/plans/20260710-feature-131-android-bilingual-interlinear.md' in /Users/ll/workspace/vreader
 succeeded in 0ms:
21:- **TXT/MD unit (round-2 H1)** — `TxtDocument` has NO chapter model; it is line-based ≤4000-char chunks addressed by UTF-16 offset. v5 defines **document-global units with segment UTF-16 spans produced ONCE by the segmenter** and renders source/translation pairs from those same spans, with the **round-3 H1 final-chunk math fix**, the new **round-4 H1 `Utf16Span` value type** (§2, replacing `IntRange`), and the **round-4 H2 one-lazy-item-per-chunk `Column` render contract** (§2, §3).
23:- **AI-config path (folded in — #136 CLOSED)** — the ONLY designed Android AI-config reader surface is the **Variant A scoped "AI Providers" sheet pushed inside the bilingual flow**, reached from the bilingual engine strip's "Set up"/"Change…" button (`reader-ai-provider-entry.md`). #131 now owns it end-to-end (§"AI-config reachability", WI-4b + WI-AIP + WI-9).
32:2. **TXT/MD (Compose `TxtReaderActivity`) — INCLUDED.** No WebView; deterministically Compose-testable. Renders translations **inside the SAME lazy item as their anchor source chunk** (round-4 H2 — one lazy item per chunk, a wrapping `Column`), from **document-global segment `Utf16Span`s** (round-2 H1 + round-4 H1).
49:- The whole `.txt`/`.md` is treated as **one translation document**. The **segmenter runs once over `TxtDocument.text`** (the full raw backing string) and emits, per segment, its **UTF-16 span as a `Utf16Span(start, endExclusive)`** (half-open) against that same backing string (the segmenter's `paragraphRanges(text): List<Utf16Span>` / `sentenceRanges(text): List<Utf16Span>` — the span-returning peers of `paragraphs`/`sentences`; iOS precedent `ChapterSegmenter.sentenceRanges(in:)` at `ChapterSegmenter.swift:78`, returns `[Range<Int>]`). These spans are the SINGLE source of truth used by BOTH the translate side and the render side, so the two segment identically **by construction** (they read the same array). Spans are stored/compared as the explicit `Utf16Span` value type (see the H1 fix below), NOT re-derived on the render side.
52:#### H1 fix (round-3 High-1 math + round-4 High-1 type) — final-chunk source span + the `Utf16Span` value type (BINDING)
58:// chunk i source span is the HALF-OPEN Utf16Span(document.offsetForChunk(i), endExclusive)
61:**The type (round-4 High-1 — THE fix this round):** v4 declared `paragraphRanges`/`sentenceRanges` as `List<IntRange>` while treating them as half-open `[start, endExclusive)`. That is a **type contradiction** — Kotlin `IntRange` is inclusive-inclusive (`range.last` is the last *included* index, and `range.last` for an empty/at-EOF span is a footgun). The half-open contract and the `IntRange` type are incompatible. **Resolution — a dedicated value type, replacing `IntRange` EVERYWHERE:**
64:// bilingual/Utf16Span.kt  (NEW FILE — rides WI-1)
65:data class Utf16Span(val start: Int, val endExclusive: Int) {
72:- `ChapterSegmenter.paragraphRanges(text): List<Utf16Span>` / `sentenceRanges(text): List<Utf16Span>` return `Utf16Span`s (half-open, against the input string). `TxtChapterTextProvider` and the TXT/MD render path consume `Utf16Span` — there is **no `IntRange`** anywhere in the segment/span contracts. (`TxtSelectionController`'s own `Utf16Range` type is a *separate*, unrelated selection type and is untouched — see H2's gesture-exclusion note.)
74:- **Tests (WI-1 / WI-4a / WI-8):** `paragraphRanges`/`sentenceRanges` return correct half-open `Utf16Span(start, endExclusive)` spans (unit — WI-1); one-chunk document (no trailing newline) → its single paragraph/sentence translation renders (not dropped); final-chunk anchor (a paragraph whose last line is the final chunk) → translation renders after the last chunk; exact-boundary (a segment ending exactly at a chunk `start`) → anchored to the correct chunk, not off-by-one; EOF anchor (`span.endExclusive == text.length`) → resolves to the last chunk, no clamp-collapse.
100:4. Emit each anchored translation as a muted, non-registered `Text` sibling **inside the same `Column`**, keyed by the segment's `Utf16Span` so a language change re-keys cleanly.
104:- **Explicit translation gesture exclusion (round-4 High-2 — BINDING):** `TxtSelectionController.hitAt` (`reader/TxtSelectionController.kt:47`) falls back to the **nearest registered source chunk** when the pointer is outside all source-chunk bounds (`chunks.entries.minByOrNull { verticalDistance(...) }` when no chunk's `boundsInWindow()` contains the point, :51–53). So merely omitting `registerChunk` for the translation does **NOT** make it non-selectable — a long-press *on the translation text* would fall through to the nearest source chunk and select source. **WI-8 must add an explicit hit-test / gesture exclusion for the translation composable's bounds** so a long-press whose pointer lands inside a translation `Text`'s bounds is consumed (no selection begun) rather than routed to `hitAt`'s nearest-chunk fallback. (Options: the translation `Text` consumes the long-press gesture in its own `pointerInput`; or the selection gesture root records the translation composables' window bounds and short-circuits `beginAt` when the point is inside one. WI-8 picks and tests one.)
106:- **Enabled-mode tests (WI-8 connected + WI-7a Compose, BINDING):** with bilingual ON —
117:  - The `TranslationGranularity` enum + `ChapterSegmenter.sentenceRanges` API **stay as reserved FOUNDATIONAL code** (WI-1, with unit tests) so the future sentence-render is a render-only follow-up.
118:  - The v1 **render/cache/VM/setup-sheet path uses paragraph exclusively:** `promptVersion`'s granularity component is **always `paragraph` in v1**; there is **no `sentenceRanges` in the v1 render path**; the setup sheet's Granularity control is **descoped to Paragraph-only in v1** (a documented divergence, tracked by the sentence design gate below — the same treatment as the Style descope).
123:This closes round-3 H1 (no dropped final-chunk translations), round-3 H2 (per-chunk layout/selection preserved; source `Text` never split), round-4 H1 (the `Utf16Span` type replaces the incompatible `IntRange`), round-4 H2 (one lazy item per chunk preserves lazy-index==chunk-index; translation gesture exclusion), round-4 H3 (Paragraph-only v1 granularity), and round-3 Low-2 (correct chunk semantics).
143:                    AiProviderEditSheet   [reused VERBATIM from #118]
160:- `bilingual/Utf16Span.kt` — **NEW (round-4 H1).** `data class Utf16Span(val start: Int, val endExclusive: Int)` (half-open UTF-16 span; `require(endExclusive >= start)`; `isEmpty`, `length`). The single span type shared by the segmenter and the TXT/MD render path, replacing the incompatible `IntRange`. Rides WI-1. (Distinct from `TxtSelectionController.Utf16Range`, the selection type, which is untouched.)
164:- `bilingual/ChapterSegmenter.kt` — **NEW file (no existing Android segmenter — verified).** Port of iOS `ChapterSegmenter`: `paragraphs(text)` / `sentences(text)` **plus the span-returning peers `paragraphRanges(text): List<Utf16Span>` / `sentenceRanges(text): List<Utf16Span>`** (half-open UTF-16 spans against the input string, as `Utf16Span` — round-4 H1; iOS `sentenceRanges(in:)` precedent). CJK-aware sentence enumeration (`。！？` vs Latin). Pure. (`sentenceRanges` is reserved-foundational; the v1 render path calls only `paragraphRanges` — round-4 H3.)
168:- `bilingual/TxtChapterTextProvider.kt` — provider over `TxtDocument` + the segmenter's `Utf16Span` array (H1). Builds the document-global segment `Utf16Span`s once (via `paragraphRanges` — paragraph only in v1), groups them into windows, resolves `unitContaining` via a segment-start binary search over `charOffsetUTF16`. MD source = raw markdown segment text.
187:- `bilingual/PerBookBilingualStore.kt` — DataStore-Preferences, keyed by `bookFingerprintKey`, holding `{ enabled, targetLanguage, granularity }` (`granularity` is persisted but pinned to `paragraph` in v1 — round-4 H3). The Android `PerBookSettingsOverride` bilingual slice — the backup contract declares exactly `bilingualEnabled` / `bilingualTargetLanguage` / `bilingualGranularity` and **NO `bilingualStyle`** (verified). Wiring into backup collect/restore is scoped OUT (§7); until then bilingual config is device-local.
192:- `data/ChapterTranslationEntity.kt` — `@Entity(tableName="chapter_translations", indices=[Index("bookKey")], foreignKeys=[FK→books.fingerprintKey ON DELETE CASCADE])`. **`@PrimaryKey val lookupKey: String`** (Room requires a PK; project pattern `@PrimaryKey` + `@Upsert`, verified `BookEntity` `@PrimaryKey val fingerprintKey`, Entities.kt:24). `lookupKey` = `bookKey|unitStorageKey|targetLanguage|promptVersion`. Columns: `lookupKey` (PK), `bookKey`, `unitStorageKey`, `targetLanguage`, `promptVersion`, `translatedJson`, `sourceParagraphCount`, `createdAt`. Mirrors iOS `ChapterTranslationRecord.lookupKey` (`book|unit|lang|prompt`, profile-agnostic — Bug #342). `sourceParagraphCount` is load-bearing for H2 (stores the enumerate's count on the `translatePreSegmented` path so `cachedTranslation(expectedSegmentCount:)` restores). **The exact `MIGRATION_8_9` DDL is authored in WI-2 — see below.**
196:**Cache-identity (reconciled with iOS parity):** the 4-part key `book|unit|lang|promptVersion` is profile-AGNOSTIC / style-agnostic (Bug #342). Style is descoped (§3) so no `s=` component. **Granularity is paragraph-only in v1** (round-4 H3): `promptVersion = "bilingual-v1|g=paragraph"` in v1 (the `g=` component is always `paragraph`). The composite `g=` slot is retained in the key format so a future granularity is a different cache row by construction (closes the iOS #344 "sentence silently ignored" class ahead of time), but v1 never emits `g=sentence`. A language change cancels in-flight jobs, bumps the VM generation, clears shaped `translationsByUnit`, and forces a correctly-keyed re-fetch (WI-6).
202:- `bilingual/BilingualSetupSheet.kt` — reproduces `vreader-bilingual.jsx`'s `BilingualSetupSheet` (lines 27–156) EXACTLY, with the granularity divergence: header; a preview strip (`BilingualPreview`); a language grid over `BILINGUAL_LANGS` (glyph tiles, selected accent); a **Granularity** segmented control **descoped to Paragraph-only in v1** ("Translate after each ¶"; the Sentence option is not rendered in v1 — round-4 H3, tracked by the sentence design gate); a **Translation engine** strip (configured: "Claude · with this book's context" + "Change…"; unconfigured: "No AI provider configured" + "Bilingual mode needs an AI provider to translate." + "Set up"); the "Turn on bilingual mode" CTA. **No Style control, no provider/model card, no term-overrides toggle, no cost footer** (those belong to the `vreader-ai-android.jsx` sheet, not reproduced — §3). The `aiConfigured` flag comes from `BilingualAiReadiness.resolve`. The "Set up"/"Change…" CTA routes to `ReaderAiProvidersSheet` (wired in WI-9).
204:  - **(a) EDITOR reused VERBATIM.** `AiProviderEditSheet` (the canonical add/edit modal, Kind / Name / Endpoint / Sampling / API Key / Test Connection) is presented UNCHANGED from the #118 Library path — that reuse is confirmed fine (`reader-ai-provider-entry.md:49–52`, :63–65).
205:  - **(b) The scoped LIST is a NEW reader-specific presentation** (`ReaderAiProvidersList`, in this file) built over the **SHARED `AiSettingsViewModel` state** (`listState`, verified `AiSettingsViewModel.kt:26`) + shared row/cell components, reproducing: the reader-scoped nav (`‹ Bilingual` back label, "AI Providers" title — `NavSheet` at jsx:247, NOT `AiProviderListScreen`'s own `NavScreen`); the **bilingual-context empty state** ("Choose the provider bilingual mode will use to translate this book." context strip + "No providers yet" + "Add provider" CTA — jsx:180–209); the **checked-active row** (`selected={p.id === selectedId}` — jsx:221; the live `AiProviderListState`/`AiProviderRow` already carries `active` per row, `AiSettingsViewModel.kt:30`); and **tap-to-SELECT** (`onSelect(p.id)` → `vm.setActive(id)` — jsx:221/237). It does **NOT** reuse `AiProviderListScreen`'s `NavScreen`/chrome/`AiEmptyState`/`ProviderRow`-tap-edit.
206:  - **(c) A save-result seam** (round-4 High-4): `AiSettingsViewModel.save()` today returns Unit and upserts async (generates `s.id ?: UUID.randomUUID().toString()` *inside* the launched coroutine, then `_edit.value = null`, no saved ID — `AiSettingsViewModel.kt:85–97`), so WI-AIP cannot deterministically `setActive(savedId)` + pop-on-success by reusing it verbatim (popping immediately races the async upsert; observing list state can't distinguish the new profile). **Note:** `AiProviderStore.upsert` ALREADY returns the saved profile (`suspend fun upsert(...): AiProviderProfile`, "Returns the saved profile", `AiProviderStore.kt:58/70/84`) — the ID is present at the store layer; only the VM discards it. So the seam is an **additive completion/result signal on `AiSettingsViewModel.save()`** (or a thin WI-AIP wrapper) returning the saved provider ID (from `store.upsert(...).id`), so WI-AIP can `setActive(savedId)` + pop-on-success **after** the upsert commits — no race. The #118 VM is currently production-UNWIRED (only test-referenced — verified), and this feature wires it to production for the FIRST time, so an additive save-result seam is safe and appropriate.
207:  - **Behavior per the nav model:** empty → "Add provider" → `AiProviderEditSheet` → Save → `save()` returns the saved ID → `store.setActive(savedId)` (first-provider-active is already the store's default `activeId = cur.activeId ?: id`, AiProviderStore.kt:81; the explicit `setActive(savedId)` guarantees the freshly-saved provider is the engine even if others existed) → **pop the whole stack** back to the bilingual sheet, engine strip now "Claude · configured / Change…". `‹ Bilingual` without adding → unconfigured, **no state mutated**. "Change…" → the SAME sheet, populated, current provider checked, tap a row → `setActive`. No consent card, no feature-flag toggle, no readiness tracker (iOS #82, deferred).
244:- `data/VReaderDatabase.kt` — add `ChapterTranslationEntity` to `@Database entities`, bump `version` **8 → 9** (the live DB is v8, migrations `MIGRATION_1_2`..`MIGRATION_7_8`, `ALL_MIGRATIONS` ends at `MIGRATION_7_8` — verified VReaderDatabase.kt:29,224–228), add **`MIGRATION_8_9`** (exact DDL below — gap A), **append `MIGRATION_8_9` to `ALL_MIGRATIONS` after `MIGRATION_7_8`**, add `abstract fun chapterTranslationDao()`. Purely additive.
246:  **`MIGRATION_8_9` exact DDL (gap A — BINDING; modeled on the verified `MIGRATION_6_7` `search_index_state` shape at VReaderDatabase.kt:154–169, whose DDL Room's PRAGMA validation already accepts):**
249:  val MIGRATION_8_9: Migration = object : Migration(8, 9) {
257:                  "`promptVersion` TEXT NOT NULL, " +
278:- `reader/TxtSelectionController.kt` — **may gain a small additive seam for the translation gesture-exclusion** (H2) IF WI-8's chosen exclusion approach records translation-composable bounds at the selection root (e.g. an optional "excluded bounds" setter the body populates). If WI-8 instead consumes the long-press in the translation `Text`'s own `pointerInput`, this file is untouched. WI-8 picks one; the `hitAt` nearest-chunk fallback (`reader/TxtSelectionController.kt:47–53`) is the reason an exclusion is required at all.
287:- **Backup collect/restore of `PerBookSettingsOverride` bilingual fields** — contract fields exist; wiring is a small additive follow-up (§7). Device-local until then. **The `bilingualGranularity` field's cross-platform conformance vector + iOS parity are UNCONFIRMED (gap B, §6/§7) — a follow-up when the backup-wiring WI lands.**
289:- **Sentence granularity (both the setup-sheet Sentence control AND the sentence-interlinear RENDER)** — not depicted (round-4 H3); design-gated together (§Design gates). v1 renders + caches + offers **paragraph only**; `sentenceRanges`/`TranslationGranularity.sentence` remain reserved-foundational code (WI-1, unit-tested) but are absent from the v1 render/cache/VM/setup-sheet path.
315:11. **Reusing `AiProviderListScreen` VERBATIM for the Variant A scoped list (v4)** — REJECTED (round-4 H4): `AiProviderListScreen` owns its own `NavScreen`/chrome (AiProviderListScreen.kt:59), a generic empty state (:84/:87), and row-tap-as-EDIT (:105), so it cannot reproduce the designed `‹ Bilingual` nav + bilingual-context empty state + checked-active row + tap-to-SELECT. Replaced by (a) reuse the EDITOR verbatim + (b) a NEW `ReaderAiProvidersList` over the shared `AiSettingsViewModel` state + (c) a save-result seam returning the saved ID.
323:**Resolution:** this plan reproduces the **`vreader-bilingual.jsx` sheet EXACTLY**, with the round-4 H3 granularity divergence (Paragraph-only in v1). **Style is DESCOPED for v1** (user decision): keep provider/model/**granularity (paragraph)**, DROP the bilingual "Style" control. Consequently store/VM carry no `style`, the chunk contract has no `style` param, and the cache key's `promptVersion` has no `s=` component.
329:The canonical decision (`reader-ai-provider-entry.md`, Variant A) + its component canvas (`vreader-ai-provider-entry.jsx`) ARE the committed design; #131 reproduces only what they depict (a `‹ Bilingual`-titled push sheet hosting the provider list + the canonical editor, pop-back-on-first-save, checked-active row, tap-to-select). The scoped list is a NEW reader-specific presentation over the shared #118 VM state (round-4 H4) — it does not reuse `AiProviderListScreen`'s chrome/empty-state/row-tap-edit — but it invents no new AI-config sheet or nav beyond what the Variant A canvas depicts. The editor (`AiProviderEditSheet`) IS reused verbatim. The iOS #82 readiness additions (flag/consent) are explicitly **out** on Android (no such subsystems exist). This is a designed surface — it is NOT a design gate.
333:- **#118 provider seam**: reuse `AiProviderStore.snapshot()` (`snapshot.active`) + `store.apiKey(profile)` + `AiProviderFactory.create` (default of an injected factory param) + `AiClient.chat`. #118's AI files are unchanged EXCEPT the additive save-result seam on `AiSettingsViewModel.save()` (round-4 H4c — returns the saved ID, which `AiProviderStore.upsert` already produces, AiProviderStore.kt:58/84); #131 wires `AiProviderStore` into `AppContainer` and reuses `AiProviderEditSheet`/`AiSettingsViewModel` for the Variant A sheet (the scoped list is new — H4b).
342:**13 WIs/PRs (round-3 Low-1 fix — corrected count; UNCHANGED in v5):** the list is exactly **WI-0, WI-1, WI-2, WI-3, WI-4a, WI-4b, WI-5, WI-6, WI-7a, WI-7b, WI-AIP, WI-8, WI-9** = **13 WIs**. `Utf16Span` (round-4 H1) is a NEW file but **rides WI-1** (the foundational value-types + pure-segmentation WI) — it does not add a WI. Each WI = one PR. Build order: **foundation/cache → service/direct-block APIs → shared DI/factory (incl. `AiProviderStore` in `AppContainer`) → VM state/prefetch → host-specific renderers (TXT/MD + EPUB) + the Variant A AI Providers sheet → entry wiring.**
347:- **WI-4b is foundational and gates the behavioral chain.** WI-4b provides `AiProviderStore` into `AppContainer` PLUS the bilingual services + factories. Per the audit's Medium-4, WI-4b transitively gates WI-6 (needs the prefetcher/DI), WI-7b (needs DI), WI-AIP (needs `AiProviderStore` + `AiSettingsViewModel` from `AppContainer`), and WI-8 (needs DI). **Chosen resolution: injected seams so the behavioral work proceeds against fakes before WI-4b lands, AND WI-4b is sequenced early.** Concretely: the VM (WI-5/WI-6) takes an injected `ChapterTranslationPrefetcher` (fake in tests) and an injected `AiProviderSnapshot` provider (fake); the TXT/MD host Compose/unit work (WI-8) and the Variant A sheet (WI-AIP) take injected VM/store/`AiSettingsViewModel` seams — so unit/Compose tests do not wait on `AppContainer`. **WI-4b is built right after WI-4a (before WI-6/WI-7b/WI-AIP/WI-8) so the production wiring lands before the host integrations that mount it.** This is stated honestly: the *production run-through* of WI-6/WI-7b/WI-AIP/WI-8 depends on WI-4b; their *unit/Compose gates* depend only on the injected seams. No external feature gates any of this.
351:**WI-1 (foundational): value types + pure segmentation/chunk/contract.** **`Utf16Span` (round-4 H1 — the half-open span value type replacing `IntRange`)**, `TranslationUnitId`, `TranslationGranularity` (reserved; v1 uses `paragraph` only — round-4 H3), `BilingualLanguages`, **`ChapterSegmenter` (with `paragraphRanges`/`sentenceRanges` returning `List<Utf16Span>` — H1; `sentenceRanges` is reserved-foundational, not in the v1 render path — H3)**, `TranslationChunker`, `TranslationChunkContract` (no `style`), `ChapterTranslationError`. Pure; ported iOS vectors. Deps: none. Tests: `paragraphRanges`/`sentenceRanges` return correct half-open `Utf16Span(start, endExclusive)` spans (both APIs unit-tested even though only `paragraphRanges` ships in the v1 render path — `sentenceRanges` stays covered as reserved-foundational code); chunker packs-to-budget/oversize/empty; contract prompt/decode/fence/mismatch; error mapping.
353:**WI-2 (foundational): Room translation cache.** `ChapterTranslationEntity` (PK = `lookupKey`, all-`NOT NULL` columns matching the DDL, `sourceParagraphCount` column) + `Dao` (`@Upsert`) + `ChapterTranslationStore`; `VReaderDatabase` **8→9 `MIGRATION_8_9`** with the **exact DDL authored in §2 (gap A)**, appended after `MIGRATION_7_8`. Robolectric migration round-trip from v8 + full-chain + upsert/get/delete-by-lookupKey + FK-CASCADE + **exact-DDL guard validated against Room's GENERATED `9.json` schema (not a hand-written approximation — gap A)**. Deps: none.
355:**WI-3 (foundational): `ChapterTranslationService`** against a fake `AiClient`. Both `cachedTranslation` overloads (incl. the `expectedSegmentCount` divergence restore — H2) + `translate` + `translatePreSegmented`. **Dual-cancellation (native + typed `Cancelled`) BEFORE generic mapping (M2).** Deps: WI-1, WI-2. Tests: cache hit → zero client calls; miss → translate + write; decode fail → per-segment fallback; one-chunk fail → source-only that chunk (others translated, NOT cached); all-chunks fail → throw; native-cancel → `Cancelled` (no write); typed-`Cancelled`-from-chunk → `Cancelled` (no write); ensureActive-before-write; `AiError` mapping incl. `Config`/`InsecureUrl` → `ProviderFailed`; `translatePreSegmented` full-success caches under the enumerate count; partial degrade NOT cached; all-fail throws; `cachedTranslation(expectedSegmentCount)` returns on stored-count match, null on mismatch, needs no provider.
357:**WI-4a (foundational): `ChapterTextProvider` (TXT/MD) + `ChapterTranslationPrefetcher` + `BilingualAiReadiness`.** `TxtChapterTextProvider` builds the document-global segment `Utf16Span`s once (via `paragraphRanges` — paragraph only, H1/H3), groups into windows, resolves `unitContaining(charOffsetUTF16)` via segment-start binary search, `sourceSegments(unit)`. Prefetcher: `prefetch` + `prefetchDirect` + `cachedDirect`; resolves active profile from `snapshot()`, decrypts snapshot-consistent, builds client via the injected factory param (default `AiProviderFactory::create`), constructs `AiRequest` with **`model = profile.model.ifBlank { profile.kind.defaultModel }` (M3)**. Readiness = active profile with non-empty decrypted key; **cipher failure → not-ready, never a crash.** Fake store + fake factory. Deps: WI-1, WI-3. Tests (all `Utf16Span`-based): unit resolution + clamp + empty; **one-chunk document (no trailing newline) → its segment translation renders, not dropped (H1)**; **final-chunk anchor → renders (H1)**; **exact-boundary → correct anchor (H1)**; **EOF anchor (`span.endExclusive == text.length`) → last chunk, no clamp-collapse (H1)**; paragraph spanning MANY chunks → one segment/one unit, anchored to the last chunk (Low-2); a >4000-char paragraph hard-split across chunks → one segment; CR/LF/CRLF; MD markers; locator→unit mapping; `unitAfter` end→null; **source-byte parity while disabled**; cache-hit-no-profile still returns (#306); no-profile miss → `ProviderFailed`; `prefetchDirect` 1:1; `cachedDirect` restores with zero provider calls; **blank `profile.model` → `AiRequest.model == kind.defaultModel` (M3 regression)**; readiness true/false; empty-key → false; no-active-with-profiles-present → false (H3); cipher-throw → readiness false (no crash). (Sentence-multi-in-one-chunk is NOT a v1 render test — the v1 provider uses `paragraphRanges` only; `sentenceRanges` behavior is covered in WI-1's reserved-foundational unit tests.)
359:**WI-4b (foundational — shared DI/factory, incl. `AiProviderStore` in `AppContainer`): AppContainer bilingual + AI-config graph.** `AppContainer` **now constructs `AiProviderStore`** (DataStore + #116 `KeystoreSecretCipher`, following the `readerSettingsStore` convention — this is #131's change, not an external feature's) and provides `ChapterTranslationStore`, `PerBookBilingualStore`, `ChapterTranslationService`, `ChapterTranslationPrefetcher`, an `AiSettingsViewModel` factory (for WI-AIP), and the `BilingualViewModel` factory. Deps: **WI-4a** (no external dep — #136 closed). Tests: container resolves the bilingual + AI-config graph; `AiProviderStore` resolves and round-trips a profile; the prefetcher's injected factory defaults to `AiProviderFactory::create`.
365:**WI-7a (behavioral): Compose UI — setup sheet + interlinear body (TXT/MD) + pill.** Reproduce `vreader-bilingual.jsx` (setup sheet: language grid / **Paragraph-only Granularity control (round-4 H3)** / preview / engine strip configured+unconfigured; body: the translation rendered **inside the anchor chunk's `Column` as a muted non-registered `Text` child** per the round-4 H2 render contract — translated / loading N%+dimmed / error+Retry / offline source-only; pill). Consumes the host-neutral `BilingualRenderState` DTO. Light+dark. Compose UI tests each state, incl. **paragraph interlinear renders a translation child after a paragraph's last source chunk (depicted)**; **the setup-sheet Granularity control shows Paragraph only, no Sentence option (H3)**. Deps: WI-5 (state shape). NO Style control; the unconfigured "Set up" CTA renders and (in WI-9) routes to the Variant A sheet.
369:**WI-AIP (behavioral — the folded-in Variant A AI Providers sheet; round-4 H4 rewritten): `ReaderAiProvidersSheet`.** The scoped in-reader "AI Providers" push sheet (nav bar `‹ Bilingual` + "AI Providers" title) reproducing `vreader-ai-provider-entry.jsx` `AIProvidersSheet`/`AIProvidersSheetBody`/`NavSheet`. Per round-4 H4:
370:  - **(a)** present `AiProviderEditSheet` VERBATIM from #118 (Kind/Name/Endpoint/Sampling/API Key/Test Connection unchanged).
371:  - **(b)** a NEW `ReaderAiProvidersList` presentation over the SHARED `AiSettingsViewModel.listState` (verified `AiSettingsViewModel.kt:26`; each `AiProviderRow` already carries `active`, :30) + shared row/cell components — reproducing the reader-scoped `‹ Bilingual` nav (`NavSheet`, jsx:247, NOT `AiProviderListScreen`'s `NavScreen`), the bilingual-context empty state ("Choose the provider bilingual mode will use to translate this book." + "No providers yet" + "Add provider" — jsx:180–209), the **checked-active row** (`selected = row.active` — jsx:221), and **tap-to-SELECT** (`onSelect(id) → vm.setActive(id)` — jsx:221/237). It does NOT reuse `AiProviderListScreen`'s NavScreen/chrome/`AiEmptyState`/`ProviderRow`-tap-edit.
372:  - **(c)** the **save-result seam**: `AiSettingsViewModel.save()` (or a thin WI-AIP wrapper) is extended to return the saved provider ID (from `store.upsert(...).id`, which the store already returns — `AiProviderStore.kt:58/84`), so on first Save → `store.setActive(savedId)` → pop the whole stack back to the bilingual sheet (engine strip now "configured / Change…"), **deterministically, after the upsert commits (no race)**.
375:**WI-8 (behavioral): `TxtReaderActivity` integration.** Wire VM into the `items(count = document.chunkCount, key = { it })` loop as **muted non-registered translation `Text` children inside each anchor chunk's wrapping `Column`, source chunk byte-unchanged, the loop + keys UNCHANGED so lazy-index==chunk-index is preserved (round-4 H2)** + the translation **gesture-exclusion** (round-4 H2) + position-change (`charOffsetUTF16`) + setup-sheet. `originalFormat`-gated (TXT/MD). Uses WI-4b's DI. **#129 VERIFIED — straight edit.** Connected test (fake `AiClient` seam): enable → setup → confirm → interlinear from seeded cache; **enabled-mode source-chunk selection registrations UNCHANGED vs disabled (H2)**; **highlights/annotation-washes/read-aloud-wash still key off source chunks (H2)**; **with bilingual ON — position-save round-trips to the same chunk; bookmark/search/scrubber/TTS jumps land on the correct chunk (lazy-index==chunk-index preserved — round-4 H2)**; **a long-press on translation text does NOT select (gesture exclusion — round-4 H2)**; a translation child is non-selectable, does not perturb source offsets (H2); disable → source-selection byte-parity; reopen persists enabled + renders from cache with zero client calls; **paragraph-spanning-many-chunks renders exactly one translation inside its last chunk's `Column` (H1/Low-2)**; **one-chunk/final-chunk anchors render (H1)**; MD source mapping. Deps: WI-6, WI-7a, WI-4b.
377:**WI-9 (behavioral): entry wiring + acceptance.** Mount `BilingualPill` in #132's VERIFIED top chrome; extend `readerMoreRows(...)` to supply the #134 VERIFIED More-menu `MoreActionId.BILINGUAL` toggle (`MoreRow.Toggle` `on`/`onToggle`, or `MoreRow.Disabled` "Configure AI provider first" when not configured) wired to the VM; **wire the setup sheet's "Set up"/"Change…" affordance → the #131-owned `ReaderAiProvidersSheet` (Variant A)**. Full acceptance across EPUB (if WI-7b landed) + TXT/MD, including the fresh-user path `unconfigured → Set up (→ Variant A AI Providers sheet) → add provider → Save → return → enable → translate` (now #131-owned end-to-end). **Flip box D to done ONLY for provider/model/granularity(paragraph) + the Style-descope AND Sentence-descope notes; file the follow-up checklist amendment; do NOT claim full box-D parity.** The DONE flip **no longer waits on #136** (closed). Update `docs/architecture.md` (bilingual pipeline + the new `chapter_translations` schema + `AiProviderStore` + bilingual services in `AppContainer` + the Variant A AI Providers sheet). → DONE. Deps: WI-8, WI-AIP, WI-7b (if go), feat:#132, feat:#134.
381:JVM/Robolectric (`android/app/src/test/...bilingual/`): `Utf16SpanTest` (**half-open invariants: `endExclusive >= start`, `isEmpty`, `length`; round-4 H1**); `ChapterSegmenterTest` (paragraph blank-line; sentence CJK `。！？` vs Latin; empty→[]; single; **`paragraphRanges`/`sentenceRanges` return correct half-open `Utf16Span(start, endExclusive)` spans — both APIs covered even though only `paragraphRanges` ships in the v1 render path**); `TranslationChunkerTest` (packs to budget; oversize→own chunk+subSplit; empty→[]); `TranslationChunkContractTest` (prompt shape; strict JSON decode; code-fence strip; count mismatch→`CountMismatch`; non-array→`NotAStringArray`); `ChapterTranslationServiceTest` (cache hit 0 calls; miss→translate→write; decode-fail per-segment fallback; one-chunk-fail partial-not-cached; all-fail→throw; **native-cancel→Cancelled no write; typed-`Cancelled`→Cancelled no write (M2)**; ensureActive-before-write; offline/timeout/429/http/config/insecure→error mapping; very long chapter N-of-M; stale-cache count-mismatch re-translates; `translatePreSegmented` caches under enumerate count on full success; partial degrade not cached; all-fail throws; `cachedTranslation(expectedSegmentCount)` hit/miss with no provider); `ChapterTranslationErrorMappingTest`; `TxtChapterTextProviderTest` (**one-chunk document → renders (H1); final-chunk anchor → renders (H1); exact-boundary → correct anchor (H1); EOF anchor → last chunk, no clamp-collapse (H1)**; paragraph spanning MANY chunks → one segment/unit anchored to last chunk (Low-2); >4000-char paragraph → one segment across hard-split chunks; CR/LF/CRLF; MD markers; locator→unit mapping; `unitAfter` end→null; source-byte parity while disabled; **provider uses `paragraphRanges` only — H3**); `ChapterTranslationPrefetcherTest` (snapshot-consistent profile+key; injected-factory used; `AiRequest` built from profile; **blank `profile.model` → `kind.defaultModel` (M3 regression)**; cache-hit-no-profile #306; no-profile miss→ProviderFailed; `prefetchDirect` 1:1; `cachedDirect` restores with zero provider calls; CJK↔English + Latin round-trip via fake; cipher-throw→ProviderFailed not crash); `BilingualAiReadinessTest` (active+key→true; **no-active-with-profiles-present→false (H3); activeId-null→false (H3)**; empty key→false; cipher-throw→false, no crash); `PerBookBilingualStoreTest` (enabled/lang/granularity round-trip; granularity pinned paragraph; no style field); `BilingualViewModelTest` (Turbine: first-enable sheet; re-enable no-sheet; disable clears; language reset; `aiConfigured` from readiness; prefetch current+next; same-unit no-op; **cancel-mid discards (no errorUnit); typed-Cancelled discards (M2); rapid re-trigger same unit single-flight, no double-write (M2)**; offline→unavailable; error→errorUnit+retry; `retryUnit`); `AiSettingsViewModelSaveResultTest` (**`save()` returns the saved provider ID after the upsert commits — round-4 H4c seam; the returned ID matches `store.upsert(...).id`**); `EpubBilingualJsTest` (JS escaping / CSP-safe insertion; RTL/CJK style; empty translations; clear idempotent; inject idempotent replacement; source-only fallback — WI-7b if go); `EpubBilingualControllerTest` (**enumerate→cachedDirect/prefetchDirect→guarded commit; stale-session-token commit discarded, no errorUnit; single-owner (regular TXT/MD prefetch never runs for EPUB unit) — Medium-1** — WI-7b if go).
385:Compose UI (`androidTest/...bilingual/`): `BilingualSetupSheetUiTest` (language grid, **Granularity control shows Paragraph only — no Sentence option (H3)**, preview, engine configured vs unconfigured driven by `aiConfigured`; no Style control present; light+dark); `BilingualInterlinearBodyUiTest` (**translation rendered as a muted `Text` child inside the anchor chunk's `Column` (round-4 H2 render contract); paragraph interlinear translated incl. CJK font + RTL Arabic**; loading N%+dimmed; error+Retry; offline source-only; empty translation→source-only no crash); `ReaderAiProvidersSheetUiTest` (**the scoped list renders `‹ Bilingual` back label + bilingual-context empty copy + checked active row + tap-selects (`setActive`) — round-4 H4b; editor (`AiProviderEditSheet`) reused verbatim (H4a)**); `BilingualPillUiTest`.
387:Connected (`androidTest/...reader/`): `TxtReaderBilingualConnectedTest` (API 35, fake `AiClient` via injected factory): enable→setup→confirm→interlinear from seeded Room cache; **enabled-mode source-chunk selection registrations UNCHANGED vs disabled (H2); highlights/annotation-washes/read-aloud-wash still key off source chunks (H2)**; **with bilingual ON — position-save round-trips to the same chunk; bookmark/search/scrubber/TTS jumps land on the correct chunk (lazy-index==chunk-index preserved — round-4 H2)**; **long-press on translation text does NOT select (gesture exclusion — round-4 H2)**; translation child non-selectable + no source-offset perturbation (H2); disable→source-selection byte-parity; reopen persists enabled + renders from cache with zero client calls; **paragraph-spanning-many-chunks renders one translation (H1/Low-2); one-chunk/final-chunk anchors render (H1)**; TXT/MD gated (PDF inert); very long chapter scroll responsive; cancellation leaves no partial cache row. `ReaderAiProvidersConnectedTest` (WI-AIP + WI-9): `unconfigured → Set up → Variant A sheet → add provider → Save → save-result-id → setActive → pop-to-bilingual configured (deterministic, no race — round-4 H4c) → enable → translate`; `‹ Bilingual` without adding → unconfigured, snapshot unchanged; "Change…" → populated, current checked, tap → setActive. `EpubReaderBilingualConnectedTest` (only if WI-0=go): enable→inject on a real EPUB; disable→clear; href-change/fragment-recreation/activity-recreation→re-apply from cache (zero provider calls); count-divergence handled via `prefetchDirect`/`cachedDirect`; regular prefetch never runs for EPUB unit (Medium-1).
389:Edge cases: empty translation, failed, partial per-chunk, CJK↔English + Latin + RTL, provider error/timeout/429/config/insecure, native + typed cancellation mid-translation + before-write, single-flight overlap, very long chapters, offline (cache-first + silent source-only), cipher-decrypt failure → not-ready (no crash), enumerate↔segment count divergence (direct path), one-chunk/final-chunk/EOF anchors (H1), blank model (M3), lazy-index==chunk-index parity with bilingual on (round-4 H2), translation-text long-press excluded (round-4 H2), save-result-id determinism (round-4 H4).
393:- **Live-translation verification is AI-credential-gated (the box-D caveat).** The whole pipeline is verified without live creds via a deterministic **fake `AiClient`** injected through the prefetcher's `clientFactory` param (default `AiProviderFactory::create`; tests override). WI-3/4a/8 prove segment→chunk→decode→cache→interleave end-to-end incl. every error/edge path. Connected tests seed the Room cache and assert render-from-cache with zero client calls. An optional live smoke confirms wire format but is NOT a gate. The fresh-user `unconfigured → Set up → add provider` reachability leg is now #131-owned (WI-AIP + WI-9) and verified by `ReaderAiProvidersConnectedTest`.
394:- **Final-chunk translation drop + span type (round-3 H1 + round-4 H1).** Fixed by `endExclusive = if (i+1<chunkCount) offsetForChunk(i+1) else text.length` + the dedicated **`Utf16Span(start, endExclusive)`** half-open value type replacing the incompatible `IntRange` everywhere in the segment/render contracts; one-chunk/final-chunk/exact-boundary/EOF tests. `offsetForChunk`'s clamp (TxtDocument.kt:17) is never relied on for the final end.
396:- **TXT/MD segment↔render pairing (round-2 H1).** Both sides read the SAME segment `Utf16Span` array over `TxtDocument.text`, so 1:1 holds by construction — no chapter model invented; a paragraph split across many chunks is translated + rendered once (inside its last chunk's `Column`). Granularity is paragraph-only in v1; the `g=` cache slot is retained for a future granularity.
397:- **Undesigned sentence render (round-4 H3).** v1 segments + caches + renders + offers **paragraph only** — the only depicted interlinear pattern. `TranslationGranularity.sentence` + `ChapterSegmenter.sentenceRanges` stay as reserved-foundational code (WI-1, unit-tested) but never appear in the v1 render/cache/VM/setup-sheet path. The Sentence control AND its render are design-gated together (§Design gates).
398:- **Variant A fold-in not wireable verbatim (round-4 H4).** The EDITOR (`AiProviderEditSheet`) is reused verbatim (a); the scoped LIST is a NEW `ReaderAiProvidersList` over the shared `AiSettingsViewModel` state reproducing the designed `‹ Bilingual` nav + bilingual empty state + checked-active row + tap-to-select (b); a save-result seam returns the saved ID (which `AiProviderStore.upsert` already produces, AiProviderStore.kt:58/84) so `setActive(savedId)` + pop-on-success is deterministic and race-free (c). No "reuse `AiProviderListScreen` verbatim" claim remains anywhere.
405:- **Migration schema drift (gap A).** `MIGRATION_8_9`'s exact DDL is authored in §2 and validated against Room's GENERATED `9.json` schema (not a hand-written approximation) by the extended `VReaderDatabaseMigrationTest` opening the real Room DB — the recurring Android migration failure mode (cf. #135's stale-version finding).
406:- **Backup `bilingualGranularity` cross-platform parity UNCONFIRMED (gap B).** The backup-contract `bilingualGranularity` field's cross-platform conformance vector + iOS parity are UNCONFIRMED. Safe for v1 (backup collect/restore is descoped / device-local — §7), but flagged as a follow-up: **when the backup-wiring WI lands, add a conformance vector under `contracts/vectors/` and confirm iOS parity before shipping backup of the field.**
410:- **Dependency honesty (round-3 Medium-4 — CONFIRMED RESOLVED).** WI-4b (DI, incl. `AiProviderStore` in `AppContainer`) is foundational and gates the production run-through of WI-6/WI-7b/WI-AIP/WI-8; those WIs' unit/Compose gates proceed against injected fakes, and WI-4b is sequenced before them. No external feature gates the chain (#136 closed).
414:- **Room migration additive.** New `chapter_translations` (FK CASCADE, `lookupKey` PK, `sourceParagraphCount`, all columns `NOT NULL`). Existing rows untouched. Against this checkout **8→9, `MIGRATION_8_9`** with the **exact DDL in §2** appended after `MIGRATION_7_8` (VReaderDatabase.kt:224–228); the migration test extended from v8 validates it against Room's generated `9.json` schema (gap A).
416:- **`AppContainer` gains `AiProviderStore`** (previously not provided — VReaderApp.kt:64/66 comment only) plus the bilingual services + `AiSettingsViewModel` factory; all additive lazy singletons following the `readerSettingsStore` pattern. #118 AI files are consumed unchanged **except** the additive save-result seam on `AiSettingsViewModel.save()` (returns the saved ID — round-4 H4c; the underlying `AiProviderStore.upsert` already returns the saved profile, so this exposes existing information without changing persistence behavior).
418:- **Backup contract already compatible** — `PerBookSettingsOverride.bilingualEnabled/TargetLanguage/Granularity` exist (no `bilingualStyle`), no translation-cache backup section (device-local, re-derivable). #131 writes the three fields locally; backup collect/restore is a small additive follow-up (no contract change), out of v1; config device-local until then. **`bilingualGranularity` cross-platform conformance vector + iOS parity are UNCONFIRMED (gap B) — a follow-up when the backup-wiring WI lands: add a `contracts/vectors/` conformance vector + confirm iOS parity before shipping backup of the field.**
424:2. **`Design needed: sentence-granularity bilingual interlinear — BOTH the setup-sheet Sentence control AND its render — for feature #131`** (round-4 H3 — broadened to cover both, filed together) — `vreader-bilingual.jsx` `BilingualPageContent` (lines ~195–277) depicts ONLY paragraph interlinear (one translation `<p>` per source paragraph), and a translation-after-each-sentence render (grouped when several sentences share a line-chunk) is depicted nowhere; the Sentence option appears only in the setup control (`vreader-bilingual.jsx:77`) with no matching renderer. v1 ships the depicted **paragraph** interlinear render + a **Paragraph-only** setup-sheet Granularity control; **Sentence is descoped from BOTH the control and the render in v1** (no undesigned surface, no paragraph-content-under-a-sentence-key). `TranslationGranularity.sentence` + `ChapterSegmenter.sentenceRanges` remain reserved-foundational code (WI-1). When the sentence-interlinear render (and its control option) is designed, it is a render-only follow-up (the one-lazy-item-per-chunk `Column` contract already accommodates several stacked sentence translation children per anchor chunk). The box-D Sentence gap is tracked by the WI-9 follow-up checklist amendment.
426:*(REMOVED in v4: the v3 "#136 dependency" design-gate line — #136 is closed and the Variant A AI Providers sheet IS the committed design, reproduced by WI-AIP, not a gate.)*
432:- v3 (2026-07-12): Gate-2 round-2 findings resolved — TXT/MD document-global segment model (H1); EPUB translatePreSegmented + count-keyed cache + direct-block prefetch (H2); #136 AI-provider-reachability spun out as a hard dependency (GH #1976) + Style descoped v1 (H3); WI-0 go/no-go + navigator-race contract (M1); EPUB DOM-injection adapter not Compose body (M2); DI/factory WI reordered (M3); Room 8→9 MIGRATION_8_9 (M4); deps/WI-count corrected (L1/L2). Gate-2 round-3 = block-recommended.
433:- v4 (2026-07-12): Gate-2 round-3 (block-recommended) findings resolved AND the AI-config path folded in — AI-config FOLDED IN (#136 CLOSED); WI-AIP added; WI-4b provides `AiProviderStore` into `AppContainer`; H1 final-chunk math; H2 additive-item render contract; M1 EPUB single-owner; M2 dual-cancellation + single-flight; M3 blank-model fallback; M4 dependency honesty; WI count corrected to 13; chunk semantics corrected. Gate-2 round-4 = block-recommended.
435:  - **H1 (round-4 High-1) — `Utf16Span` value type:** the final-chunk MATH stays (confirmed correct); the ONLY problem was the type contradiction — v4 declared `paragraphRanges`/`sentenceRanges` as `List<IntRange>` while treating them half-open, but Kotlin `IntRange` is inclusive-inclusive. Replaced `IntRange` EVERYWHERE with a dedicated `Utf16Span(start, endExclusive)` value type (NEW file `bilingual/Utf16Span.kt`, rides WI-1). `ChapterSegmenter.paragraphRanges`/`sentenceRanges` return `List<Utf16Span>`; `TxtChapterTextProvider` + the render path consume `Utf16Span`. Updated §2 H1, the segmenter/provider file entries, WI-1, and every test-catalogue "half-open UTF-16 (start,endExclusive)" mention.
436:  - **H2 (round-4 High-2) — one-lazy-item-per-chunk `Column` (THE key fix):** the v4 "separate additive `LazyColumn` items after the anchor chunk" contract is NOT implementable — the live reader treats lazy-item indices AS `TxtDocument` chunk indices (position-save via `offsetForChunk(firstVisibleItemIndex)`, TxtReaderActivity.kt:220/473/623; every bookmark/annotation/search/scrubber/TTS jump via `scrollToItem(chunkForOffset(...))`, :411/:421/:454/:481/:257; TTS visibility via `visibleItemsInfo.index == spokenChunk`, :256), so inserting separate translation items shifts every following lazy index and corrupts all of these. New binding contract: keep EXACTLY ONE lazy item per chunk (the `items(count=chunkCount, key={it})` loop + keys UNCHANGED → lazy-index==chunk-index preserved); INSIDE each item wrap the content in a `Column` — the UNCHANGED source `Text` (one `TextLayoutResult`, one `registerChunk(i)`) then the muted non-registered translation child(ren) anchored to chunk `i`. ADDED explicit translation **gesture exclusion** (TxtSelectionController.hitAt falls back to the nearest source chunk when the pointer is past source bounds, :47–53, so omitting `registerChunk` is not enough). Updated §2 H2, the `BilingualInterlinearBody` file entry, the rejected-alternatives list (added the separate-lazy-items rejection), WI-7a, WI-8, and the enabled-mode tests (position-save round-trips to the same chunk; jumps/TTS land on the correct chunk; long-press on translation does NOT select).
437:  - **H3 (round-4 High-3) — Paragraph-only v1 granularity:** v4's "Sentence selectable + sentence cache identity active + paragraph-render fallback" was underspecified (no sentence→paragraph aggregation) and would render undesigned sentence items or serve paragraph content under a sentence key. Resolution: v1 segments + caches + renders **Paragraph ONLY**. `TranslationGranularity` + `ChapterSegmenter.sentenceRanges` stay as reserved-foundational code (WI-1, unit-tested) but the v1 render/cache/VM/setup-sheet path is paragraph-exclusive (`promptVersion` `g=paragraph` always; no `sentenceRanges` in the v1 render path; the setup-sheet Granularity control is Paragraph-only). Broadened the sentence design gate to cover BOTH the control option AND its render (filed together). Updated §2 H2 granularity subsection, the cache-identity section, WI-5/WI-7a, and the tests.
438:  - **H4 (round-4 High-4) — WI-AIP editor-verbatim + new scoped list + save-result seam:** `AiProviderListScreen` owns its own `NavScreen`/chrome + generic empty state + row-tap-as-EDIT (AiProviderListScreen.kt:45/59/84/101/105), so it CANNOT be reused verbatim to reproduce the designed `‹ Bilingual` nav + bilingual empty state + checked-active row + tap-to-SELECT; AND `AiSettingsViewModel.save()` returns no ID and upserts async (:85–97), so a verbatim reuse can't deterministically `setActive(savedId)` + pop-on-success without racing the upsert. Resolution: (a) reuse the EDITOR (`AiProviderEditSheet`) VERBATIM; (b) the scoped LIST is a NEW `ReaderAiProvidersList` over the SHARED `AiSettingsViewModel` state reproducing the designed nav/empty-state/checked-row/tap-to-select; (c) an additive **save-result seam** on `save()` returning the saved provider ID (which `AiProviderStore.upsert` already produces, AiProviderStore.kt:58/84 — the #118 VM is production-unwired, wired for the first time here, so the seam is safe). Removed every "reuse `AiProviderListScreen` VERBATIM" claim. Updated the `ReaderAiProvidersSheet` file entry, §AI-config reachability, the rejected-alternatives list, WI-AIP, and its tests.
439:  - **Gap A (workflow completeness) — MIGRATION_8_9 exact DDL:** authored the exact `CREATE TABLE chapter_translations (...)` DDL (all `NOT NULL` columns + PK `lookupKey` + `index_chapter_translations_bookKey` + FK→`books(fingerprintKey)` ON DELETE CASCADE, modeled on the verified `MIGRATION_6_7` shape) in §2/WI-2 as a build-time contract, and required the migration test to validate it against Room's GENERATED `9.json` schema (not a hand-written approximation — cf. #135's stale-version finding).
440:  - **Gap B (workflow completeness) — backup granularity parity flag:** flagged (§6 Risks + §7 Backward compat) that the backup-contract `bilingualGranularity` field's cross-platform conformance vector + iOS parity are UNCONFIRMED — safe for v1 (backup collect/restore descoped / device-local), but a follow-up: when the backup-wiring WI lands, add a `contracts/vectors/` conformance vector + confirm iOS parity before shipping backup of the field.
441:  - WI count UNCHANGED at **13** (`Utf16Span` rides WI-1). Awaiting Gate-2 round-5 audit.

exec
/bin/zsh -lc "nl -ba dev-docs/plans/20260710-feature-131-android-bilingual-interlinear.md | sed -n '45,125p;130,215p;238,270p;350,390p;393,425p'" in /Users/ll/workspace/vreader
 succeeded in 0ms:
    45	- The old v3 claim "a chunk can hold multiple **paragraphs**" is **WRONG and removed.** (A single chunk cannot straddle a line terminator, and paragraph boundaries are blank lines, i.e. chunk boundaries — so a chunk holds *part of one* paragraph, never a whole extra paragraph.)
    46	
    47	**v5 model — document-global units with segment spans produced ONCE:**
    48	
    49	- The whole `.txt`/`.md` is treated as **one translation document**. The **segmenter runs once over `TxtDocument.text`** (the full raw backing string) and emits, per segment, its **UTF-16 span as a `Utf16Span(start, endExclusive)`** (half-open) against that same backing string (the segmenter's `paragraphRanges(text): List<Utf16Span>` / `sentenceRanges(text): List<Utf16Span>` — the span-returning peers of `paragraphs`/`sentences`; iOS precedent `ChapterSegmenter.sentenceRanges(in:)` at `ChapterSegmenter.swift:78`, returns `[Range<Int>]`). These spans are the SINGLE source of truth used by BOTH the translate side and the render side, so the two segment identically **by construction** (they read the same array). Spans are stored/compared as the explicit `Utf16Span` value type (see the H1 fix below), NOT re-derived on the render side.
    50	- **Unit granularity for TXT/MD is the whole document, sub-batched for cache/prefetch by a deterministic "unit window."** To avoid translating a 14 MB book at once (and to keep cache rows bounded), segment spans are grouped into fixed **unit windows** of contiguous segments (window size a build-time constant; it does not change the 1:1 contract). Each window is a `TranslationUnitId(kind = txtDocSegmentWindow, value = windowIndex)` — a document-global index, NOT a chunk index. `unitContaining(charOffsetUTF16)` maps the reader's saved offset → the segment whose span contains it → its window index (via a precomputed segment-start binary search, the same shape as `TxtDocument.chunkForOffset`, TxtDocument.kt:23–33). `unitAfter(unit)` = next window index or null at document end.
    51	
    52	#### H1 fix (round-3 High-1 math + round-4 High-1 type) — final-chunk source span + the `Utf16Span` value type (BINDING)
    53	
    54	**The math (round-3 High-1 — CONFIRMED correct by round-4, UNCHANGED):** `offsetForChunk()` **CLAMPS** an out-of-range index to the last valid chunk (`starts[index.coerceIn(0, starts.size - 1)]`, TxtDocument.kt:17–20). So for the LAST chunk `i`, `offsetForChunk(i + 1) == offsetForChunk(i)` → an **empty span** → a one-chunk document drops EVERY translation and a paragraph ending in the final chunk drops its sole translation. `textForChunk()` avoids this by using `text.length` for the final end (TxtDocument.kt:39). The render side MUST do the same. **Binding rule:**
    55	
    56	```
    57	val endExclusive = if (i + 1 < document.chunkCount) document.offsetForChunk(i + 1) else document.text.length
    58	// chunk i source span is the HALF-OPEN Utf16Span(document.offsetForChunk(i), endExclusive)
    59	```
    60	
    61	**The type (round-4 High-1 — THE fix this round):** v4 declared `paragraphRanges`/`sentenceRanges` as `List<IntRange>` while treating them as half-open `[start, endExclusive)`. That is a **type contradiction** — Kotlin `IntRange` is inclusive-inclusive (`range.last` is the last *included* index, and `range.last` for an empty/at-EOF span is a footgun). The half-open contract and the `IntRange` type are incompatible. **Resolution — a dedicated value type, replacing `IntRange` EVERYWHERE:**
    62	
    63	```
    64	// bilingual/Utf16Span.kt  (NEW FILE — rides WI-1)
    65	data class Utf16Span(val start: Int, val endExclusive: Int) {
    66	    init { require(endExclusive >= start) }
    67	    val isEmpty: Boolean get() = endExclusive == start
    68	    val length: Int get() = endExclusive - start
    69	}
    70	```
    71	
    72	- `ChapterSegmenter.paragraphRanges(text): List<Utf16Span>` / `sentenceRanges(text): List<Utf16Span>` return `Utf16Span`s (half-open, against the input string). `TxtChapterTextProvider` and the TXT/MD render path consume `Utf16Span` — there is **no `IntRange`** anywhere in the segment/span contracts. (`TxtSelectionController`'s own `Utf16Range` type is a *separate*, unrelated selection type and is untouched — see H2's gesture-exclusion note.)
    73	- A segment's "end offset" for anchoring (below) is its `endExclusive`; the chunk that "contains a segment's end" is `document.chunkForOffset(span.endExclusive - 1)` when `!span.isEmpty`, clamped to `[0, chunkCount-1]` (an empty segment is dropped by the segmenter and never anchored).
    74	- **Tests (WI-1 / WI-4a / WI-8):** `paragraphRanges`/`sentenceRanges` return correct half-open `Utf16Span(start, endExclusive)` spans (unit — WI-1); one-chunk document (no trailing newline) → its single paragraph/sentence translation renders (not dropped); final-chunk anchor (a paragraph whose last line is the final chunk) → translation renders after the last chunk; exact-boundary (a segment ending exactly at a chunk `start`) → anchored to the correct chunk, not off-by-one; EOF anchor (`span.endExclusive == text.length`) → resolves to the last chunk, no clamp-collapse.
    75	
    76	#### H2 fix (round-3 High-2 layout/selection + round-4 High-2 lazy-index identity) — the enabled render contract (BINDING; preserves BOTH the per-chunk model AND lazy-index==chunk-index)
    77	
    78	**Live invariant #1 — per-chunk layout/selection (round-3 High-2, verified TxtReaderActivity.kt:1043–1085):** the TXT/MD body iterates `items(count = document.chunkCount, key = { it })` (TxtReaderActivity.kt:1043). For **each chunk `i`** it owns **exactly ONE `TextLayoutResult`** (`var layout by remember(i) { … }`, set in `onTextLayout`, TxtReaderActivity.kt:1059/1075) and **exactly ONE selection registration** (`selectionController.registerChunk(i, l, c)` / `unregisterChunk(i)`, TxtReaderActivity.kt:1062–1066). Highlights (`highlightSpan(i)`, :1047), annotation washes (`washesForChunk(i)`, :1058), the read-aloud span wash (`addStyle(SpanStyle(background = wash), …)`, :1050–1054), and selection accents (`selectionForChunk(i)` → `drawRangeFill`, :1069/1081) all key off that **per-chunk** layout and the chunk-local UTF-16 offsets. **Splitting a chunk's source `Text` into multiple `Text` nodes would break every one of these** (two `Text` nodes = two `TextLayoutResult`s = broken selection coordinates, misplaced highlight/wash/annotation ranges, a shifted read-aloud wash).
    79	
    80	**Live invariant #2 — lazy-index == chunk-index (round-4 High-2 — THE key fix this round; verified):** the live reader treats `LazyListState` item indices as `TxtDocument` chunk indices EVERYWHERE:
    81	- **Position save** converts `firstVisibleItemIndex` → offset via `offsetForChunk` (`savePosition(...) { val offset = document.offsetForChunk(topIndex) }`, TxtReaderActivity.kt:623–624), and the steady-state/onStop save both pass `listState.firstVisibleItemIndex` directly (TxtReaderActivity.kt:220–223, :227–230). Resume converts back via `chunkForOffset` (`initialFirstVisibleItemIndex = s.initialIndex`, :220; `s.initialIndex` = `document.chunkForOffset(offset)`, :619). The bottom-chrome progress fraction reads `document.offsetForChunk(listState.firstVisibleItemIndex)` (:473).
    82	- **Bookmark / annotation / search / scrubber / TTS jumps** all call `listState.scrollToItem(document.chunkForOffset(target))` (bookmark :411, annotation :421, search :454, scrubber :481; TTS auto-scroll `animateScrollToItem(spokenChunk)` where `spokenChunk = document.chunkForOffset(tts.charStart)` — :252/:257).
    83	- **TTS visibility** compares lazy-item indices with the chunk directly: `listState.layoutInfo.visibleItemsInfo.none { it.index == spokenChunk }` (:256).
    84	
    85	**Therefore inserting SEPARATE translation `LazyColumn` items (the v4 "additive items after the anchor chunk" contract) is NOT implementable:** every separate translation item inserted before a given source chunk shifts that chunk's lazy index, so `offsetForChunk(firstVisibleItemIndex)` reads the wrong chunk's offset (corrupts position save + progress), `scrollToItem(chunkForOffset(target))` lands on the wrong item (corrupts every jump), and `visibleItemsInfo.index == spokenChunk` never matches (corrupts TTS auto-scroll). The v4 contract is **rejected**.
    86	
    87	**v5 binding render contract (one lazy item per chunk — a wrapping `Column`):**
    88	
    89	> **Keep EXACTLY ONE lazy item per chunk.** The existing `items(count = document.chunkCount, key = { it })` loop is **UNCHANGED** — so lazy-index == chunk-index is preserved and NO position/jump/TTS consumer breaks. INSIDE each item's lambda, wrap the content in a `Column`:
    90	> 1. the **UNCHANGED source `Text`** — one `TextLayoutResult`, one `registerChunk(i, …)`/`unregisterChunk(i)`, byte-identical to today (the exact code at TxtReaderActivity.kt:1044–1084 is unchanged, now nested in a `Column`);
    91	> 2. **below it, still inside the SAME lazy item**, the translation(s) **anchored** to chunk `i` (`chunkForOffset(span.endExclusive - 1) == i`) as **muted, non-registered** `Text`(s) (accent left-border, `fontSize*0.88`, CJK/RTL styling per `BilingualPageContent`).
    92	
    93	A paragraph spanning chunks `j..i` renders its ONE translation inside chunk `i`'s `Column` (after the paragraph's last source line). This preserves BOTH invariants: the per-chunk one-layout/one-registration model (the source `Text` is never split, the translation is a *sibling* `Text` in the `Column`, not a re-layout of the source) AND the lazy-index↔chunk-index identity (the translation lives inside the anchor's lazy item, adds no lazy item, shifts no index).
    94	
    95	Concretely the body becomes, per chunk `i` (in the same single `items(count = document.chunkCount, key = { it })` loop):
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
   106	- **Enabled-mode tests (WI-8 connected + WI-7a Compose, BINDING):** with bilingual ON —
   107	  - (a) each source chunk's **selection registration is UNCHANGED** (same `registerChunk(i, …)` count and coordinates as OFF; a translation child registers nothing);
   108	  - (b) **highlights/annotation washes/read-aloud wash still key off the source chunks** at the correct offsets (a translation child in the anchor's `Column` does not shift them);
   109	  - (c) **lazy-index == chunk-index preserved:** with bilingual ON — **position-save round-trips to the same chunk** (`offsetForChunk(firstVisibleItemIndex)` → save → reopen → `chunkForOffset(offset)` lands on the same chunk); **bookmark/annotation/search/scrubber jumps land on the correct chunk** (`scrollToItem(chunkForOffset(target))` scrolls to the right item); **TTS auto-scroll targets the correct chunk** (`visibleItemsInfo.index == spokenChunk` matches); (assert these are identical to the OFF baseline — no lazy index shift);
   110	  - (d) a **long-press on translation text does NOT select** (gesture exclusion — the nearest-source-chunk fallback is not reached);
   111	  - (e) a **translation child is non-selectable** and does not perturb source offsets (selecting across the source/translation boundary selects source only);
   112	  - (f) **MD source mapping** — the markdown renderer (`mapper.renderedText(i)`, TxtReaderActivity.kt:1049) still owns the source chunk render; the translation child is plain muted text;
   113	  - (g) **paragraph-spanning-many-chunks** renders exactly ONE translation (inside the paragraph's last chunk's `Column`), never per-line;
   114	  - (h) final-chunk/one-chunk anchors render (H1).
   115	
   116	- **Granularity — Paragraph ONLY in v1 (round-4 High-3):** `vreader-bilingual.jsx` `BilingualPageContent` (lines ~195–277) is a **paragraph-interlinear** renderer: it maps `page.paragraphs.map(...)` and renders **one source `<p>` followed by ONE translation `<p>`** per paragraph. **Sentence-granularity interlinear is depicted NOWHERE** — Sentence appears ONLY as an option in the `BilingualSetupSheet` Granularity segmented control (`vreader-bilingual.jsx:77`), never in the renderer, AND v4's "Sentence selectable + sentence cache identity active + paragraph-render fallback" was underspecified (no defined sentence→paragraph aggregation, so it would either render undesigned sentence items or serve paragraph content under a sentence cache key). **Resolution — v1 segments + caches + renders Paragraph ONLY:**
   117	  - The `TranslationGranularity` enum + `ChapterSegmenter.sentenceRanges` API **stay as reserved FOUNDATIONAL code** (WI-1, with unit tests) so the future sentence-render is a render-only follow-up.
   118	  - The v1 **render/cache/VM/setup-sheet path uses paragraph exclusively:** `promptVersion`'s granularity component is **always `paragraph` in v1**; there is **no `sentenceRanges` in the v1 render path**; the setup sheet's Granularity control is **descoped to Paragraph-only in v1** (a documented divergence, tracked by the sentence design gate below — the same treatment as the Style descope).
   119	  - This keeps rule 51 (implement only what is depicted — paragraph interlinear) while shipping the depicted paragraph parity. The one-lazy-item-per-chunk `Column` render contract already accommodates a future per-line sentence grouping (several translation children stacked in one chunk's `Column`), so the sentence gate, once designed, is render-only.
   120	
   121	- **MD source** = raw markdown segment text (translation renders as plain muted text, not re-markdown-rendered — matches the muted-secondary design line). Segmentation runs over the raw markdown string; MD markers are treated as ordinary characters by the paragraph splitter (blank-line delimited), consistent with `TxtMdTextExtractor` shipping raw markdown to search.
   122	
   123	This closes round-3 H1 (no dropped final-chunk translations), round-3 H2 (per-chunk layout/selection preserved; source `Text` never split), round-4 H1 (the `Utf16Span` type replaces the incompatible `IntRange`), round-4 H2 (one lazy item per chunk preserves lazy-index==chunk-index; translation gesture exclusion), round-4 H3 (Paragraph-only v1 granularity), and round-3 Low-2 (correct chunk semantics).
   124	
   125	### AI-config reachability — FOLDED IN (#136 CLOSED; Variant A owned by #131)
   130	
   131	**Navigation model (reproduced EXACTLY from `reader-ai-provider-entry.md`:110–134, invent nothing):**
   132	
   133	```
   134	More ▸ Bilingual mode (first toggle on)
   135	  └─ BilingualSetupSheet   [bottom sheet]
   136	       engine strip: "No AI provider configured"  [ Set up ]
   137	                             │  onOpenSettings
   138	                             ▼  (push, slide-left, same sheet frame)
   139	     ReaderAiProvidersSheet  [nav bar: ‹ Bilingual · "AI Providers"]
   140	       ├─ empty  → [ Add provider ] ─┐
   141	       └─ list   → tap a row SELECTS it (setActive) │  (present the canonical editor, full height)
   142	                             ▼        ▼
   143	                    AiProviderEditSheet   [reused VERBATIM from #118]
   144	                             │  Save
   145	                             ▼  (saved provider becomes the bilingual engine,
   146	                                  pop the whole stack)
   147	     BilingualSetupSheet  ← engine strip now "Claude · configured" / Change…
   148	```
   149	
   150	- **`‹ Bilingual` without adding** returns to the bilingual sheet **still unconfigured — no state mutated.**
   151	- **"Change…"** (already-configured strip) opens the **SAME** `ReaderAiProvidersSheet`, populated, **current provider checked**; tapping a row **selects** it (`setActive`).
   152	- The AI Providers view is a **push within the bilingual sheet**, NOT a modal over the reader and NOT the full app Settings.
   153	
   154	**Android readiness gate (BINDING — round-3/round-2 H3 + the #136-audit High-3 lesson; round-4 CONFIRMED correct, UNCHANGED):** `aiConfigured` on the engine strip is derived by `BilingualAiReadiness.resolve(snapshot)` = **an ACTIVE profile exists AND its API key decrypts to non-empty.** Deriving from `profiles.isEmpty()` alone is **WRONG**: the store keeps a separate `activeId` that can be **null with profiles present** (`AiProviderSnapshot.active = profiles.firstOrNull { it.id == activeId }`, AiProviderStore.kt:34–36), and key usability depends on **decrypting the active profile's token** (`apiKey(profile) = cipher.decrypt(profile.encryptedApiKey)`, AiProviderStore.kt:108). A cipher/keystore failure maps to **not-ready, never a crash** (the resolve wraps the decrypt in `runCatching`). **Note:** the iOS Variant A design-note (`reader-ai-provider-entry.md:172–174`) derives `aiConfigured` from `providers.isEmpty == false`, and iOS #82 (`reader-ai-readiness.md`) adds a 4-gate readiness (flag + consent + provider + key). **Android has NO consent manager and NO feature flag** (#118 has neither — confirm during build); the Android gate is exactly what #118 enforces = **provider (active) + key (decrypts non-empty)**. We do NOT invent a consent/flag gate.
   155	
   156	### New files
   157	
   158	**Pipeline / domain (host-agnostic, pure or coroutine — JVM-testable):**
   159	
   160	- `bilingual/Utf16Span.kt` — **NEW (round-4 H1).** `data class Utf16Span(val start: Int, val endExclusive: Int)` (half-open UTF-16 span; `require(endExclusive >= start)`; `isEmpty`, `length`). The single span type shared by the segmenter and the TXT/MD render path, replacing the incompatible `IntRange`. Rides WI-1. (Distinct from `TxtSelectionController.Utf16Range`, the selection type, which is untouched.)
   161	- `bilingual/TranslationUnitId.kt` — `data class TranslationUnitId(kind, value)` with `enum Kind { epubHref, foliateHref, txtDocSegmentWindow, mdDocSegmentWindow, pdfPageRange }`; `storageKey = "${kind.name}:$value"`. TXT/MD kinds are **document-global segment-window indices** (H1), NOT chunk indices. v5 uses `epubHref` + `txtDocSegmentWindow`/`mdDocSegmentWindow`; others reserved so the cache-key format never breaks. *(Assumption: iOS's exact Kind case names for the TXT/MD variants; only the `storageKey` string format is load-bearing for the cache contract, and that is preserved.)*
   162	- `bilingual/TranslationGranularity.kt` — `enum { paragraph, sentence }`. **Reserved foundational code** (WI-1, unit-tested); the v1 render/cache/VM/setup-sheet path uses `paragraph` exclusively (round-4 H3). `sentence` is design-gated.
   163	- `bilingual/BilingualLanguages.kt` — `BilingualLanguage(key, glyph, script)`; `BILINGUAL_LANGS` = the exact set from `vreader-bilingual.jsx:15–25` (Chinese/Japanese/Korean cjk, Spanish/French/German/Italian latin, Arabic rtl, Russian cyrillic) + `findOrDefault(key)`. Default `Chinese`.
   164	- `bilingual/ChapterSegmenter.kt` — **NEW file (no existing Android segmenter — verified).** Port of iOS `ChapterSegmenter`: `paragraphs(text)` / `sentences(text)` **plus the span-returning peers `paragraphRanges(text): List<Utf16Span>` / `sentenceRanges(text): List<Utf16Span>`** (half-open UTF-16 spans against the input string, as `Utf16Span` — round-4 H1; iOS `sentenceRanges(in:)` precedent). CJK-aware sentence enumeration (`。！？` vs Latin). Pure. (`sentenceRanges` is reserved-foundational; the v1 render path calls only `paragraphRanges` — round-4 H3.)
   165	- `bilingual/TranslationChunker.kt` — `chunk(segments, maxCharsPerChunk)` + `subSplit(text, maxChars)`. Port of iOS `ChapterTranslationChunker.chunk(...)` (`ChapterTranslationChunker.swift:85`) + `subSplit(...)` (returns index groups, oversize segment gets its own chunk; `subSplit` is the Bug #330 grapheme-safe over-budget splitter).
   166	- `bilingual/TranslationChunkContract.kt` — `userPrompt(segments, targetLanguage)`; `decode(raw, expectedCount)` (strict JSON-array + code-fence strip); `sealed class DecodeError { NotAStringArray; CountMismatch(expected, actual) }`. Port of iOS `TranslationChunkContract` (`TranslationChunkContract.swift:24`). No `style` param — Style descoped v1 (§3).
   167	- `bilingual/ChapterTextProvider.kt` — `interface { units(); sourceSegments(unit); sourceText(unit); unitContaining(charOffsetUTF16); unitAfter(unit) }`. `sourceSegments(unit)` returns the exact segment strings (from the shared span array). Resolution is host-specific: TXT/MD key on `charOffsetUTF16` → segment-window; EPUB keys on the current-resource `href`. Honest divergence from iOS's uniform Readium `Locator`, documented.
   168	- `bilingual/TxtChapterTextProvider.kt` — provider over `TxtDocument` + the segmenter's `Utf16Span` array (H1). Builds the document-global segment `Utf16Span`s once (via `paragraphRanges` — paragraph only in v1), groups them into windows, resolves `unitContaining` via a segment-start binary search over `charOffsetUTF16`. MD source = raw markdown segment text.
   169	- `bilingual/EpubChapterTextProvider.kt` (WI-0-gated shape) — provider over the Readium `Publication` reading order; `units()` = spine hrefs, `unitContaining` = the locator's href (from `EpubNavigatorFragment.getCurrentLocator()`), `sourceSegments(unit)` = the DOM-enumerated block texts (the render's OWN enumeration, for direct-block 1:1 — H2). Its render-side collaborator is `EpubBilingualJs`.
   170	- `bilingual/ChapterTranslationError.kt` — `sealed { Offline; TimedOut; ProviderFailed(msg); Cancelled }`. Maps from `AiError` (verified cases `Auth401`, `RateLimited429`, `Offline`, `Timeout`, `Http(code)`, `Decode`, `Stream`, `InsecureUrl`, `Config`, AiTypes.kt).
   171	- `bilingual/ChapterTranslationService.kt` — the iOS-parity service (full divergence-recovery surface, round-2 H2):
   172	  - `cachedTranslation(bookKey, unit, sourceText, targetLanguage, granularity, acceptCountMismatch=false)` — cache-only; serves a row only when `sourceParagraphCount == segments.size` (or `acceptCountMismatch`). No provider (#306 parity).
   173	  - `cachedTranslation(bookKey, unit, expectedSegmentCount, targetLanguage)` — the divergence-fallback cache-only restore (iOS Bug #343): serves the canonical row only when its STORED `sourceParagraphCount == expectedSegmentCount`. Needs no source text and no provider → a cache-hit toggle/reopen restores with **zero provider calls**.
   174	  - `translate(bookKey, unit, sourceText, targetLanguage, providerProfile, granularity, bypassCacheRead=false)` — segment → chunk → per-chunk `AiClient.chat` one-shot → `decode` → per-segment fallback → per-chunk graceful degrade (Bug #330) → cache-write only on full success (`sourceParagraphCount = segments.size`). **Cancellation:** maps BOTH native `CancellationException` AND typed `ChapterTranslationError.Cancelled` to `Cancelled` (mirrors iOS `ChapterTranslationService.swift:359–364`); `ensureActive()` between chunks AND immediately before the Room write.
   175	  - `translatePreSegmented(bookKey, unit, segments, targetLanguage, providerProfile)` — the count-divergence recovery (iOS Bugs #268/#330/#343). Takes the render's OWN enumerated block texts as `segments` (1:1), chunks them, translates with the same per-chunk graceful-degrade + dual-cancellation contract, and — on full success only — caches under the canonical key with the ENUMERATE's count as `sourceParagraphCount`. A partial degrade is NOT cached; a cache-write failure does not fail the translation (iOS `ChapterTranslationService.swift:374–384`).
   176	  - Uses `AiClient.chat(AiRequest)` (one-shot, verified — NOT `streamChat`).
   177	- `bilingual/ChapterTranslationPrefetcher.kt` — resolves the active profile from one `AiProviderStore.snapshot()` (`snapshot.active`), decrypts via `store.apiKey(profile)` (snapshot-consistent, AiProviderStore.kt:108), builds an `AiClient` via an **injected factory param** (below), cache-first then translate. Adds the direct-block peers (H2):
   178	  - `prefetch(unit)` — the plain-text path.
   179	  - `prefetchDirect(unit, sourceSegments, targetLanguage)` — the divergence path (iOS `translatedSegmentsDirect`, `ChapterTranslationPrefetcher.swift:197`).
   180	  - `cachedDirect(unit, expectedCount, targetLanguage)` — the **zero-provider cache-only restore** (iOS `cachedSegmentsDirect` → `cachedTranslation(expectedSegmentCount:)`, `ChapterTranslationPrefetcher.swift:236`): returns a cached translation on a hit WITHOUT requiring an active provider (#306 pre-gate precedent). Backs the EPUB cache-restore path.
   181	  - **`AiRequest` construction (round-3 M3 fix, BINDING; round-4 CONFIRMED correct):** `model = profile.model.ifBlank { profile.kind.defaultModel }` — matches `AiChatViewModel.kt:61`; both wire clients serialize `request.model` **directly** (`put("model", request.model)` in `OpenAiCompatibleProvider.kt:38` and `AnthropicProvider.kt:36`), so a blank `profile.model` would send an empty model. Full request: `AiRequest(model = profile.model.ifBlank { profile.kind.defaultModel }, messages = …, temperature = profile.temperature, maxTokens = profile.maxTokens, system = …)`. A **blank-model regression test** asserts the fallback is applied.
   182	  - Throws `ChapterTranslationError`. Mirrors iOS `ChapterTranslationPrefetcher`.
   183	- `bilingual/BilingualAiReadiness.kt` — `resolve(snapshot: AiProviderSnapshot): Boolean` — active profile exists (`snapshot.active != null`) AND `runCatching { store.apiKey(snapshot.active).isNotEmpty() }.getOrDefault(false)` (cipher/decryption failure → **not-ready**, never crashes). Drives the setup-sheet engine-strip configured/unconfigured state. Exactly the #118 gate (no consent manager / feature flag on Android — confirm during build).
   184	
   185	**State / persistence:**
   186	
   187	- `bilingual/PerBookBilingualStore.kt` — DataStore-Preferences, keyed by `bookFingerprintKey`, holding `{ enabled, targetLanguage, granularity }` (`granularity` is persisted but pinned to `paragraph` in v1 — round-4 H3). The Android `PerBookSettingsOverride` bilingual slice — the backup contract declares exactly `bilingualEnabled` / `bilingualTargetLanguage` / `bilingualGranularity` and **NO `bilingualStyle`** (verified). Wiring into backup collect/restore is scoped OUT (§7); until then bilingual config is device-local.
   188	- `bilingual/BilingualViewModel.kt` — `StateFlow<BilingualUiState>` with `enabled`, `targetLanguage`, `granularity`, `needsSetupSheet`, `aiConfigured`, `translationsByUnit`, `inFlightUnits`, `unavailableUnits`, `errorUnit`. Setters + `dismissSetupSheet`, `onPositionChanged(charOffsetUTF16)`, `retryUnit(unit)`, and the EPUB direct-block entry `onEpubBlocksEnumerated(unit, blocks)` (M1, below). Generation/epoch-guarded prefetch (current + next unit); a **per-unit single-flight job registry** (M2); dual-cancellation handling (M2). Port of iOS `BilingualReadingViewModel` (`prefetchTasks: [TranslationUnitID: Task]`, `BilingualReadingViewModel.swift:141`) + `+Prefetch`. Split to `BilingualPrefetchController.kt` if it nears ~300 lines. No `style` field.
   189	
   190	**Room (translation cache):**
   191	
   192	- `data/ChapterTranslationEntity.kt` — `@Entity(tableName="chapter_translations", indices=[Index("bookKey")], foreignKeys=[FK→books.fingerprintKey ON DELETE CASCADE])`. **`@PrimaryKey val lookupKey: String`** (Room requires a PK; project pattern `@PrimaryKey` + `@Upsert`, verified `BookEntity` `@PrimaryKey val fingerprintKey`, Entities.kt:24). `lookupKey` = `bookKey|unitStorageKey|targetLanguage|promptVersion`. Columns: `lookupKey` (PK), `bookKey`, `unitStorageKey`, `targetLanguage`, `promptVersion`, `translatedJson`, `sourceParagraphCount`, `createdAt`. Mirrors iOS `ChapterTranslationRecord.lookupKey` (`book|unit|lang|prompt`, profile-agnostic — Bug #342). `sourceParagraphCount` is load-bearing for H2 (stores the enumerate's count on the `translatePreSegmented` path so `cachedTranslation(expectedSegmentCount:)` restores). **The exact `MIGRATION_8_9` DDL is authored in WI-2 — see below.**
   193	- `data/ChapterTranslationDao.kt` — `getByLookupKey(key)`, `@Upsert suspend fun upsert(row)`, `deleteByLookupKey(key)`.
   194	- `bilingual/ChapterTranslationStore.kt` — coroutine wrapper returning a `CachedTranslation` (segments decoded from JSON), keeping Room entities off the boundary (iOS `ChapterTranslationStore` precedent).
   195	
   196	**Cache-identity (reconciled with iOS parity):** the 4-part key `book|unit|lang|promptVersion` is profile-AGNOSTIC / style-agnostic (Bug #342). Style is descoped (§3) so no `s=` component. **Granularity is paragraph-only in v1** (round-4 H3): `promptVersion = "bilingual-v1|g=paragraph"` in v1 (the `g=` component is always `paragraph`). The composite `g=` slot is retained in the key format so a future granularity is a different cache row by construction (closes the iOS #344 "sentence silently ignored" class ahead of time), but v1 never emits `g=sentence`. A language change cancels in-flight jobs, bumps the VM generation, clears shaped `translationsByUnit`, and forces a correctly-keyed re-fetch (WI-6).
   197	
   198	**DI / factory (verified live):** `AiProviderFactory` is an `object` with `create(profile, apiKey, dispatcher = Dispatchers.IO): AiClient` (verified, `AiProviderFactory.kt:10`). `ChapterTranslationPrefetcher` takes its OWN injected `clientFactory: (AiProviderProfile, String) -> AiClient` param **defaulting to `AiProviderFactory::create`**, overridden with a fake in tests.
   199	
   200	**UI (Compose — every state depicted, reproducing `vreader-bilingual.jsx` + `vreader-ai-provider-entry.jsx`):**
   201	
   202	- `bilingual/BilingualSetupSheet.kt` — reproduces `vreader-bilingual.jsx`'s `BilingualSetupSheet` (lines 27–156) EXACTLY, with the granularity divergence: header; a preview strip (`BilingualPreview`); a language grid over `BILINGUAL_LANGS` (glyph tiles, selected accent); a **Granularity** segmented control **descoped to Paragraph-only in v1** ("Translate after each ¶"; the Sentence option is not rendered in v1 — round-4 H3, tracked by the sentence design gate); a **Translation engine** strip (configured: "Claude · with this book's context" + "Change…"; unconfigured: "No AI provider configured" + "Bilingual mode needs an AI provider to translate." + "Set up"); the "Turn on bilingual mode" CTA. **No Style control, no provider/model card, no term-overrides toggle, no cost footer** (those belong to the `vreader-ai-android.jsx` sheet, not reproduced — §3). The `aiConfigured` flag comes from `BilingualAiReadiness.resolve`. The "Set up"/"Change…" CTA routes to `ReaderAiProvidersSheet` (wired in WI-9).
   203	- `bilingual/ReaderAiProvidersSheet.kt` — **NEW (folded in; the Android analog of iOS `ReaderAIProvidersView`; round-4 High-4 rewritten).** The Variant A scoped in-reader AI Providers sheet, reproducing `vreader-ai-provider-entry.jsx` `AIProvidersSheet` + `AIProvidersSheetBody` + `NavSheet` (nav bar `‹ Bilingual` leading + centered "AI Providers" title, `vreader-ai-provider-entry.jsx:247`). **Round-4 High-4: the fold-in CANNOT be "reuse `AiProviderListScreen` verbatim."** `AiProviderListScreen` owns its OWN full `NavScreen(title="AI Providers", onBack)` (`AiProviderListScreen.kt:59`), a generic `AiEmptyState` ("Connect an AI provider" / "One key unlocks…", :84/:87), and **row-tap-as-EDIT** (`ProviderRow` → `onEdit(p.id)`, :105) with **no checked-active-tap-to-select** — it cannot reproduce the designed reader-scoped `‹ Bilingual` nav, the bilingual-context empty state, the checked-active row, or tap-to-SELECT. So the fold-in splits into **(a)/(b)/(c)**:
   204	  - **(a) EDITOR reused VERBATIM.** `AiProviderEditSheet` (the canonical add/edit modal, Kind / Name / Endpoint / Sampling / API Key / Test Connection) is presented UNCHANGED from the #118 Library path — that reuse is confirmed fine (`reader-ai-provider-entry.md:49–52`, :63–65).
   205	  - **(b) The scoped LIST is a NEW reader-specific presentation** (`ReaderAiProvidersList`, in this file) built over the **SHARED `AiSettingsViewModel` state** (`listState`, verified `AiSettingsViewModel.kt:26`) + shared row/cell components, reproducing: the reader-scoped nav (`‹ Bilingual` back label, "AI Providers" title — `NavSheet` at jsx:247, NOT `AiProviderListScreen`'s own `NavScreen`); the **bilingual-context empty state** ("Choose the provider bilingual mode will use to translate this book." context strip + "No providers yet" + "Add provider" CTA — jsx:180–209); the **checked-active row** (`selected={p.id === selectedId}` — jsx:221; the live `AiProviderListState`/`AiProviderRow` already carries `active` per row, `AiSettingsViewModel.kt:30`); and **tap-to-SELECT** (`onSelect(p.id)` → `vm.setActive(id)` — jsx:221/237). It does **NOT** reuse `AiProviderListScreen`'s `NavScreen`/chrome/`AiEmptyState`/`ProviderRow`-tap-edit.
   206	  - **(c) A save-result seam** (round-4 High-4): `AiSettingsViewModel.save()` today returns Unit and upserts async (generates `s.id ?: UUID.randomUUID().toString()` *inside* the launched coroutine, then `_edit.value = null`, no saved ID — `AiSettingsViewModel.kt:85–97`), so WI-AIP cannot deterministically `setActive(savedId)` + pop-on-success by reusing it verbatim (popping immediately races the async upsert; observing list state can't distinguish the new profile). **Note:** `AiProviderStore.upsert` ALREADY returns the saved profile (`suspend fun upsert(...): AiProviderProfile`, "Returns the saved profile", `AiProviderStore.kt:58/70/84`) — the ID is present at the store layer; only the VM discards it. So the seam is an **additive completion/result signal on `AiSettingsViewModel.save()`** (or a thin WI-AIP wrapper) returning the saved provider ID (from `store.upsert(...).id`), so WI-AIP can `setActive(savedId)` + pop-on-success **after** the upsert commits — no race. The #118 VM is currently production-UNWIRED (only test-referenced — verified), and this feature wires it to production for the FIRST time, so an additive save-result seam is safe and appropriate.
   207	  - **Behavior per the nav model:** empty → "Add provider" → `AiProviderEditSheet` → Save → `save()` returns the saved ID → `store.setActive(savedId)` (first-provider-active is already the store's default `activeId = cur.activeId ?: id`, AiProviderStore.kt:81; the explicit `setActive(savedId)` guarantees the freshly-saved provider is the engine even if others existed) → **pop the whole stack** back to the bilingual sheet, engine strip now "Claude · configured / Change…". `‹ Bilingual` without adding → unconfigured, **no state mutated**. "Change…" → the SAME sheet, populated, current provider checked, tap a row → `setActive`. No consent card, no feature-flag toggle, no readiness tracker (iOS #82, deferred).
   208	- `bilingual/BilingualInterlinearBody.kt` — the Compose render surface for the **TXT/MD host ONLY** (round-2 M2). Renders per the **one-lazy-item-per-chunk `Column`** H2 render contract (source chunk unchanged as the first `Column` child; translation(s) anchored to chunk `i` as muted non-registered `Text` siblings in the SAME `Column`): muted `Text`, accent left-border, `fontSize*0.88`, CJK font for cjk scripts, RTL handling for Arabic (per `BilingualPageContent`, `vreader-bilingual.jsx:200–277`). Consumes the host-neutral `BilingualRenderState` DTO. Loading state ("Translating chapter… N%" + per-segment dim), error state ("Couldn't translate" + Retry), partial/offline (`unavailableUnits`): source-only silent fallback (iOS Decision 2). Includes the **translation gesture-exclusion** (round-4 H2) so a long-press on a translation child does not route to `hitAt`'s nearest-source-chunk fallback. **NOT the EPUB render surface.**
   209	- `bilingual/BilingualRenderState.kt` — the host-neutral state DTO shared by the Compose body and the EPUB adapter (round-2 M2): per-unit `{ segments: List<String>?, phase: Loaded|Loading(fraction)|Error|SourceOnly }`. Compose and EPUB share the state/value types, NOT the composable body.
   210	- `bilingual/EpubBilingualJs.kt` (WI-0-gated) — the EPUB render surface (round-2 M2). Pure Kotlin builder producing JS strings for `navigator.evaluateJavascript(...)`: `enumScript` (enumerate current-resource leaf blocks → JSON `[{id,text}]`), `injectScript(blockId, translationText)` (translation DOM node after the block; CSP-safe: `textContent`/`createTextNode`, never `innerHTML` string-concat; RTL/CJK via class + injected `<style>`), `clearScript()` (idempotent removal). Escaping done in Kotlin (JSON-encode every interpolated string). No Compose. Consumes `BilingualRenderState`.
   211	- `bilingual/EpubBilingualController.kt` (WI-0-gated) — **the single owner of EPUB units (M1, below).** The runtime actor that serializes enumerate→(cache-restore|translate)→inject/clear against the navigator using WI-0's chosen mechanism (a single mutex OR a monotonic navigator-session token); checks the session token after every suspended JS/AI call; clears BEFORE publication teardown; re-applies on the identified production re-apply signal.
   212	- `bilingual/BilingualPill.kt` — the `EN ↔ 中` reader-top-chrome pill (per `vreader-reader.jsx` + `vreader-bilingual.jsx` `BilingualPill`:282–305). Rendered by #132's top chrome; #131 provides the composable, #132's surface hosts it (§4).
   213	
   214	### EPUB direct-block flow — one owner + concrete API (round-3 Medium-1, BINDING; round-4 CONFIRMED RESOLVED — UNCHANGED)
   215	
   238	
   239	- **Dual-cancellation across the service/VM boundary:** both the service AND the VM handle **BOTH** native `CancellationException` **AND** the typed `ChapterTranslationError.Cancelled` **before** generic error mapping — matching iOS `ChapterTranslationService.swift:359–364` (which catches `is CancellationError` and `ChapterTranslationError.cancelled` separately, both re-throwing `cancelled`). A cancelled stale request MUST NOT surface as `errorUnit` (it is discarded).
   240	- **Per-unit single-flight job registry (VM):** a `prefetchTasks: MutableMap<TranslationUnitId, Job>` (iOS `prefetchTasks: [TranslationUnitID: Task]`, `BilingualReadingViewModel.swift:141`, cancelled/removed on disable/unit-change at :165). A NEW request for a unit **cancels-or-joins** the prior job (a stale prior is cancelled and awaited so it cannot run overlapping translations or Room writes), keyed by unit. Rapid retry/navigation cannot run overlapping translations for the same unit. `retryUnit(unit)` goes through the same registry. Tests: a mid-flight cancel discards (no `errorUnit`, no partial cache row); a rapid re-trigger for the same unit does not double-write.
   241	
   242	### Modified files
   243	
   244	- `data/VReaderDatabase.kt` — add `ChapterTranslationEntity` to `@Database entities`, bump `version` **8 → 9** (the live DB is v8, migrations `MIGRATION_1_2`..`MIGRATION_7_8`, `ALL_MIGRATIONS` ends at `MIGRATION_7_8` — verified VReaderDatabase.kt:29,224–228), add **`MIGRATION_8_9`** (exact DDL below — gap A), **append `MIGRATION_8_9` to `ALL_MIGRATIONS` after `MIGRATION_7_8`**, add `abstract fun chapterTranslationDao()`. Purely additive.
   245	
   246	  **`MIGRATION_8_9` exact DDL (gap A — BINDING; modeled on the verified `MIGRATION_6_7` `search_index_state` shape at VReaderDatabase.kt:154–169, whose DDL Room's PRAGMA validation already accepts):**
   247	
   248	  ```
   249	  val MIGRATION_8_9: Migration = object : Migration(8, 9) {
   250	      override fun migrate(db: SupportSQLiteDatabase) {
   251	          db.execSQL(
   252	              "CREATE TABLE IF NOT EXISTS `chapter_translations` (" +
   253	                  "`lookupKey` TEXT NOT NULL, " +
   254	                  "`bookKey` TEXT NOT NULL, " +
   255	                  "`unitStorageKey` TEXT NOT NULL, " +
   256	                  "`targetLanguage` TEXT NOT NULL, " +
   257	                  "`promptVersion` TEXT NOT NULL, " +
   258	                  "`translatedJson` TEXT NOT NULL, " +
   259	                  "`sourceParagraphCount` INTEGER NOT NULL, " +
   260	                  "`createdAt` INTEGER NOT NULL, " +
   261	                  "PRIMARY KEY(`lookupKey`), " +
   262	                  "FOREIGN KEY(`bookKey`) REFERENCES `books`(`fingerprintKey`) " +
   263	                  "ON UPDATE NO ACTION ON DELETE CASCADE )"
   264	          )
   265	          db.execSQL(
   266	              "CREATE INDEX IF NOT EXISTS `index_chapter_translations_bookKey` " +
   267	                  "ON `chapter_translations` (`bookKey`)"
   268	          )
   269	      }
   270	  }
   350	
   351	**WI-1 (foundational): value types + pure segmentation/chunk/contract.** **`Utf16Span` (round-4 H1 — the half-open span value type replacing `IntRange`)**, `TranslationUnitId`, `TranslationGranularity` (reserved; v1 uses `paragraph` only — round-4 H3), `BilingualLanguages`, **`ChapterSegmenter` (with `paragraphRanges`/`sentenceRanges` returning `List<Utf16Span>` — H1; `sentenceRanges` is reserved-foundational, not in the v1 render path — H3)**, `TranslationChunker`, `TranslationChunkContract` (no `style`), `ChapterTranslationError`. Pure; ported iOS vectors. Deps: none. Tests: `paragraphRanges`/`sentenceRanges` return correct half-open `Utf16Span(start, endExclusive)` spans (both APIs unit-tested even though only `paragraphRanges` ships in the v1 render path — `sentenceRanges` stays covered as reserved-foundational code); chunker packs-to-budget/oversize/empty; contract prompt/decode/fence/mismatch; error mapping.
   352	
   353	**WI-2 (foundational): Room translation cache.** `ChapterTranslationEntity` (PK = `lookupKey`, all-`NOT NULL` columns matching the DDL, `sourceParagraphCount` column) + `Dao` (`@Upsert`) + `ChapterTranslationStore`; `VReaderDatabase` **8→9 `MIGRATION_8_9`** with the **exact DDL authored in §2 (gap A)**, appended after `MIGRATION_7_8`. Robolectric migration round-trip from v8 + full-chain + upsert/get/delete-by-lookupKey + FK-CASCADE + **exact-DDL guard validated against Room's GENERATED `9.json` schema (not a hand-written approximation — gap A)**. Deps: none.
   354	
   355	**WI-3 (foundational): `ChapterTranslationService`** against a fake `AiClient`. Both `cachedTranslation` overloads (incl. the `expectedSegmentCount` divergence restore — H2) + `translate` + `translatePreSegmented`. **Dual-cancellation (native + typed `Cancelled`) BEFORE generic mapping (M2).** Deps: WI-1, WI-2. Tests: cache hit → zero client calls; miss → translate + write; decode fail → per-segment fallback; one-chunk fail → source-only that chunk (others translated, NOT cached); all-chunks fail → throw; native-cancel → `Cancelled` (no write); typed-`Cancelled`-from-chunk → `Cancelled` (no write); ensureActive-before-write; `AiError` mapping incl. `Config`/`InsecureUrl` → `ProviderFailed`; `translatePreSegmented` full-success caches under the enumerate count; partial degrade NOT cached; all-fail throws; `cachedTranslation(expectedSegmentCount)` returns on stored-count match, null on mismatch, needs no provider.
   356	
   357	**WI-4a (foundational): `ChapterTextProvider` (TXT/MD) + `ChapterTranslationPrefetcher` + `BilingualAiReadiness`.** `TxtChapterTextProvider` builds the document-global segment `Utf16Span`s once (via `paragraphRanges` — paragraph only, H1/H3), groups into windows, resolves `unitContaining(charOffsetUTF16)` via segment-start binary search, `sourceSegments(unit)`. Prefetcher: `prefetch` + `prefetchDirect` + `cachedDirect`; resolves active profile from `snapshot()`, decrypts snapshot-consistent, builds client via the injected factory param (default `AiProviderFactory::create`), constructs `AiRequest` with **`model = profile.model.ifBlank { profile.kind.defaultModel }` (M3)**. Readiness = active profile with non-empty decrypted key; **cipher failure → not-ready, never a crash.** Fake store + fake factory. Deps: WI-1, WI-3. Tests (all `Utf16Span`-based): unit resolution + clamp + empty; **one-chunk document (no trailing newline) → its segment translation renders, not dropped (H1)**; **final-chunk anchor → renders (H1)**; **exact-boundary → correct anchor (H1)**; **EOF anchor (`span.endExclusive == text.length`) → last chunk, no clamp-collapse (H1)**; paragraph spanning MANY chunks → one segment/one unit, anchored to the last chunk (Low-2); a >4000-char paragraph hard-split across chunks → one segment; CR/LF/CRLF; MD markers; locator→unit mapping; `unitAfter` end→null; **source-byte parity while disabled**; cache-hit-no-profile still returns (#306); no-profile miss → `ProviderFailed`; `prefetchDirect` 1:1; `cachedDirect` restores with zero provider calls; **blank `profile.model` → `AiRequest.model == kind.defaultModel` (M3 regression)**; readiness true/false; empty-key → false; no-active-with-profiles-present → false (H3); cipher-throw → readiness false (no crash). (Sentence-multi-in-one-chunk is NOT a v1 render test — the v1 provider uses `paragraphRanges` only; `sentenceRanges` behavior is covered in WI-1's reserved-foundational unit tests.)
   358	
   359	**WI-4b (foundational — shared DI/factory, incl. `AiProviderStore` in `AppContainer`): AppContainer bilingual + AI-config graph.** `AppContainer` **now constructs `AiProviderStore`** (DataStore + #116 `KeystoreSecretCipher`, following the `readerSettingsStore` convention — this is #131's change, not an external feature's) and provides `ChapterTranslationStore`, `PerBookBilingualStore`, `ChapterTranslationService`, `ChapterTranslationPrefetcher`, an `AiSettingsViewModel` factory (for WI-AIP), and the `BilingualViewModel` factory. Deps: **WI-4a** (no external dep — #136 closed). Tests: container resolves the bilingual + AI-config graph; `AiProviderStore` resolves and round-trips a profile; the prefetcher's injected factory defaults to `AiProviderFactory::create`.
   360	
   361	**WI-5 (behavioral): `PerBookBilingualStore` + `BilingualViewModel` state core.** Store per book (enabled/targetLanguage/granularity — granularity pinned `paragraph` in v1, no style); VM setters (persist + first-enable `needsSetupSheet`); `aiConfigured` from `BilingualAiReadiness.resolve` over an injected snapshot; language change clears cache-shaped state + bumps generation. Injected prefetcher/snapshot seams (Medium-4). Turbine tests: first-enable raises sheet; re-enable persisted does not; disable clears; language change resets; `aiConfigured` true/false from readiness; round-trip through store; no style field; granularity persists as `paragraph`. Deps: WI-1 (+ store).
   362	
   363	**WI-6 (behavioral): VM prefetch trigger + generation/cancellation + single-flight (M2).** `onPositionChanged(charOffsetUTF16)` derives current unit (TXT/MD only), dedupes, prefetches current+next; a monotonic position-request sequence checked after every suspension; **per-unit single-flight `prefetchTasks: Map<TranslationUnitId, Job>` (a new request cancels/joins the prior — M2)**; a captured language/provider snapshot per launch; generation bumps on disable/language/unit-change discard stale; **BOTH `CancellationException` AND typed `ChapterTranslationError.Cancelled` handled BEFORE generic error mapping (M2)**; a cancelled stale request does NOT surface as `errorUnit`; `Offline`→`unavailableUnits`; transient failure leaves unit unfetched + clears anchor to retry; `retryUnit` routes through the registry. The EPUB `onEpubBlocksEnumerated` entry is present but EPUB prefetch is owned by the controller (Medium-1); the VM's position-driven `prefetch` dispatches TXT/MD units only. Fake prefetcher (Medium-4 seam). Deps: WI-4a, WI-4b, WI-5. Tests: current+next on unit change; same-unit no-op; cancel-mid discards stale (no `errorUnit`); typed-`Cancelled` discards (not `errorUnit`); rapid re-trigger same unit → single-flight, no double-write; offline→unavailable; failure→retry-able; `retryUnit` re-fetches.
   364	
   365	**WI-7a (behavioral): Compose UI — setup sheet + interlinear body (TXT/MD) + pill.** Reproduce `vreader-bilingual.jsx` (setup sheet: language grid / **Paragraph-only Granularity control (round-4 H3)** / preview / engine strip configured+unconfigured; body: the translation rendered **inside the anchor chunk's `Column` as a muted non-registered `Text` child** per the round-4 H2 render contract — translated / loading N%+dimmed / error+Retry / offline source-only; pill). Consumes the host-neutral `BilingualRenderState` DTO. Light+dark. Compose UI tests each state, incl. **paragraph interlinear renders a translation child after a paragraph's last source chunk (depicted)**; **the setup-sheet Granularity control shows Paragraph only, no Sentence option (H3)**. Deps: WI-5 (state shape). NO Style control; the unconfigured "Set up" CTA renders and (in WI-9) routes to the Variant A sheet.
   366	
   367	**WI-7b (behavioral, CONDITIONAL — only if WI-0 = go): EPUB render adapter (DOM injection, NOT Compose — M2) + direct-block ownership (M1).** `EpubBilingualJs` (enum/inject/clear JS builders, CSP-safe escaping) + `EpubBilingualController` (the serialization actor / session token AND the **single-owner enumerate→cachedDirect/prefetchDirect→guarded-commit sequence — Medium-1**) + `EpubChapterTextProvider`, wired into `ReaderActivity`, driving DOM from the shared `BilingualRenderState` DTO. Uses `prefetchDirect`/`cachedDirect` for the count-divergence path (H2). Depends on WI-6 (VM state) and WI-4b (DI); the WI-7a UI dependency is only the shared `BilingualRenderState`/value types. Connected test on a real EPUB (seeded cache): enable → injects; disable → cleared; reflow/href-change/fragment-recreation/activity-recreation → re-applies from cache (zero provider calls) via `cachedDirect`; count-divergence handled (direct path); **the regular TXT/MD prefetch path is never invoked for an EPUB unit (Medium-1)**. Unit tests: JS escaping/CSP-safe insertion, RTL/CJK style, empty translations, loading cleanup, idempotent replacement, source-only fallback, stale-session-token commit discarded (no `errorUnit`). Deps: WI-0, WI-3, WI-4a, WI-4b, WI-6, (shared types from WI-7a). (If WI-0 = no-go, dropped; box D ships TXT/MD-only, tracked.)
   368	
   369	**WI-AIP (behavioral — the folded-in Variant A AI Providers sheet; round-4 H4 rewritten): `ReaderAiProvidersSheet`.** The scoped in-reader "AI Providers" push sheet (nav bar `‹ Bilingual` + "AI Providers" title) reproducing `vreader-ai-provider-entry.jsx` `AIProvidersSheet`/`AIProvidersSheetBody`/`NavSheet`. Per round-4 H4:
   370	  - **(a)** present `AiProviderEditSheet` VERBATIM from #118 (Kind/Name/Endpoint/Sampling/API Key/Test Connection unchanged).
   371	  - **(b)** a NEW `ReaderAiProvidersList` presentation over the SHARED `AiSettingsViewModel.listState` (verified `AiSettingsViewModel.kt:26`; each `AiProviderRow` already carries `active`, :30) + shared row/cell components — reproducing the reader-scoped `‹ Bilingual` nav (`NavSheet`, jsx:247, NOT `AiProviderListScreen`'s `NavScreen`), the bilingual-context empty state ("Choose the provider bilingual mode will use to translate this book." + "No providers yet" + "Add provider" — jsx:180–209), the **checked-active row** (`selected = row.active` — jsx:221), and **tap-to-SELECT** (`onSelect(id) → vm.setActive(id)` — jsx:221/237). It does NOT reuse `AiProviderListScreen`'s NavScreen/chrome/`AiEmptyState`/`ProviderRow`-tap-edit.
   372	  - **(c)** the **save-result seam**: `AiSettingsViewModel.save()` (or a thin WI-AIP wrapper) is extended to return the saved provider ID (from `store.upsert(...).id`, which the store already returns — `AiProviderStore.kt:58/84`), so on first Save → `store.setActive(savedId)` → pop the whole stack back to the bilingual sheet (engine strip now "configured / Change…"), **deterministically, after the upsert commits (no race)**.
   373	  `‹ Bilingual` without adding → unconfigured, no state mutated. "Change…" → populated list, current provider checked, tap row → `setActive`. No consent/flag surface (Android has none). Deps: WI-4b (for `AiProviderStore` + `AiSettingsViewModel` in `AppContainer`), WI-7a (bilingual sheet host). Tests (Compose + connected): the scoped list renders **`‹ Bilingual` back label** + **bilingual-context empty copy** + **checked active row** + **tap-selects (`setActive`)**; empty → Add → Save → **save→result-id→`setActive`→pop deterministic (no race)** → bilingual strip configured; `‹ Bilingual` without adding → strip unconfigured, snapshot unchanged; "Change…" → populated, current checked; editor reused verbatim (no divergent form).
   374	
   375	**WI-8 (behavioral): `TxtReaderActivity` integration.** Wire VM into the `items(count = document.chunkCount, key = { it })` loop as **muted non-registered translation `Text` children inside each anchor chunk's wrapping `Column`, source chunk byte-unchanged, the loop + keys UNCHANGED so lazy-index==chunk-index is preserved (round-4 H2)** + the translation **gesture-exclusion** (round-4 H2) + position-change (`charOffsetUTF16`) + setup-sheet. `originalFormat`-gated (TXT/MD). Uses WI-4b's DI. **#129 VERIFIED — straight edit.** Connected test (fake `AiClient` seam): enable → setup → confirm → interlinear from seeded cache; **enabled-mode source-chunk selection registrations UNCHANGED vs disabled (H2)**; **highlights/annotation-washes/read-aloud-wash still key off source chunks (H2)**; **with bilingual ON — position-save round-trips to the same chunk; bookmark/search/scrubber/TTS jumps land on the correct chunk (lazy-index==chunk-index preserved — round-4 H2)**; **a long-press on translation text does NOT select (gesture exclusion — round-4 H2)**; a translation child is non-selectable, does not perturb source offsets (H2); disable → source-selection byte-parity; reopen persists enabled + renders from cache with zero client calls; **paragraph-spanning-many-chunks renders exactly one translation inside its last chunk's `Column` (H1/Low-2)**; **one-chunk/final-chunk anchors render (H1)**; MD source mapping. Deps: WI-6, WI-7a, WI-4b.
   376	
   377	**WI-9 (behavioral): entry wiring + acceptance.** Mount `BilingualPill` in #132's VERIFIED top chrome; extend `readerMoreRows(...)` to supply the #134 VERIFIED More-menu `MoreActionId.BILINGUAL` toggle (`MoreRow.Toggle` `on`/`onToggle`, or `MoreRow.Disabled` "Configure AI provider first" when not configured) wired to the VM; **wire the setup sheet's "Set up"/"Change…" affordance → the #131-owned `ReaderAiProvidersSheet` (Variant A)**. Full acceptance across EPUB (if WI-7b landed) + TXT/MD, including the fresh-user path `unconfigured → Set up (→ Variant A AI Providers sheet) → add provider → Save → return → enable → translate` (now #131-owned end-to-end). **Flip box D to done ONLY for provider/model/granularity(paragraph) + the Style-descope AND Sentence-descope notes; file the follow-up checklist amendment; do NOT claim full box-D parity.** The DONE flip **no longer waits on #136** (closed). Update `docs/architecture.md` (bilingual pipeline + the new `chapter_translations` schema + `AiProviderStore` + bilingual services in `AppContainer` + the Variant A AI Providers sheet). → DONE. Deps: WI-8, WI-AIP, WI-7b (if go), feat:#132, feat:#134.
   378	
   379	## 5. Test catalogue
   380	
   381	JVM/Robolectric (`android/app/src/test/...bilingual/`): `Utf16SpanTest` (**half-open invariants: `endExclusive >= start`, `isEmpty`, `length`; round-4 H1**); `ChapterSegmenterTest` (paragraph blank-line; sentence CJK `。！？` vs Latin; empty→[]; single; **`paragraphRanges`/`sentenceRanges` return correct half-open `Utf16Span(start, endExclusive)` spans — both APIs covered even though only `paragraphRanges` ships in the v1 render path**); `TranslationChunkerTest` (packs to budget; oversize→own chunk+subSplit; empty→[]); `TranslationChunkContractTest` (prompt shape; strict JSON decode; code-fence strip; count mismatch→`CountMismatch`; non-array→`NotAStringArray`); `ChapterTranslationServiceTest` (cache hit 0 calls; miss→translate→write; decode-fail per-segment fallback; one-chunk-fail partial-not-cached; all-fail→throw; **native-cancel→Cancelled no write; typed-`Cancelled`→Cancelled no write (M2)**; ensureActive-before-write; offline/timeout/429/http/config/insecure→error mapping; very long chapter N-of-M; stale-cache count-mismatch re-translates; `translatePreSegmented` caches under enumerate count on full success; partial degrade not cached; all-fail throws; `cachedTranslation(expectedSegmentCount)` hit/miss with no provider); `ChapterTranslationErrorMappingTest`; `TxtChapterTextProviderTest` (**one-chunk document → renders (H1); final-chunk anchor → renders (H1); exact-boundary → correct anchor (H1); EOF anchor → last chunk, no clamp-collapse (H1)**; paragraph spanning MANY chunks → one segment/unit anchored to last chunk (Low-2); >4000-char paragraph → one segment across hard-split chunks; CR/LF/CRLF; MD markers; locator→unit mapping; `unitAfter` end→null; source-byte parity while disabled; **provider uses `paragraphRanges` only — H3**); `ChapterTranslationPrefetcherTest` (snapshot-consistent profile+key; injected-factory used; `AiRequest` built from profile; **blank `profile.model` → `kind.defaultModel` (M3 regression)**; cache-hit-no-profile #306; no-profile miss→ProviderFailed; `prefetchDirect` 1:1; `cachedDirect` restores with zero provider calls; CJK↔English + Latin round-trip via fake; cipher-throw→ProviderFailed not crash); `BilingualAiReadinessTest` (active+key→true; **no-active-with-profiles-present→false (H3); activeId-null→false (H3)**; empty key→false; cipher-throw→false, no crash); `PerBookBilingualStoreTest` (enabled/lang/granularity round-trip; granularity pinned paragraph; no style field); `BilingualViewModelTest` (Turbine: first-enable sheet; re-enable no-sheet; disable clears; language reset; `aiConfigured` from readiness; prefetch current+next; same-unit no-op; **cancel-mid discards (no errorUnit); typed-Cancelled discards (M2); rapid re-trigger same unit single-flight, no double-write (M2)**; offline→unavailable; error→errorUnit+retry; `retryUnit`); `AiSettingsViewModelSaveResultTest` (**`save()` returns the saved provider ID after the upsert commits — round-4 H4c seam; the returned ID matches `store.upsert(...).id`**); `EpubBilingualJsTest` (JS escaping / CSP-safe insertion; RTL/CJK style; empty translations; clear idempotent; inject idempotent replacement; source-only fallback — WI-7b if go); `EpubBilingualControllerTest` (**enumerate→cachedDirect/prefetchDirect→guarded commit; stale-session-token commit discarded, no errorUnit; single-owner (regular TXT/MD prefetch never runs for EPUB unit) — Medium-1** — WI-7b if go).
   382	
   383	Room migration: `VReaderDatabaseMigrationTest` (extend) **v8→v9 + full-chain from v8** + FK-CASCADE + `lookupKey`-as-PK + **exact-DDL validated against Room's generated `9.json` schema, not a hand-written approximation (gap A)**; `ChapterTranslationDaoTest` (upsert-by-PK replaces; get/delete-by-lookupKey).
   384	
   385	Compose UI (`androidTest/...bilingual/`): `BilingualSetupSheetUiTest` (language grid, **Granularity control shows Paragraph only — no Sentence option (H3)**, preview, engine configured vs unconfigured driven by `aiConfigured`; no Style control present; light+dark); `BilingualInterlinearBodyUiTest` (**translation rendered as a muted `Text` child inside the anchor chunk's `Column` (round-4 H2 render contract); paragraph interlinear translated incl. CJK font + RTL Arabic**; loading N%+dimmed; error+Retry; offline source-only; empty translation→source-only no crash); `ReaderAiProvidersSheetUiTest` (**the scoped list renders `‹ Bilingual` back label + bilingual-context empty copy + checked active row + tap-selects (`setActive`) — round-4 H4b; editor (`AiProviderEditSheet`) reused verbatim (H4a)**); `BilingualPillUiTest`.
   386	
   387	Connected (`androidTest/...reader/`): `TxtReaderBilingualConnectedTest` (API 35, fake `AiClient` via injected factory): enable→setup→confirm→interlinear from seeded Room cache; **enabled-mode source-chunk selection registrations UNCHANGED vs disabled (H2); highlights/annotation-washes/read-aloud-wash still key off source chunks (H2)**; **with bilingual ON — position-save round-trips to the same chunk; bookmark/search/scrubber/TTS jumps land on the correct chunk (lazy-index==chunk-index preserved — round-4 H2)**; **long-press on translation text does NOT select (gesture exclusion — round-4 H2)**; translation child non-selectable + no source-offset perturbation (H2); disable→source-selection byte-parity; reopen persists enabled + renders from cache with zero client calls; **paragraph-spanning-many-chunks renders one translation (H1/Low-2); one-chunk/final-chunk anchors render (H1)**; TXT/MD gated (PDF inert); very long chapter scroll responsive; cancellation leaves no partial cache row. `ReaderAiProvidersConnectedTest` (WI-AIP + WI-9): `unconfigured → Set up → Variant A sheet → add provider → Save → save-result-id → setActive → pop-to-bilingual configured (deterministic, no race — round-4 H4c) → enable → translate`; `‹ Bilingual` without adding → unconfigured, snapshot unchanged; "Change…" → populated, current checked, tap → setActive. `EpubReaderBilingualConnectedTest` (only if WI-0=go): enable→inject on a real EPUB; disable→clear; href-change/fragment-recreation/activity-recreation→re-apply from cache (zero provider calls); count-divergence handled via `prefetchDirect`/`cachedDirect`; regular prefetch never runs for EPUB unit (Medium-1).
   388	
   389	Edge cases: empty translation, failed, partial per-chunk, CJK↔English + Latin + RTL, provider error/timeout/429/config/insecure, native + typed cancellation mid-translation + before-write, single-flight overlap, very long chapters, offline (cache-first + silent source-only), cipher-decrypt failure → not-ready (no crash), enumerate↔segment count divergence (direct path), one-chunk/final-chunk/EOF anchors (H1), blank model (M3), lazy-index==chunk-index parity with bilingual on (round-4 H2), translation-text long-press excluded (round-4 H2), save-result-id determinism (round-4 H4).
   390	
   393	- **Live-translation verification is AI-credential-gated (the box-D caveat).** The whole pipeline is verified without live creds via a deterministic **fake `AiClient`** injected through the prefetcher's `clientFactory` param (default `AiProviderFactory::create`; tests override). WI-3/4a/8 prove segment→chunk→decode→cache→interleave end-to-end incl. every error/edge path. Connected tests seed the Room cache and assert render-from-cache with zero client calls. An optional live smoke confirms wire format but is NOT a gate. The fresh-user `unconfigured → Set up → add provider` reachability leg is now #131-owned (WI-AIP + WI-9) and verified by `ReaderAiProvidersConnectedTest`.
   394	- **Final-chunk translation drop + span type (round-3 H1 + round-4 H1).** Fixed by `endExclusive = if (i+1<chunkCount) offsetForChunk(i+1) else text.length` + the dedicated **`Utf16Span(start, endExclusive)`** half-open value type replacing the incompatible `IntRange` everywhere in the segment/render contracts; one-chunk/final-chunk/exact-boundary/EOF tests. `offsetForChunk`'s clamp (TxtDocument.kt:17) is never relied on for the final end.
   395	- **Enabled render breaking the per-chunk layout/selection model AND the lazy-index↔chunk-index identity (round-3 H2 + round-4 H2).** Fixed by the **one-lazy-item-per-chunk `Column`** render contract: the `items(count = chunkCount, key = { it })` loop + keys are UNCHANGED (lazy-index==chunk-index preserved, so position-save/progress/every jump/TTS visibility — TxtReaderActivity.kt:220/252/256/411/421/454/481/623 — stay correct); inside each item a `Column` holds the UNCHANGED source `Text` (one `TextLayoutResult`, one `registerChunk(i)`) then the muted non-registered translation child(ren); an explicit **gesture-exclusion** stops a long-press on translation text from routing to `hitAt`'s nearest-source-chunk fallback (TxtSelectionController.kt:47–53). Enabled-mode tests assert selection/highlight/wash/annotation parity AND lazy-index==chunk-index parity with disabled, plus translation-not-selectable.
   396	- **TXT/MD segment↔render pairing (round-2 H1).** Both sides read the SAME segment `Utf16Span` array over `TxtDocument.text`, so 1:1 holds by construction — no chapter model invented; a paragraph split across many chunks is translated + rendered once (inside its last chunk's `Column`). Granularity is paragraph-only in v1; the `g=` cache slot is retained for a future granularity.
   397	- **Undesigned sentence render (round-4 H3).** v1 segments + caches + renders + offers **paragraph only** — the only depicted interlinear pattern. `TranslationGranularity.sentence` + `ChapterSegmenter.sentenceRanges` stay as reserved-foundational code (WI-1, unit-tested) but never appear in the v1 render/cache/VM/setup-sheet path. The Sentence control AND its render are design-gated together (§Design gates).
   398	- **Variant A fold-in not wireable verbatim (round-4 H4).** The EDITOR (`AiProviderEditSheet`) is reused verbatim (a); the scoped LIST is a NEW `ReaderAiProvidersList` over the shared `AiSettingsViewModel` state reproducing the designed `‹ Bilingual` nav + bilingual empty state + checked-active row + tap-to-select (b); a save-result seam returns the saved ID (which `AiProviderStore.upsert` already produces, AiProviderStore.kt:58/84) so `setActive(savedId)` + pop-on-success is deterministic and race-free (c). No "reuse `AiProviderListScreen` verbatim" claim remains anywhere.
   399	- **EPUB direct-block flow (round-3 Medium-1 — CONFIRMED RESOLVED).** The `EpubBilingualController` is the single owner: `enumeratedBlocks → cachedDirect (zero-provider restore) else prefetchDirect → session-token-guarded commit into BilingualRenderState/translationsByUnit`. The VM's position-driven regular prefetch is TXT/MD-only, so the two paths never write the same canonical cache row. Every suspended step is token-guarded; a stale token discards silently.
   400	- **EPUB count divergence (round-2 H2).** The direct-block path (`prefetchDirect` → `translatePreSegmented`, cached by enumerate count, restored by `cachedDirect(expectedCount)` with zero provider calls) — iOS Bugs #268/#330/#343 parity.
   401	- **EPUB JS-injection race (round-2 M1).** WI-0's contract (single actor/mutex OR monotonic navigator-session token; token check after every suspended call; clear before publication teardown; identified production re-apply signal per recreation case). No deterministic re-apply signal = explicit NO-GO → TXT/MD-only ship.
   402	- **Cancellation + single-flight (round-3 Medium-2 — CONFIRMED RESOLVED).** Both service and VM handle native `CancellationException` AND typed `ChapterTranslationError.Cancelled` before generic mapping (iOS `ChapterTranslationService.swift:359–364`); a per-unit `prefetchTasks: Map<TranslationUnitId, Job>` cancels/joins a prior request so rapid retry/navigation can't run overlapping translations or Room writes; a cancelled stale request never surfaces as `errorUnit`. `ensureActive()` before the Room write.
   403	- **Blank model (round-3 Medium-3 — CONFIRMED RESOLVED).** The prefetcher builds `model = profile.model.ifBlank { profile.kind.defaultModel }` (matches `AiChatViewModel.kt:61`; both wire clients serialize `request.model` directly, `OpenAiCompatibleProvider.kt:38`/`AnthropicProvider.kt:36`). Blank-model regression test.
   404	- **AI-config readiness (H3 — CONFIRMED correct).** `BilingualAiReadiness.resolve` = active profile + decrypts-non-empty; `activeId` can be null with profiles present; cipher failure → not-ready (no crash). No consent/flag gate (Android has none).
   405	- **Migration schema drift (gap A).** `MIGRATION_8_9`'s exact DDL is authored in §2 and validated against Room's GENERATED `9.json` schema (not a hand-written approximation) by the extended `VReaderDatabaseMigrationTest` opening the real Room DB — the recurring Android migration failure mode (cf. #135's stale-version finding).
   406	- **Backup `bilingualGranularity` cross-platform parity UNCONFIRMED (gap B).** The backup-contract `bilingualGranularity` field's cross-platform conformance vector + iOS parity are UNCONFIRMED. Safe for v1 (backup collect/restore is descoped / device-local — §7), but flagged as a follow-up: **when the backup-wiring WI lands, add a conformance vector under `contracts/vectors/` and confirm iOS parity before shipping backup of the field.**
   407	- **Cost/latency of translating on scroll.** Lazy current+next prefetch + disk cache; N-of-M progress; cancellation on navigate-away/generation-bump/single-flight supersede.
   408	- **Provider JSON non-compliance.** `TranslationChunkContract.decode` + per-segment fallback — never drops a paragraph.
   409	- **DataStore per-book key growth.** One Preferences entry per book keyed by fingerprint; scales like `ReaderSettingsStore`/`AiProviderStore`.
   410	- **Dependency honesty (round-3 Medium-4 — CONFIRMED RESOLVED).** WI-4b (DI, incl. `AiProviderStore` in `AppContainer`) is foundational and gates the production run-through of WI-6/WI-7b/WI-AIP/WI-8; those WIs' unit/Compose gates proceed against injected fakes, and WI-4b is sequenced before them. No external feature gates the chain (#136 closed).
   411	
   412	## 7. Backward compat
   413	
   414	- **Room migration additive.** New `chapter_translations` (FK CASCADE, `lookupKey` PK, `sourceParagraphCount`, all columns `NOT NULL`). Existing rows untouched. Against this checkout **8→9, `MIGRATION_8_9`** with the **exact DDL in §2** appended after `MIGRATION_7_8` (VReaderDatabase.kt:224–228); the migration test extended from v8 validates it against Room's generated `9.json` schema (gap A).
   415	- **Reader unchanged when bilingual off** — the TXT/MD `items(count = document.chunkCount, key = { it })` source loop + keys are **unchanged** (lazy-index==chunk-index preserved); each item's `Column` holds only the unchanged source `Text` unless `enabled && format∈{txt,md} && translation present` (translations are additive in-item children, non-registered, non-selectable — round-4 H2). `ReaderBottomChrome` is not modified. EPUB render adapter inert unless bilingual is on.
   416	- **`AppContainer` gains `AiProviderStore`** (previously not provided — VReaderApp.kt:64/66 comment only) plus the bilingual services + `AiSettingsViewModel` factory; all additive lazy singletons following the `readerSettingsStore` pattern. #118 AI files are consumed unchanged **except** the additive save-result seam on `AiSettingsViewModel.save()` (returns the saved ID — round-4 H4c; the underlying `AiProviderStore.upsert` already returns the saved profile, so this exposes existing information without changing persistence behavior).
   417	- **#118 AI provider files otherwise unchanged** — the prefetcher/readiness/Variant A sheet are new consumers; the scoped list is a new presentation over the shared VM state (round-4 H4b), not an edit to `AiProviderListScreen`.
   418	- **Backup contract already compatible** — `PerBookSettingsOverride.bilingualEnabled/TargetLanguage/Granularity` exist (no `bilingualStyle`), no translation-cache backup section (device-local, re-derivable). #131 writes the three fields locally; backup collect/restore is a small additive follow-up (no contract change), out of v1; config device-local until then. **`bilingualGranularity` cross-platform conformance vector + iOS parity are UNCONFIRMED (gap B) — a follow-up when the backup-wiring WI lands: add a `contracts/vectors/` conformance vector + confirm iOS parity before shipping backup of the field.**
   419	- **#132/#134/#129 landed** — the top-chrome pill mount + More-menu toggle (`readerMoreRows` extension) + `TxtReaderActivity` edit land on VERIFIED surfaces (rule 48 one-writer-per-file satisfied).
   420	
   421	## Design gates (rule 51 — for `needs-design` filing)
   422	
   423	1. **"Bilingual mode" setup sheet with BOTH Style AND Granularity in one Android sheet** (unchanged — Style stays descoped v1) — `vreader-bilingual.jsx` depicts Granularity (no Style); `vreader-ai-android.jsx` depicts Style (no Granularity); no committed bundle shows both together. v1 reproduces the granularity-only `vreader-bilingual.jsx` sheet and DROPS Style (user descope, §3). If Style is wanted as an Android user control, file `Design needed: bilingual setup sheet (Style + Granularity) for feature #131`. The box-D Style parity gap is tracked by the WI-9 follow-up checklist amendment.
   424	2. **`Design needed: sentence-granularity bilingual interlinear — BOTH the setup-sheet Sentence control AND its render — for feature #131`** (round-4 H3 — broadened to cover both, filed together) — `vreader-bilingual.jsx` `BilingualPageContent` (lines ~195–277) depicts ONLY paragraph interlinear (one translation `<p>` per source paragraph), and a translation-after-each-sentence render (grouped when several sentences share a line-chunk) is depicted nowhere; the Sentence option appears only in the setup control (`vreader-bilingual.jsx:77`) with no matching renderer. v1 ships the depicted **paragraph** interlinear render + a **Paragraph-only** setup-sheet Granularity control; **Sentence is descoped from BOTH the control and the render in v1** (no undesigned surface, no paragraph-content-under-a-sentence-key). `TranslationGranularity.sentence` + `ChapterSegmenter.sentenceRanges` remain reserved-foundational code (WI-1). When the sentence-interlinear render (and its control option) is designed, it is a render-only follow-up (the one-lazy-item-per-chunk `Column` contract already accommodates several stacked sentence translation children per anchor chunk). The box-D Sentence gap is tracked by the WI-9 follow-up checklist amendment.
   425	

codex
The v5 patch is internally consistent on the span and one-item render contracts so far. I’m now checking the contracts against the live chunking, selection geometry, AI-store/VM behavior, Room conventions, and the committed JSX designs—especially for subtle new regressions caused by nesting the source `Text` in a `Column`.
exec
/bin/zsh -lc "nl -ba android/app/src/main/kotlin/com/vreader/app/reader/TxtDocument.kt | sed -n '1,115p'; nl -ba android/app/src/main/kotlin/com/vreader/app/reader/TxtSelectionController.kt | sed -n '1,125p'; nl -ba android/app/src/main/kotlin/com/vreader/app/reader/TxtReaderActivity.kt | sed -n '200,270p;395,490p;605,635p;1010,1100p'" in /Users/ll/workspace/vreader
 succeeded in 0ms:
     1	// Purpose: Addressable, range-based model of a decoded .txt — feature #111 WI-1.
     2	// Holds ONE backing decoded String and an array of chunk START offsets (UTF-16 code
     3	// units against the RAW text — NO line-ending normalization, so charOffsetUTF16 stays
     4	// exact for resume). Splits at line boundaries (CRLF/CR/LF kept inside the chunk);
     5	// hard-splits a runaway line at maxChunkChars (never mid-surrogate-pair). Visible
     6	// chunk text is materialized on demand (no per-chunk substrings retained). Pure JVM.
     7	package com.vreader.app.reader
     8	
     9	class TxtDocument private constructor(
    10	    val text: String,
    11	    private val starts: IntArray,
    12	) {
    13	    /** Number of chunks (0 for empty text). */
    14	    val chunkCount: Int get() = starts.size
    15	
    16	    /** The UTF-16 start offset of chunk [index] (clamped to a valid chunk). */
    17	    fun offsetForChunk(index: Int): Int {
    18	        if (starts.isEmpty()) return 0
    19	        return starts[index.coerceIn(0, starts.size - 1)]
    20	    }
    21	
    22	    /** The chunk index containing [offsetUtf16] (EOF-clamped); 0 for empty text. */
    23	    fun chunkForOffset(offsetUtf16: Int): Int {
    24	        if (starts.isEmpty()) return 0
    25	        val offset = offsetUtf16.coerceIn(0, text.length)
    26	        // Largest start <= offset (binary search).
    27	        var lo = 0; var hi = starts.size - 1; var ans = 0
    28	        while (lo <= hi) {
    29	            val mid = (lo + hi) ushr 1
    30	            if (starts[mid] <= offset) { ans = mid; lo = mid + 1 } else { hi = mid - 1 }
    31	        }
    32	        return ans
    33	    }
    34	
    35	    /** The text of chunk [index], materialized on demand from the backing string. */
    36	    fun textForChunk(index: Int): CharSequence {
    37	        if (starts.isEmpty()) return ""
    38	        val i = index.coerceIn(0, starts.size - 1)
    39	        val end = if (i + 1 < starts.size) starts[i + 1] else text.length
    40	        return text.subSequence(starts[i], end)
    41	    }
    42	
    43	    companion object {
    44	        const val DEFAULT_MAX_CHUNK_CHARS = 4000
    45	
    46	        /**
    47	         * Build a document from already-decoded [text]. Chunk boundaries fall after a
    48	         * line terminator (`\n`, `\r`, or `\r\n` — preserved in the chunk); a line longer
    49	         * than [maxChunkChars] is hard-split, but never between a surrogate pair.
    50	         */
    51	        fun of(text: String, maxChunkChars: Int = DEFAULT_MAX_CHUNK_CHARS): TxtDocument {
    52	            if (text.isEmpty()) return TxtDocument(text, IntArray(0))
    53	            // Primitive growable IntArray (no Int boxing) — a newline-dense 14MB file
    54	            // would otherwise spike tens of MB of boxed Integers + a duplicating copy.
    55	            var starts = IntArray(64)
    56	            var count = 0
    57	            fun push(v: Int) {
    58	                if (count == starts.size) starts = starts.copyOf(starts.size * 2)
    59	                starts[count++] = v
    60	            }
    61	            push(0)
    62	            var i = 0
    63	            var chunkStart = 0
    64	            val n = text.length
    65	            while (i < n) {
    66	                val c = text[i]
    67	                when {
    68	                    c == '\n' -> {
    69	                        i++
    70	                        if (i < n) { push(i); chunkStart = i }
    71	                    }
    72	                    c == '\r' -> {
    73	                        i++
    74	                        if (i < n && text[i] == '\n') i++   // CRLF stays one terminator
    75	                        if (i < n) { push(i); chunkStart = i }
    76	                    }
    77	                    else -> {
    78	                        i++
    79	                        // Hard-split a runaway line, but not mid-surrogate-pair (don't
    80	                        // split right after a high surrogate — its low half follows at i).
    81	                        if (i - chunkStart >= maxChunkChars && i < n && !text[i - 1].isHighSurrogate()) {
    82	                            push(i); chunkStart = i
    83	                        }
    84	                    }
    85	                }
    86	            }
    87	            return TxtDocument(text, starts.copyOf(count))
    88	        }
    89	    }
    90	}
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
   200	        setContent {
   201	            VReaderTheme {
   202	                val state by produceState<TxtUiState>(TxtUiState.Loading, key) {
   203	                    value = withContext(Dispatchers.IO) {
   204	                        runCatching { load(key) }.getOrDefault(TxtUiState.Failed)
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
   395	                            // feature #135 WI-7 — the top-bar bookmark toggle + Bookmarks-tab rows + TXT jump.
   396	                            isCurrentBookmarked = isBookmarked,
   397	                            onToggleBookmark = {
   398	                                container.appScope.launch {
   399	                                    runCatching { container.annotationsRepository.toggleBookmark(bookKey, title = null, locator = liveCanonical) }
   400	                                }
   401	                            },
   402	                            currentLocator = liveCanonical,
   403	                            bookmarks = bookmarkRows,
   404	                            // TXT jump: scroll to the bookmark's char offset via the existing chunk scroll seam
   405	                            // (the same path resume + the annotation jump use). Out-of-range → Failed (sheet stays open).
   406	                            onJumpBookmark = { record ->
   407	                                val target = txtBookmarkScrollTarget(record.locator.charOffsetUTF16, s.document.text.length)
   408	                                if (target == null) {
   409	                                    JumpResult.Failed
   410	                                } else {
   411	                                    ttsScope.launch { listState.scrollToItem(s.document.chunkForOffset(target)) }
   412	                                    JumpResult.Succeeded
   413	                                }
   414	                            },
   415	                            // TXT/MD jump: scroll to the annotation's UTF-16 offset via the existing chunk
   416	                            // scroll seam (the same path used by resume + scrubber).
   417	                            onJumpToAnnotation = { item ->
   418	                                ttsScope.launch {
   419	                                    val target = annotationScrollOffset(item)
   420	                                        .coerceIn(0, (s.document.text.length - 1).coerceAtLeast(0))
   421	                                    listState.scrollToItem(s.document.chunkForOffset(target))
   422	                                }
   423	                            },
   424	                            onShareAnnotations = { shareAnnotations(annotationsSnapshot) },
   425	                            // feature #133 WI-10 — the Search entry + sheet. The icon is hidden only when the
   426	                            // index-state gate says Unsupported (a skipped-unsupported TXT/MD book — no dead
   427	                            // control); otherwise tapping it opens the sheet for THIS book.
   428	                            onOpenSearch = if (inBookSearchState.hidesSearchEntry) null else { { showSearch = true } },
   429	                            searchSheet = if (!showSearch) null else {
   430	                                {
   431	                                    InBookSearchSheet(
   432	                                        theme = displaySettings.theme,
   433	                                        bookTitle = s.title,
   434	                                        state = inBookSearchState,
   435	                                        query = inBookSearchState.query,
   436	                                        onQueryChange = inBookSearchVm::onQueryChange,
   437	                                        onPickRecent = inBookSearchVm::onPickRecent,
   438	                                        // Resolve the tapped hit's canonical charOffsetUTF16 → scroll via the
   439	                                        // EXISTING chunk-scroll seam (the same path resume / annotation / bookmark
   440	                                        // jumps use). The WI-9 sheet's onJump is NON-suspend (JumpResult returns
   441	                                        // synchronously), so — like the sibling annotation/bookmark jumps — the
   442	                                        // range is validated UP FRONT (out-of-range/null → Failed, sheet stays
   443	                                        // open, rule 51) and a valid target returns Succeeded optimistically while
   444	                                        // the actual scroll runs on ttsScope; the launch is runCatching-guarded so
   445	                                        // a scroll cancelled during teardown can't crash. The recent is committed
   446	                                        // only on a valid result-open (the VM's commitSearch contract).
   447	                                        onJump = { hit ->
   448	                                            val off = hit.canonicalLocator?.charOffsetUTF16
   449	                                            val target = txtBookmarkScrollTarget(off, s.document.text.length)
   450	                                            if (target == null) {
   451	                                                JumpResult.Failed
   452	                                            } else {
   453	                                                inBookSearchVm.commitSearch()
   454	                                                ttsScope.launch { runCatching { listState.scrollToItem(s.document.chunkForOffset(target)) } }
   455	                                                JumpResult.Succeeded
   456	                                            }
   457	                                        },
   458	                                        onLoadMore = inBookSearchVm::loadMore,
   459	                                        onDismiss = { inBookSearchVm.onDismiss(); showSearch = false },
   460	                                    )
   461	                                }
   462	                            },
   463	                            bottomBar = { (openContents, openNotes) ->
   464	                                if (active) TtsControlBar(
   465	                                    tts,
   466	                                    onPlayPause = { if (tts.phase == TtsPhase.speaking) ttsVm.pause() else ttsVm.play() },
   467	                                    onPrevious = ttsVm::previous, onNext = ttsVm::next, onStop = ttsVm::stop,
   468	                                    onSpeed = { showSpeed = true }, onVoice = { showVoice = true },
   469	                                    onInstallVoice = ttsVm::installVoiceData, onSystemTts = ttsVm::openSystemTts,
   470	                                ) else ReaderBottomChrome(
   471	                                    theme = displaySettings.theme,
   472	                                    progress = TxtProgress.fraction(
   473	                                        s.document.offsetForChunk(listState.firstVisibleItemIndex),
   474	                                        s.document.text.length,
   475	                                    ),
   476	                                    displayPage = 0, totalPages = 0,   // TXT/MD scroll-only — no page labels
   477	                                    onScrub = { f ->
   478	                                        ttsScope.launch {
   479	                                            val target = (f * s.document.text.length).toInt()
   480	                                                .coerceIn(0, (s.document.text.length - 1).coerceAtLeast(0))
   481	                                            listState.scrollToItem(s.document.chunkForOffset(target))
   482	                                        }
   483	                                    },
   484	                                    onOpenDisplay = { showDisplaySheet = true },
   485	                                    // #132 WI-6: the scaffold hands the Contents/Notes open callbacks in.
   486	                                    // TXT/MD has no TOC → openContents is null (Contents control hidden);
   487	                                    // openNotes opens the review sheet.
   488	                                    onOpenContents = openContents,
   489	                                    onOpenNotes = openNotes,
   490	                                    extraSlot = {
   605	        val initial = computeInitialIndex(key, document)
   606	        return TxtUiState.Loaded(book.title, document, book, initial)
   607	    }
   608	
   609	    /** Restore: the saved legacy locator's charOffsetUTF16 → the chunk containing it. */
   610	    private suspend fun computeInitialIndex(key: String, document: TxtDocument): Int {
   611	        // In-memory cache first — a fast rotation / reopen sees the latest offset even
   612	        // before the prior instance's async Room flush commits. Falls to durable Room.
   613	        container.cachedOffset(key)?.let { return document.chunkForOffset(it) }
   614	        val saved = container.repository.loadPosition(key) ?: return 0
   615	        // ResumeResolver/ResumeTarget are in this package. A TXT position is a legacy
   616	        // (non-Readium) envelope → Canonical; its charOffsetUTF16 is the anchor.
   617	        val offset = (ResumeResolver.resolve(saved) as? ResumeTarget.Canonical)
   618	            ?.locator?.charOffsetUTF16 ?: return 0
   619	        return document.chunkForOffset(offset)
   620	    }
   621	
   622	    /** Enqueue the top-visible chunk's char offset; the lone writer persists it (latest-wins). */
   623	    private fun savePosition(book: Book, document: TxtDocument, topIndex: Int) {
   624	        val offset = document.offsetForChunk(topIndex)
   625	        // Cache synchronously so an immediate reopen/rotation reads the latest position
   626	        // even before the async Room write below commits.
   627	        container.cacheOffset(book.fingerprintKey, offset)
   628	        saveRequests.trySend(PendingSave(book, offset))
   629	    }
   630	
   631	    /** Launch a system intent for a read-aloud one-shot, guarded by resolveActivity with fallbacks
   632	     *  (there is no public Settings.ACTION_TTS_SETTINGS — fall back to accessibility / settings). */
   633	    private fun launchTtsIntent(i: TtsIntent) {
   634	        val candidates = when (i) {
   635	            TtsIntent.InstallVoiceData -> listOf(android.content.Intent(TextToSpeech.Engine.ACTION_INSTALL_TTS_DATA))
  1010	    val currentOnFinalize by androidx.compose.runtime.rememberUpdatedState(onSelectionFinalized)
  1011	    LazyColumn(
  1012	        Modifier
  1013	            .fillMaxSize()
  1014	            .onGloballyPositioned { selectionController?.setLazyCoords(it) }
  1015	            .then(
  1016	                if (selectionController != null) {
  1017	                    // ONE detector distinguishes a TAP (edit an existing highlight) from a LONG-PRESS+drag
  1018	                    // (new selection) — two separate pointerInput detectors conflict over the same down event.
  1019	                    Modifier.pointerInput(selectionController) {
  1020	                        awaitEachGesture {
  1021	                            val down = awaitFirstDown(requireUnconsumed = false)
  1022	                            val longPress = awaitLongPressOrCancellation(down.id)
  1023	                            if (longPress != null) {
  1024	                                // long-press → selection; finalize only on a COMPLETED drag/up (not a cancel).
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

exec
/bin/zsh -lc "nl -ba android/app/src/main/kotlin/com/vreader/app/ai/AiProviderListScreen.kt | sed -n '1,145p'; nl -ba android/app/src/main/kotlin/com/vreader/app/ai/AiSettingsViewModel.kt | sed -n '1,145p'; nl -ba android/app/src/main/kotlin/com/vreader/app/ai/AiProviderStore.kt | sed -n '1,135p'" in /Users/ll/workspace/vreader
 succeeded in 0ms:
     1	// Purpose: feature #118 WI-3 (#110 Phase 3) — the AI provider list (the gate), design surface A
     2	// from vreader-ai-android.jsx `AiProviderList`: unconfigured onboards to a single Add action;
     3	// configured shows the active provider + per-provider status (model, or the rejection reason).
     4	// Reuses the shared form vocabulary (NavScreen / SettingsCard / GroupHeader / StatusDot / tokens —
     5	// mapped from this surface's own design file). Stateless: a pure function of the list + callbacks.
     6	package com.vreader.app.ai
     7	
     8	import androidx.compose.foundation.background
     9	import androidx.compose.foundation.clickable
    10	import androidx.compose.foundation.layout.Box
    11	import androidx.compose.foundation.layout.Column
    12	import androidx.compose.foundation.layout.Row
    13	import androidx.compose.foundation.layout.fillMaxWidth
    14	import androidx.compose.foundation.layout.height
    15	import androidx.compose.foundation.layout.heightIn
    16	import androidx.compose.foundation.layout.padding
    17	import androidx.compose.foundation.layout.size
    18	import androidx.compose.foundation.shape.CircleShape
    19	import androidx.compose.foundation.shape.RoundedCornerShape
    20	import androidx.compose.material.icons.Icons
    21	import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
    22	import androidx.compose.material.icons.filled.Add
    23	import androidx.compose.material.icons.filled.AutoAwesome
    24	import androidx.compose.material3.Icon
    25	import androidx.compose.material3.Text
    26	import androidx.compose.runtime.Composable
    27	import androidx.compose.ui.Alignment
    28	import androidx.compose.ui.Modifier
    29	import androidx.compose.ui.draw.clip
    30	import androidx.compose.ui.graphics.Color
    31	import androidx.compose.ui.platform.testTag
    32	import androidx.compose.ui.text.font.FontWeight
    33	import androidx.compose.ui.text.style.TextAlign
    34	import androidx.compose.ui.unit.dp
    35	import androidx.compose.ui.unit.sp
    36	import com.vreader.app.backup.BackupFonts
    37	import com.vreader.app.backup.GroupFooter
    38	import com.vreader.app.backup.GroupHeader
    39	import com.vreader.app.backup.LocalBackupTokens
    40	import com.vreader.app.backup.NavScreen
    41	import com.vreader.app.backup.SettingsCard
    42	import com.vreader.app.backup.StatusDot
    43	import com.vreader.app.backup.VSpace
    44	
    45	@Composable
    46	fun AiProviderListScreen(
    47	    state: AiProviderListState,
    48	    onBack: () -> Unit = {},
    49	    onAdd: () -> Unit = {},
    50	    onEdit: (String) -> Unit = {},
    51	) {
    52	    val t = LocalBackupTokens.current
    53	    val addButton: @Composable () -> Unit = {
    54	        Box(
    55	            Modifier.size(44.dp).clip(RoundedCornerShape(22.dp)).clickable(onClickLabel = "Add provider", onClick = onAdd),
    56	            contentAlignment = Alignment.Center,
    57	        ) { Icon(Icons.Filled.Add, contentDescription = "Add provider", tint = t.tint, modifier = Modifier.size(22.dp)) }
    58	    }
    59	    NavScreen(title = "AI Providers", large = true, onBack = onBack, trailing = addButton) {
    60	        Column(Modifier.padding(horizontal = 18.dp).padding(bottom = 32.dp)) {
    61	            if (state.unconfigured) {
    62	                AiEmptyState(onAdd)
    63	            } else {
    64	                GroupHeader("Providers")
    65	                SettingsCard {
    66	                    state.providers.forEachIndexed { i, p ->
    67	                        ProviderRow(p, last = i == state.providers.lastIndex, onEdit = onEdit)
    68	                    }
    69	                }
    70	                GroupFooter("The selected provider is used for translation, chat, and summaries. Tap one to edit or test it.")
    71	            }
    72	        }
    73	    }
    74	}
    75	
    76	@Composable
    77	private fun AiEmptyState(onAdd: () -> Unit) {
    78	    val t = LocalBackupTokens.current
    79	    Column(Modifier.fillMaxWidth().padding(top = 36.dp), horizontalAlignment = Alignment.CenterHorizontally) {
    80	        Box(Modifier.size(64.dp).clip(CircleShape).background(t.chipBg), contentAlignment = Alignment.Center) {
    81	            Icon(Icons.Filled.AutoAwesome, contentDescription = null, tint = t.tint, modifier = Modifier.size(30.dp))
    82	        }
    83	        VSpace(18)
    84	        Text("Connect an AI provider", color = t.ink, fontFamily = BackupFonts.Serif, fontSize = 21.sp, textAlign = TextAlign.Center)
    85	        VSpace(8)
    86	        Text(
    87	            "One key unlocks bilingual translation, chat about a book, and chapter summaries. Your key is stored on-device only.",
    88	            color = t.sec, fontFamily = BackupFonts.Sans, fontSize = 14.sp, lineHeight = 22.sp, textAlign = TextAlign.Center,
    89	        )
    90	        VSpace(18)
    91	        Box(
    92	            Modifier.fillMaxWidth().clip(RoundedCornerShape(13.dp)).background(t.tint)
    93	                .clickable(onClickLabel = "Add a provider", onClick = onAdd).testTag("ai-add-provider").padding(vertical = 14.dp),
    94	            contentAlignment = Alignment.Center,
    95	        ) { Text("Add a provider", color = Color.White, fontFamily = BackupFonts.Sans, fontSize = 15.sp, fontWeight = FontWeight.SemiBold) }
    96	        GroupFooter("Works with Anthropic, OpenAI-compatible endpoints, and local models.")
    97	    }
    98	}
    99	
   100	@Composable
   101	private fun ProviderRow(p: AiProviderRow, last: Boolean, onEdit: (String) -> Unit) {
   102	    val t = LocalBackupTokens.current
   103	    Box {
   104	        Row(
   105	            Modifier.fillMaxWidth().heightIn(min = 60.dp).clickable(onClick = { onEdit(p.id) })
   106	                .testTag("provider-${p.id}").padding(horizontal = 14.dp),
   107	            verticalAlignment = Alignment.CenterVertically,
   108	        ) {
   109	            // active = filled accent circle; inactive = hollow ring (sep ring + card-coloured core)
   110	            Box(
   111	                Modifier.size(20.dp).clip(CircleShape).background(if (p.active) t.tint else t.sep),
   112	                contentAlignment = Alignment.Center,
   113	            ) {
   114	                if (!p.active) Box(Modifier.size(16.5.dp).clip(CircleShape).background(t.card))
   115	            }
   116	            Column(Modifier.weight(1f).padding(start = 12.dp)) {
   117	                Text(p.name, color = t.ink, fontFamily = BackupFonts.Sans, fontSize = 15.5.sp, fontWeight = FontWeight.Medium)
   118	                Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.padding(top = 2.dp)) {
   119	                    StatusDot(if (p.statusOk) t.green else t.red)
   120	                    Text(
   121	                        p.detail, color = if (p.statusOk) t.sec else t.red,
   122	                        fontFamily = BackupFonts.Mono, fontSize = 11.5.sp, modifier = Modifier.padding(start = 6.dp),
   123	                    )
   124	                }
   125	            }
   126	            Icon(Icons.AutoMirrored.Filled.KeyboardArrowRight, contentDescription = null, tint = t.ter, modifier = Modifier.size(18.dp))
   127	        }
   128	        if (!last) Box(Modifier.fillMaxWidth().padding(start = 46.dp).height(0.5.dp).background(t.sep).align(Alignment.BottomStart))
   129	    }
   130	}
     1	// Purpose: feature #118 WI-3 (#110 Phase 3) — drives the AI provider list + editor: observes the
     2	// AiProviderStore for the list, owns the editor form state, runs Test Connection against the LIVE
     3	// form (a transient AiClient built from the form + key, no save first), and saves/deletes. v1 list
     4	// status is ok+model (persisted per-provider test status is a follow-on). The key is never logged.
     5	package com.vreader.app.ai
     6	
     7	import androidx.lifecycle.ViewModel
     8	import androidx.lifecycle.viewModelScope
     9	import kotlinx.coroutines.CoroutineDispatcher
    10	import kotlinx.coroutines.Dispatchers
    11	import kotlinx.coroutines.flow.MutableStateFlow
    12	import kotlinx.coroutines.flow.SharingStarted
    13	import kotlinx.coroutines.flow.StateFlow
    14	import kotlinx.coroutines.flow.map
    15	import kotlinx.coroutines.flow.stateIn
    16	import kotlinx.coroutines.launch
    17	import kotlinx.coroutines.withContext
    18	import java.util.UUID
    19	
    20	class AiSettingsViewModel(
    21	    private val store: AiProviderStore,
    22	    private val clientDispatcher: CoroutineDispatcher = Dispatchers.IO,
    23	    private val factory: (AiProviderProfile, String) -> AiClient = { p, key -> AiProviderFactory.create(p, key) },
    24	) : ViewModel() {
    25	
    26	    val listState: StateFlow<AiProviderListState> = store.observe()
    27	        .map { snap ->
    28	            AiProviderListState(
    29	                snap.profiles.map { p ->
    30	                    AiProviderRow(p.id, p.name, active = p.id == snap.activeId, statusOk = true, detail = p.model.ifBlank { p.kind.defaultModel })
    31	                }
    32	            )
    33	        }
    34	        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), AiProviderListState())
    35	
    36	    private val _edit = MutableStateFlow<AiEditState?>(null)
    37	    val editState: StateFlow<AiEditState?> = _edit
    38	
    39	    // Bumped whenever the editor opens/closes or a new test starts — an in-flight test result is
    40	    // only applied if its generation still matches, so a stale Ok/Fail can't land on a different
    41	    // form (the user closed it, opened another provider, or re-tested).
    42	    private var testGen = 0
    43	
    44	    fun openAdd() { testGen++; _edit.value = AiEditState(editMode = false) }
    45	
    46	    fun openEdit(id: String) = viewModelScope.launch {
    47	        val p = store.list().firstOrNull { it.id == id } ?: return@launch
    48	        testGen++
    49	        _edit.value = AiEditState(
    50	            editMode = true, id = p.id, kind = p.kind, name = p.name, baseUrl = p.baseUrl, model = p.model,
    51	            temperature = p.temperature, maxTokens = p.maxTokens, keyAlreadySaved = true,
    52	        )
    53	    }
    54	
    55	    fun close() { testGen++; _edit.value = null }
    56	
    57	    fun update(transform: (AiEditState) -> AiEditState) { _edit.value = _edit.value?.let(transform) }
    58	
    59	    fun test() {
    60	        val s = _edit.value ?: return
    61	        if (!s.canTest) return
    62	        val gen = ++testGen
    63	        update { it.copy(test = AiConnTest.testing, testMessage = "") }
    64	        viewModelScope.launch {
    65	            // Key lookup + client creation + the network call all off the main thread.
    66	            val result = withContext(clientDispatcher) {
    67	                val key = if (s.apiKey.isNotBlank()) s.apiKey else s.id?.let { store.apiKey(it) } ?: ""
    68	                val profile = AiProviderProfile(
    69	                    id = s.id ?: "transient", name = s.name, kind = s.kind, baseUrl = s.effectiveBaseUrl,
    70	                    model = s.effectiveModel, temperature = s.temperature, maxTokens = s.maxTokens, encryptedApiKey = "",
    71	                )
    72	                runCatching { factory(profile, key).testConnection() }
    73	                    .getOrElse { AiTestResult.Fail(AiError.Offline, it.message ?: "failed") }
    74	            }
    75	            if (gen != testGen) return@launch  // superseded by a newer test / form open / close
    76	            update {
    77	                when (result) {
    78	                    is AiTestResult.Ok -> it.copy(test = AiConnTest.ok, testMessage = "Connected — the provider responded successfully.")
    79	                    is AiTestResult.Fail -> it.copy(test = AiConnTest.fail, testMessage = result.message)
    80	                }
    81	            }
    82	        }
    83	    }
    84	
    85	    fun save() {
    86	        val s = _edit.value ?: return
    87	        if (!s.canSave) return
    88	        viewModelScope.launch {
    89	            store.upsert(
    90	                id = s.id ?: UUID.randomUUID().toString(),
    91	                name = s.name, kind = s.kind, baseUrl = s.baseUrl, model = s.model,
    92	                temperature = s.temperature, maxTokens = s.maxTokens,
    93	                apiKey = s.apiKey.ifBlank { null },  // blank on edit = keep existing
    94	            )
    95	            _edit.value = null
    96	        }
    97	    }
    98	
    99	    fun delete() {
   100	        val id = _edit.value?.id ?: return
   101	        viewModelScope.launch { store.delete(id); _edit.value = null }
   102	    }
   103	
   104	    fun setActive(id: String) = viewModelScope.launch { store.setActive(id) }
   105	}
     1	// Purpose: feature #118 WI-1 (#110 Phase 3) — persists saved AI provider profiles + the active
     2	// selection. Profile metadata (name/kind/baseUrl/model/temperature/maxTokens) lives in DataStore
     3	// as a JSON list; the API key is kept ONLY as a SecretCipher token (the #116 KeystoreSecretCipher).
     4	// Reuses the #116 WebDavServerStore DataStore+SecretCipher credential pattern, adding an active-id
     5	// and a request-start `snapshot()` (a chat/test reads one consistent profile, not live mid-request
     6	// store reads). The key + auth headers are NEVER logged.
     7	package com.vreader.app.ai
     8	
     9	import androidx.datastore.core.DataStore
    10	import androidx.datastore.preferences.core.Preferences
    11	import androidx.datastore.preferences.core.edit
    12	import androidx.datastore.preferences.core.stringPreferencesKey
    13	import com.vreader.app.backup.net.SecretCipher
    14	import kotlinx.coroutines.flow.Flow
    15	import kotlinx.coroutines.flow.first
    16	import kotlinx.coroutines.flow.map
    17	import kotlinx.serialization.Serializable
    18	import kotlinx.serialization.json.Json
    19	
    20	/** A saved AI provider. `encryptedApiKey` is a [SecretCipher] token, never plaintext. */
    21	@Serializable
    22	data class AiProviderProfile(
    23	    val id: String,
    24	    val name: String,
    25	    val kind: AiProviderKind,
    26	    val baseUrl: String,
    27	    val model: String,
    28	    val temperature: Double = 0.7,
    29	    val maxTokens: Int = 2048,
    30	    val encryptedApiKey: String,
    31	)
    32	
    33	/** A consistent point-in-time view: the profiles + which is active. */
    34	data class AiProviderSnapshot(val profiles: List<AiProviderProfile>, val activeId: String?) {
    35	    val active: AiProviderProfile? get() = profiles.firstOrNull { it.id == activeId }
    36	}
    37	
    38	@Serializable
    39	private data class AiStoreState(val profiles: List<AiProviderProfile> = emptyList(), val activeId: String? = null)
    40	
    41	class AiProviderStore(
    42	    private val dataStore: DataStore<Preferences>,
    43	    private val cipher: SecretCipher,
    44	    private val json: Json = Json { ignoreUnknownKeys = true; encodeDefaults = true },
    45	) {
    46	    /** One consistent profiles + active-id view (read once at request start). */
    47	    suspend fun snapshot(): AiProviderSnapshot = read(dataStore.data.first()).toSnapshot()
    48	
    49	    fun observe(): Flow<AiProviderSnapshot> = dataStore.data.map { read(it).toSnapshot() }
    50	
    51	    suspend fun list(): List<AiProviderProfile> = snapshot().profiles
    52	
    53	    suspend fun activeProfile(): AiProviderProfile? = snapshot().active
    54	
    55	    /**
    56	     * Insert/update a profile by [id]. [apiKey] is the PLAINTEXT to encrypt; pass null on an edit
    57	     * that leaves the key unchanged (the existing ciphertext is kept). A brand-new id REQUIRES a
    58	     * key. The first profile added becomes active. Returns the saved profile (key encrypted).
    59	     */
    60	    suspend fun upsert(
    61	        id: String,
    62	        name: String,
    63	        kind: AiProviderKind,
    64	        baseUrl: String,
    65	        model: String,
    66	        temperature: Double,
    67	        maxTokens: Int,
    68	        apiKey: String?,
    69	    ): AiProviderProfile {
    70	        lateinit var saved: AiProviderProfile
    71	        dataStore.edit { prefs ->
    72	            val cur = read(prefs)
    73	            val existing = cur.profiles.firstOrNull { it.id == id }
    74	            val encrypted = when {
    75	                apiKey != null -> cipher.encrypt(apiKey)
    76	                existing != null -> existing.encryptedApiKey  // unchanged on edit
    77	                else -> throw IllegalArgumentException("a new provider ($id) requires an API key")
    78	            }
    79	            saved = AiProviderProfile(id, name, kind, baseUrl, model, temperature, maxTokens, encrypted)
    80	            val next = cur.profiles.filterNot { it.id == id } + saved
    81	            val activeId = cur.activeId ?: id  // first provider becomes active
    82	            prefs[KEY] = json.encodeToString(AiStoreState(next, activeId))
    83	        }
    84	        return saved
    85	    }
    86	
    87	    /** Remove a profile. If it was active, the active selection moves to the first remaining (or null). */
    88	    suspend fun delete(id: String) {
    89	        dataStore.edit { prefs ->
    90	            val cur = read(prefs)
    91	            val next = cur.profiles.filterNot { it.id == id }
    92	            val activeId = if (cur.activeId == id) next.firstOrNull()?.id else cur.activeId
    93	            prefs[KEY] = json.encodeToString(AiStoreState(next, activeId))
    94	        }
    95	    }
    96	
    97	    /** Select the active provider (no-op if the id isn't present). */
    98	    suspend fun setActive(id: String) {
    99	        dataStore.edit { prefs ->
   100	            val cur = read(prefs)
   101	            if (cur.profiles.any { it.id == id }) prefs[KEY] = json.encodeToString(cur.copy(activeId = id))
   102	        }
   103	    }
   104	
   105	    /** Decrypt the key from a CAPTURED [profile] — snapshot-consistent (no live store read). The
   106	     *  chat/test request path uses THIS with a profile from a single [snapshot], so it can't pair
   107	     *  snapshot metadata with a concurrently-edited/deleted key. */
   108	    fun apiKey(profile: AiProviderProfile): String = cipher.decrypt(profile.encryptedApiKey)
   109	
   110	    /** The decrypted API key for [id] via a live read, or null if absent. Convenience for UI flows
   111	     *  that aren't mid-request; the request path should prefer [apiKey] (profile). */
   112	    suspend fun apiKey(id: String): String? =
   113	        list().firstOrNull { it.id == id }?.let { cipher.decrypt(it.encryptedApiKey) }
   114	
   115	    private fun read(prefs: Preferences): AiStoreState {
   116	        val raw = prefs[KEY] ?: return AiStoreState()
   117	        return runCatching { json.decodeFromString<AiStoreState>(raw) }.getOrDefault(AiStoreState())
   118	    }
   119	
   120	    private fun AiStoreState.toSnapshot() = AiProviderSnapshot(profiles, activeId)
   121	
   122	    companion object {
   123	        private val KEY = stringPreferencesKey("ai_providers_json")
   124	    }
   125	}

exec
/bin/zsh -lc "rg -n \"\\.save\\(\\)|vm::save|AiSettingsViewModel\\(\" android/app/src | head -80; rg -n \"fun AiProviderEditSheet|onSave\" android/app/src/main/kotlin/com/vreader/app/ai -g '*.kt'" in /Users/ll/workspace/vreader
 succeeded in 0ms:
android/app/src/test/kotlin/com/vreader/app/opds/ui/OpdsSourcesViewModelTest.kt:90:        v.save(); advanceUntilIdle()
android/app/src/test/kotlin/com/vreader/app/opds/ui/OpdsSourcesViewModelTest.kt:130:        v.save(); advanceUntilIdle()
android/app/src/test/kotlin/com/vreader/app/ai/AiSettingsViewModelTest.kt:57:        AiSettingsViewModel(store, dispatcher) { _, _ -> FakeClient(result) }
android/app/src/test/kotlin/com/vreader/app/ai/AiSettingsViewModelTest.kt:66:        vm.save(); advanceUntilIdle()
android/app/src/androidTest/kotlin/com/vreader/app/opds/ui/OpdsUiRoundTripConnectedTest.kt:59:            sourcesVm.save()
android/app/src/main/kotlin/com/vreader/app/ai/AiSettingsViewModel.kt:20:class AiSettingsViewModel(
android/app/src/main/kotlin/com/vreader/app/ai/AiProviderEditSheet.kt:55:fun AiProviderEditSheet(
android/app/src/main/kotlin/com/vreader/app/ai/AiProviderEditSheet.kt:66:    onSave: () -> Unit = {},
android/app/src/main/kotlin/com/vreader/app/ai/AiProviderEditSheet.kt:79:                Box(Modifier.sizeIn(minWidth = 48.dp, minHeight = 48.dp).clickable(enabled = state.canSave, onClick = onSave).testTag("ai-save"), contentAlignment = Alignment.CenterEnd) {

exec
/bin/zsh -lc "nl -ba dev-docs/designs/vreader-fidelity-v1/project/vreader-bilingual.jsx | sed -n '20,165p;185,285p'; nl -ba dev-docs/designs/vreader-fidelity-v1/project/vreader-ai-provider-entry.jsx | sed -n '165,260p'" in /Users/ll/workspace/vreader
 succeeded in 0ms:
    20	  { k: 'French',   glyph: 'Fr', script: 'latin' },
    21	  { k: 'German',   glyph: 'De', script: 'latin' },
    22	  { k: 'Italian',  glyph: 'It', script: 'latin' },
    23	  { k: 'Arabic',   glyph: 'ع',  script: 'rtl' },
    24	  { k: 'Russian',  glyph: 'Ru', script: 'cyrillic' },
    25	];
    26	
    27	function BilingualSetupSheet({ theme, value, onChange, onClose, aiConfigured = true }) {
    28	  const t = theme;
    29	  const v = value || { lang: 'Chinese', granularity: 'paragraph' };
    30	  const update = (k, val) => onChange({ ...v, [k]: val });
    31	
    32	  return (
    33	    <Sheet theme={t} onClose={onClose} title="Bilingual mode" height={620}>
    34	      <div style={{ padding: '12px 22px 28px' }}>
    35	        {/* preview strip */}
    36	        <BilingualPreview t={t} lang={v.lang}/>
    37	
    38	        {/* target language */}
    39	        <div style={{ marginTop: 22 }}>
    40	          <SectionLabel theme={t}>Target language</SectionLabel>
    41	          <div style={{
    42	            marginTop: 10, display: 'grid',
    43	            gridTemplateColumns: 'repeat(3, 1fr)', gap: 8,
    44	          }}>
    45	            {BILINGUAL_LANGS.map(l => {
    46	              const active = l.k === v.lang;
    47	              return (
    48	                <button key={l.k} onClick={() => update('lang', l.k)} style={{
    49	                  display: 'flex', alignItems: 'center', gap: 8,
    50	                  padding: '10px 10px', borderRadius: 12, border: 'none',
    51	                  background: active
    52	                    ? (t.isDark ? `${t.accent}26` : `${t.accent}14`)
    53	                    : (t.isDark ? 'rgba(255,255,255,0.04)' : '#fff'),
    54	                  boxShadow: active
    55	                    ? `inset 0 0 0 1.5px ${t.accent}`
    56	                    : (t.isDark ? `inset 0 0 0 0.5px ${t.rule}` : `inset 0 0 0 0.5px ${t.rule}`),
    57	                  cursor: 'pointer',
    58	                }}>
    59	                  <span style={{
    60	                    width: 22, height: 22, borderRadius: 6, flexShrink: 0,
    61	                    display: 'flex', alignItems: 'center', justifyContent: 'center',
    62	                    background: active ? t.accent : (t.isDark ? 'rgba(255,255,255,0.08)' : 'rgba(0,0,0,0.06)'),
    63	                    color: active ? '#fff' : t.ink, fontWeight: 700,
    64	                    fontFamily: l.script === 'cjk' || l.script === 'rtl'
    65	                      ? '"Songti SC", "Source Han Serif", serif' : 'inherit',
    66	                    fontSize: l.script === 'cjk' ? 13 : 11,
    67	                  }}>{l.glyph}</span>
    68	                  <span style={{
    69	                    fontSize: 12.5, color: t.ink, fontWeight: active ? 600 : 500,
    70	                  }}>{l.k}</span>
    71	                </button>
    72	              );
    73	            })}
    74	          </div>
    75	        </div>
    76	
    77	        {/* granularity */}
    78	        <div style={{ marginTop: 22 }}>
    79	          <SectionLabel theme={t}>Granularity</SectionLabel>
    80	          <div style={{
    81	            display: 'flex', marginTop: 10, borderRadius: 12,
    82	            background: t.isDark ? 'rgba(255,255,255,0.06)' : 'rgba(0,0,0,0.05)',
    83	            padding: 3,
    84	          }}>
    85	            {[
    86	              { k: 'paragraph', label: 'Paragraph', sub: 'Translate after each ¶' },
    87	              { k: 'sentence',  label: 'Sentence',  sub: 'Translate after each sentence' },
    88	            ].map(o => (
    89	              <button key={o.k} onClick={() => update('granularity', o.k)} style={{
    90	                flex: 1, padding: '10px 10px', borderRadius: 10, border: 'none',
    91	                background: v.granularity === o.k ? (t.isDark ? '#3a3530' : '#fff') : 'transparent',
    92	                color: t.ink, fontFamily: 'inherit', cursor: 'pointer',
    93	                boxShadow: v.granularity === o.k ? '0 1px 2px rgba(0,0,0,0.08)' : 'none',
    94	                textAlign: 'center',
    95	              }}>
    96	                <div style={{ fontSize: 13, fontWeight: 600 }}>{o.label}</div>
    97	                <div style={{ fontSize: 10.5, color: t.sub, marginTop: 1 }}>{o.sub}</div>
    98	              </button>
    99	            ))}
   100	          </div>
   101	        </div>
   102	
   103	        {/* AI provider strip */}
   104	        <div style={{ marginTop: 22 }}>
   105	          <SectionLabel theme={t}>Translation engine</SectionLabel>
   106	          <div style={{
   107	            marginTop: 8, padding: '12px 14px', borderRadius: 12,
   108	            background: aiConfigured
   109	              ? (t.isDark ? 'rgba(255,255,255,0.04)' : '#fff')
   110	              : `${t.accent}10`,
   111	            border: aiConfigured ? `0.5px solid ${t.rule}` : `0.5px solid ${t.accent}55`,
   112	            display: 'flex', alignItems: 'center', gap: 12,
   113	          }}>
   114	            <div style={{
   115	              width: 28, height: 28, borderRadius: 14,
   116	              background: aiConfigured
   117	                ? `linear-gradient(135deg, ${t.accent}, ${t.accent}aa)`
   118	                : 'rgba(0,0,0,0.08)',
   119	              display: 'flex', alignItems: 'center', justifyContent: 'center',
   120	              flexShrink: 0,
   121	            }}>
   122	              <Icons.Sparkle size={14} color={aiConfigured ? '#fff' : t.sub} stroke={2}/>
   123	            </div>
   124	            <div style={{ flex: 1, minWidth: 0 }}>
   125	              <div style={{ fontSize: 13.5, color: t.ink, fontWeight: 600 }}>
   126	                {aiConfigured ? 'Claude · with this book\'s context' : 'No AI provider configured'}
   127	              </div>
   128	              <div style={{ fontSize: 11.5, color: t.sub, marginTop: 1 }}>
   129	                {aiConfigured
   130	                  ? 'Translations cached per paragraph, one page ahead.'
   131	                  : 'Bilingual mode needs an AI provider to translate.'}
   132	              </div>
   133	            </div>
   134	            <button style={{
   135	              padding: '5px 11px', borderRadius: 100, border: 'none',
   136	              background: aiConfigured
   137	                ? (t.isDark ? 'rgba(255,255,255,0.08)' : 'rgba(0,0,0,0.06)')
   138	                : t.accent,
   139	              color: aiConfigured ? t.ink : '#fff',
   140	              fontFamily: 'inherit', fontSize: 11.5, fontWeight: 600, cursor: 'pointer',
   141	              flexShrink: 0,
   142	            }}>{aiConfigured ? 'Change…' : 'Set up'}</button>
   143	          </div>
   144	        </div>
   145	
   146	        {/* CTA */}
   147	        <button onClick={onClose} style={{
   148	          width: '100%', marginTop: 22, padding: '14px 0', borderRadius: 14,
   149	          border: 'none', background: t.accent, color: '#fff',
   150	          fontFamily: 'inherit', fontSize: 15, fontWeight: 600, cursor: 'pointer',
   151	          boxShadow: `0 4px 14px ${t.accent}55`,
   152	        }}>Turn on bilingual mode</button>
   153	      </div>
   154	    </Sheet>
   155	  );
   156	}
   157	
   158	function BilingualPreview({ t, lang }) {
   159	  const samples = {
   160	    Chinese:  '凡是有钱的单身汉，总想娶位太太，这已经成了一条举世公认的真理。',
   161	    Japanese: '相当な財産を持っている独身の男性は妻を欲しがっているに違いない、というのは世間一般に認められた真理である。',
   162	    Korean:   '재산이 많은 독신 남성에게 아내가 필요하다는 것은 누구나 인정하는 진리이다.',
   163	    Spanish:  'Es una verdad universalmente reconocida que un hombre soltero en posesión de una buena fortuna necesita una esposa.',
   164	    French:   'C\'est une vérité universellement reconnue qu\'un homme célibataire possédant une bonne fortune doit avoir besoin d\'une épouse.',
   165	    German:   'Es ist eine allgemein anerkannte Wahrheit, dass ein lediger Mann im Besitz eines schönen Vermögens nach einer Frau verlangen muss.',
   185	      <div style={{
   186	        marginTop: 8, paddingLeft: 14, borderLeft: `2px solid ${t.accent}88`,
   187	        fontFamily: ff,
   188	        fontSize: 13, color: t.sub, lineHeight: 1.55,
   189	        direction: lang === 'Arabic' ? 'rtl' : 'ltr',
   190	      }}>{sample}</div>
   191	    </div>
   192	  );
   193	}
   194	
   195	// ────────────────────────────────────────────────────
   196	// Paragraph-interlinear renderer
   197	// Used by the reader when bilingual mode is on. Renders source + translation
   198	// stacked, one source paragraph followed by its translation.
   199	// ────────────────────────────────────────────────────
   200	function BilingualPageContent({ page, theme, fontFamily, fontSize, lineHeight, margin,
   201	                                pageDir, animating, pageIdx, lang = 'Chinese' }) {
   202	  const t = theme;
   203	  const ff = fontFamily === 'serif'
   204	    ? '"Source Serif 4", Georgia, "Times New Roman", serif'
   205	    : '"Inter", -apple-system, system-ui, sans-serif';
   206	  const translatedFF = (lang === 'Chinese' || lang === 'Japanese' || lang === 'Korean')
   207	    ? '"Songti SC", "Source Han Serif", serif'
   208	    : ff;
   209	  const isRTL = lang === 'Arabic';
   210	
   211	  const animTransform = animating
   212	    ? `translateX(${pageDir > 0 ? -8 : 8}%) ` : 'translateX(0) ';
   213	  const animOpacity = animating ? 0 : 1;
   214	
   215	  // Mock translations for the sample P&P paragraphs (matches vreader-data.jsx PP_PAGES)
   216	  const TRANSLATIONS = {
   217	    Chinese: {
   218	      'It is a truth universally acknowledged, that a single man in possession of a good fortune, must be in want of a wife.':
   219	        '凡是有钱的单身汉，总想娶位太太，这已经成了一条举世公认的真理。',
   220	      'However little known the feelings or views of such a man may be on his first entering a neighbourhood, this truth is so well fixed in the minds of the surrounding families, that he is considered as the rightful property of some one or other of their daughters.':
   221	        '这样的单身汉，每逢新搬到一个地方，四邻八舍虽然完全不了解他的性情如何，见解如何，可是，既然这样的一条真理早已在人们心目中根深蒂固，因此人们总是把他看作自己某一个女儿理所应得的一笔财产。',
   222	    },
   223	  };
   224	  const fallback = (en) => '【' + (lang === 'Chinese' ? '译文' : lang) + '】 ' + en.slice(0, 60) + '…';
   225	
   226	  return (
   227	    <div style={{
   228	      position: 'absolute', top: 76, bottom: 56, left: margin, right: margin,
   229	      overflow: 'hidden', transform: animTransform, opacity: animOpacity,
   230	      transition: 'transform 0.28s cubic-bezier(0.32, 0.72, 0, 1), opacity 0.22s ease-out',
   231	      direction: isRTL ? 'ltr' : 'ltr', // source is always LTR
   232	    }}>
   233	      {(pageIdx === 0 || page.chapter !== PP_PAGES[(pageIdx - 1 + PP_PAGES.length) % PP_PAGES.length].chapter) && (
   234	        <div style={{
   235	          fontFamily: '"Source Serif 4", Georgia, serif',
   236	          fontSize: 13, color: t.sub, letterSpacing: 2,
   237	          textTransform: 'uppercase', textAlign: 'center',
   238	          marginBottom: 18, marginTop: 8, fontWeight: 500,
   239	        }}>{page.chapter}</div>
   240	      )}
   241	      {page.paragraphs.map((para, i) => {
   242	        const tr = (TRANSLATIONS[lang] && TRANSLATIONS[lang][para]) || fallback(para);
   243	        return (
   244	          <div key={i} style={{ marginBottom: lineHeight * fontSize * 0.55 }}>
   245	            <p style={{
   246	              fontFamily: ff, fontSize, lineHeight, color: t.ink, margin: 0,
   247	              textIndent: i === 0 ? 0 : `${fontSize * 1.4}px`,
   248	              textAlign: 'justify', hyphens: 'auto',
   249	            }}>
   250	              {i === 0 && (
   251	                <span style={{
   252	                  fontFamily: '"Source Serif 4", Georgia, serif',
   253	                  fontSize: fontSize * 2.6, lineHeight: 0.85,
   254	                  float: 'left', marginRight: 6, marginTop: 4,
   255	                  color: t.accent, fontWeight: 600,
   256	                }}>{para[0]}</span>
   257	              )}
   258	              {i === 0 ? para.slice(1) : para}
   259	            </p>
   260	            <p style={{
   261	              fontFamily: translatedFF,
   262	              fontSize: fontSize * 0.88, lineHeight: 1.55,
   263	              color: t.sub, margin: '6px 0 0',
   264	              paddingLeft: fontSize * 1.0, paddingRight: isRTL ? 0 : 0,
   265	              direction: isRTL ? 'rtl' : 'ltr',
   266	              textAlign: isRTL ? 'right' : 'left',
   267	              borderLeft: isRTL ? 'none' : `2px solid ${t.accent}55`,
   268	              borderRight: isRTL ? `2px solid ${t.accent}55` : 'none',
   269	              paddingLeft: isRTL ? 0 : fontSize * 0.7,
   270	              paddingRight: isRTL ? fontSize * 0.7 : 0,
   271	            }}>{tr}</p>
   272	          </div>
   273	        );
   274	      })}
   275	    </div>
   276	  );
   277	}
   278	
   279	// ────────────────────────────────────────────────────
   280	// The "EN ↔ 中" pill shown in the reader top chrome when bilingual is on
   281	// ────────────────────────────────────────────────────
   282	function BilingualPill({ theme, lang }) {
   283	  const t = theme;
   284	  const glyph = (BILINGUAL_LANGS.find(l => l.k === lang) || BILINGUAL_LANGS[0]).glyph;
   285	  return (
   165	  return (
   166	    <div style={{ padding: '14px 18px 28px' }}>
   167	      {/* why-you're-here context — the bilingual thread, kept visible */}
   168	      <div style={{
   169	        display: 'flex', alignItems: 'center', gap: 10,
   170	        padding: '10px 12px', borderRadius: 10,
   171	        background: `${t.accent}10`, border: `0.5px solid ${t.accent}33`,
   172	        marginBottom: 18,
   173	      }}>
   174	        <div style={{
   175	          width: 22, height: 22, borderRadius: 11, flexShrink: 0,
   176	          background: `${t.accent}1f`, display: 'flex', alignItems: 'center', justifyContent: 'center',
   177	        }}>
   178	          <Icons.Translate size={13} color={t.accent} stroke={1.9}/>
   179	        </div>
   180	        <div style={{ fontSize: 11.5, color: t.ink, lineHeight: 1.35 }}>
   181	          Choose the provider <b style={{ fontWeight: 600 }}>bilingual mode</b> will use to translate this book.
   182	        </div>
   183	      </div>
   184	
   185	      {empty ? (
   186	        <div style={{ textAlign: 'center', padding: '24px 12px 8px' }}>
   187	          <div style={{
   188	            width: 54, height: 54, borderRadius: 27, margin: '0 auto 14px',
   189	            background: `linear-gradient(135deg, ${t.accent}, ${t.accent}aa)`,
   190	            display: 'flex', alignItems: 'center', justifyContent: 'center',
   191	            boxShadow: `0 6px 18px ${t.accent}44`,
   192	          }}>
   193	            <Icons.Sparkle size={26} color="#fff" stroke={1.7}/>
   194	          </div>
   195	          <div style={{ fontFamily: AIPE_SERIF, fontSize: 18, fontWeight: 600, color: t.ink }}>
   196	            No providers yet
   197	          </div>
   198	          <div style={{ fontSize: 12.5, color: t.sub, lineHeight: 1.5, maxWidth: 268, margin: '6px auto 20px' }}>
   199	            Add Claude, OpenAI, or any OpenAI-compatible endpoint. Your API key is stored in the device keychain — never synced.
   200	          </div>
   201	          <button onClick={onAdd} style={{
   202	            display: 'inline-flex', alignItems: 'center', gap: 7,
   203	            padding: '11px 20px', borderRadius: 100, border: 'none',
   204	            background: t.accent, color: '#fff',
   205	            fontFamily: 'inherit', fontSize: 14, fontWeight: 600, cursor: 'pointer',
   206	            boxShadow: `0 4px 14px ${t.accent}55`,
   207	          }}>
   208	            <Icons.Plus size={17} color="#fff" stroke={2.2}/>Add provider
   209	          </button>
   210	        </div>
   211	      ) : (
   212	        <div>
   213	          <SectionLabel theme={t}>Providers</SectionLabel>
   214	          <div style={{
   215	            marginTop: 8, borderRadius: 14, overflow: 'hidden',
   216	            background: t.isDark ? 'rgba(255,255,255,0.04)' : '#fff',
   217	            boxShadow: t.isDark ? 'none' : '0 1px 0 rgba(0,0,0,0.04)',
   218	          }}>
   219	            {providers.map((p) => (
   220	              <ProviderRow key={p.id} theme={t} name={p.name} model={p.model}
   221	                selected={p.id === selectedId} onClick={() => onSelect && onSelect(p.id)}/>
   222	            ))}
   223	            <div onClick={onAdd} style={{
   224	              display: 'flex', alignItems: 'center', gap: 12, padding: '12px 14px', cursor: 'pointer',
   225	            }}>
   226	              <div style={{
   227	                width: 30, height: 30, borderRadius: 8, flexShrink: 0,
   228	                background: t.isDark ? 'rgba(255,255,255,0.08)' : 'rgba(0,0,0,0.06)',
   229	                display: 'flex', alignItems: 'center', justifyContent: 'center',
   230	              }}>
   231	                <Icons.Plus size={18} color={t.accent} stroke={2.2}/>
   232	              </div>
   233	              <div style={{ flex: 1, fontSize: 15, color: t.accent, fontWeight: 500 }}>Add provider</div>
   234	            </div>
   235	          </div>
   236	          <div style={{ fontSize: 11.5, color: t.sub, lineHeight: 1.45, padding: '10px 4px 0' }}>
   237	            Tap a provider to use it for translating this book.
   238	          </div>
   239	        </div>
   240	      )}
   241	    </div>
   242	  );
   243	}
   244	
   245	function AIProvidersSheet({ theme, providers = [], selectedId, onBack, onAdd, onSelect, trailing, height = 620 }) {
   246	  return (
   247	    <NavSheet theme={theme} height={height} title="AI Providers" backLabel="Bilingual" onBack={onBack} trailing={trailing}>
   248	      <AIProvidersSheetBody theme={theme} providers={providers} selectedId={selectedId} onAdd={onAdd} onSelect={onSelect}/>
   249	    </NavSheet>
   250	  );
   251	}
   252	
   253	// ────────────────────────────────────────────────────
   254	// ALTERNATIVE C — inline expansion of the engine strip.
   255	// Collapsed = the unconfigured strip; expanded = a minimal provider+key form
   256	// in place. Shows why it can't host the real editor without diverging.
   257	// ────────────────────────────────────────────────────
   258	function EngineStripInline({ theme, expanded }) {
   259	  const t = theme;
   260	  const seg = ['Claude', 'OpenAI', 'Custom'];

exec
/bin/zsh -lc "nl -ba dev-docs/plans/20260710-feature-131-android-bilingual-interlinear.md | sed -n '188,212p;238,268p;355,378p'; nl -ba android/app/src/main/kotlin/com/vreader/app/data/VReaderDatabase.kt | sed -n '1,245p'; rg -n \"data class BookEntity|@Entity\\(|fingerprintKey|foreignKeys|Index\\(\" android/app/src/main/kotlin/com/vreader/app/data -g '*.kt'" in /Users/ll/workspace/vreader
 succeeded in 0ms:
   188	- `bilingual/BilingualViewModel.kt` — `StateFlow<BilingualUiState>` with `enabled`, `targetLanguage`, `granularity`, `needsSetupSheet`, `aiConfigured`, `translationsByUnit`, `inFlightUnits`, `unavailableUnits`, `errorUnit`. Setters + `dismissSetupSheet`, `onPositionChanged(charOffsetUTF16)`, `retryUnit(unit)`, and the EPUB direct-block entry `onEpubBlocksEnumerated(unit, blocks)` (M1, below). Generation/epoch-guarded prefetch (current + next unit); a **per-unit single-flight job registry** (M2); dual-cancellation handling (M2). Port of iOS `BilingualReadingViewModel` (`prefetchTasks: [TranslationUnitID: Task]`, `BilingualReadingViewModel.swift:141`) + `+Prefetch`. Split to `BilingualPrefetchController.kt` if it nears ~300 lines. No `style` field.
   189	
   190	**Room (translation cache):**
   191	
   192	- `data/ChapterTranslationEntity.kt` — `@Entity(tableName="chapter_translations", indices=[Index("bookKey")], foreignKeys=[FK→books.fingerprintKey ON DELETE CASCADE])`. **`@PrimaryKey val lookupKey: String`** (Room requires a PK; project pattern `@PrimaryKey` + `@Upsert`, verified `BookEntity` `@PrimaryKey val fingerprintKey`, Entities.kt:24). `lookupKey` = `bookKey|unitStorageKey|targetLanguage|promptVersion`. Columns: `lookupKey` (PK), `bookKey`, `unitStorageKey`, `targetLanguage`, `promptVersion`, `translatedJson`, `sourceParagraphCount`, `createdAt`. Mirrors iOS `ChapterTranslationRecord.lookupKey` (`book|unit|lang|prompt`, profile-agnostic — Bug #342). `sourceParagraphCount` is load-bearing for H2 (stores the enumerate's count on the `translatePreSegmented` path so `cachedTranslation(expectedSegmentCount:)` restores). **The exact `MIGRATION_8_9` DDL is authored in WI-2 — see below.**
   193	- `data/ChapterTranslationDao.kt` — `getByLookupKey(key)`, `@Upsert suspend fun upsert(row)`, `deleteByLookupKey(key)`.
   194	- `bilingual/ChapterTranslationStore.kt` — coroutine wrapper returning a `CachedTranslation` (segments decoded from JSON), keeping Room entities off the boundary (iOS `ChapterTranslationStore` precedent).
   195	
   196	**Cache-identity (reconciled with iOS parity):** the 4-part key `book|unit|lang|promptVersion` is profile-AGNOSTIC / style-agnostic (Bug #342). Style is descoped (§3) so no `s=` component. **Granularity is paragraph-only in v1** (round-4 H3): `promptVersion = "bilingual-v1|g=paragraph"` in v1 (the `g=` component is always `paragraph`). The composite `g=` slot is retained in the key format so a future granularity is a different cache row by construction (closes the iOS #344 "sentence silently ignored" class ahead of time), but v1 never emits `g=sentence`. A language change cancels in-flight jobs, bumps the VM generation, clears shaped `translationsByUnit`, and forces a correctly-keyed re-fetch (WI-6).
   197	
   198	**DI / factory (verified live):** `AiProviderFactory` is an `object` with `create(profile, apiKey, dispatcher = Dispatchers.IO): AiClient` (verified, `AiProviderFactory.kt:10`). `ChapterTranslationPrefetcher` takes its OWN injected `clientFactory: (AiProviderProfile, String) -> AiClient` param **defaulting to `AiProviderFactory::create`**, overridden with a fake in tests.
   199	
   200	**UI (Compose — every state depicted, reproducing `vreader-bilingual.jsx` + `vreader-ai-provider-entry.jsx`):**
   201	
   202	- `bilingual/BilingualSetupSheet.kt` — reproduces `vreader-bilingual.jsx`'s `BilingualSetupSheet` (lines 27–156) EXACTLY, with the granularity divergence: header; a preview strip (`BilingualPreview`); a language grid over `BILINGUAL_LANGS` (glyph tiles, selected accent); a **Granularity** segmented control **descoped to Paragraph-only in v1** ("Translate after each ¶"; the Sentence option is not rendered in v1 — round-4 H3, tracked by the sentence design gate); a **Translation engine** strip (configured: "Claude · with this book's context" + "Change…"; unconfigured: "No AI provider configured" + "Bilingual mode needs an AI provider to translate." + "Set up"); the "Turn on bilingual mode" CTA. **No Style control, no provider/model card, no term-overrides toggle, no cost footer** (those belong to the `vreader-ai-android.jsx` sheet, not reproduced — §3). The `aiConfigured` flag comes from `BilingualAiReadiness.resolve`. The "Set up"/"Change…" CTA routes to `ReaderAiProvidersSheet` (wired in WI-9).
   203	- `bilingual/ReaderAiProvidersSheet.kt` — **NEW (folded in; the Android analog of iOS `ReaderAIProvidersView`; round-4 High-4 rewritten).** The Variant A scoped in-reader AI Providers sheet, reproducing `vreader-ai-provider-entry.jsx` `AIProvidersSheet` + `AIProvidersSheetBody` + `NavSheet` (nav bar `‹ Bilingual` leading + centered "AI Providers" title, `vreader-ai-provider-entry.jsx:247`). **Round-4 High-4: the fold-in CANNOT be "reuse `AiProviderListScreen` verbatim."** `AiProviderListScreen` owns its OWN full `NavScreen(title="AI Providers", onBack)` (`AiProviderListScreen.kt:59`), a generic `AiEmptyState` ("Connect an AI provider" / "One key unlocks…", :84/:87), and **row-tap-as-EDIT** (`ProviderRow` → `onEdit(p.id)`, :105) with **no checked-active-tap-to-select** — it cannot reproduce the designed reader-scoped `‹ Bilingual` nav, the bilingual-context empty state, the checked-active row, or tap-to-SELECT. So the fold-in splits into **(a)/(b)/(c)**:
   204	  - **(a) EDITOR reused VERBATIM.** `AiProviderEditSheet` (the canonical add/edit modal, Kind / Name / Endpoint / Sampling / API Key / Test Connection) is presented UNCHANGED from the #118 Library path — that reuse is confirmed fine (`reader-ai-provider-entry.md:49–52`, :63–65).
   205	  - **(b) The scoped LIST is a NEW reader-specific presentation** (`ReaderAiProvidersList`, in this file) built over the **SHARED `AiSettingsViewModel` state** (`listState`, verified `AiSettingsViewModel.kt:26`) + shared row/cell components, reproducing: the reader-scoped nav (`‹ Bilingual` back label, "AI Providers" title — `NavSheet` at jsx:247, NOT `AiProviderListScreen`'s own `NavScreen`); the **bilingual-context empty state** ("Choose the provider bilingual mode will use to translate this book." context strip + "No providers yet" + "Add provider" CTA — jsx:180–209); the **checked-active row** (`selected={p.id === selectedId}` — jsx:221; the live `AiProviderListState`/`AiProviderRow` already carries `active` per row, `AiSettingsViewModel.kt:30`); and **tap-to-SELECT** (`onSelect(p.id)` → `vm.setActive(id)` — jsx:221/237). It does **NOT** reuse `AiProviderListScreen`'s `NavScreen`/chrome/`AiEmptyState`/`ProviderRow`-tap-edit.
   206	  - **(c) A save-result seam** (round-4 High-4): `AiSettingsViewModel.save()` today returns Unit and upserts async (generates `s.id ?: UUID.randomUUID().toString()` *inside* the launched coroutine, then `_edit.value = null`, no saved ID — `AiSettingsViewModel.kt:85–97`), so WI-AIP cannot deterministically `setActive(savedId)` + pop-on-success by reusing it verbatim (popping immediately races the async upsert; observing list state can't distinguish the new profile). **Note:** `AiProviderStore.upsert` ALREADY returns the saved profile (`suspend fun upsert(...): AiProviderProfile`, "Returns the saved profile", `AiProviderStore.kt:58/70/84`) — the ID is present at the store layer; only the VM discards it. So the seam is an **additive completion/result signal on `AiSettingsViewModel.save()`** (or a thin WI-AIP wrapper) returning the saved provider ID (from `store.upsert(...).id`), so WI-AIP can `setActive(savedId)` + pop-on-success **after** the upsert commits — no race. The #118 VM is currently production-UNWIRED (only test-referenced — verified), and this feature wires it to production for the FIRST time, so an additive save-result seam is safe and appropriate.
   207	  - **Behavior per the nav model:** empty → "Add provider" → `AiProviderEditSheet` → Save → `save()` returns the saved ID → `store.setActive(savedId)` (first-provider-active is already the store's default `activeId = cur.activeId ?: id`, AiProviderStore.kt:81; the explicit `setActive(savedId)` guarantees the freshly-saved provider is the engine even if others existed) → **pop the whole stack** back to the bilingual sheet, engine strip now "Claude · configured / Change…". `‹ Bilingual` without adding → unconfigured, **no state mutated**. "Change…" → the SAME sheet, populated, current provider checked, tap a row → `setActive`. No consent card, no feature-flag toggle, no readiness tracker (iOS #82, deferred).
   208	- `bilingual/BilingualInterlinearBody.kt` — the Compose render surface for the **TXT/MD host ONLY** (round-2 M2). Renders per the **one-lazy-item-per-chunk `Column`** H2 render contract (source chunk unchanged as the first `Column` child; translation(s) anchored to chunk `i` as muted non-registered `Text` siblings in the SAME `Column`): muted `Text`, accent left-border, `fontSize*0.88`, CJK font for cjk scripts, RTL handling for Arabic (per `BilingualPageContent`, `vreader-bilingual.jsx:200–277`). Consumes the host-neutral `BilingualRenderState` DTO. Loading state ("Translating chapter… N%" + per-segment dim), error state ("Couldn't translate" + Retry), partial/offline (`unavailableUnits`): source-only silent fallback (iOS Decision 2). Includes the **translation gesture-exclusion** (round-4 H2) so a long-press on a translation child does not route to `hitAt`'s nearest-source-chunk fallback. **NOT the EPUB render surface.**
   209	- `bilingual/BilingualRenderState.kt` — the host-neutral state DTO shared by the Compose body and the EPUB adapter (round-2 M2): per-unit `{ segments: List<String>?, phase: Loaded|Loading(fraction)|Error|SourceOnly }`. Compose and EPUB share the state/value types, NOT the composable body.
   210	- `bilingual/EpubBilingualJs.kt` (WI-0-gated) — the EPUB render surface (round-2 M2). Pure Kotlin builder producing JS strings for `navigator.evaluateJavascript(...)`: `enumScript` (enumerate current-resource leaf blocks → JSON `[{id,text}]`), `injectScript(blockId, translationText)` (translation DOM node after the block; CSP-safe: `textContent`/`createTextNode`, never `innerHTML` string-concat; RTL/CJK via class + injected `<style>`), `clearScript()` (idempotent removal). Escaping done in Kotlin (JSON-encode every interpolated string). No Compose. Consumes `BilingualRenderState`.
   211	- `bilingual/EpubBilingualController.kt` (WI-0-gated) — **the single owner of EPUB units (M1, below).** The runtime actor that serializes enumerate→(cache-restore|translate)→inject/clear against the navigator using WI-0's chosen mechanism (a single mutex OR a monotonic navigator-session token); checks the session token after every suspended JS/AI call; clears BEFORE publication teardown; re-applies on the identified production re-apply signal.
   212	- `bilingual/BilingualPill.kt` — the `EN ↔ 中` reader-top-chrome pill (per `vreader-reader.jsx` + `vreader-bilingual.jsx` `BilingualPill`:282–305). Rendered by #132's top chrome; #131 provides the composable, #132's surface hosts it (§4).
   238	
   239	- **Dual-cancellation across the service/VM boundary:** both the service AND the VM handle **BOTH** native `CancellationException` **AND** the typed `ChapterTranslationError.Cancelled` **before** generic error mapping — matching iOS `ChapterTranslationService.swift:359–364` (which catches `is CancellationError` and `ChapterTranslationError.cancelled` separately, both re-throwing `cancelled`). A cancelled stale request MUST NOT surface as `errorUnit` (it is discarded).
   240	- **Per-unit single-flight job registry (VM):** a `prefetchTasks: MutableMap<TranslationUnitId, Job>` (iOS `prefetchTasks: [TranslationUnitID: Task]`, `BilingualReadingViewModel.swift:141`, cancelled/removed on disable/unit-change at :165). A NEW request for a unit **cancels-or-joins** the prior job (a stale prior is cancelled and awaited so it cannot run overlapping translations or Room writes), keyed by unit. Rapid retry/navigation cannot run overlapping translations for the same unit. `retryUnit(unit)` goes through the same registry. Tests: a mid-flight cancel discards (no `errorUnit`, no partial cache row); a rapid re-trigger for the same unit does not double-write.
   241	
   242	### Modified files
   243	
   244	- `data/VReaderDatabase.kt` — add `ChapterTranslationEntity` to `@Database entities`, bump `version` **8 → 9** (the live DB is v8, migrations `MIGRATION_1_2`..`MIGRATION_7_8`, `ALL_MIGRATIONS` ends at `MIGRATION_7_8` — verified VReaderDatabase.kt:29,224–228), add **`MIGRATION_8_9`** (exact DDL below — gap A), **append `MIGRATION_8_9` to `ALL_MIGRATIONS` after `MIGRATION_7_8`**, add `abstract fun chapterTranslationDao()`. Purely additive.
   245	
   246	  **`MIGRATION_8_9` exact DDL (gap A — BINDING; modeled on the verified `MIGRATION_6_7` `search_index_state` shape at VReaderDatabase.kt:154–169, whose DDL Room's PRAGMA validation already accepts):**
   247	
   248	  ```
   249	  val MIGRATION_8_9: Migration = object : Migration(8, 9) {
   250	      override fun migrate(db: SupportSQLiteDatabase) {
   251	          db.execSQL(
   252	              "CREATE TABLE IF NOT EXISTS `chapter_translations` (" +
   253	                  "`lookupKey` TEXT NOT NULL, " +
   254	                  "`bookKey` TEXT NOT NULL, " +
   255	                  "`unitStorageKey` TEXT NOT NULL, " +
   256	                  "`targetLanguage` TEXT NOT NULL, " +
   257	                  "`promptVersion` TEXT NOT NULL, " +
   258	                  "`translatedJson` TEXT NOT NULL, " +
   259	                  "`sourceParagraphCount` INTEGER NOT NULL, " +
   260	                  "`createdAt` INTEGER NOT NULL, " +
   261	                  "PRIMARY KEY(`lookupKey`), " +
   262	                  "FOREIGN KEY(`bookKey`) REFERENCES `books`(`fingerprintKey`) " +
   263	                  "ON UPDATE NO ACTION ON DELETE CASCADE )"
   264	          )
   265	          db.execSQL(
   266	              "CREATE INDEX IF NOT EXISTS `index_chapter_translations_bookKey` " +
   267	                  "ON `chapter_translations` (`bookKey`)"
   268	          )
   355	**WI-3 (foundational): `ChapterTranslationService`** against a fake `AiClient`. Both `cachedTranslation` overloads (incl. the `expectedSegmentCount` divergence restore — H2) + `translate` + `translatePreSegmented`. **Dual-cancellation (native + typed `Cancelled`) BEFORE generic mapping (M2).** Deps: WI-1, WI-2. Tests: cache hit → zero client calls; miss → translate + write; decode fail → per-segment fallback; one-chunk fail → source-only that chunk (others translated, NOT cached); all-chunks fail → throw; native-cancel → `Cancelled` (no write); typed-`Cancelled`-from-chunk → `Cancelled` (no write); ensureActive-before-write; `AiError` mapping incl. `Config`/`InsecureUrl` → `ProviderFailed`; `translatePreSegmented` full-success caches under the enumerate count; partial degrade NOT cached; all-fail throws; `cachedTranslation(expectedSegmentCount)` returns on stored-count match, null on mismatch, needs no provider.
   356	
   357	**WI-4a (foundational): `ChapterTextProvider` (TXT/MD) + `ChapterTranslationPrefetcher` + `BilingualAiReadiness`.** `TxtChapterTextProvider` builds the document-global segment `Utf16Span`s once (via `paragraphRanges` — paragraph only, H1/H3), groups into windows, resolves `unitContaining(charOffsetUTF16)` via segment-start binary search, `sourceSegments(unit)`. Prefetcher: `prefetch` + `prefetchDirect` + `cachedDirect`; resolves active profile from `snapshot()`, decrypts snapshot-consistent, builds client via the injected factory param (default `AiProviderFactory::create`), constructs `AiRequest` with **`model = profile.model.ifBlank { profile.kind.defaultModel }` (M3)**. Readiness = active profile with non-empty decrypted key; **cipher failure → not-ready, never a crash.** Fake store + fake factory. Deps: WI-1, WI-3. Tests (all `Utf16Span`-based): unit resolution + clamp + empty; **one-chunk document (no trailing newline) → its segment translation renders, not dropped (H1)**; **final-chunk anchor → renders (H1)**; **exact-boundary → correct anchor (H1)**; **EOF anchor (`span.endExclusive == text.length`) → last chunk, no clamp-collapse (H1)**; paragraph spanning MANY chunks → one segment/one unit, anchored to the last chunk (Low-2); a >4000-char paragraph hard-split across chunks → one segment; CR/LF/CRLF; MD markers; locator→unit mapping; `unitAfter` end→null; **source-byte parity while disabled**; cache-hit-no-profile still returns (#306); no-profile miss → `ProviderFailed`; `prefetchDirect` 1:1; `cachedDirect` restores with zero provider calls; **blank `profile.model` → `AiRequest.model == kind.defaultModel` (M3 regression)**; readiness true/false; empty-key → false; no-active-with-profiles-present → false (H3); cipher-throw → readiness false (no crash). (Sentence-multi-in-one-chunk is NOT a v1 render test — the v1 provider uses `paragraphRanges` only; `sentenceRanges` behavior is covered in WI-1's reserved-foundational unit tests.)
   358	
   359	**WI-4b (foundational — shared DI/factory, incl. `AiProviderStore` in `AppContainer`): AppContainer bilingual + AI-config graph.** `AppContainer` **now constructs `AiProviderStore`** (DataStore + #116 `KeystoreSecretCipher`, following the `readerSettingsStore` convention — this is #131's change, not an external feature's) and provides `ChapterTranslationStore`, `PerBookBilingualStore`, `ChapterTranslationService`, `ChapterTranslationPrefetcher`, an `AiSettingsViewModel` factory (for WI-AIP), and the `BilingualViewModel` factory. Deps: **WI-4a** (no external dep — #136 closed). Tests: container resolves the bilingual + AI-config graph; `AiProviderStore` resolves and round-trips a profile; the prefetcher's injected factory defaults to `AiProviderFactory::create`.
   360	
   361	**WI-5 (behavioral): `PerBookBilingualStore` + `BilingualViewModel` state core.** Store per book (enabled/targetLanguage/granularity — granularity pinned `paragraph` in v1, no style); VM setters (persist + first-enable `needsSetupSheet`); `aiConfigured` from `BilingualAiReadiness.resolve` over an injected snapshot; language change clears cache-shaped state + bumps generation. Injected prefetcher/snapshot seams (Medium-4). Turbine tests: first-enable raises sheet; re-enable persisted does not; disable clears; language change resets; `aiConfigured` true/false from readiness; round-trip through store; no style field; granularity persists as `paragraph`. Deps: WI-1 (+ store).
   362	
   363	**WI-6 (behavioral): VM prefetch trigger + generation/cancellation + single-flight (M2).** `onPositionChanged(charOffsetUTF16)` derives current unit (TXT/MD only), dedupes, prefetches current+next; a monotonic position-request sequence checked after every suspension; **per-unit single-flight `prefetchTasks: Map<TranslationUnitId, Job>` (a new request cancels/joins the prior — M2)**; a captured language/provider snapshot per launch; generation bumps on disable/language/unit-change discard stale; **BOTH `CancellationException` AND typed `ChapterTranslationError.Cancelled` handled BEFORE generic error mapping (M2)**; a cancelled stale request does NOT surface as `errorUnit`; `Offline`→`unavailableUnits`; transient failure leaves unit unfetched + clears anchor to retry; `retryUnit` routes through the registry. The EPUB `onEpubBlocksEnumerated` entry is present but EPUB prefetch is owned by the controller (Medium-1); the VM's position-driven `prefetch` dispatches TXT/MD units only. Fake prefetcher (Medium-4 seam). Deps: WI-4a, WI-4b, WI-5. Tests: current+next on unit change; same-unit no-op; cancel-mid discards stale (no `errorUnit`); typed-`Cancelled` discards (not `errorUnit`); rapid re-trigger same unit → single-flight, no double-write; offline→unavailable; failure→retry-able; `retryUnit` re-fetches.
   364	
   365	**WI-7a (behavioral): Compose UI — setup sheet + interlinear body (TXT/MD) + pill.** Reproduce `vreader-bilingual.jsx` (setup sheet: language grid / **Paragraph-only Granularity control (round-4 H3)** / preview / engine strip configured+unconfigured; body: the translation rendered **inside the anchor chunk's `Column` as a muted non-registered `Text` child** per the round-4 H2 render contract — translated / loading N%+dimmed / error+Retry / offline source-only; pill). Consumes the host-neutral `BilingualRenderState` DTO. Light+dark. Compose UI tests each state, incl. **paragraph interlinear renders a translation child after a paragraph's last source chunk (depicted)**; **the setup-sheet Granularity control shows Paragraph only, no Sentence option (H3)**. Deps: WI-5 (state shape). NO Style control; the unconfigured "Set up" CTA renders and (in WI-9) routes to the Variant A sheet.
   366	
   367	**WI-7b (behavioral, CONDITIONAL — only if WI-0 = go): EPUB render adapter (DOM injection, NOT Compose — M2) + direct-block ownership (M1).** `EpubBilingualJs` (enum/inject/clear JS builders, CSP-safe escaping) + `EpubBilingualController` (the serialization actor / session token AND the **single-owner enumerate→cachedDirect/prefetchDirect→guarded-commit sequence — Medium-1**) + `EpubChapterTextProvider`, wired into `ReaderActivity`, driving DOM from the shared `BilingualRenderState` DTO. Uses `prefetchDirect`/`cachedDirect` for the count-divergence path (H2). Depends on WI-6 (VM state) and WI-4b (DI); the WI-7a UI dependency is only the shared `BilingualRenderState`/value types. Connected test on a real EPUB (seeded cache): enable → injects; disable → cleared; reflow/href-change/fragment-recreation/activity-recreation → re-applies from cache (zero provider calls) via `cachedDirect`; count-divergence handled (direct path); **the regular TXT/MD prefetch path is never invoked for an EPUB unit (Medium-1)**. Unit tests: JS escaping/CSP-safe insertion, RTL/CJK style, empty translations, loading cleanup, idempotent replacement, source-only fallback, stale-session-token commit discarded (no `errorUnit`). Deps: WI-0, WI-3, WI-4a, WI-4b, WI-6, (shared types from WI-7a). (If WI-0 = no-go, dropped; box D ships TXT/MD-only, tracked.)
   368	
   369	**WI-AIP (behavioral — the folded-in Variant A AI Providers sheet; round-4 H4 rewritten): `ReaderAiProvidersSheet`.** The scoped in-reader "AI Providers" push sheet (nav bar `‹ Bilingual` + "AI Providers" title) reproducing `vreader-ai-provider-entry.jsx` `AIProvidersSheet`/`AIProvidersSheetBody`/`NavSheet`. Per round-4 H4:
   370	  - **(a)** present `AiProviderEditSheet` VERBATIM from #118 (Kind/Name/Endpoint/Sampling/API Key/Test Connection unchanged).
   371	  - **(b)** a NEW `ReaderAiProvidersList` presentation over the SHARED `AiSettingsViewModel.listState` (verified `AiSettingsViewModel.kt:26`; each `AiProviderRow` already carries `active`, :30) + shared row/cell components — reproducing the reader-scoped `‹ Bilingual` nav (`NavSheet`, jsx:247, NOT `AiProviderListScreen`'s `NavScreen`), the bilingual-context empty state ("Choose the provider bilingual mode will use to translate this book." + "No providers yet" + "Add provider" — jsx:180–209), the **checked-active row** (`selected = row.active` — jsx:221), and **tap-to-SELECT** (`onSelect(id) → vm.setActive(id)` — jsx:221/237). It does NOT reuse `AiProviderListScreen`'s NavScreen/chrome/`AiEmptyState`/`ProviderRow`-tap-edit.
   372	  - **(c)** the **save-result seam**: `AiSettingsViewModel.save()` (or a thin WI-AIP wrapper) is extended to return the saved provider ID (from `store.upsert(...).id`, which the store already returns — `AiProviderStore.kt:58/84`), so on first Save → `store.setActive(savedId)` → pop the whole stack back to the bilingual sheet (engine strip now "configured / Change…"), **deterministically, after the upsert commits (no race)**.
   373	  `‹ Bilingual` without adding → unconfigured, no state mutated. "Change…" → populated list, current provider checked, tap row → `setActive`. No consent/flag surface (Android has none). Deps: WI-4b (for `AiProviderStore` + `AiSettingsViewModel` in `AppContainer`), WI-7a (bilingual sheet host). Tests (Compose + connected): the scoped list renders **`‹ Bilingual` back label** + **bilingual-context empty copy** + **checked active row** + **tap-selects (`setActive`)**; empty → Add → Save → **save→result-id→`setActive`→pop deterministic (no race)** → bilingual strip configured; `‹ Bilingual` without adding → strip unconfigured, snapshot unchanged; "Change…" → populated, current checked; editor reused verbatim (no divergent form).
   374	
   375	**WI-8 (behavioral): `TxtReaderActivity` integration.** Wire VM into the `items(count = document.chunkCount, key = { it })` loop as **muted non-registered translation `Text` children inside each anchor chunk's wrapping `Column`, source chunk byte-unchanged, the loop + keys UNCHANGED so lazy-index==chunk-index is preserved (round-4 H2)** + the translation **gesture-exclusion** (round-4 H2) + position-change (`charOffsetUTF16`) + setup-sheet. `originalFormat`-gated (TXT/MD). Uses WI-4b's DI. **#129 VERIFIED — straight edit.** Connected test (fake `AiClient` seam): enable → setup → confirm → interlinear from seeded cache; **enabled-mode source-chunk selection registrations UNCHANGED vs disabled (H2)**; **highlights/annotation-washes/read-aloud-wash still key off source chunks (H2)**; **with bilingual ON — position-save round-trips to the same chunk; bookmark/search/scrubber/TTS jumps land on the correct chunk (lazy-index==chunk-index preserved — round-4 H2)**; **a long-press on translation text does NOT select (gesture exclusion — round-4 H2)**; a translation child is non-selectable, does not perturb source offsets (H2); disable → source-selection byte-parity; reopen persists enabled + renders from cache with zero client calls; **paragraph-spanning-many-chunks renders exactly one translation inside its last chunk's `Column` (H1/Low-2)**; **one-chunk/final-chunk anchors render (H1)**; MD source mapping. Deps: WI-6, WI-7a, WI-4b.
   376	
   377	**WI-9 (behavioral): entry wiring + acceptance.** Mount `BilingualPill` in #132's VERIFIED top chrome; extend `readerMoreRows(...)` to supply the #134 VERIFIED More-menu `MoreActionId.BILINGUAL` toggle (`MoreRow.Toggle` `on`/`onToggle`, or `MoreRow.Disabled` "Configure AI provider first" when not configured) wired to the VM; **wire the setup sheet's "Set up"/"Change…" affordance → the #131-owned `ReaderAiProvidersSheet` (Variant A)**. Full acceptance across EPUB (if WI-7b landed) + TXT/MD, including the fresh-user path `unconfigured → Set up (→ Variant A AI Providers sheet) → add provider → Save → return → enable → translate` (now #131-owned end-to-end). **Flip box D to done ONLY for provider/model/granularity(paragraph) + the Style-descope AND Sentence-descope notes; file the follow-up checklist amendment; do NOT claim full box-D parity.** The DONE flip **no longer waits on #136** (closed). Update `docs/architecture.md` (bilingual pipeline + the new `chapter_translations` schema + `AiProviderStore` + bilingual services in `AppContainer` + the Variant A AI Providers sheet). → DONE. Deps: WI-8, WI-AIP, WI-7b (if go), feat:#132, feat:#134.
   378	
     1	// Purpose: Room database + schema-versioned migration scaffold — feature #106 WI-3.
     2	// Version 8 is the current schema; v1 was the initial books+positions baseline and
     3	// MIGRATION_1_2 is the worked example of the additive-migration pattern (adds
     4	// books.lastOpenedAt). Subsequent additive migrations: 2→3 daily_reading (#122),
     5	// 3→4 annotations (#123), 4→5 collections (#127), 5→6 books.author (#128 search),
     6	// 6→7 the FTS search index (search_sections + search_sections_fts + search_index_state
     7	// + search_sections_staging, all #128 WI-4), 7→8 the composite UNIQUE (bookKey, profileKey)
     8	// index on `bookmarks` — preceded by an in-migration dedupe of pre-existing duplicate rows so
     9	// the unique index can't fail on a legacy duplicate (feature #135 WI-3). The migration round-trip
    10	// test (VReaderDatabaseMigrationTest) guards them. Future schema changes append a
    11	// Migration(n, n+1) to ALL_MIGRATIONS and bump `version`.
    12	package com.vreader.app.data
    13	
    14	import android.content.Context
    15	import androidx.room.Database
    16	import androidx.room.Room
    17	import androidx.room.RoomDatabase
    18	import androidx.room.migration.Migration
    19	import androidx.sqlite.db.SupportSQLiteDatabase
    20	
    21	@Database(
    22	    entities = [
    23	        BookEntity::class, ReadingPositionEntity::class, DailyReadingEntity::class,
    24	        HighlightEntity::class, AnnotationNoteEntity::class, BookmarkEntity::class,
    25	        CollectionEntity::class, BookCollectionCrossRef::class,
    26	        SearchSectionEntity::class, SearchSectionFtsEntity::class,
    27	        SearchIndexStateEntity::class, SearchStagingEntity::class,
    28	    ],
    29	    version = 8,
    30	    exportSchema = true,
    31	)
    32	abstract class VReaderDatabase : RoomDatabase() {
    33	    abstract fun bookDao(): BookDao
    34	    abstract fun readingPositionDao(): ReadingPositionDao
    35	    abstract fun readingStatsDao(): ReadingStatsDao
    36	    abstract fun annotationDao(): AnnotationDao
    37	    abstract fun collectionDao(): CollectionDao
    38	    abstract fun searchDao(): SearchDao
    39	
    40	    companion object {
    41	        private const val DB_NAME = "vreader.db"
    42	
    43	        /** v1 → v2: add the nullable `lastOpenedAt` recents column to `books`. */
    44	        val MIGRATION_1_2: Migration = object : Migration(1, 2) {
    45	            override fun migrate(db: SupportSQLiteDatabase) {
    46	                db.execSQL("ALTER TABLE books ADD COLUMN lastOpenedAt INTEGER")
    47	            }
    48	        }
    49	
    50	        /** v2 → v3: feature #122 — add the additive `daily_reading` per-day/per-book stats table +
    51	         *  its bookKey index. No data transform. DDL matches Room's generated schema exactly. */
    52	        val MIGRATION_2_3: Migration = object : Migration(2, 3) {
    53	            override fun migrate(db: SupportSQLiteDatabase) {
    54	                db.execSQL(
    55	                    "CREATE TABLE IF NOT EXISTS `daily_reading` (`date` TEXT NOT NULL, `bookKey` TEXT NOT NULL, " +
    56	                        "`minutes` INTEGER NOT NULL, PRIMARY KEY(`date`, `bookKey`))",
    57	                )
    58	                db.execSQL("CREATE INDEX IF NOT EXISTS `index_daily_reading_bookKey` ON `daily_reading` (`bookKey`)")
    59	            }
    60	        }
    61	
    62	        /** v3 → v4: feature #123 — add the additive `highlights`, `annotation_notes`, and `bookmarks`
    63	         *  annotation tables (each FK→books ON DELETE CASCADE; highlights has the unique
    64	         *  `(profileKey, anchorKey)` dedupe index). No data transform. DDL matches Room's generated
    65	         *  schema for v4 exactly (the migration test opens the real Room DB, whose structural PRAGMA
    66	         *  validation catches any drift). */
    67	        val MIGRATION_3_4: Migration = object : Migration(3, 4) {
    68	            override fun migrate(db: SupportSQLiteDatabase) {
    69	                db.execSQL(
    70	                    "CREATE TABLE IF NOT EXISTS `highlights` (`highlightId` TEXT NOT NULL, " +
    71	                        "`bookKey` TEXT NOT NULL, `profileKey` TEXT NOT NULL, `anchorKey` TEXT NOT NULL, " +
    72	                        "`color` TEXT NOT NULL, `selectedText` TEXT NOT NULL, `note` TEXT, " +
    73	                        "`locatorJSON` TEXT NOT NULL, `anchorJSON` TEXT, `createdAt` INTEGER NOT NULL, " +
    74	                        "`updatedAt` INTEGER NOT NULL, PRIMARY KEY(`highlightId`), " +
    75	                        "FOREIGN KEY(`bookKey`) REFERENCES `books`(`fingerprintKey`) " +
    76	                        "ON UPDATE NO ACTION ON DELETE CASCADE )",
    77	                )
    78	                db.execSQL("CREATE INDEX IF NOT EXISTS `index_highlights_bookKey` ON `highlights` (`bookKey`)")
    79	                db.execSQL(
    80	                    "CREATE UNIQUE INDEX IF NOT EXISTS `index_highlights_profileKey_anchorKey` " +
    81	                        "ON `highlights` (`profileKey`, `anchorKey`)",
    82	                )
    83	                db.execSQL(
    84	                    "CREATE TABLE IF NOT EXISTS `annotation_notes` (`noteId` TEXT NOT NULL, " +
    85	                        "`bookKey` TEXT NOT NULL, `profileKey` TEXT NOT NULL, `content` TEXT NOT NULL, " +
    86	                        "`locatorJSON` TEXT NOT NULL, `anchorJSON` TEXT, `createdAt` INTEGER NOT NULL, " +
    87	                        "`updatedAt` INTEGER NOT NULL, PRIMARY KEY(`noteId`), " +
    88	                        "FOREIGN KEY(`bookKey`) REFERENCES `books`(`fingerprintKey`) " +
    89	                        "ON UPDATE NO ACTION ON DELETE CASCADE )",
    90	                )
    91	                db.execSQL(
    92	                    "CREATE INDEX IF NOT EXISTS `index_annotation_notes_bookKey` " +
    93	                        "ON `annotation_notes` (`bookKey`)",
    94	                )
    95	                db.execSQL(
    96	                    "CREATE TABLE IF NOT EXISTS `bookmarks` (`bookmarkId` TEXT NOT NULL, " +
    97	                        "`bookKey` TEXT NOT NULL, `profileKey` TEXT NOT NULL, `title` TEXT, " +
    98	                        "`locatorJSON` TEXT NOT NULL, `createdAt` INTEGER NOT NULL, " +
    99	                        "`updatedAt` INTEGER NOT NULL, PRIMARY KEY(`bookmarkId`), " +
   100	                        "FOREIGN KEY(`bookKey`) REFERENCES `books`(`fingerprintKey`) " +
   101	                        "ON UPDATE NO ACTION ON DELETE CASCADE )",
   102	                )
   103	                db.execSQL("CREATE INDEX IF NOT EXISTS `index_bookmarks_bookKey` ON `bookmarks` (`bookKey`)")
   104	            }
   105	        }
   106	
   107	        /** v4 → v5: feature #127 — add the additive `collections` table (unique `nameKey` index) +
   108	         *  the `book_collection` many-to-many join (composite PK, both FKs ON DELETE CASCADE, a
   109	         *  `collectionId` index for the reverse lookup). No data transform. DDL matches Room's generated
   110	         *  v5 schema exactly (the migration test opens the real Room DB, whose structural PRAGMA
   111	         *  validation catches any drift). */
   112	        val MIGRATION_4_5: Migration = object : Migration(4, 5) {
   113	            override fun migrate(db: SupportSQLiteDatabase) {
   114	                db.execSQL(
   115	                    "CREATE TABLE IF NOT EXISTS `collections` (`id` TEXT NOT NULL, `name` TEXT NOT NULL, " +
   116	                        "`nameKey` TEXT NOT NULL, `createdAt` INTEGER NOT NULL, PRIMARY KEY(`id`))",
   117	                )
   118	                db.execSQL(
   119	                    "CREATE UNIQUE INDEX IF NOT EXISTS `index_collections_nameKey` ON `collections` (`nameKey`)",
   120	                )
   121	                db.execSQL(
   122	                    "CREATE TABLE IF NOT EXISTS `book_collection` (`bookKey` TEXT NOT NULL, " +
   123	                        "`collectionId` TEXT NOT NULL, PRIMARY KEY(`bookKey`, `collectionId`), " +
   124	                        "FOREIGN KEY(`bookKey`) REFERENCES `books`(`fingerprintKey`) " +
   125	                        "ON UPDATE NO ACTION ON DELETE CASCADE , " +
   126	                        "FOREIGN KEY(`collectionId`) REFERENCES `collections`(`id`) " +
   127	                        "ON UPDATE NO ACTION ON DELETE CASCADE )",
   128	                )
   129	                db.execSQL(
   130	                    "CREATE INDEX IF NOT EXISTS `index_book_collection_collectionId` " +
   131	                        "ON `book_collection` (`collectionId`)",
   132	                )
   133	            }
   134	        }
   135	
   136	        /** v5 → v6: feature #128 — add the nullable `author` column to `books` (library search).
   137	         *  Purely additive; migrated rows read `author = null` until a backfill or restore sets it. */
   138	        val MIGRATION_5_6: Migration = object : Migration(5, 6) {
   139	            override fun migrate(db: SupportSQLiteDatabase) {
   140	                db.execSQL("ALTER TABLE books ADD COLUMN author TEXT")
   141	            }
   142	        }
   143	
   144	        /** v6 → v7: feature #128 WI-4 — add the cross-book search index (all in the one `vreader.db`):
   145	         *  `search_sections` (+ bookKey index + FK→books CASCADE), its FTS4/unicode61 content-table
   146	         *  shadow `search_sections_fts`, `search_index_state` (+ FK→books CASCADE), and the transient
   147	         *  `search_sections_staging` buffer (+ bookKey index + FK→books CASCADE). The migration ships
   148	         *  the base + FTS VIRTUAL tables only; Room recreates the FTS content-table sync triggers when
   149	         *  it opens the DB. DDL matches Room's generated v7 schema exactly (the migration test opens the
   150	         *  real Room DB, whose structural PRAGMA validation catches any drift). No data transform. */
   151	        val MIGRATION_6_7: Migration = object : Migration(6, 7) {
   152	            override fun migrate(db: SupportSQLiteDatabase) {
   153	                db.execSQL(
   154	                    "CREATE TABLE IF NOT EXISTS `search_sections` (`id` INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL, " +
   155	                        "`bookKey` TEXT NOT NULL, `sectionIndex` INTEGER NOT NULL, `chunkOrdinal` INTEGER NOT NULL, " +
   156	                        "`sectionTitle` TEXT, `text` TEXT NOT NULL, `indexedText` TEXT NOT NULL, " +
   157	                        "FOREIGN KEY(`bookKey`) REFERENCES `books`(`fingerprintKey`) " +
   158	                        "ON UPDATE NO ACTION ON DELETE CASCADE )",
   159	                )
   160	                db.execSQL("CREATE INDEX IF NOT EXISTS `index_search_sections_bookKey` ON `search_sections` (`bookKey`)")
   161	                db.execSQL(
   162	                    "CREATE VIRTUAL TABLE IF NOT EXISTS `search_sections_fts` USING FTS4(" +
   163	                        "`indexedText` TEXT NOT NULL, tokenize=unicode61, content=`search_sections`)",
   164	                )
   165	                db.execSQL(
   166	                    "CREATE TABLE IF NOT EXISTS `search_index_state` (`bookKey` TEXT NOT NULL, " +
   167	                        "`indexerVersion` INTEGER NOT NULL, `indexedAt` INTEGER NOT NULL, `status` TEXT NOT NULL, " +
   168	                        "PRIMARY KEY(`bookKey`), FOREIGN KEY(`bookKey`) REFERENCES `books`(`fingerprintKey`) " +
   169	                        "ON UPDATE NO ACTION ON DELETE CASCADE )",
   170	                )
   171	                db.execSQL(
   172	                    "CREATE TABLE IF NOT EXISTS `search_sections_staging` (`id` INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL, " +
   173	                        "`bookKey` TEXT NOT NULL, `sectionIndex` INTEGER NOT NULL, `chunkOrdinal` INTEGER NOT NULL, " +
   174	                        "`sectionTitle` TEXT, `text` TEXT NOT NULL, `indexedText` TEXT NOT NULL, " +
   175	                        "FOREIGN KEY(`bookKey`) REFERENCES `books`(`fingerprintKey`) " +
   176	                        "ON UPDATE NO ACTION ON DELETE CASCADE )",
   177	                )
   178	                db.execSQL(
   179	                    "CREATE INDEX IF NOT EXISTS `index_search_sections_staging_bookKey` " +
   180	                        "ON `search_sections_staging` (`bookKey`)",
   181	                )
   182	            }
   183	        }
   184	
   185	        /** v7 → v8: feature #135 WI-3 — make re-bookmarking the same position idempotent by adding a
   186	         *  composite UNIQUE index on `bookmarks (bookKey, profileKey)` (the atomic-toggle enforcer,
   187	         *  mirroring the highlights `(profileKey, anchorKey)` dedupe precedent).
   188	         *
   189	         *  A pre-#135 create path (`upsertBookmark`, UUID-keyed) could have produced DUPLICATE rows at
   190	         *  the same `(bookKey, profileKey)`; `CREATE UNIQUE INDEX` would FAIL on such a duplicate. So
   191	         *  the migration first DEDUPES — deleting every duplicate LOSER, keeping a DETERMINISTIC winner
   192	         *  per `(bookKey, profileKey)`: the row with the greatest `updatedAt`, tie-broken by the
   193	         *  greatest `createdAt`, then the LOWEST `bookmarkId` (a total, stable order). This is a
   194	         *  targeted dedupe — a non-duplicate row (unique `(bookKey, profileKey)`) is never deleted, and
   195	         *  no other table is touched. THEN the unique index is created, matching Room's generated name
   196	         *  + columns (`index_bookmarks_bookKey_profileKey` on `(bookKey, profileKey)`) exactly, so
   197	         *  Room's structural PRAGMA validation passes. DDL is idempotent (`IF NOT EXISTS`). */
   198	        val MIGRATION_7_8: Migration = object : Migration(7, 8) {
   199	            override fun migrate(db: SupportSQLiteDatabase) {
   200	                // 1) Dedupe: delete every row that is NOT the deterministic winner within its
   201	                //    (bookKey, profileKey) group. The winner is the row whose (updatedAt, createdAt,
   202	                //    -rowid-preference-on-bookmarkId) is greatest — expressed as: a row is a loser iff
   203	                //    another row in the same group ranks strictly higher by (updatedAt DESC,
   204	                //    createdAt DESC, bookmarkId ASC).
   205	                db.execSQL(
   206	                    "DELETE FROM `bookmarks` WHERE `bookmarkId` IN (" +
   207	                        "SELECT b.`bookmarkId` FROM `bookmarks` b JOIN `bookmarks` w " +
   208	                        "ON b.`bookKey` = w.`bookKey` AND b.`profileKey` = w.`profileKey` " +
   209	                        "AND b.`bookmarkId` <> w.`bookmarkId` " +
   210	                        "WHERE (w.`updatedAt` > b.`updatedAt`) " +
   211	                        "OR (w.`updatedAt` = b.`updatedAt` AND w.`createdAt` > b.`createdAt`) " +
   212	                        "OR (w.`updatedAt` = b.`updatedAt` AND w.`createdAt` = b.`createdAt` " +
   213	                        "AND w.`bookmarkId` < b.`bookmarkId`))",
   214	                )
   215	                // 2) Now that each (bookKey, profileKey) is unique, create the unique index.
   216	                db.execSQL(
   217	                    "CREATE UNIQUE INDEX IF NOT EXISTS `index_bookmarks_bookKey_profileKey` " +
   218	                        "ON `bookmarks` (`bookKey`, `profileKey`)",
   219	                )
   220	            }
   221	        }
   222	
   223	        /** All registered migrations, oldest first. Append future Migration(n,n+1) here. */
   224	        val ALL_MIGRATIONS: Array<Migration> =
   225	            arrayOf(
   226	                MIGRATION_1_2, MIGRATION_2_3, MIGRATION_3_4, MIGRATION_4_5,
   227	                MIGRATION_5_6, MIGRATION_6_7, MIGRATION_7_8,
   228	            )
   229	
   230	        /** The production on-disk database (app-private storage). */
   231	        fun build(context: Context): VReaderDatabase =
   232	            Room.databaseBuilder(context.applicationContext, VReaderDatabase::class.java, DB_NAME)
   233	                .addMigrations(*ALL_MIGRATIONS)
   234	                .build()
   235	    }
   236	}
android/app/src/main/kotlin/com/vreader/app/data/SearchDao.kt:63:    @Query("SELECT EXISTS(SELECT 1 FROM books WHERE fingerprintKey = :bookKey)")
android/app/src/main/kotlin/com/vreader/app/data/SearchDao.kt:80:            "LEFT JOIN search_index_state s ON s.bookKey = b.fingerprintKey " +
android/app/src/main/kotlin/com/vreader/app/data/SearchDao.kt:90:            "LEFT JOIN search_index_state s ON s.bookKey = b.fingerprintKey " +
android/app/src/main/kotlin/com/vreader/app/data/SearchDao.kt:220:    @Query("UPDATE books SET author = :author WHERE fingerprintKey = :bookKey AND author IS NULL")
android/app/src/main/kotlin/com/vreader/app/data/Daos.kt:34:    @Query("SELECT * FROM books WHERE fingerprintKey = :key")
android/app/src/main/kotlin/com/vreader/app/data/Daos.kt:38:    // Ordered by fingerprintKey (NOT the library-display addedAt) so a repeat backup of unchanged
android/app/src/main/kotlin/com/vreader/app/data/Daos.kt:40:    @Query("SELECT * FROM books ORDER BY fingerprintKey")
android/app/src/main/kotlin/com/vreader/app/data/Daos.kt:43:    @Query("DELETE FROM books WHERE fingerprintKey = :key")
android/app/src/main/kotlin/com/vreader/app/data/Daos.kt:46:    @Query("UPDATE books SET lastOpenedAt = :openedAt WHERE fingerprintKey = :key")
android/app/src/main/kotlin/com/vreader/app/data/Daos.kt:52:    @Query("UPDATE books SET author = :author WHERE fingerprintKey = :key AND author IS NULL")
android/app/src/main/kotlin/com/vreader/app/data/Daos.kt:66:            "WHERE fingerprintKey = :key",
android/app/src/main/kotlin/com/vreader/app/data/Daos.kt:87:                key = book.fingerprintKey,
android/app/src/main/kotlin/com/vreader/app/data/Daos.kt:105:            "author = COALESCE(:manifestAuthor, author) WHERE fingerprintKey = :key",
android/app/src/main/kotlin/com/vreader/app/data/Daos.kt:121:    @Query("SELECT * FROM reading_positions WHERE fingerprintKey = :key")
android/app/src/main/kotlin/com/vreader/app/data/Daos.kt:124:    // feature #116 WI-3 — all saved positions, for the backup collector. Ordered by fingerprintKey
android/app/src/main/kotlin/com/vreader/app/data/Daos.kt:126:    @Query("SELECT * FROM reading_positions ORDER BY fingerprintKey")
android/app/src/main/kotlin/com/vreader/app/data/Daos.kt:129:    @Query("DELETE FROM reading_positions WHERE fingerprintKey = :key")
android/app/src/main/kotlin/com/vreader/app/data/CollectionEntities.kt:7:// (iOS rejects duplicates case-insensitively). Membership is a many-to-many to `books` by fingerprintKey.
android/app/src/main/kotlin/com/vreader/app/data/CollectionEntities.kt:16:@Entity(
android/app/src/main/kotlin/com/vreader/app/data/CollectionEntities.kt:18:    indices = [Index(value = ["nameKey"], unique = true)],
android/app/src/main/kotlin/com/vreader/app/data/CollectionEntities.kt:33:@Entity(
android/app/src/main/kotlin/com/vreader/app/data/CollectionEntities.kt:36:    foreignKeys = [
android/app/src/main/kotlin/com/vreader/app/data/CollectionEntities.kt:39:            parentColumns = ["fingerprintKey"],
android/app/src/main/kotlin/com/vreader/app/data/CollectionEntities.kt:50:    indices = [Index("collectionId")],
android/app/src/main/kotlin/com/vreader/app/data/CollectionEntities.kt:53:    val bookKey: String,        // fingerprintKey (FK → books)
android/app/src/main/kotlin/com/vreader/app/data/SearchEntities.kt:35:@Entity(
android/app/src/main/kotlin/com/vreader/app/data/SearchEntities.kt:37:    foreignKeys = [
android/app/src/main/kotlin/com/vreader/app/data/SearchEntities.kt:40:            parentColumns = ["fingerprintKey"],
android/app/src/main/kotlin/com/vreader/app/data/SearchEntities.kt:45:    indices = [Index("bookKey")],
android/app/src/main/kotlin/com/vreader/app/data/SearchEntities.kt:65:@Entity(tableName = "search_sections_fts")
android/app/src/main/kotlin/com/vreader/app/data/SearchEntities.kt:78:@Entity(
android/app/src/main/kotlin/com/vreader/app/data/SearchEntities.kt:80:    foreignKeys = [
android/app/src/main/kotlin/com/vreader/app/data/SearchEntities.kt:83:            parentColumns = ["fingerprintKey"],
android/app/src/main/kotlin/com/vreader/app/data/SearchEntities.kt:103:@Entity(
android/app/src/main/kotlin/com/vreader/app/data/SearchEntities.kt:105:    foreignKeys = [
android/app/src/main/kotlin/com/vreader/app/data/SearchEntities.kt:108:            parentColumns = ["fingerprintKey"],
android/app/src/main/kotlin/com/vreader/app/data/SearchEntities.kt:113:    indices = [Index("bookKey")],
android/app/src/main/kotlin/com/vreader/app/data/Entities.kt:22:@Entity(tableName = "books")
android/app/src/main/kotlin/com/vreader/app/data/Entities.kt:23:data class BookEntity(
android/app/src/main/kotlin/com/vreader/app/data/Entities.kt:24:    @PrimaryKey val fingerprintKey: String,
android/app/src/main/kotlin/com/vreader/app/data/Entities.kt:39: * fingerprintKey). Storing the entire envelope (not flattened columns) is the
android/app/src/main/kotlin/com/vreader/app/data/Entities.kt:43: * column, kept for dedup/sync lookups. `fingerprintKey` is both PK and the FK child
android/app/src/main/kotlin/com/vreader/app/data/Entities.kt:46:@Entity(
android/app/src/main/kotlin/com/vreader/app/data/Entities.kt:48:    foreignKeys = [
android/app/src/main/kotlin/com/vreader/app/data/Entities.kt:51:            parentColumns = ["fingerprintKey"],
android/app/src/main/kotlin/com/vreader/app/data/Entities.kt:52:            childColumns = ["fingerprintKey"],
android/app/src/main/kotlin/com/vreader/app/data/Entities.kt:58:    @PrimaryKey val fingerprintKey: String,
android/app/src/main/kotlin/com/vreader/app/data/Entities.kt:68: * per-book dashboard table joins live titles and omits orphans). An `@Index("bookKey")` supports the
android/app/src/main/kotlin/com/vreader/app/data/Entities.kt:71:@Entity(tableName = "daily_reading", primaryKeys = ["date", "bookKey"], indices = [Index("bookKey")])
android/app/src/main/kotlin/com/vreader/app/data/Entities.kt:74:    val bookKey: String,   // fingerprintKey
android/app/src/main/kotlin/com/vreader/app/data/Entities.kt:92:@Entity(
android/app/src/main/kotlin/com/vreader/app/data/Entities.kt:94:    foreignKeys = [
android/app/src/main/kotlin/com/vreader/app/data/Entities.kt:97:            parentColumns = ["fingerprintKey"],
android/app/src/main/kotlin/com/vreader/app/data/Entities.kt:102:    indices = [Index("bookKey"), Index(value = ["profileKey", "anchorKey"], unique = true)],
android/app/src/main/kotlin/com/vreader/app/data/Entities.kt:106:    val bookKey: String,                   // fingerprintKey (FK)
android/app/src/main/kotlin/com/vreader/app/data/Entities.kt:124:@Entity(
android/app/src/main/kotlin/com/vreader/app/data/Entities.kt:126:    foreignKeys = [
android/app/src/main/kotlin/com/vreader/app/data/Entities.kt:129:            parentColumns = ["fingerprintKey"],
android/app/src/main/kotlin/com/vreader/app/data/Entities.kt:134:    indices = [Index("bookKey")],
android/app/src/main/kotlin/com/vreader/app/data/Entities.kt:157:@Entity(
android/app/src/main/kotlin/com/vreader/app/data/Entities.kt:159:    foreignKeys = [
android/app/src/main/kotlin/com/vreader/app/data/Entities.kt:162:            parentColumns = ["fingerprintKey"],
android/app/src/main/kotlin/com/vreader/app/data/Entities.kt:167:    indices = [Index("bookKey"), Index(value = ["bookKey", "profileKey"], unique = true)],
android/app/src/main/kotlin/com/vreader/app/data/CollectionDao.kt:63:            "SELECT :bookKey, :collectionId WHERE EXISTS (SELECT 1 FROM books WHERE fingerprintKey = :bookKey)",
android/app/src/main/kotlin/com/vreader/app/data/CollectionDao.kt:73:    /** The book fingerprintKeys in a collection (reverse lookup, served by the collectionId index). */
android/app/src/main/kotlin/com/vreader/app/data/VReaderDatabase.kt:75:                        "FOREIGN KEY(`bookKey`) REFERENCES `books`(`fingerprintKey`) " +
android/app/src/main/kotlin/com/vreader/app/data/VReaderDatabase.kt:88:                        "FOREIGN KEY(`bookKey`) REFERENCES `books`(`fingerprintKey`) " +
android/app/src/main/kotlin/com/vreader/app/data/VReaderDatabase.kt:100:                        "FOREIGN KEY(`bookKey`) REFERENCES `books`(`fingerprintKey`) " +
android/app/src/main/kotlin/com/vreader/app/data/VReaderDatabase.kt:124:                        "FOREIGN KEY(`bookKey`) REFERENCES `books`(`fingerprintKey`) " +
android/app/src/main/kotlin/com/vreader/app/data/VReaderDatabase.kt:157:                        "FOREIGN KEY(`bookKey`) REFERENCES `books`(`fingerprintKey`) " +
android/app/src/main/kotlin/com/vreader/app/data/VReaderDatabase.kt:168:                        "PRIMARY KEY(`bookKey`), FOREIGN KEY(`bookKey`) REFERENCES `books`(`fingerprintKey`) " +
android/app/src/main/kotlin/com/vreader/app/data/VReaderDatabase.kt:175:                        "FOREIGN KEY(`bookKey`) REFERENCES `books`(`fingerprintKey`) " +
android/app/src/main/kotlin/com/vreader/app/data/BookImporter.kt:45:     * Idempotent: re-importing identical bytes yields the same `fingerprintKey` and
android/app/src/main/kotlin/com/vreader/app/data/BookImporter.kt:95:                        fingerprintKey = key,
android/app/src/main/kotlin/com/vreader/app/data/LibraryRepository.kt:17: * `BookRecord`). `fingerprintKey` is the canonical identity.
android/app/src/main/kotlin/com/vreader/app/data/LibraryRepository.kt:20:    val fingerprintKey: String,
android/app/src/main/kotlin/com/vreader/app/data/LibraryRepository.kt:38:    val fingerprintKey: String,
android/app/src/main/kotlin/com/vreader/app/data/LibraryRepository.kt:60:            ReadingPositionRecord(e.fingerprintKey, e.toEnvelope(json), e.updatedAt)
android/app/src/main/kotlin/com/vreader/app/data/LibraryRepository.kt:85:    suspend fun findBook(fingerprintKey: String): Book? = bookDao.find(fingerprintKey)?.let(::toBook)
android/app/src/main/kotlin/com/vreader/app/data/LibraryRepository.kt:87:    suspend fun deleteBook(fingerprintKey: String) = bookDao.delete(fingerprintKey)
android/app/src/main/kotlin/com/vreader/app/data/LibraryRepository.kt:89:    suspend fun markOpened(fingerprintKey: String, openedAt: Long) =
android/app/src/main/kotlin/com/vreader/app/data/LibraryRepository.kt:90:        bookDao.markOpened(fingerprintKey, openedAt)
android/app/src/main/kotlin/com/vreader/app/data/LibraryRepository.kt:107:    suspend fun loadPosition(fingerprintKey: String): VReaderLocator? =
android/app/src/main/kotlin/com/vreader/app/data/LibraryRepository.kt:108:        positionDao.find(fingerprintKey)?.toEnvelope(json)
android/app/src/main/kotlin/com/vreader/app/data/LibraryRepository.kt:110:    suspend fun clearPosition(fingerprintKey: String) = positionDao.delete(fingerprintKey)
android/app/src/main/kotlin/com/vreader/app/data/LibraryRepository.kt:115:        fingerprintKey = e.fingerprintKey,
android/app/src/main/kotlin/com/vreader/app/data/LibraryRepository.kt:128:        fingerprintKey = fingerprintKey,
android/app/src/main/kotlin/com/vreader/app/data/LibraryRepository.kt:146:            fingerprintKey = fingerprintKey,

exec
/bin/zsh -lc "nl -ba dev-docs/plans/20260710-feature-131-android-bilingual-interlinear.md | sed -n '246,276p;342,355p;365,378p'; nl -ba android/app/src/main/kotlin/com/vreader/app/data/VReaderDatabase.kt | sed -n '1,45p'; nl -ba android/app/src/main/kotlin/com/vreader/app/data/Entities.kt | sed -n '20,62p;88,142p'; nl -ba docs/architecture.md | sed -n '1,40p'; rg -n \"Android|Room|AI provider|backup|bilingual\" docs/architecture.md | head -50" in /Users/ll/workspace/vreader
 succeeded in 0ms:
   246	  **`MIGRATION_8_9` exact DDL (gap A — BINDING; modeled on the verified `MIGRATION_6_7` `search_index_state` shape at VReaderDatabase.kt:154–169, whose DDL Room's PRAGMA validation already accepts):**
   247	
   248	  ```
   249	  val MIGRATION_8_9: Migration = object : Migration(8, 9) {
   250	      override fun migrate(db: SupportSQLiteDatabase) {
   251	          db.execSQL(
   252	              "CREATE TABLE IF NOT EXISTS `chapter_translations` (" +
   253	                  "`lookupKey` TEXT NOT NULL, " +
   254	                  "`bookKey` TEXT NOT NULL, " +
   255	                  "`unitStorageKey` TEXT NOT NULL, " +
   256	                  "`targetLanguage` TEXT NOT NULL, " +
   257	                  "`promptVersion` TEXT NOT NULL, " +
   258	                  "`translatedJson` TEXT NOT NULL, " +
   259	                  "`sourceParagraphCount` INTEGER NOT NULL, " +
   260	                  "`createdAt` INTEGER NOT NULL, " +
   261	                  "PRIMARY KEY(`lookupKey`), " +
   262	                  "FOREIGN KEY(`bookKey`) REFERENCES `books`(`fingerprintKey`) " +
   263	                  "ON UPDATE NO ACTION ON DELETE CASCADE )"
   264	          )
   265	          db.execSQL(
   266	              "CREATE INDEX IF NOT EXISTS `index_chapter_translations_bookKey` " +
   267	                  "ON `chapter_translations` (`bookKey`)"
   268	          )
   269	      }
   270	  }
   271	  ```
   272	
   273	  The `ChapterTranslationEntity` column types/order MUST match this DDL exactly (all columns `NOT NULL`; PK `lookupKey`; the `Index("bookKey")` produces `index_chapter_translations_bookKey`; the FK is `bookKey → books(fingerprintKey) ON DELETE CASCADE` — the same shape as every other child table, VReaderDatabase.kt:75–76/88–89/100–101/157–158/168–169). **The migration test MUST diff this DDL against Room's GENERATED `9.json` schema** (`exportSchema = true` at VReaderDatabase.kt:30 emits `schemas/…/9.json`), NOT a hand-written approximation — the exact-DDL guard opens the real Room DB after the v8→v9 migration and lets Room's structural PRAGMA validation catch any drift (the recurring Android migration failure mode, cf. #135's stale-version finding; the `MIGRATION_6_7` comment at VReaderDatabase.kt:148–150 documents this exact "DDL matches Room's generated schema, validated by the migration test opening the real Room DB" contract).
   274	
   275	- `reader/TxtReaderActivity.kt` — own a `BilingualViewModel`; collect state; render translations **inside each chunk `i`'s lazy item as muted non-registered `Text` children of a wrapping `Column`, source chunk byte-unchanged, the `items(count = document.chunkCount, key = { it })` loop and its keys UNCHANGED so lazy-index==chunk-index is preserved (H2, TxtReaderActivity.kt:1043–1085)**; add the translation gesture-exclusion (H2); on position change call `vm.onPositionChanged(charOffsetUTF16)`. Strictly gated to `originalFormat ∈ {txt, md}`; disabled = each item's `Column` holds only the unchanged source `Text` (source-selection-parity preserved). **Owned by #129 (VERIFIED, merged) — a straight edit, rule 48 one-writer-per-file satisfied.**
   276	- `reader/ReaderActivity.kt` (Readium EPUB) — WI-0-gated: attach `EpubBilingualController` to `navigator.evaluateJavascript`; re-apply on the identified production re-apply signal; clear on teardown BEFORE publication teardown. `navigator: EpubNavigatorFragment?` is the verified live field (ReaderActivity.kt:110).
   342	**13 WIs/PRs (round-3 Low-1 fix — corrected count; UNCHANGED in v5):** the list is exactly **WI-0, WI-1, WI-2, WI-3, WI-4a, WI-4b, WI-5, WI-6, WI-7a, WI-7b, WI-AIP, WI-8, WI-9** = **13 WIs**. `Utf16Span` (round-4 H1) is a NEW file but **rides WI-1** (the foundational value-types + pure-segmentation WI) — it does not add a WI. Each WI = one PR. Build order: **foundation/cache → service/direct-block APIs → shared DI/factory (incl. `AiProviderStore` in `AppContainer`) → VM state/prefetch → host-specific renderers (TXT/MD + EPUB) + the Variant A AI Providers sheet → entry wiring.**
   343	
   344	**Dependencies (round-3 Medium-4 — dependency honesty; #136 folded in; round-4 CONFIRMED correct):**
   345	
   346	- **`Deps: [feat:#132, feat:#134]`.** **#132 (top chrome) and #134 (More menu) are VERIFIED.** **#129 (TXT/MD reader) is VERIFIED** — `TxtReaderActivity` is a straight edit, not a blocker. **There is NO external AI-reachability blocker** — the former #136 is CLOSED (GH #1976, not-planned) and its scope is #131-owned.
   347	- **WI-4b is foundational and gates the behavioral chain.** WI-4b provides `AiProviderStore` into `AppContainer` PLUS the bilingual services + factories. Per the audit's Medium-4, WI-4b transitively gates WI-6 (needs the prefetcher/DI), WI-7b (needs DI), WI-AIP (needs `AiProviderStore` + `AiSettingsViewModel` from `AppContainer`), and WI-8 (needs DI). **Chosen resolution: injected seams so the behavioral work proceeds against fakes before WI-4b lands, AND WI-4b is sequenced early.** Concretely: the VM (WI-5/WI-6) takes an injected `ChapterTranslationPrefetcher` (fake in tests) and an injected `AiProviderSnapshot` provider (fake); the TXT/MD host Compose/unit work (WI-8) and the Variant A sheet (WI-AIP) take injected VM/store/`AiSettingsViewModel` seams — so unit/Compose tests do not wait on `AppContainer`. **WI-4b is built right after WI-4a (before WI-6/WI-7b/WI-AIP/WI-8) so the production wiring lands before the host integrations that mount it.** This is stated honestly: the *production run-through* of WI-6/WI-7b/WI-AIP/WI-8 depends on WI-4b; their *unit/Compose gates* depend only on the injected seams. No external feature gates any of this.
   348	
   349	**WI-0 (spike): Readium EPUB bilingual injection — go/no-go + race contract (M1).** Harness + criteria (a)–(e) and the race contract in §3. Output: a go/no-go on EPUB-in-v1 (no-go = box D ships TXT/MD-only, tracked) + the concrete `EpubChapterTextProvider` / `EpubBilingualJs` / `EpubBilingualController` surfaces + the EPUB direct-block ownership sequence (Medium-1). Deps: none (uses the existing #106 Readium host). Not TDD-gated (throwaway spike); feeds WI-7b.
   350	
   351	**WI-1 (foundational): value types + pure segmentation/chunk/contract.** **`Utf16Span` (round-4 H1 — the half-open span value type replacing `IntRange`)**, `TranslationUnitId`, `TranslationGranularity` (reserved; v1 uses `paragraph` only — round-4 H3), `BilingualLanguages`, **`ChapterSegmenter` (with `paragraphRanges`/`sentenceRanges` returning `List<Utf16Span>` — H1; `sentenceRanges` is reserved-foundational, not in the v1 render path — H3)**, `TranslationChunker`, `TranslationChunkContract` (no `style`), `ChapterTranslationError`. Pure; ported iOS vectors. Deps: none. Tests: `paragraphRanges`/`sentenceRanges` return correct half-open `Utf16Span(start, endExclusive)` spans (both APIs unit-tested even though only `paragraphRanges` ships in the v1 render path — `sentenceRanges` stays covered as reserved-foundational code); chunker packs-to-budget/oversize/empty; contract prompt/decode/fence/mismatch; error mapping.
   352	
   353	**WI-2 (foundational): Room translation cache.** `ChapterTranslationEntity` (PK = `lookupKey`, all-`NOT NULL` columns matching the DDL, `sourceParagraphCount` column) + `Dao` (`@Upsert`) + `ChapterTranslationStore`; `VReaderDatabase` **8→9 `MIGRATION_8_9`** with the **exact DDL authored in §2 (gap A)**, appended after `MIGRATION_7_8`. Robolectric migration round-trip from v8 + full-chain + upsert/get/delete-by-lookupKey + FK-CASCADE + **exact-DDL guard validated against Room's GENERATED `9.json` schema (not a hand-written approximation — gap A)**. Deps: none.
   354	
   355	**WI-3 (foundational): `ChapterTranslationService`** against a fake `AiClient`. Both `cachedTranslation` overloads (incl. the `expectedSegmentCount` divergence restore — H2) + `translate` + `translatePreSegmented`. **Dual-cancellation (native + typed `Cancelled`) BEFORE generic mapping (M2).** Deps: WI-1, WI-2. Tests: cache hit → zero client calls; miss → translate + write; decode fail → per-segment fallback; one-chunk fail → source-only that chunk (others translated, NOT cached); all-chunks fail → throw; native-cancel → `Cancelled` (no write); typed-`Cancelled`-from-chunk → `Cancelled` (no write); ensureActive-before-write; `AiError` mapping incl. `Config`/`InsecureUrl` → `ProviderFailed`; `translatePreSegmented` full-success caches under the enumerate count; partial degrade NOT cached; all-fail throws; `cachedTranslation(expectedSegmentCount)` returns on stored-count match, null on mismatch, needs no provider.
   365	**WI-7a (behavioral): Compose UI — setup sheet + interlinear body (TXT/MD) + pill.** Reproduce `vreader-bilingual.jsx` (setup sheet: language grid / **Paragraph-only Granularity control (round-4 H3)** / preview / engine strip configured+unconfigured; body: the translation rendered **inside the anchor chunk's `Column` as a muted non-registered `Text` child** per the round-4 H2 render contract — translated / loading N%+dimmed / error+Retry / offline source-only; pill). Consumes the host-neutral `BilingualRenderState` DTO. Light+dark. Compose UI tests each state, incl. **paragraph interlinear renders a translation child after a paragraph's last source chunk (depicted)**; **the setup-sheet Granularity control shows Paragraph only, no Sentence option (H3)**. Deps: WI-5 (state shape). NO Style control; the unconfigured "Set up" CTA renders and (in WI-9) routes to the Variant A sheet.
   366	
   367	**WI-7b (behavioral, CONDITIONAL — only if WI-0 = go): EPUB render adapter (DOM injection, NOT Compose — M2) + direct-block ownership (M1).** `EpubBilingualJs` (enum/inject/clear JS builders, CSP-safe escaping) + `EpubBilingualController` (the serialization actor / session token AND the **single-owner enumerate→cachedDirect/prefetchDirect→guarded-commit sequence — Medium-1**) + `EpubChapterTextProvider`, wired into `ReaderActivity`, driving DOM from the shared `BilingualRenderState` DTO. Uses `prefetchDirect`/`cachedDirect` for the count-divergence path (H2). Depends on WI-6 (VM state) and WI-4b (DI); the WI-7a UI dependency is only the shared `BilingualRenderState`/value types. Connected test on a real EPUB (seeded cache): enable → injects; disable → cleared; reflow/href-change/fragment-recreation/activity-recreation → re-applies from cache (zero provider calls) via `cachedDirect`; count-divergence handled (direct path); **the regular TXT/MD prefetch path is never invoked for an EPUB unit (Medium-1)**. Unit tests: JS escaping/CSP-safe insertion, RTL/CJK style, empty translations, loading cleanup, idempotent replacement, source-only fallback, stale-session-token commit discarded (no `errorUnit`). Deps: WI-0, WI-3, WI-4a, WI-4b, WI-6, (shared types from WI-7a). (If WI-0 = no-go, dropped; box D ships TXT/MD-only, tracked.)
   368	
   369	**WI-AIP (behavioral — the folded-in Variant A AI Providers sheet; round-4 H4 rewritten): `ReaderAiProvidersSheet`.** The scoped in-reader "AI Providers" push sheet (nav bar `‹ Bilingual` + "AI Providers" title) reproducing `vreader-ai-provider-entry.jsx` `AIProvidersSheet`/`AIProvidersSheetBody`/`NavSheet`. Per round-4 H4:
   370	  - **(a)** present `AiProviderEditSheet` VERBATIM from #118 (Kind/Name/Endpoint/Sampling/API Key/Test Connection unchanged).
   371	  - **(b)** a NEW `ReaderAiProvidersList` presentation over the SHARED `AiSettingsViewModel.listState` (verified `AiSettingsViewModel.kt:26`; each `AiProviderRow` already carries `active`, :30) + shared row/cell components — reproducing the reader-scoped `‹ Bilingual` nav (`NavSheet`, jsx:247, NOT `AiProviderListScreen`'s `NavScreen`), the bilingual-context empty state ("Choose the provider bilingual mode will use to translate this book." + "No providers yet" + "Add provider" — jsx:180–209), the **checked-active row** (`selected = row.active` — jsx:221), and **tap-to-SELECT** (`onSelect(id) → vm.setActive(id)` — jsx:221/237). It does NOT reuse `AiProviderListScreen`'s NavScreen/chrome/`AiEmptyState`/`ProviderRow`-tap-edit.
   372	  - **(c)** the **save-result seam**: `AiSettingsViewModel.save()` (or a thin WI-AIP wrapper) is extended to return the saved provider ID (from `store.upsert(...).id`, which the store already returns — `AiProviderStore.kt:58/84`), so on first Save → `store.setActive(savedId)` → pop the whole stack back to the bilingual sheet (engine strip now "configured / Change…"), **deterministically, after the upsert commits (no race)**.
   373	  `‹ Bilingual` without adding → unconfigured, no state mutated. "Change…" → populated list, current provider checked, tap row → `setActive`. No consent/flag surface (Android has none). Deps: WI-4b (for `AiProviderStore` + `AiSettingsViewModel` in `AppContainer`), WI-7a (bilingual sheet host). Tests (Compose + connected): the scoped list renders **`‹ Bilingual` back label** + **bilingual-context empty copy** + **checked active row** + **tap-selects (`setActive`)**; empty → Add → Save → **save→result-id→`setActive`→pop deterministic (no race)** → bilingual strip configured; `‹ Bilingual` without adding → strip unconfigured, snapshot unchanged; "Change…" → populated, current checked; editor reused verbatim (no divergent form).
   374	
   375	**WI-8 (behavioral): `TxtReaderActivity` integration.** Wire VM into the `items(count = document.chunkCount, key = { it })` loop as **muted non-registered translation `Text` children inside each anchor chunk's wrapping `Column`, source chunk byte-unchanged, the loop + keys UNCHANGED so lazy-index==chunk-index is preserved (round-4 H2)** + the translation **gesture-exclusion** (round-4 H2) + position-change (`charOffsetUTF16`) + setup-sheet. `originalFormat`-gated (TXT/MD). Uses WI-4b's DI. **#129 VERIFIED — straight edit.** Connected test (fake `AiClient` seam): enable → setup → confirm → interlinear from seeded cache; **enabled-mode source-chunk selection registrations UNCHANGED vs disabled (H2)**; **highlights/annotation-washes/read-aloud-wash still key off source chunks (H2)**; **with bilingual ON — position-save round-trips to the same chunk; bookmark/search/scrubber/TTS jumps land on the correct chunk (lazy-index==chunk-index preserved — round-4 H2)**; **a long-press on translation text does NOT select (gesture exclusion — round-4 H2)**; a translation child is non-selectable, does not perturb source offsets (H2); disable → source-selection byte-parity; reopen persists enabled + renders from cache with zero client calls; **paragraph-spanning-many-chunks renders exactly one translation inside its last chunk's `Column` (H1/Low-2)**; **one-chunk/final-chunk anchors render (H1)**; MD source mapping. Deps: WI-6, WI-7a, WI-4b.
   376	
   377	**WI-9 (behavioral): entry wiring + acceptance.** Mount `BilingualPill` in #132's VERIFIED top chrome; extend `readerMoreRows(...)` to supply the #134 VERIFIED More-menu `MoreActionId.BILINGUAL` toggle (`MoreRow.Toggle` `on`/`onToggle`, or `MoreRow.Disabled` "Configure AI provider first" when not configured) wired to the VM; **wire the setup sheet's "Set up"/"Change…" affordance → the #131-owned `ReaderAiProvidersSheet` (Variant A)**. Full acceptance across EPUB (if WI-7b landed) + TXT/MD, including the fresh-user path `unconfigured → Set up (→ Variant A AI Providers sheet) → add provider → Save → return → enable → translate` (now #131-owned end-to-end). **Flip box D to done ONLY for provider/model/granularity(paragraph) + the Style-descope AND Sentence-descope notes; file the follow-up checklist amendment; do NOT claim full box-D parity.** The DONE flip **no longer waits on #136** (closed). Update `docs/architecture.md` (bilingual pipeline + the new `chapter_translations` schema + `AiProviderStore` + bilingual services in `AppContainer` + the Variant A AI Providers sheet). → DONE. Deps: WI-8, WI-AIP, WI-7b (if go), feat:#132, feat:#134.
   378	
     1	// Purpose: Room database + schema-versioned migration scaffold — feature #106 WI-3.
     2	// Version 8 is the current schema; v1 was the initial books+positions baseline and
     3	// MIGRATION_1_2 is the worked example of the additive-migration pattern (adds
     4	// books.lastOpenedAt). Subsequent additive migrations: 2→3 daily_reading (#122),
     5	// 3→4 annotations (#123), 4→5 collections (#127), 5→6 books.author (#128 search),
     6	// 6→7 the FTS search index (search_sections + search_sections_fts + search_index_state
     7	// + search_sections_staging, all #128 WI-4), 7→8 the composite UNIQUE (bookKey, profileKey)
     8	// index on `bookmarks` — preceded by an in-migration dedupe of pre-existing duplicate rows so
     9	// the unique index can't fail on a legacy duplicate (feature #135 WI-3). The migration round-trip
    10	// test (VReaderDatabaseMigrationTest) guards them. Future schema changes append a
    11	// Migration(n, n+1) to ALL_MIGRATIONS and bump `version`.
    12	package com.vreader.app.data
    13	
    14	import android.content.Context
    15	import androidx.room.Database
    16	import androidx.room.Room
    17	import androidx.room.RoomDatabase
    18	import androidx.room.migration.Migration
    19	import androidx.sqlite.db.SupportSQLiteDatabase
    20	
    21	@Database(
    22	    entities = [
    23	        BookEntity::class, ReadingPositionEntity::class, DailyReadingEntity::class,
    24	        HighlightEntity::class, AnnotationNoteEntity::class, BookmarkEntity::class,
    25	        CollectionEntity::class, BookCollectionCrossRef::class,
    26	        SearchSectionEntity::class, SearchSectionFtsEntity::class,
    27	        SearchIndexStateEntity::class, SearchStagingEntity::class,
    28	    ],
    29	    version = 8,
    30	    exportSchema = true,
    31	)
    32	abstract class VReaderDatabase : RoomDatabase() {
    33	    abstract fun bookDao(): BookDao
    34	    abstract fun readingPositionDao(): ReadingPositionDao
    35	    abstract fun readingStatsDao(): ReadingStatsDao
    36	    abstract fun annotationDao(): AnnotationDao
    37	    abstract fun collectionDao(): CollectionDao
    38	    abstract fun searchDao(): SearchDao
    39	
    40	    companion object {
    41	        private const val DB_NAME = "vreader.db"
    42	
    43	        /** v1 → v2: add the nullable `lastOpenedAt` recents column to `books`. */
    44	        val MIGRATION_1_2: Migration = object : Migration(1, 2) {
    45	            override fun migrate(db: SupportSQLiteDatabase) {
    20	 * path goes through [BookDao.upsertPreservingAuthor], not the whole-row `@Upsert`).
    21	 */
    22	@Entity(tableName = "books")
    23	data class BookEntity(
    24	    @PrimaryKey val fingerprintKey: String,
    25	    val title: String,
    26	    val originalFormat: String,   // BookFormat raw value (epub/pdf/txt/md/azw3)
    27	    val contentSHA256: String,
    28	    val fileByteCount: Long,
    29	    val localFilePath: String?,   // app-private storage path (set at import, WI-4)
    30	    val sourceUri: String?,       // SAF source URI metadata (WI-4)
    31	    val addedAt: Long,            // epoch millis
    32	    val lastOpenedAt: Long?,      // v2 addition — epoch millis of last open, or null
    33	    val author: String? = null,   // v6 addition (feature #128) — nullable; tail default so no positional site breaks
    34	)
    35	
    36	/**
    37	 * The persisted reading position for a book — the WHOLE [VReaderLocator] envelope
    38	 * serialized into a single `vreaderLocatorJSON` column (one position per book; PK =
    39	 * fingerprintKey). Storing the entire envelope (not flattened columns) is the
    40	 * iOS-parity contract: a new envelope field gated by its own `schemaVersion` evolves
    41	 * WITHOUT a Room schema change (Gate-4 Medium — the iOS analog persists the envelope
    42	 * as one `Data?` blob on `ReadingPosition`). `canonicalHash` is the only derived
    43	 * column, kept for dedup/sync lookups. `fingerprintKey` is both PK and the FK child
    44	 * column, so it is already indexed — no separate index needed.
    45	 */
    46	@Entity(
    47	    tableName = "reading_positions",
    48	    foreignKeys = [
    49	        ForeignKey(
    50	            entity = BookEntity::class,
    51	            parentColumns = ["fingerprintKey"],
    52	            childColumns = ["fingerprintKey"],
    53	            onDelete = ForeignKey.CASCADE,
    54	        ),
    55	    ],
    56	)
    57	data class ReadingPositionEntity(
    58	    @PrimaryKey val fingerprintKey: String,
    59	    val vreaderLocatorJSON: String,   // the FULL serialized VReaderLocator envelope
    60	    val canonicalHash: String,        // derived dedup/sync key (locally deterministic)
    61	    val updatedAt: Long,              // epoch millis of last save
    62	)
    88	 * `anchorHash ?: "__nil_anchor__"` sentinel (SQLite treats NULLs as distinct in a unique index, so a
    89	 * nullable column would let repeated null-anchor highlights bypass dedupe — the sentinel collapses
    90	 * them per `profileKey`, matching iOS's nil-anchor-by-profileKey dedupe).
    91	 */
    92	@Entity(
    93	    tableName = "highlights",
    94	    foreignKeys = [
    95	        ForeignKey(
    96	            entity = BookEntity::class,
    97	            parentColumns = ["fingerprintKey"],
    98	            childColumns = ["bookKey"],
    99	            onDelete = ForeignKey.CASCADE,
   100	        ),
   101	    ],
   102	    indices = [Index("bookKey"), Index(value = ["profileKey", "anchorKey"], unique = true)],
   103	)
   104	data class HighlightEntity(
   105	    @PrimaryKey val highlightId: String,   // UUID string (iOS `highlightId: UUID` parity)
   106	    val bookKey: String,                   // fingerprintKey (FK)
   107	    val profileKey: String,                // "$bookKey:${locator.canonicalHash}"
   108	    val anchorKey: String,                 // anchorHash ?: "__nil_anchor__" (non-null dedupe key)
   109	    val color: String,                     // AnnotationColor.key (yellow/green/blue/pink/red) or hex
   110	    val selectedText: String,
   111	    val note: String?,                     // optional inline note on the highlight
   112	    val locatorJSON: String,               // full round-trippable plain Locator JSON (backup converts to canonicalJson)
   113	    val anchorJSON: String?,               // serialized AnnotationAnchor (engine-precise)
   114	    val createdAt: Long,
   115	    val updatedAt: Long,
   116	)
   117	
   118	/**
   119	 * A standalone note — feature #123. Mirrors the iOS `AnnotationNote` @Model (the design's
   120	 * "STANDALONE" card). Same `locatorJSON` (full round-trippable plain Locator; backup converts to
   121	 * canonical) + `anchorJSON` (precise) contract as [HighlightEntity]. No range-dedupe (a reader may
   122	 * keep several notes at one spot).
   123	 */
   124	@Entity(
   125	    tableName = "annotation_notes",
   126	    foreignKeys = [
   127	        ForeignKey(
   128	            entity = BookEntity::class,
   129	            parentColumns = ["fingerprintKey"],
   130	            childColumns = ["bookKey"],
   131	            onDelete = ForeignKey.CASCADE,
   132	        ),
   133	    ],
   134	    indices = [Index("bookKey")],
   135	)
   136	data class AnnotationNoteEntity(
   137	    @PrimaryKey val noteId: String,
   138	    val bookKey: String,
   139	    val profileKey: String,
   140	    val content: String,
   141	    val locatorJSON: String,
   142	    val anchorJSON: String?,
     1	# VReader Architecture
     2	
     3	## Overview
     4	
     5	VReader is an iOS e-book reader built with SwiftUI + SwiftData. It supports TXT, EPUB, AZW3/MOBI, PDF, and Markdown formats, each rendered by a format-specific native host (UIKit/WebView bridges) selected internally by `ReaderEngine` (feature #54). AZW3/MOBI is rendered via Foliate-js inside a WKWebView. **Feature #42 Phase 2 (`kindleConvertOnImport`, default ON since the G2 flip 2026-06-02):** NEW AZW3/MOBI/KF8/PRC imports are converted to a first-class EPUB at import time (via the vendored libmobi MOBI→EPUB converter) and render via the default Readium EPUB engine; already-imported native `.azw3` books are unchanged and keep rendering via Foliate, and a user can revert via the persisted `kindleConvertOnImport` override OFF. The `UnifiedTextRenderer` (TextKit 2 reflow) stack is retained in the codebase but no longer wired into the reader dispatch.
     6	
     7	## System Diagram
     8	
     9	```
    10	┌──────────────────────────────────────────────────────┐
    11	│                    VReaderApp                         │
    12	│  SwiftData SchemaV10 · PersistenceActor · BookImporter│
    13	└─────────────────────┬────────────────────────────────┘
    14	                      │
    15	          ┌───────────┴───────────┐
    16	          │                       │
    17	    ┌─────▼──────────┐    ┌──────▼──────────────────┐
    18	    │  LibraryView    │    │  ReaderContainerView     │
    19	    │  LibraryViewModel│   │  (format dispatcher)     │
    20	    │  PreferenceStore │   │  ReaderTopChrome (overlay)│
    21	    └─────────────────┘   └──────┬───────────────────┘
    22	                                 │
    23	        ┌────────┬───────────┬───┴────┬─────────┐
    24	        │        │           │        │         │
    25	    ┌───▼──┐ ┌──▼───┐  ┌───▼──┐ ┌──▼───┐ ┌────▼─────┐
    26	    │ TXT  │ │ EPUB │  │ PDF  │ │  MD  │ │  AZW3 /  │
    27	    │Bridge│ │Bridge│  │Bridge│ │Bridge│ │  MOBI    │
    28	    └──────┘ └──────┘  └──────┘ └──────┘ └──────────┘
    29	    UITextView WKWebView PDFKit  UITextView WKWebView
    30	                                            (Foliate-js)
    31	```
    32	
    33	## Layers
    34	
    35	### 1. App Layer (`vreader/App/`)
    36	
    37	- `VReaderApp.swift` — SwiftData `ModelContainer` init (SchemaV10), migration plan (V1→…→V9→V10, all lightweight; V9→V10 adds the additive `Book.sourceCanonicalKey: String?` for feature #108's converted-Kindle cross-platform identity). Also runs the feature #109 one-shot `LocatorKeyBackfillMigration` synchronously at launch (flag-gated; recomputes derived locator keys under NFC canonicalization + repairs non-finite locators — a launch backfill, NOT a migration stage, since the transform changes no entity shape). Plus test seeding, error handling. Injects the live `PersistenceActor` into the SwiftUI environment via `\.persistenceActor` so settings sub-screens can construct backup providers without rewriting every parent's signature. Adopts `@UIApplicationDelegateAdaptor(VReaderAppDelegate.self)` for background-URLSession completion-handler delivery (feature #47).
    38	- `VReaderAppDelegate.swift` — `UIApplicationDelegate` adapter that captures `application(_:handleEventsForBackgroundURLSession:completionHandler:)` into a MainActor-isolated static dictionary keyed by URLSession identifier. The lazy-download coordinator retrieves and invokes the handler from `LazyDownloadDelegate.urlSessionDidFinishEvents` so iOS releases the app's background-launch grace period.
    39	
    40	### 2. Library Layer (`vreader/Views/LibraryView.swift`, `vreader/ViewModels/LibraryViewModel.swift`)
37:- `VReaderApp.swift` — SwiftData `ModelContainer` init (SchemaV10), migration plan (V1→…→V9→V10, all lightweight; V9→V10 adds the additive `Book.sourceCanonicalKey: String?` for feature #108's converted-Kindle cross-platform identity). Also runs the feature #109 one-shot `LocatorKeyBackfillMigration` synchronously at launch (flag-gated; recomputes derived locator keys under NFC canonicalization + repairs non-finite locators — a launch backfill, NOT a migration stage, since the transform changes no entity shape). Plus test seeding, error handling. Injects the live `PersistenceActor` into the SwiftUI environment via `\.persistenceActor` so settings sub-screens can construct backup providers without rewriting every parent's signature. Adopts `@UIApplicationDelegateAdaptor(VReaderAppDelegate.self)` for background-URLSession completion-handler delivery (feature #47).
72:  bilingual wrapper from feature #56 WI-11 sits between the dispatcher
73:  and `FoliateSpikeView`, adding the bilingual VM / orchestrator / setup-
124:- `ReadiumEPUBHost` (feature #42 Phase 1, WI-5) → `ReadiumNavigatorRepresentable` → Readium Swift Toolkit `EPUBNavigatorViewController`. Selected by the dispatcher in place of `EPUBReaderHost` when `FeatureFlags.readiumEPUBEngine` is ON (**default ON since the WI-14 G2 flip 2026-06-01**; a persisted override OFF reverts to the legacy `EPUBReaderHost`). Opens the publication off-main via `ReadiumEPUBReaderViewModel` (`AssetRetriever` → `PublicationOpener`), then mounts the navigator; `EPUBPreferences(scroll:)` is mapped from `ReaderSettingsStore.epubLayout`. The `ReadiumReaderCoordinator` is the `EPUBNavigatorDelegate` + (DEBUG) `ReadiumNavigatorEvaluating` seam — it registers the active navigator with `DebugReaderRegistry.setActiveReadiumNavigator` and `markReaderSettled` on `locationDidChange`, and tears that registration down on `dismantleUIViewController` via `detach()` → `clearActiveReadiumNavigator` (the host registers no `DebugReaderProbe`, so it owns its own registry teardown). Reading-position save/restore landed in WI-6: the coordinator forwards `locationDidChange` to the VM's debounced save, which maps the Readium `Locator` → a `VReaderLocator` envelope (engine `.readium`, authoritative `readiumLocatorJSON` + a lossy legacy `Locator` leg) and dual-writes it through `PersistenceActor`'s `VReaderLocatorPersisting` conformance — `saveVReaderLocator` writes both the envelope blob into the SchemaV8 `ReadingPosition.vreaderLocatorData` column AND the legacy `locator`; legacy `savePosition` clears the envelope so a flag-OFF write can't be shadowed by a stale Readium position. On open, the host loads the saved envelope (`restoredReadiumLocator()`) before the navigator mounts and passes it as `initialLocation`. Theme/font landed in WI-7: the host body reads `ReaderSettingsStore.theme` + `.typography` + `.epubLayout` (tracked `@Observable` deps) and recomputes a full `EPUBPreferences` on any Display-settings change, which `updateUIViewController` re-submits live (`submitPreferences`). `ReadiumEPUBReaderViewModel+Mapping` translates the 5 `ReaderThemeV2` themes → Readium's 3 base `Theme`s + explicit `backgroundColor`/`textColor` (which win via `effectiveBackgroundColor`); font size from the per-format-calibrated `.epub` size (`FontSizeCalibrator`) → Readium's multiplier; `lineHeight` from `lineSpacing`; `fontFamily` (system→sansSerif, serif/sourceSerif4→serif, monospace→monospace, inter→sansSerif — custom-font registration deferred); `publisherStyles=false`. The WI-7 photo/custom-background refinement composites the decorative image behind the navigator: `ReadiumEPUBHost+Background.swift` layers the existing `ThemeBackgroundView` under the navigator in a `ZStack` (only when `useCustomBackground` + an image exists for the theme), and `ReadiumReaderCoordinator+Transparency` makes the navigator render through — `epubPreferences(..., transparentBackground:)` emits `backgroundColor: nil` (so ReadiumCSS injects no body bg rule), the representable forces `navigator.view`/spine `WKWebView`s `.clear`/`isOpaque=false`, and a read-only self-gating user script clears the opaque `html:root` ReadiumCSS paints (transparency state is authored into `localStorage` by Swift on each `locationDidChange`/toggle). Normal opaque themes are unchanged. Highlights landed in WI-8: `ReadiumDecorationHighlightAdapter` (a `HighlightRenderer`, the Readium counterpart of `EPUBHighlightRenderer`) renders stored highlights as Readium **Decorations** via `EPUBNavigatorViewController.apply(decorations:in:"highlights")` (declarative — the adapter holds the active set and re-submits the whole group on each apply/remove/restore). Re-anchoring is **text-quote** based (WI-8a migration spike): each `HighlightRecord` → `Decoration(locator: Locator(href:, text: .Text(highlight: selectedText, before/after: context)), style: .highlight(tint:))` — Readium re-finds the quote, so the legacy XPath `serializedRange` is never consulted or mutated (flag-OFF returns to legacy XPath rendering losslessly). The host owns the adapter + a `HighlightCoordinator(renderer: adapter)`, calls `restoreAll()` on open, and observes `.readerHighlightRemoved`/`.readerHighlightsDidImport`. The WI-8 new-highlight refinement adds CREATE from a live Readium selection: `ReadiumReaderCoordinator` conforms to `SelectableNavigatorDelegate` and `navigator(_:shouldShowMenuForSelection:)` forwards the finalized `Selection` to the host then returns `false` (suppressing Readium's native menu so the designed `SelectionPopoverView` is the sole selection surface — rule 51). `ReadiumEPUBHost+Highlights` stashes the `Selection` in a generic `ReadiumSelectionTokenCache<Selection>` under a token, presents the popover; on a color tap (`.readerHighlightRequested`) it resolves the token and `ReadiumSelectionHighlightBuilder` maps the `Selection`'s text-quote (highlight/before/after) + container-relative href → `HighlightRecord` inputs → `HighlightCoordinator.create` → the same `ReadiumDecorationHighlightAdapter` renders it immediately; `navCommander.clearSelection()` dismisses the selection. Navigation landed in WI-9a: the host observes the shared reader nav bus — `.readerNextPage`/`.readerPreviousPage` → the coordinator's `goForward`/`goBackward`, and `.readerNavigateToLocator` (TOC/bookmark/search-result tap, object = a vreader `Locator`) → `go(to:)` after mapping the vreader Locator → Readium Locator (`readiumLocator(fromVReader:spineHrefs:)`, reusing the WI-8 legacy→spine href resolution). Host→coordinator dispatch goes through a host-owned `ReadiumNavCommander` (`@State`, bound on `attach`/cleared on `detach`, mirrors the WI-8 adapter ownership). WI-9a also split the host into `ReadiumEPUBHost.swift` (View) + `ReadiumNavigatorRepresentable.swift` + `ReadiumReaderCoordinator.swift`. Footnotes (#138, WI-9b) remain. Search result-list extraction still uses the existing FTS/`SearchViewModel` stack — WI-9a maps only result *navigation*. **Bilingual landed in WI-11 (paged) and WI-12 (scroll parity): interlinear bilingual works under the flag by driving the enumerate→prefetch→inject loop through Readium's one-way `evaluateJavaScript(_:) async -> Result<Any,Error>` channel — NOT a script-message handler (the navigator owns its content controller, exposing no app-side message channel; this is why the WI-11a `ReadiumBilingualEvalAdapter` RETURNS the `[{bid,text}]` array rather than posting it). A host-owned `ReadiumBilingualCommander` (`@State`, the bilingual counterpart of `ReadiumNavCommander`) holds an evaluator closure the coordinator binds on `attach` (the production non-DEBUG `ReadiumReaderCoordinator.evaluateForBilingual`, returning Readium's raw `Result<Any,Error>?`) and clears on `detach`; `enumerate()` runs `ReadiumBilingualEvalAdapter.enumerateJS()` and parses the return value via `EPUBBilingualPipeline.parseEnumerateMessage`, `inject(_:)`/`clear()` run the engine-agnostic inject/clear builders. The host reuses the feature-#56 `EPUBBilingualOrchestrator` (paged `-1` bucket via `updateBlocks(_:)`) + `BilingualReadingViewModel` + the designed `BilingualSetupSheet` (rule 51 — no new UI). Source text comes from vreader's own `EPUBParser` (opened alongside the Readium open — Readium does not expose raw spine HTML), so the `EPUBChapterTextProvider` is keyed on OPF-relative spine hrefs; the Readium-produced vreader `Locator` carries Readium's CONTAINER-relative href, so `ReadiumBilingualCommander.normalizedLocator(_:toSpineHrefs:)` rewrites it onto the OPF spine via the shared `ReadiumDecorationHighlightAdapter.resolveHref` tolerance before `vm.handlePositionChange(...)` (the WI-8 href-consistency finding class — without it `unit(containing:)` returns nil and nothing translates). Chapter-change detection composes onto the existing `onLocationChange` (WI-6 position save still runs): a fresh enumerate runs only when the spine href changes, deduped intra-chapter by a reference-type `ReadiumBilingualChapterTracker`. WI-12 lifted the WI-11 paged-only gate (`isBilingualSupported` is true for both layouts) so bilingual works in scroll too — but PER-SPINE only: Readium scroll mode is per-resource (it emits `locationDidChange` at spine boundaries, driving the same per-spine enumerate the paged path uses), and Readium has no multi-spine-stitch API, so off-screen chapters enumerate when scrolled into view rather than eagerly. This is a documented behavior delta vs legacy #71 — the flag-OFF `EPUBWebViewBridge` engine keeps its full stitched cross-chapter continuous bilingual; the Readium engine does not reproduce it. A paged↔scroll layout change re-renders the spine (discarding the `data-vreader-bid` stamps + decorations), so the layout-change handler re-enumerates the current spine in both directions.** TTS (WI-10): read-aloud already works under the Readium engine with NO Readium-specific code — `ReaderContainerView.startTTS()` → `ReaderAICoordinator.loadBookTextContent(format: "epub")` extracts spine text from the **file** via `EPUBParser` (renderer-agnostic, independent of which engine renders), then feeds the shared `TTSService` pipeline. Device-verified under `readiumEPUBEngine` ON (speaking, `ttsOffsetUTF16` advancing 42→115, stop→idle). The speaking-position **follow** landed in WI-10b: as TTS speaks, the navigator auto-advances so the spoken text stays on screen. `ReadiumEPUBHost` observes the shared `TTSService.currentOffsetUTF16` (threaded in like `EPUBReaderHost`); a pure value-type `ReadiumTTSFollowMapper` maps the flat UTF-16 offset → (spine href, intra-spine fraction). CRITICAL alignment: the per-spine offset table is built from the SAME spine text the TTS engine reads — `EPUBTextExtractor.stripHTML` + trim, skip empties, join `"\n\n"` (the `ReaderAICoordinator.loadBookTextContent` recipe) — extracted off-main from the host's already-open `bilingualParser` (so the index matches the engine's offsets; the block-preserving bilingual stripper is deliberately NOT used here). `ReadiumEPUBHost+TTSFollow` throttles: it navigates on any spine-href change or an intra-spine fraction drift > 0.08 (so the navigator tracks ~chapter-eighth granularity, not every `willSpeakRange` word), maps the target → a vreader `Locator` → Readium `Locator` via the WI-9a `readiumLocator(fromVReader:spineHrefs:)` resolution, and drives the existing `navCommander.navigate(to:)` → `navigator.go(to:)`. Follow runs only while TTS state == `.speaking`; the cursor resets on each play start and on pause/stop. This unblocks the WI-14 default-ON flip.
137:`ReaderUnifiedCoordinator` loads text + applies transforms (replacement rules, simp/trad); `UnifiedTextRenderer` displays with TextKit 2 pagination or scroll. Feature #54 removed the unified path from the reader dispatch and the reader-settings Reading Mode picker, so this stack is **no longer reachable from reader dispatch** — it is retained (a follow-up may consume it for bilingual reading, or delete it once provably orphaned). Content replacement rules and Chinese conversion that previously required Unified mode now run in the native readers directly: `MDFileLoader.load` composes `ReplacementTransform` + `SimpTradTransform` over the decoded source text before parsing (feature #54 WI-7); **native EPUB applies replacement rules via `EPUBReplacementJS` (feature #54 Phase D-1)** — a CFI-safe per-text-node JS injection that runs on both EPUB engines (Readium per-spine via `ReadiumReaderCoordinator+Replacement`; the legacy #71 WKWebView stitch on `didFinish` via `EPUBWebViewBridgeCoordinator`, plus a scroll-root `MutationObserver` for appended chapters), keyed by `MDReplacementRuleFetcher`; native TXT has Chinese conversion only — TXT replacement rules are deferred (they need a source↔display offset map). Replacement rules apply at chapter/document open; a mid-read rules edit takes effect on next open (v1 scope).
170:| `WebDAVProvider`                     | `WebDAVClient`             | `BackupProvider` impl — backup/restore/list/delete over a WebDAV server   |
182:| `RemoteBookCatalog`                  | —                          | Pure decoder: extracts `library-manifest.json` from a backup ZIP via `ZIPWriter.extractEntry(named:from:)` and returns `[BackupLibraryEntry]`. Surfaces `manifestMissing` (older backups) / `manifestUndecodable` / `manifestSchemaVersionTooNew` as typed errors. Feature #47 WI-4a. |
198:| `DebugBridge`                        | URL handler (DEBUG-only)   | `vreader-debug://` reset/seed/open/settle/snapshot/eval/tts/search/highlight/provider/present/ai/seed-sessions/seek/scroll-sheet/navigate/scroll-boundary/locate?highlight=N; feature #49 added position-aware open + DebugSnapshot schema v2 (TTS state, render phase, settings provenance); feature #74 added `locate?highlight=<N>` to drive `.readerNavigateToLocator` for the active TXT/MD reader CU-free so the locate "bloom" (highlight/note landing) fires on the real render path, plus DebugSnapshot schema v3 (`landingBloomCount` / `landingBloomPeakIntensity`) read back from `HighlightableTextView`'s persisted bloom counters — the ~1.5s sub-second bloom visual can't be screenshot/video-captured on the virtual display, so the snapshot proves it fired; feature #45 WI-4c-b added `tts?action=start\|stop` to bypass XCUITest's audio-session block; bug #238 added `search?query=...[&index=N]` to drive search-result-tap repros (Bug #182 / GH #621) CU-free; bug #237 added `highlight?start=...&end=...[&color=...]` for TXT/MD highlight creation CU-free; bug #243 added `provider?action=add\|remove\|clear` for AI provider configuration without driving Settings → AI through CU (unlocks Feature #56 b/d / Feature #65 / Feature #69 / Bug #93 autonomous AI verification); bug #253 added `present?sheet=...[&tab=...]` + bug #255 added `ai?action=summarize\|chat\|translate` for CU-free reader-sheet + AI-response-card verification; bug #263 added `seed-sessions?book=<key>[&seconds=<n>]` to seed a deterministic `ReadingSession` spread (one per dashboard window band) so the reading-stats dashboard (Feature #58) renders non-zero per-window totals CU-free; bug #267 added `seek?fraction=<0...1>` to drive the active Foliate (AZW3/MOBI) reader to a fractional position CU-free; bug #271 added `scroll-sheet?to=top\|bottom` to scroll the active presented sheet's content (today `TranslationResultCard`) so the accent translation card below the tall ORIGINAL card — beyond even the `detent=large` fold (Bug #256) — becomes screenshot-capturable, unblocking Feature #65 row 11; bug #273 added `navigate?spine=<N>[&fraction=<F>]` to drive `.readerNavigateToLocator` for the active EPUB reader CU-free (the `search` driver doesn't navigate in continuous mode), posting DEBUG-only `.debugBridgeNavigateCommand` → `EPUBReaderContainerView` resolves spine → href → `Locator` → re-posts `.readerNavigateToLocator` — unblocking feature #71 WI-8 continuous-mode navigation verification (paired with the `multi-chapter-epub` 4-tall-chapter fixture for the out-of-window rebuild branch); a follow-up added `scroll-boundary?spine=<N>&near=top\|bottom` to post a DEBUG-only `.debugBridgeScrollBoundaryCommand` → `EPUBReaderContainerView` builds an `EPUBScrollBoundarySignal` and calls `EPUBContinuousScrollCoordinator.handleBoundarySignal` directly — bypassing the rAF-throttled `continuousScrollObserverJS` (unverifiable CU-free on a virtual display) so feature #71's scroll-driven extend/evict RESPONSE can be device-verified. **Host-vs-runner driving constraint (bug #242 / GH #1054)**: bridge URLs MUST be invoked from the host (`xcrun simctl openurl` outside any iOS sandbox) — invoking them from inside an XCUITest binary fails with NSPOSIX 61 because the runner sandbox blocks the CoreSimulatorService XPC endpoint. In-runner verification flows use `XCTSkipUnless(bridgeReachable())` (PR #1053) when they cannot move the bridge-dependent assertion to a host-side driver. See `docs/subsystems/debug-bridge.md` § "Driving the bridge from a verification flow". |
208:| `ChapterTranslationStore`            | SwiftData (actor-isolated) | Persistent disk cache for feature #56 bilingual reading. Wraps its own `ModelContext` over the `ChapterTranslation` `@Model` (SchemaV7) — a separate actor from `PersistenceActor` so bulk translation writes during a global-translate run never block library reads. App-scoped `.shared` single instance (the `ProviderProfileStore.shared` precedent); idempotent `upsert` fetches by `lookupKey` and updates in place, never relying on the unique constraint to throw. Returns the value-type `ChapterTranslationRecord` DTO, never the `@Model`. Bug #342: lazily migrates pre-#342 5-field keys (profile UUID baked in) to the canonical 4-field key on first access, deduping to the newest row. The cache is derived, re-fetchable data — excluded from WebDAV backup |
209:| `ChapterTranslationService`          | `ChapterTranslationStore` + `AIService` | Translates one chapter unit for feature #56 bilingual reading. Pipeline: cache lookup → (on miss) `ChapterSegmenter` → `ChapterTranslationChunker` → one `AIService.sendRequest(_:using:)` per chunk → strict `TranslationChunkContract` JSON-array decode → per-segment fallback on any decode/count/element mismatch → recombine → cache-write. Reaches the AI side through the `TranslationRequestSending` boundary protocol (tests inject a mock). `Task.checkCancellation()` between chunks so a cancelled prefetch stops promptly |
210:| `ChapterTextProviding` (`Services/Reader/`) | per-format reader services | Feature #56 WI-2.5 boundary protocol — supplies a book's translation units (`translationUnits()`), per-unit plain source text (`sourceText(for:)`), and the `Locator → unit` resolution (`unit(containing:)` / `unit(after:)`) the bilingual prefetch trigger needs. The translation *unit* is the format's natural rendering segment, not the logical TOC chapter (plan Decision 2.7). Four concrete `Sendable` `struct` adapters: `EPUBChapterTextProvider` (spine documents, HTML-stripped via `EPUBTextExtractor`), `TXTChapterTextProvider` (`TXTChapterIndex` chapters, UTF-16 slicing), `MDChapterTextProvider` (`MDHeading`-bounded chapters), `PDFChapterTextProvider` (page ranges via PDFKit). The AZW3/MOBI `FoliateChapterTextProvider` (an `actor`, bridges the `@MainActor` Foliate coordinator via the `FoliateSectionExtracting` facade) lands in WI-11. `ChapterTranslationService` / `BookTranslationCoordinator` consume this boundary, never a format-specific extractor |
212:| `FoliateSectionExtracting` (`Services/Reader/`) | `FoliateSpikeView.Coordinator` (extension) | Feature #56 WI-11 — `@MainActor protocol` bridging the live Foliate per-section text extraction seam (the `readerAPI.bilingualSectionIDs` / `readerAPI.bilingualSectionText` JS calls) into the `Sendable` `ChapterTextProviding` boundary. Class-bound + `Sendable` + `@MainActor` means a `@MainActor`-isolated `AnyObject` existential is safely `Sendable` (members are main-actor-isolated), so the `FoliateChapterTextProvider` actor can hold a single live reference without an unsafe escape hatch |
218:| `ChapterReTranslateViewModel` (`ViewModels/`) | `AIService` + `ChapterTranslationService` + `ChapterTranslationStore` | Feature #56 WI-15 `@MainActor @Observable` UI-facing state for the per-chapter re-translation flow. `presentPicker(...)` opens `ReTranslatePickerSheet` with the chosen unit + title + target language; `updateSelection(_:)` mutates the picker's `(providerProfileID, model, style, keepGlossary)` selection; `submit()` resolves the picker's `ResolvedAIProviderConfig` through the `RetranslateProviderResolving` boundary (`AIService` conforms), runs the translation through `ChapterReTranslating` (`ChapterTranslationService` conforms, with the cache READ bypassed so a fresh row can't no-op the re-translate — Bug #341 atomic swap + Bug #342 canonical key: the cache-write replaces the ONE `book|unit|lang|prompt` row in place, the original translation survives every failure/cancel path, and an override re-translation is readable by bilingual mode on reopen), and fires `onTranslationApplied` so the host posts `.readerBilingualReTranslateApplied`. Picker override never mutates `ProviderProfileStore` (acceptance criterion (f)) |
219:| `EPUBBilingualPipeline` (`Views/Reader/Bilingual/`) | `EPUBBilingualJS` + `EPUBBilingualOrchestrator` | Feature #56 WI-10 pure glue between the EPUB WKWebView's `bilingualEnumerate` message payload and the `BilingualReadingViewModel`'s `translationsByUnit` cache. `parseEnumeratePayload(_:)` decodes the raw `Any` body into an `EPUBBilingualEnumeratePayload` (`{requestedSectionIndex, blocks}`) — accepting BOTH the paged bare-array shape (`[{bid,text}]`, no section identity) and the continuous-scroll envelope (`{sectionIndex, blocks}`); the envelope preserves the section identity on an EMPTY result so the container clears ONLY that section's bucket instead of every bucket (Feature #71 WI-7 Gate-4 round-3 MEDIUM 1). `parseEnumerateMessage(_:)` is the flat-`[BilingualBlock]` convenience over it; `translationsByBid(blocks:translatedSegments:)` maps the VM's ordered segment array onto a `[bid: text]` lookup by position. No `@MainActor` — pure value transforms |
223:| `FoliateBilingualContainerView` (`Views/Reader/`) | `FoliateSpikeView` + `FoliateBilingualOrchestrator` + `BilingualReadingViewModel` + `FoliateChapterTextProvider` | Feature #56 WI-11 — AZW3/MOBI host wrapper that adds the bilingual VM / orchestrator / setup-sheet wiring around the unchanged `FoliateSpikeView`. Owns the bilingual `@State`, the first-enable `BilingualSetupSheet`, and the notification plumbing (`.readerMoreBilingual` → toggle, `.foliateSectionLoaded` → enumerate, `.foliateBilingualBlocksEnumerated` → cache + prefetch, `.readerBilingualDidChange` → inject) that mirrors `EPUBReaderContainerView+Bilingual` for the live Foliate path |
224:| `BilingualDisplaySegmentMap` (`Services/Reader/`) | `BilingualTextRenderer`, `TXTReaderContainerView`, `MDReaderContainerView` | Feature #56 WI-12a pure `Sendable` value type — the TXT/MD source↔display UTF-16 offset map. Records ordered display segments tagged `.source(sourceRange:displayRange:)` or `.synthetic(displayRange:)`. `sourceOffset(forDisplayOffset:)` returns `nil` for synthetic ranges or out-of-bounds offsets; `displayOffset(forSourceOffset:)` clamps a past-end source position to display end. `identity(sourceLength:)` builds the 1:1 pass-through used when bilingual is off. WI-12b consumes the map in TXT/MD container offset-routing |
227:| `BilingualAttributedStringComposer` (`Views/Reader/Bilingual/`) | `BilingualDisplaySegmentMap`, `BilingualTextRenderer` | Feature #56 WI-12b — typography-preserving interlinear composer. `compose(sourceAttributed:sourceParagraphRanges:translatedSegments:)` takes an already-typographed source `NSAttributedString` (font, line spacing, drop-cap, heading restyle) and interleaves synthetic translation runs at paragraph boundaries. Synthetic runs inherit the prior source paragraph's attrs + carry the `decorationAttributeKey`. Used by TXT's chapter-paged path so the chapter-start drop-cap + heading restyle survive the bilingual interleave |
228:| `BilingualDisplayPipeline` (`Views/Reader/Bilingual/`) | `BilingualTextRenderer`, `BilingualAttributedStringComposer`, `BilingualReadingViewModel` | Feature #56 WI-12b — `@MainActor` bridge between the bilingual VM state and the renderer/composer. `makeDisplay(...)` builds a fresh attrString from a plain `String` source; `compose(sourceAttributed:...)` preserves an upstream typographed attrString. Both off-path (no VM / disabled / no unit / no cached translation) returns the source + identity map — the byte-identical pass-through that gates the R-TXT-offsets risk |
229:| `BilingualOffsetRouter` (`Views/Reader/Bilingual/`) | `BilingualDisplaySegmentMap` | Feature #56 WI-12b — pure source↔display offset router for the TXT/MD container's bilingual surfaces. Helpers: `displayOffset(forSourceOffset:map:)`, `sourceOffset(forDisplayOffset:map:)`, `displayRange(forSourceRange:map:)` (segment-union projection — a source range that crosses an intervening synthetic block produces a spanning display range), `displayNSRange(forSourceNSRange:map:)`, `isSynthetic(displayOffset:map:)`. Identity-map mode is byte-identical to today's offset code |
230:| `BilingualTXTBridgeDelegateAdapter` (`Views/Reader/Bilingual/`) | `BilingualDisplaySegmentMap`, `TXTTextViewBridge` | Feature #56 WI-12b — `@MainActor` delegate wrapper that maps display-domain offsets the bridge reports (selection range, top-visible-char scroll offset) back to source-domain offsets via `BilingualOffsetRouter`, so the TXT VM keeps persisting positions in document source coordinates with bilingual on. A selection that starts inside a synthetic translation run is dropped; a scroll-into-synthetic projects to the end of the preceding source segment. Identity map (bilingual off) is a transparent pass-through |
231:| `TXTLoaderBackedChapterTextProvider` (`Services/Reader/`) | `ChapterTextProviding`, `TXTChapterContentLoader` | Feature #56 WI-12b — chapter-paged-mode `ChapterTextProviding` adapter that reads each chapter on demand via the live reader's `TXTChapterContentLoader` actor. Sibling to `TXTChapterTextProvider` (full-book-slicing). Re-enables bilingual mode for chapter-paged TXT, the mode WI-12a's `makeTextProvider` explicitly disabled because the VM's `textContent` is chapter-local in that mode |
232:| `PDFBilingualPanel` (`Views/Reader/Bilingual/`) | `PDFBilingualPanelState`, `BilingualLanguage`, `ReaderThemeV2` | Feature #56 WI-13 — PDF below-page bilingual translation panel. Stateless SwiftUI sub-view rendering the design's split-layout A1..A8: header (lang-glyph chip + page label + status suffix + chevron) + body switched on `PDFBilingualPanelState` (5 states: `.off` / `.loading` / `.translated([String])` / `.offline` / `.empty`). PDF is fixed-layout so the paragraph-interlinear renderer used by EPUB/Foliate/TXT/MD doesn't apply; the panel below the page is the entire user-visible bilingual surface for PDF. 260pt expanded / 38pt collapsed; attached to `PDFViewBridge` via SwiftUI's `.safeAreaInset(edge: .bottom)` so PDFKit's `autoScales` reflows the page rendering automatically |
233:| `PDFBilingualPanelState` (`Views/Reader/Bilingual/`) | `BilingualReadingViewModel`, `PDFChapterTextProvider` | Feature #56 WI-13 — pure synchronous derivation of the panel's 5-state matrix from the bilingual VM + the PDF's `(currentPage, pagesPerUnit, totalPages)` triple. Computes the current `TranslationUnitID` synchronously (mirrors `PDFChapterTextProvider.pageRanges` arithmetic) instead of reading the VM's async-updated `lastTriggerUnit`, so page-turn-in-flight doesn't flash stale translations (Gate-2 v5 round-1 H1). `.empty` keyed on "translated segments empty after fetch" OR "totalPages <= 0", NOT `unit == nil` (which would never fire for a real PDF — Gate-2 v5 round-1 M1) |
234:| `PDFReaderContainerView+Bilingual` (`Views/Reader/`) | `BilingualReadingViewModel`, `PDFChapterTextProvider`, `PDFBilingualPanel`, `PDFBilingualPanelState` | Feature #56 WI-13 — PDF host extension owning the bilingual VM lifecycle (lazy construction gated on `viewModel.isDocumentLoaded` + `totalPages > 0`), the `PDFChapterTextProvider` build, the prefetcher build (mirrors TXT/EPUB `makePrefetcher`), the first-enable setup sheet, the More-menu toggle observer, the retry observer (`.readerBilingualRetry`), and the `.safeAreaInset`-attached panel. On reopen of an already-enabled book, `ensureBilingualViewModel` kicks the initial `handlePositionChange` so the panel doesn't stick in `.loading` for the open page (Gate-4 round-1 H1). Mirrors `TXTReaderContainerView+Bilingual` / `MDReaderContainerView+Bilingual` / `EPUBReaderContainerView+Bilingual` structurally |
238:SwiftData SchemaV10 entities (V9→V10 adds the additive optional `Book.sourceCanonicalKey: String?` — feature #108's converted-Kindle cross-platform identity, carried in the backup manifest; feature #109's NFC locator-key recompute runs as the launch-time `LocatorKeyBackfillMigration`, not a schema migration — see the App Layer note above):
240:- `Book` (fingerprintKey unique; gains `originalExtension: String?` in SchemaV5 for backup blob extension preservation; gains `fileState: String` and `blobPath: String?` in SchemaV6 for feature #47's lazy-load row state; gains `sourceCanonicalKey: String?` in SchemaV10 — feature #108's converted-Kindle source-bytes cross-platform identity, while the converted-EPUB `fingerprintKey` stays the local primary) → `ReadingPosition` (gains `vreaderLocatorData: Data?` in SchemaV8 — feature #42's engine-agnostic `VReaderLocator` envelope, stored as raw JSON `Data?` mirroring `Highlight.anchorData`; additive/optional → lightweight migration, no stage), `Highlight`, `Bookmark`, `AnnotationNote`, `BookCollection`, `ChatSession` (SchemaV9 cascade child)
243:- `ChapterTranslation` (added in SchemaV7 — feature #56 bilingual-reading persistent translation cache; independent entity, no `@Relationship` to `Book`; `lookupKey: String` is the `@Attribute(.unique)` dedupe key joined from `bookFingerprintKey` + `unitStorageKey` + `targetLanguage` + `promptVersion` — Bug #342 dropped `providerProfileID` from the key (now provenance metadata only; one canonical translation shared by bilingual reading + re-translate), with a lazy in-store migration for pre-#342 rows)
246:`PersistenceActor.fetchAllBooksForBackup() -> [BackupBookProjection]` (in `PersistenceActor+Backup.swift`) returns a Sendable value-type view of every book — used by feature #46's WebDAV backup to emit `library-manifest.json` without leaking `@Model` instances across the actor boundary. Legacy V4 rows (no `originalExtension`) coalesce to the canonical extension for their format.
250:**Feature #46 — WebDAV materializing restore (data layer)**: backup ZIPs now carry an additional `library-manifest.json` section (one `BackupLibraryEntry` per book, including content-addressed `blobPath`). On `backup`, `WebDAVProvider` uploads each missing book blob atomically — `WebDAVBlobStore` PUTs to `VReader/uploads/tmp/<uuid>.part`, PROPFIND-verifies the size, then `MOVE`s into the canonical `VReader/books/<format>/<sha256>_<byteCount>.<ext>` path. Repeat backups skip already-published blobs via PROPFIND-by-size dedupe. On `restore`, when the manifest is present and a `BookImporter` is wired in (production: via `\.bookImporter` SwiftUI Environment), `BookFileMaterializer` downloads + verifies + imports each missing blob before metadata sections apply. v1-format backups (no manifest) restore as before — books silently skipped if missing locally. The 412 response from `MOVE Overwrite: F` is treated as "blob already converged" (content-addressing). 501 from `MOVE` raises `BackupBlobStoreError.serverCapabilityMissing` — no silent atomicity loss.
252:**Feature #89 — AI conversations backup (data layer)**: backup ZIPs carry an
262:by the unique `sessionId`, always re-keys `bookFingerprintKey` to the backup
263:("backup value wins"), re-associates `row.book` when the book is present locally
318:| `.readerMoreBilingual`         | nil                  | `ReaderMorePopover` → format containers (Feature #56 WI-8 — tap the bilingual row; per-format containers route to `BilingualReadingViewModel.setEnabled(...)`, or to AI Settings when bilingual is `.unavailable`) |
321:| `.readerBilingualDidChange`    | `["fingerprintKey": String, "isEnabled": Bool, "targetLanguage": String, "granularity": String]` | `BilingualReadingViewModel` → format renderers + parent reader chrome (Feature #56 WI-7b/WI-10/WI-11 — bilingual toggled on/off, language changed, or a unit's translation became available; renderers re-inject or clear the interlinear translation, the parent `ReaderContainerView` mirrors `isEnabled` + `targetLanguage` into `bilingualActive` / `bilingualLanguage` so the `BilingualPill` and More-menu row paint without crossing the host boundary) |
323:| `.readerMoreTranslationSettings` | `["fingerprintKey": String, "bookTitle": String]` | More-menu settings row + bilingual pill → per-format bilingual hosts (Feature #99 — keyed re-entry; the host presents the edit-framed `BilingualSetupSheet`. Every More-menu row post now carries `fingerprintKey`; only this one REQUIRES filtering) |
326:| `.readerBilingualRetry`        | nil | PDF below-page bilingual panel offline-state Retry button → `PDFReaderContainerView+Bilingual` (Feature #56 WI-13 — host calls `BilingualReadingViewModel.retryUnit(currentUnit)`, scoped to the current page's unit, NOT the whole-book `resetTriggerState()`) |
327:| `.readerBilingualSectionMaterialized` | `["fingerprintKey": String, "spineIndex": Int]` | `EPUBContinuousScrollCoordinator` (via `EPUBContinuousScrollConfig.onSectionMaterialized`) → `EPUBReaderContainerView+ContinuousBilingual` (Feature #71 WI-7 — a stitched chapter section materialized in EPUB continuous-scroll mode; the modifier drives a SECTION-SCOPED enumerate `bilingualEnumerateJS(spineIndex:)` through the live evaluator, then prefetches + injects THAT section's own unit. Posted with no View capture from the long-lived config closure) |
329:| `.readerOpenAITranslate`       | nil | PDF below-page bilingual panel offline-state "Open AI tab" button → ReaderContainerView (Feature #56 WI-13 — gated on `resolvedAICoordinator.isAIAvailable`; resets `translationViewModel` then sets `aiInitialTab = .translate` + `showAIPanel = true` to open the AI Translate tab cold without a selection) |
332:| `.foliateBilingualBlocksEnumerated` | `["blocks": [BilingualBlock], "fingerprintKey": String]` | `FoliateSpikeView.Coordinator` → `FoliateBilingualContainerView` (Feature #56 WI-11 — AZW3/MOBI live `bilingualEnumerate` JS message parsed into `[BilingualBlock]`; the container caches blocks on the orchestrator and asks the bilingual VM to prefetch translations for the current unit) |
338:| `.foliateSectionLoaded`        | `["sectionIndex": Int, "fingerprintKey": String]` | `FoliateSpikeView.Coordinator` → `FoliateBilingualContainerView` (Feature #56 WI-11 — Foliate-js `section-load` event surfaced so the bilingual container refreshes its enumerate payload against the freshly-rendered section) |
512:## Android App (`android/` — feature #106 foundation bar)
514:vreader's Android app is a **second, independently-shippable native app**
516:shares the identity / locator / cache-key / backup **contracts**
524:> module, Room persistence, EPUB import, and the resume bridge. The
535:| `:app` | Android application | Compose UI shell + the Room data layer + reader plumbing. `com.vreader.app`. |
536:| `:identity` | pure Kotlin/JVM (no Android deps) | The shared canonical contracts — `Identity` (fingerprint canonical key), `CanonicalLocator` (engine-neutral canonical JSON), `DocumentFingerprint` (streaming SHA-256 + format detection), and the `Locator` / `VReaderLocator` / `ReaderLocatorEngine` value types. **Both `:app` AND the `contracts/conformance` lane depend on this one module**, so the golden-vector conformance test proves the SAME code the app runs. |
540:- **Room** is the SwiftData analog. `VReaderDatabase` (`@Database` v4,
550:  is the canonical `Locator.canonicalJson()` (the #113 backup contract); the
555:  the Room schema.
560:  never Room entities, across the boundary (the rule-50 §2 analog).

exec
/bin/zsh -lc "rg -n \"bilingualGranularity|bilingualEnabled|bilingualTargetLanguage\" contracts android vreader | head -120; rg -n \"ChapterTranslationEntity|sourceParagraphCount|unitStorageKey|translatedJson\" android/app/src/main/kotlin android/app/schemas 2>/dev/null | head -80; rg --files android/app | rg '/schemas/|VReaderDatabaseMigrationTest' | tail -30" in /Users/ll/workspace/vreader
 succeeded in 0ms:
contracts/vectors/backup-sections.json:116:            "bilingualEnabled": true,
contracts/vectors/backup-sections.json:117:            "bilingualTargetLanguage": "Chinese"
android/identity/src/main/kotlin/vreader/contracts/backup/BackupSectionsExtended.kt:69:    val bilingualEnabled: Boolean? = null,
android/identity/src/main/kotlin/vreader/contracts/backup/BackupSectionsExtended.kt:70:    val bilingualTargetLanguage: String? = null,
android/identity/src/main/kotlin/vreader/contracts/backup/BackupSectionsExtended.kt:71:    val bilingualGranularity: String? = null,
android/identity/src/test/kotlin/vreader/contracts/backup/BackupSectionsExtendedTest.kt:86:            override = PerBookSettingsOverride(fontSize = 18.0, bilingualEnabled = true, bilingualTargetLanguage = "Chinese"),
android/identity/src/test/kotlin/vreader/contracts/backup/BackupSectionsExtendedTest.kt:91:        assertTrue(json.contains("\"bilingualEnabled\""))
vreader/Services/AI/ChapterTranslationService.swift:72:/// `bilingualGranularity`).
vreader/Services/PerBookSettings.swift:33:    var bilingualEnabled: Bool?
vreader/Services/PerBookSettings.swift:37:    var bilingualTargetLanguage: String?
vreader/Services/PerBookSettings.swift:41:    var bilingualGranularity: String?
vreader/Services/PerBookSettings.swift:53:        bilingualEnabled: Bool? = nil,
vreader/Services/PerBookSettings.swift:54:        bilingualTargetLanguage: String? = nil,
vreader/Services/PerBookSettings.swift:55:        bilingualGranularity: String? = nil
vreader/Services/PerBookSettings.swift:62:        self.bilingualEnabled = bilingualEnabled
vreader/Services/PerBookSettings.swift:63:        self.bilingualTargetLanguage = bilingualTargetLanguage
vreader/Services/PerBookSettings.swift:64:        self.bilingualGranularity = bilingualGranularity
vreader/Views/Reader/ReaderContainerView+Sheets.swift:405:            rawValue: bilingualGranularity ?? "") ?? .paragraph
vreader/ViewModels/AIAssistantViewModel.swift:77:    /// seeds the per-book `bilingualTargetLanguage` once on first appear
vreader/ViewModels/BilingualReadingViewModel.swift:154:        self.isEnabled = override?.bilingualEnabled ?? false
vreader/ViewModels/BilingualReadingViewModel.swift:155:        self.targetLanguage = override?.bilingualTargetLanguage ?? Self.defaultTargetLanguage
vreader/ViewModels/BilingualReadingViewModel.swift:157:            rawValue: override?.bilingualGranularity ?? "") ?? .paragraph
vreader/ViewModels/BilingualReadingViewModel.swift:256:        return override?.bilingualEnabled != nil
vreader/ViewModels/BilingualReadingViewModel.swift:257:            || override?.bilingualTargetLanguage != nil
vreader/ViewModels/BilingualReadingViewModel.swift:258:            || override?.bilingualGranularity != nil
vreader/ViewModels/BilingualReadingViewModel.swift:266:        override.bilingualEnabled = isEnabled
vreader/ViewModels/BilingualReadingViewModel.swift:267:        override.bilingualTargetLanguage = targetLanguage
vreader/ViewModels/BilingualReadingViewModel.swift:268:        override.bilingualGranularity = granularity.rawValue
vreader/Views/Reader/ReaderAICoordinator.swift:274:           let langKey = override.bilingualTargetLanguage {
vreader/Views/Reader/Bilingual/BilingualLanguage.swift:3:// (`bilingualTargetLanguage`) all key off. Pinned to the design
vreader/Views/Reader/Bilingual/BilingualLanguage.swift:28://   PerBookSettings.swift (`bilingualTargetLanguage`),
vreader/Views/Reader/Bilingual/BilingualLanguage.swift:36:    /// Canonical key persisted in `PerBookSettings.bilingualTargetLanguage`
vreader/Views/Reader/Bilingual/BilingualSetupSheet.swift:207:                    .accessibilityIdentifier("bilingualGranularity_\(option.rawValue)")
vreader/Views/Reader/Bilingual/BilingualSetupSheet.swift:229:                .accessibilityIdentifier("bilingualGranularityUnavailableFootnote")
vreader/Views/Reader/ReaderTopChrome.swift:48:    /// `PerBookSettings.bilingualTargetLanguage`. `nil` (book never
vreader/Views/Reader/ReaderContainerView.swift:223:    @State var bilingualGranularity: String?
vreader/Views/Reader/ReaderContainerView.swift:540:                bilingualGranularity = granularity
android/app/schemas/com.vreader.app.data.VReaderDatabase/5.json
android/app/schemas/com.vreader.app.data.VReaderDatabase/4.json
android/app/schemas/com.vreader.app.data.VReaderDatabase/8.json
android/app/schemas/com.vreader.app.data.VReaderDatabase/3.json
android/app/schemas/com.vreader.app.data.VReaderDatabase/2.json
android/app/schemas/com.vreader.app.data.VReaderDatabase/7.json
android/app/schemas/com.vreader.app.data.VReaderDatabase/6.json
android/app/src/test/kotlin/com/vreader/app/data/VReaderDatabaseMigrationTest.kt

exec
/bin/zsh -lc "nl -ba android/app/src/test/kotlin/com/vreader/app/ai/AiSettingsViewModelTest.kt | sed -n '45,78p'; nl -ba android/app/src/main/kotlin/com/vreader/app/ai/AiProviderEditSheet.kt | sed -n '45,90p'; rg -n \"AiProviderListScreen\\(\" android/app/src/main android/app/src/test android/app/src/androidTest" in /Users/ll/workspace/vreader
 succeeded in 0ms:
    45	    @Before fun setUp() {
    46	        Dispatchers.setMain(dispatcher)
    47	        // DataStore on the SAME test dispatcher so advanceUntilIdle() drives its IO too.
    48	        store = AiProviderStore(
    49	            PreferenceDataStoreFactory.create(scope = CoroutineScope(dispatcher)) { tmp.newFile("ai.preferences_pb") },
    50	            cipher,
    51	        )
    52	    }
    53	
    54	    @After fun tearDown() = Dispatchers.resetMain()
    55	
    56	    private fun vm(result: AiTestResult = AiTestResult.Ok) =
    57	        AiSettingsViewModel(store, dispatcher) { _, _ -> FakeClient(result) }
    58	
    59	    @Test fun openAdd_test_ok_thenSave_persists() = runTest(dispatcher) {
    60	        val vm = vm(AiTestResult.Ok)
    61	        vm.openAdd()
    62	        vm.update { it.copy(name = "OpenRouter", apiKey = "sk-test") }
    63	        vm.test(); advanceUntilIdle()
    64	        assertEquals(AiConnTest.ok, vm.editState.value!!.test)
    65	
    66	        vm.save(); advanceUntilIdle()
    67	        assertNull(vm.editState.value)                     // sheet closed
    68	        assertEquals(1, store.list().size)                 // persisted
    69	        assertEquals("sk-test", store.apiKey(store.list()[0].id))
    70	    }
    71	
    72	    @Test fun test_fail_surfacesMessage() = runTest(dispatcher) {
    73	        val vm = vm(AiTestResult.Fail(AiError.Auth401, "Failed: 401"))
    74	        vm.openAdd()
    75	        vm.update { it.copy(name = "X", apiKey = "bad") }
    76	        vm.test(); advanceUntilIdle()
    77	        assertEquals(AiConnTest.fail, vm.editState.value!!.test)
    78	        assertTrue(vm.editState.value!!.testMessage.contains("401"))
    45	import androidx.compose.ui.unit.sp
    46	import com.vreader.app.backup.AppSheet
    47	import com.vreader.app.backup.BackupFonts
    48	import com.vreader.app.backup.GroupFooter
    49	import com.vreader.app.backup.GroupHeader
    50	import com.vreader.app.backup.LocalBackupTokens
    51	import com.vreader.app.backup.SettingsCard
    52	import com.vreader.app.backup.VSpace
    53	
    54	@Composable
    55	fun AiProviderEditSheet(
    56	    state: AiEditState,
    57	    onKind: (AiProviderKind) -> Unit = {},
    58	    onName: (String) -> Unit = {},
    59	    onBaseUrl: (String) -> Unit = {},
    60	    onModel: (String) -> Unit = {},
    61	    onTemperature: (Double) -> Unit = {},
    62	    onMaxTokens: (Int) -> Unit = {},
    63	    onApiKey: (String) -> Unit = {},
    64	    onDeleteKey: () -> Unit = {},
    65	    onTest: () -> Unit = {},
    66	    onSave: () -> Unit = {},
    67	    onCancel: () -> Unit = {},
    68	) {
    69	    val t = LocalBackupTokens.current
    70	    Box(Modifier.fillMaxSize()) {
    71	        AppSheet(
    72	            title = if (state.editMode) "Edit Provider" else "Add Provider",
    73	            leading = {
    74	                Box(Modifier.sizeIn(minWidth = 48.dp, minHeight = 48.dp).clickable(onClick = onCancel), contentAlignment = Alignment.CenterStart) {
    75	                    Text("Cancel", color = t.sec, fontFamily = BackupFonts.Sans, fontSize = 15.sp)
    76	                }
    77	            },
    78	            trailing = {
    79	                Box(Modifier.sizeIn(minWidth = 48.dp, minHeight = 48.dp).clickable(enabled = state.canSave, onClick = onSave).testTag("ai-save"), contentAlignment = Alignment.CenterEnd) {
    80	                    Text("Save", color = if (state.canSave) t.tint else t.ter, fontFamily = BackupFonts.Sans, fontSize = 15.sp, fontWeight = FontWeight.SemiBold)
    81	                }
    82	            },
    83	        ) {
    84	            Column(Modifier.padding(horizontal = 18.dp).padding(top = 16.dp, bottom = 32.dp)) {
    85	                GroupHeader("Provider Type")
    86	                Segmented(state.kind, onKind)
    87	
    88	                VSpace(20)
    89	                GroupHeader("Name")
    90	                SettingsCard { Field("", state.name, "e.g. OpenRouter", onName) }
android/app/src/androidTest/kotlin/com/vreader/app/ai/AiProviderListScreenTest.kt:23:            BackupSurface(darkOverride = false) { AiProviderListScreen(AiProviderListState(emptyList()), onAdd = { added = true }) }
android/app/src/androidTest/kotlin/com/vreader/app/ai/AiProviderListScreenTest.kt:38:        compose.setContent { BackupSurface(darkOverride = false) { AiProviderListScreen(state, onEdit = { edited = it }) } }
android/app/src/main/kotlin/com/vreader/app/ai/AiProviderListScreen.kt:46:fun AiProviderListScreen(

exec
/bin/zsh -lc "rg -n \"enum BilingualGranularity|case paragraph|case sentence\" vreader | head -30; nl -ba android/identity/src/main/kotlin/vreader/contracts/backup/BackupSectionsExtended.kt | sed -n '55,78p'; nl -ba contracts/vectors/backup-sections.json | sed -n '105,125p'" in /Users/ll/workspace/vreader
 succeeded in 0ms:
vreader/Services/AI/ChapterTranslationService.swift:74:    case paragraph
vreader/Services/AI/ChapterTranslationService.swift:75:    case sentence
    55	data class BackupPerBookSettingsEntry(
    56	    val bookFingerprintKey: String,
    57	    val override: PerBookSettingsOverride,
    58	)
    59	
    60	/** Per-book reader overrides — mirrors Swift `PerBookSettingsOverride` (CGFloat ⇒ Double).
    61	 *  All fields optional; a nil inherits the global default. */
    62	@Serializable
    63	data class PerBookSettingsOverride(
    64	    val fontSize: Double? = null,
    65	    val fontName: String? = null,
    66	    val lineSpacing: Double? = null,
    67	    val letterSpacing: Double? = null,
    68	    val themeName: String? = null,
    69	    val bilingualEnabled: Boolean? = null,
    70	    val bilingualTargetLanguage: String? = null,
    71	    val bilingualGranularity: String? = null,
    72	    val metricsReadout: String? = null,
    73	)
    74	
    75	// MARK: - Replacement Rules
    76	
    77	@Serializable
    78	data class BackupReplacementRulesEnvelope(
   105	          "customOrder": 0
   106	        }
   107	      ]
   108	    },
   109	    "per-book-settings": {
   110	      "schemaVersion": 3,
   111	      "entries": [
   112	        {
   113	          "bookFingerprintKey": "epub:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa:1024",
   114	          "override": {
   115	            "fontSize": 18.0,
   116	            "bilingualEnabled": true,
   117	            "bilingualTargetLanguage": "Chinese"
   118	          }
   119	        }
   120	      ]
   121	    },
   122	    "replacement-rules": {
   123	      "schemaVersion": 3,
   124	      "rules": [
   125	        {

codex
## Critical

None.

## High

- **H2 remains unresolved: item-level visibility no longer proves source-text visibility.** The `Column` correctly preserves one lazy item per chunk and therefore preserves index identity. However, adding translation content increases that item’s height. When the source `Text` has scrolled above the viewport but its translation sibling remains visible, `visibleItemsInfo` still contains the chunk’s item index. The existing TTS guard therefore suppresses `animateScrollToItem(spokenChunk)`, leaving the spoken source off-screen ([TxtReaderActivity.kt](/Users/ll/workspace/vreader/android/app/src/main/kotlin/com/vreader/app/reader/TxtReaderActivity.kt:252), [TxtReaderActivity.kt](/Users/ll/workspace/vreader/android/app/src/main/kotlin/com/vreader/app/reader/TxtReaderActivity.kt:256)). The plan incorrectly equates item visibility with source visibility and does not test the translation-only-visible case ([plan](/Users/ll/workspace/vreader/dev-docs/plans/20260710-feature-131-android-bilingual-interlinear.md:89), [plan](/Users/ll/workspace/vreader/dev-docs/plans/20260710-feature-131-android-bilingual-interlinear.md:109), [plan](/Users/ll/workspace/vreader/dev-docs/plans/20260710-feature-131-android-bilingual-interlinear.md:375)).  
  **Required patch:** define TTS visibility using the registered source `Text` bounds—not merely `visibleItemsInfo.index`—and add a test where only the translation portion of `spokenChunk`’s item is visible. This is newly introduced by the in-item `Column`.

## Medium

None.

## Low

None.

## Resolved checks

- **H1 resolved.** `Utf16Span(start, endExclusive)` is consistently half-open and replaces contractual `IntRange` signatures ([plan](/Users/ll/workspace/vreader/dev-docs/plans/20260710-feature-131-android-bilingual-interlinear.md:61), [plan](/Users/ll/workspace/vreader/dev-docs/plans/20260710-feature-131-android-bilingual-interlinear.md:72)). The final-chunk calculation matches `textForChunk` ([TxtDocument.kt](/Users/ll/workspace/vreader/android/app/src/main/kotlin/com/vreader/app/reader/TxtDocument.kt:36)); `endExclusive - 1` correctly anchors one-chunk, final-chunk, exact-boundary, and EOF spans because `chunkForOffset` chooses the greatest start not exceeding the offset ([TxtDocument.kt](/Users/ll/workspace/vreader/android/app/src/main/kotlin/com/vreader/app/reader/TxtDocument.kt:23)).

- **H2 otherwise resolved.** A `Column` child creates no lazy item, so position saving, progress, jumps, and lazy keys retain chunk-index identity. Source layout/registration remains one-per-chunk ([TxtReaderActivity.kt](/Users/ll/workspace/vreader/android/app/src/main/kotlin/com/vreader/app/reader/TxtReaderActivity.kt:1043), [TxtReaderActivity.kt](/Users/ll/workspace/vreader/android/app/src/main/kotlin/com/vreader/app/reader/TxtReaderActivity.kt:1059)). Explicit gesture exclusion is necessary because `hitAt` falls back to the nearest registered source chunk ([TxtSelectionController.kt](/Users/ll/workspace/vreader/android/app/src/main/kotlin/com/vreader/app/reader/TxtSelectionController.kt:47)).

- **H3 resolved.** The renderer design is paragraph-interlinear only ([vreader-bilingual.jsx](/Users/ll/workspace/vreader/dev-docs/designs/vreader-fidelity-v1/project/vreader-bilingual.jsx:195), [vreader-bilingual.jsx](/Users/ll/workspace/vreader/dev-docs/designs/vreader-fidelity-v1/project/vreader-bilingual.jsx:241)). Descoping the Sentence control alongside its unsupported behavior is sound: it prevents sentence-keyed paragraph rows and exposes no undesigned sentence renderer. The divergence and follow-up are explicit ([plan](/Users/ll/workspace/vreader/dev-docs/plans/20260710-feature-131-android-bilingual-interlinear.md:116), [plan](/Users/ll/workspace/vreader/dev-docs/plans/20260710-feature-131-android-bilingual-interlinear.md:424)).

- **H4 resolved.** The live list screen owns incompatible chrome, generic empty copy, and edit-on-tap behavior ([AiProviderListScreen.kt](/Users/ll/workspace/vreader/android/app/src/main/kotlin/com/vreader/app/ai/AiProviderListScreen.kt:59), [AiProviderListScreen.kt](/Users/ll/workspace/vreader/android/app/src/main/kotlin/com/vreader/app/ai/AiProviderListScreen.kt:84), [AiProviderListScreen.kt](/Users/ll/workspace/vreader/android/app/src/main/kotlin/com/vreader/app/ai/AiProviderListScreen.kt:105)). A new scoped list matches the designed back label, empty state, checked row, and select action ([vreader-ai-provider-entry.jsx](/Users/ll/workspace/vreader/dev-docs/designs/vreader-fidelity-v1/project/vreader-ai-provider-entry.jsx:180), [vreader-ai-provider-entry.jsx](/Users/ll/workspace/vreader/dev-docs/designs/vreader-fidelity-v1/project/vreader-ai-provider-entry.jsx:221), [vreader-ai-provider-entry.jsx](/Users/ll/workspace/vreader/dev-docs/designs/vreader-fidelity-v1/project/vreader-ai-provider-entry.jsx:247)). Awaiting `upsert`’s returned profile ID before `setActive` and pop is race-free ([AiProviderStore.kt](/Users/ll/workspace/vreader/android/app/src/main/kotlin/com/vreader/app/ai/AiProviderStore.kt:60), [plan](/Users/ll/workspace/vreader/dev-docs/plans/20260710-feature-131-android-bilingual-interlinear.md:372)).

- **Gap A resolved.** The DDL matches the proposed non-null entity columns, PK, index, and existing FK/CASCADE conventions ([plan](/Users/ll/workspace/vreader/dev-docs/plans/20260710-feature-131-android-bilingual-interlinear.md:246), [VReaderDatabase.kt](/Users/ll/workspace/vreader/android/app/src/main/kotlin/com/vreader/app/data/VReaderDatabase.kt:151)). Opening the migrated database against generated `9.json` is the correct structural guard.

- **Gap B resolved.** Android already declares the nullable field, while the shared vector currently omits it ([BackupSectionsExtended.kt](/Users/ll/workspace/vreader/android/identity/src/main/kotlin/vreader/contracts/backup/BackupSectionsExtended.kt:63), [backup-sections.json](/Users/ll/workspace/vreader/contracts/vectors/backup-sections.json:109)). Because backup collection/restoration is explicitly outside v1, the conformance-vector and iOS-parity follow-up is adequate and non-blocking.

FINAL VERDICT: block-recommended
tokens used
101,368
## Critical

None.

## High

- **H2 remains unresolved: item-level visibility no longer proves source-text visibility.** The `Column` correctly preserves one lazy item per chunk and therefore preserves index identity. However, adding translation content increases that item’s height. When the source `Text` has scrolled above the viewport but its translation sibling remains visible, `visibleItemsInfo` still contains the chunk’s item index. The existing TTS guard therefore suppresses `animateScrollToItem(spokenChunk)`, leaving the spoken source off-screen ([TxtReaderActivity.kt](/Users/ll/workspace/vreader/android/app/src/main/kotlin/com/vreader/app/reader/TxtReaderActivity.kt:252), [TxtReaderActivity.kt](/Users/ll/workspace/vreader/android/app/src/main/kotlin/com/vreader/app/reader/TxtReaderActivity.kt:256)). The plan incorrectly equates item visibility with source visibility and does not test the translation-only-visible case ([plan](/Users/ll/workspace/vreader/dev-docs/plans/20260710-feature-131-android-bilingual-interlinear.md:89), [plan](/Users/ll/workspace/vreader/dev-docs/plans/20260710-feature-131-android-bilingual-interlinear.md:109), [plan](/Users/ll/workspace/vreader/dev-docs/plans/20260710-feature-131-android-bilingual-interlinear.md:375)).  
  **Required patch:** define TTS visibility using the registered source `Text` bounds—not merely `visibleItemsInfo.index`—and add a test where only the translation portion of `spokenChunk`’s item is visible. This is newly introduced by the in-item `Column`.

## Medium

None.

## Low

None.

## Resolved checks

- **H1 resolved.** `Utf16Span(start, endExclusive)` is consistently half-open and replaces contractual `IntRange` signatures ([plan](/Users/ll/workspace/vreader/dev-docs/plans/20260710-feature-131-android-bilingual-interlinear.md:61), [plan](/Users/ll/workspace/vreader/dev-docs/plans/20260710-feature-131-android-bilingual-interlinear.md:72)). The final-chunk calculation matches `textForChunk` ([TxtDocument.kt](/Users/ll/workspace/vreader/android/app/src/main/kotlin/com/vreader/app/reader/TxtDocument.kt:36)); `endExclusive - 1` correctly anchors one-chunk, final-chunk, exact-boundary, and EOF spans because `chunkForOffset` chooses the greatest start not exceeding the offset ([TxtDocument.kt](/Users/ll/workspace/vreader/android/app/src/main/kotlin/com/vreader/app/reader/TxtDocument.kt:23)).

- **H2 otherwise resolved.** A `Column` child creates no lazy item, so position saving, progress, jumps, and lazy keys retain chunk-index identity. Source layout/registration remains one-per-chunk ([TxtReaderActivity.kt](/Users/ll/workspace/vreader/android/app/src/main/kotlin/com/vreader/app/reader/TxtReaderActivity.kt:1043), [TxtReaderActivity.kt](/Users/ll/workspace/vreader/android/app/src/main/kotlin/com/vreader/app/reader/TxtReaderActivity.kt:1059)). Explicit gesture exclusion is necessary because `hitAt` falls back to the nearest registered source chunk ([TxtSelectionController.kt](/Users/ll/workspace/vreader/android/app/src/main/kotlin/com/vreader/app/reader/TxtSelectionController.kt:47)).

- **H3 resolved.** The renderer design is paragraph-interlinear only ([vreader-bilingual.jsx](/Users/ll/workspace/vreader/dev-docs/designs/vreader-fidelity-v1/project/vreader-bilingual.jsx:195), [vreader-bilingual.jsx](/Users/ll/workspace/vreader/dev-docs/designs/vreader-fidelity-v1/project/vreader-bilingual.jsx:241)). Descoping the Sentence control alongside its unsupported behavior is sound: it prevents sentence-keyed paragraph rows and exposes no undesigned sentence renderer. The divergence and follow-up are explicit ([plan](/Users/ll/workspace/vreader/dev-docs/plans/20260710-feature-131-android-bilingual-interlinear.md:116), [plan](/Users/ll/workspace/vreader/dev-docs/plans/20260710-feature-131-android-bilingual-interlinear.md:424)).

- **H4 resolved.** The live list screen owns incompatible chrome, generic empty copy, and edit-on-tap behavior ([AiProviderListScreen.kt](/Users/ll/workspace/vreader/android/app/src/main/kotlin/com/vreader/app/ai/AiProviderListScreen.kt:59), [AiProviderListScreen.kt](/Users/ll/workspace/vreader/android/app/src/main/kotlin/com/vreader/app/ai/AiProviderListScreen.kt:84), [AiProviderListScreen.kt](/Users/ll/workspace/vreader/android/app/src/main/kotlin/com/vreader/app/ai/AiProviderListScreen.kt:105)). A new scoped list matches the designed back label, empty state, checked row, and select action ([vreader-ai-provider-entry.jsx](/Users/ll/workspace/vreader/dev-docs/designs/vreader-fidelity-v1/project/vreader-ai-provider-entry.jsx:180), [vreader-ai-provider-entry.jsx](/Users/ll/workspace/vreader/dev-docs/designs/vreader-fidelity-v1/project/vreader-ai-provider-entry.jsx:221), [vreader-ai-provider-entry.jsx](/Users/ll/workspace/vreader/dev-docs/designs/vreader-fidelity-v1/project/vreader-ai-provider-entry.jsx:247)). Awaiting `upsert`’s returned profile ID before `setActive` and pop is race-free ([AiProviderStore.kt](/Users/ll/workspace/vreader/android/app/src/main/kotlin/com/vreader/app/ai/AiProviderStore.kt:60), [plan](/Users/ll/workspace/vreader/dev-docs/plans/20260710-feature-131-android-bilingual-interlinear.md:372)).

- **Gap A resolved.** The DDL matches the proposed non-null entity columns, PK, index, and existing FK/CASCADE conventions ([plan](/Users/ll/workspace/vreader/dev-docs/plans/20260710-feature-131-android-bilingual-interlinear.md:246), [VReaderDatabase.kt](/Users/ll/workspace/vreader/android/app/src/main/kotlin/com/vreader/app/data/VReaderDatabase.kt:151)). Opening the migrated database against generated `9.json` is the correct structural guard.

- **Gap B resolved.** Android already declares the nullable field, while the shared vector currently omits it ([BackupSectionsExtended.kt](/Users/ll/workspace/vreader/android/identity/src/main/kotlin/vreader/contracts/backup/BackupSectionsExtended.kt:63), [backup-sections.json](/Users/ll/workspace/vreader/contracts/vectors/backup-sections.json:109)). Because backup collection/restoration is explicitly outside v1, the conformance-vector and iOS-parity follow-up is adequate and non-blocking.

FINAL VERDICT: block-recommended
