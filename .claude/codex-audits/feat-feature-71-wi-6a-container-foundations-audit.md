---
branch: feat/feature-71-wi-6a-container-foundations
threadId: 019e6683-c15b-7ed0-930c-7f525a9f6847
rounds: 1
final_verdict: ship-as-is
date: 2026-05-27
---

# Codex Audit — Feature #71 WI-6a (container-integration foundations)

Two foundational, unit-testable units split out of the original Large WI-6 (see
the plan's v4 revision note): `EPUBContinuousChapterProvider` (the spine-index →
rewritten `EPUBChapterBody` factory the WI-6b coordinator is built with) and
`EPUBWebViewEvaluatorHandle` (the late-binding seam resolving the
coordinator-`evaluate`-before-webview-exists gap). No live-render change.

## Gate 2 re-audit (plan amendment) — same thread, prior turns

The WI-6 split + the evaluate-binding design were re-audited first (the plan was
amended mid-implementation). Round 1 found 1 Critical + 2 High + 1 Medium — **all
WI-6b** (continuous-mode progress must update `href` not just total progress;
stale-handle identity on rebuild; `file://` bootstrap navigation policy;
inner-scroll-root safe-area/restore). All four were folded into the plan's new
"WI-6b design requirements" subsection. Round 2 confirmed: the four are addressed
at the plan level, **WI-6a is safe to implement with zero open Critical/High/
Medium against the 6a scope**, and the split is cohesion-sound. (One Low — a
stale "creates ONE handle" sentence — fixed.) `restoreHighlightsInSectionJS` was
then narrowed out of 6a → 6b (it's coupled to the section-scoped XPath-re-rooting
paint primitive, behavioral, not foundational) — a conservative narrowing.

## Gate 4 implementation audit — round 1

**No findings.** Codex verdict, verbatim summary:
- `EPUBContinuousChapterProvider` matches the factory contract — guards
  negative/out-of-range indices, maps `spineItems[i].href` →
  `parser.contentForSpineItem` → `EPUBChapterBodyRewriter.rewrite`, and
  `makeClosure()` returns the exact `@MainActor (Int) async throws ->
  EPUBChapterBody` shape WI-6b needs.
- `EPUBWebViewEvaluatorHandle` matches the plan + coordinator contract:
  `webView == nil` throws `noWebView`; the async bridge to `evaluateJavaScript`
  is correct for the single-callback WebKit API.
- Concurrency sound under Swift 6: both types `@MainActor`; the parser
  existential is `Sendable`; the non-`Sendable` `linkedStylesheetLoader` never
  escapes the actor boundary; `makeClosure()` preserves the required
  `@MainActor` isolation. No WI-6b contract mismatch.

(Codex ran a static audit; the full unit suite — 7261 tests, 0 failures,
including the 7 new WI-6a tests — is the test-gate evidence.)

## Verdict

**ship-as-is.** Zero open findings against the WI-6a scope; the behavioral risk
is confined to WI-6b, which the amended plan now specifies explicitly.
