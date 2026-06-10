---
branch: fix/issue-1605-epub-justify-latin
threadId: bug336-run-codex
rounds: 1
final_verdict: ship-as-is
date: 2026-06-10
---

# Gate-4 Codex audit — Bug #336 (EPUB justify makes Latin text gappy)

Independent audit via `scripts/run-codex.sh` (gpt-5.4), read-only. The auditor
researched the W3C CSS Text §1.3/§5.3 language-gating of `hyphens: auto` and the
pinned Readium 3.9.0 source.

## Round 1

| file:line | severity | issue | resolution |
|---|---|---|---|
| ReaderThemeV2+EPUBCSS.swift:137 | Medium | The legacy WKWebView fix was incomplete: `hyphens: auto` only engages when the content declares a language, and the legacy stitched host document has no `lang` (chapter `<html>`/`<body>` tags are dropped during body extraction), so lang-less EPUBs still gap in legacy/scroll mode. | **Fixed** — threaded `viewModel.metadata?.language` (OPF `dc:language`) → `EPUBWebViewBridge.contentLanguage` → a new `.atDocumentEnd` `langInjectionJS` that sets `documentElement.lang`/`body.lang` when absent. Language sanitized to `[A-Za-z0-9-]` (injection-proof). 4 `EPUBWebViewBridgeLangJSTests`. |

**Readium path confirmed correct:** `EPUBPreferences(hyphens: true)` is the right
knob; in Readium 3.9.0, `ReadiumCSS` maps it to `bodyHyphens`, injects prefixed +
unprefixed hyphenation CSS, AND injects `lang` from publication metadata when
missing. Init parameter ordering is correct. Since Readium is the **default**
EPUB engine, the default experience is fully fixed.

No other findings. Side effects confirmed safe: CJK does not hyphenate
(language-gated + Readium's CJK stylesheets disable it); `pre`/`code` unaffected
(the legacy rule targets `p` only); `-webkit-hyphens` + `hyphens` is the correct
WebKit pairing; `!important` not required on the hyphenation declarations.

## Verdict

**ship-as-is.** The single Medium fixed (legacy lang propagation) + pinned by
tests. 53 tests green (EPUB CSS 28 + Readium mapping 21 + lang injection 4).
Both EPUB engines now hyphenate justified Latin when the publication declares a
language; neither engine can infer a language when metadata omits it (an
unavoidable constraint of CSS hyphenation, not a defect).
