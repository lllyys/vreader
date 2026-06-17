# 47 — Feature Implementation Workflow

Binding sequence for every feature implementation. Six gates, never skip one.

> **Plan → Independent plan audit → TDD implementation → Implementation audit loop → Device/integration verification → Merge**

This is a **gate model**, not a chronological task list. Each gate has an explicit acceptance bar; you do not enter the next gate until the current gate's bar is met. Multiple iterations within a gate are normal.

## Gate 1 — Plan

Write `dev-docs/plans/YYYYMMDD-feature-N-<slug>.md` covering, at minimum:

- **Problem** — what user need this addresses (mirror or refine the row's `Problem` field).
- **Surface area** — file-by-file with concrete signatures (which protocols, types, methods get added or modified). Includes a "files OUT of scope" subsection.
- **Prior art / project precedent / rejected alternatives** — what existing patterns we're building on, what we considered and rejected, and why. **Research is part of the plan**, not a separate step.
- **Work-item sequencing** — small, testable units (typically 1-15 WIs). Each WI is one PR's worth of work. Estimated PR size per WI.
- **Test catalogue** — concrete test files, what each covers, including the audit-driven additions (corruption, partial failure, idempotency edge cases).
- **Risks + mitigations** — known unknowns and how we'll handle them.
- **Backward compat** — what happens to existing data / older clients / older backups when this ships.

The features.md "Plan Template" fields (Problem, Scope, Edge Cases, Test plan, Acceptance criteria) live in the row; the implementation-detail plan in `dev-docs/plans/` expands on them with file paths, signatures, and sequencing.

**Acceptance bar**: plan exists at the documented path; status moves to `PLANNED` only when this gate passes.

## Gate 2 — Independent Plan Audit

Send the plan to an independent AI auditor (not the same agent/model/context as the plan author). cc-suite (driving Codex via `codex exec`) is the current default; Gemini, OpenCode, or any equivalent satisfies the gate. The invariant is **independence**, not the brand.

Audit prompt must explicitly request:

- **Model assumption verification** — do the SwiftData fields, enum cases, function signatures, file paths I named actually exist? (This catches the largest class of pre-implementation bugs.)
- **Risks + missing edge cases** — what failure modes the plan misses.
- **Protocol signature critique** — are new interfaces well-shaped, or do they leak implementation concerns?
- **Concurrency hazards** — actor isolation, Sendable, race conditions in mutable state.
- **Cohesion check** — is the WI split right, or are some WIs too big or too small?

**Acceptance bar**:

- Zero open Critical/High/Medium findings.
- Low findings either fixed in the plan or explicitly accepted with rationale (in the plan's "Known limitations" or "Audit fixes applied" section).
- **Maximum 3 audit rounds**. If unresolved findings remain after round 3, stop and escalate to the user — accept, defer, or redesign.

Track audit rounds in the plan's revision history. The author rewrites the plan to address findings; the auditor re-reviews. Same loop until clean.

**Why this gate exists**: Codex audits routinely catch 5-10 real bugs per round on non-trivial plans (compile-breaking model assumptions, missing preconditions, protocol shape mistakes). Skipping the audit shifts that cost into wasted implementation work.

## Gate 3 — TDD Implementation

Per work item:

1. **RED** — write a failing test that captures the WI's behavior. See `.claude/rules/10-tdd.md` for pattern catalogue.
2. **GREEN** — write minimal implementation to make the test pass.
3. **REFACTOR** — clean up without changing behavior. Tests stay green.
4. **PR** — small, focused PR per WI. Apply per-PR rules: docs sync (`24-doc-sync.md`), version bump (`40-version-bump.md`).

Status: feature → `IN PROGRESS` when WI-1's PR opens.

**Acceptance bar per WI**: tests pass under `xcodebuild test -only-testing:vreaderTests`; new code follows codebase conventions (`.claude/rules/50-codebase-conventions.md`).

## Gate 4 — Implementation Audit Loop

After implementation but before merge: independent audit of the changed files (read-only sandbox). This is what `/fix-issue` already runs.

Audit prompt focuses on:

- Correctness against the plan
- Edge cases in the diff (boundary conditions, nil, Unicode/CJK, concurrent access)
- Security (JS injection in evaluateJavaScript, WKWebView bridge safety, etc.)
- Duplicate / dead code introduced
- VReader compliance (Swift 6 concurrency, @MainActor correctness, file size <300 lines)
- Bridge safety (FoliateJSEscaper for JS interpolation, message parser edge cases)

**Acceptance bar**:

- Zero open Critical/High/Medium findings.
- Low findings fixed or explicitly accepted with rationale in the PR body.
- **Maximum 3 audit-fix rounds**. After round 3, escalate.

Same author/auditor separation as Gate 2.

## Gate 5 — Device / Integration Verification

For each PR before it merges:

- **Foundational WIs** (DTOs, protocols, utilities, pure types — no user-observable behavior): unit + integration tests + audit are sufficient. No device verification required.
- **Behavioral WIs** (anything that changes app behavior, persistence, networking, backup format, reader rendering, or UI flow): **slice verification** — exercise the slice end-to-end against the real environment available at this point. Run on iPhone 17 Pro Simulator with `vreader-debug://` harness; for backup/network features, against a real WebDAV server (or local Docker WebDAV equivalent); for reader features, with a fixture book.
- **Final WI** (the one that completes the feature): full end-to-end acceptance pass — every acceptance criterion exercised. This is what flips the feature row from `DONE` to `VERIFIED`.

Record slice verification in the PR description (what was run, what was observed). Record final acceptance verification in a structured evidence file at `dev-docs/verification/feature-<id>-<YYYYMMDD>.md` per the schema in `dev-docs/verification/SCHEMA.md`. The PreToolUse hook `.claude/hooks/check_terminal_status_evidence.sh` blocks any tracker edit that flips a row to `VERIFIED` (features) or `FIXED` (bugs) without a matching evidence file.

**Android tier (feature #107)** — the platform-router (`code_paths_platform`) picks the lane:
- **iOS WIs**: iPhone 17 Pro Simulator + `vreader-debug://` harness, as above.
- **Android WIs** (`android-app` / `android-spike`): verify on a booted **Android emulator** (AVD, android-35+) via `scripts/run-android-verify.sh` (the emulator analog of driving the simulator — rule 49/52/53). The CU-free instrumentation lane is the Spike-B `am instrument` pattern (#104/#105 precedent); the evidence file's `device_or_simulator` records the AVD (e.g. "Pixel 7 API 35 emulator"). Until #106's app shell exists, the only Android target is the `spikes/` harness, so Android-app Gate-5 is itself blocked on #106; pre-#106 Android work is spike/tooling (no device-verify, like a foundational WI).
- **Shared WIs** route to the iOS lane (rule 40 — shared is iOS while Android is pre-foundation).

**Acceptance bar per PR**: every behavioral slice in the PR has been verified end-to-end at the level appropriate to its WI tier. Final WI requires full acceptance pass + evidence file.

**"Tooling unavailable" is NOT an acceptable deferral reason** unless a specific tool is named and confirmed missing (e.g., `xcrun simctl` returns "command not found", a real device is required and none is connected, the rclone WebDAV server is down). "I'll do it next session" is not a tool-unavailability claim — it's a discipline lapse. The Stop hook (`.claude/hooks/check_unfinished_verification.sh`) surfaces unverified `DONE` rows at session end so the gap doesn't quietly carry over.

## Gate 6 — Merge

PR may merge when ALL of the following hold:

- Tests pass (the merge gate from `AGENTS.md`).
- Implementation audit loop is clean (Gate 4).
- Device / integration verification is complete for the PR's tier (Gate 5).
- Docs sync completed if triggered (`.claude/rules/24-doc-sync.md`).
- Version bump committed as the last commit before opening the PR (`.claude/rules/40-version-bump.md`).
- For PRs that reference an open bug/feature: the referenced row has reached its terminal status (`FIXED` for bugs, `DONE` for features) — the existing fix-or-implement merge gate.

After merge:

- Feature status moves to `DONE` only after **all** WIs are merged AND every acceptance criterion is implemented.
- `VERIFIED` is a separate post-implementation status, set after Gate 5's final-WI acceptance pass lands and is recorded in the row. Requires a `dev-docs/verification/feature-<id>-<YYYYMMDD>.md` evidence file (PreToolUse hook enforces).
- GH issue closes per close-gate rule (closure comment cites the verification: commit SHA + what was tested + what was observed).

## Gate progress is recorded in the GH issue (binding)

The GH issue mirror is not just a creation-time pointer — it is the **running record** of the feature's path through the six gates. Once the issue exists (created at the Gate 2 → `PLANNED` flip), every gate transition posts a short, append-only comment so the issue reads as a verifiable timeline of the workflow. A reviewer who only sees GitHub can then audit gate compliance without cloning the repo.

Post one comment at each of these transitions:

| Transition | Comment records |
| --- | --- |
| Gate 2 passes (issue just created) | plan path + audit verdict (Codex threadId + rounds, or `manual-fallback`) + the WI list with foundational/behavioral tiers |
| Each WI's PR merges (Gate 6) | WI number + tier, PR number, version bumped to, merge-commit SHA, Gate 4 audit verdict, Gate 5a slice result |
| Final WI merges → row `DONE` | "shipped in vX.Y.Z (commit `<sha>`), awaiting verification" — this is the existing close-gate comment |
| Gate 5b acceptance pass → row `VERIFIED` | evidence-file path + `result:` + a one-line acceptance-criteria summary — this is the existing closure comment, posted just before `gh issue close` |

Rules for these comments:

- **Append-only, short, factual.** Paths, SHAs, verdicts, version numbers — not prose. One comment per transition; do not edit prior comments.
- **The markdown artifacts stay the source of truth.** The `dev-docs/plans/` plan, the `.claude/codex-audits/` logs, `docs/features.md`, and the `dev-docs/verification/` evidence file are authoritative. The issue comments are a timeline that *points at* them; never copy a plan's full contents into the issue.
- **A skipped comment is a gate-process lapse, not a hard-blocked one.** No hook enforces these (they are post-action `gh issue comment` calls), so the discipline is the gate. If a transition happened without its comment, back-fill it before the next transition.

The two bottom rows already exist in the close-gate / finalizer flow; this rule adds the Gate-2 and per-WI-merge rows so the *middle* of the workflow is visible on GitHub, not just its endpoints.

## Audit count by feature size

To keep the audit cost honest:

| Size   | WIs     | Plan audits             | PR audits                                                                               |
| ------ | ------- | ----------------------- | --------------------------------------------------------------------------------------- |
| Small  | 1 PR    | 1                       | 1                                                                                       |
| Medium | 2-4 WIs | 1                       | 1 per WI                                                                                |
| Large  | 5+ WIs  | 1+ rounds (until clean) | 1 per WI; mechanical low-risk WIs that share the same surface MAY batch under one audit |

If a feature is genuinely 10+ WIs, consider whether the plan should split into multiple features.

## Author / auditor separation (invariant)

The agent that writes the plan must NOT be the same agent that audits it. Today this happens by accident (cc-suite runs Codex as a separate `codex exec` process from the implementing Claude Code session). The rule preserves this invariant explicitly so a future single-agent setup doesn't degenerate into self-marking.

If a future setup runs everything through one agent, the audit step requires invoking a different model/context boundary explicitly (e.g., a fresh subagent with read-only sandbox + explicit "audit, don't implement" framing).

## Manual fallback when AI auditor unavailable

When Codex / Gemini / equivalent is unavailable (network, quota, outage), do the audit manually AND record evidence in the plan or PR. Required `Manual Audit Evidence` section:

- **Files read** (paths)
- **Symbols / signatures verified** (which fields/types/enums you confirmed exist)
- **Edge cases checked** (the list)
- **Risks accepted** (with rationale)
- **Tests added or intentionally deferred**

Manual fallback is allowed only when the independent audit tool is genuinely unavailable, not just inconvenient. The audit step is non-negotiable; manual fallback is an evidence-bearing alternative, not a way to skip.

## What this rule does NOT change

- TDD discipline (`10-tdd.md`) is unchanged.
- Per-PR Codex audit in `/fix-issue` skill is exactly Gate 4 — reference, don't duplicate.
- Merge gate (fix-or-implement) and close gate (verified, not just merged) are unchanged — this rule names where they fit in the workflow.
- Bug fix workflow (`docs/bugs.md` `## Rules`) is unchanged — bugs follow Understand → RED → GREEN → REFACTOR → Verify → Track. Bugs do NOT require a separate plan + plan audit (they're reactive); they do require the implementation audit loop and verification gates.

## Worked example

Feature #46 (WebDAV materializing restore, 11 WIs, High priority):

- **Gate 1 (Plan)**: `dev-docs/plans/20260503-feature-46-materializing-restore.md` — drafted v1.
- **Gate 2 (Plan audit)**: 2 Codex rounds. Round 1 found compile-breaking model assumptions (`Book.originalFilename` doesn't exist), missing `ImportSource.restore`, MOBI handling gap, idempotency hole in `BookImporter`, MOVE 501 silent fallback. Round 2 found `Book.fileExtension` also doesn't exist, weak `BackupBlobStore` signature, weak error shape. Plan v2 incorporates all findings.
- **Gate 3 (TDD impl)**: 11 WIs sequenced (WI-0a model migration, WI-0b enum case, WI-1 BlobPath, etc.). Each ships its own PR.
- **Gate 4 (Impl audit)**: per-PR via `/fix-issue` audit loop.
- **Gate 5 (Verification)**: WI-0a, WI-0b, WI-1, WI-2 = foundational, no device verify. WI-7 (provider integration) = slice verify against Docker WebDAV. WI-10 (UI) = device verify on simulator. Final WI = full acceptance pass (backup → wipe → restore with positions/annotations).
- **Gate 6 (Merge + close)**: each WI's PR merges through its own gate. Final WI moves feature row to `DONE`. After Gate 5 final acceptance pass: row → `VERIFIED`, GH #144 closes with citation.

