---
branch: fix/issue-621-epub-cross-chapter-highlight-r3
threadId: 019e3959-f6f8-70f1-92be-a8e36ac081e0
rounds: 3
final_verdict: ship-as-is
date: 2026-05-18
---

# Codex audit — Bug #182 / GH #621 round-3: EPUB cross-chapter search highlight

## Scope

One production file, one test file:

- `vreader/Views/Reader/EPUBHighlightBridge.swift` — `searchHighlightJS`
- `vreaderTests/Views/Reader/EPUBHighlightBridgeTests.swift` — 4 new tests

### The bug (round-3 residual defect)

Bug #182's round-1 (defer the highlight JS to `webView(_:didFinish:)`) and
round-2 (`SearchHitToLocatorResolver.cleanSnippetForTextQuote` — strip HTML
markup from the search snippet) both landed, but the user-visible symptom —
*tap a cross-chapter search result → no yellow highlight* — persisted.
Verify-cron round-5 (`dev-docs/verification/bug-182-20260516.md`) proved via
`vreader-debug://eval?bridge=epub` DOM probes that chapter-2's DOM loads
correctly with the search term present, the JS works when injected directly
(`.vreader_search_highlight` count 0→1), but via the `pendingHighlightJS`
stash → `didFinish` consume pipeline the count stays 0.

### Round-3 diagnosis

The Swift stash→consume pipeline delivers the JS correctly — traced:
`pendingHighlightJS` is stashed in `EPUBWebViewBridge.updateUIView`'s
URL-change branch and consumed in `webView(_:didFinish:)`, with no clearing
in between and a single `WKWebView`/`Coordinator` instance (no stale-webview
race). The real cause: `searchHighlightJS` ran `window.find()` exactly once,
synchronously at `didFinish`. At that instant the freshly-loaded EPUB chapter
has not finished its post-load relayout — foliate-js `cssPreprocessJS` (a
`WKUserScript` injected `atDocumentEnd`) rewrites every `-epub-*` /
`page-break-*` CSS rule, forcing a style recalc; in paged mode pagination CSS
is also injected at `didFinish`. `window.find()` against the not-yet-settled
document returns `false`, so no span is created. Direct `vreader-debug://eval`
probes succeed because they fire ~1s later, after the DOM has settled.

### The fix

`searchHighlightJS` now wraps the find-and-wrap logic in a bounded
`setTimeout` retry loop (`attemptsLeft = 40`, 50ms cadence ≈ 2s window) that
polls `window.find()` until the rendered text tree is searchable, then stops.
JS-only — the Swift bridge is unchanged.

## Round 1 — findings

| # | location | severity | issue | resolution |
|---|---|---|---|---|
| 1 | EPUBHighlightBridge.swift `searchHighlightJS` | Medium | The retry loop is per-invocation and never cancels older loops; two rapid same-chapter search taps can leave two `attempt()` loops racing, an older loop can reintroduce a stale span after a newer one, and the auto-clear `querySelector` only removed the first `.vreader_search_highlight`. | FIXED — each invocation bumps a `window.__vreaderSearchHighlightGen` generation token; `attempt()` bails at its top when superseded; the 3s auto-clear is gen-guarded; the unwrap logic is a single `clearAll()` helper using `querySelectorAll` (clears ALL spans), shared by the startup clear and the auto-clear (also dedupes the unwrap loop). |
| 2 | EPUBHighlightBridge.swift `searchHighlightJS` | Low | `window.getSelection().removeAllRanges()` ran inside every 50ms poll and was unguarded (null `getSelection()` would abort the retry). | FIXED — one null-guarded `removeAllRanges()` before the retry loop. A failed `window.find()` leaves the (empty) selection unchanged, so one clear is sufficient for find-from-top semantics. |
| 3 | EPUBHighlightBridgeTests.swift | Low | The new tests were weak substring checks — a broken impl could still pass. | FIXED — strengthened to 4 tests asserting: reschedule (`setTimeout(attempt`), bounded + self-terminating (`attemptsLeft--`, `if (attemptsLeft > 0)`, success `return;`), concurrent-loop guard (`__vreaderSearchHighlightGen`), and the preserved 3s auto-clear. |

## Round 2 — findings

| # | location | severity | issue | resolution |
|---|---|---|---|---|
| 4 | EPUBHighlightBridge.swift `searchHighlightJS` | Low | The rare `window.find() === true` / `sel.rangeCount === 0` path fell through to the retry without resetting selection state — the next `window.find()` could continue from an indeterminate cursor. | FIXED — an `else if (sel) { sel.removeAllRanges(); }` branch resets the selection before the decrement+reschedule when a match produced no usable range. |
| 5 | EPUBHighlightBridge.swift `searchHighlightJS` | Low | `range.extractContents()` / `range.insertNode(span)` were unguarded; a range invalidated mid-relayout during a retry would throw and abort the whole invocation instead of consuming one bounded attempt. | FIXED — the wrap-and-insert block is wrapped in `try { … return; } catch (e) { sel.removeAllRanges(); }`; a transient throw clears the selection and falls through to the bounded retry. A span created-but-un-inserted on throw is detached and GC'd — no DOM leak. |

Round 2 also raised the file-size question: `EPUBHighlightBridge.swift` is
337 lines (was 309 pre-fix), over the ~300 guideline. Codex recommended
**ship as-is** — the diff is cohesive and localized; extracting the
search-highlight JS into its own `EPUBSearchHighlightJS.swift` is reasonable
cleanup but "not the right trade in a focused bug-fix review unless you are
already doing another pass there." Deferred: split the section if the file
grows again.

## Round 3 — verification

Zero remaining findings. Codex confirmed both round-2 fixes are correct and
introduce no new issues: the `found===true / rangeCount===0` path now resets
selection deterministically without returning to per-poll clearing, and the
`try/catch` makes a transient invalid range consume one attempt instead of
aborting the bounded retry window. Combined with the generation guard,
bounded attempts, and the `clearAll()` helper, all prior-round issues are
closed.

**Final verdict: ship-as-is.**

## Verification note

The unit tests are structural assertions on the generated JS string — the
real find-and-wrap behavior in a live `WKWebView` is not unit-testable (same
constraint the round-1 `EPUBWebViewBridgeCoordinatorPendingHighlightJSTests`
file documents). Post-merge close-gate verification re-runs the cross-chapter
search-result-tap repro with a `vreader-debug://eval?bridge=epub` DOM probe
(the same CU-free methodology verify-cron used in rounds 2 and 5) — pending
CU/device availability; the GH issue stays open with
`awaiting-device-verification` until then.
