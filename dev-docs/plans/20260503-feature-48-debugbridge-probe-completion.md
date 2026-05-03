# Feature #48 — DebugBridge Probe Completion (Implementation Plan)

> **2026-05-03 — UMBRELLA SPLIT.** Per `.claude/rules/47-feature-workflow.md` audit-cap escalation, feature #48 was split into two smaller features:
> - **#49** — Phase-A: registry / `open` / snapshot wiring. Picks up the WIs in this plan that don't touch per-format host code (originally numbered WIs 0, 1, 7, 8 in the plan's "Sequencing" section). Round-3 surface fixes (compile-correctness on `open()` referenced types, continuation type, registry weak/strong consistency) must land in #49's WI-0a.
> - **#50** — Phase-B: per-format settle hooks + live `eval` + host injection API. The part that took 3 audit rounds without converging. Plan TODO; will be written fresh after #49 lands.
>
> #48 itself is now `DUPLICATE` in the tracker. This plan is retained as the audit log + the source of truth for #49's scope (and will be referenced when #50's plan is written).

**Source**: `docs/features.md` row #49 (PLANNED, High) for resolver/open/snapshot scope. Row #48 = DUPLICATE, row #50 = TODO for per-format work.
**Phase**: Phase-1 prerequisite for feature #45 (Verification Harness Sweep)
**GH issue**: not yet filed (will be filed at PLANNED status, mirror under "GH: #N" in Notes)
**Status**: v4 — Round-3 surface fixes applied; plan covers #49 only.

## Audit cap reached — Round 3 verdict (2026-05-03)

Codex's Round-3 audit on v3 returned **REVISE-and-split** with these unresolved findings:

| # | Finding | Severity |
|---|---------|----------|
| 1 | Host probe injection API still wrong: `wireDebugProbe: ((DebugReaderProbeAdapter) -> Void)?` callback shape gives the host nothing to invoke (the adapter is owned by `ReaderContainerView`); also `[weak self]` doesn't apply to a SwiftUI `View` struct. Need `debugProbe: DebugReaderProbeAdapter?` parameter (passed in by `ReaderContainerView`) or a closure that produces the adapter on demand. | High |
| 2 | `open(bookId:position:)` sketch references `settingsStore.readingMode` — `RealDebugBridgeContext` has `userDefaults`, not `settingsStore`. `FormatCapabilities.capabilities(for:)` takes `BookFormat`, not `String`. Sketch won't compile against current code. | High |
| 3 | `evalUnsupported(bridge:)` JSON file name regressed: current `RealDebugBridgeContext.eval` writes `Caches/DebugBridge/eval-<bridge>.json`; v3 says `Caches/eval-result-<uuid>.json` and references a `dest=` URL parameter that `DebugCommand.eval` doesn't have. Either update the grammar OR keep the existing contract. | Medium |
| 4 | `positionProvider: { [currentLocator] in ... }` captures a stale value from registration time. Use a live read (closure that reads from a class-backed reference each call), not a value-type capture list. | Medium |
| 5 | `DebugReaderRegistry` weak/strong consistency: current code stores `activeReader` weakly. v3 sketch implies strong storage. Keep the weak behavior unless deliberately changing lifecycle. | Medium |
| 6 | Continuation type: `CheckedContinuation<DebugReaderProbe, Error>` should likely be `CheckedThrowingContinuation<DebugReaderProbe, Error>` per Swift convention. | Low |

**Per the workflow rule's max-3-rounds cap, this triggers escalation.** Codex has consistently recommended (Rounds 1, 2, and 3) splitting #48 into two smaller features to limit blast radius:

- **#48a** — resolver/registry/open/snapshot wiring (no per-format host changes). Smaller blast radius, can ship behind feature flag.
- **#48b** — per-format settle/eval/host wiring (the bigger refactor that touches every reader host).

The v3 plan's "Sequencing" section already includes this split as a fallback. Codex now recommends taking it.

**Decision required**:

(A) **Accept the split** — file #48a + #48b in `docs/features.md`, retain v3 plan as #48a's plan with per-format work (WIs 2-6) carved out into a future #48b plan. Recommended.

(B) **Override the cap** — apply the Round-3 surface fixes manually as a v4 (no further audit), accept residual risk, ship #48 monolithic.

(C) **Defer the entire feature** — set #48 to `DEFERRED`, unblock #45 some other way (e.g. accept that simulator-automatable verifications are limited until DebugBridge is ready).

Until the user picks, the plan stays at v3 and feature #48 stays `TODO`.

## Revision history

- **DRAFT (v1)** — initial plan, sent to Codex for audit (Gate 2)
- **v2** — incorporated Codex audit findings on 2026-05-03 (Round 1). See "Audit fixes applied" below. Major shape changes: AZW3 host retargeted to `FoliateSpikeView`, eval surface redesigned around per-host evaluator registration, `awaitNextRegister` replaced by keyed `awaitReader(fingerprintKey:)`, sentence-index probe and fixture-leak fix carved out, xcodegen DEBUG-only resource pattern resolved.
- **v4 — Round-3 surface fixes applied on 2026-05-03 (post split-accept).** Six compile-correctness edits, no scope change:
  (1) `CheckedContinuation` → `CheckedThrowingContinuation` everywhere it appears (Swift convention for throwing continuations).
  (2) `DebugReaderRegistry.activeReader` documented as **weak** to match the live code; `awaitReader` sketch reads through a weak `current` accessor instead of a strong stored property.
  (3) `open(bookId:position:)` sketch rewritten against actual types: `RealDebugBridgeContext.userDefaults` (not `settingsStore`); instantiate `ReaderSettingsStore(defaults: userDefaults)` to read `readingMode`; `FormatCapabilities.capabilities(for:)` receives the existing `BookRecord.fingerprint.format` (`BookFormat`) instead of a stringly-typed `format`.
  (4) `positionProvider` now closes over a class-backed reference (a small `@MainActor` holder updated by the host) so each call performs a live read; the v3 `[currentLocator]` capture-list pattern is documented as wrong (capture-list with a value type snapshots at registration time, not a live binding).
  (5) `evalUnsupported` JSON file path normalized to the existing `Caches/DebugBridge/eval-<bridge>.json` convention used by the live code (no `dest=` URL parameter — `DebugCommand.eval` doesn't have one); the v2 → v3 audit-fix table entry that introduced `eval-result-<uuid>.json` is corrected accordingly.
  (6) Status line updated to v4; this revision-history entry added.
- **v3 — incorporated Codex audit findings on 2026-05-03 (Round 2).** Five surgical fixes:
  1. `awaitReader` waiter ownership — each waiter gets a UUID token; timeout removes by token identity, not first-match (fixes race when two callers wait on the same key with different timeouts).
  2. Concrete DEBUG-only probe injection API for hosts — every reader host gains a `wireDebugProbe: ((DebugReaderProbeAdapter) -> Void)?` parameter with explicit per-format callback contract (selection coordinates, render-phase changes, seek-completion).
  3. `open(bookId:position:)` validates BEFORE posting `.debugBridgeOpenBook` — order is now: book lookup → position validation → unified-mode check → notification post.
  4. Foliate post-seek disambiguation — accepting the narrowed limitation (Option B): `open?position=` for AZW3 only supported from a clean reader state. Documented in Open Questions and Goal section. Verification flows always start from `vreader-debug://reset`.
  5. Explicit unknown-bridge error + build-script behavior — unknown `bridge` writes `evalUnsupported(bridge:)` to `Caches/DebugBridge/eval-<bridge>.json` (existing convention used by the live code; no `dest=` URL parameter exists for eval) with the known-bridges list; build-phase script uses `rsync -a` (idempotent on empty dir) and `inputFiles` references the parent `DebugFixtures/` directory. **Corrected in v4** — v3 erroneously specified `Caches/eval-result-<uuid>.json` and a non-existent `dest=` URL parameter.

## Audit fixes applied — Round 2 (Codex 2026-05-03)

| Finding | Severity | Resolution |
|---------|----------|-----------|
| `awaitReader` waiter ownership: storing waiters as `[String: [Continuation]]` and removing the FIRST waiter on timeout means two callers waiting on the same key with different timeouts can resume the wrong continuation. | Critical | **Each waiter gets a UUID token.** Storage becomes `[String: [(token: UUID, continuation: CheckedThrowingContinuation<DebugReaderProbe, Error>)]]` (throwing continuation per Swift convention — corrected in v4 from `CheckedContinuation`). Timeout removes the entry whose token matches the timeout task's token, never the first match. See revised sketch in "`awaitReader(fingerprintKey:timeout:)` replaces `awaitNextRegister`" below. |
| Concrete DEBUG-only probe injection API for hosts is unspecified — the plan claims hosts populate the probe but doesn't add the API parameter. | High | **Every reader host gains a DEBUG-only `wireDebugProbe: ((DebugReaderProbeAdapter) -> Void)? = nil` parameter** (`#if DEBUG` gated at the parameter site). `ReaderContainerView` constructs the adapter, passes `wireDebugProbe` to the host, and the host invokes it after the underlying view (WKWebView / UITextView / PDFView) is ready. Per-host callback contract spelled out in "Per-host probe injection contract" below. |
| `open(bookId:position:)` posts `.debugBridgeOpenBook` BEFORE validating position — malformed position opens the reader and then throws, two side effects from one bad call. | High | **Reorder: book lookup → position validation → unified-mode check → notification post.** Validation runs before any side effect; the bridge writes `openPositionUnresolvable` / `openPositionUnsupportedInUnifiedMode` to `lastError.json` and returns without opening anything. Revised `open(bookId:position:)` sketch shows the new order. |
| Foliate post-seek disambiguation: spontaneous relocate during arming window may resolve the wrong continuation (called out in v2 risks but not resolved). | Medium | **Accepted limitation (Option B).** `open?position=` for AZW3 only supports clean-reader-state seeks (no prior interactive seek within 500ms of the arming window). Verification flows always start from `vreader-debug://reset`, so they never hit this case. Documented in Goal section + Open Questions. Sequence-number disambiguation (Option A) deferred until empirical data shows it's needed. |
| `eval?bridge=<unknown>` behavior was an Open Question; build-phase script behavior on empty fixture dir was unspecified. | Medium | **Unknown bridge writes `evalUnsupported(bridge: <name>)`** to `Caches/DebugBridge/eval-<bridge>.json` (the existing live-code convention used by `RealDebugBridgeContext.eval`; `DebugCommand.eval` has no `dest=` URL parameter — corrected in v4 from the original v3 claim of `Caches/eval-result-<uuid>.json`). Payload includes `knownBridges: [<list>]` for diagnostics. **Build-phase script uses `rsync -a --include='*/' --include='*' --exclude='*' DebugFixtures/ dest/`** (idempotent, doesn't fail on empty); `inputFiles` references the parent `DebugFixtures/` directory so Xcode invalidates correctly when fixtures change. Updated `project.yml` stanza in WI-9. |

## Audit fixes applied — Round 1 (Codex 2026-05-03)

| Finding | Severity | Resolution |
|---------|----------|-----------|
| Plan targets `FoliateReaderContainerView` for AZW3, but `ReaderContainerView.nativeReaderView` routes `.azw3` to `FoliateSpikeView` (live AZW3 renderer). `FoliateReaderContainerView` exists but is not on the live dispatch path. | Critical | **Retarget WIs 4 and 6 to `FoliateSpikeView`.** Surface area updated: `FoliateSpikeView.swift` (203 LOC) replaces `FoliateViewBridge.swift` / `FoliateReaderContainerView.swift` as the per-format settle + eval host. The wiring shape (`onWebViewReady`, `onRenderCommitted`) is the same; only the file name and the existing message-handler routing change. `FoliateViewBridge.swift` and `FoliateReaderContainerView.swift` are explicitly **out of scope** for #48 (they're not on the dispatch path). If/when the dispatcher converges to the container view, follow-up plan re-targets the same wiring. |
| `TTSService.State` is `Sendable, Equatable` only — no `RawRepresentable`, so `state.rawValue` won't compile. | Critical | **Drop `state.rawValue`.** Snapshot ships `ttsOffsetUTF16: Int?` only (sourced from `TTSService.currentOffsetUTF16`). A small extension `TTSService.State.publicName: String` (`"idle" / "speaking" / "paused"`) is added inside `vreader/Services/TTS/TTSService.swift` (`#if DEBUG`-gated extension at end of file, ~10 LOC) and surfaced via `probe.ttsStateProvider`. The probe API name is `currentTTSState() -> String?`; the rendered string comes from `publicName`, not `rawValue`. |
| `LocatorValidationError` is `Sendable` only, not `Equatable`. The proposed `DebugPositionResolverError: Equatable` with `.validationFailed(LocatorValidationError)` won't compile. | Critical | **Reshape `DebugPositionResolverError`.** Replace the associated value with a flat string: `case validationFailed(reason: String)`. The resolver maps `LocatorValidationError` cases to stable strings (`"negativePageIndex"`, `"negativeUTF16Offset"`, `"invertedUTF16Range"`, `"nonFiniteProgression"`) before throwing. Keeps the resolver `Equatable` for tests; doesn't require a separate change to `Locator.swift`. (If a future feature genuinely needs `Equatable` on `LocatorValidationError`, that's a one-line standalone PR — not part of #48.) |
| `[weak Locator?]` is impossible — `Locator` is a value type. The example `positionProvider: { [weak currentLocator] in ... }` doesn't compile. | Critical | **Drop the weak capture.** `currentLocator` is `@State Locator?` (a value); the closure captures by value via `[currentLocator]` or by direct capture. Updated example uses `{ currentLocator.flatMap(DebugPositionFormatter.format(_:)) }` with the closure capturing the SwiftUI `@State` access pattern (which the compiler resolves through the property wrapper). No weak references in the rewritten DEBUG `.onAppear` example. **(Refined again in v4 Fix #4: a value-type capture list still snapshots at registration time, so the probe would never observe locator updates. v4 routes through a `@MainActor` class-backed `DebugLocatorHolder` that the host updates on every locator change; the closure captures the holder by reference and performs a live read each call.)** |
| "Optional protocol methods" is not Swift terminology. | Low | **Renamed throughout to "default-implemented" (i.e. the protocol declares the method; an extension provides a default body).** All references in the plan now say "default-implemented so existing adapters compile." |
| xcodegen `excludes:` is **not** per-build-config. Open Question 1's "exclude in base, re-add in DEBUG" pattern is not supported. | Critical | **Pick the simplest viable approach: build-phase script that copies fixtures only when `${CONFIGURATION}` is `Debug`.** `project.yml` keeps the fixtures source-listed for the test bundle (so unit tests find them in `Bundle(for: ...)`), but they are removed from the *app* target's `sources:` and instead copied at build time by a `Run Script` build phase that no-ops in Release. **Why this beats the alternatives** (Debug-only target: requires duplicating settings, risks drift; separate XcodeGen spec: invalidates `xcodegen generate` workflow and breaks the docs-sync rule). Build-phase script is one stanza in `project.yml`, runs only when `[ "${CONFIGURATION}" = "Debug" ]`, and the existing `verify-release-no-debugbridge.sh` validates the result. WI-9 details the exact `project.yml` stanza. |
| Fixture leak (`war-and-peace.txt` ships in Release) is a standalone bug, not a #48 work item. | Critical | **Carved out.** WI-9 of v2 only adds new fixtures and the build-phase script that gates the *new* fixtures directory. The pre-existing `war-and-peace.txt` Release leak is removed from #48's scope; the calling agent will file it as a separate `docs/bugs.md` row (the build-phase script will subsume the fix once the bug PR retargets `war-and-peace.txt` into the same `DebugFixtures/` directory, but that's a coordination point, not a #48 deliverable). |
| `awaitNextRegister(timeout:)` 100ms heuristic is unsound (race window is arbitrary, depends on push timing). | Critical | **Replaced with `awaitReader(fingerprintKey:timeout:)`.** Algorithm: (1) check `current` registry (which dereferences a weak `activeReader` — corrected in v4 to match the live code) — if a probe matching the key is already registered, return it immediately. (2) Otherwise install a continuation in a `[String: [CheckedThrowingContinuation<DebugReaderProbe, Error>]]` keyed by `fingerprintKey` (throwing continuation per Swift convention — corrected in v4). (3) `register(_:)` resumes ALL waiters whose key matches the newly-registered probe's key. (4) On timeout, the continuation is removed and resumed with `awaitReaderTimeout`. Multiple stale-reader-disappear/reappear cycles handled correctly because the matcher uses key equality, not "next register event." Tests cover: (a) reader already present, (b) reader registers after wait begins, (c) wrong-key reader registers (waiter still waiting), (d) timeout, (e) multiple waiters for same key (all resume). |
| Live `eval` ownership: `DebugReaderProbeAdapter.jsEvaluator` alone is insufficient — each format's bridge must surface its evaluator through the active reader registration. | High | **Spelled out per format.** EPUB: `EPUBWebViewBridge` adds `onWebViewReady: ((WKWebView) -> Void)?` SwiftUI prop, invoked at end of `makeUIView`. `EPUBReaderHost` (the format host already used by the dispatcher) captures the WKWebView and assigns the probe's `jsEvaluator` closure. Foliate (AZW3): `FoliateSpikeView` adds the same `onWebViewReady` callback (its existing `Coordinator` already holds `weak var webView: WKWebView?`); the host wraps it into the probe's evaluator. PDF/TXT/MD: no eval support — the probe's default `currentTTSState() == nil` pattern applies; eval throws `evalUnsupported(format:)` per the existing v1 behavior. **No new SwiftUI host file is created**: `FoliateSpikeView` IS the host, and `EPUBReaderHost` is in `ReaderFormatHosts.swift`. |
| `eval?bridge=` semantics: current code uses `bridge` only as the output filename; doesn't validate format match. Goal section example seeds `alice-epub` then evals `bridge=foliate` — semantically wrong. | High | **Add bridge-vs-format validation.** Allowed `bridge` values map to formats: `"epub" → "epub"`, `"foliate" → "azw3"` (and future `"mobi"`), `"unified" → reserved for future use`. Validation runs in `RealDebugBridgeContext.eval` after the active probe is fetched. If `bridge=foliate` and the active probe's `format == "epub"`, the bridge writes an error file with `error: "bridge mismatch: requested=foliate active=epub"` and returns. Goal section example fixed: now seeds `alice-epub` then evals `bridge=epub`, and a separate Foliate example seeds `sample-azw3` then evals `bridge=foliate`. |
| `open?position=` for unified renderer (`UnifiedTextRenderer`) is unscoped. Unified path uses different navigation primitives. | Medium | **Native-mode-only in #48.** Explicitly documented in the Goal section and the resolver doc-comment: `open?position=` is supported when `ReaderContainerView` is in native mode (the dispatcher routes to a format host). When `settingsStore.readingMode == .unified` AND the format has `.unifiedReflow` capability (TXT/MD currently; potentially EPUB), `open?position=` returns `openPositionUnsupportedInUnifiedMode(format:)`. A separate follow-up feature can add unified-mode seek if #45 needs it. |
| Foliate "next relocate counts" arming is fragile (Foliate posts both spontaneous and post-seek `relocate` events). | High | **Spelled out the protocol.** The host's `seekStrategy` for Foliate: (1) record `armed = true`, `armedTargetCFI = <target>`, `armedDeadline = now + timeout` immediately before invoking the JS seek. (2) On any subsequent `relocate` message, if `armed`, treat it as the post-seek relocate, clear armed, and resolve the settle continuation. If Foliate reports a CFI in the relocate payload that differs from `armedTargetCFI`, log a warning but still treat as settled (Foliate sometimes normalizes the CFI). (3) On timeout (deadline passed), clear armed and resume with `seekTimeout`. (4) When `armed == false`, spontaneous `relocate` events are ignored by the seek path (the existing position-update path still consumes them). State lives on the `Coordinator`, which already owns the WKWebView reference. |
| `ttsCurrentSentenceIndex` requires sentence boundary derivation that doesn't exist; deferring is correct. | Medium | **Dropped from #48.** Snapshot ships `ttsOffsetUTF16: Int?` only. Sentence-index probe needs explicit tokenizer semantics (Chinese/Japanese vs English, abbreviation handling, blank-line treatment) that warrants its own feature plan. Recorded in Open Questions for follow-up gated by #45 actually needing it. |
| Plan claims "5 DebugBridge test files" in one place and "6" elsewhere — actual count is 6: `DebugBridgeTests`, `DebugReaderRegistryTests`, `DebugCommandTests`, `DebugSnapshotTests`, `RealDebugBridgeContextTests`, `DebugFixtureCatalogTests`. | Low | **Normalized to 6 throughout.** Surface area table accurately lists existing files. |
| `FoliateViewBridge.swift` lives at `vreader/Views/Reader/FoliateViewBridge.swift`, not `vreader/Services/Foliate/`. | Low | **Path corrected.** All references in v2 use the actual path. (And per the Critical fix above, `FoliateViewBridge.swift` is no longer touched by #48 — the live AZW3 renderer is `FoliateSpikeView.swift` at the same directory.) |
| `renderPhase` is hardcoded `"idle"` in production but tests use `"settled"` interchangeably — naming is inconsistent. | Low | **Normalized to `"idle"`.** `"settled"` is reframed as a semantic synonym used in test names only; the wire value is always `"idle"` (post-render-committed) or `"loading"` / `"rendering"` (transient). Snapshot tests using `"settled"` are updated to `"idle"` in WI-1. |
| `cfi` / `position` parser claim was partially wrong. Verified: parser already requires `position` (rejects `cfi` as `missingParam("position")` because there's no `cfi` case in the switch). Top-of-file DocC at `DebugCommand.swift` line 15 still says `cfi`. | Low | **Plan claim corrected.** Parser already canonical; only the DocC at the file header is stale. WI-0 fixes the DocC + adds a regression test asserting `?cfi=...` URL is rejected (the test exists in spirit; v2 makes it explicit). |

## Problem

Feature #44 (DebugBridge URL scheme) shipped a working but thin probe surface. When feature #45 (verification harness sweep) tried to sit on top of it, a Codex audit revealed five concrete gaps that prevent end-to-end verification of any reader behavior:

1. **`settle` is a 100ms placeholder.** `DebugReaderProbeAdapter.awaitSettle` sleeps a fixed interval. That interval is wrong for every real format: TXT TextKit layout completes on a different schedule than EPUB's first paint, which is different again from Foliate's `relocate` event, which is different from PDF's first-page-rendered, which is different from TTS state transitions. Verification flows that take a snapshot after `settle` see partial state on slower formats and false-stable state on faster ones. The 100ms is therefore both a flake source and a correctness hole.
2. **`eval` has no live evaluator.** `DebugReaderProbeAdapter.jsEvaluator` is `nil` everywhere. EPUB and Foliate-rendered AZW3 both render in WKWebView; they could supply an evaluator but currently don't, so every `vreader-debug://eval?bridge=foliate&js=...` writes `{"error":"eval unsupported for format: ..."}`. The bridge plumbing is complete; only the registration is missing. (Live AZW3 renderer is `FoliateSpikeView`, not `FoliateReaderContainerView` — see Audit Fix #1.)
3. **`open?position=` throws `notImplemented`.** Repros that depend on opening at a specific CFI / page / UTF-16 offset can't be expressed; the probe always opens at the start.
4. **Snapshot schema is too narrow.** TTS state, render phase, current selection, and per-book vs global settings provenance are missing. Verification cases that assert "TTS started speaking" or "settings switched to per-book mode" cannot be encoded. (Sentence-index intentionally deferred — see Audit Fix on `ttsCurrentSentenceIndex`.)
5. **`DebugFixtureCatalog` has one fixture.** `war-and-peace.txt` is the only entry. EPUB / Foliate / PDF / CJK paths can't be exercised by a `seed` command.

A sixth, smaller item also surfaces: `DebugCommand.swift` top-of-file DocC still says `cfi` even though the parser already requires `position`. Reconcile the grammar.

**Carved out of #48 by audit:** the pre-existing fixture leak (`war-and-peace.txt` shipping in Release builds) is a standalone bug. The calling agent will file it separately; v2 of this plan does NOT include a fix for it. WI-9 only covers gating the *new* fixtures directory.

#48 closes the six gaps above so #45 can drive real verification. **Out of scope here**: writing the actual verification flows — that's #45's job. This feature ships only the harness primitives.

## Goal

Promote the DebugBridge from "skeleton that proves the URL plumbing works" to "probe surface rich enough to assert reader behavior end-to-end without computer-use." Concretely:

- `settle` blocks until the active reader has reached a per-format-defined "render committed" state, or times out with a clear sentinel.
- `eval` runs JS in the live EPUB / Foliate-AZW3 WKWebView and writes the JS expression's value (as JSON) to the snapshot. Bridge name is validated against the active reader's format.
- `open?position=` (native-mode only — see Audit Fix on unified renderer) resolves a position string into a `Locator` and seeks the reader to it for TXT / EPUB / AZW3 / PDF. **AZW3 limitation (v3):** `open?position=` for AZW3 only supports clean-reader-state seeks — the verification flows always start from `vreader-debug://reset`, so this restriction is invisible in practice (see "Foliate post-seek disambiguation" below and Open Question #5).
- `snapshot` exposes TTS state + offset, render phase, current selection range, and settings provenance.
- `DebugFixtureCatalog` covers every supported reader format (and a CJK case) via a build-phase script that excludes them from Release.
- The URL grammar is consistent: parser, code, and DocC all agree on `position`.

Success bar: a DEBUG build, with a freshly-installed simulator, can execute the following sequences with deterministic output:

```
# EPUB sequence (eval bridge name matches format)
xcrun simctl openurl <udid> "vreader-debug://reset"
xcrun simctl openurl <udid> "vreader-debug://seed?fixture=alice-epub"
xcrun simctl openurl <udid> "vreader-debug://open?bookId=<key>&position=epubcfi(/6/4!/4/2)"
xcrun simctl openurl <udid> "vreader-debug://settle?token=t1"
# ready-t1.json shows phase: "idle", non-nil position
xcrun simctl openurl <udid> "vreader-debug://eval?bridge=epub&js=<base64 of 'document.querySelectorAll(\"p\").length'>"
# eval-epub.json shows {"result": <int>}
xcrun simctl openurl <udid> "vreader-debug://snapshot?dest=after.json"
# after.json includes ttsState, ttsOffsetUTF16, renderPhase: "idle",
# selection: null, settingsProvenance: "global"

# Foliate (AZW3) sequence — separate sample to demonstrate bridge=foliate
xcrun simctl openurl <udid> "vreader-debug://reset"
xcrun simctl openurl <udid> "vreader-debug://seed?fixture=sample-azw3"
xcrun simctl openurl <udid> "vreader-debug://open?bookId=<key>&position=epubcfi(/6/4!/4)"
xcrun simctl openurl <udid> "vreader-debug://settle?token=t2"
xcrun simctl openurl <udid> "vreader-debug://eval?bridge=foliate&js=<base64 of 'document.title'>"
# eval-foliate.json shows {"result": "<title>"}

# Mismatched bridge example (negative test case)
xcrun simctl openurl <udid> "vreader-debug://eval?bridge=foliate&js=<...>"
# (with active EPUB reader) → eval-foliate.json shows
# {"error": "bridge mismatch: requested=foliate active=epub"}
```

…and a Release build still passes `scripts/verify-release-no-debugbridge.sh`.

## Prior art / project precedent / rejected alternatives

**Prior art (vreader internals).**
- `DebugBridge` (#44) — the dispatch layer this feature extends. Conventions to preserve: `DebugBridgeContext` protocol with `@MainActor` methods, all errors as enum cases mapped to stable strings via `DebugBridge.stableErrorMessage(for:)`, every command writes a file rather than throws when the consumer needs to read the failure mode.
- `EPUBHighlightBridge.selectionTrackingJS` and `EPUBWebViewBridge.progressTrackingJS` — already injected JS that posts back to native via `WKScriptMessageHandler`. Pattern: idempotent JS that posts a structured payload over a named channel, native side parses the dictionary shape, drops malformed payloads silently. Apply the same shape for the new "render-committed" event used by `settle`.
- `FoliateSpikeView.Coordinator.userContentController(_:didReceive:)` — already routes `bridge-ready`, `book-ready`, `relocate`, `selection`, `error` channels (and many more — see file). The render-committed signal for AZW3 is `book-ready` for first-paint and `relocate` (post-arm) for in-document jumps. Reuse, don't duplicate.
- `TTSService.state` — already an `@Observable` enum (`.idle / .speaking / .paused`) but **not** `RawRepresentable`. Snapshot uses a small `publicName` extension (Audit Fix on `state.rawValue`) rather than `rawValue`.

**Prior art (other probe systems).**
- React Native's "TestState" bridge ships per-component "ready" promises that test runners await before asserting. The component decides what "ready" means (image loaded, scroll settled, etc.). Same shape: each format owns its own `awaitSettle`, the bridge just races a timeout.
- WebDriverIO's `waitForElement(state: 'displayed')` waits on a per-element predicate, not a fixed timeout. The harness should never sleep.

**Rejected alternatives.**
- *Add a `vreader-debug://wait?ms=<n>` command.* Pushes the flakiness from the bridge into the consumer; same problem in a new place. Rejected.
- *Have `settle` poll a generic "is reader rendering" boolean every 50ms.* Polling has the same correctness hole as the 100ms sleep — the boolean only tells you "render in progress", not "first paint stable". Per-format hooks are the only correct shape.
- *Make `eval` synchronous and return JS result via the URL response.* `simctl openurl` doesn't surface response payloads; the `Caches/DebugBridge/eval-<bridge>.json` file is the only available channel. Already what #44 implemented; keep it.
- *Wrap `BookImporter` in a separate `DebugBookImporter` for fixture loads.* Means parallel implementations that drift. Reuse the production importer with `ImportSource.localCopy` (current behavior); just add the fixtures themselves.
- *Add fixtures via a separate test-only Bundle.* iOS apps can't load arbitrary external bundles at runtime without code-signing dance. Stay with `Bundle.main` + a build-phase script that excludes them in Release (see Audit Fix on xcodegen).
- *Retarget the dispatcher (`ReaderContainerView`) to `FoliateReaderContainerView` so we can wire the same hooks across both EPUB-style containers.* Would be cleaner architecturally but is a separate refactor — and the spike has been the live AZW3 renderer for months. #48 plumbs through the live path; convergence is a future feature.

**Wider-scope alternative considered: split `eval` work into its own feature.** The eval work touches two distinct WKWebView hosts (EPUB and AZW3 via FoliateSpikeView) with different surface and could grow. After reading `EPUBWebViewBridge.swift` (252 LOC, has a Coordinator with a webView reference) and `FoliateSpikeView.swift` (203 LOC, Coordinator with `weak var webView: WKWebView?`), the wiring on each side is ~30 lines per host: expose the active `WKWebView` (or an evaluator closure) to the host's parent, and have the parent populate `DebugReaderProbeAdapter.jsEvaluator` on registration. The serialization-to-JSON contract is the only nuance, and it lives in the probe (one place). **Decision: keep eval in #48.** The work fits inside a single WI per host. Splitting would create artificial coordination overhead.

## Surface area

Files in scope (current LOC in parens; column "Touch" = add / modify / new file):

| File | LOC | Touch | What changes |
|------|-----|-------|--------------|
| `vreader/Services/DebugBridge/DebugBridge.swift` | 141 | modify | Add `DebugBridgeContextError.openPositionUnresolvable(format:position:)`, `.openPositionUnsupportedInUnifiedMode(format:)`, `.bridgeMismatch(requested:active:)`, `.evalUnsupported(bridge:)` (unknown bridge name), `.awaitReaderTimeout(fingerprintKey:)`. Update `stableErrorMessage(for:)` to map them. |
| `vreader/Services/DebugBridge/DebugCommand.swift` | 195 | modify | Top-of-file DocC: rename `cfi=<position>` to `position=<string>`. Add a one-line note that `position` strings are format-specific (see WI-7 contract). No parser change. |
| `vreader/Services/DebugBridge/DebugReaderRegistry.swift` | 82 | modify | `DebugReaderProbe` gains members for the new probes (TTS state, selection, render phase, settings provenance, seek). Default-implemented so existing adapters compile. Add `awaitReader(fingerprintKey:timeout:)` to the registry — keyed continuation map keyed by `fingerprintKey`. |
| `vreader/Services/DebugBridge/DebugReaderProbeAdapter.swift` | 75 | modify | Add `seekStrategy`, `ttsStateProvider`, `ttsOffsetProvider`, `selectionProvider`, `renderPhaseProvider`, `settingsProvenanceProvider` closures. `settleStrategy` injection point already exists — host wires it on register. |
| `vreader/Services/DebugBridge/DebugSnapshot.swift` | 96 | modify | Add fields: `ttsState: String?`, `ttsOffsetUTF16: Int?`, `selection: SelectionInfo?` (already exists; populate it), `settingsProvenance: String?` (`"global"` / `"per-book"`). Bump `currentSchemaVersion` to **2**. Update `partial[]` rules. **`renderPhase` wire value normalized to `"idle"` / `"loading"` / `"rendering"`** — `"settled"` is removed from production code (only test names retain it as a synonym). |
| `vreader/Services/DebugBridge/RealDebugBridgeContext.swift` | 392 (>300 ⚠) | **split + modify** | Extract `eval` and `snapshot` into `RealDebugBridgeContext+Snapshot.swift` and `RealDebugBridgeContext+Eval.swift` (per `50-codebase-conventions.md` 300-line guideline). Implement `open(position:)` resolution + bridge-vs-format validation in `eval`. |
| `vreader/Services/DebugBridge/RealDebugBridgeContext+Snapshot.swift` (NEW) | ~120 | new | Pulled-out snapshot writer + new fields. |
| `vreader/Services/DebugBridge/RealDebugBridgeContext+Eval.swift` (NEW) | ~110 | new | Pulled-out eval writer with bridge-vs-format validation. |
| `vreader/Services/DebugBridge/DebugFixtureCatalog.swift` | 56 | modify | Expand the catalog (see WI-9). |
| `vreader/Services/DebugBridge/DebugPositionResolver.swift` (NEW) | ~120 | new | Pure parser: `(format, positionString) -> Locator?` covering TXT (`charOffsetUTF16=<int>`), PDF (`page=<int>`), EPUB (`epubcfi(...)` or `href=<href>;progression=<float>`), AZW3 (CFI). Throws `DebugPositionResolverError` on bad input. No SwiftData / WKWebView dependencies — pure tested function. |
| `vreader/Services/DebugBridge/DebugBridgeFormatBridgeMap.swift` (NEW) | ~30 | new | Pure mapping `eval bridge name → expected book format` (`"epub" → "epub"`, `"foliate" → "azw3"`). Used by `RealDebugBridgeContext+Eval.swift` to validate. |
| `vreader/Services/TTS/TTSService.swift` | (read) | modify | Add `#if DEBUG` extension at end with `TTSService.State.publicName: String` (`"idle" / "speaking" / "paused"`). ~10 LOC. |
| `vreader/Views/Reader/ReaderContainerView.swift` | 376 | modify | In the `#if DEBUG` block: construct `DebugReaderProbeAdapter`, populate universal closures (`ttsStateProvider`, `ttsOffsetProvider`, `settingsProvenanceProvider`), pass each format host a `wireDebugProbe: ((DebugReaderProbeAdapter) -> Void)?` closure that runs the host-specific population (per-host contract in "Per-host probe injection contract" below). |
| `vreader/Views/Reader/EPUBWebViewBridge.swift` | 252 | modify | Expose the live `WKWebView` to the host (via a `@MainActor onWebViewReady: (WKWebView) -> Void` callback). Inject a small "render-committed" JS that posts on `requestAnimationFrame` after the page paints. |
| `vreader/Views/Reader/FoliateSpikeView.swift` | 203 | modify | Same pattern: add `onWebViewReady` and `onRenderCommitted` SwiftUI props plus a `wireDebugProbe: ((DebugReaderProbeAdapter) -> Void)?` stored property (all DEBUG-only, default nil so non-DEBUG callers compile). The Coordinator's existing `book-ready` and `relocate` handlers are extended to invoke `onRenderCommitted` (with the relocate-arming protocol — see Audit Fix on Foliate relocate arming). The dispatcher (`ReaderContainerView.nativeReaderView` switch arm for `"azw3"`) assigns `wireDebugProbe` and wires the probe's `settleStrategy` / `jsEvaluator` / `seekStrategy` from inside the closure. |
| `vreader/Views/Reader/EPUBReaderHost` (in `ReaderFormatHosts.swift`) | 223 | modify | Add DEBUG-only `wireDebugProbe: ((DebugReaderProbeAdapter) -> Void)? = nil` init parameter. After receiving the WKWebView via `onWebViewReady`, invoke `wireDebugProbe?(adapter)` to populate the probe's evaluator, render-phase, selection, settle, and seek-by-CFI strategies. |
| `vreader/Views/Reader/PDFReaderHost` (in `ReaderFormatHosts.swift`) | (in 223) | modify | Add DEBUG-only `wireDebugProbe` init parameter. Per-format settle strategy via `PDFView` first-layout signal; populated inside the host's `wireDebugProbe` callback. |
| `vreader/Views/Reader/TXTReaderHost` (in `ReaderFormatHosts.swift`) | (in 223) | modify | Add DEBUG-only `wireDebugProbe` init parameter. TextKit `layoutManager(_:didCompleteLayoutFor:atEnd:)` settle strategy populated inside the callback. |
| `vreader/Views/Reader/MDReaderHost` (in `ReaderFormatHosts.swift`) | (in 223) | modify | Same as TXT. |
| `vreaderTests/Services/DebugBridge/DebugCommandTests.swift` | 358 | extend | Add a regression test asserting `?cfi=...` URL is rejected (parameter is `position` only). |
| `vreaderTests/Services/DebugBridge/DebugSnapshotTests.swift` | 184 | extend | Round-trip new fields; schema version 2 bump test; rename test names from `"settled"` to `"idle"` for the wire value. |
| `vreaderTests/Services/DebugBridge/DebugFixtureCatalogTests.swift` | 67 | extend | Asserts catalog matches bundled files (existing pattern), plus per-format coverage matrix. |
| `vreaderTests/Services/DebugBridge/RealDebugBridgeContextTests.swift` | 819 | extend | Tests for `open(position:)` happy path, malformed position, awaitReader timeout, snapshot includes new fields, eval-via-mock-evaluator round-trip, eval bridge mismatch error. |
| `vreaderTests/Services/DebugBridge/DebugReaderRegistryTests.swift` | (existing) | extend | Tests for `awaitReader(fingerprintKey:)`: (a) reader already present, (b) reader registers after wait, (c) wrong-key reader registers (still waiting), (d) timeout, (e) multiple waiters for same key. |
| `vreaderTests/Services/DebugBridge/DebugPositionResolverTests.swift` (NEW) | ~140 | new | Per-format parse + invalid-input cases. |
| `vreaderTests/Services/DebugBridge/DebugReaderProbeAdapterTests.swift` (NEW) | ~120 | new | New closure-based providers, settleStrategy precedence, default-implemented protocol fallthrough. |
| `vreaderTests/Services/DebugBridge/DebugBridgeFormatBridgeMapTests.swift` (NEW) | ~40 | new | Bridge-name → format mapping happy path and unknown-bridge error. |
| `vreader/Resources/DebugFixtures/` | (1 file) | add | Add `alice.epub`, `sample.pdf`, `sample.azw3`, `cjk.txt`. |
| `project.yml` | (read) | modify | Add a `Run Script` build phase in the `vreader` target that copies `vreader/Resources/DebugFixtures/*` into `$BUILT_PRODUCTS_DIR/$UNLOCALIZED_RESOURCES_FOLDER_PATH/` only when `${CONFIGURATION} = "Debug"`. The `DebugFixtures/` directory is removed from the target's `sources:` resource phase so it never ships in Release by default. Regenerate `project.pbxproj`. (Note: this only gates the *new* fixtures the calling agent files the pre-existing `war-and-peace.txt` leak as a separate bug; once that bug PR moves `war-and-peace.txt` into `DebugFixtures/`, the same script gates it.) |
| `scripts/verify-release-no-debugbridge.sh` | 113 | (no change) | Already enforces no-fixture-in-Release for `DebugFixtures/`. After WI-9 it will pass for the new fixtures. |

Files explicitly **OUT of scope**:

- `BookImporter` — used as-is for fixture loads.
- `LibraryViewModel` — no changes needed; `debugBridgeOpenBook` notification still drives push.
- `PDFViewBridge`, `TXTTextViewBridge`, `MDTextViewBridge`, `TXTChunkedReaderBridge` — these are TextKit / PDFKit; the per-format render-committed hook lives in the host (not the bridge), see WI-2.
- `FoliateViewBridge.swift` and `FoliateReaderContainerView.swift` — **NOT on the live AZW3 dispatch path** (the dispatcher routes to `FoliateSpikeView`). If/when the dispatcher converges, follow-up plan re-targets this wiring.
- `TTSService` — only adds the `publicName` extension; no new public API.
- `PerBookSettingsStore` — provenance is already inferable: `PerBookSettingsStore.settings(for:baseURL:)` returns nil when no per-book file exists. The probe reads that nil-vs-not signal.
- `ReaderSettingsStore` — read for theme; no mutation surface added.
- The verification flows themselves (#45's job).
- The pre-existing `war-and-peace.txt` Release leak — separate bug filed by calling agent.
- Unified-renderer `open?position=` support — explicitly deferred (see Audit Fix on unified renderer).
- `ttsCurrentSentenceIndex` — explicitly deferred (see Audit Fix on `ttsCurrentSentenceIndex`).
- `Locator.LocatorValidationError: Equatable` conformance — out of scope; #48 routes around it via `DebugPositionResolverError.validationFailed(reason: String)`.

## Key design decisions

### Per-format settle hooks via injectable strategies on the existing adapter

`DebugReaderProbeAdapter` already takes an optional `settleStrategy` closure (`(@MainActor (TimeInterval) async throws -> Void)?`). Today nothing populates it; v1 defaults to a 100ms sleep. The fix is *not* to add a new protocol — it's to make every reader host populate the closure on `register`, with a format-appropriate strategy.

| Format | Strategy |
|--------|----------|
| TXT (TextKit) | Wait for `NSLayoutManager.delegate.layoutManager(_:didCompleteLayoutFor:atEnd:)` with `atEnd == true`. Implementation: `TXTReaderHost` already has access to the `NSTextStorage` via the bridge; expose a one-shot completion callback. The strategy `await`s a continuation resumed on first `atEnd`. |
| MD | Same as TXT — `MDReaderHost` uses `UITextView`/TextKit. |
| EPUB (`EPUBWebViewBridge`) | Wait for a "render-committed" message posted from injected JS. The JS posts `webkit.messageHandlers.renderCommitted.postMessage({})` inside `requestAnimationFrame(() => requestAnimationFrame(post))` after `document.readyState === 'complete'` and after any pending CSS column layout (paged mode). Bridge's coordinator forwards this to a callback held by the host. |
| AZW3 (`FoliateSpikeView`) | Already has the signals. `book-ready` for first paint, `relocate` for in-document seeks. The host installs a one-shot "next relocate after seek" predicate using the **arming protocol** (see Audit Fix on Foliate relocate arming): `armed/armedTargetCFI/armedDeadline` triple maintained on the Coordinator; spontaneous relocates ignored when `armed == false`. |
| PDF | Wait for `PDFView.documentView` first layout — `PDFViewDelegate.pdfViewWillChangeDocument` / a one-shot KVO on `documentView.frame` settling. The simpler approach: `PDFDocumentDidLoadNotification` observer + first non-zero `documentView.bounds`. Detail in WI-5. |
| TTS | If TTS is active, also wait for `TTSService.state` to leave a transient state (`.speaking` is settled, `.idle` post-stop is settled, mid-state changes from a setter resolve when next settled). Implementation: subscribe to TTSService's `state` change for one tick. |

The bridge's existing timeout race in `RealDebugBridgeContext.settleWithTimeout(token:timeoutSeconds:)` already bounds any hanging strategy; per-format strategies don't need to implement timeouts themselves.

**Why closures, not subclasses or new protocols.** Adapters live as one `@State` object per `ReaderContainerView`; the closures bind to other `@State` (`viewModel`, `webView`, `ttsService`) by capture. A protocol-per-format conformance forces those state references into stored properties on a class type, which makes lifecycle harder. Closures are how SwiftUI bridges its state into UIKit-land; reuse the pattern.

### Live `eval` evaluator wired through reader hosts (per-format spelled out)

EPUB and Foliate-AZW3 hosts both already have the `WKWebView` available in their Coordinator. Today nothing exposes it back to `DebugReaderProbeAdapter`. The fix per host:

**EPUB** (`EPUBWebViewBridge.swift` + `EPUBReaderHost` in `ReaderFormatHosts.swift`):
1. `EPUBWebViewBridge` adds `var onWebViewReady: ((WKWebView) -> Void)?` SwiftUI prop. Invoked once at end of `makeUIView` (after constructing the view).
2. `EPUBReaderHost` populates `onWebViewReady` with a closure that captures the parent's `wireDebugProbe` callback.

**AZW3 / Foliate** (`FoliateSpikeView.swift` only — the spike IS the host):
1. `FoliateSpikeView` (the SwiftUI view) adds `var onWebViewReady: ((WKWebView) -> Void)?` and `var onRenderCommitted: ((RenderCommittedReason) -> Void)?` SwiftUI props (DEBUG-only; default nil).
2. The private `FoliateSpikeWebView.makeUIView` invokes `onWebViewReady?(webView)` after assigning `coordinator.webView = webView`.
3. The private `Coordinator.userContentController(_:didReceive:)` extends its `book-ready` switch arm to invoke `onRenderCommitted?(.firstPaint)`, and adds a new `relocate` switch arm (currently absent in `FoliateSpikeView` — Foliate posts to the channel but the spike ignores it) that respects the arming protocol.
4. The dispatcher (`ReaderContainerView.nativeReaderView` `case "azw3":`) wraps `FoliateSpikeView(bookURL:)` to inject the `#if DEBUG` callbacks. The wrapping happens inline in the case arm, ~10 LOC.

3. `RealDebugBridgeContext+Eval.swift`'s eval implementation (v3):
   - Looks up `DebugBridgeFormatBridgeMap.expectedFormat(for: bridge)`.
   - **If `bridge` is unknown (lookup returns nil)** → write `evalUnsupported(bridge:)` error file:
     ```json
     {
       "error": "evalUnsupported",
       "bridge": "<the requested bridge>",
       "knownBridges": ["epub", "foliate"]
     }
     ```
     File path: `Caches/DebugBridge/eval-<bridge>.json` (existing live-code convention — `RealDebugBridgeContext.eval` already writes success and error payloads to this exact path; there is no `dest=` URL parameter on `DebugCommand.eval`). The bridge then returns; nothing else runs. Listing `knownBridges` lets the consumer surface a useful diagnostic without re-reading the source. The error payload extends the existing eval-error shape (which today carries `bridge`, `ts`, `error`, optional `fingerprintKey`, optional `format`) with two additional keys: `evalUnsupported: <bridge name>` and `knownBridges: ["epub", "foliate"]`.
   - **If `bridge` is known but active probe's format ≠ expected** → write `bridgeMismatch` error file with `requested` and `active` keys, return.
   - **Else** build evaluator JS (JSON.stringify wrapper), call `probe.evaluateJavaScript(_:)`, write result to the eval-result file.

The serialization rule (already documented in `DebugReaderProbeAdapter.swift`): JS `undefined` → `null`, primitives → JSON literal, objects → `JSON.stringify(value)` round-tripped through `JSONSerialization`. We add a tiny helper in the eval implementation that wraps the JS in `JSON.stringify((function(){ return (\(userJS)); })())` so the result is always a string the bridge can parse — and JS exceptions surface as a string starting with `"throw:"` (caught in JS), which the bridge maps to `evalFailed`.

**Wrapping the user JS** is the only non-obvious bit. Without it, returning a JS object causes `evaluateJavaScript`'s callback to receive a partially-bridged dictionary that round-trips lossily. With the JSON.stringify wrapper, every JS expression becomes a string literal we can decode deterministically. Snippet:

```swift
let wrappedJS = """
(function(){try{return JSON.stringify((function(){return (\(userJS));})());}catch(e){return JSON.stringify({__vreaderError: String(e && e.message || e)});}})()
"""
```

Errors land in a structured JSON object the bridge recognizes (`__vreaderError` key) and re-throws as `evalFailed`. Real JSON results (numbers, arrays, strings) round-trip cleanly.

**Security note.** The eval surface is DEBUG-only and gated by the `vreader-debug://` URL scheme that's missing from Release Info.plist (per `DebugBridge.plist` exclusion). No new security surface is added in Release.

### Per-host probe injection contract (v3)

Round 2 of audit flagged that v2 claimed hosts populate the probe but didn't add the API parameter. v3 spells it out: every reader host gains a `#if DEBUG`-gated `wireDebugProbe` parameter that the dispatcher uses to thread an already-constructed `DebugReaderProbeAdapter` through to the host. The host invokes the closure once the underlying view (WKWebView / UITextView / PDFView) is ready, populating per-format closures.

Signature (applied to every host):

```swift
#if DEBUG
init(
    fileURL: URL,
    fingerprint: DocumentFingerprint,
    modelContainer: ModelContainer,
    settingsStore: ReaderSettingsStore,
    ttsService: TTSService,
    // … existing params …
    wireDebugProbe: ((DebugReaderProbeAdapter) -> Void)? = nil
)
#else
init(
    fileURL: URL,
    fingerprint: DocumentFingerprint,
    modelContainer: ModelContainer,
    settingsStore: ReaderSettingsStore,
    ttsService: TTSService,
    // … existing params …
)
#endif
```

(For `FoliateSpikeView`, the SwiftUI struct gains a stored DEBUG-only optional property `var wireDebugProbe: ((DebugReaderProbeAdapter) -> Void)?` rather than an init param, because the spike's existing init takes only `bookURL: URL`. Same effect — the dispatcher assigns the closure inline before returning the view.)

`ReaderContainerView.nativeReaderView` (the dispatcher at `vreader/Views/Reader/ReaderContainerView.swift:334-372`) is the single place that constructs the adapter and threads it through:

```swift
#if DEBUG
// `currentLocator` is a value type (`Locator?`). A capture-list closure like
// `{ [currentLocator] in ... }` (the v3 sketch) takes a SNAPSHOT of the
// value at registration time — every probe read returns the same stale
// initial value forever. v4 routes the live read through a tiny
// @MainActor class-backed holder that the SwiftUI view updates whenever
// the locator changes; the closure captures the holder by reference so
// each call performs a live read.
//
// Concretely (in `ReaderContainerView`):
//   #if DEBUG
//   @StateObject private var debugLocatorHolder = DebugLocatorHolder()
//   #endif
//
//   .onChange(of: currentLocator) { _, new in debugLocatorHolder.value = new }
//
// where DebugLocatorHolder is:
//   #if DEBUG
//   @MainActor final class DebugLocatorHolder: ObservableObject {
//       var value: Locator?
//   }
//   #endif
//
let probe = DebugReaderProbeAdapter(
    fingerprintKey: book.fingerprintKey,
    format: book.format,
    positionProvider: { [weak debugLocatorHolder] in
        // Live read each call — not a registration-time snapshot.
        debugLocatorHolder?.value.flatMap(DebugPositionFormatter.format(_:))
    }
)
// Universal providers (set on every format)
probe.ttsStateProvider           = { [weak ttsService] in ttsService?.state.publicName }
probe.ttsOffsetProvider          = { [weak ttsService] in ttsService?.currentOffsetUTF16 }
probe.settingsProvenanceProvider = { /* PerBookSettingsStore lookup */ }
debugProbe = probe
DebugReaderRegistry.shared.register(probe)
#endif

switch book.format.lowercased() {
case "epub":
    EPUBReaderHost(
        fileURL: resolvedFileURL,
        // …
        wireDebugProbe: { [weak probe] adapter in
            // host's own per-format wiring runs here — see contract below
        }
    )
// …same shape for pdf, txt, md, azw3
}
```

**Per-host callback contract** — what each host invokes the closure with, and what closures each host populates inside it:

| Host | Trigger for invoking `wireDebugProbe` | Closures host populates on the adapter |
|------|---------------------------------------|----------------------------------------|
| `EPUBReaderHost` | After `EPUBWebViewBridge.onWebViewReady` fires (WKWebView available + render-committed handler installed). | `jsEvaluator` (wraps `WKWebView.evaluateJavaScript` with the JSON.stringify wrapper); `settleStrategy` (continuation resolved by EPUB's `renderCommitted` JS message); `renderPhaseProvider` (reads host-local `RenderPhase` enum: `.loading` until first navigation completes, `.rendering` between page-change request and `renderCommitted`, `.idle` after); `selectionProvider` (reads cached selection populated by `selectionTrackingJS`); `seekStrategy` (calls into the EPUB ViewModel's `navigate(to:)`). |
| `PDFReaderHost` | After `PDFViewDelegate.pdfViewWillChangeDocument` fires AND first non-zero `documentView.bounds` settles. | `settleStrategy` (continuation resolved by PDF first-layout signal); `renderPhaseProvider` (`.loading` → `.idle` after first layout); `selectionProvider` (reads `PDFView.currentSelection`); `seekStrategy` (calls `viewModel.goToPage(_:)`). PDF has no `jsEvaluator`. |
| `TXTReaderHost` | After TextKit `layoutManager(_:didCompleteLayoutFor:atEnd:)` fires once with `atEnd == true`. | `settleStrategy` (one-shot continuation on next `atEnd: true`); `renderPhaseProvider` (`.loading` → `.idle`); `selectionProvider` (reads `UITextView.selectedRange` + extracted text); `seekStrategy` (calls TXT viewModel's `seek(toCharOffset:)`). No `jsEvaluator`. |
| `MDReaderHost` | Same trigger and contract as TXT. | Same closures as TXT. |
| `FoliateSpikeView` | After `Coordinator.userContentController(_:didReceive:)` receives `book-ready` (first-paint) AND `webView` is non-nil. | `jsEvaluator` (wraps the spike's `webView.evaluateJavaScript`); `settleStrategy` (continuation resolved by the arming protocol — `book-ready` for first paint, post-arm `relocate` for in-document seeks); `renderPhaseProvider` (host-local enum mirroring EPUB's); `selectionProvider` (reads cached selection from the existing `selection` channel handler); `seekStrategy` (calls the spike's JS seek API after invoking `Coordinator.armForSeek(targetCFI:deadline:)`). |

**What the host callback signals back to the bridge layer.** The host doesn't directly notify the bridge of every event; the bridge reads through the probe's closures on demand (snapshot reads `currentSelection()` etc.) and `awaitSettle` blocks on `settleStrategy`. The exception is `seekStrategy`'s completion signal:

- For TXT/MD/PDF: `seekStrategy` awaits a continuation resolved when the format's settle signal fires post-seek (TextKit `atEnd:true`, PDFView layout settle).
- For EPUB: `seekStrategy` awaits the next `renderCommitted` message.
- For AZW3 (FoliateSpikeView): `seekStrategy` calls `Coordinator.armForSeek(targetCFI:deadline:)` then awaits the continuation that `book-ready`/`relocate` resolves under the arming protocol.

The host owns these continuations (they live on the host's `Coordinator` for UIKit-wrapped hosts, or on a small per-host actor for pure-SwiftUI ones). The probe's `seekStrategy` closure is the only exposure to the bridge.

**Cleanup.** `ReaderContainerView`'s existing `#if DEBUG .onDisappear` already calls `DebugReaderRegistry.shared.unregister(probe)`. The host's captured probe reference is `weak`, so when the registry releases its reference the adapter and all its closures deallocate. The host's Coordinator-owned continuations are cancelled on host teardown via the existing bridge cleanup pattern (`50-codebase-conventions.md` §5).

### `open?position=` resolution via a pure `DebugPositionResolver`

The position string format depends on the book's format. Instead of branching inside `RealDebugBridgeContext.open`, pull the parsing into a pure type:

```swift
enum DebugPositionResolver {
    static func resolve(
        positionString: String,
        bookFingerprint: DocumentFingerprint
    ) throws -> Locator
}

enum DebugPositionResolverError: Error, Equatable {
    case unknownFormat(String)
    case malformedPosition(format: String, raw: String, reason: String)
    /// `LocatorValidationError` is `Sendable` only (not `Equatable`); the
    /// resolver flattens it to a stable string so this error stays `Equatable`.
    case validationFailed(reason: String)
}
```

Per-format grammar:

| Format | Grammar | Example |
|--------|---------|---------|
| TXT / MD | `charOffsetUTF16=<int>` | `charOffsetUTF16=12345` |
| PDF | `page=<int>` (0-based, matches `Locator.page`) | `page=42` |
| EPUB | Either `epubcfi(...)` (full CFI) or `href=<href>;progression=<float>` | `epubcfi(/6/4!/4/2)` |
| AZW3 | `epubcfi(...)` (Foliate-js produces CFIs) | `epubcfi(/6/4!/4)` |

Reasons to keep this resolver pure:
- `RealDebugBridgeContext.open` becomes "resolve → wait for keyed reader → seek" — short.
- Tests can exhaustively cover parse failures without spinning up readers.
- Phase-2 verification harness (#45) imports the same resolver directly to assert "the position string the test wrote is the position string the snapshot reports."

Seek dispatch: once a Locator is built, `RealDebugBridgeContext.open` calls `DebugReaderRegistry.shared.awaitReader(fingerprintKey: bookId, timeout: 10)` (see next section), then calls `probe.seek(to: locator)`. If the resolver returns `.unsupportedInUnifiedMode` (when the active container is in unified mode and the format has `.unifiedReflow` capability), `open` writes that as the bridge error.

The probe gains an optional `seekStrategy: ((Locator) async throws -> Void)?` — wired by each container with its native seek (TXT viewModel `seek(toCharOffset:)`, EPUB viewModel `navigate(to:)`, AZW3/Foliate `evaluateJavaScript("readerAPI.goTo(...)")`, PDF viewModel `goToPage(_:)`).

**Edge case.** `open` with no `position` keeps current behavior (open at last-saved position). `open` with `position=` (empty) is rejected at the parser layer (already handled — `nonEmpty(...)` returns nil, `position` becomes nil).

### `awaitReader(fingerprintKey:timeout:)` replaces `awaitNextRegister`

The v1 plan had `awaitNextRegister(timeout:)` with a 100ms heuristic for "register fired before await call." That's a race with no principled bound. v2 redesigns:

```swift
extension DebugReaderRegistry {
    /// Returns a probe matching `fingerprintKey`. If a matching probe is already
    /// registered, returns immediately. Otherwise installs a continuation that
    /// resumes when a matching probe registers, or throws `awaitReaderTimeout`
    /// after `timeout` seconds.
    /// Multiple waiters for the same key all resume on a single matching register.
    /// Wrong-key registers do not resume waiters.
    func awaitReader(
        fingerprintKey: String,
        timeout: TimeInterval
    ) async throws -> DebugReaderProbe
}
```

Implementation sketch (v4 — each waiter owns a unique token; timeout removes by token identity, not first-match. **Storage is weak** — the registry's `activeReader` is a `weak var` in the live code, so `current` is a computed property that dereferences it. If the SwiftUI host holding the probe deallocates without unregistering, `current` simply reads as nil and `awaitReader` treats the slot as "no active reader" rather than "still registered"):

```swift
@MainActor
final class DebugReaderRegistry {
    /// Live code stores this weakly so a forgotten unregister never keeps the
    /// presenting view alive. `current` reads through the weak slot — when the
    /// referent has deallocated this returns nil, which `awaitReader` treats
    /// as "no active reader" (no need for an explicit unregister to be
    /// observed).
    private weak var activeReader: AnyObject?
    var current: DebugReaderProbe? { activeReader as? DebugReaderProbe }

    /// Each waiter is identified by a UUID token so a per-waiter timeout
    /// can remove the *specific* continuation it owns, not the first one
    /// in the array. Without this, two callers waiting on the same key
    /// with different timeouts would race: the shorter timeout would
    /// remove (and resume-with-timeout) the longer caller's continuation.
    ///
    /// `CheckedThrowingContinuation` (not `CheckedContinuation`) is the
    /// Swift convention for continuations that may resume with an error —
    /// the timeout branch resumes with `awaitReaderTimeout`.
    private struct Waiter {
        let token: UUID
        let continuation: CheckedThrowingContinuation<DebugReaderProbe, Error>
    }
    private var waiters: [String: [Waiter]] = [:]

    func register(_ probe: DebugReaderProbe) {
        activeReader = probe
        let key = probe.fingerprintKey
        let pending = waiters.removeValue(forKey: key) ?? []
        for w in pending { w.continuation.resume(returning: probe) }
    }

    func unregister(_ probe: DebugReaderProbe) {
        if activeReader === probe as AnyObject { activeReader = nil }
        // Waiters keyed by other fingerprintKeys persist; they're for a future register.
    }

    func awaitReader(fingerprintKey: String, timeout: TimeInterval) async throws -> DebugReaderProbe {
        if let probe = current, probe.fingerprintKey == fingerprintKey { return probe }
        let token = UUID()
        return try await withThrowingTaskGroup(of: DebugReaderProbe.self) { group in
            group.addTask { @MainActor in
                try await withCheckedThrowingContinuation { c in
                    self.waiters[fingerprintKey, default: []].append(
                        Waiter(token: token, continuation: c)
                    )
                }
            }
            group.addTask { @MainActor in
                try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                // Remove THIS task's waiter by token identity, then resume it
                // with the timeout error. If the register path already drained
                // and resumed our continuation, removeByToken returns nil and
                // we throw a stale-cancellation error that the task group
                // discards (the other branch already produced the result).
                if let waiter = self.removeWaiter(key: fingerprintKey, token: token) {
                    waiter.continuation.resume(
                        throwing: DebugBridgeContextError.awaitReaderTimeout(
                            fingerprintKey: fingerprintKey
                        )
                    )
                }
                throw DebugBridgeContextError.awaitReaderTimeout(fingerprintKey: fingerprintKey)
            }
            // First to finish wins; cancel the other.
            let result = try await group.next()!
            group.cancelAll()
            return result
        }
    }

    /// Removes and returns the waiter with the given token, if still pending.
    /// Returns nil if `register` already drained it.
    private func removeWaiter(key: String, token: UUID) -> Waiter? {
        guard var pending = waiters[key] else { return nil }
        guard let idx = pending.firstIndex(where: { $0.token == token }) else { return nil }
        let waiter = pending.remove(at: idx)
        if pending.isEmpty { waiters.removeValue(forKey: key) }
        else { waiters[key] = pending }
        return waiter
    }
}
```

**Why token identity matters.** Suppose caller A awaits with timeout 10s and caller B awaits the same key with timeout 1s. After ~1s, B's timeout fires. With the v2 first-match removal, the timeout would pop A's continuation (it was inserted first) and resume A with `awaitReaderTimeout`, leaving B's continuation stuck in the array forever. With token identity, B's timeout finds B's token and resumes B; A continues waiting until either the reader registers or A's own timeout fires.

Tests cover:
- Reader already present → returns immediately.
- Reader registers after `awaitReader` begins → waiter resumes.
- Wrong-key reader registers → waiter still waiting.
- Timeout → waiter resumes with `awaitReaderTimeout`.
- Multiple waiters for the same key → all resume on a single matching register.
- Stale-reader-disappear/reappear cycle: register A → unregister A → await(A, t=long) → register A → resume.
- **Two waiters for the same key with different timeouts (token-identity test):** A waits with timeout=10s, B waits with timeout=0.1s on the same key. After ~0.1s, B times out; A is still pending. Then register fires → A resumes. Assert: B got `awaitReaderTimeout`, A got the probe. (This test fails on the v2 first-match implementation; it's the regression test for Round-2 Fix #1.)

### Snapshot schema additions + version bump

`DebugSnapshot.currentSchemaVersion` goes from 1 to 2. New fields:

| Field | Type | Source | When nil → `partial` |
|-------|------|--------|----------------------|
| `ttsState` | `String?` | `probe.ttsStateProvider?()` (closure reads `TTSService.state.publicName`) | When no probe is registered. |
| `ttsOffsetUTF16` | `Int?` | `probe.ttsOffsetProvider?()` (closure reads `TTSService.currentOffsetUTF16`) | When TTS state is `.idle` or no probe. |
| `selection` | `SelectionInfo?` (already exists, currently always nil) | EPUB: existing `selectionTracking.js` posts to `selectionChanged` channel; cache last-known selection on the host and expose via `probe.selectionProvider?()`. Foliate: same via `selection` channel (already routed in `FoliateSpikeView.Coordinator`). PDF: `PDFView.currentSelection`. TXT/MD: `UITextView.selectedRange` + extracted text. | When no reader has ever posted a selection. |
| `renderPhase` | `String` (already exists, hardcoded `"idle"`) | `probe.renderPhaseProvider?() ?? "unknown"`. Hosts maintain a small enum: `"loading" / "rendering" / "idle"`. EPUB: `"loading"` until first navigation completes, `"rendering"` between page change request and render-committed message, `"idle"` after. PDF/TXT analogous. **Wire value normalized to `"idle"` (not `"settled"`)** — see Audit Fix on renderPhase naming. | Authoritative when probe is present; `"unknown"` when not. |
| `settingsProvenance` | `String?` | `"per-book"` if `PerBookSettingsStore.settings(for:baseURL:)` returns non-nil for the active book; `"global"` otherwise. | Nil only if no active book. |

`partial[]` semantics stay: a field is in `partial` when its nil value means "not yet implemented in this build", not "no value." Selection nil with no active reader → in `partial`. Selection nil with active reader and user has never selected → not in `partial` (authoritative nil).

**Sentence-index dropped.** Recorded in Open Questions; needs separate planning with explicit tokenizer semantics.

### Test-only fixtures via build-phase script (the only viable xcodegen pattern)

The audit confirmed that xcodegen's `excludes:` is not per-build-config. Three alternatives were considered:

- **Debug-only target.** Requires duplicating most of the `vreader` target's settings; risks drift.
- **Separate XcodeGen spec generated only for Debug.** Invalidates the `xcodegen generate` workflow (which always uses one spec) and breaks the docs-sync rule (which assumes `project.yml` fully describes the project).
- **Build-phase script that copies fixtures only when `${CONFIGURATION}` is `Debug`** — chosen.

Stanza shape in `project.yml` (v3 — `rsync -a` is idempotent and doesn't fail on empty source; `inputFiles` references the parent directory so Xcode invalidates the build phase when fixtures are added/removed/changed):

```yaml
targets:
  vreader:
    sources:
      - path: vreader
        excludes:
          - "Resources/DebugFixtures/**"   # never goes through the regular Resources phase
    postBuildScripts:
      - script: |
          if [ "${CONFIGURATION}" = "Debug" ]; then
            DEST="${BUILT_PRODUCTS_DIR}/${UNLOCALIZED_RESOURCES_FOLDER_PATH}/DebugFixtures"
            mkdir -p "$DEST"
            # rsync -a: archive mode (preserves attrs, recurses), idempotent.
            # The include/exclude pattern preserves directory structure but
            # excludes nothing — the explicit '*' include + '*' exclude is a
            # no-op compared to plain `rsync -a SRC/ DEST/`, but documenting
            # the form makes the intent (copy everything, fail-safe on empty)
            # explicit and matches Xcode's typical resource-copy idiom.
            # Trailing slash on source means "contents of DebugFixtures/", not
            # the directory itself — same shape as cp -R src/. dest/.
            rsync -a "${SRCROOT}/vreader/Resources/DebugFixtures/" "$DEST/"
          fi
        name: Copy DebugFixtures (Debug only)
        # Reference the parent directory so Xcode invalidates this phase
        # when ANY fixture file under DebugFixtures/ changes. Listing
        # individual files would silently miss new fixtures added later.
        inputFiles:
          - $(SRCROOT)/vreader/Resources/DebugFixtures
        # outputFiles intentionally omitted: rsync is idempotent and
        # determining exact output paths from a wildcard source is fragile.
        # If incremental-build flakiness shows up, we'll add an explicit
        # output marker file (touch a sentinel inside DEST) and list it.
```

**Why `rsync -a` over `cp -R`.** `cp "${SRCROOT}/.../DebugFixtures/"*` fails with "no matches found" if the directory is empty (which it briefly is during a fresh checkout before WI-9 lands). `rsync -a SRC/ DEST/` succeeds on empty source as a no-op. `rsync` also preserves modification times by default, which lets Xcode skip resource embedding when nothing actually changed.

**Why `inputFiles` lists the parent directory, not individual files.** Xcode's input-file dependency tracker treats a directory entry as "anything under this directory." Listing individual files would miss new fixtures added in later PRs (WI-9 + future fixture additions); the directory entry self-updates.

The test bundle (`vreaderTests`) lists the same directory under its own `sources:` so unit tests find fixtures via `Bundle(for: TestClass.self).url(forResource:withExtension:)` regardless of build configuration. Run-time loader in `DebugFixtureCatalog` reads from `Bundle.main` (DEBUG only — the catalog is `#if DEBUG`-gated).

**The pre-existing `war-and-peace.txt` Release leak is NOT fixed by this WI.** That's a separate bug. Once the bug PR moves `war-and-peace.txt` into `vreader/Resources/DebugFixtures/`, the same script gates it; the bug PR is the right place to do that move.

### URL grammar reconciliation: `position` is canonical

The DocC at `DebugCommand.open` already says `position`; the DocC at the top of the file says `cfi`. Code uses `position` and tests assert `position`. Fix: update the top-of-file DocC + add a regression test that explicitly asserts `vreader-debug://open?bookId=X&cfi=Y` is rejected as `missingParam("position")` (so a future revert is caught).

## File-by-file changes

### Modified: `vreader/Services/DebugBridge/DebugCommand.swift`

Top-of-file DocC: change `open?bookId=<uuid>[&cfi=<position>]` to `open?bookId=<uuid>[&position=<string>]` and add a one-line link to `DebugPositionResolver` for the per-format grammar. No parser change — the existing implementation already requires `position`.

### Modified: `vreader/Services/DebugBridge/DebugReaderRegistry.swift`

```swift
@MainActor
protocol DebugReaderProbe: AnyObject {
    var fingerprintKey: String { get }
    var format: String { get }
    var currentPositionString: String? { get }

    // Existing
    func awaitSettle(timeout: TimeInterval) async throws
    func evaluateJavaScript(_ script: String) async throws -> Data

    // NEW (default-implemented so existing adapters compile)
    func currentSelection() -> DebugSnapshot.SelectionInfo?
    func currentRenderPhase() -> String
    func currentTTSState() -> String?
    func currentTTSOffsetUTF16() -> Int?
    func currentSettingsProvenance() -> String?
    func seek(to locator: Locator) async throws
}

extension DebugReaderProbe {
    func currentSelection() -> DebugSnapshot.SelectionInfo? { nil }
    func currentRenderPhase() -> String { "unknown" }
    func currentTTSState() -> String? { nil }
    func currentTTSOffsetUTF16() -> Int? { nil }
    func currentSettingsProvenance() -> String? { nil }
    func seek(to locator: Locator) async throws {
        throw DebugReaderProbeError.seekUnsupported(format: format)
    }
}

enum DebugReaderProbeError: Error, Equatable {
    case evalUnsupported(format: String)
    case settleTimeout
    case seekUnsupported(format: String)
    case seekFailed(String)
    case seekTimeout
}
```

Add `awaitReader(fingerprintKey:timeout:)` to the registry per the design decision above. This **replaces** the v1 `awaitNextRegister`.

### New: `vreader/Services/DebugBridge/DebugPositionResolver.swift` (~120 lines)

```swift
#if DEBUG
import Foundation

enum DebugPositionResolver {
    /// Parse a position string into a Locator for the given book's format.
    /// Per-format grammar:
    ///   TXT / MD: "charOffsetUTF16=<int>"
    ///   PDF:      "page=<int>"          (0-based, matches Locator.page)
    ///   EPUB:     "epubcfi(...)" OR "href=<href>;progression=<float>"
    ///   AZW3:     "epubcfi(...)"
    ///
    /// Native-mode-only. Unified-renderer mode is unsupported in #48 and
    /// returns `unsupportedInUnifiedMode` from the bridge layer (not here);
    /// the resolver itself is renderer-agnostic.
    static func resolve(
        positionString: String,
        bookFingerprint: DocumentFingerprint
    ) throws -> Locator
}

enum DebugPositionResolverError: Error, Equatable {
    case unknownFormat(String)
    case malformedPosition(format: String, raw: String, reason: String)
    /// `LocatorValidationError` is `Sendable` only (not `Equatable`). The
    /// resolver maps each LocatorValidationError case to a stable string:
    ///   .negativePageIndex     -> "negativePageIndex"
    ///   .negativeUTF16Offset   -> "negativeUTF16Offset"
    ///   .invertedUTF16Range    -> "invertedUTF16Range"
    ///   .nonFiniteProgression  -> "nonFiniteProgression"
    case validationFailed(reason: String)
}
#endif
```

Tests: `DebugPositionResolverTests.swift` covers (1) every format's happy path, (2) malformed input per format, (3) a position-string for a format that doesn't accept that grammar (e.g., `page=5` on EPUB → `malformedPosition`), (4) Locator validation propagation (negative offset → `validationFailed(reason: "negativeUTF16Offset")`).

### New: `vreader/Services/DebugBridge/DebugBridgeFormatBridgeMap.swift` (~30 lines)

```swift
#if DEBUG
import Foundation

/// Maps eval `bridge` parameter values to the book format that the bridge
/// can evaluate JS in.
enum DebugBridgeFormatBridgeMap {
    static let knownBridges: [String: String] = [
        "epub": "epub",
        "foliate": "azw3",   // FoliateSpikeView is the live AZW3 host
    ]

    /// Returns the expected book format for a bridge name, or nil if the
    /// bridge name is unknown.
    static func expectedFormat(for bridge: String) -> String? {
        knownBridges[bridge]
    }
}
#endif
```

### Modified: `vreader/Services/DebugBridge/DebugReaderProbeAdapter.swift`

Add stored closures matching the new probe protocol members, wire `seek(to:)` through `seekStrategy`. No behavior change for existing callers — every new closure is optional and the protocol's default implementation handles nil.

### Modified: `vreader/Services/DebugBridge/DebugSnapshot.swift`

Add fields per "Snapshot schema additions" table. Bump `currentSchemaVersion` to 2. Update `encode(to:)` to emit them. The `partial[]` builder lives in `RealDebugBridgeContext+Snapshot.swift` (extracted file). Wire value for `renderPhase` is `"idle"` / `"loading"` / `"rendering"` / `"unknown"` — never `"settled"`.

### Modified + split: `vreader/Services/DebugBridge/RealDebugBridgeContext.swift`

`open(bookId:position:)` becomes (v4 — **validate fully before any side effect**, then post notification, then await reader and seek; references against the actual live types):

```swift
func open(bookId: String, position: String?) async throws {
    // 1. Validate bookId by fingerprintKey lookup.
    let books = try await persistence.fetchAllLibraryBooks()
    guard let bookRecord = books.first(where: { $0.fingerprintKey == bookId }) else {
        throw DebugBridgeContextError.bookNotFound(bookId)
    }

    // BookRecord exposes the format via `bookRecord.fingerprint.format`
    // (a `BookFormat` enum). The bridge's user-facing strings stay raw values
    // so error payloads remain stable across the existing wire format.
    let bookFormat: BookFormat = bookRecord.fingerprint.format
    let formatString: String = bookFormat.rawValue

    // 2. If position provided, validate against the format BEFORE any side effect.
    //    Malformed position must NOT open the reader: previously the post-then-throw
    //    order produced two side effects from one bad call.
    var resolvedLocator: Locator? = nil
    if let positionString = position {
        let fingerprint = bookRecord.fingerprint  // already typed; no canonicalKey re-parse
        do {
            resolvedLocator = try DebugPositionResolver.resolve(
                positionString: positionString, bookFingerprint: fingerprint
            )
        } catch {
            throw DebugBridgeContextError.openPositionUnresolvable(
                format: formatString, position: positionString
            )
        }

        // 3. Unified-renderer guard: if settings put the reader in unified mode
        //    for a format with .unifiedReflow capability, position seek is
        //    unsupported. `RealDebugBridgeContext` does NOT hold a
        //    ReaderSettingsStore — it stores `userDefaults: UserDefaults`
        //    (verified against the live code at
        //    vreader/Services/DebugBridge/RealDebugBridgeContext.swift). To
        //    read the reading mode, instantiate a transient store from those
        //    same defaults; same pattern that `theme(...)` already uses on
        //    this type.
        let store = ReaderSettingsStore(defaults: userDefaults)
        // FormatCapabilities.capabilities(for:) takes BookFormat (verified
        // against the live signature at vreader/Models/FormatCapabilities.swift).
        let caps = FormatCapabilities.capabilities(for: bookFormat)
        if store.readingMode == .unified && caps.contains(.unifiedReflow) {
            throw DebugBridgeContextError.openPositionUnsupportedInUnifiedMode(
                format: formatString
            )
        }
    }

    // 4. Validation passed — post the open notification.
    NotificationCenter.default.post(
        name: .debugBridgeOpenBook, object: nil,
        userInfo: ["fingerprintKey": bookId]
    )
    log.info("open: posted notification for \(bookId, privacy: .public)")

    guard let locator = resolvedLocator else { return }

    // 5. Wait for a probe matching this specific bookId to register, then seek.
    let probe = try await DebugReaderRegistry.shared.awaitReader(
        fingerprintKey: bookId, timeout: Self.openSeekTimeoutSeconds
    )
    // probe.fingerprintKey == bookId is guaranteed by awaitReader's matcher.
    try await probe.seek(to: locator)
}

static let openSeekTimeoutSeconds: TimeInterval = 10.0
```

**Order rationale.** The previous (v2) order had two failure modes for one URL: a bad position would (1) open the reader at last-saved position, then (2) throw `openPositionUnresolvable` to `lastError.json`. A consumer reading `lastError.json` would see "open failed" but the reader is actually open, just at the wrong location — confusing and breaks the "every command writes one outcome" contract. v3 validates everything that can be validated locally before any side effect, so a bad-position URL is a pure no-op + error file write.

**v4 type fidelity.** Three live-code facts the v3 sketch got wrong, corrected here:
1. `RealDebugBridgeContext` stores `userDefaults: UserDefaults` (not `settingsStore`) — the existing `theme(...)` handler already follows the "instantiate a transient `ReaderSettingsStore(defaults: userDefaults)`" pattern, and `open` reuses it.
2. `FormatCapabilities.capabilities(for:)` takes `BookFormat` (the enum), not `String`. The existing `BookRecord` already exposes the typed format via `bookRecord.fingerprint.format`, so no string-based lookup or re-parse of `canonicalKey` is required.
3. `BookRecord` itself has no top-level `format: String` — only `fingerprint.format: BookFormat`. The wire-level error payloads still carry strings; we derive them from `bookFormat.rawValue` once at the top of the function.

`FormatCapabilities` is read here (not `Locator`) so the unified-mode guard runs without instantiating any reader machinery. The capability lookup is pure (a switch on `BookFormat`).

Tests cover:
- Malformed position string → reader is NOT opened, `lastError.json` contains `openPositionUnresolvable`.
- Unified-mode TXT + `position=charOffsetUTF16=…` → reader is NOT opened, `lastError.json` contains `openPositionUnsupportedInUnifiedMode`.
- Valid position + native mode → notification posted exactly once, then seek runs.
- Position omitted → notification posted, no seek path runs (existing behavior preserved).

Add error cases in `DebugBridgeContextError`:

```swift
case openPositionUnresolvable(format: String, position: String)
case openPositionUnsupportedInUnifiedMode(format: String)
case bridgeMismatch(requested: String, active: String)
case evalUnsupported(bridge: String)            // unknown bridge name in eval
case awaitReaderTimeout(fingerprintKey: String)
```

`stableErrorMessage(for:)` in `DebugBridge.swift` gains the case mappings.

`snapshot` and `eval` methods move into the new extension files. `eval` adds bridge-vs-format validation as the first step after fetching the active probe — see the `RealDebugBridgeContext+Eval.swift` description below.

### Modified: `vreader/Views/Reader/EPUBWebViewBridge.swift`

Add SwiftUI prop:

```swift
/// DEBUG-only callback invoked once when the WKWebView is ready to receive
/// `evaluateJavaScript`. Host wires this into DebugReaderProbeAdapter.jsEvaluator.
var onWebViewReady: ((WKWebView) -> Void)?
```

Invoke at end of `makeUIView`: `onWebViewReady?(webView)`. Inject one new user script (DEBUG-only — gate at the inject site with `#if DEBUG`):

```js
// render-committed.js  (small inline literal)
(function(){
  function postReady(){
    requestAnimationFrame(function(){
      requestAnimationFrame(function(){
        try { window.webkit.messageHandlers.renderCommitted.postMessage({}); } catch(e){}
      });
    });
  }
  if (document.readyState === 'complete') { postReady(); }
  else { window.addEventListener('load', postReady); }
})();
```

Add `renderCommitted` channel to `userContentController.add(weakHandler, name:)`. Coordinator forwards to a new optional callback `onRenderCommitted: (() -> Void)?`.

### Modified: `vreader/Views/Reader/FoliateSpikeView.swift` (live AZW3 renderer)

Add `#if DEBUG`-gated SwiftUI props on `FoliateSpikeView`:

```swift
#if DEBUG
var onWebViewReady: ((WKWebView) -> Void)?
var onRenderCommitted: ((RenderCommittedReason) -> Void)?
enum RenderCommittedReason { case firstPaint; case afterSeek }
#endif
```

Pass them through to `FoliateSpikeWebView` and into `Coordinator`. In `Coordinator.userContentController(_:didReceive:)`:

- Existing `book-ready` arm: after the existing logic, invoke `onRenderCommitted?(.firstPaint)` (DEBUG-only).
- New `relocate` arm (currently absent — the spike doesn't handle this channel, but Foliate posts to it): if `armed`, invoke `onRenderCommitted?(.afterSeek)` and clear arming state. Otherwise, ignore.
- Add `armed: Bool`, `armedTargetCFI: String?`, `armedDeadline: Date?` to Coordinator state (DEBUG-only).
- Add a method `armForSeek(targetCFI: String, deadline: Date)` that the host calls before invoking the JS seek.

The dispatcher (`ReaderContainerView.nativeReaderView` `case "azw3":`) wraps the spike to wire DEBUG callbacks:

```swift
case "azw3":
    let spike = FoliateSpikeView(bookURL: resolvedFileURL)
    #if DEBUG
    var spikeWithProbe = spike
    spikeWithProbe.onWebViewReady = { webView in
        // populate debugProbe.jsEvaluator
    }
    spikeWithProbe.onRenderCommitted = { reason in
        // resolve settle continuation / clear seek arm
    }
    return spikeWithProbe
    #else
    return spike
    #endif
```

### Modified: `vreader/Views/Reader/ReaderContainerView.swift` (DEBUG-only block, v3)

The dispatcher constructs the adapter and populates **universal** closures (those that don't need per-format machinery), then threads `wireDebugProbe` to each format host. The host invokes the closure once its underlying view is ready, populating **per-format** closures (`settleStrategy`, `jsEvaluator`, `renderPhaseProvider`, `selectionProvider`, `seekStrategy`). Full per-host contract: see "Per-host probe injection contract" design decision above.

```swift
#if DEBUG
.onAppear {
    // v4: positionProvider must perform a LIVE read on each call. A value-type
    // capture list like `[currentLocator]` (v3) snapshots the value at
    // registration time, so the probe would forever report the initial
    // locator. The fix is a small class-backed holder that the host updates
    // whenever the SwiftUI `@State Locator?` changes; the closure captures
    // the holder by reference and reads `.value` on every invocation.
    let probe = DebugReaderProbeAdapter(
        fingerprintKey: book.fingerprintKey,
        format: book.format,
        positionProvider: { [weak debugLocatorHolder] in
            debugLocatorHolder?.value.flatMap(DebugPositionFormatter.format(_:))
        }
    )
    // Universal providers (set on every format — no UIKit/WKWebView dependency).
    probe.ttsStateProvider           = { [weak ttsService] in ttsService?.state.publicName }
    probe.ttsOffsetProvider          = { [weak ttsService] in ttsService?.currentOffsetUTF16 }
    probe.settingsProvenanceProvider = { /* PerBookSettingsStore lookup */ }
    debugProbe = probe
    DebugReaderRegistry.shared.register(probe)
    // Per-format closures (settleStrategy, jsEvaluator, renderPhaseProvider,
    // selectionProvider, seekStrategy) are populated by the format host
    // through the `wireDebugProbe` parameter — see nativeReaderView below.
}
.onChange(of: currentLocator) { _, newValue in
    // Push every locator update into the holder so the probe's
    // positionProvider closure reads the freshest value on its next call.
    debugLocatorHolder.value = newValue
}
#endif
```

The per-format population happens inside `nativeReaderView`'s switch arms via the `wireDebugProbe` host parameter:

```swift
@ViewBuilder
func nativeReaderView(fingerprint: DocumentFingerprint) -> some View {
    switch book.format.lowercased() {
    case "epub":
        EPUBReaderHost(
            fileURL: resolvedFileURL,
            fingerprint: fingerprint,
            modelContainer: modelContext.container,
            settingsStore: settingsStore,
            ttsService: ttsService,
            #if DEBUG
            wireDebugProbe: { [weak self] adapter in
                // host has the WKWebView and the bridge by now; populate the
                // per-format closures directly on the adapter here. The host's
                // own onWebViewReady has already fired before this runs.
                // (Concrete population per "Per-host probe injection contract".)
            }
            #endif
        )
    // …same shape for pdf / txt / md / azw3
    }
}
```

(Note: `[weak ttsService]` is fine because `TTSService` is a class; `[weak currentLocator]` was wrong because `Locator` is a struct (Round-1 fix). v4 goes further: the v3 `[currentLocator]` capture-list pattern is also wrong because a value-type capture-list closure snapshots the value at registration time and never re-reads. The v4 pattern routes through a `@MainActor` class-backed `DebugLocatorHolder` that the host updates on every locator change; the closure captures the holder by reference (`[weak debugLocatorHolder]`) and reads `.value` live each call.)

### Modified: `vreader/Services/TTS/TTSService.swift`

Append at end of file:

```swift
#if DEBUG
extension TTSService.State {
    /// Stable string for the snapshot probe. Not `RawRepresentable` because
    /// the production type doesn't need it; this extension is DEBUG-only.
    var publicName: String {
        switch self {
        case .idle:     return "idle"
        case .speaking: return "speaking"
        case .paused:   return "paused"
        }
    }
}
#endif
```

### New helper: `DebugPositionFormatter` (~30 lines, in same file as resolver)

`Locator → String?` — inverse of resolver. Used by `currentPositionString` so the snapshot's `position` field round-trips with what `open?position=` accepts.

### New tests

Each new test file is sized 100–250 LOC (under guideline). Coverage:

- `DebugPositionResolverTests.swift` (~140 LOC) — per-format parse + edge cases + flattened-validation-error cases.
- `DebugReaderProbeAdapterTests.swift` (~120 LOC) — closure precedence (adapter falls through to protocol default when closure nil), settleStrategy chosen over default sleep, jsEvaluator chosen over `evalUnsupported`.
- `DebugBridgeFormatBridgeMapTests.swift` (~40 LOC) — known bridges map correctly; unknown bridge returns nil.
- `DebugReaderRegistryTests.swift` extension — `awaitReader` (5 cases listed in design decision above).
- `RealDebugBridgeContextTests` extension — `open(position:)` happy path with mock probe; `open(position:)` with malformed position throws `openPositionUnresolvable`; `open(position:)` when probe doesn't register within timeout throws `awaitReaderTimeout`; snapshot includes new fields with mocked probe; eval with mock evaluator round-trips JSON; eval with bridge-vs-format mismatch writes `bridgeMismatch` error file.
- `DebugSnapshotTests` extension — schema version 2, new fields encode/decode, partial[] correctness for new fields, `renderPhase` wire value normalized to `"idle"` (test names using `"settled"` updated).
- `DebugFixtureCatalogTests` extension — every format covered (assert at least one fixture per `BookFormat` case the catalog should support).

## Sequencing

Each WI: RED test first, then GREEN, then REFACTOR. Each WI ships in its own PR with version bump (per `.claude/rules/40-version-bump.md`). Per-PR audit per `.claude/rules/47-feature-workflow.md` Gate 4.

| WI | Title | Files touched | PR size |
|----|-------|--------------|---------|
| 0 | **Grammar reconciliation**: top-of-file DocC update + regression test asserting `position` is canonical and `?cfi=` is rejected. | `DebugCommand.swift`, `DebugCommandTests.swift` | trivial |
| 1 | **Snapshot schema v2**: bump `currentSchemaVersion`, add the new optional fields (`ttsState`, `ttsOffsetUTF16`, `selection` populated, `settingsProvenance`), normalize `renderPhase` wire value to `"idle"`. Probe protocol gains the corresponding `current*` methods with default implementations. Add `TTSService.State.publicName` DEBUG-only extension. No production wiring beyond the schema + probe protocol. | `DebugSnapshot.swift`, `DebugReaderRegistry.swift`, `TTSService.swift`, `DebugSnapshotTests.swift`, `RealDebugBridgeContextTests.swift` (snapshot tests adapted; renderPhase test names normalized). | small |
| 2 | **Per-format settle hooks (TXT/MD)**: TXT/MD reader hosts + bridges expose a `onLayoutCompleted` callback. `ReaderContainerView` populates `probe.settleStrategy` with a continuation that resolves on first `atEnd: true`. Tests using a mock layout manager. | `TXTReaderHost`/`MDReaderHost` (in `ReaderFormatHosts.swift`), `TXTTextViewBridge.swift`, `MDTextViewBridge.swift`, `ReaderContainerView.swift`, `RealDebugBridgeContextTests.swift`. | medium |
| 3 | **Per-format settle hooks (EPUB)**: `EPUBWebViewBridge` injects render-committed JS and exposes `onRenderCommitted`. `EPUBReaderHost` wires `probe.settleStrategy` and `probe.renderPhaseProvider`. Tests for the JS string shape + the coordinator routing. | `EPUBWebViewBridge.swift`, `EPUBReaderHost` (in `ReaderFormatHosts.swift`), `ReaderContainerView.swift`, EPUB bridge tests. | medium |
| 4 | **Per-format settle hooks (AZW3 via `FoliateSpikeView`)**: spike adds `onRenderCommitted`, the Coordinator routes `book-ready` (first-paint latch) and adds the previously-absent `relocate` handler with the **arming protocol** (armed/armedTargetCFI/armedDeadline). Container-arm in `ReaderContainerView.nativeReaderView` wraps the spike to wire DEBUG callbacks. Tests via the existing message-handler test pattern + arming-state unit tests. | `FoliateSpikeView.swift`, `ReaderContainerView.swift`, new `FoliateSpikeViewArmingTests.swift`. | medium |
| 5 | **Per-format settle hooks (PDF)**: PDF host wires settle to first-non-zero `documentView.bounds` + `PDFDocumentDidLoadNotification`. Tests via mock PDFView. | `PDFReaderHost` (in `ReaderFormatHosts.swift`), `PDFViewBridge.swift`, `ReaderContainerView.swift`. | medium |
| 6 | **Live `eval` evaluator (EPUB + AZW3-Foliate)**: `EPUBWebViewBridge` and `FoliateSpikeView` expose `onWebViewReady`. Hosts populate `probe.jsEvaluator` with the `JSON.stringify`-wrapped evaluator. Add `DebugBridgeFormatBridgeMap` + bridge-vs-format validation in `RealDebugBridgeContext+Eval.swift`. Tests assert the JS wrapper shape, that thrown JS errors land as `__vreaderError`, and that mismatched `bridge=` writes `bridgeMismatch`. | `EPUBWebViewBridge.swift`, `FoliateSpikeView.swift`, `EPUBReaderHost`, `ReaderContainerView.swift` (azw3 case-arm), `DebugBridgeFormatBridgeMap.swift` (NEW), `RealDebugBridgeContext.swift` → `RealDebugBridgeContext+Eval.swift` (NEW), `RealDebugBridgeContextTests.swift`. | large |
| 7 | **`open?position=` resolution + `awaitReader`**: `DebugPositionResolver` (pure parser) + `DebugPositionFormatter`. `DebugReaderRegistry.awaitReader(fingerprintKey:timeout:)` replaces v1 `awaitNextRegister`. `RealDebugBridgeContext.open` calls resolver, awaits keyed reader, calls `probe.seek(to:)`. Each reader's host populates `probe.seekStrategy`. Tests for resolver per format + `awaitReader` 5-case matrix + integration test for open→seek with a mock probe + native-vs-unified guard. | `DebugPositionResolver.swift` (NEW), `DebugReaderProbeAdapter.swift`, `DebugReaderRegistry.swift` (`awaitReader`), `DebugBridge.swift` (`stableErrorMessage`), `RealDebugBridgeContext.swift`, all four format hosts (`seekStrategy` capture). | large |
| 8 | **Snapshot enrichment wiring**: hosts populate the new providers (TTS state, TTS offset, selection, render phase, settings provenance) and `RealDebugBridgeContext.snapshot` writes them. Tests assert each field populated under each scenario. | `RealDebugBridgeContext+Snapshot.swift` (NEW — extracted in same WI), `ReaderContainerView.swift`, four format hosts. | medium |
| 9 | **Fixture catalog expansion + Debug-only build-phase script**: add `alice.epub`, `sample.pdf`, `sample.azw3`, `cjk.txt`. Update `DebugFixtureCatalog.entries`. Add `project.yml` build-phase script that copies fixtures only in Debug. Run `verify-release-no-debugbridge.sh` against a Release build, attach output to PR. **Does NOT fix the pre-existing `war-and-peace.txt` Release leak — that's a separate bug filed by the calling agent.** | `DebugFixtureCatalog.swift`, `project.yml`, `vreader.xcodeproj/project.pbxproj` (regenerated), `vreader/Resources/DebugFixtures/` (new files), `DebugFixtureCatalogTests.swift`. | medium |
| 10 | **`docs/architecture.md` + `docs/manual-test-checklist.md` updates**: document the new probe surface, fixture-loading recipe, and the verification entry points unlocked. Mark feature #48 → `DONE` (then `VERIFIED` after Gate 5 pass). | `docs/architecture.md`, `docs/manual-test-checklist.md`, `docs/features.md`. | small |

**Critical path**: 0 → 1 → 7 (open/seek/awaitReader) and 1 → 8 (snapshot enrichment) are independent of 2-6 (per-format settle/eval). 9 (fixtures) blocks #45's verification flows but not anything inside #48. 10 closes the feature.

**Parallelization**: WIs 2-5 (per-format settle hooks) can ship in parallel — different files. WI-6 depends on the `onWebViewReady` plumbing landing in WIs 3 and 4 (EPUB / FoliateSpikeView); ship 6 after 3 and 4.

### Recommendation re feature scope

Sized this way, #48 is 11 WIs — at the upper end of what `47-feature-workflow.md` calls a "Large" feature. Per that rule's guidance: "If a feature is genuinely 10+ WIs, consider whether the plan should split into multiple features."

I considered splitting along two natural axes:

1. **Split eval into its own feature.** Considered and rejected above (Prior art section). The eval surface fits cleanly inside one WI per host.
2. **Split fixture catalog into its own feature.** Tempting because it's a different concern (tooling/build) from the probe completion (runtime). But the build-phase script is small and ships only once; carrying it inside #48 keeps the audit/review surface coherent ("here's everything #45 needs").

**Final recommendation: keep as one feature** but treat WIs 2-5 (per-format settle) as a "batch" — the audit can review them together since they share the same pattern (closure injection from host) and only differ in which format-specific layout hook is used. That collapses the audit cost from 4 PR audits to 1 and makes the actual work in #48 closer to "8 audited PRs" than 11.

If the audit pushes back on the size, the cleanest split is: **#48a = WIs 0, 1, 7, 8, 10** (the probe protocol + open/seek + snapshot enrichment + docs); **#48b = WIs 2-6, 9** (per-format hooks + fixtures). 48a is small and unblocks the snapshot tests; 48b is the bulkier behavior work.

## Risks + mitigations

| Risk | Mitigation |
|------|-----------|
| TextKit `layoutManager(_:didCompleteLayoutFor:atEnd:)` doesn't fire on every visible-frame change — only on layout invalidations. For TXT settle-after-seek to be deterministic, we may need a different signal (e.g., `setContentOffset` completion). | WI-2 starts with the TextKit delegate hook; if tests show false-stable signals, fall back to listening on `UIScrollViewDelegate.scrollViewDidEndScrollingAnimation`. Document the chosen signal in the host file's comment. |
| `requestAnimationFrame`-based render-committed signal in EPUB might fire before the final paged-mode column layout settles. | Test by injecting a deliberately slow CSS pagination and asserting the snapshot's `position` is non-nil after `settle`. If false, the JS waits a third `requestAnimationFrame` after `setTimeout(_, 0)` to give layout one more pass. |
| `awaitReader` race with reader teardown: a stale reader unregister + new register interleaves with the awaiter. | Tests cover the unregister-while-awaiting case (waiter persists); register matching by `fingerprintKey` (not "next register") makes this deterministic. |
| `seekStrategy` for TXT requires the ViewModel's `seek(toCharOffset:)` to exist. Some readers may not have a sync seek. | WI-7 reads each ViewModel before writing the probe wiring. If a seek API is missing, file as a precondition WI (e.g., WI-7-pre adds `seek(to:)` to the ViewModel) and audit it before #48. |
| Build-phase script doesn't fire in incremental builds because `inputFiles` is wrong. | Test by switching configurations + clean-build; verify the `DebugFixtures/` directory presence. If incremental flakiness shows up, set `outputFiles` too so Xcode tracks the dependency. |
| `JSON.stringify` wrapper for eval may swallow user JS that itself contains `})()` inside a string literal. | The wrapper uses an immediately-invoked function expression; user JS is the `return (...)` argument. Strings inside user JS are safe — they're inside the inner function body. Add a regression test with a payload like `js = "'/* })() */ '"`. |
| TTSService's offset → sentence index mapping is non-trivial (no existing `currentSentenceIndex` field). | **Resolved by carving out** — #48 ships only `ttsOffsetUTF16`. Sentence-index needs separate planning with explicit tokenizer semantics. |
| Mid-PR a Codex audit reveals the per-format hooks need protocol shape changes that ripple back through WI-1 (snapshot v2). | Each WI's PR audit is the firewall. WI-1 ships the schema; if a later WI needs a v3, that's a separate PR. The probe protocol's default implementations protect old adapters from breakage. |
| `EPUBHighlightBridge.selectionTrackingJS` already posts to `selectionChanged` channel — the new selection probe must read the bridge's cached selection without double-handling the message. | The host's selection cache is updated by the existing `selectionChanged` handler; `probe.selectionProvider` reads the cache. No new message channel. |
| `FoliateSpikeView` Coordinator currently doesn't handle the `relocate` channel — adding it might accidentally break existing AZW3 behavior. | WI-4 adds the `relocate` arm strictly as DEBUG-only behavior wrapped in `#if DEBUG`; non-DEBUG builds don't touch the new code path. The `relocate` channel was already added to `userContentController`, just not switched on — so the message was being silently dropped, not crashing. |
| Foliate spontaneous `relocate` events between arming and the seek's actual relocate. | **Resolved by accepting the limitation (v3 Round-2 Fix #4, Option B):** `open?position=` for AZW3 is only supported from a clean reader state. Concretely: a `position=` seek must not be issued within 500ms of any prior interactive seek (user tap, programmatic navigation, reader-resume scroll). Verification flows always begin with `vreader-debug://reset` (which destroys the reader and tears down all Foliate state), so they never hit this case. The arming protocol still resolves the post-seek `relocate` correctly because there are no spontaneous relocates pending after a fresh load. Sequence-number disambiguation (Option A) was considered and deferred — its cost (sequence-number stamping in JS, predicate matching on every relocate) outweighs its benefit while the only consumer is verification flows that already start from `reset`. If a future consumer needs interleaved seek tolerance, file as a follow-up feature; the data WI-4 logs (arming + relocate pairs) will inform the design. |
| Release verifier is not currently CI-gated — fix in WI-9 may regress silently if the next person doesn't run the script. | WI-9 also adds a one-line GitHub Actions step that runs the verifier post-Release-build. If the repo doesn't have GH Actions set up for vreader, the WI uses a `Run Script` build phase route as a tighter alternative (the verifier itself becomes a Release-only build phase). |

## Backward compat

Three scenarios:

1. **Old DEBUG harness (pre-#48) → new build.** Snapshot schema bumped 1 → 2; consumers that pin v1 get a snapshot they don't recognize. Mitigation: schema version is published in the JSON; consumers must check before reading new fields. Since the only consumer today is humans reading by hand, no action needed beyond the bump.
2. **New DEBUG harness → no active reader.** Probe protocol's default methods return nil/`"unknown"`; snapshot's `partial[]` lists every reader-derived field. Same as today.
3. **Release build.** Zero new symbols leak — every new file is `#if DEBUG`-gated, the new probe-protocol additions are inside the existing `#if DEBUG` block in `DebugReaderRegistry.swift`. Verifier passes after WI-9 (for the *new* fixtures; the pre-existing `war-and-peace.txt` leak remains until the separate bug PR lands).

The `cfi` parameter rename was completed in #44 already (parser uses `position`); WI-0 just fixes the stale DocC. No live caller uses `cfi`.

## Open questions (for next Codex audit round)

1. **Build-phase script idempotency** — **resolved in v3 Round-2 Fix #5b.** `rsync -a` is idempotent and doesn't fail on empty source; `inputFiles` references the parent `DebugFixtures/` directory so Xcode invalidates the phase when any fixture changes. WI-9 still empirically validates by switching configurations + clean-build; if incremental flakiness shows up, the fallback is an explicit sentinel `outputFiles` entry (documented in the WI-9 stanza).
2. **TTS sentence index** (carved out, recorded for follow-up). Should `ttsCurrentSentenceIndex` ship in a follow-up gated by #45 actually needing it? If yes, what's the tokenizer policy (BCP-47-aware? CJK-aware?)? Suggest: defer; pick semantics when #45 specifies the verification flow that needs it.
3. **`open?position=` for the unified renderer** (carved out). Confirmed native-mode-only in #48. Is that scoping acceptable to #45? Suggest: yes, native-mode is the higher-fidelity rendering path that verification cares about.
4. **`awaitReader` timeout default.** 10s assumes worst-case device launch + reader navigation. Confirm against device measurements or accept 10s as a conservative starting point.
5. **Foliate post-seek `relocate` arming** — **resolved in v3 Round-2 (Option B).** `open?position=` for AZW3 only supports clean-reader-state seeks (no prior interactive seek within 500ms of arming). Verification flows always begin with `vreader-debug://reset`, so this is invisible in practice. WI-4 still logs arming + relocate pairs so future consumers (if any) can revisit the limitation with empirical data; the sequence-number disambiguation alternative (Option A) is deferred until a real consumer hits the limitation.
6. **Eval target for non-webview readers** — **resolved in v3 Round-2 Fix #5a; file path corrected in v4.** Unknown `bridge` value (anything not in `DebugBridgeFormatBridgeMap.knownBridges`, e.g. `bridge=banana`, `bridge=txt`, `bridge=pdf`) writes `evalUnsupported(bridge: <name>)` to `Caches/DebugBridge/eval-<bridge>.json` (the existing convention used by the live `RealDebugBridgeContext.eval`; `DebugCommand.eval` has no `dest=` parameter). The error JSON payload includes the list of known bridges for diagnostics. See "Live `eval` evaluator" design decision for the file shape.
7. **Snapshot schema migration story.** Bumping `currentSchemaVersion` 1 → 2 is the chosen approach; consumers re-read the version field. Alternative was a `v2` sub-object; rejected because no live consumer needs v1 stability.
8. **WI-6 (eval) test strategy.** Mock-WKWebView is harder than mocking other classes; tests today route through `DebugReaderProbeAdapter.jsEvaluator` closure which is already injectable. Closure-level testing is sufficient for the wrapper logic; a real-WebView integration test rides on the manual-test-checklist (WI-10).
9. **`seekStrategy` failure mode.** Should it be fatal to `open` (current plan: throw `seekFailed`), or best-effort (open succeeds, seek failure logged but bridge.lastError unset)? The verification flows want loud failure; defaulting to fatal seems right but flagging.
10. **Settings provenance granularity.** `"global"` vs `"per-book"` is binary. Per-book settings are a partial overlay (some fields per-book, others fall back to global). Should provenance be per-field instead? Suggest: binary for #48, per-field if #45 needs it.

## Acceptance gate

This plan (v4) covers feature **#49 only** (resolver / registry / `open` / snapshot wiring; per-format host work moved to #50). Per the audit-cap escalation, Round 3's split recommendation was accepted in PR #170; v4 applies the six surface fixes Codex flagged in Round 3 without re-opening scope. Implementation may begin against this v4 once #49's Gate 2 is recorded.

After implementation, Gate 4 (per-PR audit) and Gate 5 (slice verification per WI; full acceptance pass on the final WI of #49 — verified against the success-bar URL sequence from the Goal section against a fresh simulator install).

## Audit reference

- **Codex Round 1 (Gate 2, 2026-05-03):** findings codified in "Audit fixes applied — Round 1" table. v2 of the plan addressed every Critical and High finding; Low findings (test count, file path, renderPhase naming) folded into the surface area + WI-1 acceptance criteria.
- **Codex Round 2 (Gate 2, 2026-05-03):** findings codified in "Audit fixes applied — Round 2" table at top of this doc. v3 addresses all five Round-2 findings: (1) `awaitReader` waiter ownership now uses UUID tokens; (2) DEBUG-only `wireDebugProbe` parameter formalized on every reader host with per-host callback contract; (3) `open(bookId:position:)` validates fully before posting `.debugBridgeOpenBook`; (4) Foliate post-seek limitation accepted (Option B — clean-reader-state only, verification flows always start from `reset`); (5) unknown `bridge` writes `evalUnsupported(bridge:)` with `knownBridges` list, build-phase script uses idempotent `rsync -a` with parent-directory `inputFiles`. Open questions reduced from 10 to ~7 (3 Round-2 questions resolved inline).
- **Codex Round 3 (Gate 2, 2026-05-03) — audit cap reached, split accepted in PR #170.** Round 3 returned six compile-correctness surface findings (continuation type, registry weak/strong consistency, `open()` references against actual types, `positionProvider` live-read, eval file path, status line). v4 applies them as surgical edits without re-revising Round-2 design decisions or pulling per-format host work back into scope. Per the workflow rule's audit-cap clause, v4 is the user's final say — it does not go through Round 4. Per-format work tracks separately under #50.
