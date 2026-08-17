# 57 — Ultracode Within-WI Fan-out

Binding when **ultracode is ON** (a system-reminder confirms it). This rule closes the gap rule 48
and rule 55 leave open: they govern the `/dispatch` **worktree-lane** mechanism (multi-item,
isolation-first, wall-clock-denominated), and they correctly degrade a single work item (N=1) to the
inline flow. Neither says anything about fanning out the **analytical** work *within* one WI — the
reads, the edge-case brainstorm, the audit. Ultracode's standing directive ("use the Workflow tool
on every substantive task; token cost is not a constraint") already makes that within-WI fan-out the
default; this rule resolves the rulebook ambiguity (rule 48's decision test read as if it priced
analytical spawns like worktree lanes) and specifies the mechanism.

Origin: feature #138 WI-6 (2026-07-23), honestly decomposed (the first draft of this rule
over-claimed; a 5-angle adversarial grill of the rationale corrected it). A single acceptance-test
WI ran almost entirely inline. The post-write Gate-4 audits then surfaced three false-green defects,
and the three had **different** root causes: one had been *surfaced by the deep 5-lens pass and
mis-triaged in the solo reconcile step* (stated targets logged but only looser ceilings asserted);
one was a genuine lens-scope miss (a synthetic-fallback that hollowed the real-book acceptance); one
was implementation-emergent (a short-circuit only visible in the written code). The durable lessons:
(a) run the deep AND broad audits in parallel and let the block gate (the broad pass caught all
three); (b) the deep pass's triage/reconcile step needs hardening, not just more layers — see
"Follow-ups" below; (c) a **pre-write** "how could this false-green?" pass *plausibly* front-loads
the requirement-level defect classes (the first two), though this is a **hypothesis, hindsight-
assessed** — it is justified below on cost asymmetry, not on a claimed counterfactual save.

## The principle

**Fan out every analytical step that does NOT hold the exclusive resource.** The binding serial
resource (the single emulator/simulator — rule 52; one Codex/test session — rule 48) caps
*verification* parallelism, not *analysis* parallelism. Analytical fan-out either (a) runs
*concurrently* with the serial critical section (the emulator run) — genuinely ~zero added
wall-clock — or (b) *precedes* the exclusive resource being touched: **serial, but small relative to
the audit-block cycle it hedges** (a Gate-4 block costs a fix + connected re-run + another audit
round). With ultracode removing the token-cost objection, the residual costs are the ones to manage
honestly: the orchestrator's reconcile tax on fan-out findings, context dilution from each
synthesis, and occasional fan-out infrastructure failure (a workflow died on a schema retry-cap in
the origin session). So the default is **net-positive in expectation, not free**: on infrastructure
failure, retry once then degrade to inline analysis with a note; keep syntheses summary-sized; the
reconcile stays a deliberate solo step (see below).

## The three sanctioned within-WI fan-outs

Run these via the `Workflow` tool (or parallel read-only `Agent`/`Explore` spawns). They are the
default for any substantive inline WI under ultracode — a bug fix (`/fix`, `/fix-issue`) or a
feature WI (`/feature-workflow`).

1. **Parallel context sweep — BEFORE the write.** Instead of sequential Reads to gather the files,
   APIs, prior art, and constraints a WI needs, fan out read-only `Explore` agents to gather them at
   once and return a structured map. Replaces serial reads; strictly faster. (Per rule 48's
   context-absorption warning, treat the map as orientation — reconfirm load-bearing details
   first-hand before editing.)

2. **Pre-write adversarial brainstorm — BEFORE the write.** Before authoring the RED test / the fix,
   fan out adversarial lenses over the *intended* change: "how could this test pass while proving
   nothing?", "what edge cases (empty/nil/max/Unicode-CJK/RTL/concurrent/failure-injection) must it
   cover?", "what invariant between subsystems could this break?" Fold the findings into the
   test/impl you then write **once, solo**. Justification: cost asymmetry — the pass is minutes and
   sits before any exclusive-resource work; the Gate-4 block cycle it hedges is tens of minutes.
   Whether it actually front-loads block-class defects is **instrumented, not assumed**: when you run
   it, record in the WI's notes whether its findings intersect the subsequent Gate-4 findings —
   sustained zero intersection over ~5 WIs retires this fan-out to optional.

3. **Deep + broad audit — AFTER the write, before merge, in PARALLEL.** Run the per-claim
   adversarial fan-out AND the broad Codex audit (`scripts/run-codex.sh`) concurrently. The evidence
   (n=2: #131 plan gate, #138 WI-6) is that the broad pass catches classes the deep pass misses —
   whether that is true complementarity or a deep-triage defect, the remedy is the same: run both,
   and when they disagree, **trust the block on cost-asymmetry grounds** (a false block costs one
   bounded re-check; a false ship ships a hollow gate). Reconcile deliberately: a deep-pass finding
   you decide to accept/deflect rather than fix is exactly the shape that produced a Codex block in
   the origin session — record the reason in the audit artifact so the choice is reviewable.

## What to keep SOLO (do NOT fan out)

- **The write itself.** One coherent file/change has ONE author (rule 48 hard rule 3 —
  one-writer-per-file). Fanning out the authoring produces merge conflict, not speed.
- **The reconcile judgment.** Deciding which audit findings to fix vs accept is one judgment call,
  made by the main agent that owns the change — but it is the step that failed in the origin
  session, so it carries its own discipline: every accepted/deflected Medium-or-above finding gets a
  one-line written rationale in the audit artifact (reviewable, not silent).
- **Anything that would CONTEND the exclusive resource.** Never fan out "run the connected test" onto
  the same emulator/simulator (rule 52 — contention wedges the run into a ghost). Verification stays
  serial on one device; only a second leased device unlocks parallel runs (rule 55 Android tier +
  `scripts/sim-lease.sh`).

## Scope boundaries

- **Binds the INLINE flows and the ORCHESTRATOR, not restricted-tool lanes.** A `/dispatch`
  `implementer` lane is a subagent with no `Agent`/Workflow tool and cannot fan out (Workflow nesting
  is one level). So this rule binds the inline authoring flows (`/feature-workflow`, `/fix`,
  `/fix-issue`) and the dispatch *orchestrator's* own analytical steps (e.g., the deep+broad plan
  audit before spawning lanes) — never the lane interior. The lane's analytical work is front-loaded
  by the orchestrator before dispatch.
- **Ultracode-gated.** When ultracode is OFF, the rule-48 decision test governs (the token-cost term
  is back in play, so a marginal fan-out may not clear the bar). When ON, treat these three fan-outs
  as the default and note any WI where you *skipped* one and why.

## Follow-ups (named, so they don't silently drop)

- **Mechanize the logged-vs-asserted check**: a test that logs `target_met(<X>)` while asserting a
  looser bound is detectable mechanically — worth a lint/hook so the origin session's High-2 class
  can't recur on discipline alone.
- **Deep-pass falsification discipline**: each adversarial lens states what evidence WOULD falsify
  the change, so a "sound" verdict is a checked claim, not a skim.
- **Instrumentation review**: after ~5 ultracode WIs, review the fan-out-#2 hit-rate notes and keep,
  tune, or retire it.

## What this rule does NOT change

TDD order (rule 10), the six gates (rule 47), sim/emulator isolation (rule 52), codex isolation
(rule 53), background-shell discipline (rule 49), the `/dispatch` multi-item mechanism (rule 55).
Rule 48 remains the *when parallelism is legal*; rule 55 is the *`/dispatch` multi-item how*; this
rule is the *within-WI analytical how under ultracode*.
