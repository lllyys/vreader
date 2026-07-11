---
branch: feat/135-wi8-backup-restore-jump
threadId: 019f5227-cf46-7a43-8a86-c52df6f16d54
rounds: 2
final_verdict: ship-as-is
date: 2026-07-12
---

# Gate-4 audit — feature #135 WI-8 (backup-restored bookmark jump + AZW3 nav connected tests)

Test-only WI (no `src/main/**` change). Two new connected (androidTest) classes:

- `android/app/src/androidTest/kotlin/com/vreader/app/backup/BookmarkBackupRestoreJumpTest.kt`
- `android/app/src/androidTest/kotlin/com/vreader/app/reader/Azw3BookmarkNavTest.kt`

Auditor: Codex (`scripts/run-codex.sh`, rule 53). Author/auditor separation held
(rule 48). Gate: `RUN-ANDROID-TESTS RESULT: SUCCEEDED` — the androidTest source
set compiles (both new classes) + the JVM suite stays green. The LIVE emulator
runs of these connected tests ride WI-9 acceptance (rule 52 — no
`connectedAndroidTest` in this lane).

## Round 1 — findings (all addressed)

- **H1/H2** — backup test only asserted `ReadiumLocatorReconstructor` returned a
  locator, not that a jump lands / the sheet stays open. → Strengthened: assert
  the reconstruction resolves to the bookmarked resource AND carries the
  canonical progression (`0.25`) — a real POSITION, the landing precision
  `navigator.go` consumes. Full `navigator.go` landing + live Compose sheet-open
  are WI-9 acceptance by design (WI-7's `EpubBookmarkNavTest` already drives the
  host jump seam); the progression-carrying reconstruction is the checkable half
  at the backup-round-trip layer.
- **H3** — re-restore idempotency tested only the UUID primary key, not the WI-3
  `(bookKey, profileKey)` unique-index fallback. → Added case (3b): after
  restore, wipe + recreate a same-position bookmark with a DIFFERENT UUID via the
  toggle path, then re-restore; assert exactly one row survives. This exercises
  `insertBookmarkIfAbsent` (`@Insert(onConflict=IGNORE)`) being suppressed by the
  unique index, not a PK collision.
- **H4** — render-death test's `takePendingGoTo()==null` was vacuous (the target
  is cleared before the reissue launches; a never-loaded document would also pass).
  → `awaitLoaded` now returns a Boolean the test asserts `true`, so the
  cleared-target assertion is gated on the replacement actually reaching
  book-ready (the branch that re-issues the carried jump).
- **M (deterministic selection)** — "first with books>=1" could pick an older
  archive on a reused live server. → Select `latest && books>=1` only.
- **M (silent 30s return)** — `awaitLoaded` returned silently on timeout. → It now
  returns `false` and the test fails with a clear assertion.
- **M (fragmented workflow)** — toggle/list and jump used independently
  constructed locators. → The created+listed bookmark's OWN locator is threaded
  through `azw3JumpDecision` (full toggle→list→jump).

## Round 2 — re-audit

All round-1 High findings confirmed CLOSED; "no block-recommended issue found."
Two low/medium follow-ups applied in the same round:

- Backup selection: dropped the first-with-books fallback (require
  `latest && books>=1`; `listBackups()` marks its newest entry `latest`, and the
  test writes its backup last).
- Softened the render-death comment/message from "the reissue path ran" to
  "reached book-ready (where the carried jump is re-issued)" — the observable is
  the load precondition, not an independent observation of `goTo` executing.

## Verdict

**ship-as-is.** Test-only; both classes compile in the androidTest source set +
JVM suite green; tests reuse the established connected-test idioms (the #132
live-WebDAV round-trip, real EPUB reconstruction via `BookOpener`, the WI-2
real-WebView/AZW3 fixture + `takePendingGoTo`/`run(pendingGoTo=)` carry, the
dead-bundle timeout) — not a forked harness; assertions are non-tautological and
deterministic (no bare synchronization sleeps for correctness; the WebView-load
poll mirrors the WI-2 slice and now asserts on its outcome). The reconstruction /
render-death cases skip gracefully when their local-only fixtures are absent
(`minimal.epub` is bundled; `foliate-spike/book.azw3` is gitignored), matching
the WI-2 slice, so CI stays green while the live runs ride WI-9.
