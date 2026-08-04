---
branch: feat/139-wi-3-md-scanner
threadId: 019fcb97-9687-7823-a40b-54be17f6e8bb
rounds: 4
final_verdict: ship-as-is
date: 2026-08-04
---

# Gate-4 audit — feature #139 WI-3 (`MdTocScanner`)

Files under review (both new on this branch):

- `android/app/src/main/kotlin/com/vreader/app/reader/nav/MdTocScanner.kt`
- `android/app/src/test/kotlin/com/vreader/app/reader/nav/MdTocScannerTest.kt`

Auditor: Codex `gpt-5.6-sol` via `scripts/run-codex.sh` (rule 53), read-only sandbox, four
independent sessions. Raw transcripts: `.reports/audit-r{1,2,3,4}.txt` (not committed — ~90–215 KB
each); the round-4 scope diff is `.reports/r4-scope.diff`.

Every round was asked for the same five things: fidelity to the iOS original
(`vreader/Services/TOCBuilder.swift:107-216`), fence/setext/front-matter edge cases,
source-offset correctness under LF/CRLF/CR, **whether any named test passes vacuously**, and
Kotlin-specific hazards.

## Round 1 — threadId `019fcb83-2b74-7ac1-8682-2ed15bda82ee` — block-recommended

| Sev | Finding | Disposition |
| --- | --- | --- |
| High | MD extraction was unbounded before materialization: `scan` returned a bare `List` and built every heading of a pathological document before WI-4 could apply plan §4.4's 50 000 cap. It also disagreed with the `ExtractResult` shape WI-4's own `applyCap(result: ExtractResult)` expects. | **FIXED** (`b23e961d`) — `scan(text, limit): ExtractResult`, `require(limit > 0)`, stops the walk at the budget. Plan §6.1's `scan(text): List<DetectedHeading>` signature is superseded; §4.4 and WI-4's surface both want the bounded shape. |
| Medium | The two-pass whole-document `lineStarts()` index ran to completion — and allocated an O(lines) `IntArray` — before the first cancellation check. | **FIXED** (`b23e961d`) — replaced by a streaming line walk; the front-matter pre-pass is bounded to 100 lines. |
| Low | No coverage for a document ending WITH a terminator under each line ending. | **FIXED** — `md_documentEndingWithATerminator_doesNotShiftOffsets`. |
| Low | `emptyDocument_yieldsNoHeadings` would pass against a scanner that never scans. | **FIXED** — positive control added in the same test. |

Verified clean in r1: ATX/fence parity construct by construct, the trim set (Zs ∪ TAB), the
guarded closing-hash strip, front-matter conditions, setext negatives, and "all 36 tests checked;
none asserts against the wrong object."

## Round 2 — threadId `019fcb88-0ec2-7f52-b4ec-16450c8eaf32` — block-recommended

Confirmed r1's fixes landed with **no offset regression** across LF, CRLF, lone CR, terminal
separators, separator-only input, unterminated input, empty input, and front matter ending at EOF.

| Sev | Finding | Disposition |
| --- | --- | --- |
| Medium | Cancellation and allocation were still unbounded WITHIN one line: `contentEnd()` had no check, and every line was `substring`'d merely to classify it, so a multi-megabyte terminator-free document was copied twice and deferred a cancel for the whole walk. | **FIXED** (`6871eff3`) — classification is RANGE-based (`from`/`to` indices); the only string allocated is a heading title about to be emitted, plus one front-matter probe bounded by `MAX_FRONT_MATTER_LINE_LENGTH`. `contentEnd()` checks every 8 192 code units. |
| Low | `scan_stopsAtLimit_doesNotMaterializeBeyondIt` only asserted the returned shape — a scan-everything-then-truncate implementation would pass it. | **FIXED** — the test now proves the early stop observably with a cancel-on-second-query job plus a same-document/no-limit control that must throw. |
| Low | Cancellation was only tested pre-cancelled, never mid-walk. | **FIXED** — `scan_isCancellationCooperative_evenInsideOneEnormousLine`. |

## Round 3 — threadId `019fcb8f-c586-7e30-a06c-27ca5991a5f9` — block-recommended

No Critical, High or Low. The auditor re-derived every range bound by hand after the refactor and
found **no offset or classifier regression**; it confirmed the bounded-allocation claim is now
accurate, that the rewritten limit test genuinely queries the job and its control discriminates,
and that `scan(text, MAX_TOC_ENTRIES + 1)` remains compatible with WI-4's `applyCap` flow.

| Sev | Finding | Disposition |
| --- | --- | --- |
| Medium | Cancellation was still unbounded during range *classification*: `trimmedStart`, `trimmedEnd`, `fenceRunLength`, `parseAtxHeading` and `setextDepth` could each traverse an arbitrarily long line without a check (a huge all-space line, a huge marker run), so the header's "observed every 8 192 units inside one line" claim overclaimed. The enormous-line test cancelled inside `contentEnd()` and could not detect it. | **FIXED** (`02072f85`) — every traversal that can run a line's length now goes through one shared checked pair, `walkForward` / `walkBackward`; `contentEnd` is expressed in terms of it. The header claim is restated to say exactly that. New test `scan_isCancellationCooperative_insideALongClassifierRun` cancels on the sixth query — the first one raised *inside* the setext run — with the query accounting written out in the test. **Independently confirmed closed by round 4.** |

## Round 4 — threadId `019fcb97-9687-7823-a40b-54be17f6e8bb` — ship-as-is

**Sanctioned override of rule 47's 3-round cap — authorized by the orchestrator, reason recorded
so the cap is not treated as advisory by default.** Round 3 ended `block-recommended`; its single
Medium was fixed immediately afterwards in `02072f85`, which left the fix itself unaudited. The
lane offered an accept-with-precedent instead (merged WI-2 documents a strictly larger residual of
the same class), and the orchestrator declined it for a specific reason: the artifact's
`final_verdict` was `block-recommended`, the merge hook accepts only `ship-as-is` /
`follow-up-recommended`, so the real choice was "one scoped round" versus "hand-edit a verdict
nobody earned". One round on a ~60-line diff was the cheaper and more honest path. This is the
same shape of override the Gate-2 plan audit took (its R4), and for the same kind of reason.

Scope was narrowed to the fix ONLY — three questions, with the `ExtractResult` signature
deviation, ATX/fence/setext/front-matter semantics, the CR-only improvement and the file length
declared out of scope and non-reportable.

| Question | Result |
| --- | --- |
| Is EVERY line-length traversal now routed through the checked pair, or did the refactor move the unbounded work elsewhere? | **No finding.** Confirmed for `contentEnd`, both trims, the fence run, the fence info-string scan, the ATX opening and closing hash runs, and the setext run. "Each predicate is O(1), and no alternative unchecked loop bypasses the pair or skips checks during a pathological matching run." |
| Does `scan_isCancellationCooperative_insideALongClassifierRun` genuinely exercise a classifier, or pass vacuously (specifically: the wrong-object shape a sibling WI hit)? | **No finding.** The auditor re-derived the query arithmetic independently — entry 1, four during the 32 768-unit terminator scan, so query 6 lands 8 192 units into `setextDepth` — and confirmed `CancelAfter`'s `CoroutineContext.get(Job)` override makes the scanner query the wrapper, "if it queried the delegate instead, the cancellation assertion would fail". The no-cancel control confirms the fixture is a valid setext heading. |
| Does the header now claim exactly what is true? | **No finding** — "precise for the scanner's line traversals: neither overclaiming nor underclaiming". |

**Severity counts: Critical 0, High 0, Medium 0, Low 0. Verdict: ship-as-is.**

No code changed in round 4, so no re-test was required by the lane order; the gate was re-run
against the final tree anyway and stayed green.

## Status

**Gate 4 CLOSED — zero open Critical/High/Medium findings** across four rounds (r1 H=1 M=1 L=2,
r2 M=1 L=2, r3 M=1, r4 clean). Every finding is dispositioned above; none was accepted-with-
rationale, all were fixed.

## Test gate

`RUN-ANDROID-TESTS RESULT: SUCCEEDED` — `./gradlew :app:testDebugUnitTest --tests
'*MdTocScannerTest*' --rerun-tasks`, 44 tests / 0 failures / 0 errors. JVM only; no emulator.

## Deviations from the plan, recorded

- **`MdTocScanner.scan` signature** — plan §6.1 says `suspend fun scan(text: String):
  List<DetectedHeading>`; shipped as `suspend fun scan(text: String, limit: Int): ExtractResult`
  (r1 High). WI-4 calls `scan(text, MAX_TOC_ENTRIES + 1)` and feeds `applyCap`.
- **File length** — `MdTocScanner.kt` is 338 lines against the ~300 guideline, of which ~140 are
  documentation. Splitting the classifiers into a third file was not available: WI-3's declared
  write-set is exactly two files. Named as a candidate follow-up, not a defect.
