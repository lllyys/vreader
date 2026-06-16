# Contract: translation cache key (`ChapterTranslationRecord.lookupKey`)

**Canonical · level: breaking-sensitive** (the key is the dedupe identity
of a cached translation; changing it strands every cached row).

Reference: `vreader/Models/ChapterTranslationRecord.swift`.

## Canonical key

```
lookupKey = [ bookFingerprintKey, unitStorageKey, targetLanguage, promptVersion ].joined("|")
```

| Component | Type | Rule |
|---|---|---|
| `bookFingerprintKey` | String | the book identity (= `DocumentFingerprint.canonicalKey`). |
| `unitStorageKey` | String | the translation unit's stable storage key (per-format chapter/segment identity). |
| `targetLanguage` | String | the target language code. |
| `promptVersion` | String | the prompt/derivation version (so a prompt change is a new row, not a silent overwrite). |

Separator is a literal `|`.

## What is NOT in the key (provenance, not identity)

`providerProfileID` is **provenance metadata, NOT part of the key** (iOS
bug #342 — baking the profile into the key made re-translate and bilingual
reads diverge). A cached translation is shared across providers by
`book|unit|lang|prompt`; the producing profile is recorded on the row but
does not partition the cache. The Kotlin side must follow the same rule —
provider is metadata, the four-part key is identity.

## Cross-platform requirement

For cache interop (a translation cached on one platform reused on
another), all four components must be computed identically:

- `bookFingerprintKey` — already canonical (see `fingerprint.md`).
- `unitStorageKey` — the per-format unit identity must match across
  platforms (a Spike-A / Phase-3 obligation when the Kotlin reader's unit
  enumeration lands; flagged here as the cross-platform risk in this key).
- `targetLanguage` — same language-code normalization.
- `promptVersion` — same prompt version strings.

## Golden vectors / conformance

`contracts/vectors/cache-key-*.json`: `{ bookFingerprintKey,
unitStorageKey, targetLanguage, promptVersion, expectedLookupKey }`.
Swift conformance (WI-2) asserts `ChapterTranslationRecord.lookupKey(...)
== expected`. Kotlin (WI-5, toolchain-gated) the same.
