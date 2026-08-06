---
branch: feat/142-wi-2-azw3-annotation-mapper
threadId: 019fd533-4b3e-7890-9ebc-d904f3df9a88
rounds: 2
final_verdict: follow-up-recommended
date: 2026-08-06
---

# Codex Audit Log — Feature #142 WI-2 (`Azw3AnnotationMapper`)

Gate 4 for the WI-2 work item: the pure mapper between foliate-js selections and
the annotation domain — `selectionToInputs`, `cfiFor` (anchor → **locator
fallback**), `highlightIdForCfi`.

Plan: `dev-docs/plans/20260806-feature-142-android-azw3-annotations.md` §4.2,
§6, §10. Gate-2 artifact: `.claude/codex-audits/plan-feature-142-gate2-audit.md`.

## Scope of audit

Two new files (plus a mid-flight split of the test file):

- `android/app/src/main/kotlin/com/vreader/app/annotations/Azw3AnnotationMapper.kt`
- `android/app/src/test/kotlin/com/vreader/app/annotations/Azw3AnnotationMapperSelectionTest.kt`
- `android/app/src/test/kotlin/com/vreader/app/annotations/Azw3AnnotationMapperCfiTest.kt`

No production file outside the mapper was modified. The vendored foliate bundle,
`reader.html`, WI-1's bridge/parser files and the AZW3 hosts were read for
context only.

Codex sessions: round 1 `019fd533-4b3e-7890-9ebc-d904f3df9a88`, round 2
`019fd53f-814e-75b1-8894-4b4119e6c688` (both via `scripts/run-codex.sh`, rule 53).
Raw transcripts: `.reports/audit-r1.txt`, `.reports/audit-r2.txt`.

## Round 1 findings (7) — verdict `block-recommended`

| File:line | Severity | Issue | Resolution |
|---|---|---|---|
| `Azw3AnnotationMapper.kt:34` | High | Live-vs-restored dedupe identity split: a live row keys `(profileKey, anchorHash)`, a restored row `(same profileKey, "__nil_anchor__")`, so restore-then-re-highlight inserts a second row instead of updating. Duplicate overlays share a CFI and `highlightIdForCfi` edits whichever appears first. | **Accepted as out of scope, documented + bounded.** See "Findings rejected with reasoning" below. WI-2's own behaviour under the duplicate is now pinned by `highlightIdForCfi_liveAndRestoredDuplicatesShareACfiAndResolveDeterministically`, and the `highlightIdForCfi` KDoc carries the limitation. Reported as a follow-up in the HANDOFF. |
| `Azw3AnnotationMapper.kt:78` | Medium | Anchor/locator disagreement untested; the mutation pass proved ordering sensitivity but not this corrupt-record behaviour. | **Fixed.** `disagreeingAnchorAndLocator_anchorWinsAndTheStaleLocatorCfiDoesNotResolve` asserts all three legs: the anchor wins, a tap on the anchor CFI resolves, a tap on the **stale locator CFI does not** (matching it would let a tap elsewhere delete the row). Added different-section and prefix near-miss cases. |
| `Azw3AnnotationMapperTest.kt:156` | Medium | The CJK test used `canonicalJson().contains(cjk)` — not a round trip; never touched `profileKey` or the promised NFC behaviour; the profileKey test was ASCII-only. | **Fixed.** Assertions now cross the real persistence path (`HighlightRecord.toEntity()` → decode `locatorJSON`). `profileKeyFoldsNfdToNfcWhileTheStoredQuoteKeepsItsOriginalForm` pins the bug #356 contract in both directions: `canonicalJson()` NFC-folds `textQuote` so NFD and NFC selections share one `profileKey`, while each row stores its original bytes. Fixture is `Normalizer`-built with an `assertNotEquals` guard so it cannot pass vacuously. Added a CJK `profileKey` case. |
| `Azw3AnnotationMapperTest.kt:176` | Low | CFI at the 4 000 cap untested; over-cap behaviour unpinned. | **Fixed.** `cfiAtTheParserCapIsCarriedIntact` (length-asserted, so the fixture arithmetic is self-checking) and `overCapInputIsPassedThroughBecauseTheParserOwnsTheCaps`, which also asserts the parser rejects the over-cap message — pinning the division of responsibility rather than assuming it. |
| `Azw3AnnotationMapperTest.kt:126` | Low | Several tests pinned DTO shape rather than behaviour: `rect`/`sectionIndex` DTO equality, a redundant UTF-16 `.length` assertion, 50 repeated calls to a pure lookup. | **Fixed.** `rectAndSectionIndexReachNoPersistedColumn` now compares the **persisted columns** (`locatorJSON`, `anchorJSON`, `profileKey`, `anchorKey`, `selectedText`); the redundant length assertion and the 50-call repeat are gone. |
| `Azw3AnnotationMapper.kt:39` | Low | The KDoc claimed `locator.fingerprintKey == book.fingerprintKey` "always holds", which `Book` (a DTO with independent fields) does not guarantee. The `book.originalFormat.name` divergence itself was confirmed **correct**. | **Fixed.** KDoc now scopes the equality to repository-originated books and states it as a consequence of well-formed input, not a type-level guarantee. |
| `Azw3AnnotationMapperTest.kt:21` | Low | Test file 335 lines, over the ~300-line convention. | **Fixed.** Split into `…SelectionTest.kt` (277 after the round-2 additions) and `…CfiTest.kt` (226); the mapper itself is 119. Round 2 confirmed against `a5efbc03` that no substantive coverage was lost. |

## Round 2 findings (2) — verdict `follow-up-recommended`

Round 2 was a re-review with each round-1 disposition stated explicitly and the
auditor asked to challenge the F1 scope argument rather than accept it.

| File:line | Severity | Issue | Resolution |
|---|---|---|---|
| `Azw3AnnotationMapper.kt:101` | High | F1 re-raised as still technically unresolved, while explicitly agreeing the deferral "need not block WI-2 given the … scope boundary". The auditor **independently verified** the cross-format claim is true, and added a real nuance: foliate keys overlays **by CFI**, so an AZW3 duplicate pair collapses into ONE overlay whose single tap must pick one of two rows — sharper than the generic cross-format description. | **Accepted; documentation sharpened, not silently re-filed as parity.** The KDoc now states the AZW3-specific consequence and that first-match ordering *bounds* the symptom without curing the split, ending with "treat it as a tracked limitation, not as harmless parity". Carried to the orchestrator as a named follow-up. |
| `…SelectionTest.kt:246` | Low | **A surviving mutation, named exactly**: `val cfi = selection.cfi.trim()` would pass the entire suite — blank rejection still works and every fixture was already unpadded. | **Fixed.** `aCfiWithSurroundingWhitespaceIsStoredByteExactNotTrimmed` and the quote analog. Verified by applying the auditor's exact mutation (`.trim()` on both fields): it now kills precisely those two tests, and nothing else. |

Round 2 marked **F2–F7 RESOLVED** individually, confirmed the split lost no
coverage, and found no newly-introduced duplication or dead test.

## Findings rejected with reasoning

**F1 / round-2 #1 — the live-vs-restored dedupe split is real and is NOT fixed here.**
The split originates in two merged, out-of-write-set files: `anchorKeyFor(anchor)`
in `Annotation.kt` (`anchor?.anchorHash ?: NIL_ANCHOR`) and
`AnnotationsRepository.restoreAnnotations`, which reconstructs **every** restored
highlight and note with `anchor = null`. Both are format-agnostic: EPUB (#123),
TXT/MD (#124/#125) and AZW3 all inherit it. WI-2 introduces no dedupe behaviour —
it only makes AZW3 participate in the existing system.

The recommended remedy (reconcile restored rows against the live anchor identity
at insertion) edits the shared persistence seam, which the feature plan §3.3
declares "reused verbatim, zero changes", and which four formats depend on. Doing
it inside WI-2 would be an unplanned, un-Gate-2'd change to a merged cross-format
surface. The auditor concurred on both rounds that this need not block WI-2.

What was done instead, so the finding is bounded rather than dropped: the
behaviour under a duplicate is pinned by test, the KDoc records the limitation
including the AZW3-specific CFI-keyed-overlay consequence, and the HANDOFF
carries it to the orchestrator as a follow-up to file against the shared
annotation persistence seam.

## Findings disproven by measurement

- **"`book.originalFormat.name` may break the cross-platform locator contract"** —
  raised as a question in the round-1 prompt (this is a deliberate divergence from
  the plan's literal `format = BookFormat.azw3.name`). Round 1 verified it against
  `EpubAnnotationMapper`, iOS `FoliateSpikeView+Selection.swift` and the identity
  contract and confirmed the divergence is **correct**: iOS derives the format from
  the book's own fingerprint, and hardcoding would mint a locator addressing a
  different identity (an orphan annotation). Recorded as a plan erratum, not a bug.
- **"Resolving `highlightIdForCfi` through `cfiFor` may introduce a false match"** —
  round 1 examined the disagreement case and confirmed it does **not**: `cfiFor`
  paints and matches through the same precedence, so the painted key and the
  looked-up key are the same string by construction. Round 2 confirmed the added
  test pins this.
- **Test vacuity of the NFD fixture** — round 2 explicitly checked that the
  `Normalizer`-built fixture plus `assertNotEquals` cannot pass vacuously.

## What the audit confirmed (load-bearing, already checked)

- `AnnotationsRepository.restoreAnnotations` really does insert `anchor = null`
  for **both** highlights and notes — so the locator fallback in `cfiFor` is
  load-bearing, not defensive. Verified by the auditor against the source, not
  taken from the plan.
- The backup wire's `locatorJSON` really is a plain `Locator`
  (`BackupJson.encode(locator)`), **not** `canonicalJson()`. `canonicalJson()` is
  a hashing input only.
- `canonicalJson()` NFC-normalizes `textQuote` (bug #356, matching Swift
  `precomposedStringWithCanonicalMapping`), so the dedupe key folds Unicode while
  the stored quote does not.
- The split test files lost no coverage relative to the deleted single file.

## Mutation testing

Every mutation was applied to the production file, the targeted suite run, then
reverted. A mutation that kills nothing means the test is decoration.

| # | Mutation | Tests killed |
|---|---|---|
| M1 | Remove the locator fallback from `cfiFor` (the "obvious iOS-parity" anchor-only design) — run as the **initial RED**, before the fallback existed | **6** — incl. `cfiFor_nullAnchor_fallsBackToTheLocatorCfi` and `highlightIdForCfi_resolvesARestoredHighlightByItsLocatorCfi` |
| M2 | `records.shuffled()` in `highlightIdForCfi` | **2** — `…firstMatchWinsInListOrder`, `…isDeterministicAcrossRepeatedCalls` |
| M3 | Hardcode `format = BookFormat.azw3.name` (the plan's literal text) | **1** — `formatFollowsTheBookNotAConstant` |
| M4 | Drop `textQuote` from the locator | **4** — field-shape, CJK, surrogate-pair, at-cap |
| M5 | Flip `cfiFor` to locator-first precedence | **4** — incl. the new `disagreeingAnchorAndLocator_…` |
| M6 | `.trim()` both fields (the exact mutation round 2 named as surviving) | **2** — the two new whitespace tests; nothing else |

Zero mutations survived unkilled among those attempted. Round 1's compile-level
RED (type absent) and M1's behavioural RED are both recorded.

## Test result

```
RUN-ANDROID-TESTS RESULT: SUCCEEDED
Azw3AnnotationMapperSelectionTest  tests=18  skipped=0  failures=0  errors=0
Azw3AnnotationMapperCfiTest        tests=22  skipped=0  failures=0  errors=0
```

Zero skips is asserted from the JUnit XML, not inferred from a green build — a
skip exits 0 exactly like a pass (bug #369).

## Verdict

**`follow-up-recommended`** — all Medium and Low findings fixed across both
rounds; the single remaining High is a pre-existing cross-format persistence
limitation, verified as such by the auditor, deliberately out of this work item's
write-set, documented in code and carried to the orchestrator as a follow-up.
