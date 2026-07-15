# Feature #138 — Android paged phase-1: windowed / incremental pagination for very large docs

**Status:** Gate-1 plan (v3 — Gate-2 round-2 findings resolved; pending Gate-2 confirmation audit). Driver: #110
Android parity (box E follow-up). Parent: feature #137 (Compose paged TXT/MD renderer, VERIFIED
android/v0.20.6). Source row: `docs/features.md` #138 (Medium, TODO). Evidence that motivated it:
`dev-docs/verification/feature-137-20260715.md` (§Observations — phase-1 median 95,912 ms on the real
14 MB CJK book, and `TxtPaginatorPerfBenchmark.kt` recorded ~85 s/run). Design authority: NO new
user-visible surface introduced (see §Design decision and §UI/rule-51) — a pure-mechanism change behind
the already-designed #137 paged surface.

## Revision history

**v2 → v3: Gate-2 round-2 findings (1 High / 4 Medium / 1 Low) resolved.** The round-2 verdict was
`revise` with all round-1 Criticals/Highs confirmed resolved (`.reports/feat138-gate2-r2.txt` §Round-1
Resolution + §Critical "None"). v3 closes ONLY the remaining refinements; the v2 core (doc-start-forward,
single-session actor, sealed pages, async source-offset jumps, honest far-jump budget, WI-1..WI-6/5a-b-c
split, model-assumptions appendix, backward-compat) is unchanged except where a finding names it. Each
round-2 finding → the v3 change:

- **High 1 — deep-resume auto-scroll fighting the user + one-shot-scroll clamp/clear hazard.** The
  round-2 audit confirmed: the body's user-swipe path (`snapshotFlow { pagerState.settledPage }`,
  `TxtReaderBody.kt:343`) has NO "user interacted, cancel the pending resume reveal" state, so an
  `onReveal` firing seconds after a user has paged away YANKS the pager; and the existing one-shot
  consumer (`localScrollTarget` at `TxtReaderBody.kt:356-367`) CLAMPS a target to the CURRENT
  composition's `pageCount` and CLEARS it — so if `onSnapshot` (a grown index) and `onReveal` fire in the
  same publication, the old collector can clamp a not-yet-in-range resume page to the OLD last page and
  clear it before the grown `idx` composition exists. **v3: the resume reveal becomes CONDITIONAL,
  INDEX-AWARE, ONE-SHOT, and USER-CANCELABLE, and is a DISTINCT mechanism from the ordinary in-range
  `localScrollTarget` scroll** so the two never stomp each other. Full design in §Design decision
  (Deep-resume) + §Surface area (`TxtReaderBody.kt`) + WI-5b; connected proofs added to WI-5c
  ("user pages before the anchor seals → reveal dropped"; "snapshot publish + reveal same publication →
  reveal lands on the grown index, not clamped to the old last page").

- **Medium 1 — state the sealed-page pending-start model EXACTLY.** v2's sealed-page invariant was sound
  but under-specified. **v3 states it plainly** in §Design decision (Sealed-page pending-start model) +
  §Surface area (`TxtPageIndex.kt`) + WI-2/WI-3: a partial published index contains starts for SEALED
  pages ONLY; the next known offset is `frontierSourceOffset` — a FRONTIER MARKER, not a page start;
  `pageEndExclusive(lastSealedPage)` == the next sealed page's start (which exists precisely because a
  page is sealed only once its successor's start is known); the FINAL page is sealed by DOC END, not by a
  next start. Consequence stated plainly: **rendering page 0 waits until page 1's start is known (a +1-page
  lookahead latency); a one-page doc is sealed at doc end.** WI-2/WI-3 tests: "known-but-unpublished next
  start", "final page sealed at doc end", "+1 lookahead".

- **Medium 2 — make the `Mutex + worker` supersede/publish contract precise.** v2 named the single-session
  mutex/worker but did not bound the critical sections or order the publish. **v3 specifies** (§Surface area
  `PaginationSession.kt` + WI-4): PAGE/WINDOW-SIZED critical sections (NEVER hold the mutex for an unbounded
  full-book run); a generation check IMMEDIATELY before EVERY publish (drop a stale-generation publish);
  the snapshot handed to the main thread taken via an `AtomicReference` (or a mutex-guarded `snapshot()`);
  and the main-thread `onSnapshot`/publish called AFTER RELEASING the mutation lock (never a main-thread
  callback while holding the lock). WI-4 test: a superseded generation never publishes; a reflow
  mid-background cancels cleanly.

- **Medium 3 — do NOT overstate reuse of the loading affordance for on-demand extends.** The round-2 audit
  confirmed `txt-paged-loading` shows ONLY while `idx == null` (`TxtReaderBody.kt:286`), so after the first
  publish a far bookmark/search/scrub/TTS jump has NO visible pending state — v2's "reuse the loading
  affordance during an on-demand extend" claim was wrong. **v3 removes that claim and defines QUEUED /
  EVENTUAL jump semantics**: a far jump is ENQUEUED (`JumpResult` = request-enqueued) and lands when the
  session measures THROUGH the target; the reader stays on the current page meanwhile (no freeze, no new
  UI). Acceptance/connected tests assert EVENTUAL landing on the right page WITHOUT implying a visible
  loading state. A designed pending/"measuring…" affordance stays an explicit OUT-of-scope rule-51 follow-up.

- **Medium 4 — name the HorizontalPager-growth FALLBACK.** v2 kept growing-`pageCount`-doesn't-yank as a
  blocking WI-5c connected proof but named no fallback if it fails. **v3 names the fallback** (§Design
  decision + §Risks + WI-5c): if WI-5c's no-yank-on-growth test FAILS, recreate `PagerState` keyed by the
  saved source offset / current page on a safe append boundary, OR hold the published `pageCount` stable
  until a proven-safe append boundary and grow in batches. WI-5c is restated as a BLOCKING acceptance
  criterion.

- **Low — tighten `JumpResult` wording.** A synchronous `JumpResult.Succeeded` returned by a
  bookmark/search feeder (`TxtReaderActivity.kt:632, :698`) means the request was ENQUEUED, not that the
  pager has already landed. **v3 makes the type/wording say enqueued-vs-landed** (§Surface area
  `TxtReaderActivity.kt` WI-5a + §Design decision Jump semantics).

**v1 → v2: Gate-2 round-1 findings (2 Critical / 5 High / 4 Medium / 1 Low) resolved.** (Retained for the
record; the round-2 audit confirmed each round-1 finding resolved.) The v1 verdict was `revise`
(`.reports/feat138-gate2-r1.txt`). Each finding and how v2 addressed it:

- **Critical 1 — anchor-start non-determinism.** v1 started the first window at the resume anchor's
  chunk with `carryHeight = 0`, but the page-break state (`currentPageHeight`/`pageHasLine`) is
  sequential and carried across every prior line (`TxtPaginator.kt:105-107`); `chunkForOffset()` gives
  a chunk, not the prior page's remaining height (audit). So an anchor-start window is NOT byte-identical
  to the full pass, and the "byte-identical while starting mid-doc" claim was unsound. **v2: always
  paginate from DOCUMENT START (chunk 0) forward.** The only deterministic pagination begins at chunk 0
  (the sole point where `currentPageHeight = 0` / `pageHasLine = false` is a true invariant). The
  determinism claim is narrowed to the real, provable property: *an incremental doc-start run to
  completion is byte-identical to today's `index(...)`*.

- **Critical 2 — backward-completion renumbering.** v1's anchor-start forced backward completion
  (prepending page-starts before the anchor), which renumbers every visible page and invalidates
  `PagedRenderCache` keys; not prepending makes `pageContaining(0)` clamp wrongly (audit,
  `TxtPageIndex.kt:17-18` `[0] == document start`). **v2: dissolved entirely by doc-start-forward
  pagination — page numbers are STABLE and APPEND-ONLY** (page 0 = doc start; new pages append at the
  end; NEVER prepend; NEVER renumber). `pageContaining(0)` is always correct; render-cache keys are
  stable.

- **High 1 — jump protocol is not a thin change.** The host converts source→page synchronously at
  `TxtReaderActivity.kt:572-585`; `TxtPagedBody` consumes `jumpRequest: Int?` as a target PAGE
  (`TxtReaderBody.kt:147, :374`). A frontier-aware async extend cannot fit that API (audit). **v2:
  its own work item (WI-5a) — change the paged jump protocol to an ASYNC SOURCE-OFFSET jump command;**
  the body/session does `ensureMeasuredThrough(offset)` then scrolls to `pageContaining(offset)`. All
  feeders (bookmark/annotation/search/scrubber/TTS-follow) already pass source offsets — they route
  unchanged; only the seam's synchronous source→page conversion and the body's page-vs-offset request
  type change.

- **High 2 + High 5 + Medium 2 + Low 1 (round 1) — concurrency / ownership / slice-leakage / concurrent
  TextMeasurer.** The navigator is explicitly `NOT thread-safe` (`TxtPageNavigator.kt:44`); a background
  loop + on-demand extension can both extend the same slice (generation tokens reject stale generations,
  not *lost updates within the same generation*). The body owns `activeToken` + Compose `index` state
  directly (`TxtReaderBody.kt:231, :241`), NOT through the navigator — split ownership. `PaginationSlice`
  leaked mutable cursor fields. Concurrent `TextMeasurer` use must be forbidden. **v2: a single
  `PaginationSession` (an actor-like owner) OWNS the resumable cursor, the growing sealed page-start list,
  the one `LineMeasurer` instance, the `PaginationToken`/generation, Compose publication, and cache
  invalidation.** Its public API is COMMANDS + immutable snapshots, never raw cursor fields.

- **High 3 — append vs render-cache (sealed pages).** "Append doesn't clear the cache" holds only if
  already-published page *ranges* never change; with `frontierSourceOffset` the old last page's end
  moves when the next start is discovered (audit). **v2: publish only SEALED pages** whose `[start, end)`
  is FINAL — the in-progress frontier page is NOT in the published snapshot until sealed. An append then
  never changes an already-published page's range, so `PagedRenderCache` stays valid on append; ONLY a
  reflow clears it.

- **High 4 — far-jump budget honesty.** A scrub to 90% before background completion measures
  frontier→90%, which can approach the full ~85–96 s cost; v1 called this "bounded by a UX budget" but
  it is bounded by document DISTANCE (audit). **v2: acceptance criteria state this honestly** — the
  < 2 s budget applies to a FRESH/near-start open only; a far jump into an unmeasured region is bounded
  by the frontier→target distance, worst-case near the full measure time. Truly instant deep-resume
  needs a persistent page-index cache — a NAMED FOLLOW-UP.

- **Medium 3 (round 1) — WI-5 too big.** **v2: split into WI-5a (async source-offset jump protocol),
  WI-5b (body windowed lifecycle + session integration + sealed-page/cache policy), WI-5c (connected UX
  tests).**

- **Medium 1 (round 1) — HorizontalPager growing count unproven.** Kept as a WI-5c connected ACCEPTANCE
  test (no-yank-on-growth), never an assumption.

- **Medium 4 (round 1) — perf number wording.** Aligned to the benchmark's source of truth: the real
  book is **14,059,220 bytes (GBK)** (`TxtPaginatorPerfBenchmark.kt:80`) → decoded to 7.03 M UTF-16
  chars / 20.05 MB UTF-8 → 254,109 chunks → 30,695 pages.

- **Low 1 (round 1) — concurrent TextMeasurer.** Explicitly forbidden: the single `PaginationSession`
  owns the ONE `LineMeasurer` instance for its generation.

## Problem

Feature #137's Compose paged TXT/MD renderer paginates in two phases. **Phase 1**
(`TxtPaginator.index(...)`) measures the ENTIRE document once — every rendered line of every chunk is
laid out against the chrome-aware content box via a Compose `TextMeasurer` (through the injected
`LineMeasurer` seam), building a page-start source-UTF-16 `IntArray` — BEFORE the first page can render.
On the real 14 MB CJK book `test-books/books/txt/黑暗血时代.txt` (**14,059,220 bytes GBK** → 20.05 MB
UTF-8 / 7.03 M UTF-16 chars → 254,109 chunks → 30,695 pages) this measured **~85 s/run in the benchmark
and a 95,912 ms median in the #137 verification** on emulator-5554, a Pixel-class device.

**User-facing symptom:** when a user opens (or switches to Paged) a very large book, the reader shows
only a static loading surface (`txt-paged-loading`) for ~1.5 minutes before the first page appears —
effectively a frozen "open" for large books.

**Blast radius is narrow and opt-in:**
- **Paged is opt-in**; the default layout is **Scroll**, which uses the pre-existing chunked
  `LazyColumn` renderer (`TxtBody`) and is completely unaffected. Only a user who explicitly switches a
  large book to Paged hits this.
- Memory is already fine (peak PSS 296 MB, peak used-heap delta 24 MB) — the two-phase design stores
  only the page-start `IntArray`, never rendered pages. **This feature is purely a latency fix; it must
  not regress the already-good memory posture.**
- Small/medium books paginate in well under a frame budget (typical English books are sub-100 ms), so
  those must see no behavioral change.

**Goal:** make **open-to-first-page in Paged mode bounded regardless of document size for a fresh or
near-start open** — show the first page within a small, size-independent budget (target < 2 s; see
§Test catalogue) — and complete / extend the page-boundary index incrementally in the background and on
demand, keeping the reader **never frozen** even for a deep resume, without regressing correctness
(exact UTF-16 offsets, position save/restore, reflow reconciliation, MD dual-affinity, min-one-line
progress, degenerate-box degrade) or the memory posture. The #137 plan (§Pagination strategy — "Perf
bound") pre-authorized exactly this as a windowed-measurement follow-up.

**Honest scope statement (from Gate-2 R1 High 4):** windowing alone does NOT make an *instant deep resume*
into a huge book. Measuring from chunk 0 to an anchor deep in the book is O(depth). #138's honest win is:
(a) a fresh/near-start open is fast (< 2 s), and (b) the reader is never frozen — it is usable
immediately and progressively catches up even for a deep resume or a far jump. Truly instant deep-resume
needs a persistent page-index cache, which is a **NAMED FOLLOW-UP, not #138** (see §Rejected).

## Design decision

### The approach: **doc-start-forward incremental pagination + single-session ownership + on-demand forward extension**

Phase-1 becomes an *incremental, append-only* pass that ALWAYS starts at document start (chunk 0):

1. **First-window measure (bounded, from chunk 0):** measure forward from chunk 0 emitting SEALED page
   boundaries as they are discovered, publishing an immutable partial index as soon as the first few
   pages (the pager's immediate need — the visible page + `beyondViewportPageCount = 1` on each side +
   a small lookahead, a fixed `INITIAL_WINDOW_PAGES`) are sealed. On a fresh/near-start open this is
   O(first-window chunks) → published in < ~2 s. This is the headline win.
2. **Background completion (append-only):** after the first window publishes, keep measuring forward on
   the SAME off-main worker, sealing + appending page-starts to the growing index and republishing
   (throttled) so the page count and `pageContaining` become progressively complete. This is the ~85 s
   of work, now *behind* an already-usable reader instead of *before* it. Because pagination always
   runs forward from chunk 0, every appended page-start is exact — no renumber, no prepend.
3. **On-demand forward extension (safety net for a fast reader / a far jump):** if a page-turn or a jump
   targets at/near the measured frontier before the background pass has reached it, extend forward from
   the last sealed page-start until the target is covered — through the SAME single session (coalesced
   with the background loop, never a second concurrent writer). Deterministic contiguous tiling makes an
   extended boundary identical to what the background pass would have produced.

### Sealed-page pending-start model (Gate-2 R2 Medium 1 — stated EXACTLY)

The published partial index is not "all pages measured so far"; it is precisely the SEALED pages, and the
distinction is load-bearing:

- A page is **SEALED** only once its exclusive end is FINAL. For any page but the last, that means the
  NEXT page's start is known; a partial published index therefore contains starts for **sealed pages
  only**.
- The next known offset — the source offset the cursor has measured up to but which is NOT yet a
  published page start — is `frontierSourceOffset`: a **FRONTIER MARKER, NOT a page start**. It is not in
  `pageStartsUtf16`.
- Consequently, for a partial index, **`pageEndExclusive(lastSealedPage)` == the NEXT sealed page's
  start** (which exists precisely because a page is sealed only once its successor's start is known) —
  equivalently the `frontierSourceOffset` at the moment that page sealed. This is the one subtle
  correctness change (Gate-2 R1 High 3) and it is well-defined ONLY because we never publish an unsealed
  frontier page.
- The **FINAL page is sealed by DOC END**, not by a next page start: when the forward pass reaches
  `docEndExclusive`, the in-progress last page's end is final (== `docEndExclusive`), so it seals and the
  index becomes complete.
- **Consequence stated plainly:** rendering page 0 waits until page 1's START is known — a **+1-page
  lookahead latency** (page 0 cannot seal until page 1 begins). For a **one-page document**, page 0 seals
  at DOC END (there is no next start), so a tiny doc publishes a complete one-page index immediately once
  it reaches doc end. `INITIAL_WINDOW_PAGES` measures a few pages past the visible one, so the +1
  lookahead is subsumed by the window for any non-degenerate multi-page doc — it is a latency note, not a
  hazard.

**Deep-resume behavior (Gate-2 R1 Critical 1 + R1 High 4 + R2 High 1 — the rule-51-clean default, DOCUMENTED):**

A saved offset deep in a huge book cannot be shown *instantly* by windowing (its page is O(depth)). The
default is **conditional auto-scroll on reveal** — never-frozen AND adds no new visible surface — but the
reveal is CONDITIONAL, INDEX-AWARE, ONE-SHOT, and USER-CANCELABLE (Gate-2 R2 High 1), and is a mechanism
DISTINCT from the ordinary in-range `localScrollTarget` scroll so the two do not stomp each other:

- **DEFAULT (conditional auto-scroll on reveal) — chosen:** publish page 0 immediately so the reader is
  USABLE at once (never a frozen loading surface), keep measuring forward in the background, and
  AUTO-SCROLL to the resume page the MOMENT the background pass seals the anchor's page — **but ONLY if
  the user has NOT taken over**. Rule-51-clean: no new UI, reuses programmatic scroll. The one visible
  effect is a brief settle-then-jump to the resume page, exactly the shape a reflow clamp already produces
  today.
- **The reveal is user-cancelable.** The body tracks `userInteractedSinceOpen`, set true on the FIRST
  user-driven `settledPage` change (a swipe) via the existing `snapshotFlow { pagerState.settledPage }`
  path (`TxtReaderBody.kt:343`). The pending resume reveal is consumed (auto-scroll performed) ONLY if
  `!userInteractedSinceOpen` AND the currently-shown source offset is still the initial default (page 0 /
  the open offset). If the user has paged away, the pending reveal is DROPPED — no yank.
- **The reveal is stored as a SOURCE OFFSET (or `(generation, targetPage, minPageCount)`), NOT a bare
  page int**, and is consumed only AFTER the published index actually CONTAINS that page
  (`idx.pageCount > targetPage`, i.e. the sealed frontier has reached the anchor). Until then it stays
  pending. **It is NEVER clamped-and-cleared while out of range** — the exact hazard the current
  `localScrollTarget` consumer (`TxtReaderBody.kt:356-367`) creates: that consumer clamps a target to the
  CURRENT composition's `pageCount` and clears it, so a future resume page would be clamped to the OLD
  last page and cleared before the grown composition exists. The resume-reveal collector waits instead of
  clamping.
- **DISTINCT from `localScrollTarget`.** `localScrollTarget` stays the ordinary IN-RANGE page scroll (the
  reflow clamp / on-demand-extend landing — always within the published `pageCount`). The resume reveal is
  a SEPARATE Compose-state one-shot that is index-aware and user-cancelable. Keeping them separate means a
  snapshot publish (a grown `idx`) and a reveal firing in the SAME frame don't collide: the reveal lands
  on the grown index, never clamped to the old last page.
- **ALTERNATIVE (hold loading until anchor sealed) — rejected as default:** keep showing
  `txt-paged-loading` until the anchor page is measured, then reveal directly on the resume page.
  Rejected because the wait is proportional to resume depth — a deep resume would freeze the loading
  surface for many seconds, the exact symptom #138 exists to remove.

Both behaviors are correct-by-source-offset (the saved position is a `charOffsetUTF16`,
layout-independent); the choice is purely which is shown first. The conditional auto-scroll default reuses
the existing programmatic scroll, so no design round-trip is needed.

**Why not the v1 anchor-start idea (Gate-2 R1 Critical 1/2):** starting the first window at the resume
anchor changes later page breaks (the sequential `currentPageHeight`/`pageHasLine` carry) and forces
backward completion (page renumbering + cache invalidation). Both are dissolved by always paginating from
chunk 0 forward. The v1 "byte-identical while starting mid-doc" claim is dropped as unsound. The real,
provable determinism invariant is now: **an incremental doc-start pagination run to completion produces a
byte-identical page-start `IntArray` to today's `index(...)`** (WI-3's load-bearing equivalence test).

**How `HorizontalPager` gets a page count when the full count is unknown:**

`rememberPagerState(pageCount = { … })` takes a *lambda* Compose re-evaluates; `HorizontalPager` reads
the count reactively and clamps the current page when it changes (confirmed by the current #137 code:
`TxtReaderBody.kt:296-300` drives `pageCount = { pageCount }` with `pageCount = idx.pageCount`, and
`:356-367` re-clamps on a reflow-driven count change). The count-source is the **growing SEALED index's
`pageCount`**, published as Compose state exactly as #137 already publishes `index`.

- **Ship the REAL-COUNT-ONLY variant (default, rule-51-clean, no shrink hazard).** The pager's
  `pageCount` is the *sealed-so-far* count. The user pages forward only up to the sealed frontier;
  nearing it triggers on-demand extension (which grows the count before the edge). Because pagination is
  doc-start-forward + append-only + sealed, the count only GROWS — never shrinks, never shows a phantom
  page. No new visible state → rule-51-clean.
- **Growing-count FALLBACK (Gate-2 R2 Medium 4).** Runtime `HorizontalPager` behavior when `pageCount`
  GROWS is undocumented by Google, so WI-5c's connected "growing count does not yank the current page"
  test is the GATE (a BLOCKING acceptance criterion, not an assumption). **If WI-5c FAILS, the fallback
  is:** (a) recreate `PagerState` keyed by the saved source offset / current page on a safe append
  boundary (so the recreated state's `initialPage` maps to the same source offset under the grown count),
  OR (b) hold the published `pageCount` STABLE until a proven-safe append boundary and grow it in BATCHES
  (fewer, larger recompositions at boundaries where the current page is not near the seam). The plan ships
  real-count-only first because it is the simplest rule-51-clean shape; the fallback is pre-designed so a
  WI-5c failure does not reopen Gate-1.
- The estimated-upper-bound variant (seed the pager with an estimate so the user can fling far ahead,
  render a "measuring…" placeholder beyond the frontier) is REJECTED for v1: the estimate can over-count
  and SHRINK the pager (yank hazard), and the placeholder page is a new visible surface needing a rule-51
  `needs-design` issue. Documented as a follow-up only.

**Jump semantics — QUEUED / EVENTUAL (Gate-2 R2 Medium 3 + Low):**

A jump (bookmark / find / TTS / scrubber / resume) supplies a SOURCE UTF-16 offset. Against the current
sealed partial index:
1. **Offset within the sealed region** → `pageContaining` binary-searches the current `IntArray` exactly
   as today, and the pager scrolls to it. No change.
2. **Offset beyond the sealed frontier** → the request is **ENQUEUED**: `session.ensureMeasuredThrough(offset)`
   extends the index forward (sealing contiguous pages from the last sealed frontier until a sealed page
   whose range contains the target exists), off-main, coalesced with the background loop; the pager then
   scrolls to `pageContaining(offset)` once that snapshot lands. **The reader STAYS on the current page
   meanwhile — no freeze, no new UI.** Bounded by the frontier→target distance (honestly stated in
   acceptance — Gate-2 R1 High 4); deterministic tiling matches the background pass.
   - **There is NO visible pending affordance for a far jump after the first publish** — `txt-paged-loading`
     shows only while `idx == null` (`TxtReaderBody.kt:286`), i.e. before the first sealed window. v3 does
     NOT claim reuse of the loading affordance for on-demand extends (Gate-2 R2 Medium 3). A designed
     pending/"measuring…" affordance is an explicit OUT-of-scope rule-51 follow-up.
   - **`JumpResult` wording (Gate-2 R2 Low):** a synchronous `JumpResult.Succeeded` returned by a
     bookmark/search feeder means the request was **ENQUEUED**, NOT that the pager has already LANDED. The
     `JumpResult` type/callers are worded enqueued-vs-landed; the actual landing is EVENTUAL (asserted by
     tests as eventual landing, never as a synchronous position — see WI-5a/WI-6).
3. **Resume anchor at open** (`initialSourceOffset`) → pagination starts at chunk 0; the conditional
   auto-scroll reveal (above) shows page 0 immediately and auto-scrolls to the anchor's page the instant
   the forward pass seals it — IF the user has not taken over. No backward completion; page numbers never
   shift.

**Rejected alternatives:**
- **Anchor-start first window** — Gate-2 R1 Critical 1: non-deterministic against the sequential
  paginator. Rejected; replaced by doc-start-forward.
- **Estimated-upper-bound pager count** — shrink/yank hazard + a new "measuring…" surface needing
  design. Named follow-up.
- **Chunk-parallel measurement** (measure N chunk-ranges concurrently) — page-start offsets must be
  stitched contiguously (a page spans chunk boundaries; the min-one-line/oversized-split state is
  sequential), so parallelism needs a careful join and risks the exact-offset invariants. Named
  follow-up if the background pass can't keep ahead of a fast reader on the largest books.
- **Precomputed persistent page cache** (store the `IntArray` in Room keyed by book+layout hash) — the
  real fix for *instant deep resume*, but adds a schema/DataStore surface + cache-invalidation on every
  font/margin change; orthogonal to "first open is bounded." **Named follow-up (the honest answer to
  instant deep-resume — Gate-2 R1 High 4).**
- **A designed "measuring…" pending affordance for far jumps** — a new visible surface, needs a rule-51
  `needs-design` issue. Named follow-up (Gate-2 R2 Medium 3); v3 ships the no-new-UI EVENTUAL-landing
  semantics instead.
- **Lower measurement cost per line** (skip Compose `TextMeasurer`, approximate with font metrics) —
  breaks the determinism contract (phase-1 breaks MUST equal phase-2 render breaks;
  `ComposeLineMeasurer` header). Not touched.

### UI / rule-51

No new user-visible surface. The already-designed #137 paged surface, loading placeholder
(`txt-paged-loading`), scrubber, and tap-zones are reused unchanged. The deep-resume conditional
auto-scroll reuses the existing programmatic scroll (a DISTINCT one-shot Compose state from
`localScrollTarget`, but the same scroll mechanism); a far on-demand jump is EVENTUAL with NO new pending
state (the reader stays on the current page). The only *possible* new visible elements — a "measuring…"
placeholder page (estimated-upper-bound variant) or a disabled/pending affordance for a far jump — are
why those are OUT of scope: each would require a `needs-design` issue (rule 51). **This plan ships the
real-count-only + conditional-auto-scroll + eventual-landing variants precisely so it stays rule-51-clean
with no design round-trip.**

## Surface area (file-by-file, with ACTUAL current signatures verified against the code)

### `reader/paged/TxtPaginator.kt` (MODIFY — the resumable measure core)

Current phase-1 signature (verified, `TxtPaginator.kt:85-92`):
```kotlin
suspend fun index(
    document: TxtDocument, style: TextStyle, contentBox: PageContentBox,
    measurer: LineMeasurer, token: PaginationToken, isMarkdown: Boolean = false,
): TxtPageIndex
```
It loops `for (chunkIndex in 0 until document.chunkCount)` (`:118`), carries sequential page-break state
`currentPageHeight`/`pageHasLine` (`:105-107`) across chunks, pushes page-starts into a private
`GrowableIntArray` via `tryStartPage(candidate)` (strict-advance, `:113-116`), uses
`sourceOffsetForLineStart(...)` (`:221`), `checkCancelled(token)`, the paginator-local
`LocalChunkOffsetMapper`, and returns `TxtPageIndex(starts.toIntArray(), docEndExclusive = docEnd)`
(`:149`).

Changes:
- **Extract the per-chunk measure loop body into a private resumable core** that (a) always starts at
  chunk 0 (or resumes from a saved cursor whose state descends from chunk 0 — NEVER an arbitrary
  anchor), (b) emits SEALED page boundaries via an `emit` callback as each new page start is discovered
  (a page is sealed the moment the *next* page's start is known; the FINAL page seals at doc end — Gate-2
  R2 Medium 1), and (c) stops after sealing K pages OR reaching a target source offset OR reaching doc
  end. Factor into a private `measureFrom(cursor, stopCondition, emit)` so the same tiling logic
  (min-one-line, oversized-split, strict-advance) lives in ONE place — do NOT fork the loop. The cursor
  holds `nextChunk`, `carryHeight`, `carryHasLine`, `lastSealedStart`, `frontierSourceOffset`,
  `isComplete` — **private to `TxtPaginator`/`PaginationSession`, never exposed publicly** (Gate-2 R1
  Medium 2).
- **Keep `index(...)` as the "measure to completion" path** (used by the background completion + the
  perf benchmark), re-implemented in terms of the resumable core so behavior is byte-identical for all
  docs (the 43 existing JVM `TxtPaginatorTest`/`PageOffsetMapTest` MUST stay green). Simplest:
  `index(...)` = start a cursor at chunk 0 with an unbounded stop condition and collect every sealed
  start (plus the final in-progress page sealed at doc end).
- **Add resumable measure entry points** consumed ONLY by `PaginationSession` (kept `internal`):
  ```kotlin
  internal fun freshCursor(document, style, contentBox, isMarkdown): MeasureCursor          // at chunk 0
  internal suspend fun measureThroughOffset(cursor, targetOffset, token): MeasureCursor      // seal until target covered or complete
  internal suspend fun measurePages(cursor, additionalPages, token): MeasureCursor           // seal N more pages or complete
  ```
  These return an advanced (immutable-copy) cursor + the pages sealed since the last call via the `emit`
  callback the session provides. `MeasureCursor` is `internal` — the public API is the session's
  commands (below), never a raw cursor.
- **`renderPage(...)` UNCHANGED** — it renders one page from `pageStart(page)`/`pageEndExclusive(page)`;
  a SEALED partial index answers those correctly for any published page.
- New companion constants: `DEFAULT_INITIAL_WINDOW_PAGES`, `DEFAULT_EXTEND_PAGES`.

### `reader/paged/PaginationSession.kt` (NEW — the single owner; Gate-2 R1 High 2/5 + R2 Medium 2, R1 Low 1)

A new Kotlin file (Gradle-glob safe — the rule-55 "new Swift file" caveat is iOS-pbxproj-specific and
does not apply to Kotlin). It is the ONE owner of the incremental lifecycle, superseding the split
ownership the navigator + body currently have over `activeToken`/Compose `index` state.

```kotlin
class PaginationSession(
    private val paginator: TxtPaginator,
    private val worker: CoroutineDispatcher = Dispatchers.Default,
) {
    // A single Mutex + one worker coroutine serialize ALL slice mutation. The cursor + sealed
    // page-start list + the ONE LineMeasurer instance + the PaginationToken/generation live HERE,
    // private. Publication is on the main thread as immutable snapshots.

    /** Start a fresh doc-start-forward pass; publish the first sealed window; launch background
     *  completion. Cancels/supersedes any prior generation (reflow reuses this). */
    suspend fun openFromStart(
        document: TxtDocument, style: TextStyle, contentBox: PageContentBox,
        measurer: LineMeasurer, isMarkdown: Boolean, resumeAnchorOffset: Int,
        onSnapshot: (TxtPageIndex) -> Unit, onReveal: (revealOffset: Int) -> Unit,
    )

    /** Ensure sealed pages cover [sourceOffset] (extend forward if beyond the frontier), coalesced
     *  with the background loop; returns the snapshot in which pageContaining(offset) is exact. */
    suspend fun ensureMeasuredThrough(sourceOffset: Int): TxtPageIndex

    /** The latest published immutable sealed snapshot (or null before the first window). */
    fun snapshot(): TxtPageIndex?

    /** Supersede: cancel the active generation's token so no stale pass publishes (reflow/dispose). */
    fun supersede()
}
```

**Mutex + worker supersede/publish contract (Gate-2 R2 Medium 2 — made precise):**

- **Page/window-sized critical sections — NEVER hold the mutex for an unbounded full-book run.** The
  background completion loop measures ONE window (or one page) per acquire, then releases; it re-acquires
  for the next window. So an on-demand `ensureMeasuredThrough` never waits behind the whole ~85 s pass —
  it interleaves at the next window boundary (coalesced, still single-writer). The mutation lock is held
  only for the duration of measuring/appending one bounded window's sealed starts.
- **Generation check immediately before EVERY publish.** Before building or handing off any snapshot, the
  session re-reads the active generation; if it changed (a `supersede`/reflow raced in), the publish is
  DROPPED and the loop exits. A stale-generation pass never publishes.
- **Snapshot via `AtomicReference` (or a mutex-guarded `snapshot()`), published AFTER releasing the
  mutation lock.** The immutable `TxtPageIndex` of the sealed pages is built and stored in an
  `AtomicReference`; the main-thread `onSnapshot`/`onReveal` callbacks are invoked AFTER the mutation lock
  is released — NEVER while holding it. No main-thread callback runs under the lock (no lock-order
  inversion, no main-thread work blocking the worker).
- **One writer:** the background completion loop and every `ensureMeasuredThrough` acquire the same
  `Mutex`; on-demand requests are coalesced with the background worker — never two concurrent slice
  mutations (Gate-2 R1 High 2). The ONE `LineMeasurer` is used only under the mutex (Gate-2 R1 Low 1).
- **Immutable snapshots on main:** each seal-and-publish builds a NEW immutable `TxtPageIndex` of the
  SEALED pages and calls `onSnapshot` on the main thread (the body's `LaunchedEffect` scope), exactly as
  a reflow republishes today. No mutable state crosses a thread boundary.
- **Generation/token:** reuses the existing `PaginationToken` + a monotonic generation; a superseded
  generation's token is cancelled and its worker stops publishing (identical to the current
  `checkCancelled` + generation discipline in `TxtPageNavigator.reconcileAfterReflow`).
- **`onReveal`** fires once, when the resume anchor's page is first sealed — carrying the resume SOURCE
  OFFSET (the body decides, conditionally + index-aware, whether to auto-scroll — Gate-2 R2 High 1).
  Absent (anchor == 0 / near start), the first snapshot already contains it.

### `reader/paged/TxtPageIndex.kt` (MODIFY — sealed partial support)

Current (verified, `TxtPageIndex.kt:21-72`): ctor `(pageStartsUtf16: IntArray, docEndExclusive: Int,
isDegenerate: Boolean = false)`; members `pageCount`, `isEmpty`, `pageStart(page)`,
`pageEndExclusive(page)` (= next start or `docEndExclusive`, `:46-51`), `pageContaining(...)` (binary
search, clamps, `:58-67`), `pageStartsUtf16` (defensive copy), `companion degenerate()`. Immutable;
assumes a COMPLETE index; `[0] == document start` (`:17-19`).

Changes (keep it immutable — a windowed pass publishes a NEW immutable index each republish, exactly as
a reflow does today; page 0 is ALWAYS document start since pagination is doc-start-forward, so
`pageContaining(0) == 0` always holds — Gate-2 R1 Critical 2):
- **`val isComplete: Boolean = true`** (default true so every existing construction is unchanged); a
  partial windowed index sets false.
- **`val frontierSourceOffset: Int`** — the FRONTIER MARKER: the source offset up to which pages are
  SEALED. It is NOT a page start (it is not in `pageStartsUtf16`); it == `docEndExclusive` when complete.
  **Because only SEALED pages are published, `pageEndExclusive(lastSealedPage)` for a partial index
  returns the frontier — which is the NEXT sealed page's start** (it exists in the in-progress cursor; a
  page is published only once its successor's start is known). This is the ONE subtle correctness change
  (Gate-2 R1 High 3) and it is well-defined precisely because we never publish an unsealed frontier page.
  Document it in the header + test it (Gate-2 R2 Medium 1: "known-but-unpublished next start"; the FINAL
  page's end is `docEndExclusive`, sealed at doc end).
- `pageContaining` for a beyond-frontier offset keeps the clamp as the *fallback*, but the SESSION is
  responsible for `ensureMeasuredThrough` BEFORE calling `pageContaining` for a beyond-frontier offset —
  so `TxtPageIndex` stays a pure data structure. Document the contract in the header.

### `reader/paged/TxtPageNavigator.kt` (MODIFY — delegate lifecycle to the session, keep pager seam)

Current (verified, `TxtPageNavigator.kt:44` `NOT thread-safe by design`; `activeToken` `:72`, `generation`
`:76`, `reconcileAfterReflow` `:150`): `var index: TxtPageIndex?`, `var currentPage`, `var
pendingScrollTarget`, `var activeToken`, monotonic `generation`. Methods `setIndex`, `pageContaining`,
`pageStart`, `currentSourceOffset`, `onPagerPageChanged`, `jumpToOffset(offset)` (currently synchronous:
`pageContaining` → set `currentPage` + `pendingScrollTarget`), `consumePendingScrollTarget`,
`reconcileAfterReflow`, private `publishReflow`, `clampPage`.

Changes (the navigator stays the Compose-free pager-position seam; the SESSION owns lifecycle + token +
publication + cache-invalidation, resolving the split ownership — Gate-2 R1 High 5):
- **`jumpToOffset` becomes async source-offset-aware** — `suspend fun jumpToOffset(sourceOffsetUtf16:
  Int, session: PaginationSession)`: if the current index is partial AND the offset is beyond
  `frontierSourceOffset`, `session.ensureMeasuredThrough(offset)` first (off-main, coalesced), install
  the extended snapshot, THEN `pageContaining` + set `pendingScrollTarget`. Within the sealed region it
  is the current synchronous path. This is the mechanism WI-5a's protocol change routes through. The jump
  is EVENTUAL for a beyond-frontier offset (Gate-2 R2 Medium 3/Low).
- **`reconcileAfterReflow` delegates to `session.openFromStart(...)`** with the captured source offset as
  the resume anchor (a reflow = "re-open windowed pagination from the captured offset"). The navigator no
  longer owns `activeToken`/its own `index()` call — the session does; the navigator receives published
  snapshots via a callback and clamps `currentPage`/`pendingScrollTarget` to
  `pageContaining(capturedOffset)`. The generation/token discipline moves into the session but is
  otherwise unchanged.
- Keep `setIndex`, `pageContaining`, `pageStart`, `currentSourceOffset`, `onPagerPageChanged`,
  `consumePendingScrollTarget`, `clampPage` (pure pager-position state). Add `val isComplete: Boolean
  get() = index?.isComplete ?: false` the body can observe.

### `reader/TxtReaderBody.kt` — `TxtPagedBody` (MODIFY — session integration, sealed-cache policy, conditional reveal)

Current (verified): the `LaunchedEffect(contentBox, effectiveStyle, marginDp, document)` at `:248` OWNS
`activeToken` (`:241`) and the Compose `index` state (`:231`) directly, calling `paginator.index(...)`
(whole-doc blocking pass) then `navigator.setIndex`; `renderCache.clear()` on reflow (`:258`); pager
`rememberPagerState(initialPage=…, pageCount = { pageCount })` (`:297-300`) with `pageCount =
idx.pageCount` (`:296`); the user-swipe path `snapshotFlow { pagerState.settledPage }` (`:343-349`); the
one-shot reflow-clamp scroll `localScrollTarget` (`:356-367`, CLAMPS to the current `pageCount` and
CLEARS); the external jump consumes `jumpRequest: Int?` as a target PAGE (`:147, :374-383`); `txt-paged-loading`
shown only while `idx == null` (`:286`); `beyondViewportPageCount = 1` (`:417`); `PagedRenderCache(maxCached
= 6)` (`:544`); save via `onSaveSourceOffset(navigator.currentSourceOffset())` (`:348, :365, :381`).

Changes (WI-5b):
- **Replace the single blocking `index(...)` call with the session lifecycle.** The `LaunchedEffect`
  captures the resume anchor (unchanged), then drives `session.openFromStart(..., resumeAnchorOffset =
  captured, onSnapshot = { index = it; navigator.setIndex(it) }, onReveal = { revealOffset -> pendingResumeReveal
  = revealOffset })`. The first sealed snapshot publishes quickly → `index` state updates → the first page
  renders. Background republishes update `index` (and thus `pageCount`) reactively — the pager already
  re-reads `pageCount = { idx.pageCount }` and re-clamps. The **session** now owns the token/cancellation
  (the body no longer holds `activeToken` — Gate-2 R1 High 5); the `LaunchedEffect`'s only job is to drive
  the session and mirror its published snapshots into Compose state.
- **Conditional resume reveal (Gate-2 R2 High 1) — a DISTINCT one-shot from `localScrollTarget`.** Add
  two body flags:
  - `userInteractedSinceOpen: Boolean` — set true on the FIRST user-driven `settledPage` change in the
    existing `snapshotFlow { pagerState.settledPage }` collector (`:343-349`). (Distinguish a user swipe
    from a programmatic scroll: the programmatic scrolls set their own targets, so a `settledPage` change
    with no pending programmatic target is user-driven.)
  - `pendingResumeReveal: Int?` — the resume SOURCE OFFSET (or `(generation, targetPage, minPageCount)`)
    the session's `onReveal` sets. A DEDICATED collector, SEPARATE from the `localScrollTarget` consumer,
    consumes it: on each `index` publish, if `pendingResumeReveal != null` AND the published index now
    CONTAINS that page (`idx.pageCount > pageContaining(revealOffset)` / the offset is within the sealed
    frontier) AND `!userInteractedSinceOpen` AND the shown offset is still the initial default, then
    scroll to `pageContaining(revealOffset)` and clear `pendingResumeReveal`. Otherwise: if the user has
    taken over, DROP it (clear, no scroll); if the offset is still out of range, LEAVE it pending (NEVER
    clamp-and-clear an out-of-range target — the exact hazard the `localScrollTarget` consumer at
    `:356-367` creates). This collector never touches `localScrollTarget`, and `localScrollTarget`'s
    consumer never touches the resume reveal — the two are independent one-shots (Gate-2 R2 High 1).
- **`localScrollTarget` stays the ordinary IN-RANGE scroll.** The reflow clamp and the on-demand-extend
  landing set `localScrollTarget` to an ALREADY-PUBLISHED (in-range) page; its consumer's clamp-and-clear
  (`:356-367`) is correct for those because the page is within `pageCount`. It is NOT used for the resume
  reveal.
- **`pageCount` becomes the live growing SEALED `idx.pageCount`** (already the mechanism; now grows over
  time, append-only, never shrinks). **On-demand forward extension:** when a settled/target page is within
  `EXTEND_MARGIN` of `pageCount - 1` on a partial index, a Compose-observable target drives
  `session.ensureMeasuredThrough(...)` (NO busy loop — the idling-resource lesson from #137's
  `TxtReaderBody` is binding: "NO frame-poll loop").
- **Sealed-page render-cache policy (Gate-2 R1 High 3):** a background APPEND publishes only SEALED pages
  and NEVER changes an already-published page's `[start, end)`, so an append must NOT clear
  `PagedRenderCache`. **Only a reflow clears it** (the reflow renumbers pages — the existing `:258`
  `renderCache.clear()` stays, but ONLY on the reflow branch, not on a plain background append). Document
  + test this invariant (WI-5b JVM-observable via the session snapshot ranges; WI-5c connected).
- **Loading surface reused unchanged for the FIRST OPEN ONLY** (`txt-paged-loading` while `index == null`,
  `:286`; the FIRST sealed window clears it in < 2 s for a fresh open instead of ~85 s). **A far on-demand
  extend does NOT show a loading affordance (Gate-2 R2 Medium 3)** — the reader stays on the current page
  and the jump lands EVENTUALLY when the session measures through the target. No new visible state (rule 51).
- **Deep-resume reveal** uses the DEDICATED conditional collector above (NOT the reflow's `localScrollTarget`):
  the session's `onReveal` sets `pendingResumeReveal`; the collector auto-scrolls only if the user has not
  taken over and the page is in range.

### `reader/TxtReaderActivity.kt` (host — MODIFY, WI-5a)

Verified: per-open `pagedPaginator`/`pagedNavigator`/`pagedRenderCache`; `pagedJumpRequest`;
`TxtPagedBody(...)` call site; the mode-aware `jumpToOffset` seam (`:572-585`) SYNCHRONOUSLY converts a
source offset → page via `pagedNavigator.pageContaining(target)` (`:580`) then raises `pagedJumpRequest.value
= <page>`; the feeders all pass a SOURCE offset into `jumpToOffset(target)` — bookmark (`:632`, returns
`JumpResult.Succeeded`), annotation (`:641`), search (`:698`, returns `JumpResult.Succeeded`), scrubber
(`:731`); the TTS-follow effect (`:597-605`) raises `pagedJumpRequest.value` to a PAGE from
`pagedTtsFollowTarget`; progress `TxtProgress.fraction(pagedOffset.value, …)` source-offset-based; page
labels hardcoded `displayPage = 0, totalPages = 0`. `TxtReaderActivity.kt` is **1552 lines**.

Change (WI-5a — the async source-offset jump protocol, EVENTUAL landing):
- **`TxtPagedBody`'s external-jump parameter becomes a SOURCE OFFSET, not a page.** Rename/retype
  `jumpRequest: Int?` (a page) → a source-offset request (`jumpToSourceOffset: Int?`); the body's jump
  `LaunchedEffect` (`:374-383`) does `session.ensureMeasuredThrough(offset)` (via the navigator's async
  `jumpToOffset`) THEN scrolls to `pageContaining(offset)` — instead of consuming a pre-computed page. The
  landing is EVENTUAL for a beyond-frontier offset (Gate-2 R2 Medium 3).
- **The host seam (`:572-585`) stops converting source→page synchronously.** It raises the SOURCE offset
  directly: `pagedJumpToOffset.value = target` (a source offset), and no longer calls
  `pagedNavigator.pageContaining` on the UI thread. The "no index yet → skip" guard stays (before the
  first sealed window the offset is queued or dropped as today).
- **`JumpResult` wording (Gate-2 R2 Low):** the bookmark/search feeders (`:632, :698`) that return
  `JumpResult.Succeeded` synchronously mean the request was **ENQUEUED**, not that the pager has already
  LANDED. Reword the `JumpResult` doc / the feeder callsites (a comment + the type's KDoc) to say
  enqueued-vs-landed so a reader is not misled that a far jump has completed; the actual landing is
  EVENTUAL (asserted by WI-5a/WI-6 tests as eventual, never as a synchronous position).
- **All feeders unchanged in routing** — bookmark/annotation/search/scrubber already pass source offsets
  into the seam; only the seam's internal conversion, the body's request type, and the `JumpResult`
  wording change. The **TTS-follow effect (`:597-605`)** switches from raising a PAGE (`pagedTtsFollowTarget`
  returns a page) to raising the spoken SOURCE offset (`tts.charStart`), letting the session/navigator do
  extend-then-resolve — so TTS-follow into an unmeasured region is correct too (`pagedTtsFollowTarget` is
  refactored to return a source offset or a skip signal).
- Test seams (`testPagedJumpRequest`, `TxtReaderActivityJumpSeam`) retype to source offsets correspondingly.

### Out of scope (files NOT changed)

`reader/paged/PageOffsetMap.kt` (lazy per-page, answers from a SEALED partial index — MD dual-affinity
untouched); `reader/paged/ComposeLineMeasurer.kt` (determinism seam reused; concurrent use forbidden by
the single session — Gate-2 R1 Low 1); the scroll path (`TxtBody`); EPUB/PDF readers; `ReaderSettings*` (no
new setting/schema); selection/highlight/wash/bookmark/TTS/find features (they route through
`pageContaining` + `PageOffsetMap` + the source-offset jump seam, preserved). The estimated-upper-bound
pager count, the persistent page-index cache, and a designed "measuring…"/pending far-jump affordance are
named follow-ups, NOT #138.

## Correctness invariants that must NOT regress (each maps to a test)

1. **Exact UTF-16 offsets / contiguous tiling** — the resumable core, run from chunk 0 to completion,
   produces a byte-identical page-start `IntArray` to today's `index(...)` (the real, provable property —
   Gate-2 R1 Critical 1); windows tile contiguously with no dropped/duplicated source char across a
   boundary. (WI-3.)
2. **Doc-start / append-only page numbering** — page 0 is ALWAYS document start; new pages append at the
   end; the array is NEVER prepended and existing page numbers NEVER change; `pageContaining(0) == 0`
   always (Gate-2 R1 Critical 2). (WI-3 + WI-4.)
3. **Sealed-page invariant + pending-start model** — only pages with a FINAL `[start, end)` are published;
   an append never changes an already-published page's range; `frontierSourceOffset` is a marker, NOT a
   page start; `pageEndExclusive(last-sealed)` == the next sealed start; the FINAL page seals at doc end;
   page 0 has a +1-page lookahead latency (Gate-2 R1 High 3 + R2 Medium 1). (WI-2 + WI-3.)
4. **Single-writer serialization + bounded critical sections** — the background completion loop and every
   `ensureMeasuredThrough` are serialized through the session's ONE mutex/worker with PAGE/WINDOW-sized
   critical sections; the mutex is never held for a full-book run; a generation check precedes every
   publish; main-thread callbacks fire AFTER the lock releases; no lost update; no concurrent
   `LineMeasurer` use (Gate-2 R1 High 2, Low 1 + R2 Medium 2). (WI-4.)
5. **Min-one-line forward progress** — `tryStartPage` strict-advance in the resumable core; no windowed
   path emits a zero-advance page; `measureThroughOffset`/`measurePages` from a cursor also guarantee
   forward progress. (WI-3.)
6. **Degenerate-box degrade** — `contentBox.isDegenerate` returns `degenerate()` BEFORE any windowing;
   the body still degrades to scroll. (WI-3/WI-5b.)
7. **MD dual-affinity** — `renderPage` + `PageOffsetMap` unchanged; a page from a sealed partial index
   uses the same per-chunk `MarkdownOffsetMap` composition. (WI-5c connected.)
8. **Position save/restore by source offset + conditional reveal** — the saved position is a
   `charOffsetUTF16` (current page START offset); the deep-resume CONDITIONAL auto-scroll lands on the
   right page once the forward pass seals it AND the user has not taken over; a user who pages before the
   anchor seals is NOT yanked; saving persists the offset, never a page number (Gate-2 R2 High 1). (WI-4
   + WI-5b/5c.)
9. **Reflow reconciliation** — a font/margin/rotation change captures the current source offset, cancels
   the in-flight (windowed + background) pass via the session's generation token, restarts
   `openFromStart` from the captured offset, and clamps to `pageContaining(captured)` via
   `localScrollTarget`. A reflow (and ONLY a reflow) clears `PagedRenderCache`. (WI-4 + WI-5b/5c.)
10. **Cancellation on settings/rotation change** — the `PaginationToken` + monotonic generation (in the
    session) guard BOTH the windowed first pass and the background loop; a superseded pass never
    publishes (generation re-checked immediately before every publish — Gate-2 R2 Medium 2). (WI-4.)
11. **Memory posture** — no new full-book structure; one `IntArray` (KB) + the unchanged 6-page
    `PagedRenderCache`; peak PSS stays ~≤300 MB (regression-checked by the perf benchmark's memory
    sampler). (WI-6.)

## Work-item sequencing

| WI | Tier | Summary | Files | Depends | Lane? |
|----|------|---------|-------|---------|-------|
| WI-1 | Foundational | Extract the phase-1 measure loop into a private resumable core (`measureFrom` + a private `MeasureCursor`) inside `TxtPaginator`, ALWAYS starting at chunk 0; re-implement `index(...)` in terms of it — behavior byte-identical (43 existing JVM tests stay green). No windowing/session yet. | `TxtPaginator.kt` (+JVM test) | — | Yes (JVM) |
| WI-2 | Foundational | `TxtPageIndex` sealed-partial support: `isComplete`, `frontierSourceOffset` (a FRONTIER MARKER, not a page start), `pageEndExclusive(last)`→frontier (== next sealed start) for a partial index, final page's end == docEnd; defaults keep every existing construction complete; `pageContaining(0)==0`; +1-lookahead note (Gate-2 R2 Medium 1). | `TxtPageIndex.kt` (+JVM test) | — | Yes (JVM; ∥ WI-1) |
| WI-3 | Foundational | Resumable measure entry points (`measureThroughOffset`, `measurePages`) + the SEAL discipline (publish only pages with a final range; the final page seals at doc end) inside `TxtPaginator`. Deterministic-tiling equivalence proved vs `index(...)`: doc-start incremental-to-completion == `index(...)`, byte-identical. | `TxtPaginator.kt` (+JVM test) | WI-1, WI-2 | Yes (JVM) |
| WI-4 | Foundational | `PaginationSession` (NEW file): single mutex/worker owner of the cursor + sealed list + one measurer + token/generation; commands `openFromStart`/`ensureMeasuredThrough`/`snapshot`/`supersede`; PAGE/WINDOW-sized critical sections; generation-checked, lock-released-before-main publish; immutable snapshots on main; background completion loop coalesced with on-demand extend. `TxtPageNavigator` delegates lifecycle to it (async `jumpToOffset`, `reconcileAfterReflow` → `openFromStart`). | `PaginationSession.kt` (new), `TxtPageNavigator.kt` (+JVM tests) | WI-3 | Yes (JVM) |
| WI-5a | Behavioral | Async SOURCE-OFFSET jump protocol (EVENTUAL landing): retype `TxtPagedBody`'s external jump to a source offset; the host seam raises the source offset (no synchronous source→page); route bookmark/annotation/search/scrubber/TTS-follow through the session's extend-then-resolve; reword `JumpResult` to enqueued-vs-landed (Gate-2 R2 Low). Retype the test seams. | `TxtReaderActivity.kt`, `TxtReaderBody.kt` (signature/seam) (+connected test) | WI-4 | Yes (connected, width-1) |
| WI-5b | Behavioral | `TxtPagedBody` windowed lifecycle + `PaginationSession` integration + sealed-page render-cache policy: fast first-window open, reactive growing `pageCount`, on-demand forward extension near the frontier, CONDITIONAL user-cancelable deep-resume reveal (`onReveal` → `pendingResumeReveal`, a one-shot DISTINCT from `localScrollTarget`, index-aware, dropped if the user paged away, never clamp-and-cleared out of range — Gate-2 R2 High 1), append-does-NOT-clear-cache, reflow (only) clears. Body no longer owns `activeToken`. | `TxtReaderBody.kt` (+connected test) | WI-5a | Yes (connected, width-1) |
| WI-5c | Behavioral (BLOCKING) | Connected UX acceptance tests: fast first open; **growing-`pageCount`-does-NOT-yank on append (BLOCKING — if it FAILS, apply the Medium-4 fallback: recreate `PagerState` keyed by source offset, or hold count stable + batch)**; **user pages before the anchor seals → resume reveal DROPPED (no yank)**; **snapshot publish + reveal in the same publication → reveal lands on the GROWN index, not clamped to the old last page** (Gate-2 R2 High 1); far jump into an unmeasured region EVENTUALLY resolves correctly (no visible loading claim — Gate-2 R2 Medium 3); reflow mid-background re-paginates + clamps; position survives Paged→Scroll→Paged; render cache stays bounded (append doesn't blow it, reflow clears). | (`src/androidTest` only) | WI-5b | Yes (connected, width-1) |
| WI-6 | Behavioral (final) | Acceptance + perf: 14,059,220-byte CJK open-to-first-page < budget (fresh open); full index completes in the background byte-identical to #137's `index(...)` (30,695 starts); far jump EVENTUAL landing + honest distance bound (records latency, no UX SLA); memory unchanged → evidence file → VERIFIED. | `TxtPaginatorPerfBenchmark.kt` (+acceptance connected test) | all | No (final acceptance) |

Sequencing: WI-1 → (WI-2 ∥) → WI-3 → WI-4 → WI-5a → WI-5b → WI-5c → WI-6. WI-1/WI-3 both touch
`TxtPaginator.kt` → serialize; WI-2 (only `TxtPageIndex.kt`) parallels WI-1. WI-4 adds the new
`PaginationSession.kt` file (Gradle-glob safe; the rule-55 "new Swift file" caveat is iOS-pbxproj-specific
and does not apply to Kotlin). Behavioral WIs run connected on emulator-5554, width-1 (rule 52 Cause D;
pass `ANDROID_SERIAL=emulator-5554`, not the iOS sim-lease UDID — MEMORY #133); **ONE connected class per
run** (a comma-joined `class=A,B` fast-fails tests=0 — MEMORY #129/#133); use `compose.waitUntil` polling,
never bare `waitForIdle`, since the background pass runs across frames + the session debounces republishes
(the #133 debounce lesson — a merged-compile-only connected test is UNVERIFIED until the Gate-5 connected
run, so budget a re-verify pass — MEMORY #133).

## Test catalogue

### JVM (foundational — `src/test`, JUnit5 + `runTest`)
- **WI-1 `TxtPaginatorResumableCoreTest`:** the extracted `measureFrom` (from chunk 0) produces
  byte-identical page-starts to today's `index(...)` on: empty doc, one-line doc, oversized 4000-char
  chunk (mid-chunk split), CJK-no-whitespace, surrogate pairs, text exactly on a page boundary. The 43
  existing `TxtPaginatorTest`/`PageOffsetMapTest` stay green (regression guard).
- **WI-2 `TxtPageIndexSealedPartialTest`:** `isComplete` default true for every existing constructor;
  a partial index reports `frontierSourceOffset` as a MARKER (not present in `pageStartsUtf16`), and
  `pageEndExclusive(lastSealedPage) == frontier == the next sealed start` (NOT docEnd) for a non-final
  partial; **`pageEndExclusive(finalPage) == docEndExclusive`** for a complete index (final page sealed at
  doc end — Gate-2 R2 Medium 1); a **one-page doc** is complete with page 0's end == docEnd; `pageContaining`
  within the sealed region exact; `pageContaining(0) == 0` for a partial index (Gate-2 R1 Critical 2);
  beyond-frontier clamps to last sealed page (documented fallback); degenerate()/empty unchanged.
- **WI-3 `TxtPaginatorWindowingTest`:** windowing math (`measurePages(freshCursor, K)` seals the first K
  pages, cursor frontier == Kth page end); **the +1-page lookahead** — sealing page 0 requires measuring
  into page 1 (page 0's end == page 1's start); the FINAL page seals at doc end; **append equivalence** —
  `freshCursor` + repeated `measurePages`/`measureThroughOffset` until complete == `index(...)`,
  byte-identical (the load-bearing property, Gate-2 R1 Critical 1); **sealed invariant** — an append never
  mutates a previously-emitted page's `[start, end)` (Gate-2 R1 High 3); extend-through-offset seals
  exactly enough to cover X, `pageContaining(X)` exact; cancellation aborts a resumable pass mid-loop;
  min-one-line across a window boundary.
- **WI-4 `PaginationSessionTest` + `TxtPageNavigatorWindowedTest`:**
  - `PaginationSession`: `openFromStart` publishes the first sealed window then background-completes to
    the full index; `ensureMeasuredThrough(beyondFrontier)` extends + returns a snapshot where
    `pageContaining` is exact; **single-writer serialization + bounded critical sections** — a background
    loop + a concurrent `ensureMeasuredThrough` never interleave a lost update (assert the final sealed
    list == the deterministic full list, and that the ONE measurer is never entered re-entrantly — a
    counting fake measurer asserts no concurrent `measure` call, Gate-2 R1 High 2/Low 1); **the mutex is
    never held across a full-book run** (a slow fake measurer lets an `ensureMeasuredThrough` interleave
    at a window boundary — it does not block for the whole background pass); **stale-generation publish
    dropped** — after `supersede`, a mid-flight window's publish is DROPPED (the generation re-check
    before publish, Gate-2 R2 Medium 2) — assert no `onSnapshot` fires post-supersede; **no main callback
    under the lock** — `onSnapshot`/`onReveal` observed only after the mutation lock is released (a fake
    that records lock-held state at callback time asserts released); `onReveal` fires exactly once with
    the resume offset when the anchor page seals.
  - `TxtPageNavigator`: first-window publish sets partial index + `currentPage == pageContaining(captured)`;
    background append does not move `currentPage`; async `jumpToOffset(beyondFrontier, session)`
    extends-then-resolves to the exact page (EVENTUAL); reflow mid-background delegates to `openFromStart`
    + clamps; real-count-only convergence with no shrink on append.

### Connected (behavioral — `src/androidTest`, `createComposeRule`, emulator-5554, ONE class/run — MEMORY #133)
- **WI-5a `TxtPagedSourceOffsetJumpConnectedTest`:** a source-offset jump (bookmark/search/scrubber/TTS)
  into a SEALED region lands on the right page; a jump BEYOND the sealed frontier triggers
  extend-then-resolve and EVENTUALLY lands on the right page (the reader stays on the current page
  meanwhile — assert eventual landing, NO visible loading state — Gate-2 R2 Medium 3); the feeders all
  route through the source-offset seam. `compose.waitUntil` polling.
- **WI-5b `TxtPagedWindowedConnectedTest`:** first page renders quickly (partial sealed index;
  `txt-paged-loading` clears fast); paging past the initial window grows the count (on-demand extension)
  with no gap; deep-resume opens page 0 then CONDITIONALLY auto-scrolls to the resume page once its page
  seals (user did not interact); append does NOT clear the render cache (a page re-visited after an append
  is a cache hit); a font-size change mid-background re-paginates + clamps to the saved offset AND clears
  the cache. `compose.waitUntil`.
- **WI-5c `TxtPagedWindowedAcceptanceConnectedTest` (BLOCKING):**
  - **growing-count-no-yank** — the pager's current page is unaffected by an end-append (the Gate-2 R1
    Medium 1 connected proof; BLOCKING — a FAILURE triggers the Gate-2 R2 Medium 4 fallback: recreate
    `PagerState` keyed by source offset, or hold count stable + batch);
  - **user pages before the anchor seals → the resume reveal is DROPPED** — swipe away during the
    background pass; when the anchor page later seals, the pager is NOT yanked (Gate-2 R2 High 1);
  - **snapshot + reveal in the same publication → the reveal lands on the grown index** — an anchor whose
    page is sealed in the SAME republish that grows the count lands on the correct grown page, NOT clamped
    to the old last page (Gate-2 R2 High 1);
  - far scrubber jump into an unmeasured region EVENTUALLY lands correctly (no visible loading);
  - position survives Paged→Scroll→Paged; render cache stays bounded across appends + is cleared on reflow.
- **WI-6 acceptance:** **perf** — measure **open-to-first-page** = `openFromStart` → FIRST sealed-window
  publish on the REAL **14,059,220-byte** CJK book; assert **< 2 s (hard ceiling < 3 s)** for a FRESH
  (offset-0) open, independent of the 30,695-page total; separately assert the **full index still
  completes in the background** to the same 30,695 page-starts, byte-identical to #137's `index(...)`
  (the benchmark SUMMARY log is the cross-check), peak PSS ≤ ~300 MB (reuse the existing `MemorySampler`);
  **far-jump honesty** — a bookmark/find/TTS/scrubber to ~90% EVENTUALLY resolves to the correct page, and
  the test RECORDS the extend latency (does NOT hard-fail on a UX budget — Gate-2 R1 High 4: the bound is
  frontier→target distance, not a fixed UX SLA); **correctness cross-check** — the windowed full index ==
  the #137 non-windowed index (same 30,695 page-starts).

## Risks + mitigations

1. **HorizontalPager count changing under the user** — the count only GROWS (append-only, sealed,
   real-count-only); Compose re-reads `pageCount` + clamps; the current page (0..frontier) is unaffected
   by an end-append → no yank. Mitigation: real-count-only (no shrink), append-only growth (doc-start-
   forward → never prepend), extension margin so the frontier is invisible. **WI-5c asserts no visible
   jump on append (Gate-2 R1 Medium 1 — a BLOCKING test, not an assumption). FALLBACK if it fails
   (Gate-2 R2 Medium 4):** recreate `PagerState` keyed by the saved source offset / current page on a safe
   append boundary, OR hold `pageCount` stable until a proven-safe boundary and grow in batches.
2. **A jump target in an unmeasured region** — the session's `ensureMeasuredThrough` extends-then-resolves
   EVENTUALLY; deterministic tiling → exact. Worst case (far scrub before completion) measures
   frontier→target on-demand, off-main, coalesced with the background loop; **the reader stays on the
   current page — no freeze, no new UI (Gate-2 R2 Medium 3); NO loading affordance is shown after the
   first publish.** **Honestly bounded by document distance, not a UX budget (Gate-2 R1 High 4).** JVM
   extend-through-offset + WI-5a/6 connected far-jump tests assert EVENTUAL landing.
3. **A background pass racing a reflow OR racing an on-demand extend** — the session's single mutex/worker
   + monotonic generation serialize all slice mutation and reject stale generations; the background loop
   and `ensureMeasuredThrough` are coalesced (one writer) with PAGE/WINDOW-sized critical sections; a
   generation check precedes every publish; main callbacks fire after the lock releases (Gate-2 R2
   Medium 2). **`PaginationSessionTest` single-writer + bounded-critical-section + stale-generation-publish
   + no-callback-under-lock + reflow-mid-background tests (Gate-2 R1 High 2 + R2 Medium 2).**
4. **Append changing an already-published page's range** — dissolved by publishing only SEALED pages;
   the in-progress frontier page is never in a snapshot until its successor's start is known; `frontier`
   is a marker, not a page start (Gate-2 R2 Medium 1). **WI-3 sealed-invariant test + WI-5b
   append-doesn't-clear-cache connected test (Gate-2 R1 High 3).**
5. **Deep-resume auto-scroll fighting the user / lost-or-clamped reveal** — the reveal is CONDITIONAL
   (dropped if the user paged away), INDEX-AWARE (consumed only after the published index contains the
   page; NEVER clamp-and-cleared out of range), ONE-SHOT, and a DISTINCT Compose one-shot from
   `localScrollTarget` so a snapshot publish + a reveal in the same frame don't collide (Gate-2 R2
   High 1). **WI-5c "user pages before anchor seals" + "snapshot+reveal same publication" connected tests.**
6. **Deep resume is not instant** — acknowledged honestly (Gate-2 R1 High 4): windowing bounds a
   fresh/near-start open, not a deep resume (O(depth)). The conditional auto-scroll keeps the reader
   never-frozen (usable at page 0, auto-scrolls to the resume page when sealed IF the user has not taken
   over). Truly instant deep-resume is the **persistent page-index cache follow-up**, explicitly NOT #138.
7. **Estimate error making the scrubber jump** — moot: the real-count-only default has no estimate, and
   the scrubber/percent is `TxtProgress.fraction(sourceOffset, textLength)`, NOT page-derived (page labels
   are hardcoded `displayPage=0, totalPages=0`), so even a future estimated variant's count error never
   reaches the visible progress UI.
8. **Memory of the session** — no new full-book structure; the session holds the same growing `IntArray`
   + a few-int cursor + one measurer; the paginator-local mapper LRU is already bounded. **Perf
   benchmark's memory sampler regression-checks peak PSS.**
9. **On-demand extension can't keep ahead of a fling** — extension measures a margin ahead + the
   background pass runs continuously; worst case the pager briefly can't swipe past the last-sealed page
   (real-count-only) — acceptable, self-heals in a frame or two. Named follow-up: chunk-parallel
   background measurement if too slow on the largest books.
10. **Behavior change for small docs (regression)** — a small doc's first window may == the whole doc, so
    `openFromStart` publishes a complete sealed index immediately (a one-page doc seals at doc end),
    behavior identical to today. WI-1's byte-identical-core test + the 43 existing JVM tests staying green
    is the guard.

## Backward compat

No schema change; position stays `Locator.charOffsetUTF16` (layout-independent; paged saves the current
page's START source offset via the same conflated writer); existing saved positions open in either mode
(a deep resume conditionally auto-scrolls once its page seals); layout preference is the existing
device-local DataStore pref (default Scroll), unchanged; no backup-format impact; a downgrade to a
pre-#138 build reverts to the whole-doc blocking pass (no persisted state is windowing-specific).

## Open questions for Gate-2 (round 3 — confirmation)

1. **Budgets:** `DEFAULT_INITIAL_WINDOW_PAGES`, `DEFAULT_EXTEND_PAGES`, `EXTEND_MARGIN`, and the < 2 s
   fresh-open target — right for a Pixel-class emulator (the perf-evidence baseline)?
2. **Session shape:** a `Mutex` + one launched worker (page/window-sized critical sections) vs an
   actor-style `Channel<Command>` loop — both give single-writer serialization with bounded sections; the
   plan specifies mutex+worker for JVM-testability without an Android main-dispatcher, but confirm the
   reflow-supersede + generation-checked-publish path is clean under whichever shape.
3. **Reveal cancellation heuristic:** `userInteractedSinceOpen` set on the first user-driven `settledPage`
   change (distinguished from a programmatic scroll by the absence of a pending programmatic target) —
   confirm this reliably separates a user swipe from the programmatic reflow/extend scrolls in the current
   body.

## Model assumptions verified (for the Gate-2 auditor)

Signatures below were read from the actual files (not paraphrased), with the Gate-2 round-1 + round-2
corrections applied:
- `TxtPaginator.index(...)` = `TxtPaginator.kt:85-92`; whole-doc loop `for (chunkIndex in 0 until
  document.chunkCount)` at **`:118`**; sequential page-break state `currentPageHeight`/`pageHasLine` at
  **`:105-107`**, carried across chunks; `tryStartPage` strict-advance at `:113-116`;
  `sourceOffsetForLineStart` at `:221`; returns `TxtPageIndex(starts, docEndExclusive)` at `:149`.
- `TxtPageIndex` = `TxtPageIndex.kt:21-72` ctor `(pageStartsUtf16, docEndExclusive, isDegenerate=false)`;
  `[0] == document start` documented at **`:17-19`**; `pageCount`/`isEmpty`/`pageStart`/`pageEndExclusive`
  (= next start or `docEndExclusive`, **`:46-51`**)/`pageContaining` (binary search, clamps,
  **`:58-67`**)/`pageStartsUtf16`/`degenerate()`; immutable + complete-assuming.
- `TxtPageNavigator` = `TxtPageNavigator.kt`; **`NOT thread-safe by design` at `:44`**; `activeToken` at
  **`:72`**, `generation` at **`:76`**, `reconcileAfterReflow(...)` at **`:150`**; `index?`, `currentPage`,
  `pendingScrollTarget`; `jumpToOffset` currently SYNCHRONOUS (`pageContaining` → set
  `currentPage`+`pendingScrollTarget`); `setIndex`/`pageContaining`/`pageStart`/`currentSourceOffset`/
  `onPagerPageChanged`/`consumePendingScrollTarget`/`reconcileAfterReflow`/`publishReflow`/`clampPage`.
- `TxtPagedBody` = `TxtReaderBody.kt`; the `LaunchedEffect` at `:248` OWNS `activeToken` (`:241`) and the
  Compose `index` state (`:231`) directly → `paginator.index(...)`; `renderCache.clear()` on reflow at
  `:258`; `rememberPagerState(pageCount = { pageCount })` `:297-300` with `pageCount = idx.pageCount`
  `:296`; the user-swipe path `snapshotFlow { pagerState.settledPage }` at **`:343-349`** (no
  "user-interacted" flag today — Gate-2 R2 High 1); the one-shot reflow-clamp `localScrollTarget`
  consumer that **CLAMPS to the current composition's `pageCount` and CLEARS** at **`:356-367`** (the
  clamp/clear hazard — Gate-2 R2 High 1); `beyondViewportPageCount = 1` `:417`; `PagedRenderCache(maxCached
  = 6)` at **`:544`**; **external jump consumes `jumpRequest: Int?` as a target PAGE at `:147` (param) +
  `:374-383` (effect)**; **`txt-paged-loading` shown ONLY while `idx == null` at `:286`** (Gate-2 R2
  Medium 3); `onSaveSourceOffset(navigator.currentSourceOffset())` `:348, :365, :381`.
- `TxtReaderActivity` = `TxtReaderActivity.kt` (**1552 lines**); paged per-open + `pagedJumpRequest`;
  `TxtPagedBody(...)` call site; **the `jumpToOffset` seam SYNCHRONOUSLY converts source→page at
  `:572-585`** (`pagedNavigator.pageContaining(target)` at **`:580`** → `pagedJumpRequest.value = <page>`);
  feeders pass SOURCE offsets — bookmark **`:632`** (returns `JumpResult.Succeeded` — Gate-2 R2 Low),
  annotation **`:641`**, search **`:698`** (returns `JumpResult.Succeeded`), scrubber **`:731`**;
  TTS-follow effect **`:597-605`** (raises a PAGE from `pagedTtsFollowTarget`); progress
  `TxtProgress.fraction(pagedOffset.value, …)` source-offset-based; page labels `displayPage=0,
  totalPages=0`.
- `TxtProgress.fraction(offset, textLength)` = `TxtProgress.kt:9` (source-offset ÷ length — de-risks the
  estimate-error risk).
- `ComposeLineMeasurer` = `ComposeLineMeasurer.kt` (determinism seam, reused; concurrent use forbidden by
  the single session).
- `TxtDocument` = `chunkCount`, `offsetForChunk`, `chunkForOffset` (chunk only, NOT the prior page's
  remaining height — the reason anchor-start is non-deterministic, Gate-2 R1 Critical 1), `textForChunk`,
  `text`, `DEFAULT_MAX_CHUNK_CHARS = 4000`.
- `TxtPaginatorPerfBenchmark.kt` validates the real book at **`REAL_BOOK_BYTES = 14_059_220L` (`:80`)**;
  `MAX_RUN_MS` is a termination ceiling, not a latency SLA; recorded ~85 s/run real.

**Could NOT fully verify (flagged, not guessed):** the runtime behavior of `HorizontalPager` when
`pageCount` GROWS at runtime is undocumented by Google — handled by making growing-count-doesn't-yank a
WI-5c BLOCKING connected acceptance criterion WITH a named fallback (recreate `PagerState` keyed by
source offset, or hold count stable + batch) rather than an assumption (Gate-2 R1 Medium 1 + R2 Medium 4).
