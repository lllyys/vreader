---
branch: docs/renumber-bug-236-to-239
threadId: manual-fallback
rounds: 1
final_verdict: ship-as-is
date: 2026-05-19
---

## Scope

Docs-only tracker-integrity fix. Renumbers one bug row in
`docs/bugs.md` (236 → 239) to resolve a duplicate-ID collision. Touches
`docs/bugs.md` only, plus `project.yml` / `project.pbxproj` (version
bump 3.36.20/535 → 3.36.21/536).

**No Swift source files changed.** The audit-gate hook fires on
`project.pbxproj` — false positive of the Swift-file heuristic. Manual
mini-audit.

## What happened

Two `| 236|` rows existed in `docs/bugs.md` after PR #991 merged:

1. `XCUITestMockSpeechSynthesizerTests.speakCompletesWithDidFinish` flaky
   test — a bug that had already been renumbered 234 → 235 → 236
   (commits `d920bbd`, `a312f00`) due to two earlier concurrent-agent
   ID collisions.
2. "Paged layout — side-tap page-turn dead across all native readers"
   (GH #988) — filed by PR #991 (this session's triage), which assumed
   236 was free without re-checking the max ID; meanwhile the flaky-test
   bug had been renumbered into 236 and bugs #237/#238 had been filed
   (commit `9a46a2c`).

`docs/bugs.md` did not conflict on the PR #991 merge (the two `| 236|`
rows are on different lines), so the collision merged silently.

## Resolution

Per the `#225/#226` and `#228` collision precedent already recorded in
`docs/bugs.md` (established row keeps the number; the newcomer takes the
next free number):

- The flaky-test bug — already established at 236 on `main` before PR
  #991 — **keeps 236**.
- The paged-pageturn bug (the newcomer) is renumbered **236 → 239** —
  the next free integer (237, 238 are taken).

Changes:
- `docs/bugs.md`: the paged-pageturn summary row `| 236|` → `| 239|`
  and its Open Bug Details header `### Bug #236` → `### Bug #239`; a
  renumbering note prepended to the row's Notes per precedent.
- GH issue #988's title updated `Bug #236:` → `Bug #239:` via
  `gh issue edit` (the issue number #988 is unchanged; only the title's
  bug number).

### Correctness checks

1. **No remaining duplicate** — after the edit, `grep -c '^| 236| '` =
   1 (flaky-test only), `'^| 239| '` = 1, `'^### Bug #239 '` = 1.
2. **Only the paged-pageturn rows touched** — the Python pass matched
   on the row/detail text "Paged layout — side-tap page-turn is dead",
   so the flaky-test `| 236|` row (line ~871) was untouched.
3. **GH linkage intact** — the row still carries `GH: #988`; only the
   GH issue's *title* bug-number was updated. `docs/bugs.md` remains the
   source of truth.
4. **Version bump** — 3.36.21 / build 536 (patch — docs / tracker
   hygiene). `xcodegen generate` confirmed.

## Verdict

ship-as-is — documentation only, one tracker renumber, no code risk.
Manual fallback used because there is nothing to send to Codex.
