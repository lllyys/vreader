# Feature #70 — Cross-format font-size perceptual calibration

> **Implementation plan** (rule 47, Gate 1). GH issue: #491. Source of truth: `docs/features.md` row #70.
> Status target after Gate 2: `PLANNED`.

## Revision history

| Rev | Date | Change |
|-----|------|--------|
| v1 | 2026-05-19 | Initial Gate-1 draft (feature-cron). |
| v2 | 2026-05-19 | Gate-2 round 1 — Codex audit `019e3ebb`. 1 Critical + 3 High + 2 Medium + 1 Low; all applied (see "Audit fixes applied"). Major change: WI-4 redirected — the live AZW3/MOBI path (`FoliateSpikeView`) has **no font-size wiring at all**, so WI-4 is now first-time plumbing, not a calibrator swap. |
| v3 | 2026-05-19 | Gate-2 round 2 — Codex re-review (same thread `019e3ebb`). All 7 round-1 findings confirmed resolved; AZW3-in-#70 question answered "acceptable". 1 new Medium (WI-4's `updateUIView` early-return on `layoutFlow` would dead-code a font-size-only `themeCSS` diff) + 1 Low (stale "dictionary"/R3 wording) — both applied. |

---

## Problem

vreader supports five reading formats and routes each through a different
renderer. A single stored font-size number (`TypographySettings.fontSize`,
range `12...64`) is piped — **unchanged** — into five rendering systems whose
notion of "size" is not the same physical quantity:

| Format | Live host (verified) | How `fontSize` is consumed | Unit reality |
|--------|----------------------|----------------------------|--------------|
| TXT | `TXTReaderHost` → `TXTReaderContainerView` → `TXTAttributedStringBuilder` (`vreader/Services/TXT/TXTAttributedStringBuilder.swift:35-43`) | `UIFont.systemFont(ofSize: config.fontSize)` then `UIFontMetrics.default.scaledFont(for:)` | UIKit points (≈ screen points), Dynamic-Type-scaled |
| MD | `MDReaderHost` → `MDReaderContainerView` → `MDAttributedStringRenderer` (`vreader/Services/MD/MDAttributedStringRenderer.swift:243,344`) | `UIFont.systemFont(ofSize: config.fontSize)` — **no `UIFontMetrics` wrap** | UIKit points, **not** Dynamic-Type-scaled |
| EPUB | `EPUBReaderHost` → `EPUBReaderContainerView` → `EPUBWebViewBridge` | injected CSS `font-size: <n>px` (`ReaderThemeV2.epubOverrideCSS`, `vreader/Models/ReaderThemeV2+EPUBCSS.swift:108`) | CSS px in a `WKWebView`, compounding with the book stylesheet's own `em`/`%` cascade |
| AZW3/MOBI | `ReaderContainerView` `.foliateWeb` → **`FoliateSpikeView`** → `FoliateSpikeWebView` (`vreader/Views/Reader/FoliateSpikeView.swift:43-54`) | **NOT consumed at all** — `FoliateSpikeWebView` passes only `layoutFlow`; it never reads `typography.fontSize` and never calls `FoliateStyleMapper.themeCSS`. The Foliate font-size slider is currently a **no-op** for AZW3/MOBI. | n/a today — Foliate-js renders the book's own default size |
| PDF | `PDFReaderHost` → `PDFReaderContainerView` → `PDFViewBridge` | **NOT consumed at all** — `pdfView.autoScales = true` (`vreader/Views/Reader/PDFViewBridge.swift:65`); the PDF reader files never read `typography.fontSize`/`TypographySettings` | n/a (page-zoom model, not a text-size model) |

> **Audit correction (v2).** The v1 draft assumed AZW3/MOBI rendered through
> `FoliateReaderContainerView` + `FoliateViewBridge` (which *do* call
> `FoliateStyleMapper.themeCSS` with `Int(store.typography.fontSize)`).
> `FoliateReaderContainerView` exists in `ReaderFormatHosts.swift` but
> **`ReaderContainerView` does not dispatch to it** — `.foliateWeb` routes to
> `FoliateSpikeView`. The spike landed as the live path and
> `FoliateReaderContainerView` is dormant for live rendering. Consequently
> AZW3/MOBI has *no* font-size wiring today, and WI-4 is **first-time
> plumbing**, not a calibrator drop-in. See WI-4.

Two distinct unit families ("UIKit point" vs "CSS px in a WebView"), an
unscaled MD path, an AZW3/MOBI path with no font-size input, and a PDF path
that ignores the setting entirely mean the same slider number renders at
perceptibly different sizes (or no effect) when the user switches formats.
Users report jarring size jumps even though the displayed number never
changed.

Bug #166's *slider-ceiling* half is already shipped (`fontSizeRange`
`12...32` → `12...64`, PR #516). This feature is the *other* half: a
**perceptual normalization layer** so one stored number maps to a
per-renderer value that renders at a consistent perceived size.

### Refined problem statement

Introduce a single, testable `FontSizeCalibrator` that converts the stored
unified font-size value into a per-renderer concrete value, and thread it
through the four text-reflow renderers: TXT, MD, EPUB, and AZW3/MOBI. Three of
those (TXT/MD/EPUB) already consume font size and need their consumption
*re-anchored* through the calibrator; the fourth (AZW3/MOBI via
`FoliateSpikeView`) currently consumes *nothing*, so WI-4 both adds the
font-size wiring **and** routes it through the calibrator in one step. PDF is
explicitly **excluded from calibration** (it has no text-size input) and is
handled honestly — see "PDF disposition" below.

The calibration must be *measurement-grounded*, not guessed: the per-renderer
multipliers are derived from rendered cap-height comparison at a reference
size **at the default content-size category**, captured once and encoded as
constants with a documented derivation, mirroring how Bug #57 chose its CSS
rule from observed behavior. The default-content-size-category restriction is
deliberate — see "Dynamic Type scope" below.

### Dynamic Type scope (audit-driven, v2)

Codex flagged that a *single* multiplier measured once at one size cannot make
MD track TXT across all content-size categories, because the two paths scale
differently:

- **TXT** wraps its base `UIFont` in `UIFontMetrics.default.scaledFont(for:)`
  (`TXTAttributedStringBuilder.swift:43`) — its rendered size is the slider
  value **further scaled by the OS Dynamic Type setting**.
- **MD** uses raw `UIFont.systemFont(ofSize:)`
  (`MDAttributedStringRenderer.swift:243,344`) — **no** Dynamic Type scaling.
- **EPUB / Foliate** WebViews honor neither UIKit Dynamic Type
  (`-webkit-text-size-adjust: 100%` is set, `ReaderThemeV2+EPUBCSS.swift:112`)
  — they render the injected CSS px verbatim.

So a constant multiplier is only exact at the **default content-size
category** (`UIContentSizeCategory.large`), where `UIFontMetrics` is the
identity. At any other category, TXT diverges from MD/EPUB/Foliate by the
Dynamic Type factor — which is *orthogonal* to this feature.

**Decision**: feature #70's calibration target is parity **at the default
content-size category**. This is honest and bounded:

1. The four multipliers are measured and asserted at
   `UIContentSizeCategory.large` (the default — and the value the calibration
   reference run uses).
2. Non-default Dynamic Type is a *pre-existing*, *separate* inconsistency
   (TXT already diverges from EPUB/Foliate under Dynamic Type today, before
   this feature). Feature #70 neither fixes nor worsens it — the calibrator
   re-anchors the *baseline*; the Dynamic Type delta rides on top of TXT
   exactly as it does now.
3. The plan records this as a **known limitation** (see "Risks", R1a) and the
   acceptance criteria + Gate-5 verification explicitly run at the default
   content-size category. A future feature could unify the scaling model
   (e.g. wrap MD in `UIFontMetrics` too, or strip it from TXT) — that is
   called out in "Rejected alternatives" as deliberately deferred.

This keeps WI-1's measurement deterministic (one category, one set of numbers)
and the feature's promise truthful ("consistent at the default text-size
setting") rather than overclaiming universal Dynamic Type parity.

---

## Surface area

### Files ADDED

#### `vreader/Models/FontSizeCalibration.swift` (new, ~95 lines)

Pure value types — no UIKit, no actor isolation, `Sendable`.

```swift
/// The renderer a calibrated font size is destined for.
/// PDF is intentionally absent — PDFKit has no text-size input.
enum CalibrationTarget: String, CaseIterable, Sendable {
    case txt        // UITextView, UIFontMetrics-scaled (the anchor)
    case md         // UITextView, NOT UIFontMetrics-scaled
    case epub       // injected CSS px in WKWebView
    case foliate    // Foliate-js CSS px (AZW3/MOBI)
}

/// A per-target multiplier set. The unified stored value is the
/// "reference" quantity; each target's rendered value is
/// `referenceValue * multiplier(for:)`.
///
/// Audit fix (v2): explicit named fields, NOT a `[CalibrationTarget: Double]`
/// dictionary — a dict permits partial states (a missing key) and defers
/// exhaustiveness to a runtime test. Four fixed fields + a `switch` in
/// `multiplier(for:)` make the compiler enforce completeness.
struct FontSizeCalibrationProfile: Sendable, Equatable {
    /// Multiplier for TXT. 1.0 by definition: TXT/UITextView point is
    /// the anchor. Kept as a stored field (not hard-coded) so the
    /// `Equatable`/round-trip tests treat all four uniformly.
    let txt: Double
    let md: Double
    let epub: Double
    let foliate: Double

    /// Total `switch` — compiler-checked exhaustiveness over the enum.
    func multiplier(for target: CalibrationTarget) -> Double {
        switch target {
        case .txt: return txt
        case .md: return md
        case .epub: return epub
        case .foliate: return foliate
        }
    }

    /// The shipped, measurement-derived profile (see "Calibration
    /// derivation" below). `txt == 1.0` anchor.
    static let standard: FontSizeCalibrationProfile
}
```

#### `vreader/Services/FontSizeCalibrator.swift` (new, ~90 lines)

Pure, stateless mapper. No actor isolation; a plain `struct` with static-style
methods (instance carries the profile so tests can inject a probe profile).

```swift
struct FontSizeCalibrator: Sendable {
    let profile: FontSizeCalibrationProfile

    init(profile: FontSizeCalibrationProfile = .standard)

    /// Map the stored unified font-size value to a target's concrete value.
    /// The result is re-clamped to the target's own legal range so a
    /// calibrated value can never exceed what the renderer accepts
    /// (e.g. Foliate's `8...72`).
    func calibratedSize(
        forUnified unified: CGFloat,
        target: CalibrationTarget
    ) -> CGFloat

    /// Foliate consumes an `Int` px value; this rounds the calibrated
    /// CGFloat and clamps to Foliate's accepted band BEFORE
    /// `FoliateJSEscaper.clampFontSize` sees it (so the clamp is a
    /// belt-and-braces no-op, not a silent value change).
    func calibratedFoliateSize(forUnified unified: CGFloat) -> Int
}
```

`calibratedSize` clamps per target. The clamp ranges live as constants on
`FontSizeCalibrator` and are sourced from the *existing* renderer limits:
TXT/MD/EPUB → `TypographySettings.fontSizeRange` (`12...64`); Foliate →
`8...72` (the band `FoliateJSEscaper.clampFontSize` already enforces). No new
range is invented; the calibrator just refuses to emit a value the renderer
would silently reject.

### Files MODIFIED

#### `vreader/Services/ReaderSettingsStore.swift` (~+28 lines)

`ReaderSettingsStore` is the single fan-out point: `txtViewConfig`,
`mdRenderConfig`, and the EPUB/Foliate CSS calls all originate here or just
downstream. Add one calibrator and route every *renderer-bound* per-renderer
font-size read through it. **No new public stored property** —
`typography.fontSize` stays the unified value; calibration happens at the
per-renderer accessor.

- Add `let calibrator = FontSizeCalibrator()` (stateless, default profile).
  Exposed `internal` (not `private`) so `EPUBReaderContainerView` /
  `FoliateSpikeView` can read it — see those files. It is a `Sendable` value
  type and the store is `@MainActor`, so the exposed `let` is safe.
- `txtViewConfig` (`:216`): `c.fontSize = calibrator.calibratedSize(forUnified: typography.fontSize, target: .txt)`.
  Because `.txt` multiplier is `1.0`, this is behavior-preserving for TXT — it
  re-anchors the system on the existing TXT appearance rather than changing it.
- `mdRenderConfig` (`:199`): `fontSize: calibrator.calibratedSize(forUnified: typography.fontSize, target: .md)`.

**Line spacing / CJK letter spacing — audit-revised approach (v2).** These two
derive from `typography.fontSize` and are *ratios* of font size, so a
calibrated body glyph must get a base-matched leading. The v1 plan proposed
converting the existing `lineSpacingPoints` / `cjkLetterSpacing` *properties*
to `(for:)` *functions*. Codex flagged this as underscoped and semantically
muddy: those properties have **four** call sites, not two —

| Call site | Role |
|-----------|------|
| `ReaderSettingsStore.swift:208` (`mdRenderConfig`) | renderer config — MD |
| `ReaderSettingsStore.swift:217-218` (`txtViewConfig`) | renderer config — TXT |
| `ReaderSettingsPanel.swift:637-638` (`.tracking` / `.lineSpacing` on the live preview `Text`) | settings **preview**, not a renderer |

— and the settings-panel preview is not a renderer-targeted surface, so a
mandatory `(for:)` argument there is meaningless.

**Revised decision**: do **not** change the public property signatures.

- Keep `var lineSpacingPoints` and `var cjkLetterSpacing` exactly as they are
  (unified-value-based) — they remain the **anchor / preview metrics**, used
  unchanged by `ReaderSettingsPanel`'s preview `Text`. The preview shows a
  TXT-anchored sample, so the anchor metric is the right one for it.
- Add two `private` per-target helpers used **only** by the renderer configs:
  ```swift
  private func calibratedLineSpacingPoints(for target: CalibrationTarget) -> CGFloat {
      let size = calibrator.calibratedSize(forUnified: typography.fontSize, target: target)
      return size * (typography.lineSpacing - 1.0)
  }
  private func calibratedCJKLetterSpacing(for target: CalibrationTarget) -> CGFloat {
      guard typography.cjkSpacing else { return 0 }
      return calibrator.calibratedSize(forUnified: typography.fontSize, target: target) * 0.05
  }
  ```
- `txtViewConfig` uses `calibratedLineSpacingPoints(for: .txt)` /
  `calibratedCJKLetterSpacing(for: .txt)`; `mdRenderConfig` uses the `.md`
  variants. Since `.txt` multiplier is `1.0`, `calibratedLineSpacingPoints(for: .txt)`
  is numerically identical to today's `lineSpacingPoints` — TXT leading is
  behavior-preserving; MD leading shifts in lockstep with MD's calibrated
  glyph.

This keeps the public API stable (zero churn in `ReaderSettingsPanel` and zero
churn in any existing test that reads `lineSpacingPoints`), confines the new
behavior to two private helpers, and removes the property→function refactor
from the WI entirely (Medium finding #5).

- `uiFont` (`:184`): used by chrome/measurement; left unchanged (it already
  reads `typography.fontSize` directly — equivalent to the `.txt` anchor).
- The EPUB and AZW3/MOBI paths do **not** read their font size from
  `ReaderSettingsStore`'s config accessors — they read `typography.fontSize`
  inside their container views. See the next two files.

#### `vreader/Views/Reader/EPUBReaderContainerView.swift` (~+6 lines)

`EPUBReaderContainerView.swift:392-405` builds the theme CSS with
`fontSize: $0.typography.fontSize`. Change to feed the calibrated EPUB value:

```swift
fontSize: settingsStore.calibrator.calibratedSize(
    forUnified: $0.typography.fontSize, target: .epub),
```

`calibrator` is the `internal let` on `ReaderSettingsStore`. The
`letterSpacing` line (`:396`) currently divides `fontSize` by itself (a known
no-op producing `0.05`); leave that line untouched — it does not depend on
the calibrated value and changing it is out of scope.

#### AZW3/MOBI — `FoliateSpikeView.swift` + `FoliateSpikeWebView` (~+30 lines, WI-4 — first-time plumbing)

**Audit-corrected (v2).** The live AZW3/MOBI host is `FoliateSpikeView`
(`ReaderContainerView.swift:684`), whose nested `FoliateSpikeWebView`
(`FoliateSpikeView.swift:101`) currently passes **only** `layoutFlow` to the
spike WebView — it has no `themeCSS`/font-size wiring. `FoliateStyleMapper`
and `FoliateViewBridge` *do* know how to emit `font-size` CSS, but they are
wired to the **dormant** `FoliateReaderContainerView` host, not the live
spike. So WI-4 is **first-time font-size plumbing for AZW3/MOBI**, not a
calibrator swap.

WI-4 threads a calibrated `themeCSS` string into the spike, mirroring how
`FoliateViewBridge` already does it for the dormant host:

- `FoliateSpikeView` computes a `themeCSS` string:
  ```swift
  FoliateStyleMapper.themeCSS(
      fontSize: settingsStore?.calibrator.calibratedFoliateSize(
          forUnified: settingsStore?.typography.fontSize ?? 18) ?? 18,
      lineHeight: Double(settingsStore?.typography.lineSpacing ?? 1.4),
      fontFamily: nil)              // family stays book-default this WI
  ```
  and passes it into `FoliateSpikeWebView`.
- `FoliateSpikeWebView` gains a `themeCSS: String?` stored field, and its
  `Coordinator` gains a `currentThemeCSS: String?` (mirroring the existing
  `currentLayoutFlow`).

> **Audit fix (v2 round 2) — `updateUIView` control flow must be
> restructured, not appended to.** `FoliateSpikeWebView.updateUIView`
> currently *early-returns* unless `layoutFlow` changed
> (`FoliateSpikeView.swift:219`: `guard coordinator.currentLayoutFlow != safeFlow else { return }`).
> A font-size-only slider change leaves `layoutFlow` unchanged, so a
> `themeCSS` diff appended *after* that guard would **never fire**. WI-4 MUST
> rewrite `updateUIView` to match `FoliateViewBridge.swift:209-237`'s shape:
> 1. compute both `safeFlow` and `themeCSS` up front;
> 2. **no early `return`** — instead diff each independently:
>    `if coordinator.currentLayoutFlow != safeFlow { … apply layout … }`
>    and `if coordinator.currentThemeCSS != themeCSS { … apply setStyles … }`;
> 3. each branch updates its own `current*` coordinator field.
> This way a font-size change with unchanged layout still pushes
> `setStyles`, and a layout change with unchanged font still pushes
> `setLayout`. The existing layout-stash-before-ready behavior
> (`window.__vreaderTargetFlow`) is preserved inside the layout branch.

- The `themeCSS` branch pushes via `readerAPI.setStyles('<escaped>')` — the
  **exact** mechanism `FoliateViewBridge.swift:218-225` already uses (Foliate-js
  exposes the same `setStyles` JS API to both webviews; the spike's WebView
  loads the same `foliate-bundle.js` and exposes the same `readerAPI`). JS
  interpolation goes through `FoliateJSEscaper` per rule 50's bridge-safety
  convention — the same escaper `FoliateViewBridge` uses.
- **Pre-ready handling**: if `themeCSS` changes before `isBookReady`, WI-4
  also pushes `setStyles` once from the spike's `onBookReady` callback (the
  belt-and-braces pattern — Foliate-js's `setStyles` is a no-op before
  `readerAPI.init({})` resolves, so the post-ready push guarantees the
  initial calibrated size lands).
- `calibratedFoliateSize` already rounds + clamps to `8...72`, so
  `FoliateStyleMapper`'s internal `FoliateJSEscaper.clampFontSize` is a
  verified no-op.

> **Scope boundary for WI-4.** WI-4 wires font-size (and the line-height that
> rides with it) only. It does **not** also wire theme colors / font-family
> into the spike — AZW3/MOBI theme-color parity is a *separate* gap (the spike
> never themed at all) and pulling it in would balloon the WI. WI-4 emits a
> `themeCSS` that sets `font-size` + `line-height`; colors/family are left at
> Foliate-js defaults exactly as today. If the user later wants AZW3/MOBI
> theme-color parity, that is its own feature row. This keeps WI-4 a small,
> focused, single-responsibility PR.

This raises a real question — *should AZW3/MOBI font-size wiring even live
under feature #70?* It is arguably a missing-capability bug ("the font-size
slider does nothing for AZW3/MOBI") rather than a calibration concern. The
plan keeps it inside #70 because: (a) the calibration layer is the natural and
only consumer of a unified→Foliate mapping, (b) splitting it into a separate
bug row would still block #70's "consistent across all reflow formats"
acceptance criterion until that bug shipped, creating an artificial
cross-tracker dependency, and (c) the wiring is genuinely small (~30 lines,
one `setStyles` call mirroring an existing one). The "files OUT of scope"
note records the deliberate carve-out of *theme-color* parity so the
boundary is unambiguous. **Audit re-confirm requested**: is folding the
first-time wiring into #70 acceptable, or should it be a prerequisite bug
row? (Resolved in round 2 — see "Audit fixes applied".)

### Files OUT of scope

- **`vreader/Models/TypographySettings.swift`** — `fontSizeRange` and the
  stored `fontSize`/clamp logic are NOT touched. The stored value stays the
  unified value. The slider-ceiling raise (`12...32` → `12...64`) is Bug #166's
  shipped half — explicitly out of scope.
- **`vreader/Views/Reader/ReaderSettingsPanel.swift`** — the font-size slider
  (`:390`) binds to `typography.fontSize` and keeps showing the unified
  number; the panel's preview `Text` (`:635-639`) keeps reading the unchanged
  `lineSpacingPoints` / `cjkLetterSpacing` properties. The panel UI does not
  change; this feature is a render-path transform, not a UI feature. No new
  visible element ⇒ rule 51 (no self-designed UI) is not engaged.
- **`ReaderSettingsStore.lineSpacingPoints` / `cjkLetterSpacing` public
  properties** — signatures unchanged (v2 audit revision; see the
  `ReaderSettingsStore` surface-area note). Only two new `private` per-target
  helpers are added.
- **`FoliateReaderContainerView` + `FoliateViewBridge` + `FoliateReaderHost`**
  — the *dormant* AZW3/MOBI host stack (exists in `ReaderFormatHosts.swift`
  but `ReaderContainerView` does not dispatch to it). NOT modified — touching
  dead-for-live-dispatch code would be misleading. WI-4 wires the *live*
  `FoliateSpikeView` path instead.
- **AZW3/MOBI theme-color + font-family parity** — the spike never themed
  colors or family at all; WI-4 deliberately wires *only* font-size +
  line-height. Theme-color parity for AZW3/MOBI is a separate gap → its own
  future row, not feature #70.
- **PDF (`PDFReaderContainerView.swift`, `PDFViewBridge.swift`,
  `PDFReaderViewModel.swift`)** — see "PDF disposition". No PDF file is
  modified.
- **`FoliateJSEscaper.clampFontSize`** — kept as the existing safety clamp; not
  modified, just made redundant by the calibrator's own clamp.
- **`ChapterStartTypography` / drop-cap CSS / chapter-start decorators** —
  drop-cap sizes are `em`-relative (`dropCapCSSFontSizeEm`), so they ride the
  calibrated body size automatically. No change needed and none made.
- **AI / search / library / persistence layers** — untouched.
- **`UnifiedTextRenderer` / `PaginationCache`** — pagination keys already
  include `config.fontSize`; since `txtViewConfig.fontSize` becomes the
  calibrated value, cache keys stay correct with no change. (Verified: cache
  key string at `TXTReaderContainerView.swift:148` interpolates
  `config.fontSize` — the post-calibration value flows through.)

### PDF disposition (explicit)

PDFKit renders the document's own embedded text at a document-fixed size and
exposes only a *page zoom* (`autoScales` / `scaleFactor`), not a text-size
input. There is no honest way to map a unified font-size point value to PDF
text size. Therefore:

- PDF is **not** a `CalibrationTarget` case — the enum cannot tempt a future
  caller into a meaningless mapping.
- The feature does **not** make the font-size slider affect PDF. That is a
  separate capability (PDF reflow / zoom-by-font-size) and is **not** in this
  feature's scope or acceptance criteria.
- The plan documents this so a reader of the acceptance criteria does not
  expect PDF parity. "Consistent across all formats" in the row's acceptance
  sketch is refined to "consistent across all *text-reflow* formats (TXT, MD,
  EPUB, AZW3/MOBI)"; PDF is consistent-by-exclusion.

---

## Prior art / project precedent / rejected alternatives

### Bug #57 — EPUB-vs-TXT pairwise calibration (FIXED, the direct precedent)

Bug #57 ("EPUB and TXT font sizes render differently at same setting value")
was fixed with a **CSS-cascade neutralization**, not a numeric multiplier.

**Audit correction (v2).** The v1 draft mis-stated the rule as
`body * { font-size: inherit !important }`. The *actual* live CSS in
`ReaderThemeV2+EPUBCSS.swift` is:

- `p, div, span, li, td, th, dd, dt, blockquote, figcaption { font-size:
  inherit !important; line-height: inherit !important; color: inherit
  !important; }` (`:127-131`) — flattens the cascade for a **defined list of
  text elements**, not universally.
- `h1,h2,h3,h4,h5,h6 { font-size: revert !important; … }` (`:132-136`) —
  headings keep the book's own relative sizing.
- `body * { font-family: inherit !important; }` (`:137-139`) — the `body *`
  universal selector is used **only for `font-family`**, not `font-size`.

That set makes the book stylesheet stop *compounding* the injected
`font-size` for the enumerated text elements — they inherit the one injected
size instead of multiplying it by the book's own `em`/`%` rules.

**What we reuse**: those CSS rules stay — they are load-bearing and untouched.
The calibrator does **not** replace them. Bug #57 made EPUB's *internal*
cascade predictable (for the enumerated element list); feature #70 makes the
*cross-renderer* baseline consistent. They are orthogonal and both required.
**No-regression-vs-#57** is an explicit test target — and the test asserts the
*real* selector list above, not the v1 mis-statement (see catalogue,
`ReaderThemeV2EPUBCSSCalibrationTests`).

**Known limitation inherited from #57**: the cascade is flattened only for the
enumerated text elements. A book that styles `font-size` on a tag *outside*
that list (or with its own `!important` on a descendant) can still compound —
that is pre-existing and outside feature #70's control (see Risks R2).

**What we reject from #57's approach**: #57 was *pairwise* (EPUB tuned against
TXT, by hand, at the CSS layer). Extending the pairwise approach to N formats
is O(N²) hand-tuning and has no single source of truth. We reject pairwise in
favor of a **hub-and-spoke** model: TXT/UITextView point is the *anchor*
(multiplier `1.0`), every other renderer has one multiplier *to the anchor*,
and cross-format consistency falls out transitively. This is why
`FontSizeCalibrationProfile.standard` has `txt: 1.0`.

### Project precedent — `ReaderSettingsStore` as the per-renderer fan-out

`ReaderSettingsStore` already converts `typography` into renderer-specific
shapes: `txtViewConfig` (`TXTViewConfig`), `mdRenderConfig` (`MDRenderConfig`),
`uiFont`, `lineSpacingPoints`. Adding a calibration step is consistent with the
existing pattern — the store is *already* the place that knows "this renderer
wants its config like *this*". We are not adding a new architectural layer;
we are adding one pure transform inside the existing fan-out.

`FoliateStyleMapper.themeCSS` and `ReaderThemeV2.epubOverrideCSS` already take
`fontSize` as a parameter — the calibrated value drops into the existing
parameter with no signature change to those functions.

### Project precedent — pure value-type + pure mapper, mock-at-boundary

`DocumentFingerprint`, `Locator`, `SummaryScope`/`ChapterBounds` (feature #69
WI-1) are all pure `Sendable` value types with deterministic logic and
parameterized Swift Testing suites. `FontSizeCalibration` +
`FontSizeCalibrator` follow that mold exactly — no I/O, no actor, fully unit
testable with `@Test(arguments:)`.

### Rejected alternatives

1. **Store a calibrated value per renderer in persistence.** Rejected —
   multiplies the source of truth by 4, breaks the moment a multiplier is
   re-tuned, and complicates `PerBookSettings`. The stored value stays unified;
   calibration is a *render-time* transform.
2. **Calibrate inside each renderer (4 separate edits to TXT/MD/EPUB/Foliate
   builders).** Rejected — scatters the multiplier knowledge across four files,
   each of which would need its own test. Centralizing in
   `ReaderSettingsStore`'s fan-out keeps one transform, one test target.
3. **Use a physical-units model (convert pt → mm → CSS px via DPI).** Rejected
   as over-engineering for this iteration — device DPI is available but the
   WebView's CSS px is already a 96-dpi-reference logical unit, and the
   *perceived* mismatch is dominated by font-metric and cascade differences,
   not raw DPI. A measurement-derived multiplier captures the real gap with far
   less machinery. Documented as a possible future refinement (see Risks).
4. **Change `TypographySettings.fontSize` to carry per-renderer values.**
   Rejected — that is alternative 1 in disguise and breaks Codable backward
   compat.
5. **Make the multipliers user-tunable in Settings.** Rejected — that is a
   *UI feature* (needs a designed surface, engages rule 51) and is a different
   feature row. This feature ships a fixed, measurement-derived profile.
6. **Unify the Dynamic Type scaling model (wrap MD in `UIFontMetrics` too, or
   strip `UIFontMetrics` from TXT) so calibration holds across all
   content-size categories.** Deliberately deferred. It is a real follow-on —
   without it, parity is exact only at the default content-size category (see
   "Dynamic Type scope") — but it is a behavior change to *every* TXT/MD
   reader independent of calibration, with its own verification matrix across
   ~12 content-size categories. Folding it into #70 would balloon scope and
   couple two unrelated changes. Feature #70 ships default-category parity;
   the Dynamic Type unification is a candidate future feature row.
7. **Add a `CalibrationTarget.pdf` case for completeness.** Rejected — PDFKit
   has no text-size input; a `.pdf` case would invite a future caller to
   request a meaningless mapping. The enum's absence of PDF is intentional API
   design (see PDF disposition).

---

## Calibration derivation (how the multipliers are obtained)

The shipped `FontSizeCalibrationProfile.standard` multipliers are **not
guessed**. WI-1's "measurement" deliverable is a one-time, reproducible
procedure recorded in the plan and in the test file's doc comment:

1. Render a fixed reference string at unified size `24` in each of the four
   renderers on iPhone 17 Pro Simulator (the DebugBridge `seed` + `open`
   fixtures already exist per format).
2. Capture the rendered cap-height in device pixels (TXT via
   `font.capHeight`; EPUB/Foliate via a one-off `getBoundingClientRect` on a
   measurement span injected by a throwaway debug eval; MD via `font.capHeight`).
3. The multiplier for target *T* is `capHeight(txt) / capHeight(T)` — i.e. the
   factor that makes *T*'s rendered glyph match TXT's.
4. Encode the four ratios as the four `Double` fields of
   `FontSizeCalibrationProfile.standard` (`txt`/`md`/`epub`/`foliate`); `txt`
   is `1.0` by construction.

The procedure and the captured numbers go into the WI-1 commit message and the
`FontSizeCalibratorTests` file header so the constants are auditable and
re-derivable. The *measurement run itself* is dev tooling (DebugBridge eval),
not shipped code — the shipped artifact is the four constant fields.

> If the measurement run cannot be completed before WI-1's PR (e.g. simulator
> unavailable), WI-1 ships with the four fields populated from the
> **conservative identity-leaning estimates** documented inline (EPUB/Foliate
> WebViews render CSS px slightly smaller than the equivalent UIKit point at
> default metrics, so the WebView multipliers are ≥ 1.0; MD ≈ 1.0 since it is
> also UITextView) and the WI is explicitly marked "estimates pending Gate-5
> measurement refinement". Gate 5's behavioral verification then either
> confirms or re-tunes them in a follow-up patch. The architecture does not
> change either way — only the four field literals in
> `FontSizeCalibrationProfile.standard`.

---

## Work-item sequencing

Four WIs. Each is one PR.

### WI-1 — `FontSizeCalibration` value types + `FontSizeCalibrator` mapper — **foundational**

- Add `FontSizeCalibration.swift` (`CalibrationTarget`,
  `FontSizeCalibrationProfile`).
- Add `FontSizeCalibrator.swift` (the pure mapper + per-target clamp).
- `FontSizeCalibrationProfile.standard` populated (measurement-derived or
  documented estimates per "Calibration derivation").
- No renderer touched yet — pure types only, zero user-observable change.
- **Tier: foundational** (pure value types + pure function, no app behavior
  changes). Gate 5 = unit + audit, no device verify.
- Est. PR size: small (~200 new lines + ~120 test lines).

### WI-2 — Route TXT + MD through the calibrator (`ReaderSettingsStore`) — **behavioral**

- Add `let calibrator = FontSizeCalibrator()` (`internal`) to
  `ReaderSettingsStore`.
- `txtViewConfig.fontSize` and `mdRenderConfig.fontSize` route through
  `calibrator.calibratedSize`.
- Add the two `private` per-target helpers `calibratedLineSpacingPoints(for:)`
  / `calibratedCJKLetterSpacing(for:)`; `txtViewConfig` uses the `.txt`
  variants, `mdRenderConfig` the `.md` variants. **No change** to the public
  `lineSpacingPoints` / `cjkLetterSpacing` properties — the `ReaderSettingsPanel`
  preview keeps reading them unchanged (audit fix — no property→function
  refactor, no `ReaderSettingsPanel` churn).
- TXT is behavior-preserving (`.txt` multiplier `1.0`); MD shifts to match TXT.
- **Tier: behavioral** (changes MD reader rendering — TXT unchanged but the
  MD glyph + leading move). Gate 5 = slice verify: open a TXT and an MD
  fixture, confirm TXT unchanged and MD now matches TXT at the same slider
  value, at the default content-size category.
- Est. PR size: small (~28 modified/added lines in one file + ~90 test lines).

### WI-3 — Route EPUB through the calibrator (`EPUBReaderContainerView`) — **behavioral**

- `EPUBReaderContainerView` feeds `settingsStore.calibrator.calibratedSize(…, target: .epub)`
  into `epubOverrideCSS` (reads the `internal` `calibrator` exposed in WI-2).
- **Tier: behavioral** (changes EPUB reader rendering). Gate 5 = slice verify
  with a fixture EPUB; **explicit no-regression-vs-Bug-#57 check** — the
  `p, div, span, … { font-size: inherit !important }` rule and the
  `h1-h6 { font-size: revert !important }` rule must still be present and the
  EPUB internal cascade for those elements must still be flat.
- Est. PR size: small (~6 modified lines + ~60 test lines).

### WI-4 — AZW3/MOBI font-size wiring through the calibrator + final acceptance — **behavioral (final WI)**

- **First-time plumbing** (audit-corrected): `FoliateSpikeView` computes a
  calibrated `themeCSS` (`font-size` + `line-height`) and threads it into
  `FoliateSpikeWebView`, which gains a `themeCSS: String?` field + a
  `Coordinator.currentThemeCSS` and pushes it via
  `readerAPI.setStyles('<FoliateJSEscaper-escaped>')` — mirroring
  `FoliateViewBridge.swift:218-225`. Font size comes from
  `calibrator.calibratedFoliateSize(forUnified:)`.
- **`FoliateSpikeWebView.updateUIView` control flow is restructured** (v2
  round-2 audit fix): the existing `guard currentLayoutFlow != safeFlow else
  { return }` early-return is removed and replaced with two independent
  `if`-diff branches (layout, theme) so a font-size-only change still fires
  `setStyles` when `layoutFlow` is unchanged. See the surface-area note for
  the exact required shape.
- Also pushes `setStyles` once on `onBookReady` (pre-ready belt-and-braces).
- Does NOT wire theme colors / font-family into the spike (separate scope —
  see "files OUT of scope").
- Confirm `FoliateJSEscaper.clampFontSize` is now a verified no-op for all
  in-range calibrated values.
- **Final WI** — its merge flips the row to `DONE`. Gate 5 = full acceptance
  pass: open one fixture of *each* of TXT/MD/EPUB/AZW3 at the same slider
  value (default content-size category), confirm perceptually consistent
  rendered size across all four; confirm AZW3/MOBI now *responds* to the
  slider at all (it didn't before); confirm PDF behavior unchanged; confirm
  Bug #57 has not regressed.
- Est. PR size: small-to-medium (~30 modified/added lines across
  `FoliateSpikeView.swift` + ~80 test lines). Larger than WI-3 because it
  adds a new wiring path, not just a value swap.

Sequencing rationale: WI-1 is the foundation everything imports. WI-2 is the
only WI that *writes* `ReaderSettingsStore` (adds `calibrator` + the two
private helpers); WI-3 and WI-4 only *read* the `internal calibrator`, so
WI-3/WI-4 depend on WI-2 having landed the `calibrator` property but touch
disjoint files otherwise (`EPUBReaderContainerView.swift` vs
`FoliateSpikeView.swift`). WI-4 is sequenced last because it is the final
acceptance WI and is the largest (first-time wiring). The row's note already
says implementation is dispatched separately later because these reader files
overlap with other in-flight agents — so this plan stops at `PLANNED`.

---

## Test catalogue

All new tests are Swift Testing (`import Testing`, `@Test`, `#expect`) per
rule 10 — pure value types and a pure mapper, the exact case Swift Testing is
the default for.

### `vreaderTests/Models/FontSizeCalibrationTests.swift` (WI-1, ~12 cases)

- `CalibrationTarget` has exactly four cases (PDF intentionally absent) —
  guards the "PDF is not calibratable" decision against accidental extension.
- `FontSizeCalibrationProfile.standard.multiplier(for: .txt) == 1.0` — the
  anchor invariant.
- `multiplier(for:)` returns the matching field for every target —
  `@Test(arguments: CalibrationTarget.allCases)` — the total `switch` means
  there is no missing-case path, but the parameterized test still proves each
  case maps to the right field.
- All four multipliers in `.standard` are finite and `> 0`.
- `Equatable` round-trip for `FontSizeCalibrationProfile` (a probe profile
  with four distinct field values round-trips).

### `vreaderTests/Services/FontSizeCalibratorTests.swift` (WI-1, ~16 cases)

File header documents the measurement derivation (per "Calibration
derivation").

- `calibratedSize(forUnified: 24, target: .txt) == 24` — anchor is identity.
- Parameterized: for each target, `calibratedSize(forUnified: 24, …)` ==
  `24 * multiplier` — `@Test(arguments:)`.
- **Lower-bound clamp**: `calibratedSize(forUnified: 12, target: .epub)` with a
  multiplier `< 1.0` never drops below `12` (TXT/MD/EPUB min).
- **Upper-bound clamp**: `calibratedSize(forUnified: 64, target: .epub)` with a
  multiplier `> 1.0` never exceeds `64`.
- **Foliate clamp**: `calibratedFoliateSize(forUnified: 64)` never exceeds
  `72`; `calibratedFoliateSize(forUnified: 12)` never drops below `8`.
- `calibratedFoliateSize` returns a rounded `Int` (e.g. `23.6 → 24`).
- Edge: `calibratedSize` with a probe profile of all-`1.0` multipliers is the
  identity for every target (proves the transform is pure).
- Edge: extreme injected multiplier (probe profile) still clamps — proves the
  clamp is unconditional, not multiplier-trusting.
- Boundary: unified value exactly at `12` and exactly at `64`.

### `vreaderTests/Services/ReaderSettingsStoreCalibrationTests.swift` (WI-2, ~10 cases)

`@MainActor` (the store is `@MainActor @Observable`).

- `txtViewConfig.fontSize` for unified `24` == `24` (TXT anchor preserved —
  **this is the no-regression guard for the existing TXT appearance**).
- `mdRenderConfig.fontSize` for unified `24` == `24 * mdMultiplier` (MD now
  calibrated).
- `txtViewConfig.lineSpacing` equals today's `lineSpacingPoints` formula for
  unified `24` (TXT leading behavior-preserving — `.txt` multiplier `1.0`).
- `mdRenderConfig.lineSpacing` uses the `.md`-calibrated base — differs from
  `txtViewConfig.lineSpacing` exactly when the MD multiplier ≠ 1.
- `txtViewConfig.letterSpacing` / `mdRenderConfig` CJK spacing parity with the
  per-target calibrated base; `cjkSpacing == false` ⇒ `0` for both.
- The public `lineSpacingPoints` / `cjkLetterSpacing` properties are
  **unchanged** — assert they still equal the unified-value formula (guards
  the `ReaderSettingsPanel` preview).
- Changing `typography.fontSize` re-derives both configs (observation still
  fires).
- Boundary: unified `12` and `64` flow through both configs clamped.

### `vreaderTests/Models/ReaderThemeV2EPUBCSSCalibrationTests.swift` (WI-3, ~8 cases)

- `epubOverrideCSS(fontSize: calibratedEpubValue, …)` emits
  `font-size: <calibratedValue>px` — the calibrated value reaches the CSS.
- **No-regression vs Bug #57** (asserts the *real* selectors per the v2 audit
  correction): the emitted CSS still contains `font-size: inherit !important`
  inside the `p, div, span, li, td, th, dd, dt, blockquote, figcaption` rule,
  AND `font-size: revert !important` inside the `h1,h2,h3,h4,h5,h6` rule, AND
  `body * { font-family: inherit !important }` (the `body *` selector applies
  to `font-family` only — the test must NOT assert `body * { font-size }`).
  This is the literal "no regression in bug #57" acceptance item.
- The injected `html, body` `font-size` is the calibrated value, not the raw
  unified value, for a non-`1.0` EPUB multiplier.
- Boundary: calibrated value at the clamp edges still produces valid CSS.

### `vreaderTests/Views/Reader/FoliateSpikeThemeCSSTests.swift` (WI-4, ~10 cases)

Tests the WI-4 wiring at the pure-logic seam — the calibrated-CSS string
construction, not the WebView. (`FoliateSpikeView`'s `themeCSS` computation is
extracted to a small testable pure helper, consistent with the existing
`FoliateContainerErrorLogic` / `FoliateSelectionMapper` extraction pattern
noted in `FoliateReaderContainerView.swift`'s header.)

- The helper builds a `themeCSS` whose `body { font-size: … }` is the
  **calibrated Foliate value** for the given unified size, not the raw value.
- `FoliateStyleMapper.themeCSS(fontSize: calibratedFoliateValue, …)` emits
  `body { font-size: <calibratedValue>px … }`.
- The calibrated Foliate value is already inside `8...72`, so
  `FoliateJSEscaper.clampFontSize` leaves it **unchanged** — assert
  `clampFontSize(calibratedFoliateSize(forUnified: u)) == calibratedFoliateSize(forUnified: u)`
  for `u` across the full `12...64` unified range (the "verified no-op" claim).
- The `setStyles` JS payload is escaped via `FoliateJSEscaper` (bridge-safety
  per rule 50) — assert a CSS string with a quote/backslash is escaped.
- `nil` `settingsStore` ⇒ the helper falls back to the documented default
  (unified `18`) without crashing.
- Cross-format consistency assertion: at unified `24`, the ratio
  `calibratedSize(.epub) / 24`, `calibratedSize(.md) / 24`, and
  `Double(calibratedFoliateSize(forUnified: 24)) / 24` are all within a
  documented tolerance band of each other and of TXT (`1.0`) — the
  *consistency* property the feature exists to deliver, asserted at the value
  layer.

### Existing suites that must stay green (regression surface)

- `TypographySettingsTests` — untouched model; must stay green.
- `FoliateStyleMapperTests` — `themeCSS` signature unchanged; existing
  `themeCSSAcceptsAppMaxFontSize64` and pass-through tests stay green.
- `ReaderSettingsStore` existing tests / `PerBookSettings` tests — **no
  signature change** (v2 audit revision: the `lineSpacingPoints` /
  `cjkLetterSpacing` properties are kept; only `txtViewConfig.fontSize` /
  `mdRenderConfig.fontSize` / their leading values change numerically). Any
  existing test asserting an *exact* `txtViewConfig.fontSize` survives because
  `.txt` multiplier is `1.0`; an existing test asserting an exact
  `mdRenderConfig.fontSize` would shift by the MD multiplier and is updated in
  WI-2 if one exists (WI-2's first step greps for it).
- `EPUBWebViewBridge` / EPUB CSS tests — `epubOverrideCSS` signature
  unchanged; the injected `font-size` value shifts by the EPUB multiplier
  (≠ 1) — any existing exact-value assertion is updated in WI-3.

---

## Risks + mitigations

| # | Risk | Mitigation |
|---|------|------------|
| R1 | The measurement-derived multipliers are wrong / device-dependent, so calibration "consistency" is itself off. | Multipliers derived from on-simulator cap-height measurement at a reference size + the default content-size category, recorded reproducibly (WI-1 header + commit). Gate-5 behavioral verification re-checks perceived consistency on-device; if off, re-tune is a one-line literal change to `FontSizeCalibrationProfile.standard` — architecture unaffected. |
| R1a | Calibration is exact only at the default content-size category — TXT (via `UIFontMetrics`) diverges from MD/EPUB/Foliate (no Dynamic Type) under non-default Dynamic Type. | Accepted, documented as a **known limitation** (see "Dynamic Type scope"). It is *pre-existing* — TXT already diverges from EPUB/Foliate under Dynamic Type today; feature #70 neither introduces nor worsens it. Acceptance + Gate-5 verification run explicitly at the default category. Full Dynamic-Type unification is a deliberately deferred future feature (Rejected alternative 6). |
| R2 | EPUB book stylesheets with aggressive `font-size` rules still compound despite Bug #57's `inherit` rule (some books use `!important` on their own elements, or use absolute `px` on descendants). | Out of this feature's control and pre-existing — Bug #57's rule is the mitigation already in place. The calibrator only sets the *baseline*; it does not promise to defeat a hostile book stylesheet. Documented as a known limitation, not a regression. |
| R3 | An existing test asserts an exact `mdRenderConfig.fontSize` / EPUB-injected `font-size`; once MD/EPUB calibrate (multiplier ≠ 1) that value shifts and the test fails. | WI-2 (MD) and WI-3 (EPUB) each begin by grepping their test suite for exact-value assertions on the calibrated field and updating them to the post-calibration value in the same WI. TXT exact-value assertions are unaffected (`.txt` multiplier `1.0`). The public `lineSpacingPoints` / `cjkLetterSpacing` properties are NOT changed, so any test reading them stays green (v2 audit revision — the property→function refactor was dropped). |
| R4 | MD shifting size (multiplier ≠ 1) is a *visible* change to existing MD readers — a user mid-book sees their MD text resize on update. | This is the intended fix (MD currently mis-renders relative to the unified value). It is a one-time shift toward *correct*, documented in the PR and release notes. The unified stored number is unchanged, so the slider position is unchanged — only the rendered glyph corrects. |
| R5 | PaginationCache keys could go stale if a calibrated value collides with a previously-cached raw value. | Cache key interpolates `config.fontSize`, which becomes the *calibrated* value uniformly — old raw-value-keyed entries simply never match and are recomputed once. No corruption, only a one-time recompute. Covered by leaving `PaginationCache` untouched (verified in "files OUT of scope"). |
| R6 | Foliate's `Int` rounding of a calibrated CGFloat introduces a sub-pixel inconsistency vs the EPUB path (which keeps a `.1f` float). | Accepted — Foliate-js's `setStyles` API takes integer px; sub-point precision is below perceptual threshold. The consistency tolerance band in `FoliateSpikeThemeCSSTests` accounts for ±0.5px rounding. |
| R7 | WI-4 is first-time wiring for AZW3/MOBI (the spike never themed) — the `setStyles` push could mis-time vs Foliate-js book load, or be dead-code'd by the pre-existing `layoutFlow` early-return in `updateUIView`. | (a) Both WebViews load the **same** `foliate-bundle.js`, so `readerAPI.setStyles` is the same API; `FoliateViewBridge.swift:209-237` is the proven reference. (b) **The pre-existing `guard currentLayoutFlow != safeFlow else { return }` early-return WILL dead-code a font-size-only `themeCSS` diff if naively appended** — v2 round-2 audit finding. WI-4 explicitly restructures `updateUIView` into two independent `if`-diff branches (see surface-area note) so the theme branch fires regardless of `layoutFlow`. (c) Pre-ready: WI-4 also pushes `setStyles` once on `onBookReady`. Gate-5 slice verification opens an AZW3 fixture and confirms the slider now visibly resizes the text *with the layout mode left unchanged* (the exact case the early-return would have broken). |

---

## Backward compat

- **Stored data**: `TypographySettings` is **not** modified — same Codable
  shape, same `CodingKeys`, same `fontSizeRange`. Every existing persisted
  `readerTypography` blob (and every `PerBookSettings` typography blob) decodes
  unchanged. The stored value stays the unified value.
- **Older clients**: no schema bump, no `@Model` change, no
  `VReaderMigrationPlan` touch — this is a pure render-path transform. An older
  build reading the same `UserDefaults` sees the same unified number.
- **In-flight readers**: a user updating mid-book keeps their exact slider
  position. TXT keeps its current appearance (`.txt` multiplier `1.0`); MD and
  EPUB are re-anchored on TXT by their multipliers; **AZW3/MOBI gains slider
  responsiveness it never had** — before this feature the slider was a no-op
  for AZW3/MOBI, so a user mid-AZW3-book will, after update, see the text
  respond to the slider for the first time (a one-time *new capability*, not a
  regression). No data loss, no re-import, no position loss — `Locator`s are
  size-independent.
- **PDF**: unchanged in every respect (never consumed the setting; still
  doesn't).
- **Forward**: re-tuning `FontSizeCalibrationProfile.standard` in a future
  patch changes only rendered appearance, never stored data — safe to iterate.

---

## Acceptance criteria

1. A `FontSizeCalibrator` exists as a pure, `Sendable`, unit-tested type that
   maps a unified font-size value → a per-renderer value for each of
   TXT/MD/EPUB/AZW3-MOBI.
2. At a single fixed slider value **and the default content-size category**,
   the rendered text in TXT, MD, EPUB, and AZW3/MOBI is perceptually
   consistent in size (verified on-device in Gate 5; asserted at the value
   layer by the cross-format-consistency tests). Non-default Dynamic Type is
   out of scope (known limitation R1a).
3. TXT rendering at any given slider value is **unchanged** from pre-feature
   behavior (TXT is the calibration anchor, multiplier `1.0`).
4. The AZW3/MOBI font-size slider, which was a no-op before this feature, now
   visibly resizes AZW3/MOBI reader text.
5. Bug #57 does not regress — EPUB's `p,div,span,…{font-size:inherit}` rule
   and `h1-h6{font-size:revert}` rule remain present and the EPUB internal
   cascade for those elements stays flat.
6. PDF behavior is unchanged — the font-size slider continues to not affect PDF
   (documented exclusion, not a regression).
7. Every existing persisted `TypographySettings` / `PerBookSettings` blob
   decodes unchanged; no schema migration.
8. All new and existing test suites pass under
   `xcodebuild test -only-testing:vreaderTests`.

---

## Audit fixes applied (Gate 2)

### Round 1 — Codex thread `019e3ebb`

Codex returned 1 Critical + 3 High + 2 Medium + 1 Low. All verified against
the live codebase by the author and applied in plan rev v2:

| Severity | Finding | Resolution in v2 |
|----------|---------|------------------|
| Critical | WI-4 aimed at the wrong AZW3/MOBI surface — live dispatch is `ReaderContainerView.swift:684` → `FoliateSpikeView` → `FoliateSpikeWebView`, which does **not** read `typography.fontSize` or call `FoliateStyleMapper.themeCSS`. `FoliateReaderContainerView`/`FoliateViewBridge` (which do) are dormant. | **Verified** (`ReaderContainerView.swift:683-691`, `FoliateSpikeView.swift:43-54`, `ReaderFormatHosts.swift:196` shows `FoliateReaderHost` is unreferenced by `ReaderContainerView`). WI-4 rewritten as **first-time font-size plumbing** through the live `FoliateSpikeView` path: `FoliateSpikeWebView` gains a `themeCSS` field + a `setStyles` push mirroring `FoliateViewBridge.swift:218-225`. `FoliateReaderContainerView`/`FoliateViewBridge` added to "files OUT of scope". Acceptance criterion 4 added. R7 added. |
| High | Calibration model not stable across Dynamic Type — TXT uses `UIFontMetrics`, MD does not, EPUB/Foliate honor neither; a single multiplier is exact only at the default content-size category. | **Verified** (`TXTAttributedStringBuilder.swift:43` `UIFontMetrics`; `MDAttributedStringRenderer.swift:243,344` raw `systemFont`; `ReaderThemeV2+EPUBCSS.swift:112` `-webkit-text-size-adjust:100%`). Added "Dynamic Type scope" section: feature scoped to parity at the default content-size category, documented as known limitation R1a, full unification deferred (Rejected alternative 6). Acceptance criterion 2 + Gate-5 verification qualified to the default category. |
| High | Bug #57 precedent mis-stated — the live CSS is `font-size:inherit` for an enumerated text-element list, not `body * {font-size:inherit}`; `body *` is `font-family`-only. The WI-3 test expectation was wrong. | **Verified** (`ReaderThemeV2+EPUBCSS.swift:127-139`). Prior-art section corrected to the real selectors; WI-3 test (`ReaderThemeV2EPUBCSSCalibrationTests`) rewritten to assert the actual selector list and explicitly NOT assert `body *{font-size}`. Known-limitation note added. |
| High | `lineSpacingPoints`/`cjkLetterSpacing` property→function refactor underscoped + semantically muddy — they have a settings-**preview** call site (`ReaderSettingsPanel.swift:637-638`) that is not a renderer-targeted surface; "two call sites" was wrong (there are four). | **Verified** (4 call sites: `ReaderSettingsStore.swift:208`, `:217-218`, `ReaderSettingsPanel.swift:637-638`). Refactor **dropped**: public properties kept unchanged for the preview; two new `private` per-target helpers (`calibratedLineSpacingPoints(for:)` / `calibratedCJKLetterSpacing(for:)`) added for renderer configs only. Zero `ReaderSettingsPanel` churn. |
| Medium | WI-2 too wide — bundled the first behavioral calibration change with an internal API-shape refactor spilling into the preview + tests. | Resolved by the High-finding fix above — the property→function refactor is gone, so WI-2 is now just "add calibrator + route the two configs + two private helpers", a small single-file change. |
| Medium | `FontSizeCalibrationProfile` as `[CalibrationTarget: Double]` permits partial states; exhaustiveness pushed to tests not the compiler. | `FontSizeCalibrationProfile` rewritten with four explicit `Double` fields (`txt`/`md`/`epub`/`foliate`) + a total `switch` in `multiplier(for:)` — compiler-checked exhaustiveness. |
| Low | Plan's renderer file-path references were imprecise. | Renderer table now cites exact paths + line numbers (`TXTAttributedStringBuilder.swift:35-43`, `MDAttributedStringRenderer.swift:243,344`, etc.). |

### Round 2 — Codex thread `019e3ebb` (re-review)

Codex re-read the v2 plan and confirmed **all 7 round-1 findings resolved in
substance** (the Critical AZW3 surface correction, the Dynamic Type bound, the
Bug #57 CSS claim, the dropped `lineSpacingPoints` refactor, WI-2 sizing, the
explicit-fields profile, the file paths). It also explicitly answered the
round-1 re-confirm question:

> **AZW3/MOBI first-time wiring in #70 — verdict: acceptable.** "Folding
> first-time AZW3/MOBI font-size wiring into feature #70 is acceptable. It is
> the live-path implementation needed to satisfy #70's cross-format scope, not
> a reason to force a separate prerequisite bug row." — Codex `019e3ebb`.

Round 2 surfaced **1 new Medium + 1 new Low**, both applied in plan rev v3:

| Severity | Finding | Resolution in v3 |
|----------|---------|------------------|
| Medium | WI-4's `FoliateSpikeWebView.updateUIView` *early-returns* unless `layoutFlow` changed (`FoliateSpikeView.swift:219`). A `themeCSS` diff appended after that guard would **never fire** on a font-size-only slider change. | **Verified** (`FoliateSpikeView.swift:213-237` — the `guard coordinator.currentLayoutFlow != safeFlow else { return }`). WI-4 surface-area note + WI-4 sequencing entry + R7 now **explicitly require** restructuring `updateUIView` to match `FoliateViewBridge.swift:209-237`: no early return, two independent `if`-diff branches (layout, theme), each updating its own `current*` coordinator field. Pre-ready `setStyles` push on `onBookReady` added. |
| Low | Stale wording after the v2 design change — "multipliers dictionary" / "dictionary literal" (the profile no longer uses a dict) and risk R3 still framed around the dropped property→function refactor. | "Calibration derivation" reworded to "four `Double` fields"; `FontSizeCalibrationTests` catalogue items reworded ("matching field", not "dictionary value" / "no `nil` lookup"); R3 rewritten around the real risk (exact-value test assertions shifting when MD/EPUB calibrate). |

**Gate-2 outcome**: after rev v3, zero open Critical/High/Medium findings.
Codex's round-2 Medium and Low are both resolved in this revision. Gate 2
passes — row may move to `PLANNED`.
