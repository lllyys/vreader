---
branch: feat/feature-56-wi-11-azw3-mobi-interlinear
threadId: 019e42c2-2d41-7072-bb66-14ed1029c2df
rounds: 3
final_verdict: ship-as-is
date: 2026-05-20
---

# Codex Gate-4 audit — feature #56 WI-11

AZW3/MOBI bilingual interlinear renderer + Foliate host wiring. Audit
ran read-only over the diff against `main` (`2544fa2` ← `fc5ad82`+
audit-fix commits).

## Round 1 — findings + resolutions

| File | Severity | Finding | Resolution |
|---|---|---|---|
| `vreader/Views/Reader/FoliateSpikeView.swift:711` | High | `relocate` carries the live `sectionIndex`, but WI-11 dropped it on the floor and only updated `currentSectionHref` from `section-load`. Page turns inside an already-loaded section would keep bilingual state pinned to a stale section. | **Fixed.** Added `.foliateRelocated` notification fired on every relocate. Container observes both `.foliateSectionLoaded` (fresh DOM → enumerate) AND `.foliateRelocated` (every position change → update unit tracking). `currentSectionIndex` is the canonical state; `injectIfCached` + toggle/confirm now scope by it. |
| `vreader/Services/Foliate/JS/foliate-host.js:329` | High | `bilingualEnumerate` flattened every loaded section's DOM into one block list. Foliate paginated mode can keep multiple sections loaded; without per-section scoping, one unit's translation map would spill into adjacent sections. | **Fixed.** `bilingualEnumerate(targetSectionIndex)`, `bilingualInject({...targetSectionIndex})`, `bilingualClear(targetSectionIndex)` now scope their walks. JS payload tags each block with its `sectionIndex`. `BilingualBlock` gained an optional `sectionIndex` (nil for EPUB). `FoliateBilingualPipeline.blocks(_:forSection:)` filters by section before mapping translations. |
| `vreader/Services/Reader/FoliateChapterTextProvider.swift:52` | Medium | `translationUnits()` cached `[]` unconditionally on first call. The live extractor returns `[]` whenever `Coordinator.isBookReady == false`, permanently poisoning the provider. | **Fixed.** Only cache non-empty results. A pre-ready call is retried on the next lookup. |
| `vreader/Services/Foliate/JS/foliate-host.js:357` | Medium | `bilingualInject` interpolated raw `bid` attribute values into `querySelector` — a hostile book HTML's `data-vreader-bid` could break the selector. `FoliateJSEscaper` (Swift-side) cannot help because the dangerous input is DOM-side. | **Fixed.** `bilingualEnumerate` re-stamps any pre-existing `data-vreader-bid` that doesn't match `^fb\d+$` (trusted prefix). `bilingualInject` defensively uses `CSS.escape` on every bid before interpolating. |

Round-1 resolution: 12 new tests added (4 pipeline partitioning, 4 JS section-scoping, 3 orchestrator section-scoping, 1 enumerate sectionIndex tagging). All 49 WI-11 tests pass.

## Round 2 — findings + resolutions

| File | Severity | Finding | Resolution |
|---|---|---|---|
| `vreader/Views/Reader/FoliateBilingualContainerView.swift:231` | High | `section-load` was treated as "current section changed", but in paginated mode foliate-js can fire it for adjacent preloaded sections before the user relocates. The handler overwrote canonical position state + clobbered the orchestrator's single `currentBlocks` cache. | **Fixed.** (a) `handleSectionLoaded` no longer mutates `currentSectionHref` / `currentSectionIndex`. Only `.foliateRelocated` (which fires *after* the user is actually on the section) owns canonical position. (b) `FoliateBilingualOrchestrator` now keeps per-section block caches (`blocksBySection: [Int: [BilingualBlock]]`) instead of a single array. `updateBlocks(_:forSection:)` updates one section; other sections preserved. |

Round-2 resolution: 3 new tests added (per-section update isolation, inject against preloaded adjacent, per-section clear). All 52 WI-11 tests pass.

## Round 3 — findings + resolutions

| File | Severity | Finding | Resolution |
|---|---|---|---|
| `vreader/Views/Reader/FoliateBilingualContainerView.swift:221` | Medium | The per-section cache had no way to drop a section when its scoped enumerate returned `[]` (`handleEnumeratedBlocks` dropped empty arrays outright). A previously-populated section that re-renders empty would leave stale block ids in the cache; a later inject for that section could reuse obsolete bids. | **Fixed.** JS payload now wraps blocks: `{requestedSectionIndex, blocks}`. The scoped enumerate that returns no blocks still surfaces the requested section. `FoliateBilingualPipeline.parseEnumeratePayload` decodes both the new wrapped shape AND the legacy bare-array shape (older bundles). The container calls `clearBlocks(forSection:)` when a scoped enumerate returns `[]`. |

Round-3 resolution: 5 new tests added (wrapped-shape decode, scoped-empty signal, legacy bare-array fallback, parseEnumerateMessage shape-tolerance). All 57 WI-11 tests pass.

## Round 3 — closing pass

| File | Severity | Finding | Resolution |
|---|---|---|---|
| `vreader/Views/Reader/FoliateBilingualContainerView.swift:303` | Low | Stale doc comment on `handleRelocated`: said it "also push[es] a scoped clear of the just-left section", but the implementation no longer does that (intentional — back-paging in paginated mode benefits from keeping the cache). | **Fixed.** Comment rewritten to accurately describe the per-section-cache retention policy and explain why no clear runs here. No behavior change. |

## Final verdict

**ship-as-is**

Zero open Critical/High/Medium findings. Round-3 closing-pass Low finding fixed (stale comment). 57 WI-11 tests pass; full `vreaderTests` suite green.

## Coverage of audit dimensions

1. **Correctness vs the plan** — Per-section enumerate/inject/clear interlinear rendering delivered. AZW3/MOBI bilingual translation cached + injected on the live Foliate path.
2. **Edge cases** — Race: bilingual toggle during section load → `ensureBilingualViewModel` is idempotent; setup-sheet gate defers enumerate until user confirms. Race: section advance during prefetch → BilingualReadingViewModel's epoch + request-token handles cancellation. VM construction order: lazy + coordinator-box-driven, retries on next coordinator notification.
3. **Security** — `FoliateJSEscaper.escapeForJSString` applied to all translation interpolation. `bilingualEnumerate` re-stamps untrusted `data-vreader-bid`. `bilingualInject` `CSS.escape`s bids defensively.
4. **Duplicate / dead code** — None introduced. `BilingualBlock` shared with EPUB via optional `sectionIndex` (EPUB callers use the default-nil init).
5. **VReader compliance** — Swift 6 strict concurrency clean. `@MainActor` correct on container, orchestrator, view extension. `FoliateChapterTextProvider` is an `actor` (correct: bridges `@MainActor` seam). File sizes: largest new file is `FoliateBilingualContainerView.swift` at ~360 lines including comments — over the soft 300-line guideline, accepted because splitting would fork the SwiftUI state across files and reduce readability; tracked as a refactor candidate.
6. **Bridge safety** — `FoliateJSEscaper` used in `bilingualInjectJS` (translation text) AND in `FoliateSpikeView+SectionExtracting.swift` (section-id JS interpolation, defence-in-depth — unit values are currently stringified ints).
7. **Rule 51 (no self-designed UI)** — Container reuses the designed `BilingualSetupSheet` (committed under `dev-docs/designs/vreader-fidelity-v1/`); no new UI surfaces invented.
8. **Concurrency model** — `FoliateSectionExtracting` declared `@MainActor + AnyObject + Sendable` (a main-actor-isolated AnyObject existential is safely Sendable). `FoliateChapterTextProvider` actor holds it and reaches it via `await`. No `nonisolated(unsafe)` introduced.
9. **Notification plumbing** — All three new channels (`.foliateBilingualBlocksEnumerated`, `.foliateRequestBilingualEvalJS`, `.foliateSectionLoaded`, `.foliateRelocated`) filter by `fingerprintKey`. The Coordinator's `.foliateRequestBilingualEvalJS` observer mirrors the existing `.foliateRequestAnnotationJSCreate` / `.foliateRequestAnnotationJSDelete` lifecycle (init + deinit).
10. **JS host semantics** — Missing sections handled (`if (!doc) continue`). Malformed DOM handled (try/catch). Idempotent re-inject: existing decoration sibling has `textContent` replaced rather than a duplicate appended.
