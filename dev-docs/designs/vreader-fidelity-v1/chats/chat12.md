# GitHub Issues Discussion

_Started 2026-05-31 01:04 UTC_

---

## User

https://github.com/lllyys/vreader/issues/1296 https://github.com/lllyys/vreader/issues/1292

## Assistant

_[tool: list_files]_

_[tool: read_file]_

Let me fetch those two issues to understand what's being requested.

_[tool: web_fetch]_

_[tool: web_fetch]_

I now understand both issues. Let me explore the existing project's patterns before building. The user is viewing the Slider Track Canvas — and issue #1292 explicitly references that the slider-track facet already shipped via a sibling design pass. Let me study the established conventions.Let me study the slider-track artboards (the sibling design that shipped) and the themes file — these are the closest precedent for issue #1292.

_[tool: read_file]_

_[tool: read_file]_

_[tool: read_file]_

_[tool: read_file]_

This is a well-established pattern: each `needs-design` issue gets a "decision canvas" — DesignCanvas artboards with live-measured WCAG ratios, before/after, candidates, across-themes, and a binding spec card. I'll match it exactly for both issues. Let me read the canvas/frame APIs and the components involved in #1296 (the standalone-note editor flow).

_[tool: read_file]_

_[tool: read_file]_

Excellent — I have the full pattern now. Let me read the components I need to faithfully recreate for both issues: the unified notes card / highlights sheet / annotation editor (for #1296), and the Display panel list chrome (for #1292).

_[tool: read_file]_

Now let me read the panels file — it holds the `Sheet` component, the Display panel, and the List section headers/footers that issue #1292 is about.

_[tool: read_file]_

I have a thorough understanding of both issues and the codebase conventions. Let me quickly check the existing note-actions / delete menu pattern (the `⋯` menu referenced in #1296) so my standalone-note card menu matches.

_[tool: read_file]_

_[tool: grep]_

The `vreader-notes-delete.jsx` (issue #1103) already built `HighlightsSheetV4`, `StandaloneNoteCardV4`, and `NotesActionMenu` with the `⋯ → Edit note` flow — and even notes the open question my issue #1296 resolves. Let me check the existing canvas HTML shells to copy the exact dependency-include pattern.

_[tool: read_file]_

Let me peek at how the delete canvas artboards mount `HighlightsSheetV4` inside a phone frame, so my #1296 storyboard matches.

_[tool: update_todos]_

I have a complete picture — the conventions, components, data, and dependency-include pattern are all clear. These are two specific, well-scoped design decisions in a mature, established "decision-canvas" system (this is the 12th+ such canvas). I won't ask questions; I'll match the precedent exactly. Let me lay out the plan.

_[tool: write_file]_

Starting with **#1292** (secondary-text AA contrast) — it's the direct sibling of the slider-track canvas the user is viewing. Writing the artboards file with live-measured WCAG ratios.Now the HTML shell for #1292:

_[tool: write_file]_

Let me verify #1292 loads cleanly before moving on.

_[tool: show_html]_

_[tool: show_html]_

_[tool: get_webview_logs]_

_[tool: save_screenshot]_

Clean. Let me screenshot to confirm the layout.

_[tool: view_image]_

_[tool: update_todos]_

#1292 renders beautifully — the measured ratios (3.82 Paper, 3.37 Sepia) match the issue exactly, and the AFTER panels are visibly more legible. Marking done and moving to #1296.

_[tool: write_file]_

Now **#1296** — the standalone-note editor presentation. This is the storyboard-based decision (Option A "edit over the sheet" vs Option B "dismiss + navigate"). I'll reuse `HighlightsSheetV4`, `NotesActionMenu`, `FakeIOSKeyboard`, `NoteSavedToast`, and `DiscardNoteAlert`, and build a faithful standalone-note editor surface. Writing the artboards file:Now the HTML shell for #1296, loading the full dependency chain (icons, panels, the V4 notes sheet, the note editor):

_[tool: write_file]_

_[tool: show_html]_

_[tool: get_webview_logs]_

Clean. Let me screenshot the decision and storyboard sections to confirm the stacked-sheet rendering and overall layout.

_[tool: save_screenshot]_

_[tool: view_image]_

_[tool: str_replace_edit]_

Looks great — the editor is clearly stacked over the dimmed list. One nit: the "Edit note" title wraps to two lines (the center header group is narrow). Let me fix that with `nowrap`.

_[tool: show_html]_

Let me confirm the title fix and spot-check a storyboard section by panning the canvas.

_[tool: save_screenshot]_

_[tool: view_image]_

_[tool: delete_file]_

Both canvases are complete and render faithfully — the "Edit note" title is now on one line, the CJK/pinyin keyboard, saving state, long-note scroll, and spec card all read correctly. Let me clean up the temp screenshots and finalize.

_[tool: update_todos]_

_[tool: done]_

_[tool: fork_verifier_agent]_

Both `needs-design` issues are resolved as decision canvases, matching the project's established pattern (live-measured contrast, before/after, candidates, across-themes, binding spec card).

**#1292 — Paper/Sepia secondary-text AA contrast** → `VReader Secondary Text Canvas.html`
Decision: bump the light-family `sub` token from **ink @ 55% → ink @ 68%**. One rule derived from each theme's ink (mirroring #1273's rail), it's the smallest unified alpha that clears WCAG AA in the binding case — Sepia at **4.88:1**, Paper at **5.81:1** — while staying clearly lighter than primary ink. All ratios are computed live in-canvas (current values reproduce the issue's 3.82 / 3.36). Dark/OLED are measured honestly (~3.7:1, also under AA) and flagged as an out-of-scope follow-up rather than silently claimed fine.

**#1296 — Standalone-note editor presentation (WI-3)** → `VReader Standalone Note Editor Canvas.html`
Decision: **Option A — present `AnnotationEditSheet` over the HighlightsSheet, non-dismissing**, returning to the list on Save. Both options are storyboarded 4-up; a decision matrix and a "two intents" card make the case: a standalone note is anchorless, so the "after the jump" rationale (which exists for highlights so the popover can anchor to the visible passage) does nothing here. A keeps the user in their triage context, reuses the existing sheet primitive, and needs no new reader-level mount. The spec card defines the exact plumbing (`edit().standalone → editAnnotation(id)` observed at sheet level → `updateAnnotation` → dismiss to list).

A background verifier is sweeping both. Two notes:
- The recommended values are computed/displayed, but a maintainer should confirm the 68% weight against any other `sub`-consuming surfaces before merging globally (the spec calls out the considered-and-rejected `subAA` alternative if a scoped token is preferred).
- These present the design decision; both still carry the `needs-design` framing — they don't ship code.

