---
branch: fix/bug-286-txt-toc-chapter-detection
threadId: 019e74e9-6532-7f71-85c2-105714f55a1d
rounds: 2
final_verdict: ship-as-is
date: 2026-05-30
---

# Gate-4 Codex audit — Bug #286 (GH #1267): TXT TOC navigates to the wrong chapter

Independent Codex audit (cc-suite / `codex exec --sandbox read-only`) of the
fix that routes the TXT table-of-contents builder through the same decode +
full-text chapter-detection pipeline the reader uses, so TOC entry offsets
land exactly on reader chapter starts.

Files audited:
- `vreader/Services/TXT/TXTService.swift`
- `vreader/Views/Reader/ReaderTOCBuilder.swift`
- `vreaderTests/Views/Reader/ReaderTOCTXTAlignmentTests.swift`

## Round 1 — verdict: follow-up-recommended

Thread `019e74e6-04f1-78a1-a388-56667bc72f96`.

Findings:

- **Critical / High:** none.
- **Medium (M1):** the new tests validated `TXTService.buildTXTTOCEntries`
  directly, not the production `ReaderTOCFactory.buildTOC(format:"txt", …)`
  path. A wiring regression could pass the tests.
- **Medium (M2):** the "pattern-shift after 512KB" test used the same `第N章`
  rule before and after the boundary, so it proved full-text extraction but not
  rule-selection parity across a genuine competing-pattern shift.
- **Low:** comments said "detect rule from full text" but `detectBestRule`
  samples the first 512K UTF-16 for the *decision*. Wording corrected.
- **Low:** `offset == 0 && title == "前言"` is a title-sentinel; safe because no
  current rule matches literal `前言` (the symbol exists only as the synthetic
  preamble title in `buildChapterIndexFromFullText`). Accepted as-is — a future
  rule for literal `前言` would need structural tagging; out of scope here.
- **Low (confirmed not-dead-code):** `TOCBuilder.forTXT(text:)` is still used by
  `TOCBuilderTXTTests`; `detectEncodingFromSample` / `encodingFromName` remain
  used by TXT decoding, chapter loading, and `BookContentCache`. Not orphaned.

Round-1 confirmations: fix is directionally correct (TOC and reader now share
one decoder + one chapter-index builder); navigation stays offset-based via
`TXTReaderViewModel.navigateToTOCTap` → `navigateToGlobalOffset`, so bug #234 is
NOT reintroduced; `static` methods on the `TXTService` actor are nonisolated and
synchronously callable from `ReaderTOCFactory` — no actor-isolation violation.

## Author fixes applied

- **M1:** added `productionPathAlignment` — writes the GBK ASCII-head fixture to
  a temp file, calls `await ReaderTOCFactory.buildTOC(format:"txt", …)`, opens
  the same file via `TXTService.openChapterBased`, and asserts every TOC entry
  offset is a chapter `globalStartUTF16`.
- **M2:** rewrote `patternShiftAlignment` — first >512KB dominated by `第N章`
  (family A), tail switches to `Chapter N` (family B). Asserts the past-boundary
  `第N章` chapter is present + aligned AND that no family-B `Chapter ` heading
  becomes a TOC entry (the chosen rule is `第N章` and both passes agree).
- **Low:** reworded the two source comments to state that `detectBestRule`
  samples 512K for the decision then extracts over the full decoded string.

## Round 2 — verdict: ship-as-is

Thread `019e74e9-6532-7f71-85c2-105714f55a1d`.

"No new findings." Both Medium findings resolved; no new correctness,
concurrency, or edge-case issues; the production-path test would fail on the
important wiring regression (reverting to the pre-fix sample-detect/raw-UTF-8
TXT decode → empty/divergent entries on the GBK fixture).

## Test gate

`xcodebuild test -only-testing:vreaderTests` (iPhone 17 Pro, UDID
`61149F0E-DC18-4BE2-BB37-52659F1F4F62`, `-parallel-testing-enabled NO`):
**8208 passed, 0 failed, 6 skipped.** New suite `ReaderTOCTXTAlignmentTests`:
8/8 passing. (Earlier full-suite runs showed 4–5 `signal kill`/`signal term`
crashes in unrelated subsystems — backup, PDF import, cache pre-extract,
auto-page-turn timer — that all passed in isolation and on a clean-sim retry;
environmental simulator flake, not test failures.)

RED demonstration: temporarily reverting `decodeTXTForTOC` to the pre-fix decode
(sample-hint + raw `String(data:encoding:)`, UTF-8-only fallback) made the GBK
ASCII-head tests fail exactly as the bug predicts — `entries.count → 0` (TOC
empty) and `decodeTXTForTOC → nil` while the reader's `decodeForDisplayAndSearch`
succeeded (decode-parity broken). Restored to GREEN for the shipped fix.
