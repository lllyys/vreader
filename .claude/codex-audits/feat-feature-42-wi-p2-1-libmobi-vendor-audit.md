---
branch: feat/feature-42-wi-p2-1-libmobi-vendor
threadId: manual-fallback
rounds: 1
final_verdict: ship-as-is
date: 2026-06-01
---

# Manual audit — Feature #42 P2-WI-1a (vendor libmobi)

The merge-gate flags this branch as "touches code" because it adds vendored
**third-party C sources** (libmobi). There is **no first-party Swift** in the diff
(`git diff main --name-only | grep '\.swift$'` is empty), so a Codex audit of
*app code* has nothing to audit. Manual evidence below per the fix-issue fallback.

## Files read / verified

- `git diff main --name-only` → only `project.yml`, `vreader.xcodeproj/project.pbxproj`,
  and `vreader/Services/Libmobi/**` (17 `.c` + 19 `.h` + LICENSE/README/BUILD-RECIPE.md).
- The `.c`/`.h` are **verbatim upstream libmobi** (commit `906274205c…`,
  `https://github.com/bfabiszewski/libmobi`) — not modified. LGPL-3.0; LICENSE retained.

## My (non-vendored) changes audited

1. **`project.yml`** — added `- "Services/Libmobi/**"` to the vreader target's
   source `excludes`, and a comment. Verified: `grep -c "Services/Libmobi"
   vreader.xcodeproj/project.pbxproj` → **0** (the vendored C is NOT in the app's
   compile sources), so it cannot break the app build with wrong flags. The
   surrounding excludes (DebugFixtures, Foliate JS toolchain) follow the same
   pattern. Version bump folded into the commit.
2. **`BUILD-RECIPE.md`** — documents the verified iOS build (17/17 sources compile,
   `.a` archived, conversion symbols present) + the two gotchas. No code.

## Edge cases checked

- Release build: the exclude is unconditional, so libmobi never enters either
  Debug or Release source phases — no Release-leak of unbuilt C.
- App build with the change: `xcodebuild build` → **BUILD SUCCEEDED** (libmobi
  excluded → app unchanged).
- LGPL-3.0: source retained in-tree (source-availability satisfied); the
  distribution/relink decision is deferred to the WI-1b static-lib packaging step
  (noted in BUILD-RECIPE.md), per the user's accepted LGPL posture.

## Risks accepted

- The vendored upstream C is not line-audited (it's a mature third-party library;
  auditing upstream is out of scope). It is currently **not compiled** (excluded),
  so it has zero runtime effect until WI-1b integrates it behind its own target.

## Verdict

ship-as-is — no first-party code to audit; the vendoring is inert (excluded) and
the app build is green.
