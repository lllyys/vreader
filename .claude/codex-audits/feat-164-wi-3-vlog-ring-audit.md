---
branch: feat/164-wi-3-vlog-ring
threadId: 019fcf1e-ee13-7a13-ac87-67573bb65122
rounds: 3
final_verdict: block-recommended
date: 2026-08-05
---

# Gate-4 audit — feature #164 WI-3 (VLog + ring buffer + composite source)

Auditor: Codex `gpt-5.6-sol` via `scripts/run-codex.sh` (rule 53), read-only sandbox.
Round transcripts: `.reports/audit-r1.txt`, `.reports/audit-r2.txt`, `.reports/audit-r3.txt`.

| Round | threadId | Findings | Verdict |
| --- | --- | --- | --- |
| 1 | `019fcf08-bc6d-7d40-8be2-60b930989c12` | C0 **H1** M2 L1 | block-recommended |
| 2 | `019fcf12-a720-7f20-b935-1ca94fe19606` | C0 **H1** M3 L1 | block-recommended |
| 3 | `019fcf1e-ee13-7a13-ac87-67573bb65122` | C0 **H1** M2 L1 | block-recommended |

**Status: escalated at the 3-round cap (rule 47 Gate 4).** Every round's findings were
addressed — fixed, or explicitly accepted with rationale below — and all gates are green, but
round 3's fixes have had no independent review and the standing verdict is `block-recommended`.
The orchestrator decides: accept the two documented residuals, or requeue for a 4th round.

## Round 1

**HIGH — sequence ids collided across process launches.** `VLog`'s counter restarted at 1 every
launch while logd deliberately retains prior-launch entries, so the current process's first ids
were the previous launch's first ids. `CompositeDiagnosticsSource` prefers the ring on an id
collision, so it dropped exactly the pre-crash breadcrumbs the platform log exists to provide —
on *every* launch. FIXED: the id is now `nonce | counter` (21 random per-launch bits + a 42-bit
counter), still a positive `Long` that WI-1's `«v(\d+)»` marker regex parses unchanged.
Regression tests `idsFromTwoLaunchesWithDistinctNoncesDoNotCollide` and
`aPriorLaunchLogcatEntryIsNotDroppedByTheCurrentLaunchsRing`; both verified RED against a bare
counter.

**MEDIUM — the containment gate had four one-line evasions.** It keyed on call *shapes*, so
`import android.util.Log as PlatformLog`, `import android.util.*`, a qualified call split across
lines, and `Class.forName("android.util.Log")` all passed; `.java` sources and non-`main` source
sets were never scanned. FIXED: the gate bans the *name* rather than the shapes, and scans `.kt`
+ `.java` across source sets. Fixtures added for each evasion.

**MEDIUM — the ring concurrency test did not establish an overlapping read.** FIXED (twice — see
round 2).

**LOW — `VLogTest.kt` exceeds ~300 lines and hosts a second test class.** ACCEPTED: WI-3's
write-set allots exactly three test files while owning `DiagnosticsCategoryBounding.kt`, whose
acceptance bullet sits in WI-4 (which cannot write this file). The alternative was shipping the
source untested. Splitting it out is a one-line follow-up for whoever holds a wider write-set.

## Round 2

**HIGH — `install()` published the nonce and the counter reset as two independent writes.** An
`emit` could read the old nonce, be descheduled across `install()`, then increment the
freshly-reset counter into `oldNonce|1` — a duplicate of an id the old generation had already
issued. FIXED: nonce and counter became one immutable object swapped atomically; round 3 widened
that to include `sink` and `clock` (see below).

**MEDIUM — the gate's comment stripping was not syntax-aware.** `/** doc */ val p =
android.util.Log.WARN` was skipped whole (line began with a block comment) and
`"https://x".length + android.util.Log.WARN` was cut at a `//` inside a string literal. FIXED
with an awk state machine tracking multi-line block comments, inline spans, and `//` only outside
a string.

**MEDIUM — the gate scanned only `android/app/src`.** FIXED: the whole `android/` tree, so
`:identity` and any future module are covered; `build/` output pruned; non-shipped source sets
matched as the segment directly beneath a module rather than as a loose substring.

**MEDIUM — the concurrency test proved only that a read saw an incomplete buffer.** FIXED: it now
counts *distinct* intermediate snapshot sizes and requires 10, which only interleaved reads
produce. The first attempt at that assertion FAILED honestly — a cold reader's first `runBlocking`
snapshot costs more than the whole write burst, so it always sampled after the writers finished;
the reader now warms up on the empty ring and releases the writers only once it is looping hot.

**LOW — a blank category vanished from the chip row.** `chipFor` returned `null`, contradicting
the documented rule that everything uncategorised collapses into one *filterable* bucket, and
`LogcatLineParser` legitimately yields `""` for a tagless line. FIXED: blank buckets like any
other unknown tag.

## Round 3

**HIGH — duplicate ids remain representable across concurrent `install()` calls.** Two parts.
The part that is a real defect — `sink`, `clock` and the generation were three independent writes,
so a concurrent emit could pair a new counter with the old sink — is FIXED: all four are now one
immutable `Installation` published through a single `AtomicReference`, and `emit` takes one
snapshot of it. The other part (two installs sharing a nonce yield the same ids) is the
probabilistic residual accepted below.

**MEDIUM — the lexer was not Kotlin-raw-string aware.** `val x = """ " // raw text """` left the
machine mid-string, so the `//` on the next construct read as a comment and hid a reference.
FIXED: a persistent `"""` raw-string state plus char-literal handling; fixtures `RawString.kt` and
`CharLiteral.kt`.

**MEDIUM — the concurrency test remains scheduler-dependent.** PARTLY FIXED, PARTLY ACCEPTED. The
strand path is closed (`start.await()` moved inside `try`/`finally` for both reader and writers).
The proposed remedy — phased writer/reader milestones — is what the *previous* revision did and
what this same auditor rejected in round 2 as proving less, so re-adopting it would just
oscillate. The design is validated empirically instead: with `synchronized` removed the test fails
**4 runs out of 4**; with it restored it passes **5 runs out of 5**. The residual failure mode is a
loud assertion failure, never a vacuous pass. The suggested performance concern is refuted by
measurement: the test runs in **33 ms**.

**LOW — trailing slash on the scan root broke the relative-path strip.** FIXED (`${1%/}`), with a
self-test asserting an identical finding set either way.

## Explicitly accepted residuals

1. **Nonce repeat, ~1 in 2^21 per launch pair.** Eliminating it needs durable state — a counter or
   epoch persisted to disk and read at start-up — which puts an I/O dependency and a failure mode
   inside a logging facade. The loss on a repeat is bounded: a handful of prior-launch logcat
   entries whose counters overlap the current ring's are deduped away. Strictly better than the
   pre-fix behavior, where that happened every launch. Recorded in `VLog.kt`'s KDoc.
2. **A runtime-assembled class name** (`Class.forName("android." + "util.Log")`) is invisible to
   any textual gate. The gate stops accidental drift and honest reintroduction; it is not an
   adversarial sandbox. Catching this needs bytecode or dependency analysis — out of scope for
   WI-3. Recorded in the script header.
3. **`VLogTest.kt` size / second test class** — write-set constraint, see round 1.

## Verification

- `RUN-ANDROID-TESTS RESULT: SUCCEEDED` — 213 tests, 0 failures, 0 errors (JUnit XML, not the
  `BUILD SUCCESSFUL` line): the three new WI-3 suites plus WI-1/WI-2's, plus the JVM suites of
  every migrated file (`BookShareIntentTest`, `SearchIndexCoordinatorTest`,
  `FoliateBridgePolicyTest`).
- `scripts/__tests__/check-android-log-containment.sh` → `ALL PASS` (23 self-test assertions incl.
  9 evasion fixtures and 3 false-positive fixtures; the real `android/` tree scans clean).

### Mutation testing (every claim below was run, not reasoned)

| Mutation | Expected | Observed |
| --- | --- | --- |
| Remove the `android.util.Log` forward from `VLog.emit` | forwarding tests red, ring tests green | 8 forwarding tests RED; all 15 ring tests and every ring-side `VLogTest` case GREEN |
| Dedupe on `(time, category, message)` instead of the sequence id | look-alike-survival tests red | 3 RED incl. `twoDistinctEntriesWithByteIdenticalTextAndTimestampBothSurvive` |
| Disable dedupe entirely | "appears exactly once" red | 3 RED incl. `anEventPresentInBothSourcesAppearsExactlyOnce` |
| Drop the launch nonce (bare counter) | cross-launch tests red | 2 RED: `idsFromTwoLaunchesWithDistinctNoncesDoNotCollide`, `aPriorLaunchLogcatEntryIsNotDroppedByTheCurrentLaunchsRing` |
| Remove `synchronized` from the ring | concurrency test red | RED 4/4 runs (`ArrayIndexOutOfBoundsException` from a concurrently-growing `ArrayDeque`) |
| Reintroduce a short-form `Log.w(` into `PdfDocument.kt` | containment gate fails | `PdfDocument.kt:103` reported, `FAIL — production sources still reference android.util.Log` |
