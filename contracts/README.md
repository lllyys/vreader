# `contracts/` — vreader cross-platform identity & data contracts

The canonical, platform-neutral specification of vreader's **identity and
data interop surface**: how a book is identified, how a reading position
is located, how the translation cache is keyed, and how a backup archive
is shaped. It is the single source of truth that the iOS (Swift) and
Android (Kotlin) apps must BOTH satisfy so "your library follows you
across devices" (content-hash dedup + WebDAV materializing restore) holds.

> Decomposed from feature #102 (Android port) per
> `docs/decisions/0001-android-port-strategy.md`. This directory is
> **Spike A** (feature #104) — the interop gate (ADR Risk 1). The Swift
> app is the **reference implementation**; these specs are distilled FROM
> it, and the Swift conformance suite ASSERTS the app matches the spec (if
> it doesn't, the spec is wrong, not the app).

## Why this exists (the gate)

A Kindle book's `DocumentFingerprint` is the hash of the **converted
EPUB**, and there is no a-priori guarantee that (1) libmobi conversion is
byte-deterministic across an iOS build and an Android NDK build, or (2)
Swift-Readium and Kotlin-Readium emit round-trippable `Locator`s. Until
both are proven on a shared corpus, library/backup interop is a hope.
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
│   └── kotlin/               # Kotlin suite asserts the Android impl == vectors (toolchain-gated)
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

## Status (2026-06-17)

- **WI-1 (this)**: the canonical specs (`identity/*.md`) — DONE.
- **WI-2**: golden vectors + the Swift conformance suite — Swift-only, next.
- **WI-3/4/5 + the harnesses**: libmobi NDK determinism, Readium round-trip,
  Kotlin conformance — **toolchain-gated** (no Android SDK/NDK/JDK/Kotlin
  on the build host yet; standing it up is a prerequisite the plan flags).
