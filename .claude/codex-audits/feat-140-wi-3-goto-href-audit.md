---
branch: feat/140-wi-3-goto-href
threadId: 019fd0fd-d0ba-7881-ab2d-9727ec7e2e8f
rounds: 4
final_verdict: ship-as-is
---

## Round 4 — orchestrator-run confirming round: **VERDICT: clean**

Round 3 ended at the rule-47 cap with `block-recommended`, but the block was **procedural, not
substantive**: all three round-3 findings were fixed in `5161765`, and re-auditing its own fixes
would have been self-certification. Run by the orchestrator (`scripts/run-codex.sh`, gpt-5.5/high,
read-only). **Zero findings.**

- **The three fixes are correctly transcribed.** No wording anywhere in the changed files still
  equates an ack with having landed; the stale "asserted below" parenthetical is gone; the
  whitespace guard is pinned.
- **The shipped precedence is `cfi → href → progression`** with `isNotBlank()` guards on both cfi
  and href, and the tests assert href-over-progression rather than the withdrawn round-1/2
  expectation.
- **No regression**: the href is still byte-preserving through the existing `jsString` JSON seam
  (no second escaper), `reader.html`'s cfi and fraction branches are unchanged apart from the
  inserted href branch, and **no `Succeeded OR Timeout` assertion shape exists** in
  `FoliateGoToTest.kt`.

### On the withdrawn High — orchestrator adjudication

Rounds 1 and 2 recommended **changing** the precedence; round 3 **withdrew** that on the merits.
Because a reversal should not be accepted on an auditor's say-so, the orchestrator verified the iOS
source directly:

> `vreader/Services/Foliate/FoliateNavSeek.swift` — `navigationTarget(for:)` returns `cfi` (blank-
> trimmed), else `href` (blank-trimmed), else `nil`. **There is no progression leg.**

So Android's `cfi → href → progression` matches iOS for every case iOS handles and merely adds a
fallback iOS lacks. The withdrawal is correct, plan §5.2 defense 1 needs no amendment, and **rounds 1
and 2 were the ones in error**. Accepted.

### Mutation note worth preserving

Mutation 7 — moving the shim branch into a **trailing** comment — **initially SURVIVED**. That forced
`executableJsOf` to strip trailing comment tails, not merely whole-line comments. Without it, a
commented-out navigation branch would have read as shipped.

Verdict updated on a clean independent confirmation, not an override.

# Gate-4 implementation audit — feature #140 WI-3 (`FoliateGoToTarget.Href`)

Auditor: Codex (`gpt-5.6-sol`, reasoning effort `high`), via `scripts/run-codex.sh` (rule 53).
Author/auditor separation held — the auditor ran read-only in a separate process and was never
asked to certify its own fix.

Transcripts: `.reports/audit-r1.txt`, `.reports/audit-r2.txt`, `.reports/audit-r3.txt`
(worktree-local, not committed).

Round thread ids: r1 `019fd0fd-d0ba-7881-ab2d-9727ec7e2e8f`,
r2 `019fd0fd-d0ba-7881-ab2d-9727ec7e2e8f` (re-audit of the same work),
r3 `019fd10a-9be3-7281-8b3a-342942bfbf07`.

## Scope

Three files, the WI's entire declared write-set:

- `android/app/src/main/kotlin/com/vreader/app/reader/foliate/FoliateBridge.kt`
- `android/app/src/main/assets/foliate/reader.html`
- `android/app/src/test/kotlin/com/vreader/app/reader/foliate/FoliateGoToTest.kt`

## Verdict trail

| Round | Findings | Verdict |
| --- | --- | --- |
| 1 | 1 High, 1 Medium, 3 Low | block-recommended |
| 2 | 1 High (restated), 1 Medium (partial), 3 Low | block-recommended |
| 3 | **High WITHDRAWN on the merits**, 1 Medium, 2 Low | block-recommended |

Round 3 is the rule-47 cap. Every round-3 finding was fixed in commit `f45d3f9`-class work
(the final fix commit on this branch), but those fixes are **not independently re-audited** —
the cap was reached. That is the sole reason this artifact records `block-recommended`.

## Round 1 — findings and disposition

**High — "existing AZW3 locators never carry an href" was FALSE.** My commit message asserted it;
the auditor disproved it (iOS `FoliateReaderViewModel.currentLocator()` sets `href = lastTOCHref`).
Correct catch. Disposition: the prose claim was withdrawn and replaced with a test,
`from_persistedAzw3LocatorShapes_resolveExactlyAsTheyDidBeforeTheHrefLeg`, after independently
tracing every producer. See "The High" below for the final resolution.

**Medium — a test documented a false premise** ("an unresolvable href acks `ok:false`"). It does
not: `view.goTo` catches a failed resolution and fulfils, so the shim acks `ok:true` with nothing
moved. Reframed as dispatcher-mapping-only; the correction propagated to the `FoliateBridge` KDoc
and the `reader.html` shim header. RESOLVED.

**Low — the shim accepted inherited / non-string hrefs**, letting a malformed target shadow a
legitimate fraction. Guard is now an OWN, non-blank STRING property. RESOLVED (r2 confirmed).

**Low — static shim assertions could be satisfied by commented-out text.** `executableJsOf` now
strips comments before matching. RESOLVED (r2 confirmed for whole-line, r3 for trailing).

**Low — the escaping test overclaimed.** Now states exactly what it proves; gained a
JS-line-terminator case (U+2028 / U+2029 / CR / LF / NUL / BOM). RESOLVED.

## Round 2 — findings and disposition

The High was restated with a sharper mechanism: `AnnotationsRepository.restoreAnnotations` accepts
an arbitrary decoded locator from a backup file, so the flip-shape `(cfi=null, href=…,
progression=0.37)` is production-reachable even though — by the auditor's own producer enumeration
— **no live producer on either platform emits it**. Proposed fix: `cfi → progression → href` for
persisted locators plus a TOC-only resolver for WI-6.

Also: the whitespace-only href divergence (Kotlin `isNotBlank` vs shim `!== ''`), trailing-comment
stripping, the counterproductive `</script>`-stays-raw assertion, and an overclaim of my own that
round 2 correctly caught (the new test claimed a future producer would fail it; it would not —
they are hand-built fixtures). All fixed.

## The High — resolved in round 3, on the merits

Round 3 was given one material fact rounds 1–2 did not have, and asked to verify it itself rather
than take it from me: **iOS's `FoliateNavSeek.navigationTarget` — the target resolver for this exact
engine and format — is `cfi → href` with NO progression leg at all.**

The auditor's own conclusions:

- **B1** — iOS jumps by **href** for the flip-shape.
- **B2** — Android's `cfi → href → progression` **matches** iOS.
- **B3** — the proposed `cfi → progression → href` would **diverge** from iOS.
- **B4** — "Matching iOS is the correct goal. Preserving Android's pre-WI-3 behavior is not a useful
  compatibility requirement for a shape no live producer emits, particularly when the previous
  resolver could not express the canonical href at all. Plan §5.2 explicitly requires href to
  outrank progression as defense 1."
- **B5** — the restore boundary is **not** the right place to fix it: "the locator contract permits
  both canonical `href` and `progression`; rejecting or rewriting that combination during restore
  would … potentially discard valid cross-platform data."

> "Therefore, the former High is already-correct behavior, not a blocker or required follow-up."

Plan §5.2 defense 1 stands unmodified. No plan amendment is needed.

## Round 3 — findings, all fixed in-lane

1. **Medium — the ack contract was still internally contradictory.** `reader.html` said "only a
   REJECTED promise yields `ok:false`" while the code also acks `ok:false` for a missing
   `readerAPI`/target, a target with no recognized field, and a synchronous throw. Fixed: the shim
   header now enumerates the exact contract, and `Azw3GoToResult.Failed`'s KDoc matches it. The
   `DEFAULT_GOTO_TIMEOUT_MS` comment no longer says foliate "must relocate + ack".
2. **Low — stale parenthetical** ("asserted below") left by removing the `</script>` assertion. Fixed.
3. **Low — the whitespace fix was not regression-pinned**; reverting `trim() !== ''` to `!== ''`
   would have stayed green. Fixed: the static shell assertion now requires it.

## Open items — OUTSIDE this WI's write-set (carried to the orchestrator)

These were raised across rounds and are real, but the owning files belong to other work items:

- `Azw3Document.kt` / `Azw3ReaderActivity.kt` KDoc still equates the ack with the jump "landing"
  (WI-5 and WI-6 own these files).
- `Azw3ReaderActivity.kt` sets `currentCanonical = record.locator` off a `Succeeded` that may not
  have moved the reader — a behavioral item for WI-6, not a comment nit.
- `FoliateBridge.kt` is 341 lines and `FoliateGoToTest.kt` 634, both past the ~300-line guideline.
  Splitting either needs a new file outside this write-set. The auditor rated deferring these
  acceptable as non-blocking cleanup.
- The test name `gotoJs_hrefIsJsonEscaped_quotesBackslashesScriptTagsNeutralized` overclaims
  (`</script>` is deliberately NOT neutralized — it is safe only because the string reaches
  `evaluateJavascript`, never an HTML parser). The name is fixed by the plan's WI-3 `tests:` list,
  so renaming it is a plan amendment.

## Mutation pass (the real evidence the tests bite)

Seven mutations, each applied, confirmed RED, and reverted:

| Mutation | Tests killed |
| --- | --- |
| precedence reordered to progression-before-href | 3 — incl. both §5.2 regressions |
| href fragment stripped before escaping | `gotoJs_hrefWithFragmentQueryOrNonAscii_isPassedThroughUNCHANGED` |
| shim calls `goToFraction` for an Href target | `gotoJs_hrefTarget_callsReaderApiGoTo_notGoToFraction` |
| ack await dropped (fire-and-forget goTo) | 10 — incl. `hrefGoTo_awaitsAck_andSupersedeStillApplies` |
| href guard weakened to `!= null` | `gotoJs_hrefTarget_callsReaderApiGoTo_notGoToFraction` |
| shim branch commented out (whole line) | `gotoJs_hrefTarget_callsReaderApiGoTo_notGoToFraction` |
| shim branch moved into a TRAILING comment | `gotoJs_hrefTarget_callsReaderApiGoTo_notGoToFraction` |

No mutation survived.

## Test state

`ANDROID_CMD="cd android && ./gradlew :app:testDebugUnitTest --tests '*Foliate*' --tests '*Azw3*' --rerun-tasks" scripts/run-android-tests.sh`
→ `RUN-ANDROID-TESTS RESULT: SUCCEEDED`, **121 tests / 0 failures / 0 errors** (JUnit XML).
`FoliateGoToTest` itself: 26 tests. `foliate-bundle.js` untouched; its pinned-SHA provenance test
passes (auditor re-hashed it independently in rounds 1 and 2).
