---
branch: docs/triage-bug-246-reopen-108
threadId: manual-fallback
rounds: 1
final_verdict: ship-as-is
date: 2026-05-20
---

## Scope

Docs-only triage filing. Two distinct issues, one new bug + one
regression, from a single user `/triage` message:

- **NEW**: Bug #246 — AZW3 book opens in the wrong reader UI.
- **REOPENED**: Bug #108 — AZW3/Foliate reader center-tap does not
  toggle chrome (was FIXED 2026-05-04, regressed 2026-05-20).

Touches `docs/bugs.md` only, plus `project.yml` / `project.pbxproj`
(version bump 3.38.16/591 → 3.38.17/592).

**No Swift source files changed.** The audit-gate hook fires on
`project.pbxproj` — false positive of the Swift-file heuristic.
Manual mini-audit.

## Manual audit evidence

### What changed and why

User reported via `/triage`: "azw3 book now at wrong format, and can
not see the tool bar by tapping on the center". Per the rule's
"One issue per triage" guidance, each clause was investigated
separately. Symptom-questionnaire on the first clause clarified to
"Opens in the wrong reader UI".

`docs/bugs.md` gains:

- **One new summary row** at the top of the table — Bug #246 (TODO,
  High, Reader/AZW3, GH #1072) with full notes column.
- **One reopen**: Bug #108's summary row changed status `FIXED →
  REOPENED`, title suffixed with "(REOPENED 2026-05-20 — regression)",
  and Notes column rewritten to lead with the regression context;
  the original fix history is preserved verbatim after the new
  reopen header.
- **One new Open Bug Details entry** for Bug #246 above Bug #244
  (chronological-newest order). Sections: Reported / Symptom /
  Repro / Expected / Actual / Scope / Possible root causes / Fix
  direction / Verification harness / Cross-ref.

### Correctness checks

1. **Bug-vs-feature distinction (both)**:
   - Bug #246: AZW3 reader is implemented and was openable on prior
     versions (feature #21 VERIFIED; Bug #108 closed 2026-05-04
     against a working AZW3 reader). Now-broken implementation =
     bug.
   - Bug #108: was FIXED 2026-05-04 and is now regressing — by the
     skill's rule, a fixed-bug regression is **REOPENED**, not a
     new bug.
2. **No new-bug duplicate** — code-checked the bug tracker for
   `azw3.*wrong|wrong.*azw3|center.*tap` etc. Closest matches all
   FIXED (#108, #239 covers paged side-tap not center-tap, #162
   covers tap-zones config). Bug #246 has no open duplicate.
3. **REOPEN reasoning for #108** — User's literal complaint ("can
   not see the tool bar by tapping on the center" on AZW3) matches
   the Bug #108 title verbatim. Per the skill's rule "Duplicate
   (fixed): Matches a fixed bug — it's a regression. Reopen the
   existing bug." Original FoliateSpikeView fix (handleMessage
   `case "tap"`) is still present at line 617-623; the JS producer
   is still at `foliate-host.js:120`. Regression suspect: feature
   #56 WI-11 (`FoliateBilingualContainerView`) or WI-15
   (re-translation) bilingual JS injection breaks the doc-level
   click listener attached on `view.addEventListener('load', ...)`.
4. **GH mirror**:
   - Bug #246: created GH issue #1072 with `bug` + `severity:high`
     labels; `GH: #1072` stamped in the row's Notes column.
   - Bug #108: GH #224 reopened via `gh issue reopen` with a
     regression-context comment; the row's `GH: #224` link is
     unchanged.
5. **Bug IDs** — max ID on `main` (post-PR-#1071 pull) is 245.
   Next free is **246** (assigned to the new bug). 247 reserved
   for potential follow-up but not used here (the second issue
   reopens #108 rather than filing a new row).
6. **Cross-reference** — Bug #246's notes cross-ref Bug #108 (the
   reopened one) and vice versa. If both share a feature #56 WI-11
   root cause, fixing #246 may resolve #108's repro too.
7. **No fix attempted** — triage is classification only. Filing /
   reopening captures symptom, scope, repro, suspects, fix
   direction. The fix(es) will go through `/fix-issue` runs with
   separate user invocations.
8. **Version bump** — 3.38.17 / build 592 (patch — docs / tracker
   triage). `xcodegen generate` confirmed; `xcodebuild build`
   SUCCEEDED on iPhone 17 Pro Simulator (Debug).

## Verdict

ship-as-is — documentation only, one bug filing + one regression
reopen, no code risk. Manual fallback used because there is nothing
to send to Codex.
