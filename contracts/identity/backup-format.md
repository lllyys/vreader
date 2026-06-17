# Contract: backup archive format

**level: versioned** (a backup written by one platform must restore on the
other — the materializing-restore interop, feature #46).

Reference: `vreader/Services/Backup/BackupSectionDTOs.swift`.

## Global schema version

`kBackupCurrentSchemaVersion = 3`. Every section JSON is a
`BackupVersionedEnvelope` carrying its own `schemaVersion: Int` so a
restorer can branch per-section without special-casing the whole archive.

## Sections (each a versioned envelope)

| Section file | Envelope | Identity-bearing fields |
|---|---|---|
| annotations | `BackupAnnotationsEnvelope` | book `fingerprintKey`, highlight/note locators (`Locator` envelope) |
| positions | `BackupPositionsEnvelope` → `positions: [BackupPosition]` | each `BackupPosition` = `{ bookFingerprintKey, locatorJSON, updatedAt, lastOpenedAt? }`, where **`locatorJSON` is JSON for a plain `Locator`** (NOT `VReaderLocator`) — restore decodes `Locator.self`. |
| settings | `BackupSettingsEnvelope` | device-local prefs (not identity) |
| collections | `BackupCollectionsEnvelope` | collection membership by `fingerprintKey` |
| book-sources | `BackupBookSourcesEnvelope` | OPDS/source config |
| per-book-settings | `BackupPerBookSettingsEnvelope` | per-book config keyed by `fingerprintKey` (incl. bilingual config) |
| replacement-rules | `BackupReplacementRulesEnvelope` | content-replacement rules |
| **`reading-history.json`** | `BackupReadingHistoryEnvelope` (**schema-v2 addition**, feature #58) | `ReadingSession` + `ReadingStats` rows keyed by `fingerprintKey` |
| **`ai-conversations.json`** | `BackupAIConversationsEnvelope` / `BackupChatSession` (**schema-v3 addition**, feature #89) | AI chat sessions (book-scoped where applicable) |
| **`library-manifest.json`** | `BackupLibraryManifestEnvelope` (**schema 1**, separate from the global 3) | the library index — book `fingerprintKey` → blob path; the materializing-restore map |

**Pre-v3 sections are byte-identical across v1/v2/v3** — only the integer
`schemaVersion` differs — so a v3 restorer accepting v1/v2 archives is
sound (the v2 addition is `reading-history`, the v3 addition is
`ai-conversations`; everything else is unchanged).

## Identity rules

- Every cross-book reference is by **`fingerprintKey`** (the canonical
  book identity). A backup written on iOS references books by the same
  fingerprint Kotlin computes — which is exactly why the `fingerprint.md`
  + `locator.md` contracts gate this whole contract. (Backup identity does
  NOT depend on converter determinism: for converted-Kindle formats the
  canonical key is the SOURCE bytes, per `fingerprint.md` / `DECISION.md`.)
- Locators inside annotations/positions are serialized as **plain
  `Locator` JSON** (the `locatorJSON` String field), NOT the
  `VReaderLocator` envelope — the backup wire format encodes a `Locator`
  and restore decodes `Locator.self`. (`VReaderLocator` is the live
  persisted reading-position envelope elsewhere, not part of the backup
  section schema.) Restore uses the `Locator`'s canonical fields + the
  lossy fallback (`locator.md`), so a position saved by one platform's
  engine restores on the
  other at least to progression+quote precision.
- `library-manifest.json` (schema 1) is the materializing-restore index:
  `fingerprintKey → blob path`. The canonical `fingerprintKey` is the
  **SOURCE-bytes** key for converted-Kindle formats (`.azw3`/`.mobi`/`.prc`) —
  see `fingerprint.md` + `DECISION.md`. On restore, identity is confirmed by
  re-fingerprinting the **source bytes** (not the converted EPUB), so a Kindle
  book backed up on one platform restores under the same identity on the other
  without requiring byte-identical conversion.

## Cross-platform requirement

- Both platforms read/write schema **3** sections + manifest schema **1**,
  branching on `schemaVersion` for older archives.
- Section DTO field names + JSON shapes must match (canonical JSON, stable
  key order).
- Per the contract merge gate: a backup-schema bump is a **breaking**
  level event (both platforms green) unless purely additive (a new
  optional field / new section).

## Golden vectors / conformance

`contracts/vectors/backup-*.json`: representative section envelopes →
expected canonical JSON. Swift conformance (WI-2) asserts the iOS DTOs
encode/decode the vectors at schema 3 / manifest 1; Kotlin (WI-5,
toolchain-gated) the same — a round-trip backup → restore across platforms
is the Phase-2+ end-to-end acceptance.
