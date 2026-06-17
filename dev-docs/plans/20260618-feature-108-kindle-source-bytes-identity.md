# Feature #108 — Source-bytes canonical fingerprint for converted-Kindle

Status: Gate-1 draft (2026-06-18). The #354 obligation: make iOS persist the
SOURCE-file-bytes canonical fingerprint for converted-Kindle (`.azw3`/`.mobi`/
`.prc`) as the cross-platform identity, matching the decided contract
(`contracts/identity/DECISION.md`, `fingerprint.md`, `backup-format.md`).

## Problem

`contracts/identity/DECISION.md` decides: converted-Kindle cross-platform
identity = SHA-256 of the **SOURCE** `.azw3`/`.mobi`/`.prc` bytes, NOT the
converted EPUB. iOS does not match: when `kindleConvertOnImport` is ON,
`BookImporter` hashes the **converted EPUB** and stores `epub:{sha}:{bytes}` as
`fingerprintKey` (`BookImporter.swift:208-217`). So the same Kindle book imported
on iOS (converted) and Android (native `.azw3`) gets different canonical keys →
library/backup identity silently diverges once an Android client exists. Latent
today (no Android client), but it's the standing #354 obligation.

## The hard constraints (why this is migration-sensitive)

1. **`BookFormat` drives BOTH identity AND reader routing.** `fingerprintKey`'s
   `format` component selects the reader: `epub:` → EPUB/Readium engine,
   `azw3:` → Foliate native. `kindleConvertOnImport` EXISTS to route Kindle
   books through the better EPUB engine. So we CANNOT simply change
   `fingerprintKey` to `azw3:{source}` — that would re-route every converted
   book back to Foliate, regressing the rendering that convert-on-import was
   built to provide (feature #42 "Decision #1" chose the converted-EPUB
   fingerprint SPECIFICALLY for this).
2. **The source bytes are discarded.** After conversion the source `.azw3` is
   not stored — only `provenance.convertedFromKindleExtension` (the extension
   string) is kept (`ImportProvenance.swift`). So **existing** converted-Kindle
   books physically cannot be re-keyed to source-bytes (the bytes are gone) —
   they can only be grandfathered.
3. **Blob-identity invariant.** `BookFileImportFinalizer.finalize()` verifies
   `downloadedHash == entry.sha256` (blob bytes) AND
   `importResult.fingerprintKey == entry.fingerprintKey` (re-import reproduces
   the key) (`BookFileImportFinalizer.swift:56,88`). Today the blob is the
   converted EPUB and the key is the EPUB key — consistent. Any source-key change
   must keep this invariant intact.

## Recommended design — source key as an ADDITIVE canonical identity; EPUB key stays the local primary

Per the contract's own framing — "iOS's converted-EPUB fingerprint is an
explicitly **platform-local** storage detail, not the cross-platform identity;
the source→converted mapping is the local seam" — the lowest-risk faithful design
is to **persist BOTH**:

- `fingerprintKey` (the SwiftData `@Attribute(.unique)` primary key) **stays the
  converted-EPUB key** — drives local storage, reader routing (EPUB engine), and
  the blob-identity invariant. UNCHANGED. No re-keying, no rendering regression,
  no SwiftData primary-key migration, no blob change.
- A NEW persisted field `sourceCanonicalKey: String?` on `Book` = the
  **source-bytes key** (`azw3:{sha256_of_source}:{source_byte_count}`) = the
  **cross-platform canonical identity**. Computed at import for converted-Kindle
  books by hashing the source BEFORE conversion (the source file is in hand at
  `BookImporter.swift:164-176`). `nil` for native imports and for existing
  converted books (source bytes gone → grandfathered).

This satisfies the contract: the source-bytes key IS computed + persisted as the
canonical identity; the converted-EPUB `fingerprintKey` is the documented
platform-local detail; `sourceCanonicalKey` is the source→converted seam.

### Open design question for Gate-2 (Codex) — the backup leg

For cross-platform restore (Android importing an iOS backup), does the backup
need the source **blob** (so Android re-derives the source key + renders via its
own path), or only the source **key** as manifest metadata (so Android dedups
identity but the blob stays the EPUB it can render directly)?

- **Option B1 (recommended): carry the source KEY in the manifest, blob stays the
  EPUB.** `BackupLibraryEntry` gains `sourceCanonicalKey: String?`. Cross-platform
  dedup matches on it; the blob is the converted EPUB (Android renders EPUB fine).
  Blob-identity invariant unchanged (blob = EPUB, `entry.fingerprintKey` = EPUB
  key, `entry.sha256` = EPUB hash). Cheapest; no re-conversion on restore; no
  double storage. Cost: Android importing the EPUB blob natively would derive the
  EPUB key, so identity match relies on the carried `sourceCanonicalKey`
  metadata, not on re-hashing the blob.
- **Option B2: store the SOURCE `.azw3` as the blob, re-convert on restore.**
  Clean "blob bytes == source key" but: doubles local storage (keep source +
  converted) or forces re-conversion on every open, and changes which artifact
  restore yields. Heavier; rejected unless Codex argues the invariant demands it.

The plan RECOMMENDS B1 and asks Codex to confirm it's contract-faithful (the
contract says "store the source blob, OR map" — B1 is the map).

## Surface area (file-by-file)

- **`vreader/Services/BookImporter.swift`** — in the convert-on-import branch
  (~164-217): hash the SOURCE bytes (`ContentHasher.hash(fileAt: sourceURL)`)
  BEFORE `MobiEPUBConverter.convertToFile`, build the source `DocumentFingerprint`
  (`format: .azw3`), and thread its `canonicalKey` through to the `BookRecord` as
  `sourceCanonicalKey`. The existing EPUB-fingerprint path is unchanged. On the
  dedupe-hit path, preserve an existing non-nil `sourceCanonicalKey` (mirror the
  `originalExtension` dedupe-preserve, `BookImporterOriginalExtensionTests`).
- **`vreader/Models/Book.swift`** — add `var sourceCanonicalKey: String?` (additive
  optional → lightweight migration). Thread through `init` + `BookRecord`.
- **`vreader/Models/BookRecord.swift`** (+ the record↔model mapping) — add the
  field.
- **`vreader/Models/Migration/SchemaV10.swift`** (NEW) + `SchemaV1.swift` plan
  registration — SchemaV9→V10 is a genuine ADDITIVE column (Book gains
  `sourceCanonicalKey`), so unlike #109 this IS a real lightweight migration that
  fires (entity shape changes). No custom stage.
- **`vreader/Services/Backup/*`** (B1) — `BackupLibraryEntry` gains
  `sourceCanonicalKey: String?`; the collector writes it; restore/dedup may match
  on it. Manifest schema version bump + back-compat (older manifests: nil).
- **`contracts/vectors/`** — add a converted-Kindle source-bytes conformance
  vector driven through the real importer (a real `.azw3` from `test-books/`).

### Files OUT of scope
- `MobiEPUBConverter` / `MobiEPUBAssembler` (the converter is unchanged).
- Reader routing / `ReaderContainerView` (rendering path unchanged — still EPUB).
- Existing books' re-keying (impossible; grandfathered as `sourceCanonicalKey = nil`).
- Android code (computes its own source key natively; no iOS change needed there).

## Work-item sequencing

| WI | Scope | Size | Tier |
|---|---|---|---|
| WI-1 | `Book.sourceCanonicalKey` field + SchemaV10 additive migration + `BookRecord` threading + disk-backed migration test (existing rows → nil) | Medium | Behavioral (persistence) |
| WI-2 | `BookImporter` computes + persists `sourceCanonicalKey` for converted-Kindle (hash source pre-convert; dedupe-preserve); real-`.azw3` importer test + conformance vector | Medium | Behavioral |
| WI-3 (final) | Backup `BackupLibraryEntry.sourceCanonicalKey` (B1) + collector/restore + manifest back-compat; round-trip test | Medium | Behavioral |

## Test catalogue
- `BookSourceCanonicalKeyMigrationTests` — disk-backed V9→V10: existing converted
  book (EPUB-keyed) survives with `sourceCanonicalKey == nil`.
- `BookImporterTests` additions — converted `.azw3` import populates
  `sourceCanonicalKey == azw3:{source_sha}:{bytes}` (real source file); native
  import leaves it nil; dedupe-hit preserves it; flag-OFF native path nil.
- Conformance vector — converted-Kindle source-bytes identity through the real
  importer (corrects the current `BookImporterTests` `.epub`-format assertion
  expectation only where it conflates identity with the source key).
- Backup round-trip — manifest carries `sourceCanonicalKey`; restore preserves it;
  older manifest (nil) restores cleanly.

## Risks + mitigations
- **R1 — re-keying existing books**: NOT done (source bytes gone). Grandfather as
  nil; document that pre-#108 converted books have no cross-platform source key
  until re-imported. Mitigation: `sourceCanonicalKey` is additive/optional.
- **R2 — blob-identity invariant regression**: B1 keeps blob = EPUB, key = EPUB
  key → invariant unchanged. Verified by existing materializer tests staying green.
- **R3 — contract fidelity**: confirm with Codex that "source key persisted as
  canonical identity + EPUB key as platform-local primary" satisfies DECISION.md
  (it mirrors the contract's own wording) — Gate-2.
- **R4 — manifest back-compat**: new field optional; older manifests decode nil.

## Backward compatibility
Existing converted-Kindle books: `sourceCanonicalKey = nil`, unchanged identity,
unchanged rendering, unchanged blob. New imports populate the source key. Older
backups restore with nil. No data re-key, no forced re-conversion.

## Acceptance criteria
1. A converted-Kindle import (real `.azw3`, flag ON) persists
   `sourceCanonicalKey == azw3:{sha256_of_source}:{source_byte_count}` while
   `fingerprintKey` stays `epub:...` and rendering routes to the EPUB engine.
2. Native (flag OFF) import + non-Kindle import → `sourceCanonicalKey == nil`.
3. Dedupe re-import preserves the first import's `sourceCanonicalKey`.
4. Existing V9 converted books migrate to V10 with `sourceCanonicalKey == nil`,
   identity/rendering/blob unchanged.
5. Backup manifest carries `sourceCanonicalKey`; round-trips; older manifests
   (nil) restore cleanly. Blob-identity invariant holds (materializer tests green).
6. A converted-Kindle source-bytes conformance vector passes through the real
   importer.

## Revision history
- v1 (2026-06-18) — Gate-1 draft. Surface mapped via Explore agent. Recommends
  the additive `sourceCanonicalKey` (EPUB key stays local primary) + backup
  option B1. Pending Gate-2 Codex audit.
- v2 (2026-06-18) — **Gate-2 manual-fallback audit** (Codex backend genuinely
  unavailable — `chatgpt.com/backend-api/codex/responses` returned HTTP 404 via
  Cloudflare across 4 consecutive attempts incl. a trivial ping that had
  succeeded ~10 min earlier; a transient backend outage, not quota). Per rule 47
  / rule 53 manual-fallback provision. **The Gate-4 implementation audit will be
  re-run on real Codex once the backend recovers** (a wakeup is scheduled), so
  independent review still gates the merge.

  ### Manual Audit Evidence

  **Files read**: `BookImporter.swift` (convert flow 147-360, fingerprint
  208-220), `Models/Book.swift` (fields), `Models/DocumentFingerprint.swift`,
  `Utils/ContentHasher.swift`, `Models/BookFormat.swift`, `PersistenceActor.swift`
  (`BookRecord` 56-112), `Models/ImportProvenance.swift`,
  `Models/Migration/SchemaV9.swift`, `Services/Backup/BookFileImportFinalizer.swift`,
  `contracts/identity/DECISION.md` + `fingerprint.md`.

  **Symbols verified to exist**: `ContentHasher.hash(fileAt: URL) async throws ->
  HashResult{ sha256Hex, byteCount }`; `BookFormat.isKindleConvertible`;
  `DocumentFingerprint.validated(contentSHA256:fileByteCount:format:)` +
  `.canonicalKey`; `Book` @Model has `fingerprintKey`(unique), `fingerprint`,
  `format`, `originalExtension: String?`, `blobPath`, `provenance` — adding
  `sourceCanonicalKey: String?` is a clean additive optional; `BookRecord` init
  defaults `originalExtension` (same pattern for the new field); `ImportResult`
  carries `fingerprintKey`/`fingerprint`/`provenance`/`isDuplicate`; SchemaV9 is
  head (`Schema.Version(9,0,0)`).

  **Design soundness (verified against the contract)**: DECISION.md states
  verbatim "both platforms compute+persist the source-bytes key as the canonical
  identity. iOS additionally keeps its converted-EPUB fingerprint as a local
  detail" — the additive `sourceCanonicalKey` (canonical) + unchanged
  converted-EPUB `fingerprintKey` (local primary) matches this exactly. The
  contract does NOT require the SwiftData `@Attribute(.unique)` primary key to be
  the source key. Backup B1 ("carry source KEY in manifest, blob stays EPUB") is
  explicitly one of the two options the contract sanctions ("or a
  source-hash→converted-blob mapping"); it preserves the blob-identity invariant
  (blob = EPUB, `entry.sha256` = EPUB hash) and supports Android dedup-by-identity
  on the carried key.

  **Edge cases checked**: source fingerprint uses `format: .azw3` (all Kindle
  exts normalize to the single `.azw3` BookFormat → cross-platform-consistent with
  Android hashing a `.mobi`); dedupe-hit re-import must preserve an existing
  non-nil `sourceCanonicalKey` (mirror `originalExtension` preserve —
  `BookImporterOriginalExtensionTests`); native/non-Kindle import → nil; flag-OFF
  native Kindle → nil (no conversion, identity already = source = `.azw3` key);
  existing V9 converted books → nil after V10 lightweight migration (source bytes
  discarded, can't re-key — grandfathered).

  **Migration**: V9→V10 ADDS `Book.sourceCanonicalKey` → entity shape changes →
  SwiftData lightweight migration fires (contrast #109, whose V10 was
  shape-identical and never fired). No custom stage. NOTE: #109 deleted its
  (shape-identical) SchemaV10; this is a fresh, legitimate SchemaV10 with a real
  field — no conflict.

  **Risks accepted**: existing converted books stay nil (un-re-keyable — source
  bytes gone); B1 relies on trusted manifest metadata for Android identity match
  (Android can't re-hash the EPUB blob to the source key) — acceptable, the
  manifest is authored by the trusted backup collector.

  **Tests planned**: per the Test catalogue above. No findings require a plan
  change; proceeding to Gate-3.
- v3 (2026-06-18) — **Gate-3/Gate-4: WI-2 and WI-3 merged into one PR.** WI-1
  (`Book.sourceCanonicalKey` + SchemaV10) shipped v3.66.37 (PR #1729). The WI-2
  Gate-4 Codex audit (real, 3 rounds) found WI-2 must NOT ship without WI-3 (a
  backup taken between them silently loses the field), so WI-3 (backup-manifest
  carry + restore re-attach) was folded into the WI-2 PR — making it the final WI.
  **5 findings resolved** (audit log
  `.claude/codex-audits/feat-feature-108-wi2-importer-sourcekey-audit.md`): M1
  dedupe-backfill of pre-#108 nil rows (new `setSourceCanonicalKey` persistence
  API); M2 full backup-path threading (projection/entry/collector/
  makeRemoteOnlyRecord/remote-only-insert/materialize-re-attach); M3 source hash
  offloaded to `Task.detached`; M4 source hash computed before conversion; M5
  Phase-1 selective-restore existing-row backfill. Round 3 CLEAN.
