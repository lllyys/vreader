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
- **Kotlin** (`contracts/conformance/kotlin/`) — a pure Kotlin/JVM Gradle
  module with the Kotlin reference impl (`Identity.kt`) + a test asserting
  the SAME vectors. The future Android app's identity code must keep this
  green (or change the vectors via the versioned contract merge gate).

## Coverage (WI-2 seed)

`fingerprint` (DocumentFingerprint.canonicalKey + validation) and
`cache-key` (lookupKey) — the pure string-composition contracts. The full
`Locator`/`VReaderLocator` JSON conformance + the libmobi-determinism and
Readium-round-trip harnesses are WI-3/4/5 (the toolchain-heavy legs).
