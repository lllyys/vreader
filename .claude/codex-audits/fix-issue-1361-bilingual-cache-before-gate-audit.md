---
branch: fix/issue-1361-bilingual-cache-before-gate
threadId: codex-exec-gpt-5.4
rounds: 1
final_verdict: ship-as-is
date: 2026-06-02
---

# Codex audit — Bug #306 (consult translation cache before the provider gate)

Runner: cc-suite via `scripts/run-codex.sh` (watchdog — SUCCEEDED, no ghost),
gpt-5.4, medium, read-only.

## Verdict: CLEAN — no findings.

- `cachedTranslation` builds `lookupKey` via the SAME `ChapterTranslationRecord.lookupKey(...)`
  and the SAME granularity segmentation + `sourceParagraphCount == segments.count`
  freshness gate as `translate()` — so a pre-gate hit here is also a hit inside
  `translate()` (no divergence).
- The prefetcher reorder is correct: profile snapshot stays first (needed for the
  key), `sourceText` is fetched once before the cache check, config resolved only
  on miss, miss path reuses the already-fetched `sourceText`. No double-fetch; the
  miss path is unchanged apart from skipping the gate on a true hit.
- No wrong/stale-result risk: both paths accept/reject on the same key + count.
  `cachedTranslation` doesn't delete stale rows, but `translate()` still does that
  cleanup on the miss path — not a wrong-result risk.
- Actor isolation sound: `cachedTranslation` is actor-isolated, touches only
  immutable state + the `ChapterTranslationStore` actor, returns a Sendable value.

ship-as-is.
