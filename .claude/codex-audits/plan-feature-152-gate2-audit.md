---
gate: 2
kind: plan-audit
feature: 152
plan: dev-docs/plans/20260806-feature-152-android-cover-extraction.md
rounds: 2
final_verdict: pending-round-2
---

# Gate-2 plan audit — feature #152 (Android embedded cover extraction + display)

## Why this file exists

Round 1 found that the **previous** Gate-2 audit of this feature left no artifact. The superseded
v2 plan records *"6 High + 8 Medium + 2 Low remain open"* and **that list exists nowhere in the
repo**. A v3 was written from the code instead, and no one could show whether those 16 findings
were addressed or silently dropped — the author searched and confirmed the artifact is simply
absent. Gate 4 has always committed its audit log; Gate 2 now does too, and this is the
demonstration of why.

## Method — two independent auditors

- **Static**: Codex `gpt-5.5`, effort `high`, read-only, via `scripts/run-codex.sh` (rule 53).
- **Empirical**: a separate agent that ported the plan's §4 MOBI spec to Kotlin/Java, ran it
  against **4 real books and 39 mutated files**, cross-checked every extraction against an
  independently written Python MOBI reader, and disassembled the resolved Readium AAR.

## Round 1 — `block-recommended`. All 15 findings accepted; 3 remedies deviated.

### Found only by execution

| # | Sev | Finding | Fix in v4 |
|---|---|---|---|
| C-1 | **Critical** | The §4 restatement **dropped Swift's `end <= data.count` guard**. Record-table entry 136 set to `0x7FFFFFF0` → computed length **2 147 138 052 bytes**; `OutOfMemoryError` at every heap size from `-Xmx64m` to `-Xmx1g`, where the iOS-faithful path returns `None`. Critical because **`OutOfMemoryError` is an `Error`, not an `Exception`** — the plan's `catch (Exception)` contract misses it, so it escapes the coroutine and kills the app-scope backfill for the whole library. | Three pre-allocation guards (`start > fileLength`, `end > fileLength` — which subsumes non-monotonic offsets — and a 64 MiB `MAX_RECORD_BYTES`); `CoverCoordinator` catches `Throwable` as defence in depth **with an explicit note that catching OOM after the fact is not the fix**; 3 new cases, one asserting no OOM escapes at `-Xmx64m`. |
| H-2 | High | The `Failed`/`None` split **contradicts the plan's own §7 table**: moving from mapped `Data` to `RandomAccessFile` turns bounds violations into `EOFException` (an `IOException`), so cases ①③⑨ that expect `None` measurably return `Failed` — meaning every truncated book is re-parsed on **every app start, forever**, the exact cost the memoisation exists to prevent. 6 of 39 mutations diverge this way. | Normative content-vs-access table: `None` = reachable and structurally parsed (incl. EOF during a bounded read); `Failed` = could not be accessed (missing file, permission, device I/O). Boundary pinned at the *open*. New contract test; §7 expectations corrected. |
| H-3 | Med→High | `CoverStore.save()` recycling a caller-owned bitmap is unsound — **bytecode-proven**: `BitmapKt.scaleToFit` returns `this` unchanged when the source fits (`34: aload_0 / 35: areturn`), and `InMemoryCoverService` holds the bitmap in a `private final` field, so `coverFitting` can return the `Publication`'s retained bitmap. A double-`save` also hands a recycled bitmap to `compress()`. **Risk-4's stated mitigation was a grep — which passes while the defect is present.** | Reversed: `CoverStore` **borrows**, no `.recycle()` anywhere. Risk 4 rewritten to name the old mitigation as itself defective; replaced by a behavioural double-save test. |

### Static findings

| # | Sev | Finding | Fix in v4 |
|---|---|---|---|
| H-4 | High | The rule-51 gap is larger than the plan's G1. | **Deviation** — verified the pencil in `vreader-book-details.jsx:128-140` sits *outside* the `missingCover` ternary (renders in both branches) and `vreader-generated-cover.jsx:31-34` says swap controls *return* when a cover store lands. Filed as G2. Remedy: **move WI-8 to #153** rather than commission new design. |
| H-5 | High | Extraction can still race a user-chosen cover. | `saveIfAbsent` (non-replacing) vs `saveReplacing` (#153 only), both under a per-key `Mutex` held across re-check → temp write → `renameTo`; latched interleaving test ×50. |
| H-6 | High | v2 reconciliation not independently auditable. | Confirmed **no v2 artifact exists anywhere**; §12.1 states what is reconcilable and that the unenumerated residue **cannot be shown to have been addressed**. Produced this artifact requirement. |
| M-9 | Med | `StorageNaming` maps every non-`[A-Za-z0-9._-]` char to `_`, so `a:b` and `a/b` collide, contradicting the plan's own non-collision test. | **Deviation** — neither proposed fix taken: `fileNameForKey` already names every book file on every device, so changing the mapping orphans existing libraries; and the substitution is injective on `Identity.canonicalKey`'s real domain. Mapping frozen, precondition explicit, contradictory tests deleted, injectivity property test added. |
| M-10 | Med | No cover deletion / orphan cleanup. | `onBookDeleted` + a `sweepOrphans()` backstop at `start()`, both idempotent and non-throwing. |
| M-11 | Med | "Import-time extraction" under-specified — `RestoreImporter` calls `BookImporter` directly. | Four `importStream` callers verified; hook moved to the convergence point (`BookImporter.onImported`, fire-and-forget on the app scope). |
| M-12 | Med | WI parallelisation collides — 5 WIs write under `library/covers/`. | Exact per-WI **file** lists, no shared files; parallelism claim **downgraded honestly** (both extractors depend on WI-3 and share one emulator, so no speed-up claimed). |

### Empirical mediums / lows

| # | Sev | Finding | Fix in v4 |
|---|---|---|---|
| M-7 | Med | Risk-1's Gate-5 mitigation **cannot test what it is assigned to** — all three fixtures are single-part `mobiType = 2` files despite `.azw3`; zero `BOUNDARY` markers across 153 records. | **Deviation** — the false claim is withdrawn; the MOBI6+KF8 limitation ships **untested and named**, with a Residuals section required in the evidence file. |
| M-8 | Med | `firstImageIndex == 0xFFFFFFFF` occurs in a real committed fixture (`DebugFixtures/divider-azw3.azw3`) and was documented only for EXTH 201/202. | Reconfirmed by parsing the file; sentinel checked before the EXTH scan; §7 case added. |
| L-13 | Low | ~~Fixture policy over-pessimistic — `androidTest/assets/foliate-spike/book.azw3` is **byte-identical** to the "gitignored" real book (`md5 f4ae9259b82cc2a765242bebd015df84`, 6 288 371 B), so that suite is CI-safe.~~ **WITHDRAWN — THIS FINDING WAS WRONG.** | ~~Adopted~~ **RETRACTED at WI-3 (2026-08-06).** The byte-identity half is true and re-confirmed. The **conclusion** is false: `android/app/src/androidTest/assets/foliate-spike/.gitignore` contains exactly `book.azw3`; `git ls-files` on that directory returns `.gitignore`, `bundle-patch.md`, `foliate-bundle.js`, `reader.html` and **not** the book; it has never been tracked, and it is absent from a fresh worktree — six existing `androidTest` files already `assumeTrue`-skip on it. (The repo also has **no `.github/workflows`**, so "CI-safe" had no referent.) **No committed test may depend on it**, and the per-run `adb push` the plan had removed must be reinstated for every connected real-book leg. Caught by the WI-3 implementer *trying to use it* — the audit had checked the file's bytes but not its tracked status, and the orchestrator propagated the conclusion into this artifact and into the plan without re-deriving it. |
| L-14 | Low | §7 omitted the one mode that actually crashes. | Five cases added. |
| L-15 | Low | `Signature:` attribute quoted as `descriptor:`. | Corrected. |

### What the measurement CONFIRMED (recorded, not buried)

Ported faithfully with the plan's two stated Kotlin corrections, the spec extracted the **correct**
cover from 3/3 cover-bearing real books — the 6.3 MB CJK book → record 135, 379 691 B JPEG, 542×800,
rendered and visually confirmed as the real jacket — correctly returned `None` for the one book with
none, **matched an independent Python reader byte-for-byte** (`md5 fa84a175…`), returned cleanly on
36 of 39 hostile inputs with no hang, and parsed a 300 MB sparse file at `-Xmx16m` with **0 MB heap
delta**.

Both claimed Kotlin corrections are real, reproduced in compiled Kotlin: `0xFFFFFFFF` is typed
`Long`, so an `Int` read gives `-1` → `rec[134]`, a **non-image record** (silently wrong bytes, not
an error); and `numRecords` at file offset 76 is `00 99`, so an unmasked read gives **-103** — an
unmasked port fails on the *first field it reads*, on a real book. `firstImageIndex` is an
**absolute** PDB record index and EXTH-201/202 are **relative** to it — proven by mutation, since
the happy path cannot discriminate (`135 + 0 == 135`).

Readium independently verified from the resolved AAR: `coverFitting(Publication, Size,
Continuation) -> Bitmap?`, no `@ExperimentalReadiumApi` — a sound negative, proven by finding 31
other classes in the same jar that **do** carry it.

## Round 2 — in progress

Verifying each fix; evaluating the three deviations (WI-8 → #153, frozen sanitiser, KF8 untested);
and sweeping for defects the revision introduced — the 64 MiB cap vs a legitimately large cover,
`catch (Throwable)` vs `CancellationException`, the fire-and-forget `onImported` hook vs
transaction visibility on a 200-book restore, per-key `Mutex` growth, and `sweepOrphans` racing a
mid-import book. Result appended on completion.
