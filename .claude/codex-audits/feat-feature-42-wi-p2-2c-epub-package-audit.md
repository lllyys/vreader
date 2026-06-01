---
branch: feat/feature-42-wi-p2-2c-epub-package
threadId: codex-exec-gpt-5.4
rounds: 1
final_verdict: ship-as-is
date: 2026-06-01
---

# Codex audit — Feature #42 P2-WI-2c (end-to-end MOBI→EPUB converter)

Runner: cc-suite via `scripts/run-codex.sh` (stdin-isolated watchdog —
`RUN-CODEX RESULT: SUCCEEDED`, no ghost), gpt-5.4, medium, read-only. Codex
confirmed the wiring is correct: decode/assemble/package errors propagate,
mimetype-first is guaranteed (assemble emits it first + ZIPWriter preserves
order), Stored-only ZIP is valid EPUB OCF, and `convert()` is background-safe
(no shared mutable state, Sendable values).

## Round 1 findings + resolutions

| file:line | sev | issue | resolution |
|---|---|---|---|
| MobiEPUBConverter.swift:38 | Medium | `package` relies on ZIPWriter storing every entry without proving it — a future ZIPWriter change could silently ship a non-compliant (deflated-mimetype) EPUB. | **FIXED (CI-gated).** Added `mimetypeRawHeaderIsStored`: parses the RAW first local-file-header (independent of ZIPWriter's own helpers) and asserts compression-method == 0 (Stored) + filename == "mimetype" + first. If ZIPWriter ever deflates, this fails before merge. `package()` doc now cites the guarding test. |
| MobiEPUBConverterTests.swift:32 | Medium | Tests round-tripped only via ZIPWriter's own helpers, never inspecting raw ZIP headers → didn't prove the OCF Stored-mimetype invariant. | **FIXED.** Same raw-header test independently validates the local-file-header structure (signature, method, filename). |
| MobiEPUBConverter.swift:39 | Low | ZIPWriter lives under `Services/Backup/` — a layering smell now that Libmobi depends on it. | **ACCEPTED w/ rationale.** ZIPWriter is pure/static/generic and vreader is a single module (no real import dependency — purely organizational). Relocating it is a separate Backup reorg; doing it as a drive-by in a Libmobi WI risks destabilizing Backup + its tests. Tracked as a future infra-tidy, not done here. |
| MobiEPUBConverter.swift:29 | Low | Fully in-memory pipeline → ~2-3× peak RAM for image-heavy books. | **ACCEPTED + documented.** `convert()` doc now states the peak-memory behavior; acceptable for the current ≤~18 MB fixture range; flagged a file-backed archive path as a WI-4 option if larger Kindle books appear. |

## Verdict

ship-as-is — both Medium fixed (raw-header CI gate); both Low accepted with
documented rationale. Suite 5/5 green (`RUN-TESTS SUCCEEDED`), incl. the real
6 MB CJK AZW3 full-pipeline conversion to a structurally-valid .epub.
