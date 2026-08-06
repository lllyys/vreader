---
gate: 4
kind: implementation-audit
feature: 142
work_item: WI-1
branch: worktree-agent-a2e991a330c870d97
threadId: 019fd51e-1a74-7a12-a24e-38f551d74c90
rounds: 2
final_verdict: follow-up-recommended
---

# Gate-4 implementation audit — feature #142 WI-1 (foliate annotation messages + raw ceiling)

Auditor: Codex `gpt-5.5`, effort `high`, read-only sandbox, via `scripts/run-codex.sh` (rule 53).
Author/auditor separation held (separate `codex exec` process, no implementation authority).

Round 1 thread: `019fd50d-6ed4-76e2-a9a3-3bdae545295e` (commit `426ab6d4`), raw output
`.reports/audit-r1.txt`.
Round 2 thread: `019fd51e-1a74-7a12-a24e-38f551d74c90` (commit `4f9517e1`), raw output
`.reports/audit-r2.txt`.

Scope audited: `FoliateMessage.kt`, `FoliateMessageParser.kt`, `FoliateBridgePolicy.kt`,
`FoliateBridge.kt`, the `Azw3Document.kt` exhaustive-`when` branches, and the four extended JVM test
classes. Plan: `dev-docs/plans/20260806-feature-142-android-azw3-annotations.md` §4.1 / §4.3 / §8 /
§10. The Gate-2 artifact (`plan-feature-142-gate2-audit.md`) was supplied to both rounds so settled
decisions were not re-litigated.

## Round 1 — `follow-up-recommended` (1 Medium, 2 Low)

| # | Sev | Finding | Disposition |
| --- | --- | --- | --- |
| r1-1 | **Medium** | The structural source-scan test (`foliateBridge_appliesTheAdmissionGateBeforeParsing`) did not prove what it claimed. It asserted `admitsMessage(` appears textually before `FoliateMessageParser.parse(`, which would still pass if the gate call sat above an **unconditional** parse — i.e. the exact regression the test existed to catch. Production was correctly gated; the *test* was weaker than its claim. | **FIXED** (`4f9517e1`) via the auditor's own remedy. The listener's whole decision moved into `foliateInboundMessage(raw, sourceOrigin, isMainFrame, parse = FoliateMessageParser::parse)` — a pure seam in `FoliateBridge.kt` with an injectable parser — so "an inadmissible payload never reaches the parser" is now an **observation** (a spy records whether the parser ran), not an inference from source order. Three behavioural tests replace the claim; the residual structural assertion was narrowed to what it can actually support: `FoliateBridge.kt` has **zero** direct `FoliateMessageParser.parse(` call sites. |
| r1-2 | Low | The comment/test claiming a nested decoy "only ever TIGHTENS" was **wrong in one direction**. `sniffName` scanned for the first `"name"` *anywhere*, so `{"detail":{"name":"book-ready"},"name":"selection"}` classified from the nested key as **uncapped** while the parser read the top-level `selection` — a payload could pick its own classification and *loosen* the gate. | **FIXED** by taking the stronger of the two offered remedies. `sniffName` now anchors to the **first key of the top-level object** (skip JSON whitespace → `{` → skip → the literal `"name"`), which removes the class in both directions and matches exactly what the shim emits. Any other ordering degrades to `null` = uncapped = today's behaviour. Whitespace skipping also tightened from Kotlin's `Char.isWhitespace()` (accepts NBSP and other Unicode spaces) to JSON's set — space/tab/LF/CR, RFC 8259 §2. |
| r1-3 | Low | File sizes over the repo's ~300-line guidance: `FoliateMessageParserTest.kt` 677, `FoliateTocParserTest.kt` 356, `FoliateBridgePolicyTest.kt` 331, `FoliateBridge.kt` 356. | **ACCEPTED with rationale, re-checked and confirmed sound by round 2.** See "Accepted findings" below. |

## Round 2 — `follow-up-recommended` (1 Low)

Round 2 re-verified both round-1 fixes against the real files and confirmed:

- **r1-1 genuinely fixed** — `FoliateBridge.kt` has no direct parse call site; the listener calls
  `foliateInboundMessage(...)`, which calls `FoliateBridgePolicy.admitsMessage(...)` before invoking
  the injected parser.
- **The new `sniffName` is correct** — bounded to 256 chars, JSON whitespace only, the closing-quote
  window edge handled correctly, no throw on short/truncated input, and (the regression that
  mattered) **no well-formed current shim message is now rejected**, since `reader.html` serialises
  `{ name, detail }` in that order.
- **r1-3's acceptance rationale is sound** on the evidence.
- **No Critical/High** in `FoliateMessage.kt`, `FoliateMessageParser.kt`, `FoliateBridgePolicy.kt`
  or the `Azw3Document` exhaustive branches.

| # | Sev | Finding | Disposition |
| --- | --- | --- | --- |
| r2-1 | Low | **Duplicate top-level `name` keys.** The sniff is lexical and reads the FIRST key; kotlinx builds a map, so `parse` sees the LAST. `{"name":"book-ready","name":"selection",…}` therefore presents an uncapped name to the gate and a capped one to the parser. | **ACCEPTED with rationale AND pinned by a test** (the auditor's own first remedy option) — `duplicateTopLevelNameKeys_areAnACCEPTEDResidual_boundedByTheFieldCaps`. See below. |

## Accepted findings — reasoning, so a later round does not re-litigate

**r2-1 (duplicate top-level `name`).** Not fixed, deliberately, on three grounds. (a) The shim
cannot emit it — it serialises one `name` from a JS object literal. (b) Forging it requires posting
from the shell origin, which per the Gate-2 reasoning already implies control of the shell page and
`evaluateJavascript`-equivalent power, at which point the ceiling is moot; the load-bearing defense
remains the bundle patch plus the origin/main-frame gate. (c) The damage is bounded regardless: the
ceiling only ever bounded **parse-time amplification**, and every value that survives is still
subject to the field caps. The committed test asserts all three legs — the gate admits it, and
`parse` still returns `null` on an over-cap `text` — so the residual is recorded behaviour rather
than an unknown. Fixing it properly would mean either rejecting duplicate keys (a JSON-validity
concern this class does not own) or coupling the parser's dispatch to the lexical sniff (which would
re-introduce the coupling the per-name design deliberately avoids).

**r1-3 (file sizes).** The production files this WI owns are `FoliateMessage.kt` 127,
`FoliateMessageParser.kt` 154 and `FoliateBridgePolicy.kt` 176 lines — all well under 300.
`FoliateBridge.kt` was **already** 348 lines before this WI (`git show HEAD~N`), so its 356 is
pre-existing drift plus ~8 lines; it is also WI-3's file, so splitting it here would churn a file
another work item is about to edit. For the tests, rule 50 §8 states "one test class per source file
under test", and this module's own corpus routinely runs far longer (`DiagnosticsRedactorTest` 1117,
`DiagnosticsLogStoreTest` 1067, `IncomingImportCoordinatorTest` 1011), so 677 is within actual
convention and the proposed split would violate the stated one-class-per-source rule.

## Confirmed load-bearing (do not weaken without re-auditing)

- **The gate runs before the parse, and that ordering is now observable.** `parseToJsonElement`
  materialises a tree several times its source string, so a limit applied to parsed *fields* cannot
  bound what parsing already cost. `foliateInboundMessage` exists precisely so this is a tested
  property rather than a comment.
- **The ceiling is per message NAME and the sniff is lexical.** Re-derived and re-confirmed: no
  finite global ceiling exists (TOC label/href lengths are unbounded by contract and preserved
  byte-for-byte for #140's exact `tocHref` matching), and a cap-by-name requiring the parse it bounds
  would be circular.
- **The adversarial TOC test is genuinely adversarial.** A 10 000-row TOC with 200-char labels *and*
  hrefs is ~4.37M chars — above the withdrawn 4 MiB global cap — and is asserted admitted, parsed
  whole, and preserved byte-for-byte. The mutation pass confirms it: capping `book-ready` reddens it.

## Mutation pass (author-run, post-fix)

Each mutation was applied to production code alone, the targeted suite re-run, and the mutation
reverted. Every one reddened a *specific* test:

| Mutation | Test(s) killed |
| --- | --- |
| `rawCeilingFor` parses before classifying | `rawCeiling_isLexical_soAnUnparseablePayloadIsStillCapped` |
| a ceiling applied to `book-ready` | `maxEntryTocWithLongLabelsAndHrefs_isAdmittedParsedAndPreservedByteForByte`, `rawCeiling_isNullForEveryOtherName`, `withinRawCeiling_admitsAnUncappedNameOfAnySize`, `admitsMessage_requiresTrustAndTheCeilingTogether` |
| `MAX_SELECTION_CHARS` check dropped | `selection_textAtFieldCap_isAccepted_oneOverIsDropped`, `selection_capsCountUtf16Units_soAstralTextIsBounded`, `oversizedSelectionPayload_isIgnoredWithoutThrowing` |
| an unknown name treated as capped | `rawCeiling_isNullForEveryOtherName`, `withinRawCeiling_admitsAnUncappedNameOfAnySize`, `admitsMessage_requiresTrustAndTheCeilingTogether`, both TOC/relocate uncapped pins |
| the seam parses first, then gates | `inboundMessage_neverInvokesTheParserForAnInadmissiblePayload` |
| `sniffName` reverted to a first-occurrence scan | `rawCeiling_requiresNameToBeTheFIRSTTopLevelKey_soNoDecoyCanReclassify`, `rawCeiling_acceptsOnlyJsonWhitespace_notEveryUnicodeSpace`, `rawCeiling_isNullForNamelessOrNonJsonInput` |

## Gate 4: PASSED

`follow-up-recommended`, **zero open Critical/High/Medium**. The single open Low is accepted with
rationale above and pinned by a committed test.

Test gate: `RUN-ANDROID-TESTS RESULT: SUCCEEDED` — `:app:testDebugUnitTest --rerun-tasks`,
**2481 tests, 0 skipped, 0 failures, 0 errors** (zero skips verified from the JUnit XML, not from the
build's exit code — bug #369).
