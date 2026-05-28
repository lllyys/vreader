---
branch: feat/feature-42-wi1-spm-readium
threadId: codex-exec-2026-05-29-wi1
rounds: 1
final_verdict: ship-as-is
date: 2026-05-29
---

# Codex Gate-4 audit — Feature #42 Phase-1 WI-1 (add Readium SPM + open-smoke test)

Foundational WI: adds the Readium Swift Toolkit (3.9.0, exact-pinned) SPM dependency
(ReadiumShared + ReadiumStreamer + ReadiumNavigator; no ReadiumLCP, no GCDWebServer adapter)
+ a genuine open-smoke test (`AssetRetriever` → `PublicationOpener` parses the bundled
`mini-epub3.epub`, asserts readingOrder + metadata title). No dispatch/flag/engine change.

## Round 1 — 1 High + 1 Low

| file:line | severity | issue | resolution |
|---|---|---|---|
| project.yml (vreaderTests) / ReadiumOpenSmokeTests.swift:17 | High | The Readium products were declared only on the `vreader` app target; the test target imports `ReadiumShared`/`ReadiumStreamer` but its `packageProductDependencies` was empty — fragile (relied on host-app transitive exposure, can fail to compile). | **Fixed** — added `ReadiumShared` + `ReadiumStreamer` to the `vreaderTests` target deps in project.yml; regenerated; pbxproj now carries the test-target package deps (20 refs). Re-ran the focused test: `** TEST SUCCEEDED **` 2/2. |
| Package.resolved:31 | Low | `GCDWebServer` is resolved as a transitive package even though its adapter product is not linked. Expected from Readium's manifest (it's a package-level dep of the toolkit); not linked into the binary. | **Accepted** — not linked (no GCDWebServer product in the app or test target); resolving-but-not-linking is inherent to Readium's package graph. Recorded for the security-review trail. |

## Verdict

Round 1: 1 High (fixed — test-target deps) + 1 Low (accepted — transitive GCDWebServer not linked).
Readium 3.9.0 product names confirmed correct against the package manifest. Scope clean (no
ReaderContainerView/ReaderEngine/FeatureFlags/engine changes). Smoke test is a genuine parse, not
a mock; DEBUG-gated. **Verdict: ship-as-is.** Focused test 2/2 green; build SUCCEEDED.
