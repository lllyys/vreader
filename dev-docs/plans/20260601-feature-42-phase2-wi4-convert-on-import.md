# Feature #42 Phase 2 WI-4 — Kindle convert-on-import (BookImporter integration)

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

## Key design decisions (revised after Gate-2 round 1)

1. **Identity = the SOURCE Kindle file's fingerprint + `converterVersion`** — NOT
   the converted EPUB bytes. *(Gate-2 High-2: the converted bytes embed the
   caller-provided `title` in `content.opf`/`nav.xhtml`, so the same Kindle file
   under a different title override would produce a different fingerprint and
   defeat dedup.)* The book's `fingerprintKey` is the original AZW3's
   `DocumentFingerprint` (`azw3:{sha256}:{bytes}`), so re-importing the same
   Kindle file always dedupes, regardless of title. The converted `.epub` is the
   stored **render artifact**, not the identity. `converterVersion` is recorded
   so a future converter improvement is distinguishable from the same-version
   render.
2. **Render-format vs identity split (needs SchemaV9).** Identity stays on the
   source (`originalFormat = .azw3`), but the book must **render as EPUB**. The
   reader dispatcher routes on `fingerprint.format`, which would be `.azw3` →
   Foliate. So WI-4a adds a persisted **render-format** signal (a `renderFormat`
   / `converted` field) and the dispatcher consults it, so a converted book
   routes to the EPUB engine while keeping its azw3 identity. *(Gate-2 High-3:
   `Book` only has `originalExtension` today — `converterVersion` /
   `originalFormat` / render-format are a real SchemaV9 change touching
   `Book`/`BookRecord`/`PersistenceActor`/backup projections; it is a MANDATORY
   foundational WI, audited on its own, before any importer wiring.)*
3. **Store ONLY the converted EPUB as the canonical blob — do NOT retain a
   sidecar source.** *(Gate-2 High-4: the backup manifest carries exactly one
   blob per book and reader/materializer resolve one canonical sandbox file from
   `fingerprintKey`; a sidecar `source.azw3` would be invisible to
   backup/restore and path resolution.)* The converted `.epub` is the single
   canonical file (backup/restore/path-resolution all keep working unchanged).
   Trade-off accepted: re-conversion after a `converterVersion` bump requires the
   user to **re-import** the Kindle file (a second-blob "source asset" model is a
   deliberately deferred later enhancement, not v1). This is a documented
   deviation from BUILD-RECIPE's "retain the original source", justified by the
   backup-architecture finding.
4. **Metadata + cover come from the SOURCE Kindle file, not the converted EPUB.**
   *(Gate-2 High-1: importer Step 9 extracts metadata from the original
   `fileURL`; if `format` flips to `.epub`, `EPUBMetadataExtractor` would run
   against the AZW3 path and fall back to filename junk.)* WI-4b threads TWO URLs
   explicitly: the source (for `AZW3MetadataExtractor` — already exists — title /
   author / cover) and the converted EPUB (the file that gets hashed/sandboxed/
   stored). Metadata stays correct; the stored render file is the EPUB.
5. **Conversion runs OFF the main actor.** *(Gate-2 Medium: `importFile` is
   entered from a `@MainActor` task and doesn't suspend until `ContentHasher.hash`;
   a CPU-bound libmobi convert in the pre-hash slot would stall the UI.)*
   `convert` is `Sendable`/stateless (WI-2c) — WI-4b invokes it via an explicit
   off-main hop (`Task.detached` or a converter actor) and `await`s it before
   re-entering the file pipeline.
6. **Conversion-failure fallback is limited to SEMANTIC failures.** *(Gate-2
   Low.)* Only `MobiDecodeError` (`.parseFailed` DRM, `.corrupt`, `.noMarkup`)
   and `MobiEPUBError` fall back to native AZW3 import (so a user never loses the
   ability to import a book the converter can't yet handle). **Filesystem/temp-
   write failures from `convertToFile` are REAL import errors** (not silently
   masked). Temp `.epub` artifacts are cleaned up on every path (success,
   fallback, throw) via `defer`.
7. **Gated, default OFF.** `kindleConvertOnImport` OFF → today's behavior exactly
   (AZW3 imports native, renders via Foliate). The flip is a later, separate,
   human-gated decision after WI-5 device verification — symmetric with the
   Readium rollout.

## Work-item sequencing (revised: schema is now a mandatory foundational WI)

- **WI-4a** *(foundational — flag + converter conveniences, no schema)* —
  `FeatureFlags.kindleConvertOnImport` (default OFF) + `MobiEPUBConverter.version`
  + `MobiEPUBConverter.convertToFile(mobiPath:title:destinationDir:) throws -> URL`
  (off-main-safe; cleans temp on throw). Unit-tested; no behavior change. ~1 PR.
- **WI-4b** *(foundational — SchemaV9)* — add the persisted metadata the design
  needs: `originalFormat: BookFormat`, `converterVersion: Int`, and the
  **render-format** signal, on `Book` + mirror in `BookRecord` +
  `PersistenceActor` + backup projections. Lightweight/additive migration
  (existing rows default to "native, not converted"). **Audited on its own**
  (Gate-2 round for the migration). ~1 PR.
- **WI-4c** *(behavioral — dispatcher)* — the reader dispatcher consults the
  render-format signal so a converted book (azw3 identity, epub render) routes
  to the EPUB engine. ~1 small PR; device-checkable.
- **WI-4d** *(behavioral — importer wiring, gated)* — flag-on Kindle → off-main
  convert → import the EPUB as the canonical blob, source metadata threaded
  separately, semantic-failure fallback to native. ~1 PR. WI-5 device-verifies
  the rendered result.

The split grew from 2 → 4 WIs because Gate-2 showed the schema change and the
dispatcher render-format split are first-class foundational work, not add-ons
folded into the importer wiring.

## Test catalogue

- `FeatureFlagsTests` — `kindleConvertOnImport` default OFF; override on/off.
- `MobiEPUBConverterTests` — `convertToFile` writes a readable `.epub`; the
  written file round-trips (reuse the existing real-AZW3 enabled-if case).
- `BookImporterTests` (in-memory container, real AZW3 fixture via the
  skip-when-absent guard; synthetic for CI):
  - flag OFF + AZW3 → book persists as `.azw3` (today's behavior, regression).
  - flag ON + AZW3 → book persists as `.epub`; the stored file is a valid OCF;
    the original source is retained; fingerprint is stable across re-import.
  - flag ON + conversion failure (a deliberately-corrupt/DRM-ish fixture, or a
    converter stub that throws) → falls back to native `.azw3` import (no loss).
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
- **R4 — schema churn for converterVersion/originalFormat.** Mitigated by
  splitting any migration into WI-4a foundational + auditing it separately;
  WI-4b may store the minimal metadata in existing provenance fields if a
  migration is disproportionate.

## Backward compatibility

- Flag OFF (default) → byte-for-byte today's behavior. No migration.
- Existing AZW3 books in libraries → untouched; they keep rendering via Foliate.
- Flag ON, then OFF later → new imports go native again; already-converted books
  remain `.epub` (they are valid EPUBs; no corruption). The retained original
  source allows a future "revert to native" if ever wanted.

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

**Status: NOT yet Gate-2-clean.** The v2 design must go back for a Gate-2 round 2
(the revisions are substantial — a render-format dispatcher split + a SchemaV9
migration). Implementation (Gate 3) does not start until round 2 returns zero
open Critical/High/Medium. Per rule 47, max 3 rounds before escalation.

## Revision history

- v1 (2026-06-01) — initial Gate-1 design.
- v2 (2026-06-01) — Gate-2 round-1 fixes: identity → source-fingerprint;
  metadata-from-source; SchemaV9 promoted to a mandatory foundational WI;
  render-format/dispatcher split (WI-4c); drop sidecar source (single-blob);
  off-main convert; semantic-only fallback. WI split 2 → 4. Pending Gate-2 r2.
