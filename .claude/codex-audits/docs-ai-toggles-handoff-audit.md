---
branch: docs/ai-toggles-handoff
threadId: manual-fallback
rounds: 1
final_verdict: ship-as-is
date: 2026-05-20
---

## Scope

Syncs the claude.ai/design "VReader AI Toggles Canvas" handoff
(chat9) into the `dev-docs/designs/vreader-fidelity-v1/` bundle.
Touches the design bundle, plus `project.yml` / `project.pbxproj`
(version bump 3.38.18/593 → 3.38.19/594).

**No Swift source files changed.** The audit-gate hook fires on
`project.pbxproj` — false positive of the Swift-file heuristic.
Manual mini-audit.

## Manual audit evidence

### What changed and why

Bundle sync (rsync, superset — nothing deleted): 4 new files —
`VReader AI Toggles Canvas.html`, `ai-toggles-artboards.jsx`,
`vreader-ai-toggles.jsx`, `chats/chat9.md`; `README.md` updated
(chat count 8 → 9).

The handoff delivers the committed design for `needs-design` issue
**#1068** — two undesigned toggle rows in `SettingsView`'s AI
section for feature **#67** (Settings re-skin). The two rows are
the AI-master toggle ("Enable AI Assistant") and the
Data-&-Privacy-consent toggle, both peers of the AI Provider row
already shipped in feature #67 WI-5 (PR #1069).

Canonical: variant A (tile-parity) — both render as
`SettingsToggleRow` inside the AI group; master reuses the shipped
AI Provider palette (`#8c2f2f` sparkle); consent adds a new tile
color (`#4a6a8a`) with a `shield.checkmark` glyph. When AI is off,
peer rows are *hidden* (height collapse) — not disabled / greyed.
Variants B (master-as-section-header) and C (privacy callout card)
are alternatives.

### Correctness checks

1. **#1068 is a real, open `needs-design` issue** — verified via
   `gh issue view 1068`: OPEN, labels `enhancement` +
   `needs-design`, title "Design needed: AI Assistant + Data &
   Privacy toggle rows in SettingsView for feature #67".
2. **Issue → feature linkage** — #1068's body names feature #67
   (Settings re-skin). Feature #67's row in `docs/features.md`
   carries no row-level `BLOCKED: needs-design (#1068)` annotation
   (the toggle rows are a sub-affordance gap, not a row-level
   block); no `docs/features.md` row is flipped here.
3. **Issue closure** — PR uses `Resolves #1068` so the
   `needs-design` issue auto-closes on merge (same precedent as
   PRs #1037 / #1039 / #1060 / #972 / #956 / #930 / #869 / #848).
4. **No Swift implemented** — design-delivery only. Building the
   two toggle rows is gated feature-#67 feature-workflow work;
   deliberately not in this PR.
5. **Bundle-diff sanity** — `diff -rq` against the incoming
   handoff matched exactly the 4 expected files (README + chat9 +
   1 HTML + 2 JSX). No silent overwrites of existing canvases.
6. **Version bump** — 3.38.19 / build 594 (patch — docs /
   design-bundle sync). `xcodegen generate` confirmed both
   `project.yml` and `project.pbxproj`. `xcodebuild build`
   SUCCEEDED on iPhone 17 Pro Simulator (Debug).

## Verdict

ship-as-is — design-bundle sync + version bump. No Swift logic.
Manual fallback used because there is nothing to send to Codex.
