---
branch: feat/feature-60-wi-11-five-theme-picker
threadId: 019e30fd-3424-7a90-ba6d-b0f1ddde2a80
rounds: 2
final_verdict: follow-up-recommended
date: 2026-05-16
---

## Gate 4 — Codex implementation audit, feature #60 WI-11

WI-11 is the final work item of feature #60 (visual identity v2). It
migrates `ReaderSettingsStore.theme` from the legacy 3-case
`ReaderTheme` enum to the 5-case `ReaderThemeV2`, making all 5 themes
(Paper / Sepia / Dark / OLED / Photo) user-selectable, with
backward-compatible decoding of existing persisted choices.

Codex MCP, read-only sandbox. Thread `019e30fd-3424-7a90-ba6d-b0f1ddde2a80`.

## Round 1

Findings:

- **High** — Photo theme is user-selectable but EPUB cannot render the
  user-picked photo background image (`ReaderThemeV2+EPUBCSS.swift`
  `backgroundImageRule` is dormant; `EPUBReaderContainerView` passes
  `backgroundImageURL: nil`; the EPUB webview's opaque `html`
  background occludes `ThemeBackgroundView` behind it).
- **Low** — the 5-theme picker is close to the design but not literal:
  the selected swatch dropped the design's second outer ring, and the
  Photo swatch used a flat fill instead of the design's diagonal
  gradient.

Backward-compat decode, strict no-clobber handling, `theme`/`asV2`
migration, DebugBridge producer/observer compatibility, Swift 6
concurrency, and legacy `ReaderTheme` retention were all confirmed
correct.

## Round 1 → fixes applied

- **Low (fixed)** — `ReaderSettingsPanel.themeSwatch` rewritten to
  match the design literally: the selected swatch now gets the
  design's two-ring treatment (a 2.5pt accent ring hugging the tile +
  a 1.5pt outer band in `sheetTheme.sheetSurfaceColor` — the design's
  `0 0 0 2.5px accent, 0 0 0 4px surface` box-shadow; `sheetSurfaceColor`
  is exactly the design's `t.isDark ? '#222020' : '#fcf8f0'`), and the
  Photo swatch uses `photoSwatchGradient` — a 135° `LinearGradient`
  from `#3a2818` to `#1a1410`, the design's exact
  `linear-gradient(135deg, #3a2818, #1a1410)`.
- **High** — pushed back with scope evidence: the EPUB photo-image-CSS
  injection is a *pre-existing WI-4 deferral*, not a WI-11 regression.
  The `backgroundImageRule` doc comment (shipped in WI-4) explicitly
  states the WKWebView read-access plumbing "ships in a later WI;
  until then callers pass `backgroundImageURL: nil` and this branch
  stays dormant." WI-11's brief scoped Photo to "make it selectable +
  engage the existing `ThemeBackgroundStore` flow + do NOT invent UI"
  — it did not scope the `allowingReadAccessTo` security-boundary work.
  WI-11 broke nothing: `EPUBReaderContainerView` passed
  `backgroundImageURL: nil` before WI-11 and still does.

## Round 2

- **High → resolved.** Codex agreed: "The EPUB custom-photo backdrop
  gap is a pre-existing WI-4 deferral, not a WI-11 regression... For
  WI-11 specifically, the right disposition is follow-up, not blocker."
- **Low → resolved.** "The Low finding on picker fidelity is resolved
  by the current `themeSwatch` implementation."
- **Medium (new)** — plan/code source-of-truth mismatch: the feature
  plan stated EPUB Photo "injects a background image via local file
  URL" as if it were live, while the shipped code documents the branch
  as deferred.

## Round 2 → fixes applied

- **Medium (fixed)** — `dev-docs/plans/20260515-feature-60-visual-identity-v2.md`
  "Reader-engine theme injection updates > EPUB" bullet updated to
  state the EPUB Photo background-image branch ships deferred, with
  the WKWebView `allowingReadAccessTo` blocker spelled out and the
  follow-up issue cited. A WI-11 revision-history entry was added.
- **Follow-up filed** — **GH #795** ("EPUB Photo theme: render
  user-picked background image inside the WKWebView") tracks wiring
  the Photo theme's `ThemeBackgroundStore` image into EPUB rendering
  (copy/symlink under the EPUB extraction root, or widen WKWebView
  read access). Refs #718.

## Disposition

- Critical: none. High: none open (round-1 High re-classified as a
  pre-existing WI-4 deferral and tracked as GH #795). Medium: none
  open (round-2 Medium fixed via the plan update). Low: none open
  (round-1 Low fixed).
- Gate 4 acceptance bar (zero open Critical/High/Medium) met. The
  single Low was fixed; the follow-up (GH #795) is for a pre-existing
  deferral outside WI-11's scope, recorded per rule 47.

Final verdict: `follow-up-recommended` (follow-up = GH #795).
