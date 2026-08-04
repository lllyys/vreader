---
branch: feat/139-wi-7-host-wiring
threadId: 019fcd1e-bb0f-7242-8b7f-47ee071e50da
rounds: 2
final_verdict: ship-as-is
date: 2026-08-04
---

# Codex Audit Log — Feature #139 WI-7 (host wiring: TXT/MD table of contents)

Wire the already-merged `TxtMdTocProvider` into `TxtReaderActivity` so the
Contents control becomes reachable for TXT/MD books. Before this WI the host
passed `tocEntries = emptyList()` unconditionally, so `ReaderChromeScaffold`'s
empty-list rule hid Contents on every TXT/MD book — WI-1..WI-6 were plumbing
behind a hidden control.

Plan: `dev-docs/plans/20260804-feature-139-android-txt-md-toc.md` (§4.5 the
readiness gate, §7 the WI-7 spec block, **§7a the binding Gate-4 focus**).

## Scope of audit

Three files:

- `android/app/src/main/kotlin/com/vreader/app/reader/TxtReaderActivity.kt` (modified)
- `android/app/src/test/kotlin/com/vreader/app/reader/TxtTocHostWiringTest.kt` (new, JVM)
- `android/app/src/androidTest/kotlin/com/vreader/app/reader/TxtTocConnectedTest.kt` (new, connected)

Session threads: round 1 `019fcd1e-bb0f-7242-8b7f-47ee071e50da`
(`.reports/audit-r1.txt`), round 2 `019fcd23-51e2-7561-be40-3136bc985bf0`
(`.reports/audit-r2.txt`). Both run through `scripts/run-codex.sh` (rule 53).

The round-1 prompt carried §7a verbatim as a binding focus: for every value the
readiness gate observes, confirm against the REAL source that it actually
re-emits; enumerate deadlock paths; confirm the scan runs in scroll, in paged,
and after a mid-session toggle; and hunt a **fourth** instance of the
"mechanism that can never fire" family that this plan produced three times.

## Round 1 findings (3)

| File:line | Severity | Issue | Resolution |
|---|---|---|---|
| `TxtReaderActivity.kt` (`awaitTocScanGate`) | **High** | **The fourth never-fires instance, and a real one.** A *mounted* paged body does not always publish a settled page: when the page index is degenerate or empty, `TxtPagedBody` renders `TxtScrollFallback` instead of a pager (`TxtReaderBody.kt:445-450`), so `onSaveSourceOffset` — and therefore the host's `pagedOffset` — never fires for the whole session. `pagedBodyMounted` stays `true` (it tracks the host's `usePaged`, not the body's internal fallback), so the unbounded `snapshotFlow { … }.first { it }` suspends forever and Contents stays hidden with no crash and no log. | **Fixed** in `548b6644`. Stage 2 of the gate is now `withTimeoutOrNull(PAGED_READY_TIMEOUT_MS)` (3 s, injectable per call). This is the correct degrade rather than a workaround: only stage 1 (`withFrameNanos`) was ever a hard guarantee — the settled-page wait is an optimization to keep the scan off the first-paint path, and the scan is off-main either way. A navigation affordance must not depend on a signal that may never arrive. `TxtReaderBody.kt` is outside this WI's write-set, so a body-side terminal-readiness signal was not available; round 2 confirmed the bounded wait is the best localized fix. |
| `TxtTocHostWiringTest.kt` | Medium | The JVM gate tests drive `runTxtTocScan` with synthetic `mutableStateOf` values, not the production `TxtPagedBody → onSaveSourceOffset → pagedOffset` chain, so they could not have detected the stranding above; no connected test covered a mid-session layout toggle either. | **Fixed.** Added connected `pagedMode_scanCompletes_evenForABookWithNoChapters` (drives the real chain to completion for a headings-free book — the case where a stranded gate would be invisible, since the control is hidden either way) and `layoutToggleMidSession_keepsContentsAvailable`. Added JVM `pagedMode_gateNeverStrands_whenNoSettledPageEverArrives` and `pagedReadyTimeoutIsBounded`. |
| `TxtReaderActivity.kt:441,822` | Low | Two comments still asserted "TXT/MD has no TOC" — false after this WI (rule 22). | **Fixed.** The bottom-chrome comment now says `openContents` is null only while the detected-entry list is empty; the bookmark-row comment names the un-labelled chapter column as the deliberate out-of-scope follow-up F3 (plan §6.3). |

### Round-1 §7a conclusions (recorded, since §7a says a pass that does not address these is not a pass)

- **Every gate read re-emits.** `pagedBodyMounted` and `pagedOffset` are both
  host-owned `mutableStateOf` (created at the host's `remember(s.document)`),
  written by the body's `SideEffect` and its `onSaveSourceOffset` callback
  respectively. Neither is `TxtPageNavigator.index` (a plain `var`) — the banned
  shape that would never re-emit.
- **Deadlock sweep.** Reader closed mid-wait → the composition-scoped effect is
  cancelled. Layout or bilingual toggled mid-wait → `pagedBodyMounted` flips and
  the `!mounted || offset >= 0` predicate releases. Document reloaded → the
  `LaunchedEffect(s.document)` restarts with fresh state. Paged body never
  mounts → `pagedBodyMounted` stays false, so the gate opens on the frame alone.
  Deep resume (`resumePage`/`programmaticPending`) delays but does not withhold
  publication. The one unresolved path was the degenerate/empty fallback above.
- **All three modes scan.** Scroll scans after the first frame; paged after the
  first settled page (or the bound); a mid-session toggle correctly does *not*
  re-scan, because the document is unchanged and the entries are already
  published — now asserted by a connected test.
- **`followSpokenChunkInScroll` extraction is behaviour-preserving**: keys,
  visibility decision, animation and exception swallowing all match the
  pre-change inline effect.
- **Test vacuity check**: the connected positive tests fail if the host passes an
  empty `tocEntries`; the negative test waits for `tocScanCompletedForTest()` so
  it cannot pass via a stuck gate.
- **Rule 51**: no new visible surface. `txtTocIndexFor` recomputes on position
  change but only over the bounded heading-offset list — not material.

## Round 2 findings

**None.** All three round-1 findings confirmed RESOLVED against the current
source, with the High re-checked path-by-path (degenerate index, empty document,
index never publishing, fallback rendering, delayed deep resume all now proceed
within the bound; parent cancellation propagates correctly through
`withTimeoutOrNull`, so a closed composition never triggers a stale scan). The
remaining gap — no connected test for a *degenerate-layout* fallback
specifically — was judged not material, because the timeout's behaviour does not
depend on which production condition withholds the offset.

Verdict: **ship-as-is**.

## Mutation evidence (author-run, before the audit)

A gate test that cannot fail is worse than no test, so each claim was checked by
breaking the implementation and confirming the named tests go red:

| Mutation | Result |
|---|---|
| A — delete `withFrameNanos { }` (the gate fires too early) | JVM 10/0 → **10/6**: `scanMustNotStartBeforeTheFirstFrame`, the paged tests' `produceFrame` awaiter assertion, and `preScanState_passesEmptyEntries…` all fail |
| B — `.first { false }` (the gate can never open — the banned shape) | JVM 10/0 → **10/6**: every "the gate releases" and "the scan ran/published" assertion fails |
| C — pass `tocEntries = emptyList()` to the chrome unconditionally (the pre-WI-7 bug, restored) | connected 8/0 → **8/5**: control-visibility, the real UI row tap, the MD sheet, the live highlight and the scroll TTS re-follow all fail. (The two paged tests drive the jump lambda directly and are by design unaffected — the scroll-mode test is the one that walks the production UI path.) |

## Test results at the audited commit

- JVM `TxtTocHostWiringTest`: **12 tests, 0 failures**
- Connected `TxtTocConnectedTest`: **10 tests, 0 failures** (emulator-5554)
- Full `:app:testDebugUnitTest`: **1586 tests, 0 failures**
- Connected regressions, one class per run: `TxtReaderChromeUiTest` 6/0,
  `TxtPagedTtsFindConnectedTest` 4/0, `TxtFindInBookTest` 6/0,
  `TxtReaderBilingualConnectedTest` 8/0.
- `TxtReaderActivityTest` 6 tests / 1 failure
  (`tapExistingHighlight_opensEditPopover_andRemoveDeletesIt`) — **proven
  pre-existing** by stashing this branch's changes and re-running the same class
  on the clean base, where it fails identically. Known long-press/gesture
  emulator-flake class; unrelated to this WI.
