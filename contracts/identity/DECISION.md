# Canonical cross-platform identity — DECISION (feature #104 Spike A)

**ADR-0001 Risk 1.** The gate question: when Swift (iOS) and Kotlin (Android)
derive book identity / reading position independently, what is **canonical** —
exact-match, a normalization layer, or platform-local + a mapping? This file is
the written decision the spike was charged to produce; it is backed by the
running dual-platform conformance lane (`contracts/conformance/run.sh`) and the
investigations recorded below.

## Decisions

| Surface | Decision | Basis |
|---|---|---|
| **Fingerprint — native files** (EPUB/PDF/TXT/MD imported as-is) | **EXACT-MATCH.** `DocumentFingerprint.canonicalKey = {format}:{sha256}:{byteCount}` is identical Swift↔Kotlin; no normalization layer. | The conformance lane asserts the Swift impl and a Kotlin reference impl produce identical keys from one shared `contracts/vectors/fingerprint.json`; round-trip + invalid-rejection parity verified (WI-2/WI-5, merged). |
| **Fingerprint — converted Kindle** (`.azw3`/`.mobi`/`.prc`) | **Cross-platform identity = the SOURCE file bytes, NOT the converted EPUB.** The canonical key for a converted Kindle book is the SHA-256 of the *original imported file*. | The iOS `MobiEPUBConverter` IS deterministic + content-addressed (ZIP mtimes pinned to 0; EPUB `dc:identifier` = SHA-256 of part bytes; no clock/RNG — only the temp *filename* uses a UUID, which doesn't touch the bytes). But it is a **vreader-specific pipeline** (libmobi extraction + `MobiEPUBAssembler` OPF/nav generation + `ZIPWriter`); byte-identical cross-platform conversion would require Android to re-implement that exact pipeline — a fragile interop contract. Hashing the source bytes is platform-independent, converter-version-independent, and matches the artifact the user actually imported. **NB:** iOS currently fingerprints the *converted EPUB* when `kindleConvertOnImport` is on — so the converted-EPUB fingerprint is a **platform-local** detail; the cross-platform/backup identity contract uses the source-bytes hash (a source→converted mapping is the interop seam, see follow-up). |
| **Cache key** (`ChapterTranslationRecord.lookupKey = book\|unit\|lang\|prompt`) | **EXACT-MATCH.** `providerProfileID` is intentionally excluded (provenance only, bug #342). | Conformance lane asserts identical composition Swift↔Kotlin from `contracts/vectors/cache-key.json` (WI-2/WI-5, merged). |
| **Locator — engine-neutral canonical form** (`Locator.canonicalJSON`/`canonicalHash`) | **EXACT-MATCH.** A reading position serializes byte-identically Swift↔Kotlin → identical `canonicalHash` → cross-platform position identity for dedup/sync. | WI-4: the Swift `Locator.canonicalJSON()` and a Kotlin `CanonicalLocator.canonicalJson()` reference impl produce the identical string for one shared `contracts/vectors/locator.json` (sorted keys, nil omission, `%.6f` POSIX floats, normalized line-endings, RFC-8259 escaping). Verified by both the Swift suite (`RUN-TESTS RESULT: SUCCEEDED`) and the Kotlin suite (`BUILD SUCCESSFUL`). |
| **Locator — EPUB `cfi`** | **PLATFORM-LOCAL → LOSSY-FALLBACK.** Do NOT rely on cross-platform CFI equality; cross-device EPUB resume uses `progression` + the text-quote anchors. | `identity/locator.md` field classification + corroborating measurement: feature #105 WI-3 found Readium-Kotlin fragment restore is ~2-paragraph-approximate on CJK (the CFI/fragment anchor is not pixel-exact), so progression + text-quote (both canonical) are the reliable resume anchors. |

## Canonical model, in one line

**Exact-match for native fingerprint + cache-key + the engine-neutral
`Locator.canonicalJSON`; source-bytes (not converted-EPUB) for converted-Kindle
cross-platform identity; CFI is lossy-fallback (resume on progression + text
quotes).** No global normalization layer is required — the only platform-local
seams are the converted-EPUB fingerprint and CFI, both with a defined fallback.

## Why no Android-NDK libmobi byte-identity harness was built

The plan listed an Android-NDK libmobi determinism harness (WI-3). It is **not on
the critical path for the decision**: the decision rejects the
"byte-identical-conversion-across-platforms" model (it chose source-bytes), so a
harness proving/disproving cross-platform conversion byte-identity does not change
the canonical model. The relevant fact — that the iOS conversion is deterministic
but pipeline-specific — was established by reading the converter + its CI
determinism test, not assumed. Building the full Android libmobi pipeline-port +
harness becomes required **only if** a future decision adopts the converted-EPUB
hash as the cross-platform identity (it didn't); that is recorded as the follow-up
below.

## Follow-ups (for Phase 2/3, not blockers)

1. **Source→converted mapping seam.** When Android imports a `.azw3`, persist the
   source-bytes fingerprint as the canonical/backup identity and keep the
   platform-local converted-EPUB fingerprint (if any) as a local detail. The
   library/backup contracts key on the source hash.
2. **If** converted-EPUB cross-platform identity is ever wanted: port
   `MobiEPUBAssembler` + `ZIPWriter` to Kotlin byte-for-byte and stand up the
   Android-NDK libmobi determinism harness on a shared MOBI corpus.
3. **Locator engine-neutral form** is the cross-device resume key; the Readium
   `Locator` (CFI-bearing) stays platform-local. Wire the `Locator.canonicalJSON`
   contract into the Android position store when it lands.
