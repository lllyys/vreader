---
branch: feat/feature-42-wi5-readium-host
threadId: codex-exec-readonly
rounds: 3
final_verdict: ship-as-is
date: 2026-05-29
---

# Gate-4 Implementation Audit — Feature #42 WI-5 (ReadiumEPUBHost)

Independent Codex audit (`codex exec --sandbox read-only`) of the first
behavioral WI of feature #42 Phase 1: render an EPUB via the Readium Swift
Toolkit `EPUBNavigatorViewController`, selected only when the default-OFF
`FeatureFlags.readiumEPUBEngine` is ON. Author = implementing Claude Code
session; auditor = separate `codex exec` process (rule-48 author/auditor
separation preserved).

Changed files audited:
- `vreader/ViewModels/ReadiumEPUBReaderViewModel.swift`
- `vreader/Views/Reader/ReadiumEPUBHost.swift`
- `vreader/Services/DebugBridge/ReadiumDebugProbe.swift`
- `vreader/Services/DebugBridge/DebugReaderRegistry.swift`
- `vreader/Views/Reader/ReaderContainerView.swift`
- `vreader/Models/ReaderEngine.swift`
- `vreaderTests/Views/Reader/ReadiumEPUBHostTests.swift`
- `vreaderTests/.../ReaderEngineTests.swift`, `ReaderContainerViewEngineDispatchTests.swift`

## Round 1 — 1 High / 2 Medium (found on the initial implementation)

| File:line | Severity | Issue | Resolution |
|---|---|---|---|
| ReadiumEPUBHost.swift:~75 | **High** | No teardown on disappear (bug #252 class): navigator/publication leak, DebugBridge registry slot never cleared. The legacy EPUB/Foliate slots are cleared by `DebugReaderRegistry.unregister(_:)`, but the Readium host registers no `DebugReaderProbe`, so that path never fires for it. | FIXED — host `.onDisappear` → `viewModel.close()` (releases the `Publication`); `dismantleUIViewController` → `coordinator.detach()` clears the registry slot (DEBUG) via new `clearActiveReadiumNavigator(for:token:)` and drops the navigator delegate/ref. |
| ReadiumEPUBHost.swift:~103 | **Medium** | Navigator-init throw returned a blank `UIViewController()` while VM state stayed renderable → blank page, no error view. | FIXED — init throw routes into host state via `markNavigatorInitFailed(_:)` (deferred to the next main-actor turn), so the host's `.failed` error view renders. |
| ReaderContainerView.swift:~735 | **Medium** | DEBUG eval format-gate keyed on `book.format` (parallel String `@Model` column) instead of the canonical `fingerprint.format` (bug #246/#1072 hardened the dispatcher to read `fingerprint.format`; the eval gate must agree). | FIXED — added `resolvedFingerprintFormat` (parses `book.fingerprintKey`, falls back to `book.format`); the eval-gate routes on it for `.epub`/`.azw3`. |

## Round 2 — 1 High / 2 Medium (NEW, found on the round-1 fixes)

| File:line | Severity | Issue | Resolution |
|---|---|---|---|
| ReadiumEPUBReaderViewModel.swift:54 | **High** | `close()` did not stop an in-flight `open()`; a dismiss-during-open could resume after `close()` and assign `.ready(publication)`, re-leaking a fresh `Publication` into a closed VM. | FIXED — added `@MainActor private var isClosed`; `close()` sets it before clearing state, and `open()` re-checks `guard !isClosed` at entry and after every `await` before mutating `state`. |
| ReadiumDebugProbe.swift:~107 | **Medium** | `clearActiveReadiumNavigator` cleared settle state without preserving the incoming `expectedReaderToken` — in a same-book quick reopen, outgoing reader A's detach wiped incoming reader B's settle state (unlike `unregister(_:)`). | FIXED — added internal `expectedReaderTokenInternal` accessor; the clear now passes `preservingToken: expected == token ? nil : expected`, matching `unregister(_:)`'s semantics. |
| ReadiumEPUBHost.swift:~115 | **Medium** | `onNavigatorInitFailure` stored as a non-`@Sendable` function value, captured into `Task { @MainActor }` under `SWIFT_STRICT_CONCURRENCY = complete` — latent sendability hazard. | FIXED — type is now `(@MainActor @Sendable (String) -> Void)?`; capturing `[weak viewModel]` (main-actor-isolated class) into a main-actor-isolated `@Sendable` closure is sound. Build passes under `complete`. |

## Round 3 — clean

**No Critical/High/Medium findings.** All three round-2 fixes confirmed
resolved:
- HIGH close/open race — `open()` checks `isClosed` at entry + after each
  suspension before mutating state; `close()` sets `isClosed` first.
- MEDIUM settle preservation — `preservingToken: expected == token ? nil :
  expected` matches `unregister(_:)` for last-reader / incoming-reader /
  nil-expected cases.
- MEDIUM strict concurrency — `(@MainActor @Sendable (String) -> Void)?` with
  `[weak viewModel]` is sound (captured VM is main-actor isolated; closure
  executes on `MainActor`).

## Verdict

**ship-as-is.** Three audit rounds, zero open Critical/High/Medium. Regression
tests added for every behavioral fix (`open_afterClose_isNoOp`,
`clearActiveReadiumNavigator_preservesIncomingTokenSettleState`,
`clearActiveReadiumNavigator_clearsOwnSettleWhenLastReader`,
`markNavigatorInitFailed_setsFailedWithMessage`, `close_resetsToLoading`,
`clearActiveReadiumNavigator_clearsMatchingSlot`,
`clearActiveReadiumNavigator_ignoresNonMatchingKey`). Focused test gate green
(42 tests, 3 suites).
