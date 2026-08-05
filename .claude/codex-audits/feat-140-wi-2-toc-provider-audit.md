---
branch: feat/140-wi-2-toc-provider
threadId: 019fd137-589d-7ff0-b7b7-b78fe28bf130
rounds: 2
final_verdict: ship-as-is
date: 2026-08-05
---

# Gate-4 audit — feature #140 WI-2 (`FoliateTocProvider`)

Independent Codex audit (gpt-5.5, high reasoning, read-only sandbox, via
`scripts/run-codex.sh` per rule 53). Two rounds:

| round | thread | verdict |
|---|---|---|
| 1 | `019fd129-4664-7e61-898b-d58520e19761` | follow-up-recommended (0 Critical/High/Medium, 4 Low) |
| 2 | `019fd137-589d-7ff0-b7b7-b78fe28bf130` | **ship-as-is** (0 new findings) |

Files audited: `android/app/src/main/kotlin/com/vreader/app/reader/nav/FoliateTocProvider.kt`
(131 lines) and `android/app/src/test/kotlin/com/vreader/app/reader/nav/FoliateTocProviderTest.kt`.
Production code was **unchanged** between rounds; all four findings were test-side.

## The three load-bearing questions (asked explicitly, both rounds)

1. **Can any emitted row carry a non-null progression** (or any other field
   `FoliateGoToTarget.from` would pick ahead of the href)? — **No.** The `Locator` is
   constructed with `href` only; `cfi`/`progression`/`totalProgression`/`page`/offsets all
   default to null, so `from()` returns `Href(node.href)` before reaching the progression leg.
   This is plan §5.2 **defense 2**, independent of WI-3's `cfi → href → progression`
   precedence (defense 1) — it holds even if that precedence is later reordered.
2. **Can a blank-labelled or blank-href container lose its children?** — **No**, on any path:
   blank parents, blank grandparents and consecutive blank containers alike. The recursion sits
   *outside* `entryFor`, so a skipped row still descends, and still counts as a nesting level.
3. **Is any href altered between parser and locator?** — **No.** `FoliateTocParser` reads the
   string verbatim; the provider uses `href.isBlank()` only as an emit/drop predicate and passes
   `node.href` through unchanged. `validatedOrNull()` validates numeric structural fields only
   and returns the same instance — it never trims, normalizes, re-encodes, strips fragments or
   case-folds.

## Round-1 findings and dispositions

| # | severity | finding | disposition |
|---|---|---|---|
| 1 | Low | Test file (405 lines) exceeds the repo's ~300-line guidance. | **Accepted, not fixed.** The work item's write-set is exactly two files, so a third test file is not permitted; and the local norm in this package is larger — `TxtTocEngineWalkEquivalenceTest` 838, `TxtTocRuleEngineTest` 697, `FoliateGoToTest` 642 (the WI-3 sibling), `MdTocScannerTest` 624. The production file is 131 lines. **Round 2 accepted the rationale and withdrew the finding.** |
| 2 | Low | Single-skip fixtures would still pass under a bug that only loses children once **two** skipped containers nest. | **Fixed** — `consecutiveSkippedContainers_stillYieldTheirDescendants`: blank-label grandparent → blank-href parent → real chapter, asserting the chapter survives at **depth 2** with its href intact. Round 2 confirmed FIXED and confirmed depth 2 is the correct expectation. |
| 3 | Low | `entryLocator_isValid` was vacuous if every row were dropped (a `forEach` over an empty list asserts nothing). | **Fixed** — an expected-size assertion now precedes the `forEach`. Round 2 confirmed FIXED. |
| 4 | Low | The Unicode-normalization comment claimed `\u` escapes while the source carried literal UTF-8. | **Fixed by correcting the comment**, not the literals: the editing tool in use materializes `\u` escapes back into characters, so the comment now states the actual byte sequences and explains that the `assertNotEquals` guard is what makes the fixture robust to a normalizing reformat. Round 2 verified by hexdump that the fixtures genuinely differ (`63 61 66 65 cc 81` vs `63 61 66 c3 a9`) and that the comment is now accurate. |

Round 2 also re-confirmed the three answers above against the current source and reported
**no new findings**.

`validatedOrNull()` is dead today for an href-only locator; the auditor rated it *defensible*
(the plan §5.3 calls for it, it matches the sibling construction-site style, and it cannot alter
the href). Kept, with the reasoning stated inline.

## Test-adequacy evidence — the mutation pass

Ten mutations were introduced one at a time and the targeted suite re-run; **every one was
killed**, so no assertion in the suite is decorative:

| mutation | killed by |
|---|---|
| `progression = 0.0` (the iOS shape) | `entryLocator_hasNoProgression` |
| skip the subitems of a skipped node | `blankLabel_…`, `blankHref_…`, `whitespaceOnlyHref_…` (3) |
| `href.trim()` + NFC normalize | `hrefIsNotTrimmed_paddedHrefSurvivesVerbatim`, `hrefIsNotUnicodeNormalized` |
| `href.substringBefore("#")` | `hrefWithFragmentOrQuery_…`, `twoHrefsDifferingOnlyByFragment_…`, `nonAsciiHref_…` |
| `href.lowercase()` + prefix strip | `kf8PosUriHref_…`, `mobi6FileposHref_…` |
| breadth-first walk | `nestedTree_isDepthFirst_parentBeforeChildren`, `depthIncrementsOncePerNestingLevel`, +4 |
| `format = "azw3"` literal | `entryLocator_formatComesFromBookOriginalFormatNotALiteral` |
| drop `coroutineContext.ensureActive()` | `cancellation_isCooperative` |
| drop `withContext(dispatcher)` | `runsOnTheInjectedDispatcher_notTheCaller` |
| drop the label trim + blank-label skip | `labelIsTrimmed`, `labelInteriorIsPreserved_…`, `blankLabel_…`, `treeOfOnlyUnusableNodes_…` |

Note on the href-preservation family: trim+NFC alone does **not** kill the fragment/KF8/MOBI6/CJK
tests (their inputs carry no padding and are already NFC), so three sharper href mutations were
run to prove each of those four is load-bearing rather than assuming it.

## Test gate

`RUN-ANDROID-TESTS RESULT: SUCCEEDED` — `:app:testDebugUnitTest --tests '*Foliate*' --tests
'*Toc*' --rerun-tasks`, **306 tests, 0 failures, 0 errors, 0 skipped** (JUnit XML), of which
`FoliateTocProviderTest` contributes 27. JVM-only; no emulator involved.

## Verdict

**ship-as-is.**
