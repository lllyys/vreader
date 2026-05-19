# I don't have access to external links or the ability to browse GitHub. Could you please share the content of the issue or describe what design question you're asking

_Started 2026-05-19 13:57 UTC_

---

## User

https://github.com/lllyys/vreader/issues/963

## Assistant

## Assistant

_[tool: github_list_repos]_

_[tool: list_files]_

_[tool: web_fetch]_

_[tool: read_file]_

_[tool: read_file]_

_[tool: read_file]_

_[tool: read_file]_

_[tool: grep]_

_[tool: grep]_

_[tool: grep]_

_[tool: grep]_

_[tool: grep]_

_[tool: grep]_

_[tool: grep]_

_[tool: update_todos]_

I'll design a canvas exploring annotation-import affordances for issue #963. The repo is your own (lllyys/vreader), so I'll follow the same patterns I see across the existing fidelity bundle — `HighlightsSheetV3`, `BookDetailsSheet`, the `DesignCanvas` + `DCArtboard` + `DCPostIt` scaffolding, the paper/sepia/dark theme palette, and the iOS-style sheet chrome.

Plan: three candidate families (overflow menu on HighlightsSheet, Actions-card row in BookDetailsSheet, alternate surfaces) with variants and a canonical recommendation note. I'll create one new components file and one canvas artboards file so it composes cleanly with the existing bundle.

_[tool: grep]_

_[tool: grep]_

_[tool: grep]_

_[tool: read_file]_

_[tool: write_file]_

I have enough context now. Let me write the components file.Now the canvas artboards:

_[tool: write_file]_

Now the host HTML:

_[tool: write_file]_

_[tool: done]_

_[tool: fork_verifier_agent]_

Designed candidates for issue #963 in **VReader Import Affordance Canvas.html**, alongside your existing fidelity bundle.

**Four sections, in the same DesignCanvas vocabulary as the other issue canvases:**

- **A — HighlightsSheet trailing slot** (`A1` ••• overflow menu / `A2` two-icon anti-pattern / `A3` Share + Import pill), plus a true-size header comparison strip
- **B — BookDetailsSheet Actions** (`B1` Import paired with Export / `B2` single "Annotations…" row → half-sheet)
- **C — Empty-state secondary CTA** on HighlightsSheet — composes with A or B
- **P — Post-pick preview sheet** (VReader JSON / Readwise / Apple Books / dark / error-mismatch) — shared surface across all triggers

**Canonical pick recorded on post-its:** **A1 + C1**, with **B1** as the backstop in Book Details. Reasoning lives next to each section so the Gate-2 audit has something to cite.

Two new component files only — no edits to existing fidelity sources:
- `vreader-annotation-import.jsx`
- `import-affordance-artboards.jsx`

