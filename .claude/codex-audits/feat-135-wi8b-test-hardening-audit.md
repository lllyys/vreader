---
branch: feat/135-wi8b-test-hardening
threadId: 019f5252-1420-7f72-b0a2-0acd9dec0895
rounds: 2
final_verdict: ship-as-is
date: 2026-07-12
---

# Gate-4 audit — feature #135 WI-8b (bookmark connected-test hardening, TEST-ONLY)

Independent Codex audit (rule 53, `scripts/run-codex.sh`) of the three
androidTest-only fixes a Gate-5 real-emulator acceptance run surfaced. No
production code changed.

## Scope of the diff (`origin/main..HEAD`)

Three instrumentation-test files only:

- `android/app/src/androidTest/kotlin/com/vreader/app/reader/chrome/BookmarkToggleButtonTest.kt`
- `android/app/src/androidTest/kotlin/com/vreader/app/reader/Azw3BookmarkNavTest.kt`
- `android/app/src/androidTest/kotlin/com/vreader/app/reader/TxtPdfBookmarkTest.kt`

## The three fixes audited

1. **BookmarkToggleButtonTest.contentDescription_flipsWithState** — was calling
   `compose.setContent {}` TWICE (the #134 `IllegalStateException: has already
   set content` class the connected run catches but compile/JVM do not).
   Reworked to a single `setContent` driving a hoisted `mutableStateOf`
   bookmarked flag; flips the flag via `runOnIdle` + `waitForIdle`, then asserts
   the a11y content-description flips `Add bookmark` → `Remove bookmark` on the
   same live node (and the old label is gone via
   `onAllNodesWithContentDescription(...).assertCountEquals(0)`). A genuine
   state-driven flip on one node, not two static snapshots. The other 5 tests in
   the class are unchanged.

2. **Azw3BookmarkNavTest.toggleAtAzw3Position_createsThenRemoves_oneRowPerPosition**
   — was toggling a bookmark against a synthetic `bookKey`
   (`Locator("a".repeat(64), 2048, "azw3").fingerprintKey`) without seeding the
   parent `BookEntity`, so the `bookmarks.bookKey -> books.fingerprintKey` FK
   (in-memory Room enforces FKs) aborted `insertBookmarkIfAbsent` with a
   `SQLiteConstraintException` before any create/remove assertion could run. Now
   seeds a `BookEntity` carrying the same synthetic identity triple
   (`fingerprintKey = bookKey`, `contentSHA256 = "a"*64`, `fileByteCount = 2048`,
   `originalFormat = "azw3"`) via `db.bookDao().upsert(...)` (the exact
   `AnnotationDaoTest` seeding pattern) so the AZW3 repository toggle path
   (Added → one row, Removed → zero, same-position-different-UUID → one) actually
   runs and asserts. The other 4 AZW3 tests are unchanged.

3. **TxtPdfBookmarkTest** — covered only TXT despite its name. Added
   `pdfHost_rendersTopBarBookmarkToggle` (render assertion, mirroring the TXT
   method) and `pdfHost_topBarToggle_createsBookmarkRow_atCurrentPage` (render →
   real top-bar toggle click → deadline-bounded repository poll confirming the
   created row at the current-page canonical + the host's jump-decision function
   `pdfBookmarkPageTarget` asserted in-range vs out-of-range). Uses the synthetic
   `sample-3page.pdf` (feature #115 fixture) — the documented "no real PDF today"
   real-books-first exception. The existing TXT method is unchanged. No new asset
   was needed (the fixture already ships).

## Findings

**Round 1** (`.reports/wi8b-audit.txt`): all four requested checks passed except
one follow-up + one minor:
- (follow-up) the PDF jump assertion called the pure `pdfBookmarkPageTarget`
  helper directly rather than the host's `onJumpBookmark`.
- (minor) the poll used `return@repeat`, which does not break the loop — a
  success still ran all 40 iterations (~8s wasted).

**Round-1 fixes applied**:
- The poll is now a deadline-bounded `while` loop that breaks on first success.
- The jump-decision assertion is framed accurately: `PdfReaderActivity`'s
  `onJumpBookmark` is an inline `setContent` lambda that delegates its ENTIRE
  decision (in-range page → scroll + `Succeeded`; out-of-range → `Failed`,
  sheet stays open — rule 51) to the pure `pdfBookmarkPageTarget`. The host
  exposes NO `@VisibleForTesting` jump seam, and adding one is a forbidden
  production change — so the test exercises that same decision function directly.
  The row-tap UI jump rides WI-9 acceptance.

**Round 2** (`.reports/wi8b-audit-r2.txt`): **ship-as-is — no blocking or
follow-up findings.** Confirmed: single `setContent` + real flip; AZW3 seeds the
`BookEntity` so the toggle path runs; PDF render toggle + create-seam +
jump-decision coverage correct and deterministic; only the three connected-test
files changed relative to `origin/main`; no production code changed; no other
existing test method altered.

## Gate

`RUN-ANDROID-TESTS RESULT: SUCCEEDED` — androidTest source set compiles
(`:app:compileDebugAndroidTestKotlin`) + JVM unit suite green
(`:app:testDebugUnitTest`). The live re-run of the three affected suites on the
real emulator is the orchestrator's Gate-5 finalize (this lane compiles only —
rule 52 emulator contention).
