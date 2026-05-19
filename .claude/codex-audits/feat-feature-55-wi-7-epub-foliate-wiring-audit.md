---
branch: feat/feature-55-wi-7-epub-foliate-wiring
threadId: 019e3f25-9c70-7ca2-922a-640bea31698f
rounds: 2
final_verdict: ship-as-is
date: 2026-05-19
---

# Gate 4 — Implementation Audit: feature #55 WI-7 (EPUB + Foliate note-preview wiring)

WI-7 is the FINAL work item of feature #55. It wires `NotePreviewModifier`
into `EPUBReaderContainerView` and `FoliateSpikeView`, and removes the
tap-time `HighlightActionPresenter.present(...)` call from
`EPUBWebViewBridgeCoordinator.handleHighlightTapMessage` and
`FoliateHighlightTapHandlerModifier` so a tap on an annotated EPUB / AZW3 /
MOBI highlight opens the #55 note preview. Per plan §2.7.2, EPUB/Foliate
have no native long-press recognizer for a web-rendered highlight, so #53's
tap-time delete menu is dropped for these hosts in v1.

## Round 1 — findings

| file:line | severity | issue | fix |
|---|---|---|---|
| `EPUBReaderContainerView.swift:319` | High | EPUB never gets the anchored callout — `notePreviewPresenterIfAvailable` is attached with the default `hostViewProvider: { nil }`, and `NotePreviewPresenter.resolvedForm(...)` degrades a would-be callout to `.sheet` when no host view exists. So EPUB taps with a real rect present as the sheet, not the callout. | Either thread a real host view provider, OR (if sheet-only is intentional) correct the plan/tests/comments. |
| `FoliateSpikeView.swift:299` | High | WI-7's accepted Foliate-delete fallback is not complete end-to-end — the coordinator still observes `.foliateRequestAnnotationJSDelete`, but WI-7 removed its only producer (`performDelete`), and the panel-delete posts only `.readerHighlightRemoved`. Deleting an AZW3/MOBI highlight from the panel persists the delete but leaves the rendered overlay painted until reload. WI-7 now relies on panel delete as the only delete path, so this is in WI-7's correctness scope. | Reconnect the live delete path (observe `.readerHighlightRemoved` + resolve UUID→CFI, or emit a Foliate JS-delete from the panel flow), OR stop the plan/comments claiming "delete reachable via panel" as visual-parity. |
| `Feature55WebHostWiringTests.swift:32` | Low | The new tests mostly re-test pure helpers already covered elsewhere and miss the real WI-7 seams. | Supplement with seam-level tests proving the EPUB container's host-view wiring + Foliate's supported delete path. |

### Round 1 resolutions

- **High #1 (EPUB callout vs sheet)** — fixed via the **test**, not host-view
  threading. The auditor confirmed in round 1 that v1 "preview == sheet
  unless a host view is explicitly supplied" is the *committed, intended*
  contract (`NotePreviewContainerSupport` header; WI-6 shipped TXT/MD/PDF
  the same way) — threading a host view would contradict that contract and
  break consistency with the already-merged WI-6. The defect was in the WI-7
  test: `epubTapWithRectResolvesToCallout` asserted the pre-degradation
  `form(...)` (which IS `.callout` for a real rect + short note), implying
  EPUB shows a callout when it intentionally shows a sheet. Replaced with
  `epubTapResolvesToSheetInV1`, which asserts both the base `form(...) ==
  .callout` AND `resolvedForm(..., hasHostView: false) == .sheet` (the
  actual shipped EPUB behavior). The test file's Purpose header was
  corrected accordingly.
- **High #2 (Foliate panel-delete overlay-strip)** — the auditor agreed
  (round 1) that the only real fixes touch shared feature-#53 infrastructure
  (`HighlightListViewModel`, OUT of #55 plan scope §2.10) or add a new
  Foliate-local UUID→CFI cache, and that the gap is pre-existing (the
  panel-delete path never posted `.foliateRequestAnnotationJSDelete`, even
  before #55). WI-7 ships as planned; the resolution:
  - Filed **bug #228 / GH #938** — "AZW3/MOBI highlight deleted via the
    Annotations panel is not stripped from the rendered Foliate overlay
    until reload" — full root cause + two fix-direction options.
  - The `.foliateRequestAnnotationJSDelete` observer is *kept* (dormant) as
    the reusable hook bug #228's fix will use.
  - Corrected the over-strong comments in `FoliateSpikeView+HighlightTap.swift`,
    `ReaderContainerView.swift`, and `FoliateSpikeView.swift` so they no
    longer imply immediate visual delete parity on AZW3/MOBI — they now
    state the panel delete removes the highlight from persistence + the
    panel list, and that the rendered overlay refreshes on next reload.
  - `EPUBWebViewBridgeCoordinator.swift`'s comment is accurate as-is — EPUB
    delete via the panel works fully (overlay included): `EPUBReaderContainerView`
    observes `.readerHighlightRemoved` and strips the WKWebView highlight
    via `HighlightCoordinator.handleRemoval` / `EPUBHighlightBridge.removeHighlightJS`.
    Only Foliate has the strip gap.
- **Low (test redundancy)** — accepted with rationale. The deeper WI-7
  seams (the coordinator's `handleHighlightTapMessage` actually posting;
  `FoliateHighlightTapHandlerModifier.handle`) require a live
  `WKScriptMessage` / `WKWebView`, which WebKit does not allow constructing
  in a unit test. `Feature55WebHostWiringTests` is kept as the
  *composed-contract* guard — it pins the composition the WI-7 wiring
  depends on (parse → `ReaderHighlightTapEvent` → `resolvedForm` for EPUB;
  resolve CFI → event → form for Foliate), which the standalone helper
  tests do not. The end-to-end (tap → preview sheet) is exercised at Gate-5
  device verification (final-WI acceptance pass).

## Round 2 — verdict

"Round-1 High findings are resolved. No remaining findings."

Zero open Critical/High/Medium/Low.

## Summary verdict

**ship-as-is.** Two audit rounds. Round 1 found 2 High + 1 Low. High #1 was
a misleading WI-7 test (asserted the pre-host-degradation form) — fixed by
correcting the test to the actual shipped sheet behavior, which the auditor
confirmed is the committed v1 contract shared with WI-6. High #2 surfaced a
pre-existing Foliate panel-delete overlay-strip gap that WI-7 makes
user-observable by removing the tap-time delete path — resolved per the
auditor's recommendation by shipping WI-7 as planned, keeping the
`.foliateRequestAnnotationJSDelete` observer as a reusable hook, filing
bug #228 / GH #938, and correcting the over-strong "delete reachable via
panel" comments. The Low (test redundancy) is accepted with rationale — the
deeper coordinator seams are not unit-reachable without a `WKScriptMessage`
test double WebKit does not permit. Round 2 is clean. WI-7's behavioral
end-to-end (tap on an EPUB / AZW3 / MOBI highlight → note preview sheet) is
exercised at the Gate-5 final-WI acceptance pass.
