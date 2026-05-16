---
branch: fix/issue-737-bookformat-azw3-tts-stale
threadId: 019e2e1d-bf9d-74e2-9d39-169e8b14402e
rounds: 2
final_verdict: ship-as-is
date: 2026-05-16
---

# Codex Audit — Bug #200 / GH #737

Bug: `BookFormatAZW3Tests` still expected `.tts` in the AZW3 capability
set, but PR #644 (Bug #176 / GH #602) intentionally cap-gated `.tts`
off AZW3 because `ReaderAICoordinator.loadBookTextContent` has no
AZW3/MOBI case — TTS would silently fail. Two assertions in the
suite were therefore stale and would fail against the production
capability set.

This is a pure-test fix: two assertions inverted in
`vreaderTests/Models/BookFormatAZW3Tests.swift`. No production code
changes.

## Round 1 findings

| File:Line | Severity | Issue | Fix |
|---|---|---|---|
| `vreaderTests/Models/BookFormatAZW3Tests.swift:102` | Low | `capabilitiesDoesNotSupportTTSUntilFoliateWiringShips` was described as a "BookFormat-path mirror" of the canonical `azw3_doesNotSupportTTS` regression guard in `FormatCapabilitiesTests`, but both tests called `FormatCapabilities.capabilities(for: .azw3)` directly — making it a true duplicate rather than a second-path guard. | Switched assertion to exercise `BookFormat.azw3.capabilities` (the convenience property at `vreader/Models/BookFormat.swift:38-40`) — the path through which production view-models and host dispatchers resolve capabilities. Rewrote the doc comment to explain why the convenience path is the right exercise target. The companion test `azw3 convenience property matches direct factory call` at line 178 already cross-checks the two paths return identical sets, so neither test is redundant. |

## Round 2 findings

No findings. Codex Round 2 verdict (verbatim):

> 1. Round 1 Low finding is resolved. BookFormatAZW3Tests.swift:102
>    now exercises `BookFormat.azw3.capabilities`, while the canonical
>    guard in FormatCapabilitiesTests.swift:120 still exercises
>    `FormatCapabilities.capabilities(for: .azw3)` directly. That
>    removes the "same path twice" problem.
> 2. No new issues introduced. The updated comment matches the code,
>    and the existing parity check at BookFormatAZW3Tests.swift:178
>    usefully cross-links the wrapper to the factory.
> 3. Ready to ship. The fix still addresses the root cause, and the
>    Round 1 adjustment improved the test's contract coverage rather
>    than weakening it.

## Summary

Ship-as-is. Two inverted assertions now align with the post-PR-#644
capability contract:

- `capabilitiesDoesNotSupportTTSUntilFoliateWiringShips` — exercises
  the `BookFormat.azw3.capabilities` convenience-property path,
  complementing (not duplicating) the canonical
  `FormatCapabilities`-path guard in `FormatCapabilitiesTests`.
- `capabilitiesMatchSimpleEPUBExceptTTS` — asserts the precise diff
  (`azw3Caps.union(.tts) == epubCaps` AND `!azw3Caps.contains(.tts)`)
  rather than equality between the two capability sets.

Test gate: 25/25 BookFormatAZW3Tests pass.
