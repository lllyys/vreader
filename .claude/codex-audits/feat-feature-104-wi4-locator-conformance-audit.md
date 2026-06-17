---
branch: feat/feature-104-wi4-locator-conformance
threadId: 019ed3xx-wi4
rounds: 1
final_verdict: ship-as-is
date: 2026-06-17
---

# Codex Gate-4 audit — feature #104 Spike A WI-4 (Locator canonical-serialization conformance)

Runner: `scripts/run-codex.sh -m gpt-5.4 -e high`. The change completes Spike A:
the engine-neutral `Locator.canonicalJSON` cross-platform conformance leg (Swift
`Locator.canonicalJSON()` + a Kotlin `CanonicalLocator` reference impl asserting
one shared `contracts/vectors/locator.json`) + the canonical-identity DECISION
(`contracts/identity/DECISION.md`).

## Round 1 — 1 Medium (resolved); all else CLEAN

| Finding | Sev | Resolution |
|---|---|---|
| The 3 locator vectors didn't pin several canonicalization rules they claim to verify: key-sort was a no-op (construction order already sorted), and no case for RFC-8259 escaping, `\r\n`/`\r` normalization, paired `charRange`, or non-finite float omission — a Kotlin drift in those branches could ship with both suites green | Medium | Applied the auditor's exact fix: added a **coverage vector** exercising RFC-8259 escaping (`"`/`\`), CR-LF + bare-CR normalization to LF, and a paired char range (charRangeEnd sorts before charRangeStart — load-bearing sort); added **non-finite-omission unit tests on both platforms** (NaN/+Inf/-Inf can't be JSON vectors) asserting the `isFinite` gate omits progression/totalProgression. Both suites green. |

The auditor's other checks were all CLEAN, verbatim: "the Kotlin
`CanonicalLocator.canonicalJson` implementation itself looks faithful to the Swift
reference on key inclusion/order, nil omission, finite gating, float formatting
for normal finite values, RFC-8259 escaping shape, and CRLF-before-CR
normalization. The three `expectedCanonicalJSON` strings are correct as written.
Comparing canonical JSON strings is sufficient for the identity claim because
`canonicalHash` is just `SHA-256(canonicalJSON.utf8)`. The Swift test's
`Locator(...)` argument order and `JSONSerialization` numeric casts are correct…
I did not see secrets, machine-local paths, or real book bytes in the vectors."

The single Medium had a concrete auditor-prescribed fix, applied and verified by
both suites green (Kotlin `BUILD SUCCESSFUL`; Swift 4 tests, `RUN-TESTS RESULT:
SUCCEEDED`) — Gate-4 clean within the 3-round budget.

## Verdict

ship-as-is. The cross-platform canonical-Locator contract holds (byte-identical
serialization Swift↔Kotlin → identical canonicalHash → cross-platform position
identity), now with escaping / normalization / char-range / non-finite coverage.
This completes the Spike A dual-platform identity conformance lane for
fingerprint + cache-key + locator, and the canonical-identity DECISION is written.
