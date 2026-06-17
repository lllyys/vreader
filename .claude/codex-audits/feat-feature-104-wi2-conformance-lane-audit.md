---
branch: feat/feature-104-wi2-conformance-lane
threadId: 019ed16f-0857-7422-8214-f8c43033c123
rounds: 3
final_verdict: ship-as-is
date: 2026-06-17
---

# Codex Gate-4 audit — feature #104 Spike A WI-2 (dual-platform identity conformance lane)

Runner: `scripts/run-codex.sh -m gpt-5.4 -e high`. Sessions: R1
`019ed16f`, R2 `019ed179`, R3 `019ed17d`. The lane: shared golden vectors
(`contracts/vectors/`) asserted by BOTH a Swift suite (`vreaderTests/
Contracts/IdentityConformanceTests.swift`) and a Kotlin suite
(`contracts/conformance/kotlin/`) — the ADR-0001 Risk-1 interop gate.

## Round 1 — 1 High + 2 Medium

| Finding | Sev | Resolution |
|---|---|---|
| `run.sh` missing-JDK returned 0 → `both` mode could print `CONFORMANCE RESULT: PASS` while silently skipping Kotlin (fail-open) | High | Missing JDK is now a HARD FAIL (`rc=1`). |
| Kotlin "reference impl" didn't mirror Swift's PARSE semantics (free-form `format` String, no parser, no round-trip / invalid-parse) — both suites could go green while Kotlin accepts keys Swift rejects | Medium | Added a Kotlin `BookFormat` enum + `parseCanonicalKey` (enum-raw-value parity, 3-part split, non-negative Long, lowercase-hex); Kotlin test now asserts the round-trip + invalid-parse cases the Swift side does. |
| bare `gradle` from PATH, no wrapper → host-dependent, larger trust surface | Medium | Checked in a pinned Gradle wrapper (8.14.4); `run.sh` uses `./gradlew`. |

## Round 2 — 1 (Low/Medium) hardening

| Finding | Sev | Resolution |
|---|---|---|
| Wrapper version-pinned but not checksum-pinned | Low/Med | Added `distributionSha256Sum` (the official `gradle-8.14.4-bin.zip` checksum, fetched + verified). |

R2 confirmed the High + 2 Medium fixes: `parseCanonicalKey` is "a faithful
mirror of Swift", `run.sh` hard-fails on missing JDK, the wrapper is
correct.

## Round 3 — CLEAN

Verdict verbatim: "No Critical/High/Medium findings in `git diff main`.
CLEAN." Residual: the auditor (read-only) did not execute `run.sh` —
**closed by actually running it**: `contracts/conformance/run.sh both` →
`RUN-TESTS RESULT: SUCCEEDED` (Swift) + `CONFORMANCE RESULT: PASS` (both
platforms green via the unified script).

## Verdict

ship-as-is. WI-2 + the WI-5 seed: the dual-platform identity conformance
lane works for `fingerprint` + `cache-key` — a book is identified and a
translation keyed identically on iOS (the reference app) and a Kotlin
reference impl, against one shared vector set. The interop gate's core
mechanism is proven; the audit (on the now-gated `contracts/` surface)
drove genuine Swift↔Kotlin parity (the parse round-trip) rather than a
string-building stub.
