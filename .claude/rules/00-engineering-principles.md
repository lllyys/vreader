# 00 - Engineering Principles (Local)

Follow the shared rules in `AGENTS.md`.
This file mirrors local-only references for vreader.

Key points:

- Read before editing; keep diffs focused; avoid drive-by refactors.
- Keep features local; avoid cross-feature imports unless the type is genuinely shared.
- Keep code files under ~300 lines.
- Prefer protocols at boundaries (`LibraryPersisting`, `BookImporting`, `HighlightPersisting`) so tests can mock the boundary.
- Cross-actor calls go through `await`; avoid `assumeIsolated` outside narrow App-init contexts.
- See `50-codebase-conventions.md` for the patterns this codebase actually uses.
