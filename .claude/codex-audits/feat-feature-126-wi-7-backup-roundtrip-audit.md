---
branch: feat/feature-126-wi-7-backup-roundtrip
threadId: 019f119a-f7d8-77e0-9119-9e601c57c690
rounds: 1
final_verdict: ship-as-is
date: 2026-06-29
---

# Gate-4 audit — feature #126 WI-7 (plain-Locator backup round-trip test)

Codex (gpt-5.5/high). **No findings.** Confirmed:
- The test exercises the REAL production seam (`BackupJson.encode(plainLocator)` →
  `BackupJson.decode<Locator>`, the same as `BackupCollector.kt:92` / `RestoreImporter.kt:108`)
  AND the `BackupPositionsEnvelope` section shape — not contrived (generic collector/importer
  coverage already exists elsewhere).
- `plain == restored` + explicit `format`/`cfi`/`progression` assertions are adequate for the
  AZW3/foliate fields `Azw3LocatorBridge` actually produces.
- The progression-only (no-CFI) case is meaningful (foliate can emit no CFI; progression is the
  cross-platform anchor).
- `totalProgression`/`textQuote`/NFC correctly out of scope (the bridge doesn't populate them; NFC
  is a canonical-locator concern, not a `BackupJson` round-trip concern).
- `schemaVersion = 3` = `BackupSchema.CURRENT_SCHEMA_VERSION`.

Verification: `Azw3BackupRoundTripTest` 3/3 (`:app:testDebugUnitTest`).

**Verdict: ship-as-is.**
