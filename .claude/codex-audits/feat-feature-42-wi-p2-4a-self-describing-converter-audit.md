---
branch: feat/feature-42-wi-p2-4a-self-describing-converter
threadId: codex-exec-gpt-5.4
rounds: 1
final_verdict: ship-as-is
date: 2026-06-02
---

# Codex audit — Feature #42 P2-WI-4a (self-describing title-neutral converter)

Runner: cc-suite via `scripts/run-codex.sh` (stdin-isolated watchdog —
`RUN-CODEX RESULT: SUCCEEDED`, no ghost), gpt-5.4, medium, read-only.

## Verdict: CLEAN — no findings in the changed files.

The implementation followed the Gate-2-approved v4 design (4 rounds), so it
audited clean on the first round. Codex validated each risk area against the code:

- **`copyMetaString` memory-safe** — `mobi_meta_get_*` are caller-owned
  (`malloc`/`strdup` in the vendored source), so `free(ptr)` is the correct
  deallocator; no double-free, no leak on success, `defer` runs after
  `String(cString:)` copies.
- **Determinism holds** — title/author come only from source metadata;
  `fallbackTitle` is the fixed `"Untitled"` (not the filename); `ZIPWriter` zeroes
  ZIP timestamps; the `convertToFile` UUID affects only the temp filename, not the
  EPUB payload. No clock/path input leaks into the bytes.
- **Cover selection deterministic** — first image resource in source order;
  no-image → no cover markers; multi-image → consistently the first.
- **OPF recovery-compatible** — `dc:creator` + EPUB3 `properties="cover-image"` +
  EPUB2 `<meta name="cover">` all emitted; `xmlEscape` covers author/title.
- **Flag** — `kindleConvertOnImport` default OFF everywhere, non-persisted, no
  Swift 6 concurrency issue.

ship-as-is.
