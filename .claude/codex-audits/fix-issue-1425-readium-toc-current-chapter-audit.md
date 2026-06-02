---
branch: fix/issue-1425-readium-toc-current-chapter
threadId: codex-exec (run-codex.sh, 2 rounds)
rounds: 2
final_verdict: follow-up-recommended
date: 2026-06-03
---

# Codex audit — Bug #313 (GH #1425): Readium TOC current-chapter wiring

## Fix summary

The Readium EPUB host was the only format host that never posted
`.readerPositionDidChange`, so `ReaderContainerView.currentLocator` stayed nil
for Readium EPUBs → `TOCSheet` couldn't highlight/scroll to the current chapter
(and the AI-panel locator was stale). Fix: a testable seam
`ReadiumPositionBroadcast.post(_:on:)` / `spineResolved(_:spineHrefs:)`, wired
into the host's `onLocationChange` closure.

Changed files:
- `vreader/Views/Reader/ReadiumPositionBroadcast.swift` (new)
- `vreader/Views/Reader/ReadiumEPUBHost+Body.swift` (closure posts via the seam)
- `vreaderTests/Views/Reader/ReadiumEPUBHostTests.swift` (`ReadiumPositionBroadcastTests`, 7 tests)

## Round 1

| file:line | severity | issue | resolution |
|---|---|---|---|
| ReadiumEPUBHost+BilingualDriver.swift:284 | Medium | `post(currentVReaderLocator(from: locator))` can post an unresolved/stale href (`currentVReaderLocator` falls back to `lastEnumeratedHref`; `normalizedLocator` keeps the raw href when unresolvable) → overwrites a good `currentLocator` with a non-TOC-matchable position. | **Fixed.** Added `spineResolved(_:spineHrefs:)` gate — posts only when the locator's href ∈ `bilingualSpineHrefs` (the exact form `normalizedLocator` rewrites a resolvable href to, and the form `TOCSheet` matches by). Unresolved → no-op, previous `currentLocator` preserved. |
| ReadiumEPUBHostTests.swift:262 | Low | New tests were seam-only (post + nil-noop), not the decision path. | **Fixed.** Added 4 `spineResolved` tests (in-spine / not-in-spine / nil / empty-spine) + 1 e2e-through-gate test asserting only the resolvable href reaches the bus. Host `onLocationChange` wiring itself is device-verified per the host's established test boundary (the View render is not unit-instantiated). |

Round-1 open questions (Codex): no feedback loop (consumer only updates local
state/AI context, never relocates); ordering safe; no Sendable/@MainActor
hazard. All confirmed.

## Round 2 (verify)

| file:line | severity | issue | resolution |
|---|---|---|---|
| ReadiumPositionBroadcast.swift:47 / ReadiumEPUBHost+Body.swift:129 | Medium | Original overwrite bug confirmed resolved, BUT for a duplicate-basename spine `normalizedLocator` leaves the href raw → `spineHrefs.contains(href)` is false → a legitimate relocate is dropped (TOC/AI stays stale). Suggested an index-based `readingOrder`→`spineItems` remap. | **Downgraded to Low + accepted with rationale + follow-up filed (Bug #318 / GH #1446).** The conservative skip is the same no-highlight outcome as pre-fix for those rare books (minus AI-locator pollution) — strictly not a regression. Codex's index-remap would risk highlighting the WRONG chapter if Readium's `readingOrder` and vreader's parser `spineItems` ever diverged (two independent parsers); "no highlight" is preferable to "maybe-wrong highlight." The complete fix (a verified-parallel index map that degrades to the skip when the lists aren't provably 1:1) is tracked as low-priority Bug #318. Comment in `ReadiumPositionBroadcast.swift` corrected to state this limitation accurately (was overclaiming "posts every real relocate"). |

## Verdict

`follow-up-recommended` — zero open Critical/High/Medium; the one round-2
Medium is downgraded to Low and accepted (conservative-by-design, no regression,
no wrong-chapter risk) with the complete fix tracked as Bug #318. Fix ships.
