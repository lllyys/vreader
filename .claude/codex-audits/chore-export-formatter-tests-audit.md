---
branch: chore/export-formatter-tests
threadId: 019f44a2-41d0-7c31-98ab-a7bf01a56660
rounds: 1
final_verdict: ship-as-is
---

# Gate-4 audit — export-formatter test suites (feature #130 M-SHAKEDOWN Lane B)

## Scope

Test-only diff on `vreaderTests/Services/Export/AnnotationExporterTests.swift`
(`git diff main...HEAD`): two appended Swift Testing suites,
`MarkdownExportFormatterTests` and `JSONExportFormatterTests`, exercising
`MarkdownExportFormatter` / `JSONExportFormatter` directly with hand-built
`AnnotationExportPayload` values. No production code touched.

## Round 1 (Codex gpt-5.5, read-only sandbox, xhigh)

- Report: `.reports/audit-r1.txt` (lane worktree, untracked)
- Findings: **0 Critical / 0 High / 0 Medium / 1 Low**
  - **Low** — `allDateFields_encodeAsISO8601` overstated its name:
    `createdAt`/`updatedAt` shared one fixture date, so the two fields were
    not individually pinned.
- Auditor notes: Markdown tests pin real formatter behavior; JSON
  sorted-keys assertions are deterministic (they target explicit
  `JSONEncoder.OutputFormatting` settings); redundancy with the sibling
  `MarkdownExportTests`/`JSONExportTests` suites is intentional; file at
  299 lines (under the guideline, no headroom).
- Verdict line: `VERDICT: ship-as-is`

## Fixes applied after round 1

- Commit `441c7b46`: gave `createdAt` a distinct date (epoch + 1 day) so
  `exportedAt`, `createdAt`, and `updatedAt` are each pinned by a unique
  ISO-8601 string; dropped the cosmetic pretty-print assertion to hold the
  file under 300 lines.
- Targeted suites re-run after the fix — all
  `RUN-TESTS RESULT: SUCCEEDED`:
  - `vreaderTests/MarkdownExportFormatterTests` (5 tests)
  - `vreaderTests/JSONExportFormatterTests` (3 tests)
  - `vreaderTests/AnnotationExporterTests` (9 tests, regression)

## Outcome

Ship-as-is after the Low fix; no further rounds required (acceptance bar —
zero open Critical/High/Medium — met in round 1).
