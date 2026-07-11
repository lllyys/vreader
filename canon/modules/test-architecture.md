---
title: Module — test architecture
updated: 2026-07-11
status: verified
---

# Module — test architecture

## Purpose

Describes vreader's test suites as a subsystem in their own right — the framework split, shared helpers, and how suites map onto the product modules the rest of this canon documents. This page intentionally covers `vreaderTests/` and `vreaderUITests/` at directory-level (file-count) inventory, not a per-test-file behavioral account — the tests document the product code, not vice versa; its `status` field follows the whole-page verified/proposed convention set by `canon/decisions/composite-dossier-schema.md`.

## Scale (as of 2026-07-10/11 capture)

- `vreaderTests/`: 694 Swift files.
- `vreaderUITests/`: 73 Swift files.
- `TestPlans/`: `All.xctestplan`, `Verification.xctestplan` (feature #45 WI-6 shipped `Verification.xctestplan`).

## Framework split (per `.claude/rules/10-tdd.md`)

- **Swift Testing** (`import Testing`, `@Test`, `#expect`) is the default for new tests: 647 of 694 `vreaderTests/` files import it directly.
- **XCTest** (`import XCTest`) is *policy*-reserved (per rule 10) for tests needing `XCTestExpectation`/notification-timing machinery or `XCUnwrap` — but that's the stated preference, not the actual split: 25 files import it directly, and 16 of those 25 use neither `XCTestExpectation` nor `XCUnwrap` (e.g. `DebugCommandTests.swift`, `DebugPositionResolverTests.swift`, `DebugSnapshotTests.swift` — ordinary parser/value-behavior suites written as plain `XCTestCase`). The remainder either import both, or are pure support files with no direct test-framework import (fixtures, protocols, helpers).
- `vreaderUITests/` is XCUITest-based throughout (a distinct framework from both of the above, driving the compiled app via accessibility).

## Directory map (`vreaderTests/`, file counts)

| Directory | Files | Covers |
| --- | --- | --- |
| `Services/` | 299 | the bulk of the suite — one test file per service/subsystem, mirroring `vreader/Services/` |
| `Views/` | 257 | SwiftUI/UIKit bridge behavior tests, mirroring `vreader/Views/` |
| `Models/` | 51 | value-type and `@Model` invariant tests |
| `ViewModels/` | 50 | ViewModel state-transition and async-flow tests |
| `Integration/` | 11 | cross-subsystem integration tests (e.g. `Feature72CloudTTSIntegrationTests.swift`) |
| `App/` | 9 | app-bootstrap / `VReaderApp` init-path tests |
| `Utils/` | 6 | pure-utility tests (`AccessibilityFormattersTests`, `ReadingTimeFormatterTests`, etc.) |
| `Fixtures/` | 3 | shared test fixtures |
| `Contracts/` | 2 | `IdentityConformanceTests` and friends — see [[Module — cross-platform contracts]] |
| `Verification/` | 2 | device-verification-adjacent test support |
| `Helpers/` | 2 | `MockBackgroundTaskRequester.swift`, `PollUntil.swift` |
| `Accessibility/` | 1 | accessibility-focused unit tests |
| (root) | 1 | `SmokeTests.swift` |

Each directory mirrors its `vreader/` source counterpart (per `.claude/rules/50-codebase-conventions.md` §8: "Tests go next to the production code, mirroring the source tree"), so the per-module dossiers in this canon (`canon/modules/*.md`) each cite their own test files directly in their `**Verified.**` artifact lists rather than this page re-deriving that mapping.

## `vreaderUITests/` directory map

`AI/`, `Accessibility/`, `Annotations/`, `Errors/`, `Helpers/`, `Keyboard/`, `Library/`, `Navigation/`, `Reader/`, `Search/`, `Sync/`, `Verification/` — one subdirectory per user-facing surface, run against a built app via XCUITest/accessibility rather than in-process. The `Verification/` subdirectory (e.g. `vreaderUITests/Verification/Feature35AnnotationsExportVerificationTests.swift`, cited by [[Module — export]]) holds the acceptance-pass tests referenced by the six-gate workflow's Gate-5 (see [[Decision — six-gate workflow and lane dispatch]]).

## Shared helpers

- `vreaderTests/Helpers/MockBackgroundTaskRequester.swift` — mock seam for background-task-dependent tests (used by feature #98 background-resilient-translation tests — `BackgroundExecutionTokenTests`, `ChapterReTranslateViewModelTests`, `BookTranslationCoordinatorTests` — see [[Module — bilingual translation]]).
- `vreaderTests/Helpers/PollUntil.swift` — polling helper for async-completion assertions, an alternative to bare `Task.sleep` (per rule 10's anti-pattern table: "Bare `Task.sleep(...)` for sync" is flagged).
- Per-module mock types live alongside their tests rather than centrally (e.g. `MockTXTService.swift` inside `vreaderTests/Services/TXT/`, next to `TXTServiceTests.swift`), consistent with rule 10's "mock boundaries, not internal logic" guidance.

## Test commands

Unit tests run via `scripts/run-tests.sh` (watchdog-wrapped `xcodebuild test`, rule 52) — never bare `xcodebuild`. `TestPlans/Verification.xctestplan` selects 33 acceptance-pass method identifiers for Gate-5's final-WI acceptance pass, but the plan is partially stale: 3 of those identifiers target `Feature55NotePreviewVerificationTests`, whose Swift file no longer exists anywhere under `vreaderUITests/` — the plan needs a re-sync pass before its selection can be trusted as a live subset.

## Manual & supplementary test docs

- `docs/manual-test-checklist.md` — dated, checkbox-based manual device-test protocol against real books, organized by product area (Library, OPDS, Reader chrome/TOC, etc.) with inline `VERIFIED`/`SKIP` annotations; the current go-to manual regression pass.
- `archive/comprehensive-testing-guide.md` — archived, superseded manual testing guide scoped to AZW3/MOBI (Kindle) support, P0/P1/P2-prioritized, predating `docs/manual-test-checklist.md`.
- `dev-docs/integration-tests/` — per-feature integration-test runbooks against real backends, e.g. `feature-47-webdav-rclone.md` (rclone-served WebDAV round-trip).
- `dev-docs/test-debt/` — dated snapshots of pre-existing, non-regression test failures tracked as known debt, e.g. `pre-existing-failures-20260506.md`.
- `dev-docs/verification-red-checks.md` — RED-proof evidence log for `vreaderUITests/Verification/` `verify_*` methods, per rule 10's RED-proof requirement.

## History

The 694/73 file counts and the Swift Testing/XCTest split reflect the state after feature #45 (verification harness) and the broader TDD-mandatory discipline in `.claude/rules/10-tdd.md`, which made Swift Testing the default for all subsystems built since. See [[Timeline — feature delivery history]] for the era-by-era feature history these tests accompany.

**Sources.** [[session 014jggU2u3f3t6YRoPLS457u · 2026-07-10]] · [[session 014jggU2u3f3t6YRoPLS457u-audit · 2026-07-11]]

**Verified.** 2026-07-11 — checked against: vreaderTests/, vreaderTests/Services/, vreaderTests/Views/, vreaderTests/Models/, vreaderTests/ViewModels/, vreaderTests/Integration/, vreaderTests/Integration/Feature72CloudTTSIntegrationTests.swift, vreaderTests/App/, vreaderTests/Utils/, vreaderTests/Fixtures/, vreaderTests/Contracts/, vreaderTests/Contracts/IdentityConformanceTests.swift, vreaderTests/Contracts/BackupConformanceTests.swift, vreaderTests/Verification/, vreaderTests/Helpers/MockBackgroundTaskRequester.swift, vreaderTests/Helpers/PollUntil.swift, vreaderTests/Accessibility/, vreaderTests/SmokeTests.swift, vreaderTests/Services/ContentHasherTests.swift, vreaderTests/Services/EncodingDetectorTests.swift, vreaderTests/Services/Mocks/MockPersistenceActor.swift, vreaderTests/Services/TXT/MockTXTService.swift, vreaderTests/Services/TXT/TXTServiceTests.swift, vreaderTests/Services/BookImporterTests.swift, vreaderTests/ViewModels/ChapterReTranslateViewModelTests.swift, vreaderTests/Services/BackgroundExecutionTokenTests.swift, vreaderTests/Services/AI/BookTranslationCoordinatorTests.swift, vreaderUITests/, vreaderUITests/Verification/, vreaderUITests/Verification/Feature35AnnotationsExportVerificationTests.swift, vreaderUITests/Helpers/TestConstants.swift, TestPlans/All.xctestplan, TestPlans/Verification.xctestplan, scripts/run-tests.sh, docs/features.md, docs/architecture.md, docs/manual-test-checklist.md, archive/comprehensive-testing-guide.md, dev-docs/integration-tests/feature-47-webdav-rclone.md, dev-docs/test-debt/pre-existing-failures-20260506.md, dev-docs/verification-red-checks.md, .claude/rules/10-tdd.md, .claude/rules/50-codebase-conventions.md, .claude/rules/52-test-sim-isolation.md, canon/decisions/composite-dossier-schema.md, canon/modules/contracts.md, canon/modules/export.md, canon/modules/bilingual-translation.md, canon/modules/ai-providers.md, canon/decisions/six-gate-lane-dispatch.md, canon/timeline/feature-history.md, canon/logbook/2026/07/014jggU2u3f3t6YRoPLS457u.md, canon/logbook/2026/07/014jggU2u3f3t6YRoPLS457u-audit.md
