---
branch: fix/issue-275-replacement-rules-banner
threadId: 019e0b2d-e835-7511-ab00-7e63658bcd99
rounds: 1
final_verdict: ship-as-is
date: 2026-05-09
---

# Codex Audit — fix/issue-275-replacement-rules-banner

## Round 1

**Files audited**:
- `vreader/Views/Settings/ReplacementRulesView.swift` (constant extraction)
- `vreaderTests/Views/Settings/ReplacementRulesViewBannerTests.swift` (new)

**Findings**: zero.

**Codex summary**:
> No findings in the changed files. The refactor in
> `ReplacementRulesView.swift` is behavior-preserving: the `Text` now
> reads from `Self.nativeModeBannerText`, but the rendered banner
> copy is otherwise identical. The new tests are proportionate
> regression guards: they avoid brittle full-string snapshotting, but
> still pin the two user-critical semantics of the mitigation, that
> rules work only in Unified mode and that the user must switch via
> Reading Mode. `static let` here is also fine under Swift 6 strict
> concurrency because it is immutable `String` data, not shared
> mutable state. Marking bug #128 `FIXED` on the cheap-path precedent
> is reasonable; the proper native-pipeline wiring remains
> feature-class scope rather than bugfix scope.

## Resolution per finding

(none — zero findings)

## Verdict

`ship-as-is`. Mitigation precedent matches bug #120 (Path B
capability-gate). Test gate: new suite (3 tests) pass + full
suite remains green. Pre-FIXED simulator verify confirms banner
renders end-to-end.
