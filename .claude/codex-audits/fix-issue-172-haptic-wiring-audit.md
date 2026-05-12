---
branch: fix/issue-172-haptic-wiring
threadId: 019e1bec-4a03-7d50-ab32-0c55fb0e31a6
rounds: 2
final_verdict: ship-as-is
date: 2026-05-12
---

## Round 1 — Initial Audit

Files changed:
- `vreader/Views/Reader/TXTReaderContainerView.swift`
- `vreader/Views/Reader/EPUBReaderContainerView.swift`
- `vreader/Views/Reader/PDFReaderContainerView.swift`
- `vreader/Views/Reader/FoliateReaderContainerView.swift` (reverted — dead code)
- `vreader/Views/Reader/FoliateSpikeView.swift`
- `vreaderTests/Views/Reader/ReaderNotificationHandlerTests.swift`

### Findings

| # | Severity | Finding | Location | Resolution |
|---|----------|---------|----------|------------|
| 1 | High | AZW3 haptic wired to `FoliateReaderContainerView` which is dead code — `ReaderContainerView:488` routes AZW3 to `FoliateSpikeView` directly | `FoliateReaderContainerView.swift` | **Fixed** — reverted `FoliateReaderContainerView` to original; applied bookmark+haptic handler to `FoliateSpikeView` instead |
| 2 | Low | Inline `do { try await persistence.addBookmark(...); haptic.triggerLightImpact() } catch {}` pattern duplicated across EPUB, PDF, FoliateSpikeView | All three container files | **Accepted** — each view has its own persistence wiring pattern; extraction would introduce unnecessary abstraction for 3 call sites |

## Round 2 — Re-audit after FoliateSpikeView fix

### Prompt
Verified FoliateSpikeView.swift now adds `.onReceive(.readerBookmarkRequested)` with:
- `fingerprintKey` nil/malformed guard
- `DocumentFingerprint(canonicalKey: key)` failable parse
- Minimal nil-position Locator (AZW3 has no position tracking)
- `PersistenceActor(modelContainer: modelContext.container)` 
- `do { try await ... addBookmark; HapticFeedbackProvider().triggerLightImpact() } catch {}`

### Findings

**No findings.**

Codex confirmed:
- Previous High finding (dead-code path) is resolved
- `fingerprintKey` nil guard is safe, suppresses both persistence and haptic
- `Task {}` in `.onReceive` is main-actor safe (inherits actor context from SwiftUI view body)
- Persistence failure correctly suppresses haptic via `do/catch`
- Task lifetime is acceptable (fire-and-forget, matches EPUB/PDF pattern)

Residual note (not a finding): AZW3 bookmarks all dedupe to nil-position locator — pre-existing limitation of AZW3 having no position tracking, not introduced by this fix.

## Verdict

**ship-as-is**

Round 1 High finding (dead-code wiring) was fixed by redirecting to `FoliateSpikeView`. Round 1 Low finding (inline duplication) accepted with rationale. Round 2 confirmed no new issues.

Test gate: 12/12 `ReaderNotificationHandlerTests` pass, including two new regression tests:
- `handleBookmarkRequest_firesHaptic_onSuccess`
- `handleBookmarkRequest_suppressesHaptic_onPersistenceFailure`
