---
branch: docs/reader-navigation-design-bundle
threadId: manual-fallback
rounds: 1
final_verdict: ship-as-is
date: 2026-05-18
---

## Scope

Syncs the `dev-docs/designs/vreader-fidelity-v1/` bundle to the latest claude.ai/design handoff (share token `uf8gWxcXyEmO9U-eNK8zJQ`) — the reader-navigation design resolving two `Design needed:` issues, and unblocks the two bugs they gated. Touches the design bundle, `docs/bugs.md` (bug #165 + #215 status flips), `project.yml` / `project.pbxproj` (version bump 3.27.27/441 → 3.27.28/442).

**No Swift source files changed.** The audit-gate hook fires on `project.pbxproj` — false positive of the Swift-file heuristic. Manual mini-audit.

## Manual audit evidence

### What changed and why

- Bundle sync: new `design-notes/reader-navigation.md` (the committed decisions), 3 new jsx (`vreader-scroll-mode.jsx`, `vreader-tap-zones.jsx`, `vreader-autoturn.jsx`), `VReader Navigation Canvas.html`, `nav-canvas-artboards.jsx`, 2 screenshots, plus updated prototype HTML + `vreader-app/panels/reader/tweaks` jsx. rsync — superset of the prior bundle, nothing deleted.
- `docs/bugs.md`:
  - **Bug #165** (EPUB chapter navigation unintuitive, High) — status `BLOCKED: needs-design (#812)` → `TODO`. `reader-navigation.md` §2 delivers the design #812 was blocking on (EPUB hybrid: side-tap chapter-boundary wrap in paged mode, continuous cross-chapter scroll in scroll mode).
  - **Bug #215** (MD Paged layout never engages, Medium) — status `BLOCKED: needs-design (#842)` → `TODO`. `reader-navigation.md` §3 delivers the design #842 was blocking on (chrome-aware content inset, de-duplicated page indicator, first-open tap-zone hint, auto-page-turn ribbon).

### Correctness checks

1. **#812 / #842 are `Design needed:` blocker issues** — verified via `gh issue view`: #812 "Design needed: EPUB reader chapter-navigation interaction model (for bug #489)" OPEN; #842 "Design needed: MD reader paged-mode layout ... for bug #215" OPEN. `reader-navigation.md`'s own header states it "Resolves #842, #812." Committing the design resolves them — same pattern as #760 (PR #771) and #789/#790/#793 (PR #797).
2. **Bug #165 ↔ #812** — bug #165's row carried `BLOCKED: needs-design (#812)` verbatim; #812's title references "bug #489" which is bug #165's own GH issue number. The linkage is consistent.
3. **`BLOCKED: needs-design` → `TODO`** — `BLOCKED: needs-design` is a custom blocked annotation, not a standard bug status. With the design delivered the correct standard status is `TODO` (ready to fix). The `check_terminal_status_evidence.sh` hook does not gate `TODO`.
4. **No Swift implemented** — design-delivery only. The EPUB hybrid chapter nav (bug #165) and MD paged-mode layout (bug #215) implementations are gated bug-fix work via `/fix-issue`; deliberately not in this PR.
5. **Version bump** — 3.27.28 / build 442 (patch — docs / design-bundle sync). xcodegen regen confirmed.

### Adjacency note (not edited)

`reader-navigation.md` §2.3's continuous-scroll model (chapter divider + heading + lazy load) is conceptually adjacent to bug #180 (TXT scroll-mode continuous cross-chapter, REOPENED) — but the design note frames §2.3 for EPUB scroll mode and does not name bug #180 or TXT. Bug #180's row was deliberately NOT edited; claiming this design covers it would overstate the note. The adjacency is flagged in the PR description for the user.

## Verdict

ship-as-is — design-bundle sync + two bug status flips + version bump. No Swift logic. Manual fallback used because there is nothing to send to Codex.
