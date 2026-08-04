---
branch: feat/172-wi-2-one-matcher
threadId: 019fce24-0077-7871-841b-342824fbff70
rounds: 3
final_verdict: ship-as-is
date: 2026-08-05
---

# Gate-4 audit — feature #172 WI-2 (one `Matcher` per scan)

Auditor: Codex `gpt-5.6-sol` via `scripts/run-codex.sh` (rule 53), read-only, three rounds.
Author/auditor separation held: the implementing lane never audited its own work.

| Round | Thread | Verdict |
| --- | --- | --- |
| 1 | `019fce0b-534b-75d1-8f8f-5986b80cfca5` | `follow-up-recommended (C=0 H=0 M=1 L=2)` |
| 2 | `019fce18-75b6-7301-9ec1-d5bd318b398b` | `follow-up-recommended (C=0 H=0 M=1 L=2)` |
| 3 | `019fce24-0077-7871-841b-342824fbff70` | **`ship-as-is (C=0 H=0 M=0 L=0)`** |

Raw transcripts: `.reports/audit-r1.txt`, `.reports/audit-r2.txt`, `.reports/audit-r3.txt`
(worktree-local, not committed — long output travels as paths per rule 55).

## Scope

- `android/app/src/main/kotlin/com/vreader/app/reader/nav/TxtTocRuleEngine.kt` (the change)
- `android/app/src/test/kotlin/com/vreader/app/reader/nav/TxtTocEngineWalkEquivalenceTest.kt` (new, JVM oracle)
- `android/app/src/androidTest/kotlin/com/vreader/app/reader/nav/TxtTocScanCostTest.kt` (RED added)
- `android/app/src/main/kotlin/com/vreader/app/reader/nav/TxtTocRules.kt` (read-only context)

Every round was asked the same six adversarial questions: is exactly ONE `Matcher` constructed per
scan on every path; is the walk driven by no-arg `find()` and never `find(int)`; is the
`(title, offset)` sequence provably identical; are `limit` / empty-title / cancellation / `sampleOf`
semantics preserved; is the oracle's corpus genuinely adversarial or vacuous; is the budget tight
enough to fail a `find(int)` implementation.

## Headline

**No round found a single defect in the production change.** All six findings across rounds 1–2 were
in the new test file, and every one was about the *strength of the evidence*, not the behaviour.
Round 3 independently re-derived the equivalence argument, the `\G` claim, the surrogate-advancement
claim and the cancellation cadence, and closed with no findings.

## Findings and dispositions

### Round 1 — `C=0 H=0 M=1 L=2`

| # | Sev | Finding | Disposition |
| --- | --- | --- | --- |
| 1 | **Medium** | `cancellationCadenceIsUnchanged` used a 40-match fixture, so it never reached the every-`CANCELLATION_CHECK_INTERVAL` (1024) branch — it would have passed with the whole `sinceCheck` block deleted. | **FIXED** (`56f02ecf`). The fixture now walks `2 × INTERVAL + 953` matches whose titles are ALL empty and counts the checks: `assertEquals(1 + 2 + 1, checks)`. Because zero headings are emitted, this also discriminates per-match-EXAMINED from per-heading-EMITTED (the latter would give 2). A `CancelAfter(1)` is additionally asserted to stop AT the interval check (`checks == 2`), and the same count check was added for `countMatches` via `detectBestRule`. |
| 2 | Low | `theCorpusDiscriminatesEveryPlausiblyWrongWalk` claimed more than four loop-body mutations prove; nothing covered resume-state constructs (`\G`, lookbehind, zero-width at EOF, astral-boundary advancement). | **FIXED** (`56f02ecf`). Renamed to `theCorpusDiscriminatesTheFourLoopBodyMistakes` with a KDoc naming where resume-state mistakes are actually covered. Three rules added to the MAIN sweep — a lookbehind rule, a bare `$` rule, and the EMPTY pattern — so those are demonstrated rather than argued. New `noShippedRuleUsesAResumeSensitiveConstruct` guards the equivalence's one genuine precondition: `\G` is the only construct that can observe *where* a walk resumed (old walk anchored it at `end + 1` after an empty match, new walk at `end`), so a future `\G` rule fails the guard instead of silently changing behaviour. The engine header records it. |
| 3 | Low | The new test file is 607 lines vs the repo's ~300-line guidance. | **ACCEPTED with rationale.** The sibling suites in this area are 624–1207 lines by established precedent (`MdTocScannerTest` 624, `TxtTocRuleEngineTest` 697, `TxtTocAcceptanceTest` 1207) and the plan's own §8 test catalogue cites those counts approvingly. Splitting the legacy oracle from the corpus that discriminates it would separate the reference implementation from its evidence — the opposite of readable. **No production file grew**; `TxtTocRuleEngine.kt` is 247 lines. |

### Round 2 — `C=0 H=0 M=1 L=2`

| # | Sev | Finding | Disposition |
| --- | --- | --- | --- |
| 4 | **Medium** | Round 1's own fix was half-real: `emptyPatternRule` and `endAnchorRule` DO match zero-width inside a surrogate pair and at end-of-input, but every such match trims to `""` and is **dropped**, so the emitted-output sweep compared two empty lists on exactly the positions the rules were added to cover. A walk skipping the inside-a-surrogate position would still have passed. | **FIXED** (`da2d350a`). `theTwoResumeStrategiesAgreeOnRawOffsetsIncludingTheInvisibleOnes` drops below the engine and compares the strategies themselves over the whole corpus: `legacyResumeOffsets` (a FRESH `Matcher` per match, `find(from)`, `from = end + (if end == start) 1 else 0` — `MatcherMatchResult.next()` transcribed) vs `newResumeOffsets` (ONE `Matcher`, `while (find())`). Every raw offset is compared, dropped or not, and the two invisible positions are asserted PRESENT: an empty pattern matches at `[0, 1, 2]` of a surrogate pair (advancement is by code UNIT — code-POINT advancement would make the strategies diverge there) and a bare `$` matches at end-of-input. Both walks carry a step cap so a non-advancing regression fails loudly instead of hanging the suite. |
| 5 | Low | Detection cadence asserted only as `>= 4`, permitting an over-checking regression. | **FIXED** (`da2d350a`). `assertEquals` on the exact 5 (entry + per-rule + 2 interval checks inside `countMatches` + post-loop). |
| 6 | Low | `allRules` KDoc still said "five synthetic" rules; `extraRules` has eight. | **FIXED** (`da2d350a`). |

### Round 3 — `ship-as-is (C=0 H=0 M=0 L=0)`

> "No findings. R2's M1 is closed: `legacyResumeOffsets` faithfully models Kotlin's initial
> `Regex.find(input, 0)`, zero-width advancement, and `nextIndex > input.length` termination.
> Android's API 35 matcher advances empty matches by one UTF-16 code unit, so `[0, 1, 2]` is correct
> for a surrogate pair; `$` also matches at EOF. The detection cadence is exactly five checks: entry
> + pre-rule + two interval checks across 3001 matches + post-loop. Production behavior, matcher
> allocation, cancellation, limits, compilation parity, documentation, imports, and thread safety
> show no blocking defect."

## What the audit independently confirmed about the production change

- Exactly ONE `Matcher` is constructed per scan on **every** path of `extractHeadings` and
  `countMatches`, including the empty-text early return, the uncompilable-pattern return, the
  `limit` early-return and every cancellation exit.
- The walk is driven by **no-arg `find()`** everywhere; `find(int)` appears nowhere in production.
- The `(title, offset)` sequence is identical to the pre-change Kotlin walk, with `\G` as the single
  documented and mechanically-guarded precondition.
- `Regex(p, MULTILINE)` and `Pattern.compile(p, Pattern.MULTILINE)` have exception-type parity
  (`PatternSyntaxException`), so the iOS-parity `try?`-style skip is unchanged.
- No `Matcher` instance is shared across threads (each is a local in the call that made it).
- Rule-22: the header's new `Key decisions` block matches the code sentence by sentence.

## Test evidence at the audited HEAD

| Gate | Result |
| --- | --- |
| JVM (`:app:testDebugUnitTest --rerun-tasks --tests '*TxtToc*' --tests '*MdTocScanner*' --tests '*TxtMdTocProvider*'`) | `RUN-ANDROID-TESTS RESULT: SUCCEEDED` — 174 tests, 0 failures, 0 errors |
| Connected (`:app:connectedDebugAndroidTest`, `TxtTocScanCostTest`, emulator-5554 / API 35) | `RUN-ANDROID-TESTS RESULT: SUCCEEDED` — 6 tests, 0 failures |
| RED before / after | `extractionMeetsEngineBudget` 7111 ms **FAIL** → 83 ms **PASS** (300 ms budget) |

The declared JVM gate's `--tests '*TxtToc*'` glob does **not** match `TxtMdTocProviderTest`; the run
above adds `--tests '*TxtMdTocProvider*'` so all five regression suites the WI-2 spec names are
actually executed. All five pass **unmodified** — the only test files touched are the new oracle and
the connected harness the RED was added to.
