---
branch: feat/feature-42-wi11a-bilingual-evalchannel
threadId: 019e723e-bfcb-7c12-8150-7dce1dbd87f0
rounds: 4
final_verdict: ship-as-is
date: 2026-05-29
---

# Gate-4 audit — Feature #42 WI-11 (Readium paged bilingual via the eval channel)

Covers the WI-11a spike (`ReadiumBilingualEvalAdapter`) + the WI-11b wiring
(commander, host+Bilingual extension/driver, coordinator eval seam, chapter
tracker). Independent auditor: Codex (`codex exec --sandbox read-only`, model
gpt-5.5). Author = the implementing Claude Code session(s); auditor = separate
Codex process (rule-48 author/auditor separation preserved).

## Round-count note (deviation from the nominal 3-round cap)

Rule 47 caps the implementation audit at 3 rounds, then "escalate: accept,
defer, or redesign". This audit ran **4 rounds**. The deviation was a
deliberate engineering call, not churn:

- Findings **converged monotonically**: R1 = 2 High + 4 Med + 1 Low → R2 =
  1 High + 2 Med → R3 = 2 Med (one a minor regression from an R2 fix) → R4 = 0.
- Both R3-residual findings were **bounded, surgical edge cases** (a
  malformed-eval-payload dedupe hole; a first-enable-in-scroll setup-sheet
  bypass) — not the design-level failure the cap guards against.
- The Gate-4 bar is **zero open Critical/High/Medium**, so "accept" / "defer"
  would have shipped open Mediums; "redesign" was unwarranted. One more bounded
  round was the proportionate choice. Recorded here so the deviation is visible.

## Round 1 — block-recommended

| Severity | File | Issue | Resolution |
|---|---|---|---|
| High | ReadiumEPUBHost+Bilingual.swift | First-enable/confirm didn't translate the VISIBLE chapter — `runBilingualEnumerateForCurrentChapter` reset `lastEnumeratedHref=nil` then relied on it for the locator → prefetch/inject never started until a page turn. | Fixed R2: `@State lastKnownReadiumLocator` captured in `onLocationChange`; forced enumerate passes it; `selectedHref(supplied→lastKnown→lastEnumerated)`. |
| High | ReadiumEPUBHost.swift | Persisted bilingual-on state + "Translate entire book" provider not initialized on open (`ensureBilingualViewModel` only called from the More-menu toggle). | Fixed R2: `.task` calls `ensureBilingualViewModel()` after `openBilingualParser()`. |
| Medium | ReadiumEPUBHost+Bilingual.swift | Same-chapter duplicate enumerates (dedupe href written only after `await enumerate()`). | Fixed R2: synchronous in-flight guard before the Task; forced path bypasses via `force:`. |
| Medium | ReadiumEPUBHost+Bilingual.swift | PAGED-only path not gated from Readium scroll layout. | Fixed R2 (toggle/entry no-op) + R3 (layout-change handler). |
| Medium | ReadiumEPUBHost+Bilingual.swift | Disable raced an in-flight enumerate (mutated orchestrator state after disable). | Fixed R2: recheck `vm.isEnabled` after `await enumerate()` before `updateBlocks`. |
| Medium | ReadiumEPUBHost+Bilingual.swift | "Translate entire book" provider publication delayed (same root cause as the persisted-on High). | Fixed R2 (same fix). |
| Low | ReadiumBilingualCommander.swift | Add ambiguous-basename normalization test. | Fixed R2: test added (ambiguous basename → raw, never mis-resolves). |
| OK | — | Security (FoliateJSEscaper), reuse (no fork), compliance (no message handler, files <300, designed surfaces reused), bridge safety (tolerant parse) all clean. | — |

Seam #3 (the WI-8 href-consistency class) reviewed and **passed** — OPF spine
hrefs from `EPUBParser.open` metadata, normalization via exact→unique-suffix→
unique-basename, ambiguous matches refused.

## Round 2 — block-recommended (commit eccef886)

| Severity | Issue | Resolution |
|---|---|---|
| High | Persisted-on open race: first `locationDidChange` could fire before the VM was built (the navigator mounts on `state=.ready` from `vm.open()`, before `ensureBilingualViewModel` ran). | Fixed R3: `.task` reordered so `openBilingualParser()` + `ensureBilingualViewModel()` run BEFORE `await vm.open()`. |
| Medium | Dedupe blocked retry after a FAILED enumerate (`enumerate()` returned `[]` for failure AND empty alike). | Fixed R3: `enumerate() -> [BilingualBlock]?` (nil=failure, []=success-empty); driver commits on non-nil, `clearInFlight` reverts on nil. |
| Medium | No `epubLayout`-change handler: paged→scroll while enabled left stale decorations. | Fixed R3: `.onChange(of: epubLayout)` → clearAndReset on leaving paged, reEnumerate on returning. |

HIGH-1, MED-5, LOW-7 confirmed resolved in R2.

## Round 3 — block-recommended (commit f91f10ac)

| Severity | Issue | Resolution |
|---|---|---|
| Medium | Parse failure committed as success-empty (`parseEnumerateMessage` returns `[]` for malformed payloads → permanent dedupe). | Fixed R4: `isValidEnumerateShape(_:)` positive shape gate — bare `[Any]` or `{blocks:[Any]}` → `[]`; string/number/blocks-less dict → `nil` (retryable). |
| Medium | First-enable-in-scroll bypassed the setup sheet; return-to-paged then enumerated with default lang/granularity. | Fixed R4: `enableToggleAction`/`confirmAction`/`reEnumerateAllowed` — setup presented regardless of layout; enumerate never runs while `needsSetupSheet`. |

R2's HIGH (persisted-on race), layout handling, and nil/empty commit guard
confirmed resolved in R3.

## Round 4 — ship-as-is (commit 4f6fc78d)

Both R3-residual Mediums confirmed resolved. No new Critical/High/Medium from
the tracker extraction (`ReadiumBilingualChapterTracker.swift`), the route
changes, or the file-size budget. Parser/gate shapes confirmed consistent
(no false-negative rejection of a real enumerate result). No path found where
`enumerate()` runs while `needsSetupSheet == true`.

## Verdict

**ship-as-is.** Zero open Critical/High/Medium. Full serial `vreaderTests`
bundle: 7531 tests pass. `xcodebuild build`: BUILD SUCCEEDED. All WI-11 files
<300 lines. Device slice-verification recorded in the PR description.
