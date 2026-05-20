---
branch: docs/bilingual-offline-handoff
threadId: manual-fallback
rounds: 1
final_verdict: ship-as-is
date: 2026-05-20
---

## Scope

Syncs the claude.ai/design "VReader Bilingual Offline Canvas" handoff
into the `dev-docs/designs/vreader-fidelity-v1/` bundle. Touches the
design bundle, plus `project.yml` / `project.pbxproj` (version bump
3.37.27/573 → 3.37.28/574).

**No Swift source files changed.** The audit-gate hook fires on
`project.pbxproj` — false positive of the Swift-file heuristic. Manual
mini-audit.

## Manual audit evidence

### What changed and why

Bundle sync (rsync, superset — nothing deleted): 3 new files —
`VReader Bilingual Offline Canvas.html`, `bilingual-offline-artboards.jsx`,
`vreader-bilingual-offline.jsx`; `README.md` + `chats/chat7.md` updated.

The handoff delivers the committed design for `needs-design` issue
**#1024** — the **bilingual offline / "translation unavailable" inline
state** for feature #56 (bilingual reading mode). Feature #56's plan
(`dev-docs/plans/20260519-feature-56-bilingual-reading.md`, Decision 2
edge case (c)) requires bilingual mode to show *something* when a
chapter is not cached and the device is offline; the prior committed
design bundles depicted no offline state. This handoff commits that
surface.

### Correctness checks

1. **#1024 is a real, open `needs-design` issue** — verified via
   `gh issue view 1024`: OPEN, labels `enhancement` + `needs-design`,
   title "Design needed: bilingual offline / translation-unavailable
   inline state for feature #56".
2. **Issue → feature linkage** — #1024's body names feature #56 and
   cites the plan's Decision-2 edge case (c). Feature #56's row in
   `docs/features.md` carries no `BLOCKED: needs-design (#1024)`
   annotation (the offline-state is a sub-affordance gap from #56's
   plan, not a row-level block), so no `docs/features.md` row is
   flipped here.
3. **Issue closure** — PR uses `Resolves #1024` so the `needs-design`
   issue auto-closes on merge (same precedent as PRs #1037 / #972 /
   #956 / #930 / #869 / #848: a `needs-design` issue is resolved by
   the design being committed).
4. **No Swift implemented** — design-delivery only. Building the
   offline state is gated feature-#56 feature-workflow work;
   deliberately not in this PR.
5. **Version bump** — 3.37.28 / build 574 (patch — docs / design-bundle
   sync). `xcodegen generate` confirmed.

## Verdict

ship-as-is — design-bundle sync + version bump. No Swift logic. Manual
fallback used because there is nothing to send to Codex.
