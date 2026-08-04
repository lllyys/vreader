---
branch: feat/139-wi-1-toc-rules
threadId: 019fcb40-8348-76d2-999e-2be4c26eeeda
rounds: 3
final_verdict: follow-up-recommended
date: 2026-08-04
---

# Gate-4 audit — feature #139 WI-1 (ported TXT TOC rule data)

Item: `feat:#139/WI-1`. Auditor: Codex `gpt-5.6-sol` via `scripts/run-codex.sh` (rule 53),
read-only sandbox, three rounds. Thread ids: r1 `019fcb40-8348-76d2-999e-2be4c26eeeda`,
r2 `019fcb45-e8ab-7a33-9739-c0448857f8ab`, r3 `019fcb48-1b81-70b3-8419-c073733c4879`.
Raw transcripts: `.reports/audit-r{1,2,3}.txt` (gitignored, lane-local).

Scope audited: `TxtTocRule.kt`, `TxtTocRules.kt`, `TxtTocRulesTest.kt`, and the committed
Gate-1 probes, against the iOS source of truth `vreader/Services/TXT/TXTTocRuleEngine.swift:142-350`.

## Round 1 — verdict `block-recommended`

| Sev | Finding | Disposition |
| --- | --- | --- |
| HIGH | All 25 rules widened the **leading indent** class to `WS`. Not a D1b repair — iOS writes the indent as a literal `[space, U+3000, tab]` class and uses `\s` only for interior positions. `WS` contains line terminators, so at a blank line the indent consumed that line's own terminator and the match started one line early; WI-2 turns match starts into navigation locators, so every heading preceded by a blank line (ubiquitous in real books) would carry an off-by-one-line offset. | **FIXED** (`20101fa2`). `INDENT` is now iOS's literal class, built from a code point. New test `everyRule_keepsTheLiteralIosIndentClass`; the old test that *pinned* the defect was replaced by `headingAfterBlankLines_matchesAtTheHeadingLine_notTheBlankLine`. |
| MEDIUM | No independent fidelity pin — a pattern and its example could drift together and still pass "matches its own example". | **FIXED** (`20101fa2`). Golden table `iosRules` transcribed independently from the Swift source; every rule's name, example and pattern asserted against it. |
| MEDIUM | D1/D1b populations were derived from the implementation under test, so one wrong removal plus one wrong addition could cancel out. | **FIXED** (`20101fa2`). `IOS_DIGIT_RULE_IDS` / `IOS_WHITESPACE_RULE_IDS` hard-coded from Swift; both the derived population and the sample-table keys assert against them. |
| LOW | `inlineFlags()` KDoc overclaimed completeness. | **FIXED** (`20101fa2`). Reworded; backstopped by `noRule_containsAnyForbiddenFlagToken`. |
| LOW | Docs framed the offset shift as a "known limitation", risking WI-2 treating it as contractual. | **FIXED** (`20101fa2`) — the defect itself was removed. |

The HIGH was raised to the auditor as an explicit question because plan §3.5 *mandates* the
normalization. The auditor's independent verdict: ship iOS's literal class, "there is no
ICU/Java incompatibility to repair here". Corroborating evidence found in the plan itself — its
Appendix A.5 non-regression measurement kept the leading class literal and widened only interior
positions, so the "widening is non-regressive" evidence never covered the indent. **This is a
deliberate, audited deviation from plan §3.5** and is recorded in the HANDOFF for the plan to be
corrected.

## Round 2 — verdict `follow-up-recommended`

| Sev | Finding | Disposition |
| --- | --- | --- |
| MEDIUM | The fidelity check reversed the substitutions and compared back to iOS, but the reversal is **not injective**: a bracketed class and its bare contents both reverse to the same token, so a pattern splicing class contents where the whole class belongs (`\s\p{Z}\x{0085}{0,4}` outside a class is a literal sequence, not whitespace) would reverse cleanly and pass. | **FIXED** (`6f2017b6`). Reversal deleted; replaced by `expandIosPattern()` — a forward, context-aware expansion (class-depth tracking, escape skipping) compared for character equality. `expandIosPattern_isContextAware` pins the expander. |

Round 2 also positively verified: all 25 golden names/bodies/examples character-identical to
Swift; substitution ordering correct; `INDENT` produces exactly Swift's prefix; blank-line
offsets correct for LF, repeated LF and CRLF; both hard-coded id sets match the Swift patterns.

## Round 3 (final) — verdict `follow-up-recommended`

**Zero Critical, zero High, zero Medium.** Two LOW findings, both closed in-lane:

| Sev | Finding | Disposition |
| --- | --- | --- |
| LOW | Golden-table KDoc still described round-tripping after the forward-expansion rewrite. | **FIXED** — KDoc rewritten. |
| LOW | The expander's own tests stated expectations in terms of the production constants, so a consistently-wrong constant could ride through every assertion. | **FIXED** — `theWidenedClasses_areExactlyWhatTheyClaimToBe` pins all four constants against literals, with the full-width digit bounds built from code points. |

Round 3 confirmed: the expander handles all 25 golden bodies correctly (every backslash has a
following character; `\(`, `\)`, `\.`, `\[`, `\-` copied atomically; only unescaped brackets
change class state); the equality is injective over shipped rule strings; the golden table
faithfully matches Swift including numeral inventories, enabled flags and ordering;
`narrowedWhitespace` / `narrowedDigits` are still used and correct; no dead production code.

## Port-fidelity result (auditor-confirmed across all three rounds)

All 25 ids, serialNumbers, enabled flags, names and examples match iOS. The three CJK numeral
inventories are correctly distinct (rules 1/2/7/23 include `〇`, `两` and the financial forms;
rule 22 excludes `两` and the financial forms; rule 19 excludes `〇` and `两` but keeps the
financial forms). No bare `\d` or `\s` survives; nothing was widened that iOS did not write as
`\d`/`\s` — rule 17's full-width-only class is correctly left alone. The D1/D1b negative controls
are real, not vacuous.

## Test gate (re-run after every audit-driven change)

```
RUN-ANDROID-TESTS RESULT: SUCCEEDED
```
`ANDROID_CMD="./gradlew :app:testDebugUnitTest --tests '*TxtTocRulesTest*'"` — 21 tests,
0 failures, 0 errors, 0 skipped.
