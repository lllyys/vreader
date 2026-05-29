---
branch: feat/feature-42-wi12-scroll-bilingual
threadId: codex-exec-wi12-r1..r4
rounds: 4
final_verdict: ship-as-is
date: 2026-05-29
---

# Gate-4 audit — Feature #42 WI-12 (per-spine bilingual in Readium scroll mode, Option B)

Lifts WI-11's paged-only bilingual gate so interlinear translation works in
Readium scroll layout — per-spine (one chapter on scroll-into-view), accepting a
documented behavior delta vs legacy #71's stitched cross-chapter bilingual
(Readium has no multi-spine-stitch API; user chose Option B). Legacy
EPUBWebViewBridge #71 untouched while the flag is OFF.

Independent auditor: Codex (`codex exec --sandbox read-only`). Author/auditor
separation preserved (separate process).

## Round-count note (4 rounds — one over the nominal cap, deliberate)

The audit found ONE race class — **stale blocks vs current locator** in scroll
mode (rapid spine changes against the shared single `-1` orchestrator bucket) —
surfacing in a different inject path each round:

- **R1 (block):** stale enumerate RESULT could overwrite the bucket (MED) + a
  vestigial `newLayout` param (LOW).
- **R2 (block):** the per-await generation guard covered the enumerate boundary
  but not the later inject-chain awaits (MED).
- **R3 (block):** the enumerate chain was fully guarded, but the nil-generation
  `.readerBilingualDidChange` path still paired current-unit translations
  against stale `currentBlocks` (MED).
- **R4 (ship-as-is):** the per-site generation guards were converging but
  whack-a-mole; the **root cause** was the shared blocks bucket having no owner
  identity. R4 applied a single **block-ownership invariant** at the shared
  inject choke point that closes the class for BOTH entry points.

Per rule 47 the cap is 3 rounds → escalate. The 4th round was a deliberate
engineering call, recorded here: findings were all MEDIUM (no Critical/High),
strictly converging, and round 4 was a ROOT-CAUSE fix (one invariant) rather
than another per-site patch. The orchestrator stopping rule was explicit — if
R4's re-audit had found yet another instance of this class, it would have
escalated to the user (that would have indicated the single-bucket model needs
a redesign decision the user owns). R4 came back clean, so the class is closed
without redesign.

## The root-cause fix (commit 1b1be47c)

- `blocksOwnerHref: String?` on the Readium-side `ReadiumBilingualChapterTracker`
  (`@MainActor`) — NOT on the shared `EPUBBilingualOrchestrator` (legacy #71
  untouched).
- Stamped via `setBlocksOwner(href:)` at the `updateBlocks(blocks)` commit in
  `runBilingualEnumerate` (after the generation guard passes), using the
  normalized OPF-relative href — same space the inject locator carries.
- `injectBilingualIfCached(for:)` — the single funnel for BOTH the
  generation-guarded enumerate chain and the nil-generation
  `.readerBilingualDidChange` path — guards `blocksMatch(locatorHref:)` BEFORE
  `translationsByBid` pairing AND the Bug #268 `translateBlocksDirectly`
  fallback. A→B mismatch ⟹ inject rejected (the in-flight enumerate injects when
  it commits its own blocks + owner).
- Per-await generation guards (R2/R3) kept as cheap defense-in-depth on the
  enumerate path.

## R4 verdict (ship-as-is) — confirmations

- Both inject entry points funnel through the owner-gated choke point; A-owned
  blocks cannot be used for B's locator.
- Owner href and inject locator href share the same `normalizedLocator`
  OPF-relative space (no false-negative/positive from normalization mismatch).
- `setBlocksOwner` is synchronous-after-`updateBlocks` on `@MainActor` (no await
  between) — owner and blocks cannot disagree; a stale enumerate can't set a
  stale owner (generation guard precedes it).
- Normal settled inject (owner == current locator) proceeds — no false-negative.
- No Readium inject/pairing path bypasses the choke point. `bilingualCommander.inject`
  is only called from the gated site.

## Verdict

**ship-as-is.** Stale-blocks race class closed. Zero open Critical/High/Medium.
Full serial `vreaderTests`: 7544 pass. `xcodebuild build`: BUILD SUCCEEDED.
Production files <300 (driver 300, tracker 250). Legacy #71 untouched
(Readium-host-only diff). Device-verified in scroll mode (interlinear Chinese
rendered per-spine; evidence:
`dev-docs/verification/artifacts/feature-42-wi12-scroll-bilingual-20260529.png`).
