---
branch: feat/feature-76-wi1-logical-offset
threadId: codex-exec-readonly
rounds: 1
final_verdict: ship-as-is
date: 2026-05-31
---

# Codex audit — Feature #76 WI-1 (Swift-seam: canonical logical-offset)

Read-only `codex exec` audit. Foundational WI (Swift-seam portion). No findings.

## Summary

Added `FoliateScrolledWindowMath.logicalOffset(rawOffset:sign:)` +
`rawOffset(logicalOffset:sign:)` — the canonical raw↔logical scroll-offset
conversion (Gate-2 audit's "one canonical logical-offset API") so RTL /
vertical-rl's negative WebKit `scrollLeft` (sign -1) maps to the reading-order
positive logical offsets the existing windowing math consumes. `sign +1` is
identity → Feature #73 vertical-scroll callers byte-unchanged. The JS side
(`paginator.js` `getDirection` writingMode + `#logicalScrollOffset` routing of
all callers + `#container` layout + windowed-primitive axis-awareness) is the
remaining device-dependent bulk of WI-1/2/3.

## Findings

None. Codex confirmed: sign convention correct; `rawOffset` exact inverse for
±1; `sign +1`/`0` identity; composes with `intraSectionFraction`/section math;
pure/Sendable.

## Verdict

ship-as-is. Tests: `FoliateScrolledWindowMathTests` 19/19 (existing + 4 new:
positive-identity, negative-RTL-map, round-trip, feeds-section-math). This is the
Swift mirror; the vendored-`paginator.js` rework is the device-dependent
remainder of #76.
