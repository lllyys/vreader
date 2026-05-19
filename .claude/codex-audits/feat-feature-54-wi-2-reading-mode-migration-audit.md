---
branch: feat/feature-54-wi-2-reading-mode-migration
threadId: 019e3da4-7ab1-7ec3-b5ef-c6e619b4c647
rounds: 2
final_verdict: ship-as-is
date: 2026-05-19
---

# Codex audit — feature #54 WI-2 (ReadingModeMigration namespace)

## Scope

`git diff main` on branch `feat/feature-54-wi-2-reading-mode-migration`:

- `vreader/Services/ReadingModeMigration.swift` — new `enum ReadingModeMigration` (synchronous one-shot launch migration).
- `vreaderTests/Services/ReadingModeMigrationTests.swift` — 14 tests.
- `docs/architecture.md` — `ReadingModeMigration` Services Layer table row.
- `project.yml` / `vreader.xcodeproj/project.pbxproj` — version bump 3.31.4 → 3.31.5.

## Round 1

**Verdict: follow-up-recommended. 1 Medium + 1 Low — both test-coverage gaps, no code defect.**

- **Medium** — `ReadingModeMigrationTests.swift`: the semantic-preservation cases only used fields already on `PerBookSettingsOverride` (`fontSize`, `fontName`, `themeName`, `lineSpacing`). A regression to a typed `JSONDecoder`/`JSONEncoder` round-trip would still pass while silently dropping unknown future keys. Fix: add a fixture with unknown top-level members (nested object/array/scalar), assert all survive.
- **Low** — `ReadingModeMigrationTests.swift`: the second-run idempotency test only covered the UserDefaults half. WI-2 also requires per-book file cleanup idempotency (no needless rewrite). Fix: migrate a file once, record bytes/mtime, re-run, assert unchanged.

Auditor confirmed no correctness bug in `ReadingModeMigration.swift`: genuinely synchronous, uses raw `JSONSerialization` (not the typed override model), skips missing/invalid/non-JSON cases, `try?` usage reasonable as best-effort startup cleanup.

## Resolution (round 1 → round 2)

Both findings fixed as pure test additions (no production code change):

- `run_preservesUnknownTopLevelKeys_notJustStructFields` — fixture with unknown scalar/bool/number/nested-object/array members; asserts each survives the migration with identical decoded content.
- `run_perBookFileCleanup_isIdempotent_noRewriteOnSecondRun` — migrates a per-book file once, records bytes, re-runs, asserts the file is byte-identical on the second pass and still `readingMode`-free.

Suite re-ran green: 14 tests.

## Round 2

**Verdict: ship-as-is.** Both prior findings confirmed genuinely resolved. `run_preservesUnknownTopLevelKeys_notJustStructFields` closes the Medium (exercises unknown top-level members; would fail under a typed round-trip). `run_perBookFileCleanup_isIdempotent_noRewriteOnSecondRun` closes the Low (records migrated bytes, re-runs, asserts no rewrite).
