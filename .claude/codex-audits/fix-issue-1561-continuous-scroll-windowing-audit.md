---
branch: fix/issue-1561-continuous-scroll-windowing
threadId: 019e9e06-a015-7533-a49e-62b01c686d25
rounds: 1
final_verdict: ship-as-is
date: 2026-06-07
---

# Codex audit — Bug #327 / GH #1561 continuous-scroll windowing fix

Audit of the directional-eviction + integer-0 parse fix for the "EPUB scroll
mode STICKS / can't continue scrolling" residual (the windowed continuous-scroll
half of Bug #327, after the v3.59.18 double-scroller fix).

## Scope (Swift diff vs `main`)

- `vreader/Views/Reader/EPUBSpineWindow.swift` — replaced `evictFarFromAnchor(maxSpan:)`
  with directional `evictTrailing(forward:maxSpan:)`.
- `vreader/Views/Reader/EPUBContinuousScrollCoordinator.swift` — `extend(forward:)`
  uses `evictTrailing`; removed `allowEvict`/geometry-gated no-evict branch;
  `EPUBScrollBoundarySignal` reverted to its 4 original fields.
- `vreader/Views/Reader/EPUBContinuousScrollBridge.swift` — `EPUBScrollBoundarySignal.parse`
  int/double coercers test the `NSNumber` branch FIRST and discriminate a real
  boolean via `CFGetTypeID(n) == CFBooleanGetTypeID()` (integer-0 reports now
  accepted); reverted the scrollHeight/clientHeight passthrough.
- `vreader/Views/Reader/EPUBContinuousScrollJS.swift` — observer report reverted
  to 4 fields.
- tests: `EPUBSpineWindowTests`, `EPUBContinuousScrollCoordinatorTests`,
  `EPUBContinuousScrollBridgeTests`, `EPUBContinuousScrollJSTests`.

## Findings

**No findings** (Critical/High/Medium/Low all zero).

## Residual risk (acknowledged, accepted)

`EPUBSpineWindow.swift` (`evictTrailing`) / `EPUBContinuousScrollCoordinator.swift`
(`extend`) intentionally allow `span > maxSpan` while the topmost-visible anchor
lags the trailing edge. Codex confirmed no unbounded-growth sequence exists from
this diff: re-anchoring tracks the topmost visible section on every boundary
signal, so the overage is bounded by how many short sections fit within the
effective visible/prefetch height (≈ one viewport of short chapters — cheap),
not by repeated eviction mistakes. The append/remove loop still matches the DOM
one section at a time (`singleDroppedIndex` + post-`await` generation guards).
The `NSNumber`/`CFBooleanGetTypeID` parse fix correctly accepts integer `0` while
rejecting real booleans (Int / integer-Double / true / false / NaN / Inf all
handled). No remaining `evictFarFromAnchor`/old-payload references in the audited
files. Existing tests cover forward/backward lagging-anchor eviction plus
initial-window and navigate-rebuild regressions.

## Verdict

**ship-as-is.** Codex (session `019e9e06-a015-7533-a49e-62b01c686d25`,
read-only) returned no findings. Tests were not run inside the audit; the four
affected suites pass under `scripts/run-tests.sh` (verified separately).
