---
branch: chore/feature-44-reverify-after-bug-121
threadId: 019df608-f3b3-7360-84ea-e94c7c445348
rounds: 2
final_verdict: ship-as-is
date: 2026-05-05
---

# Codex audit: feature #44 re-verification post bug-#121-fix

## Scope

| File | Change |
|---|---|
| `dev-docs/verification/feature-44-20260505b.md` (new) | Re-verification of feature #44 after bug #121 fix landed. result=partial. |
| `docs/bugs.md` | Added bug #123 ("DebugBridge `.onOpenURL` handler doesn't fire") row + detail entry. GH #243. |
| `docs/features.md` | Feature #44 row notes updated with verification history (first pass: fail/bug #121 → fixed; re-verify: partial/bug #123 blocking re-promote). Status stays IN PROGRESS. Backfilled `GH: #244`. |

## Round 1

3 findings.

| File:line | Severity | Issue | Resolution |
|---|---|---|---|
| `docs/features.md:97` | High | Feature #44 in `IN PROGRESS` (mirror-required) but lacked `GH: #N` in Notes. `check_gh_issue_mirror.sh` would block any downstream edit. | **Fixed**: filed `gh issue create` for feature #44 → got #244; stamped `GH: #244` into row. |
| `feature-44-20260505b.md:95` + `docs/bugs.md:87` | Medium | Suspected-root-cause citations referenced wrong enclosing conditional. I quoted `if initError == nil, let persistenceActor = persistenceActor`; the actual condition at `VReaderApp.swift:216` is `if let modelContainer, let contentView`. | **Fixed**: updated both citations to match actual code; labeled hypothesis as UNVERIFIED; added alternative causes to rule out (debugBridge nil, scheme guard mismatch, different Scene route). |
| `feature-44-20260505b.md:32` | Medium | Overstated claim: "the directory is created (handler reaches `snapshotsDirectory()`)". Commands shown didn't prove directory creation happened during URL dispatch — directory could have been created during earlier handler activity. | **Fixed**: removed that sentence. Evidence now ties the FAIL claim to the log-stream observation (zero log lines on `com.vreader.app` subsystem during URL invocation), which IS direct evidence the handler block didn't fire. |

## Round 2 (verify only)

Same Codex thread, after the 3 fixes.

> No findings. The three issues are resolved. feature #44 now satisfies the mirror rule with GH: #244, the root-cause citations in both feature-44-20260505b.md and bugs.md match the actual code at VReaderApp.swift:216, and the evidence file no longer overclaims handler reachability.
>
> Final verdict: clean for the scoped audit.

## Verdict

**ship-as-is.** Three findings, one round, all addressed. The
re-verification batch correctly captures: (1) bug #121 fix is
verified — URL scheme registration now PASSES; (2) bug #123 is filed
because the in-app handler doesn't fire its block — confirmed by
observable absence of log lines + DB state unchanged after URL
invocation; (3) feature #44 stays at IN PROGRESS until bug #123
lands. Filed GH #244 (feature #44 mirror backfill) and #243 (bug
#123).
