---
branch: fix/issue-472-epub-highlight-render
threadId: 019e0c82-a4b2-7c42-a4e4-27ba9d4d9da0
rounds: 2
final_verdict: ship-as-is
date: 2026-05-09
---

# Codex audit log — bug #159 / GH #472

Fix: namespace-aware XPath rewrite in `resolveNodeFromXPath` so the EPUB
highlight render pipeline can resolve unqualified selection paths back
to nodes inside `application/xhtml+xml` documents. Also fixed the
foliate-bridge.js DOMContentLoaded auto-setup timing so
`window.__foliate.overlayer` is initialized when the script is injected
at `.atDocumentEnd` (which runs after DOMContentLoaded has already
fired).

## Round 1 (initial audit)

### Findings

- **`vreader/Views/Reader/EPUBHighlightJS.swift:117`** | Medium | The
  XPath rewrite is correct for the current `getXPath` shapes on plain
  XHTML text (`/html/body/p[3]/text()[1]`, `/html/body/p`,
  `/html/body/p[3]/em`), but it is not safe for qualified element
  names. `getXPath` serializes `node.tagName.toLowerCase()` at lines
  38 and 47, so selections inside foreign-namespace content in EPUB
  XHTML (for example inline `svg:svg` / `svg:text` or `math:*`) can
  produce steps containing `:`. The regex only matches the prefix-
  sized `/svg` portion, which turns `/svg:svg` into
  `/*[local-name()="svg"]:svg`, i.e. invalid XPath, so highlight
  rendering/restoration will still fail for those documents.
  - **Resolution**: extended the regex character class to accept an
    optional `:prefix` segment in the captured name; replacement
    function strips the prefix via `name.indexOf(':')` before emitting
    the `local-name()` predicate. Added regression-guard test
    `highlightAPIJS_handlesPrefixedElementNames` pinning both the
    colon-aware regex and the prefix-strip step in the JS source.

## Round 2 (re-verify)

> No findings.
>
> For your example, the updated rewrite is correct:
>
> `/html/body/svg:svg/svg:text/text()[1]`
> becomes
> `/*[local-name()="html"]/*[local-name()="body"]/*[local-name()="svg"]/*[local-name()="text"]/text()[1]`
>
> That is valid XPath and resolves the intended nodes:
> - `svg:svg` is treated as an element step, prefix stripped to local name `svg`
> - `svg:text` is also treated as an element step, prefix stripped to local name `text`
> - `text()[1]` stays the XPath text-node axis, because the axis-token guard fires before prefix stripping
>
> I don't see a remaining bug for any path shape `getXPath` currently
> emits in `EPUBHighlightJS.swift:24`. It only serializes element
> names from `node.tagName.toLowerCase()` and text-node steps.
>
> Residual note, not a finding: the tests in
> `EPUBHighlightBridgeTests.swift:396` are still source-token guards,
> not behavioral execution. That's acceptable for this unit-test
> layer, but the only unverified part now is runtime behavior in a
> real XHTML `WKWebView`.

## Verdict

**ship-as-is.** Zero open findings after round 2. Runtime behavior
will be confirmed in the pre-FIXED simulator verify against
`mini-epub3.epub` Native EPUB mode (the same fixture that surfaced
the bug in feature #11 round-3 verification).
