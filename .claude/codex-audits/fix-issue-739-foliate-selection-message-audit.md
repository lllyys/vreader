---
branch: fix/issue-739-foliate-selection-message
threadId: 019e2e64-118b-79a2-b2dc-d17037cbf97b
rounds: 2
final_verdict: ship-as-is
date: 2026-05-16
---

# Codex Audit — Bug #201 / GH #739

Bug: `FoliateSpikeView.Coordinator.handleMessage` registers
`"selection"` in its WKScriptMessageHandler names but the switch has
no `case "selection":` branch — falls through to `default: break`,
so long-pressing text in AZW3/MOBI brings up iOS's default WKWebView
menu (Copy/Look Up/Translate/Search Web/Share) with no Highlight
option.

Fix: add the missing case, parse via the existing
`FoliateMessageParser.parseSelection`, route via a new pure-logic
`FoliateSelectionDispatcher` that builds the notification
`userInfo`, post `.foliateSelectionDetected`, and observe in a new
`FoliateSpikeView+Selection.swift` modifier that presents a
`confirmationDialog` ("Highlight" / "Cancel"). On Highlight: persist
via `PersistenceActor.addHighlight` with an `AnnotationAnchor.epub(
href:"", cfi:cfi, serializedRange:placeholder)` (mirrors the
existing `FoliateHighlightTapResolver`'s read-only-cfi contract),
then post a sibling `.foliateRequestAnnotationJSCreate` so the
Coordinator (which holds the live `webView`) evaluates
`FoliateHighlightRenderer.addAnnotationJS` and the overlay paints
immediately.

## Round 1 findings

| File:Line | Severity | Issue | Fix |
|---|---|---|---|
| `vreader/Services/Foliate/FoliateMessageParser.swift:61-64` | Medium | `parseSelection` required a well-formed `rect`. A bad/missing rect would drop the entire selection — silently re-breaking highlight creation when foliate-host.js shifts its rect shape, even with valid cfi/text/index. | Made rect best-effort: missing/malformed rect now yields `event.rect = .zero` instead of nil. Doc-comment updated. Existing test `rect with missing width returns nil` flipped to assert `event != nil && rect == .zero`; new regression test `malformed rect returns event with .zero rect` added. |
| `vreader/Services/Foliate/FoliateMessageParser.swift:59-70` | Medium | Empty `cfi` accepted by parser, but downstream JS-create observer requires `!cfi.isEmpty` and tap resolver matches only non-empty cfis. Empty-cfi highlights would persist but never paint or round-trip on tap. | Added `guard !cfi.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }` immediately after cfi extraction. Two new tests: `empty cfi returns nil` + `whitespace-only cfi returns nil`. |

## Round 2 findings

No findings. Codex Round 2 verdict (verbatim):

> Both round-1 issues are cleanly resolved... I don't see a new
> issue from the best-effort rect path... The whitespace trim is the
> right choice, not overreach. It closes the real downstream gap...
> Ready to ship Bug #201 from the parser side. Residual debt remains
> the same as before: Foliate selection anchoring still uses
> placeholder EPUB anchor fields, but that is pre-existing/accepted
> and does not block this fix.

## Pre-existing technical debt accepted

- `AnnotationAnchor.epub(href: "", cfi: cfi, serializedRange:
  placeholder)` mirrors the existing `FoliateHighlightTapResolver`
  pattern, which keys only on CFI. A Foliate-specific anchor case
  would be a cleaner abstraction but is out of scope for this fix —
  it's pre-existing debt across the Foliate persistence stack.
- `FoliateReaderContainerView+Highlights.swift` has a dead-code
  `handleSelection(_:)` with the same intent for the non-live
  dispatch path. Not deleted here per Codex round 1 ("should be
  deleted in a follow-up cleanup, not as part of this fix unless
  you want to widen scope").

## Summary

Ship-as-is. Adds the missing `case "selection":` to the live
AZW3/MOBI long-press path. Persists via the existing
`PersistenceActor.addHighlight` boundary; paints via the existing
`FoliateHighlightRenderer.addAnnotationJS` (same JS escape contract
as the tap-delete and restore paths). Cross-format selection
contract preserved: TXT/MD/EPUB/PDF flows untouched.
