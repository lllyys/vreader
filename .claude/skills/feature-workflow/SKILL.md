---
name: feature-workflow
description: "Run the binding 6-gate feature workflow end-to-end per rule 47 (Plan → Independent Plan Audit → TDD Implementation → Implementation Audit Loop → Device/Integration Verification → Merge). Use this skill whenever the user wants to implement a new feature in vreader, asks 'implement feature #N', 'work on feature 47', 'start the feature workflow', 'plan + build feature X', or describes building a new capability that doesn't yet exist. NOT for fixing broken implementations (that's fix-issue). The skill drives the row from `TODO` → `VERIFIED` through six gates that must never be skipped — author/auditor separation, evidence files, hook compliance are all binding."
---

# Feature Workflow (rule 47, six gates, never skip one)

Drives a feature from `TODO` → `VERIFIED` through the binding 6-gate
sequence in `.claude/rules/47-feature-workflow.md`:

> Plan → Independent Plan Audit → TDD Implementation → Implementation
> Audit Loop → Device/Integration Verification → Merge → (close gate)

Each gate has an explicit **required artifact**, **author/auditor
separation rule**, **tracker status transition**, **blocking hook**,
and **exit criteria**. You don't enter the next gate until the current
gate's exit criteria are met. Multiple iterations within a gate are
normal.

## Input

Parse the user's request to extract a feature identifier — either a numeric id from
`docs/features.md` (e.g. `48`) or a short slug (e.g. `materializing-restore`). If
the user did not name a feature, list `TODO`/`PLANNED` candidates from `docs/features.md`
and ask the user to pick.

`$ARGUMENTS` is the feature identifier — either a numeric id from
`docs/features.md` (e.g. `48`) or a short slug (e.g.
`materializing-restore`). If empty, list `TODO`/`PLANNED` candidates
from `docs/features.md` and ask the user to pick.

## Scope guard — read this first

This skill is for **features only** (capabilities never implemented).
If the work is fixing a broken implementation, stop here and use
`/fix-issue`. The bug-vs-feature distinction is binding per AGENTS.md;
running a fix through this skill skips the bug-tracker workflow.

## Hooks you'll trip

| Hook | Triggers when | What it requires |
|---|---|---|
| `check_gh_issue_mirror.sh` | `Edit/Write/MultiEdit` on `docs/features.md` | mirror-required rows (`PLANNED`/`IN PROGRESS`/`DONE`/`VERIFIED`) must have `GH: #N` in Notes column |
| `check_terminal_status_evidence.sh` | tracker flip to `VERIFIED` on `docs/features.md` | matching `dev-docs/verification/feature-<id>-<YYYYMMDD>.md` evidence file with valid frontmatter |
| `check_codex_audit_artifact.sh` | `gh pr merge` on a Swift-touching PR | `.claude/codex-audits/<branch>-audit.md` with `final_verdict` ∈ {ship-as-is, follow-up-recommended} |

Plan around them; do not bypass.

## Pre-flight Checks

1. **Resolve target**: parse `$ARGUMENTS` to a feature row in
   `docs/features.md`. Read the row + any sub-section plan.
2. **Working tree**: `git status --porcelain`. If dirty, isolate work
   on a branch; do not revert unrelated changes.
3. **Branch / sync**: `git fetch origin`. Confirm `main` is current.
4. **Tracker baseline + entry-gate selection**: note the current row
   status, then check whether `dev-docs/plans/*-feature-<id>-*.md`
   exists. The two artifacts can disagree (the row's `PLANNED` may
   have been set on the lighter row-template definition: Problem/
   Scope/Edge Cases filled in). The combination decides where to
   enter:

   | Row status | `dev-docs/plans/*-feature-<id>-*.md` present? | Enter at |
   |---|---|---|
   | `TODO` | no | **Gate 1** (write the plan) |
   | `TODO` | yes (drafted ahead, not yet audited) | **Gate 2** |
   | `PLANNED` | no | **Gate 1** (drawing up the plan IS the work — do not bail out) |
   | `PLANNED` | yes, no audit revision history | **Gate 2** |
   | `PLANNED` | yes, audited (revision history shows clean Gate 2) | **Gate 3** |
   | `IN PROGRESS` | yes (assumed) | **resume next pending WI / re-enter Gate 4 if a WI is mid-audit** |
   | `DONE` | yes | **Gate 5b** (post-merge final acceptance) |
   | `VERIFIED` | yes | already complete; nothing to do |

   **Do not stop because the plan doc is missing.** Drawing up the
   `dev-docs/plans/` doc is Gate 1's deliverable, not a precondition.
   A row already at `PLANNED` whose dev-docs plan doesn't exist
   means: row-level template was filled, full implementation plan
   wasn't lifted yet — lift it now (Gate 1), audit it (Gate 2),
   then proceed. Only TODO/IDEA-level rows whose row-template
   itself is empty (no Problem/Scope/Edge Cases at all) need
   triage before Gate 1 is meaningful — those redirect to /triage.
5. **Bug-vs-feature sanity check**: re-confirm this is a feature
   (capability never implemented), not a bug (broken implementation).
   If it's a bug → STOP, redirect to `/fix-issue`.

---

# Gate 1 — Plan

| Field | Value |
|---|---|
| Required artifact | `dev-docs/plans/YYYYMMDD-feature-<id>-<slug>.md` with all required sections (see below) |
| Owner / auditor | Author = orchestrator (or Planner subagent). No auditor — that's Gate 2. |
| Status transition | If row was `TODO`: stays `TODO` through Gate 1; flips to `PLANNED` only after Gate 2 passes. If row was already `PLANNED` (row-template definition filled but no plan doc): stays `PLANNED` — do NOT regress to `TODO`. The plan doc fills in what was missing |
| Blocking hook | `check_gh_issue_mirror.sh` fires on the `PLANNED` flip (must have `GH: #N` in row Notes; create the issue here) |
| Exit criteria | Plan file exists at the documented path with all required sections filled in |

**Required artifact**: `dev-docs/plans/YYYYMMDD-feature-<id>-<slug>.md`.

**Required content** (rule 47 + features.md plan template):

- **Problem** — user need this addresses (mirror or refine row's `Problem`).
- **Surface area** — file-by-file with concrete signatures: which
  protocols, types, methods get added or modified. Include a "files
  OUT of scope" subsection.
- **Prior art / project precedent / rejected alternatives** — what
  existing patterns we're building on, what was considered and
  rejected, and why. Research is part of the plan, not a separate
  step.
- **Work-item sequencing** — small, testable units (typically 1–15
  WIs). Each WI is one PR's worth of work. Estimate PR size per WI.
  **Mark each WI as foundational or behavioral** (see Gate 5).
- **Test catalogue** — concrete test files, what each covers,
  including audit-driven additions (corruption, partial failure,
  idempotency edge cases).
- **Risks + mitigations** — known unknowns and how we'll handle them.
- **Backward compat** — what happens to existing data / older clients
  / older backups when this ships.

**Author**: this skill's orchestrator (or a Planner subagent).

**Status transition**: row stays at `TODO` until Gate 2 passes; only
then move to `PLANNED`. Per the mirror rule, `PLANNED` triggers GH
issue creation if not already mirrored — `gh issue create` for
`Feature #N: <summary>` with the `enhancement` label, then stamp
`GH: #M` into the row's Notes column.

**Exit criteria**: plan file exists at the documented path with all
required sections filled in. Ready for independent audit.

---

# Gate 2 — Independent Plan Audit

| Field | Value |
|---|---|
| Required artifact | Audit verdict captured inline in the plan file's revision history (Codex thread + rounds + verdict), OR a `Manual Audit Evidence` section when AI auditor unavailable |
| Owner / auditor | Author = Gate 1 author. Auditor = **DIFFERENT agent context** (the configured Codex runner — cc-suite — by default, or a fresh subagent with read-only sandbox + "audit, don't implement" framing). Author/auditor separation is mandatory per rule 48 |
| Status transition | row → `PLANNED` only after this gate passes; that flip triggers GH issue creation if not already mirrored |
| Blocking hook | `check_gh_issue_mirror.sh` on the `PLANNED` flip |
| Exit criteria | Zero open Critical/High/Medium findings; Low findings fixed or accepted with rationale; **max 3 audit rounds** (escalate to user if not clean by round 3) |

**Required artifact**: Codex (or equivalent independent agent) audit
verdict captured inline in the plan file's revision history, OR a
`Manual Audit Evidence` section if the AI auditor is unavailable.

**Author/auditor separation**: the agent that wrote the plan must
**not** audit it. cc-suite running Codex as a separate `codex exec` process satisfies this
by default. If a future setup runs everything through one agent, this
gate requires invoking a different model/context boundary explicitly
(e.g., a fresh subagent with read-only sandbox + explicit
"audit, don't implement" framing). See `.claude/rules/48-parallel-execution.md`.

## 2a. Plan audit via the configured Codex runner

Run the project's configured **independent Codex audit runner** — current
runner **`cc-suite`**, via **`/cc-suite:review-plan`** (architectural plan
review: consistency, completeness, feasibility, ambiguity, risk; it drives
Codex through `codex exec`). Do NOT use `ToolSearch +codex` or
`mcp__plugin_codex-toolkit_codex__codex` — cc-suite intentionally avoids the
MCP bridge (it hangs on long responses) and the old `codex-toolkit` MCP
server is no longer loaded. If the `codex` CLI is missing/unauthenticated or
cc-suite errors, skip to **2c. Manual fallback**.

## 2b. Audit focus

Point `/cc-suite:review-plan` at `dev-docs/plans/<plan-file>.md` for feature
#<id>: <title> (read-only sandbox) and have it be direct — contradict the
plan where it's wrong — focusing on:

1. Model assumption verification — do the SwiftData fields, enum
   cases, function signatures, file paths the plan names actually
   exist in the current codebase? (This catches the largest class
   of pre-implementation bugs.)
2. Risks + missing edge cases — what failure modes the plan misses.
3. Protocol signature critique — are new interfaces well-shaped,
   or do they leak implementation concerns?
4. Concurrency hazards — actor isolation, Sendable, race conditions
   in mutable state, @MainActor correctness.
5. Cohesion check — is the WI split right, or are some WIs too big
   or too small?
6. Foundational-vs-behavioral classification — is each WI's tier
   correct? (Foundational = DTOs/protocols/utilities, no user-observable
   behavior. Behavioral = anything that changes app behavior, persistence,
   networking, backup format, reader rendering, or UI flow.)

Have it report findings as: file:line | severity (Critical/High/Medium/Low) | issue | fix

## 2c. Manual fallback (Codex unavailable)

Add a `Manual Audit Evidence` section to the plan with:
- **Files read** (paths)
- **Symbols / signatures verified** (which fields/types/enums you confirmed exist)
- **Edge cases checked** (the list)
- **Risks accepted** (with rationale)
- **Tests added or intentionally deferred**

Manual fallback is allowed only when the independent audit tool is
genuinely unavailable, not just inconvenient. The audit step is
non-negotiable; manual fallback is an evidence-bearing alternative.

## 2d. Loop or exit

Author rewrites the plan to address findings; auditor re-reviews.
Track audit rounds in the plan's revision history.

**Exit criteria**:
- Zero open Critical/High/Medium findings.
- Low findings either fixed or explicitly accepted with rationale in
  the plan's "Known limitations" or "Audit fixes applied" section.
- **Maximum 3 audit rounds.** If unresolved findings remain after
  round 3, STOP and escalate to the user — accept, defer, or redesign.

**Status transition**: row → `PLANNED` (mirror rule fires; create GH
issue if not present, stamp `GH: #N` in Notes).

## 2e. Open the gate-progress timeline on the GH issue

Per rule 47's "Gate progress is recorded in the GH issue", the issue is
the running record of the feature's path through the six gates. Right
after the issue exists, post the **first** timeline comment recording
that Gate 2 passed:

```bash
gh issue comment <feature-gh-issue> --body "$(cat <<'EOF'
**Gate 2 — plan audited.**
- Plan: `dev-docs/plans/<plan-file>.md`
- Audit: Codex threadId `<id>`, <N> round(s), verdict clean (or `manual-fallback`)
- Work items (tier):
  - WI-1 <slug> — foundational
  - WI-2 <slug> — behavioral
  - …
EOF
)"
```

Keep it short and factual — the plan file stays the source of truth;
this comment points at it. Do not paste the plan's contents into the
issue.

> **Hard dependency**: Gate 3 cannot start on an unaudited plan.
> Skipping Gate 2 and starting TDD anyway is the most likely failure
> mode here. Don't.

---

# Gate 3 — TDD Implementation (per Work Item)

| Field | Value |
|---|---|
| Required artifact | Per WI: failing test (RED), minimal impl (GREEN), refactored code (REFACTOR), per-WI PR with audit log + version bump |
| Owner / auditor | Author = implementer (the agent driving this skill or a TDD-implementer subagent). The Codex audit *of this WI's PR* is **Gate 4**, with auditor != implementer. |
| Status transition | When WI-1's PR opens, row → `IN PROGRESS` |
| Blocking hook | `check_codex_audit_artifact.sh` blocks `gh pr merge` without audit log; `check_gh_issue_mirror.sh` blocks tracker edits without `GH: #N` |
| Exit criteria | Per WI: tests green, Gate 4 audit clean, docs sync committed if triggered, version bump committed, PR opened with the right reference convention. **Gate 3 cannot start on an unaudited plan** — Gate 2 must have passed first |

**Status transition**: when WI-1's PR opens, row → `IN PROGRESS`.

For each Work Item, run the per-WI inner loop:

## 3a. Branch + WI scaffold

- Branch: `feat/feature-<id>-wi-<n>-<slug>` off `main`.
- (No tracker move yet — already at `IN PROGRESS` from WI-1's PR.)

## 3b. RED → GREEN → REFACTOR

Per `.claude/rules/10-tdd.md`:
1. **RED** — write a failing test that captures the WI's behavior.
   - SwiftData boundary → persistence test with in-memory container
   - WKWebView bridge → parser/coordinator unit test
   - ViewModel → Swift Testing async test with `@MainActor`
   - Pure utility → parameterized `@Test(arguments:)`
2. **GREEN** — minimal implementation to make the test pass.
3. **REFACTOR** — clean up without changing behavior. Tests stay green.

Codebase conventions: see `.claude/rules/50-codebase-conventions.md`.
File-size guideline: ~300 lines max.

## 3c. Test gate

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test \
  -project vreader.xcodeproj -scheme vreader \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:vreaderTests
```

Pass → continue. Fail → fix and retry. 3 failures → stop, report.

> **Note**: `xcodebuild` CLI builds to a different DerivedData than
> Xcode's Run button. **Never use `simctl uninstall`** — wipes user
> data. Use `simctl install` to replace the binary.

## 3d. Gate 4 — Implementation Audit (per-WI, inline)

| Field | Value |
|---|---|
| Required artifact | `.claude/codex-audits/<branch>-audit.md` with valid frontmatter (branch, threadId, rounds, final_verdict, date) |
| Owner / auditor | Author = WI implementer. Auditor = the configured Codex runner (cc-suite) or a fresh subagent. Author/auditor separation per rule 48 |
| Status transition | none — row stays `IN PROGRESS` |
| Blocking hook | `check_codex_audit_artifact.sh` blocks `gh pr merge` without this file |
| Exit criteria | Zero open Critical/High/Medium findings; **max 3 audit rounds** (escalate to user if not clean by round 3) |

This is the same audit shape as `/fix-issue` Phase 4. Runs against the
WI's PR before merge.

### Collect changed files

```bash
git diff main --name-only
git diff main
```

### Codex audit

Run the same configured Codex runner as Gate 2a — **`cc-suite`**:
**`/cc-suite:audit`** for a read-only audit (Codex audits, you fix —
preserves rule-48 author/auditor separation), or **`/cc-suite:audit-fix`**
for the audit→fix→verify loop. Do NOT use `ToolSearch +codex` /
`mcp__plugin_codex-toolkit_codex__codex` — the codex-toolkit MCP server is
gone. Point it at the changed files (`git diff main --name-only`) and focus on:

1. Correctness vs the plan — does this WI deliver what the plan promised?
2. Edge cases — boundary conditions, nil, Unicode/CJK, concurrent access
3. Security — JS/CSS injection in evaluateJavaScript() and WKWebView bridges
4. Duplicate code — repeated logic that should be unified
5. Dead code — unused imports, unreachable branches, orphaned functions
6. Shortcuts & patches — workarounds, TODO markers, band-aids
7. VReader compliance — Swift 6 concurrency, @MainActor correctness,
   SwiftData actor isolation, file size <300 lines
8. Bridge safety — FoliateJSEscaper used for all JS interpolation,
   message parser handles edge cases

Have it report as: file:line | severity (Critical/High/Medium/Low) | issue | fix

Fix every finding, then re-run `/cc-suite:audit` on the updated diff to
verify (or let `/cc-suite:audit-fix`'s built-in verify pass cover it).

If the Codex runner is unavailable: manual mini-audit (same dimensions 1–8,
written into the audit log artifact with `threadId: manual-fallback`).

### Audit log artifact (required before merge)

Path: `.claude/codex-audits/<branch-with-slashes-replaced-by-hyphens>-audit.md`

Frontmatter:

```markdown
---
branch: <current branch name, exactly as `git branch --show-current` returns>
threadId: <Codex exec session id>    # OR `manual-fallback`
rounds: <integer ≥ 1>
final_verdict: ship-as-is | follow-up-recommended | block-recommended
date: YYYY-MM-DD
---
```

Body:
- Per-round findings (file:line | severity | issue | fix).
- Resolution note for each finding (fixed / accepted / deferred).
- Summary verdict statement.
- Manual fallback section if applicable.

Commit the audit log alongside the WI changes (own commit or folded
into the relevant fix commit).

**Exit criteria**: zero open Critical/High/Medium findings. **Max 3
rounds** for this WI's audit; after round 3 escalate.

## 3e. Docs sync (if triggered, before version bump)

Per `.claude/rules/24-doc-sync.md`:

| If this WI touched | Update |
|---|---|
| New service / actor / `@Model` / `Notification.Name` / cross-feature pattern | `docs/architecture.md` |
| User-visible behavior, tech stack, requirements, setup, ≥5-row tracker change | `README.md` |
| Otherwise | nothing |

If updates needed: own commit (`docs: update architecture.md for
feature #<id> WI-<n>`) **before** the version bump.

## 3f. Version bump (mandatory)

Per `.claude/rules/40-version-bump.md` — every WI's PR ends with one.

```bash
# Edit project.yml: bump MARKETING_VERSION + increment CURRENT_PROJECT_VERSION
xcodegen generate
grep -E "MARKETING_VERSION|CURRENT_PROJECT_VERSION" project.yml
grep -E "MARKETING_VERSION =|CURRENT_PROJECT_VERSION =" vreader.xcodeproj/project.pbxproj

# Smoke build
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild build \
    -project vreader.xcodeproj -scheme vreader \
    -destination 'platform=iOS Simulator,name=iPhone 17 Pro'

git add project.yml vreader.xcodeproj/project.pbxproj
git commit -m "chore: bump version to X.Y.Z"
```

**Bump tier (deterministic per WI):**

| WI tier | Bump |
|---|---|
| Foundational (no user-observable change) | `patch` |
| Behavioral but not the final WI | `patch` |
| Final WI of the feature (completes user-visible behavior) | `minor` (or `major` if the feature is a breaking change) |

Every PR merge produces a tag — see Gate 6's tag step. The tag count
across a multi-WI feature ≈ the WI count, because every PR carries a
mandatory version bump per rule 40.

## 3g. PR

**Reference convention** (binding, derived from AGENTS.md merge gate):

- **Intermediate WI PRs** (every WI except the final one): use plain
  prose like `Part of feature #<feature-gh-issue>` in the body. **Do
  NOT** use `Refs #N` or `Fixes #N` magic words. Reason: the merge
  gate ("a PR that references an open feature does not merge until
  the feature reaches `DONE`") would otherwise block every
  intermediate WI's merge and force one giant PR. Plain prose
  cross-links the PR to the feature without tripping the gate.
- **Final WI PR** (the one whose merge brings the feature to `DONE`):
  use `Refs #<feature-gh-issue>`. **Never** `Fixes #N` — the GH issue
  stays open until Gate 5b post-merge acceptance lands; auto-close
  is wrong here.

```bash
gh pr create --title "feat(#<feature-id> WI-<n>): <concise description>" --body "$(cat <<'EOF'
## Summary

{1-3 bullets describing what changed and why}

{For intermediate WIs}: Part of feature #<feature-gh-issue>
{For final WI only}: Refs #<feature-gh-issue>

## What Changed

{list of key changes}

## WI Status

- WI-<n>: {tier — foundational | behavioral} — this PR
- Remaining WIs: {summary}

## Codex Audit (Gate 4)

{audit summary — iterations run, findings fixed, verdict}

Audit log: `.claude/codex-audits/{branch-slug}-audit.md`

## Validation

- [x] `xcodebuild test` passes (Gate 3 test gate)
- [x] Tests cover changed behavior (TDD: RED → GREEN)
- [x] Codex audit loop completed ({M} iterations, verdict: {verdict})
- [x] Docs sync — {architecture.md updated | README.md updated | n/a}
- [x] Version bumped: {old} → {new}

## Gate 5a Verification (per-PR slice — pre-merge)

- Tier: {foundational — unit + integration sufficient | behavioral — slice verified end-to-end | final WI — pre-merge slice with `5b post-merge evidence file pending`}
- {What was run, what was observed}

## Type of Change

- [x] Feature WI ({Part of feature #<feature-gh-issue> for intermediate WIs | Refs #<feature-gh-issue> for the final WI})
EOF
)"
```

---

# Gate 5 — Device / Integration Verification

| Field | Value |
|---|---|
| Required artifact | 5a: PR description "Gate 5a Verification" section per WI. 5b (final-WI only): `dev-docs/verification/feature-<id>-<YYYYMMDD>.md` per SCHEMA.md |
| Owner / auditor | Author = verifier (orchestrator or designated subagent). 5b is "evidence-bearing"; SCHEMA result-field semantics gate any `VERIFIED` flip |
| Status transition | 5a alone does NOT change status. After 5b lands with `result: pass`, row → `VERIFIED` |
| Blocking hook | `check_terminal_status_evidence.sh` blocks the `VERIFIED` flip without 5b file present at the documented path |
| Exit criteria | 5a: PR's slice verification recorded honestly; 5b: every acceptance criterion exercised end-to-end with `result: pass` (or `partial` / `fail` per SCHEMA semantics) |

Gate 5 has two phases — **5a (pre-merge slice)** and **5b (post-merge
final acceptance)** — because the SCHEMA.md evidence file requires the
**merge-commit SHA on `main`**, which doesn't exist before the final
WI's merge.

## 5a. Pre-merge slice verification (per WI)

| WI tier | Verification depth (pre-merge) | Where recorded |
|---|---|---|
| **Foundational** (DTOs, protocols, utilities, pure types — no user-observable behavior) | Unit + integration tests + Gate 4 audit are sufficient | PR description "Gate 5a Verification" line |
| **Behavioral** (anything that changes app behavior, persistence, networking, backup format, reader rendering, or UI flow) | **Slice verification** — exercise the slice end-to-end against the real environment available at this point. iPhone 17 Pro Simulator with `vreader-debug://` harness; for backup/network features, against real WebDAV (or local Docker WebDAV); for reader features, with a fixture book. | PR description "Gate 5a Verification" section: what was run, what was observed |
| **Final WI** (the one that completes the feature) | **Pre-merge slice** of the final acceptance criteria — exercise what's exercisable on the working-tree binary against the real backend. Defer anything that requires a merged-on-main build. | PR description "Gate 5a Verification" + a note "5b post-merge evidence file pending" |

5a is the pre-merge gate that lets Gate 6 merge land. It is NOT the
final acceptance pass.

## 5b. Post-merge final acceptance (final WI only)

After the final WI's PR merges, write the **structured evidence file**
that flips the row to `VERIFIED`.

Path: `dev-docs/verification/feature-<id>-<YYYYMMDD>.md` per
`dev-docs/verification/SCHEMA.md`.

**Required frontmatter**:

```yaml
---
kind: feature
id: <N>
status_target: VERIFIED
commit_sha: <40-hex of merge commit on main>
app_version: <MARKETING_VERSION (build CURRENT_PROJECT_VERSION)>
date: YYYY-MM-DD
verifier: <name or "claude">
device_or_simulator: <e.g. "iPhone 17 Pro Simulator">
os_version: <e.g. "iOS 26.4">
build_configuration: Debug | Release
backend: <e.g. "rclone WebDAV ~/vreader-webdav-data" or "n/a">
result: pass | partial | fail
---
```

**Required body sections** (rule 47 + SCHEMA):

- `## Acceptance criteria` — table mapping each criterion from the
  plan to observed behavior + pass/fail.
- `## Commands run` — fenced code blocks of the actual shell /
  `simctl` / `xcrun` / curl commands used. Reproducible recipe.
- `## Observations` — what surprised you, what was almost a
  regression, what's brittle for next time.
- `## Artifacts` — paths to screenshots, log captures, `.xcresult`
  bundles. Optional but strongly recommended.

**Result-field semantics** (binding):

- `pass` — every acceptance criterion verified end-to-end. Tracker
  may move to `VERIFIED`; GH issue may be closed.
- `partial` — some criteria deferred. Tracker stays at `DONE`; a
  follow-up evidence file is required.
- `fail` — at least one criterion regressed. Tracker moves back to
  `IN PROGRESS`; do NOT flip to `VERIFIED`.

> **"Tooling unavailable" is NOT an acceptable deferral reason** unless
> a specific tool is named and confirmed missing (e.g. `xcrun simctl`
> returns "command not found", required device unavailable, Docker
> WebDAV down). "I'll do it next session" is not a tool-unavailability
> claim — it's a discipline lapse.

---

# Gate 6 — Merge

| Field | Value |
|---|---|
| Required artifact | per WI: green PR ready to merge with audit log + version bump + Gate 5a slice noted in description |
| Owner / auditor | Author = WI implementer. Merge gate enforced by AGENTS.md (fix-or-implement) + active hooks |
| Status transition | per merge: not-final WI → row stays `IN PROGRESS`; final WI → row → `DONE`. (`VERIFIED` is a separate post-merge step, see Gate 5b.) |
| Blocking hook | `check_codex_audit_artifact.sh` blocks `gh pr merge` without audit log |
| Exit criteria | Squash merge succeeds; tag `v<X.Y.Z>` cut from the merge commit on `main`; status transitioned per the rules above |

**A WI's PR may merge** when ALL hold:

- Tests pass (Gate 3c).
- Implementation audit loop is clean (Gate 3d / 4).
- Audit log artifact exists at `.claude/codex-audits/<branch>-audit.md`
  with valid frontmatter (`check_codex_audit_artifact.sh` will block
  `gh pr merge` otherwise).
- **Gate 5a slice verification** complete for the WI's tier and recorded
  in the PR description. **5b post-merge evidence file is NOT required
  pre-merge** — it's chicken-and-egg with the merge commit SHA.
- Docs sync committed if triggered (Gate 3e).
- Version bump committed as the last commit before opening the PR
  (Gate 3f).
- PR reference convention satisfied (Gate 3g): intermediate WIs use
  `Part of feature #N` prose; only the final WI uses `Refs #N`.

```bash
gh pr merge <PR#> --squash --delete-branch
```

After EACH WI's merge (every PR carries its own version bump per
rule 40, so every merge gets its own tag):

```bash
git checkout main && git pull origin main
git tag v<X.Y.Z>          # the version this WI's PR bumped to
git push origin v<X.Y.Z>
```

Then post the per-WI timeline comment on the GH issue (rule 47, "Gate
progress is recorded in the GH issue"):

```bash
gh issue comment <feature-gh-issue> --body "$(cat <<'EOF'
**WI-<n> merged** (<foundational | behavioral>).
- PR #<pr>, merged as `<short-sha>`
- Version: v<X.Y.Z>
- Gate 4 audit: <ship-as-is | follow-up-recommended>
- Gate 5a slice: <what was run / observed, or "unit + integration (foundational)">
EOF
)"
```

This makes the *middle* of the workflow visible on GitHub. The final
WI's merge instead uses the existing "shipped, awaiting verification"
comment in the Post-Merge Finalizer below — do not double-post.

**Status transitions** (per merge):

- WI lands but more remain → row stays `IN PROGRESS`.
- **Final WI** lands → row → `DONE` (implemented; not yet verified).
  This flip is what enables the Gate 5b post-merge evidence file to
  reference the merge-commit SHA.
- After Gate 5b evidence file lands with `result: pass` → row →
  `VERIFIED` via a tracker edit. **`check_terminal_status_evidence.sh`
  blocks this `VERIFIED` flip** if the evidence file isn't at
  `dev-docs/verification/feature-<id>-<YYYYMMDD>.md`.

---

# Post-Merge Finalizer (close gate)

**Do NOT auto-`gh issue close` on the GH issue when the final WI
merges.** Per AGENTS.md "Close gate":

> The "shipped, awaiting verification" comment (below) and the closure
> comment after Gate 5b are the **last two rows** of the gate-progress
> timeline from rule 47. Together with the Gate-2 comment (2e) and the
> per-WI-merge comments (Gate 6), they make the issue a complete record
> of the feature's path through all six gates.

## Right after final WI's `gh pr merge`

1. Apply label to GH issue (if device-verifiable, default
   `awaiting-device-verification`; otherwise pick from
   `verification-exception` / `verification-blocked` per AGENTS.md).
2. Post a "shipped, awaiting verification" comment:

   ```
   gh issue comment <feature-gh-issue> --body "Shipped in v<X.Y.Z> (commit <short-sha>). Awaiting Gate 5 final acceptance pass."
   ```

3. Tag is cut from the merge commit (per Gate 6's `git tag` step).

## After Gate 5 final acceptance

- For **device-verification** path:
  - Install merged build on iPhone 17 Pro Sim (or device).
  - Run every acceptance criterion from the plan.
  - Record observations in `dev-docs/verification/feature-<id>-<YYYYMMDD>.md`.
  - Post closure comment citing the evidence file:

    ```
    gh issue comment <feature-gh-issue> --body "VERIFIED on iPhone 17 Pro Simulator (commit <sha>). All acceptance criteria pass. Evidence: dev-docs/verification/feature-<id>-<YYYYMMDD>.md."
    gh issue close <feature-gh-issue>
    ```

- For **non-device-reproducible** features (race conditions, fault
  injection, etc.): close under `verification-exception` with a
  high-fidelity integration test at real subsystem boundaries (not
  stubs). Same evidence file, citation comment, then `gh issue close`.

- For **verification-blocked** (no harness exists yet): keep open,
  apply the label, file a follow-up to build the harness (potentially
  as another feature).

If verification reveals a regression: do NOT close. Move row back to
`IN PROGRESS`, file a bug, fix, re-verify.

---

## Acceptance Contract

The feature is "done" — i.e. row may flip to `VERIFIED` and GH issue
may close — only when:

1. All Work Items merged via Gate 6.
2. Final WI's `dev-docs/verification/feature-<id>-<YYYYMMDD>.md` has
   `result: pass` covering every acceptance criterion from the plan.
3. Closure comment posted with commit SHA, what was tested, what was
   observed.
4. `gh issue close <feature-gh-issue>` executed.

If uncertain at any gate: stop and ask. Don't guess your way past a
gate — that's how rule 47 was tightened in the first place.

## Error Handling

| Scenario | Action |
|---|---|
| `$ARGUMENTS` is empty | List `TODO`/`PLANNED` candidates; ask user to pick |
| Target is actually a bug | Redirect to `/fix-issue`; STOP |
| Plan exists at `dev-docs/plans/...` from a prior run | Resume at the correct gate (re-run Gate 2 if plan changed; else continue) |
| Codex runner unavailable | Use manual fallback; mark audit log `threadId: manual-fallback` |
| 3 audit rounds with findings still open (Gate 2 OR Gate 4) | STOP. Escalate to user — accept, defer, or redesign |
| Test gate fails 3x | Report errors, keep branch, STOP |
| `check_gh_issue_mirror.sh` blocks tracker edit | Add `GH: #N` to the row's Notes column, retry |
| `check_codex_audit_artifact.sh` blocks `gh pr merge` | Verify the audit log file exists at the expected path with valid frontmatter |
| `check_terminal_status_evidence.sh` blocks `VERIFIED` flip | Write the evidence file at `dev-docs/verification/feature-<id>-<YYYYMMDD>.md` first |
| Gate 5 verification reveals a regression | Move row back to `IN PROGRESS`, file a bug, fix, re-verify. Do NOT close GH issue |
| Branch already exists | Reuse if WI matches; else rename |
