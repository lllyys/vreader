---
branch: feat/feature-71-wi-2-chapter-body-rewriter
threadId: 019e601a-f449-7c81-afdb-8ac9fb7d3235
rounds: 3
final_verdict: ship-as-is
date: 2026-05-26
---

# Codex Gate-4 audit — Feature #71 WI-2 (EPUBChapterBodyRewriter)

Independent audit (Codex MCP, separate process — author/auditor separation per
rule 48) of the pure XHTML→merged-DOM chapter rewriter that lets one EPUB
chapter's body live as a `<section>` inside the shared continuous-scroll
WKWebView document.

Files audited (all new):
- `vreader/Views/Reader/EPUBChapterBodyRewriter.swift`
- `vreader/Views/Reader/EPUBChapterResourceURL.swift`
- `vreader/Views/Reader/EPUBChapterCSSScoper.swift`
- `vreaderTests/Views/Reader/EPUBChapterBodyRewriterTests.swift` (35 tests, all green)

## Round 1 — 3 High, 2 Medium

| # | Severity | Finding | Resolution |
|---|---|---|---|
| 1 | High | Active HTML (`<script>`/`on*=`/`javascript:`) passes through unsanitized; `src` absolutization makes relative `<script src>` loadable | **Accepted (not a WI-2 defect).** The existing single-chapter path (`EPUBWebViewBridge.swift:294` `loadFileURL`) already loads chapter XHTML verbatim into the same WKWebView with content JS at default — same trust model (local user-imported EPUB). WI-2 introduces no new surface. Sanitization, if ever wanted, is a uniform bridge-level concern for both paged + continuous modes, not this pure shape-transformer. Trust boundary documented in the rewriter header. Codex accepted the objection with the `loadFileURL` evidence. |
| 2 | High | `@import` left unscoped → cross-chapter CSS leak | **Fixed** — top-level `@import` is dropped (OSLog notice). The per-block loader resolves relative to the chapter dir, not the imported sheet's dir, so clean recursive inlining isn't possible here; dropping closes the leak (recursive inlining = documented follow-up; EPUB chapters overwhelmingly use `<link>`, which IS inlined+scoped). Codex accepted drop-over-leak. Test `atImportDropped`. |
| 3 | High | Attribute rewriting required `attr="x"` with no whitespace around `=`; legal `id = "x"` missed | **Fixed** — `\s*=\s*` in `rewriteAttribute` + `attributeValue`. Test `attrWhitespaceAroundEquals`. |
| 4 | Medium | Root-selector mapping only rewrote a single leading token (`html body p` → broken `[section] body p`) | **Fixed** — `scopeOne` consumes a leading run of root compounds + inter-root combinators, collapsing onto the section (`html body p`→`[section] p`, `body.x`→`[section].x`, `html > body > img`→`[section] > img`). Tests `rootChainCollapsed`, `rootDirectQualifier`, `rootChildCombinator`. |
| 5 | Medium | Multi-`<body>` returned `a</body>junk<body>b` (first-open to last-close) | **Fixed** — first `<body>` to FIRST `</body>` after it. Test `multipleBodyTakesFirst`. |

## Round 2 — 2 Medium

| # | Severity | Finding | Resolution |
|---|---|---|---|
| 6 | Medium | `url()` regex broke on quoted URLs containing `)` / escapes (`url("bg(1).png")`) | **Fixed** — replaced with a hand scanner `EPUBChapterResourceURL.rewriteCSSURLs` honoring quote state + `\` escapes; absolute/data:/fragment emitted verbatim, resolved relatives double-quoted. Test `cssUrlWithParensInQuotes`. |
| 7 | Medium | Stylesheet-link detection used `contains("stylesheet")` over the whole tag | **Fixed** — `matchStylesheetLinks` parses the `rel` attribute and token-matches `stylesheet`. Negative test `nonStylesheetLinkIgnored` (`<link rel="icon" href="foo-stylesheet.png">`). |

## Round 3 — 1 Medium

| # | Severity | Finding | Resolution |
|---|---|---|---|
| 8 | Medium | The new url scanner ran blind through CSS strings/comments (`content: "url(x)"`, `/* url(x) */`) | **Fixed** — scanner now copies CSS strings (`endOfCSSString`) + `/* */` comments verbatim before testing for `url(`. Tests `cssUrlInsideStringNotRewritten`, `cssUrlInsideCommentNotRewritten`. |

## Residual (accepted) — Low

| file:line | Severity | Finding | Disposition |
|---|---|---|---|
| EPUBChapterBodyRewriter.swift:~164/~173 | Low | `<style>` collection/stripping is regex-based; a literal `</style>` inside CSS text/comment/string would terminate the block early | **Accepted/deferred.** A literal `</style>` inside chapter CSS is pathological (and would break the source XHTML's own parsing too). Not worth a 4th round per Codex; a small HTML/style scanner is a possible later refinement. |

## Verdict

Round 3 closed clean: **no remaining Critical/High/Medium. Ship-as-is.** One Low
accepted above. 35 tests pass under
`xcodebuild test -only-testing:vreaderTests/EPUBChapterBodyRewriterTests`.
