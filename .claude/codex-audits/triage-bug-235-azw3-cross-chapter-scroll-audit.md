---
branch: triage/bug-235-azw3-cross-chapter-scroll
threadId: manual-fallback
rounds: 1
final_verdict: ship-as-is
date: 2026-05-19
---

## Scope

Docs-only triage commit. Records one new bug (#235) in `docs/bugs.md`
from a `/triage` of GH #614 / bug #180 ("so are the epub and azw3").
Touches `docs/bugs.md` only, plus `project.yml` / `project.pbxproj`
(version bump 3.36.15/530 → 3.36.16/531).

**No Swift source files changed.** The audit-gate hook fires on
`project.pbxproj` — false positive of the Swift-file heuristic. Manual
mini-audit.

## What this triage processed

User input (`/triage`): GH #614 (= bug #180, TXT cross-chapter
continuous scroll, FIXED) + "so are the epub and azw3" — i.e. EPUB and
AZW3 have the same cross-chapter scroll discontinuity. Two items,
triaged separately.

### EPUB → DUPLICATE of open bug #165

`docs/bugs.md` bug #165 ("EPUB chapter navigation unintuitive", `EPUB/*`,
High, `TODO`) explicitly covers "continuous cross-chapter scroll in
scroll mode" — its row cites `reader-navigation.md` §2.3, design landed
2026-05-18. The EPUB half of the report is already tracked. Per the
triage rule for an open duplicate: reference the existing ID, create
nothing. No `docs/bugs.md` change for EPUB.

### AZW3 → new bug #235

- **Bug, not feature** — AZW3/MOBI reader + scroll mode exist; the
  cross-chapter continuity is the defect. Implemented-but-discontinuous
  = bug, consistent with how the same problem is tracked for TXT (#180)
  and EPUB (#165).
- **Not a duplicate** — no `docs/bugs.md` row tracks AZW3 cross-chapter
  continuous scroll. The AZW3/MOBI/Foliate bugs (#106/#108/#149/#176/
  #189/#199/#201/#207/#229 …) cover loading, chrome, TTS, highlights,
  the scroll *toggle* — none the cross-section scroll continuity. #165
  is EPUB-scoped; `reader-navigation.md` scopes #812 (EPUB) and #842
  (MD), not Foliate/AZW3.
- **Investigation evidence** — AZW3/MOBI renders via Foliate-js; the
  bundled paginator (`vreader/Services/Foliate/JS/paginator.js`,
  `foliate-bundle.js`) navigates **section-by-section** (`prevSection`
  / `nextSection`). Bug #189 (FIXED) set `flow: scrolled` so scroll
  mode engages within a section; cross-section continuity was never
  addressed.
- Recorded as bug #235 (`Reader/AZW3`, Medium, `TODO`) — GH #983;
  summary row + Open Bug Details entry.

## Mechanics

- GH issue #983 created (labels `bug` + `severity:medium`); the row
  carries `GH: #983` per the mechanical-mirror rule.
- `docs/bugs.md` edited via a Python pass (file too large for the Edit
  tool); the row already carries `GH: #983`.
- Triage is classification only — no fix attempted. The fix is
  `/fix-issue #983` work.

## Verdict

ship-as-is — documentation only, one new bug row + detail, no code
risk. Manual fallback used because there is nothing to send to Codex.
