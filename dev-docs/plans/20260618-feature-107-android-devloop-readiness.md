# Feature #107 — Android Phase 1.5: dev-loop workflow readiness

Status: Gate-1 draft (2026-06-18). Make the `.claude/` workflow machinery able to
*drive* Android dev — not just classify `android/` PRs (Phase 0 / #103 did the
classification). Prerequisite to #106 (the real Android app shell).

## Problem

Today every gate that TESTS / VERIFIES / BUMPS / CARRIES a task is iOS-hardcoded
(xcodebuild / simctl / iPhone 17 Pro / DebugBridge), and two gates silently
false-green Kotlin:
- **tdd-guardian** runs a frozen swift-xcode command → a Kotlin change "passes"
  tests that never ran.
- **`check_audit_debt.sh`** (the Stop-time audit-debt gate) still uses the pre-#103
  `vreader/|vreaderTests/` regex → an `android/` change is classified as docs-only
  and never accrues audit debt (#103 fixed the PreToolUse twin
  `check_codex_audit_artifact.sh` but NOT this Stop-time one).

Until the workflow can test/verify/bump/route Android, #106 cannot run through the
6-gate workflow — an `android/` PR would bypass real gates. This feature builds
the tooling; the actual `android/` app is #106 (carve-out).

## Surface area (file-by-file) — 5 PRs, each WI assigned to exactly one PR

Gate-2 (round 1) corrected the original grouping (Critical + 2 High + 2 Medium).
Each WI now belongs to exactly ONE PR; dependency chain is strictly
**PR-A → PR-B → PR-C → PR-D → PR-E**.

### PR-A — audit-debt gate parity + a path→platform classifier (WI-1) [foundational]
- **`.claude/hooks/lib/code-paths.sh`** — ADD a **path→platform classifier**
  `code_paths_platform()` (Gate-2-C: the existing `code_paths_touched()` is a
  BOOLEAN gate per AGENTS.md — "not a full ownership taxonomy" — and excludes
  `.claude/*`; routing needs a real classifier). `code_paths_touched()` stays
  unchanged for Gate-4 audit gating.
  - **Full ownership coverage (Gate-2-r2-M)** — the classifier matches the
    COMPLETE AGENTS/rule-40 ownership set, not just `android/`+`*.kt`:
    `android-app` ⊇ `android/`, `*.kt[s]`, `buildSrc/`, `gradle/`, root Gradle
    files (`build.gradle*`, `settings.gradle*`), `gradlew*`, `gradle.properties`,
    `AndroidManifest.xml`, any `res/` tree; `android-spike` = `spikes/`;
    `ios` = `vreader/`, `vreaderTests/`, `*.xcodeproj`, `project.yml`;
    `shared` = `docs/`, `contracts/`, `.claude/`, `scripts/`, root shared docs.
  - **Multi-valued + deterministic precedence (Gate-2-r2-H1)** — a PR can touch
    several classes; the classifier returns the SET, and the TEST/VERIFY lane
    routes by precedence `android-app > android-spike > ios > shared`. **Routing is
    PURELY PATH-BASED — no tracker metadata field (Gate-2-r3-H resolution)**: the
    earlier `Platform:` override is dropped because it needed a tracker contract
    the repo doesn't define, and write-isolation (rule 48) makes it unnecessary —
    an Android-app PR necessarily touches `android/`/`*.kt`/Gradle files, so its
    path set already classifies `android-app`; a truly `shared`-only PR correctly
    routes to iOS (rule 40: "shared → iOS while Android is pre-foundation").
    `scripts/` is `shared` (so this feature's own runner PRs bump iOS + run the iOS
    gate — correct per rule 40). The rule-40 "shared as part of an Android-app PR"
    case is therefore covered by the path set, not a separate field.
- **`.claude/hooks/check_audit_debt.sh`** — replace its inline
  `^(vreader/|vreaderTests/)` regex (confirmed at `check_audit_debt.sh:51`) with a
  `source` of `code-paths.sh` (mirrors the #103 precedent at
  `check_codex_audit_artifact.sh:121`), so `android/` / `*.kt[s]` / `contracts/`
  accrue audit debt at Stop time too.
- **Hook regression test** (repo hook-test convention) — `android/`-only → code
  (accrues debt); docs-only → not; + classifier unit cases.

### PR-B — Android test/verify runners (spike-scoped now) + ghost sweep (WI-2, WI-3) [tooling]
- **`scripts/run-android-tests.sh`** — watchdog-wrapped runner (rule-49/52/53:
  exact-pid wait, hard wall-clock timeout, single `RUN-ANDROID-TESTS RESULT:`
  line, kills the Gradle/daemon tree on timeout). **Gate-2-H1: there is NO
  `android/` tree or root `gradlew` yet** (AGENTS: "not wired yet"); the only real
  Android harness is **`spikes/android-reader-bench/run-bench.sh`**. So the runner
  is **parameterized** (`ANDROID_GRADLE_ROOT` / target script) and **drives the
  spike harness now** for a REAL integration smoke; the root-`./gradlew` lane is a
  documented TODO that lights up with #106's app shell (NOT a dry-run-only stub).
- **`scripts/run-android-verify.sh`** — emulator lane (`am instrument` /
  `connectedAndroidTest`), watchdog-wrapped; also spike-harness-scoped now (the
  spikes already run on the emulator per #104/#105).
- **`scripts/sweep-ghosts.sh`** + **`.claude/cron-prompts/watchdog.md`** (Gate-2-M2:
  watchdog.md still sweeps iOS-era ghosts) — detect+reap Gradle-daemon /
  `am instrument` / emulator (`qemu`/`emulator`) ghost classes; never flag a
  healthy resident Gradle daemon (same carve-out as `SWBBuildService`).
- **`.claude/rules/52-test-sim-isolation.md`** — add "Cause D" (Gradle-daemon /
  emulator ghost classes + the Android runner reference).

### PR-C — Kotlin TDD + conventions + Gate-5 Android tier + verify SKILL (WI-4, WI-5) [docs]
- **`.claude/rules/10-tdd.md`** — Kotlin TDD section (JUnit5/Robolectric/Compose-test;
  the Android test command via `run-android-tests.sh`).
- **`.claude/rules/50-codebase-conventions.md`** — Kotlin/Compose conventions.
- **`.claude/rules/47-feature-workflow.md`** — Gate-5 Android tier (emulator verify
  via `run-android-verify.sh`; Android evidence-file schema).
- **verify SKILL** (`.claude/skills/verify/SKILL.md` + `.claude/cron-prompts/verify.md`)
  — currently ENTIRELY XCUITest/DebugBridge/iOS-framed (Gate-2-r2-H2); add an
  "Android Mode" that routes verification to the emulator lane (`am instrument` /
  the spike harness) with Android-framed evidence, while the iOS path is unchanged.

### PR-D — platform-route skills + commands + crons + tdd-guardian (WI-6, WI-7, WI-8) [tooling]
Depends on PR-A (the classifier), PR-B (the runners), AND PR-C (the Android verify
behavior). Gate-2-M2: the crons invoke SLASH COMMANDS, so **`.claude/commands/*`**
must be in scope, not just `.claude/skills/*`.
- **`.claude/skills/{fix-issue,feature-workflow}/SKILL.md`** +
  **`.claude/commands/{fix-issue,feature-workflow}.md`** + plan-verify — **rewrite
  EVERY downstream Android-carrying phase, not just the test lane (Gate-2-r2-H2)**.
  The iOS-hardcoded surfaces to make platform-aware: the **test gate** (`xcodebuild`
  → `run-android-tests.sh`), **pre-FIXED verify** (`fix-issue` Phase 6a), **Gate-5
  verification** (iPhone-sim/DebugBridge → emulator lane), the **PR validation
  checklist**, the **version/tag/comment examples** (plain `vX.Y.Z` →
  `android/vX.Y.Z` where applicable), the **evidence-file metadata examples**
  (`device_or_simulator`), and the **closure templates** ("shipped in vX.Y.Z" →
  `android/vX.Y.Z`). For the version-BUMP step specifically, the Android mechanics
  are deferred to #106 — so those sections state explicitly "Android bump lands in
  #106; until then spike/shared PRs bump iOS" rather than leaving a bare iOS
  instruction that reads as the universal rule.
- **`/bump` is EXPLICITLY OUT of platform-routing scope (Gate-2-H2)**: rule 40
  mandates that pre-Phase-2 Android spike/harness AND shared-only PRs still bump
  the iOS `project.yml`; an Android bump lane begins only when
  `android/version.properties` exists — that lands in **#106**, not here. `/bump`
  stays iOS-only.
- **`.claude/cron-prompts/{verify,bugfix,feature,watchdog}.md`** (the **4** current
  crons — Gate-2-M2 corrected "3 crons" → 4) — platform-route with a
  **SKIP-Android-until-ready** safety default (no auto-start of Android work until
  this feature + #106 land).
- **`.claude/tdd-guardian/config.json`** — platform-safety: stop the frozen
  `swift-xcode` `testCommand` (confirmed at `config.json:3`) from false-greening
  Kotlin (a no-op + explicit "Android not wired" signal until #106's app exists).

### PR-E — agent + doc addenda (WI-9, WI-10) [docs]
- **`.claude/agents/*`** (the 9 stale agents) — rewrite tiptap/tauri/pnpm
  boilerplate → vreader dual-platform reality.
- **`AGENTS.md`** Android operational addendum; **`README.md`** Android section;
  **`.claude/rules/24-doc-sync.md`** + **`22-comment-maintenance.md`** Android triggers.

### Files OUT of scope
- The actual `android/` app (version.properties / root Gradle / JaCoCo) → **#106**.
- The root-`./gradlew` test lane (no app to test yet) → lights up with #106.
- A general Android `/bump` lane (rule 40) → #106.
- iOS gates: behavior unchanged for iOS PRs (every change is platform-gated, so iOS
  routing is identical to today — guarded by a dry-run test).

## Prior art / precedent
- #103 (Phase 0, VERIFIED) wired `code-paths.sh` into `check_codex_audit_artifact.sh`
  (the PreToolUse audit gate). PR-A is its Stop-time twin.
- `scripts/run-tests.sh` (rule 52) + `scripts/run-codex.sh` (rule 53) are the
  watchdog-runner template for `run-android-tests.sh`.
- `scripts/sweep-ghosts.sh` already reaps tool-name + waiter-loop ghost classes.

## Work-item sequencing
Strict chain **PR-A → PR-B → PR-C → PR-D → PR-E** (Gate-2-M1: PR-D depends on
PR-A's classifier + PR-B's runners + PR-C's Android verify behavior, not PR-B
alone). PR-A/PR-B are foundational (no iOS behavior change); PR-D is the
highest-risk (routing) and lands last among the tooling PRs; C/E are docs.

## Test catalogue
- `check_audit_debt` hook regression + `code_paths_platform()` classifier unit
  (PR-A) covering the FULL ownership set + precedence (Gate-2-r2): `android/`,
  `*.kt[s]`, `buildSrc/`, `gradle/`, `build.gradle*`, `settings.gradle*`,
  `gradlew*`, `gradle.properties`, `AndroidManifest.xml`, `res/` → `android-app`;
  `spikes/` → `android-spike`; `vreader/`,`vreaderTests/`,`*.xcodeproj`,
  `project.yml` → `ios`; `.claude/`,`docs/`,`contracts/`,`scripts/` → `shared`.
  Precedence cases (pure path-based, no metadata field): `shared`-only → iOS lane;
  `shared`+`android-app` → Android lane (android-app in the set wins); `scripts/
  run-android-*` change → still `shared` (iOS bump/gate, per rule 40); mixed
  `android-app`+`ios` → android-app wins the test lane (write-isolation should
  prevent this in practice).
- `run-android-tests.sh` REAL smoke against `spikes/android-reader-bench/run-bench.sh`
  (Gate-2-H1: not a dry-run — the spike harness is a genuine Android target that
  exists today); assert the watchdog + single-RESULT-line contract.
- `sweep-ghosts.sh` Gradle/emulator-class detection unit (PR-B).
- Routing dry-run (PR-D): a synthetic `android/` path → skills/commands/crons pick
  the Android test/verify lane; an `ios` path routes IDENTICALLY to today (the
  no-regression guard); `/bump` stays iOS for both.

## Risks + mitigations
- **R1 — routing regresses iOS flows**: every change is platform-gated; iOS PRs
  must route identically to today. Mitigation: a dry-run test asserting iOS routing
  is unchanged.
- **R2 — cron auto-starts Android before #106**: SKIP-Android-until-ready is the
  default; Android crons are inert until explicitly enabled.
- **R3 — runners can't be fully exercised without the Android app**: assert the
  watchdog/RESULT-line contract now (rule-52/53 compliance); full exercise is a
  #106 acceptance item.

## Backward compatibility
iOS workflow behavior is unchanged (platform-gated). No `android/` app exists yet,
so the Android lanes are dormant until #106. No data/schema impact (pure tooling).

## Acceptance criteria
1. `check_audit_debt.sh` classifies `android/`/`*.kt`/`contracts/` as code (sources
   `code-paths.sh`); hook regression green.
2. `run-android-tests.sh` + `run-android-verify.sh` exist, rule-49/52/53-compliant
   (watchdog, exact-pid, single RESULT line); self-smoke green.
3. `sweep-ghosts.sh` detects Gradle-daemon / emulator ghost classes; rule 52 has
   Cause D.
4. rules 10/47/50 + verify SKILL carry Kotlin/Compose/emulator guidance.
5. `/fix-issue`, `/feature-workflow`, plan-verify, and the 4 crons (bugfix/
   feature/verify/watchdog) platform-route every Android-carrying phase (not just
   the test lane — see PR-D scope), with SKIP-Android-until-ready default; iOS
   routing unchanged (dry-run test). `/bump` stays iOS (rule 40, deferred to #106).
6. tdd-guardian no longer false-greens Kotlin.
7. 9 `.claude/agents/*` rewritten to vreader dual-platform; AGENTS.md + README +
   rules 24/22 carry Android triggers.

## Revision history
- v1 (2026-06-18) — Gate-1 draft. 10 WIs (from the #107 row) grouped into 5 PRs.
- v2 (2026-06-18) — Gate-2 round 1 (Codex) applied. Named files/precedents all
  VERIFIED real. Fixes: **Critical** — `code-paths.sh` is a boolean gate, not a
  platform classifier (and excludes `.claude/*`); PR-A now adds a separate
  `code_paths_platform()` (ios/android-app/android-spike/shared) for routing,
  keeping `code_paths_touched()` for Gate-4. **High** — no `android/`/root-`gradlew`
  exists; runners are re-scoped to drive the REAL `spikes/android-reader-bench/
  run-bench.sh` now (root-Gradle lane deferred to #106), so the smoke exercises a
  real lane, not dry-run text. **High** — removed `/bump` from platform-routing
  scope: rule 40 keeps spike/shared PRs on the iOS bump; an Android bump lane
  begins only with `android/version.properties` (#106). **Medium** — renumbered so
  each WI maps to exactly one PR; dependency chain corrected to A→B→C→D→E (PR-D
  depends on A+B+C). **Medium** — added `.claude/commands/*` to PR-D scope, folded
  `watchdog.md` into PR-B, and corrected "3 crons" → 4 (bugfix/feature/verify/
  watchdog).
- v3 (2026-06-18) — Gate-2 round 2 applied (the 5 round-1 findings confirmed
  resolved). Fixes: **High** — `code_paths_platform()` routing contract made
  explicit: multi-valued + deterministic precedence (`android-app > android-spike
  > ios > shared`) + a feature/bug `Platform:` metadata override for rule 40's
  context-sensitive `shared` case; `scripts/` defined as `shared`. **High** — PR-C/
  PR-D scope expanded from "route the lane" to "rewrite EVERY downstream
  Android-carrying phase" (test gate, pre-FIXED verify, Gate-5, PR checklist,
  version/tag/comment + evidence-metadata examples, closure templates); the
  verify SKILL's iOS-only framing gets an explicit Android Mode; deferred Android
  bump mechanics are stated in-place (not left as bare iOS instructions). **Medium**
  — classifier + tests cover the FULL AGENTS ownership set (`buildSrc/`,`gradle/`,
  root Gradle, `gradlew*`,`gradle.properties`,`AndroidManifest.xml`,`res/`).
  **Low** — last "3 crons" residue → 4.
- v4 (2026-06-18) — Gate-2 round 3 (final allowed round) applied; all four round-2
  findings confirmed resolved. Round-3 raised one new **High**: the `Platform:`
  metadata override had no defined tracker contract. **Resolution (round cap
  reached — accepted + fixed in-plan, not re-audited): the override is REMOVED.**
  Routing is now purely path-based — write-isolation (rule 48) guarantees an
  Android-app PR's path set already classifies `android-app`, and a shared-only PR
  correctly defaults to iOS (rule 40), so the rule-40 context-sensitive case is
  covered by the path set with no new tracker field. This eliminates the
  under-defined mechanism the finding flagged rather than building a metadata
  sub-feature (avoids scope creep). No other Critical/High/Medium open per round 3.
  **Gate-2 CLEAN** (3 rounds; final finding resolved by simplification).
