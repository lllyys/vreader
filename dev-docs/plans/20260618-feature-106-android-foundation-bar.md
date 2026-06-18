# Feature #106 — Android Phase 2: foundation bar (the first real `android/` app)

Status: Gate-1 draft (2026-06-18). The deferred Android-port epic, unblocked now
that Spike A (#104, identity) + Spike B (#105, Readium-Kotlin scroll) + #107
(dev-loop tooling) are all VERIFIED. Source of truth:
`docs/decisions/0001-android-port-strategy.md` (ADR-0001 Phase 2).

## Problem / reach (the "foundation bar", NOT EPUB parity)

Stand up the first real Android app and reach a **foundation bar**, then switch
to steady state (iOS-leads-Android-follows). The bar (ADR Phase 2):

1. **Import / open / resume ONE EPUB slice** end-to-end on a real emulator
   (Readium-Kotlin reader; resume to progression precision).
2. **The `contracts/` conformance lane alive in Kotlin** — the shared
   identity/locator golden vectors run against the Android impl in CI/local (the
   #104/#107 conformance harness, now consumed by app code).
3. **Release / version plumbing alive** — `android/version.properties`
   (`versionName`/`versionCode`) + the `android/vX.Y.Z` tag lane (rule 40).
4. **A minimally-automatable verification story** — the `am instrument` lane via
   `scripts/run-android-verify.sh` (#107), the Spike-B precedent.

Explicitly NOT in scope: AZW3/Kindle, PDF/TXT/MD, AI, TTS, book sources, backup
UI, full library management, the visual-identity design system. Those are Phase 3
(`docs/parity/` ledger), decomposed after this bar lands.

## Verified spike constraints (the toolchain — from #104/#105, VERIFIED)

- **Readium-Kotlin 3.3.0** consumed on **AGP 8.13.2 / Kotlin 2.3.20 / compileSdk
  36 + mandatory core-library desugaring** (Spike B finding). Scroll mode VIABLE
  (60fps, bounded eviction ~1.1GB high-water on a 1000+-spine CJK novel).
- **Identity = exact-match** native fingerprint / cache-key /
  `Locator.canonicalJSON` (Spike A); converted-Kindle = source-bytes (not in this
  EPUB slice). The Kotlin `CanonicalLocator` reference already exists in the
  conformance harness — the app's locator store keys on it.
- Cron CAN drive the emulator (`am instrument`) — the verification lane.

## Surface area (file-by-file) — WI sequencing

Per ADR reuse-leverage order: app shell → identity/conformance → persistence →
import/storage → reader → resume → release. **Gate-2 round 1 re-split the
oversized WIs** (was 5, now 7) so each is one focused PR.

| WI | Scope | Tier | Size |
|---|---|---|---|
| WI-1 | **Gradle app shell**: root `settings.gradle.kts` + `android/app` module. **Pin the FULL Spike-B-verified toolchain**: AGP 8.13.2 / Kotlin 2.3.20 / **Gradle 8.14.4** / **JDK 17** / compileSdk 36 / minSdk 26 + mandatory core-library desugaring. `android/version.properties` (`versionName`/`versionCode`). Compose `MainActivity` + empty "Library" screen. JUnit5 + Robolectric wiring + a smoke unit test driven by `scripts/run-android-tests.sh :app:testDebugUnitTest`. | foundational | Medium |
| WI-2 | **Shared identity/locator module + conformance (Gate-2 High-1 + r2-Medium)**: extract `DocumentFingerprint` + `Locator`/`canonicalJSON`/`canonicalHash` **+ the `VReaderLocator` envelope** into a `:identity` module. **Build topology (binding)**: `:identity` is a **pure Kotlin/JVM** module — NO `:app`/Android/Readium deps — so it compiles in both the Android app build AND a plain-JVM context. **Rewire `contracts/conformance/kotlin` to consume `:identity` from the root/composite Gradle build (not its own standalone JVM build), pin it to the SAME Kotlin/JDK toolchain as `:app`, and DELETE the now-duplicate reference impl** under `contracts/conformance/kotlin` — otherwise the lane false-greens on non-app code again. Extend the shared vectors to cover the persisted envelope shape (`readiumLocatorJSON` + engine + canonical fallback Locator), not just canonical Locator JSON. Unit + conformance tests, both against `:identity`. | behavioral | Medium |
| WI-3 | **Room persistence**: `BookEntity` + `ReadingPositionEntity` (storing the `VReaderLocator` envelope, NOT a bare Locator — Gate-2 Critical) + DAOs (the `PersistenceActor` analog) + repository returning DTOs; schema-versioned `Migration` scaffold. In-memory-Room tests + a migration round-trip test. | behavioral (persistence) | Medium |
| WI-4 | **EPUB import → app-private storage (Gate-2 High-2)**: SAF `OpenDocument` → **copy the bytes into app-private storage immediately** → fingerprint the LOCAL artifact (exact-match) → store `BookEntity` + keep the source URI as separate metadata. ~~Compose Library list.~~ **Test: import → process restart → reopen from app-private storage** (cold-start identity holds). | behavioral | Medium |
| WI-5 | **EPUB reader host + open**: Readium `EPUBNavigatorFragment` (scroll mode, per Spike B) in a Compose host; open the stored publication from app-private storage. ~~Instrumented open test on the emulator.~~ Plumbing only: the **publication opener** (Readium Streamer opens the stored EPUB → `Publication`) + a JVM open/metadata test. | behavioral | Medium |
| WI-6 | **Resume + process-death (Gate-2 Critical + Medium)**: on `locationDidChange` save the `VReaderLocator` envelope (Readium `Locator` JSON + canonical fallback) → Room. Restore **precise-first / canonical-fallback-second**. Acceptance bar = the **Spike-B-proven window** (resource/progression precision; scroll-mode `currentLocator` is ~2-paragraph-coarse on CJK, NOT within-chapter exact — do not over-claim). Plumbing: the **Readium-`Locator` ↔ `VReaderLocator` bridge** + Room save/restore + unit tests; the `locationDidChange` wiring + config-change/process-death recovery ride with the reader-host design. | behavioral | Large |

### Design-blocked surfaces (rule 51 — user-directed 2026-06-18)

Per a user decision (strict rule 51), the **visible** Android surfaces are NOT
self-designed; they wait for `claude.ai/design` bundles. Only the **non-UI
plumbing** of WI-4/5/6 ships now. Blocked slices:

- **Android Library list + import affordance** — `BLOCKED: needs-design (#1744)`.
  WI-4 ships the import/fingerprint/storage engine + identity test; the list
  rendering + SAF-launch button wait for the design.
- **Android reader host chrome** — `BLOCKED: needs-design (#1745)`. WI-5/6 ship
  the publication opener + locator bridge + Room save/restore + unit tests; the
  reader screen + `locationDidChange`/process-death wiring wait for the design.

The Android visual-identity system was already Phase 3 (out of this bar's scope);
this just makes the foundation-bar UI surfaces explicitly design-gated too.
| WI-7 (final) | **Release plumbing + app verify lane**: `android/vX.Y.Z` tag lane (rule 40); **wire the app's instrumentation command into `scripts/run-android-verify.sh`** (today it's a spike wrapper — Gate-2 Medium) + define the post-#106 evidence recipe; `docs/parity/` ledger seeded; README/architecture Android sections. Full foundation-bar acceptance pass (import→open→resume one real EPUB on the emulator). | behavioral (final) | Medium |

### Files OUT of scope (Phase 3, separate features)
AZW3/PDF/TXT/MD readers, AI/TTS/book-sources/backup, full library UI, the design
system, iOS code (write-isolation — rule 48: Android agents never touch
`vreader/`).

## Prior art / precedent
- Spike B harness (`spikes/android-reader-bench/`) — the Readium-Kotlin scroll +
  emulator-instrumentation precedent; WI-3/WI-4 lift its Gradle/Readium wiring.
- The `contracts/` conformance lane (#104/#107) — the Kotlin identity reference +
  golden vectors WI-2 consumes.
- iOS `PersistenceActor`/`Locator`/`BookImporter` — the architecture WI-2/WI-3
  mirror (Room = SwiftData, coroutines = actor — rule 50 §12).

## Risks + mitigations
- **R1 — toolchain drift** (AGP/Kotlin/Readium versions): pin exactly to the
  Spike-B-verified set; CI uses the same.
- **R2 — emulator flakiness in CI/cron**: the `am instrument` lane + watchdog
  (`run-android-tests.sh`) + ghost-sweep (#107) bound it; verification is
  instrumentation-first (no UI automation), the Spike-B pattern.
- **R3 — scope creep into Phase 3**: the bar is ONE EPUB slice; anything beyond
  is a separate `docs/parity/` row.
- **R4 — identity divergence**: WI-2's conformance lane is the guard — the app
  types MUST match the shared vectors before WI-3 keys storage on them.

## Backward compat
New `android/` app; no iOS impact (write-isolation). The `android/vX.Y.Z` tag
namespace is additive (iOS plain `vX.Y.Z` unchanged, rule 40).

## Acceptance criteria (the foundation bar)
1. `android/app` builds (full pinned toolchain incl. JDK 17 / Gradle 8.14.4) +
   `:app:testDebugUnitTest` green via `scripts/run-android-tests.sh`.
2. The `contracts/` conformance lane runs against the shared `:identity` module
   that `:app` ALSO depends on (proves app code, not a reference) — green
   exact-match parity with iOS, incl. the persisted `VReaderLocator` envelope
   shape.
3. Import a real EPUB → bytes copied to app-private storage → it appears in the
   Library keyed by the exact-match fingerprint of the LOCAL artifact; survives a
   process restart (cold reopen from app-private storage).
4. Open in the Readium scroll reader; read; close; reopen → resumes to the saved
   position at the **Spike-B-proven window** (resource/progression precision; not
   claimed within-chapter-exact). Restore is precise-first / canonical-fallback.
5. Config-change / process-death recovers the current book + last position.
6. `android/version.properties` + an `android/vX.Y.Z` tag are produced; the app's
   instrumentation command is wired into `scripts/run-android-verify.sh`.
7. The whole flow is verifiable via `scripts/run-android-verify.sh` (am
   instrument), recorded in `dev-docs/verification/feature-106-*.md`.

## Revision history
- v1 (2026-06-18) — Gate-1 draft. Foundation-bar scope per ADR Phase 2; 5 WIs.
- v2 (2026-06-18) — Gate-2 round 1 (Codex) applied. Toolchain claims VERIFIED
  against Spike B (Readium 3.3.0 / AGP 8.13.2 / Kotlin 2.3.20 / compileSdk 36 /
  minSdk 26 / desugaring); conformance reference + vectors + `run-android-verify.sh`
  confirmed real. Fixes: **Critical** — persist the `VReaderLocator` ENVELOPE
  (readiumLocatorJSON + engine + canonical fallback), not a bare Locator; resume
  bar lowered to the Spike-B-proven resource/progression window (scroll
  `currentLocator` is ~2-para-coarse, not within-chapter exact). **High** — make
  the conformance lane prove APP code: extract a shared `:identity` module both
  `:app` and the conformance tests depend on; extend vectors to the persisted
  envelope. **High** — WI-4 import now SAF→copy-to-app-private-storage→fingerprint
  the local artifact + source-URI metadata, with an import→restart→reopen test.
  **Medium** — pin JDK 17 + Gradle 8.14.4 in WI-1; conformance becomes a shared
  module. **Medium** — re-split 5→7 WIs (identity/conformance, Room, import,
  reader, resume/process-death now separate). **Medium** — WI-7 wires the app's
  instrumentation into the verify wrapper (not "already exists"). **Medium** —
  added config-change/process-death recovery tests to WI-6.
- v3 (2026-06-18) — Gate-2 round 2 applied (Critical + both Highs confirmed
  resolved; SAF identity model + 7-WI split + Spike-B resume bar confirmed sound).
  Last **Medium** — `:identity` build topology underspecified: WI-2 now mandates
  it be a **pure Kotlin/JVM** module (no Android/Readium deps), the
  `contracts/conformance/kotlin` lane REWIRED to consume it from the composite
  Gradle build (same Kotlin/JDK toolchain) with the duplicate reference impl
  deleted — so the lane proves `:identity` (app code), not a standalone reference.
  **Gate-2 CLEAN** (the prescribed fix incorporated; no Critical/High open).
