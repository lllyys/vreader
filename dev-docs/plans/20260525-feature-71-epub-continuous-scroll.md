# Feature #71 — EPUB scroll-mode continuous cross-chapter scroll

> Plan doc for the binding 6-gate feature workflow (rule 47). Gate 1 artifact.
> Design source: `dev-docs/designs/vreader-fidelity-v1/project/design-notes/reader-navigation.md` §2.3 + §2.4 + `vreader-scroll-mode.jsx`.
> Cross-ref: Bug #165 / GH #489 (FIXED, v3.39.6) shipped §2.2 (paged-mode side-tap wrap) and explicitly deferred §2.3 (this feature). Bug #180 (TXT) + Bug #235 (AZW3/Foliate) already satisfy continuous scroll for their formats.

---

## Revision history

- **v1 (2026-05-25)** — initial draft. Author: feature-workflow orchestrator (Claude). Sent to Gate 2.
- **v2 (2026-05-25)** — Gate 2 Codex audit round 1 (thread `019e5f97`) returned 2 Critical / 4 High / 2 Medium / 1 Low. Core reframe accepted: **this is an early DOM-contract change, not late bridge wiring** — anchor/selection/lifecycle work moves into the early WIs, not WI-5. All findings addressed; see "Audit fixes applied (Gate 2)" at the end. WI count grew 6 → 8 with a tighter foundational front.
- **v3 (2026-05-25)** — Gate 2 Codex round 2 (same thread) confirmed H3/H4/H5(struct)/H6/M1/M2/L1 resolved but found 2 residual Highs + 1 Medium: C2-residual (linked external stylesheets + nested CSS `url(...)` not covered), C1-residual (cross-section selection policy undefined), H5-contradiction (stale "out of scope" claim). All three fixed in v3 — rewriter gains a `linkedStylesheetLoader` closure + `url(...)` rewrite, explicit cross-section clamp-to-start-section-or-reject policy, retracted the bilingual out-of-scope claim. Awaiting round 3.
- **v4.2 (2026-05-27)** — Per user direction (foreground `/feature-workflow 71`), staged the Large WI-6b into three gated sub-PRs (6b-i live rendering core, 6b-ii section-scoped annotations, 6b-iii restore + mode-switch). This is **execution sequencing of the already-Gate-2-re-audited WI-6b requirements** (the 4 re-audit findings are distributed across the sub-slices, not changed): finding 1 (position callback) + 3 (bootstrap load) → 6b-i; M1 (find-in-section) + the highlight-restore hook → 6b-ii; finding 2 (fresh handle per generation) + 4 (inner-scroll-root safe-area) → 6b-iii. Re-audit (Gate-2-lite) confirmed the staging is coherent — see revision note.
- **v4.3 (2026-05-27)** — WI-6b-i Gate-4 audit (Codex thread `019e6726`, 3 rounds) surfaced a Critical the staging missed: `.scroll` is the **default user-selectable EPUB layout**, and continuous rendering replaces the single-chapter load path, so all cross-chapter navigation (TOC/bookmark/search → `.readerNavigateToLocator` → `contentURL`) would no-op until 6b-iii lands — i.e. shipping 6b-i alone regresses the default reading mode. **Resolution (user decision, foreground): ship continuous DARK behind `FeatureFlags.epubContinuousScroll` (default off, persisted-overridable — mirrors the `bilingualReading`/`aiAssistant` dark-ship precedent).** With the flag off the default `.scroll` keeps its existing single-chapter behaviour (zero regression); continuous + its still-incomplete navigation is reachable only with the flag overridden on, for device verification and the later WIs; the final WI flips the default on once 6b-ii/iii complete the navigation/restore/mode-switch story. Also folded in: a one-way mode-switch hard-block (leaving `.scroll` retires the config this open — full live teardown stays 6b-iii) and a documented linked-stylesheet chapter-relative-resolution limitation (WI-6a provider seam passes no chapter context → deferred to 6b-ii). Audit log: `.claude/codex-audits/feat-feature-71-wi-6b-i-live-rendering-audit.md`.
- **v4 (2026-05-27)** — Mid-implementation split of the Large WI-6 (after WI-1..5 merged). WI-6 (container integration) was marked Large and carried an **unresolved architectural gap**: the WI-4 coordinator's `evaluate` is an init-time `let`, but the container must create the coordinator before the bridge's `WKWebView` exists, so there was no specified path for `evaluate` to reach the webview. Split into **WI-6a** (foundational: `restoreHighlightsInSectionJS` + `EPUBContinuousChapterProvider` + `EPUBWebViewEvaluatorHandle` — all unit-testable, no live-render change) and **WI-6b** (the behavioral live wiring). Added the "WI-6 evaluate-binding" design subsection resolving the late-binding gap via the weak-webview handle. Re-audited (Gate-2 re-audit of the split) — see revision note below.

---

## Problem

In EPUB **scroll layout** (the default `EPUBLayoutPreference.scroll`), scrolling to the end of a chapter stops at the chapter boundary. The reader does not flow into the next chapter — the user must tap a chapter-navigation affordance (TOC → next) to continue. This breaks the continuous-reading convention that TXT (Bug #180) and AZW3/MOBI (Bug #235) already satisfy. EPUB is the remaining reflowable format without it.

Root cause: `EPUBWebViewBridge` loads **one spine item (chapter) per `loadFileURL`** into a single `WKWebView`. "Scroll mode" today only means `webView.scrollView.isScrollEnabled = true` *within that one chapter's document*. There is no DOM for the adjacent chapters, so the scroll view bottoms out at the current chapter's end.

## Goal (design §2.3)

When the user picks Scroll in the Display sheet:

- Chapters render one after another in a single scrollable column.
- A chapter boundary is a small horizontal divider flanking an uppercase, letter-spaced chapter label (no full-bleed transition page).
- Lazy load: render current chapter + ±1 chapter eagerly; a 4-line shimmer skeleton (§2.4) appears at the bottom when the user scrolls within ~800px of an unrendered boundary.
- Scroll-position is saved on every settle; resuming a scroll-mode book scrolls to the exact pixel within the right chapter.
- Paged mode (§2.2, Bug #165) is unchanged. Highlights / search / TOC continue to work across the continuous view. Memory stays bounded (the ±1 window, not all chapters).

---

## Chosen architecture

### The decision: bespoke multi-chapter WKWebView with a ±1 lazy window (approach **b**), NOT routing EPUB through Foliate (approach **d**)

Three candidate approaches were considered:

- **(a) Concatenate ALL chapters into one document up front.** Rejected: a 600-page novel is dozens of spine items; eager-loading every chapter's DOM into one WKWebView blows memory and first-paint time. The design explicitly mandates lazy ±1 (§2.3 line 60). Rejected.
- **(b) Lazy-load a window of chapters (current ±1) into ONE scrollable WKWebView document, appending/prepending chapter DOM as the user nears a boundary, and evicting far chapters to bound memory.** **CHOSEN.** Matches the design's single `overflowY:auto` column with `<ChapterDivider>` separators (`vreader-scroll-mode.jsx`). Keeps the existing `EPUBWebViewBridge` (CSS injection, highlight API, selection, theme, safe-area, foliate-bridge.js) — we extend its *content model* from "one file" to "a stitched window," not rip it out.
- **(c) One WKWebView per chapter stacked in a SwiftUI `ScrollView`/`UITableView`.** Rejected: N WKWebViews is far heavier than N DOM subtrees in one WebView; cross-WebView selection, CFI, and unified scroll-progress are intractable; the divider/heading lives between two separate web processes.
- **(d) Re-route the EPUB reader through the Foliate engine** (which AZW3/MOBI already use and which natively supports `flow: scrolled` over a multi-section renderer — `view.renderer.getContents()` returns `[{doc, index}]`, `r.setAttribute('flow','scrolled')`). **Rejected for THIS feature** (documented under Prior art): it would deliver continuous scroll "for free" but is a *replacement of the entire EPUB rendering stack* (highlight/search/TOC/bilingual/theme/position all re-anchor onto Foliate CFI), an order of magnitude larger and riskier than #71's framing, and would regress the EPUB-specific WKWebView seams (bug #163 safe-area, #167 overscroll, #182 search, #126/#142 reopen race, feature #70 calibration, #60 themes). Logged as a strategic alternative for a future "unify EPUB+AZW3 on Foliate" feature, explicitly out of scope here.

### How approach (b) works

A new host-side coordinator owns a **spine window** `[lo...hi]` (a contiguous range of spine indices currently materialized in the DOM) anchored on the chapter the user is reading. The bridge loads a single bootstrap HTML document; chapter bodies are injected as `<section data-vreader-spine-index="i" data-vreader-href="...">` blocks separated by divider elements. As the user scrolls:

- Near the bottom of `hi`'s section and `hi < spineCount-1` → fetch chapter `hi+1`'s rewritten body HTML from the parser, append a divider + section, `hi += 1`.
- Near the top of `lo`'s section and `lo > 0` → fetch `lo-1`, prepend (with scroll-offset compensation so the viewport doesn't jump), `lo -= 1`.
- When the window exceeds a max span (e.g. 5 chapters), evict the far end (remove its section + divider) and adjust `lo`/`hi`.

The current "reading chapter" for position/progress is derived from **which section's top-most visible boundary the viewport is past** (a JS scroll observer reports `{visibleSpineIndex, intraSectionFraction}` back to Swift), feeding the existing `(spineIndex + fraction)/spineCount` progress formula unchanged.

**Mutual exclusivity with paged mode**: paged mode keeps the existing one-chapter-per-`loadFileURL` + multi-column CSS path verbatim. The continuous-window model activates *only* when `settingsStore.epubLayout == .scroll`. Switching modes live tears down one model and builds the other (same `isPagedChanged` seam that exists today, extended).

### Why this is a DOM-contract change first (Gate-2 reframe)

The original v1 framing treated this as "add a new message handler at the end." Codex round 1 correctly identified that the load-bearing complexity is **the merged-DOM contract**, which must be settled *before* the bridge wiring, because every existing EPUB subsystem assumes "one chapter == one `loadFileURL` document with its own base URL":

1. **Per-chapter base URL is lost.** Today `loadFileURL(chapterURL, allowingReadAccessTo: root)` gives each chapter a distinct base URL, so relative asset refs (`<img src="../img/a.png">`), local fragment links (`href="#note1"`), SVG `use`/ARIA `id` references, and the one-shot `cssPreprocessJS` all resolve against that chapter. A stitched single document collapses all chapters onto the bootstrap doc's base URL → broken images, duplicate `id` collisions, cross-chapter `#anchor` mis-resolution. **`EPUBChapterBodyRewriter` (renamed from "Sanitizer") must rewrite relative URLs to absolute `file://` (or the foliate URL-scheme), namespace `id`s + intra-doc references by spine index, and scope/rewrite each chapter's CSS.** This is foundational and is its own WI.
2. **Anchors are document-relative.** `EPUBHighlightActions.restoreHighlightsJS` filters `href == currentHref` and paints into `document`; `EPUBWebViewBridgeCoordinator` assigns selection `href = currentHref ?? ""` (verified: coordinator line ~222). In a stitched DOM, a selection or highlight must carry the **section's** href/spine-index, not the global "current" one, and the paint/restore JS must scope to that section subtree. **Selection + highlight anchoring move into the early WIs**, not WI-5. **Cross-section selection policy (round-2 [C1-residual]):** in a stitched DOM a drag selection can span a chapter boundary, which the per-section anchor + per-section eviction model cannot represent. Policy: the selection JS **clamps the range to the section containing its START anchor** (`range.startContainer.closest('[data-vreader-href]')`); the popover then operates on that single section's text. If the clamp empties the selection (start and end in different sections with no text in the start section past the boundary — degenerate), the selection is **rejected** (no popover). This is explicit + unit-tested, not implicit. (Per-section *split* into multiple highlights is rejected as out-of-scope complexity for v1.)
3. **Lifecycle hook.** Today highlight restore + bilingual enumerate both hang off one `onPageDidFinishLoad` per `loadFileURL`. Appended/prepended sections never fire `didFinish`. **A "section materialized" lifecycle callback is part of the bridge-wiring WI**, and highlight-restore / bilingual-enumerate are driven from it.
4. **The always-injected `progressTrackingJS` user script** reports single-document scroll progress on a `Double` channel and *will* fire on the bootstrap doc, racing the new section-aware observer. **Script injection becomes mode-specific**: continuous mode replaces `progressTrackingJS` + the `progressHandler` single-`Double` contract with the section-aware observer.

---

## Surface area (file-by-file)

### New files

| File | Contents |
|---|---|
| `vreader/Views/Reader/EPUBSpineWindow.swift` | **Foundational, pure value type.** `struct EPUBSpineWindow: Equatable` modeling the materialized contiguous range over `0..<spineCount`. Round-1 Low [L1]: uses an **explicit non-empty invariant** (`anchor: Int` + `lo`/`hi` with `lo <= anchor <= hi`, all in `0..<spineCount`); a `spineCount == 0` book has **no window** (the type is constructed only once metadata yields `spineCount >= 1`, container guards the empty case). Pure transitions: `static func initial(anchor:spineCount:) -> EPUBSpineWindow?` (nil for `spineCount==0`), `extendForward()`, `extendBackward()`, `evictFarFromAnchor(maxSpan:)`, `contains(_:)`, `canExtendForward`/`canExtendBackward`. No UIKit, no I/O. WI-1. |
| `vreader/Views/Reader/EPUBChapterBodyRewriter.swift` | **Foundational, pure** (renamed from "Sanitizer" per round-1 Critical [C2]). `EPUBChapterBodyRewriter.rewrite(xhtml:spineIndex:href:resourceBaseAbsolutePrefix:linkedStylesheetLoader:) -> EPUBChapterBody`. Rewrites a chapter's XHTML so it can live in a shared document: (1) extract `<body>` inner HTML; (2) **rewrite relative resource URLs** (`src`/`href` to images/fonts) to absolute against the chapter's own directory; (3) **namespace `id` attributes + intra-doc `#fragment` references** by spine index (`id="x"`→`id="s3-x"`, `href="#x"`→`href="#s3-x"`), plus SVG `<use href="#sym">` / ARIA `aria-labelledby`/`aria-describedby`; (4) **inline + scope CSS** (round-2 [C2-residual]): inline `<style>` blocks AND `<link rel=stylesheet>` (the latter resolved via the injected `linkedStylesheetLoader: (_ relativeHref: String) -> String?` closure — the container supplies one that reads the already-extracted CSS file's bytes from `extractedRoot`; if a stylesheet can't be loaded the rewriter logs + skips it rather than crashing), with selectors prefixed under `[data-vreader-spine-index="3"]` and **nested `url(...)` references inside the CSS rewritten** to absolute against the stylesheet's own directory. Keeping the loader a closure preserves WI-2's purity + testability (stub loader in tests). Returns `EPUBChapterBody { spineIndex, href, bodyHTML, scopedStyleHTML }`. WI-2. |
| `vreader/Views/Reader/EPUBContinuousScrollJS.swift` | **Behavioral** (pure JS-string generators, unit-testable). `bootstrapDocumentHTML(themeCSS:)`, `appendChapterSectionJS(body:dividerTitle:)`, `prependChapterSectionJS(body:dividerTitle:)` (captures `scrollHeight` pre-insert, restores `scrollTop += delta` post-insert in one transaction), `removeChapterSectionJS(spineIndex:)`, `continuousScrollObserverJS` (reports `{visibleSpineIndex, intraFraction, nearTopBoundary, nearBottomBoundary}` throttled — **replaces** `progressTrackingJS` in continuous mode), `scrollToSpineFractionJS(spineIndex:fraction:)`, `findInSectionJS(spineIndex:quote:)`, `restoreHighlightsInSectionJS(...)`. All interpolation through `FoliateJSEscaper.escapeForJSString` (real path: `vreader/Services/Foliate/FoliateJSEscaper.swift`). The divider markup (per `vreader-scroll-mode.jsx::ChapterDivider`) lives here as DOM-injected HTML, styled from the injected theme tokens — no separate SwiftUI view. WI-3. |
| `vreader/Views/Reader/EPUBContinuousScrollCoordinator.swift` | **Behavioral.** `@MainActor` host-side coordinator: owns the current `EPUBSpineWindow`, an injected `chapterBodyProvider: @MainActor (Int) async throws -> EPUBChapterBody`, and emits section JS through an **async-throwing** evaluator `evaluate: @MainActor (String) async throws -> Void` (round-1 High [H4]: a `(String)->Void` closure can't observe JS failure, and the test plan requires "window state must not advance if the DOM insert failed"). Carries a **generation token** (`UUID`) bumped on mode-switch / reopen / book-change so a stale in-flight `chapterBodyProvider` task that resolves after a switch is discarded (round-1 High [H4]). Decision logic (`EPUBSpineWindow` transition from `EPUBScrollBoundarySignal`) is pure + unit-testable with a recording stub evaluator; window mutation happens only after a successful eval. WI-4 (decision logic) + WI-5 (bridge integration). |

### Modified files

| File | Change | WI |
|---|---|---|
| `vreader/Views/Reader/EPUBWebViewBridge.swift` | Add a `continuousScroll: EPUBContinuousScrollConfig?` input (nil ⇒ legacy one-chapter path, preserving paged + the current scroll-single-chapter behavior for any non-#71 caller, source-compatible). When non-nil: `makeUIView` injects the **continuous** observer user-script (NOT `progressTrackingJS`) + registers `continuousScrollHandler` + `sectionMaterialized` message handlers and loads the bootstrap doc; `updateUIView` routes section append/prepend/evict/seek through the coordinator's async evaluator instead of `loadFileURL`. Existing seams (safe-area #163, overscroll #167, theme, foliate-bridge, highlight API, selection) stay attached. Round-1 High [H3]: script/handler injection is now mode-branched so the single-`Double` `progressHandler` does not race the section-aware observer. | WI-5 |
| `vreader/Views/Reader/EPUBWebViewBridgeCoordinator.swift` | (1) Handle `continuousScrollHandler`: parse `EPUBScrollBoundarySignal`, forward to coordinator; on visible-spine change drive `onProgressChange`/position with the *windowed* spine index + fraction. (2) Handle `sectionMaterialized` (round-1 High [H6] lifecycle hook): fire the per-section highlight-restore + bilingual-enumerate, replacing the `didFinish`-only path that appended sections never hit. (3) Round-1 Critical [C1]: selection messages now resolve their **section's** href/spine-index from the tapped DOM section (`closest('[data-vreader-href]')`), not the global `currentHref`. | WI-5, WI-6 |
| `vreader/Views/Reader/EPUBReaderContainerView.swift` | When `epubLayout == .scroll`, instantiate `EPUBContinuousScrollCoordinator` (wired to a `chapterBodyProvider` that calls `ensureChapterExtracted` + `parser.contentForSpineItem` + `EPUBChapterBodyRewriter.rewrite`) and pass `continuousScroll:` into the bridge. Restore: bootstrap a window containing `savedSpineIndex`, then `scrollToSpineFraction(savedSpineIndex, savedProgression)`. Mode-switch bumps the coordinator generation token + rebuilds. Keep paged path untouched. | WI-6 |
| `vreader/Views/Reader/EPUBReaderContainerView+Highlights.swift` & `EPUBHighlightActions.swift` | `restoreHighlightsJS(currentHref:)` filters `href == currentHref` (verified line ~49) — extend with `restoreHighlightsInSection(href:spineIndex:)` that scopes the paint to the section subtree, and drive restore from the `sectionMaterialized` hook for **every** materialized section. | WI-6 |
| `vreader/Views/Reader/EPUBHighlightBridge.swift` | `searchHighlightJS` uses whole-`document` `window.find()` — round-1 Medium [M1]: this matches the FIRST occurrence across ALL loaded sections, wrong when the quote also appears in another loaded chapter. Add `findInSection(spineIndex:quote:)` scoped to the target section; if the target spine index is outside the window, the container extends/seeks the window to include it first, then finds scoped. | WI-6 |
| `vreader/Views/Reader/Bilingual/EPUBBilingualOrchestrator.swift` & `EPUBBilingualPipeline.swift` | Round-1 High [H5]: EPUB bilingual uses one global `currentBlocks` and `BilingualBlock.sectionIndex` is nil for EPUB; re-enumerating on append would bleed `bid`s across sections. Adopt the **section-scoped pattern the Foliate orchestrator already uses** (`FoliateBilingualOrchestrator` keys per `sectionIndex`): namespace EPUB `bid`s by spine index and partition enumerate/inject per materialized section. If this proves heavy, gate continuous-mode bilingual behind a follow-up issue (documented, not silently dropped). | WI-7 |
| `vreader/Views/Reader/EPUBProgressCalculator.swift` | No formula change expected — the windowed `{visibleSpineIndex, intraFraction}` feeds the existing `progress(spineIndex:scrollFraction:totalSpineItems:)`. Confirm no edit during WI-5. | WI-5 |
| `docs/architecture.md` | Add `EPUBContinuousScrollCoordinator` + the continuous-scroll DOM-window model to the reader-architecture notes (alongside the one-chapter-per-load paged model). | WI-8 |

### Files OUT of scope

- **Foliate engine / AZW3 path** (`vreader/Services/Foliate/**`, `vreader/Services/EPUB/FoliateJS/**`) — approach (d) rejected; no edits.
- **Paged-mode code** (`EPUBPaginationHelper`, `BasePageNavigator`, `EPUBChapterNavigationRouter`, `EPUBChapterWrapPendingTarget`, `EPUBReaderContainerView+ChapterWrap.swift`) — §2.2 is shipped; untouched.
- **PDF / TXT / MD readers** — already have continuous scroll or are out of format scope.
- **Reader Settings UI** (`ReaderSettingsPanel.swift`) — the Scroll/Paged picker already exists; no new control (design §6: "same Display sheet; no new controls").
- **ReaderBottomChrome / scrubber** — already computes whole-book progress; reused as-is.
- **Bilingual injection** (`EPUBBilingual*`) — round-2 [H5] correction: **this IS in scope for WI-7** (`EPUBBilingualOrchestrator` / `EPUBBilingualPipeline` get section-scoped `bid` namespacing + per-section enumerate/inject, mirroring `FoliateBilingualOrchestrator`). The earlier "not rewritten" claim was a v1 leftover and is retracted. If WI-7 proves heavy at implementation, continuous-scroll bilingual is **deferred entirely** behind a follow-up GH issue (with non-bilingual continuous scroll shipping first) — that deferral is the only path under which `EPUBBilingual*` stays untouched, and it would be recorded explicitly in the WI-7 PR.

---

## Prior art / project precedent / rejected alternatives

- **Foliate engine (the AZW3/MOBI path) natively does continuous cross-section scroll.** `vreader/Services/Foliate/JS/foliate-host.js` sets `r.setAttribute('flow', opts.flow)` ('scrolled' | 'paginated') on a single `view.renderer` that owns the *whole* book; `view.renderer.getContents()` returns `[{doc, index}]` across multiple materialized sections. Bug #235 wired AZW3 continuous scroll essentially by passing `flow: scrolled`. **This is the proven pattern** — a renderer that owns a multi-section window and stitches them in one scroll context. Approach (b) replicates this *model* for the EPUB WKWebView path without adopting the whole Foliate engine (which would re-anchor highlights/search/TOC/position onto CFI — too big for #71).
- **Project precedent for windowed lazy rendering**: the chunked TXT reader (`TXTReaderHost` → `UITableView` for >500K UTF-16) already establishes "materialize a window, evict the far end, compensate scroll offset on prepend" as a vreader pattern. Bug #180's TXT continuous scroll is the format sibling.
- **Project precedent for pure-decision + closure-eval split**: `EPUBChapterNavigationRouter` (pure `Decision` enum, container performs the side effect) and `EPUBPaginationHelper` (pure JS string generators) are the exact shape WI-1/WI-2 follow — testable logic, untestable WKWebView eval behind a closure.
- **Prepend scroll-offset compensation** is the well-known "infinite scroll up" problem (measure `scrollHeight` before insert, restore `scrollTop += delta` after) — standard web pattern; we adopt it rather than invent.
- **Rejected**: a SwiftUI `LazyVStack` of per-chapter WKWebViews (approach c) — cross-WebView selection/CFI/progress is intractable; precedent against it is the entire reason EPUB uses one WebView today.

---

## Work-item sequencing

Round-1 Medium [M2] applied: WI-2 split into the DOM-contract vs the bridge integration; WI-4 split into bridge-plumbing vs container-integration; anchor/lifecycle/bilingual moved earlier. 6 → 8 WIs.

| WI | Title | Tier | Est. PR size | Depends on |
|---|---|---|---|---|
| **WI-1** | `EPUBSpineWindow` — pure window value type (non-empty invariant) + transition functions | **Foundational** | Small (1 type + 1 test file) | — |
| **WI-2** | `EPUBChapterBodyRewriter` — pure XHTML→merged-DOM rewriter: `<body>` extract + relative-URL absolutization + `id`/fragment namespacing + scoped CSS, returns `EPUBChapterBody` | **Foundational** | Medium (the DOM contract; heavy edge-case test surface) | — |
| **WI-3** | `EPUBContinuousScrollJS` — static JS generators (bootstrap, append/prepend w/ scroll-compensation, evict, section-scoped observer, scroll-to-section, find-in-section, restore-in-section) | **Foundational** (pure JS strings, no WKWebView; injection-escaping is the test focus) | Medium | WI-2 |
| **WI-4** | `EPUBContinuousScrollCoordinator` — `@MainActor` window-transition decision logic, async-throwing evaluator contract, generation token; window mutates only on successful eval | **Behavioral** (logic unit-testable with stub evaluator; no live WKWebView yet) | Medium | WI-1, WI-3 |
| **WI-5** | Bridge plumbing: `continuousScroll:` input on `EPUBWebViewBridge`, mode-branched script/handler injection (observer replaces `progressTrackingJS`), `continuousScrollHandler` parse + windowed progress, **section-scoped selection href** | **Behavioral** | Medium | WI-4 |
| **WI-6a** | Container-integration foundations (split out of the original Large WI-6, see v4 revision note): (1) `EPUBContinuousChapterProvider` — a testable `@MainActor` factory: spine index → `metadata.spineItems[i].href` → `parser.contentForSpineItem(href:)` → `EPUBChapterBodyRewriter.rewrite(...)` → `EPUBChapterBody` (the closure the WI-6b coordinator is built with); (2) `EPUBWebViewEvaluatorHandle` — `@MainActor final class { weak var webView: WKWebView?; func evaluate(_ js: String) async throws }` resolving the coordinator-`evaluate`-late-binding gap (see "WI-6 evaluate-binding" below). **Narrowed during implementation (v4.1)**: `restoreHighlightsInSectionJS` was originally listed here but is NOT cleanly foundational — section-scoped highlight restore must re-root the stored single-chapter XPaths within the `[data-vreader-spine-index]` section subtree, which is coupled to the highlight-paint primitive's resolution model + the live `sectionMaterialized` hook. Moved to **WI-6b** (where it already appears in the surface-area table) — a conservative narrowing (strictly fewer, more-foundational units than the Gate-2-approved scope). | **Foundational** (a factory + a handle type; no live-render change; both unit-testable with stubs) | Small–Medium | WI-5 |
| **WI-6b-i** | **Live rendering core** (v4.2 staging — see note): container instantiates the coordinator (WI-6a provider `makeClosure()` + a FRESH `EPUBWebViewEvaluatorHandle` per bridge generation) + `EPUBContinuousScrollConfig` when `epubLayout == .scroll`; bridge `makeUIView` populates `handle.webView`; bridge load-path branch loads the **bootstrap doc** (`file://` baseURL under the extracted root — re-audit finding 3) instead of a single chapter; initial window materializes the anchor chapter ±1; **continuous-mode position callback** carrying `{visibleSpineIndex, intraFraction}` so the container updates chapter `href` + progression (re-audit Critical finding 1). Gets continuous cross-chapter scroll RENDERING + progress-tracking. | **Behavioral** | Large | WI-6a |
| **WI-6b-ii** | **Section-scoped annotations**: `restoreHighlightsInSectionJS` (re-root stored single-chapter XPaths within the `[data-vreader-spine-index]` section subtree) driven from the `sectionMaterialized` lifecycle hook for every materialized section; `findInSection` search-into-unmaterialized-chapter (extend window then find-in-section, re-audit M1). | **Behavioral** | Medium | WI-6b-i |
| **WI-6b-iii** | **Restore + mode-switch**: position restore (bootstrap a window containing `savedSpineIndex` + `scrollToSpineFraction`); inner-scroll-root safe-area inset + section-top restore against `#vreader-scroll-root` (re-audit finding 4); live `epubLayout` mode-switch teardown/rebuild with a fresh coordinator generation (re-audit finding 2). | **Behavioral** | Medium | WI-6b-i (independent of 6b-ii — Gate-2-lite nit) |
| **WI-7** | Bilingual section-scoping for continuous EPUB (namespace `bid` by spine index, per-section enumerate/inject) OR gate-behind-follow-up if heavy | **Behavioral** | Medium | WI-6 |
| **WI-8** | Final integration: memory-eviction tuning, divider/heading + skeleton (§2.4) polish, docs sync (`architecture.md`), full acceptance pass | **Behavioral (final WI)** | Medium | WI-7 |

WI-1 (`EPUBSpineWindow`) is the clean small+foundational first WI — purely integer-range arithmetic, no XHTML parsing, tight unit test. WI-2/WI-3 are foundational but not small (the DOM contract + JS escaping carry the heavy edge-case surface). This iteration starts WI-1 if time allows; otherwise stops at the audited plan.

### WI-6 evaluate-binding (resolves the v4-split design gap)

`EPUBContinuousScrollCoordinator` (WI-4) holds `evaluate: @escaping @MainActor
(String) async throws -> Void` as an immutable `let`, set at init. But the
**container creates the coordinator before the live `WKWebView` exists** — the
webview is built in `EPUBWebViewBridge.makeUIView`, which runs *after* the
container passes `continuousScroll: EPUBContinuousScrollConfig` into the bridge.
So the container cannot supply a working `evaluate` closure at coordinator-init
time. The original Large WI-6 did not specify how `evaluate` reaches the webview;
WI-6a closes that gap with a late-binding handle:

- `EPUBWebViewEvaluatorHandle` — `@MainActor final class` holding
  `weak var webView: WKWebView?` and `func evaluate(_ js: String) async throws`.
  `evaluate` bridges `WKWebView.evaluateJavaScript` (the completion-handler form)
  through a `withCheckedThrowingContinuation`; when `webView == nil` (not yet
  mounted, or torn down) it **throws** `EPUBWebViewEvaluatorError.noWebView`, so
  the coordinator's existing round-1 [H4] contract (window does NOT advance on a
  failed eval) handles the pre-mount window safely — a boundary signal that
  arrives before the webview mounts is a no-op, not a crash or a desynced window.
- Wiring (WI-6b): the container builds the coordinator with
  `evaluate: { [handle] js in try await handle.evaluate(js) }`, and threads the
  handle to the bridge; `makeUIView` sets `handle.webView = webView` (a weak
  capture — no retain cycle, released with the bridge). **Provisional — see the
  "WI-6b design requirements" freshness rule below**: the `weak` ref alone is NOT
  sufficient (an outgoing webview can briefly outlive a rebuild), so WI-6b must
  use a FRESH handle per bridge generation (or nil+rebind on teardown), per
  re-audit finding 2; the single-handle description here is the happy-path sketch,
  not the teardown contract.
- This keeps WI-4's coordinator API unchanged (still a `let` evaluate closure),
  isolates the WKWebView dependency behind a testable seam (the handle is
  unit-testable with `webView == nil`), and is the single architectural unblock
  WI-6b's live wiring depends on.

WI-6a is fully unit-testable with no live-render change (JS-string assertions for
`restoreHighlightsInSectionJS`; a stub `contentForSpineItem` for the provider; a
`webView == nil` handle for the evaluator-throws path). WI-6b is the behavioral
live integration that consumes all three.

### WI-6b design requirements (from the v4 Gate-2 re-audit — Codex thread 019e6683)

The re-audit confirmed the split + WI-6a scope are sound (all named seams exist;
`restoreHighlightsInSectionJS` is genuinely absent). It raised four **WI-6b**
hardening requirements that MUST be in 6b's implementation (not deferrable):

1. **[Critical] Continuous-mode progress must update `href`, not just total
   progress.** WI-5's `EPUBWebViewBridgeCoordinator.handleContinuousScrollMessage`
   currently maps the windowed `{visibleSpineIndex, intraFraction}` to a `Double`
   and calls the existing `onProgressChange(Double)`. The container's
   `onProgressChange` (EPUBReaderContainerView ~:495) then looks the spine index
   up from `viewModel.currentPosition?.href` — which stays pinned to the OLD
   chapter when the reader scrolls into the next section. WI-6b must add a
   continuous-mode callback carrying at least `{visibleSpineIndex, intraFraction}`
   (or the full `EPUBScrollBoundarySignal`) so the container updates both the
   chapter `href` (from `metadata.spineItems[visibleSpineIndex].href`) and the
   progression. Do NOT reuse the `Double`-only `onProgressChange` for position in
   continuous mode.
2. **[High] Handle stale-identity on rebuild.** `weak var webView` prevents a
   retain cycle but does NOT guarantee freshness: a live mode-switch / reopen can
   leave `handle.webView` pointing at an outgoing (still-briefly-alive) webview,
   so an eval could hit the stale DOM instead of throwing `noWebView`. WI-6b must
   break identity explicitly: create a FRESH `EPUBWebViewEvaluatorHandle` per
   bridge generation (tie it to the coordinator's generation token / reader
   token), OR nil+rebind it on teardown, so a stale-webview eval can't fire.
3. **[High] Bootstrap load must satisfy the `file://` navigation policy.** The
   bridge's `decidePolicyForNavigationAction` (EPUBWebViewBridgeCoordinator ~:283)
   cancels any non-`file://` navigation. A naive `loadHTMLString(_, baseURL: nil)`
   bootstrap is blocked. WI-6b must either `loadHTMLString` with a `file://`
   `baseURL` under the extracted root, or write+`loadFileURL` a file-backed
   bootstrap document, or narrowly relax the policy for the one bootstrap nav.
4. **[Medium] Inner-scroll-root safe-area + restore.** Continuous mode scrolls
   `#vreader-scroll-root`, not `webView.scrollView`. The bug-#163 safe-area top
   inset and the "scroll to chapter top" restore both operate on
   `webView.scrollView` today; WI-6b must revalidate them against the inner root
   (inset via bootstrap CSS / root padding, or root-level JS scrolling) and add a
   slice test for safe-area top + section-top restore in continuous mode.

---

## Test catalogue

| Test file | WI | Covers |
|---|---|---|
| `vreaderTests/Views/Reader/EPUBSpineWindowTests.swift` | WI-1 | `initial(anchor:spineCount:)` returns nil for `spineCount==0`, `0...0` for `spineCount==1` (no extend possible); `extendForward`/`extendBackward` clamp at `0`/`spineCount-1` and respect `canExtend*`; `evictFarFromAnchor(maxSpan:)` keeps anchor in window, trims the far side first; `contains`; `maxSpan` boundary (extend past max triggers eviction); anchor at first/last chapter; anchor in the middle evicts symmetrically toward whichever end is farther. |
| `vreaderTests/Views/Reader/EPUBChapterBodyRewriterTests.swift` | WI-2 | `<body>` inner extraction; **relative `src`/`href` absolutization** against the chapter dir (`../img/a.png` from `OEBPS/text/c1.xhtml` → correct absolute); **`id` namespacing** (`id="n1"`→`id="s3-n1"`) + **intra-doc fragment rewrite** (`href="#n1"`→`href="#s3-n1"`) without touching cross-document hrefs; SVG `<use href="#sym">` / ARIA `aria-labelledby` reference namespacing; **inline `<style>` scoped** (a chapter's `p{color}` does not restyle a sibling chapter); **linked `<link rel=stylesheet>` inlined+scoped via stub `linkedStylesheetLoader`** (round-2 [C2-residual]); **nested CSS `url(../fonts/x.woff)` rewritten to absolute** against the stylesheet dir; loader returning nil for a missing stylesheet → skipped, no crash; malformed XHTML (no body) returns empty body, no crash; CJK content + CJK in href preserved (UTF-8/UTF-16); empty chapter; href with subdirectory path. |
| `vreaderTests/Views/Reader/EPUBContinuousScrollJSTests.swift` | WI-3 | `appendChapterSectionJS`/`prependChapterSectionJS` escape body via `FoliateJSEscaper` (injection: `</script>`, backtick, `${`, quote, U+2028, U+2029); prepend JS captures+restores `scrollTop` (string contains the compensation transaction); divider title escaping; `removeChapterSectionJS` targets the right `data-vreader-spine-index`; `scrollToSpineFractionJS` clamps fraction; `findInSectionJS` scopes the search root to the section subtree, not `document`. |
| `vreaderTests/Views/Reader/EPUBContinuousScrollCoordinatorTests.swift` | WI-4 | `nearBottomBoundary` at `hi<spineCount-1` ⇒ extends forward + emits ONE append (idempotent: a duplicate signal does NOT double-append); `nearTopBoundary` at `lo>0` ⇒ prepend; at last/first chapter ⇒ no-op (no bounce JS); **partial failure**: if the async evaluator throws, the window state does NOT advance (round-1 [H4]); **stale generation**: a `chapterBodyProvider` task that resolves after the generation token bumped is discarded; rapid alternating signals don't thrash; eviction emits remove JS for the trimmed index. Recording stub evaluator (`async throws`) + stub `chapterBodyProvider`. `@MainActor`. |
| `vreaderTests/Views/Reader/EPUBContinuousScrollPositionTests.swift` | WI-5/WI-6 | A windowed `{visibleSpineIndex:2, intraFraction:0.5}` signal maps to `EPUBProgressCalculator.progress(spineIndex:2, scrollFraction:0.5, total:N)`; restore: open at `(spineIndex:3, progression:0.4)` bootstraps a window containing 3 + seeks to section+offset; restore mid-book interior chapter; mode-branched injection picks the observer (not `progressTrackingJS`) in continuous mode. |
| `vreaderTests/Views/Reader/EPUBContinuousScrollAnchorTests.swift` | WI-5/WI-6 | Selection in section i resolves `href` to section i's `data-vreader-href`, NOT the global `currentHref` (round-1 [C1]); **cross-section selection clamps to the START section** + a degenerate cross-boundary selection is rejected (round-2 [C1-residual]); highlight created in section i paints scoped to section i; `restoreHighlightsInSection` only paints that section's records; the `sectionMaterialized` hook drives restore for each appended/prepended section (round-1 [H6]); search target in an unmaterialized chapter triggers window-extend-then-find-in-section; a highlight in an evicted chapter re-applies on re-materialization; same quote in two loaded sections finds the TARGET section's occurrence (round-1 [M1]). |
| `vreaderTests/Views/Reader/EPUBBilingualSectionScopeTests.swift` | WI-7 | EPUB `bid`s are namespaced by spine index; enumerate on append partitions blocks per section (no cross-section bleed); inject targets only the section's blocks — mirrors the existing `FoliateBilingualOrchestrator` per-`sectionIndex` tests (round-1 [H5]). |

Audit-driven additions already folded in above (partial-failure eval, stale-generation, scroll-compensation, CSS scoping, id/fragment namespacing, section-scoped selection/search/restore, bilingual partitioning). Remaining edge to confirm in impl: idempotent re-bootstrap on theme change must not duplicate sections (theme change in continuous mode re-injects CSS, not the bootstrap).

---

## Risks + mitigations

| Risk | Mitigation |
|---|---|
| **WKWebView memory with multiple chapters loaded** | Hard `maxSpan` (start at 5 chapters) with far-end eviction; pure `EPUBSpineWindow.evictFarFromAnchor` keeps it testable. Tune in WI-6 with the largest fixture available. |
| **Scroll-position math across chapter inserts** (prepend jumps the viewport) | Measure `scrollHeight` before prepend, set `scrollTop += (newHeight - oldHeight)` after, in one JS transaction; covered by `EPUBContinuousScrollJSTests` + slice-verified on device. |
| **Per-chapter CSS bleed + lost base URL** (round-1 [C2]) | `EPUBChapterBodyRewriter` (WI-2) absolutizes relative asset URLs, namespaces `id`/fragment refs by spine index, and scopes each chapter's `<style>`/`<link>` to its section. Decision on scoping mechanism (selector-prefix vs `@scope` vs section-wrap) finalized in WI-2 against a real multi-CSS fixture. |
| **Document-relative anchors break in stitched DOM** (round-1 [C1]) | Selection messages resolve the section's `data-vreader-href`/spine-index from the tapped DOM (`closest('[data-vreader-href]')`), not the global `currentHref`. Highlight restore + paint scope to the section subtree. Moved into WI-5/WI-6 (early), not the final WI. |
| **`progressTrackingJS` races the section observer** (round-1 [H3]) | Script + handler injection is mode-branched in `makeUIView` (WI-5): continuous mode injects the section-aware observer and does NOT inject `progressTrackingJS`; the single-`Double` `progressHandler` contract is replaced, not augmented. |
| **JS-eval failure is invisible / stale async chapter fetch** (round-1 [H4]) | The coordinator's evaluator is `async throws`; the `EPUBSpineWindow` mutates only after a successful eval. A generation `UUID` token (bumped on mode-switch / reopen / book-change) discards `chapterBodyProvider` results that resolve after the switch. |
| **`.readerPositionDidChange` / locator sync across chapters** | The windowed signal carries `visibleSpineIndex`; the existing `EPUBPosition{href, progression}` + `makeCurrentLocator()` path is reused unchanged — the *source* of the spine index changes, not the persistence shape. Backward-compatible locators. |
| **Interaction with §2.2 paged wrap** | Mutually exclusive at the mode level; paged code untouched. Mode switch bumps the generation token, tears down the window, and rebuilds paged (existing `isPagedChanged` seam). Slice-verify both directions of the switch. |
| **Search matches wrong section** (round-1 [M1]) | `findInSection(spineIndex:quote:)` scopes `window.find` / range-walk to the target section subtree; if the target spine index is outside the window, the container extends/seeks first. WI-6. |
| **Section-materialized lifecycle** (round-1 [H6]) | Appended/prepended sections never fire `onPageDidFinishLoad`. A `sectionMaterialized` message handler (WI-5) drives per-section highlight restore + bilingual enumerate; the `didFinish`-only path stays for the bootstrap doc. |
| **Reopen race / late didFinish** (bugs #126/#142/#251) | Bootstrap doc reuses the same `(webView, fingerprintKey, readerToken)` registry pairing + early-settle fallback already in the bridge — we do not regress those seams. The new generation token is complementary (covers async chapter fetches, not webview identity). |
| **Bilingual section bleed** (round-1 [H5]) | EPUB `bid`s namespaced by spine index; enumerate/inject partitioned per materialized section, mirroring the `FoliateBilingualOrchestrator` per-`sectionIndex` pattern that already exists. WI-7; gate-behind-follow-up if heavy (documented, not silently dropped). |
| **Foliate-bridge.js side effects** in a multi-section DOM | foliate-bridge is injected per-document; the bootstrap is one document, so it loads once. Verify CFI/overlayer helpers don't assume a single section — likely fine (they operate on whatever DOM exists) but slice-verify. |

---

## Backward compatibility

- **Existing EPUB reading positions (locators)** are `{href, progression, totalProgression}` — unchanged. A position saved in the old single-chapter scroll mode restores identically: the window bootstraps around `href`'s spine index and seeks to `progression`.
- **Paged mode** byte-for-byte unchanged (the `continuousScroll:` input is nil on the paged path).
- **Older books / single-chapter EPUBs**: `EPUBSpineWindow` with `spineCount==1` is `0...0` and never extends — degenerates to today's single-document scroll, no regression.
- **Non-#71 callers of `EPUBWebViewBridge`** (tests, previews): `continuousScroll` defaults to nil ⇒ legacy behavior. Source-compatible.
- **The default `epubLayout` is `.scroll`** (confirmed in `ReaderSettingsStore.loadEPUBLayout`) — so this feature changes the default reading experience for EPUB. That is the intent (the convention TXT/AZW3 already meet). The mode is user-switchable to Paged with no data migration.

---

## Acceptance criteria (developed here — the row lacked them)

Exercised end-to-end on iPhone 17 Pro Simulator via the `vreader-debug://` harness with a multi-chapter EPUB fixture (`mini-epub3` has 2 content chapters; a larger fixture may be seeded for memory/eviction).

- **(a) Continuous forward flow**: in scroll mode, scrolling to the end of chapter N continuously reveals chapter N+1's content inline — **no tap, no chapter button, no visible reload flash**.
- **(b) Boundary divider + heading**: the chapter boundary renders as a horizontal divider flanking an uppercase, letter-spaced chapter heading per design §2.3 / `vreader-scroll-mode.jsx::ChapterDivider`.
- **(c) Continuous reverse flow**: scrolling up past chapter N's start reveals chapter N-1's content, with the viewport staying anchored (no jump) when the previous chapter is prepended.
- **(d) Position persistence + restore**: closing mid-chapter-N and reopening restores to the same chapter and scroll offset (exact-pixel per §2.3 line 61), including when N is an interior chapter.
- **(e) Paged mode unchanged**: switching Display → Paged restores §2.2 paged behavior (side-tap chapter wrap, multi-column) with no regression; switching back to Scroll re-enters continuous flow.
- **(f) Highlights + search + TOC across the continuous view**: a highlight created in any materialized chapter persists and re-paints on scroll; a search-result tap into a not-yet-materialized chapter navigates and highlights; a TOC tap to chapter M seeks the continuous view to chapter M.
- **(g) Bounded memory**: only the current ±1 (up to `maxSpan`) chapters are materialized; far chapters are evicted (verifiable via a JS `eval` count of `section[data-vreader-spine-index]` nodes staying ≤ `maxSpan`); the skeleton shimmer (§2.4) shows while a near boundary materializes.

---

## Gate 2 — Independent Plan Audit

### Round 1 — Codex thread `019e5f97` (2026-05-25)

Verdict: plan NOT sound as v1; core reframe ("multi-chapter scroll is an early DOM-contract change, not late bridge wiring") accepted. Model-assumption verification largely passed (named seams exist). 2 Critical / 4 High / 2 Medium / 1 Low.

**Model assumptions verified by Codex (no fix needed):** `EPUBLayoutPreference.scroll/.paged`; `EPUBWebViewBridge.isPaged` + `updateUIView`'s `isPagedChanged`/`urlIsChanging` seams; `EPUBParserProtocol.contentForSpineItem(href:)`; `EPUBReaderContainerView.ensureChapterExtracted(href:)` (a thin wrapper over `contentForSpineItem`); `EPUBProgressCalculator.progress(spineIndex:scrollFraction:totalSpineItems:)`; `EPUBPosition{href,progression,totalProgression,cfi}`; `FoliateJSEscaper.escapeForJSString` (path corrected to `vreader/Services/Foliate/FoliateJSEscaper.swift`); `EPUBReaderViewModel.navigateToSpine`/`currentSpineIndex`; foliate-host.js `r.setAttribute('flow', …)` prior art. Minor correction noted: href filtering lives in `EPUBHighlightActions.restoreHighlightsJS`, not inside `EPUBHighlightRenderer` itself — surface-area table corrected accordingly.

### Audit fixes applied (Gate 2 round 1 → plan v2)

| # | Severity | Finding | Resolution in v2 |
|---|---|---|---|
| C1 | Critical | Anchors are document-relative; selection assigns `href = currentHref`, breaks in a stitched/evicted DOM | Selection resolves the **section's** `data-vreader-href` from the tapped DOM; highlight restore + paint scope to the section subtree. Moved into WI-5/WI-6 (early). |
| C2 | Critical | "Sanitizer" under-shaped — merged DOM breaks relative asset URLs, duplicate `id`s, local `#anchor`s, SVG/ARIA refs, one-shot CSS preprocessing | Renamed `EPUBChapterBodyRewriter`; WI-2 now absolutizes relative URLs, namespaces `id`/fragment refs by spine index, scopes per-chapter CSS. Reframed as the load-bearing DOM contract. |
| H3 | High | Always-injected `progressTrackingJS` + single-`Double` `progressHandler` races the new observer | Mode-branched script/handler injection in `makeUIView` (WI-5): continuous mode injects the section-aware observer instead of `progressTrackingJS`. |
| H4 | High | `(String)->Void` evaluator can't observe JS failure; no token for stale async chapter fetches | Evaluator is `@MainActor (String) async throws -> Void`; window mutates only on success; generation `UUID` token discards stale `chapterBodyProvider` results. |
| H5 | High | EPUB bilingual one global `currentBlocks`, `sectionIndex` nil for EPUB → cross-section `bid` bleed | WI-7 adopts the Foliate orchestrator's per-`sectionIndex` pattern; namespace `bid` by spine index; gate-behind-follow-up if heavy. |
| H6 | High | Highlight/bilingual lifecycle hangs off one `onPageDidFinishLoad` per `loadFileURL`; appended sections never fire it | `sectionMaterialized` message handler (WI-5) drives per-section restore + enumerate. |
| M1 | Medium | Whole-document `window.find()` matches the wrong section when the quote repeats | `findInSection(spineIndex:quote:)` scopes to the target section; extend-then-find if outside window. WI-6. |
| M2 | Medium | WI-2 not "Small"; WI-4 too large | Split: WI-2 = DOM contract; WI-3 = JS; WI-4 = coordinator logic; WI-5 = bridge plumbing; WI-6 = container integration. 6 → 8 WIs. |
| L1 | Low | `EPUBSpineWindow` closed `lo...hi` range vs `spineCount==0` test | Explicit non-empty invariant + `initial(anchor:spineCount:) -> EPUBSpineWindow?` (nil for empty); container guards the zero-spine case. |

### Round 2 — Codex thread `019e5f97` (2026-05-25)

Confirmed resolved: H3, H4, H6, M1, M2 (WI-6 large-but-cohesive, "would not split again yet"), L1; H5 structurally resolved. 2 residual Highs + 1 Medium remained:

| # | Severity | Finding | Resolution in v3 |
|---|---|---|---|
| C2-residual | High | Rewriter (XHTML + base URL only) can't scope **external linked stylesheets**; nested CSS `url(...)` not covered | Added `linkedStylesheetLoader: (String) -> String?` closure to the rewrite signature (container reads extracted CSS bytes; pure+testable via stub); rewriter inlines+scopes linked CSS and rewrites nested `url(...)` to absolute; missing stylesheet is skipped with a log, not a crash. |
| C1-residual | High | No policy for a selection range that crosses a chapter boundary in the stitched DOM | Explicit policy: clamp the range to the section containing its START anchor; reject if the clamp empties it. Unit-tested. Per-section split rejected as v1 out-of-scope. |
| H5-contradiction | Medium | "Files OUT of scope" still said bilingual is not rewritten, contradicting the WI-7 modified-files entry | Retracted the stale claim; `EPUBBilingual*` is explicitly in scope for WI-7, with full deferral-behind-follow-up as the only untouched path. |

### Round 3 — Codex thread `019e5f97` (2026-05-25) — CLEAN

C2-residual / C1-residual / H5-contradiction all confirmed resolved. **No open Critical/High/Medium.** Final verdict: **`sound-with-low-notes`** — the Low notes (L1 already fixed; no other Lows raised) are acceptable to defer. Plan is **PLANNED-ready**; cleared to start TDD on WI-1 (`EPUBSpineWindow`).

**Gate 2 summary**: 3 rounds (the rule-47 max). Codex caught 12 findings total (round 1: 2C/4H/2M/1L; round 2: 2H/1M) — the largest being the "early DOM-contract change" reframe that restructured the plan from 6 → 8 WIs and moved anchor/selection/lifecycle/CSS-scoping work to the front. Author/auditor separation satisfied (Codex is a separate process).
