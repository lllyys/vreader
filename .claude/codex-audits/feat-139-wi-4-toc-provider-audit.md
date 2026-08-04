---
branch: feat/139-wi-4-toc-provider
threadId: 019fcbb0-bcc3-78a2-8bfb-7a4630f41eae
rounds: 2
final_verdict: ship-as-is
date: 2026-08-04
---

# Gate-4 audit — feature #139 WI-4 (`TxtMdTocProvider`)

Files under review:

- `android/app/src/main/kotlin/com/vreader/app/reader/nav/TxtMdTocProvider.kt` (new)
- `android/app/src/test/kotlin/com/vreader/app/reader/nav/TxtMdTocProviderTest.kt` (new)
- `docs/architecture.md` (one added service bullet under "Reader plumbing", rule 24)

Auditor: Codex `gpt-5.5` effort=high via `scripts/run-codex.sh` (rule 53), read-only sandbox, two
independent sessions. Raw transcripts: `.reports/audit-r{1,2}.txt` (not committed — 519 KB / 1.8 MB).
Round-1 thread `019fcba9-a88d-7ed3-927f-4f7f1e021e9b`; round-2 thread (recorded above)
`019fcbb0-bcc3-78a2-8bfb-7a4630f41eae`.

Both rounds were asked the same eight questions against the real source (not the plan's prose):
locator construction identity with a #135 bookmark, the 50 000 cap boundary on both branches,
whether rejection can happen without materializing the full list, whether ANY named test could pass
vacuously (with the fixtures' arithmetic re-derived independently), dispatcher injection + the test
harness's soundness, cancellation/concurrency/edge cases, vreader compliance (rule 22 comment
accuracy, file size, no Android imports in JVM-testable code), and the accuracy of the docs bullet.

Both rounds were explicitly told that plan §4.4 **deleted** the density/saturation/ambiguous-rule
guards (Option A) and that recommending one is out of scope — so no round could "fix" the tripwire
this WI exists to pin.

## Round 1 — C=0 H=0 M=1 L=2, verdict `follow-up-recommended`

| # | Sev | Finding | Disposition |
| --- | --- | --- | --- |
| R1-1 | **Medium** | The cap boundary tests exercised only the **MD** branch. The TXT branch is a second, independent `extractHeadings` call site with its own budget, so a wrong limit / a truncation / an over-materialization there would have passed. | **FIXED** — added `cap_txtAtExactlyMaxTocEntries_returnsEntries` and `cap_txtAtMaxPlusOne_returnsEmpty`, and narrowed `cap_rejectionHappensWithoutMaterializingFullList`'s comment so it claims only what it proves (the scanner stops at the budget; the *budget itself* is pinned by the two boundary pairs). |
| R1-2 | Low | `docs/architecture.md` read as though the TXT/MD host already sourced Contents from this provider. It does not — `TxtReaderActivity.kt:1432` still passes `tocEntries = emptyList()`; host wiring is WI-7. | **FIXED** — the bullet now states that explicitly. |
| R1-3 | Low | The test file is over the repo's ~300-line guideline. | **ACCEPTED with rationale** — the lane's declared write-set is exactly four paths, so creating a second test file is outside it; and at 365 lines the file is the second *smallest* in its package (`ReadiumTocProviderTest` 193, `BookmarkPresentationTest` 485, `TxtTocRulesTest` 532, `MdTocScannerTest` 624, `TxtTocRuleEngineTest` 697). Round 2 accepted the rationale. |

## Round 2 — C=0 H=0 M=0 L=1, verdict `follow-up-recommended` → fixed to `ship-as-is`

Round 2 re-verified every round-1 disposition against the code rather than the claim, and
independently re-derived the TXT fixtures' arithmetic: `txtChapters(n)` emits exactly `n` lines of
`第<i>章 甲`, every one matched by rule 1 (rule 2 ties; `detectBestRule`'s strictly-greater
comparison keeps the earlier rule), and both fixtures sit under the 512 KiB detection sample
(50 000 → 488 894 UTF-16 units; 50 001 → 488 904), so detection sees every heading and the `>= 2`
threshold is satisfied. It confirmed the boundary pair genuinely binds the TXT branch's own budget.

| # | Sev | Finding | Disposition |
| --- | --- | --- | --- |
| R2-1 | Low | Rule 22: the file header claimed a mis-detected TOC is harmless because "`LazyColumn` bounds rendering" — but WI-6 (the lazy sheet) has not landed on this branch, so the claim was false *as written*. | **FIXED** — the header now says WI-6 makes the sheet lazy and lands **before** WI-7 wires this provider to a host, so no user can reach a large TOC through today's eager sheet. |

Everything else came back clean and is recorded here as the round-2 findings of fact:

- **Locator identity**: `toEntry` calls `txtBookmarkLocator(book, heading.sourceOffsetUtf16)`
  directly, so a TOC row and a #135 bookmark at one offset are the same value by construction.
  The locator's `format` leg is `book.originalFormat.name` (the ctor's `format` param only routes),
  matching the bookmark path exactly.
- **Cap boundary**: both scanner loops append then return `hitLimit = true` at `size == limit`, and
  the provider passes `SCAN_LIMIT = 50 001`. 49 999 / 50 000 are kept; 50 001 rejects to an empty
  list. Reject, never truncate; TXT and MD agree by code.
- **No materialization**: a 5 M-heading document never becomes a 5 M-element list — TXT detection
  samples 512 KiB, both extractions stop at 50 001, and allocation is proportional to the
  already-resident document `String` plus a cap-sized heading list.
- **Dispatcher**: the provider (not the host) owns `withContext(dispatcher)` on an injected
  dispatcher; nothing is hardcoded; the `RecordingDispatcher` harness proves the hop by observing
  execution on its own named thread and shuts its executor down in a `finally`.
- **Concurrency / cancellation / edge cases**: provider state is immutable and each scan uses local
  state, so concurrent `toc()` calls are safe; cancellation is cooperative inside both scanners;
  empty text, an unsupported format, a heading at offset 0, and CJK/astral titles all behave.

## Mutation probes (author-run, beyond the audit)

Because this feature has twice shipped a test that passed for free (WI-2 asserted against the wrong
object; WI-3 needed its arithmetic re-derived), each load-bearing claim was probed by breaking the
production code and confirming the *named* test goes red:

| Mutation | Tests that failed |
| --- | --- |
| `applyCap` truncates instead of rejecting | `cap_aboveMaxTocEntries_returnsEmpty_notTruncated`, `cap_atMaxPlusOne_returnsEmpty`, `cap_rejectionHappensWithoutMaterializingFullList`, `applyCap_isTheWholePolicy` |
| `SCAN_LIMIT = MAX_TOC_ENTRIES` (budget one too small) | `cap_atExactlyMaxTocEntries_returnsEntries` |
| TXT branch budget `SCAN_LIMIT + 1` (one too large, TXT only) | `cap_txtAtMaxPlusOne_returnsEmpty` |
| `withContext` on `EmptyCoroutineContext` (no hop) | `runsOnInjectedDispatcher_providerOwnsWithContext` |
| a 90 %-saturation guard reintroduced (the withdrawn D4) | `noDensityOrSaturationGuardExists`, `mdAllHeadingOutline_isKept`, + 3 collateral |

The last row is the one that matters most: the D4-deletion tripwire fires loudly, so a future change
cannot quietly reintroduce a density or saturation guard without also editing the plan.

## Test gate

`RUN-ANDROID-TESTS RESULT: SUCCEEDED` — `:app:testDebugUnitTest --rerun-tasks --tests
'*TxtMdTocProviderTest*'`, **26 tests, 0 failures, 0 errors, 0 skipped** (the plan's 18 named tests
plus 8 author-added edge cases: unsupported format, empty text, the `>= 2` threshold observed
end-to-end, document order, verbatim CJK/astral titles, `applyCap` in isolation, and the TXT cap
boundary pair). JVM only — no emulator.

## Verdict

**ship-as-is.** Zero open Critical/High/Medium findings; both Lows fixed, the third accepted with
the rationale round 2 endorsed.
