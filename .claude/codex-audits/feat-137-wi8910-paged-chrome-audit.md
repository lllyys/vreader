---
branch: feat/137-wi8910-paged-chrome
threadId: 019f6214-e65d-7012-991e-42c904bab872
rounds: 2
final_verdict: follow-up-recommended
---

# Gate-4 audit — feature #137 WI-8/9/10 (Android paged reader chrome: bookmarks, find, TTS-follow, bilingual gate)

Auditor: Codex (gpt-5.6, rule-53 `scripts/run-codex.sh`). Author/auditor separation preserved
(independent Codex process). Raw transcripts: `.reports/wi8910-audit-r1.txt`,
`.reports/wi8910-audit-r2.txt`.

## Scope

- `android/app/src/main/kotlin/com/vreader/app/reader/TxtReaderActivity.kt` — WI-9 re-enabled TTS in
  paged mode; added the PAGED TTS-follow `LaunchedEffect` (raises `pagedJumpRequest` to
  `pageContaining(tts.charStart)`); added the pure `pagedTtsFollowTarget` helper; gated the SCROLL
  TTS auto-scroll on `!pagedBodyMounted`; added `@VisibleForTesting` seams
  (`pagedJumpToOffsetForTest` / `simulatePagedTtsFollowForTest` / `pagedBookmarkLocatorForTest` /
  `pagedToggleBookmarkForTest` / `pagedIsBookmarkedForTest` / `pagedDocLengthForTest` +
  `testPagedDocLength`). WI-8 bookmarks + find-jump + scrubber were already routed to the pager by
  WI-6a's mode-aware `jumpToOffset` + `liveOffset`; WI-10's `usePaged = layout==Paged &&
  !bilingualState.enabled` gate already existed — this WU verifies them with connected tests.
- `android/app/src/test/kotlin/com/vreader/app/reader/PagedTtsFollowTest.kt` (JVM, 9 cases).
- `android/app/src/androidTest/kotlin/com/vreader/app/reader/TxtPagedBookmarkConnectedTest.kt`,
  `TxtPagedTtsFindConnectedTest.kt`, `TxtPagedBilingualGateConnectedTest.kt`.

No `TxtReaderBody.kt` change was needed — the TTS-follow reuses WI-6a's existing `jumpRequest` seam.

## Round 1 — verdict: block-recommended (1 High, 2 Medium, 1 Low)

- **HIGH — TTS follow fought user swipes.** The `LaunchedEffect` keyed on `pagedOffset.value`, so a
  user swipe (which changes the page offset) re-fired the follow and jumped back to the spoken page.
  **FIXED:** the effect now keys ONLY on the narration signal `(usePaged, tts.phase, tts.charStart)`
  — a user swipe changes the offset, not `charStart`, so it never re-invokes the follow; the pager
  re-tracks only when the narration advances to a new sentence. A new connected test
  `userSwipeWhileNarrationSteady_doesNotGetYankedBack` verifies the no-fight end state.
- **MEDIUM — key on `tts.phase`, not `active`.** `active` was true for both paused + speaking, so a
  pause/resume could miss a restart. **FIXED:** the effect keys on `tts.phase` directly (`active`
  removed).
- **MEDIUM — the connected TTS test bypasses the real effect** (drives `simulatePagedTtsFollowForTest`).
  Inherent: a real TTS engine cannot speak on the emulator without voice data. Accepted as a
  test-quality follow-up; the pure `PagedTtsFollowTest` + the reviewed effect keys cover the restart
  behavior. Test comment tightened to state what it proves (the no-fight end state, not the keys).
- **LOW — `spokenOffset == 0` treated as idle.** 0 is a valid first-sentence offset. **FIXED:**
  `pagedTtsFollowTarget` now rejects only NEGATIVE offsets (the caller already gates on
  `tts.phase == speaking`); offset 0 follows back to page 0. JVM test
  `zeroOffsetOnFirstSentence_followsBackToPageZero` added.

## Round 2 — verdict: follow-up-recommended (safe to ship)

All round-1 High/Medium/Low resolved; no NEW Critical/High/Medium found. Confirmed correct:

- The TTS-follow effect keys only on `usePaged`/`tts.phase`/`tts.charStart`; page-offset changes
  cannot restart it (no swipe-fight); a narration update reads the navigator's latest page
  synchronously (no stale-closure hazard).
- Bookmark toggle records the settled paged page-start SOURCE offset
  (`txtBookmarkLocator(book, navigator.currentSourceOffset())`); bookmark / annotation / find /
  scrubber jumps clamp the source offset and resolve via `pageContaining(offset)`.
- `layout == Paged && !bilingualState.enabled` forces scroll while bilingual is enabled and restores
  paged when disabled, without changing the stored layout preference.
- The pure helper's edge cases (null/empty/degenerate index, negative offset, past-doc-end clamp,
  page-boundary start-inclusive) are correct.

**Non-blocking caveat (accepted):** the connected TTS test drives the follow seam, not live TTS
state, so it would not catch an accidental reintroduction of `pagedOffset` as an effect key. The
implementation is correct; strengthening the seam to drive production TTS state is a named
follow-up. The test comment reflects this.

## Test gate (per class, one connected class per invocation — rule 52 / MEMORY #129/#133)

- JVM `PagedTtsFollowTest` — `RUN-ANDROID-TESTS RESULT: SUCCEEDED` (9/9).
- Connected `TxtPagedBookmarkConnectedTest` — SUCCEEDED (3/3).
- Connected `TxtPagedTtsFindConnectedTest` — SUCCEEDED (4/4, incl. the no-fight test, after the fix).
- Connected `TxtPagedBilingualGateConnectedTest` — SUCCEEDED (3/3).
- No-regression: `TxtPagedBodyConnectedTest` (6/6), `TxtPagedSelectionConnectedTest` (8/8),
  `TxtPagedHighlightConnectedTest` (6/6) — all SUCCEEDED.

## Notes

- `TxtReaderActivity.kt` is 1548 lines — a plan-acknowledged pre-existing condition (the plan defers
  full decomposition to a follow-up; WI-6a already did a light extraction to `TxtReaderBody.kt`).
  This WU adds ~123 lines of chrome wiring + test seams following the established structure.
- Round-2 thread: `019f621a-a803-7731-a007-c77698496e46`.
