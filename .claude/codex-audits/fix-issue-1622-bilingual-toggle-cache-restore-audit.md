---
branch: fix/issue-1622-bilingual-toggle-cache-restore
threadId: 019eb23f-1348-71e0-a3c6-07cf397d79b8
rounds: 1
final_verdict: ship-as-is
date: 2026-06-10
---

# Gate-4 Codex audit — Bug #343 (bilingual toggle cache-restore, GH #1622)

Independent audit via `scripts/run-codex.sh` (gpt-5.4, read-only),
adversarially briefed on the acceptCountMismatch self-heal reasoning, write
ordering / thrash, cross-format row isolation, Swift 6 concurrency, and
protocol-default dispatch.

## Round 1 — CLEAN, ship-as-is

No correctness findings. The audit explicitly confirmed:

- **Flag scoping** — `acceptsCountMismatchedRows: true` only on the
  self-healing EPUB consumers (legacy EPUB `EPUBReaderContainerView+
  Bilingual.swift:122`, Readium `ReadiumEPUBHost+Bilingual.swift:94`);
  Foliate explicitly false; TXT/MD/PDF default false.
- **No blind inject** — every consumer that can receive a foreign-contract
  row validates `segments.count != blocks.count` before inject (legacy
  paged `:232`, continuous per-section `+ContinuousBilingual.swift:144/:180`,
  Readium driver `:216`) and falls back to the divergence path.
- **Write ordering** — the direct fallback only starts after the plain-text
  leg completed and published a mismatch; the enumerate-contract write is
  not racing a still-running first-enable plain-text write, and once the
  row exists, acceptance-on readers stop re-entering `translate()` — no
  clobber loop.
- **Cross-format isolation** — the cache key includes book fingerprint +
  unit storage key; non-EPUB formats never read the EPUB divergence rows,
  so their strict stale-delete path cannot thrash them.
- **Protocol default** — `cachedSegmentsDirect` is a protocol REQUIREMENT
  with an extension default, so existential calls dispatch via the witness
  table (no shadowed-default pitfall).

| finding | severity | resolution |
|---|---|---|
| A host-level regression test for the flag threading would be nice | Low (test gap, "not a defect in the fix" per the auditor) | **Accepted with rationale** — the threading is a compile-pinned constructor argument; the acceptance behavior itself is service-level tested (`cachedTranslation_acceptCountMismatch_servesForeignContractRow`), and the VM-level toggle restore is pinned (`translateBlocksDirectly_afterToggleOffOn_restoresFromCache_zeroProviderCalls`). |

## Verdict

**ship-as-is** in 1 round.
