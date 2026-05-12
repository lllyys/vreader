# Feature #49 — EPUB chapter top/bottom padding

**Status when written**: PLANNED (Cat 3 — row had Problem/Scope/Edge Cases/Test plan/Acceptance criteria but no plan doc).
**Plan date**: 2026-05-12.
**GH issue**: #496.
**Severity**: Low.

## Problem

`ReaderTheme.epubOverrideCSS` injects `body { padding: 0 16px !important }` — **zero vertical padding** — so EPUB chapter content starts and ends flush against the viewport edge. Readers accustomed to Kindle / Apple Books / Moon+ expect ≥ 1em of whitespace at each chapter boundary. Combined with the chrome bar overlay at the top, the very first line of a new chapter feels visually pinned to the bezel.

## Scope

A **single CSS change** in `vreader/Models/ReaderTheme.swift:122`:

```diff
-        body { \
-          padding: 0 16px !important; \
+        body { \
+          padding: 2em 16px !important; \
           margin: 0 !important; \
         }\
```

That's it. No new types, no new files, no Swift logic, no view changes. All three themes (Light / Sepia / Dark) inherit the new padding automatically because `epubOverrideCSS()` is called per-theme.

### Files in scope

- `vreader/Models/ReaderTheme.swift` (~1-line CSS string change)
- `vreaderTests/Models/ReaderThemeTests.swift` (~2 regression-guard tests)

### Files OUT of scope

- `vreader/Views/Reader/EPUBPaginationHelper.swift` — the pagination CSS uses its own `body { margin: 0 }`, but it's injected ON TOP of `epubOverrideCSS` so any padding from theme CSS applies first. Bug #171's `column-count: 1 !important` works orthogonally.
- `vreader/Views/Reader/EPUBWebViewBridge.swift` — bug #163's safe-area inset wiring is unchanged; the new body padding ADDS to it (chrome offset + DI offset + body padding-top), all of which converge on "content has breathing room from the top of the screen".
- Any non-EPUB renderer (TXT/MD/PDF/AZW3) — those use their own pipelines.

## Prior art / project precedent

- The existing `epubOverrideCSS()` is the project's source of truth for theme-level CSS. Both bug #168 (font-family) and bug #163 (safe-area) modified other parts of this same CSS string. The pattern is well-precedented: one-line CSS change + a regression-guard test asserting the declaration is present at the expected shape.
- The `!important` declaration is consistent with the rest of the theme CSS — bug #171 round 2 explicitly normalized to `!important` on every pagination-related declaration. Adding `!important` here matches that convention.
- The choice of `2em` (not `16px` or `24px`) follows the typographic convention: padding scales with the user's font size. A 64pt user keeps proportional breathing room; a 12pt user doesn't get over-padded.

## Edge cases

| Case | Interaction | Mitigation |
|---|---|---|
| EPUB book sets its own `body { padding }` (normal author CSS) | Our injected `body { padding: 2em 16px !important; }` is appended late to `<head>` and uses `!important`, so it beats normal author CSS and same-specificity sheet rules by source order. | Sufficient for the typical case. |
| EPUB author uses a more-specific selector with `!important` (e.g. `body.calibre { padding: 0 !important }`) OR inline `style="padding: ... !important"` on `<body>` | More-specific `!important` rules and inline `!important` styles beat our bare `body { ... !important }`. **Our rule will NOT win in these cases** — book's padding wins. | Accepted edge case (round-2 audit finding 1). Same posture as current `padding: 0 16px !important` — neither is fully bullet-proof against author-important. Real-world frequency is low (<1% of EPUBs). If user reports it, follow-up bug can switch to a more-specific selector. |
| Paged layout mode (CSS columns), default-height viewport | Body padding eats into the per-page viewport height. With `2em` top + `2em` bottom = ~64px lost per page on default 16px font. | Acceptable. The book margin is a feature; CSS columns flow within the reduced height. Verified by Gate 5 paged-mode probe (see Test plan). |
| Paged layout mode, **short-height viewport** (landscape orientation, smaller devices) | Multicol container has fixed `height`, `overflow: hidden`, and now ~64px subtracted by body padding. Last page could clip content, or scrollWidth/clientWidth math could be off by one page. | **Round-2 audit finding 2**: Gate 5 MUST include an explicit short-viewport paged-mode check (landscape orientation, last-page rendering). See "Test plan — Gate 5 device verification" below for exact procedure. |
| Bug #163 safe-area inset stacking | WebView `scrollView.contentInset.top` already provides safe-area cushioning. Body padding adds another 2em on top. Net: MORE breathing room — improves bug #163's fix rather than fighting it. | No fix needed; the fixes are complementary. Verified by reading `EPUBWebViewBridge.swift:186`. |
| Bug #171 single-column pagination | `column-count: 1 !important` is on body (verified `EPUBPaginationHelper.swift:66`); padding is also on body. Pagination CSS does not declare its own `padding`, so it doesn't fight ours. Theme CSS injects first (line 188), pagination second (line 196) — both target `body`, distinct properties. | Pagination math (`scrollWidth / viewportWidth`) unaffected because viewport is the visible client area; columns still scale to `viewportWidth - column-gap`. |
| Cover XHTML pages using ordinary `<body>` content | Bare `body` selector is broad — any cover XHTML using normal body content will get inset by 2em. This is a **scope expansion beyond "chapter text padding"**, not just chapter content. | **Round-2 audit finding 3**: Explicitly accepted as a known behavior change for this feature. Real-world EPUB covers are typically in dedicated cover.xhtml with custom page rules and a centered cover image — those aren't visually broken by a 2em inset (the image is already centered). For text-only covers and unusual layouts, the inset will be visible. If user reports it, follow-up bug can scope padding to `body > p, body > div, body > section` instead of bare `body`. Gate 5 includes a cover-page visual smoke check. |
| First / last chapter of a book | Padding applies per chapter document, so the visual breathing room appears at every chapter boundary. | Working as designed — this is the requested behavior. |

## Test plan

### Unit tests — `vreaderTests/Models/ReaderThemeTests.swift`

Per round-2 audit finding 4, strengthen the tests beyond a brittle whole-string `contains()` check. The existing test file already does block-level CSS assertions in its `EPUB CSS Generation` section (verified `vreaderTests/Models/ReaderThemeTests.swift:119`); new tests fit there.

1. **`epubOverrideCSS_appliesVerticalBodyPadding_allThemes`** (RED → GREEN):
   - For each of `[.light, .sepia, .dark]`, generate CSS via `theme.epubOverrideCSS(fontSize: 18, ...)`.
   - Extract the `body { ... }` rule block (helper: find `body {` start, match braces to end).
   - Assert the body block contains `2em`, `16px`, and `!important`.
   - Asserting all three themes catches a future regression where a theme-specific override is added incorrectly.

2. **`epubOverrideCSS_doesNotRetainOldZeroVerticalPadding`** (regression guard against partial edits):
   - Assert the generated CSS does NOT contain `padding: 0 16px` (the old declaration).
   - This catches a sloppy edit where the old declaration is left as a duplicate elsewhere in the string.

3. **`epubOverrideCSS_paddingHorizontal16pxPreserved`** (axis-of-change guard):
   - Assert `16px` appears in the body's padding declaration (extracted as in test 1).
   - Confirms the change is "0 → 2em" on the vertical axis only, not a full rewrite that drops the 16px horizontal margin.

### Gate 5 device verification (CU-free via DebugBridge)

All commands use the documented DebugBridge URL grammar (see `docs/subsystems/debug-bridge.md`). The `open` command takes `bookId=<fingerprintKey>`, not `key`. The `settle` command waits for the reader to settle, it does not advance pagination. There is no native `navigateNext` URL command — page-advance is reader-internal and is probed (not driven) via `eval`.

Default-viewport probe (portrait, 16px font):
1. `vreader-debug://reset` → `vreader-debug://seed?fixture=mini-epub3` (the currently-bundled EPUB fixture used by feature #44 round-13 verification; verify against `DebugFixtureCatalog.swift` at probe time in case it's been renamed).
2. Compute the seeded book's `bookId` per the documented recipe (`<format>:<sha>:<bytes>`).
3. `vreader-debug://open?bookId=<encoded>` → `vreader-debug://settle?token=open`.
4. `vreader-debug://eval?bridge=epub&js=<base64>` where js = `JSON.stringify({paddingTop: getComputedStyle(document.body).paddingTop, paddingBottom: getComputedStyle(document.body).paddingBottom, firstElTop: document.body.firstElementChild?.getBoundingClientRect().top})`.
5. Read `Caches/DebugBridge/eval-epub.json`. Confirm `paddingTop` and `paddingBottom` both report `32px` or larger (2em at 16px default = 32px; rounder values acceptable). Confirm `firstElTop` is ≥ 32 (was ≥ 0 pre-fix per bug #163 round verification — content now starts below the new top padding, plus any existing safe-area inset).
6. `vreader-debug://snapshot?dest=portrait.json` → `simctl io booted screenshot` for visual confirmation.

Paged-mode short-viewport probe (round-2 audit finding 2; round-3 audit finding L2 clarifies the page-advance mechanism):
7. Rotate the simulator to landscape: `xcrun simctl ui $SIM_ID orientation landscape` (preferred; falls back to `osascript -e 'tell application "Simulator" to ...'` if `simctl ui orientation` is unavailable on this Xcode version).
8. `vreader-debug://settle?token=landscape` to give the reader time to reflow.
9. `vreader-debug://eval?bridge=epub&js=<base64>` where js queries all paged-mode invariants in one call: `JSON.stringify({columnCount: getComputedStyle(document.body).columnCount, scrollWidth: document.body.scrollWidth, clientWidth: document.body.clientWidth, pageCount: Math.ceil(document.body.scrollWidth / document.body.clientWidth), paddingBottom: getComputedStyle(document.body).paddingBottom, bodyHeight: document.body.clientHeight})`.
10. Assert from the result: `columnCount === "1"` (per bug #171 baseline), `paddingBottom === "32px"` (intact in short viewport), `scrollWidth % clientWidth === 0` OR `pageCount > 1` (real pagination, not single-page collapse), and `bodyHeight > 0` (no zero-height collapse from over-aggressive padding).
11. Drive page-advance to the last page via `eval` with `var t = document.body.scrollWidth - document.body.clientWidth; document.documentElement.scrollLeft = t; document.body.scrollLeft = t; return JSON.stringify({html: document.documentElement.scrollLeft, body: document.body.scrollLeft, target: t});`. This mirrors how production `EPUBPaginationHelper` actually advances pages (sets BOTH `documentElement.scrollLeft` and `body.scrollLeft`). Confirm the returned values for `html` and `body` both equal `target` — any mismatch means WebKit pagination math broke. `simctl io booted screenshot` captures the last-page render for visual inspection (no clipping, no excessive blank space).

Cover-page smoke (round-2 audit finding 3, accepted scope expansion):
12. If the test fixture has a dedicated cover.xhtml spine item: open and `screenshot` it. Confirm the cover image is centered and visually acceptable with the 2em inset (centered cover images stay centered; minor inset is acceptable per accepted-gap rationale).
13. If the fixture has no cover.xhtml: skip with a note in the evidence file. Documented as known limitation — full coverage of this case requires sourcing an EPUB fixture with a dedicated cover page.

Evidence file: `dev-docs/verification/feature-49-YYYYMMDD.md` per `dev-docs/verification/SCHEMA.md`. Required artifacts: portrait + landscape last-page + cover screenshots (where applicable), plus the eval JSON outputs from `Caches/DebugBridge/`.

## Acceptance criteria

(a) Opening a chapter document shows ≥ 1em top padding before the first line of text — verified via DebugBridge eval of `getComputedStyle(body).paddingTop ≥ 16px` on default font size, or via screenshot inspection.

(b) Bottom of chapter shows ≥ 1em padding after the last line — verified via DebugBridge eval of `getComputedStyle(body).paddingBottom ≥ 16px`.

(c) No visual regression in mid-chapter reading — paged mode pagination still works (scrollWidth/clientWidth ratio matches expected page count), scroll mode still scrolls smoothly.

(d) All three themes (Light, Sepia, Dark) render consistently with the same padding values.

## Work item sequencing

Single-WI feature. One PR delivers everything:

| WI | Description | Tier | Files | LOC |
|---|---|---|---|---|
| WI-1 | Add `2em` vertical padding to body in `epubOverrideCSS`; add 2 regression-guard tests. | Behavioral (final) | 1 modified + 1 modified (tests) | ~2 LOC + ~30 LOC tests |

Since the change is a single CSS declaration with no Swift logic, this fits in a single PR through the full 6-gate sequence.

## Risks + mitigations

| Risk | Likelihood | Mitigation |
|---|---|---|
| Padding interacts badly with paged-mode column math | Low | Body padding is in the multicol container; CSS spec says columns flow within the padded box. Verified at planning by reading WebKit docs + the existing column-count: 1 contract. |
| Cover-image pages get unwanted padding | Low | Accepted as known minor regression per scope above. Most cover.xhtml files have their own styling. |
| Padding feels too big at large font (64pt) | Low | `2em` scales with font-size, so 64pt → 128px padding which IS large. But the user explicitly opted into 64pt, and 2em is the typographic norm; if it's a real issue, follow-up can clamp to `min(2em, 48px)`. |
| Bug #163 fix relies on specific content layout | Low | DOM-position eval (round-3 verify for bug #163) shows first element at top=24. After this change first element top will be ~56 (24 + 32 padding). Still below DI safe-area. No regression. |

## Backward compat

- New theme CSS replaces the previously-injected one on every theme call. No persisted state changes. Existing EPUBs reopen with the new padding immediately.
- No SwiftData schema changes. No migration.
- No new feature flag — this is a typography refinement, not a togglable behavior.

## Known limitations / accepted gaps

- **Cover XHTML inset is intentional scope expansion** (round-2 audit finding 3). Bare `body` selector applies the 2em inset to every chapter document including cover pages. Real-world cover.xhtml files with centered cover images are visually acceptable; text-only covers will be inset. Track as follow-up bug only if user-reported with a problematic real-world book.
- **Author-important / inline-important EPUBs win against our rule** (round-2 audit finding 1). More-specific author `!important` rules (e.g., `body.calibre { padding: 0 !important }`) or inline `style="padding: 0 !important"` on `<body>` beat our bare `body { padding: 2em 16px !important }`. Same posture as the pre-fix `padding: 0 16px !important` — neither is bullet-proof against author-important. Frequency in real-world EPUBs is low.
- The `2em` choice is a typographic default. If user feedback suggests a different value, change is one CSS literal.

## Gate progression for this iteration

This plan doc is the Gate 1 output. The plan flows through:

- **Gate 2**: Codex MCP independent plan audit (separate context). **Completed 2026-05-12 in 3 rounds** — thread `019e1949-5a3c-7682-93f7-433d3bae4ccd`. Round 1 returned 2 Medium + 2 Low findings; Round 2 returned 1 Medium + 1 Low after revisions; Round 3 cleared with only 1 Low finding (cosmetic fixture-name cleanup). No Critical/High findings ever raised. All findings addressed in this plan revision:
  - R1-M1 (`!important` cascade language): edge case table updated with explicit author-important / inline-important caveat.
  - R1-M2 (paged-mode short-viewport check): Gate 5 test plan now includes landscape short-viewport probe with last-page integrity check.
  - R1-L1 (cover-page regression): documented as accepted scope expansion in Known limitations, with cover-page smoke check added to Gate 5.
  - R1-L2 (test brittleness): test design switched from whole-string `contains()` to body-block extraction with all-themes loop and old-declaration-absence assertion.
  - R2-M1 (`open?key` typo): corrected to `open?bookId=<encoded>` matching the documented DebugBridge param name. Lead-in note added clarifying that there is no native `navigateNext` command; page-advance is reader-internal and probed via `eval`.
  - R2-L1 (page-advance mechanism underspecified): step 11 now drives page-advance via `eval` setting BOTH `document.documentElement.scrollLeft` and `document.body.scrollLeft` (mirrors production `EPUBPaginationHelper`).
  - R3-L1 (fixture name cleanup): `alice-epub` → `mini-epub3` matching the currently-bundled fixture.
  - Codex verified `eval?bridge=epub` actually works today on the live EPUB renderer (per `RealDebugBridgeContext+Eval.swift` + `ReaderContainerView.swift:327` + feature #44 round-13 evidence), so Gate 5 is not blocked by harness gaps.
- **Gate 3**: TDD — RED tests (3 regression-guard tests per Test plan) → GREEN implementation (1-line CSS change) → REFACTOR.
- **Gate 4**: Codex MCP implementation audit (read-only sandbox).
- **Gate 5**: Device / integration verification — CU-free via DebugBridge eval per Test plan (portrait + paged-mode short-viewport + cover-page smoke) on iPhone 17 Simulator at the merged build. Evidence file at `dev-docs/verification/feature-49-YYYYMMDD.md`.
- **Gate 6**: Merge through PR + version bump (patch: 3.17.0 → 3.17.1) + tag.
