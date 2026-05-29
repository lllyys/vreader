---
branch: fix/bug-278-epub-scroll-font-reinject
threadId: codex-exec-read-only (no thread id; codex exec one-shot)
rounds: 1
final_verdict: ship-as-is
date: 2026-05-29
---

# Codex Audit Log — Bug #278 (GH #1255)

Fix: EPUB font-size slider had no live effect in continuous-scroll mode (the
default: legacy engine + `.scroll` layout). `EPUBWebViewBridge.updateUIView`
returned early when `continuousScroll != nil` BEFORE the paged theme-change
cascade (`injectThemeCSSJS`), so a font-size / line-height / font-family slider
change never re-injected — it only took effect on book reopen. Paged mode + the
Readium engine already live-applied correctly.

## Scope of audit

Codex (`codex exec --sandbox read-only`, one-shot) audited the focused 2-file
production diff:

- `vreader/Views/Reader/EPUBWebViewBridgeJS.swift` — new pure decision seam
  `continuousThemeReinjectJS(previousCSS:newCSS:) -> String?` (inject / remove /
  nil), mirroring the paged theme-change branch.
- `vreader/Views/Reader/EPUBWebViewBridge.swift` — `updateUIView`'s
  continuous-scroll branch now re-injects `#vreader-theme` into the bootstrap
  `document.head` via the live `webView.evaluateJavaScript` on a theme change,
  after the bootstrap is loaded.

The test-only file (`EPUBWebViewBridgeTests.swift`, new
`EPUBWebViewBridgeContinuousThemeReinjectTests` suite) was not part of the
audited production surface.

## Audit prompt focus

Correctness (re-inject reaches ALL materialized sections, not one; CSS
cascade/specificity vs the bootstrap's anonymous baked-in style), double-apply /
idempotency, first-pass race vs bootstrap `didFinish`, paged-mode regression, JS
injection safety (FoliateJSEscaper), Swift 6 @MainActor / Sendable, and
interaction with the continuous-scroll coordinator's separate evaluator handle.

## Findings

**Verdict: ship-as-is. Zero Critical / High / Medium / Low findings.**

1. **Correctness** — Re-inject reaches the whole continuous document. Sections
   are body descendants of the SAME DOM; `#vreader-theme` is appended to
   `document.head`, so its `html, body` rules cascade across already-materialized
   AND future `<section>`s. Inserted AFTER the bootstrap's anonymous baked-in
   `<style>`, so equal-specificity `!important` font-size rules win by source
   order. No stale-bootstrap-wins scenario found for the font-size path.
2. **Double-apply / idempotency** — None. `continuousThemeReinjectJS` returns
   `nil` on unchanged CSS; `injectThemeCSSJS` removes any existing `#vreader-theme`
   before appending. `coordinator.themeCSS` is updated before the eval, matching
   the paged path, preventing repeated evals on unrelated SwiftUI refreshes.
3. **First-pass race** — No lost-change defect. If the slider changes before the
   bootstrap's `didFinish`, the branch still updates `coordinator.themeCSS`; the
   coordinator's `didFinish` handler then injects the coordinator's latest
   `themeCSS` (EPUBWebViewBridgeCoordinator.swift:445), repairing any premature
   eval against a loading document.
4. **Paged regression** — Paged path untouched; its live theme cascade remains
   (EPUBWebViewBridge.swift, post-`return` cascade). The diff is wholly inside the
   `continuousScroll != nil` branch.
5. **JS safety** — No new injection surface. The seam only routes the string to
   the existing `injectThemeCSSJS`, which extracts the inner CSS and escapes it
   through `FoliateJSEscaper.escapeForJSString`.
6. **Concurrency** — No isolation issue. `updateUIView` runs on the main/UI
   context; the `evaluateJavaScript` completion closure captures no actor-isolated
   mutable state.
7. **Coordinator interaction** — Mixing direct `webView.evaluateJavaScript` for
   the global head CSS with the coordinator's section-materialization evaluator is
   acceptable: existing sections restyle via normal CSS recalculation, future
   sections inherit the already-installed head style.

## Resolution

No fixes required. Diff merged as audited.
