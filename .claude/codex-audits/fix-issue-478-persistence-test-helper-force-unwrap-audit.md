---
branch: fix/issue-478-persistence-test-helper-force-unwrap
threadId: 019e0dc5-8a59-72d2-a5d7-952d7cc786aa
rounds: 3
final_verdict: ship-as-is
date: 2026-05-10
---

# Codex Audit — bug #161 / GH #478 (PersistenceHighlightTests / PersistenceBookmarkTests force-unwrap crash)

Tests-only change. `makeLocator(key:offset:)` in both test files force-unwrapped `DocumentFingerprint(canonicalKey: key)!`; tests passing deliberately-bogus keys ("wrong:key:123", "missing:key:999") trapped on nil. Pre-existing on `main` (commit `b2063b6`); blocks the `/fix-issue` test gate for unrelated bug fixes on the shared simulator.

## Round 1

| File:Line | Severity | Issue | Resolution |
|---|---|---|---|
| `vreaderTests/Services/PersistenceHighlightTests.swift:69` | Medium | After the helper fallback is added, `addHighlightToMissingBookThrows` no longer tests the missing-book path. The locator's fingerprint canonicalKey is the SHA-derived bogus value, not `"missing:key:999"`, so the `bookKeyMismatch` guard at `PersistenceActor+Highlights.swift:37` fires before the missing-book lookup at `:46`. Test name and intent diverge. | **Fixed.** Switched the test to construct a parseable canonical key from a real fingerprint (`sha = String(repeating: "b", count: 64)`, byteCount = 1) — different from the default-inserted book (`sha = "aaa…a"`, byteCount = 1024) — and pass that key to both `makeLocator` and `toBookWithKey`. The mismatch guard now passes; the predicate fetch returns 0 books and throws the actual missing-book error. |
| `vreaderTests/Services/CollectionTestHelper.swift:33` | Low | The `makeBogusFingerprint(seed:)` docstring claimed "guaranteed not to match a real book's canonical key", which is stronger than the helper provides — a real EPUB with `fileByteCount == 0` and the same SHA would collide. | **Fixed.** Reworded the docstring to describe a deterministic well-formed fallback fingerprint without overclaiming distinctness. |

## Round 2

| File:Line | Severity | Issue | Resolution |
|---|---|---|---|
| `vreaderTests/Services/PersistenceHighlightTests.swift:11` and `PersistenceBookmarkTests.swift:11` | Low | The inline `makeLocator` comments still said "well-formed but distinct fingerprint", echoing the round-1 overclaim. | **Fixed.** Replaced with "deterministic, well-formed fallback fingerprint" so the comments match the helper contract. |

## Round 3

Zero open findings.

## Summary verdict

`ship-as-is`. Test-helper-only change. The fix replaces a force-unwrap with a tolerant fallback that derives a deterministic well-formed `DocumentFingerprint` from the seed string via `SHA256.hash`, so the rejection-path tests can run without trapping. The previously-misnamed `addHighlightToMissingBookThrows` now exercises the actual missing-book lookup. All 22 tests in the two affected suites pass.

Production code is unaffected. Test gate (`xcodebuild test -only-testing:vreaderTests`) was previously crashing in `PersistenceHighlightTests` / `PersistenceBookmarkTests` and now runs to completion, unblocking the `/fix-issue` pipeline for other bugs on the same simulator.
