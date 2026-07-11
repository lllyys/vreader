# Plan v4 (final) — compile the full-codebase canon into bureau + Codex audit-fix

**Date**: 2026-07-11 (session 014jggU2u3f3t6YRoPLS457u, started 2026-07-10)
**Directive**: Deeply analyze all code, uncover all dependencies, logic, features, bug
fixes, and other code facts, and write them into bureau, using cc-suite codex audit fix.
Codex must ensure ALL the code and relationships are analyzed (coverage, not just accuracy).
**Codex model**: `gpt-5.6-sol` (user override), effort `high`, sequential calls only.
**Revision history**: v1 → Codex round 1 (thread `019f4e3b-d37d-7f12-a8e2-ab6df3e102d3`):
MAJOR GAPS, 30 findings. v2 → round 2: NEEDS REVISION (12 RESOLVED / 14 PARTIAL /
1 FAILED / 12 new). v3 → round 3: NEEDS REVISION with a closed minimal residual set of 6.
v4 folds in the 4 mechanical residuals and the minute-ordering fix; the 2 protocol
deviations are **escalated to the human as pre-execution gates** (3-round audit cap
reached — rule-47 escalation, not silent acceptance).

## PRE-EXECUTION GATES — human decisions required (Codex r3 minimal-change #1)

> **RESOLVED 2026-07-11**: the user approved BOTH gates — H1 composite dossiers
> approved (option a), H2 audit minute approved (option a). Execution unblocked.

Execution does not start until the user decides:

- **Gate H1 — composite-dossier schema deviation.** The bureau compile skill specifies
  one claim per page; the 36 dossiers are claim-composites (one page per module) whose
  `verified` tier means "every checkable claim on the page verified", with whole-page
  demotion on any substantive edit. Options: (a) APPROVE the deviation now (the
  `decisions/composite-dossier-schema.md` page records it; `bureau:review` later ratifies
  it to `canonical`), or (b) REJECT → the corpus must be split into atomic claim pages
  (~500+ pages) before any verification continues.
- **Gate H2 — one-session-two-minutes deviation.** The capture skill says one session =
  one minute file, and the 2026-07-10 minute must never be rewritten. This plan needs a
  2026-07-11 **audit minute filed in Phase 0** so corrections can cite provenance that
  exists before they're written. Options: (a) APPROVE the second minute
  (`…-audit · 2026-07-11`, documented deviation), or (b) REJECT → corrections carry only
  the 07-10 origin link and this phase's provenance lives solely in the final report
  (weaker traceability).

If both approved, everything below runs autonomously; findings that would touch a
`canonical` page still stop for the human.

## Background — the bureau write gate (binding), with capture-first ordering

`canon/` routes durable knowledge through **capture** → **compile** (`proposed`/
`verified`) → **review** (HUMAN writes `canonical`). This pipeline is the compile/verify
machinery. Ordering guarantees (Codex D1#1/N1/r3-N1):

- The audit minute is filed at Phase 0 step 0, BEFORE any canon write; every
  corrected/extended/new page cites BOTH minutes (origin 07-10 + audit 07-11).
- The audit minute is **finalized by a single append in Phase 5 step 1 — BEFORE
  press/health run #3 — and never touched after**; `_compile-state.json` is written
  last, so no minute content is ever compiled-then-mutated.
- Canonical pages are read-only; disagreement → `contested` finding for the human.
- The 07-10 minute stays byte-identical throughout.

## Current state (all uncommitted; nothing committed without an explicit ask)

- 36 dossiers on disk (4 architecture, 28 modules, 2 decisions, 2 timeline).
- 11 of 36 verifiers completed on 07-10; 12 pages read `verified` (incl. the unproven
  `modules/pdf-reader.md` flip). **Correction from v3 (Codex r3-N2): the 11 completed
  verifiers' structured returns were schema-capped at 12 checks — they are NOT complete
  evidence.** Therefore ALL 36 pages go through Phase-1 verification under the new
  uncapped schema: 25 first-time + 11 re-verifications (cheap: those pages are already
  clean, the re-run mostly re-confirms and returns full evidence).
- Corruption (grep-confirmed, root-caused): Workflow `args` arrived as a JSON string →
  `undefined` template values: 30 pages `**Sources.** [[undefined]]`, 8
  `updated: undefined`, 4 `**Verified.** undefined`. The old workflow/cache is abandoned;
  survey output on disk is the input.
- The 07-10 minute claims `_compile-state.json`/`_verify.json` exist; they don't yet —
  recorded in the audit minute; the 07-10 entry stays untouched.

## Ledgers and data contracts

All underscore files are deterministic rebuilds (temp file → JSON-parse validation →
atomic rename), never appends:

1. **`canon/_coverage-manifest.md`** — universe = `git ls-files -co --exclude-standard`
   (exact command in the header), minus bureau outputs (`canon/`, `gazette/`,
   `BUREAU.md`, this plan) as excluded-with-reason rows.
2. **`canon/_coverage-ledger.json`** — **one row per FILE for every included path**
   (Codex r3-N4); directory-group rows are allowed ONLY for homogeneous `excluded` or
   `listed` sets (e.g. one row per `vreaderTests/` suite directory, one per asset
   catalog). Row: `{path, disposition, required_level, dossier, section,
   achieved_level, verdict}`. Levels are ordered cumulative `listed < described <
   behavioral`, assigned by FILE CONTENT: `behavioral` for state
   transitions/I-O/parsing/navigation/bridge/concurrency logic (all Services/,
   ViewModels/, App/, Views/Reader bridges+coordinators+hosts, Android logic,
   `scripts/*.sh`, `.claude/hooks/`); `described` for declarative leaf UI + passive data
   definitions; `listed` for resources/fixtures/config/designs/`.github/`. Verdicts
   start `unchecked`; only C1 evidence (or an orchestrator spot-read citing the section)
   sets `achieved_level`+`verdict`; preassignment ≠ coverage; machine test:
   `achieved_level < required_level` ⇒ under-covered.
   `vreaderTests/`: `listed` rows per suite directory + a "Module — test architecture"
   dossier at `described` (framework split, helpers, suite↔subsystem map).
3. **`canon/_edge-ledger.json`** — expected relationship universe, built by
   **deterministic extraction scripts** (Codex r3-N7), one per class, each spec'd as:
   exact search commands, normalization (resolve `Notification.Name` constants to their
   string values; strip whitespace; canonical repo-relative paths), dedup by
   `(class, from, to)`, pairing rules (e.g. a notification edge pairs a `post` site with
   an `addObserver` site by resolved name), and **fail-visible handling: an unpaired or
   ambiguous candidate gets `verdict: ambiguous` — never an invented edge**. Classes:
   (a) notification post↔observe; (b) protocol conformance + injection seams;
   (c) actor/persistence access; (d) JS bridge channels (`WKScriptMessageHandler` names,
   `evaluateJavaScript` call sites); (e) `contracts/` doc↔iOS↔Android↔vectors;
   (f) build/target deps (`project.yml`, SPM, bridging headers). Row: `{class, from,
   to, evidence: {from_loc, to_loc}, dossier, verdict: unchecked|represented|
   missing-from-canon|ambiguous}`.
4. **`canon/_verify.json`** — built ONLY from Phase-1 structured verifier returns
   (never prose parsing). Verifier artifact arrays are **uncapped**; a dossier whose
   full artifact set would be unreasonable to enumerate is split into claim scopes by
   the verifier rather than truncated — truncation is a verifier-contract violation
   (Codex r3-N3). Directory entries expand recursively to tracked regular files at
   build time; nonexistent/escaping paths demote the page. sha256 byte-level, keys
   sorted. The page's human-readable `**Verified.**` line is RENDERED from this data.

## Status state machine

`proposed` →(full-page verification)→ `verified`; substantive edit demotes immediately;
re-promotion needs fresh full-page verification + rebuilt ledger entry; conflicts →
`contested`. Terminal `proposed` semantics: interpretive pages (`decisions/`,
`timeline/`, hub) = awaiting-human-review by design, no marker; factual pages that
failed verification carry `**Blocked.** <reason>`. Hub terminal status: `proposed`.

## Phase 0 — capture, repair, preflight

0. **File the audit minute** (Gate H2 approved form). File
   `decisions/composite-dossier-schema.md` (Gate H1 record).
1. **Provenance/schema repair** (Edit tool, file-by-file): exactly the three corrupt
   structural forms — `**Sources.** [[undefined]]` → dual minute links (prepended where
   a raw artifact list exists, list kept); `updated: undefined` → `2026-07-10`;
   `**Verified.** undefined —` → `**Verified.** 2026-07-10 —`. Demote `pdf-reader.md`.
   Exit check: zero matches for `\[\[undefined\]\]`, `^updated: undefined`,
   `\*\*Verified\.\*\* undefined` (a blanket `grep undefined` is WRONG — the diagnostics
   dossier legitimately documents a `DiagnosticsLevel.undefined` enum case).
2. **Press/health run #1**: build + health; fix dangling links/duplicate titles/schema
   errors now.
3. **Manifest v2 + coverage-ledger v0** (per-file rows; unowned rows = gaps for Phase 2).
4. **Workflow preflight**: verify workflow embeds all constants in the script body (no
   `args`). Sacrificial verifier = wave 1 member 1 (`modules/export.md`): run alone,
   inspect structured return + page diff, then continue.

## Phase 1 — full verification pass (ALL 36 pages, dynamic waves)

- Target set: 25 unverified + 11 re-verifications under the uncapped schema (r3-N2).
- Waves built dynamically from the remaining unresolved set (≤13/wave), checkpoint
  grep-audit between waves (corrupt patterns, frontmatter legality, status legality);
  failed page → requeue once; second failure → demote if flipped + `**Blocked.**` +
  continue. A usage-limit hit is a checkpoint pause, not corruption.
- Verifier contract: hostile fact-check every checkable claim; fix/delete wrong claims;
  repair Sources/updated lines; flip clean factual pages `verified` with rendered
  `**Verified.** <actual date> — …`; interpretive pages fact-fixed, stay `proposed`.
  Structured return: verdict, claims_checked, errors_fixed, artifacts (uncapped array,
  regular files; split into claim scopes rather than truncate).

## Phase 2 — synthesis + ledgers + structural gate

1. Hub dossier `architecture/system-overview.md`.
2. "Module — test architecture" dossier + gap dossiers for unowned ledger rows (each:
   `proposed` → Claude hostile-verify → ledger update).
3. Build `_edge-ledger.json` via the extraction scripts; map edges to dossiers; unmapped
   edges become dossier fixes NOW (pre-Codex).
4. Rebuild `_verify.json` from Phase-1 returns.
5. **Press/health run #2**; then `_compile-state.json` (marks both minutes compiled —
   the audit minute still receives its single pre-health-#3 append in Phase 5, after
   which compile-state is rebuilt last).

## Phase 3 — Codex audit (coverage → accuracy → relationships)

Mechanics: `codex-runner.mjs --kind audit --model gpt-5.6-sol --effort high --sandbox
read-only --timeout-ms 900000 --summary "<batch>"`, sequential; persona + provenance
disclosure + `.cc-suite.md` project instructions; `*.md` skip pattern overridden.
Output contract: fenced JSON `{items: [{id, verdict, findings: [{severity, claim,
correction, location}]}]}` validated against the exact batch inventory; mismatch → one
re-scope → escalate. Raw outputs persisted; thread/job IDs recorded. First call = model
probe + timing calibration; batch weights shrink if hot.

- **C1 coverage** (2 calls): C1a iOS production ledger rows; C1b tests/automation/
  Android/contracts/docs rows. Codex sets `achieved_level`+`verdict` per row.
  → Fix window: gap/extension dossiers + Claude verify + ledger rebuild.
- **C2 accuracy — dynamically partitioned** (Codex r3-N6): after the C1 fix window,
  snapshot EVERY non-canonical cabinet page (the 36 + hub + test-architecture + gap
  pages); partition into batches by domain with a ≈40-artifact weight cap; **assert
  every page appears in exactly one batch** (the partition is printed before the first
  call); expect ≥7 calls.
- **C3 relationships** (2 calls): C3a classes (a)(b)(f); C3b classes (c)(d)(e) —
  verdict per edge-ledger row + per-class missed-edge hunt; `ambiguous` rows are
  resolved (paired or dropped with reason), never left as silent coverage.

## Phase 4 — fix loop (≤3 rounds; fixer = Claude)

Per round: (1) fix all findings (IDs `<batch>-<n>`), Critical/High first;
verified-page edits demote → same-round re-verification; coverage/edge findings →
dossier + ledger updates. (2) Re-verify per originating batch (bounded), then one small
closure call over the verdict ledger. (3) Convergence gate: round N+1 runs only if round
N closed ≥50% of its open Critical+High findings; else stop + escalate with numbers.
Round-3 residuals reported; user may approve an extension.

## Phase 5 — finalize (ordering per Codex r3-N1)

1. **Finalize the audit minute — single append** (incident+repair, thread IDs, rounds,
   final inventory, ledger stats). The minute is frozen from here on.
2. **Press/health run #3** (validates the final minute + full canon state).
3. Rebuild `_verify.json`, `_coverage-ledger.json`, `_edge-ledger.json`; reconcile the
   state machine; **`_compile-state.json` written last**.
4. Final report: inventory by status, finding dispositions, ledger stats, Codex
   verdicts, `/bureau:review` handoff.

## Acceptance criteria

- Zero matches for the three corrupt patterns; every page carries valid minute links.
- All 36+ factual pages `verified` (uncapped evidence) or `**Blocked.**`-annotated;
  interpretive pages `proposed` by design; `canonical` untouched.
- `_coverage-ledger.json`: per-file rows, every included row `achieved_level ≥
  required_level` with an evidence-backed verdict — or residuals listed.
- `_edge-ledger.json`: every row `represented`, `ambiguous` resolved — or residuals
  listed.
- Codex: schema-valid per-item verdicts for all C1/C2/C3 inventories — or honest
  residual list.
- Press health green ×3; minute frozen before health #3; `_compile-state.json` last;
  07-10 minute byte-identical.
- No commits.

## Contingencies

- Usage limit mid-wave → checkpoint pause, requeue, next wave.
- Codex `failed`/`stalled` → no blind retry (one re-scope on contract mismatch); report
  jobId, stop phase, escalate. No silent self-audit substitution.
- `gpt-5.6-sol` rejected → surface and ask.
- Structural surprise → stop, report.

## Round-3 disposition summary

| r3 item | v4 disposition |
| --- | --- |
| Min-change 1 (human approvals) | Escalated as pre-execution Gates H1/H2 — execution blocked on the user's answer |
| Min-change 2 / N2 / N3 (11 capped returns; 60-cap) | All 36 pages re-verified under an UNCAPPED schema; truncation = contract violation; split-into-scopes rule |
| Min-change 3 / N4 (directory rows) | Per-file ledger rows; homogeneous-group rows only for excluded/listed |
| Min-change 4 / N6 (C2 partition) | Post-synthesis snapshot + dynamic partition + exactly-one-batch assertion |
| Min-change 5 / N1 (minute ordering) | Minute finalized by single append BEFORE health #3; compile-state last; frozen after |
| Min-change 6 / N7-r3 (edge extraction) | Deterministic per-class extraction spec: commands, normalization, dedup, pairing, ambiguous = fail-visible |
| D1#4 / N5-r3 (schema reliance before ratification) | Gate H1 moves ratification BEFORE execution |
| D5#4 / N12 (final health scope) | Health #3 runs after the frozen minute, validating true final state |
