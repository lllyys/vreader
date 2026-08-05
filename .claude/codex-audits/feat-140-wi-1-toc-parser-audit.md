---
branch: feat/140-wi-1-toc-parser
threadId: 019fd0cf-b6cc-7040-85ee-dc543e957f54
rounds: 1
final_verdict: ship-as-is
date: 2026-08-05
---

# Codex Audit Log — Feature #140 (GH #2064) WI-1

`FoliateTocItem` + `FoliateTocParser`: stop discarding the `toc` tree the
foliate-js bundle already posts on every AZW3 `book-ready`.

Plan: `dev-docs/plans/20260805-feature-140-android-azw3-toc.md`, `id: WI-1`
(tier foundational, JVM tests only).

## Scope of audit

Commit `cf381071`, six files:

| File | Change |
| --- | --- |
| `android/app/src/main/kotlin/com/vreader/app/reader/foliate/FoliateTocItem.kt` | new — the `{label, href, subitems}` wire shape |
| `android/app/src/main/kotlin/com/vreader/app/reader/foliate/FoliateTocParser.kt` | new — bounded, throw-free `parse(tocElement: JsonElement?)` |
| `android/app/src/main/kotlin/com/vreader/app/reader/foliate/FoliateMessage.kt` | `BookReady` gains `toc: List<FoliateTocItem> = emptyList()` |
| `android/app/src/main/kotlin/com/vreader/app/reader/foliate/FoliateMessageParser.kt` | reads `detail["toc"]`, delegates the walk |
| `android/app/src/test/kotlin/com/vreader/app/reader/foliate/FoliateTocParserTest.kt` | new — 18 tests |
| `android/app/src/test/kotlin/com/vreader/app/reader/foliate/FoliateMessageParserTest.kt` | +3 tests (28 → 31) |

`android/app/src/main/assets/foliate/foliate-bundle.js` is **not** touched —
it is SHA-pinned by `FoliateBundleProvenanceTest`, which stayed green.

## Round 1 — Codex `gpt-5.5` / reasoning `high`

Prompt asked specifically for: (1) any payload shape that can make
`parse` throw (incl. `StackOverflowError`/`OutOfMemoryError`) rather than
degrade, given it runs on the WebView message-callback (main) thread;
(2) any test name / KDoc / comment / commit message **overclaiming** beyond
payload parsing — i.e. implying the Kotlin bounds make a pathological *book*
open, or that the bundle's own recursive `assignIDs`/`flatten`/`serializeTOC`
walks are protected (rated a High in the prompt, since that JS exposure is
pre-existing, out of scope, and tracked as risk R13 / follow-up F6);
(3) whether byte-for-byte preservation is actually *asserted* (exact equality)
rather than approximated; (4) reject-whole vs silently-truncate past
`MAX_TOC_ENTRIES`, including whether nested rows count and whether the
boundary is tested; (5) `MAX_TOC_DEPTH` semantics + genuinely bounded
recursion; (6) backward compatibility of every existing `BookReady` site;
(7) correctness against the plan's WI-1 spec + scope creep into WI-2/3/4;
(8) project conventions (rule 50 §12, rule 22, file size, purity).

**Findings: Critical none, High none, Medium none, Low none.**

Auditor's substantive confirmations:

- **No throwing shape found.** Shapes considered: `null`, JSON null,
  non-array scalars/objects, non-object array elements, missing/null/non-array
  `subitems`, wrong/missing `label`/`href`, 200-deep nesting, flat cap+1,
  nested cap+1, junk interleaved with valid rows. Root type-check, non-object
  skip, recursion gate and over-cap rejection each cited by line.
- **No overclaim.** The scope limit (Kotlin stage only; the JS recursion is
  pre-existing and unfixable from Kotlin) is stated in the parser's header,
  both test-file headers, and the commit message; no test is named or worded
  as though it proves a book opens.
- **Byte-for-byte is genuinely asserted** with `assertEquals` against exact
  input strings for CJK/RTL/non-ASCII labels, blank/padded values, embedded
  newlines, and hrefs carrying fragments, queries, non-ASCII, KF8
  `kindle:pos:fid:…:off:…` and MOBI6 `filepos:…`.
- **Reject-whole is real**, one shared budget across nesting, with the
  boundary (exactly-at-cap kept, cap+1 empty) and nested-row counting both
  tested; "a truncating implementation would fail the emptiness assertions."
- **Recursion is bounded by the constant** regardless of payload nesting, and
  the parent row is kept when its subitems are dropped.
- **Backward compatible** — `toc` is defaulted; every pre-#140 two-argument
  `BookReady` construction still compiles, and `Azw3Document` still ignores
  `toc` (its wiring is WI-6).
- **No scope creep** — no provider, no href goTo leg, no `relocate.tocHref`.

Verdict: **ship-as-is**. No fixes were required, so no code changed after the
audit and no re-test was needed.

Raw transcript: `.reports/audit-r1.txt` (not committed — lane-local).

## Test evidence

`RUN-ANDROID-TESTS RESULT: SUCCEEDED` for both gates, counts read from the
JUnit XML under `android/app/build/test-results/testDebugUnitTest/`:

- targeted: `FoliateTocParserTest` 18/0, `FoliateMessageParserTest` 31/0
- full `*Foliate*` suite: **71 tests, 0 failures, 0 errors**
  (incl. `FoliateBundleProvenanceTest` 2/0 — the bundle SHA is intact)

## Mutation pass (author-run, pre-audit)

Six mutants applied one at a time to `FoliateTocParser.kt`, each reverted
after its run. All were killed:

| # | Mutation | Killed by |
| --- | --- | --- |
| 1 | `break` instead of `return null` past the entry cap (truncate, not reject) | `overMaxEntries_rejectsWholeToc_neverTruncates`, `entryCapCountsNestedRows_notJustTopLevelOnes` |
| 2 | `.trim()` the label/href | `blankLabelAndBlankHref_arePreservedVerbatim_filteringIsTheProvidersJob`, `labelWithEmbeddedNewline_isPreserved_sheetNormalizesAtRender` |
| 3 | never read `subitems` (drop the recursion) | 5 parser tests + `bookReady_populatesTocTree`, `hostileTocPayload_isParsedWithoutThrowing` |
| 4 | `parse` returns `emptyList()` for a valid TOC | 14 parser tests + 2 message-parser tests |
| 5 | `href.substringBefore('#')` (strip the fragment) | `hrefWithFragmentQueryOrNonAscii_isPreservedByteForByte`, `nestedToc_preservesSubitemTree`, `bookReady_populatesTocTree` |
| 6 | depth off-by-one (`depth + 1 <= MAX_TOC_DEPTH`) | `deeplyNestedToc_doesNotOverflow_andDropsBeyondMaxDepth`, `hostileTocPayload_isParsedWithoutThrowing` |

No surviving mutant, so no test needed strengthening.

## Residual risk (characterized, not fixed — out of WI-1 scope)

A JVM-green deep-nesting test is weak evidence for the device: **ART's stack
budget is not the JVM's**. The plan already routes an on-device re-run of the
200-deep payload through the real `addWebMessageListener` path to **WI-7**.
The bundle-side (stage 1) recursion remains untouched and untouchable from
Kotlin — risk **R13**, follow-up **F6**.
