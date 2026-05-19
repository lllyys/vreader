---
branch: triage/bug-236-paged-pageturn-regression
threadId: manual-fallback
rounds: 1
final_verdict: ship-as-is
date: 2026-05-19
---

## Scope

Docs-only triage commit. Records one new bug (#236) in `docs/bugs.md`
for a user-reported paged-mode page-turn defect. Touches `docs/bugs.md`
only, plus `project.yml` / `project.pbxproj` (version bump 3.36.16/531
→ 3.36.17/532).

**No Swift source files changed.** The audit-gate hook fires on
`project.pbxproj` — false positive of the Swift-file heuristic. Manual
mini-audit.

## What this triage processed

User input (`/triage`): "turning paged is not working in txt, epub, azw3"
— page-turning in Paged layout is broken in the TXT, EPUB, and
AZW3/MOBI readers.

### Investigation

The classification rests on a read-only investigation by a separate
agent context (general-purpose subagent — author/auditor separation per
rule 48). It read the reader-dispatch / paged-render / tap-zone code
across all three readers and reported with file:line + commit
evidence. Key finding: feature #54 WI-3 (commit `e30f769`) deleted
`ReaderUnifiedDispatch.swift`, the only mount of `.tapZoneOverlay(config:)`;
`TapZoneOverlay` is the sole producer of `.readerNextPage` /
`.readerPreviousPage`, so all native readers' page-turn observers are
dead. Verified independently: grep for `tapZoneOverlay(config` in
`vreader/` returns only the modifier definition — zero call sites.

### Classification — bug #236 (Reader/*, High, TODO) — GH #988

- **Bug, not feature** — page-turn was implemented (the `.readerNextPage`
  observers + the `TapZoneOverlay` producer existed pre-#54); feature
  #54 broke it. A regression bug.
- **Not a duplicate.** Bug #162 ("Tap Zones config is a no-op on native
  readers") is `FIXED`, but its fix was a config-visibility *mitigation*
  ("hide the Tap Zones section outside Unified mode"); feature #54
  removed Unified mode entirely, so #162's mitigation is moot and the
  page-turn breakage is a distinct, newer regression. Bug #171 (EPUB
  paged columns) is `FIXED` and unrelated (rendering, not input). Bug
  #215 (MD paged) is the MD-scoped instance of the *same* root cause —
  cross-referenced, not duplicated (the user's report is TXT/EPUB/AZW3,
  not MD; #215's row + history are MD-specific).
- **Severity High** — page-turn in Paged layout is a core reading
  interaction, dead via side-tap across every native reader; regression
  of VERIFIED feature #21 + DONE feature #25.
- **One bug, not three** — the investigation found a single shared root
  cause (the deleted `TapZoneOverlay` producer) behind the TXT/EPUB/AZW3
  symptom, so it is recorded as one bug with a per-format breakdown,
  not fragmented per format.

### Recorded sub-findings (in the bug detail, not separate rows)

- **TXT** has a second, deeper, pre-existing layer — `TXTReaderContainerView`
  has no paged renderer at all (`updatePaginationIfNeeded()` is dead
  code; no `NativeTextPagedView` branch). The detail flags this and
  notes it may warrant its own row when the fix is picked up — not
  pre-fragmented here (one user report, one symptom).
- **AZW3 swipe** page-turn still works (Foliate-js internal touch
  handling); only side-tap is dead. The detail records that the
  swipe-vs-side-tap distinction may need a device repro to confirm
  which the user observed.

## Mechanics

- GH issue #988 created (labels `bug` + `severity:high`); the row
  carries `GH: #988` per the mechanical-mirror rule.
- `docs/bugs.md` edited via a Python pass (file too large for the Edit
  tool); the row already carries `GH: #988`.
- Triage is classification only — no fix attempted. The fix is
  `/fix-issue #988` work.

## Verdict

ship-as-is — documentation only, one new bug row + detail, no code
risk. Manual fallback used because there is nothing to send to Codex.
