---
branch: triage/bug-234-txt-toc-jump
threadId: manual-fallback
rounds: 1
final_verdict: ship-as-is
date: 2026-05-19
---

## Scope

Docs-only triage commit. Records one new bug (#234) in `docs/bugs.md`
for a user-reported TXT TOC-navigation defect. Touches `docs/bugs.md`
only, plus `project.yml` / `project.pbxproj` (version bump 3.36.12/527
→ 3.36.13/528).

**No Swift source files changed.** The audit-gate hook fires on
`project.pbxproj` — false positive of the Swift-file heuristic. Manual
mini-audit.

## What this commit records

User report: "txt toc jumping sometime is not working or to the wrong
place." → **Bug #234** (`Reader/TXT`, Medium, TODO) — GH #978.

### Classification reasoning

- **Bug, not feature.** TXT TOC navigation IS implemented — the
  `.readerNavigateToLocator` handler in `TXTReaderContainerView.swift`
  and `TXTReaderViewModel.navigateToChapterByTitle` /
  `navigateToChapter` / `navigateToGlobalOffset`. An implemented path
  that is intermittently broken is a bug (tracker rule).
- **Not a duplicate.** The TXT/TOC bugs in `docs/bugs.md` — #83 (TOC
  *detection*), #109 (chapter-mode progress bar), #173 (fixture
  headings), #180 (scroll-continuity), #179 (Dynamic Island) — are all
  `FIXED`; #165 / #182 are EPUB. No open bug covers "TXT TOC tap →
  wrong chapter / no-op."
- **Not a reopen of #180.** #180's headline symptom is scroll
  *continuity* across chapters — a different symptom than "TOC tap
  jumps wrong." But #180's continuous-scroll fix (FIXED 2026-05-19)
  reworked the TXT chapter-nav/offset path, so #180 is recorded as a
  cross-reference and a prime regression suspect — without conflating a
  focused TOC-jump defect into the large continuous-scroll row.

### Investigation evidence (recorded in the bug detail)

Read `TXTReaderContainerView.swift` (TOC-tap handler ~552-566) and
`TXTReaderViewModel.swift` (`navigateToChapter` 554, `navigateToChapterByTitle`
594, `navigateToGlobalOffset` 609). Candidate root causes captured in
the row + detail: exact-`charOffsetUTF16` entry match, exact trimmed
chapter-title `firstIndex(where:)` match (duplicate/empty titles → wrong
chapter; drift → no-op), byte-ratio offset estimation when
`globalStartUTF16 < 0`, and a continuous-surface scroll timing race.

### Mechanics

- A GH issue (#978, labels `bug` + `severity:medium`) was created; the
  row's Notes carry `GH: #978` per the mechanical-mirror rule.
- Triage is classification only — no fix is attempted here. The fix is
  `/fix-issue` work against GH #978.
- `docs/bugs.md` was edited via a Python pass (the file is too large
  for the Edit tool); the new row already carries `GH: #978`, so the
  mirror rule is satisfied.

## Verdict

ship-as-is — documentation only, one new bug row + detail, no code
risk. Manual fallback used because there is nothing to send to Codex.
