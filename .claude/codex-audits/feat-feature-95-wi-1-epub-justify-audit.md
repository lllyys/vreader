---
branch: feat/feature-95-wi-1-epub-justify
threadId: 019eac73-b16b-7550-b285-4be8a5810c01
rounds: 1
final_verdict: ship-as-is
date: 2026-06-09
---

# Codex Audit — Feature #95 WI-1 (EPUB justify default)

## Change

Justify EPUB body prose by default across all three EPUB-family engines:
- Legacy WKWebView (`ReaderThemeV2+EPUBCSS.epubOverrideCSS`) — adds
  `p:not([style*=text-align]):not([align]):not([class*=center]):not([class*=right]) { text-align: justify !important; }`
  (covers legacy paged + #71 continuous stitch).
- Readium (`ReadiumEPUBReaderViewModel+Mapping.epubPreferences`) — `textAlign: .justify`
  (Readium-native; it owns hyphenation + blockquote/figcaption exclusions).
- Foliate (`FoliateStyleMapper.themeCSS`) — same guarded `p` rule.

## Findings

**No functional findings.** Codex confirmed: the selector is a static literal (no
injection), the legacy rule placement (after `h1–h6`, before the font-family-only
`body *`) doesn't conflict on `text-align`, the Foliate rule placement is inert
relative to the drop-cap rule, and the `EPUBPreferences` change is Swift-6 correct.

| file:line | severity | issue | resolution |
|---|---|---|---|
| EPUBThemeOverrideCSSV2Tests.swift / FoliateStyleMapperTests.swift | Low (optional) | The tests pin the exact guarded selector but don't express the exclusion intent as standalone negative assertions. | **Accepted** — the exact-string `#expect(css.contains("p:not(...):not(...):not(...):not(...) { text-align: justify !important; }"))` already pins every exclusion guard + the p-only scope (a heading/li/inline-aligned regression would change the emitted string and fail). Functionally covered. |

## Verification (Gate 5a)

Device-verified on iPhone 17 Pro Simulator (mini-cjk EPUB + mini-azw3):
- Legacy continuous EPUB: CJK `<p>` computes `text-align: justify`.
- Readium paged EPUB: CJK `<p>` computes `text-align: justify`; screenshot shows flush margins, heading centered.
- AZW3 Foliate: Latin prose renders justified (flush right margins) in the screenshot.

## Verdict

ship-as-is — no functional findings; the one optional Low accepted with rationale;
all three engines device-verified.
