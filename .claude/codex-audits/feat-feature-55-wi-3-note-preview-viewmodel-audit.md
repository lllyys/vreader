---
branch: feat/feature-55-wi-3-note-preview-viewmodel
threadId: 019e3eb6-6e89-7481-801e-1b7d12b3bf17
rounds: 2
final_verdict: ship-as-is
date: 2026-05-19
---

# Codex Audit — feature #55 WI-3 (NotePreviewViewModel)

## Scope

Files changed:
- `vreader/ViewModels/NotePreviewViewModel.swift` (new, 89 LOC) — `@Observable @MainActor` view model
- `vreaderTests/ViewModels/NotePreviewViewModelTests.swift` (new) — Swift Testing tests with a gated mock `HighlightLookup`
- `vreader.xcodeproj/project.pbxproj` — xcodegen regen

## Round 1

Codex thread `019e3eb6-6e89-7481-801e-1b7d12b3bf17`, sandbox `read-only`.

| file:line | severity | issue | resolution |
|---|---|---|---|
| NotePreviewViewModelTests.swift | Medium | The out-of-order guard was proven on the success path only — not on the throw / nil early-return branches. A regression that cleared `presented` before the stale-token check in `catch` or the nil path would still pass. | **Fixed** — added two gated race tests: `handleTap_outOfOrder_olderThrowingLookupDoesNotClearNewer()` and `handleTap_outOfOrder_olderNilLookupDoesNotClearNewer()`. The mock gained `armFirstCallGate(throwsOnRelease:)` so the gated first call can throw on release. Both assert the newer tap's card survives. |
| NotePreviewViewModelTests.swift | Low | The mock ignored `forBookWithKey`, so `bookFingerprintKey` forwarding was untested — a meaningful coverage gap given book-scoping prevents cross-book leakage. | **Fixed** — the mock gained `expectedKey` / `requireKey(_:)` / `receivedKeys`. New test `handleTap_forwardsBookFingerprintKeyToLookup()` asserts the positive case (record surfaces + `receivedKeys.last`) and the negative case (a wrong-book view model gets nil). |

Implementation itself: auditor confirmed the monotonic-token guard is correct
(tap A token 1, tap B token 2 — B publishes, A on resume fails the guard and
cannot overwrite B; the `catch` clears only when the token is still latest);
the `@MainActor` story is correct (`&+=` + capture with no intervening await,
the equality check detects mutation during the suspension; `&+=` wrap
acceptable; `any HighlightLookup` storage fine since the protocol is
`Sendable`); `dismiss()` bumping the token is sufficient against the
in-flight-resurrect race. No Critical/High at any point.

## Round 2

Same thread — verification of the round-1 test additions.

| file:line | severity | issue |
|---|---|---|
| — | — | No findings — Critical / High / Medium / Low all clear |

Auditor confirmed: the two new gated race tests are deterministic (same
gated-continuation mechanism as the success-path test) and genuinely exercise
the stale-token guard on the throw and nil early-return branches; the mock's
`firstCallThrows` / `throwAfterGate` handling has no double-resume or
leaked-continuation bug (`throwAfterGate` is copied to a local before
suspension; both continuations are resumed at most once and nulled
immediately); the key-forwarding test proves forwarding via both the positive
and negative cases. Verdict: "the round-1 fixes are adequate."

## Verdict

**ship-as-is** — 2 rounds. Round 1: 1 Medium + 1 Low (both test-coverage gaps,
implementation was already correct), both fixed. Round 2: zero findings.
