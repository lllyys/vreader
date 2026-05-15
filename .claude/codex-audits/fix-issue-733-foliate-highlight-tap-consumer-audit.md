---
branch: fix/issue-733-foliate-highlight-tap-consumer
threadId: 019e2d21-766a-7683-86d4-9df3bd841106
rounds: 2
final_verdict: ship-as-is
date: 2026-05-16
---

# Codex Audit — Bug #199 / GH #733 (Foliate tap-on-highlight consumer)

## Summary

Bug #199: WI-5 (Feature #53) wired the `annotation-show` → `.readerHighlightTapped` post on the live AZW3 `FoliateSpikeView` path, but no production consumer subscribed, so the user saw no inline edit/delete menu when tapping a Foliate-rendered highlight.

This branch threads `UIKitHighlightActionPresenter` from `ReaderContainerView` into `FoliateSpikeView`, presents the inline menu on tap-on-highlight, and on Delete: persists the row removal, posts `.readerHighlightRemoved` for the annotations panel, and posts a new `.foliateRequestAnnotationJSDelete` notification that the `FoliateSpikeView.Coordinator` (the only place with WKWebView access) picks up and translates into `readerAPI.deleteAnnotation({value: '<cfi>'})` so the rendered annotation disappears from the Foliate-js overlay without waiting for the next book reopen.

## Round 1 Findings

| File:Line | Severity | Issue | Resolution |
|-----------|----------|-------|------------|
| `FoliateSpikeView.swift:133` (delete handler) | Medium | `try? await persistence.removeHighlight(highlightId:)` swallowed failures while still posting `.readerHighlightRemoved` + `.foliateRequestAnnotationJSDelete`. A failed DB delete would still clear panel UI and strip the WebView overlay → persisted and rendered state drift until reopen. | Fixed. Replaced with `do/try/catch` inside a new static `performDelete(...)`. On `removeHighlight` failure: log via OSLog and `return` early; the two follow-up notifications fire only on success. Code lives in the new `FoliateSpikeView+HighlightTap.swift`. |
| `FoliateAnnotationDeleteJS.swift:20` (duplicate JS builder) | Low | Introduced a second Foliate delete-JS builder when `FoliateHighlightRenderer.removeAnnotationJS(cfi:)` already exists alongside `addAnnotationJS` / `restoreAllJS`, all of which route through `FoliateJSEscaper`. Two places to keep escape behavior aligned. | Fixed. Deleted `FoliateAnnotationDeleteJS.swift` and its tests entirely; the Coordinator observer now uses `FoliateHighlightRenderer.removeAnnotationJS(cfi:)`. Empty-CFI guard moved to the call site (`!cfi.isEmpty` in the observer's guard chain). Pre-existing `FoliateHighlightRendererRemoveTests` already cover happy path + single-quote + backslash escapes. |
| `FoliateSpikeView.swift:1` (file size 541 LOC) | Low | Branch pushed `FoliateSpikeView.swift` further past the ~300-line guideline. File owns view body, bookmark handling, highlight-tap resolution, delete-menu flow, notification bridging, WebView construction, and coordinator logic in one unit. | Fixed. Extracted the tap-handler flow into a new file `FoliateSpikeView+HighlightTap.swift` (147 LOC) exposing `FoliateHighlightTapHandlerModifier` + a `.foliateHighlightTapHandler(fingerprintKey:presenter:)` View extension. Host file now 454 LOC — still above guideline because of pre-existing chrome, but the new code is no longer compounding it. |

## Round 2 Findings

`no findings`. Codex confirmed:

- Delete ordering correct: `removeHighlight` first, failure logs and returns early, follow-up notifications fire only on success (`FoliateSpikeView+HighlightTap.swift:109`).
- Coordinator's `.foliateRequestAnnotationJSDelete` observer now uses canonical `FoliateHighlightRenderer.removeAnnotationJS(cfi:)`, which routes through `FoliateJSEscaper.escapeForJSString` for `'`, `\`, `\n`, U+2028, U+2029.
- Live AZW3 path is still `ReaderContainerView -> FoliateSpikeView`. Modifier attached at the host. Inner delete closure does not capture `self` cyclically (`performDelete` is a static helper).

## Verdict

`ship-as-is`. All Round 1 findings fixed; Round 2 returned clean. Ready for merge once test gate, FIXED flip, version bump, and PR creation complete.
