---
branch: fix/845-debugbridge-epub-highlight-driver
threadId: 019e4485-37a1-7f60-bf86-dca766483924
rounds: 2
final_verdict: ship-as-is
date: 2026-05-20
---

# Codex Gate-4 audit — Bug #220 / GH #845 (EPUB DebugBridge highlight-driver)

**Branch**: `fix/845-debugbridge-epub-highlight-driver`
**Thread id**: `019e4485-37a1-7f60-bf86-dca766483924`
**Final verdict**: `ship-as-is` (after 2 rounds)

## Summary

Ships the EPUB counterpart of PR #1047 (TXT/MD highlight-driver). Adds a
DEBUG-only EPUB observer + JS helper so the existing
`vreader-debug://highlight?start=<int>&end=<int>[&color=<name>]` URL
grammar routes through the EPUB reader when an EPUB is active. The
verification harness can now create EPUB highlights end-to-end CU-free,
unblocking `Feature11EPUBHighlightVerificationTests` which previously
`XCTSkip`ped on the XCUITest long-press that does not reliably trigger
WKWebView text selection on iOS 26.

Files changed:
- `vreader/Views/Reader/EPUBDebugBridgeHighlightJS.swift` (new, 282 lines)
- `vreader/Views/Reader/EPUBReaderContainerView+DebugBridgeHighlight.swift` (new, 217 lines)
- `vreader/Views/Reader/EPUBReaderContainerView.swift` (+10 lines)
- `vreaderUITests/Verification/Feature11EPUBHighlightVerificationTests.swift` (rewritten — bridge-driven)
- `vreaderUITests/Verification/Helpers/VerificationDebugBridgeHelper.swift` (+35 lines)
- `vreaderTests/Views/Reader/EPUBDebugBridgeHighlightJSTests.swift` (new, 216 lines, 13 tests)
- `docs/bugs.md` — Bug #220 TODO → FIXED (post-test-gate)
- `project.yml` + pbxproj — version bump

## Round 1 — 1 High + 3 Medium + 1 Low

### High @ EPUBReaderContainerView+DebugBridgeHighlight.swift:160 — transient JS highlight ID never cleaned up

> "This path paints `transientId`, then persists via
> `HighlightCoordinator.create`, then posts `.readerHighlightsDidImport`,
> which only adds the canonical ID back on top; it never removes the
> transient one. In EPUB, restore is additive, not replace-all, so a
> later delete/recolor can leave the transient paint and transient tap
> target behind on the live page until chapter reload."

**Resolution — fixed**: Refactored the design so the JS NO LONGER paints.
The JS now only resolves the DOM range and returns the serialized range
to Swift. Paint happens via the Swift-side coordinator → renderer
pipeline (`HighlightCoordinator.create` →
`EPUBHighlightRenderer.apply(record:)` →
`EPUBHighlightActions.createHighlightJS(for: record)` →
`__vreader_createHighlight(record.highlightId.uuidString, ...)`) — same
path as the gesture. No transient ID can exist on the live page.

Renamed `buildSelectRangeJS` → `buildResolveRangeJS` to reflect the new
responsibility. Removed `highlightId` and `color` parameters from the
JS builder (the JS doesn't paint, so it doesn't need them).

Added a test asserting the JS does NOT contain `__vreader_createHighlight`.

### Medium @ EPUBReaderContainerView+DebugBridgeHighlight.swift:131 — stale-async state

> "If the user closes the reader or navigates chapters during the JS
> round-trip, you can persist a range computed from a different DOM
> against the old `href`/locator."

**Resolution — fixed**: Added re-validation in the `evaluateJavaScript`
completion. Before persisting:
1. Re-resolve the EPUB WebView from the registry using captured
   `(fingerprintKey, token)` and verify it `===` matches the captured
   `expectedWebView` (weak reference so a dealloc surfaces as `nil`).
2. Verify `viewModel.currentPosition?.href` still equals the captured
   `expectedHref`.

If either check fails, the result is dropped with an info-level log.
Drops stale results from reader-close or chapter-nav that races the
JS round-trip.

### Medium @ EPUBDebugBridgeHighlightJS.swift:195 — surrogate-pair snapping missing

> "UTF-16 offsets are mapped directly to DOM offsets with no surrogate-
> pair snapping. If `start` or `end` lands in the middle of an
> emoji/non-BMP scalar, this can build a half-scalar DOM range and a
> malformed `selectedText`."

**Resolution — fixed**: Added `snapToScalarBoundary(loc, direction)` in
the JS. Detects if `charCodeAt(off-1)` is a high surrogate
(0xD800-0xDBFF) AND `charCodeAt(off)` is a low surrogate (0xDC00-0xDFFF),
meaning the offset falls between the two halves of a non-BMP scalar.
Snaps `start` backward and `end` forward so the resulting range always
surrounds full scalars. Combining-mark sequences (Round-2 confirmed)
remain unsnapped — matching gesture semantics. Added a test asserting
the snap helper and surrogate ranges are present in the JS.

### Medium @ EPUBDebugBridgeHighlightJS.swift:234 — whitespace-only selection accepted

> "Whitespace-only selections are accepted even though the gesture path
> rejects them. `selectionTrackingJS` drops `!text.trim()`, but this
> bridge path only rejects `selectedText.length === 0`, so
> `highlight?start=...&end=...` can persist highlights containing only
> spaces/newlines."

**Resolution — fixed**: Changed the empty-text guard from
`selectedText.length === 0` to `!selectedText || !/\S/.test(selectedText)`.
Matches the gesture path's `!text.trim()` rejection in
`selectionTrackingJS`. Added a test asserting the JS contains the `\S`
regex check.

### Low @ EPUBDebugBridgeHighlightJSTests.swift:22 — no headless WKWebView integration test

> "The new tests only assert string construction and dictionary parsing.
> They do not execute the JS in a real `WKWebView`, so the riskiest cases
> in this fix remain unproven."

**Resolution — accepted with rationale**:

The verification harness (`Feature11EPUBHighlightVerificationTests`)
exercises the full JS-evaluator round-trip on the simulator as the
post-merge close-gate verification. Building a headless `WKWebView`
unit test would duplicate that signal while adding nontrivial XCTest
infrastructure (WebKit isn't easy to instantiate in a unit test
context — typically needs a UIWindow + DOMContentLoaded wait).

The JS uses production-tested algorithms:
- `getXPath` is copied verbatim from
  `EPUBHighlightJS.selectionTrackingJS`'s same-name function (the
  gesture path).
- The DOM-walk + offset map is a straightforward `TreeWalker`
  iteration with a prefix-sum array — no novel algorithm.
- `__vreader_createHighlight` is exercised on every gesture-driven
  highlight in production today, and the bridge-driven path now
  routes through the same renderer call.

The unit tests added in this PR cover the structural shape:
- `test_buildJS_doesNotCallCreateHighlight` — the High fix invariant.
- `test_buildJS_snapsSurrogatePairBoundaries` — Medium #3 fix invariant.
- `test_buildJS_rejectsWhitespaceOnlySelection` — Medium #4 fix invariant.
- `test_buildJS_skipsBilingualDecorationNodes` — XPath parity with `selectionTrackingJS`.
- `test_buildJS_isWrappedInIIFE` — locals don't leak to `window`.

The end-to-end integration signal lands in the device-verification slice.
Codex Round-2 confirmed this acceptance does not introduce a new
correctness gap.

## Round 2 — zero findings

> "No findings.
>
> The Round-1 issues are fixed cleanly. The important behavior changes
> are correct:
>
> - paint exclusively through `HighlightCoordinator.create(...)` and the
>   existing renderer path — transient-ID leak is gone.
> - stale-result guard with `=== expectedWebView` + `href` check blocks
>   close/reopen, same-book-reopen, and chapter-nav races.
> - snap only surrogate-pair splits; combining-mark sequences remain
>   unsnapped, matching gesture semantics.
> - `TreeWalker.nextNode()` yields text nodes in DOM order, so the
>   multi-node `selectedText` composition is stable.
> - the renderer buffering path is acceptable: if `create()` persists
>   and the reader closes before `onInjectJS` can deliver, the visual
>   paint may be dropped for that session, but that does not strand
>   stale UI or data; the persisted highlight restores on reopen
>   through the normal chapter-load restore path."

## Verdict

`ship-as-is`. Two rounds, all High + Medium findings fixed, the Low
accepted with rationale.

## Manual audit evidence

N/A — Codex MCP was available throughout.
