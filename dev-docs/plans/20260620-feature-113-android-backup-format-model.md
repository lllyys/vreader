# Feature #113 — Android backup-format contract model (Kotlin DTOs + conformance)

Status: Gate-2 audited (2026-06-20, Codex round 1 → revised; see Revision history). Third capability under the #110 Android Phase-3 driver
(after EPUB/TXT/MD readers), and the FIRST slice of the "backup & WebDAV restore" capability
chosen as the most autonomously-completable next step (Codex decision, thread `019ee0be`).

## Problem

iOS has a full WebDAV backup/restore subsystem (~30 files) writing a versioned ZIP archive
whose **cross-platform format is a `contracts/` versioned contract** (`contracts/identity/
backup-format.md`, schema 3 / manifest 1): "a backup written by one platform must restore on
the other." Android has **zero** backup code. Before Android can read or write an interop
backup it needs the **data-layer foundation**: Kotlin value types for every archive section +
the manifest, byte-compatible with the iOS DTOs (field names, JSON shapes, ISO8601-UTC dates,
plain-`Locator` `locatorJSON`).

This feature delivers ONLY that contract model + its conformance — a pure, design-gate-free,
fully-JVM-testable data layer. It is the prerequisite for (future, separately-filed) Android
WebDAV client + restore-import-pipeline work, and is independent of the **design-gated** user
UI (`needs-design #1767` — no backup/restore/WebDAV surface in the committed bundle).

## Surface area

All under the existing `:identity` module's package `vreader.contracts` (the shared,
JVM-only, no-Android-deps contract module that both `:app` and `contracts/conformance` depend
on — so a conformance test proves the same code the app will run). NEW files:

- `vreader/contracts/backup/BackupSchema.kt` — `kBackupCurrentSchemaVersion = 3`,
  `kBackupAcceptedSchemaVersions = setOf(1,2,3)`, `kBackupManifestSchemaVersion = 1`;
  `BackupRestoreError` sealed type (`UnsupportedSchemaVersion(section, actual, supported)`,
  `PartialFailure(section, failed, total)`) mirroring the Swift enum; a `BackupVersionedEnvelope`
  interface (`val schemaVersion: Int`).
- `vreader/contracts/backup/BackupJson.kt` — the canonical encode/decode surface, configured
  for **Swift `Codable` parity** (Gate-2 round-1 Highs):
  - `Json { encodeDefaults = true; explicitNulls = false; ignoreUnknownKeys = true }` —
    **`explicitNulls = false`** so nil optionals (`note`, `title`, `lastOpenedAt`,
    `sourceCanonicalKey`, …) are **OMITTED**, matching Swift's synthesized `Codable` (which
    drops nil keys); `ignoreUnknownKeys` so a newer archive's extra keys don't break decode.
  - `IsoInstantSerializer` — a `KSerializer<java.time.Instant>` using a fixed
    `DateTimeFormatter` (UTC, **second precision, no fractional seconds**) producing exactly
    `2026-06-20T16:30:00Z`, matching Swift `.iso8601` (= `ISO8601DateFormatter` default).
    `java.time.Instant` (NOT `kotlinx.datetime`) — already on JDK 17, whose `toString()` would
    otherwise emit fractional seconds; the custom formatter pins the format.
  - `Base64DataSerializer` — a `KSerializer<ByteArray>` emitting/parsing a **base64 String**,
    matching Swift `Data` JSON encoding (Swift `Data` ⇒ base64 string). Applied to every
    Swift-`Data` mirror field.
  - `canonicalEncode(...)` — for the WI-2 conformance: serialize to `JsonElement`, recursively
    **sort object keys**, and the conformance compares the **parsed `JsonElement`** of the
    iOS vector vs the Kotlin re-encode (semantic equality — robust to Swift `.prettyPrinted`'s
    `" : "` colon-spacing, which a byte compare would trip on). The iOS section encoder uses
    `.prettyPrinted + .sortedKeys` (`BackupDataCollector.swift:300`, `WebDAVProvider.swift:222`)
    — but interop only needs both sides to DECODE each other + agree on the parsed value, not
    byte-identical whitespace, so the conformance is parsed-element equality.
- `vreader/contracts/backup/BackupMetadata.kt` (NEW — Gate-2 Medium) — `BackupMetadata`, the
  `metadata.json` written into every ZIP before the sections (`BackupProvider.swift:15`); the
  Android backup-list UI will need it. Modeled in WI-1.
- `vreader/contracts/backup/BackupSections.kt` — the section envelopes + row DTOs as
  `@Serializable` `data class`es, field-name-identical to `BackupSectionDTOs.swift`:
  - **WI-1 (core identity-bearing)**: `BackupAnnotationsEnvelope` (`highlights`/`bookmarks`/
    `notes` → `BackupHighlight`/`BackupBookmark`/`BackupNote`), `BackupPositionsEnvelope` →
    `BackupPosition`, `BackupCollectionsEnvelope` → `BackupCollection`,
    `BackupLibraryManifestEnvelope` → `BackupLibraryEntry` (incl. optional
    `sourceCanonicalKey`). UUIDs modeled as `String` (Swift `UUID` encodes as a string);
    Dates as `@Serializable(IsoInstantSerializer::class) Instant`.
  - **WI-2 (remaining sections + conformance)**: `BackupSettingsEnvelope` +
    `BackupDefaultsValue` (the type-tagged `{type,value}` union — a custom
    `KSerializer`/sealed mirror of the Swift enum), `BackupBookSourcesEnvelope` →
    `BackupBookSource`, `BackupPerBookSettingsEnvelope` → `BackupPerBookSettingsEntry`
    (+ a Kotlin `PerBookSettingsOverride` mirror), `BackupReplacementRulesEnvelope` →
    `BackupReplacementRule`, `BackupReadingHistoryEnvelope` (schema-v2), and
    `BackupAIConversationsEnvelope` (schema-v3).

**Files OUT of scope** (separate future features): any WebDAV client / networking; the ZIP
read/write; the restore-import pipeline into Room; `:app` wiring; ALL user-facing UI
(`needs-design #1767`); the iOS side (unchanged — it is the reference).

## Prior art / project precedent / rejected alternatives

- **Precedent**: `VReaderLocator.kt` / `Locator.kt` in `:identity` already use kotlinx
  `@Serializable` + a `CANONICAL_JSON` instance; `IdentityConformanceTest.kt` already proves
  golden-vector parity against `contracts/vectors/`. This feature follows that exact pattern
  for the backup sections.
- **Reference**: `vreader/Services/Backup/BackupSectionDTOs.swift` (+ `BackupReadingHistory
  .swift`, `BackupAIConversations.swift` for the v2/v3 sections) is the authoritative shape.
- **Date strategy (parity-critical)**: iOS uses `.iso8601` (no fractional seconds, UTC). The
  Kotlin serializer MUST match exactly — the single biggest parity risk. Rejected: epoch
  seconds/millis (Swift `.iso8601` is a string, not a number).
- **Rejected**: putting DTOs in `:app`. They belong in `:identity` so the conformance lane
  (which has no `:app` dep) can test the same code, exactly like the locator/identity DTOs.
- **Rejected**: one mega-WI for all 10 sections — WI-2's settings type-tagged union +
  per-book-override + book-source-rule DTOs pull in more iOS types and a custom serializer, so
  they split cleanly from the primitive-field core sections.

## Work items

| WI | Scope | Tier |
|---|---|---|
| WI-1 | `BackupSchema` + `BackupRestoreError` + `BackupJson` (`explicitNulls=false`/`IsoInstantSerializer`/`Base64DataSerializer`/`canonicalEncode`) + `BackupMetadata` + the 4 core identity-bearing sections (annotations/positions/collections/library-manifest). Tests: round-trip, **omitted-null shape**, **base64-Data shape**, **ISO8601 exact-string**, sorted-key canonical, edge cases | foundational |
| WI-2 | remaining 6 sections (settings type-tagged value w/ base64 data, book-sources w/ rule data, per-book-settings + override, replacement-rules, reading-history, ai-conversations) + `contracts/vectors/backup-*.json` golden vectors generated from the iOS encoder + Kotlin `BackupConformanceTest` (decode vector → re-encode → parsed-`JsonElement` equality) wired like `IdentityConformanceTest` | foundational |

Both WIs are **foundational** (pure DTOs/serializers, no user-observable behavior) → unit +
conformance tests are sufficient, no device verification (rule 47 Gate-5 tier).

## Test catalogue

- `BackupSchemaTest` (WI-1): schema constants equal the contract (3 / {1,2,3} / 1);
  `BackupRestoreError` equality.
- `IsoInstantSerializerTest` (WI-1): emits a known instant as the **exact** string
  `2026-06-20T16:30:00Z` (assert NO fractional seconds, `Z` suffix, UTC); parses the same back
  to the instant; a non-zero-nanos instant emits **truncated to seconds** (no fractional —
  Swift parity); a fractional-second INPUT string is **explicitly decided** (parse-and-truncate
  vs reject — defaulting to lenient parse, asserted, and revisited against an iOS vector in
  WI-2); pre-1970 + far-future dates.
- `BackupJsonShapeTest` (WI-1, the Gate-2-r1 Highs): a nil optional key is **OMITTED** from the
  JSON (`explicitNulls=false` — assert the substring `"note"`/`"sourceCanonicalKey"` is ABSENT
  when null); a `ByteArray` field serializes as a **base64 String** (assert the value is the
  base64 of known bytes, and decodes back byte-equal); `canonicalEncode` output has
  **lexicographically sorted** object keys (assert key order in a nested object).
- `BackupSectionsTest` (WI-1): each core envelope encodes→decodes→equals; field NAMES match the
  Swift DTO (`"bookFingerprintKey"`, `"locatorJSON"`, `"fingerprintKey"`, `"blobPath"`,
  `"schemaVersion"`, …); empty collections; a `BackupLibraryEntry` with
  `sourceCanonicalKey = null` (omitted) AND a present one (round-trips); CJK title/author; a
  highlight with `note = null`; `BackupMetadata` round-trip.
- WI-2: `BackupDefaultsValueTest` (each tagged case bool/int/double/string/**data (base64)**
  round-trips + the `{type,value}` shape matches Swift); the remaining envelopes' round-trips;
  `BackupConformanceTest` decodes every iOS-generated `contracts/vectors/backup-*.json` and
  re-encodes to a payload whose **parsed `JsonElement`** equals the vector's parsed element
  (semantic cross-platform proof — robust to whitespace/colon-spacing; toolchain-gated like the
  locator lane). Vectors include non-empty `Data` + nil-optional fields.

## Risks + mitigations

- **R1 — ISO8601 date parity (biggest risk, Codex-flagged).** Swift `.iso8601` =
  `ISO8601DateFormatter` default (`yyyy-MM-dd'T'HH:mm:ss'Z'`, UTC, no fractional). Use
  `java.time.Instant` + a fixed UTC second-precision `DateTimeFormatter` (NOT `Instant.toString()`,
  which emits fractional nanos); exact-string test in WI-1. The byte-exact golden vectors (WI-2)
  come from the REAL iOS encoder, not hand-guessed.
- **R2 — Swift `Codable` JSON shape parity (Gate-2-r1 Highs).** Three concrete shape rules,
  all tested in WI-1 (not deferred to WI-2 vectors): (a) **nil optionals are OMITTED** —
  `explicitNulls = false` (Swift drops nil keys; kotlinx emits explicit null by default);
  (b) **`Data` ⇒ base64 String** — a `Base64DataSerializer` on every `ByteArray` (Swift `Data`
  is base64); (c) **canonical = sorted keys** — `canonicalEncode` recursively sorts object keys
  (iOS uses `.sortedKeys`). The WI-2 conformance compares **parsed `JsonElement`** equality, not
  bytes, so Swift `.prettyPrinted` colon/whitespace differences don't cause false failures.
- **R3 — UUID representation.** Swift `UUID` JSON-encodes as an uppercase string; model as
  `String` (the wire type) — no Kotlin UUID dependency, and restore re-attaches by
  `fingerprintKey` not by these ids.
- **R4 — `PerBookSettingsOverride` / book-source rule / `BackupMetadata` shapes** (WI-1/WI-2)
  may be richer than the reference file shows; each WI reads the ACTUAL iOS type
  (`BackupProvider.swift` for `BackupMetadata`, the per-book/book-source DTOs) before mirroring.

## Revision history

- **v1** (2026-06-20) — Gate-1 draft.
- **v2** (2026-06-20) — Gate-2 audit round 1 (Codex `019ee0c3`). All findings addressed:
  - *(High)* iOS section JSON is `.prettyPrinted + .sortedKeys` (not default order as v1 said)
    → added `canonicalEncode` (recursive key sort) + parsed-`JsonElement`-equality conformance.
  - *(High)* Swift omits nil optionals → `explicitNulls = false` + an omitted-null shape test in
    WI-1 (not just `encodeDefaults`).
  - *(High)* Swift `Data` ⇒ base64 String → `Base64DataSerializer` on every `ByteArray` + a
    base64 shape test in WI-1.
  - *(Medium)* ISO8601 → `java.time.Instant` + fixed UTC second-precision formatter; tightened
    the fractional-seconds test wording.
  - *(Medium)* `metadata.json` / `BackupMetadata` was omitted → added to WI-1 (Android's
    backup-list UI needs it).
  - *(Low ×2)* `:identity` placement confirmed correct; canonicalization/null/base64 tests
    moved INTO WI-1 (so WI-2 vectors aren't the first place a parity bug surfaces).
  - Model fields (`BackupHighlight`, `BackupPosition`, `BackupLibraryEntry.sourceCanonicalKey`,
    schema constants) confirmed to exist; #113 = DTO-model-only cohesion confirmed (WebDAV
    client + restore pipeline stay separate features).

## Backward compat

Purely additive — a brand-new Kotlin module file set. No Android schema change, no iOS change,
no existing-test impact. The DTOs accept schema 1/2/3 archives by construction (the
`schemaVersion` field + `kBackupAcceptedSchemaVersions`).

## Acceptance criteria

1. Kotlin `@Serializable` DTOs exist for the core identity-bearing backup sections + manifest,
   field-name-identical to `BackupSectionDTOs.swift`, in `:identity`.
2. Dates serialize as ISO8601-UTC-no-fractional strings (exact-string test green).
3. Every section round-trips (encode→decode→equal) incl. edge cases (empty, null, CJK,
   pre-1970/far-future dates, `sourceCanonicalKey = null`).
4. (WI-2) golden-vector `BackupConformanceTest` proves the Kotlin DTOs decode the
   iOS-generated `contracts/vectors/backup-*.json` and re-encode canonical-equal.
5. Unit suite green; no `:app`/UI/device involvement (foundational tier).
