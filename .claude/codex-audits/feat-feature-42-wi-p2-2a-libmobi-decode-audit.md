---
branch: feat/feature-42-wi-p2-2a-libmobi-decode
threadId: codex-exec-gpt-5.4
rounds: 1
final_verdict: ship-as-is
date: 2026-06-01
---

# Codex audit — Feature #42 P2-WI-2a (libmobi decode path)

Runner: cc-suite `codex exec` (invoked with `< /dev/null` after a stdin-wedge
incident — see memory feedback_codex_exec_stdin_wedge), model gpt-5.4, effort
medium, read-only. Mini audit over MobiDocument.swift + MobiDocumentTests.swift
(vendored libmobi `.c/.h` upstream → out of scope).

Codex explicitly confirmed **no use-after-free**: `mobi_free_rawml` is deferred
after `mobi_init_rawml` so it runs before `mobi_free`; `Data(bytes:count:)` is a
copying initializer, not an alias of libmobi-owned memory.

## Round 1 findings + resolutions (all fixed)

| file:line | sev | issue | resolution |
|---|---|---|---|
| MobiDocument.swift:93 | Medium | `appendChain` trusted `MOBIPart.next` acyclic — a corrupt cyclic chain loops forever / OOM. | **FIXED.** Added `maxPartsPerSection` ceiling; the walk throws `.corrupt` past it. Tested with a self-cyclic synthetic node. |
| MobiDocument.swift:96 | Medium | `size==0` branch too broad — `data==nil && size>0` silently became `Data()`, masking corruption. | **FIXED.** Now: `size==0` → empty Data (legit); `size>0 && data==nil` → throw `.corrupt`. Tested with a null-data synthetic node. |
| MobiDocumentTests.swift:39 | Medium | Real-book `guard…return` reported PASS when the fixture was absent (false green). | **FIXED.** Real-AZW3 case now uses `.enabled(if: realAzw3Path != nil)` → reported SKIPPED, not passed; body uses `try #require`. |
| MobiDocumentTests.swift:17 | Low | CI error tests asserted only `MobiDecodeError.self`, not the specific case. | **FIXED.** Now match `.loadFailed(code != 0)` for missing path; load/parse/noMarkup for junk. |
| MobiDocumentTests.swift:17 | Low | No deterministic coverage of the risky `appendChain` edges (cycle, null-data, zero-size). | **FIXED.** `appendChain` made `internal`; added 4 synthetic-chain tests building `MOBIPart` nodes directly (ordered extraction, cycle→throw, null-data→throw, zero-size→empty). CI-safe, no real parse needed. |

## Verdict

ship-as-is after fixes — all 3 Medium + 2 Low resolved; suite green at 7/7
(`RUN-TESTS RESULT: SUCCEEDED`), including the new synthetic defensive-path
coverage. No memory-safety defect found in the wrapper.
