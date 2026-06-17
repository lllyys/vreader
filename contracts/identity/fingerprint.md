# Contract: `DocumentFingerprint` — book identity

**Canonical · level: breaking-sensitive** (the fingerprint IS the book
identity; any change orphans every library/backup reference).

Reference: `vreader/Models/DocumentFingerprint.swift`.

## Canonical key

A book's identity is the deterministic content fingerprint:

```
canonicalKey = "{format}:{contentSHA256}:{fileByteCount}"
```

| Component | Type | Rule |
|---|---|---|
| `format` | enum raw string (`BookFormat.rawValue`) | the document format — `epub`, `pdf`, `txt`, `md`, `azw3`. For a **converted Kindle** book the format component is **`azw3`** (the single `BookFormat` value covering the `.azw3`/`.azw`/`.mobi`/`.prc` extensions — there is NO `mobi`/`prc` raw value; the extension is not part of `canonicalKey`), and `contentSHA256`/`fileByteCount` are of the **SOURCE file bytes** — NOT the converted EPUB (decided in `DECISION.md`; see the Kindle note below). |
| `contentSHA256` | 64 lowercase hex chars | SHA-256 of the file's bytes — the SOURCE file for converted-Kindle formats. Validated: exactly 64 chars, all hex, all lowercase. |
| `fileByteCount` | Int64 ≥ 0 | byte length of the file (the SOURCE file for converted-Kindle formats). |

Separator is a literal `:`; parsing uses `split(":", maxSplits: 2)` so a
`:` inside later components is tolerated (only the first two split). The
three components are reassembled losslessly.

## Converted Kindle books (`.azw3` / `.mobi` / `.prc`) — DECIDED

**Canonical cross-platform identity = the SOURCE file bytes** (SHA-256 of the
original `.azw3`/`.mobi`/`.prc` + its byte count + the source format), NOT the
converted EPUB. Rationale + full decision: `DECISION.md`. This avoids coupling
two platforms' converter pipelines: Android hashes the source file directly; no
byte-for-byte parity of the conversion is required.

**iOS local detail (NOT cross-platform identity):** when `kindleConvertOnImport`
is enabled, the iOS app currently fingerprints the *converted EPUB* for its local
SwiftData/blob storage. That converted-EPUB fingerprint is a **platform-local**
storage key; the canonical identity used for cross-device dedup, library sync, and
backup/restore is the **source-bytes** key above. The source→converted mapping is
the local seam.

**Implementation obligation:** both platforms compute + persist the source-bytes
fingerprint as the canonical identity. iOS additionally keeps its converted-EPUB
fingerprint as a local detail (migration: compute the source-bytes key at import;
existing converted-EPUB-keyed rows map via the seam). Android computes only the
source-bytes key natively (no converter port needed for identity).

## Cross-platform requirements

- **SHA-256** is standard and identical across platforms for identical
  bytes. For converted-Kindle formats this is the SOURCE file bytes, which
  are byte-identical on any platform (same imported file) — so the
  fingerprint matches without any converter-pipeline parity.
- `BookFormat.rawValue` strings must match exactly across platforms (the
  Kotlin enum's raw values mirror Swift's).
- Lowercase-hex normalization is part of the contract (Kotlin must emit
  lowercase).

## Golden vectors

`contracts/vectors/fingerprint-*.json`: `{ bytesSHA256, byteCount, format,
expectedCanonicalKey }` + round-trip (`canonicalKey → parse → equals`).
Converted-Kindle canonical vectors are **converter-independent** (the
identity is the SOURCE bytes), so they need NOT record any libmobi /
`MobiEPUBConverter.version` — those only matter for the iOS-local
converted-EPUB artifact, not canonical identity.

## Conformance

- Swift (WI-2): assert `DocumentFingerprint(...).canonicalKey == expected`
  and `DocumentFingerprint(canonicalKey:)` round-trips, against the
  vectors.
- Kotlin (WI-5, toolchain-gated): the identical assertions in Kotlin.
