---
branch: fix/issue-1054-debugbridge-xcuitest-sandbox-docs
threadId: 019e450f-1a6a-7dc0-8ca2-c47fa96497da
rounds: 1
final_verdict: ship-as-is
date: 2026-05-20
---

# Codex audit — fix/issue-1054-debugbridge-xcuitest-sandbox-docs

## Scope

Docs-only PR resolving GH #1054 / Bug #242. Three trackers/docs touched plus the
per-rule-40 version bump:

- `docs/bugs.md` — new row #242 (FIXED, `GH: #1054` in Notes); promoted from
  "Bug #240b" inside row #240's notes.
- `docs/subsystems/debug-bridge.md` — new "Driving the bridge from a
  verification flow" section: HOST-driven path (works, primary), in-runner
  path via `VerificationDebugBridgeHelper.openURL(...)` (NSPOSIX 61, does NOT
  work), and `XCTSkipUnless(bridgeReachable())` in-runner workaround (PR #1053).
- `docs/architecture.md` — DebugBridge service row gains a host-vs-runner
  callout pointing to the new doc section.
- `project.yml` + `vreader.xcodeproj/project.pbxproj` — version bump
  3.38.10 → 3.38.11 (build 585 → 586) per rule 40.

No Swift code change; the in-runner workaround `XCTSkipUnless(bridgeReachable())`
already shipped in PR #1053 (the #1049 fix).

## Audit rounds

### Round 1 — `019e450f-1a6a-7dc0-8ca2-c47fa96497da` — ship-as-is

Codex MCP, read-only sandbox, single round per rule 47 "Audit count by feature
size" (Small / 1 PR → 1 audit).

The audit checked:

1. **Clarity** — Does the new doc-bridge section unambiguously distinguish the
   working from the broken path? *Pass* — HOST-driven is explicitly marked
   "primary, works" and in-runner is explicitly marked "DOES NOT WORK"; the
   "Choosing between the two paths" paragraph at the end of the section is
   unambiguous.
2. **Completeness** — Does the section name (a) the exact NSPOSIX error code,
   (b) the structural cause (XCUITest sandbox vs CoreSimulatorService XPC),
   and (c) the in-runner workaround? *Pass* on all three.
3. **Consistency** — Does the new architecture.md row contradict anything
   else in the file? Does the new bug row #242 contradict row #240's
   narrative? *Pass* — row #242 explicitly says it was promoted from row
   #240's "Bug #240b" note, so the trackers are coherent.
4. **Cross-reference integrity** — Codex confirmed the cross-references
   (PR #1053, bug #240, GH #1049, GH #1054, bug #242) are locally coherent
   inside the docs/trackers. External `gh issue view 1054` / `gh pr view
   1053` was not reachable from Codex's sandbox; the orchestrating Claude
   session confirmed those manually before opening the PR.
5. **Hook compliance** — The new bug row has `GH: #1054` in Notes (satisfies
   `.claude/hooks/check_gh_issue_mirror.sh`). The row is marked `FIXED`;
   `.claude/hooks/check_terminal_status_evidence.sh` exits 0 for
   `docs/bugs.md` (only `docs/features.md` `VERIFIED` requires an evidence
   file). *Pass*.

No Critical/High/Medium/Low findings open.

## Verdict

`ship-as-is` — docs/architecture cleanup with no introduced contradiction.
The structural in-runner failure already has a code-level workaround in main
(PR #1053); this PR is the docs catch-up that prevents future agents from
re-discovering NSPOSIX 61 the hard way.
