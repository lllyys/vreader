---
branch: feat/feature-42-p2-wi6-kindle-convert-default-on
threadId: 019e8761-ae5a-7b71-99ad-477b1150aaac
rounds: 1
final_verdict: ship-as-is
date: 2026-06-02
---

# Codex audit — Feature #42 Phase-2 G2 flag flip (`kindleConvertOnImport` default ON)

Independent Codex audit (cc-suite via `scripts/run-codex.sh`, model `gpt-5.5`,
effort `high`, read-only) of the user-ratified G2 flip: `kindleConvertOnImport`
default OFF→ON, so NEW AZW3/MOBI/KF8/PRC imports convert to a first-class EPUB
(rendered via the default Readium engine). Symmetric with the Phase-1
`readiumEPUBEngine` flip.

## Scope

- `vreader/Services/FeatureFlags.swift` — default `true` + added to `persistedFlags`.
- `vreaderTests/Services/{FeatureFlagsTests, BookImporterTests, BookImporterAZW3Tests, BookImporterOriginalExtensionTests}.swift`.
- Comment/doc sync: `BookImporter.swift`, `VReaderApp.swift`, `docs/architecture.md`.

## Findings — no Critical/High

The auditor confirmed the flip is sound + symmetric: `defaultValue` returns `true`,
`persistedFlags` membership makes OFF overrides survive reload, and `BookImporter`
reads `featureFlags.isEnabled(.kindleConvertOnImport)` so both the new default and a
persisted override are honored. **Behavioral safety**: existing native AZW3/MOBI/PRC
books are unaffected (they already have `.azw3` fingerprints + route to Foliate);
NEW valid Kindle files become first-class EPUBs routed through Readium (the verified
target). No production code assumes native-Kindle-import-by-default.

| Severity | Issue | Resolution |
|---|---|---|
| Medium | `BookImporterAZW3Tests` asserted Kindle extensions import as `.azw3` through a default importer — with default ON they only pass via the unconvertible-synthetic-fixture conversion fallback (testing the wrong path). | FIXED — `makeImporter()` now pins `kindleConvertOnImport` override OFF, so the native format-normalization is tested deterministically. |
| Low | `BookImporterOriginalExtensionTests` same (MOBI native extension-preservation). | FIXED — same override-OFF pin in `makeImporter()`. |
| Low | Stale "default OFF / not persisted" comments in `FeatureFlags.swift` (header + enum doc). | FIXED — updated to default ON + persisted-revertable. |
| Low | `BookImporter.swift` Step-3.5 comment said gated default OFF. | FIXED. |
| Low | `VReaderApp.swift` `--enable-kindle-convert` comment framed the flag as default OFF. | FIXED — reworded as force-ON/override-persisted-OFF for verification. |
| Low | `docs/architecture.md` said AZW3/MOBI render via Foliate without the new import default. | FIXED (doc-sync, rule 24) — added the Phase-2 import-default + native/override-OFF exception. |

## Verdict

**ship-as-is.** Build + affected suites GREEN: `FeatureFlagsTests` 34 (incl. new
default-ON + persistence tests), `BookImporterTests` 24, `BookImporterAZW3Tests` 10,
`BookImporterOriginalExtensionTests` 6. Device verification: a fresh real-AZW3
import with no flag now produces a converted EPUB (see the WI-6 evidence).
