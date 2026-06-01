---
branch: feat/feature-42-wi-p2-2b-epub-assembler
threadId: codex-exec-gpt-5.4
rounds: 1
final_verdict: ship-as-is
date: 2026-06-01
---

# Codex audit — Feature #42 P2-WI-2b (EPUB assembly core)

Runner: cc-suite via `scripts/run-codex.sh` (the new stdin-isolated watchdog
wrapper — `RUN-CODEX RESULT: SUCCEEDED`, no ghost), gpt-5.4, medium, read-only.
The escaper was confirmed correct (5 entities, `&` first); hrefs/ids are
safe-by-construction (assembler-generated).

## Round 1 findings + resolutions (all fixed)

| file:line | sev | issue | resolution |
|---|---|---|---|
| MobiEPUBAssembler.swift:162 | High | `packageUUID` hashed only `part.data` → two part lists with identical bytes but different section/uid/extension collide on one `urn:uuid:` id. | **FIXED.** Now hashes a domain-separated, length-prefixed header (`section|uid|ext|byteCount\n`) before each payload. New test `idDependsOnStructureNotJustBytes` proves different uid / different section-bytes → different id. |
| MobiEPUBAssembler.swift:128 | Medium | Zero markup → `<ol>` with no `<li>` = invalid EPUB3 nav, yet the package was emitted. | **FIXED.** `assemble` is now throwing and rejects zero markup with `MobiEPUBError.noMarkup` (mirrors the decode layer's `.noMarkup`; the real pipeline already guards it upstream). |
| MobiEPUBAssemblerTests.swift:99 | Medium | The old `noMarkup` test only checked the opf, masking the invalid nav. | **FIXED.** Replaced with `zeroMarkupThrows` (asserts `.noMarkup`) + a new `navStructure` test that parses nav.xhtml and asserts one `<li>` per markup part. |
| MobiEPUBAssembler.swift:172 | Low | `mediaType` lacked `mpg` though the decoder can emit it → wrong manifest type. | **FIXED.** Added `mpg`/`mpeg` → `video/mpeg`. |
| MobiEPUBAssemblerTests.swift:74 | Low | Escaping test covered only the opf title, not nav, not all 5 entities. | **FIXED.** `titleEscapedEverywhere` asserts all 5 entities escaped + well-formed + raw title absent, in BOTH content.opf and nav.xhtml. |

## Verdict

ship-as-is after fixes — High + 2 Medium + 2 Low all resolved; suite green at
9/9 (`RUN-TESTS RESULT: SUCCEEDED`).
