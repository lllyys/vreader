# Feature #104 — Android Spike A: canonical cross-platform identity conformance

> Decomposed from the #102 Android-port umbrella per **ADR-0001**
> (`docs/decisions/0001-android-port-strategy.md`), the ADR's **Phase 1
> Spike A**. This is **Risk 1 — the gate**: vreader's whole value
> proposition ("your library follows you across devices") rests on a
> deterministic, cross-platform book identity. If Swift and Kotlin cannot
> agree on identity, the monorepo + interop strategy falls back to the
> ADR's flip condition (separate repos + shared contracts package).
>
> **Depends on Feature #103 (Phase 0)** — the `contracts/` write-owner +
> gate routing must exist first. Runs as **library/CLI harnesses**, NOT a
> full Android app (the ADR defers the `android/` app shell until identity
> is proven).

## Problem

`DocumentFingerprint` for a Kindle book is the hash of the **converted
EPUB**, and there is **no guarantee** that:

1. libmobi conversion of the same `.mobi`/`.azw3` produces a byte-identical
   EPUB across platforms (iOS build vs Android NDK build); and
2. Swift-Readium and Kotlin-Readium emit byte-identical / round-trippable
   `Locator`s (CFI, progression, position) for the same reading position.

Until both are proven on a shared corpus, "library/backup interop" is a
hope, not a contract. Spike A's deliverable is **not** a yes/no — it is to
**decide the canonical identity model** (normalize to a platform-neutral
form, or accept platform-local identity with a mapping layer) and capture
it as enforceable golden vectors in `contracts/`.

## Scope

**In scope:**

1. **A `contracts/` canonical spec for the ACTUAL persisted identity
   envelope** (Codex Gate-2 Critical — the reduced `href+progression+CFI+
   charOffset` model can go green while breaking saved-position
   back-compat). The spec models the real shapes and marks each field
   **canonical-cross-platform vs platform-local vs lossy-fallback**:
   - `DocumentFingerprint` — `format:contentSHA256:fileByteCount`
     (`canonicalKey`); **canonical**.
   - `Locator` (`vreader/Models/Locator.swift`) — the full envelope, EVERY
     persisted field (Codex Gate-2 round-2 Medium — the inventory must be
     exhaustive): `bookFingerprint` (**canonical** — the book identity the
     locator belongs to), `href` (**canonical**), `progression`
     (**canonical**), `totalProgression` (**canonical**, derived),
     `cfi` (**platform-local** — CFI dialect may not round-trip
     Swift↔Kotlin Readium → **lossy fallback** to progression+quote),
     `page` (**platform-local** — PDF-format-specific page index, not a
     cross-engine cross-platform anchor), `charOffsetUTF16` (**canonical**),
     `charRangeStartUTF16`/`EndUTF16` (**canonical** — selection range),
     `textQuote`, `textContextBefore`/`After` (**canonical** — the
     quote-anchor resume), plus the canonical-JSON rules.
   - `VReaderLocator` (`vreader/Models/VReaderLocator.swift`) — EVERY
     persisted field: `fingerprintKey` (**canonical** — book identity
     key), `originalFormat` (**canonical** — part of the fingerprint),
     `engine` (**platform-local** — which renderer produced it),
     `readiumLocatorJSON` (**platform-local** — Readium's own CFI-bearing
     JSON; lossy fallback to `legacyLocator`'s progression+quote),
     `legacyLocator` (**canonical** — the platform-neutral resume
     envelope; the nested `Locator`'s own per-field classifications above
     apply within it), `schemaVersion` (**canonical** — a persisted
     contract field
     both platforms must serialize consistently; also the migration hook).
   - The translation cache key (`ChapterTranslationRecord.lookupKey`).
   - The backup contract (see below) — concrete files, not "blob/manifest".
2. **A Kindle-conversion determinism harness**: build libmobi on the host
   (and on Android NDK/arm) and convert a shared MOBI/AZW3 corpus to EPUB
   on both, comparing the resulting fingerprints.
3. **A Readium locator round-trip harness**: take a set of canonical
   positions, serialize via Swift-Readium and Kotlin-Readium, and compare
   / round-trip them.
4. **The canonical-identity DECISION**, written into the `contracts/`
   spec: exact-match required, or a documented normalization layer, or
   platform-local identity + a mapping table — with the rationale.
5. **Golden vectors** checked into `contracts/` (legally clean — derived
   hashes/locators only, never Kindle source bytes) + a **dual-platform
   conformance test** that both a Swift target and a Kotlin/JVM target run
   against the same vectors (the Risk-1 → CI-gate conversion).

**Explicitly OUT of scope:**

- Any Android app UI, Compose, or `android/` app shell (library/CLI
  harnesses only).
- Shipping the conversion pipeline into a product (Spike, not Phase 2).
- PDF/locator parity beyond what identity requires.
- The actual CI wiring (no in-repo CI exists; the dual-platform test is
  authored to be CI-ready, run locally for the spike).

## Surface area (file-by-file, concrete)

- `contracts/README.md` — what `contracts/` is, the versioning levels
  (breaking vs additive), the legal rule (golden vectors only, no Kindle
  source).
- `contracts/identity/fingerprint.md` + `…/locator.md` +
  `…/cache-key.md` + `…/backup-format.md` — canonical specs distilled from
  the Swift reference: `vreader/Models/DocumentFingerprint.swift`,
  `vreader/Models/VReaderLocator.swift` + `Locator.swift` (the FULL field
  set above), `vreader/Models/ChapterTranslationRecord.swift` (`lookupKey`).
- **Backup contract (Codex Gate-2 Medium — name the surfaces, not "blob/
  manifest"):** `contracts/identity/backup-format.md` owns the versioned
  backup DTOs in `vreader/Services/Backup/BackupSectionDTOs.swift` (global
  backup schema **3**) and the separate `library-manifest.json` (schema
  **1**). The spec records both schema versions, the section DTO shapes,
  and which fields are identity-bearing (fingerprint keys, locator
  envelopes) vs device-local. Cross-ref the materializing-restore feature
  (#46) blob layout.
- `contracts/vectors/*.json` — golden vectors: input descriptor →
  expected fingerprint / locator serialization. **Codex Gate-2 Medium —
  pin tool versions:** every vector records the producing
  `MobiEPUBConverter.version`, the libmobi version, and the Readium
  version, because a deliberate converter version bump (which has changed
  produced EPUB bytes before) would otherwise be indistinguishable from
  cross-platform nondeterminism. Rule: a vector mismatch is a determinism
  FAILURE only when the tool versions match; a tool-version bump updates
  the versioned baseline (a `contracts/` breaking-vs-additive level event),
  not a determinism failure.
- `contracts/conformance/swift/` — a tiny SwiftPM test target (NOT in the
  Xcode app) that loads the vectors and asserts the Swift implementations
  match.
- `contracts/conformance/kotlin/` — a tiny Gradle/JVM (Kotlin) test
  module that loads the same vectors and asserts the Kotlin
  implementations match.
- `contracts/harness/` — the libmobi-build + convert + compare scripts
  (host + Android NDK), and the Readium round-trip drivers. Reference
  corpus pointer (the gitignored `test-books/` MOBI/AZW3 set; vectors are
  derived, not the source files).

## Prior art / project precedent / rejected alternatives

- **Precedent**: feature #42 already does Kindle→EPUB convert-on-import via
  libmobi on iOS; Spike A reuses that conversion path's *definition* and
  tests its cross-platform determinism. `DocumentFingerprint` /
  `VReaderLocator` dual-write are existing, stable Swift types — the
  canonical spec is distilled FROM them, the Swift side is the reference
  implementation.
- **Precedent**: the project already keeps a legally-clean fixture posture
  (`test-books/` gitignored) — golden vectors extend that (derived data
  checks in, source does not).
- **Rejected — assume identity matches and discover divergence in Phase
  3**: that's the exact failure the ADR's Risk 1 exists to prevent; a late
  divergence would invalidate already-shipped Android library/backup.
- **Rejected — KMP shared core now** to guarantee identity: the ADR defers
  KMP (it would force migrating the stable Swift layer to Kotlin); the
  spec+vectors approach proves identity without that cost.

## Work-item sequencing

| WI | Deliverable | PR size | Tier |
|---|---|---|---|
| WI-1 | `contracts/` scaffold + README + canonical specs distilled from the Swift reference + versioning/legal rules | Med (docs) | Foundational |
| WI-2 | Golden vectors + the Swift conformance test target asserting the Swift impls match the vectors (proves the spec is faithful to today's iOS behavior) | Med | Foundational (no app behavior change) |
| WI-3 | libmobi cross-platform determinism harness (host + Android NDK build) + fingerprint comparison on the shared corpus | Large (build/tooling) | Spike (investigation) |
| WI-4 | Readium locator round-trip harness (Swift ↔ Kotlin) + the canonical-identity DECISION written into the spec | Large | Spike |
| WI-5 | Kotlin/JVM conformance test running the SAME vectors; the dual-platform conformance lane is the Risk-1 → gate output | Med | Foundational |

WI-1/WI-2 are doable immediately (Swift-only, no Android toolchain). WI-3
onward need an Android NDK + Kotlin/JVM toolchain — the plan flags this as
a tooling prerequisite (and a Spike-B-shared environment concern).

## Test catalogue

- `contracts/conformance/swift/` — vector round-trip tests (fingerprint
  determinism, locator serialize/parse, cache-key composition, backup
  manifest shape) against the golden vectors.
- `contracts/conformance/kotlin/` — the identical vector suite in Kotlin.
- `contracts/harness/` — determinism assertions: same input → same
  fingerprint across host vs NDK libmobi builds; locator round-trip
  equivalence (or the documented normalization).
- **The gate**: a single command that runs BOTH conformance suites against
  the SAME `contracts/vectors/` and fails if either diverges.

## Risks + mitigations

- **R1 (the whole point) — conversion is non-deterministic across
  platforms.** Outcome-defining: if libmobi output diverges, the canonical
  model becomes "normalize the converted EPUB before hashing" or
  "fingerprint the SOURCE bytes, not the conversion." The spike's job is
  to find which and write it down — a divergence is a SUCCESSFUL spike
  result, not a failure.
- **R2 — locators genuinely can't round-trip** (CFI dialect differences).
  Mitigation: the decision may be "identity = fingerprint only; locators
  are platform-local + a progression-based cross-device resume" (lossy but
  viable) — captured in the spec.
- **R3 — toolchain availability** (Android NDK, Kotlin/JVM, Readium-Kotlin
  3.3.0) on the build host is UNVERIFIED. Mitigation: WI-1/WI-2 (Swift-only)
  derisk the spec first; WI-3+ gate on standing up the toolchain (shared
  with Spike B) and the plan names this explicitly rather than assuming it.
- **R4 — legal**: vectors must be derived (hashes/serializations), never
  Kindle source. Mitigation: the `contracts/README.md` legal rule + a
  check that `contracts/` contains no book bytes.

## Backward compatibility

- Pure additive: `contracts/` is new; no change to the shipping iOS app,
  its fingerprints, or its locators (the Swift conformance test ASSERTS
  the spec matches today's behavior — if it doesn't, the spec is wrong,
  not the app).

## Acceptance criteria

1. `contracts/` holds canonical specs for fingerprint / locator /
   cache-key / backup-format, distilled from and consistent with the Swift
   reference, with **every persisted `Locator` and `VReaderLocator` field
   inventoried and classified** (canonical / platform-local /
   lossy-fallback). The Swift conformance test asserts the FULL serialized
   shapes (not a reduced subset), so a vector can't go green while ignoring
   stored fields.
2. The libmobi determinism + Readium round-trip harnesses run on the
   shared corpus and produce a written **canonical-identity decision** in
   the spec (exact-match, normalization, or platform-local + mapping).
3. Golden vectors check in (legally clean) and a **dual-platform
   conformance command** runs both the Swift and Kotlin suites against
   them.
4. No Android app shell, no product pipeline change, no iOS behavior
   change.

## Revision history

- v1 (2026-06-16) — initial Gate-1 draft from ADR-0001 Spike A.
- v2 (2026-06-16) — Gate-2 round 1 (Codex `019ed111`) applied: **Critical**
  — model the FULL persisted identity envelope (`Locator`'s
  totalProgression/page/UTF-16 ranges/quote-context + `VReaderLocator`'s
  engine/readiumLocatorJSON/legacyLocator/schemaVersion), marking each
  field canonical / platform-local / lossy-fallback (the reduced spec
  could go green while breaking back-compat); **Medium** — named the
  concrete backup surfaces (`BackupSectionDTOs.swift` global schema 3 +
  `library-manifest.json` schema 1); **Medium** — vectors pin
  converter/libmobi/Readium versions so a deliberate version bump isn't
  mistaken for nondeterminism.
- v3 (2026-06-16) — Gate-2 round 2 (Codex `019ed11c`) applied: completed
  the field inventory — added `Locator.bookFingerprint`, `Locator.cfi`,
  `VReaderLocator.fingerprintKey`, `VReaderLocator.originalFormat` (the
  round-1 fix had omitted them), and tightened AC1 to require conformance
  against the FULL serialized shapes. #103 + #105 were CLEAN at round 2.
- v4 (2026-06-16) — Gate-2 rounds 3+4 (Codex `019ed120`, `019ed122`)
  applied: per-field taxonomy completeness — `page` `format-local` →
  **platform-local**; `schemaVersion` → **canonical**; `legacyLocator` →
  **canonical**. All 18 persisted `Locator`+`VReaderLocator` fields now
  carry exactly one of canonical / platform-local / lossy-fallback
  (self-verified field-by-field). Rounds 1→4 converged 11→1→2→1 findings,
  the tail being cosmetic per-field-label completeness on this HELD plan;
  substance was settled by round 2 (#103/#105 CLEAN at round 2).
