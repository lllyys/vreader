---
branch: fix/issue-1131-azw3-font-size-overshoot
threadId: 019e4c36-d6e4-7903-b75e-b5fc853abf95
rounds: 1
final_verdict: follow-up-recommended
date: 2026-05-22
---

# Codex Audit — Bug #261 / GH #1131 (AZW3/MOBI font-size overshoot)

- **Branch**: `fix/issue-1131-azw3-font-size-overshoot`
- **Thread**: `019e4c36-d6e4-7903-b75e-b5fc853abf95`
- **Date**: 2026-05-22
- **Rounds**: 1
- **Verdict**: `follow-up-recommended` (zero Critical/High/Medium code defects requiring a change; the one Medium finding is a pre-existing limitation shared with EPUB, not a regression)

## Scope audited

Diff `HEAD~1..HEAD` on the branch:
- `vreader/Services/Foliate/FoliateStyleMapper.swift` — added the em-compounding cascade-flatten rule.
- `vreaderTests/Services/Foliate/FoliateStyleMapperCascadeFlattenTests.swift` — new regression suite.
- `vreaderTests/Services/Foliate/FoliateStyleMapperTests.swift` — rewrote the font-family injection-security test.

## Root cause (device-measured, CU-free via DebugBridge `eval`)

At unified font-size 28, `getComputedStyle` inside the Foliate content document:

| Format | html | body | `<p>` |
|---|---|---|---|
| EPUB (mini-epub3) | 31.4px | 31.4px | 31.4px (flat) |
| AZW3 (mini-azw3, no book CSS) | 16px | 31px | 31px |
| AZW3 + mock Kindle CSS (`p{font-size:1.15em}`, `.big{1.4em}`) **pre-fix** | 16px | 31px | **35.65px / 43.4px** (compounded +15% / +40%) |
| AZW3 + mock Kindle CSS **post-fix CSS** | 31px | 31px | **31px** (flat) |

→ **Candidate 2 (em-compounding) confirmed.** The `foliate: 1.12` multiplier is correct (body 31px ≈ EPUB 31.4px); the overshoot came from the book's own `em`-based descendant CSS compounding against the body base, which `FoliateStyleMapper` did not flatten (EPUB does, via `ReaderThemeV2+EPUBCSS`).

## Findings

### 1. Medium — flatten not universal (pre-existing, shared with EPUB)
A book using higher-specificity / `!important` selectors (`p.note{font-size:1.15em !important}`) or font-size on container elements outside the reset list can still compound. **Codex explicitly classified this as NOT a feature-#70 regression and NOT unique to Foliate** — EPUB's `ReaderThemeV2+EPUBCSS.swift:122` uses the identical selector shape and has the same boundary. The fix solves the reproduced + common case (the +15-40% paragraph compounding the bug reported and I measured).

**Resolution applied**: widened the Foliate reset list beyond EPUB's to also cover the HTML5 semantic containers Kindle KFX/MOBI output commonly wraps content in (`section, article, aside, main, header, footer, figure`) — strictly increases compounding immunity at zero risk. Going further to a universal `* { font-size: inherit }` was rejected: it would over-flatten and break legitimate book typography (drop-caps, captions, code blocks) that EPUB deliberately preserves via `revert`. **Residual boundary accepted with rationale**: parity-with-EPUB is the bug's explicit goal ("AZW3 too large *vs EPUB*"); a fix that flattens *more* than EPUB would diverge the two formats in the opposite direction.

### 2. Low — injection test implementation-coupled
The rewritten `themeCSSFontFamilyStripsInjection` hard-coded `closeBraceCount == 4`, brittle to future legitimate rule additions.

**Resolution applied**: replaced the exact-count assertion with structural security checks robust to rule-count changes — (a) font-family still emitted, (b) no `} body {` / `} .x {` breakout block, (c) balanced brace count (`{` == `}`). These assert the actual safety property (`escapeForCSS` strips `" ' \ ; { } \n \r`) without coupling to how many rules the mapper emits.

## Confirmed sound by Codex (no change needed)

- **No feature #70 regression** — calibration path unchanged; `FoliateSpikeView.themeCSS(for:)` still only passes the calibrated size into CSS generation; `FontSizeCalibration.standard.foliate = 1.12` and `FontSizeCalibrator` untouched. Fix is CSS-injection-only. (50 feature-#70 calibration tests pass.)
- `html, body` pinning is correct for `rem` resolution.
- Omitting `color: inherit` is consistent with Foliate's current no-color-theming contract.
- Bridge safety intact — final CSS still escaped via `FoliateJSEscaper.escapeForJSString` before `setStyles('…')`.
- `font-size: revert !important` acceptable in WebKit; worst case (unsupported) the declaration is ignored and only heading parity degrades, never body-size calibration.
