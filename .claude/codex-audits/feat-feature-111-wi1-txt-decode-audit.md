---
branch: feat/feature-111-wi1-txt-decode
threadId: 019ede-wi1-txt-1round
rounds: 1
final_verdict: ship-as-is
date: 2026-06-19
---

# Gate-4 audit — feature #111 WI-1 (Android TXT decode + document model)

WI-1 is the foundational offset/decode contract for the Android TXT reader:
`TxtDecoder` (BOM-first charset detection + decode; BOM-less fallback strict-UTF-8 →
GBK heuristic → UTF-8 replacement) and `TxtDocument` (range-based chunking over one
backing decoded `String`; UTF-16 `offsetForChunk`/`chunkForOffset` against the RAW
text; hard-split at `maxChunkChars` never mid-surrogate-pair; EOF clamp). Pure JVM.

Codex (gpt-5.4, high), 1 round, follow-up-recommended → fixed to ship-as-is.

## Findings (1 Medium, 1 Low — both fixed)

| file | sev | issue | resolution |
|---|---|---|---|
| TxtDocument.kt | Medium | chunk-start collection used `ArrayList<Int>` + `toIntArray()` → boxed every offset + a duplicating copy; a newline-dense 14MB file spikes tens of MB of transient objects (breaks the "one String + one IntArray" profile). | Rewrote with a primitive growable `IntArray` (double-on-full + a single `copyOf(count)` trim) — no Int boxing. |
| TxtDecoder.kt | Low | empty input → `confident = true` (strict UTF-8 accepts empty), inconsistent with "real charset evidence" elsewhere. | Special-cased empty → `confident = false`; test `emptyFile_decodesToEmpty_notConfident` asserts it. |

## Confirmed correct (auditor, no correctness bugs)

- BOM stripping + detection order correct (UTF-8 / UTF-16 LE/BE).
- GBK cannot shadow valid UTF-8 — strict UTF-8 runs first.
- Offsets are raw UTF-16 code-unit indexes; CRLF/CR/LF preserved (no normalization)
  — the resume contract holds.
- The surrogate-pair hard-split always advances and never splits a valid pair.
- `chunkForOffset` clamp + binary search sound; empty/single-line/no-newline edges correct.

## Validation

`scripts/run-android-tests.sh :app:testDebugUnitTest` → **SUCCEEDED**; `TxtDecoderTest`
7 + `TxtDocumentTest` 7 = 14 tests (UTF-16LE/BE BOM+CJK, GBK fallback, empty-not-confident,
mixed CRLF/CR/LF preservation, surrogate-pair safety, EOF clamp, huge-line split,
offset↔chunk round-trip), 0 failures. Full `:app` suite green.

## Verdict

**ship-as-is.** No correctness bugs; the Medium (memory) + Low (confident semantics)
fixed with tests.
