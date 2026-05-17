---
branch: fix/issue-828-epub-tap-delete-stale-paint
threadId: 019e3537-b753-7ae3-b07b-a6f356438ea9
rounds: 3
final_verdict: ship-as-is
date: 2026-05-17
---

# Codex audit — issue #828 (Bug #212): EPUB tap-Delete leaves stale highlight paint

## Scope

Files audited:

- `vreader/Views/Reader/EPUBHighlightJS.swift` — the fix: a new
  `forceRangeRepaint` / `repaintBlockFor` / `repaintElement` helper
  trio added to the embedded `highlightAPIJS` bundle, plus
  `__vreader_removeHighlight` now captures the highlight's `Range`
  from the registry and hands it to `forceRangeRepaint` after
  clearing CSS Highlight API state. The repaint forces the affected
  text block(s) to re-rasterize (`display:none` → forced synchronous
  reflow → restore), because deleting a `CSS.highlights` entry does
  not reliably invalidate an already-composited paged/columned EPUB
  column.
- `vreaderTests/Views/Reader/EPUBHighlightTapBridgeTests.swift` —
  regression-guard test `highlightAPIJS_removeHighlight_forcesRepaintOfAffectedRange`,
  a JS-bundle string-assertion test (the repo has no JS-execution
  harness; mirrors the suite's existing strategy).

## Round 1 — findings

| # | file:line | severity | issue | resolution |
|---|---|---|---|---|
| 1 | EPUBHighlightJS.swift (`forceRangeRepaint`) | Medium | First version repainted `range.commonAncestorContainer` directly. For a cross-block/cross-paragraph highlight that ancestor can be a large wrapper, `<body>`, or `<html>` — turning a targeted repaint into a full-chapter remove/reinsert that repaginates columns and resets the paged-column scroll position. | **Fixed.** Replaced with a boundary-derived `repaintBlockFor(node)` that resolves `range.startContainer` / `range.endContainer` to bounded targets and returns `null` for `<body>` / `<html>` / document root. `forceRangeRepaint` repaints the start block, the end block, and (when they are siblings) the bounded set of blocks between them (`guard < 64`). |
| 2 | EPUBHighlightTapBridgeTests.swift | Low | The regression test only proved the bundle contained the tokens `forceRangeRepaint` / `offsetHeight` / `style.display` somewhere — it would still pass if `__vreader_removeHighlight` stopped capturing the range or stopped invoking the helper. | **Fixed** (completed in round 2): the test now slices the bundle to `__vreader_removeHighlight`'s body and asserts the capture + registry-delete + helper-call within that slice. |

## Round 2 — findings

| # | file:line | severity | issue | resolution |
|---|---|---|---|---|
| 3 | EPUBHighlightJS.swift (`repaintBlockFor`) | Low | Inline-boundary gap: for a multi-paragraph highlight that starts/ends inside inline markup (`<em>`, `<span>`, …), `startEl`/`endEl` resolved to those inline elements, the `startEl.parentElement === endEl.parentElement` sibling test failed, and the middle paragraphs never got repainted. | **Fixed.** Added an inline-tag climb (`REPAINT_INLINE_TAGS`, keyed by lowercase `localName`) so each boundary normalizes up to its containing text block before the sibling comparison. |
| 4 | EPUBHighlightTapBridgeTests.swift | Low | The round-1 test fix still asserted `var range = window.__vreader_highlightRanges[id];` against the whole bundle — that line could be satisfied by the click-hit-test path, so removeHighlight could stop capturing the range and the test would still pass. | **Fixed.** Test now slices the bundle from `window.__vreader_removeHighlight = function(id) {` to the next function (`window.__vreader_clearAllHighlights`) and asserts the capture / registry-delete / `forceRangeRepaint(range);` call *inside that slice*. |

## Round 3 — verification

**No findings.** Codex confirmed the fix is correct and complete:

- The inline-boundary gap is closed; normalizing through
  `REPAINT_INLINE_TAGS` before the sibling check makes the
  "repaint start/end blocks plus bounded siblings between them"
  logic match the intended block-level behavior.
- The `el.localName` (lowercase) lookup with a lowercase-keyed table
  is correct: EPUB chapters load as `application/xhtml+xml` where
  `tagName` is case-sensitive and authored lowercase — an
  uppercase-keyed `tagName` lookup would silently never match and
  the climb would be dead code.
- The test now genuinely pins `__vreader_removeHighlight`'s body;
  the slice prevents the assertions from being satisfied by the
  click-hit-test path.
- The `display:none` → `void el.offsetHeight` → restore sequence is
  a real render-object rebuild; the forced layout read prevents the
  two style writes from being coalesced into a no-op, and the
  "no paint between writes within one JS turn" reasoning is correct.
- Returning `null` from `repaintBlockFor` for the pathological
  bare-text-in-`<body>` chapter is the right safety tradeoff — it
  avoids whole-chapter repagination/scroll jumps and only preserves
  the pre-existing stale-paint behavior in that rare structure (no
  regression vs. the original all-stale bug).

Scope note (raised by Codex, not a defect): `__vreader_clearAllHighlights`
does not need the same nudge — it has no live "clear all without
reload" call site; it is invoked on chapter/book swap, which reloads
the chapter DOM. If a future "clear all in place" path is added it
would need the same (root-safe) repaint strategy.

Residual gap (pre-existing, codebase-wide): there is still no
executable WebKit/JS test harness for the embedded `highlightAPIJS`
bundle, so JS syntax/runtime regressions remain outside unit-test
coverage. The string-assertion guard is the appropriate lightweight
mitigation for this repo. Device verification (Phase 9) exercises the
real WebKit path.

## Verdict

**ship-as-is.** Three rounds: round 1 (1 Medium + 1 Low) and round 2
(2 Low) all fixed; round 3 clean — zero open Critical/High/Medium/Low
findings. The repaint is bounded (never rebuilds `<body>`/`<html>`),
handles single-block, multi-block-sibling, and inline-boundary
highlights, and the regression test pins the actual remove path.
