---
branch: feat/feature-103-wi234-release-isolation
threadId: 019ed13b-e327-7152-90fe-d9d4572bad4a
rounds: 3
final_verdict: ship-as-is
date: 2026-06-17
---

# Codex Gate-4 audit — feature #103 WI-2/3/4 (Android Phase 0 release/isolation policy)

Runner: `scripts/run-codex.sh`. Sessions: R1 `019ed13b`, R2 `019ed141`,
R3 `019ed144`. Policy-doc changes only (rule 40 multi-platform section,
rule 48 cross-platform write isolation, AGENTS.md Platforms section, plus
ADR-0001 reconciliation + the #103 row flip).

## Round 1 — 2 High + 3 Medium + 1 Low

| Finding | Sev | Resolution |
|---|---|---|
| Pre-Phase-2 Android spike (`spikes/`) PRs had no bump target; the status line falsely said "every PR is iOS or shared" | High | Explicit rule: pre-Phase-2 spike/harness PRs bump iOS `project.yml` (no Android app to version yet); status line corrected. |
| Tag policy conflicted with ADR-0001 (ADR still said `ios/vX` vs `android/vY`) | High | ADR-0001 updated to record the decided iOS-plain / `android/`-prefixed namespace, no retag. |
| "Authoritative classifier" overstated — `code-paths.sh` is a boolean audit gate, doesn't classify `project.yml`/`*.xcodeproj` | Medium | Reworded in AGENTS + rule 48. |
| Android forbidden-path list didn't mirror the classifier (missing `gradle/`, `gradlew*`, `gradle.properties`, manifests, `res/`) | Medium | Full list copied into rule 48 + AGENTS. |
| Shared-surface list incomplete (missing `dev-docs/*` verification/evidence) | Medium | Expanded to `dev-docs/*` + root shared docs. |
| #103 row tag wording still said `ios/` vs `android/` | Low | Fixed to iOS plain `vX.Y.Z` vs `android/vX.Y.Z`. |

## Round 2 — 2 Medium (same theme)

| Finding | Sev | Resolution |
|---|---|---|
| Rule 40 + ADR implied `code-paths.sh` "routes" platform/version ownership when it's only the boolean audit predicate | Medium ×2 | Reworded: rule 40 OWNS the version-bump routing table (path sets kept aligned with the classifier); the classifier is only the code-vs-docs audit gate. |

## Round 3 — CLEAN

Verdict verbatim: "FINAL verdict: CLEAN." Confirmed rule 40 owns
platform/version routing, `code-paths.sh` is only the Gate-4 predicate,
and ADR-0001 + rule 48 + AGENTS.md align with that distinction.

## Verdict

ship-as-is. Completes #103 Phase 0 (all 4 WIs). The audit drove the policy
docs to be internally consistent and to mirror the WI-1 classifier exactly
— important because these are the rules every future Android PR follows.
