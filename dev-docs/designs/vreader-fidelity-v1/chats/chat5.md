# I don't have the ability to access external links or browse the internet, including GitHub issues. 

Could you please share the content of the issue or describe

_Started 2026-05-19 10:30 UTC_

---

## User

https://github.com/lllyys/vreader/issues/949

## Assistant

_[tool: list_files]_

_[tool: read_file]_

_[tool: read_file]_

_[tool: web_fetch]_

_[tool: read_file]_

_[tool: read_file]_

_[tool: read_file]_

_[tool: read_file]_

_[tool: read_file]_

_[tool: read_file]_

_[tool: grep]_

_[tool: list_files]_

_[tool: write_file]_

I have everything I need. Issue #949 calls for a **single unified highlight-action popover** that reconciles two existing surfaces (`NoteCallout` from #55 and `HighlightActionPopover` from #53) into one design used across all 5 reader formats.

Plan:
- `vreader-highlight-popover.jsx` — the unified component (anchored callout + bottom-sheet fallback)
- `highlight-popover-canvas-artboards.jsx` — full state matrix
- `VReader Highlight Popover Canvas.html` — entry

The system: header (swatch · HIGHLIGHT · date · ×) → excerpt with colored left bar → note region (read/empty/edit, all in serif, replacing the read-mode note in #55) → color palette → action row (Copy, Share, Delete). One pointer-notched anchored form is canonical; a bottom sheet handles long-note / VoiceOver paths. Format-consistency row shows the same surface across TXT/MD/PDF/EPUB/AZW3 backdrops.Now the artboards file:

_[tool: write_file]_

Now the entry HTML:

_[tool: write_file]_

_[tool: done]_

_[tool: fork_verifier_agent]_

Built the unified surface for issue #949 as a design canvas at `VReader Highlight Popover Canvas.html`.

**The system**
- `HighlightActionCard` — anchored to the tapped passage with a pointer notch (inherits the #55 geometry). Composition: meta row (swatch · HIGHLIGHT · chapter/date · ×) → italic excerpt with colored left bar → note region (reading/empty/editing) → color palette → action row (Copy · Share · Delete).
- `HighlightActionSheet` — same content, no notch; routed to on VoiceOver or when the anchored card can't fit.
- The card's `confirm-delete` state replaces the action row inline so the surface stays a single visual unit instead of stacking an iOS alert on top.

**Coverage on the canvas** — 9 sections, ~35 artboards:
1. Intent (canonical, no-note, anchored-below)
2. State machine (reading short/long, empty, editing, editing-empty, confirm-delete)
3. Color row (current, pressing-blue with halo, after, alt color)
4. **Format consistency** (TXT, MD, PDF, EPUB, AZW3 backdrops, identical card on top — the point of the issue)
5. CJK (zh reading + editing) and RTL (ar)
6. Themes (paper, sepia, dark, OLED, dark + confirm)
7. Bottom-sheet fallback (reading, editing, confirm, dark)
8. Migration: before/after — small recreations of NoteCallout and the bare TXT/MD/PDF UIMenu side-by-side with the new card, with red-tagged gaps
9. Spec card — binding contract for the #64 adapters

Component file is `vreader-highlight-popover.jsx`; artboards in `highlight-popover-canvas-artboards.jsx`. Edit hand-off to the committed full editor (`HighlightNoteEditSheet` from #914) is referenced via the inline "Expand" hint rather than re-implemented.

