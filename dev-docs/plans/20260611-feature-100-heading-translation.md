# Feature #100 — Bilingual mode translates chapter headings

- **Status**: Gate 1 v3.1 (2026-06-11) — Gate 2 PASSED (3 rounds)
- **Revision history**:
  - v1: initial draft.
  - v3.1 (Gate-2 round 3): both round-2 residuals confirmed resolved; ONE
    editorial Medium remained — the Foliate surface-area row named
    `FoliateBilingualPipeline.swift` while the out-of-scope section
    excludes it. Fixed per the auditor's prescribed remediation: the row
    now names only the real JS-builder/message seams
    (`FoliateBilingualJS` + the orchestrator call sites + the
    `foliate-host.js` message path). No other blockers found. Codex
    sessions: r1 `019eb4d4-f7ce`, r2 `019eb4d9-8f87`, r3
    `019eb4dc-6dce-78c0-be19-9c52716f7783`.
  - v3 (Gate-2 round 2, NEEDS-REVISION → 2 residuals): (1) Readium's CJK
    threading made EXPLICIT — `ReadiumBilingualEvalAdapter.injectJS`/
    `loadingJS` delegate to the SHARED `EPUBBilingualJS.bilingualInjectJS`/
    `bilingualInjectLoadingJS` builders, and the live call chain is
    `ReadiumEPUBHost+BilingualDriver` → `ReadiumBilingualCommander.inject`
    → adapter — so the `targetIsCJK` flag rides the commander + adapter
    signatures down to the shared builders (one flag, both engines).
    (2) `FoliateBilingualPipelineTests` removed from the test catalogue —
    Foliate modifier assertions live in the host-JS string pins +
    `FoliateBilingualJS` tests only.
  - v2 (Gate-2 round 1, NEEDS-REVISION → 1 High, 2 Medium, 1 Low):
    (H) Readium does NOT share `EPUBBilingualJS`'s enumerate — it has its
    own `ReadiumBilingualEvalAdapter.enumerateJS()` with its own
    `BLOCK_TAGS` literal; WI-1 now updates BOTH + Readium-specific tests.
    (M1) `targetIsCJK` threading moved to the ORCHESTRATORS
    (`EPUBBilingualOrchestrator` / `FoliateBilingualOrchestrator` — the
    actual JS-builder call sites), derived at the host boundary via
    `BilingualLanguage.findOrDefault(key: vm.targetLanguage).script ==
    .cjk`; the parse/pairing pipelines are untouched. (M2) the legacy
    continuous-scroll stitch is a first-class target: `EPUBBilingualJS`
    carries TWO `BLOCK_TAGS` literals (global `bilingualEnumerateJS()` +
    section-scoped `bilingualEnumerateJS(spineIndex:)`) and its own
    per-section inject/reinject path — both literals get h1–h6 + pins,
    plus a continuous-mode section-scoped test. (L) modifier-class
    assertions live in JS-source/host/adapter tests, not pipeline tests
    (the pipelines only parse/pair).
- **Design**: landed (PR #1652) — `vreader-bilingual-suite.jsx` `BSHeadingPair`
  + `design-notes/bilingual-suite-issues.md` §#1650: **centered echo row
  (H-A)** — a translated heading keeps HEADING vocabulary, not paragraph
  vocabulary: centered, NO left border, target-language serif ≈15.5px with
  wide tracking for CJK targets, `sub` color, 6px under the source strip;
  loading = ONE centered shimmer bar (72×9) in the row's slot; the inline
  dot-join (H-B) is an alt for known-short headings, NOT the base; the
  chapter-start drop cap (#68) sits below the pair, untouched.
- **Tracker row**: `docs/features.md` #100 (Medium). GH needs-design #1650
  (fulfilled by the landed bundle); feature GH issue to be created at the
  `PLANNED` flip.

## Problem

Bilingual mode covers body blocks only (`BLOCK_TAGS = { p, li, blockquote,
pre, dd, dt }` in `EPUBBilingualJS` and its Foliate mirror), so chapter
titles (`h1`–`h6`) — the most prominent line on the page — get no
translation row. User report: "the title isnt translated".

## Surface area

| File | Change |
|---|---|
| `vreader/Views/Reader/Bilingual/EPUBBilingualJS.swift` | (a) BOTH `BLOCK_TAGS` literals (the global `bilingualEnumerateJS()` AND the continuous-scroll section-scoped `bilingualEnumerateJS(spineIndex:)`) gain `h1…h6` — one heading, one row, the 1:1 contract intact across paged + stitch modes. (b) `makeInjectJS(translationsByBid:targetIsCJK:)` gains the CJK flag; `makeBlock` checks the SOURCE block's `tagName` against `/^H[1-6]$/i` and adds `vreader-bilingual--heading` (+ `vreader-bilingual--cjk` when `targetIsCJK`) to the decoration div — on BOTH the fresh-append and the idempotent next-sibling-replace paths, and on the continuous reinject path. The loading-shimmer inject does the same so a heading's pending row centers its single bar. |
| `vreader/Views/Reader/Bilingual/ReadiumBilingualEvalAdapter.swift` + `ReadiumBilingualCommander.swift` | (Gate-2 High + round-2) Readium's OWN `enumerateJS()` `BLOCK_TAGS` literal gains `h1…h6`. Its `injectJS`/`loadingJS` DELEGATE to the shared `EPUBBilingualJS` builders, so the modifier classes come for free once the shared builders emit them — the `targetIsCJK` flag threads explicitly through `ReadiumBilingualCommander.inject(...)` → adapter → shared builder (the live chain from `ReadiumEPUBHost+BilingualDriver:228`). Readium-specific tests pin the enumerate literal + the flag pass-through. |
| `vreader/Views/Reader/Bilingual/EPUBBilingualOrchestrator.swift` + `FoliateBilingualOrchestrator.swift` | (Gate-2 M1) the actual JS-builder call sites thread `targetIsCJK`, derived at the host boundary: `BilingualLanguage.findOrDefault(key: viewModel.targetLanguage).script == .cjk`. |
| `vreader/Models/ReaderThemeV2+EPUBCSS.swift` | `bilingualCSSRule` gains the heading override appended after the base rule: `.vreader-bilingual--heading[data-vreader-decoration] { text-align: center !important; border-left: none !important; padding: 0 !important; margin: 6px 0 0 0 !important; font-size: 0.95rem !important; font-family: Georgia, 'Source Serif 4', serif !important; }` + `.vreader-bilingual--heading.vreader-bilingual--cjk { letter-spacing: 0.32em !important; }` (the design's 5px tracking at 15.5px) + a centered single-bar loading variant (`.vreader-bilingual--heading.vreader-bilingual-loading .vreader-shimmer-bar { width: 72px; margin: 0 auto; }`). `rem` keys the row to the user's font scale; `text-align: center` outranks the #336 justify facet by specificity + `!important` ordering (later rule wins at equal specificity). |
| `vreader/Services/Foliate/JS/foliate-host.js` | Mirror: `BILINGUAL_BLOCK_TAGS` gains `h1…h6`; the host-side inject adds the same modifier classes (tag check at runtime; CJK flag threaded through the existing bilingual message payload). |
| `vreader/Views/Reader/Bilingual/FoliateBilingualJS.swift` (+ the `FoliateBilingualOrchestrator` builder call sites and the `foliate-host.js` message seam) | Thread the CJK flag through the REAL JS-builder/message seams only (round-3: `FoliateBilingualPipeline` stays out of scope — parse/pair glue). The Foliate `setStyles` CSS gains the heading rules automatically via the shared `bilingualBlockCSSRule`. |

**Files OUT of scope**: `EPUBBilingualPipeline` / `FoliateBilingualPipeline` (parse/pairing only — no JS building, no class knowledge; Gate-2 L). TXT/MD pipelines — `BilingualParagraphRanges.scan`
already treats a heading line as a paragraph, so TXT/MD headings translate
TODAY (with paragraph-row vocabulary; on MD the composer inherits the
heading's own typography onto the row, which is the closest native analog
of the echo treatment). `ChapterSegmenter`, the cache schema, the count
contract (#343 divergence fallback absorbs old cached rows whose counts
predate the new tag list — those re-translate once, the documented cost).

## Prior art / precedent / rejected alternatives

- **#268/#343 DOM-enumerate contract**: both EPUB pipelines translate the
  enumerate's OWN block texts (`translatePreSegmented`, 1:1 by
  construction) — adding tags to the enumerate is automatically
  count-consistent; stale cached rows mismatch → re-translate (#343).
- **Modifier-class styling** mirrors the existing loading-state pattern
  (`vreader-bilingual-loading`) — the inject marks state, the theme CSS
  styles it.
- **Rejected**: paragraph-row vocabulary under headings (design H-C — two
  alignment systems clash); inline dot-join as base (H-B — breaks on
  wrapped headings); `figcaption`/`th`/`td`/`caption` (design commits
  h1–h6 only; table cells would need row-level pairing the design doesn't
  depict).

## Work items

- **WI-1 (behavioral, ~300-line PR)** — EPUB legacy (BOTH enumerate
  literals + continuous reinject) + Readium (`ReadiumBilingualEvalAdapter`)
  + orchestrator CJK threading + theme CSS + tests. RED: JS-source pins
  (h1–h6 in BOTH `EPUBBilingualJS` literals AND the Readium adapter;
  heading/cjk modifier emission on fresh-append, replace, reinject, and
  loading paths), CSS-rule pins (centered, no border, rem size, tracking
  only under `--cjk`, centered loading bar), a continuous-mode
  section-scoped enumerate pin.
- **WI-2 (behavioral, ~150-line PR)** — Foliate mirror: host tag list +
  modifier emission + CJK threading + tests (the shared CSS rule lands in
  WI-1).

## Edge cases

- Empty headings (decorative anchors): the enumerate already skips blocks
  with no text — no row.
- Headings inside `blockquote`/nested markup: the leaf-block rule (#266)
  governs as for any block; a heading containing a block child is non-leaf.
- Numbered headings ("Chapter 12"): the translator owns numeral handling —
  the row never mixes scripts (design note).
- Long headings wrap centered (CSS default for centered block).
- Idempotent re-inject: the existing next-sibling replace path is
  class-agnostic on match but must KEEP the heading modifier when
  replacing a shimmer with the landed text (set classes on both paths).
- Old cache rows without headings: count mismatch → #343 divergence
  fallback → re-translate once.
- The #95/#336 justify facet must not stretch the centered row
  (text-align: center declared after justify with !important).
- Latin targets get NO extra tracking (the `--cjk` modifier gates it).

## Test catalogue

- `vreaderTests/Views/Reader/Bilingual/EPUBBilingualJSTests.swift`
  (extend): BLOCK_TAGS pins h1–h6; inject JS emits the heading-modifier
  branch + the CJK class only when flagged; loading JS same.
- `vreaderTests/Models/ReaderThemeV2EPUBCSSTests.swift` (or the existing
  CSS test home): heading rule present, centered, border-less, tracking
  under `--cjk` only, loading variant centered.
- Foliate: host-JS string pins (`foliate-host.js` tag list + modifier
  emission) + `FoliateBilingualJS` tests — NO pipeline tests (Gate-2 L).

## Risks + mitigations

- **Count-contract churn**: every previously-translated chapter with
  headings re-translates once (counts grew). Mitigation: documented; the
  #343 fallback handles it without wrong pairings; cost equals one
  re-translate per affected chapter.
- **CSS specificity vs publisher styles**: `!important` on every property
  (the existing base-rule convention) + the dedicated class.
- **rem vs publisher root sizing**: some EPUBs set `html { font-size }`;
  rem follows it — acceptable (the row tracks the book's own scale, same
  as the user-font-size behavior of body text).

## Backward compat

No schema/cache-format changes. Old cache rows re-translate once via the
existing staleness machinery. Books without headings see no delta.
