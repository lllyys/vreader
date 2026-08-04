---
branch: feat/172-wi-1-cost-attribution
threadId: 019fcdec-8b1b-7513-894a-17d789d3b650
rounds: 3
final_verdict: block-recommended
date: 2026-08-05
---

# Gate-4 audit — feature #172 WI-1 (on-device TXT TOC scan cost attribution)

Scope: one new file, `android/app/src/androidTest/kotlin/com/vreader/app/reader/nav/TxtTocScanCostTest.kt`.
Measurement-only work item — **no production code changed** (verified by the auditor:
`git diff --name-status` over the branch shows exactly one added file).

Auditor: Codex `gpt-5.6-sol`, reasoning effort `high`, read-only sandbox, driven through
`scripts/run-codex.sh` (rule 53). Round transcripts: `.reports/audit-r1.txt`,
`.reports/audit-r2.txt`, `.reports/audit-r3.txt` (thread ids `019fcdcc-bb6d-78c1-afae-9263dfdfaf6c`,
`019fcde1-52a7-70d1-ba3f-ebc0e02530fc`, `019fcdec-8b1b-7513-894a-17d789d3b650`).

## Round 1 — `VERDICT: block-recommended` (C=0 H=2 M=5 L=2)

| # | Sev | Finding | Disposition |
| --- | --- | --- | --- |
| 1 | HIGH | Arm (h) did not decompose reset from construction: `Pattern.matcher()` resets internally and `find(int)` resets again, so an expensive reset appeared in BOTH differences and `h3 − h2` was not "construction net of reset" | **FIXED.** Added **h0a** (`K × matcher.reset(text)`) and **h0b** (`K × matcher.reset()`) — direct measurements with no matching at all — which anchor the arithmetic instead of inferring it. h0b independently corroborates `find(int) − find()` |
| 2 | HIGH | Arm (g)'s decisive ratio rested on a subtraction (raw minus an `Object`-allocation floor) with a zero clamp, least reliable in exactly the flat case that would kill H1 | **FIXED.** The reading now rests on RAW paired measurements; a **third text size** turns the bare ratio into a held-out-point check both models can fail; net figures kept only as a secondary correction |
| 3 | MED | The sink published only `identityHashCode`, not the object, so constructor initialisation was not provably observable | **FIXED.** The constructed `Matcher` itself is published to a `@Volatile Matcher?` field inside the timed loop — a real reference escape |
| 4 | MED | Adaptive expensive/cheap sizing produced asymmetric execution regimes from a noisy 32-iteration probe | **FIXED.** Replaced the 5 µs cliff with time-budget sizing (`TARGET_TIMED_NS / probe`); the probe now only chooses how many iterations are averaged |
| 5 | MED | A 200-construction timed batch could hold ~2.8 GB of native attachments before any collection — the H1-confirming case could be lowmemorykiller-ed before reporting | **FIXED.** Timed work is batched with **untimed** collections between batches, batch size derived from bytes-attached |
| 6 | MED | Controls insufficient for the strength of the conclusions; arms (c)/(d)/(e) single-shot | **FIXED.** Arms (c)/(d)/(e) each read twice; arm (a) read once in each of two methods |
| 7 | MED | Arm (a) compiles its `Regex` inside the timed region while arm (b) receives a precompiled `Pattern` | **FIXED.** The compile cost is measured and reported (`compile_ns_per_call` ≈ 39–43 µs, i.e. 0.0007 % of arm (a)) rather than hidden |
| 8 | LOW | Comment claimed internal storage survives the connected task, contradicting the class doc | **FIXED.** `connectedAndroidTest` uninstalls the app; logcat is the primary channel |
| 9 | LOW | `constructionSink != 0` cannot prove the sink was written (an `Int` sum can legitimately be zero) | **FIXED.** Replaced with a write counter plus an observed reference escape |

Confirmed sound in round 1: no latency asserted anywhere; `walkReused` faithful to
`extractHeadings`; the a/b element-level oracle and three-way counts non-vacuous; `resumePositions`
matches Kotlin's end-or-empty-`+1` rule; `countLineStarts` correct for index 0, all five Java
terminators, CRLF as one terminator, and end-of-input suppression; the fixture fails loudly and is
pinned by SHA-256 plus decoded length.

## Round 2 — `VERDICT: block-recommended` (C=0 H=1 M=5 L=0)

Every finding except the file-size one was that the file **claimed more than its design proves**.

| # | Sev | Finding | Disposition |
| --- | --- | --- | --- |
| 1 | HIGH | h0a/h0b do establish that reset is expensive, but `h2 − h1` and `h3 − h2` remain differences of separately-settled whole walks; an **exclusive** construction-vs-reset split is not established, and the negative residual is a resolution artifact, not a negative cost | **FIXED (documentation).** The KDoc now names each figure a PATH cost, describes `find_int_minus_find` as "the `find(int)` path, which h0b corroborates", documents a negative residual as "below the experiment's resolution, never a measurement", and states that an exclusive split "is NOT established here and must not be quoted from this arm" |
| 2 | MED | The three-point check tests an affine model over three sampled sizes, not Big-O in both directions; no variance estimate, no pre-registered threshold | **FIXED.** "Falsifier" downgraded to "the decisive arm"; the limits are stated in the arm's KDoc and at the constants |
| 3 | MED | Equal DURATION does not equalise JIT/GC/allocator regimes (a small input runs one batch, the book runs dozens) | **FIXED.** Stated explicitly; the fitted ns/char is labelled an order-of-magnitude slope, not a precise coefficient |
| 4 | MED | The escape assertions were circumstantial: warm-up/probe left the sink non-null, and `writesBefore` included the 200 k-iteration overhead loop | **FIXED (code).** The sink is cleared immediately before the first timed batch, so `escaped` can only be satisfied by a timed write; sink writes are sampled at the start of the timed regions and asserted **exactly** equal to the construction count |
| 5 | MED | A whole-process PSS delta shows association, not causal identity between the memory growth and the latency | **FIXED.** The KDoc now says "same path, removed by the same rewrite" and forbids upgrading it to causal identity on this evidence |
| 6 | MED | The file is over the repository's ~300-line guideline | **ACCEPTED — see the adjudication below** |

## Round 3 (FINAL — rule 47's cap) — `VERDICT: block-recommended` (C=0 H=1 M=1 L=2)

Round 3 confirmed the round-2 code changes are correct and cleared the file-size disposition. Its
findings were four places where the method-level KDoc had been corrected but a class-level or
constant-level summary was left stale — i.e. **internal contradictions**, which matter here because
the High one "could mislead WI-2".

| # | Sev | Finding | Disposition |
| --- | --- | --- | --- |
| 1 | HIGH | The class-doc summary still said arm (h) "attributes the cost to `reset()` rather than to construction", contradicting the corrected arm-(h) KDoc | **FIXED.** The summary now says arm (h) prices the PATHS a fix could remove and defers to the arm's own documentation for what it does and does not establish |
| 2 | MED | The constants KDoc still called the three-point check a "LINEARITY test" under which both O(n) and O(1) are falsifiable | **FIXED.** Reworded to the held-out-point framing with the same caveats as the arm's KDoc |
| 3 | LOW | "two orders of magnitude cheaper" overstated the h1-vs-h3 saving (actual ≈ 28×) | **FIXED.** Now states a full h1 step costs roughly 3 % of a full h3 step, read from totals rather than component differences |
| 4 | LOW | "`gcSettle` runs before every timed region" was inaccurate — the compile price and per-rule counts are not separately settled | **FIXED.** Qualified to "every timed ARM", with the two in-method diagnostics named as diagnostics no conclusion rests on |

Round 3 explicitly confirmed: the escape changes are correct (clearing `matcherSink` before the
timed batches makes `escaped` meaningful; the exact `timedWrites == count` comparison excludes
warm-up, probe and overhead writes; removing the old `>=` assertion introduces no accounting
defect); no performance budget or upper-bound latency is asserted anywhere (`totalNs > 0` is a
measurability check); the a/b element-by-element and arm-(h) offset-array equivalences are real; the
fixture fails loudly through existence, readability, SHA-256, decoded length, heading count and
winning-rule checks; only the new instrumentation file changed; and **WI-4 is not misled** — arm (d)
is correctly described as a lower-bound floor rather than the expected cost of line-start scanning.

### File-size Medium — adjudicated and accepted

The auditor was asked to rule on this explicitly and did: *"The file-size Medium is reasonably
accepted with recorded rationale: the WI permits only this test file, splitting helpers into another
file would violate its write-set, most of the size is measurement methodology demanded by prior
audits, and the 1,206-line sibling connected harness is direct precedent. It should not block."*
The file is 1,118 lines against `TxtTocAcceptanceTest.kt`'s 1,206.

## Status at the cap

All 22 findings across the three rounds have fixes applied. The **round-3 fixes are
documentation-consistency only** — four textual corrections whose exact wording the auditor
supplied; no code, no assertion, no measurement changed, and the connected suite was re-run
afterwards (5 tests, 0 failures) so the committed tree is the tested tree. What remains is a
confirming fourth round, which exceeds rule 47's three-round cap, so this is escalated to the
orchestrator per the rule rather than self-certified. The recorded verdict stays
`block-recommended`, which is the round-3 verdict, unmodified.

## Measurement outcome (the work item's actual deliverable)

Real book `黑暗血时代.txt` (14,059,220 bytes, 7,029,609 UTF-16 chars, 1,859 chapters, SHA-256
`04d60f6d…c543cfe4`), API-35 emulator `emulator-5554`, debug build.

**H1 is CONFIRMED.** `Pattern.matcher(text)` costs 1.90–2.02 ms on the 7 M-char book, 159 µs on a
512 K-char prefix and 1.19–1.20 µs on a 64-char prefix — a raw long/short ratio of 1,598–1,681×,
with the length-proportional model fitted from the outer two points predicting the held-out middle
point to within 4.7–9.9 % and a fitted marginal cost of 0.271–0.287 ns/char, reproducible across two
reversed rounds. The constant-cost model is excluded by three orders of magnitude.

The shipped walk costs 6,508 ms; the same scan with one reused `Matcher` and no-arg `find()` costs
60–62 ms and returns all 1,859 headings with an element-for-element identical `(title, offset)`
sequence. Arm (d) shows layer 2's floor (65–75 ms) is **worse** than layer 1's achieved result.
