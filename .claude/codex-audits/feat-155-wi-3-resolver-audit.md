---
branch: feat/155-wi-3-resolver
threadId: 019fcfbd-6112-7473-aad6-d661f9ccb4e0
rounds: 4
final_verdict: follow-up-recommended
date: 2026-08-05
---

# Gate-4 audit — feature #155 WI-3 (`IncomingBookResolver` + `BookMagicSniffer`)

Adversarial security audit of code that parses **attacker-controlled bytes**: `ImportActivity`
is an exported activity, so any app on the device can hand VReader a hostile content URI.
Three rounds, `scripts/run-codex.sh -e high` (rule 53), read-only sandbox.

| Round | Thread | Verdict | Open C/H/M |
|---|---|---|---|
| 1 | `019fcf92-2d2f-77b1-a24d-5d7b6a85b3cf` | block-recommended | 0 / 2 / 3 |
| 2 | `019fcfa9-d8d9-7560-972a-7ea86aa15017` | block-recommended | 0 / 1 / 4 |
| 3 | `019fcfbd-6112-7473-aad6-d661f9ccb4e0` | block-recommended | 0 / 1 / 0 |
| 4 | orchestrator-run adjudication (gpt-5.5 / high) | **follow-up-recommended** (condition met) | 0 / 0 / 0 |

## Round 4 — orchestrator-run disposition adjudication (2026-08-05)

The lane escalated correctly rather than certifying its own disposition (rule 48). Rounds 2 and 3
had each been asked directly whether the open HIGH could be fixed inside WI-3's write-set; both said
no and both endorsed escalation. So the question put to round 4 was **not** "is the stall HIGH
fixed?" — it is accepted, not disputed — but the genuinely different question the orchestrator's
ruling raises:

> Given the gap is (1) unreachable at this HEAD and (2) tracked with WI-5 gated, is merging WI-3 as a
> foundational WI an acceptable disposition?

Scoped to three questions: reachability, whether the tracking is accurate and complete enough that a
WI-4/WI-5 implementer cannot miss it, and the disposition itself.

**Findings:**

1. **Reachability — NOT reachable, verified by call-site search, not assumption.** `IncomingBookResolver`
   and `BookMagicSniffer` appear only in their own files and comments under `android/app/src/main`;
   `ImportActivity.onCreate()` still calls `finish()` and constructs neither. The stall gap therefore
   cannot be triggered by a user or a hostile app at this HEAD.
2. **Tracking — accurate and complete.** The amended D8 block and the features row were judged to
   state the mechanism correctly and completely: unbounded synchronous provider calls, the watchdog
   sitting after resolution, the permit taken before a stream exists, the required worker/watchdog
   extension across `peek`/`resolveAndOpen`, timeout-to-outcome routing, late-result stream disposal,
   and the rejection of a resolver-local executor timeout.
3. **One NEW HIGH — an orchestrator process error, now fixed.** The audit ran against branch HEAD and
   found the D8/features/version changes **uncommitted in the working tree**: the orchestrator's
   `git commit` had been inside a compound command that the merge-gate hook aborted. Merging that HEAD
   would have landed WI-3 *without* the promised gate in the branch history a future WI dispatcher
   consumes — a tracked gap that isn't actually in the history is an untracked gap.

   > `docs/features.md:208 | HIGH | The WI-5-blocking stall gap tracking is only in the dirty working
   > tree, not branch HEAD | Commit the D8/features/version tracking change before merge.`

   **Fixed**: commit `05959d02` (plan D7/D8 + features row) and `cc541807` (version bump) are now in
   `main..HEAD`. This was the auditor's *sole* blocking condition, stated explicitly and verifiably —
   *"With the dirty tracking commit included, the disposition would be acceptable."* The verdict is
   therefore updated on a **met condition**, not on an override.

**Verdict rationale, in the auditor's own framing**: block-recommended was returned "not because the
stall HIGH is newly disputed, and not because it is reachable today; it is not reachable" — purely
because the documented orchestration action was not committed. With that condition satisfied, the
stated disposition is `follow-up-recommended`: unreachable resolver/sniffer code plus an explicit
WI-5 gate.

**The open HIGH remains open.** It is carried in plan D8 as `BLOCKS WI-5` and in the `docs/features.md`
#155 row. WI-5 is not dispatched until it is closed.

Round-3 High is the SINGLE remaining finding, and all three rounds agree it is **not fixable
inside this work item's four-file write-set**. Everything else is resolved or accepted with
rationale. Raw transcripts: `<worktree>/.reports/audit-r{1,2,3}.txt` (gitignored).

## The blocker (escalated, not patched)

**HIGH — a hostile provider can block resolution indefinitely.** `ContentResolver.query`,
`openInputStream`, `getType` and the probe read are synchronous and uninterruptible.
`withContext(Dispatchers.IO)` moves the blockage to another thread; it does not bound it, and
coroutine cancellation cannot interrupt a blocking `InputStream.read`. A batch of hostile URIs
can therefore hold every inbound permit before plan D8's coordinator watchdog ever sees an item
— D8 puts the stall watchdog in the **coordinator**, which only receives an item *after*
resolution has finished.

The auditor's own fix ("extend D8's isolated per-item worker/watchdog design across `peek` and
`resolveAndOpen`, with late-result stream disposal and timeout-to-outcome mapping") requires
`ImportActivity.kt` (WI-5), `IncomingImportCoordinator.kt` (WI-4) and a plan revision — all
outside this write-set. Rounds 2 and 3 were asked directly whether a fix fits inside
`IncomingBookResolver.kt` alone; both said no, and both explicitly confirmed the scope
judgment. Round 3: *"This confirms R2-1; it is not a defect to patch inside this write-set."*

A resolver-local executor with a timeout was considered and rejected by the auditor: it trades
a visible hang for leaked/poisoned workers, i.e. resource exhaustion or permanent import denial.

**Action for the orchestrator:** this is a cross-WI design gap in plan D6/D8, not a WI-3
implementation defect. It needs a plan amendment plus WI-4/WI-5 work before the exported entry
point ships.

## Findings fixed in-lane

| # | Sev | Finding | Fix |
|---|---|---|---|
| R1-1 | High | `withContext` DISCARDS its result if the caller is cancelled after the block completed but before delivery; the block's own catch never sees that cancellation, so the opened stream had no owner and leaked | ownership crosses the hand-off in an `AtomicReference` drained by a caller-side `finally`; round 3 confirms the publication/drain protocol is happens-before safe with no double-close, early-close or leak interleaving |
| R1-3 | Med | `markSupported()` / wrapper construction ran between the open and the ownership `try`, stranding the descriptor | the `try` starts at the open; round 2 then removed the vector entirely (below) |
| R1-4 | Med | decoder always got `endOfInput=false`, so `hello` + `C2` at real EOF sniffed as `txt` | `fill` reports FULL/EOF/ZERO; only FULL gets the boundary benefit of the doubt; a probe decoding to zero characters is rejected |
| R1-5 | Med | the 200-char cap ran after NFC + a filtering `StringBuilder` + a regex, each allocating an attacker-sized copy | leaf taken first, pre-capped at 8192 raw chars |
| R2-2 | Med | a stream can return `true` from `markSupported()` and implement `reset()` as a **successful no-op** — the sniffer would return a verdict on an advanced stream and `BookImporter` would hash only the suffix, minting a wrong canonical key | the resolver never asks the source; it **always** supplies its own `BufferedInputStream` |
| R2-3 | Med | that wrapper was 8192 bytes, so its first fill pulled 8192 bytes from the **provider** though the probe looks at 4096 | sized to exactly `PROBE_BYTES`; the budget is now asserted at the source, not at the sniffer's argument |
| R2-5 | Med | `substringAfterLast` materialised the whole attacker-sized leaf before the pre-cap applied | index-based `boundedLeaf`; only the kept prefix and extension are copied |
| R1-7 | Low | lone surrogates already present in a provider name survived | dropped while scanning; valid pairs (astral CJK) preserved |
| R1-8 / R2-6 | Low | `runCatching` swallowed `CancellationException` and JVM `Error`s | `providerCall`/`guarded` helpers rethrow cancellation and let errors propagate; `Normalizer.normalize` called directly |
| R1-9 | Low | `sniff()`'s "never throws" contract was not absolute | `markSupported()` guarded; contract narrowed in the KDoc to malformed bytes + ordinary I/O |
| R1-10 | Low | the `sourceUri` cap was a convention at one assignment site | a `PendingImport` construction invariant (`init { require(...) }`) — so WI-5 cannot re-derive it and silently discard the cap |
| R2-7 | Low | the cancellation test recorded only a boolean | exact `closeCount`, `job.isCancelled`, plus a successful-handoff control proving the delivered stream is NOT closed |

## Accepted with rationale

1. **An OCF-shaped header is a format HINT, not EPUB validation** (R1-6, per plan D7). No
   4096-byte prefix can prove a central directory exists, and the fixture's CRC is zero. The
   file header now says so, and the test fixture was renamed `validEpub()` → `ocfShapedEpub()`
   because the old name overstated what is proven. Every other step of the D3 chain already
   trusts an attacker-supplied declaration, so a false positive costs a failed open, never a
   privilege.

2. **A file of exactly `PROBE_BYTES` whose last byte starts an incomplete sequence is hinted
   `txt`** (R2-4). Round 3 agreed this is **inherent**: such a file and a longer file whose
   character crosses byte 4096 are observationally identical without reading byte 4097, and
   `available()` / declared metadata are attacker-influenced. Fixing it needs either a 4097th
   byte (weakening the read ceiling the sniffer exists to guarantee) or false negatives on
   every boundary-cut CJK text file. Round 3 agreed Low severity. Documented in the
   `BookMagicSniffer` header and pinned in both directions by
   `aFileExactlyTheProbeLengthWithATruncatedTailIsAcceptedAsText`. **Worth a one-line note in
   plan D7.**

3. **File-size guidance exceeded**: `IncomingBookResolver.kt` is 376 lines and both test files
   are over ~300. Splitting requires new files outside the four-file write-set. Suggested
   follow-up: extract the name sanitizer into its own file.

4. **Residual weak assertion** (round 3, Low): `closeCount == 1` observes the *source*, and
   `BufferedInputStream.close()` is idempotent, so it proves closure but cannot detect two
   calls to the *wrapper's* close. The cancellation race itself is real and latch-controlled.

## Mutation pass (11 mutations, all killed)

The brief's six required mutations plus five verifying the audit fixes themselves.

| # | Mutation | Killed by |
|---|---|---|
| 1 | sniff result overrides a DISPLAY_NAME extension | `aDisplayNameExtensionAlwaysBeatsAContradictingSniff` (+3) |
| 2 | drop the `mark`/`reset` rewind | `theStreamIsRewoundAfterSniffing_sha256Matches` (+25) |
| 3 | accept a DEFLATED first entry | `deflatedFirstEntryIsNull` only — the positive stayed green |
| 4 | skip the `extra len == 0` check | `nonZeroExtraLengthIsNull` — **SURVIVED at first** (see below) |
| 5 | remove U+200F from the strip set | `sanitizeStripsEachBidiControlIndividually` |
| 6 | open a second stream in `resolveAndOpen` | both counting-resolver tests |
| 7 | disable the cross-hand-off close | `aStreamIsClosedWhenTheCallerIsCancelledDuringTheDispatcherHandoff` |
| 8 | force `endOfInput=false` | `aTruncatedEncodingAtRealEofIsNotText` — **SURVIVED at first** (see below) |
| 9 | wrap outside the ownership `try` | `aStreamWhoseMarkSupportedThrowsIsClosedNotLeaked` |
| 10 | restore conditional wrapping | `aStreamThatLiesAboutMarkSupportStillYieldsTheFullBytes` |
| 11 | oversize the wrapper buffer | `theProviderIsNeverReadPastTheProbeBudgetDuringResolution` |

**Two mutations initially survived; both times the TEST was fixed, not the mutation.**

- **#4**: the fixture used a plain four-zero-byte extra field, which the *constant* content
  offset rejects anyway — so it proved nothing about the extra-length check. The fixture now
  **smuggles the media type into the extra field**, so the bytes at offset 30+8 spell
  `application/epub+zip` and only the extra-length check can reject it.
- **#8**: the truncated-EOF fixtures decoded to *nothing* and were caught by the empty-output
  rule instead. The fixtures now truncate **after valid text**, which only the end-of-input
  distinction rejects.

## Test gate

```
ANDROID_CMD="cd android && ./gradlew :app:testDebugUnitTest --tests '*imports*' --tests '*BookImporterTest*' --rerun-tasks" scripts/run-android-tests.sh
RUN-ANDROID-TESTS RESULT: SUCCEEDED
```

JUnit XML, not just `BUILD SUCCESSFUL`: **135 tests, 0 failures, 0 errors** — 34
`BookMagicSnifferTest`, 52 `IncomingBookResolverTest`, plus 21 + 9 + 17 + 1 + 1 pre-existing
in the package (no regression).
