---
branch: feat/140-wi-8-acceptance
threadId: 019fd1ec-933a-7340-b7d2-2fc063c9a69e
rounds: 3
final_verdict: ship-as-is
---

# Gate-4 audit — feature #140 WI-8 (AZW3 Contents, Gate-5b acceptance suite)

Auditor: Codex `gpt-5.5`, reasoning effort `high`, read-only sandbox, driven through
`scripts/run-codex.sh` (rule 53). One file under review:
`android/app/src/androidTest/kotlin/com/vreader/app/reader/Azw3TocAcceptanceTest.kt`.

Each round was asked the same three standing questions — (Q1) can any assertion run before
`Azw3DocState.Loaded` is observed, (Q2) does the test reach the reader through the real LAUNCHER
path rather than a shortcut, (Q3) can any criterion pass on a stuck or broken pipeline — plus a
normal Gate-4 review and an explicit doc-honesty check.

| Round | Thread | Findings | Verdict |
| --- | --- | --- | --- |
| 1 | `019fd1d4-48fe-7a33-b4dd-be88d4d65e65` | 2 High, 3 Medium, 2 Low | changes required |
| 2 | `019fd1e2-0809-7d91-89f9-6a01eb930207` | 1 High, 1 Medium, 1 Low | block-recommended |
| 3 | `019fd1ec-933a-7340-b7d2-2fc063c9a69e` | none | **ship-as-is** |

Round-3 wording: *"No still-open or new findings. … The R2 findings stay closed: the digest pin
breaks the provider/content circularity for the asserted row sequence, the target href uniqueness
check fixes the earlier duplicate gap, and the LazyColumn length squeeze is valid here."*

## Round 1 — dispositions

| Sev | Finding | Disposition |
| --- | --- | --- |
| **High** | Criteria 4/5 were asserted in two independent waits ("the position changed" and "the highlight landed"), which drift plus a later unrelated relocate could satisfy between them. | **Fixed.** The two are now ONE claim in ONE window: the baseline must still be the current persisted position at the instant of the tap → tap → the highlight must reach the tapped chapter's row (href-bound — that index is `foliateTocIndexFor` over `relocate.tocHref`, so only a report naming the tapped href can produce it) → the position is read *while that highlight still holds* and is re-asserted afterwards → `cfi` must have changed and `progression` advanced. |
| **High** | Title/order checks compared the UI against the same provider run that fed the reader, so a parser emitting 71 *wrong* non-blank titles would pass. | **Fixed over two rounds.** Round 1: pinned real NCX constants (first/second/third/last title, and a pinned jump target row/title/href) instead of computing the target. Round 2: `EXPECTED_TOC_DIGEST` over the entire flattened sequence (see below). |
| Medium | "No node one past the last" does not bound a lazy list. | **Fixed** (see round 2 — the first attempt, `CollectionInfo.rowCount`, turned out to publish `-1` on device and was replaced). |
| Medium | KDoc claimed *every* assertion is made after `Loaded`; several preconditions necessarily run before a reader exists. | **Fixed.** The KDoc now says every assertion **about the reader** is gated and names the ungated preconditions explicitly (fixture digest, pinned-content/oracle checks, reader-stack drain + intent identity). |
| Medium | The method name promises every acceptance criterion, but 6/8/9/10 are delegated. | **Fixed as far as the contract allows.** The two test names are fixed by the dispatch brief and were not renamed. Instead the file declares `CRITERIA_HERE` / `CRITERIA_SIBLING` / `CRITERIA_WI7` / `CRITERIA_SUITE_RERUNS` and asserts they partition 1..10 with no overlap, and the KDoc states plainly what the method does and does not assert. Round 3 did not re-raise it. |
| Low | Settle wording overclaimed relative to a 3 s progression-only hold. | **Fixed.** `settledPosition` now holds BOTH persisted fields (`cfi` + `progression`) stable, the KDoc states exactly what settling does and does not establish, and the caller re-checks the baseline at tap time. |
| Low | Depth honesty was good — keep it. | **Kept.** The KDoc states the fixture is `maxDepth 1`, so real-data nesting is evidenced at depth 1 only. |

## Round 2 — dispositions

| Sev | Finding | Disposition |
| --- | --- | --- |
| **High** | Residual circularity: pinning rows 0/1/2/35/70 still let a regression that corrupts or reorders the other 66 rows pass. | **Fixed.** `EXPECTED_TOC_DIGEST` = SHA-256 over every row's `(depth, title, href)` in order (fields joined by U+0001, rows by U+0002 — documented, since the characters are invisible in source). Golden `68e9168c…970556`, asserted by both tests. The on-screen walk was also widened from a 6-row sample to **all 71 rows**. With the provider's whole sequence pinned, "the UI matches the provider" *is* "the UI matches the pin". |
| Medium | `indexOfLast == 35` only rules out a *later* duplicate of the target href; an earlier one would still let the highlight land on 35 for a report naming another row. | **Fixed.** Uniqueness is now asserted directly (`count { it == TARGET_HREF } == 1`), plus `TARGET_ROW_INDEX == EXPECTED_HIGHLIGHT_ROW`. |
| Low | The exact-length proof asserted on Compose's exception *message* text. | **Fixed.** Replaced by a message-free two-sided squeeze: scrolling to `rows.size - 1` must succeed (itemCount ≥ 71) and to `rows.size` must throw `IllegalArgumentException` (itemCount ≤ 71) ⇒ itemCount == 71 exactly. The message is logged only. |

## Two findings the device disproved, not the auditor

Both were my own fixes, caught by re-running the gate rather than by review:

- `SemanticsProperties.CollectionInfo.rowCount` publishes **-1** for this `LazyColumn` — "unknown" — so the
  first attempt at the round-1 Medium was itself invalid. Replaced by the scroll squeeze.
- Scrolling to the last index leaves the list at the bottom, so a subsequent row-0 assertion failed on
  an off-screen node. Ordering corrected; the full-row walk now scrolls per index.

## Verification that the fixes hold

Every audit-driven code change was followed by a re-run of the targeted gate (rule 10 step 5). Final
state on `emulator-5554`:

```
RUN-ANDROID-TESTS RESULT: SUCCEEDED
com.vreader.app.reader.Azw3TocAcceptanceTest  tests=2 failures=0 errors=0 skipped=0
```

with `roots=15 rows=71 histogram={0=15, 1=56} maxDepth=1`, digest identical across both tests, and the
jump moving `epubcfi(/6/2!…)` → `epubcfi(/6/86!/4,/2[CHP11-2],/6/3:65)`, progression `0.001102` →
`0.449993`.
