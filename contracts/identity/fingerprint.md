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
| `format` | enum raw string (`BookFormat.rawValue`) | the document format — `epub`, `pdf`, `txt`, `md`, `azw3`, … For a **converted Kindle** book the format is the CONVERTED format (`epub`), and `contentSHA256`/`fileByteCount` are of the **converted EPUB bytes**, not the source `.mobi`/`.azw3`. |
| `contentSHA256` | 64 lowercase hex chars | SHA-256 of the (converted) file's bytes. Validated: exactly 64 chars, all hex, all lowercase. |
| `fileByteCount` | Int64 ≥ 0 | byte length of the (converted) file. |

Separator is a literal `:`; parsing uses `split(":", maxSplits: 2)` so a
`:` inside later components is tolerated (only the first two split). The
three components are reassembled losslessly.

## Cross-platform requirements

- **SHA-256** is standard and identical across platforms for identical
  bytes. The risk is NOT the hash — it is whether the **converted EPUB
  bytes are identical** across an iOS-built libmobi and an Android-NDK
  libmobi (Spike A WI-3, the `harness/` determinism driver). If they
  diverge, the canonical model must change (normalize the converted EPUB
  before hashing, OR fingerprint the SOURCE bytes) — that decision is
  Spike A's deliverable, recorded here.
- `BookFormat.rawValue` strings must match exactly across platforms (the
  Kotlin enum's raw values mirror Swift's).
- Lowercase-hex normalization is part of the contract (Kotlin must emit
  lowercase).

## Golden vectors

`contracts/vectors/fingerprint-*.json`: `{ bytesSHA256, byteCount, format,
expectedCanonicalKey }` + round-trip (`canonicalKey → parse → equals`).
For converted-Kindle vectors, also record the producing libmobi /
`MobiEPUBConverter.version` so a converter bump is distinguishable from
nondeterminism.

## Conformance

- Swift (WI-2): assert `DocumentFingerprint(...).canonicalKey == expected`
  and `DocumentFingerprint(canonicalKey:)` round-trips, against the
  vectors.
- Kotlin (WI-5, toolchain-gated): the identical assertions in Kotlin.
