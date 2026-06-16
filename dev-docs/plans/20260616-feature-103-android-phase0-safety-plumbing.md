# Feature #103 — Android Phase 0: safety plumbing (gate routing + release namespacing + write isolation)

> Decomposed from the #102 Android-port umbrella per **ADR-0001**
> (`docs/decisions/0001-android-port-strategy.md`). This is the ADR's
> **Phase 0 — safety plumbing ONLY**, a HARD prerequisite: *no `android/`
> PR may land until this is done*. All work here is on the existing
> iOS-side automation layer (`.claude/`, `scripts/`, rules, `AGENTS.md`) —
> **no Android code, no Kotlin, no `android/` directory created**.

## Problem

vreader's automation layer is iOS-shaped and filename-specific, so the
moment an `android/` PR exists it is **silently mis-gated**:

- `.claude/hooks/check_codex_audit_artifact.sh` treats only `vreader/` +
  `vreaderTests/` as "code". An `android/**` PR therefore **bypasses
  Gate 4 (the Codex-audit merge gate) as if it were docs-only** — the
  single largest day-1 hazard.
- The version-bump rule (`40-version-bump.md`) and `scripts/run-tests.sh`
  are hard-wired to `project.yml` → `pbxproj`, `xcodebuild`, the
  simulator, and a single `vX.Y.Z` tag space that cannot represent two
  independently-shippable native apps.
- Rule 48's "one writer per area" assumes Swift; nothing stops a Kotlin
  agent from editing `vreader/` (the `project.pbxproj`-contamination
  class that has already bitten worktree agents — PR #1029).

Phase 0 makes the automation **platform-aware / path-scoped** so Android
PRs are gated correctly the day the first one is opened.

## Scope

**In scope** (iOS-side automation only):

1. **Path-scope the gate-routing hooks.**
2. **Per-platform version / tag policy.**
3. **Write-prefix isolation (rule 48 extension).**
4. **Minimal `AGENTS.md` Android addendum.**

**Explicitly OUT of scope** (deferred per the ADR until the spikes prove
viability — these are NOT Phase 0):

- Creating the `android/` directory or any Gradle/Compose/Kotlin code.
- A full tracker remodel (platform child-rows / split trackers).
- Full Android close-gate automation (device verification, evidence).
- `contracts/` content (Spike A owns the golden vectors); Phase 0 only
  reserves the *path* and its write-owner.
- CI config (none exists in-repo; unverified per the ADR).
- `docs/parity/` ledger content (steady-state concern).

## Surface area (file-by-file)

### WI-1 — Path-scope the gate-routing hooks

- `/.claude/hooks/check_codex_audit_artifact.sh` — the "is this PR code?"
  predicate currently matches `^vreader/` + `^vreaderTests/`. Add an
  `android/**` (and `*.kt`, `*.kts`, `*.gradle`, `*.gradle.kts`) code
  predicate so an Android code PR REQUIRES an audit artifact. The audit
  artifact path/contract stays the same (`.claude/codex-audits/<branch>-audit.md`).
- `/.claude/hooks/check_gh_issue_mirror.sh` — confirm it keys on
  `docs/{features,bugs}.md` row edits (platform-agnostic); no change
  expected, but add a regression note/test that an `android/` PR touching
  only `android/**` doesn't trip the mirror hook spuriously.
- `/.claude/hooks/check_terminal_status_evidence.sh` — same: it parses a
  single status cell; Phase 0 does NOT change the tracker schema, so this
  hook is unchanged but documented as "iOS-shaped, Android verification
  evidence is a later phase."
- Concrete signature: each hook gains a small `is_code_path()` /
  `platform_of_path()` shell helper (or a shared sourced
  `.claude/hooks/lib/paths.sh`) so the routing logic is defined once.

### WI-2 — Per-platform version / tag policy

- `/.claude/rules/40-version-bump.md` — add an "Android / multi-platform"
  section: per-platform version files (iOS stays `project.yml`
  `MARKETING_VERSION`/`CURRENT_PROJECT_VERSION`; Android gets
  `android/version.properties` or Gradle `versionName`/`versionCode` —
  *path reserved, file created in Phase 2, not now*), a "which platform
  did this PR touch → bump that platform's file" rule, and a tag policy:
  `ios/vX.Y.Z` vs `android/vX.Y.Z` (or an explicitly unified product
  version — the ADR leaves this open; the plan must PICK one and state
  it). The existing iOS history uses plain `v3.66.x`; the policy must
  define how the existing plain tags coexist with the new namespaced ones
  (proposal: keep plain `vX.Y.Z` as the iOS tag until Android ships, then
  cut over — OR alias). **This decision is the WI's core deliverable.**
- Close-gate comment: the GH "shipped in vX.Y.Z" comment template
  (referenced in AGENTS.md + `/fix-issue` skill) gets platform-namespaced
  wording for Android (`shipped in android/vX.Y.Z`). Phase 0 documents the
  rule; the iOS path is unchanged.

### WI-3 — Write-prefix isolation (rule 48 extension)

- `/.claude/rules/48-parallel-execution.md` — add a "Cross-platform write
  isolation" subsection: Kotlin/Android agents MUST NOT touch `vreader/`
  or `*.xcodeproj`; Swift/iOS agents MUST NOT touch `android/`; shared
  surfaces (`docs/*`, `contracts/`, `dev-docs/designs/*`, release config,
  `AGENTS.md`, `.claude/`) get a single owner per change (the existing
  one-writer-per-area rule, made explicit for the platform split). Tie to
  the existing pbxproj-contamination precedent (PR #1029).

### WI-4 — Minimal AGENTS.md addendum

- `/AGENTS.md` — a short Android section: path ownership (`android/**` =
  Android), the Android test command placeholder (Gradle —
  *documented as "lands in Phase 2", not wired now*), release semantics
  pointer to the updated rule 40, and a pointer to ADR-0001 as the source
  of truth.

## Prior art / project precedent / rejected alternatives

- **Precedent**: the hooks already path-discriminate (the audit hook's
  `vreader/` predicate; the mirror hook's `docs/` keying). Phase 0
  *generalizes* that existing discrimination rather than inventing a new
  mechanism.
- **Precedent**: rule 48's worktree cwd discipline + the PR #1029
  pbxproj-contamination incident are the exact motivation for WI-3.
- **Rejected — "grow, don't fork" the prompts** (teach every prompt both
  toolchains): the ADR's audits explicitly reject this; it bloats every
  prompt and couples the toolchains. Path-scoped routing keeps each
  entrypoint single-toolchain.
- **Rejected — single unified `vX.Y.Z` tag space**: the ADR calls this
  "the biggest miss"; two independently-shippable apps need distinct tag
  namespaces.
- **Rejected — full tracker remodel now**: premature; the spikes may
  invalidate assumptions. Phase 0 keeps single-status rows.

## Work-item sequencing

| WI | Deliverable | PR size | Tier |
|---|---|---|---|
| WI-1 | Path-scope `check_codex_audit_artifact.sh` (+ shared paths helper) so `android/**`/`*.kt` PRs require an audit; hook tests | Small | Behavioral (gate behavior) |
| WI-2 | Rule 40 per-platform version/tag policy + the tag-namespace decision; close-gate comment wording | Small–Med (docs) | Foundational (docs/policy) |
| WI-3 | Rule 48 cross-platform write-isolation subsection | Small (docs) | Foundational |
| WI-4 | AGENTS.md Android addendum | Small (docs) | Foundational |

WI-1 is the load-bearing one (it's the gate that actually blocks a
mis-gated PR) and ships first. WI-2/3/4 are policy docs and can batch
under one audit if small.

## Test catalogue

- **WI-1 hook test** (the only one with executable behavior): a shell
  test (mirroring the existing hook-test pattern under
  `.claude/hooks/` or a `bats`/shell harness) asserting:
  - an `android/app/src/Foo.kt`-only diff → hook DEMANDS an audit artifact
    (exit non-zero without one);
  - a `docs/`-only diff → hook does NOT demand one (unchanged);
  - a mixed `vreader/` + `android/` diff → demands one;
  - a `*.gradle.kts`-only diff → demands one.
- WI-2/3/4 are docs/policy (rule 10 exemption — no runtime behavior);
  verification is a careful read + the WI-1 hook test proving the gate
  actually fires. The "Manual Audit Evidence" path is acceptable for the
  docs WIs.

## Risks + mitigations

- **R1 — the hook change accidentally over-gates iOS docs PRs.** Mitigate
  with the explicit `docs/`-only negative test (must NOT demand an audit).
- **R2 — the tag-namespace decision is reversible-but-costly.** Mitigate
  by writing the decision + the coexistence rule for existing plain tags
  explicitly into rule 40, and keeping iOS on plain `vX.Y.Z` until Android
  actually ships (no retroactive retag).
- **R3 — write-isolation is advisory (no hook enforces it yet).** Accept
  for Phase 0 (rule-level, like the rest of rule 48); a path-scoped
  enforcement hook is a candidate follow-up once `android/` exists.

## Backward compatibility

- Existing iOS PRs and the running cron are UNAFFECTED: the audit hook's
  iOS predicate is unchanged (it only *adds* an Android predicate); rule
  40's iOS bump flow is unchanged; the plain `vX.Y.Z` tag space continues
  for iOS. No tracker schema change. No `android/` directory created.

## Acceptance criteria

1. An `android/**` or `*.kt`/`*.gradle*` code PR cannot merge without a
   `.claude/codex-audits/<branch>-audit.md` artifact (hook test proves
   it); a `docs/`-only PR still can.
2. Rule 40 documents per-platform version files + the `ios/` vs `android/`
   (or unified) tag policy with an explicit decision and the
   existing-plain-tag coexistence rule.
3. Rule 48 documents cross-platform write isolation (Kotlin↛`vreader/`,
   Swift↛`android/`, shared-file single owner).
4. AGENTS.md has the Android path-ownership + release-semantics addendum
   pointing at ADR-0001.
5. No Android code, no `android/` directory, no tracker schema change.

## Revision history

- v1 (2026-06-16) — initial Gate-1 draft from ADR-0001 Phase 0. Awaiting
  Gate-2 independent audit.
