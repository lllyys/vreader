---
branch: feat/feature-111-wi3-txt-resume
threadId: 019ee0-wi3-txt-2rounds
rounds: 2
final_verdict: ship-as-is
date: 2026-06-19
---

# Gate-4 audit — feature #111 WI-3 (Android TXT reader resume, final WI)

WI-3 adds resume to the TXT reader via the LEGACY locator path (NOT the Readium
bridge): `load` computes the initial scroll index from `loadPosition → ResumeResolver
→ Canonical → chunkForOffset`; the top-visible chunk's `charOffsetUTF16` is saved as a
`VReaderLocator.wrapLegacy` envelope (debounced via `snapshotFlow` + an `onStop` flush).

Codex (gpt-5.4, high), 2 rounds.

## Round 1 — 1 High (block-recommended)

| file | sev | issue | resolution |
|---|---|---|---|
| TxtReaderActivity | **High** | the debounced save and the `onStop` flush each launched an INDEPENDENT `appScope` job → nondeterministic save order; an older debounced save could land after the final flush and regress the position. | All writes funnel through one `Channel<PendingSave>(CONFLATED)` drained by a SINGLE consumer (launched once in `onCreate` on `appScope`); `savePosition` only `trySend`s. Saves are serialized + latest-wins; `onDestroy` closes the channel (the final buffered save is still drained; post-close `trySend` drops safely). |

Auditor confirmed everything else sound: `TxtDocument` offset round-trip, the
`SideEffect` refreshing the flush capture, `drop(1)` avoiding an immediate re-save,
null/path fail-safety, memory profile.

## Round 2 — High resolved; 1 narrow new finding (follow-up-recommended)

| file | sev | issue | resolution |
|---|---|---|---|
| TxtReaderActivity / VReaderApp | Low/Medium | on a FAST rotation/reopen, the new instance's `computeInitialIndex` reads Room before the prior instance's async `onStop` flush commits → could restore a slightly stale offset. | Added a process-level in-memory offset cache (`AppContainer.cacheOffset`/`cachedOffset`, `ConcurrentHashMap`): `savePosition` caches synchronously; `computeInitialIndex` reads the cache FIRST, falling back to durable Room (across process death). Round-2 verdict confirmed the round-1 conflated-channel fix is correct (per the Kotlin CONFLATED/close/trySend docs). |

## Validation

- `scripts/run-android-tests.sh :app:testDebugUnitTest` → SUCCEEDED (49 unit tests
  incl. `TxtResumeTest` — the TXT legacy envelope round-trips the repo + resolves
  `Canonical`).
- `scripts/run-android-verify.sh` (`:app:connectedDebugAndroidTest`) on emulator-5554
  → SUCCEEDED; 6 instrumented tests incl. `resumesToSavedCharOffset` (seed a position
  at line 080's offset → reopen lands there, line 001 not visible), 0 failures.

## Verdict

**ship-as-is.** The round-1 High (out-of-order saves) fixed with a serialized
conflated-channel writer; the round-2 fast-reopen staleness fixed with an in-memory
offset cache. Resume is emulator-verified.
