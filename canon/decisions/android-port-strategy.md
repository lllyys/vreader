---
title: Decision — Android port strategy
updated: 2026-07-10
status: proposed
---

# Decision — Android port strategy

## The decision

ADR-0001 (`docs/decisions/0001-android-port-strategy.md`, status **Accepted 2026-06-16**; method: Claude recommendation + **three** independent Codex audits, `gpt-5.4` high effort, under Gate-2 author/auditor separation), indexed per the append-only-supersession policy in `docs/decisions/README.md`:

1. **Build Android natively (Kotlin + Jetpack Compose); keep the iOS app native and untouched.** No uni-app/Flutter/webview-everything rewrite.
2. **One repo (monorepo)** — conditional on iOS↔Android library/backup interop being a hard requirement (it is: content-hash dedup + WebDAV materializing restore, "your library follows you across devices").
3. **`android/` as a sibling of `vreader/`; do NOT reorganize iOS under `ios/`** — a path-move would collide with the hot agent cron. The asymmetric layout (iOS at root, Android in a subdir) is the deliberate pragmatic call, mirrored by the tag asymmetry.

**Flip condition**: if Android is ever a standalone product with no shared library/backup interop → separate repos + a tiny shared contracts package (a git submodule is explicitly the wrong form for an agent cron — pointer drift, detached-HEAD).

## Rationale

- **Against cross-platform rewrite**: it discards a mature native iOS app (hundreds of triaged bugs, Readium Swift navigator, PDFKit, TextKit, SwiftData) and replaces it with a weaker runtime exactly where vreader is hardest — windowed continuous scroll on 1000+-spine CJK novels, memory/eviction, CFI anchoring, selection gestures, large-file performance. (If scope were simplified, Flutter beats uni-app for this class — but that is a different, smaller product.)
- **A real port, not free reuse**: effort reuse estimated **~40–55%, not 60–70%** — the hard 20% (continuous scroll, eviction, anchor restore, selection, storage, background, verification) is where reuse is weakest. Load-bearing reuse: `readium/kotlin-toolkit` 3.3.0 (vs Swift 3.9.0). KMP (shared Kotlin core) deferred — it would force migrating the stable Swift business layer.
- **The audits' real corrections** (what made it hard): "one writer per area" doesn't hold as stated — `AGENTS.md`, `.claude/`, trackers, designs, `contracts/`, release docs are the shared contended surfaces; the automation layer was iOS-shaped and filename-specific ("grow, don't fork" is the wrong instinct — make `.claude/` path-scoped); **tag namespace was the biggest miss** — decided: iOS keeps plain `vX.Y.Z` unchanged (no retag of `v3.66.x` history), Android uses `android/vX.Y.Z` (rule 40 "Multi-platform" owns the routing table); single-status trackers can't model "done on iOS, planned on Android" → parity in a **separate ledger** (`docs/parity/`), never per-platform tuples in the trackers; secrets/signing understated; the conformance corpus has a legal problem (derived vectors check in, Kindle source bytes never).

## Risks and how they resolved

1. **Deterministic cross-platform identity** (Risk 1) — **RESOLVED by Spike A #104** (`contracts/identity/DECISION.md`): converted-Kindle canonical identity = the **SOURCE file bytes** (converter-independent; iOS's converted-EPUB fingerprint is platform-local), and the engine-neutral `Locator.canonicalJSON` round-trips byte-identically Swift↔Kotlin. The standing gate is `contracts/conformance/run.sh` (see [[Module — cross-platform contracts]]).
2. **Android WebView reader hardening** (Risk 2) — **RESOLVED by Spike B #105** (VERIFIED 2026-06-17, evidence `dev-docs/verification/feature-105-20260617.md`): Readium-Kotlin 3.3.0 scroll mode is **VIABLE** on the real 1042-chapter 道诡异仙 CJK book on the android-35 arm64 emulator — 60fps (0.23% jank), bounded renderer memory (~1.1GB high-water receding to a 580–870MB oscillation, no OOM), zero renderer crashes, chapter-level restore + Locator JSON + selection round-trip. Also proved the cron CAN drive an emulator end-to-end (`am instrument`); the minimally-automatable lane is `spikes/android-reader-bench/run-bench.sh`. Two recorded Phase-3 hardening obligations (not blockers): validate the ~1.1GB high-water on a 3–4GB device; fragment-level restore is ~2-paragraph-approximate on CJK.
3. **Android platform semantics** — design around Scoped Storage + SAF (import into app-private storage immediately, keep source-URI metadata separately — implemented in `BookImporter`) and WorkManager + foreground-service for whole-book translation (still ahead; bilingual is checklist item D).

## Sequencing (audit-corrected) and how it played out

Three required pre-start changes: (1) **Phase 0 = safety plumbing only** — path-scoped gate routing (the day-1 blocker: `check_codex_audit_artifact.sh` treated only `vreader/`+`vreaderTests/` as code, so an `android/` PR would have bypassed Gate 4 as docs-only), per-platform version/tag policy, write-prefix isolation (rule 48); (2) **versioned contract merge gate** — breaking = both platforms green, additive = one green + filed parity obligation; (3) **parity in a separate ledger**, never tracker tuples.

Executed as: Phase 0 = feature #103 (VERIFIED); Phase 1 spikes = #104 (identity) + #105 (CJK benchmark, instrumentation-first — NOT UI-automation-dependent, because the verification stack was iOS-specific); Phase 1.5 = #107 dev-loop readiness (`scripts/run-android-tests.sh` / `run-android-verify.sh`, platform routing in `code_paths_platform`); Phase 2 = #106 **foundation bar** (not "EPUB parity"): import/open/resume one EPUB + the conformance lane alive + release plumbing alive + a minimally-automatable verification story — VERIFIED at `android/v0.3.0`; Phase 3 = catch-up in reuse-leverage order under the #110 program driver, whose finite definition of parity is `docs/parity/android-checklist.md` (feature #110 was re-scoped from an unbounded driver to a checkable box list). The umbrella row #102 closed **DONE 2026-06-18 by decomposition** — Phase-3 parity is explicitly NOT open work on that row. Delivery record: [[Module — Android port]].

## Steady state ("one product spec, two tracks")

Plan once (platform-agnostic spec + one design bundle + identified contract changes), but a per-platform implementation delta still gets its own Gate-2 audit ([[Decision — six-gate workflow and lane dispatch]]). **Default mode = iOS leads, Android follows** for user-facing features; strict parity is reserved for identity/locator/backup/schema surfaces only (strict-by-default would make Android the release brake). Design: one bundle, two implementations — the handoff must mark shared invariants vs allowed platform-native divergence (in practice, #106 established that iOS `vreader-fidelity-v1` bundles reuse cleanly for Android under rule 51). Assume lower Kotlin/Compose agent fluency → smaller Android WIs.

## Notable post-decision correction

The ADR's AZW3 row ("legacy compat scope only"; libmobi NDK port framed as large/HIGH-risk, initially DEFERRED on a go/no-go) was **overturned by a framing correction** in `docs/parity/android-checklist.md`: iOS does NOT read Kindle books via libmobi — it renders them with foliate-js (`mobi.js`) in a WKWebView (`FoliateSpikeView`, see [[Module — Foliate AZW3 reader]]); libmobi is auxiliary (metadata/cover/convert). So Android's path was a WebView + pinned foliate-js host with a security-first bridge (`WebViewCompat.addWebMessageListener` + `WebViewAssetLoader`, never `addJavascriptInterface`) — no NDK. User go/no-go = **GO** (2026-06-29, "the azw3 is needed"); feature #126 shipped VERIFIED at `android/v0.12.9`.

**Known doc drift**: ADR-0001's own header still reads "Accepted (strategy) — not yet started," which is stale — this dossier's Sequencing and Consequences sections below document extensive post-ADR delivery (#103–#107, #110, #126, through `android/v0.12.9`). Not corrected in the ADR itself per its append-only-supersession policy; noted here instead.

## Consequences

- iOS development unaffected; the cron kept its cadence.
- The shared surface (automation, trackers, contracts) became the maintenance cost center and was made platform-aware FIRST (Phase 0/#107 landed before Android app PRs flowed).
- Release semantics are per-platform: `android/version.properties` (`versionName`/`versionCode`) + `android/vX.Y.Z` tags began with #106, exactly as rule 40 "Multi-platform" specifies.
- If the identity corpus ever cannot be kept cleanly enforceable, the recorded fallback is the flip condition (separate repos + shared contracts package).

**Sources.** [[session 014jggU2u3f3t6YRoPLS457u · 2026-07-10]] · [[session 014jggU2u3f3t6YRoPLS457u-audit · 2026-07-11]]
