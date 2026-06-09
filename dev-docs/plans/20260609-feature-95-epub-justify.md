# Feature #95 — Justified text alignment for the EPUB reader (default-justify slice)

**Status**: Gate 1 (plan) → Gate 2 (audit pending)
**Row**: `docs/features.md` #95 (Medium, TODO)
**Slug**: epub-justify

## Problem

EPUB body text is left/natural-aligned — the override CSS injects no `text-align`,
so the book's default `left`/`start` wins → ragged right edge, uneven-looking
margins (especially CJK, which wraps per full-width char up to ~1 char short of the
right inset). Justify so both margins are flush, matching the convention CJK
readers expect. The EPUB analog of #92 (TXT, VERIFIED v3.53.1 — `NSParagraphStyle.alignment = .justified`).

## Scope (default-justify is Rule 51 N/A — pure rendering attribute, no new UI)

Inject `text-align: justify` by default for EPUB **paragraph-level** text across all
three EPUB-family render engines + both layouts. An explicit Left/Justified *toggle*
in the Display panel would be NEW UI → `needs-design` (deferred, out of scope — exactly
as #92 noted).

## Engine / layout routing (CORRECTED per Gate-2 audit)

EPUB routing is NOT "3 engines for both layouts". Per `ReaderEngine.routeEPUB`
(`ReaderEngine.swift:72-77`): **paged EPUB → Readium** (default), **scroll EPUB →
legacy WKWebView continuous (#71 stitch)**, and legacy is also used for paged when
the Readium flag is off. AZW3/MOBI → Foliate. So the three surfaces to cover are:

| Surface | Engine | Layout(s) | Injection point |
|---|---|---|---|
| Readium EPUB | Readium Navigator | paged | `EPUBPreferences.textAlign` |
| Legacy EPUB | WKWebView | paged (flag-off) + continuous stitch | `epubOverrideCSS` |
| Foliate | WKWebView + foliate-js | AZW3/MOBI | `FoliateStyleMapper` CSS |

## Surface area (file-by-file)

1. **Legacy WKWebView EPUB** — `vreader/Models/ReaderThemeV2+EPUBCSS.swift`,
   `epubOverrideCSS(...)`. The same override CSS feeds legacy paged AND the #71
   continuous stitch (`EPUBReaderContainerView.swift:734-752`, `EPUBWebViewBridge.swift`).
   Add the justify rule:
   ```css
   p:not([style*="text-align"]):not([align]):not([class*="center"]):not([class*="right"]) {
     text-align: justify !important;
   }
   ```
   - **Selector-syntax fix (Gate-2 High + R2 Medium)**: the `:not(...)` guards chain
     directly on a SINGLE `p` selector. Round-1 had a multi-selector `:not()` bug (the
     guard applied only to the last selector) AND an `li`-vs-`p` guard asymmetry — both
     eliminated by scoping to prose `<p>` only.
   - **`!important` is required (Gate-2 High, cascade)**: in the continuous stitch each
     chapter's `scopedStyleHTML` is appended AFTER the override (`EPUBContinuousScrollJS.swift`),
     so a non-`!important` rule loses to any book `p {}` rule. `!important` wins over
     non-`!important` book CSS (the common case); a book that itself uses
     `!important` on `p` is the residual — accepted + validated on real books in Gate 5.
   - **Respect intentional alignment**: the `:not([style*="text-align"])`,
     `:not([align])`, `:not([class*="center"])`, `:not([class*="right"])` guards skip
     inline-aligned, deprecated-`align`-attr, and common center/right-CLASS paragraphs.
     These are HEURISTICS (inline `style` is case-sensitive; arbitrary centering class
     names are missed) — documented as such, not a complete alignment detector.
   - Headings (`h1–h6`), `figcaption`, table cells (`td/th`), and list items (`li`) are not `p` → untouched (list-item justify is low-value + looks odd, so it's out of scope).

2. **Readium EPUB (default paged engine)** — `vreader/ViewModels/ReadiumEPUBReaderViewModel+Mapping.swift`,
   `EPUBPreferences(...)` (line 124). Add `textAlign: .justify`. `EPUBPreferences.textAlign:
   TextAlignment?` + `TextAlignment.justify` confirmed in the SPM checkout
   (`EPUBPreferences.swift:87`, `Preferences/Types.swift:109-114`). `publisherStyles:
   false` already set → the preference applies. Readium owns its own per-paragraph
   cascade AND auto-enables hyphenation + its own blockquote/figcaption exclusions
   when justify is on (`ReadiumCSS-after.css`) — so Readium's justify will look
   BETTER than legacy/Foliate on Latin (see Risks).

3. **AZW3/MOBI Foliate** — `vreader/Services/Foliate/FoliateStyleMapper.swift`,
   the `rules: [String]` list (line 40-44). Append the SAME guarded justify rule as
   legacy (consistent with this file's all-`!important` convention).

### Files OUT of scope

- TXT / MD readers (#92 already did TXT; MD is a separate attributed-string renderer — not this feature).
- PDF (fixed-layout, no reflow — N/A).
- Any Display-panel UI / Left↔Justified toggle (needs-design, deferred).
- `hyphens: auto` (reduces Latin justification gaps) — a separate enhancement; not bundled here.

## Prior art / project precedent / rejected alternatives

- **#92 (TXT, VERIFIED v3.53.1, GH #1505)** — same root cause + remedy, different
  render layer (`NSParagraphStyle.alignment = .justified`). Direct precedent.
- The override CSS already uses `!important` throughout to win over book CSS — the
  justify rule follows that established convention.
- **Rejected: `body { text-align: justify }`** — too broad, justifies headings + the
  whole layout. Target paragraph-level elements instead.
- **Rejected: no `!important`** — without it the rule may lose to the book's own
  `p {}` stylesheet (source-order dependent), so the default wouldn't reliably apply.
  `!important` + `:not([style*="text-align"])` is the balance (force the default, respect inline intent).
- **Rejected: Readium injected raw user-CSS** — Readium exposes a first-class
  `EPUBPreferences.textAlign`; using it is cleaner than string-injecting CSS and stays
  on the supported API.

## Work-item sequencing (1 WI — Small feature, 1 PR)

- **WI-1 (behavioral)** — add the justify default to all three engines + tests.
  Estimated PR size: small (~3 one-line rule additions + ~6 tests). Behavioral
  (changes reader rendering) → Gate 5 slice verification required.

## Test catalogue (CORRECTED suite names per Gate-2 audit)

- `EPUBThemeOverrideCSSV2Tests` — the override CSS contains the justify rule for `p`; the per-selector `:not(...)` guards are present (incl. the syntax fix —
  each selector carries its own `:not`); `h1–h6`/`li` are NOT in the justify selector.
- `ReadiumEPUBPreferencesMappingTests` — the built `EPUBPreferences.textAlign == .justify`.
- `FoliateStyleMapperTests` — the generated CSS contains the paragraph justify rule.
- Edge tests: an inline-aligned `<p style="text-align:center">` is NOT in scope of the
  rule (selector-level assertion); a `<p class="center">` is excluded; a plain CJK `<p>`
  is in scope (rule is language-agnostic).

## Risks + mitigations

- **Over-forcing non-prose paragraphs** (Gate-2 High/Medium) — `!important` + the
  class/inline heuristics skip the COMMON intentional-alignment cases but NOT:
  verse/poetry encoded as plain `<p>`, blockquote inner prose, faux-headings using a
  non-"center"/"right" class. Mitigation: Gate-5 verification runs on a real book with
  verse + epigraphs + headings and confirms they read acceptably; if a real regression
  shows, narrow the selector (add the offending class) before VERIFIED.
- **Cross-engine Latin divergence** (Gate-2 Medium) — Readium auto-enables hyphenation
  with justify (`ReadiumCSS-after.css:559-575`) and excludes blockquote/figcaption;
  legacy/Foliate do NOT hyphenate and apply the simpler selector. So Latin books look
  smoother on Readium than on legacy/Foliate. ACCEPTED for this slice; `hyphens: auto`
  for legacy/Foliate is a noted follow-up.
- **Inline-guard is a heuristic, not detection** (Gate-2 Medium) — `:not([style*="text-align"])`
  is inline-style-only + case-sensitive; class/stylesheet alignment isn't detected
  (hence the extra `:not([class*="center"])` / `:not([class*="right"])` partial guards).
  Documented as best-effort, not complete.
- **Continuous-mode cascade** (Gate-2 High) — `!important` is what makes the rule win
  over the later-appended chapter CSS; verified on a real continuous-mode book in Gate 5
  rather than assumed from source order.
- **Readium textAlign vs publisherStyles** — `publisherStyles: false` already set, so
  the preference applies; verified in the Gate-5 Readium (paged) slice.

## Backward compat

Pure rendering-default change. No data/schema/format impact. Older books re-render
with justified prose on next open; nothing persisted, nothing migrated.

## Acceptance criteria (per the corrected routing)

1. Readium EPUB (paged, default): body paragraphs render justified (flush right margin).
2. Legacy EPUB (continuous #71 stitch + paged flag-off): body paragraphs render justified.
3. AZW3/MOBI Foliate: body paragraphs render justified.
4. CJK EPUB: both margins flush (the motivating case).
5. Headings NOT force-justified; an inline/`align`/center-class-aligned paragraph keeps its alignment.

## Revision history

- v1 (2026-06-09) — initial plan.
- v2 (2026-06-09) — Gate-2 Codex audit (`/tmp/feat95-planaudit.txt`, 3 High + 4 Medium + 3 Low). Fixes applied:
  - **High** — corrected engine/layout routing (Readium=paged, legacy=paged+continuous, Foliate=AZW3), not "3 engines both layouts".
  - **High** — fixed the `:not()` selector syntax (per-selector, not just on `dd`); dropped `dd`, kept `p`/`li`.
  - **High** — softened the continuous-mode cascade claim; `!important` is load-bearing + real-book-verified, not assumed from source order.
  - **Medium** — added `:not([class*=center])` / `:not([class*=right])` / `:not([align])` guards; documented the heuristics' limits; documented hyphenation divergence (Readium auto-hyphenates, legacy/Foliate don't); Gate-5 now verifies verse/epigraph/headings on a real book.
  - v3 (2026-06-09) — Gate-2 round 2: 3 High resolved, 1 Medium remained (the `li` guard asymmetry). Fix: dropped `li` from the selector — scope is prose `<p>` only (the auditor's offered resolution). Zero open Critical/High/Medium → Gate 2 PASSED.
  - **Low** — corrected test suite names (`EPUBThemeOverrideCSSV2Tests`, `ReadiumEPUBPreferencesMappingTests`, `FoliateStyleMapperTests`); kept 1-WI shape; kept Readium native `textAlign` (not raw CSS).
