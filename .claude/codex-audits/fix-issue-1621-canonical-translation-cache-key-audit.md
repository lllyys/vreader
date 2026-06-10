---
branch: fix/issue-1621-canonical-translation-cache-key
threadId: 019eb21f-3b50-7971-b4ba-6eefa27f5026
rounds: 2
final_verdict: ship-as-is
date: 2026-06-10
---

# Gate-4 Codex audit — Bug #342 (canonical translation cache key, GH #1621)

Independent audit via `scripts/run-codex.sh` (gpt-5.4, read-only),
adversarially briefed across migration correctness, atomic-swap regression
risk (vs the just-shipped #341), cross-flow row sharing, Swift 6
concurrency, and the prefetcher reorder. Round-2 session id
`019eb227-c0b5-7eb1-acdd-9ab19454f48c`.

## Round 1

| file:line | severity | issue | resolution |
|---|---|---|---|
| ChapterTranslationStore.swift:72 | High | `configure(modelContainer:)` replaces the container but `didMigrateLegacyKeys` was never reset — a swapped-in container's legacy 5-field rows would never migrate that process (canonical lookups miss them while `cachedUnits` still counts them by columns, so whole-book translate could skip units bilingual mode can't read). | **Fixed** — `configure` resets the flag when the container reference actually changes (`!==`). Regression test `containerSwap_reArmsLegacyMigration` (migrate container A → swap to container B seeded with a legacy row → canonical lookup + `cachedUnits` both see it). |
| ChapterTranslation.swift:1 | Low | Model header still documented the five-field identity contract ("one row per … provider profile") — would steer future maintenance back toward the bug. | **Fixed** — header + `lookupKey` doc rewritten to the canonical `book|unit|lang|prompt` key with `providerProfileID` explicitly provenance metadata. |
| ChapterReTranslateViewModel.swift:133 | Low | `promptVersion` became dead state in the VM (injected, stored, never read after the orphan-delete removal). | **Fixed** — field + init param removed; host (`ReaderContainerView+ReTranslate.swift`) and tests updated. |

Round 1 found no issue with: the migration's dedupe ordering and `!==`
identity comparison, the legacy-detection heuristic (5 fields + UUID at
index 3 — `bookFingerprintKey` uses `:`, prompt versions are alphanumeric,
so a canonical key cannot false-positive), unique-constraint safety of the
keeper rewrite, the removal of #341's orphan delete (no loss path
reintroduced — the in-place upsert carries the atomic-swap guarantee), the
cross-flow row sharing semantics, or the prefetcher's cache-before-guard
reorder.

## Round 2

**CLEAN, ship-as-is.** Verified the `configure` re-arm is correct (`!==`
appropriate for the reference-typed `ModelContainer`; actor isolation
serializes the flag reset and later migration reads — no new concurrency
hazard), the model docs are consistent, the dead state is fully removed,
and the regression test directly covers the missed-swap case.

## Verdict

**ship-as-is** after 2 rounds. High fixed with a regression test; both
Lows fixed.
