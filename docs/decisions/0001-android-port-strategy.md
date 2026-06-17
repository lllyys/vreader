# ADR-0001 — Android port: native app, monorepo, shared-identity conformance lane

- **Status:** Accepted (strategy) — not yet started.
- **Date:** 2026-06-16
- **Decides:** how to build an Android version of vreader, and how to house it.
- **Method:** Claude recommendation, **three** independent Codex audits
  (`gpt-5.4`, high effort) under the project's Gate-2 author/auditor-separation
  discipline — (1) native-vs-cross-platform, (2) repo structure, (3)
  implementation sequencing & multi-platform workflow. Verified facts and
  corrections from all three are folded in below.

---

## Decision

1. **Build Android natively (Kotlin + Jetpack Compose). Keep the iOS app native
   and untouched.** Do **not** rewrite both into uni-app, Flutter, or any
   webview-everything cross-platform framework.
2. **One repo (monorepo), not a separate `vreader-android` repo** — *conditional*
   on iOS↔Android library/backup interop being a hard requirement (it is: vreader's
   identity is content-hash dedup + WebDAV materializing restore, "your library
   follows you across devices").
3. **Add `android/` as a sibling of the existing `vreader/` app. Do NOT
   reorganize** the iOS app under an `ios/` directory — a path-move would collide
   with the hot agent cron. The asymmetric layout (iOS at root, Android in a
   subdir) is the right pragmatic call.

### Flip condition

If Android is ever scoped as a **standalone product with no shared
library/backup interop**, prefer **separate repos + a tiny shared contracts
package** instead, and skip the conformance corpus. A git **submodule** is the
wrong form of that shared layer for an agent cron (pointer drift, detached-HEAD,
stale checkouts) — use a published package or a `git subtree` if splitting.

---

## Why not a cross-platform rewrite

"One uni-app for both" discards a mature, deeply-polished native iOS app
(hundreds of triaged bugs, the Readium Swift navigator, PDFKit, TextKit,
SwiftData, background-task + keychain integration) and replaces it with a weaker
runtime — **exactly where vreader is hardest**: windowed continuous scroll on
1000+-spine CJK novels, memory/eviction, CFI anchoring, selection gestures, and
large-file performance. Those were brutal to get right *with* full native control
over the scroll view and gesture system; a cross-platform abstraction on top makes
them harder, and webview-cross-platform perf/memory is its weakest area — our
critical path. If product scope were *simplified* (drop native-Kindle fallback,
ultra-large-scroll hardening, exact locator parity, aggressive offline/background),
cross-platform becomes rational and **Flutter beats uni-app** for this class — but
that is a different, smaller product.

## Why native Android is a real port, not "free reuse"

The engine layer is cross-platform-shaped, but **effort reuse is ~40–55%, not
60–70%** — the hard 20% (continuous scroll, eviction, anchor restore, selection,
storage, background, verification) is where reuse is weakest.

| Layer | Android plan | Verified fact (June 2026) |
|---|---|---|
| **EPUB** | **Readium Kotlin Toolkit** — the load-bearing reuse | `readium/kotlin-toolkit` `3.3.0` vs Swift `3.9.0`; maintained, roughly concept-parity (EPUB/PDF, paginate/scroll/RTL/search/highlights/TTS, `go(Locator)`/`currentLocator`/progression restore) |
| **AZW3/MOBI** | **Legacy compat scope only** — Foliate is a *shrinking* path | Convert-on-import (feature #42) defaults Kindle → EPUB → Readium; only legacy native `.azw3` stays on Foliate. Foliate-js is itself unstable / no published releases; Android System WebView is a more variable target than WKWebView. 1000+-spine CJK perf/CFI parity = **UNVERIFIED** |
| **libmobi convert** | NDK build feasible | LGPL-3.0-or-later, C99, CMake, builds on Android/arm. **But** determinism across platforms is the real constraint (see Risk 1) |
| **PDF** | PDFium via a Kotlin adapter | Readium's `PdfiumAndroid` adapter is free/performant but **currently unmaintained**; PSPDFKit is the robust-but-paid alternative; `AndroidPdfViewer` (Apache-2.0) is downstream of PdfiumAndroid. Maintenance risk higher than first stated |
| **TXT/MD** | Native Compose/Text | Compose is not the main risk; CJK large-text parity for the reader's hardest cases = **UNVERIFIED**, don't decide architecture on it |
| **AI / WebDAV** | Plain HTTP+JSON → reimplement in Kotlin | cheap; reuse the *contract shapes*, not code |
| **Data contracts** | Port the *schemas* (fingerprint, Locator, cache key, backup format) | identity round-trip is **not** guaranteed — see Risk 1 |
| **Chrome / persistence** | Rebuild (Compose; SwiftData → Room) | the cheap, well-trodden parts |

Kotlin Multiplatform (a shared format-agnostic core) is **deferred**: KMP shares
Kotlin *outward*, so sharing today's logic would force migrating the stable Swift
business layer to Kotlin. Extract a thin KMP/contracts core *later* only if
duplication actually hurts.

## The real corrections (from the audits) — what makes this hard

The recommendation was directionally right but undersold the work. The decision is
**not** "one repo or two" — it's: *before the cron touches Android, convert the
iOS-shaped automation layer to platform-aware/path-scoped, and stand up
release-namespacing + a real contracts conformance lane.*

- **"One writer per area" does NOT hold as stated.** Swift vs Kotlin *code* is
  disjoint, but `AGENTS.md`, `.claude/`, the trackers, designs, `contracts/`,
  release docs, and verification evidence are the **shared, contended** surfaces.
- **The automation layer is iOS-shaped and filename-specific.** Hooks
  (`check_gh_issue_mirror.sh`, `check_terminal_status_evidence.sh`), the
  version-bump rule, and `scripts/run-tests.sh` are hard-wired to `docs/bugs.md`,
  `project.yml`, `vreader.xcodeproj`, `xcodebuild`, and the simulator. **"Grow,
  don't fork" is the wrong instinct** — make `.claude/` **path-scoped** (route by
  touched paths; Android-specific entrypoints), not enlarged.
- **Tag namespace is the biggest miss.** A single `vX.Y.Z` tag space (current tags
  are plain `v3.66.x`) does not survive two independently-shippable native apps.
  **DECIDED (feature #103 Phase 0, Gate-2 clean): iOS keeps plain `vX.Y.Z`
  UNCHANGED (no retag of the existing `v3.66.x` history); Android uses
  `android/vX.Y.Z`.** The asymmetry mirrors the directory asymmetry (iOS at
  root, Android in a subdir). Rejected: a unified product version
  (re-couples the two cadences). Authoritative version/tag rule:
  `.claude/rules/40-version-bump.md` ("Multi-platform").
- **Release coupling is broader than the version bump** — commands, skills, audits,
  and merge/close rituals all assume iOS release semantics today.
- **A single platform-tagged tracker will degrade at high PR volume** — single-status
  rows can't model "done on iOS, planned on Android." Expect platform child-rows or
  split trackers once Android volume is real.
- **Secrets/signing is understated** — Android adds keystore/release-signing +
  `google-services`-style files; needs separate secret hygiene from day 1 (the
  existing local `project.pbxproj` signing edit already shows this is live).
- **The conformance corpus has a legal/check-in problem** — if it contains real
  Kindle-derived material it may need a *sanitized* corpus or a private artifact
  store (the `test-books/` fixtures are already gitignored for this reason; golden
  vectors can check in, source Kindle files cannot).
- **No CI config exists in-repo** — path-filtered CI is good advice but unverified;
  CI cost claims are unverified.

## Top risks to de-risk *before* any parity promise

1. **Deterministic cross-platform identity.** `DocumentFingerprint` of a Kindle
   book = hash of the **converted EPUB**, and there is no guarantee Swift vs Kotlin
   Readium emit byte-identical Locators for the same position. → Prove Kindle
   conversion + Readium locator round-trips on a **shared corpus** before promising
   library/backup interop. This is the gate.
2. **Android WebView reader hardening.** Spike on real 1000+-spine CJK books and
   measure scroll smoothness, memory/eviction, renderer stability, CFI/selection
   restore — *before* committing to the WebView-engine plan.
3. **Android platform semantics.** Design import/storage/share/WebDAV/translation
   around **Scoped Storage + SAF** (import into app-private storage immediately;
   keep source-URI metadata separately) and **WorkManager + foreground-service**
   for whole-book translation — not iOS path/background assumptions.

## Day-1 setup (when the port starts)

1. **Path-scoped automation** — keep root policy minimal; add Android-specific
   agent/rule/test entrypoints; route by touched paths instead of teaching every
   prompt both toolchains.
2. **Release namespacing up front** — per-platform version files, per-platform
   bump rules, per-platform tags.
3. **`contracts/` as a real conformance lane** — canonical spec
   (fingerprint/Locator/cache-key/backup-format) + legally-clean corpus / golden
   vectors + **mandatory dual-platform tests on every contracts-touching change**.
   This turns Risk 1 from a hope into a CI gate.

## Implementation & sequencing (audit-corrected)

> The third Codex audit (2026-06-16) corrected the first-cut plan on three points
> that are **required before starting**. They are folded in here. The shape held
> (native, monorepo, spikes-before-app, one-spec-two-tracks) — the edits are about
> not producing **false gate passes**, not making Android a **release brake**, and
> not breaking the **existing single-status trackers**.

### The three required pre-start changes

1. **Phase 0 = safety plumbing only** (path-scoped gate routing + per-platform
   version/tag policy + write-prefix isolation) — *before any Android PR lands*.
2. **Contract merge gate is versioned** — breaking-vs-additive, **not** strict
   both-platforms-green-by-default.
3. **Parity lives in a separate ledger**, never per-platform tuples stuffed into
   `docs/features.md` / `docs/bugs.md`.

### Phase 0 — safety plumbing ONLY (before any Android PR)

The automation is iOS-shaped and will silently **mis-gate** Android PRs until fixed:

- **Path-scope the gate-routing hooks — the day-1 blocker.**
  `.claude/hooks/check_codex_audit_artifact.sh` treats only `vreader/` +
  `vreaderTests/` as "code", so an `android/` PR currently **bypasses Gate 4 (the
  audit gate) as if it were docs-only**. Fix gate routing *before* the cron is
  allowed to open any Android PR.
- **Per-platform version/tag policy.** `40-version-bump.md` is hard-wired to
  `project.yml` → pbxproj + plain `vX.Y.Z`. **DONE (feature #103 WI-2)**:
  iOS stays plain `vX.Y.Z`, Android uses `android/vX.Y.Z`, per-platform
  version files, a "which platform did this PR touch → bump that" rule
  (rule 40 owns that routing table; its Android/Kotlin/`contracts/` path
  list is kept aligned with `code-paths.sh`, which remains only the
  audit-required code-vs-docs predicate), and a platform-namespaced GH
  close-gate comment. See `40-version-bump.md` "Multi-platform".
- **Write-prefix isolation (rule 48).** Kotlin agents must never touch `vreader/`;
  Swift agents never `android/`; shared files (`docs/*`, `contracts/`, release
  config) get a single owner — prevents the pbxproj-contamination class that has
  bitten worktree agents before.
- **Minimal AGENTS.md addendum** — Android path ownership, test command, release
  semantics.

**Defer until the spikes prove viability:** full tracker remodel, full Android
close-gate automation, and even a permanent `android/` app shell (run Spike A as
library/CLI harnesses first — an empty `android/` directory is low-value).

### Phase 1 — two viability spikes (benchmark-first)

- **Spike A — canonical cross-platform identity.** Deliverable is **not** "do
  Swift vs Kotlin locators/fingerprints match?" — it is to **decide the canonical
  identity model when they differ** (a normalization layer, or accept
  platform-local identity). Build the libmobi + Readium-Kotlin harness (real setup
  work, not a trivial preflight); compare on a shared MOBI/EPUB corpus; emit golden
  vectors into `contracts/`.
- **Spike B — CJK WebView reader, INSTRUMENTATION-first.** The cron's ability to
  drive an Android emulator/device is **UNVERIFIED** — the verification stack
  (rule 47, `cron-prompts/verify.md`, `tdd-guardian/config.json`) is iOS-specific.
  Make Spike B benchmark/instrumentation-driven (scroll / memory / CFI / selection
  metrics on a real 1000+-spine CJK novel via Readium-Kotlin), **not**
  UI-automation-dependent. Standing up a *minimally-automatable* Android
  verification lane is itself a Spike-B output.

  > **Amendment — Spike B verdict (2026-06-17, feature #105 VERIFIED).** Measured
  > on the android-35 arm64 emulator over the real 1042-chapter 道诡异仙 CJK book
  > (evidence: `dev-docs/verification/feature-105-20260617.md`).
  > **Outcome: Readium-Kotlin 3.3.0 scroll mode is VIABLE as the Android v1
  > reader engine — the WebView-engine plan is CONFIRMED, the engine strategy is
  > NOT reopened.** Scroll holds 60fps (0.23% jank); renderer memory is bounded
  > (eviction works — ramps to ~1.1GB high-water then recedes to a 580–870MB
  > oscillation, no OOM); zero renderer crashes; chapter-level position restore +
  > Locator JSON round-trip + text selection all round-trip faithfully. The cron
  > **can** drive an Android emulator end-to-end (`am instrument`), resolving the
  > UNVERIFIED above; the minimally-automatable lane is
  > `spikes/android-reader-bench/run-bench.sh`. Two **recorded Phase-3 hardening
  > obligations** (not blockers): (1) renderer ~1.1GB high-water → validate on a
  > 3–4GB device + consider a tighter resource-cache budget; (2) fragment-level
  > restore is ~2-paragraph-approximate on CJK (chapter/JSON/selection are exact)
  > → position re-hardening for exact same-paragraph CJK restore.

### Phase 2 — Android **foundation bar** (not "EPUB parity")

Reach a foundation bar, then switch to steady state: import/open/resume one EPUB
slice + the `contracts/` conformance lane alive + release/version plumbing alive +
a minimally-automatable verification story.

### Phase 3 — catch up in reuse-leverage order

EPUB reading (Readium-Kotlin) → library/persistence (Room) → format-agnostic
services (AI, WebDAV — port the contracts) → the hard native bits (continuous
scroll, bilingual, selection = **re-hardening**, not a port).

### Steady state — "one product spec, two tracks" (corrected)

- **Plan once** (platform-agnostic spec + one design bundle + identified contract
  changes), **but** a short **per-platform implementation delta still gets a
  Gate-2 audit** — Gate 2 here audits concrete paths/signatures, which are
  platform-specific.
- **Contract gate is VERSIONED** (needs a semver-like `contracts/` level policy):
  - *breaking* contract/schema/version change → **both platforms green before
    merge**;
  - *additive / backward-compatible* → merge with **one platform green** + a filed
    parity obligation + a compatibility window + updated conformance vectors.
- **Default mode = iOS leads, Android follows** for user-facing features; **strict
  parity reserved for identity / locator / backup / schema surfaces only.**
  (Strict-by-default makes Android the release brake.) A *partial* iOS freeze on
  contract-breaking surfaces is defensible; a full product freeze is not.
- **Parity in a separate ledger** (or parent product row + platform child issues),
  **never** per-platform status tuples in the trackers — the hooks
  (`check_gh_issue_mirror`, `check_terminal_status_evidence`,
  `check_unfinished_verification`) parse a single status cell and would break, and
  "VERIFIED + Android-pending" cannot coexist in the current state machine.
- **Define a parity-budget policy** — how long Android may lag and where the debt
  is tracked — or "parity pending" becomes permanent.
- **Design: one bundle, two implementations.** The handoff must mark **shared
  invariants vs allowed platform-native divergence**, or agents build "equivalent
  but non-identical" UI across UIKit ↔ Compose.
- **Assume lower Kotlin/Compose agent fluency than Swift** → smaller Android WIs +
  stronger scaffolding (repo conventions, lint/test defaults).

## Target layout (no reorg of iOS)

```
repo root
├── docs/                     # product trackers (single-status, UNCHANGED) + this ADR
│   └── parity/               # NEW: separate platform-parity ledger (NOT tuples in the trackers)
├── AGENTS.md                 # + Android section; route by touched paths
├── dev-docs/designs/         # shared design bundles (mark shared-invariant vs native-divergence)
├── contracts/                # NEW: canonical spec + golden vectors + conformance corpus + version levels
├── .claude/                  # hooks/rules → PATH-SCOPED (gate routing fixed before any android/ PR)
├── vreader/ + *.xcodeproj    # iOS, unchanged
└── android/                  # NEW: Gradle/Compose project (deferred until Spike A proves identity)
```

## Consequences

- iOS development is unaffected; the cron keeps its current cadence.
- Android is treated as a genuine port with two gating spikes (identity + a CJK
  WebView reader spike), not a checklist reuse.
- The shared surface (automation, trackers, contracts) becomes the maintenance
  cost center and must be made platform-aware *first*.
- If the identity corpus cannot be made cleanly enforceable, fall back to the flip
  condition (separate repos + shared contracts package).
