---
branch: fix/issue-1605-justify-cjk-gate
threadId: 019eb298-83d3-7060-b0bf-cd30792b280f
rounds: 2
final_verdict: ship-as-is
date: 2026-06-11
---

# Gate-4 Codex audit — Bug #336 reopen (CJK-gated EPUB justify, GH #1605)

Independent audit via `scripts/run-codex.sh` (gpt-5.4, read-only), 2 rounds.

## Round 1

| file:line | severity | issue | resolution |
|---|---|---|---|
| ReadiumEPUBReaderViewModel+Mapping.swift:161 | Medium | The CJK gate is metadata-only — and this repo manufactures the failure case: `MobiEPUBAssembler` hardcoded `dc:language=und`, so converted CJK Kindle books would lose justify on BOTH engines. | **Fixed at the root** — `MobiMetadata` gains `language` (libmobi `mobi_meta_get_language`); the assembler writes it into the OPF (xmlEscape'd; nil/empty falls back `und`); the converter threads it. Residual `und` (source has no language) stays ragged — pinned in the `isCJKLanguage` table. |
| ReaderThemeV2+EPUBCSS.swift:138 | Low | The rule split dropped the `center`/`right` intentional-alignment guards from the hyphenation rule (an undocumented cascade change). | **Fixed** — guards restored; selector parity with the justify rule; test asserts the guarded selector. |
| EPUBThemeOverrideCSSV2Tests.swift:240 | Low | Stale test name/assertions; no pins for unknown-language handling. | **Fixed** — renamed to `hyphenationIsLanguageIndependent_justifyIsCJKOnly` (asserts exactly ONE justify occurrence — the `:lang`-gated rule); `und` pinned non-CJK. |

Round 1 confirmed clean: `textAlign = nil` removes `--USER__textAlign` and
falls back to ReadiumCSS ragged-right (Latin path sound); the `h1–h6
text-align: initial` user script is RTL-safe (matches Readium's own use of
`initial`).

## Round 2

| file:line | severity | issue | resolution |
|---|---|---|---|
| MobiEPUBConverter.swift:21 | Medium | The converter `version` wasn't bumped though output bytes changed (`dc:language` now real). | **Fixed** — `version = 2` with a doc comment; test asserts the exact version. |
| MobiEPUBConverterTests.swift:100 | Low | `version >= 1` wouldn't catch a missed bump; no `dc:language` threading test. | **Fixed** — exact-version assertion + `opfLanguageThreading` (zh-cn preserved; nil/empty → und). |

Round 2 confirmed: the language threads decode → assemble → OPF;
`isCJKLanguage` handles `zh-cn`-style tags (lowercase + primary subtag).
Both round-2 resolutions are mechanical (a constant + tests) and verified
by green suite runs.

## Verdict

**ship-as-is** after 2 rounds.
