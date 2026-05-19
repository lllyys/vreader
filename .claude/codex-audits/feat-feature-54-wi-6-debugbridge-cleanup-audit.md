---
branch: feat/feature-54-wi-6-debugbridge-cleanup
threadId: 019e3df5-1071-7242-b99e-9f7710c97dcd
rounds: 2
final_verdict: ship-as-is
date: 2026-05-19
---

# Codex audit — feature #54 WI-6 (DebugBridge cleanup — retire openPositionUnsupportedInUnifiedMode)

## Scope

`git diff main` on branch `feat/feature-54-wi-6-debugbridge-cleanup` (feature-#54 WI-6 changes only; unrelated origin/main merge files excluded):

- `vreader/Services/DebugBridge/RealDebugBridgeContext.swift` — remove the unified-mode guard + dead `formatUnsupported` catch arm + the `openPositionUnsupportedInUnifiedMode` enum case.
- `vreader/Services/DebugBridge/DebugBridge.swift` — remove the matching `stableErrorMessage` branch.
- `vreaderTests/Services/DebugBridge/RealDebugBridgeContextTests.swift` — new test.
- `docs/architecture.md` — doc-sync.
- `project.yml` / pbxproj — version bump → 3.31.11.

## Note — plan ordering correction

The plan §4 listed WI-5 before WI-6. That ordering is wrong: `RealDebugBridgeContext` reads `store.readingMode`, so WI-5's removal of the field would break the DEBUG build without WI-6's guard removal first. WI-6 was therefore done **before** WI-5.

## Round 1

**Verdict: follow-up-recommended.** No Critical/High/Medium. The auditor confirmed the WI-6 implementation matches the spec: the unified-mode guard removed, step comments correctly renumbered (4→3, 5→4), the dead `catch` arm correctly removed (`DebugPositionResolver.resolve` handles every `BookFormat` directly and never throws `formatUnsupported` — verified), the enum case + `stableErrorMessage` branch removed with the switch still exhaustive, no orphaned `ReaderSettingsStore`/`BookFormat`/`FormatCapabilities` references, all edits DEBUG-gated.

- **Low** — `RealDebugBridgeContextTests.swift`: `openTask.cancel()` did not stop the in-flight `awaitReader` wait (`DebugReaderRegistry.awaitReader` is not cancellation-aware — resumes only via registration or its 10s timeout). The test passed but left an unstructured task alive ~10s; the "detached" comment was inaccurate. Fix: avoid the long-lived waiter.

## Resolution (round 1 → round 2)

After the open notification fires (proving the guard removal), the test registers a stub `DebugReaderProbeAdapter` matching the book key — `DebugReaderRegistry.register(_:)` resumes the `awaitReader` waiter deterministically, so `open` completes cleanly and the test joins it with `try await openTask.value`. Added `DebugReaderRegistry.shared.reset()` setup/teardown. Test now passes in 0.020s.

## Round 2

**Verdict: ship-as-is.** The test is now a sound regression guard — deterministic `awaitReader` resume, no lingering task, no 10s-timeout dependency, sufficient isolation.
