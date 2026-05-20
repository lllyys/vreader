---
branch: fix/986-debugbridge-highlight-driver
threadId: 019e4456-35d7-7191-82a4-59ac0f9d7e63
rounds: 3
final_verdict: ship-as-is
date: 2026-05-20
---

# Codex Gate-4 audit — Bug #237 / GH #986 (DebugBridge highlight-driver)

**Branch**: `fix/986-debugbridge-highlight-driver`
**Final commit**: `067d259`
**Thread id**: `019e4456-35d7-7191-82a4-59ac0f9d7e63`
**Final verdict**: `ship-as-is` (after 3 rounds)

## Summary

Adds a DEBUG-only DebugBridge URL command (`vreader-debug://highlight?start=<int>&end=<int>[&color=<name>]`) to create a TXT/MD highlight without going through the long-press → SelectionPopoverView gesture path that XCUITest cannot synthesize on iOS 26. Mirrors the PR #1046 search-driver structure.

## Round 1

Codex flagged 2 High + 1 Medium against the initial implementation that
attached the observer to the format-agnostic `ReaderContainerView`:

- **High #1 — Locator construction**: The orchestration built a bare
  `Locator.validated(...)` and passed `selectedText: ""`, bypassing
  `LocatorFactory`. Because `canonicalHash` includes
  `textQuote` / `textContextBefore` / `textContextAfter`, a bridge-
  created highlight at (start, end) had a DIFFERENT canonicalHash than
  a gesture-created highlight at the same offsets — dedupe path in
  `PersistenceActor.addHighlight` diverged. Highlight-list / export
  cards rendered empty selectedText too.
- **High #2 — Format scoping**: The observer was at `ReaderContainerView`
  level, so an EPUB / PDF / AZW3 reader receiving a stray
  `vreader-debug://highlight` URL would persist a TXT-shaped highlight
  against its own book — invisible at render time (EPUB needs an
  anchor, PDF needs a page) and contaminating the library / export.
- **Medium #3 — Cancellation race**: `Task.isCancelled` check between
  persistence and `.readerHighlightsDidImport` post meant a cancelled
  second URL could leave the first highlight persisted-but-unpainted
  in the current session.

Fixes (commit `bcc5e23`):

1. **Per-format observer placement**. Modifier
   `DebugBridgeHighlightObserver` is now attached only inside
   `TXTReaderContainerView` and `MDReaderContainerView` via
   `debugBridgeHighlightObserverModifier` computed properties on each
   host. Release builds get an `EmptyModifier` stub so the body
   compiles without any DebugBridge symbols.
2. **LocatorFactory delegation**. TXT continuous mode →
   `LocatorFactory.txtRange(sourceText:)`; TXT chapter mode →
   `TXTReaderContainerView.makeLocatorForTXT` →
   `LocatorFactory.txtChapterRange` (which translates chapter-local
   offsets to document-global and extracts quote + context); MD →
   `LocatorFactory.mdRange(sourceText:)`.
3. **HighlightCoordinator.create(...) routing**. Same boundary the
   gesture path uses; persist + paint atomic — no cancellation gap.
4. **selectedText extraction**. New shared helper
   `DebugBridgeHighlightObserver.extractSelectedText(locator:
   continuousSource:chapterSource:chapterLocalStart:chapterLocalEnd:)`
   with 10 pure-helper tests (CJK, surrogate-pair emoji, out-of-bounds,
   chapter-vs-continuous preference, missing source, default color).

## Round 2

Codex confirmed rounds 1's High #1/#2 + Medium #3 are fixed, found 1
remaining Medium:

- **Medium — Renderer double-apply**: two rapid identical highlight URLs
  race through `HighlightCoordinator.create()`. Persistence dedupes to
  one row (the `profileKey + anchor` match), but the renderer's `apply`
  is still called on the returned existing record —
  `TextHighlightRenderer.apply` blindly appended the range, double-
  painting the same highlight until the next full restore. Gesture
  path protected by physical input rate-limiting; the bridge can fire
  URLs back-to-back, so the latent bug becomes observable.

Fix (commit `067d259`):

- `TextHighlightRenderer.apply` checks
  `uiState.persistedHighlightLookup.contains(where: { $0.id ==
  record.highlightId })` and bails early if true. First-write-wins on
  the dedupe path; later mutations flow through
  `restoreAll` / `changeColor` (which rebuild state from scratch).
- 2 new Swift Testing cases:
  `applyIsIdempotentOnSameHighlightId`,
  `applyIsIdempotentEvenWhenColorChanged`.

## Round 3

Final verdict: `ship-as-is`. No remaining findings against this PR.

Codex noted that the EPUB and PDF renderers have an analogous double-
apply path that could be addressed in a follow-up, but explicitly does
NOT block this PR because the DebugBridge highlight-driver is scoped to
TXT/MD only. Follow-up tracked as a known gap; can ship as a separate
hardening fix when EPUB highlight-driver is needed (not in this PR's
scope).

## Edge-case asks (round 2)

- `highlightCoordinator == nil` during reader load: acceptable; the
  existing `settle` URL handles the "wait for reader ready" gate, and
  the bailing log lets the harness diagnose the timing issue. Not a
  blocker.
- Surrogate-pair safety: acceptable. The new helper uses the same
  `String.Index(utf16Offset:in:)` strategy as
  `LocatorFactory.substringFromUTF16`.
- Rapid distinct URLs: `PersistenceActor` serializes; only the
  double-apply was an issue, fixed in round 2.

## Files touched (final state)

```
vreader/Services/DebugBridge/DebugBridge.swift
vreader/Services/DebugBridge/DebugBridgeNotifications.swift
vreader/Services/DebugBridge/DebugCommand.swift
vreader/Services/DebugBridge/RealDebugBridgeContext.swift
vreader/Views/Reader/DebugBridgeHighlightObserver.swift                NEW
vreader/Views/Reader/MDReaderContainerView+DebugBridgeHighlight.swift  NEW
vreader/Views/Reader/MDReaderContainerView.swift
vreader/Views/Reader/ReaderContainerView.swift
vreader/Views/Reader/TXTReaderContainerView+DebugBridgeHighlight.swift NEW
vreader/Views/Reader/TXTReaderContainerView.swift
vreader/Views/Reader/TextHighlightRenderer.swift
vreaderTests/Services/DebugBridge/DebugBridgeTests.swift
vreaderTests/Services/DebugBridge/DebugCommandTests.swift
vreaderTests/Services/DebugBridge/RealDebugBridgeContextTests.swift
vreaderTests/Views/Reader/DebugBridgeHighlightObserverTests.swift      NEW
vreaderTests/Views/Reader/HighlightRendererTests.swift
```
