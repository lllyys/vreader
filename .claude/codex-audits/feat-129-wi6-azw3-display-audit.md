---
branch: feat/129-wi6-azw3-display
threadId: 019f4e7c-69ab-7841-a11a-3af25846778e
rounds: 1
final_verdict: ship-as-is
---

# Gate-4 audit — feature #129 WI-6 (Android AZW3 reader Display settings)

Independent Codex audit (gpt-5.5, high effort) of the WI-6 diff: apply the shared
`ReaderSettings` (theme + typography) to the AZW3 (foliate-js WebView) reader by
injecting a deterministic CSS blob through the foliate bridge `readerAPI.setStyles`
seam. Read-only sandbox; author/auditor separation preserved (rule 47 Gate-4).

Raw output: `.reports/wi6-audit-r1.txt`. Session id `019f4e7c-69ab-7841-a11a-3af25846778e`.

## Round 1 — verdict: ship-as-is (1 Low, fixed)

**Critical / High / Medium: none.**

The auditor confirmed:
- CSS generation matches the WI-6 plan: `html, body` font-size (px) + line-height
  (multiplier), the fixed-selector descendant cascade-flatten, heading `font-size:
  revert`, serif/sans stacks, the exact five theme hex values, the descendant
  `color: inherit` reset, and the margin as `body { padding }`.
- Settings-derived CSS is deterministic (byte-identical for equal settings).
- Production JSON-encodes the CSS (`Json.encodeToString(String.serializer(), css)`)
  before `evaluateJavascript`, and the bridge uses `addWebMessageListener`, NEVER
  `addJavascriptInterface`.
- The re-apply flow is sound: a pre-book-ready `setStyles` records `pendingStylesCss`
  and is re-applied at `BookReady`; live settings changes re-inject; holder recreation
  on render-process death re-records the current CSS for the new document.

### Low (fixed in this branch)

- **Test pinned a parallel copy of the JS builder, not the production seam.**
  `Azw3DisplayCss.foliateSetStylesJs` (test-verified) duplicated the JS-shell +
  JSON escaping that `FoliateBridge.setStyles` built separately with its own private
  `jsString`. Equivalent + injection-safe today, but future drift could leave the
  security test green while `evaluateJavascript` used different escaping.
  **Resolution:** moved the builder into the foliate package as a single shared
  top-level `foliateSetStylesJs(css)`; `FoliateBridge.setStyles` now calls it, and
  `Azw3DisplayCssTest` imports and pins that exact production function. The
  duplicate + its private `jsString` were removed from `Azw3DisplayCss.kt`.
  JVM CSS test re-run green; main + androidTest compile clean.

Zero open Critical/High/Medium; the single Low is fixed. Gate-4 clean in 1 round.
