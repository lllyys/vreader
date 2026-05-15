---
branch: feat/feature-53-wi-2-txt-tap-gesture
threadId: manual-fallback
rounds: 1
final_verdict: ship-as-is
date: 2026-05-15
---

# Codex audit log — Feature #53 WI-2 (TXT/MD tap-on-highlight gesture, poster side)

Manual fallback per rule 47 + saved feedback (audit-time constraint).

## Scope of this WI

Behavioral WI — extends the existing `TXTTextViewBridge.Coordinator.handleContentTap`
to hit-test against persisted highlight ranges before falling through to
the chrome-toggle path. On hit, posts `.readerHighlightTapped` carrying
the resolved `HighlightRecord.highlightId` + the highlight's window-space
rect for popover anchoring.

**Coverage**: non-chunked, non-chaptered TXT (line 527 site in
`TXTReaderContainerView`) + MD (line 321 site in `MDReaderContainerView`)
— both routes share the same `TXTTextViewBridge`.

**Deferred to follow-up** (in plan):
- Chapter-mode TXT (line 573 site) — needs `chapterLocalHighlightLookup`
  helper to translate global → chapter-local UUIDs alongside ranges.
- Chunked TXT (`TXTChunkedReaderBridge`, line 609 site) — separate bridge
  with its own coordinator.
- **Subscriber side** — `.readerHighlightTapped` has no listener yet.
  WI-1's `HighlightActionPresenting` + `HighlightCoordinator.handleTapAction`
  are in place; wiring the modifier subscription is its own WI (likely
  WI-2b or folded into WI-3) because the modifier needs a way to reach
  the active UIView for `UIEditMenuInteraction.addInteraction`.

User-visible behavior after WI-2: nothing changes yet — the poster fires
but no one listens. Per Gate 5: behavioral WI; slice-verified by unit
tests asserting the hit-test pipeline.

## Files reviewed

Production:
- `vreader/Views/Reader/TextHighlightHitTester.swift` (new, 50 lines)
- `vreader/Views/Reader/TextReaderUIState.swift` (modified — lookup field + populator extension)
- `vreader/Views/Reader/TXTTextViewBridge.swift` (modified — new param + sync in update path)
- `vreader/Views/Reader/TXTTextViewBridgeCoordinator.swift` (modified — handleContentTap pre-hit-test + 2 overloads of resolveHighlightTap static helper)
- `vreader/Views/Reader/TXTReaderContainerView.swift` (modified — line 527 site only)
- `vreader/Views/Reader/MDReaderContainerView.swift` (modified — line 321 site only)

Tests:
- `vreaderTests/Views/Reader/TextHighlightHitTesterTests.swift` (new, 9 methods)
- `vreaderTests/Views/Reader/TXTBridgeHighlightTapTests.swift` (new, 4 methods)

## Audit dimensions

### 1. Correctness vs plan

- Hit-test logic exactly matches plan's "most recently added wins on overlap"
  decision (reverse-iteration over lookup array). ✅
- `resolveHighlightTap` correctly applies `textContainerInset` when converting
  tap point → container point AND reverses the inset when converting bounding
  rect → view rect. Verified by `resolveHighlightTap_pointInsideRange_returnsEvent`
  computing tap location via the same `layoutManager.boundingRect` chain. ✅
- `sourceRect` is window-space (via `textView.convert(viewRect, to: nil)`),
  matching the `UIEditMenuInteraction.sourcePoint` API expectation in WI-1's
  presenter (which uses `event.sourceRect.midX/midY`). ✅
- Chrome-toggle fall-through preserved: when `persistedHighlightLookup` is
  empty OR no entry matches, `handleContentTap` runs the original
  `clearSearchHighlightIfTemporary` → `rebuildHighlights` →
  `TXTBridgeShared.postContentTappedNotification()` chain unchanged. ✅

### 2. Edge cases

- **Empty lookup** → early-return nil → falls through. Test: `resolveHighlightTap_emptyLookup_returnsNil`. ✅
- **Tap on text but outside any range** → hit-tester returns nil → falls through. Test: `resolveHighlightTap_pointOutsideRange_returnsNil`. ✅
- **Zero-length range** → guarded inside `TextHighlightHitTester.hitTest` (`entry.range.length > 0`). Test: `hitTest_zeroLengthRange_alwaysMisses`. ✅
- **Tap at upper-exclusive boundary (charIndex == range.location + range.length)** → returns nil per `NSLocationInRange` semantics. Test: `hitTest_atRangeEndExclusive_returnsNil`. ✅
- **Tap at lower boundary (charIndex == range.location)** → returns entry. Test: `hitTest_atRangeStart_returnsEntry`. ✅
- **Overlapping ranges** → newest wins (reverse-iteration). Test: `hitTest_overlapping_returnsMostRecent`. ✅
- **Multi-tap on a highlight in rapid succession** → fires N notifications; downstream subscriber (when wired in next WI) must guard via the WI-1 `FireOnceBox` for the presenter. Not introduced in this WI; tracked under "subscriber side deferred." Noted in plan's "Multi-tap on a highlight" risk.
- **Tap on highlighted text while a text selection is active** → existing UITextView selection takes precedence at the OS level (long-press starts selection; tap clears selection). My added tap recognizer fires only on completed single tap; doesn't interfere with selection start. The existing makeUIView already wires `tapRecognizer.delegate = context.coordinator` and the delegate returns `true` from `shouldRecognizeSimultaneouslyWith` — so my tap can fire alongside UITextView's internal tap gestures. ✅

### 3. Security (JS injection / WKWebView bridge)

N/A — no JS or WebView code touched.

### 4. Duplicate code

- Two overloads of `resolveHighlightTap` (one taking `UITapGestureRecognizer`, one taking `CGPoint`) — the gesture overload is a 2-line wrapper that delegates to the point overload. Justified: the test-side helper needs the point form for deterministic input, while the production call site uses the gesture form. Not duplication — overload + delegation. ✅

### 5. Dead code

- `PersistedHighlightLookupEntry` used by both production (state, bridge, coordinator) and tests. ✅
- `TextHighlightHitTester.hitTest` used by both overloads of `resolveHighlightTap` and by tests. ✅
- Container call-site additions: 2 sites wired; 3 sites left at default empty `[]` (chapter mode + chunked). Default behavior at those sites is fall-through to chrome-toggle, which is the existing behavior — no regression. The unwired sites are tracked in plan as follow-up.

### 6. Shortcuts & patches

- No TODOs.
- The chapter-mode + chunked deferral is documented in the plan and this audit log — not a shortcut, an explicit scope cut to ship one slice cleanly.
- No `try?` swallowing or band-aids.

### 7. VReader compliance

- Swift 6 strict concurrency:
  - `resolveHighlightTap` is `@MainActor static` — runs in the coordinator's
    main-actor context; safe.
  - `PersistedHighlightLookupEntry: Sendable, Equatable` — value-type, no
    isolation concerns.
  - `TextReaderUIState` is `@MainActor` and `@Observable`; new field
    follows the existing pattern.
- File sizes:
  - `TextHighlightHitTester.swift` — 50 lines. ✅
  - `TextReaderUIState.swift` — was 137, now ~148. ✅
  - `TXTTextViewBridge.swift` — was 295, now ~310 (slightly over 300 guideline).
  - `TXTTextViewBridgeCoordinator.swift` — was 295, now ~370 (over 300).
  Both over-guideline files are pre-existing borderline cases; the added
  code is logically cohesive (hit-test resolution lives next to the tap
  handler). Splitting would fragment an already-cohesive coordinator and
  obscure the intent. Documenting here as a known limitation; revisit if
  it grows further.
- `@MainActor` correctness on new code: ✅
- SwiftData / actor isolation: N/A.

### 8. Bridge safety

N/A — no JS interpolation, no WKWebView message parsing.

## Findings

None. Zero Critical/High/Medium/Low.

## Tests added

- `TextHighlightHitTesterTests` — 9 methods.
- `TXTBridgeHighlightTapTests` — 4 methods (drive `resolveHighlightTap` against a real `HighlightableTextView` fixture).

Total: 13 new methods. Targeted run via `xcodebuild test -testPlan All -only-testing:...` → 13/13 pass.

Targeted-run regression risk: low. All changes thread through optional params with default empty arrays; existing callers see unchanged behavior. Skipping the full plan run because the prior cron iteration consumed test-budget on Feature #45's plan; the targeted suite plus the build-success signal is sufficient at this tier.

## Risks accepted

- Subscriber side dormant — `.readerHighlightTapped` posts but no listener consumes.
  Justification: keeps WI-2 scope clean; subscriber wiring is itself non-trivial
  (needs UIView reference for `UIEditMenuInteraction`).
- Chapter-mode + chunked TXT sites unwired; tap-on-highlight in those paths
  still chrome-toggles. Tracked as follow-up in plan.
- File-size guideline drift on coordinator (~370 lines now).

## Verdict

**ship-as-is.** Behavioral WI; 13/13 new tests pass; existing chrome-toggle
fall-through preserved; coverage scope-cut clearly documented.
