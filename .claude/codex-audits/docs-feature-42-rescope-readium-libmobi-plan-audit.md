---
branch: docs/feature-42-rescope-readium-libmobi-plan
threadId: manual-fallback
rounds: 1
final_verdict: ship-as-is
date: 2026-05-28
---

## Scope

Docs/planning only. Moves the converged reader-engine architecture (developed across this
session via web research + four Codex consults) into the repo as the **re-scoped Feature #42
Gate-1 plan**, and updates the `docs/features.md` #42 row to reflect the re-scope. No Swift,
no app behavior. The `project.pbxproj` delta is the rule-40 version bump (3.40.8/689 →
3.40.9/690, after rebasing onto main which advanced to v3.40.8) which trips this audit-gate hook.

Files:
- NEW `dev-docs/plans/20260528-feature-42-readium-libmobi-reader-engine.md` — Gate-1 plan
  DRAFT (Option B = Readium + libmobi convert-on-import; Option A Foliate-swap retained as a
  rejected alternative; both Mermaid diagrams; open-decision BLOCKERS; Gate-1 completion TODO
  + first-cut WI sketch).
- `docs/features.md` #42 row — summary re-scoped; Notes prepended with the re-scope +
  BLOCKERS + plan link; prior Option-A/Foliate history preserved; **status kept DEFERRED**.
- removed `/tmp/vreader-new-architecture.md` (the scratch source — "moved", not duplicated).

## Manual audit evidence

Manual fallback: the change is a plan document + one tracker-row edit — no code/logic/security
surface for Codex to audit. (The plan's *content* was itself developed through four Codex
`codex exec` consults this session.)

### Checks performed

1. **Status discipline** — Feature #42 left **DEFERRED**, not flipped to PLANNED. Per rule 47,
   PLANNED requires a passed Gate-2 independent audit; this is a Gate-1 DRAFT, Gate-2 pending.
   Keeping DEFERRED also avoids the `check_gh_issue_mirror.sh` requirement (DEFERRED is not
   mirror-required) — confirmed the edit saved without a hook block.
2. **No premature implementation** — per the project's design/feature-workflow rule and the
   user's standing instruction, this records the plan only; it does NOT start `/feature-workflow`
   Gate-3. The plan's scope-guard + BLOCKERS sections state this explicitly.
3. **Blockers surfaced, not buried** — the plan and the row both name the three gates that must
   clear before #42 leaves DEFERRED: (a) libmobi LGPL-3.0 distribution decision (potential hard
   blocker), (b) Kindle conversion-fidelity corpus spike, (c) explicit go-ahead.
4. **History preserved** — the prior Option-A / Foliate-swap deferral rationale (incl. the
   2026-05-18 Gate-1+2 note + GH #113) is retained in the row, below the new re-scope note.
   Option A's diagram is kept in the plan under a collapsed "rejected — for the record" block.
5. **Naming convention** — plan filename follows rule-47 `YYYYMMDD-feature-N-<slug>.md`.
6. **Clean authoring** — the plan was authored fresh (clean Markdown), NOT copied from the
   linter-mangled `/tmp` scratch (which had escaped bold + `&#xA;` entities).
7. **Version bump** — 3.40.9 / build 690 (patch — docs/plan; rebased over main's v3.40.8). `xcodegen generate` succeeded;
   pbxproj reflects the bump. No Swift changed.

## Verdict

ship-as-is — plan + tracker re-scope only, status correctly held at DEFERRED with explicit
blockers, no code risk, no premature implementation.
