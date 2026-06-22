---
branch: feat/feature-117-wi-1-opds-parser
threadId: 019eea3a-f117wi1
rounds: 2
final_verdict: ship-as-is
date: 2026-06-22
---

# Codex audit — feature #117 WI-1 (OpdsModels + OpdsParser + SafeXml)

Scope: `android/app/.../opds/OpdsModels.kt`, `.../opds/OpdsParser.kt`, `.../xml/SafeXml.kt`
(the reusable #116-WI-6 XXE defence), and `OpdsParserTest.kt`. OPDS 1.2 Atom feed parsing,
design-free, mirroring iOS `OPDSModels`/`OPDSParser`.

## Round 1 — 2 findings (1 High / 1 Medium)

| file:line | severity | issue | resolution |
|---|---|---|---|
| OpdsModels.kt (acquisitionKind) | High | An unknown acquisition sub-rel fell through to `generic` → `isAutoImportable` true, so an unrecognised (possibly auth/payment/lending) acquisition could auto-import. `isAcquisition` also matched `…/acquisitionXYZ`. | FIXED — unknown acquisition sub-rels → new `unsupported` kind (an acquisition, but NOT importable); `isAutoImportable` stays `generic`/`openAccess` only. `isAcquisition` tightened to `rel == ACQ_PREFIX || rel.startsWith("$ACQ_PREFIX/")`. Tests for buy/borrow/sample/preview/subscribe/indirect/unknown + `acquisitionXYZ`. |
| OpdsModels.kt (resolveAgainst) | Medium | `URI(base).resolve("?page=2")` / `"#frag"` resolved against the directory, dropping a file-like base's `root.xml` — breaks OPDS pagination/search forms that use query-only refs. | FIXED — query-/fragment-only hrefs rebuild `URI(scheme, authority, base.path, query, fragment)`, preserving the base path; normal `../`/absolute/scheme/no-base paths unchanged. Tests added. |

## Round 2 — verify pass

Codex confirmed both resolved + no new defects: `unsupported`→non-importable mapping correct,
`isAutoImportable` limited to generic/openAccess, `acquisitionXYZ` no longer an acquisition, and
normal `../` resolution unchanged (still `base.resolve`). **No findings.**

Verdict: **ship-as-is.** 11 JVM `OpdsParserTest` (navigation/acquisition/relative-href/query-only/
pagination/search/dedup/CJK/default-Atom-ns/malformed/**DOCTYPE-rejected**/**UTF-16-not-a-bypass**)
+ full `:app` suite green.
