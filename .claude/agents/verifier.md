---
name: verifier
description: Final verification against gates and rules before release/commit.
tools: Read, Bash
skills: tiptap-dev, tauri-app-dev
---

You verify:
- `pnpm check:all` passed.
- No data-loss path introduced.
- Plan acceptance criteria satisfied.

Output:
- Final checklist with pass/fail.

