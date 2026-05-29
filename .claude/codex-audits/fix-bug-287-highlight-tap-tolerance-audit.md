---
branch: fix/bug-287-highlight-tap-tolerance
threadId: 019e7xxx-codex-exec
rounds: 2
final_verdict: ship-as-is
date: 2026-05-30
---

# Gate-4 Codex Audit — Bug #287 / GH #1268 (highlight tap-target tolerance)

Audit driven by `codex exec --sandbox read-only - < /tmp/audit-287-prompt.md`
(read-only; auditor independent of the implementing Claude Code session).
The prompt carried the full diff-against-HEAD + the two new files inline so the
read-only sandbox did not need the working tree.

## Round 1 — verdict: changes-required (1 High, 2 Medium, 1 Low)

1. **High — PDF lost "exact hit first, tolerance fallback second."**
   `PDFHighlightTapResolver.resolveHighlightIDWithTolerance` ran nearest-center
   over expanded rects for *every* tap, so a tap squarely inside highlight A
   could resolve to a nearby highlight B whose expanded band also covered the
   point and whose center was closer. Violated the stated invariant.
   - **Fix**: `resolveHighlightIDWithTolerance` now calls the exact
     `resolveHighlightID` first and only consults the tolerance band on a nil
     (exact) result. (`PDFHighlightTapResolver.swift`.)

2. **Medium — EPUB tolerance fallback unreachable on caret failure.**
   The click handler did `catch (err) { return; }` and `if (!hitNode) return;`
   before the slop fallback — but line gaps / adjacent whitespace (exactly
   where a near-miss lands) are where `caretPositionFromPoint` /
   `caretRangeFromPoint` fail or return null.
   - **Fix**: caret failure now sets `hitNode = null` (no early return); the
     exact `compareBoundaryPoints` loop is guarded by `probe` so a null probe
     skips it and the handler falls through to `__vreader_tapSlopHit`.
     (`EPUBHighlightJS.swift`.)

3. **Medium — single union bounding box over-absorbs multi-line whitespace.**
   TXT/MD/chunked-TXT and EPUB built one candidate rect from the whole range's
   bounding box; for a multi-line (ragged-edge) highlight that union includes
   unhighlighted whitespace between line fragments, so a tap in the gap could
   be absorbed.
   - **Fix**: candidates are now built per visual line fragment —
     `NSLayoutManager.enumerateEnclosingRects(forGlyphRange:…)` for TextKit
     (`TextHighlightHitResolver.swift`, `TXTChunkedReaderBridge.swift`) and
     `range.getClientRects()` for EPUB (`EPUBHighlightJS.swift`). The union
     `getBoundingClientRect` is kept only for popover anchoring.

4. **Low — zero-area rect inflated into a 44x44 tappable region.**
   `HighlightHitTolerance.nearestHit` accepted `width >= 0 / height >= 0`, and
   the PDF path appended annotation bounds without filtering, so a malformed
   zero-area annotation became a full 44x44 hit target.
   - **Fix**: `nearestHit` now requires `width > 0 && height > 0`; the PDF
     candidates inherit the filter. (`HighlightHitTolerance.swift`.)

All four findings fixed in-branch; regression tests added:
`HighlightHitToleranceTests.nearestHit_zeroAreaRect_*`,
`PDFHighlightTapResolverTests.resolveWithTolerance_exactHitBeatsNearerToleranceBand`
+ `_zeroAreaAnnotation_doesNotBecomeTappable`,
`EPUBHighlightTapBridgeTests.highlightAPIJS_tapSlopHit_usesPerFragmentClientRects`
+ `_caretFailureFallsThroughToSlop`.

## Round 2 — verdict: ship-as-is

Re-audit of the four fixes confirmed the exact-first ordering, the caret
fall-through, the per-fragment candidate construction, and the zero-area guard.
Zero open Critical/High/Medium findings.

## Scope note — Foliate (AZW3/MOBI)

Foliate's tap-on-highlight path has **no point hit-test** to expand: the
`annotation-show` event from foliate-js fires only on an exact tap of the
rendered SVG overlay, and `FoliateSpikeView+HighlightTap.swift` forwards a
`.zero` sourceRect (foliate-host.js does not forward the annotation rect). There
is no Swift-side point→highlight resolution to add tolerance to without modifying
the vendored foliate-js paginator. Left as a documented follow-up in the bug row
(out of scope for this bounded fix). The other four formats (TXT/MD/PDF/EPUB)
are fixed.
