---
branch: test/bug-265-persistence-integration
threadId: 019e63ed-f38c-7c63-8b15-3922171dec49
rounds: 1
final_verdict: ship-as-is
date: 2026-05-26
---

# Codex Audit — Bug #265 persistence integration test + tracker reconciliation

This branch carries:
- `vreaderTests/Integration/FoliatePositionPersistenceIntegrationTests.swift` (new) —
  high-fidelity controller → `ReaderPositionService` → real in-memory
  `PersistenceActor` (SwiftData) round-trip for the Foliate position save/restore.
- `docs/bugs.md` reconciliations: #270 → FIXED (resolved by Feature #72), #269 →
  WONT DO (purpose resolved by Feature #72), #265 → REOPENED (device verification
  FAILED — see below).
- `dev-docs/verification/bug-265-20260526.md` (result=fail) — the device-verification
  finding that reopened #265.

Only the test file is Swift; the rest is docs.

## Round 1 findings

| # | file:line | severity | issue | resolution |
|---|---|---|---|---|
| 1 | FoliatePositionPersistenceIntegrationTests.swift (header) | Medium | The test comments overstated fidelity — it drives the real persistence path but does NOT exercise the production `FoliateBilingualContainerView+Position` view-wiring (the missing-call seam Bug #265 lived in), and the "existing 9 gate-logic tests" it referenced use `MockPositionStore`, not view-wiring tests. | **Fixed.** Narrowed the test header to state explicitly: this verifies the controller↔real-persistence round-trip ONLY; the live SwiftUI/WKWebView wiring (`.onReceive(.foliateRelocated)` / `.task` / `.onDisappear`) remains device-verification-blocked. |

Codex confirmed everything else is sound: genuinely high-fidelity on persistence
(real in-memory `PersistenceActor`, no mock store), assertions are non-trivial
(direct `loadPosition` read-back + fresh-controller reopen), `flush()`/
`debounceNanoseconds: 0` are correct, Swift 6 `@MainActor` isolation is correct,
flake risk low (in-memory store, no time-based waits).

## Note — the Medium was prophetic

After this audit, a CU-free device verification (on the bundled `mini-azw3`
fixture + the `seek?fraction=` command) confirmed exactly the gap Codex flagged:
the merged #265 fix does **not** restore position end-to-end on the live Foliate
path (reopen resumes at the start). The persistence layer this test covers is
sound; the failure is in the live save/restore-seek application. #265 is therefore
REOPENED (see `dev-docs/verification/bug-265-20260526.md`); this test stands as
regression coverage for the persistence subsystem boundary the eventual fix
depends on.

## Verdict

**ship-as-is** — the test is correct, high-fidelity for its (now accurately
scoped) target, and the tracker reconciliations reflect verified reality.
