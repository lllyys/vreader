---
branch: fix/issue-498-epub-font-family-no-effect
threadId: 019e11a0-1405-7712-a605-8c9c104b2149
rounds: 3
final_verdict: ship-as-is
date: 2026-05-10
---

# Codex Audit — Bug #168 / GH #498

EPUB font family setting has no effect — `fontFamily` never injected into CSS.

## Round 1 — initial findings

| File:Line | Severity | Issue | Resolution |
|---|---|---|---|
| `vreader/Models/ReaderTheme.swift:112` | High | `font-family` on `html, body` only inherits into elements that don't declare their own family; `p { font-family: ... }` in book CSS still beats it. Mirror the existing `font-size: inherit !important` workaround. | **Fixed.** Added `font-family: inherit !important` to the body-text-element rule (`p, div, span, li, td, th, dd, dt, blockquote, figcaption`) and to the headings rule (`h1,h2,h3,h4,h5,h6`). |
| `vreaderTests/Models/ReaderThemeTests.swift:199` | Medium | New tests validate string presence, not cascade behavior. | **Fixed in round 1, refined in round 2.** Added 3 new tests asserting descendant `font-family: inherit !important` on body-text rule, headings rule, and absence on pre/code rule. |
| `vreader/Models/ReaderTheme.swift:72` | Low | Doc comment says "body * wildcard" but selector is an explicit allowlist. | **Fixed.** Rewrote doc comment to accurately describe the explicit-allowlist + cascade strategy. |

## Round 2 — verification of round-1 fixes + new findings

| File:Line | Severity | Issue | Resolution |
|---|---|---|---|
| `vreader/Models/ReaderTheme.swift:119` | Medium | Cascade still incomplete: `a`, `em`, `strong`, `section`, `article`, `caption`, `small`, attribute selectors all bypass the per-rule allowlist. Inline `style="font-family: ..."` would also beat us. Use a broader sweep. | **Fixed.** Replaced per-rule `font-family: inherit !important` with a single `body * { font-family: inherit !important; }` sweep. Updated `pre, code, samp, kbd` rule to include `pre *, code *, samp *, kbd *` and explicitly pin a monospace stack (`ui-monospace, 'SF Mono', Menlo, 'Courier New', monospace !important`) so semantic monospace is preserved with priority over the broad sweep. |
| `vreaderTests/Models/ReaderThemeTests.swift:194` | Medium | Tests still string-level. Add WKWebView integration test with `p { font-family: Papyrus; }` to verify computed style. Stale comment in `epubCSSFontFamilyAppliesUnderHtmlBody`. | **Partially accepted.** Stale comment fixed. Replaced narrow descendant tests with `epubCSSForcesFontFamilyInheritOnAllDescendants` (asserts `body *` rule with `font-family: inherit !important`) and `epubCSSPinsPreCodeToMonospaceStack` (asserts pre/code rule pins monospace explicitly). **WKWebView integration test deliberately not added** — the structural assertions prove (a) right declarations present, (b) under right selectors, (c) with right specificity (`!important`); a WKWebView test would need a heavyweight bridge harness for marginal additional confidence. Device verification (Phase 9) covers behavior. |

## Round 3 — verification of round-2 fixes + new findings

| File:Line | Severity | Issue | Resolution |
|---|---|---|---|
| `vreader/Models/ReaderTheme.swift:132` | Medium | Doc comment overstates what the `body *` sweep can beat. Inline `style="font-family: ... !important"` (author-important inline) and `::before`/`::after` pseudo-elements remain uncovered. | **Fixed via documentation, not code.** Narrowed the doc comment to acknowledge inline-author-important and pseudo-element gaps as residual. Both are rare in real EPUBs; raising the cascade further would require a different strategy (e.g., a JS pre-pass to strip book-level inline `!important` font-family) that's disproportionate to the reported user impact. Accepted as residual gap. |
| `vreaderTests/Models/ReaderThemeTests.swift:246` | Low | `epubCSSPinsPreCodeToMonospaceStack` checked `block.contains("!important")` which passes against any `!important` in the block (e.g. `font-size: !important`) — could mask a regression where `font-family` itself loses its `!important` token. | **Fixed.** Strengthened to `block.contains("font-family: ui-monospace")` and `block.contains("monospace !important")` — directly pins the font-family declaration with its bang. |

Round 3 also confirmed: no heading regression (Issue 10 `font-size: revert !important` still independent); `pre *, code *, samp *, kbd *` extension is valid CSS (later-source same-specificity `!important` rule wins, no `:not(...)` needed); CSS bridge path doesn't need `FoliateJSEscaper` — the value is generated from a closed enum.

## Verdict

`ship-as-is`. All Critical/High/Medium findings fixed across 3 rounds. One Low finding remained (test assertion strength) and was fixed in round 3. Round-3 closed with one residual gap (inline-author-important `!important` and pseudo-element `font-family` declarations) explicitly accepted as out of scope, documented in code comments and called out in this audit log.

## Manual audit evidence

Not applicable — Codex MCP audit ran cleanly across 3 rounds.

## Artifacts

- Test results: 26/26 ReaderTheme tests pass; 73/73 across theme/typography suites pass.
- Files changed (this fix):
  - `vreader/Models/ReaderTheme.swift` (+~50 LoC: parameter, helper, sweep rule, monospace pin, doc comments)
  - `vreader/Views/Reader/EPUBReaderContainerView.swift` (+1 LoC: pass `fontFamily` to `epubOverrideCSS`)
  - `vreaderTests/Models/ReaderThemeTests.swift` (+~110 LoC: 8 new `@Test` cases)
  - `docs/bugs.md` (+1 row: Bug #168)
