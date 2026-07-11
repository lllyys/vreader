---
branch: chore/128-wi4-version-bump
threadId: manual-fallback
rounds: 1
final_verdict: ship-as-is
date: 2026-07-11
---

# Manual audit — #128 WI-4 version bump (rule-40 correction)

**Why manual fallback:** the diff is a **pure 2-line version-integer bump** with
zero code logic — there is nothing for an independent code auditor to reason
about. The audit-gate hook fires only because `android/version.properties`
matches an `android/` path, not because code shipped.

**Context:** WI-4 (Room v7 FTS schema, PR #1916, merge `5a035924`) merged
**without** its rule-40 version bump — the bump commit was part of a compound
`gh pr merge` call that a PreToolUse hook blocked before execution, so the
push + PR ran with `version.properties` still uncommitted. This PR restores the
missing bump so WI-4 has a distinct, monotonic version; the mis-placed
`android/v0.13.21` tag (which had labelled the un-bumped `5a035924`) was deleted
and is re-cut on this PR's merge commit.

## Diff

`android/version.properties`: `versionName` 0.13.20→0.13.21, `versionCode`
93→94.

## Checks

- Monotonic: `versionCode` 93→94 (+1); `versionName` 0.13.20→0.13.21 (patch).
- No other file touched; no code, no schema, no runtime behavior.

**Verdict: ship-as-is.**
