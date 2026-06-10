# Feature #98 — Background-resilient translation

- **Status**: Gate 1 v3.1 (2026-06-11) — Gate 2 PASSED (3 rounds)
- **Revision history**:
  - v1: initial draft.
  - v3.1 (Gate-2 round 3): the round-2 High is RESOLVED — round 3 verified
    the `ProviderConfigResolving` seam against the real code
    (`AIService.resolveProviderConfig` at `AIService.swift:258` matches the
    protocol exactly; actor conformance to a Sendable protocol with an
    async-throws requirement is Swift-6-clean; `VReaderApp.swift:154/163`
    has `aiService` in scope at the `configure` call; terminal phases
    `finish()` the stream at `BookTranslationCoordinator.swift:346`, so
    `restartObserving()` is the right seam). ONE Medium remained: an
    internal text contradiction on deleted-profile resume behavior (scope
    said "fails visibly per-unit"; surface area + tests said silent
    log+retain). Fixed by applying the auditor's prescribed remediation
    verbatim — the silent log+retain behavior is authoritative (the
    resolver throw precedes any job, so no failure surface exists to
    drive; recovery = the user's manual re-start from Book Details). No
    other blockers found ("I did not find another implementation blocker
    beyond the deleted-profile behavior contradiction"). Codex session ids:
    r1 `(see /tmp/f98-planaudit.txt)`, r2 `(/tmp/f98-planaudit-r2.txt)`,
    r3 `019eb2fc-bd56-79e3-bf3e-227ba252d3f5`.
  - v3 (Gate-2 round 2, NEEDS-REVISION → 1 High): the coordinator has NO
    resolver access — its live contract is `service/store/promptVersion`
    only, and `start(...)` requires a caller-supplied pre-resolved
    `ResolvedAIProviderConfig`, so `resumeInterruptedJob` could not be
    implemented from v2's surface area. RESOLVED: add a narrow
    `ProviderConfigResolving` seam (`resolveProviderConfig(profileID:
    modelOverride:) async throws -> ResolvedAIProviderConfig`); `AIService`
    conforms (the method already exists verbatim at `AIService.swift:258`);
    `configure(service:resolver:)` injects it at the existing wiring site
    (`VReaderApp.swift:163`); `resumeInterruptedJob` rebuilds `config`
    through the seam before re-entering `start(...)`. Round 2 confirmed
    all round-1 findings resolved and validated `restartObserving()`
    against the real VM lifecycle (`startObserving()` already replaces a
    prior subscription) and the container handler site
    (`ReaderContainerView.swift:512`).
  - v2 (Gate-2 round 1, NEEDS-REVISION): 3 High + 4 Medium findings.
    Highs: (1) the `BookTranslationProgress` AsyncStream is ONE-SHOT — it
    finishes on any terminal phase, so an auto-resumed job would never
    re-surface in an already-open reader's VM; (2) there is NO app-scoped
    text-provider registry — `translateBookTextProvider` is a per-container
    cache fed by a notification while a reader is open; (3) the persisted
    descriptor must carry `providerProfileID` (the coordinator pins a
    resolved config per run; resuming on "current active profile" silently
    switches providers). Mediums: cancel-between-units is not an existing
    primitive (expiry needs an explicit between-units flag, not actor-racing
    cancellation); observer ownership must be single (coordinator-owned,
    idempotent); the token's deinit-end is a Swift 6 hazard (explicit
    `end()` is the contract; deinit logs only); "no new UI states" was
    false for a terminal-then-resume flicker — RESOLVED by emitting the
    EXISTING `.failed` phase (which the designed `TranslateStatusSheet`
    already renders as "PAUSED") on expiry. v2 rescopes WI-2 to
    resume-at-reader-open (below) which dissolves Highs 1–2.
- **Tracker row**: `docs/features.md` #98 (Medium). Filed from the user report
  "the translation task cant background or it will fail" (screenshot:
  Re-translating sheet at 50%, ~9s left, app switch → failure).

## Problem

No translation path requests OS background execution. When iOS suspends the
process seconds after backgrounding, the in-flight streaming `URLSession`
request dies and the task errors (post-#333: a timeout/connection error).
This affects both flows: the per-chapter re-translate
(`ChapterReTranslateViewModel`) and the whole-book job
(`BookTranslationCoordinator.start` — in-app structured concurrency, not
OS-background-survivable). `beginBackgroundTask` exists ONLY on the reader
position-save paths.

## Scope (the row's tiers 1 + 2; tier 3 BGProcessingTask explicitly deferred)

1. **Grace window (tier 1)** — wrap in-flight translation work in
   `UIApplication.beginBackgroundTask` so iOS grants ~30s of continued
   execution after backgrounding. Alone covers the reported "~9s left" case.
2. **Whole-book checkpoint + resume-at-reader-open (tier 2, rescoped in
   v2)** — the whole-book job is already unit-checkpointed on disk
   (`cachedUnits` skips covered units on any restart). On expiry the job
   stops cleanly BETWEEN units and emits the EXISTING `.failed` phase (the
   designed status sheet renders it "PAUSED"; the library badge clears —
   both existing designed behaviors), persisting a descriptor
   `{v, bookKey, targetLanguage, style, providerProfileID}`. Resume is NOT
   background-automatic: when `ReaderContainerView` next receives the
   book's text provider (reader open / re-foreground re-publication — the
   ONLY moment a `ChapterTextProviding` exists today), it calls
   `coordinator.resumeInterruptedJob(bookKey:textProvider:)`, which
   re-resolves the PERSISTED profile id (same provider identity;
   AUTHORITATIVE deleted-profile behavior: the resolver throw happens
   BEFORE any job exists, so resume logs, retains the descriptor, and
   starts nothing — recovery is the user's normal manual re-start from
   Book Details, which surfaces provider problems through the existing
   start flow) and re-enters the normal `start` path; the container then tells its
   `BookTranslationViewModel` to `restartObserving()` so the fresh
   AsyncStream drives the existing banner (the prior stream is one-shot and
   already finished at expiry).
3. **Per-chapter re-translate**: tier 1 only. Chunk-level persistence would
   require partial cache rows, which Bug #330 forbids (a partially-degraded
   row served forever); the grace window covers the realistic single-chapter
   window, and the existing failed→picker→retry path (with the #341 atomic
   swap: the original translation is never lost) remains the fallback.

**No new UI states (rule 51: N/A).** The progress sheet/banner simply keeps
advancing during the grace window; an auto-resumed whole-book job re-surfaces
through the EXISTING `BookTranslationProgress` stream → the existing designed
banner/status sheet. No "paused" state is introduced.

## Surface area

| File | Change |
|---|---|
| `vreader/Services/BackgroundExecutionToken.swift` (NEW, ~60 lines) | Token over `begin/endBackgroundTask` behind a `BackgroundTaskRequesting` protocol seam (production = `UIApplication.shared`; tests = recorder). ALL UIApplication interaction `@MainActor`; the token is a small `Sendable` value whose **explicit `end()` (a `@MainActor` func) is the contract** — `deinit` only logs a leak in DEBUG (Gate-2: calling endBackgroundTask from deinit is a Swift 6 isolation hazard). `onExpiry` runs on the main actor; callers hop into their own isolation. `.invalid` short-circuits to a no-op token (no regression when iOS denies time). |
| `vreader/ViewModels/ChapterReTranslateViewModel.swift` | `runSubmit` acquires a token for the translate phase (steps 1–5) and ends it in all exits. On expiry: nothing special — the request dies as today, the error path already restores the picker and (post-#341) the cached original survives. Injected requester with a `UIApplication.shared` default. |
| `vreader/Services/AI/ProviderConfigResolving.swift` (NEW, ~15 lines) | Narrow seam: `protocol ProviderConfigResolving: Sendable { func resolveProviderConfig(profileID: UUID, modelOverride: String?) async throws -> ResolvedAIProviderConfig }`. `extension AIService: ProviderConfigResolving {}` — the method already exists with this exact signature (`AIService.swift:258`). Tests inject a stub resolver. |
| `vreader/Services/AI/BookTranslationCoordinator.swift` | (a) the job loop acquires a token per run, renewing per unit boundary; the expiry handler (a `@Sendable` main-actor closure) calls an actor method that SETS `expiredJobKeys.insert(bookKey)`; the unit loop CHECKS the flag between units (no cancellation racing — the in-flight unit completes or fails on its own) and stops with the EXISTING `.failed` phase + persists the descriptor `{v, bookKey, targetLanguage, style, providerProfileID}` (UserDefaults `vreader.bookTranslation.interruptedJobs`). (b) Descriptor removed on completion and user cancel. (c) NEW stored `private var resolver: (any ProviderConfigResolving)?`; `configure(service:resolver:)` gains the resolver param (wired at the existing site `VReaderApp.swift:163`, where `AIService` is in scope; idempotent like today). (d) `resumeInterruptedJob(bookKey:textProvider:)` — called by the container when a provider arrives; rebuilds `config` via `resolver.resolveProviderConfig(profileID: descriptor.providerProfileID, modelOverride: nil)` (a throw — deleted profile / missing key — logs + leaves the descriptor for a later retry, surfacing nothing new) and re-enters `start(...)` with the SAME persisted `providerProfileID` + resolved config (the `cachedUnits` skip = resume; the one-job-per-book invariant absorbs double calls). Unconfigured resolver = no-op (same guard shape as the existing `service` guard). |
| `vreader/Views/Reader/ReaderContainerView.swift` (+ the existing provider-arrival observer) | Where the container already caches `translateBookTextProvider` from `.readerBookTranslationTextProviderAvailable`, ALSO call `coordinator.resumeInterruptedJob(bookKey:textProvider:)` and, if it started a job, `bookTranslationViewModel.restartObserving()`. Documented limitation (v2): resume happens at reader-open / provider-republication, not in the background — matching how `start` is reachable today. No new observer ownership: the per-container observer already exists; the coordinator's one-job invariant absorbs duplicates from multiple containers. |
| `vreader/ViewModels/BookTranslationViewModel.swift` | `restartObserving()` — tears down the finished stream subscription and re-subscribes (the stream is one-shot by design; this is the explicit re-subscribe path the audit required). |

**Files OUT of scope**: `ChapterTranslationPrefetcher` (bilingual prefetch
already retries by design), `ChapterTranslationService` (no change — the
token wraps callers), any UI files beyond observer wiring, BGTaskScheduler
(tier 3 deferred).

## Prior art / precedent

- `beginBackgroundTask` RAII shape: the reader hosts' position-save guards
  (`EPUBReaderContainerView.swift:248`, `ReaderFormatHosts.swift:198`,
  `FoliateBilingualContainerView+Position.swift` teardown — added in #345).
- Protocol seam for UIApplication: the `BackgroundTaskRequesting` pattern
  mirrors `TranslationRequestSending` (tests inject; production conforms).
- Unit-checkpointing: `BookTranslationCoordinator.start` already skips
  `cachedUnits` — resume-by-restart is the designed-in recovery.
- Rejected: chunk-level chapter checkpoints (conflicts with #330's
  no-partial-rows rule); BGProcessingTask (heavy, OS-scheduled, no streaming
  — tier 3, separate feature if ever needed).

## Work items

- **WI-1 (behavioral, ~250-line PR)** — `BackgroundExecutionToken` +
  re-translate grace window + whole-book per-unit token renewal with
  expiry-checkpoint. RED: token begin/end/expiry lifecycle via the recorder
  seam; VM acquires/releases around submit (incl. failure + cancel exits);
  coordinator renews per unit and checkpoints cleanly on expiry (job ends
  `.cancelled`-like with completed units cached, marker persisted).
- **WI-2 (behavioral, ~250-line PR)** — `ProviderConfigResolving` seam +
  expiry-checkpoint descriptor + resume-at-reader-open. RED: descriptor
  (incl. `providerProfileID`) persisted on expiry, cleared on
  completion/user-cancel; `resumeInterruptedJob` resolves the SAME profile
  id THROUGH the injected resolver and re-starts, skipping cached units; a
  resolver throw (deleted profile) logs, retains the descriptor, starts
  nothing; unconfigured resolver no-ops; double-call no-op via the one-job
  invariant; `restartObserving()` yields a live stream after a finished
  one; expiry emits the EXISTING `.failed` phase (no new UI).

## Edge cases

- Expiry mid-chunk (re-translate): request dies → existing error path;
  original row intact (#341). No checkpoint claimed.
- Expiry mid-unit (whole-book): cancel BETWEEN units; the in-flight unit's
  partial chunks are discarded (#330 forbids caching partials) — that unit
  re-translates on resume.
- Cancel-while-backgrounded: user-initiated cancel clears the descriptor —
  no zombie resume.
- Double-resume race: foreground observer + manual start — the coordinator's
  one-job-per-book invariant (silent no-op on second start) already guards.
- Provider unreachable on resume: `start` fails per-unit as today (the
  existing failure surface); descriptor cleared only on job completion or
  user cancel, so a later foreground retries.
- Token exhaustion (iOS denies background time): `beginBackgroundTask`
  returns `.invalid` → behave exactly as today (no regression).
- UserDefaults descriptor schema versioned with a `v` field; unknown
  versions ignored (forward compat).

## Test catalogue

- `vreaderTests/Services/BackgroundExecutionTokenTests.swift` — lifecycle:
  begin on acquire, end on release, single end despite double-release,
  expiry handler fires `onExpiry` and self-ends, `.invalid` short-circuits.
- `vreaderTests/ViewModels/ChapterReTranslateViewModelTests.swift` (extend)
  — token acquired before the runner call and released on: success, runner
  failure, cancellation, sourceText failure (recorder seam asserts pairing).
- `vreaderTests/Services/AI/BookTranslationCoordinatorTests.swift` (extend)
  — per-unit renewal count == units processed; expiry → clean stop with
  marker persisted + completed units cached; descriptor lifecycle;
  `resumeInterruptedJob` (stub `ProviderConfigResolving` recorder) resolves
  the persisted profile id + restart-skips-cached; resolver-throw retains
  the descriptor and starts nothing; unconfigured-resolver no-op;
  double-resume no-op.

## Risks + mitigations

- **UIApplication in actor context**: token acquisition is `@MainActor`;
  the coordinator hops via the token factory (acquire on main, pass the
  Sendable token into the actor). Mitigation: the seam returns a token
  value; no UIApplication reference crosses actors.
- **Renew-per-unit cost**: begin/end per unit is cheap (system call); iOS
  rate-limits begin/end churn only at pathological frequencies — units run
  seconds each.
- **Resume trigger placement (v2)**: no new global observer at all — the
  container's EXISTING provider-arrival handler is the single trigger, and
  the coordinator's one-job-per-book invariant absorbs duplicate calls
  from multiple containers/scenes.

## Backward compat

No schema changes; UserDefaults key is new (absent = no jobs to resume).
Older builds ignore the key. Cache rows unchanged.
