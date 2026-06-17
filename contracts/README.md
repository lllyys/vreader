# `contracts/` — vreader cross-platform identity & data contracts

The canonical, platform-neutral specification of vreader's **identity and
data interop surface**: how a book is identified, how a reading position
is located, how the translation cache is keyed, and how a backup archive
is shaped. It is the single source of truth that the iOS (Swift) and
Android (Kotlin) apps must BOTH satisfy so "your library follows you
across devices" (content-hash dedup + WebDAV materializing restore) holds.

> Decomposed from feature #102 (Android port) per
> `docs/decisions/0001-android-port-strategy.md`. This directory is
> **Spike A** (feature #104) — the interop gate (ADR Risk 1). These
> identity specs (`identity/*.md` + `DECISION.md`) are the **authoritative
> cross-platform contract** — the decided target. They are distilled from
> the Swift reference where the app already matches, and the Swift
> conformance suite asserts that match; where a deliberate decision moves
> the contract AHEAD of the current app (e.g. source-bytes converted-Kindle
> identity vs iOS's current converted-EPUB fingerprint), the gap is
> explicitly acknowledged in `DECISION.md` and tracked as a follow-up
> feature (#108), not a spec error.

## Why this exists (the gate)

The original risk was that a Kindle book's identity might depend on the
**converted EPUB** — which would couple two platforms' converter
pipelines. That risk is retired: the canonical cross-platform identity for
`.azw3`/`.mobi`/`.prc` is the **SOURCE file bytes** (decided in
`identity/DECISION.md`; iOS's converted-EPUB fingerprint is a
platform-local detail), so identity is converter-independent. The
remaining contract is that Swift-Readium and Kotlin-Readium emit
round-trippable `Locator`s. Until proven on a shared corpus,
library/backup interop is a hope.
`contracts/` turns that hope into an enforceable, versioned conformance
lane.

## Layout

```
contracts/
├── README.md                 # this file (versioning + legal + status)
├── identity/
│   ├── fingerprint.md        # DocumentFingerprint canonical key
│   ├── locator.md            # Locator + VReaderLocator persisted envelope
│   ├── cache-key.md          # ChapterTranslationRecord.lookupKey
│   └── backup-format.md      # backup section schemas + library manifest
├── vectors/                  # golden vectors (legally clean — derived only)
├── conformance/
│   ├── swift/                # Swift suite asserts the iOS impl == vectors
│   └── run.sh                # drives both: Swift + the shared android/:identity module (#106 WI-2)
└── harness/                  # libmobi-determinism + Readium round-trip drivers (toolchain-gated)
```

## Versioning levels (the contract merge gate)

Each contract carries a level so the ADR's versioned merge gate
(breaking-vs-additive) can apply:

- **breaking** — changes the serialized shape or identity of existing
  data (a fingerprint/locator/key/backup field's meaning or presence). →
  BOTH platforms green before merge + a migration note.
- **additive / backward-compatible** — a new optional field, a new
  section, a widened set. → merge with ONE platform green + a filed parity
  obligation + updated vectors.

Every contracts-touching PR updates the affected golden vectors and notes
the level. (Phase 0 already routes contracts/ PRs through the Codex audit
gate — `.claude/hooks/lib/code-paths.sh`.)

## Tool-version pinning

Golden vectors that depend on a producing tool (libmobi conversion,
Readium serialization) record the producing **`MobiEPUBConverter.version`,
libmobi version, and Readium version**. A deliberate tool-version bump
that changes produced bytes updates the versioned baseline (a level
event) — it is NOT a cross-platform determinism failure. A vector
mismatch is a determinism failure ONLY when the tool versions match.

## Legal (binding)

Golden vectors contain **derived data only** — fingerprints (hashes),
serialized locators, key strings, schema shapes. They must NEVER contain
Kindle/copyrighted source bytes. Source corpus files (the gitignored
`test-books/` MOBI/AZW3 set) stay out of `contracts/`; only the derived
vectors check in. A `contracts/` PR adding raw book bytes is a defect.

## Status (2026-06-17) — Spike A (#104) VERIFIED

- **Canonical specs** (`identity/*.md` + `DECISION.md`): DONE — the
  canonical-identity DECISION is source-bytes (converted-Kindle) +
  exact-match (native fingerprint / cache-key / `Locator.canonicalJSON`) +
  CFI lossy-fallback.
- **Dual-platform conformance lane**: GREEN — `contracts/conformance/run.sh`
  runs the Swift suite (`vreaderTests/IdentityConformanceTests`) + the
  shared Android `:identity` module (`android/gradlew :identity:test` — feature
  #106 WI-2; the same module the app depends on) against the shared
  `contracts/vectors/` (fingerprint + cache-key + locator). Toolchain
  (JDK 17 / Kotlin / Android SDK+NDK) installed.
- **Follow-up**: the iOS source-bytes BookImporter implementation +
  migration is tracked as **feature #108** (the contract is ahead of the
  app there by decision; see `DECISION.md` → Implementation status).
