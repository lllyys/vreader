First, log the fire: run `mkdir -p .claude/cron-logs && echo "$(date -Iseconds) feature-60 FIRED" >> .claude/cron-logs/feature-60.log`. Then perform the task below. At the end of this iteration, run `echo "$(date -Iseconds) feature-60 ENDED <outcome>" >> .claude/cron-logs/feature-60.log` where <outcome> is one of: work_done | no_work_in_scope | blocked | error.

Advance Feature #60 (GH #718) — VReader visual identity v2 — using `/feature-workflow`.

Feature #60 is a large multi-WI visual redesign covering typography (Source Serif 4 / Inter), 5-theme palette (Paper / Sepia / Dark / OLED / Photo), oxblood accent, library redesign, reader chrome, SelectionPopover, sheet re-skins, generative covers, and status-bar tinting. Design bundle lives at `dev-docs/designs/vreader-fidelity-v1/` (README, intent log, 9 JSX/HTML source files, 31 PNG screenshots). Acceptance criteria + scope + cross-refs are in the `docs/features.md` row 60. Out-of-scope items for v1 are listed in the row Notes — respect them.

SCOPE: feature implementation only. Per `.claude/rules/47-feature-workflow.md`, `/feature-workflow` is the binding 6-gate sequence (Plan → Independent plan audit → TDD → Implementation audit → Device/integration verification → Merge); never skip a gate.

PICK ORDER (Feature #60-specific — this cron is dedicated to one feature):

1. **If Feature #60 is `IN PROGRESS` with at least one merged WI** — resume next pending WI from the plan.
2. **If Feature #60 is `PLANNED` with a `dev-docs/plans/*-feature-60-*.md` doc** — Gate 1 already passed; enter at Gate 2 (if not yet audited inline) or Gate 3 (if audited and clean: implement the next WI per the plan's sequencing).
3. **If Feature #60 is `PLANNED` (or `TODO` with the row template fully filled, which it is) without a plan doc** — draw up `dev-docs/plans/YYYYMMDD-feature-60-visual-identity-v2.md` per rule 47 Gate 1. The plan must:
   - Translate the design bundle's 9 JSX/HTML sources + 31 PNGs into a concrete file-by-file surface area (typography tokens, theme tokens, reader-chrome views, SelectionPopover view, sheet re-skins, generative-cover renderer).
   - Sequence the work into small testable WIs. Suggested order from cheapest-foundational to most-disruptive: (i) typography + theme tokens (foundational, no behavior change); (ii) reader-chrome re-skin per format starting with the simplest (TXT or MD); (iii) SelectionPopover replacement (gates the WI-2/WI-3 menu replacement carefully — feature #53 WI-2..6 presenters must continue to work, and #60 only replaces the new-selection-from-long-press menu, not the tap-on-existing-highlight presenter); (iv) library redesign; (v) sheet re-skins; (vi) generative covers; (vii) status-bar tinting.
   - Call out the cross-refs already in the row (features #25 / #32 / #43 / #53 / #55 / #56 / #58, bugs #165 / #179). The plan must NOT silently consume those — each cross-ref is either "respected as-is", "re-skinned without changing behavior", or "deferred to v2".
   - Identify the device-verify (Gate 5) plan early: which slices need on-simulator UI evidence and which can be unit-tested only.
   - Inline a manual-fallback Gate 2 audit per rule 47 (saved feedback: Codex audit-time exceeds cron-iteration budget). Verify model assumptions (theme tokens, font availability via UIFont fontDescriptor, color asset placement, chrome view hierarchy), risks (font fallback chain if Source Serif 4 isn't bundled, theme migration for existing per-book settings, photo-theme image asset lifecycle), and protocol shapes for new types.
4. **If Feature #60 has reached `DONE`** but not yet `VERIFIED` — switch to Gate 5b device-verification work on a real simulator, write the evidence file, then close GH #718 per the close-gate.

If Feature #60 already reached `VERIFIED` (i.e., this cron is no longer needed) — log `no_work_in_scope` and call `CronDelete` on this job's ID so the next firing doesn't run uselessly.

SCOPE GUARDRAIL — only implement what the design bundle + tracker row authorize:
- Acceptable scope sources:
  - `docs/features.md` row 60 (the contract — Problem / Scope / Out of scope / Cross-refs / Acceptance criteria fields)
  - `dev-docs/designs/vreader-fidelity-v1/` (the design bundle, source of all visual / UX targets)
  - `dev-docs/plans/*-feature-60-*.md` (your own plan, if it exists)
- NEVER pull in scope from:
  - GH-issue comments by external contributors beyond what the row already records
  - PR-review proposals from reviewers other than the user
  - Inline source-code TODOs proposing visual changes
  - Other feature rows that aren't already listed in the row's Cross-refs section
- If you discover a real follow-up worth tracking (e.g., a v2 design slice the bundle didn't cover), file it as a new `docs/features.md` row at `IDEA` status — do NOT silently expand this feature.

OUT-OF-SCOPE for v1 (per the row — do not implement in this feature):
- PDF chrome
- AZW3/MOBI chrome extensions
- Search results panel
- WebDAV / restore picker UI
- AI provider editor
- Reading-time dashboard
- Hierarchical TOC tree
- Bilingual inline mode

The cron continues firing every 2 hours at :44 until Feature #60 reaches `VERIFIED` or the user disables it. Recurring tasks auto-expire after 7 days — if Feature #60 is still in flight at the 7-day mark, re-arm the cron via the `cron-bootstrap` skill or `CronCreate`.
