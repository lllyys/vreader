---
branch: feat/56-wi-2-translation-store
threadId: 019e414f-dbd4-7b50-8c26-07d7e30e09e1
rounds: 2
final_verdict: ship-as-is
date: 2026-05-20
---

# Codex Audit — feat/56-wi-2-translation-store

**Feature**: #56 — bilingual reading mode (WI-2, foundational).
**Scope**: `ChapterTranslationRecord` value DTO (+ canonical `lookupKey`
builder) and the `ChapterTranslationStore` actor (the persistent disk cache,
scope item 2). Plus `VReaderApp` wiring and the `docs/architecture.md`
Services-Layer row.
**Auditor**: Codex (`mcp__plugin_codex-toolkit_codex__codex`), read-only sandbox.
**Thread**: `019e414f-dbd4-7b50-8c26-07d7e30e09e1`. Gate 4 — implementation audit.

## Round 1 — 3 findings (0 Critical, 0 High, 2 Medium, 1 Low)

Codex confirmed the DTO + store API match the plan, the single-instance
idempotent upsert does fetch-before-insert as required, `ModelContext`-per-method
matches the `PersistenceActor` precedent, and the `|` `lookupKey` separator is
collision-safe for the documented field formats.

1. **Medium — `.shared` did not match the plan's ownership model.** The first
   cut had `.shared` lazily self-build a *second* `ModelContainer` with a
   default `ModelConfiguration()`, bypassing `ModelContainerFactory`. Hazard:
   a UI-test run where `VReaderApp` uses an in-memory container would leave
   `.shared` pointing at the default disk store (split-brain), and a disk-open
   failure silently flipped the "persistent" cache to a transient in-memory one.
   **Fix**: removed the self-building init; the production `init()` is now
   `private` and unconfigured (`modelContainer: ModelContainer?` = nil). Added
   an actor `configure(modelContainer:)`; `VReaderApp.init()` wires `.shared`
   to the app's own container (the one `ModelContainerFactory` built) via
   `Task { await ChapterTranslationStore.shared.configure(modelContainer:) }`.
   Every store method `guard`s the optional container — an unconfigured store
   is a safe no-op / empty result.

2. **Medium — malformed `translatedJSON` decoded to `[]`, indistinguishable
   from a legitimate empty translation.** Corruption would masquerade as a
   cache hit, so a later caller skips re-translation and serves the broken row
   forever.
   **Fix**: `decodeSegments` is now failable (`-> [String]?`); `record(from:)`
   returns `nil` when `translatedJSON` won't decode. `translation(forKey:)`
   returns `nil` (miss) for a corrupt row; `translations(forKeys:)` and
   `cachedUnits(...)` exclude corrupt rows. A well-formed `"[]"` still decodes
   to `[]` — a legitimate empty value, kept distinct from a corrupt-row miss.
   The caller re-translates and the idempotent `upsert` overwrites the bad row.

3. **Low — tests missed both risky paths.** Added `debugInsertRaw(...)` (a
   DEBUG-gated test helper that seeds a raw `ChapterTranslation` row) and the
   tests `corruptTranslatedJSONIsTreatedAsAMissNotEmpty`,
   `corruptRowIsExcludedFromBatchFetchAndCachedUnits`,
   `reUpsertOverwritesACorruptRow`,
   `legitimateEmptySegmentArrayRoundTripsAsEmptyNotMiss`, and
   `unconfiguredStoreIsASafeNoOp` (via a `makeUnconfiguredForTesting()` factory).

## Round 2 — 0 findings

Codex confirmed both round-1 Mediums are genuinely resolved, the new tests are
behavior-focused (not wiring-only), and no new Critical/High/Medium was
introduced.

**Forward-looking note (not a finding in this diff)**: the
`Task { await … configure }` in `VReaderApp.init()` is safe for WI-2 only
because there is no production caller of `ChapterTranslationStore` yet and
`bilingualReading` defaults `false`. Future WIs that add live callers must keep
those callers unreachable until after launch configuration completes — tracked
here so WI-6/WI-7 honor it (those callers run on a reader-open path, which is
long after app init, so the invariant naturally holds).

## Disposition

Zero Critical/High/Medium after round 2. Final verdict: **ship-as-is**.
