---
branch: feat/feature-56-wi-10-epub-interlinear
threadId: 019e4291-7e0f-7243-87e4-3951a8bf232d
rounds: 3
final_verdict: ship-as-is
date: 2026-05-20
---

# Codex Gate-4 Audit — Feature #56 WI-10 (EPUB bilingual interlinear)

Three rounds of Codex audit per rule 47 Gate 4. Each round identified
real issues that were fixed before the next round. All findings closed
or accepted with rationale below.

## Round 1 (thread 019e4291-7e0f-7243-87e4-3951a8bf232d)

Five findings — 4 High + 1 Medium.

### [1] (High): `EPUBChapterTextProvider` whitespace-collapses block boundaries → segment/block count mismatch.

**Root cause**: `EPUBTextExtractor.stripHTML(_:)` replaces every block-level
closing tag with a single space. The translation service's
`ChapterSegmenter.paragraphs(in:)` splits on blank lines, so a chapter
with N `<p>` blocks produced 1 segment. The enumerator JS stamped N
blocks. Mismatch broke the inject path's 1:1 mapping — typical chapters
would inject only the first translation or mis-align translations onto
later blocks.

**Fix (rounds 1 → 3 iterative)**: new `EPUBTextExtractor.stripHTMLPreservingBlocks(_:)`
that emits `\n\n` after every block-level closing tag whose tag set
matches `EPUBBilingualJS.BLOCK_TAGS` exactly (`p|li|blockquote|pre|dd|dt`).
`<br>` is treated as a soft wrap (single `\n`). `<script>` /
`<style>` blocks are removed entirely. Switched
`EPUBChapterTextProvider.sourceText(for:)` to use the new variant. Search
indexing keeps the legacy whitespace-collapsing path.

**Tests** (`vreaderTests/Services/Search/EPUBTextExtractorBilingualTests.swift`):
N blocks → N segments; `<br>` is soft-wrap; mixed block types preserve
order; structural wrappers (`<section>`, `<article>`, `<div>`) transparent
to segment count; empty body → 0 segments.

**Status**: closed.

### [2] (High): Sentence granularity blind 1:1 inject.

**Root cause**: `BilingualReadingViewModel` passes `granularity: .sentence`
through to the prefetcher when the user picks that setup-sheet option.
But the EPUB enumerator walks DOM block elements; sentence segmentation
produces N×M segments (where M is sentences-per-block), and the
1:1-index inject would mis-map.

**Fix**: `ChapterTranslationPrefetcher.translatedSegments(...)` forces
`.paragraph` regardless of the VM's input on EPUB. The setup sheet's
sentence option becomes meaningful only when a per-format
sentence-aware enumerator lands (future WI). Loud override with
explicit `_ = granularity` discard.

**Status**: closed.

### [3] (High): Toggling bilingual on with chapter already loaded doesn't enumerate.

**Root cause**: enumerate JS was only evaluated from `onPageDidFinishLoad`.
A user enabling bilingual mid-chapter (the More-menu row taps) saw the
VM flip to `isEnabled=true` but no enumerate run until the next
navigation — chapter stayed source-only.

**Fix**: `handleMoreBilingualToggle()` pushes
`bilingualOrchestrator.enumerateJS()` through `pendingHighlightJS` on
enable. Round 2's `R2-2` then refined this further: the push happens
only when the setup sheet is NOT raised, so first-enable defers
enumerate until confirm.

**Status**: closed.

### [4] (High): `providerProfileID` read separately from config → race.

**Root cause**: `ChapterTranslationPrefetcher` called
`AIService.resolveActiveProviderConfig()`, then later
`ProviderProfileStore.shared.loadSnapshot()` for the ID. A user changing
the active provider between those awaits could cache the result under
provider B's ID while config came from provider A — straddled cache
identity.

**Fix**: prefetcher now snapshots the active profile FIRST
(`ProviderProfileStore.shared.activeProfileSnapshot()`), then calls
`AIService.resolveProviderConfig(profileID:modelOverride:)` (the
by-named-id seam) for the config. Same `profile.id` used for both
config and `lookupKey`. Throws `.providerFailed("no active provider profile")`
if no active profile.

**Status**: closed.

### [5] (Medium): `h1`-`h6` in `BLOCK_TAGS` translates headings.

**Root cause**: original `BLOCK_TAGS` set in `EPUBBilingualJS.bilingualEnumerateJS`
included `h1`...`h6`. The plan and design bundle exclude headings (the
interlinear-renderer mock shows source paragraphs only; chapter / section
titles are short, stylized, and shouldn't be re-rendered with translations
underneath).

**Fix**: removed `h1`...`h6` from `BLOCK_TAGS`. Comment explicitly cites
the audit + design rationale.

**Status**: closed.

## Round 2 (thread 019e429b-7e7b-7043-877e-60b9820cca6d)

Two findings — 1 High + 1 Medium.

### [R2-1] (High): `stripHTMLPreservingBlocks` over-emits boundaries for tags the enumerator doesn't walk.

**Root cause**: round-1's fix emitted `\n\n` for `div`, `h1`-`h6`,
`section`, `article`, `header`, etc. — but `EPUBBilingualJS` only walks
`p`, `li`, `blockquote`, `pre`, `dd`, `dt`. A chapter shape like
`<h1>Title</h1><p>Body</p>` produced 2 source segments (`Title`, `Body`)
but 1 enumerated block (`<p>`) — the title's translation would inject
under the body.

**Fix**: round-2 dropped the extra tags from the closing-tag regex AND
removed heading content globally so `<h1>Title</h1><p>Body</p>` → 1
segment `Body` matching 1 enumerator block. Then round 3 (see R3-2)
revisited the heading-removal.

**Tests**: `headingsAreDropped` (initial round 2), then replaced by
`headingsGlueToNextParagraph` + `nestedHeadingsKept` (round 3).
`structuralWrappersTransparent` pins that `<section>`, `<article>`,
`<div>` wrappers don't alter segment count.

**Status**: closed (refined in round 3).

### [R2-2] (Medium): First-enable triggered enumerate + prefetch before setup-sheet confirmed.

**Root cause**: `handleMoreBilingualToggle` enabled the VM + pushed
enumerate immediately, then raised the setup sheet. The prefetch fired
with the persisted defaults (English, paragraph) before the user could
confirm their preferred language.

**Fix**: `handleMoreBilingualToggle` now branches: if the VM raised
`needsSetupSheet`, it raises the sheet ONLY (no enumerate push).
`confirmBilingualSetup` is the path that commits settings AND pushes
enumerate. `cancelBilingualSetup` turns the VM off — no enumerate runs.

**Status**: closed.

## Round 3 (thread 019e42a1-be92-7453-bcbb-ef60764a843d)

Two findings — 1 High + 1 Medium.

### [R3-1] (High): `didFinish`-driven enumerate still ran while the setup sheet was open.

**Root cause**: round-2 fixed the More-menu path but the `onPageDidFinishLoad`
callback only gated on `bilingualViewModel?.isEnabled`. If a chapter
re-load (navigation, re-render) happened while the first-enable sheet
was open, enumerate would run and the prefetch would fire with
un-confirmed settings.

**Fix**: `onPageDidFinishLoad` gates on
`bilingualViewModel?.isEnabled == true && !showBilingualSetupSheet`.
Confirm path's explicit enumerate push covers the post-confirm case.

**Status**: closed.

### [R3-2] (Medium): Global heading-strip drops content from headings nested inside enumerated blocks.

**Root cause**: round-2's heading-removal regex was greedy and global.
A shape like `<blockquote><h2>Title</h2><p>Body</p></blockquote>` enumerates
as one block whose `textContent` includes "Title Body", but the
stripper dropped the heading so the translation source saw only "Body".
Silent text loss.

**Resolution** (accepted with documented trade-off, NOT a "Low downgrade —
fix is principled):
- Reverted the global heading-removal regex.
- Instead, top-level headings stay in source text and glue onto the
  next paragraph's segment ("Title Body" as one segment matching one
  `<p>` enumerator block whose text is "Body"). The translated segment
  is slightly longer than what the renderer paints under, but **no
  content is lost**.
- Nested headings inside an enumerated block also stay in the source,
  so the segment text matches the enumerator's `textContent` for that
  block. Pinned by `nestedHeadingsKept`.

Trade-off accepted: top-level headings cause a slight over-translation
(the translation includes the heading text in addition to the paragraph)
— not perfect alignment, but no content loss and no incorrect text
mapping. A follow-up WI can switch translation input to the enumerator's
block texts directly (rather than HTML-stripped source), eliminating
the trade-off entirely.

**Status**: closed with documented limitation. No follow-up issue filed
yet — this is captured in the PR body's Known Limitations section.

## Manual fallback evidence

Codex MCP was used for all three rounds; no manual fallback required.

## Test gate

All 6587 unit tests pass under `xcodebuild test`:

```
xcodebuild test -project vreader.xcodeproj -scheme vreader \
    -destination 'platform=iOS Simulator,id=61149F0E-DC18-4BE2-BB37-52659F1F4F62' \
    -parallel-testing-enabled NO \
    -only-testing:vreaderTests
```

Result: `Test run with 6587 tests in 661 suites passed after 33.640 seconds.`

## Verdict

`ship-as-is`. All Critical/High/Medium findings closed. The R3-2
known limitation (top-level heading over-translation) is documented in
the PR body and slated for a follow-up.
