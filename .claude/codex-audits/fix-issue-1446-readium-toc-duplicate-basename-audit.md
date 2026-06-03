---
branch: fix/issue-1446-readium-toc-duplicate-basename
threadId: codex-exec (run-codex.sh)
rounds: 1
final_verdict: ship-as-is
date: 2026-06-03
---

# Codex audit — Bug #318 (GH #1446): Readium TOC duplicate-basename index map

## Fix summary

Completes #313's duplicate-basename edge. #313's `spineResolved` skipped a Readium
relocate when the normalized href wasn't in `bilingualSpineHrefs` — which happens
for a spine with duplicate basenames, where `ReadiumBilingualCommander.normalizedLocator`
leaves the href RAW (its Readium reading-order form). The skip meant no
current-chapter highlight for those rare books.

Fix: `spineResolved` gains a `readingOrderHrefs` fallback — when the raw href is
found in `readingOrderHrefs` at index `idx` AND `readingOrderHrefs.count ==
spineHrefs.count` (verified-parallel), it adopts `spineHrefs[idx]` (via
`Locator.replacingHref`). A divergence (unequal counts) degrades to the
conservative skip, so it never pins the WRONG chapter. The call site passes
`publication.readingOrder.map(\.href)`.

Changed files:
- `vreader/Views/Reader/ReadiumPositionBroadcast.swift`
- `vreader/Views/Reader/ReadiumEPUBHost+Body.swift`
- `vreaderTests/Views/Reader/ReadiumEPUBHostTests.swift` (4 index-fallback tests)

## Round 1 — CLEAN

Codex confirmed, tracing the code:
1. The equal-count guard is sound in practice — both arrays come from OPF spine
   order (`EPUBParser` builds `metadata.spineItems` in OPF order; Readium's
   `readingOrder` is the spine). No concrete wrong-chapter path; a hypothetical
   reordered-but-equal-count divergence would be a deeper parser/Readium contract
   break, not introduced here.
2. **The raw-case href is the same string space as `readingOrder.map(\.href)`** —
   `currentVReaderLocator` starts from `readiumLocator?.href.string`, and
   `normalizedLocator` keeps that raw href when ambiguous, so the fallback compares
   Readium `Locator.href.string` against Readium `Link.href` (the right pairing).
   This validates the fix's load-bearing assumption.
3. `replacingHref` preserves every `Locator` field except `href`.
4. Backward-compatible: existing #313 callers omit `readingOrderHrefs` (default
   `[]`) → guard fails → old conservative skip.
5. No new defect. Residual: the tests don't prove the parallel-lists assumption
   against a real duplicate-basename EPUB fixture — a testing gap (device
   verification), not a correctness bug.

## Verdict

`ship-as-is` — zero findings. The duplicate-basename case can't be reproduced
without a crafted EPUB fixture (no real book has it), so it merges
`awaiting-device-verification`. The index-map logic + the string-space pairing are
unit-proven and Codex-validated.
