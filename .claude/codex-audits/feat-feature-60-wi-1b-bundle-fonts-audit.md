---
branch: feat/feature-60-wi-1b-bundle-fonts
threadId: 019e2ed0-31f0-7773-8dc6-60e0ab10748f
rounds: 2
final_verdict: ship-as-is
date: 2026-05-16
---

## Scope

Feature #60 WI-1b — bundle the Source Serif 4 + Inter font binaries (deferred manual-ops step, GH #774).

Changes:
- 7 `.otf` files added to `vreader/Resources/Fonts/` — `SourceSerif4-{Regular,It,Bold,BoldIt}.otf` (Source Serif 4.005, Adobe `adobe-fonts/source-serif`), `Inter-{Regular,Medium,SemiBold}.otf` (Inter 4.1, `rsms/inter`).
- 2 SIL OFL 1.1 license texts vendored alongside: `SourceSerif4-LICENSE.md`, `Inter-LICENSE.txt`.
- `UIAppFonts` array added to `project.yml`'s `info.properties` — 7 bare `.otf` filenames.
- 3 tests added to `vreaderTests/Services/ReaderTypographyTests.swift`: `body_sourceSerif4_resolvesToBundledFace`, `body_inter_resolvesToBundledFace`, parameterized `bundledFace_resolvesByPostScriptName` over all 7 PostScript names.
- `vreader.xcodeproj/project.pbxproj` regenerated via xcodegen.

## Round 1 — Codex thread 019e2ed0

| File | Severity | Issue | Resolution |
|---|---|---|---|
| `project.yml` (font assets) | High | The 7 font/license files were present on disk but **untracked** — `git diff main` didn't show them, so a clean checkout would ship without the registered fonts. | **Fixed** — `git add vreader/Resources/Fonts/`; all 9 files staged before commit. |
| `ReaderTypographyTests.swift:6` | Low | File header + the two `*_whenFontNotRegistered` fallback tests still said "fonts NOT bundled in this WI / deferred to WI-1b" — stale after WI-1b. | **Fixed** — header rewritten to state WI-1b bundles the binaries + `UIAppFonts`; the two fallback tests renamed `body_sourceSerif4_resolvesToASerifFace` / `body_inter_resolvesToASansFace` with corrected comments (trait invariant holds for bundled face OR defensive fallback). |

Codex independently confirmed clean: `UIAppFonts` bare filenames are correct (xcodegen flat-copies individual file resources to the bundle root); PostScript names match the `.otf` metadata (Codex verified via `fc-scan`); OFL/RFN handling is correct (fonts bundled unmodified under original names, OFL texts vendored — the Reserved Font Name 'Source' clause only restricts modified derivatives); no Release/DebugBridge gate risk (fonts ship in all configs, intended); the 3 new tests are behavior-asserting, not wiring-only; bundling the `.md`/`.txt` license files as resources is fine.

## Round 2 — Codex thread 019e2ed5 (verification)

| File | Severity | Issue | Resolution |
|---|---|---|---|
| `ReaderTypographyTests.swift:14` | Low | After the round-1 rename, the header still referenced the tests by their *old* working names `*_hasSerifTrait` / `*_hasSansTrait` — never the actual method names. | **Fixed** — header reference corrected to `*_resolvesToASerifFace` / `*_resolvesToASansFace` to match the methods. |

Codex confirmed round-1 fixes resolved (9 resources staged, misleading comments gone, renamed tests coherent) and gave "fix the one stale header reference, then ship." That reference is a comment-only change with no logic impact; fixed without a further Codex round.

## Test evidence

- `vreaderTests/ReaderTypographyTests` — 12/12 pass (the 3 new WI-1b tests + 9 existing), confirmed twice (before and after the round-1 rename).
- Full `-only-testing:vreaderTests` run: the test host crashed mid-run ("Restarting after unexpected exit, crash, or test timeout" — a 66 s output gap) and xcodebuild flagged a scatter of unrelated suites (`SyncOutboundQueueTests`, `HTTPTTSProviderAzureTests`, `MDReaderViewModelLifecycleTests`, `SelectionPopoverActionTests`, `ReadingSessionTrackerCapTests`). This is the documented pre-existing vreader full-suite instability (cf. feature #50's "full-suite SIGSEGV in unrelated suites"). All 27 tests across the 5 flagged suites were re-run **in isolation and pass** — confirming the crash is environmental, not a regression from font bundling (a font-resource addition cannot SIGSEGV `SyncOutboundQueueTests`).

## Verdict

ship-as-is — both Low findings and the High (staging) finding resolved; no Critical/High/Medium open. Font bundling is a resource + plist + test change with no Swift logic surface.
