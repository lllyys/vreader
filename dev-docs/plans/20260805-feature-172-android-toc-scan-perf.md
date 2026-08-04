# Feature #172 — Android TXT TOC scan performance (real-book budget)

**Status**: Gate 1 draft v1 → Gate 2 audit pending
**Row**: `docs/features.md` line 224 (`| 172|`) · **GH**: #2043
**Blocks**: feature #139 reaching `VERIFIED` (row stays `DONE` until this lands)
**Parent plan**: `dev-docs/plans/20260804-feature-139-android-txt-md-toc.md` (§5 is the decision this feature reopens)
**Platform**: `android-app` (rule 40 → bumps `android/version.properties`, tags `android/vX.Y.Z`)

---

## 1. Problem

Feature #139's Gate-5b acceptance run on the **real** 14 MB CJK book
(`test-books/books/txt/黑暗血时代.txt`, 7 029 609 UTF-16 chars, 254 109 lines, 1 859 chapters) fails
the parent plan's §5 gate 1 by a factor of ~5:

| Measurement (emulator-5554) | Observed | Stated budget |
| --- | --- | --- |
| Quiet whole-document scan | **8 300 ms** (lane) / **11 449 ms** (orchestrator re-run) | 1 500 ms |
| Contended scan (pagination running) | **7 479 ms** / **7 324 ms** | 1 500 ms |
| Detection only (512 KB sample, 14 rules) | ~**103 ms** | — |
| Implied extraction (residual) | ~**8 200 ms** | — |
| Direct extraction measurements (earlier runs) | 7 630 / 7 840 / 6 604 ms | — |

Independently reproduced twice, so it is not a flake. It is **steady state, not warm-up** (the warm
runs are the same order), so caching compiled `Pattern`s cannot help.

The corresponding desktop-JVM measurement in the parent plan's Appendix A.1 is **22–23 ms** for the
identical extraction over the identical file
(`dev-docs/plans/20260804-feature-139-android-txt-md-toc.md:1509-1520`). The device is therefore
**~350× slower than the desktop JVM on the extraction path**, while being only **~4× slower on the
detection path** (desktop 24 ms → device ~103 ms for the same 14 rules over the same 512 KB sample).

**Those two ratios are the whole problem.** The same regex engine, the same rules, the same kind of
work — one path is 4× slower on device, the other is 350×. No uniform "ART is slower than HotSpot"
explanation can produce both. Something on the extraction path scales with a quantity that the
detection path barely exercises. §4 identifies what, and that identification — not a guessed
optimisation — is what this feature is built on.

**Why it escaped every earlier gate.** §5's "do not persist in v1" decision rested on the desktop
number (`…-139-…md:665-685`), with an explicitly stated caveat that it was not a substitute for the
emulator measurement. Every WI before WI-8, including WI-7's connected tests, used small generated
fixtures. Only the real book could show this — which is precisely what AGENTS.md's "real books
first" rule exists for, and it worked: the gate fired.

### What is NOT broken

The **blocking primary gate passes**: open-to-first-page is **47 ms quiet / 7 ms with a concurrent
scan** against a `< 2 000 ms` target (`TxtTocAcceptanceTest.kt:857-916`). #138's windowed pagination
is intact and nothing regressed. Also passing: exactly 1 859 chapters with the expected first/last
titles, nested MD depths 0–3, and a headings-free document correctly hiding the Contents control.
This feature must keep all of that true.

### Acceptance (restated from the row, unchanged)

Plan §5 gates **1 and 3** pass on the real 14 MB CJK book using the **already-committed**
`android/app/src/androidTest/kotlin/com/vreader/app/reader/TxtTocAcceptanceTest.kt`, with the
**1 500 ms budget asserted, not loosened**, and gate 2 (open-to-first-page) not regressed.

> **Binding constraint, stated once and honoured throughout this plan**: `SCAN_BUDGET_MS = 1_500`
> (`TxtTocAcceptanceTest.kt:215`) is **not** to be relaxed, and no assertion in
> `TxtTocAcceptanceTest`, `TxtTocRuleEngineTest`, `TxtTocRulesTest`, `TxtMdTocProviderTest`,
> `TxtTocIndexTest` or `TxtTocConnectedTest` is to be weakened, re-scoped, or `@Ignore`d. The
> acceptance suite is the oracle; this plan's job is to make it pass as written. Any WI that
> proposes editing an assertion in those files has failed and must escalate instead.

---

## 2. Rule-51 confirmation — no UI, no visible delta

**This feature adds no UI surface whatsoever.** It changes how `TxtTocRuleEngine` walks matches over
a `String`. There is no new screen, sheet, row, control, indicator, empty state, or visual state; the
Contents sheet, its rows, its highlight and its show/hide rule are all untouched, and every file in
the write-set is either a non-UI Kotlin object or a test. The only user-perceptible change is that an
existing, already-designed Contents sheet appears sooner. That is rule 51's explicit
"pure code changes with no visible delta" out-of-scope category. **No design bundle is required and
no `needs-design` issue is owed.**

---

## 3. Prior art, project precedent, and rejected alternatives

### 3.1 The parent plan's own §5 — the precedent that failed, and how

`…-139-…md:704-718` rejected Room persistence with: *"Trading a schema migration and two known bug
classes for ~100 ms of gated background work is a bad deal at v1. Measure first (WI-8), then persist
if — and only if — the measurement demands it."* The reasoning was sound; the **input** was a
desktop-JVM number used to predict device cost. This plan's governing lesson is therefore:

> **Do not choose an optimisation from a cost model that has not been measured on the target.**
> Every quantitative claim below is labelled either MEASURED-ON-DEVICE, MEASURED-ON-DESKTOP, or
> PREDICTED — and no WI ships a production change on a PREDICTED number alone.

### 3.2 Appendix A.2 `HeadScan.java` — read in full, and what it actually exploits

The parent plan's cross-validation probe (`dev-docs/benchmarks/feature-139/HeadScan.java`, reproduced
at `…-139-…md:1522-1571`) finds the same headings in **6–13 ms on desktop**. Read closely, it does
three distinct things, and only one of them is safely transferable:

1. **It enumerates line starts once** into an `int[]`, then iterates lines rather than characters
   (`HeadScan.java:12-19`). Transferable and provably safe — see §5.2.
2. **It tests one character** after skipping `[space, tab, U+3000]`, rejecting the line unless it is
   `第` or `#` (`HeadScan.java:26-27`). Transferable only with a *correctly derived* character set —
   `{第, #}` is **not** correct for rule 1, which also matches `序章|楔子|正文|终章|后记|尾声|番外`.
3. **It re-implements the match inside a bounded 64-char line window** (`HeadScan.java:28-34`). **Not
   transferable.** It is a different algorithm with different results — it reports **1860**, not
   1859 (`…-139-…md:1570-1577`), and it is structurally incapable of the cross-terminator match the
   shipped engine documents and pins by test (`TxtTocRuleEngine.kt:15-19`, `:40-45`): because
   `TxtTocRules.WS` widens whitespace to ICU's `\s`, which **contains line terminators**, rule 1
   genuinely matches `第\n一\n章 标题`. A line-window matcher drops that heading. The parent plan
   already rejected this approach as the shipping algorithm for exactly this reason (§3.4).

**So the honest reading of A.2 is narrower than "6–13 ms proves a prefix scan is the answer".** Its
6–13 ms is the cost of (1) + (2) + a *non-equivalent* (3). Against the desktop regex extraction's
22–23 ms, the whole hand-rolled scanner is only **~2–3.5× faster than the regex on the same
machine** — not the 100×+ that closing a 5.5× budget gap on device would want, if the device
slowdown were uniform. Under a uniform-slowdown model, a prefix-filtered scan on device would land
at ~2 300–3 800 ms and **still miss the budget**. That model is almost certainly wrong (§4), but it
is the model the "prefix filter is the bigger lever" hypothesis implicitly assumes, and on its own
terms the hypothesis does not close the gap.

### 3.3 Why Room persistence (parent follow-up F1) is not the primary fix

Correct on the merits, and the row already says so: persistence amortises **repeat** opens, while the
**first** open of any large TXT book still pays the full cost — and the first open is the case a user
hits when they add a book. A user who imports a 14 MB novel and waits 8 s for its Contents has been
failed by an 8 s scan whether or not the second open is instant. Persistence also costs a Room
entity + DAO + migration, a `TOC_HEURISTIC_VERSION` invalidation key, and a stale-read failure class
with two shipped-bug precedents on iOS (`…-139-…md:704-718`).

**Disposition**: persistence stays a *last-resort* contingency (follow-up F1, §7), reachable only if §5's whole
chain fails to reach the budget. It is not rejected on principle — it is sequenced last because it
does not fix the case that matters and costs the most.

### 3.4 Alternatives considered and rejected

| Alternative | Verdict |
| --- | --- |
| **Relax the 1 500 ms budget** | **Prohibited** by the row and by this plan's §1. A budget that moves to meet the implementation is not a gate. |
| **Cache compiled `Pattern`s** | Rejected — the row's own evidence: the cost is steady-state across warm runs, and detection already compiles all 14 rules for ~103 ms total. |
| **Reuse the search FTS index** | Rejected in the parent plan §3.4 and still wrong here: the FTS index is a different tokenisation with no heading semantics, and it is populated asynchronously. |
| **Parallel decomposition (split the text across cores)** | Rejected as a *primary* fix. It cannot be made exactly equivalent without care (a match may cross any split point — the same cross-terminator property that kills line-window matching), it multiplies memory pressure on a device already being lowmemorykiller-ed, and it is a constant-factor win (≤ core count) against a 5.5× gap. Re-considerable only if §5's chain lands within ~2× of budget. |
| **RE2/`com.google.re2j` linear-time matching** | Rejected. It is a new third-party dependency (the Android app has none for text), RE2 rejects lookarounds — and rules 1, 2 and 7 all use them (`(?!完\|结)`, `(?!课)`, `(?![合和])`, `(?![分赛游])`, `(?!张)`, `TxtTocRules.kt:101-153`) — so the ported rules would have to be rewritten, which is a correctness divergence from iOS, not an optimisation. |
| **Rewrite the rules to be cheaper** | Rejected. AGENTS.md/#139's binding constraint is to port iOS's heuristics, not invent new ones; the parent plan already withdrew one invented heuristic (divergence D4) after four audit rounds. The rules are correct; the *walk over them* is what is slow. |
| **Scan lazily / progressively (populate the Contents sheet as it fills)** | Rejected for v1. It is a visible-behaviour change (a Contents list that grows while you look at it) on a designed surface → rule 51 would require a design. It also does not make the scan cheaper, only later. |

---

## 4. Root cause: the leading hypothesis, its arithmetic, and what is still unverified

### 4.1 A verified fact about the extraction walk

`TxtTocRuleEngine.extractHeadings` walks matches with Kotlin's `Regex` idiom
(`TxtTocRuleEngine.kt:142`, `:155`):

```kotlin
var match = regex.find(text)          // :142
while (match != null) { … ; match = match.next() }   // :155
```

`countMatches` uses the same idiom (`TxtTocRuleEngine.kt:188`, `:195`).

**Verified by disassembling the exact stdlib this app builds against** (kotlin-stdlib **2.3.20**, the
version pinned at `android/build.gradle.kts:9`; jar at
`~/.gradle/caches/modules-2/files-2.1/org.jetbrains.kotlin/kotlin-stdlib/2.3.20/…`), the bytecode of
`kotlin.text.MatcherMatchResult.next()` is:

```
54: invokevirtual  // Method java/util/regex/Matcher.pattern:()Ljava/util/regex/Pattern;
61: invokevirtual  // Method java/util/regex/Pattern.matcher:(Ljava/lang/CharSequence;)Ljava/util/regex/Matcher;
75: invokestatic   // Method kotlin/text/RegexKt.access$findNext:(Ljava/util/regex/Matcher;ILjava/lang/CharSequence;)Lkotlin/text/MatchResult;
```

**Every call to `MatchResult.next()` constructs a brand-new `java.util.regex.Matcher` over the entire
7 029 609-char input.** This is not an inference from source I might be misremembering — it is the
compiled shape of the library on this machine. (It is a deliberate stdlib design choice: it keeps
each `MatchResult` independently valid after `next()`.)

So the real book's extraction constructs **1 859 Matchers over a 14 MB string**, and detection
constructs one per match found across all 14 rules over the 512 KB sample.

### 4.2 The hypothesis

> **H1 — `Matcher` construction is O(text length) on Android and O(1) on the desktop JVM.**
> On the desktop JVM (OpenJDK), `Pattern.matcher(CharSequence)` stores a reference and allocates
> two small `int[]`s — constant time, independent of input size. If Android's `java.util.regex` is
> backed by a native engine (as it historically has been), constructing a `Matcher` — or the
> `reset()` inside it — must hand the input to the native side, which is **O(n) per construction**.

H1 predicts the exact pair of ratios in §1, which is what makes it the leading hypothesis rather
than a guess:

| | Matchers constructed | × input size | Total char-work under H1 |
| --- | --- | --- | --- |
| Detection | ~14 + total matches over the sample (best rule alone contributes 171) → order 300–500 | 524 288 | ~1.6–2.6 × 10⁸ |
| Extraction | 1 859 | 7 029 609 | **1.31 × 10¹⁰** |

Ratio extraction : detection ≈ **50–83×**. Applying that to the MEASURED-ON-DEVICE detection cost of
~103 ms predicts extraction at **~5 100–8 500 ms**. The MEASURED-ON-DEVICE extraction cost is
**6 604–8 200 ms**. The prediction lands inside the observed range, and the only free parameter is
"how many matches the 14 rules found in the sample", which is bounded and knowable.

Under the alternative model (no per-Matcher O(n) cost), extraction is a single linear pass over the
text and should cost detection's ~4× device factor applied to desktop's 22 ms ≈ **~90 ms**. That is
off by ~90× from what was measured, and nothing else in the code scales with anything that could
absorb the difference.

**H1 also explains the second anomaly, which no other hypothesis does.** The row records RSS reaching
**1.4–1.9 GB while the Java heap stayed at 19–34 MB**, with the lowmemorykiller taking the app
mid-class. A pure-Java cost model has no explanation for that at all — a Java-side leak would show up
in the Java heap, and it did not. H1 explains it precisely: 1 859 native attachments of a 14 MB
buffer is ~26 GB of native allocation traffic, and native allocations owned by Java objects are
reclaimed on **Java** GC — which barely runs when the Java heap is flat at 20 MB. RSS at 1.4–1.9 GB
corresponds to roughly 100–135 undisposed 14 MB buffers, i.e. exactly what "GC reclaims them in
occasional batches" looks like.

**Two independent anomalies — a 350×/4× time split and large native growth under a flat Java heap —
explained by one mechanism, with arithmetic that matches to within its stated uncertainty.** That is
the strongest evidence available without touching the device.

### 4.3 What is NOT verified, and how WI-1 settles it

- **Whether Android's `java.util.regex` is native-backed on API 36.** I could not verify this
  locally: the SDK at `/opt/homebrew/share/android-commandlinetools` has no `sources/` component
  installed, and `platforms/android-36/android.jar` carries stubs only. AOSP has moved this package
  between implementations historically, so memory is not evidence. **WI-1 settles it on-device in
  three lines** (below).
- **The count of matches detection finds across all 14 rules.** Only rule 1's 171 is recorded.
  WI-1 logs the rest, which tightens H1's predicted ratio from a range to a number.
- **Per-pass memory magnitude.** The row is explicit that this was never isolated. WI-1 isolates it.

**What actually falsifies H1 — a direct construction-cost arm, not a semantics probe.** H1 is a claim
about *cost*, so it must be measured as cost. WI-1 therefore isolates the two operations the two
walks differ in:

- **arm (g)** — construct `pattern.matcher(text)` N times over the 7 M-char text and do **no
  matching at all**. If construction is O(1), the per-construction cost is flat regardless of text
  size; if it is O(n), it scales with the text and H1 is confirmed. The arm is run against the 7 M-char
  text **and** against a deliberately short string, and it is the **ratio of the two slopes**, not
  either absolute number, that is read.

  > **The result must not be elidable** (Gate-2 R2 HIGH). A constructed `Matcher` that is never used
  > can be dead-code-eliminated or scalar-replaced by ART's JIT, which would report a spuriously
  > flat cost and **falsely kill H1** — the exact wrong outcome, since it would send a correct fix
  > back to planning. Every constructed `Matcher` must therefore escape to a non-elidable sink: a
  > `@Volatile` field, or an accumulator over `System.identityHashCode(m)`, written before the timer
  > stops and logged afterwards so the compiler cannot prove it dead. The sink must not perform any
  > *match* operation, or the arm stops isolating construction. Both text-size slopes are reported
  > from that non-elidable arm; an arm without a proven sink is not evidence and its result is
  > discarded.
- **arm (h)** — the same total number of matches walked two ways on one text: a reused `Matcher`
  with no-arg `find()`, versus `find(start)` on a freshly constructed `Matcher` each time. This
  separates "constructing a `Matcher` is expensive" from "`find(int)`'s `reset()` is expensive" —
  two different defects with two different fixes, which arms (a)/(b) alone would conflate.

Arm (g) is the falsifier: if it is flat, H1 is dead and WI-2 does not ship on a prediction.

**A separate, cheap semantics probe, logged rather than gated** (also WI-1): the parent plan's
divergences D1/D1b assert that Android's `\d` and `\s` are ASCII-only (`TxtTocRules.kt:41-64`), but
those assertions are pinned **only by JVM unit tests** (`TxtTocRulesTest.kt:296`, `:356`, `:361`),
which run on the desktop JVM and therefore say nothing about the device engine. Recording on-device
whether `Pattern.compile("第\\d+章").matcher("第１２章").find()` and
`Pattern.compile("第\\s一").matcher("第　一").find()` are `false` confirms a #139 port-fidelity claim
that currently rests on desktop evidence. It is **target-semantic logging**, and it is deliberately
*not* claimed to identify the engine implementation: character-class semantics are a weak proxy for
"is this native-backed", and arm (g) answers the cost question directly without needing to know.

### 4.4 The fix H1 implies

Walk the matches with **one reused `java.util.regex.Matcher`**:

```kotlin
val matcher = pattern.matcher(text)     // ONE construction for the whole scan
while (matcher.find()) { … }            // continues from the previous match's end
```

This is semantically identical to the Kotlin idiom, and the equivalence is exact rather than
approximate (§5.1). Under H1 it turns 1 859 O(n) constructions into 1, collapsing 1.31 × 10¹⁰
char-operations to 7.03 × 10⁶ — a predicted extraction cost of **~90–350 ms**, against a 1 500 ms
budget, and it removes the native-allocation churn that the RSS signal tracks. Under ¬H1 it is still
strictly better (1 858 fewer allocations) but would not close the gap — which is why WI-1 measures
before WI-2 ships, and why §5.2/§5.3 specify the contingencies in full **now** rather than inventing
them later under pressure.

### 4.5 Disposition of the memory signal (the row's "secondary, not overclaimed")

**In scope, as a measured output of WI-1 — not as a separate follow-up, and not as a claim.** H1
makes the memory growth and the latency the *same* defect, so isolating it costs one extra pair of
samples per benchmark arm rather than a separate investigation. WI-1 records, per arm, the Java heap
delta and the process PSS delta across a single extraction pass on the real book, with a forced
collection and settle before each sample (the idiom already used at
`TxtTocAcceptanceTest.kt:667-671`). The decision rule is stated in advance so the outcome cannot be
rationalised after the fact:

- If the reused-`Matcher` arm shows **materially lower** process growth than the baseline arm →
  same root cause, closed by WI-2, recorded in the WI-3 evidence file. No follow-up needed.
- If both arms show comparable growth → the growth is **not** the scan; file a separate bug row
  against whatever the WI-1 arms implicate (the paginator and the Compose text measurement are the
  standing suspects, since #138's own index covers 30 695 pages), and note it in the evidence file.
  This plan does not chase it further.
- If the measurement is too noisy to distinguish (single-sample PSS across runs already varied
  267→381 MB and 259→1439 MB per `TxtTocAcceptanceTest.kt:659-666`) → report exactly that, claim
  nothing, and file the isolation as a follow-up with the observed noise floor recorded.

---

## 5. Design

Three layers, each independently correct, sequenced so that **each is only built if the measured
result of the previous one demands it**. Layer 1 is the primary fix; layers 2 and 3 are fully
specified here so that, if triggered, they are executed from an audited design rather than invented
mid-implementation.

### 5.1 Layer 1 (primary) — one `Matcher` per scan

**Change**, entirely inside `TxtTocRuleEngine.kt`:

- `compile(rule)` returns `java.util.regex.Pattern?` instead of `Regex?`
  (`Pattern.compile(rule.pattern, Pattern.MULTILINE)`), still returning `null` on
  `PatternSyntaxException` — iOS's `try?` behaviour, unchanged (`TxtTocRuleEngine.kt:200-205`).
  `RegexOption.MULTILINE` **is** `Pattern.MULTILINE`; no flag semantics change.
- `extractHeadings` obtains one `Matcher` and loops on `matcher.find()`; the title becomes
  `matcher.group().trim()` (identical to `match.value.trim()`) and the offset `matcher.start()`
  (identical to `match.range.first`).
- `countMatches` does the same.
- **Everything else is untouched**: the cancellation cadence (one `ensureActive()` at entry, one
  before each detection rule, one every `CANCELLATION_CHECK_INTERVAL` matches examined, one final
  check after the loop), the empty-title drop, the `limit` early-return that stops the scan rather
  than truncating a materialised list, `sampleOf`'s surrogate-safe truncation, and the file's
  documented invariants.

**Why the match sequence is exactly identical** — the one claim the whole layer rests on:

- Kotlin's `next()` resumes at `end + (if (end == start) 1 else 0)` then calls `find(from)`.
- `java.util.regex.Matcher.find()` (no-arg) resumes at `last`, incrementing by one when the previous
  match was empty — **the same rule**.
- `find(int)` additionally calls `reset()`, which clears region, append position and `hitEnd` state.
  None of those are used here: no region is ever set, no append is performed, and the patterns are
  matched against the full text with default bounds. So the reset is unobservable.
- The `Pattern` is the same object with the same flags, so the matches themselves are the same.

This is an argument, and arguments have been wrong in this feature before. It is therefore **pinned
by a differential-oracle unit test** (§7 T-2a) that runs the old Kotlin walk and the new `Matcher`
walk over an adversarial corpus and asserts element-for-element equality of `(title, offset)` — the
same technique #139 WI-5 used for `txtTocIndexFor` (commit `24451540`).

**Correctness surface: none.** No pattern changes, no rule changes, no candidate is skipped, no
window is bounded. This is the entire reason it is layer 1.

**Risk of layer 1 being insufficient**: if ¬H1, the win is small. That is what WI-1 measures first.

### 5.2 Layer 2 (contingency) — line-start anchored scanning

**Trigger**: WI-3's re-measurement misses 1 500 ms after layer 1.

**Theorem (safe candidate set).** *Every match of every rule in `TxtTocRules.defaults` begins at a
Java-multiline line start.*

*Proof.* All 25 patterns begin with `INDENT = "^[ 　\t]{0,4}"` — verified by reading every entry
at `TxtTocRules.kt:96-304`; rules 6, 21, 22, 23 spell it `${INDENT}` for Kotlin-identifier reasons
(`TxtTocRules.kt:143-145`), which is the same string. `^` is zero-width, so the match start is the
position at which `^` succeeded. Under `MULTILINE` with default bounds, Java's `^` succeeds at index
0, or immediately after a line terminator (`\n`, `\r`, ``, ` `, ` `), **except**
between the `\r` and `\n` of a CRLF pair, and **never** at end-of-input. ∎

So the scan may attempt a match at line starts only, and skip every other position. Implementation:

- Enumerate line starts once into an `IntArray` (254 109 entries ≈ 1 MB for the real book, transient).
  The terminator set and the CRLF and end-of-input rules must match Java's `^` **exactly** — this is
  the layer's only real hazard, and it is what the tests target.
- For each line start `s` in ascending order, attempt an anchored match at `s`
  (`matcher.region(s, text.length)` + `useTransparentBounds(true)` + `useAnchoringBounds(false)` +
  `lookingAt()`), so `^`/`$`/`.` still see the surrounding text and the match tail is **not**
  truncated by the region end — preserving the documented cross-terminator match
  (`TxtTocRuleEngine.kt:15-19`) and any unbounded numeral run.
- After a match ending at `e`, advance the line-start cursor to the first line start `≥ e`. This
  reproduces `find()`'s resume-at-previous-end rule; positions strictly between `e` and that line
  start cannot match by the theorem.

**Expected win**: eliminates ~6.78 M failed `^` attempts out of 7.03 M positions. If the residual
cost is dominated by the per-position walk, this is large; if it is dominated by per-line work, it is
small. WI-1's arm (d) measures the line-enumeration floor so the ceiling on this layer's win is known
before it is built.

**Cost**: exact-equivalence reasoning that a future reader must re-derive, plus a hand-rolled
replication of Java's line-terminator semantics. Not free — hence contingent.

### 5.3 Layer 3 (contingency) — mechanically-derived first-character pre-filter

**Trigger**: layer 2 lands and still misses 1 500 ms.

**This is the layer the row hypothesised as the primary fix. It is placed last because it is the only
layer with a real correctness surface, and because §3.2 shows its measured desktop advantage over the
regex is ~2–3.5×, not the 100×+ the gap would need under a uniform-slowdown model.**

**Answer to "is a prefix pre-filter provably safe for all 14 enabled rules?" — see §9.1. Short form:
line-start anchoring is provably safe; a first-character filter is safe only if its character set is
derived mechanically, and a hand-written set is exactly where a silent regression would hide.**

**Design.** The set that matters is a property of the rule's **body** — the pattern with its shared
`INDENT` prefix removed — not of the whole pattern. Define `BODY(R)` = `R.pattern` with the leading
literal `TxtTocRules.INDENT` string stripped, and `FIRST(R)` = the set of code points that can begin
a match of `BODY(R)`. The filter at a line start is:

1. `run` = length of the leading run of `[space, U+3000, tab]` (the literal `INDENT` class, **not**
   `WS`).
2. `c` = the code point at `lineStart + min(run, 4)`.
3. Accept the line iff `c ∈ FIRST(R)`, **or** (`run > 0` and `FIRST(R)` contains any of
   `[space, U+3000, tab]`).

Clause 3 is what keeps it sound when the rule's **own** `WS{0,4}` absorbs indentation beyond
`INDENT`'s cap of 4 — e.g. rule 2 matches `"␣␣␣␣␣␣1、题"` (six spaces: `INDENT` takes 4,
`[第（\(]?` matches empty, `WS{0,4}` takes 2), so a space must be treated as viable *for rule 2*.

> **The body/whole-pattern distinction is load-bearing, not pedantry** (Gate-2 R1 MEDIUM). If
> `FIRST` were derived from the **whole** pattern, `INDENT` itself would make space, U+3000 and tab
> viable for **every** rule, clause 3 would fire on every indented line for every rule, and the
> filter would be **sound but completely inert**. That is not a hypothetical on this corpus: the real
> book indents every line — body text *and* headings — with two U+3000 characters (its first heading
> is `　　第一章　太阳消失`, parent plan `…-139-…md:1515`), so `run > 0` holds for essentially all
> 254 109 lines and a whole-pattern derivation would reject nothing at all on the one document this
> feature exists to fix. Derived from the **body**, rule 1's `FIRST` is `{序 楔 正 终 后 尾 番 第}`,
> which contains no whitespace, so clause 3 does not fire for rule 1, `c` is the first real character
> after the U+3000 indent, and prose lines are rejected. Three WI-5 tests assert exactly this:
> **SELECTIVITY-STRUCTURAL** (a rule's `FIRST` contains an indent character *if and only if* its
> body can begin with `WS` — on the current rule set that is rule id 2 alone, independently verified
> rule-by-rule in Gate-2 round 3), **SELECTIVITY-RATE** (exact integer bounds over a committed
> deterministic fixture), and **SELECTIVITY-REAL** (the real book, measured on the connected lane
> where that fixture actually exists).

**`FIRST` must be derived mechanically, not written by hand.** The proposed derivation uses
`java.util.regex`'s own partial-match signal against `BODY(R)`: for a candidate code point `cp`, run
the compiled body against the one-code-point string; if `lookingAt()` is `false` **and** `hitEnd()`
is `false`, then the failure did not depend on running out of input, so no longer string beginning
with `cp` can match the body, and `cp` is safely excluded. `hitEnd() == true` (or a match) means
"viable" → accept → run the real regex. **False positives are free; only false negatives are
correctness bugs, and `hitEnd() == false` is precisely the guarantee that excludes them.**

Stripping the prefix is exact rather than heuristic: all 25 patterns begin with the identical literal
`INDENT` string (`TxtTocRules.kt:96-304`, verified), so the operation is
`pattern.removePrefix(TxtTocRules.INDENT)` with a **fail-open** branch — if the prefix is not
present (a rule was edited, a rule was added), no filter is built for that rule and the scan runs
unfiltered.

Rather than sweeping all of Unicode at startup, the predicate is **memoised per distinct code point
encountered** (a real Chinese novel has a few thousand distinct line-initial code points), so the
probe cost is bounded by the document's alphabet, not by Unicode's size, and the derivation is
**rule-agnostic** — enabling rule 15/16/17 later, or editing a pattern, cannot invalidate it, because
nothing is hard-coded.

**Two hazards, both named and both testable:**

- **Surrogates.** The probe and the lookup must key on the **code point**, not the code unit. A
  lone/unpaired surrogate fails open (accept).
- **`hitEnd()` fidelity on the device engine.** The whole derivation rests on `hitEnd()`'s contract.
  On the desktop JVM this is well-trodden; on the device engine it is unverified — and if §4.3's
  probe shows a native-backed engine, `hitEnd()` may be a shim. **Mitigation**: layer 3 ships behind
  a self-validating gate — at construction the filter checks its own derived set against a bounded
  witness corpus generated from the rule's own grammar, and **falls open (no filter, scan
  everything)** on any disagreement. This is bounded *coverage*, not a decision procedure and not a
  proof; its value is that an unsound derivation degrades to a slow scan instead of a lost chapter.

**Explicitly rejected within layer 3**: re-implementing the match inside a bounded line window
(HeadScan step 3, §3.2). It is not equivalent, it drops cross-terminator matches, and it produced a
different count (1860 vs 1859) in the parent plan's own probe.

### 5.4 Layer 4 (last resort) — Room persistence

**Trigger**: layers 1–3 land and the budget is still missed. Design deferred to that point rather
than half-specified now, because at that point the measured residual dictates the shape (whether the
first open needs a progressive path at all). Its known cost and failure classes are in §3.3.

---

## 6. Surface area

### 6.1 Modified files

| File | Change | Layer |
| --- | --- | --- |
| `android/app/src/main/kotlin/com/vreader/app/reader/nav/TxtTocRuleEngine.kt` | `compile` → `Pattern?`; `extractHeadings` + `countMatches` walk one reused `Matcher`; file-header `Key decisions` updated (rule 22) to record *why* the walk is hand-written rather than `Regex.find()/next()` — otherwise a future reader "simplifies" it straight back | 1 |
| same | line-start index + anchored `lookingAt()` scanning | 2 (contingent) |
| same, or a new `TxtTocPrefilter.kt` in the same package | mechanically-derived first-character predicate + self-validating fail-open gate | 3 (contingent) |

### 6.2 New files

| File | Contents |
| --- | --- |
| `android/app/src/androidTest/kotlin/com/vreader/app/reader/nav/TxtTocScanCostTest.kt` | WI-1's on-device measurement harness: the arms, the engine probe, the per-arm memory sampling, and a cross-arm result-equality assertion |
| `android/app/src/test/kotlin/com/vreader/app/reader/nav/TxtTocEngineWalkEquivalenceTest.kt` | the JVM differential oracle for §5.1 (and §5.2/§5.3 if triggered) |
| `dev-docs/verification/feature-172-<YYYYMMDD>.md` | WI-3's Gate-5 evidence file (schema: `dev-docs/verification/SCHEMA.md`) |
| `android/app/src/main/kotlin/com/vreader/app/reader/nav/TxtTocPrefilter.kt` | WI-5 only — the body-relative mechanically-derived first-character predicate + its fail-open self-validation gate |
| `android/app/src/test/kotlin/com/vreader/app/reader/nav/TxtTocPrefilterTest.kt` | WI-5 only — the witness sweep, reject-side BMP coverage, the three selectivity tests, and the fail-open test |
| `android/app/src/test/resources/prefilter-cjk-sample.txt` | WI-5 only — the committed deterministic selectivity fixture (10 000 U+3000-indented CJK lines, exactly 100 rule-1 headings), so the JVM selectivity assertion is an exact integer bound rather than a statistical one |

### 6.3 Files explicitly OUT of scope

- **`TxtTocRules.kt`** — no rule, pattern, id, `enabled` flag, `INDENT`, `WS` or `DIGIT` changes.
  The rules are a verified 1:1 iOS port and are not this feature's problem.
- **`TxtTocAcceptanceTest.kt`, `TxtTocConnectedTest.kt`, `TxtTocRuleEngineTest.kt`,
  `TxtTocRulesTest.kt`, `TxtMdTocProviderTest.kt`, `TxtTocIndexTest.kt`** — these are the oracle.
  Not edited, not weakened, not re-scoped. (WI-1 *adds* a new file; it does not touch these.)
- **`TxtMdTocProvider.kt`** — the provider's policy (detect → extract with `cap + 1`, reject rather
  than truncate, the injected-dispatcher hop) is unchanged. Layer 1 is entirely below it.
- **`MdTocScanner.kt`** — verified not to use the `Regex.find()/next()` walk at all: it uses `Regex`
  only for two YAML front-matter line tests (`MdTocScanner.kt:74`, `:77`) and scans line by line.
  The MD path is not implicated and is not touched. (If WI-1 shows otherwise, that is a new row.)
- **`reader/paged/*`, `TxtDocument.kt`, `TxtDecoder.kt`** — no pagination or decoding change. Gate 2
  (open-to-first-page) must be *preserved*, which means not touching this.
- **Room (`data/AppDatabase.kt`, DAOs, migrations)** — untouched unless layer 4 triggers.
- **`contracts/`** — no contract change. Offsets, `Locator` and `TocEntry` are unchanged, so no
  cross-platform parity surface moves.
- **iOS (`vreader/`, `vreaderTests/`, `project.yml`, `*.xcodeproj`)** — rule 48 cross-platform write
  isolation. iOS's `TXTTocRuleEngine` has a different runtime and a persistent cache; nothing here
  applies to it.
- **`docs/features.md`, `docs/bugs.md`, `docs/architecture.md`, `README.md`** — orchestrator-owned
  (rule 55). No architecture-doc trigger fires: no new service, schema, notification, environment key
  or user-visible feature (rule 24) — this changes the internals of an already-documented one.

---

## 7. Work-item sequencing

Five WIs; **two are conditional** and are only dispatched if the named measured trigger fires.
Room persistence is a triggered follow-up (F1), not a WI — see the end of this section.
Tiers per rule 47 Gate 5.

### WI-1 — On-device cost attribution + engine probe (foundational)

Measure before changing anything. This is the WI whose absence caused #139's §5 to be wrong.

The harness runs on the real book and reports, per arm, wall-clock plus Java-heap and process-PSS
deltas around a single pass:

| Arm | What it isolates |
| --- | --- |
| (a) `TxtTocRuleEngine.extractHeadings` as shipped | the baseline (`Regex.find()/next()`) |
| (b) same `Pattern`, one reused `Matcher`, same title/offset/limit logic | layer 1's predicted win |
| (c) `matcher.find()` counting only, no `group()`/`trim()`/list building | separates the match walk from allocation |
| (d) line-start enumeration alone over the same text | layer 2's floor (its best possible outcome) |
| (e) `detectBestRule` as shipped, logging per-rule match counts | tightens H1's predicted ratio to a number |
| **(g)** N × `pattern.matcher(text)` construction, **no matching**, over the 7 M-char text AND over a short string | **the H1 falsifier** — is `Matcher` construction O(n) or O(1) on the target? |
| **(h)** the same match count walked two ways: reused `Matcher` + no-arg `find()` vs a fresh `Matcher` + `find(start)` | separates "construction is expensive" from "`find(int)`'s `reset()` is expensive" — arms (a)/(b) alone conflate them |
| (f) target-semantic logging (§4.3): `\d` vs `第１２章`, `\s` vs `第　一` | records whether D1/D1b hold on the target; **not** an engine-identity claim |

Assertions are **equivalence**, never budgets: arms (a), (b) and (c) must agree on the match count
(1 859), and (a) and (b) must agree element-for-element on `(title, offset)`. No latency assertion —
a benchmark that gates on a number it was written to discover is not evidence.

**The harness is built to falsify, not to confirm.** Arm (g) is capable of returning a flat result,
which kills H1 and sends WI-2 back to planning; arm (h) is capable of attributing the cost to
`reset()` instead of construction, which would change WI-2's fix. Both outcomes are named in advance
so neither can be explained away afterwards.

```yaml
id: feat:#172/WI-1
tier: foundational
depends: []
writes:
  - android/app/src/androidTest/kotlin/com/vreader/app/reader/nav/TxtTocScanCostTest.kt
tests:
  - android/app/src/androidTest/.../TxtTocScanCostTest#armsAgreeOnHeadings
  - android/app/src/androidTest/.../TxtTocScanCostTest#reportsCostAttribution
  - android/app/src/androidTest/.../TxtTocScanCostTest#reportsMatcherConstructionCost   # arm (g), the H1 falsifier
  - android/app/src/androidTest/.../TxtTocScanCostTest#reportsConstructionVsResetSplit   # arm (h)
  - android/app/src/androidTest/.../TxtTocScanCostTest#logsTargetRegexSemantics          # arm (f)
gate: ANDROID_SERIAL=emulator-5554 ANDROID_CMD="./gradlew :app:connectedDebugAndroidTest --rerun-tasks -Pandroid.testInstrumentationRunnerArguments.class=com.vreader.app.reader.nav.TxtTocScanCostTest" scripts/run-android-tests.sh
acceptance: >
  Every arm's numbers are recorded in the WI's HANDOFF notes and carried into this plan's
  Revision history. Arms (a)/(b)/(c) agree on 1859 headings and (a)/(b) agree element-for-element.
  Arm (g) reports per-construction cost at BOTH text sizes, so O(n)-vs-O(1) is read off directly;
  arm (h) attributes the cost to construction or to reset(); arm (f)'s two booleans are logged.
  The measurement DECIDES WI-2's shape: if arm (g) is flat, H1 is FALSIFIED and WI-2 is re-planned
  (escalate to a plan amendment) rather than shipped on a prediction; if arm (h) attributes the
  cost to reset() instead, WI-2's fix changes accordingly.
notes: >
  Measurement-only; no production change, so rule 10's RED->GREEN does not apply — this WI IS the
  test. Fixtures must be re-pushed (the connected task wipes /sdcard/Android/data/<pkg>/ at run end).
  Run this class alone; never drive the emulator while it runs (rule 52 Cause D).
bump_tier: patch
```

### WI-2 — One `Matcher` per scan (foundational)

```yaml
id: feat:#172/WI-2
tier: foundational
depends: [feat:#172/WI-1]
writes:
  - android/app/src/main/kotlin/com/vreader/app/reader/nav/TxtTocRuleEngine.kt
  - android/app/src/test/kotlin/com/vreader/app/reader/nav/TxtTocEngineWalkEquivalenceTest.kt
  - android/app/src/androidTest/kotlin/com/vreader/app/reader/nav/TxtTocScanCostTest.kt
tests:
  - RED  (connected): TxtTocScanCostTest#extractionMeetsEngineBudget  # asserts extractHeadings on the
                                                                      # real book within an engine-level
                                                                      # budget derived from WI-1's arm (b);
                                                                      # fails on the pre-WI-2 engine
  - GREEN (jvm): TxtTocEngineWalkEquivalenceTest  (differential oracle, adversarial corpus)
  - REGRESSION (jvm, unmodified): TxtTocRuleEngineTest, TxtTocRulesTest, TxtMdTocProviderTest, TxtTocIndexTest, MdTocScannerTest
gate:
  # BOTH commands are the WI-2 gate. The JVM command alone would NOT execute the declared RED,
  # which is a connected test — a gate that cannot run its own RED is not a gate (Gate-2 R1 HIGH).
  - ANDROID_CMD="./gradlew :app:testDebugUnitTest --rerun-tasks --tests '*TxtToc*' --tests '*MdTocScanner*'" scripts/run-android-tests.sh
  - ANDROID_SERIAL=emulator-5554 ANDROID_CMD="./gradlew :app:connectedDebugAndroidTest --rerun-tasks -Pandroid.testInstrumentationRunnerArguments.class=com.vreader.app.reader.nav.TxtTocScanCostTest" scripts/run-android-tests.sh
acceptance: >
  The connected RED (extractionMeetsEngineBudget) is RED on the pre-WI-2 engine and GREEN after —
  demonstrated by running it once before the production change and once after, both recorded;
  extractHeadings and countMatches construct exactly ONE Matcher per scan; the emitted
  (title, offset) sequence is byte-identical to the pre-change walk on every corpus document;
  cancellation cadence, the empty-title drop, the limit early-return and sampleOf are unchanged;
  all five existing suites pass UNMODIFIED.
notes: >
  The differential oracle passes both before and after by construction — it is a regression guard,
  not the RED. The RED is the connected engine-budget assertion, which is red on the shipped engine.
  The file header's Key decisions block MUST record why the walk is hand-written (rule 22), or a
  future cleanup reverts this fix.
bump_tier: patch
```

### WI-3 — Gate-5 acceptance re-measurement + evidence (behavioral)

```yaml
id: feat:#172/WI-3
tier: behavioral
depends: [feat:#172/WI-2]
writes:
  - dev-docs/verification/feature-172-<YYYYMMDD>.md
tests:
  - android/app/src/androidTest/.../TxtTocAcceptanceTest  (all six methods, UNMODIFIED)
gate: ANDROID_SERIAL=emulator-5554 ANDROID_CMD="./gradlew :app:connectedDebugAndroidTest --rerun-tasks -Pandroid.testInstrumentationRunnerArguments.class=com.vreader.app.reader.TxtTocAcceptanceTest" scripts/run-android-tests.sh
acceptance: >
  §5 gate 1 (quiet AND contended) passes at the STATED 1500 ms; §5 gate 3 (evidence recorded with
  contention conditions named) satisfied; §5 gate 2 (open-to-first-page, BLOCKING PRIMARY) still
  passes on both arms and is compared against the pre-change 47 ms / 7 ms so a regression is
  visible rather than merely absent; the chapter count is still exactly 1859 with the expected
  first/last titles; the memory disposition of §4.5 is applied and recorded.
notes: >
  If any gate misses, WI-4 is dispatched and this WI re-runs after it. Fixtures re-pushed per run
  (both the book and docs/architecture.md). Reboot the emulator first if a prior run was truncated.
bump_tier: patch
```

### WI-4 — CONDITIONAL: line-start anchored scanning (foundational)

**Trigger**: WI-3 reports the scan over 1 500 ms.

```yaml
id: feat:#172/WI-4
tier: foundational
condition: dispatched ONLY if WI-3 measures > 1500 ms
depends: [feat:#172/WI-3]
writes:
  - android/app/src/main/kotlin/com/vreader/app/reader/nav/TxtTocRuleEngine.kt
  - android/app/src/test/kotlin/com/vreader/app/reader/nav/TxtTocEngineWalkEquivalenceTest.kt
tests:
  - RED (jvm): line-terminator conformance — CRLF, lone CR, lone LF, U+0085, U+2028, U+2029,
               a terminator at end-of-input, an empty final line, consecutive blank lines
  - RED (jvm): resume-after-a-cross-terminator-match equals find()'s resume rule
  - GREEN (jvm): differential oracle extended — anchored walk == reused-Matcher walk, per document
acceptance: >
  Match sequence identical to WI-2's on every corpus document INCLUDING the cross-terminator case
  (第\n一\n章 標題) and every terminator variant; no line-window truncation is introduced anywhere.
bump_tier: patch
```

### WI-5 — CONDITIONAL: mechanically-derived first-character pre-filter (foundational)

**Trigger**: WI-4 lands and the scan is still over 1 500 ms.

```yaml
id: feat:#172/WI-5
tier: foundational
condition: dispatched ONLY if the post-WI-4 re-measurement is > 1500 ms
depends: [feat:#172/WI-4]
writes:
  - android/app/src/main/kotlin/com/vreader/app/reader/nav/TxtTocPrefilter.kt
  - android/app/src/main/kotlin/com/vreader/app/reader/nav/TxtTocRuleEngine.kt
  - android/app/src/test/kotlin/com/vreader/app/reader/nav/TxtTocPrefilterTest.kt
  - android/app/src/test/resources/prefilter-cjk-sample.txt        # the committed deterministic fixture
  - android/app/src/androidTest/kotlin/com/vreader/app/reader/nav/TxtTocScanCostTest.kt  # SELECTIVITY-REAL arm
tests:
  # NOTE (Gate-2 R1 MEDIUM): "no string starting with cp can match" is a property of an INFINITE
  # suffix language and is NOT decidable by a brute-force oracle. The tests below therefore do not
  # claim a proof. Soundness rests on hitEnd()'s contract; the tests are (i) a finite per-rule
  # WITNESS GENERATOR, (ii) bounded differential coverage, (iii) the fail-open net. Stated as what
  # they are.
  - RED (jvm): WITNESS SWEEP — for each of the 25 rules (enabled AND disabled), generate matching
               lines from the rule's OWN grammar (every alternation branch, every numeral
               inventory, every indent width 0..8, both digit widths) and assert the filter accepts
               every generated line. A rule whose witnesses the filter rejects fails the build.
  - RED (jvm): BMP ACCEPT-SIDE SWEEP — for every BMP code point cp, if the derived predicate
               ACCEPTS cp the test does nothing (accepting is always safe); if it REJECTS cp,
               assert the rule body also rejects a bounded family of suffixes beginning with cp.
               A disagreement is a red build. This is coverage, not a decision procedure.
  # SELECTIVITY is split across the two lanes because the real 14 MB book is gitignored and
  # unavailable to a JVM unit test (§8) — a JVM test naming it would be unimplementable (R2 MEDIUM).
  - RED (jvm): SELECTIVITY-STRUCTURAL — for each of the 25 rules, assert FIRST contains an indent
               character (space/U+3000/tab) IF AND ONLY IF that rule's BODY can begin with WS. On
               the current rule set exactly one rule (id 2) satisfies the right-hand side, so this
               test fails outright under the whole-pattern derivation defect (R1 MEDIUM).
  - RED (jvm): SELECTIVITY-RATE — over a COMMITTED deterministic fixture asset
               (`src/test/resources/prefilter-cjk-sample.txt` — the JVM unit-test source set, NOT
               androidTest assets: 10 000 lines of CJK prose, EVERY
               line indented with two U+3000 to mirror the real book's typesetting, containing
               exactly 100 rule-1 headings), assert the rule-1 filter accepts <= 300 of the 10 000
               lines (<= 3 %) AND accepts all 100 headings. Both bounds are exact integers over a
               fixed asset, so the test is deterministic, not statistical.
  - RED (connected, WI-5 only): SELECTIVITY-REAL — the same accept-rate measurement against the
               REAL 14 MB book as an added TxtTocScanCostTest arm, LOGGED with a loose ceiling
               (<= 10 % of 254 109 lines). The real book's number belongs on the device lane, where
               the fixture actually exists.
  - RED (jvm): adversarial corpus — every branch of rule 1's alternation (序章/楔子/正文/终章/后记/
               尾声/番外/第…), rule 2 with >=5 leading spaces, rule 2 with NBSP indent, full-width
               digits, surrogate-pair line starts, a lone surrogate line start
  - RED (jvm): the fail-open gate — a deliberately broken derivation disables the filter rather
               than dropping a heading
  - GREEN (jvm): differential oracle extended — filtered walk == unfiltered walk, per document
acceptance: >
  The derivation is mechanical (no hard-coded character table) and body-relative; every generated
  witness for all 25 rules is accepted; self-validation failure falls open. Soundness is argued
  from hitEnd()'s contract and BACKED by the sweeps — it is explicitly NOT claimed as a proof, and
  the fail-open net is what makes an unsound derivation a slow scan rather than a lost chapter.
notes: >
  This is the only WI in this plan with a correctness surface. Its Gate-4 audit prompt MUST
  explicitly ask the auditor to construct a heading that a currently-enabled rule matches and the
  filter rejects.
bump_tier: patch
```

### Not a WI — F1 (Room persistence), a named follow-up with a trigger

Room persistence is **deliberately not numbered as a work item** (Gate-2 R1 LOW): a WI whose
`writes` is `TBD`, whose tests are unnamed and whose acceptance is "specified later" is not a
dispatchable unit, and counting it inflates the sequence with something no lane could execute.

**F1 — persist the derived TOC (Room).** *Trigger*: WI-5 lands and the real-book scan still exceeds
1 500 ms. *Then*: this plan is **amended** (a Gate-1 revision + a fresh Gate-2 round) before any
implementation, because the shape depends on the measured residual — in particular whether the first
open needs a progressive path at all, and whether such a path would put new state on a designed
surface and therefore need a design (rule 51). Its known cost and its two shipped-bug precedents on
iOS are in §3.3. If this trigger fires, nothing is implemented until the amendment passes Gate 2.

### Tier summary

Five work items; two are conditional.

| WI | Tier | Conditional | Gate-5 requirement |
| --- | --- | --- | --- |
| WI-1 | foundational | no | none (it IS a device measurement) |
| WI-2 | foundational | no | slice: the connected engine-budget assertion |
| WI-3 | behavioral | no | **full acceptance pass + evidence file** |
| WI-4 | foundational | yes | slice re-measurement |
| WI-5 | foundational | yes | slice re-measurement |
| (F1) | — | follow-up | not a WI; re-plans through Gate 1 + Gate 2 if triggered |

---

## 8. Test catalogue

| Test | File | Covers |
| --- | --- | --- |
| `armsAgreeOnHeadings` | `TxtTocScanCostTest` (new, androidTest) | the measurement arms produce identical results, so the cost comparison is between equivalent implementations |
| `reportsCostAttribution` | same | per-arm wall-clock + Java-heap + PSS deltas on the real book; §4.5's memory disposition |
| `reportsMatcherConstructionCost` | same | arm (g) — **the H1 falsifier**: per-construction cost at two text sizes, with a non-elidable sink |
| `reportsConstructionVsResetSplit` | same | arm (h) — attributes cost to construction vs `find(int)`'s `reset()` |
| `logsTargetRegexSemantics` | same | arm (f) — **target-regex semantic logging only** (D1/D1b on the target). Explicitly **not** engine discrimination and **not** a cost claim; O(n)-vs-O(1) is answered by arms (g)/(h) |
| `extractionMeetsEngineBudget` | same (added by WI-2) | the RED for WI-2 |
| differential oracle | `TxtTocEngineWalkEquivalenceTest` (new, JVM) | old walk == new walk, element-for-element, over an adversarial corpus |
| — cross-terminator | same | `第\n一\n章 标题` (the case a line-window matcher drops) |
| — terminator variants | same | CRLF, lone CR, lone LF, U+0085, U+2028, U+2029, terminator at EOF, blank lines |
| — indentation | same | 0–4 indent chars, ≥5 indent chars, U+3000 indent, tab indent, NBSP indent |
| — CJK/full-width | same | full-width digits, financial numerals, `第 一 章` with U+3000 separators |
| — surrogates | same | astral-plane line starts, lone surrogates |
| — limit boundary | same | `limit`-1 / `limit` / `limit`+1 headings; empty-title matches not counted |
| — cancellation | same | cancellation still observed at the documented cadence |
| witness sweep | `TxtTocPrefilterTest` (WI-5 only) | all 25 rules; lines generated from each rule's OWN grammar must all be ACCEPTED by the filter |
| reject-side BMP coverage | same | bounded coverage, **not** a decision procedure and **not** a proof: where the predicate REJECTS a code point, a bounded suffix family is checked to agree. The accept side needs no check — accepting is always safe |
| selectivity | same | body-relative derivation actually discriminates: no rule whose body cannot begin with whitespace acquires an indent char in `FIRST`, and the accept rate on the committed corpus is within its stated ceiling |
| fail-open gate | same | a broken derivation disables the filter, never drops a heading |
| **unmodified regression suites** | `TxtTocRuleEngineTest` (697 ln), `TxtTocRulesTest` (532), `TxtMdTocProviderTest` (363), `TxtTocIndexTest` (416), `MdTocScannerTest` (624) | every existing guarantee, including the D1/D1b divergence repairs, the 25-rule parameterised regressions with negative controls, and `noDensityOrSaturationGuardExists` |
| **acceptance** | `TxtTocAcceptanceTest` (unmodified, 1 207 ln) | §5 gates 1/2/3 on the real book through the production entry point |

**Corpus construction note.** The differential oracle's corpus uses real content where it can — the
`resume-sample.txt` asset and slices of the real book are preferred over invented text
(AGENTS.md "real books first"). Synthetic documents are used only for the structural edge cases a
real book cannot deterministically provide (a lone ` `, an unpaired surrogate, exactly
`limit ± 1` headings), which is the rule's explicit "deterministic tiny structure" exception. The
real 14 MB book is not readable from a JVM unit test (it is gitignored and not in CI), which is why
the whole-book equivalence check lives in the connected arm-comparison instead.

---

## 9. Risks and mitigations

### 9.1 The central question: is a prefix pre-filter provably safe for all 14 enabled rules?

**Answered in two parts, because the row's "line-prefix pre-filter" bundles two things with very
different safety properties.**

**(a) Restricting candidate positions to line starts — YES, provably safe.** The theorem and its
proof are in §5.2, and its premise is verified rather than assumed: all 25 patterns begin with
`INDENT` (`TxtTocRules.kt:96-304`). The residual risk is implementation fidelity to Java's `^`
semantics (CRLF, U+0085/U+2028/U+2029, no match at end-of-input) and to `find()`'s resume rule — a
bounded, testable surface, covered by WI-4's RED tests.

**(b) Rejecting a line on its first character — NO, not by inspection.** Hand-deriving `FIRST(R)`
for the 14 enabled rules is *possible* but is exactly where a silent heading-dropping regression
would live. These are **body-relative** sets — derived from the pattern with its shared `INDENT`
prefix stripped (§5.3); derived from the *whole* pattern instead, every row below would additionally
contain space/U+3000/tab and the filter would be inert on an indented corpus. Derived by hand:

| Rule | `FIRST` (of the post-`INDENT` body) | Size |
| --- | --- | --- |
| 1 (the winner) | `序 楔 正 终 后 尾 番 第` | 8 |
| 23 | `第` | 1 |
| 6 | `正` | 1 |
| 7 | `卷 篇 部 集` | 4 |
| 8 | `☆ ★` | 2 |
| 9 / 10 | `V v` / `B b` | 2 |
| 13 | `( （` | 2 |
| 3 | `C c S s P p E e` | 8 |
| 20 | `P p E e I i F f A a C c` | 12 |
| 5 | `【 [ ☆ ★ ● ◆ ◇ ○ ◎ □ ■ △ ▲ ※ 卐` | 15 |
| 4 / 14 | `[0-9０-９]` | 20 |
| **2** | `第 （ (` ∪ **WS** (`\s` ∪ `\p{Z}` ∪ U+0085) ∪ `[0-9０-９]` ∪ 24 CJK numerals | **unbounded category** |

Rule 2 is the counterexample to any "small literal set" intuition: its `[第（\(]?` is **optional** and
its `WS{0,4}` can match zero characters, so its first character may be a digit, any of 24 CJK
numerals (including `一`, `二`, `十` — extremely common line-initial characters in Chinese prose), or
**any whitespace**. It is decidable, but it is a predicate, not a table, and its selectivity on CJK
prose is poor.

Concrete constructions that break naive versions of the filter — the adversarial cases WI-5's tests
must contain, and which a Gate-2/Gate-4 auditor should try to extend:

1. **`{第, #}` (HeadScan's set) drops 7 of rule 1's 8 branches.** A book whose chapters read `楔子`,
   `序章` or `番外` loses every one of them. `HeadScan.java:27` is not a correct filter for rule 1;
   it is a filter for the subset of rule 1 that the *one measured book* happens to use.
2. **Cross-terminator match.** `第\n一\n章 标题` matches rule 1 (`TxtTocRuleEngine.kt:15-19`). A
   first-character filter survives this (the first character is still `第`); a *line-window matcher*
   does not. This is precisely why layer 3 keeps the real regex as the decider.
3. **≥5 leading indent characters.** `INDENT` caps at 4, but rule 2's own `WS{0,4}` absorbs up to 4
   more, so `"␣␣␣␣␣␣1、题"` matches. A filter that skips exactly 4 and tests must accept-on-indent;
   §5.3's clause 3 handles it.
4. **NBSP indentation.** `INDENT`'s literal class excludes NBSP, but rule 2's `WS` includes it via
   `\p{Z}`, so a line starting with NBSP can match with `INDENT` consuming zero.
5. **Full-width digits.** `１、题` matches rules 2/4/14 through the D1 repair; a filter keyed on
   ASCII digits drops it — the exact class of bug D1 exists to prevent.
6. **Astral-plane line start.** A code-unit-keyed filter mis-reads a surrogate pair.
7. **A future rule edit.** Enabling rule 15/16/17, or amending a pattern, silently invalidates a
   hard-coded table with no test to notice.

**Therefore**: the filter ships only if it is derived **mechanically** and **body-relatively** from
the compiled pattern (§5.3), is exercised by a per-rule witness generator plus a bounded BMP
reject-side sweep across **all 25 rules** (not a proof — see the WI-5 note), and **falls open** when
it cannot validate itself. And it ships **third**, after two layers with no correctness surface at
all — because a dropped heading is a far worse outcome than a slow scan, and this feature exists to
avoid trading one for the other.

**Independent confirmation (Gate-2 round 1).** The auditor was asked explicitly to construct a
heading that a currently-enabled rule matches and this filter rejects. It ran ten constructions —
`楔子`, `序章`, the cross-terminator `第\n一\n章 标题`, six-space-indented rule-2, NBSP-indented
rule-2, four-spaces-then-NBSP, full-width `１.标题`, `正文　第一章`, a post-U+2028 line start, and a
NEL line start — and **found no counterexample**: every one survives, and it separately confirmed
that the rejected HeadScan `{第,#}` shortcut does *not*. That is meaningful evidence for the
*specified* filter's soundness. It is **not** a proof, and it did not need to be for the plan's
decision, because the filter is sequenced third behind two layers that have no correctness surface —
it may never be built at all.

### 9.2 Other risks

| Risk | Severity | Mitigation |
| --- | --- | --- |
| **H1 is wrong** — layer 1 measures no better than baseline | High | WI-1 measures *before* WI-2 ships. If arm (b) is not materially faster, WI-2 escalates rather than shipping on a prediction. This is the whole reason WI-1 exists. |
| **Layer 1 wins on the emulator but not on real hardware** | Medium | The emulator is the stated Gate-5 environment for this repo (rule 47 Android tier) and is where the failure was observed, so it is the right oracle. The evidence file records the AVD. Real-device confirmation is a named follow-up, not a gate. |
| **A future refactor reverts the hand-written walk** to `Regex.find()/next()` because it "reads better" | Medium | Rule 22: the reason is recorded in `TxtTocRuleEngine.kt`'s `Key decisions` header, and the connected engine-budget assertion fails if it is reverted. |
| **Fixing the walk changes the emitted headings** | High if it happened | Differential oracle over an adversarial corpus + five unmodified regression suites + the acceptance suite's per-entry structural oracle against the real bytes (`TxtTocAcceptanceTest.kt:590-610`). |
| **Open-to-first-page regresses** (the blocking primary gate) | High | WI-3 asserts it on both arms and compares against the recorded pre-change 47 ms / 7 ms. Nothing in the write-set touches `reader/paged/*`. |
| **Connected tests are emulator-flaky / the run is lowmemorykiller-ed** | Medium | One class per connected invocation; never drive the emulator during a run (rule 52 Cause D); re-push fixtures every run; reboot the emulator if truncated. If layer 1 works, the memory pressure that caused the truncations should itself recede (§4.5). |
| **Codex/Gate-2 unavailable** | Low | Rule 47's manual-fallback evidence section. |
| **The memory signal turns out to be the paginator, not the scan** | Low | §4.5's decision rule files it as a separate row rather than expanding this feature's scope. |

---

## 10. Backward compatibility

**Nothing to migrate.** The TOC is derived in memory, per reader session, and is not persisted
anywhere (`TxtMdTocProvider.kt:76-86`; the parent plan §5 declined Room). There is no stored artifact
whose format could change, no schema version, no cache to invalidate, and no cross-platform contract
in play — `TocEntry`, `Locator` and the source-offset semantics are untouched, so a heading's
`canonicalLocator` remains byte-identical to what #139 shipped and stays interchangeable with the
bookmark/resume seam it is constructed from (`TxtMdTocProvider.kt:26-30`).

Older backups, older clients and existing books are all unaffected: the same input produces the same
1 859 entries at the same offsets, only sooner. If layer 4 (persistence) is ever reached, it
introduces the *first* migration surface in this feature and the plan is amended before that happens.

---

## 11. Revision history / Gate-2 audit rounds

| Rev | Date | Change |
| --- | --- | --- |
| v1 | 2026-08-05 | Gate-1 draft. Primary approach = one `Matcher` per scan (§5.1), on evidence in §4; prefix filter demoted to a specified contingency (§5.3) with its safety limits stated (§9.1); persistence sequenced last (§3.3). |
| v2 | 2026-08-05 | Gate-2 round 1 findings applied (all 5) — headline change: the pre-filter's `FIRST` derivation became **body-relative**, without which it would have been inert on the real book. |
| v3 | 2026-08-05 | Gate-2 round 2 findings applied (all 4) — headline change: benchmark arm (g) gained a **non-elidable sink**, without which it could have falsely killed H1. |
| v4 | 2026-08-05 | Gate-2 round 3 findings applied (all 4, stale wording only). **Gate 2 closed: C=0 H=0.** |

### Gate-2 round 1 — `VERDICT: block-recommended (C=0 H=1 M=3 L=1)`

Auditor: Codex `gpt-5.5`, reasoning effort `high`, read-only sandbox, via `scripts/run-codex.sh`
(rule 53). Author/auditor separation holds — a separate process with its own context.
Transcript: `<scratchpad>/f172-gate2-r1.txt` (6 625 lines).

| # | Sev | Finding | Disposition |
| --- | --- | --- | --- |
| 1 | **HIGH** | WI-2 declares a *connected* RED (`extractionMeetsEngineBudget`) but its `gate` ran only `:app:testDebugUnitTest` — the gate could not execute its own RED | **FIXED.** WI-2's `gate` is now two commands (JVM suite **and** the connected `TxtTocScanCostTest`), and its acceptance requires the RED to be demonstrated red-before / green-after |
| 2 | MEDIUM | The mechanical `FIRST` derivation probed the **whole** pattern, so `INDENT` made space/U+3000/tab viable for *every* rule; clause 3 would then accept *every indented line*, erasing the filter's selectivity | **FIXED, and this was the most valuable finding.** Derivation is now **body-relative** (`pattern.removePrefix(TxtTocRules.INDENT)`, exact for all 25, fail-open otherwise). The defect was not hypothetical: the real book indents **every** line with two U+3000 (`　　第一章　太阳消失`), so a whole-pattern derivation would have rejected nothing at all on the one document this feature exists to fix. §5.3 now states this explicitly and WI-5 gains a SELECTIVITY test |
| 3 | MEDIUM | The WI-5 "soundness sweep over every BMP code point" overclaimed a brute-force oracle for an **infinite suffix-language** property | **FIXED.** No proof is claimed. Replaced with a per-rule **witness generator**, a bounded reject-side BMP sweep (accept side needs no check — accepting is always safe), and the fail-open net, each labelled as what it is |
| 4 | MEDIUM | WI-1 claimed to "settle" whether the target regex is native-backed, but its probe only checked character-class semantics, and no arm isolated `Pattern.matcher()` construction from `find(int)`'s `reset()` | **FIXED.** Added arm **(g)** — N × construction with no matching, at two text sizes: the direct O(n)-vs-O(1) **falsifier** for H1 — and arm **(h)**, construction vs `reset()` attribution. The semantics probe is demoted to *target-semantic logging* and no longer claims engine identity |
| 5 | LOW | WI-6 was counted in the sequence with `writes: TBD`, no tests and unspecified acceptance | **FIXED.** Demoted out of the numbered sequence to triggered follow-up **F1**, which re-enters Gate 1 + Gate 2 as a plan amendment if its trigger fires. Sequence is now **five** WIs, two conditional |

**Adversarial pre-filter result**: the auditor was asked to construct a heading matched by an enabled
rule that the filter rejects. Ten constructions attempted, **zero counterexamples found** — see
§9.1's "Independent confirmation".

**Not challenged by the auditor** (no finding raised): the bytecode claim about
`MatcherMatchResult.next()`, the semantic equivalence of the reused-`Matcher` walk (audit item 4b —
the one place a CRITICAL was invited and none was returned), the §5.2 line-start theorem, the
rule-51 no-visible-delta claim, the write-set's rule-48/55 isolation, and the §1 no-budget-loosening
constraint.

### Gate-2 round 2 — `VERDICT: block-recommended (C=0 H=1 M=2 L=1)`

Same auditor configuration; fresh context. Round 2's brief asked it to (a) verify each round-1 fix
rather than trust the table above, and (b) hunt for defects the revision itself introduced.
Transcript: `<scratchpad>/f172-gate2-r2.txt`.

**Round-1 fixes it confirmed**: #1 FIXED (WI-2's gate now runs its own RED), #2 FIXED (`removePrefix`
verified exact against all 25 patterns including the braced `${INDENT}` ones), #5 FIXED (no stale
WI-6). #3 and #4 were marked NOT-FIXED — correctly: the WI text was fixed but §8's catalogue and
§12's evidence row still carried the old wording, which is finding 3 and 4 below.

| # | Sev | Finding | Disposition |
| --- | --- | --- | --- |
| 1 | **HIGH** | **Arm (g) is defeatable by dead-code elimination** — a constructed `Matcher` that is never used can be scalar-replaced or elided by the JIT, reporting a spuriously flat cost and **falsely killing H1** | **FIXED.** §4.3 now requires a non-elidable sink (`@Volatile` field or an `identityHashCode` accumulator) written before the timer stops, forbids any *match* operation in the sink, and states that an arm without a proven sink is discarded rather than believed. This is the single most valuable finding of the two rounds: it would have produced a confidently wrong answer, not a visible failure |
| 2 | MEDIUM | WI-5's SELECTIVITY test asserted an accept rate "far below 1" on a "real indented CJK corpus" — no numeric threshold, and §8 states the real book is unavailable to JVM tests, so the test was unimplementable as written | **FIXED.** Split by lane: **SELECTIVITY-STRUCTURAL** (iff-condition over all 25 rules), **SELECTIVITY-RATE** (a committed 10 000-line U+3000-indented fixture with exactly 100 headings; exact integer bounds ≤ 300 accepted and all 100 headings accepted), and **SELECTIVITY-REAL** (the real book, on the *connected* lane where it exists, logged with a loose ceiling) |
| 3 | MEDIUM | §8's catalogue still said "all 25 rules × the BMP; brute-force oracle", contradicting the corrected WI-5 text | **FIXED.** Catalogue rewritten into three rows — witness sweep, bounded reject-side BMP coverage (explicitly "not a decision procedure and not a proof"), selectivity |
| 4 | LOW | §8 still credited arm (f) with "engine discrimination" and §12 row 16 still said arm (f) settles native/O(n) | **FIXED.** Both now point cost attribution at arms (g)/(h); arm (f) is semantic logging only |

**Body-relative probe soundness — the question the revision put at risk, answered explicitly.** The
auditor was asked whether stripping the `^`-anchored `INDENT` prefix makes the `hitEnd` probe unsound
(a body matched without an anchor could behave as a search). Its verdict: **sound**, because
`lookingAt()` still anchors the body at position 0, so a failed `lookingAt()` with `hitEnd() == false`
still means no suffix extension can make that body match starting with that code point; and clause 3
still covers the indentation-backtracking case. The round-1 fix therefore did not trade a selectivity
bug for a correctness bug.

### Gate-2 round 3 (FINAL — rule 47's cap) — `VERDICT: block-recommended (C=0 H=0 M=3 L=1)`

Same auditor configuration; fresh context. Transcript: `<scratchpad>/f172-gate2-r3.txt`.

**Severity fell to zero Critical and zero High.** All four remaining findings were **stale wording**
— prose in §5.3, §6.2 and the WI-5 spec that still described the *pre-revision* design after the
round-1/round-2 fixes had already changed it elsewhere in the document. None implied a design change;
each was applied verbatim as the auditor prescribed:

| # | Sev | Finding | Disposition |
| --- | --- | --- | --- |
| 1 | MEDIUM | §5.3's blockquote still said the selectivity test asserts "far below 1" on a "real indented CJK corpus" | **FIXED** — replaced with the three-test split (STRUCTURAL / RATE / REAL) |
| 2 | MEDIUM | §5.3 still used "brute-force oracle" and "prove itself" for the fail-open gate | **FIXED** — now "bounded witness corpus", explicitly "not a decision procedure and not a proof" |
| 3 | MEDIUM | SELECTIVITY-RATE is a JVM test but its fixture was parenthesised as "androidTest assets" — the wrong source set | **FIXED** — now `src/test/resources/…`, matching the write-set |
| 4 | LOW | §6.2's new-files table omitted `TxtTocPrefilterTest.kt` (and `TxtTocPrefilter.kt`) | **FIXED** — both added |

**Independently confirmed in round 3** (the auditor re-derived these rather than accepting them):

- **Arm (g)'s sink is sufficient** — the `@Volatile` / `identityHashCode` escape written before the
  timer stops does prevent elision and scalar replacement of `Pattern.matcher(text)` without adding
  match work. Round 2's HIGH is genuinely closed.
- **The `FIRST`-contains-whitespace ⟺ body-begins-with-`WS` claim is correct rule-by-rule: on the
  current rule set, rule id 2 is the only one.** This is the load-bearing premise of the layer-3
  filter's selectivity and it was checked against `TxtTocRules.kt`, not taken from the plan.
- Arm (f)'s demotion to semantic logging is complete in both §8 and §12.

### Gate-2 close-out

Rule 47 caps Gate 2 at three rounds. After round 3 the open severity was **C=0 H=0**, and the three
Medium findings were documentation-consistency defects whose exact remedies the auditor itself
specified and which were applied verbatim, introducing no new design surface and no new claim. On
that basis **Gate 2 is closed as clean and the plan is cleared to enter Gate 3.**

This is recorded as a judgement rather than a fourth audited round, because a fourth round is not
permitted without escalation. The residual risk is bounded and named: the only unverified
load-bearing claim left is **H1 itself** (§4.2), which is *not* a Gate-2 question — it is exactly
what WI-1 exists to measure on the target before WI-2 changes any production code, and the plan
states in advance what falsifying it looks like and what happens then.

**Round-over-round severity**: R1 `C=0 H=1 M=3 L=1` → R2 `C=0 H=1 M=2 L=1` → R3 `C=0 H=0 M=3 L=1`.
The High count fell to zero and no round ever returned a Critical. Notably, across all three rounds
the auditor never challenged the plan's **primary** claim — the reused-`Matcher` walk's exact
equivalence to Kotlin's `next()` walk — despite being explicitly invited to return a CRITICAL for any
input on which the two differ, in every round.

---

## 12. Gate-1 evidence appendix — claims verified against the live codebase

Every load-bearing claim in this plan, with where it was checked. Claims are marked
**MEASURED-ON-DEVICE**, **MEASURED-ON-DESKTOP**, **VERIFIED** (read in the repo), or **PREDICTED**.

| # | Claim | Status | Evidence |
| --- | --- | --- | --- |
| 1 | Kotlin's `MatchResult.next()` constructs a new `Matcher` over the whole input per match | **VERIFIED** | `javap -c kotlin/text/MatcherMatchResult.class` from kotlin-stdlib **2.3.20** (the version at `android/build.gradle.kts:9`): `Matcher.pattern()` → `Pattern.matcher(input)` → `RegexKt.findNext`. Disassembly at `<scratchpad>/ks/mmr.txt:84-121` |
| 2 | The engine uses that idiom on both hot paths | **VERIFIED** | `TxtTocRuleEngine.kt:142`, `:155` (extract); `:188`, `:195` (detect) |
| 3 | All 25 rule patterns begin with `INDENT`, i.e. `^` + a literal indent class | **VERIFIED** | `TxtTocRules.kt:96-304`; `INDENT` defined at `:91` as `"^[ " + Char(0x3000) + "\\t]{0,4}"` |
| 4 | `WS` contains line terminators, so a rule can match across a newline | **VERIFIED** | `TxtTocRules.kt:51-54` (`\s\p{Z}\x{0085}`); documented + pinned at `TxtTocRuleEngine.kt:15-19`, `:40-45` |
| 5 | The provider calls detect-then-extract once per `toc()`, with `cap + 1` | **VERIFIED** | `TxtMdTocProvider.kt:76-86`, `:105-111` |
| 6 | `MdTocScanner` does **not** use the `Regex.find()/next()` walk | **VERIFIED** | only two `Regex` uses, both single-line YAML tests: `MdTocScanner.kt:74`, `:77` |
| 7 | The acceptance budget is 1 500 ms and is asserted, not advisory | **VERIFIED** | `TxtTocAcceptanceTest.kt:215`, asserted at `:714-717` and `:817-821` |
| 8 | The open-to-first-page gate is separate, blocking, and currently passing | **VERIFIED** | `TxtTocAcceptanceTest.kt:857-916`; row records 47 ms / 7 ms vs 2 000 ms |
| 9 | Existing engine tests pin the cancellation cadence structurally, so the loop shape must be preserved | **VERIFIED** | `TxtTocRuleEngineTest.kt:458-479`, `:564-611` |
| 10 | `TxtTocRulesTest` compiles rules with its own `Regex(...)`, not through the engine's private `compile` | **VERIFIED** | `TxtTocRulesTest.kt:56` — so changing the engine's internal compile to `Pattern` cannot break it |
| 11 | D1/D1b are pinned only by **JVM** unit tests, so they are unverified on the device engine | **VERIFIED** | `TxtTocRulesTest.kt:296`, `:356`, `:361` are `src/test` (JVM), not `src/androidTest` |
| 12 | Desktop extraction of the real book with rule 1 = 22–23 ms | **MEASURED-ON-DESKTOP** | parent plan `…-139-…md:1509-1520` (Appendix A.1 output) |
| 13 | Desktop hand-rolled prefix scan = 6–13 ms, and finds **1860**, not 1859 | **MEASURED-ON-DESKTOP** | `…-139-…md:1570-1577`; probe at `dev-docs/benchmarks/feature-139/HeadScan.java` |
| 14 | Device extraction ≈ 6 604–8 200 ms; device detection ≈ 103 ms | **MEASURED-ON-DEVICE** | #139 Gate-5b run; recorded in `docs/features.md:224` and `TxtTocAcceptanceTest.kt:680-693` |
| 15 | Layer 1 brings extraction to ~90–350 ms | **PREDICTED** | §4.4 arithmetic under H1 — **the reason WI-1 exists is that this is a prediction** |
| 16 | Android's `java.util.regex` is native/O(n)-per-`Matcher` | **NOT VERIFIED** | No SDK `sources/` component installed locally; `platforms/android-36/android.jar` is stubs. Settled on-device by **arm (g)** (construction cost at two text sizes) and **arm (h)** — *not* by arm (f), which is semantic logging only and cannot speak to cost (Gate-2 R2 LOW) |

### Incidental finding (recorded, not actioned here)

The Gate-1 benchmark harness `dev-docs/benchmarks/feature-139/RuleScan.java:10` transcribes rule 5's
character class with **卍** (U+534D), while the shipped Kotlin rule uses **卐** (U+5350) —
`TxtTocRules.kt:135` — which is what iOS ships (`vreader/Services/TXT/TXTTocRuleEngine.swift:182`).
**The shipped port is correct; the benchmark transcription is not.** It has no effect on any number
this plan or #139 relies on: rule 5 is not the winning rule on the real book (rule 1 is, asserted at
`TxtTocAcceptanceTest.kt:708-711`), and rule 5's sample match count feeds no shipped decision.
Recorded here so the discrepancy is not rediscovered as a port defect; correcting the benchmark is a
docs-only change owned by whoever next touches `dev-docs/benchmarks/feature-139/`, and it is
deliberately **not** in this feature's write-set.
