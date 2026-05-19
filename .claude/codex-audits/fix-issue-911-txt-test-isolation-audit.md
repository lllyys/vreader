---
branch: fix/issue-911-txt-test-isolation
threadId: 019e3f8f-73a6-78f1-964e-7081d30ef1c7
rounds: 1
final_verdict: ship-as-is
date: 2026-05-19
---

# Codex Audit — GitHub issue #911 (Bug #225)

TXT / SelectiveRestore test-isolation defect under Swift Testing's parallel
execution. Test-only fix — no production code touched.

## Scope

Two changed files:

- `vreaderTests/Services/TXT/TXTReaderViewModelTests.swift`
- `vreaderTests/Services/Backup/SelectiveRestoreCoordinatorTests.swift`

## The bug

Both suites registered `NotificationCenter.default` observers with
`object: nil`. Swift Testing runs `@Test` methods in parallel by default,
so sibling tests' notification posts bled into a capturing test's observer:

- `TXTReaderViewModelPositionBroadcastTests`: `observeLocator()` counted ALL
  `.readerPositionDidChange` posts; `openSeedsRestoredPosition`'s
  `#expect(observer.count() == 1)` failed (count → 5-7).
- `SelectiveRestoreCoordinatorTests`: `preplant_partialSuccess_notifiesForLandedRowsOnly`
  and `preplant_postsBookFileStateDidChange_perRow` captured
  `.bookFileStateDidChange`; sibling `restoreSelectively` posts polluted
  `receivedKeys` (10 keys observed vs the 1 / 3 expected).

Production code (`TXTReaderViewModel.broadcastPosition`,
`SelectiveRestoreCoordinator.postPreplantNotifications`) is correct — it
posts exactly once per legitimate event. Confirmed PRE-EXISTING on
`origin/main`; not a product defect.

## Fix-direction note (why not `.serialized` alone)

The `docs/bugs.md` row suggested `@Suite(.serialized)` as the lowest-risk
fix. An empirical attempt with `.serialized` ALONE was **insufficient** —
running the suites with the trait applied still produced cross-test
pollution (10 keys captured, including sibling tests' fingerprints). The
shipped fix instead makes each capturing observer FILTER deterministically
by a globally-unique discriminator, which is immune to parallel
scheduling. `.serialized` is kept on both suites only as cheap
defense-in-depth + documented intent (matching the bug #213
`BookSourceHTTPClient` precedent).

## The fix

- **TXT suite**: `observeLocator(for:)` filters captured posts by the
  posting `Locator.bookFingerprint`. Each of the 5 broadcast tests mints
  its own unique fingerprint via `uniqueFingerprint()` (UUID-derived
  64-char SHA). A sibling's posts carry a different fingerprint and are
  dropped — each test observes exactly its own VM's broadcasts.
- **SelectiveRestore suite**: the two `preplant_*` tests mint entries from
  `makeUniqueEPUBBytes()` (UUID-salted bytes → globally-unique
  `fingerprintKey`) and observe through `observePreplant(expectedKeys:)`,
  which records only posts whose `fingerprintKey` is in the test's own key
  set. The other 7 tests in the suite keep seed-based `makeEPUBBytes` (they
  register no `.bookFileStateDidChange` observer, so they can pollute but
  not be polluted; their seed-based keys can never match the `preplant_*`
  tests' UUID-unique keys).

## Round 1 findings

| file:line | severity | issue | resolution |
|---|---|---|---|
| `SelectiveRestoreCoordinatorTests.swift` ~464 | Low | `preplant_postsBookFileStateDidChange_perRow` asserted `Set(capture.receivedKeys) == expectedKeys` — a `Set` comparison hides a regression that double-posts an expected key. | **Fixed.** Added `#expect(capture.receivedKeys.count == entries.count)` before the set comparison. The key-set filter already drops sibling pollution, so the cardinality check now pins "one notification per row". |

Codex confirmed everything else clean:

- **Correctness**: both observers filter on payload identity the production
  code actually posts (`Locator.bookFingerprint` for TXT;
  `userInfo["fingerprintKey"]` for preplant). Each test mints its own
  discriminator → sibling posts dropped regardless of parallel scheduling.
- **Determinism**: `uniqueFingerprint()` builds a valid 64-char lowercase
  hex string; `makeUniqueEPUBBytes()` embeds `UUID().uuid` bytes — UUID
  collision risk is astronomically low and sufficient for test isolation.
- **Regression detection preserved**: `preplant_partialSuccess` filters by
  all 3 manifest keys then asserts exact array equality to `[goodA]` — still
  catches a wrongful notify for B or C. `preplant_postsBookFileStateDidChange_perRow`
  catches under-notification (set mismatch) and, after the round-1 fix,
  over-notification (cardinality mismatch).
- **No broken cross-test byte assumption**: `makeUniqueEPUBBytes()` used
  only in the 2 notification-capture tests; the other 7 keep seed-based
  bytes.
- **Validation path verified**: `DocumentFingerprint`'s memberwise init does
  NOT validate the SHA (`DocumentFingerprint.swift:13`); only
  `validated(...)` checks format (`:33`). `Locator.validated`
  (`Locator.swift:59`) validates locator fields only, not the fingerprint
  SHA. `LocatorFactory.txtPosition` (`LocatorFactory.swift:72`) forwards the
  fingerprint without re-validation. The fix's UUID-derived SHAs are
  therefore accepted exactly like the fixture `testFingerprint`.
- **Swift 6 concurrency**: TXT observer (`queue: nil`, synchronous delivery,
  suite `@MainActor`, `nonisolated(unsafe)` captures) — acceptable;
  with unique per-test fingerprints, cross-test posts do not mutate shared
  state. Preplant observer (`queue: .main`, `MainActor.assumeIsolated`
  consistent with the `@MainActor` capture object) — acceptable.
- **No dead code / unused symbols** introduced.

## Round 1 verification reply

Codex re-reviewed the cardinality-assertion fix: "The added assertion is
correct and it closes the only gap I found. ... The audit is now clean. No
open findings."

## Verdict

**ship-as-is.** 1 audit round; the single Low finding was fixed and
verified. Test-only fix; no production code modified. Both suites pass
14/14 under Swift Testing's default parallel mode (3 consecutive runs
deterministic).
