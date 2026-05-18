---
branch: docs/issues-canvas-handoff
threadId: manual-fallback
rounds: 1
final_verdict: ship-as-is
date: 2026-05-18
---

## Scope

Syncs the claude.ai/design "VReader Issues Canvas" handoff into the
`dev-docs/designs/vreader-fidelity-v1/` bundle and lifts the
`needs-design` block on the five feature rows it unblocks. Touches the
design bundle, `docs/features.md` (5 row annotations), `project.yml` /
`project.pbxproj` (version bump 3.30.3/454 → 3.30.4/455).

**No Swift source files changed.** The audit-gate hook fires on
`project.pbxproj` — false positive of the Swift-file heuristic. Manual
mini-audit.

## Manual audit evidence

### What changed and why

- Bundle sync (rsync, superset — nothing deleted): 9 new files —
  `VReader Issues Canvas.html`, `issues-canvas-artboards.jsx`,
  `design-notes/needs-design-issues.md`, `chats/chat3.md`, and 5 new
  component jsx (`vreader-note-preview.jsx`, `vreader-retranslate.jsx`,
  `vreader-translate-book.jsx`, `vreader-profile-stats.jsx`,
  `vreader-notes-unified.jsx`); `README.md` updated.
- `docs/features.md`: five rows had their `**BLOCKED: needs-design
  (#N)**` annotation replaced with `**Design delivered 2026-05-18 —
  issue-canvas handoff resolves needs-design #N**`. Status of all five
  stays `TODO` (the BLOCKED text was a notes annotation, not the status
  field). The rest of each row's note — the original triage rationale —
  is left intact.

### Correctness checks

1. **The 5 `needs-design` issues are real, open, design-gap issues** —
   verified via `gh issue view`: #860 / #862 / #863 / #864 / #865 all
   `OPEN` with the `needs-design` label, titles `Design needed: …`.
   Their titles name the exact features the design note maps them to.
2. **Issue → feature mapping matches the trackers** — design note
   `needs-design-issues.md` maps #865→#55, #864+#863→#56, #862→#67/#58,
   #860→#62. Each feature row's pre-existing `BLOCKED: needs-design`
   annotation named the same issue number: #55←#865, #56←#863/#864,
   #58←#862, #62←#860, #67←#862. Linkage consistent.
3. **`BLOCKED` → delivered, status stays `TODO`** — `BLOCKED:
   needs-design` was a custom notes annotation. With the design
   delivered the rows are ready for `/feature-workflow` Gate 1 (or Gate
   2 for #62, which already has a plan doc). `TODO` is not a hook-gated
   terminal status.
4. **Edits applied surgically** — a Python pass replaced each marker
   only after asserting it occurred exactly once. One unrelated
   `BLOCKED: needs-design` string remains (a stale cross-reference to
   `#842` inside feature #31's historical verification note — not a
   live block, not in this handoff's scope, deliberately untouched).
5. **No Swift implemented** — design-delivery only. The five features
   (#55/#56/#58/#62/#67) are gated feature-workflow work; deliberately
   not in this PR.
6. **Version bump** — 3.30.4 / build 455 (patch — docs / design-bundle
   sync). `xcodegen generate` confirmed.

### Issue-closure note

The PR body uses `Resolves #860 … #865` so the five `needs-design`
issues auto-close on merge. This matches the reader-navigation handoff
precedent (PR #848, commit `6d0b1bb`, "resolves #812 / #842"): a
`needs-design` issue is resolved purely by the design being committed —
there is no device-verification step for a design's existence, so the
close-gate's verify-before-close rule (which targets bugs/features)
does not apply.

## Verdict

ship-as-is — design-bundle sync + five row annotations + version bump.
No Swift logic. Manual fallback used because there is nothing to send to
Codex.
