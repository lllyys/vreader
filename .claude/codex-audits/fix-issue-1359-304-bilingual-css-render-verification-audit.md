---
branch: fix/issue-1359-304-bilingual-css-render-verification
threadId: 019e8776-a6b4-7f53-b04f-dc7075fab4a2
rounds: 1
final_verdict: ship-as-is
date: 2026-06-02
---

# Codex audit — Bug #304 verification-exception integration test

Independent Codex audit (cc-suite via `scripts/run-codex.sh`, model `gpt-5.5`,
effort `high`, read-only) of the new high-fidelity integration test that verifies
the #304 fix's render effect without AI.

## Scope

- `vreaderTests/Views/Reader/BilingualCSSRenderIntegrationTests.swift` (new) —
  loads a `.vreader-bilingual[data-vreader-decoration]` block into a LIVE
  `WKWebView`, injects the production `EPUBBilingualJS.bilingualStyleJS(css:)`, and
  asserts the computed style (smaller font ratio, accent left border, non-select).

## Findings — CLEAN (zero findings)

The auditor confirmed:
- **Legitimate** — the synthetic `.vreader-bilingual` element is an acceptable
  stand-in because #304 is about styling that exact selector, not AI generation;
  the real inject JS creates the same class/attribute and the test drives the real
  CSS rule through a live WKWebView.
- **Assertions sound** — the `0.88` font-size RATIO (vs absolute px) + disabled
  `-webkit-text-size-adjust` + viewport meta make it deterministic; the border /
  user-select readbacks match `ReaderThemeV2+EPUBCSS.swift`.
- **Hygiene acceptable** — `@MainActor`, live WKWebView + `didFinish` waiter +
  async JS wrappers match existing patterns; no window needed for computed-style.
- **"Yes, it exercises the relevant failure path well enough for a
  verification-exception close"** — without the injected rule the block computes
  like plain body text; with the production rule injected the computed style
  changes across the real WebKit boundary. Caveat: cite it WITH the existing unit
  coverage (`BilingualCSSInjectionTests`) that the rule reaches the Readium/Foliate
  delivery paths.

## Verdict

**ship-as-is.** 6 tests GREEN. Supports the #304 verification-exception close
together with the existing `BilingualCSSInjectionTests` plumbing coverage.
