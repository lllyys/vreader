---
branch: feat/feature-54-wi-3-engine-dispatch
threadId: 019e3db7-7fa5-7032-a90e-a7b9246424ab
rounds: 3
final_verdict: ship-as-is
date: 2026-05-19
---

# Codex audit — feature #54 WI-3 (route reader dispatch by ReaderEngine)

## Scope

`git diff main` on branch `feat/feature-54-wi-3-engine-dispatch` (feature-#54 WI-3 changes only; unrelated feature-#68 merge files excluded from review):

- `vreader/Views/Reader/ReaderContainerView.swift` — `engineReaderView` dispatch by `ReaderEngine.resolve`; error views moved in.
- `vreader/Views/Reader/ReaderContainerView+Sheets.swift` — dead `loadReplacementRules` removed; unused `import SwiftData` dropped.
- `vreader/Views/Reader/ReaderUnifiedDispatch.swift`, `UnifiedPlaceholderView.swift` — DELETED.
- `vreaderTests/Views/Reader/ReaderContainerViewEngineDispatchTests.swift` — 10 tests.
- `docs/architecture.md`, `README.md` — doc-sync.
- `project.yml` / `vreader.xcodeproj/project.pbxproj` — version bump → 3.31.7.

## Round 1

**Verdict: follow-up-recommended.** No code-correctness findings — the new `engineReaderView` mapping is equivalent to the old `nativeReaderView` switch, the routing path no longer reads `readingMode`, no orphan references, unknown-format fallback preserved.

- **Medium** — `README.md` / `docs/architecture.md`: the doc updates claimed the user-visible reading-mode toggle was already gone, but WI-3 only collapses the dispatch — `ReaderSettingsPanel` still renders the picker until WI-4. Fix: scope the docs to the dispatch change only.
- **Low** — `ReaderContainerViewEngineDispatchTests.swift`: the engine-resolution invariant proves `ReaderEngine.resolve` is correct but does not pin the `engine case → host` wiring inside `engineReaderView`. Fix: add a tighter host-mapping assertion.

## Resolution (round 1 → round 2)

- Medium: reverted the premature `README.md` "no rendering-mode toggle" bullet (WI-4 owns that README change); reworded `architecture.md` overview + Dispatcher subsection to scope WI-3's claim to the dispatch only.
- Low: added `engineReaderViewMapsEachEngineCaseToItsHost` — per-engine-case source guard asserting each `case .<engine>:` constructs the host its engine implies.

## Round 2

**Verdict: needs-revision.** README + test fixes confirmed resolved. One remaining Medium: `architecture.md` line 100 (Unified Engine subsection) still said "Feature #54 removed the Native/Unified toggle" — the same premature claim elsewhere in the file.

## Resolution (round 2 → round 3)

Reworded `architecture.md` line 100: "removed the unified path from the reader dispatch ... no longer reachable from reader dispatch ... picker UI removed in a later feature-#54 work item."

## Round 3

**Verdict: ship-as-is.** No remaining doc claim that the picker is gone; all three mentions scope WI-3's claim to the dispatch only.
