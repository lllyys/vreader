---
branch: feat/135-wi2-azw3-goto
threadId: codex-run-codex-sh
rounds: 2
final_verdict: ship-as-is
date: 2026-07-11
---

# Gate-4 audit — feature #135 WI-2 (awaited AZW3/foliate goTo bridge)

Independent Codex audit (rule 53 `scripts/run-codex.sh`, author/auditor separation) of the
awaited AZW3/foliate goTo bridge: `FoliateBridge.goTo` + `FoliateGoToDispatcher` +
`FoliateMessage.GoToAck` + parser branch + `Azw3Document.goTo`/`FoliateGoToController` + the
`foliate-bundle.js` goTo-return patch + the `reader.html` `__vreaderGoTo` shim.

Raw transcripts: `.reports/wi2-audit.txt` (round 1), `.reports/wi2-audit-r2.txt` (round 2).

## Round 1 — verdict: block-recommended (3 findings)

1. **High — cancelled `goTo` leaks its pending request.** `goTo()` only cleared `pending` on ack or
   timeout; a caller cancelled while suspended in `deferred.await()` left the entry (and the orphan
   deferred) behind, so `pendingCount()` stayed 1 and a late ack could resolve the orphan.
2. **High — render-death re-issue does not survive document recreation.** The host recovery
   (`Azw3ReaderActivity`, WI-7) disposes the document and creates a fresh one, so the in-document
   `pendingGoTo` field was lost — the re-issue only fired if the SAME instance got another
   `book-ready`, which is not the production recovery path. The androidTest assertion was tautological.
3. **Medium — single-dispatcher confinement claimed by comment only.** `pending` is mutated from the
   goTo caller's context and the ack collector; safe only under a Main-confinement invariant that was
   not documented/enforced.

## Fixes applied (round 1 → round 2)

- **F1**: `goTo` now clears its pending entry in a `finally` (timeout OR caller-cancellation) and
  completes the orphan deferred, only if the entry is still the one this invocation minted (a
  supersede/ack may have replaced or cleared it — `CompletableDeferred.complete` is a safe no-op if
  already resolved, so the success path's `finally` cannot clobber `Succeeded`). New RED test
  `cancelledGoTo_clearsPending_andLateAckIsIgnored` asserts `pendingCount()==0` after cancel + a late
  ack is a no-op.
- **F2**: added `Azw3Document.takePendingGoTo()` (host reads+clears the held target off the dying
  document during render-death recovery) + `run(restore, pendingGoTo=…)` (seeds the target into the
  replacement, mirroring how `restore`/`resume` already survive recreation). The androidTest
  (`Azw3GoToSliceTest.renderDeathMidJump_pendingTargetSurvivesRecreation`) now exercises the REAL
  carry-across-recreation seam and proves exactly one re-issue after the replacement's book-ready.
- **F3**: documented the single-threaded-scope invariant on `FoliateGoToDispatcher` — production's
  only constructor is `FoliateBridge` (`@MainThread`) with a `Dispatchers.Main` scope; `goTo` + the
  ack collector both run there; the `pending` read-then-replace has no suspension point, so
  interleaving is safe. (Tests use `runTest`'s single-threaded scheduler — the same confinement.)

## Round 2 — verdict: ship-as-is (0 findings)

- F1/F2/F3 all confirmed resolved; no harmful double-completion (`complete` returns false if already
  completed); the `run(pendingGoTo)` seam does not clobber restore/init (restore/init runs first, then
  the carried jump after book-ready; the field is cleared before launch → no replay loop).
- Security (#126) re-confirmed intact: no `addJavascriptInterface`; `addWebMessageListener`
  allow-listed to the shell origin + main-frame; request id + CFI JSON/JS-string escaped; fraction
  finite-only; missing id rejected by the parser; unknown/stale ids ignored; wrong-origin /
  non-main-frame messages never enter the flow.

Non-finding coverage note (not blocking): an explicit "ack-success-immediately-before-finally"
regression test would further document the non-clobber guarantee, but the state-transition ordering
already makes it deterministic.
