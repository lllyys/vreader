# Contract: `Locator` + `VReaderLocator` — reading position

**level: breaking-sensitive** (saved positions + cross-engine/cross-device
resume depend on this envelope).

Reference: `vreader/Models/Locator.swift`, `vreader/Models/VReaderLocator.swift`.

Each field is classified **canonical** (must agree cross-platform for
cross-device resume), **platform-local** (may legitimately differ — not
relied on across platforms), or **lossy-fallback** (the degraded resume
path used when a platform-local anchor doesn't round-trip).

## `Locator` (the engine-neutral position)

| Field | Type | Class | Notes |
|---|---|---|---|
| `bookFingerprint` | `DocumentFingerprint` | **canonical** | the book this position belongs to (see `fingerprint.md`). |
| `href` | String? | **canonical** | spine/resource href (EPUB). Compared **fragment-insensitively + percent-encoding-normalized** (cf. iOS bug #349 `EPUBScrollAnchorResolver`). |
| `progression` | Double? | **canonical** | within-spine-item position (conventionally 0…1). The primary cross-device resume anchor. The only enforced invariant is **finite** (see invariants below). |
| `totalProgression` | Double? | **canonical** (derived) | within-whole-book position (conventionally 0…1). Enforced invariant: **finite**. |
| `cfi` | String? | **platform-local → lossy-fallback** | EPUB CFI. CFI dialects may NOT round-trip Swift-Readium ↔ Kotlin-Readium; do not rely on cross-platform CFI equality — fall back to `progression` + the text-quote anchors. |
| `page` | Int? | **canonical** | PDF page index — the page tree is defined by the document, so page N is page N on any renderer (PDFKit ↔ PdfiumAndroid). ≥ 0. |
| `charOffsetUTF16` | Int? | **canonical** | UTF-16 char offset (TXT/MD). ≥ 0. |
| `charRangeStartUTF16` | Int? | **canonical** | selection range start (UTF-16). ≥ 0. |
| `charRangeEndUTF16` | Int? | **canonical** | selection range end (UTF-16). ≥ start. |
| `textQuote` | String? | **canonical** | the quoted text at the position — the engine-independent anchor. |
| `textContextBefore` | String? | **canonical** | text immediately before the quote (disambiguates repeats). |
| `textContextAfter` | String? | **canonical** | text immediately after the quote. |

Validation invariants — EXACTLY what `Locator.validate()` enforces (do not
strengthen): `page` / `charOffsetUTF16` / `charRangeStartUTF16` /
`charRangeEndUTF16` non-negative; `charRangeStartUTF16` and
`charRangeEndUTF16` must appear **together or neither** (paired), with
`start ≤ end`; `progression` / `totalProgression` must be **finite** (NOT
required to be within 0…1). Serialization uses a canonical JSON form
(stable key ordering) so the hash/round-trip is deterministic.

Canonical-string + numeric rules (bug #356) — both platforms MUST apply, or
the cross-platform hash diverges:

- **NFC normalization.** Every string field (`href`, `cfi`, `textQuote`,
  `textContext*`) is Unicode-**NFC**-normalized before escaping (Swift
  `precomposedStringWithCanonicalMapping`; Kotlin
  `Normalizer.normalize(_, NFC)`). iOS hands back NFD on some text paths, so
  without NFC a decomposed vs precomposed form of the same text would hash
  differently within iOS AND across platforms. **Impl status (feature #109):**
  BOTH platforms now apply NFC — the Kotlin reference (`CanonicalLocator`) and
  iOS (`Locator.canonicalJSON` via `precomposedStringWithCanonicalMapping`).
  iOS re-derives the 18 persisted profileKey/locatorHash sites via a one-shot,
  flag-gated launch backfill (`LocatorKeyBackfillMigration`) — NOT a SwiftData
  migration stage, because the transform changes no entity shape and a custom
  stage between schema-identical versions never fires. The same backfill repairs
  preexisting non-finite locators. The shared NFD vector in
  `contracts/vectors/locator.json` is exercised by both platforms' conformance
  suites.
- **Non-finite is REJECTED, not omitted.** A non-finite `progression` /
  `totalProgression` is invalid — `Locator.validate()` returns
  `.nonFiniteProgression` and the Kotlin canonical reference throws. The
  canonical form is defined ONLY for validated locators; never silently omit a
  non-finite value (that would let an invalid locator canonicalize identically
  to a valid missing-progression one).
- **Float format** is POSIX/US-locale `%.6f`; **line endings** `\r\n`/`\r` → `\n`.

## `VReaderLocator` (the persisted envelope)

| Field | Type | Class | Notes |
|---|---|---|---|
| `fingerprintKey` | String | **canonical** | the book identity key (= `DocumentFingerprint.canonicalKey`). |
| `originalFormat` | `BookFormat` | **canonical** | part of the fingerprint identity. |
| `engine` | `ReaderLocatorEngine` | **platform-local** | which renderer produced the position. Exactly two persisted cases: `epubWKWebView` (the legacy bespoke EPUB engine — locator in `legacyLocator`) and `readium` (locator in `readiumLocatorJSON`). |
| `readiumLocatorJSON` | String? | **platform-local → lossy-fallback** | Readium's own CFI-bearing JSON. Platform-specific; the cross-platform fallback is `legacyLocator`'s progression + text-quote. |
| `legacyLocator` | `Locator?` | **canonical** | the platform-neutral resume envelope (the `Locator` above; its per-field classes apply within it). |
| `schemaVersion` | Int | **canonical** | the migration hook — both platforms serialize it consistently. |

## Cross-platform resume rule (the decision Spike A confirms)

1. Resolve the book by `fingerprintKey` (canonical).
2. Try the precise anchor (`charOffset`/`charRange` for text; `href` +
   `progression` for EPUB; `page` for PDF) — all canonical.
3. If the platform that saved used a CFI/`readiumLocatorJSON` the current
   platform can't resolve, **fall back** to `progression` +
   `textQuote`/context (the lossy path) rather than losing the position.

This is the **canonical-identity model**: a position is cross-device-
restorable to at least progression+quote precision on any platform, exact
when the precise anchor round-trips. Spike A's Readium round-trip harness
(WI-4, toolchain-gated) tests how often the exact anchor survives; this
spec already commits the fallback so a non-round-trip is degraded, never
lost.

## Golden vectors / conformance

`contracts/vectors/locator-*.json`: full serialized `Locator` /
`VReaderLocator` shapes (every field) → expected canonical JSON + parse
round-trip. Swift conformance (WI-2) asserts the iOS impl serializes /
parses the FULL shapes (not a reduced subset) so a vector can't go green
while ignoring stored fields.
