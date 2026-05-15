---
branch: feat/feature-60-wi-4-epub-theme
threadId: 019e2de0-9d1a-72d2-860d-f371205cd7bb
rounds: 3
final_verdict: ship-as-is
date: 2026-05-16
---

# Codex Gate 4 audit — Feature #60 WI-4 (EPUB theme injection)

Audit of WI-4: switching EPUB CSS injection from the legacy 3-theme
`ReaderTheme.epubOverrideCSS` to `ReaderThemeV2`'s 7-token surface
(`backgroundColor` / `paperColor` / `inkColor` / `subColor` /
`ruleColor` / `accentColor` / `chromeColor`) with the Photo-theme
`html { background-image: url(...) }` rule.

## Round 1 — initial audit

| Finding | Severity | Resolution |
|---|---|---|
| `ReaderThemeV2+EPUBCSS.swift:161` — backgroundImageURL interpolated raw into CSS `url("…")`; off-EPUB-root file URLs would also fail WKWebView access scope when later wired. | Medium | **Fixed**: Added `cssEscapeURL` helper that neutralises `\` and `"` (the two characters that can break out of `url("…")`). Documented the WKWebView access-scope limitation explicitly in the helper's doc-comment; callers pass `backgroundImageURL: nil` for now (Photo plumbing ships in a later WI). |
| `EPUBThemeOverrideCSSV2Tests.swift:15` — substring assertions don't pin the selector→token mapping; a regression that swapped html/body backgrounds or routed accent through ::selection-color would still pass. | Medium | **Fixed**: Replaced substring-only assertions with explicit selector→property pairs (`html { background-color: <outer-bg>`, `body { background-color: <paper-bg>`, `a:link { color: <accent>`, `a:visited { color: <sub>`, `td/th ... border: 1px solid <rule>`, `hr ... border-top: 1px solid <rule>`, `::selection { background-color: <accent>`). Added a `normalize(_:)` helper that collapses whitespace runs so the test contracts stay readable. |
| `ReaderThemeV2+EPUBCSS.swift:78` — emitted `<style id="vreader-theme-v2">` but the bridge strips the wrapper and re-injects under `id="vreader-theme"`; the v2 id was misleading docs. | Low | **Fixed**: Changed emitted wrapper id to `vreader-theme` matching the bridge. Added a comment block explaining the deliberate id collision (the bridge owns the id; no runtime caller needs to distinguish V2 from legacy). |

## Round 2 — verification of round-1 fixes

| Finding | Severity | Resolution |
|---|---|---|
| `EPUBThemeOverrideCSSV2Tests.swift:141` — `photoBackgroundImageURLIsCSSEscaped` test would pass even if the escape helper were deleted, because `URL.absoluteString` percent-encodes `"` to `%22` before reaching the helper. | Low | **Fixed**: Promoted `cssEscapeURL` to `static` (internal) and replaced the indirect URL-based test with 4 direct unit tests (`escapesBackslash`, `escapesDoubleQuote`, `orderingDoesNotDoubleEscape`, `passthroughForCommonURLChars`) plus one end-to-end test (`photoCSSEmitsTheEscapedURLVerbatim`) that asserts the CSS embeds `url("\(cssEscapeURL(absoluteString))")` verbatim. |
| `ReaderThemeV2+EPUBCSS.swift:2` — file header still claimed `<style id="vreader-theme-v2">` while body now emitted `vreader-theme`. | Low | **Fixed**: Updated file header + method doc to match reality and added a paragraph explaining the deliberate id collision. |

## Round 3 — verification of round-2 fixes

**No findings.** Codex confirmed:

- Doc/header mismatch resolved.
- Helper tests now actually prove the escaping behaviour instead of
  being masked by `URL.absoluteString` percent-encoding.
- `cssEscapeURL` ordering (escape `\` before `"`) is correct and
  doesn't damage already percent-encoded URLs.
- Promoting `cssEscapeURL` to `internal` for testability is a
  reasonable tradeoff; the doc comment explains why.
- No new correctness, security, or scope issues introduced.

## Final verdict

**ship-as-is**

- Zero open Critical / High / Medium findings.
- 19 V2 CSS tests pass.
- No regressions in adjacent suites (the 2 pre-existing AZW3 TTS
  failures tracked at Bug #200 are out of WI-4 scope).
- Plan promises (5-theme CSS, new token names, legacy theme decode
  via projection, Photo theme background-image rule with safe
  escaping) all met.

## Manual fallback section

Not applicable — Codex MCP available throughout; thread id
`019e2de0-9d1a-72d2-860d-f371205cd7bb` was used for all three rounds.
