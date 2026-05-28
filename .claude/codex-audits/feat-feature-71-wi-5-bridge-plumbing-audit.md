---
branch: feat/feature-71-wi-5-bridge-plumbing
threadId: 019e6541-13b3-7520-92d5-07446a5fb85e
rounds: 3
final_verdict: ship-as-is
date: 2026-05-27
---

# Codex Audit — Feature #71 WI-5 (EPUB continuous scroll — bridge plumbing)

Wires the four foundational WIs (EPUBSpineWindow, EPUBChapterBodyRewriter,
EPUBContinuousScrollJS, EPUBContinuousScrollCoordinator) into `EPUBWebViewBridge`:
a `continuousScroll: EPUBContinuousScrollConfig?` input that, when non-nil,
mode-branches script/handler injection (the section-aware observer replaces
`progressTrackingJS`), parses the `continuousScrollHandler` JS message into
`EPUBScrollBoundarySignal`, drives windowed whole-book progress, and attributes
selections to their section href. Additive — nil config ⇒ the legacy
one-chapter path is byte-identical.

## Round 1 — 1 High / 1 Medium / 1 Low

| file:line | severity | issue | resolution |
|---|---|---|---|
| EPUBHighlightJS.swift (selection JS) | **High** | Tagging the selection with the START section's `data-vreader-href` without clamping the range left a cross-divider drag with `endPath`/`endOffset` in the NEXT section — an invalid mixed-section anchor for per-section restore. | **Fixed.** The selection JS now resolves both start + end section ancestors; when they differ it clamps `range.setEnd(startSection, startSection.childNodes.length)` (the plan's [C1] clamp-to-start-section), re-reads `text`+`rect`, and rejects (no postMessage) if the clamp empties the selection. Legacy mode (both sections null) never runs the clamp. |
| EPUBContinuousScrollBridge.swift:96 | Medium | `visibleSpineIndex` parse too permissive — `Int(d)` truncated `3.9`→3 and a bool-backed `NSNumber` (`true`) became `1`. | **Fixed.** `intValue` rejects bools, bool-backed `NSNumber` (`CFGetTypeID == CFBooleanGetTypeID`), and non-integral/non-finite Doubles (`d == d.rounded()`); `doubleValue` similarly rejects bools/non-finite. Added tests: `rejectsFractionalIndex`, `rejectsBoolIndex`, `rejectsBoolFraction`. |
| EPUBWebViewBridge.swift:162 | Low | (round-1) Claimed `dismantleUIView` teardown asymmetry. | Initially mis-rebutted (I grepped the wrong files); resolved in round 2 — see below. |

Round 1 confirmed clean: nil-config legacy path byte-identical; `progressTrackingJS`
correctly replaced (not doubled) in continuous mode; `onProgressChange` before
the `await handleBoundarySignal` is fine (progress derives from the current
observer signal, not the post-mutation window); the `sectionHref` JS addition is
injection-safe; the ungated Foundation-only helper file is fine.

## Round 2 — Low (teardown, corrected)

Codex corrected my round-1 rebuttal: `dismantleUIView` DOES exist (in
`EPUBWebViewBridgeJS.swift`) and removed only the legacy handlers, so the new
`continuousScrollHandler` teardown was genuinely missing.

**Fixed.** `dismantleUIView` now also `removeScriptMessageHandler(forName:
"continuousScrollHandler")` (unconditional, like the other handlers — a safe
no-op in legacy mode where it was never registered). The bilingual enumerate
handler teardown gap Codex also noted is **pre-existing** (Feature #56 WI-10,
not WI-5) and left out to keep the WI-5 diff focused — noted for a separate
cleanup.

Round 2 confirmed both substantive fixes correct: the JS clamp produces a range
ending inside one section (no leak into the next chapter) with the right
degenerate reject; the parser hardening matches the bridge contract.

## Round 3 — clean

**Ship-as-is.** Teardown fix correct + symmetric; no remaining WI-5-specific
blocker. Cross-section clamp aligned with the plan, parser hole closed, legacy
path unchanged, handler set intact in both modes.

## Summary

3 rounds, 1 High + 1 Medium + 1 Low fixed, final verdict **ship-as-is**.

## Gate-5a note (per-WI slice)

WI-5 is behavioral but its runtime path is not reachable until WI-6 constructs
the `EPUBContinuousScrollConfig` (coordinator + chapterBodyProvider + bootstrap).
Pre-merge slice verification for WI-5 is therefore: (a) the pure logic
(`EPUBScrollBoundarySignal.parse`, `windowedProgress`, section-href parsing)
is unit-tested (`EPUBContinuousScrollBridgeTests`, 18 cases); (b) the full suite
stays green (7254 tests, 0 failures), confirming the nil-config legacy path is
behaviorally unchanged. End-to-end continuous-scroll behavior (the live observer
→ window-transition → windowed-progress loop, and the cross-section selection
clamp DOM behavior) is verified at WI-6 + the final-WI Gate-5b device pass.
