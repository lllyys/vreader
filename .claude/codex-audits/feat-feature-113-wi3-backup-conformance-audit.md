---
branch: feat/feature-113-wi3-backup-conformance
threadId: 019ee2f5-e832-7e90-ad3f-73f2d630f043
rounds: 1
final_verdict: ship-as-is
date: 2026-06-20
---

# Gate-4 implementation audit — feature #113 WI-3 (cross-platform backup conformance)

Codex (`scripts/run-codex.sh`, gpt-5.5, read-only) audited the conformance lane:
`contracts/vectors/backup-sections.json`, the Kotlin `BackupConformanceTest.kt`, the Swift
`BackupConformanceTests.swift`, and the `backup-format.md` doc-sync.

## Round 1 — 1 Low (fixed)

| file:line | severity | issue | resolution |
|---|---|---|---|
| `BackupConformanceTests.swift:47` | Low | `NSDictionary.isEqual` treats JSON `true` == `1` (Foundation `NSNumber(bool) == NSNumber(int)`), so it doesn't strictly prove Bool/Number type parity the way Kotlin's `JsonElement` equality does | **Fixed**: replaced with a recursive `jsonEqual` that distinguishes `CFBoolean` from a numeric `NSNumber` (and recurses dicts/arrays/strings/null). 12/12 Swift tests still green. |

## Clean (round 1)

- **Methodology SOUND**: decode → re-encode → shared-vector equality is "a sound interop proof
  by transitivity for parsed JSON" — both platforms agreeing on the same vector ⇒ they agree
  with each other. No separate other-platform-bytes fixture needed (that only guards
  test-vs-prod encoder divergence).
- **Coverage complete**: the 9 schema-v3 data sections + `library-manifest` (schema 1) +
  `metadata` — the full archive surface. No uncovered contract section.
- **Vector fidelity**: vectors line up with both the Swift and Kotlin DTO required fields;
  omitted fields are optional/defaulted on both sides; UUID-as-string is sound (iOS enforces
  valid UUIDs on decode, Kotlin carries the wire string).

## Verdict

**ship-as-is.** The cross-platform backup-format contract holds: **Kotlin 12/12 + Swift 12/12**
green against ONE shared `contracts/vectors/backup-sections.json` — a backup written on one
platform decodes + re-encodes identically on the other. Completes feature #113 (the full Kotlin
backup DTO model + conformance). Foundational tier — no device verification (the round-trip
backup→restore against a live WebDAV is a separate future backend feature).
