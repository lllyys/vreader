---
branch: feat/feature-113-android-backup-restore
threadId: 019ee0cd-d0cf-7670-9a1e-14db0b425251
rounds: 1
final_verdict: ship-as-is
date: 2026-06-20
---

# Gate-4 implementation audit — feature #113 WI-1 (Android backup-format core DTOs)

Codex (`scripts/run-codex.sh`, gpt-5.5, read-only) audited the WI-1 diff against the Swift
reference (`BackupSectionDTOs.swift`, `BackupProvider.swift`) + `contracts/identity/backup-format.md`:
`BackupSchema.kt`, `BackupJson.kt`, `BackupMetadata.kt`, `BackupSections.kt`, `BackupSectionsTest.kt`.

## Round 1 — CLEAN (zero findings)

Confirmations:
- DTO field names/types match Swift for highlights, bookmarks, notes, positions, collections,
  library-manifest entries, and metadata.
- `IsoInstantSerializer` emits UTC second-precision `yyyy-MM-dd'T'HH:mm:ss'Z'`, no fractional
  seconds; lenient `Instant.parse` decode is safe for restore.
- `explicitNulls=false` omits null optionals; `encodeDefaults=true` does not force nulls back
  in; defaulted nullable fields covered.
- `Base64DataSerializer` matches Swift `Data` base64 shape.
- `BackupRestoreError.UnsupportedSchemaVersion.supported: Int` matches Swift's singular `Int`.
- `canonicalElement` sorts nested objects and recurses through arrays.
- No DTO data class contains `ByteArray` (only the standalone serializer does), so data-class
  equality is intact.
- File sizes under the guideline; no dead code / serialization-compliance issue.

## Verdict

**ship-as-is.** 22 `:identity` unit tests green (17 new `BackupSectionsTest` + existing
identity/conformance), 0 failures. Foundational WI (pure DTOs, no user-observable behavior) →
no device verification required (rule 47 Gate-5 tier).
