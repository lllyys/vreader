---
branch: docs/feature-42-relabel-stale-gh113
threadId: manual-fallback
rounds: 1
final_verdict: ship-as-is
date: 2026-05-28
---

## Scope

One-line tracker clarity edit. Relabels the stale `GH: #113` stamp in the `docs/features.md`
Feature #42 row to read as historical (`Old GH #113 (Foliate scope, closed — superseded …)`).
No Swift, no app behavior. The `project.pbxproj` delta is the rule-40 version bump
(3.40.9/690 → 3.40.10/691) which trips this audit-gate hook.

## Manual audit evidence

Codex-validated direction (the relabel was Codex's own fourth-consult suggestion in the
file-feature process question). Manual-fallback here because the change is a single doc line.

### Checks
1. **Intent** — #113 was the mirror for the OLD Foliate-js EPUB-swap scope and is CLOSED;
   #42 was re-scoped 2026-05-28 to Readium+libmobi. The `GH: #113` stamp read like an *active*
   mirror, which (a) misrepresented history and (b) would make `/file-feature` idempotent-stop
   on #113 even after #42 later reaches PLANNED.
2. **Regex correctness** — `check_gh_issue_mirror.sh` keys on `GH:\s*#?\d+` (colon required).
   The relabel drops the colon (`GH: #113` → `Old GH #113`), so the row now has **zero**
   active-mirror matches (verified by grep). The prose refs `GH #113 closed` / `re-open #113`
   were already colon-free and are left as historical narrative.
3. **Hook compatibility** — #42 is `DEFERRED` → NOT mirror-required, so removing the active
   stamp is allowed (the hook only requires `GH: #N` on PLANNED/IN PROGRESS/DONE/VERIFIED
   rows). Edit saved without a hook block, confirming this.
4. **No premature mirror** — consistent with the held decision: #42 stays DEFERRED, no GH
   issue filed; a fresh issue will be filed when it reaches PLANNED (post Gate-2 + blockers +
   go-ahead).
5. **Version bump** — 3.40.10 / build 691 (patch — docs). `xcodegen generate` succeeded.

## Verdict

ship-as-is — single-line tracker clarity edit; no active mirror stamp remains; no code risk.
