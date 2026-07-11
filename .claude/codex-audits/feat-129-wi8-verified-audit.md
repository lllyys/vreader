---
branch: feat/129-wi8-verified
threadId: manual-fallback
rounds: 1
final_verdict: ship-as-is
date: 2026-07-11
---

# Manual audit — feature #129 WI-8 finalizer (Gate-5 acceptance → VERIFIED)

**Why manual fallback:** the Codex runner (`scripts/run-codex.sh`, gpt-5.x) returned
`ERROR: You've hit your usage limit … try again at 11:48 AM` on this diff — the
independent auditor is genuinely unavailable (quota outage), which is the exact
condition rule 47's Manual Fallback covers. Re-run through Codex once quota
resets is unnecessary: this PR ships **no functional code** (the audit-gate hook
fired only because `android/version.properties` matches an `android/` path).

## Diff scope (vs `origin/main`, 3 files, +70/-3)

| File | Change |
| --- | --- |
| `android/version.properties` | `versionName` 0.13.15→0.13.16, `versionCode` 88→89 |
| `docs/features.md` | row #129 status cell `IN PROGRESS`→`VERIFIED` + WI-8 note appended |
| `dev-docs/verification/feature-129-20260711.md` | new Gate-5 evidence file (+67) |

## Files read

- `android/version.properties`
- `docs/features.md` (row #129 only)
- `dev-docs/verification/feature-129-20260711.md`
- `dev-docs/verification/SCHEMA.md` (evidence-format reference)

## Checks

1. **Version bump monotonic + well-formed.** `versionName=0.13.16` (patch bump
   over 0.13.15, the #129 WI-4 lane's `android/v0.13.12` line advanced through
   the WI-5/6/7 slots to 0.13.15); `versionCode=89` = 88+1, strictly increasing.
   Both fields parse (`key=value`, no stray whitespace). PASS.
2. **Row edit does not corrupt the table.** Exactly one row (#129) changed; the
   `| … | Medium | VERIFIED | …notes… |` pipe structure is intact; no adjacent
   rows touched; the anchor `Remaining: WI-8 acceptance (→ VERIFIED).` was
   replaced in place by the WI-8 VERIFIED note. `GH: #1879` preserved. PASS.
3. **Evidence file honest + schema-conformant.** Frontmatter carries
   `kind/id/status_target: VERIFIED/commit_sha/app_version/date/verifier/
   device_or_simulator/os_version/build_configuration/backend/result: pass`
   per SCHEMA.md; body has the acceptance-criteria table, commands-run, and
   observations. The AZW3 theme-CSS path is disclosed as **documented-injecting**
   (JVM-tested `setStyles` seam; WebView bg not screencap-readable — the
   sanctioned #68-class limitation) rather than claimed as a visual pass — no
   overclaim. Every other criterion is backed by a named connected/JVM test
   with pass counts. PASS.

## Edge cases checked

- AZW3 limitation not hidden (explicitly labelled, cross-referenced to #68). ✓
- Box E correctly NOT auto-checked — the note states the separate layout-toggle
  follow-up is still required before parity box E flips. ✓
- No `FIXED`/`VERIFIED` flip without a matching evidence file (the
  `check_terminal_status_evidence.sh` hook accepted the flip). ✓

## Risks accepted

None material. Docs + a version-integer bump only; no code logic, no schema, no
runtime behavior changes to audit.

## Tests added or intentionally deferred

N/A — finalizer PR, no production code. The acceptance tests it cites were run
by the verifier on `emulator-5554` and recorded in the evidence file.

**Verdict: ship-as-is.**
