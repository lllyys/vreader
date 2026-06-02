---
branch: fix/issue-1371-kindle-provenance-dedupe
threadId: codex-exec-gpt-5.4
rounds: 1
final_verdict: ship-as-is
date: 2026-06-02
---

# Codex audit — Bug #307 (Kindle-origin wiped on dedupe re-import)

Runner: cc-suite via `scripts/run-codex.sh` (watchdog — SUCCEEDED, no ghost),
gpt-5.4, medium, read-only.

## Verdict: CLEAN — no findings.

- `kindleOriginExtension` is in scope for Step 7 + Step 10, set only after a
  successful conversion → nil on non-converted / fallback / native imports, so no
  false Kindle origin on a plain re-import.
- The dedupe-path provenance now mirrors the new-import-path provenance exactly.
- Flag-toggle edge case is safe: with convert-on-import later OFF, re-importing
  the original Kindle file fingerprints the original azw3 bytes → it never hits
  this EPUB dedupe path.
- `converterVersion: kindleOriginExtension == nil ? nil : MobiEPUBConverter.version`
  is consistent with the `ImportProvenance` contract (version iff origin).

ship-as-is.
