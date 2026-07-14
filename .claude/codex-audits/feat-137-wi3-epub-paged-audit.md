---
branch: feat/137-wi3-epub-paged
threadId: 019f6190-a821-7cf2-bff3-502240fb5d21
rounds: 1
final_verdict: follow-up-recommended
---

# Gate-4 audit — feature #137 WI-3 (EPUB paged toggle via Readium)

**Auditor:** Codex gpt-5.5 / reasoning=high (rule 53 via `scripts/run-codex.sh`, `RUN-CODEX RESULT: SUCCEEDED`).
**Scope audited:** the 2-site `EpubPreferences(scroll)` flip in
`android/app/src/main/kotlin/com/vreader/app/reader/ReaderActivity.kt` (open-time `initialPrefs` +
live `observeDisplaySettings` `submitPreferences`), the 3 new `@VisibleForTesting` hooks, and the new
connected test `EpubPagedToggleConnectedTest.kt` + `paged-multipage.epub` fixture.

## Verdict: follow-up-recommended (no Critical/High). Two Mediums FIXED in-lane, one Low accepted.

## Verified (Codex)
- Scroll default remains `scroll=true`; Paged maps to `scroll=false`.
- BOTH the open-time `initialPrefs` and the live `submitPreferences` paths are layout-driven.
- No custom gesture code was added — Readium's native page-turn is used.
- The `+` merge order is correct: Readium 3.3.0 `EpubPreferences.plus` uses `other.scroll ?: scroll`,
  and `EpubPreferencesMapper.toEpubPreferences()` leaves `scroll` null, so the left operand's
  `scroll` survives the merge (confirmed against the Readium 3.3.0 source).
- `val current` at open-time does not shadow the book-loop var (the book is `loaded`).
- Lifecycle risk unchanged by the flip.

## Findings

### Medium-1 — position residue could make the page-turn assertion flaky — FIXED
`stageBook()` imports the same fixture bytes each run; `BookImporter` preserves a saved position on a
duplicate import, and `ReaderActivity` restores it on open, so a prior run could reopen mid/near-end
of the book (no page after the current one to advance into).
**Fix:** the test now calls `repository.clearPosition(book.fingerprintKey)` right after staging,
guaranteeing a deterministic start-of-book open.

### Medium-2 — page-turn poll could pass without a turn — FIXED
The predicate checked `now != before` before calling `goForwardForTest()`, so a spurious async
`currentLocator` settle before any turn could satisfy it.
**Fix:** a `turnedAtLeastOnce` gate — the poll drives `goForward` FIRST and only accepts a changed
locator AFTER at least one real turn has happened (still reading the change on a later iteration, past
the 200ms settle, to avoid racing the async emission).

### Low — hooks not DEBUG-stripped — ACCEPTED (rationale)
The 3 new hooks are `src/main` public methods annotated `@VisibleForTesting` only (not `#if DEBUG`
equivalent). This matches the EXISTING local convention on this exact activity — `appliedBackgroundArgb`,
`currentHref`, `jumpToTocEntryForTest`, and ~20 other `@VisibleForTesting` hooks are the same shape.
They alter no user behavior (pure reads + one seam over the existing `navigator.goForward`). A different
pattern for these 3 would be inconsistent; accepted.

## Post-fix re-test
Production changed after the audit (an unused `currentTotalProgressionForTest` hook removed) + the test
hardened for both Mediums, so the targeted connected suite was re-run GREEN on emulator-5554 (see the
HANDOFF `test_result_line`).
