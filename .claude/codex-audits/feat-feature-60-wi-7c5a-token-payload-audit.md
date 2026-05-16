---
branch: feat/feature-60-wi-7c5a-token-payload
threadId: 019e2f21-e10c-7240-9d3a-9e7232062f78
rounds: 2
final_verdict: ship-as-is
date: 2026-05-16
---

# Codex Audit — Feature #60 WI-7c5a typed payload + request-token plumbing

## Round 1 — 2 Lows

### Low #1 — `requestToken` pass-through untested
- **`vreaderTests/Views/Reader/TXTBridgeSharedTests.swift`** | Low
  The new `requestToken` parameter on
  `TXTBridgeShared.postSelectionNotification` is never exercised by
  a test. No production TXT/MD caller passes a non-nil token, so a
  future regression in the helper's delegation to
  `SelectionPopoverRequest.post(selection:requestToken:)` would go
  uncaught.

**Resolution**: Fixed. Added
`postSelectionNotificationPassesThroughRequestToken()` —
calls `postSelectionNotification(.readerSelectionPopoverRequested,
from:, range:, requestToken: token)` and asserts
`SelectionPopoverRequest.payload(from:)?.requestToken == token` plus
the selection round-trip. New test passes; TXTBridgeShared suite is
6 tests, all green.

### Low #2 — stale `ReaderNotifications.swift` companion comment
- **`vreader/Views/Reader/ReaderNotifications.swift:130`** | Low
  The `readerSelectionPopoverRequested` doc comment still said the
  notification `object` is a `TextSelectionInfo` — WI-7c5a changed
  the primary wire shape to `SelectionPopoverRequestPayload`.

**Resolution**: Fixed. Comment now documents the
`SelectionPopoverRequestPayload` object (selection + optional
`requestToken`) and the legacy bare-`TextSelectionInfo`
compatibility via `SelectionPopoverRequest.payload(from:)`.

## Round 2 — clean

Codex verified both fixes: *"No findings. Both Round 2 fixes are
correct. … WI-7c5a looks clean for merge."*

## Accepted with rationale (not blocking)

- **`requestToken` speculative generality on
  `postSelectionNotification`**: no current caller passes it
  non-nil (TXT/MD pass nil; EPUB WI-7c5b does not route through
  this helper). Codex round 1: *"acceptable speculative generality
  in this case because it is internal, small, and explicitly
  called for by the plan; I would keep it, just pin it with the
  missing test"* — the test was added (Low #1 fix).
- **Test-file size**: `SelectionPopoverActionRouterTests.swift`
  (319 lines) and `SelectionPopoverPresenterTests.swift`
  (306 lines) are marginally over the repo's ~300-line guideline.
  Accepted: cohesive single-contract Swift Testing suites;
  splitting would scatter one notification contract across files,
  and the ~300 guideline targets production-code readability.
  Codex: *"I would not block on that alone."*

## Verdict statement

**ship-as-is** after round 1 (2 Lows both fixed). Round 2 clean.

All 8 audit dimensions clean:
1. Correctness — matches the plan v10 WI-7c5a spec exactly (typed `SelectionPopoverRequestPayload`, `post(...requestToken:)`, `payload(from:)` migration-safe, `route(action:payload:)`, `postSelectionNotification` delegation, `nextPending(after:currentPayload:)`).
2. Edge cases — nil token, legacy-bare-`TextSelectionInfo` migration branch, `makeUserInfo` nil-vs-empty-dict, the `.readerSelectionPopoverRequested` name branch — all covered by tests.
3. Security — none (pure NotificationCenter, in-process).
4. Duplicate code — `makeUserInfo` is the right factoring for the token+color userInfo assembly; no other dup.
5. Dead code — none. `requestToken` param accepted as plan-mandated speculative generality, now test-pinned.
6. Shortcuts / patches — none.
7. VReader compliance — Swift 6 satisfied (`nonisolated` on `payload(from:)` so the synchronous NotificationCenter observer closure can call it without "sending note risks data races"); `@MainActor` correctness preserved on `post`; all touched runtime files <300 lines.
8. Bridge safety — N/A (no JS). The router still posts a bare `TextSelectionInfo` as the action notification's `object`, so `ReaderNotificationModifier` + `ReaderContainerView` consumers are unaffected — Codex confirmed.

## Test results

- WI-7c5a's 6 affected suites: 40 tests pass (SelectionPopoverPresenterTests, SelectionPopoverRequestPayloadTests, SelectionPopoverDismissPolicyTests, SelectionPopoverActionRouterTests, TXTTextViewBridgeEditMenuTests, TXTChunkedReaderBridgeEditMenuTests) + TXTBridgeShared 6 tests.
- Full `vreaderTests` gate: WI-7c5a code clean; the only full-gate failures were the pre-existing parallel-execution flakes (`ReplacementTransformTests`, `CoverLifecycleTests`) — confirmed pass in isolation (17/17). Same flake class documented in WI-7c2's audit log.

## Strengths called out by Codex

- The routed action notifications still carry bare `TextSelectionInfo` objects, so `ReaderNotificationModifier` and `ReaderContainerView` remain compatible — the wire-format change is contained to `.readerSelectionPopoverRequested`.
- `payload(from:)` is migration-safe — a producer still posting a bare `TextSelectionInfo` decodes as a tokenless payload, so the contract change is not a flag-day break.

## Follow-up items

None. WI-7c5b (EPUB producer/consumer swap) consumes this token plumbing — next WI.
