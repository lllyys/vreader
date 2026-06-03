---
branch: feat/feature-86-wi-5b-retrieval-cluster
threadId: codex-exec (run-codex.sh, 3 rounds)
rounds: 3
final_verdict: ship-as-is
date: 2026-06-03
---

# Codex audit — Feature #86 WI-5b: retrieval cluster + whole-book send-flow (Gate 4)

## Implementation summary

The whole-book on-demand retrieval surface + its integration into the chat flow:

- `WholeBookRetrievalViewModel` — the `@MainActor` mirror over the WI-5a reducer
  (phase machine: idle/armed/reading%/ready/partial; ordered async progress;
  `cancel()` → reducer-flag → `.partial`).
- `ChatRetrievalCluster` — the bar morphs to Armed / Reading% (spinner + progress +
  Cancel) / Ready / Partial when the scope is `.wholeBook`.
- `ChatScopeMenu` re-adds the Whole-book row (retrieval now exists).
- `AIChatViewModel` — `wholeBookRetrieval` + `onWholeBookReadRequested`;
  `sendMessage` triggers the on-demand read on the first whole-book question (before
  building context); `isComposerDisabled` while reading.
- `ReaderAICoordinator` — owns the retrieval VM; `runWholeBookRead` resolves ONE
  provider config (pinned) + drives `read` with a per-chunk summarize `condense`
  closure + awaits + re-assembles; `scopedChatContext(.wholeBook)` returns the
  digest once ready (else book-so-far).

Plan: `dev-docs/plans/20260603-feature-86-wi2-chat-scope-sources-retrieval.md` (WI-5).

## Round 1 — 1 High + 1 Medium

| severity | issue | resolution |
|---|---|---|
| High | `handleChatContextChanged` (shared by `setScope` + `setSources`) armed whole-book on EVERY change → a sources toggle downgraded a `.ready` digest back to armed → the next send re-ran the expensive read. | **Fixed.** Track `lastChatScope`; arm ONLY on the transition INTO `.wholeBook`; a sources-only toggle leaves scope unchanged and preserves `.ready`/`.partial`; leaving whole-book disarms. |
| Medium | The composer only disabled *sending* (`canSend`); the `TextField` stayed editable while reading. | **Fixed.** `.disabled(viewModel.isComposerDisabled)` on the field + `.onChange` drops focus when reading begins. |

Round 1 explicitly cleared: no deadlock/re-entrancy in `sendMessage → onWholeBookRead
Requested → runWholeBookRead → read → await readTask`; the digest ordering before
`buildContextText()` is correct; cancel-to-partial sound; `.wholeBook` degrades to
`.bookSoFar` when no digest exists (backward-compatible); Rule-51 cluster/state reuse
acceptable; `@MainActor` consistent; no dead code.

## Round 2 — 1 Medium

Both round-1 findings confirmed fixed. New: `disarm()` cancelled the consuming
`readTask` but not the reducer, so a stale in-flight read could write `.ready`/
`.partial` back over `.idle` after the user left whole-book.

**Fixed.** A monotonic `generation` epoch: `disarm()` bumps it + calls
`reducer.cancel()` (stops the off-actor work) + `.idle`; `read()` bumps + captures the
epoch and guards BOTH the onProgress hop and the terminal write with
`guard generation == self.generation`, so a superseded read never writes. The user's
`cancel()` (the × button) does NOT bump the epoch, so a user-cancel still lands
`.partial` (keeps what was indexed). Test: `disarm_duringRead_staysIdle_noStaleWrite`.

The file-size note (AIChatView 308 / ReaderAICoordinator 325, marginally over ~300) is
**accepted** — both recently refactored; further extraction is churn.

## Round 3 — 1 Medium fixed + 1 Medium accepted (round cap)

The round-2 generation guard surfaced a deeper nuance:

| severity | issue | resolution |
|---|---|---|
| Medium | `disarm()`'s fire-and-forget `Task { await reducer.cancel() }` could land AFTER a quick re-enter's `reset()` on the SHARED reducer, poisoning the fresh read. | **Fixed robustly** — a **fresh reducer per read** (`reducerFactory()` in `read()`), so the cancel flag is per-read state; an old read's cancel can never touch a new read's reducer (different instance). `reset()` is gone (a fresh reducer starts un-cancelled). This eliminates the shared-flag race *class*, not just one path. |
| Medium | The "cancel→partial" test invokes `reducer.cancel()` directly, not the UI's `vm.cancel()`. | **Accepted with rationale.** `vm.cancel()`/`vm.disarm()` are the same 1-line `if let reducer { Task { await reducer.cancel() } }` forward; the new `disarm_duringRead_staysIdle_noStaleWrite` test exercises `vm.disarm()` → `reducer.cancel()` through the real method, and the reducer-level cancel→partial + the read→`.partial` phase mapping are both deterministically tested. A fully deterministic `vm.cancel()`→partial test needs an async-suspension hook the `read()` API doesn't expose without contrivance; the path is covered by composition. |

**Round cap (rule 47, ≤3).** Round 3 is reached; the substantive correctness issue
(the shared-flag race) is robustly fixed, and the one remaining item is a test-coverage
nicety accepted with rationale. Concluding rather than a 4th round.

## Verdict

`ship-as-is` after 3 rounds (Medium 1 fixed via fresh-reducer-per-read; Medium 2
accepted with composition-coverage rationale).

## Verification

- Unit (green via `scripts/run-tests.sh`): `WholeBookRetrievalViewModelTests` (phase
  machine, cancel→partial, overflow→partial, re-arm), `AIChatViewModelWholeBookTests`
  (send-flow trigger on the first whole-book question; non-whole-book doesn't trigger;
  `isComposerDisabled` cases).
- Tier: behavioral. Gate-5 slice — the menu re-adds the Whole-book row and selecting
  it shows the Armed cluster are device-verifiable; the actual whole-book *read effect*
  is **provider-key-blocked** for CU-free verification (same as WI-1), so it's keyed/
  manual-verification — recorded in the PR.
