# Feature #93 — AZW3/MOBI (Foliate) theme-color parity

**Status**: Gate 2 PASSED (round 2 clean) → Gate 3 (TDD implementation)
**Row**: `docs/features.md` #93 (Medium, TODO)
**Author**: claude
**Date**: 2026-06-05

---

## Problem

AZW3/MOBI books render through the vendored Foliate-js engine
(`FoliateSpikeView` → `<foliate-view>` custom element + book-section iframe).
The reader injects only `font-size` + `line-height` via `readerAPI.setStyles`
(feature #70 WI-4) and passes `textColor: nil, backgroundColor: nil` to
`FoliateStyleMapper.themeCSS`. Consequences the user reported (triage
2026-06-04, `docs/features.md` #93):

1. **Publisher background wins** — the book's embedded `background-image`
   (e.g. the blue watercolor in 被讨厌的勇气) renders unmodified, so the
   app's paper/sepia/dark theme background is ignored. The user's words:
   *"azw3, background img didn't set, it refers to the azw3 img."*
2. **Body + per-element text use the publisher's ink**, not the theme ink —
   illegible on a dark theme when the book hard-codes near-black text on
   `<span>` / legacy `<font>` / container elements.
3. **White band / unthemed host shell** — the host `loadHTMLString` document
   and the WKWebView are opaque-white by default, so any area Foliate does
   not itself paint (a top band around `<foliate-view>`) stays white even on
   dark/sepia themes.

EPUB (`ReaderThemeV2.epubOverrideCSS`), TXT, MD, and PDF all already apply
the theme background + ink (EPUB also resets descendant `color: inherit
!important` so publisher per-element ink yields to the theme). AZW3/MOBI is
the one format left out — a documented, never-implemented gap (sibling of
feature #70 font-size parity, which explicitly listed color parity as OUT of
scope). A **feature**, not a bug.

**Context — the gap is narrowing but real.** Feature #42 flipped Kindle
convert-on-import default-ON (v3.42.42), so NEW Kindle imports become
EPUB→Readium (already themed). This gap now only hits **existing native
`.azw3`/`.mobi`** books still rendering through Foliate. Those books exist in
users' libraries today and re-importing is not automatic, so the parity fix
is still worthwhile.

---

## Surface area

### In scope

#### 1. `vreader/Models/ReaderThemeV2+EPUBCSS.swift` — expose theme colors as CSS

The private `static func cssColor(_:) -> String` (line 337) already converts
a `UIColor` to a CSS `rgb(R,G,B)` / `rgba(R,G,B,a)` string. Add three thin
**internal** computed accessors on `ReaderThemeV2` so the Foliate path can
reuse it without duplicating UIColor→CSS logic and without widening
`cssColor`'s visibility:

```swift
/// The theme's text-container surface as a CSS color string
/// (`rgb(...)`), for the book iframe `body { background }`. Mirrors the
/// color EPUB paints onto `body { background-color }` (`epubOverrideCSS`).
var paperColorCSS: String { Self.cssColor(self.paperColor) }

/// The theme's primary body-text color. Mirrors EPUB's `color: ink`.
var inkColorCSS: String { Self.cssColor(self.inkColor) }

/// The theme's OUTER page-frame tint — used for the Foliate host shell
/// (the WKWebView background behind `<foliate-view>`), mirroring EPUB's
/// `html { background-color: <backgroundColor> }`.
var outerBackgroundColorCSS: String { Self.cssColor(self.backgroundColor) }
```

These live in the same `#if canImport(UIKit)` extension as `cssColor`, so the
private helper is in scope. No behavior change to EPUB.

> **Two-stop model, matching EPUB (Gate-2 finding 2 fix).** EPUB paints
> `html { background-color: <backgroundColor> }` (the darker OUTER frame) and
> `body { background-color: <paperColor> }` (the lighter text surface). #93
> mirrors that: the book iframe `body` gets `paperColor`; the Foliate host
> shell (the WKWebView behind `<foliate-view>`) gets `backgroundColor`. Using
> `paperColor` for BOTH (the v1 plan's mistake) would diverge from EPUB's
> outer-surface model.

#### 2. `vreader/Services/Foliate/FoliateStyleMapper.swift` — descendant color reset (Gate-2 finding 1 fix)

`themeCSS` already emits `body { color: <ink> !important; }` (L87) and
`body { background: <bg> !important; }` (L92) when the args are non-nil — but
the cascade-flatten rule (L68-72) resets only `font-size`/`line-height`, NOT
`color` (its comment explicitly defers color theming as a "separate gap" —
that gap is #93). So publisher per-element ink (`<span style=color>`, legacy
`<font color>`, container colors) survives `body { color }` and stays dark on
dark themes — parity stays broken.

Fix: when `textColor` is applied, **also** emit a descendant `color: inherit
!important` reset mirroring EPUB (`epubOverrideCSS` does exactly this), and
**add legacy `<font>`** to the selector set (Kindle/MOBI content frequently
uses `<font color>`):

```swift
if let color = FoliateJSEscaper.sanitizeCSSColor(textColor) {
    rules.append("body { color: \(color) !important; }")
    // Feature #93: flatten descendant publisher ink so the theme ink wins
    // (mirrors EPUB's descendant `color: inherit`). `font` covers legacy
    // Kindle/MOBI `<font color>`. Emitted ONLY when a text color is applied,
    // so the font-size-only path (nil textColor) is unchanged.
    rules.append(
        "p, div, span, li, td, th, dd, dt, blockquote, figcaption, "
        + "section, article, aside, main, header, footer, figure, font { "
        + "color: inherit !important; }")
}
```

The existing font-size flatten rule (L68-72) is left untouched (still emitted
unconditionally) so feature #70 behavior does not change.

#### 3. `vreader/Views/Reader/FoliateSpikeView.swift` — thread colors into both surfaces

**(3a) iframe content — the PRIMARY fix.** `static func themeCSS(for store:)
-> String?` (line 62). Compute theme colors (excluding Photo — see finding 3)
and thread them in:

```swift
// Feature #93: theme colors, EXCEPT Photo theme (its paperColor is an
// intentionally alpha-blended overlay for a background IMAGE — applying it
// to a Foliate body would let the publisher image bleed through; AZW3
// custom-background is a separate, out-of-scope concern).
let themeColors: (bg: String, ink: String)? = {
    guard let theme = store?.theme, theme != .photo else { return nil }
    return (theme.paperColorCSS, theme.inkColorCSS)
}()
let base = FoliateStyleMapper.themeCSS(
    fontSize: calibrator.calibratedFoliateSize(forUnified: unified),
    lineHeight: lineHeight,
    fontFamily: nil,
    textColor: themeColors?.ink,
    backgroundColor: themeColors?.bg
)
```

`FoliateStyleMapper` routes each color through `FoliateJSEscaper.sanitizeCSSColor`
(which accepts `rgb(...)` — parens/commas are not in its forbidden set). The
`background` **shorthand** + `!important` **resets the publisher's
`background-image`** (`FoliateStyleMapper.swift:91-92`), neutralizing the blue
watercolor. Per Gate-2 finding 2, **Foliate repaints its paginator background
from the loaded section document on every `setStyles`**, so this iframe CSS is
what themes the column AND the gutters — the host shell (3b) is only a
fallback for any residual band.

A `nil` store (or `.photo` theme) → `themeColors == nil` → both args `nil` →
current font-size-only behavior preserved.

**Live theme switching is free**: `updateUIView` already diffs the `themeCSS`
string and re-pushes `setStyles` on any change (line 358). Switching
paper→dark recomputes `themeCSS(for:)` with new `rgb(...)` colors → diff
fires → `setStyles` re-applies.

**(3b) host shell — DEFENSIVE fallback only.** Mirror EPUB's
`webView.isOpaque = false` (`EPUBWebViewBridge.swift:261`). In `makeUIView`
set `webView.isOpaque = false` and seed `webView.backgroundColor` /
`webView.scrollView.backgroundColor` from the initial theme's **outer**
`backgroundColor` (NOT `paperColor` — finding 2). In `updateUIView`
unconditionally (cheap, idempotent — unlike the diffed `setStyles` push)
re-assign them from `settingsStore?.theme.backgroundColor` for live re-tint.
This only shows in areas Foliate does not itself paint (e.g. a top band); it
is a belt-and-braces against a white flash/band, not the core fix. Skipped
(left default) when there's no store or Photo theme.

Extract the host color as a pure, unit-testable helper:

```swift
/// The host-shell background for a store's theme (outer frame tint), or nil
/// when there's no store / Photo theme (keep the WebView default). Separated
/// from the WKWebView assignment so the color-selection seam is unit-testable.
static func hostShellBackgroundColor(for store: ReaderSettingsStore?) -> UIColor?
```

Update the file's "theme colors deliberately NOT wired" doc comment
(lines 73-77) to a feature #93 note.

### Files OUT of scope

- `ReaderThemeV2.swift` (the enum + `paperColor`/`inkColor`/`backgroundColor`
  definitions) — reused as-is.
- EPUB / TXT / MD / PDF theming — already correct; untouched.
- **Photo theme + custom-background parity for AZW3** — explicitly excluded
  (finding 3). Photo theme's `paperColor` is an alpha overlay for a
  background IMAGE; delivering it for AZW3 means a transparent-host /
  custom-background strategy that needs its own design. #93 leaves Photo-theme
  AZW3 rendering unchanged (publisher background) and documents it in
  acceptance + a regression test.
- The custom-background-**image** feature (`readerUseCustomBackground`)
  extending to AZW3 — separate, possibly-designed (row #93 notes this).
- `<foliate-view>` shadow-DOM / paginator-internal CSS surgery — only reached
  if Gate-5 shows a residual band the host-shell fill does NOT cover; that
  remediation is a documented follow-up, NOT a PR blocker.
- Font-size / line-height (feature #70) — preserved unchanged.

---

## Prior art / project precedent / rejected alternatives

- **EPUB precedent (the pattern this mirrors)**:
  `ReaderThemeV2.epubOverrideCSS()` derives `outerBG = cssColor(backgroundColor)`,
  `paperBG = cssColor(paperColor)`, `ink = cssColor(inkColor)`, emits
  `html { background-color: outerBG }`, `body { background-color: paperBG;
  color: ink }`, AND descendant `color: inherit !important`. #93 reuses the
  same `cssColor` converter (new accessors), the same two-stop frame, and the
  same descendant reset. `EPUBWebViewBridge` uses `isOpaque = false` for the
  host frame — #93 mirrors it.
- **Foliate font-size precedent**: feature #70 WI-4 established the
  `FoliateSpikeView.themeCSS(for:)` pure seam + the `updateUIView` diff →
  `setStyles` live-push path. #93 extends the SAME seam; the live path is
  reused unchanged.
- **`FoliateStyleMapper` already parameterized**: `themeCSS(textColor:
  backgroundColor:)` was built to accept colors (feature #68 wired
  `accentColor` for the drop-cap through the same shape); #70 passed `nil`.
  #93 completes that interface AND adds the descendant reset the color path
  needs.
- **Rejected — widen `cssColor` to `internal`**: would expose a generic
  converter app-wide. Named theme-specific accessors read better at the call
  site and keep the converter private.
- **Rejected — `paperColor` for the host shell** (v1 plan): diverges from
  EPUB's outer-frame model; corrected to `backgroundColor` per finding 2.
- **Rejected — host-shell fill as the PRIMARY gutter fix** (v1 plan): Foliate
  repaints the paginator background from the section document, so the iframe
  CSS is primary; the host fill is demoted to a defensive fallback (finding 2).
- **Rejected — `webView.backgroundColor = .clear` (EPUB's exact value)**:
  EPUB's content document paints its own `html` background over the frame;
  Foliate's host shell is our transparent shell document, so `.clear` would
  show whatever SwiftUI view sits behind. An explicit outer-token fill is
  self-contained.
- **Rejected — theming Photo for AZW3 now**: needs a transparent-host /
  custom-background design (finding 3). Excluded + documented.
- **Rejected — rely on feature #42 convert-on-import instead**: #42 only
  helps NEW imports; existing native `.azw3` libraries stay on Foliate.

---

## Work-item sequencing

**One WI** (Small feature per rule 47's audit-count table → 1 plan audit + 1
PR audit). The three surfaces (theme accessors, mapper descendant reset,
caller wiring of iframe + host) are one cohesive user-facing change ("AZW3
respects the theme"). Splitting iframe-vs-host (finding 2 floats this) is
rejected: the host fill is only a defensive sliver and shares the same
theme-color source and the same `themeCSS(for:)`/`updateUIView` seam — an
auditor reviewing both at once verifies the paper(iframe)/outer(host) token
agreement.

- **WI-1 — thread theme paper/ink into Foliate (mapper descendant reset +
  iframe content + defensive host shell, Photo excluded)** — *behavioral,
  FINAL WI*. Estimated PR size: 3 source files, ~55 LOC + tests. Flips the row
  to `DONE` on merge.

---

## Test catalogue

`vreaderTests/Views/Reader/FoliateSpikeThemeCSSTests.swift` (extend the
existing #70 suite — same `makeStore` helper, add a `theme:` param) plus
`vreaderTests/Services/Foliate/FoliateStyleMapperTests.swift` (if present;
else add the mapper tests to the same suite):

| Test | Asserts |
|---|---|
| `themeCSSEmitsThemeBackgroundRule` (`.paper`) | CSS contains `background: rgb(250,246,234) !important` (paperColor of `.paper`) |
| `themeCSSEmitsThemeTextColorRule` (`.paper`) | CSS contains `color: rgb(29,26,20) !important` (inkColor of `.paper`) |
| `themeCSSDarkThemeEmitsDarkPaperAndInk` (`.dark`) | `background: rgb(33,32,28)` + `color: rgb(216,210,197)` |
| `themeCSSEmitsDescendantColorResetWhenThemed` | when a theme is applied, CSS contains a `… , font { color: inherit !important; }` descendant rule (finding 1) |
| `themeCSSNilStoreEmitsNoColorOrDescendantReset` | `themeCSS(for: nil)` → no `body { background:` / `body { color:` / descendant `color: inherit` rules; font-size-only fallback preserved (regression guard) |
| `themeCSSPhotoThemeEmitsNoColorRules` | store with `theme = .photo` → no color/background/descendant-reset rules (finding 3 exclusion) |
| `themeCSSColorRulesChangeWithTheme` | switching `.paper`→`.dark` changes the emitted bg/ink substrings (live-switch contract) |
| `themeCSSBackgroundShorthandResetsPublisherImage` | the rule uses `background` shorthand (not `background-color`) + `!important` (guards bg-image neutralization) |
| `paperColorCSS/inkColorCSS/outerBackgroundColorCSS valid` (param, all 5 themes) | each is a valid `rgb(...)`/`rgba(...)`; paper/ink equal the emitted iframe rules |
| `hostShellBackgroundColorUsesOuterToken` | `hostShellBackgroundColor(for: .dark store)` == `ReaderThemeV2.dark.backgroundColor` (NOT paperColor); `(for: nil)` == nil; `(for: .photo store)` == nil |
| Mapper-level: `descendantColorResetOmittedWhenTextColorNil` | `FoliateStyleMapper.themeCSS(..., textColor: nil, ...)` emits no `color: inherit` descendant rule |
| Mapper-level: `descendantColorResetIncludesFontElement` | with a textColor, the descendant selector set contains `font` |

The actual `webView.isOpaque` / `backgroundColor` assignment (no WKWebView in
unit tests) is covered by the `hostShellBackgroundColor(for:)` pure seam at
the unit layer and Gate-5 device verification at the visual layer.

---

## Risks + mitigations

| Risk | Likelihood | Mitigation |
|---|---|---|
| **Residual white band Foliate doesn't repaint** that the host-shell fill also misses (foliate-view paints opaque white in that region) | Low (finding 2 says Foliate repaints from the section doc) | Gate-5 device verification on a real native `.azw3`. If a sliver persists, the iframe fix (the user's primary symptom) still landed; residual = documented follow-up (shadow-DOM CSS) — do NOT block the PR. |
| **Publisher sets `background-image` on `html`/wrapper, not `body`** | Low | `setStyles` targets the section body; Foliate normalizes content into `body`. Gate-5 confirms on 被讨厌的勇气 or equivalent. |
| **Per-element publisher ink via inline `style="color:…"`** (not a selector) survives the descendant `color: inherit` | Low | Inline styles beat selector `!important` only when the inline also has `!important`; rare in Kindle content. The `body`+descendant `inherit` covers the overwhelming majority; residual inline-`!important` is out of scope. |
| **`rgb(...)` rejected by a stricter future `sanitizeCSSColor`** | Very low | A test pins the `rgb(...)` rule; a sanitizer regression turns it red. |
| **Photo-theme AZW3 left unthemed** surprises a user | Low | Documented exclusion + a regression test; Photo-for-AZW3 is a separate custom-background feature. |

---

## Backward compat

- **No persistence / schema / format change.** Pure render-time CSS + a
  WKWebView property. Nothing written to disk.
- **EPUB/TXT/MD/PDF unaffected** — only the Foliate caller, the mapper's
  new conditional descendant rule (no-op when `textColor` nil → EPUB/other
  callers never pass it here anyway), and three additive theme accessors
  change.
- **AZW3 books already open** re-tint on the next `updateUIView` (immediately,
  via `@Observable` re-evaluation) — no re-import, no migration.
- **Previews / tests** (nil store) and **Photo theme** keep the exact current
  font-size-only CSS.
- **Rule 51**: applies the EXISTING committed theme paper/ink/outer tokens
  (the same EPUB/TXT/PDF use) to AZW3 — parity with already-designed theming,
  no new chrome, no new control. Confirmed N/A in the row's triage record.

---

## Revision history

- **v1 (2026-06-05)** — initial plan. Gate-2 round 1 (Codex `019e93f6`,
  `gpt-5.4`/high) → **NEEDS REVISION**: 1 High + 2 Medium.
- **v2 (2026-06-05)** — addresses all three round-1 findings:
  - **High (FoliateStyleMapper:64 — descendant color not reset)**: added a
    conditional descendant `color: inherit !important` rule (incl. legacy
    `<font>`), emitted only when `textColor` is applied. Surface area §2.
  - **Medium (paginator.js:1748 — host-frame layer)**: iframe content is now
    the documented PRIMARY fix (Foliate repaints gutters from the section
    doc); host shell demoted to a defensive fallback using the **outer**
    `backgroundColor` token, not `paperColor`. Surface area §3a/§3b.
  - **Medium (ReaderThemeV2:76 — Photo alpha)**: Photo theme explicitly
    excluded from color theming (scope + acceptance + regression test).
- **v2 audit (2026-06-05)** — Gate-2 round 2 (Codex `019e93fd`, `gpt-5.4`/high)
  → **READY TO BUILD**. Zero remaining Critical/High/Medium; all 3 round-1
  findings confirmed resolved (descendant reset matches EPUB + correctly
  gated on `textColor`; iframe CSS primary + host shell demoted to
  outer-token fallback; Photo excluded in the right place; new accessors see
  the private `cssColor`). Gate 2 passes.
