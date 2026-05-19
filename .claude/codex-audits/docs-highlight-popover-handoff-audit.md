---
branch: docs/highlight-popover-handoff
threadId: manual-fallback
rounds: 1
final_verdict: ship-as-is
date: 2026-05-19
---

## Scope

Syncs the claude.ai/design "VReader Highlight Popover Canvas" handoff
into the `dev-docs/designs/vreader-fidelity-v1/` bundle. Touches the
design bundle, plus `project.yml` / `project.pbxproj` (version bump
3.36.0/515 → 3.36.1/516 (rebased onto main)).

**No Swift source files changed.** The audit-gate hook fires on
`project.pbxproj` — false positive of the Swift-file heuristic. Manual
mini-audit.

## Manual audit evidence

### What changed and why

Bundle sync (rsync, superset — nothing deleted): 4 new files —
`VReader Highlight Popover Canvas.html`,
`highlight-popover-canvas-artboards.jsx`,
`vreader-highlight-popover.jsx`, `chats/chat5.md`; `README.md` updated.

The handoff delivers the committed design for `needs-design` issue
**#949** — the **unified cross-format highlight-action popover**. Per
`vreader-highlight-popover.jsx`, the design is `HighlightActionCard`:
one surface and one gesture for all five formats (TXT/MD/PDF/EPUB/AZW3)
— quoted excerpt with a colored left border, a highlight-colour row,
note view + edit, and a Copy / Share / Delete action row; anchored to
the tapped passage with a pointer notch, with a bottom-sheet variant
for long notes and VoiceOver. It reconciles the two prior highlight-tap
models — `vreader-note-preview.jsx` (the #55 read-only callout) and
`vreader-reader.jsx`'s `HighlightActionPopover` — into one.

### Correctness checks

1. **#949 is a real, open `needs-design` issue** — verified via
   `gh issue view 949`: OPEN, labels `enhancement` + `needs-design`,
   title "Design needed: unified cross-format highlight-action popover
   for feature #64".
2. **Issue → feature linkage** — #949's body names feature #64
   ("Styled highlight-action popover (v2)"). Feature #64's row
   (`docs/features.md` line 106) is `TODO`; it carries no
   `BLOCKED: needs-design` annotation and no `#949` reference, so no
   `docs/features.md` row is flipped here. Committing the design simply
   makes #64 design-ready for its eventual feature-workflow (Gate 1).
3. **Issue closure** — PR uses `Resolves #949` so the `needs-design`
   issue auto-closes on merge (same precedent as PR #930 / #869 / #848:
   a `needs-design` issue is resolved purely by the design being
   committed).
4. **No Swift implemented** — design-delivery only. Building
   `HighlightActionCard` is gated feature-#64 feature-workflow work;
   deliberately not in this PR.
5. **Version bump** — 3.36.1 / build 516 (patch — docs / design-bundle
   sync). `xcodegen generate` confirmed.

## Verdict

ship-as-is — design-bundle sync + version bump. No Swift logic. Manual
fallback used because there is nothing to send to Codex.
