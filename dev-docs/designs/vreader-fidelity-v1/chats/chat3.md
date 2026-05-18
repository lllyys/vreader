# GitHub issues review

_Started 2026-05-18 14:27 UTC_

---

## User

https://github.com/lllyys/vreader/issues/865 https://github.com/lllyys/vreader/issues/864 https://github.com/lllyys/vreader/issues/863 https://github.com/lllyys/vreader/issues/862 https://github.com/lllyys/vreader/issues/860

## Assistant

_[tool: list_files]_

_[tool: github_list_repos]_

_[tool: read_file]_

_[tool: list_files]_

_[tool: web_fetch]_

_[tool: web_fetch]_

_[tool: web_fetch]_

_[tool: web_fetch]_

_[tool: web_fetch]_

I've got 3 of the 5 issues. Let me grab the remaining two and explore the existing design assets in parallel.

_[tool: read_file]_

_[tool: read_file]_

_[tool: web_fetch]_

_[tool: web_fetch]_

_[tool: read_file]_

I have web_fetch back this turn. Let me get the remaining 2 issues and explore key source files.

_[tool: web_fetch]_

_[tool: web_fetch]_

_[tool: read_file]_

_[tool: read_file]_

_[tool: read_file]_

_[tool: web_fetch]_

_[tool: web_fetch]_

I have all 5 issues now. Let me explore the existing components to ground new designs in the same vocabulary.

_[tool: read_file]_

_[tool: read_file]_

_[tool: read_file]_

_[tool: read_file]_

_[tool: read_file]_

_[tool: read_file]_

_[tool: read_file]_

Now let me look at the existing canvas pattern and remaining components quickly.

_[tool: snip]_

_[tool: update_todos]_

_[tool: read_file]_

I have enough context. Let me snip earlier large outputs and plan the build.

_[tool: write_file]_

Now I'll build five new component files and a canvas tying them together. Let me start.

### Component 1 — Note-preview presenter (#865)### Component 2 — Re-translate menu + provider picker (#864)

_[tool: write_file]_

_[tool: write_file]_

### Component 3 — Translate entire book (#863)### Component 4 — Profile-card identity (#862)

_[tool: write_file]_

### Component 5 — Unified HighlightsSheet (#860)

_[tool: write_file]_

### Canvas — tying all 5 issues together

_[tool: write_file]_

Now the canvas HTML host that wires it all together.

_[tool: write_file]_

_[tool: show_html]_

_[tool: write_file]_

Let me write the design notes markdown alongside, then surface to the user.

_[tool: done]_

_[tool: fork_verifier_agent]_

_[tool: update_todos]_

All five `needs-design` issues now have a committed design pass on the canvas. Each section is one issue, with every state across themes; decisions live in `design-notes/needs-design-issues.md`.

**Canonical picks:**
- **#865** — anchored note callout (not the bottom-popover used for highlight actions), bottom-sheet fallback for long notes / VO
- **#864** — re-translate row in the More popover when bilingual is on, secondary swipe action in TOC, half-sheet provider picker with per-run scope
- **#863** — Book Details > Actions row (canonical) + library long-press; confirmation shows real cost; cancel alert disabuses the user that they're losing translated chapters
- **#862** — *Library-as-identity* card (no fake user-name), plus dashboard gains time-window bar + sortable per-book table
- **#860** — extend the design (option 2); Notes filter merges `HighlightRecord.note` + standalone `AnnotationRecord`; new `StandaloneNoteCard` distinguished by dashed accent rule + small "Standalone" pill

Each section ships with a post-it sticky explaining the why; the canvas state persists so reorderings / hides / renames you make stick across reloads.

## User

Verifier agent check completed

## Assistant

_[tool: str_replace_edit]_

_[tool: done]_

Fixed — the `ProfileCardNamed` outer wrapper is now a `<div role="button">` with keyboard handlers, so the inner "Stats" pill stays a real `<button>` without nesting. Console is clean.

