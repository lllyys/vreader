---
branch: feat/139-wi-3-md-scanner
threadId: 019fcb8f-c586-7e30-a06c-27ca5991a5f9
rounds: 3
final_verdict: block-recommended
date: 2026-08-04
---

# Gate-4 audit — feature #139 WI-3 (`MdTocScanner`)

Files under review (both new on this branch):

- `android/app/src/main/kotlin/com/vreader/app/reader/nav/MdTocScanner.kt`
- `android/app/src/test/kotlin/com/vreader/app/reader/nav/MdTocScannerTest.kt`

Auditor: Codex `gpt-5.6-sol` via `scripts/run-codex.sh` (rule 53), read-only sandbox, three
independent sessions. Raw transcripts: `.reports/audit-r1.txt`, `-r2.txt`, `-r3.txt` (not
committed — they are ~170 KB each).

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
| Medium | Cancellation was still unbounded during range *classification*: `trimmedStart`, `trimmedEnd`, `fenceRunLength`, `parseAtxHeading` and `setextDepth` could each traverse an arbitrarily long line without a check (a huge all-space line, a huge marker run), so the header's "observed every 8 192 units inside one line" claim overclaimed. The enormous-line test cancelled inside `contentEnd()` and could not detect it. | **FIXED after the round** (`02072f85`) — every traversal that can run a line's length now goes through one shared checked pair, `walkForward` / `walkBackward`; `contentEnd` is expressed in terms of it. The header claim is restated to say exactly that. New test `scan_isCancellationCooperative_insideALongClassifierRun` cancels on the sixth query — the first one raised *inside* the setext run — with the query accounting written out in the test. |

## Status — why this artifact says `block-recommended`

Rule 47 / rule 55 cap the in-lane audit loop at **3 rounds**, and round 3 ended
`block-recommended`. Its single Medium is **fixed on the branch and the targeted gate is green
(44/44)**, but that fix is itself **unaudited** — a fourth round would exceed the cap, so the lane
stops here and reports rather than self-certifying.

To clear this, the orchestrator needs exactly one of:

1. **One confirmation audit round** scoped to the r3 fix (the `walkForward`/`walkBackward`
   extraction + the header claim + the new test) — then update `final_verdict` here; or
2. **An explicit accept** of the residual with rationale. The precedent for accepting it is in
   this feature's own merged WI-2: `TxtTocRuleEngine`'s header documents and accepts exactly this
   class ("the worst case after a cancel is one uninterrupted walk … bounded by a full pass over
   the text (~100 ms for the real 14 MB book)"), on a background dispatcher. The MD residual was
   strictly smaller than that even before the fix.

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
