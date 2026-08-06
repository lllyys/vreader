---
gate: 4
kind: implementation-audit
feature: 152
work_item: WI-3
branch: worktree-agent-a9a6525e57d9db147
threadId: 019fd51f-6307-7733-8b60-31cb720e7f42
rounds: 2
final_verdict: ship-as-is
---

# Gate-4 implementation audit — feature #152 WI-3 (MOBI/AZW3 cover parser)

Auditor: Codex `gpt-5.5`, effort `high`, read-only, via `scripts/run-codex.sh` (rule 53).
Author/auditor separation holds: the implementing Claude Code session did not review its own work.

Files under audit (all new):

- `android/app/src/main/kotlin/com/vreader/app/library/covers/MobiCoverParser.kt`
- `android/app/src/main/kotlin/com/vreader/app/library/covers/MobiCoverExtractor.kt`
- `android/app/src/main/kotlin/com/vreader/app/library/covers/CoverResult.kt`
- `android/app/src/test/kotlin/com/vreader/app/library/covers/{MobiCoverParserTest, MobiCoverParserIndexTest, MobiCoverResultClassificationTest, MobiCoverExtractorTest, MobiFixtures}.kt`

## Round 1 — `follow-up-recommended` (thread `019fd510-a0cd-7e63-8157-0c7702ac9c27`). 1 Medium + 2 Low. All three fixed in `e766f03f`.

| # | Sev | Finding | Disposition |
|---|---|---|---|
| 1 | **Medium** | `scanExthForImageIndex` bounded its EXTH record walk by **record 0's end** rather than by the block's own declared length. A block that understates `exthLength` therefore let real-looking `{type, length, payload}` records be read out of the bytes *following* the block — so a malformed file could aim the cover at any record. Noted as matching the Swift reference's laxity, i.e. a hardening gap rather than a port defect. | **FIXED.** `exthLength >= 12` is now required (the block must contain at least its own header) and both loop bounds compare against `exthEnd = exthStart + exthLength`. Deliberate divergence from the Swift, recorded in a code comment: for a well-formed book the two bounds coincide, so no real book changes behaviour. New tests `records past the DECLARED EXTH end are not honoured` and `an EXTH length smaller than its own 12-byte header is None`; mutation-checked (restoring the `record0.size` bound reddens the first). |
| 2 | Low | The plan's high-bit catalogue names `numRecords >= 0x8000` and a record offset `>= 0x80000000`; the suite covered only low-byte signedness (`numRecords = 155`, `firstImageIndex = 153`). A partially-masked UInt16 reader would pass. | **FIXED.** Added `numRecords = 0x8003` (32,771 records — bit 15 set) and a record offset of `0x80000000` read from a **sparse 2 GiB** fixture (`MobiFixtures.writeSparseHighOffsetBook`), which only a masked `Long` read can reach: as a signed `Int` the offset is negative and the `start < 0` guard returns `None`. |
| 3 | Low | `MobiCoverParserTest.kt` was 396 lines, over the repo's ~300-line convention. | **FIXED.** Split into `MobiCoverParserTest` (structural failure modes ①–⑬, bounds/allocation) and `MobiCoverParserIndexTest` (EXTH scan, masking, relative indexing, 201/202 preference, bounded reads). Every file in the WI is now under 300 lines. |

## Round 2 — `ship-as-is` (thread `019fd51f-6307-7733-8b60-31cb720e7f42`). **No findings.**

Round 2 was asked to verify the three fixes, hunt for defects the fixes introduced, and re-sweep
independently. It confirmed:

1. `exthEnd` is arithmetically safe (`exthStart` is already bounded into `record0`, `exthLength` is
   UInt32-sized, and the record itself is capped at 64 MiB before this path is reached).
2. The two new high-bit tests genuinely discriminate — they *require* `Art`, so they cannot be
   satisfied by a parser that returns `None` for everything.
3. The test split preserved every case; nothing was silently weakened.

**Independent corroboration worth recording**: the auditor cross-checked the EXTH fix against
**libmobi**'s `mobi_parse_extheader`, which narrows its buffer to `exth_length + buf->offset` before
walking the records — i.e. the reference C implementation bounds the walk by the *declared* block
length exactly as this fix does. The hardening is not an invention; it restores the format's own
contract, which the Swift port had dropped.

## Findings rejected / disproven by measurement (so a later round does not re-raise them)

Two guards the plan mandates are **provably redundant** given the `Long` correction. Both were
mutated away and **no test failed**. Both are kept deliberately, with the reasoning in code comments
rather than a test that cannot be written:

- **The `firstImageIndex == 0xFFFFFFFF` sentinel check (Gate-2 M-8).** `numRecords` is a u16, so
  `0xFFFFFFFF + rel` always exceeds it and the `target >= numRecords` range check rejects the file
  anyway. Kept because it states intent at the field it belongs to, costs one comparison, and is the
  guard that would still hold if the read were ever narrowed back to `Int` (where the sentinel
  becomes `-1` and resolves to a real, wrong record). Round 1 confirmed: "a reasonable intent guard
  and not a bug."
- **`catch (EOFException)`** is unreachable on a *stable* file, because every span is validated
  against `raf.length()` before it is read — which is the point: a bound is validated, never
  discovered by exception. It is reachable only when the file **shrinks mid-parse** (removable
  storage, a cloud-backed SAF document being re-downloaded). Rather than leave the Gate-2 H-2
  mapping as dead code, `classify(RandomAccessFile)` was made `internal` and
  `MobiCoverResultClassificationTest` drives it with a `RandomAccessFile` subclass that over-reports
  `length()`. Round 1 confirmed this is "a valid way to pin the H-2 contract."

## What the mutation pass established (8 mutations, in-lane)

Each mutation was applied to the production source, the suite run, and the mutation reverted.

| # | Mutation | Killed by |
|---|---|---|
| 1 | drop `end > fileLength` in `sliceRecord` | **Initially SURVIVED** — the 64 MiB cap catches the ~2 GiB C-1 span first, so case ⑪ could not tell the two guards apart. A new test isolates it with a **60 MiB** span (past EOF, *under* the cap) and asserts the **allocation**, not the return value: the unguarded parser allocates **62,918,024 bytes** where the guarded one allocates < 1 MiB. Now killed. |
| 2 | read 32-bit fields through `Int` (`0xFFFFFFFF` → `-1`) | `⑧ a 0xFFFFFFFF cover offset falls through to the thumbnail` (resolved to record 1's 32 text bytes instead of the 64-byte cover — the exact empirically-predicted `firstImageIndex - 1`), and `an EXTH length overrunning record 0 is None` (the negative length bypasses the overrun guard) |
| 3 | drop a byte mask in `readUInt16BE` | `a high bit in a field's LOW byte does not read as a negative number` |
| 4 | treat EXTH 201/202 as an absolute record index | 15 tests, including the dedicated `the EXTH cover offset is RELATIVE to firstImageIndex` |
| 5 | map bounded-read `EOFException` → `Failed` | **Initially SURVIVED** (the branch was unreachable — see above). After adding `a file that shrinks mid-parse is None, not Failed`: killed. |
| 6 | remove the `MAX_RECORD_BYTES` cap | `⑬ a span exceeding MAX_RECORD_BYTES` + `all three unbacked-span rejections are None` |
| 7 | remove the `firstImageIndex` sentinel check | **SURVIVES — equivalent mutant.** Documented above; not a test gap. |
| 8 | bound the EXTH walk by `record0.size` (the pre-fix behaviour) | `records past the DECLARED EXTH end are not honoured` |

Two mutations surviving on first pass is the substantive result of this audit: both pointed at real
coverage holes in the *original* suite, and both are now either closed (1, 5) or proven equivalent
and documented (7).

## Test gate

`RUN-ANDROID-TESTS RESULT: SUCCEEDED` — `:app:testDebugUnitTest`, **2482 tests, 0 failures,
0 errors, 0 skipped** (47 of them in `com.vreader.app.library.covers`). Zero skips is asserted, not
assumed: no `assumeTrue` and no `@Ignore` appears anywhere in this WI, because a skip exits 0
exactly like a pass (bug #369).

## Real-book verification

Run in-lane against the real 6.3 MB CJK AZW3, reproducing every empirical claim in the Gate-2
record independently: **record 135, 379,691-byte JPEG, 542×800, `numRecords` raw bytes `00 99`,
0 MiB heap delta**. Evidence + the L-13 erratum: `.reports/wi3-real-book-evidence.md`.
