---
branch: fix/issue-494-epub-overscroll-bounce-white
threadId: 019e1210-ba8e-7de3-8fe4-3688dafa3a8c
rounds: 3
final_verdict: ship-as-is
date: 2026-05-10
---

# Codex Audit — Bug #167 / GH #494

EPUB overscroll bounce reveals white background instead of theme color.

## Round 1 — initial findings

| File:Line | Severity | Issue | Resolution |
|---|---|---|---|
| `vreaderTests/Views/Reader/EPUBWebViewBridgeTests.swift:71` | Medium | New tests prove the pure helper returns its input but do not exercise the actual bridge wiring in `makeUIView` or `updateUIView`. Deleting either call site re-introduces the white-bleed regression with the suite still passing. | **Fixed via seam extraction.** Added `static func applyScrollViewBackground(to scrollView:color:)` in `EPUBWebViewBridgeJS.swift`, replaced both call sites in `EPUBWebViewBridge.swift` (makeUIView + updateUIView post-cascade branch) to use it. Added 2 new `@MainActor` tests that exercise the actual `UIScrollView.backgroundColor` assignment (pre-set `.red`, call seam, assert overwrite) — covers nil → `.clear` and themed-color → themed-color including subsequent overwrite for live theme switch. |

Round-1 also confirmed: correctness OK (first paint covered in `makeUIView`; live theme switch covered by separate post-cascade branch); ordering rationale correct (new branch is a separate `if` outside the URL/theme `if/else if` chain so it runs every `updateUIView` pass); AZW3/MOBI does NOT need the same fix (Foliate bridges set `scrollView.isScrollEnabled = false` so no rubber-band overscroll); no Swift 6 sendability issue from adding `UIColor?`.

## Round 2 — verification of round-1 fix + remaining finding

| File:Line | Severity | Issue | Resolution |
|---|---|---|---|
| `vreaderTests/Views/Reader/EPUBWebViewBridgeTests.swift:118` | Medium | Even with the seam, the new tests don't verify `makeUIView` / `updateUIView` actually CALL the seam. If a future change deletes either call site the suite still passes. Codex offered two alternatives: (a) construct the representable on `@MainActor` and assert, OR (b) explicitly weaken the comments to state the gap. | **Accepted alternative (b)** — `UIViewRepresentableContext` plumbing is too deep to mock in a bridge unit-test file (would need a `UIHostingController` harness, out of scope). Updated the test-suite comment to explicitly call out the coverage gap and name the post-merge device-verification step (Phase 9 of `/fix-issue` per `.claude/rules/47-feature-workflow.md`) as the wiring lock. **Belt-and-suspenders**: added "Bug #167 wiring: keep this call" marker comments at BOTH bridge call sites so future edits land in obvious diff hunks and `grep -rn "Bug #167 wiring"` finds them. |

## Round 3 — verification of round-2 fix

`No findings. Ship as-is.` — Codex confirmed: code path correct for first paint and live theme switches; updated comments accurately describe the real test boundary; call-site marker comments are useful rather than misleading; residual risk (bridge wiring protected by review + device verification rather than unit tests) is now explicit.

## Verdict

`ship-as-is`. All Critical/High/Medium findings fixed across 3 rounds. The remaining residual gap (call-site wiring is not unit-testable without representable-context mocking) is explicitly documented in code comments AND the test suite, and is covered by the binding device-verification gate.

## Manual audit evidence

Not applicable — Codex MCP audit ran cleanly across 3 rounds.

## Artifacts

- Test results: 8/8 `EPUBWebViewBridgeScrollBackgroundTests` + 7/7 `EPUBWebViewBridgeScrollJSTests` pass.
- Files changed (this fix):
  - `vreader/Views/Reader/EPUBWebViewBridge.swift` (+~14 LoC: `themeBackgroundColor` property, both call sites + marker comments, post-cascade live-update branch)
  - `vreader/Views/Reader/EPUBWebViewBridgeCoordinator.swift` (+~5 LoC: `themeBackgroundColor` field on Coordinator)
  - `vreader/Views/Reader/EPUBWebViewBridgeJS.swift` (+~22 LoC: `scrollViewBackgroundColor(for:)` resolver + `applyScrollViewBackground(to:color:)` seam, `UIKit` import)
  - `vreader/Views/Reader/EPUBReaderContainerView.swift` (+1 LoC: pass `settingsStore?.theme.backgroundColor` to bridge)
  - `vreaderTests/Views/Reader/EPUBWebViewBridgeTests.swift` (+~80 LoC: 8 new `@Test` cases — 6 helper, 2 `@MainActor` seam)
  - `docs/bugs.md` (Bug #167 row → IN PROGRESS, will move to FIXED)
