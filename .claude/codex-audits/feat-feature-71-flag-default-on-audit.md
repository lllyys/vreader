---
branch: feat/feature-71-flag-default-on
threadId: 019e6c3f-6124-77a0-9074-23df067056c0
rounds: 3
final_verdict: ship-as-is
date: 2026-05-28
---

# Codex audit — feature #71 terminal WI: flip `FeatureFlags.epubContinuousScroll` default ON

Gate-4 implementation audit for the WI that flips EPUB continuous cross-chapter
scroll from default-OFF to default-ON (the feature's terminal step). The
real-touch-scroll device verification that retired the deferral risk is recorded
in `dev-docs/verification/feature-71-20260527-realscroll.md`.

## Round 1 — initial audit (3 Low)

| # | file:line | severity | issue | resolution |
|---|---|---|---|---|
| 1 | FeatureFlagsTests.swift:176 | Low | `epubContinuousScrollOverridePersists` persisted `true` — now equal to the new default, so the reload assertion no longer proves the persisted-override LOAD path (would pass even if init ignored persisted values). | **Fixed** — test now persists `false`, asserts the reloaded instance reads `false` (persisted OFF beats the new ON default), then `removeOverride` + asserts the default returns to `true`. Discriminating again. |
| 2 | EPUBReaderContainerView.swift:541 | Low | Stale comment said the feature "ships dark behind a feature flag (default off)" + "final WI flips it on" at the only production consumer. | **Fixed** — comment rewritten: flag defaults ON, the guard still honours an explicit persisted `false` override, continuous mode restricted to EPUB `.scroll`. |
| 3 | FeatureFlags.swift:9 / :147 | Low | Header + `setOverride` docs described only `aiAssistant` as persisted; `epubContinuousScroll` is also in `persistedFlags`. | **Fixed** — both comments now list `aiAssistant` AND `epubContinuousScroll` (pointing at `persistedFlags`). |

Codex also confirmed: persistence behavior correct (absent UD key → new ON default; persisted `true` → ON; persisted `false` → OFF via `object(forKey:) != nil` guard); only one production read of the flag (`buildContinuousScrollConfig`), paged mode unaffected via `epubLayout == .scroll`; no Swift 6 / actor impact.

## Round 2 — verify Low fixes + consumer re-scan (1 Medium surfaced)

The 3 Low fixes verified correct. The same consumer scan surfaced a Medium the
flag-flip newly exposes:

| # | file:line | severity | issue | resolution |
|---|---|---|---|---|
| 4 | EPUBReaderContainerView.swift:577 (loader) → EPUBChapterBodyRewriter.swift (stylesheet loop) | Medium | The continuous-scroll linked-stylesheet loader passed the **bare** `<link>` href to resolve against the resource base. A nested chapter's cross-directory `<link href="../css/x.css">` mis-resolves (root-escaping path) → chapter renders unstyled. The original code's acceptability rationale was *"continuous mode ships dark behind a flag"* — which the flag flip invalidates. Real regression vs paged mode (paged loads each spine item with the chapter's own base URL). | **Fixed** — the rewriter now resolves the bare `<link>` href against the chapter dir (`EPUBChapterResourceURL.join(dir: chapterDir, relative: linkHref)`) BEFORE calling the loader, handing it the resource-root-relative path. This is identical to how the rewriter already absolutizes img `src` / CSS `url(...)`, so CSS resolves to the same root images do. Flat EPUBs (chapterDir == "") pass the bare href unchanged — no regression. Loader in `EPUBReaderContainerView` now anchors the resolved path against `resourceBase`. |

Tests added (EPUBChapterBodyRewriterTests, suite 35→37 GREEN):
- `linkedStylesheetResolvedAgainstChapterDir` — nested chapter `OEBPS/text/sub/c.xhtml` + `<link href="../css/style.css">` → loader receives exactly `OEBPS/text/css/style.css`, CSS inlined.
- `flatLinkedStylesheetUnchanged` — flat chapter `chapter1.xhtml` + `<link href="style.css">` → loader receives `style.css` (common-case no-regression).
- `linkedStylesheetInlined` updated to match the resolved href.

## Round 3 — verify Medium fix

**No findings.** Codex confirmed the fix correct + complete, `linkDir` still
correct (derived from `resolvedHref`), tests cover regression + no-regression
cases, and the updated doc comments (rewriter param, provider field, container
loader) match the new contract. One non-blocking naming nit (rewriter closure
param still `relativeHref`) — **applied** (renamed to `resolvedHref`).

## Summary verdict

`ship-as-is`. All findings resolved: 3 Low (test discrimination + 2 stale
comments) + 1 Medium (nested-EPUB stylesheet resolution — a real regression the
flag flip would otherwise have shipped) + 1 naming nit. Zero open
Critical/High/Medium/Low. The Medium catch is the headline: flipping the default
ON correctly forced the nested-EPUB CSS path to become production-correct before
shipping.

## Files changed

- `vreader/Services/FeatureFlags.swift` — default flip OFF→ON + doc comments.
- `vreader/Views/Reader/EPUBChapterBodyRewriter.swift` — resolve `<link>` href against chapter dir before the loader; param/doc.
- `vreader/Views/Reader/EPUBContinuousChapterProvider.swift` — loader field doc.
- `vreader/Views/Reader/EPUBReaderContainerView.swift` — loader receives resolved href; comments updated.
- `vreaderTests/Services/FeatureFlagsTests.swift` — default-ON + persistence-discriminating tests.
- `vreaderTests/Views/Reader/EPUBChapterBodyRewriterTests.swift` — nested/flat stylesheet resolution tests.
- `README.md`, `docs/architecture.md`, `docs/features.md` — doc sync.
- `dev-docs/verification/feature-71-20260527-realscroll.md` (+ artifact) — real-scroll device-verification evidence.
