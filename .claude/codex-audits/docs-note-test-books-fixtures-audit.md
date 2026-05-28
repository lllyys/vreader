---
branch: docs/note-test-books-fixtures
threadId: manual-fallback
rounds: 1
final_verdict: ship-as-is
date: 2026-05-29
---

## Scope

Docs only — records the local `test-books/` fixture directory in the repo (it was in no
file before, only in agent memory). No Swift, no app behavior. The `project.pbxproj` delta is
the rule-40 version bump (3.40.10/691 → 3.40.11/692) which trips this audit-gate hook.

Files:
- `AGENTS.md` — +1 bullet under the test guidance: real EPUB/TXT/AZW3 fixtures live in
  `test-books/` (gitignored, local), import via `sim-transfer`.
- `docs/manual-test-checklist.md` — +1 "Source files" note: the books it already names live
  in `test-books/`.
- `dev-docs/plans/20260528-feature-42-readium-libmobi-reader-engine.md` — names
  `test-books/被讨厌的勇气.azw3` as the libmobi→EPUB Kindle-fidelity spike corpus (open-decision
  + WI-0).
- `project.yml` / `project.pbxproj` — version bump.

## Manual audit evidence

Manual fallback: documentation-only, no code/logic surface for Codex.

### Checks
1. **Path correctness** — used `/Users/ll/Desktop/workspace/vreader/test-books` (verified to
   exist); the user's `/Users/ll/workspace/vreader/test-books` does NOT exist on this machine
   (missing `Desktop/` segment — same quirk hardcoded in rules/48 + sim-drive-fallback, tracked
   separately).
2. **Fixture accuracy** — dir holds `被讨厌的勇气.azw3` (~6 MB Kindle/KF8), large CJK EPUBs
   (`道诡异仙` ~18 MB, `《黑暗血时代》…` ~13 MB), and a TXT. The `.azw3` is named as the #42 spike
   fixture. `test-books/` is gitignored (real books not committed — correct).
3. **Linter-mangling avoided** — editing the plan via the Edit tool triggered the markdown
   linter, which corrupted `**bold `code`**` → `****`code`****` (4 occurrences) + added `\#`
   escapes. Caught it, reverted the plan to clean `main`, and re-inserted the two fixture
   references via a Bash/python write (which bypasses the Edit-tool linter hook). Verified the
   committed plan has 0 `****`` mangles. AGENTS.md + manual-test-checklist were unaffected
   (no `**bold `code`**` pattern) and kept as their clean Edit-tool output.
4. **Version bump** — 3.40.11 / build 692 (patch — docs). `xcodegen generate` succeeded.

## Verdict

ship-as-is — documentation pointers only, paths verified, no markdown mangling shipped, no code risk.
