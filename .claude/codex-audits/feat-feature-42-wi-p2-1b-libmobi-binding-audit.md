---
branch: feat/feature-42-wi-p2-1b-libmobi-binding
threadId: codex-exec-gpt-5.4-mini-audit
rounds: 1
final_verdict: ship-as-is
date: 2026-06-01
---

# Codex audit — Feature #42 P2-WI-1b (libmobi → Swift binding)

Runner: cc-suite `codex exec`, model gpt-5.4, effort medium, sandbox read-only.
Mini audit (5 dims) over the first-party WI-1b surface (the vendored libmobi
`.c/.h` are upstream + already merged in WI-1a → out of scope).

## Round 1 findings + resolutions

| file:line | severity | issue | resolution |
|---|---|---|---|
| project.yml:215 | Medium | `GCC_WARN_INHIBIT_ALL_WARNINGS: YES` was target-wide → would suppress warnings on any future first-party ObjC/ObjC++ in the vreader target, not just the vendored C. | **FIXED.** Removed the target-wide flag. The libmobi C is now excluded from the app-wide source entry and re-added via a dedicated `vreader/Services/Libmobi/src` source entry with `compilerFlags: "-w"` — scoping warning suppression to the third-party C only. Verified: pbxproj shows `COMPILER_FLAGS = "-w"` on all 17 `.c`, `GCC_WARN_INHIBIT_ALL_WARNINGS` gone (0 refs), `** BUILD SUCCEEDED **`, smoke `RUN-TESTS RESULT: SUCCEEDED`. |
| vreaderTests/.../LibmobiSmokeTests.swift:21 | Low | The smoke proves runtime linkage for `mobi_version` + `mobi_init`/`mobi_free` but does NOT exercise the `USE_LIBXML2`-gated xmlwriter/OPF path, so it can't prove that conversion path runs. | **ACCEPTED + narrowed (Codex's offered alt).** Exercising the xmlwriter path needs a real MOBI→EPUB conversion — that IS WI-2, verified there with a real fixture. The libxml2 *link* is already proven at build time: xmlwriter.c references libxml2 symbols, so the app would fail to link if `-lxml2` didn't resolve (it links → proven). The test header now scopes the runtime claim to the two exercised symbols + states the link-vs-runtime distinction explicitly. |

## Clean (no change needed)

- `Libmobi.swift` — `version` is a read-only `mobi_version()` wrapper; `contextAllocates()` ownership is correct: nil early-return, single `mobi_free` on success, no leak/double-free. No shared mutable state → isolation-safe.
- `Libmobi-Bridging-Header.h` — exposing `mobi.h` is broad but acceptable: self-contained, consistently `mobi_`/`MOBI_`-prefixed → low collision risk.
- `project.yml` `$(inherited)` chains on GCC_PREPROCESSOR_DEFINITIONS / HEADER_SEARCH_PATHS / OTHER_LDFLAGS are preserved; `-lxml2` is the correct iOS SDK link; `SWIFT_OBJC_BRIDGING_HEADER` points at the right file.

## Verdict

ship-as-is — the one Medium is fixed + build/smoke-verified; the one Low is an
explicit, documented WI-2 deferral with the link already proven at build time.
