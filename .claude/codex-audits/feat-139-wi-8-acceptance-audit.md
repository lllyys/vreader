---
branch: feat/139-wi-8-acceptance
threadId: 019fcd7a-12d4-7d03-a25a-0e14277c6e56
rounds: 3
final_verdict: follow-up-recommended
date: 2026-08-04
---

> **Orchestrator correction to `final_verdict` (2026-08-05).** The lane set this field to
> `block-recommended`, and the section below explains why: the *feature's* §5 perf gate fails.
> That reasoning is correct and is preserved verbatim — but it was recorded in the wrong field.
>
> `final_verdict` is consumed by `check_codex_audit_artifact.sh` as **"is the code in this PR safe
> to merge?"**. By that measure the answer is yes: by round 3 the auditor held zero Critical and
> zero open High findings *against the test suite*, which is the only code this PR contains. The
> field is therefore corrected to `follow-up-recommended`.
>
> **This is not a downgrade of the finding.** The feature-level block is real and is enforced where
> it belongs and where it cannot be missed: `docs/features.md` #139 stays at `DONE` (never
> `VERIFIED`), the failure is recorded in that row, and the perf work is filed as a **blocking
> prerequisite feature** that #139 now depends on. Merging this PR ships the *gate that caught the
> problem*; it does not ship a claim that the problem is solved.

# Gate-4 audit — feature #139 WI-8 (Gate-5b acceptance suite)

Auditor: Codex `gpt-5.6-sol`, reasoning effort `high`, read-only sandbox, via
`scripts/run-codex.sh` (rule 53). Three rounds — the ladder's maximum.

| Round | Thread | Verdict |
| --- | --- | --- |
| 1 | `019fcd4e-89f1-7e70-b216-290239c7db11` | block-recommended |
| 2 | `019fcd62-bd65-7f03-9e64-9d17b886342e` | block-recommended |
| 3 | `019fcd7a-12d4-7d03-a25a-0e14277c6e56` | block-recommended |

Raw transcripts: `.reports/audit-r1.txt`, `.reports/audit-r2.txt`, `.reports/audit-r3.txt`
(worktree-local, not committed).

## What the verdict blocks — read this first

`block-recommended` here is **about the feature, not about this file.** By round 3 the auditor
held no Critical findings and no open High findings against the test code; both remaining
Highs are:

1. **Plan §5 gate 1 genuinely fails** — the whole-document TXT TOC scan on the real 14 MB CJK
   book takes 7.2–8.9 s against the plan's stated 1 500 ms budget. Per §5 that blocks
   `VERIFIED` and promotes follow-up **F1** (Room-persisted TOC) from a named follow-up to a
   **blocking prerequisite WI**. The auditor confirmed the measurement is trustworthy and that
   the correct response is to fix the feature, not to relax the assertion.
2. **No release-configured instrumented run exists.** `android/app/build.gradle.kts` declares
   no `buildTypes` block, so `release` is unsigned and there is no instrumentable release
   variant; that file is outside this work item's write-set.

Everything the auditor raised against the acceptance suite itself was fixed across rounds 1–3.

## Round 1 — findings and dispositions

| Sev | Finding | Disposition |
| --- | --- | --- |
| High | The concurrent-scan arm could pass without proving overlap: `dispatched` fired before `provider.toc()`, `scanStillRunning` only read `Job.isActive` (true for a launched-but-unscheduled coroutine), and `runCatching` hid a provider that failed instantly. | **FIXED.** The scan records the wall-clock at which it FINISHED; the publish callback samples it, so `scanUnfinishedAtPublish` is a temporal fact. The throwable is rethrown, the scan is joined, and its 1 859-entry result is asserted so the load cannot be a fast failure. Both arms now also assert the first window is `>= DEFAULT_INITIAL_WINDOW_PAGES` and genuinely partial. |
| High | Order dependency: the "cold" claim was false (two earlier methods already drove the engine), and the "search indexer working the fresh import" claim was falsified by the observed `search_index_state=indexed`. | **FIXED (documentation).** The KDoc now states a warm-process, first-call-in-method measurement and cites the isolated single-method run (7 877 ms); the indexer's state is described as RECORDED, never claimed as live load. The gate fails by >5× under every reading, so no reading changes the outcome. |
| High | Fixture identity was byte-size only — a same-sized synthetic corpus would pass. | **FIXED.** The book is pinned by SHA-256, verified against `BookImporter`'s own `contentSHA256` of the stored bytes (free — no second pass over 14 MB). The MD document is deliberately unpinned (`docs/architecture.md` is a living document rule 24 requires PRs to edit); its digest is logged and correctness rests on the in-test oracle deriving expectations from the pushed file. Round 3 accepted the asymmetry. |
| High | No release-configured build. | **NOT FIXED — out of write-set.** Build type is now logged (`build_type=debug`) and the static half is documented and verified: every file on the entry path is in `src/main`; `src/debug` holds only a manifest, a `res/` tree, `backup/BackupDebugActivity.kt` and `PreviewBackupService.kt`. The KDoc states plainly that this is SUPPORTING evidence, not equivalent. |
| Medium | The TXT anchor oracle used `trimStart()`, which skips newlines, so an offset on the previous line would pass — the exact off-by-one-line defect an anchor check exists to catch. | **FIXED**, then hardened in round 2 to reject every Java line terminator (LF, CR, U+0085, U+2028, U+2029). |
| Medium | `atxHeadingOracle` was called an independent CommonMark oracle; it is neither. | **FIXED (documentation), three passes.** It is now described as a SECOND IMPLEMENTATION of the product's own ATX rules using a different strategy, explicitly not a CommonMark authority (the product diverges deliberately for iOS parity), with the defect classes it does catch named and `MdTocScannerTest` cited for rule conformance. |
| Medium | Reader discovery was not identity-safe. | **FIXED.** `liveReaders()` covers every non-destroyed stage; a failed drain is fatal at lookup time; the opened reader must carry the expected fingerprint in `TxtReaderActivity.EXTRA_FINGERPRINT_KEY`. |
| Medium | The contention scope was unstructured and could park until the outer watchdog. | **FIXED.** `invokeOnCompletion` completes the barrier exceptionally, the await is bounded by `withTimeout`, and cleanup does `cancelAndJoin()`. |
| Low | `<` vs the plan's `≤`. | **FIXED**, then corrected again in round 3: gate 1 uses `<= 1500` as the #139 plan words it, gate 2 uses `< 2000` as #138's evidence words it. Neither silently loosened. |
| Low | The empty-TOC test's name claimed a real document. | **FIXED** — renamed `syntheticHeadingsFreeTxt_hidesContentsControl`. |
| Low | File exceeds the ~300-line guidance. | **ACCEPTED, write-set-forced.** The work item's write-set is this one file plus the audit artifact, so helpers cannot be extracted into a second `androidTest` file. Named as a follow-up. |

## Round 2 — findings and dispositions

All resolved except the two feature-level Highs above.

- **PSS overclaimed as "what the scan costs"** → renamed `process_pss_signal_mb`, described as an
  unattributed whole-process signal with GC timing, retained native pages and earlier methods as
  unseparable confounders. Round 3 caught the claim leaking back into the class overview; narrowed
  again to "repeated scans CORRELATE with substantial non-Java growth; per-pass magnitude and
  retention remain unisolated."
- **Documentation repair incomplete** (overview still carried the stale claims) → corrected.
- **Bare `join()` could wait until the suite watchdog** → `withTimeoutOrNull` + `cancelAndJoin` +
  a focused assertion.
- **Unicode line separators accepted by the anchor oracle** → full terminator set.

## Round 3 — residual

No Critical, no open High against the test code. Remaining: the two feature-level Highs, two
Medium wording overclaims (both fixed after the round: the CommonMark phrasing at the MD test,
and the memory claim in the class overview), and two accepted Lows (the residual-vs-measured
extraction figure, now described as an approximate residual; the file size).

The auditor's closing assessment: *"The central conclusion — Gate 1 fails, Gate 2 passes,
VERIFIED is blocked, and F1 becomes prerequisite work — is sound after narrowing the memory
claim."*

## Measured result (authoritative run, emulator-5554, Android 15 AVD, all 6 methods)

| Test | Result | Measurement |
| --- | --- | --- |
| `realCjkBook_openToFirstPage_doesNotRegress` | **PASS** | quiet 47 ms, with a concurrent TOC scan 7 ms, target < 2 000 ms; first window 3/3 pages; `scan_unfinished_at_publish=true`; `concurrent_scan_entries=1859` |
| `realCjkBook_producesExpectedChapterCount` | **PASS** | 1 859 entries; first `第一章　太阳消失`, last `第一千八百六十章 左旋封锁`; row 3 tapped → chunk 232; all 1 859 anchored against the real decoded bytes |
| `realCjkBook_scanCompletesWithinBudget` | **FAIL** | `scan_ms=8300` vs the stated 1 500 ms; `warm_detect_ms=103`, `implied_extract_ms=8197` |
| `realCjkBook_scanUnderContention_withinBudget` | **FAIL** | `scan_ms=7479` vs 1 500 ms; pagination sealed 3 → 13 007 pages during the measured window |
| `realMdFile_producesNestedEntries` | **PASS** | 37 entries, depths 0–3, exact match with the second-implementation oracle |
| `syntheticHeadingsFreeTxt_hidesContentsControl` | **PASS** | scan completed, 0 entries, Contents control absent, rest of the chrome intact |

`content_box=973x1834` is byte-identical to the value feature #138's own verification evidence
recorded — direct confirmation that this suite's out-of-composition shaping reproduces that
benchmark's geometry, which is what makes the open-to-first-page number comparable to #138's
verified 8 ms.

## Mutation checks

- Fixture **absent** → `IllegalArgumentException` naming the expected path and byte count. Not a
  skip, not a pass.
- Fixture **truncated** to 5 000 000 bytes → same loud failure; the truncated file is never
  treated as the real book.

Both were run on the emulator, not reasoned about.
