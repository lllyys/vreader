---
branch: feat/feature-113-wi2-backup-sections
threadId: 019ee0d4-ae72-7121-a593-0be7563c5294
rounds: 1
final_verdict: ship-as-is
date: 2026-06-20
---

# Gate-4 implementation audit — feature #113 WI-2 (remaining backup-format DTOs)

Codex (`scripts/run-codex.sh`, gpt-5.5, read-only) audited the WI-2 diff against the Swift
reference (`BackupSectionDTOs.swift`, `BackupReadingHistory.swift`, `BackupAIConversations.swift`,
`PerBookSettings.swift`): `BackupDefaultsValue.kt`, `BackupSectionsExtended.kt`, `BackupSectionsExtendedTest.kt`.

## Round 1 — 1 Medium (fixed)

| file:line | severity | issue | resolution |
|---|---|---|---|
| `BackupDefaultsValue.kt:28` | **Medium** | `IntValue` used Kotlin `Int` (32-bit), but Swift `BackupDefaultsValue.int(Int)` is `Int64` on iOS — a valid iOS backup with a >32-bit integer default would fail Android decode (`jsonPrimitive.int`). | **Fixed**: `IntValue.value` → `Long`; decode via `jsonPrimitive.long`. Regression test `defaultsValue_int_is64Bit` (`Int.MAX_VALUE + 1L` round-trips). Verified green. |

Clean confirmations (round 1):
- Field names + nullable fields match Swift for book sources, reading-history/stats, AI
  conversations, per-book settings, replacement rules.
- `Data`/`ByteArray` fields are base64 (`Base64DataSerializer`); `DataValue` overrides equality;
  ByteArray-bearing DTOs use encode/decode/re-encode round-trip in tests (correct).
- `CGFloat` ⇒ `Double` for `PerBookSettingsOverride`; UUID ⇒ `String`; `explicitNulls=false`
  matches Swift's omitted nil keys. No dead code; file sizes fine.

## Verdict

**ship-as-is.** The single Medium is a one-line type widening (`Int`→`Long`) with a regression
test. 32 `:identity` unit tests green, 0 failures. Foundational WI — no device verification
(rule 47 tier).

> Remaining for #113: WI-3 — the golden-vector `BackupConformanceTest` (generate
> `contracts/vectors/backup-*.json` from the iOS encoder + parsed-`JsonElement`-equality
> Kotlin conformance). Split from WI-2 because it requires the iOS Swift encoder run + a
> `contracts/` change, warranting its own focused pass. The full Kotlin DTO model (all 10
> sections + manifest + metadata) is complete after this WI.
