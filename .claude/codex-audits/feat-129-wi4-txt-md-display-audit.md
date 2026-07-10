---
branch: feat/129-wi4-txt-md-display
threadId: 019f4e37-8c4f-7b83-ac18-2a280b345849
rounds: 3
final_verdict: follow-up-recommended
---

# Gate-4 audit — feature #129 WI-4 (Android reader Display-settings → TXT/MD reader)

Scope: `origin/main..HEAD` — apply the WI-1 `ReaderSettings` live to the TXT/MD
reader (`TxtReaderActivity`): `bodyTextStyle` (size / lineHeight = size×spacing /
serif|sans family / theme ink), theme background on the scaffold, margin
contentPadding; MD inherits the base size via the shared host with em-relative
heading `SpanStyle`s; the WI-3 `ReaderBottomChrome` shell is wired (scrubber +
Display slot + reconciled read-aloud slot) and opens the WI-2
`ReaderSettingsSheet`.

Auditor: Codex via `scripts/run-codex.sh` (rule 53), 3 rounds. Session
`019f4e37-8c4f-7b83-ac18-2a280b345849`. Raw round logs: `.reports/wi4-audit-r1.txt`,
`.reports/wi4-audit-r2.txt`, `.reports/wi4-audit-r3.txt`.

## Round 1 — verdict BLOCK-RECOMMENDED

No Critical. Two High + several Medium/Low findings, all on the Display-settings
write path.

- **H1 — Activity-owned `settingsWrites` Channel is per-Activity but consumed on
  process-wide `appScope`.** On rotation the old Activity's channel keeps draining
  while the replacement starts a SECOND consumer → the two can commit slider edits
  out of order and restore a stale value.
- **H2 — the lone channel consumer dies permanently if any store setter throws**
  (unbounded channel, `trySend` results ignored), silently stranding queued edits.
- Mediums/Lows: empty-document scrubbing (`chunkForOffset(0)` on a 0-chunk doc),
  a brief pre-emission Paper-theme scaffold flash, file size (>750 lines), test
  coverage of the new concurrency risk areas, `bodyTextStyle` assuming clamped
  inputs.

**Resolution (commit `a3f98ed5`):** removed the Activity-owned channel entirely
and moved write serialization into `ReaderSettingsStore` — one process-wide
`writeMutex` (the store is a container singleton, so it orders every setter across
a reader, its rotation replacement, and a second reader). Setters reverted to a
direct `appScope.launch`. `withLock` is exception-safe → H2 fully closed (a
throwing/cancelled setter releases the lock, can never wedge a queue). Added two
`ReaderSettingsStoreTest` concurrency tests (no-torn-state across different-field
writes; valid-committed-value on a same-field burst).

## Round 2 — verdict BLOCK-RECOMMENDED

Confirmed **H2 resolved**, no deadlock/lock-order inversion, `DataStore.edit`
under the Mutex is atomic, cancellation releases the lock. **H1 only partly
resolved:** a bare Kotlin `Mutex` gives mutual exclusion but NOT FIFO acquisition,
so an older slider value could still win the lock last and commit stale — the
"submission order == commit order" claim was incorrect. Recommended: monotonic
sequence numbers + drop stale same-field writes.

**Resolution (commit `910c6d9e`):** added a monotonic submission sequence
(`AtomicLong`) + a per-field committed-sequence high-water map; inside the lock a
same-field write is DROPPED when a newer sequence already committed →
latest-submission-wins regardless of lock-acquisition order. This also retires the
Medium "obsolete intermediate value gets applied." Added a latest-wins store test.

## Round 3 (final) — verdict BLOCK-RECOMMENDED, then resolved

No new Critical/High/Medium. The auditor precisely noted the sequence was stamped
at the coroutine's ENTRY (`incrementAndGet()` inside the setter body), which still
inherits the multi-threaded dispatcher's (unordered) coroutine-start order — a
later UI event whose `launch` happens to start first receives a lower sequence and
loses. The drop logic itself, the `HashMap` confined under the Mutex, and per-field
independence were all confirmed correct.

**Resolution (commit `e95d91a4`):** the sequence is now stamped SYNCHRONOUSLY at
the caller's true submission point — `store.nextSeq()` is called on the main thread
in the sheet's slider callback, in edit order, and passed into the setter as
`order`. Latest-wins therefore reflects the user's real edit order, immune to how
the fire-and-forget launches are scheduled. Sequential callers (tests) keep an
entry-time default. Deterministic tests prove the drop path with INVERTED execution
order (`staleSameFieldWrite_isDropped_evenWhenItRunsLast`) and per-field
independence (`perFieldHighWater_isIndependent_...`).

## Final state (round cap reached)

- **H1: resolved** — synchronous main-thread sequence stamp + per-field drop-if-
  stale under one process-wide write Mutex; verified by deterministic JVM tests and
  a green connected re-render run.
- **H2 + deadlock/consumer-death: resolved.**
- All prior Mediums that were correctness concerns are resolved (obsolete-value
  application closed by the drop; torn state closed by the Mutex).

### Accepted follow-ups (Low, non-blocking — none introduced by WI-4)

- **File size** — `TxtReaderActivity.kt` was already ~730 lines pre-WI-4; a split
  (reader composable / body / chrome) is a separate refactor, out of WI-4 scope.
- **Empty-document scrubbing** — `chunkForOffset(0)` on a zero-chunk doc is
  pre-existing WI-1/2/3 behavior; the scrub is already `coerceIn`-guarded. Out of
  WI-4's "apply settings" scope; a scrubber-hardening follow-up.
- **Pre-emission scaffold theme** — a brief Paper-background window before the
  DataStore's first emission (the body is already gated). Cosmetic Low; kept
  consistent with the existing designed theme system rather than adding a second
  neutral surface.
- **Unbounded launch-per-slider-event under pathologically slow DataStore I/O** —
  the correctness half (stale value winning) is closed by the drop; only a resource
  concern remains, Low in practice (a gesture fires a bounded number of events,
  DataStore writes are fast). A debounced StateFlow intent model would need the
  merged WI-2 sheet, so it is a named follow-up.

## Gates

- JVM: `RUN-ANDROID-TESTS RESULT: SUCCEEDED` —
  `:app:testDebugUnitTest --tests '*ReaderSettingsStoreTest' --tests '*TxtDisplaySettingsTest'`
  (ReaderSettingsStoreTest 9/9, TxtDisplaySettingsTest 7/7).
- Connected: `RUN-ANDROID-TESTS RESULT: SUCCEEDED` —
  `:app:connectedDebugAndroidTest ...class=TxtDisplaySettingsUiTest` (3/3 on
  emulator-5554), re-run after each audit-driven code change.
