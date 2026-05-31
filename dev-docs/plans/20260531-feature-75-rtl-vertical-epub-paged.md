# Feature #75 — RTL / vertical-writing EPUB paged rendering

**Reclassified from Bug #292 / GH #1300** (2026-05-31, per user direction). The
"bug" was that `metadata.readingDirection` is parsed but consumed by *zero*
renderers — i.e. RTL / vertical-writing paged rendering is **never-implemented
code**, not broken code. Per AGENTS.md ("never implemented → feature") this is a
feature.

## Problem

EPUB paged mode assumes left-to-right horizontal reading everywhere. For an RTL
publication (Arabic/Hebrew; `page-progression-direction="rtl"`) or a
vertical-writing publication (`writing-mode: vertical-rl`, common for Chinese/
Japanese), the column layout + page-turn math are wrong: "next" moves content
the wrong way, the first page is on the wrong side, and the within-chapter
progress fraction is inverted. `EPUBParser` already parses `readingDirection`
(`EPUBParser.swift:357`, default `.ltr`) into `EPUBMetadata.readingDirection`,
but no renderer reads it.

**Caveat to confirm before WI-1**: the original Bug #292 repro did not confirm
the user's book is actually RTL/vertical vs. an LTR expectation mismatch. WI-0
is an explicit confirmation step (inspect the repro book's
`page-progression-direction` / `writing-mode`).

## Scope

In scope: RTL (horizontal right-to-left) paged EPUB, then vertical-writing
(`vertical-rl`) paged EPUB. Consuming a **per-spine-document page axis** through
the paged column CSS, page→scroll math, page-count, current-page, swipe/tap-zone
direction, and within-chapter progress.

Out of scope: scroll-mode RTL/vertical (separate surface); the Foliate/AZW3
path (its own engine); fixed-layout EPUB; `vertical-lr` (rare) — deferred.

### Keystone abstraction — `PageAxis` is PER-DOCUMENT, not per-book (Gate-2 High)

Vertical writing can vary **per spine item** (the `mini-cjk` fixture is the
proof: chapter 1 is horizontal, chapter 2 is `vertical-rl` —
`DebugFixtureCatalog.swift:83`). A book-level `isRTL/isVertical` would render one
chapter wrong. So the unit of direction is the **loaded spine document**, modeled
as:

```
enum PageAxis { case horizontalLTR, case horizontalRTL, case verticalRL }
```

Resolved fresh for each `contentURL` load (and recomputed on chapter change, TOC
jump, resume, wrap nav) by a **pre-pagination probe**:

1. After theme injection + content load, **BEFORE** `setupPagination` injects
   pagination CSS, eval `getComputedStyle(document.body)` →
   `{ writingMode, direction }` (and `document.documentElement.dir` / `lang` for
   `.auto` resolution).
2. Map to `PageAxis`: `writing-mode: vertical-rl` → `.verticalRL`; else
   `direction: rtl` (or `readingDirection == .rtl`, or `.auto` resolving to RTL
   via computed `dir`) → `.horizontalRTL`; else `.horizontalLTR`.
3. Store the resolved `PageAxis` on the coordinator for that spine item; inject
   pagination CSS + run all page math against it.

This fixes BOTH Gate-2 Highs: probe-before-injection (so it reads the BOOK's CSS,
not the app's pagination CSS) and per-document granularity. `ReadingDirection`
(book-level) is only a *hint* used when computed direction is ambiguous; the
probe is authoritative (also resolves `.auto`, Gate-2 Medium).

## Surface area (file-by-file)

LTR-assumption surface confirmed by grep (≈10 files). The math is concentrated
in `EPUBPaginationHelper` + `EPUBPagedProgress`; the rest consume them.

- **`EPUBPaginationHelper.swift`** — thread a `PageAxis` parameter:
  - `paginationCSS(viewportWidth:viewportHeight:axis:)`: `.horizontalRTL` adds
    `direction: rtl`; `.verticalRL` adds `writing-mode: vertical-rl`; LTR
    unchanged.
  - `navigateToPageJS(page:viewportWidth:axis:)`: `.horizontalRTL` uses WebKit's
    negative `scrollLeft` (`offset = -(page * vw)`); `.verticalRL` uses
    `scrollTop`; LTR uses `scrollLeft = page * vw` (byte-unchanged).
  - `totalPagesJS` / `currentPageJS`: per-axis source (`scrollWidth`/`scrollLeft`
    horizontal, `scrollHeight`/`scrollTop` vertical) + RTL sign.
- **`EPUBPagedProgress.swift`** — `intraChapterFraction` / `pageForFraction`
  already pure on a zero-based page index; page-INDEX stays 0=first-page-read,
  so these may be unchanged IF page indexing is kept reading-order (page 0 =
  first page the reader sees). Verify with a test.
- **`EPUBWebViewBridge.swift` / `EPUBWebViewBridgeCoordinator.swift`** — store
  the resolved per-document `PageAxis` (from the pre-pagination probe) on the
  coordinator for the loaded spine item and pass it into the pagination calls.
- **`EPUBReaderContainerView.swift`** — owns nothing direction-specific; the
  `PageAxis` is resolved at load time by the probe, not derived from book
  metadata up front.
- **`EPUBSwipeGestureClassifier.swift` + the injected swipe JS
  (`EPUBPaginationHelper.swift:176`)** — BOTH are horizontal-`dx`-only today
  (Gate-2 Medium). For `.horizontalRTL` the existing horizontal classifier maps
  to inverted next/prev; for `.verticalRL` a NEW vertical-`dy` swipe path is
  needed in the injected JS + classifier (axis selection, dominance, threshold,
  rapid-repeat, no side-tap double-turn). Tested per axis.
- **Tap-zone routing — DO NOT change `ReaderTapZoneRouter`'s global default**
  (Gate-2 Medium): it is shared by TXT/MD/PDF/Foliate/Readium, is **x/width-only**
  (left-center-right), and defaults left→previous/right→next
  (`ReaderTapZoneRouter.swift:68`). For `.horizontalRTL`, the EPUB-paged call site
  passes an explicit swapped `TapZoneConfig`; the global default is untouched.
  For `.verticalRL` the x/width router cannot express top/bottom zones, so
  (Gate-2 round-2 Medium) WI-5 adds an **EPUB-paged-only axis-aware tap path**:
  the content-tap JS sends `{x,y,w,h}` (today it sends `{x,w}` —
  `foliate-host.js`/`EPUBPaginationHelper` mapping), and a thin EPUB-paged tap
  router routes vertical taps by `y/h` to prev/next while delegating horizontal
  axes to the existing shared `ReaderTapZoneRouter` unchanged.
- **`BasePageNavigator.swift`** — page +1/-1 stays reading-order; the physical
  direction is handled by the per-document `PageAxis` CSS + scroll math, so this
  stays unchanged (verify with the LTR suite staying green).
- **`EPUBParser.swift` / `EPUBTypes.swift`** — `readingDirection` already parsed
  (hint only). Add a new `PageAxis` enum; the authoritative resolution is the
  load-time `getComputedStyle` probe (above), NOT a parse-time field, because
  vertical/`auto` are content-driven and per-document.

### Files OUT of scope

`TXT*`, `MD*`, `PDF*`, `Foliate*` readers; scroll-mode EPUB; fixed-layout.

## Prior art / precedent

- The `Bug #293` fix just added `EPUBPagedProgress.pageForFraction` (the inverse
  seam) — the page-index abstraction is already clean and reading-order-based.
- `HighlightHitTolerance` / the `EPUBPaginationHelper` static-pure pattern is the
  precedent for new pure seams (testable JS-string generators).
- WebKit RTL `scrollLeft`: in WebKit, an RTL block's `scrollLeft` is `0` at the
  start (right edge) and goes NEGATIVE toward later content — the dominant gotcha
  to pin with a focused JS-contract test + device check.
- Foliate already handles vertical writing in its overlayer (`writingMode`
  branch in `overlayer.js`) — reference for the vertical rect geometry.

## Rejected alternatives

- **Swap next/prev only** (no CSS/scroll change): makes turning *feel* right but
  leaves content order LTR (page 1 = leftmost) — wrong for a true RTL book.
  Rejected.
- **Rely on the browser's native RTL**: WKWebView column pagination does not
  auto-handle `page-progression-direction`; the app owns the column math.

## Work-item sequencing (revised after Gate-2)

- **WI-0** (confirm): inspect the repro book's computed `direction`/`writing-mode`.
  If LTR-horizontal, the user-facing issue is an expectation mismatch — re-scope.
  (investigation.)
- **WI-1** (foundational): `PageAxis` enum + the pure resolution seam
  `PageAxisResolver.resolve(writingMode:direction:dir:lang:readingDirectionHint:)`
  → `PageAxis`. Pure tests (LTR, RTL, vertical-rl, `.auto` via computed dir,
  ambiguous → hint). No rendering yet.
- **WI-2** (foundational): `EPUBPaginationHelper` methods take a `PageAxis`:
  `paginationCSS` emits `direction: rtl` / `writing-mode: vertical-rl`;
  `navigateToPageJS` uses negative `scrollLeft` (RTL) / `scrollTop` (vertical);
  `totalPagesJS` source = `scrollWidth` (horizontal) / `scrollHeight` (vertical);
  `currentPageJS` reads the matching axis. LTR branch byte-unchanged. Pure-seam
  tests per axis.
- **WI-3** (behavioral): the **pre-pagination probe** — eval
  `getComputedStyle(document.body)` BEFORE `setupPagination`, resolve `PageAxis`
  via WI-1, store per spine item on the coordinator, recompute on chapter
  change/TOC/resume/wrap. Thread it into WI-2's calls. Device-verify
  `.horizontalRTL` with the `mini-rtl` fixture (synthetic — no real RTL book;
  legitimate per real-books rule).
- **WI-4** (behavioral): direction-aware input — RTL inverts the EPUB paged
  `TapZoneConfig` (NOT the shared router default) + the horizontal swipe maps
  inverted; verify `mini-rtl`.
- **WI-5** (behavioral): vertical (`mini-cjk` chapter 2) — the vertical column
  CSS + `scrollTop` page math (WI-2) validated end-to-end in WKWebView, the NEW
  vertical-`dy` swipe JS path + classifier, AND the EPUB-paged axis-aware tap
  path (content-tap JS extended to `{x,y,w,h}`; vertical taps routed by `y/h`,
  horizontal delegated to the unchanged shared router). Per-document axis means
  chapter 1 (horizontal) and chapter 2 (vertical) of the SAME book both render
  correctly.
- **WI-6** (final): full acceptance — RTL + per-chapter-vertical books page the
  correct direction, resume the correct page (compose with #293's
  `pageForFraction` — verify the fraction stays reading-order under each axis),
  progress correct.

## Test catalogue

- `PageAxisResolverTests` — LTR/RTL/vertical-rl mapping, `.auto` via computed
  `dir`/`lang`, ambiguous → `readingDirection` hint, default LTR.
- `EPUBPaginationHelperRTLTests` — `navigateToPageJS` RTL negative `scrollLeft`,
  `paginationCSS` carries `direction: rtl`, `totalPages`/`currentPage` axis+sign.
- `EPUBPaginationHelperVerticalTests` — `writing-mode: vertical-rl` CSS,
  `scrollTop` nav, `scrollHeight` page count. (String tests; the WKWebView
  layout is validated on-device in WI-5 — multicol vertical stride can't be
  string-tested.)
- `EPUBPagedProgress` round-trip unchanged (page-index reading-order invariant
  holds under every axis — explicit test per axis).
- Swipe: `EPUBSwipeGestureClassifierTests` extended — horizontal RTL inversion +
  the NEW vertical-`dy` path (axis selection, dominance, threshold,
  rapid-repeat, no side-tap double-turn).
- Device: `mini-rtl` (RTL, WI-3) + `mini-cjk` **chapter 2** (vertical-rl, WI-5 —
  there is no fixture literally named `vertical-rl`; vertical content lives in
  `mini-cjk` ch2 per `DebugFixtureCatalog.swift:83`) via DebugBridge +
  `scripts/sim-tap.sh`.

## Risks + mitigations

- **WebKit RTL scrollLeft convention** (negative) is the top risk — pin with a
  JS-contract test + a device check on `mini-rtl` early (WI-2).
- **Vertical detection is content-driven** (not always OPF-declared) — hence the
  `getComputedStyle` probe (WI-3).
- **Regression to LTR** (the 99% case) — every WI keeps LTR the default branch;
  full LTR paged suite must stay green at each WI.

## Backward compat

LTR books are unaffected (the new direction params default to LTR/horizontal).
No persistence/schema change — `readingDirection` is already stored in metadata,
just newly consumed.

## Audit fixes applied (Gate-2 round 1 → revision)

Codex `codex exec` plan audit, round 1: verdict NEEDS REVISION, 2 High + 4
Medium + 1 Low (all model assumptions verified to exist; WebKit negative-RTL
`scrollLeft` confirmed via MDN). Revisions:

- **High — writing-mode probe sequencing**: WI-3 now runs the
  `getComputedStyle` probe BEFORE `setupPagination` injects pagination CSS, so it
  reads the book's CSS, not the app's.
- **High — per-spine-item vertical**: replaced book-level `isRTL/isVertical` with
  a per-document `PageAxis` resolved per `contentURL` load (the `mini-cjk`
  fixture mixes horizontal ch1 + vertical-rl ch2).
- **Medium — vertical math underspecified**: WI-2 now names the axis sources
  (`scrollHeight`/`scrollTop`) and WI-5 validates the multicol vertical stride
  on-device (not string-only).
- **Medium — `.auto`**: resolved in `PageAxisResolver` from computed
  `dir`/`lang` before LTR fallback.
- **Medium — shared `ReaderTapZoneRouter`**: scoped to an EPUB-paged
  `TapZoneConfig`; the global default is unchanged (no TXT/MD/PDF/Foliate/Readium
  regression).
- **Medium — vertical swipe JS**: WI-5 adds a vertical-`dy` swipe path (the
  existing JS + classifier are horizontal-`dx`-only).
- **Low — fixture name**: vertical verification uses `mini-cjk` chapter 2 (no
  `vertical-rl`-named fixture exists).

Round-2 re-audit: all 7 round-1 items confirmed resolved. New findings — 1 Medium
(vertical tap routing: `TapZoneConfig`/`ReaderTapZoneRouter` are x/width-only, so
vertical needs an EPUB-paged-only `{x,y,w,h}` tap path routed by `y/h`, shared
router untouched) + 1 Low (stale `isRTL/isVertical` wording in the bridge/
container surface bullets). Both fixed: tap-zone-routing bullet + WI-5 now
specify the axis-aware `{x,y,w,h}` path; bridge/container bullets now say
"resolved per-document `PageAxis` from the pre-pagination probe."

## Status

Gate 1 + Gate 2 (round-2 revisions applied). Pending Gate-2 round-3 confirmation
before Gate 3 (TDD). Implementation (WI-1…6) is the next focused phase.
