---
branch: feat/140-wi-4-toc-index
threadId: 019fd142-e340-7583-b545-dff0fb83faba
rounds: 3
final_verdict: ship-as-is
---

# Codex Audit Log — Feature #140 WI-4 (`relocate.tocHref` + `foliateTocIndexFor`)

Gate 4, run in-lane via `scripts/run-codex.sh` (rule 53), read-only sandbox, `-e high` for rounds
1–2 and `-e medium` for the narrow confirming round 3. Session ids:

| Round | Session id | Effort | Verdict |
| --- | --- | --- | --- |
| 1 | `019fd128-7484-7641-9984-4f8ac5afec9b` | high | follow-up-recommended (0 Critical, 0 High, 1 Medium, 2 Low) |
| 2 | `019fd137-cbad-7de3-b55f-79c2e24dbccb` | high | follow-up-recommended (0 Critical, 0 High, 0 Medium, 3 Low) |
| 3 | `019fd142-e340-7583-b545-dff0fb83faba` | medium | **ship-as-is** (0 findings) |

Full transcripts: `.reports/audit-r1.txt`, `.reports/audit-r2.txt`, `.reports/audit-r3.txt`
(worktree-local, not committed).

## Scope

Five files (the plan's WI-4 `writes:` block, exactly):

- `android/app/src/main/kotlin/com/vreader/app/reader/foliate/FoliateMessage.kt` — `Relocate` gains
  `tocHref: String? = null`
- `android/app/src/main/kotlin/com/vreader/app/reader/foliate/FoliateMessageParser.kt` — populates it
- `android/app/src/main/kotlin/com/vreader/app/reader/nav/FoliateTocIndex.kt` — NEW,
  `foliateTocIndexFor`
- `android/app/src/test/kotlin/com/vreader/app/reader/foliate/FoliateMessageParserTest.kt` — extended
  (WI-1's cases untouched)
- `android/app/src/test/kotlin/com/vreader/app/reader/nav/FoliateTocIndexTest.kt` — NEW

`foliate-bundle.js` is untouched (its pinned-SHA provenance test still passes).

## The three questions the audit was asked

1. **Is the index contract identical to `tocIndexFor`'s in every branch?** Confirmed identical on
   every branch WI-4 owns: empty → `-1` (`ReaderChromeModel.kt:79`), TOC-exists-but-unknown → `0`
   (`:80`), duplicate href → LAST match (`:86`, the overwriting loop). Two deliberate divergences,
   both accepted as justified: AZW3 has no lexical best-effort fallback (EPUB's `:90-98`) and no
   progression leg (`:82-88`) — foliate has already resolved the current TOC item, so WI-4 maps that
   identity rather than re-deriving position, exactly as the plan's §4/§5.1 specify.
2. **Can any href comparison normalize?** No. The auditor traced every string operation from
   `foliate-bundle.js:7048` → `reader.html`'s `JSON.stringify` → `Json.parseToJsonElement` →
   `str()` (`isNotBlank` only, never `trim()`) → `href == currentTocHref`, and the TOC side
   (`serializeTOC` → `FoliateTocParser.stringOrEmpty`, verbatim). NFC and NFD remain distinct.
3. **Did adding `tocHref` change any existing field or message?** No. `cfi` / `fraction` /
   `sectionIndex` / `sectionTotal` keep their expressions; the trailing default preserves every
   four-argument construction site (`Azw3LocatorBridgeTest.kt:19`, `Azw3BackupRoundTripTest.kt:25`,
   the parser tests); `book-ready` / `error` / `goto-ack` / `Other` branches are untouched, and a
   `tocHref` on those messages is ignored (pinned by `tocHrefOnOtherMessages_isNotConsumed`).

## Findings and dispositions

### Round 1 — 0 Critical, 0 High, 1 Medium, 2 Low

- **Medium — Unicode normalization was not mutation-tested.** The code was correct, but no fixture
  distinguished NFC from NFD, so a `Normalizer.normalize` mutation would have survived.
  **FIXED**: added `FoliateTocIndexTest.canonicallyEquivalentHrefs_areDistinctRows` (NFC vs NFD at
  distinct non-zero indices, in both orderings, with guards asserting the two literals genuinely
  differ) and the same pair to the parser's verbatim test plus a `shapes.distinct()` guard.
  Mutation-verified in both places (kill map below). Round 2 read the on-disk code points
  (`C3 A9` vs `65 CC 81`) and closed it.
- **Low — `FoliateMessageParserTest.kt` is 350 lines, past the ~300-line guideline.**
  **ACCEPTED, not fixed.** Splitting adds a sixth file outside this WI's declared write-set, and the
  guideline is applied to production files here — sibling suites are already 416
  (`TxtTocIndexTest.kt`) and 642 (`FoliateGoToTest.kt`) lines. All three production files in this WI
  are 67–88 lines. Round 2 accepted the rationale and closed it as non-actionable.
- **Low — comments said "byte-identical" / "not code units", which is imprecise** (Kotlin
  `String.equals` is UTF-16 code-unit equality after JSON unescaping, not wire-byte comparison).
  **FIXED** across the header + KDoc of `FoliateTocIndex.kt`, the parser comment, the `Relocate`
  KDoc and the suite header. Round 2 found one leftover (below).

### Round 2 — 0 Critical, 0 High, 0 Medium, 3 Low (all comment/naming accuracy)

- **Low (carryover) — the parser test was still named `…IsCarriedByteForByte` and its comment still
  said "matched byte-exactly".** **FIXED**: renamed to
  `relocate_tocHrefPreservesDecodedStringExactly`, comment reworded. No stale references repo-wide.
- **Low — `matchIsByteExact_noNormalization_noTrimming`'s comment claimed every entry was a
  normalization twin of index 0**, which is false for the percent-encoded and blank rows (they are
  killed by separate assertions). **FIXED**: the comment now names which indices kill which mutation.
- **Low — `FoliateTocIndex.kt`'s header said foliate resolves `tocItem` over "the SAME toc objects it
  serialized to us"**, which is literally false — `serializeTOC` maps into fresh objects; the real
  invariant is that the href STRINGS come from the same source TOC. **FIXED**.

### Round 3 — narrow confirming round, 0 findings

All three Lows verified CLOSED against the code (including `serializeTOC` in the bundle), no stale
test-name references, and the production logic confirmed byte-identical to what round 2 approved:
empty → `-1`, null → `0`, unmatched → `0`, last exact match wins, plain `String` equality,
`tocHref = detail.str("tocHref")` with no transformation. **VERDICT: ship-as-is.**

Author/auditor separation held: every round ran in a fresh Codex process, and no fix authored by the
lane was certified by the round that requested it.

## Mutation pass (the evidence the tests have teeth)

Each mutation was applied alone, the suite re-run with `--rerun-tasks`, and the mutation reverted.
Counts read from the JUnit XML, never from `BUILD SUCCESSFUL`.

| # | Mutation | Killed by |
| --- | --- | --- |
| M1 | return the FIRST match instead of the last | `duplicateHrefs_returnsTheLastMatch`, both differentials (3) |
| M2 | `return found` — `-1` when a TOC exists but nothing matches | 9 tests incl. `noMatch_butTocExists_returnsZero` |
| M3 | `return 0` for empty entries | `emptyEntries_returnsMinusOne` + differential (2) |
| M4 | `null` current href → `-1` | `nullHref_butTocExists_returnsZero` + both differentials (3) |
| M5 | `trim().lowercase()` both sides + treat blank as unknown | `matchIsByteExact_noNormalization_noTrimming` + differential (2) |
| M6 | `substringBefore('#')` both sides (fragment stripping) | `hrefsDifferingOnlyByFragment_areDistinctRows`, `hrefWithQuerySuffix_matchesOnlyItself`, `cjkHref_matches`, differential (4) |
| M7 | drop the `currentTocHref == null` early return (so a null query matches a null ROW) | `nullHref_butTocExists_returnsZero` + both differentials (3) |
| M8 | parser drops a sibling: `sectionTotal = 1` hardcoded | `relocate_withoutTocHref_isNull_otherFieldsUnchanged` + 3 others |
| M9 | parser accepts blank/non-string tocHref (raw `JsonPrimitive.content`) | `relocate_blankTocHref_isNull` |
| M10 | parser `trim()`s the href | `relocate_tocHrefPreservesDecodedStringExactly` |
| M11 | index NFC-normalizes both operands | `canonicallyEquivalentHrefs_areDistinctRows` (the round-1 Medium's fix, proven) |
| M12 | parser NFC-normalizes the href | `relocate_tocHrefPreservesDecodedStringExactly` (same, parser side) |

Zero survivors. Every mutation the brief named is in the table.

## Residual risk (stated, not claimed solved)

- The **provider→index wiring** (which hrefs actually reach `entryHrefs`) lands in WI-6; WI-4 is
  JVM-only and foundational, so a real AZW3 book's highlight is proven at WI-6/WI-7's connected
  Gate-5 pass, not here.
- **Stage-1 JS recursion** over a pathological TOC (`assignIDs`/`flatten`/`serializeTOC` inside the
  SHA-pinned bundle) is upstream of every Kotlin bound and unchanged by #140 — plan §5.4,
  follow-up F6. Nothing in this WI claims to bound it.
- The differential oracle is example-based: a mutant keyed on one exact untested size above the
  exhaustive 0–64 sweep could survive. Mitigated by including the cap and its neighbours
  (`MAX_TOC_ENTRIES - 1 / ± 0 / + 1`) and by drawing hrefs from a small alphabet so duplicates and
  misses occur densely at every size.
