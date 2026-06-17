# Feature #42 Phase 2 WI-4 — Kindle convert-on-import (BookImporter integration)

> **⚠️ SUPERSEDED (cross-platform identity only) — bug #354 / `contracts/identity/DECISION.md` (2026-06-17).**
> This plan's "identity = the converted EPUB's own fingerprint" decision (below, incl. the §"Decision #1" audit row) is correct for iOS LOCAL storage but is NO LONGER the canonical CROSS-PLATFORM identity. The canonical converted-Kindle identity is the **SOURCE-file bytes**; the converted-EPUB fingerprint is now classified iOS-platform-local. The BookImporter implementation + migration to compute/persist the source-bytes canonical key is tracked as the #354 follow-up. The rest of this plan (the conversion pipeline, render-format wiring) is unaffected.

Gate-1 design for wiring the now-complete MOBI→EPUB converter (WI-1a..2c:
`Libmobi.decodeParts` → `MobiEPUBAssembler.assemble` → `MobiEPUBConverter`)
into the import flow. High-blast-radius (core import path), so this design is
audited (Gate 2) before any code (Gate 3).

## Problem

AZW3/MOBI/KF8/PRC books currently import as their native format and render via
the Foliate spike (`FoliateBilingualContainerView`). Feature #42's goal is to
unify EPUB-family reading on the Readium engine. Phase 2 makes Kindle books join
that path by **converting them to EPUB at import time**, so a Kindle book
becomes an ordinary `.epub` in the library and renders via whatever EPUB engine
is active (today the Foliate EPUB bridge; Readium once its human-gated flag
flips in Phase 1 WI-14/15).

## Surface area (file-by-file)

- **`vreader/Services/BookImporter.swift`** — insert a conversion step between
  format resolution (Step 1) and hashing (Step 5). When the flag is ON and the
  resolved format is a Kindle format, convert the file to an EPUB on disk, then
  run the EXISTING pipeline (hash / fingerprint / sandbox-copy / persist) over
  the **converted .epub**, not the original. The original is retained alongside.
- **`vreader/Services/FeatureFlags.swift`** — add `kindleConvertOnImport`
  (default **OFF**). Gating mirrors Phase 1's `readiumEPUBEngine`: the capability
  ships dark; flipping default is a separate, deliberate decision.
- **`vreader/Services/Libmobi/MobiEPUBConverter.swift`** — add a
  `convertToFile(mobiPath:title:destinationDir:) throws -> URL` convenience that
  writes the `.epub` Data to a temp file (the importer needs a file URL for the
  existing sandbox-copy + hash path, which is file-based). Reuses `convert`.
- **`vreader/Models/Book.swift`** (or the import metadata) — record
  `converterVersion: Int` + `originalFormat: BookFormat` + a pointer to the
  retained source, so a future converter improvement can re-convert. **Scoped
  minimally**: if adding columns triggers a schema migration, that is its own
  foundational sub-WI (WI-4a) audited separately; WI-4b is the importer wiring.

### Files OUT of scope
- The reader dispatcher (`ReaderContainerView`) — a converted book is a `.epub`,
  so it routes through the existing EPUB path with **zero dispatcher change**.
- The Readium engine itself (Phase 1) — converted EPUBs ride whatever EPUB
  engine is active; this WI does not touch engine selection.
- Existing already-imported AZW3 books — untouched (no retroactive migration).
- Any UI — convert-on-import is a silent backend transform; the library shows
  the book exactly as today (no new surface → no `needs-design` per rule 51).

## Key design decisions (v3 — converged after Gate-2 rounds 1 + 2)

The two audit rounds converged on one root principle: **the converted book is a
first-class EPUB**, with self-consistent identity (its fingerprint describes its
own blob bytes). Everything else follows and simplifies.

1. **Title-neutral converter → deterministic, self-consistent EPUB.** *(Resolves
   round-1 High-2 AND round-2 High-1 together.)* The converter no longer takes a
   caller-supplied display title; it derives the EPUB's internal `<dc:title>`
   from the **AZW3's own embedded metadata** (`mobi_meta_get_title`), which is a
   deterministic function of the source. So the same Kindle file always converts
   to byte-identical EPUB regardless of any import-time title override. The book's
   `fingerprintKey` is then the **converted EPUB's own** `DocumentFingerprint`
   (`epub:{sha256-of-the-epub}:{epub-byteCount}`) — it describes the stored blob,
   so backup upload / manifest / restore re-verification all round-trip
   *(**SUPERSEDED for cross-platform identity by bug #354 / `contracts/identity/DECISION.md`**: the CANONICAL cross-platform identity for converted-Kindle books is the SOURCE-file bytes; this converted-EPUB `fingerprintKey` is now classified iOS-platform-local. The implementation change is tracked separately — see the #354 follow-up.)*
   correctly (the round-2 invariant that fingerprint == blob is preserved). Dedup
   works: same source → same EPUB → same key.
2. **No render-format split, no identity schema migration.** *(Resolves round-2
   High-2 + Medium.)* Because the converted book genuinely IS an EPUB —
   `fingerprint.format = .epub`, `book.format = "epub"`, `originalExtension =
   "epub"` (the blob), blob bytes = the EPUB — **every existing consumer
   (dispatcher, settings, search, TOC, file-path resolution, DebugBridge,
   backup) routes it correctly with zero changes.** There is no azw3/epub
   split-brain. The only Kindle trace is provenance (below).
3. **Store ONLY the converted EPUB as the canonical blob.** *(Resolves round-1
   High-4.)* Single canonical file; backup/restore/path-resolution unchanged.
   Re-conversion after a `converterVersion` bump = user re-imports the Kindle
   file (deferred second-blob "source asset" model is out of scope). Documented
   deviation from BUILD-RECIPE's "retain original source", justified by the
   single-blob backup architecture.
4. **The converted EPUB is SELF-DESCRIBING (title + author + cover).** *(v4 —
   resolves round-3 High-1.)* The converter embeds, from the AZW3's own
   deterministic metadata: `<dc:title>` (`mobi_meta_get_title`), `<dc:creator>`
   author (`mobi_meta_get_author`), and a **cover** — the cover image resource
   (libmobi exposes it; fall back to the first image resource) referenced by an
   OPF `<meta name="cover" content="…"/>` (EPUB2) + `properties="cover-image"`
   (EPUB3). So on a fresh restore/new device, `EPUBMetadataExtractor` recovers
   title/author/cover **from the blob itself** — no metadata is lost. All three
   are deterministic functions of the source, so the EPUB bytes (and thus the
   fingerprint) stay source-deterministic (decision #1 holds).
5. **Kindle-origin metadata is BEST-EFFORT, non-load-bearing.** *(v4 — resolves
   round-3 High-2 by scoping, not by a backup-architecture change.)* Because the
   converted EPUB is a self-describing first-class EPUB (decision #4), the book
   is fully correct as an EPUB **without** knowing it was Kindle-sourced. So
   `ImportProvenance.convertedFromKindle` / `converterVersion` are **optional,
   local, observability-only** hints — nothing in correctness, rendering,
   backup, or restore depends on them. It is ACCEPTABLE that they are not carried
   in the backup manifest and are lost on restore/dedupe-replace: a restored
   converted book is simply a valid EPUB. (Re-conversion after a converter
   improvement is inherently a *local re-import* operation anyway — we don't
   retain the source blob, decision #3 — so durable origin would buy nothing.)
   This removes the round-2/3 pressure to change `BackupSectionDTOs` / restore /
   `PersistenceActor` provenance-merge. The fields are decoded with backward-
   compatible defaults (decision #6).
6. **Display metadata + cover also set at import from the SOURCE.** `Book.title`/
   `author`/`coverImagePath` are set at import from `AZW3MetadataExtractor` on
   the source (not `EPUBMetadataExtractor` on the converted file) — same values
   the EPUB embeds (decision #4), so import-time and restore-time metadata agree.
   *(This also resolves round-1 High-1 — metadata no longer comes from running
   `EPUBMetadataExtractor` against the AZW3 path; WI-4b threads the source URL
   for metadata and the converted EPUB URL for the stored blob explicitly.)*
7. **Conversion runs OFF the main actor.** *(Gate-2 r1 Medium: `importFile` is
   entered from a `@MainActor` task and doesn't suspend until `ContentHasher.hash`;
   a CPU-bound libmobi convert in the pre-hash slot would stall the UI.)*
   `convert` is `Sendable`/stateless (WI-2c) — WI-4b invokes it via an explicit
   off-main hop (`Task.detached` or a converter actor) and `await`s it before
   re-entering the file pipeline.
8. **Conversion-failure fallback is limited to SEMANTIC failures.** *(Gate-2 r1
   Low.)* Only `MobiDecodeError` (`.parseFailed` DRM, `.corrupt`, `.noMarkup`)
   and `MobiEPUBError` fall back to native AZW3 import (so a user never loses the
   ability to import a book the converter can't yet handle). **Filesystem/temp-
   write failures from `convertToFile` are REAL import errors** (not silently
   masked). Temp `.epub` artifacts are cleaned up on every path (success,
   fallback, throw) via `defer`.
9. **Gated, default OFF.** `kindleConvertOnImport` OFF → today's behavior exactly
   (AZW3 imports native, renders via Foliate). The flip is a later, separate,
   human-gated decision after WI-5 device verification — symmetric with the
   Readium rollout.

## Work-item sequencing (v4 — 2 WIs; self-describing EPUB; no schema/dispatcher WI)

The title-neutral / converted-book-IS-an-EPUB principle removes the SchemaV9
identity migration AND the render-format dispatcher split that the v2 (flawed)
design needed. The split is two WIs:

- **WI-4a** *(foundational — self-describing title-neutral converter + flag +
  file helper)* —
  (1) the decode layer (`Libmobi.decodeParts` companion) extracts the source's
  own **title** (`mobi_meta_get_title`), **author** (`mobi_meta_get_author`), and
  **cover** (libmobi cover resource, else first image) — all deterministic
  functions of the source.
  (2) the converter **embeds title + author + cover** into the EPUB OPF
  (self-describing, decision #4) and is **title-neutral** w.r.t. callers
  (`convert(mobiPath:)` drops the caller `title` param) → output is a
  deterministic function of the source only.
  (3) `FeatureFlags.kindleConvertOnImport` (default OFF).
  (4) `MobiEPUBConverter.version` constant.
  (5) `convertToFile(mobiPath:destinationDir:) throws -> URL` (off-main-safe;
  temp cleanup on throw).
  Unit-tested: determinism (same source → byte-identical EPUB regardless of any
  display title); author + cover present in the OPF + recoverable by
  `EPUBMetadataExtractor`. No behavior change (flag off). ~1 PR.
- **WI-4b** *(behavioral — importer wiring, gated)* — flag-ON Kindle → off-main
  `convertToFile` → run the EXISTING file pipeline over the converted `.epub`
  (so identity/fingerprint/blob are all the EPUB's, self-consistent); the book's
  **display** title/author/cover come from `AZW3MetadataExtractor` on the source
  (matching what the EPUB embeds); `ImportProvenance` records the **optional,
  best-effort** `convertedFromKindle` + `converterVersion` (decision #5 —
  optional fields, backward-compat decode); semantic-failure fallback to native
  AZW3. ~1 PR. WI-5 device-verifies the rendered result.

No schema migration for identity (decision #2), no dispatcher change (decision
#2), no second blob (decision #3), no backup-manifest change (decision #5 — the
EPUB is self-describing so origin is non-load-bearing). The only additive
persistence is the optional provenance fields (decision #5/#6).

## Test catalogue

- `FeatureFlagsTests` — `kindleConvertOnImport` default OFF; override on/off.
- `MobiEPUBConverterTests` — `convertToFile` writes a readable `.epub`; the
  written file round-trips (reuse the existing real-AZW3 enabled-if case);
  **self-describing**: the OPF carries `<dc:title>` + `<dc:creator>` + a cover
  (`<meta name="cover">` / `properties="cover-image"`), and `EPUBMetadataExtractor`
  on the converted bytes recovers title + author + cover (round-3 High-1);
  **title-neutral determinism**: same source → byte-identical EPUB irrespective
  of any caller display title.
- `ImportProvenanceTests` — pre-v3 provenance payloads (no
  `convertedFromKindle`/`converterVersion`) still decode (optional fields +
  backward-compat defaults — round-3 Medium).
- `BookImporterTests` (in-memory container, real AZW3 fixture via the
  skip-when-absent guard; synthetic for CI):
  - flag OFF + AZW3 → book persists as `.azw3` (today's behavior, regression).
  - flag ON + AZW3 → book persists as a first-class `.epub`: `book.format` =
    "epub", `fingerprint.format` = .epub, the stored blob is a valid OCF whose
    sha256/byteCount MATCH the fingerprint (blob-identity invariant); the display
    title comes from the AZW3 metadata; re-importing the same AZW3 dedupes (same
    title-neutral EPUB → same key) even under a different title override. (NO
    sidecar source is retained — decision #3.)
  - flag ON + conversion failure (a deliberately-corrupt/DRM-ish fixture, or a
    converter stub that throws a semantic error) → falls back to native `.azw3`
    import (no loss). A `convertToFile` IO/write failure is a REAL error, NOT a
    silent fallback (decision #7).
  - flag ON + non-Kindle (txt/epub) → untouched (no conversion attempted).

## Risks + mitigations

- **R1 — changes how AZW3 renders (Foliate → EPUB path).** Mitigated by the flag
  (default OFF) + the fact that the EPUB path is itself being unified under #42.
  The flip is human-gated, after WI-5 device verification.
- **R2 — converted EPUB fidelity (CSS/footnotes/CJK pagination) below the
  Foliate-native AZW3 render.** This is the WI-3 fidelity-spike concern; WI-5
  device verification on the real CJK book is the gate before any flag flip.
- **R3 — peak memory (in-memory convert of a large book).** Documented in
  `MobiEPUBConverter` (Codex WI-2c Low); `convertToFile` streams the result to
  disk, bounding the resident EPUB copy to the convert call.
- **R4 — no identity schema migration needed (v3).** Because the converted book
  is a first-class EPUB (decision #1/#2), the canonical identity fields are
  untouched; the only possibly-additive persistence is a provenance note
  (`convertedFromKindle`/`converterVersion`), which is not an identity field and
  migrates additively (legacy rows default to "not converted").

## Backward compatibility

- Flag OFF (default) → byte-for-byte today's behavior. No migration.
- Existing AZW3 books in libraries → untouched; they keep rendering via Foliate.
- Flag ON, then OFF later → new imports go native again; already-converted books
  remain first-class `.epub`s (valid EPUBs with self-consistent identity; no
  corruption, no orphaned blob). No sidecar source is kept (decision #3), so
  there is nothing to clean up; "revert to native" = re-import the Kindle file.

## Audit fixes applied (Gate-2 round 1)

Codex (gpt-5.4, high, via `scripts/run-codex.sh`) returned **MAJOR GAPS**: 4
High + 1 Medium + 1 Low. All addressed in v2:

| Finding | Severity | Resolution in v2 |
|---|---|---|
| Metadata extracted from the original `fileURL`, not the converted EPUB | High | Decision #4 — thread source + converted URLs; metadata/cover from the source via `AZW3MetadataExtractor`. |
| Identity over converted bytes is unsound (title is embedded in the EPUB) | High | Decision #1 — identity = SOURCE fingerprint + `converterVersion`, not converted bytes. |
| No schema room for `converterVersion`/`originalFormat`/render-format | High | Decision #2 + WI-4b — a mandatory, separately-audited SchemaV9 foundational WI. |
| Retained sidecar source breaks single-blob backup/restore/path-resolution | High | Decision #3 — store ONLY the converted EPUB as the canonical blob; re-conversion = re-import (sidecar source deferred). |
| CPU-bound convert in the pre-hash slot stalls the `@MainActor` importer | Medium | Decision #5 — explicit off-main hop before re-entering the file pipeline. |
| Native-fallback masks IO faults + leaks temp files | Low | Decision #6 — fallback only on semantic `MobiDecodeError`/`MobiEPUBError`; IO failures are real errors; `defer` temp cleanup. |

## Audit fixes applied (Gate-2 round 2)

Round-2 re-audit (gpt-5.4, high, via `scripts/run-codex.sh`) returned **MAJOR
GAPS** again — but the findings converged on one root flaw in v2 and pointed to
a *simpler* fix. All addressed in v3:

| Finding | Severity | Resolution in v3 |
|---|---|---|
| Source-AZW3 identity over an EPUB blob breaks the blob-identity invariant (backup/restore/materializer verify fingerprint == blob bytes) | High | Decision #1 — identity is the **converted EPUB's own** fingerprint (matches the blob); source identity is NOT used as the canonical key. |
| Render-format split mis-wires every `book.format`/`fingerprint.format` consumer (settings/search/TOC/path/DebugBridge), not just the dispatcher | High | Decision #2 — the converted book IS a first-class EPUB (epub fingerprint + format + blob), so **all consumers route it correctly with zero changes**; the split is removed. |
| SchemaV9 still mis-specified (originalExtension is the canonical blob ext, not provenance) | Medium | Decision #2/#4 — no identity migration; the blob ext is "epub" (correct); Kindle origin lives in provenance only. |
| Plan self-contradicts (drops sidecar in Decision 3, retains it in test/back-compat) | Low | Test catalogue + Backward-compat rewritten to the single-blob, no-sidecar model. |

The v3 design is **simpler than v2** (2 WIs, no schema/dispatcher WI) because
the title-neutral converter makes the converted book self-consistent.

**Status: pending Gate-2 round 3** (the final allowed round per rule 47). v3 is a
material simplification, so it needs one confirming re-audit before Gate-3
implementation. If round 3 is not clean, escalate to the user.

## Audit fixes pending (Gate-2 round 3 — RULE-47 LIMIT REACHED → ESCALATED)

Round-3 re-audit (gpt-5.4, high, via `scripts/run-codex.sh`) confirmed **"the v3
identity model itself is sound"** — the core identity/dedup/blob-invariant
question that failed rounds 1+2 is RESOLVED. But it surfaced 2 new High + 1
Medium (narrower, but real):

| Finding | Severity | Nature |
|---|---|---|
| Converted EPUB embeds title only, not author/cover → restore (re-extracts from blob) loses author+cover | High | Converter must embed author (`mobi_meta_get_author`) + cover (first image resource + OPF `<meta name="cover">`) so the EPUB is self-describing. Tractable converter enhancement. |
| Kindle-origin in provenance isn't durable — manifest doesn't carry provenance, restore synthesizes fresh, dedupe replaces it | High | Needs durable origin (manifest carriage or an immutable field + merge-not-replace on dedupe). More involved (touches backup DTOs / restore). |
| Non-optional `ImportProvenance` fields break decoding pre-v3 rows/backups | Medium | Optional fields + backward-compat `init(from:)` + decode tests. Easy. |

**Rule 47 limit reached → escalated to the user.** The user chose **one more
design round (v4)** before any code. All 3 round-3 findings are addressed in v4
(below).

## Audit fixes applied (Gate-2 round 3 → v4; user-approved 4th round)

Round-3 confirmed the identity model sound; its 2 High + 1 Medium are resolved in
v4 — notably WITHOUT a backup-architecture change, by making the EPUB
self-describing (so origin metadata becomes non-load-bearing):

| Finding | Severity | Resolution in v4 |
|---|---|---|
| Converted EPUB lacked author/cover → restore loses them | High | Decision #4 — the converter embeds title + author (`mobi_meta_get_author`) + cover into the OPF; `EPUBMetadataExtractor` recovers them from the blob. Deterministic (source metadata), so identity stays stable. |
| Provenance origin not durable across restore/dedupe | High | Decision #5 — scoped origin to **best-effort, non-load-bearing**: a self-describing converted EPUB is fully correct without it, so its loss on restore/dedupe is acceptable. No `BackupSectionDTOs`/restore/merge change needed. |
| Non-optional `ImportProvenance` fields break old-row decode | Medium | Decision #5/#6 — fields are optional with backward-compat `init(from:)` defaults; `ImportProvenanceTests` decode pre-v3 payloads. |

**Status: pending Gate-2 round 4 confirmation.** v4 must return zero open
Critical/High/Medium before Gate-3 implementation begins (per the user's "one
more round before code" directive).

## Revision history

- v1 (2026-06-01) — initial Gate-1 design.
- v2 (2026-06-01) — Gate-2 r1 fixes: source-fingerprint identity; SchemaV9 +
  render-format split; single-blob; off-main; semantic fallback. WI 2 → 4.
- v3 (2026-06-01) — Gate-2 r2 fixes: **title-neutral converter → converted book
  is a first-class EPUB** (identity = EPUB's own fingerprint, matching the blob).
  Removes the render-format split AND the identity schema migration; WI 4 → 2.
- v4 (2026-06-01) — Gate-2 r3 fixes (user-approved 4th round): **self-describing
  EPUB** (embed title+author+cover) so restore recovers metadata; **best-effort
  non-load-bearing** Kindle-origin (no backup-architecture change); optional
  provenance fields with backward-compat decode. Pending Gate-2 r4 confirmation.
