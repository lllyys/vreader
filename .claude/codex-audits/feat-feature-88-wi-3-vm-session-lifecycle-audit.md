---
branch: feat/feature-88-wi-3-vm-session-lifecycle
threadId: 019e978b-d907-7cc3-90e6-c64171850987
rounds: 7
final_verdict: follow-up-recommended
date: 2026-06-05
---

# Gate-4 audit — Feature #88 WI-3 (AIChatViewModel session lifecycle + streaming handoff)

WI-3 adds the chat-session lifecycle to `AIChatViewModel`: one-shot load of the
most-recent non-empty session, lazy create-on-first-turn, debounced settled-turn
save, and the switch / new / rename / delete transitions — wired into the
streaming send path (`+Streaming`). Because every one of these mutates the same
small state set (`messages` / `settledMessages` / `activeSessionId` / the store)
across `await`s on the @MainActor, the audit centered on **async interleaving**.

## Round history

The point-patch rounds (1–5) each found a real new interleaving and fixed it
with a targeted guard. Round 5 concluded the *class* was not closeable by more
await-boundary patches and recommended a **structural** fix; round 6 audited the
structural fix and found one separate (non-interleaving) High, now fixed.

| Round | Finding (sev) | Resolution |
|---|---|---|
| 1 | Load-hook reruns on Chat-tab re-entry → clobbers a fresh thread (High) | `loadedFingerprintKey` idempotency + non-clobber guard |
| 2 | Orphan session left when a transition races the first-turn create (High); orphan-cleanup delete silently swallowed (Medium) | delete the orphan when the token changed mid-create; log (not swallow) a cleanup-delete failure |
| 3 | Test-gate arming was fire-and-forget → nondeterministic gate miss (Medium) | `gateFetch`/`gateUpdate`/… arm `async` + awaited before the raced task |
| 4 | A transition racing an existing-session settled-turn UPDATE seals the STALE snapshot → just-settled turn lost (High) | promote `settledMessages = snapshot` BEFORE the `updateChatSession` await |
| 5 | Whole interleaving class not closeable by point patches (structural) | **moved ALL session-mutating ops onto one serialized async lane** (`runSerializedSessionOp`) — see below |
| 6 | `deleteSession` cancels the active stream + bumps `opCounter` even for a NON-active delete → active turn's save skipped, lost (High) | gate the transition-style cancel/token-bump on `id == activeSessionId` |
| 7 | (confirming audit of the round-6 fix, threadId `019e978b`) | **clean** — round-6 High resolved, no new Critical/High/Medium |

## Round 5 → the structural fix (closes the interleaving class)

All session-mutating public ops (`loadSessions`, `saveSettledTurn`,
`switchToSession`, `newConversation`, `renameActiveSession`, `deleteSession`)
now run their bodies through `runSerializedSessionOp` (`AIChatViewModel.swift:96`):
it captures the prior chain task, builds a new `@MainActor` Task that `await`s the
prior then runs the body, assigns the chain, and `await`s its own completion. The
read-of-prior + write-of-chain happen with no `await` between them, so the
capture+assign is atomic on the MainActor serial executor → two ops launched
without awaiting each other **cannot interleave their bodies**. The synchronous
pre-lane steps (stream cancel + `sessionTransitionToken` bump + `requestedSessionId`)
stay OUTSIDE the lane so a superseded body still bails early on its token check.

Deadlock constraint honored: no laned public op body calls another laned public
op; the only helpers invoked inside laned bodies (`sealCurrentSessionIfNeeded`,
`loadMostRecentRemaining`) are explicitly NON-laned.

## Round 6 — confirming audit of the structural fix (threadId `019e977d`)

Codex confirmed, with line references:

- **Q1 serialization** — `AIChatViewModel.swift:96` does serialize; the capture+assign is atomic; two un-awaited callers cannot interleave. *No fix.*
- **Q2 deadlock** — no laned public op awaits another laned public op; helpers are non-laned. *No fix.*
- **Q3 R5 unrelated-delete-during-save** — **closed** by the lane (delete queues behind the parked save; no interleave). *No fix.*
- **Q4 pre-lane ordering** — correct for supersession; no lost-update on `activeSessionId`. *No fix.*
- **Q5 Swift 6 / @MainActor / Sendable** — clean; spawned task + closure are `@MainActor`, the persistence boundary is `Sendable`. File sizes within cap (287 / 183 / 186 / 292). *No fix.*
- **One High (separate, non-interleaving)** — `AIChatViewModel+SessionTransitions.swift:100` + `+Streaming.swift:178`: `deleteSession` unconditionally treated EVERY delete as a transition (`cancelStreamingForTransition()` + token bump). Deleting an unrelated non-active session B while session A streams cancelled A's stream → `runSend` saw `opId != opCounter` → skipped `saveSettledTurn` → A's latest turn never persisted; a later seal could then write the older snapshot.

### Resolution of the round-6 High (fixed this round)

`deleteSession(_:)` now only performs the transition-style cancel + token bump
when `id == activeSessionId`; a non-active delete still runs through the
serialized lane but leaves the active send untouched (no `opCounter` bump → the
active turn still reaches its settled-turn save). Pinned by a RED→GREEN
regression test `nonActiveDeleteDuringActiveStream_doesNotCancelStream_norLoseTurn`
(gates the active stream mid-flight, deletes a non-active session, asserts the
active turn is still persisted — 4 messages, contains "active q2").

## Round 7 — confirming audit of the round-6 fix (threadId `019e978b`)

Codex verified the one-method `deleteSession` fix with line references:
(1) the round-6 High is resolved — a non-active delete no longer cancels the
active stream nor bumps `opCounter`, so `runSend` still reaches `saveSettledTurn`;
(2) the active-delete-while-streaming path still works (cancel + token bump +
`wasActive` re-eval + `loadMostRecentRemaining`);
(3) `wasActive` stays consistent — a non-active delete returns at `guard wasActive`
before the token check, so the un-bumped token is unused;
(4) no new interleaving from the un-bumped token — the delete still runs through
the serialized lane;
(5) both lane orderings are correct — delete-first → the later switch fetch finds
no record and returns; switch-first → `_deleteSession` re-evaluates `wasActive` and
treats it as an active delete at execution time.
**Verdict: "Round-6 High is resolved. I do not see any new Critical/High/Medium
issue in this one-method fix."**

## Verdict

`follow-up-recommended`. The structural serial lane closes the whole interleaving
race class the point-patch rounds were chasing (Q1–Q5 clean), and the one
separate High found in the confirming audit is fixed + regression-tested. The
auditor's round-5 recommendation — "move session-mutating work onto one
serialized async lane before WI-4 adds more surface area" — is now **implemented**,
so WI-4/WI-5 build on serialized session state rather than a web of await-boundary
guards. 27 prior session tests + 2 structural tests + this regression test green.

### Test rework forced by the structural change (orchestrator-caught)

The serial lane changed the concurrency model: a session op issued while another
is parked now QUEUES behind it (it cannot interleave). Five pre-existing
interleaving tests `await`-ed a transition while a lane op was parked on a test
gate and only released the gate AFTER that await returned — which now **deadlocks**
(the awaited op waits for the parked op; the parked op waits for the release that
never comes). The implementing subagent reported "67/0 passed" but the run had
actually hung on these 5 (the watchdog `TIMEOUT` was misread as a finalization
stall); the orchestrator caught it by reading the test `$LOG` directly — only 23
of 28 session tests flushed, 0 failed, no suite-summary line. The five
(`rapidSwitch_BthenC`, `coldOpen_sendBeforeLoadResolves`,
`transitionDuringFirstTurnCreate`, `orphanCleanupFailure`,
`transitionDuringExistingSessionUpdate`) were reworked to the fire-as-Task
pattern (fire the second op without awaiting so its synchronous pre-lane bump
runs, release the gate, drain the lane, then assert the serialized end-state) —
the same pattern the subagent's own `unrelatedDeleteDuringActiveSave` test uses.
This is a TEST-design fix, not a production change: production gates resolve, so
the lane drains normally with no deadlock. **Lesson: trust the test `$LOG`, not a
subagent's pass claim.**

### Note on round count

This WI exceeded the nominal 3-round Gate-4 cap (6 rounds). The justification is
recorded here per rule 47's escalation clause: rounds 1–4 were convergent
point-fixes (each closed a distinct, real race), round 5 was the auditor's own
structural recommendation (not a new defect), and round 6 confirmed the
structural fix + found one separate, mechanical High with an obvious fix. The
work was converging, not thrashing; the structural fix is the durable close-out.
