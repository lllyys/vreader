# `contracts/conformance/` — dual-platform identity conformance lane

The ADR-0001 Risk-1 gate as a CI gate: BOTH platforms' implementations of
the canonical identity contracts (`contracts/identity/*`) are asserted
against the SAME golden vectors in `contracts/vectors/`. Both green ⇒ a
book identified / a position located / a translation keyed identically on
iOS and Android ⇒ library/backup interop holds.

## Run

```bash
contracts/conformance/run.sh          # both platforms
contracts/conformance/run.sh swift    # Swift only (vreaderTests)
contracts/conformance/run.sh kotlin   # Kotlin only (gradle)
```

Needs JDK 17 (`brew install openjdk@17`) for the Kotlin side; the run
script resolves it at `/opt/homebrew/opt/openjdk@17/...` or honors a
pre-set `JAVA_HOME`. The Swift side runs via `scripts/run-tests.sh` on the
iPhone 17 Pro simulator.

## Sides

- **Swift** (`vreaderTests/Contracts/IdentityConformanceTests.swift`) — the
  app types ARE the reference; this asserts they match the vectors. Reads
  `contracts/vectors/` via `#filePath` (single source of truth, no bundled
  copy).
- **Kotlin** (`android/identity/`, the shared `:identity` module — feature #106
  WI-2) — a pure Kotlin/JVM module holding the identity/locator impl (`Identity.kt`)
  that the Android **app** also depends on, so the conformance test proves the
  SAME code the app runs (not a standalone reference). `run.sh kotlin` drives
  `android/gradlew :identity:cleanTest :identity:test` (the build injects
  `vreader.vectors.dir` → `contracts/vectors`). The app's identity code must keep
  this green (or change the vectors via the versioned contract merge gate).

## Coverage (WI-2 seed)

`fingerprint` (DocumentFingerprint.canonicalKey + validation) and
`cache-key` (lookupKey) — the pure string-composition contracts. The full
`Locator`/`VReaderLocator` JSON conformance + the libmobi-determinism and
Readium-round-trip harnesses are WI-3/4/5 (the toolchain-heavy legs).
