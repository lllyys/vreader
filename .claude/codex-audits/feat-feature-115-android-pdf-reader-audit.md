---
branch: feat/feature-115-android-pdf-reader
threadId: 019ee3f0-2bb8-7a90-8c21-b677463be1d1
rounds: 2
final_verdict: ship-as-is
date: 2026-06-20
---

# Gate-4 implementation audit — feature #115 WI-1 (PdfDocument + page cache)

Codex (`scripts/run-codex.sh`, gpt-5.5, read-only) audited the `PdfRenderer` wrapper:
`PdfDocument.kt`, the `VReaderApp` `cachePage`/`cachedPage` addition, `PdfDocumentTest.kt`, and
the synthetic PDF fixtures.

## Round 1 — 1 Medium + 1 Low

| file:line | severity | issue | resolution |
|---|---|---|---|
| `PdfDocument.kt` pageCount | **Medium** | `pageCount` read `renderer.pageCount` directly (unserialized; would use a closed renderer after `close()`) | **Fixed**: `pageCount` captured once at open time + stored as a `val` constructor param. |
| `PdfDocumentTest.kt` | Low | the close-during-render test was mostly a smoke test (the `started` signal fires before the render enters the mutex) | **Addressed** (renamed + rationale, see round 2). |

Clean (round 1): `renderPage`/`close` share one `Mutex` on the injected dispatcher; `closed`
checked under the lock; `Page.close()` in `finally`; `open()` maps every failure + closes the
`ParcelFileDescriptor` on each branch (no fd leak); bitmap handling correct (ARGB_8888, white
erase, aspect height + `coerceAtLeast(1)`, caller-owns KDoc); `cachePage` correctly separated
from `cacheOffset`, `ConcurrentHashMap`.

## Round 2 — Medium resolved; the residual Low ACCEPTED WITH RATIONALE

Round 2 confirmed the Medium fixed and found **no new Critical/High/Medium**. It restated the
Low: the test doesn't *deterministically* prove close waits behind an in-flight render, and
suggested a render-critical-path test probe.

**Decision (accepted, not fixed):** a test probe inside the serialized production critical path
couples production code to the test for a marginal determinism gain — declined per clean-code
conventions (rule 50). The test was **renamed** to `close_isSafeUnderConcurrentRenders_andIdempotent`
so it no longer overclaims: it proves the real invariant — `close()` never throws / corrupts the
renderer **for all interleavings** (win-first or wait-behind) and is idempotent — under a busy
40-render contended loop. The exact ordering is **structurally guaranteed** by both `renderPage`
and `close` sharing one `Mutex`; that structure is the proof, the test is the safety net.

## Verdict

**ship-as-is** (zero open Critical/High/Medium). 5 instrumented `PdfDocumentTest` green on
emulator-5554 + the full `:app` unit suite green. Foundational WI (the `PdfRenderer` wrapper +
page cache) — its device-only behavior is instrumented-verified.
