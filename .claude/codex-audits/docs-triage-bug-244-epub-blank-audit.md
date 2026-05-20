---
branch: docs/triage-bug-243-epub-blank
threadId: manual-fallback
rounds: 1
final_verdict: ship-as-is
date: 2026-05-20
---

## Scope

Docs-only triage filing. Adds one new row + one Open-Bug-Details
entry to `docs/bugs.md` for Bug #244 (EPUB reader opens but content
area is blank). Touches `docs/bugs.md` only, plus `project.yml` /
`project.pbxproj` (version bump 3.38.14/589 → 3.38.15/590).

**No Swift source files changed.** The audit-gate hook fires on
`project.pbxproj` — false positive of the Swift-file heuristic.
Manual mini-audit.

## Manual audit evidence

### What changed and why

User reported via `/triage`: "can not open the epub books now".
Symptom-questionnaire clarified to "opens but blank / no text" on a
single tested EPUB.

`docs/bugs.md` gains:

- One new summary row at the top of the table (Bug #244 — TODO,
  High, Reader/EPUB, GH #1065).
- One new Open Bug Details entry above Bug #239 (chronological-newest
  order). Sections: Reported / Symptom / Scope / Repro / Expected /
  Actual / Likely cause / Fix direction / Verification harness.

### Number-collision handling

This filing was originally inserted as Bug #243 (max ID on local
`main` at the time of the user's `/triage` was 242), pushed to a
branch, and opened as PR #1066. While the PR sat unmerged, the
bug-fix cron concurrently merged PRs #1057 / #1062 / #1063 / #1064
onto `main`, the first of which filed a *different* Bug #243
(DebugBridge `provider`-URL-family bug, GH #1057). The PR became
non-mergeable due to the version-bump conflict, and the number
collision required renumbering per the established #225/#226/#228
and #236→#239 precedent.

Resolution: established row (DebugBridge provider, on `main` first)
keeps #243; this newcomer renumbers to **#244** (next free integer).
GH issue #1065's title updated via `gh issue edit` from "Bug #243…"
to "Bug #244…"; the GH issue *number* (#1065) is unchanged — only
the title's bug-number was renumbered. Branch was reset to clean
origin/main and the row re-applied as #244 with a renumbering note
in its Notes column.

### Correctness checks

1. **Bug-vs-feature distinction** — EPUB reader is implemented and
   was openable on prior versions (feature #11 VERIFIED, feature #21
   VERIFIED, recent EPUB-touching fixes #182 / #219 / #220 in
   v3.37.x shipped against an openable reader). Now-broken
   implementation = bug, not feature. Correct classification per
   AGENTS.md.
2. **No open duplicate** — code-checked the bug tracker for
   EPUB-open / EPUB-blank / EPUB-fail rows. The closest matches
   (Bug #168 EPUB font family, Bug #167 EPUB overscroll bounce,
   Bug #171 EPUB paged mode columns, Bug #165 EPUB chapter
   navigation) all describe different symptoms and most are FIXED.
   No regression of a previously-FIXED bug — symptom is new.
3. **GH mirror** — issue #1065 created with `bug` +
   `severity:high` labels; title renumbered to "Bug #244" after the
   collision. `GH: #1065` stamped in the row's Notes column per the
   mechanical-mirror rule.
4. **Bug ID** — max ID on origin/main is 243 (DebugBridge provider);
   next free is 244. There is a pre-existing collision at #237 (two
   FIXED rows share that ID), but per triage rules this is not
   fixed during triage — it's a tracker-integrity issue noted for a
   future cleanup PR.
5. **No fix attempted** — triage is classification only; the entry
   captures symptom, scope, repro, suspects, and fix direction but
   does not implement the fix. The fix will go through `/fix-issue`
   GH #1065 with a separate user invocation.
6. **Version bump** — 3.38.15 / build 590 (patch — docs / tracker
   triage). `xcodegen generate` confirmed; `xcodebuild build`
   SUCCEEDED on iPhone 17 Pro Simulator (Debug).

## Verdict

ship-as-is — documentation only, one bug filing, no code risk.
Manual fallback used because there is nothing to send to Codex.
