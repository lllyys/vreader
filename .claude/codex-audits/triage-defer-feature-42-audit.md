---
branch: triage/defer-feature-42
threadId: manual-fallback
rounds: 1
final_verdict: ship-as-is
date: 2026-05-19
---

## Scope

Docs-only triage commit. Re-classifies feature #42 in `docs/features.md`
from `PLANNED` to `DEFERRED`. Touches `docs/features.md` only, plus
`project.yml` / `project.pbxproj` (version bump 3.36.1/516 →
3.36.2/517).

**No Swift source files changed.** The audit-gate hook fires on
`project.pbxproj` — false positive of the Swift-file heuristic. Manual
mini-audit.

## What this commit records

Feature #42 — "AZW3/KF8 + Foliate-js unified reader engine" — status
`PLANNED` → `DEFERRED`, on an explicit human decision (2026-05-19).

### Rationale (recorded in the row)

- The headline of #42 is swapping the working, `VERIFIED`
  `EPUBWebViewBridge` for Foliate-js. The feature's own audited plan
  (`dev-docs/plans/20260518-feature-42-foliate-unified-reader-engine.md`
  §1) states it has **no direct user-facing feature** and is a
  **high-risk replacement of a VERIFIED, heavily-bug-fixed engine**.
- #42 was `PLANNED` with a Gate-2-passed plan but had been parked at
  **Gate 3, blocked on human ratification** (plan §9 G1) — no
  ratification was given. `GH #113` is already CLOSED.
- EPUB has accrued further investment since the plan was drafted
  (feature #60 v2 reskin, EPUB-highlight bug fixes), which raises both
  the throwaway cost and the regression surface of the swap.
- The low-risk half — consolidating the unwired duplicate Foliate path
  (`FoliateReaderHost` / `FoliateViewBridge` / `FoliateURLSchemeHandler`
  vs the live `FoliateSpikeView`) — is explicitly recommended by the
  plan's §10 to be split into its own feature. It is **not** filed by
  this commit; the user asked only for the deferral. The row's note
  records that the split is available.

### Hook / mirror notes

- `DEFERRED` is not a mirror-required status, so `check_gh_issue_mirror.sh`
  does not gate this edit; #42 retains `GH: #113` in Notes regardless.
- The GH-issue rule says not to *create* a GH issue for `DEFERRED`
  features — none is created. #113 already exists and is closed; no GH
  action is taken.
- `check_terminal_status_evidence.sh` gates `VERIFIED`/`FIXED` flips
  only — `DEFERRED` is not gated.

## Verdict

ship-as-is — documentation only, one tracker status flip, no code risk.
Manual fallback used because there is nothing to send to Codex.
