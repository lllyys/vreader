---
branch: fix/issue-476-txt-highlight-coordinator-wiring
threadId: 019e0d0a-30a6-7e71-b0d0-5cd8098d0b96
rounds: 2
final_verdict: ship-as-is
date: 2026-05-09
---

# Codex Audit — Bug #160 / GH #476

TXT highlight coordinator wiring fix in `TXTReaderContainerView.swift`.

## Round 1

### Findings

**1. `vreader/Views/Reader/TXTReaderContainerView.swift:486` | High | Chapter-mode TXT bridge ignores `uiState.persistedHighlightRanges`** — `chapterReaderContent` hardcodes `persistedHighlights: []`, so even though `restoreAll()` populates `uiState.persistedHighlightRanges`, the chapter-mode bridge will never read it. For any TXT book opened in chapter mode (default for files with detected `CHAPTER`/`Section` markers, including the bug-#160 verify fixture `war-and-peace.txt`), the original symptom remains: no yellow paint and no restored highlights on reopen.

**Resolution: deferred to feature #48 (WI-7).** Chapter-mode display+creation translation is the WI-7 scope per `docs/features.md` row 48. The pre-existing `// Highlight offset translation is WI-7` comment in `chapterReaderContent` already documents this as an unimplemented translation boundary. Sibling bug #154 (search-tap highlight rendering) shipped with the same scope-limit pattern (PARTIAL FIX in non-chapter paths, chapter mode deferred). Bug #160 row updated to PARTIALLY FIXED with the same explanation; feature #48 row expanded 2026-05-09 to cover the gesture-creation pipeline, not just search-tap rendering.

**2. `vreader/Views/Reader/TXTReaderContainerView.swift:410` | High | Chapter-mode highlight creation persists with chapter-local offsets** — `TXTTextViewBridge` selection offsets are chapter-local in chapter mode, but `locatorFactory` calls `LocatorFactory.txtRange` with those offsets as-is. Persisted records would have chapter-local offsets stored as if global; multiple chapters with offset 100 would collide on the same fingerprint+offset key.

**Resolution: deferred to feature #48 (WI-7).** Same scope reasoning as finding 1. The creation-side translation (chapter-local→global before locator factory + chapter text as context source while storing global offsets) requires a new `LocatorFactory.txtChapterRange` variant or `txtRange` extension — feature work, not a bug fix. Tracked in expanded feature #48 surface area + acceptance criteria.

**3. `vreaderTests/Views/Reader/TXTReaderContainerHighlightCoordinatorWiringTests.swift:88` | Medium | Wiring tests are source-text grep tests** — they prove certain strings exist but don't run executable behavior; they explicitly bless the broken chapter path (`persistedHighlights: []`).

**Resolution: accepted with rationale.** Source-text wiring tests follow project precedent (`TXTReaderContainerSearchHighlightWiringTests.swift` for bug #154 uses the same pattern). The blessing of `persistedHighlights: []` for chapter path is INTENTIONAL — it pins the WI-7 boundary so a future PR knows it's expanding scope when chapter wiring is added. `HighlightCoordinator` behavior is already covered by `HighlightCoordinatorTests` + `HighlightIntegrationTests` at the unit/integration level. The SwiftUI `@State` lifecycle inside `.task` blocks doesn't have a clean SwiftUI-level test harness in this project; the wiring-test pattern is the project's accepted compromise.

## Round 2

After scope clarification + tracker updates, Codex re-reviewed and confirmed:

> "No additional code findings in the agreed non-chapter scope. The TXT fix is correct and complete for small-file and chunked paths: the real coordinator is now wired in `.task`, `restoreAll()` feeds `uiState.persistedHighlightRanges`, and both non-chapter bridges consume that shared state."

One Low finding flagged tracker mismatches (bug #160 still IN PROGRESS, feature #48 still scoped to search-tap only). Both addressed in this PR's tracker commits.

## Verdict

**ship-as-is** for the agreed non-chapter scope. The wiring bug — orphan `@State highlightCoordinator/highlightRenderer` causing `makeNoOpCoordinator` to silently drop every gesture — is a real bug independent of chapter mode and gets fixed here. Chapter-mode TXT highlight (creation translation + display translation) is feature #48 / WI-7 scope, not bug-fix scope.

## Manual audit evidence

Not applicable — Codex MCP audit completed end-to-end in 2 rounds.
