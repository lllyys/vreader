---
branch: feat/feature-42-wi9a-readium-nav
threadId: codex-exec-readonly
rounds: 3
final_verdict: ship-as-is
date: 2026-05-29
---

# Gate-4 Implementation Audit — Feature #42 WI-9a (Readium navigation)

Independent Codex audit (`codex exec --sandbox read-only`) of WI-9a: wire the
Readium EPUB host into vreader's reader navigation bus — page-turn
(`.readerNextPage`/`.readerPreviousPage` → `goForward`/`goBackward`) + search/
TOC/bookmark jumps (`.readerNavigateToLocator` → `go(to:)`). Fixes the
page-navigation gap found in WI-6 device verification. Author = worktree
implementer + orchestrator fixes; auditor = separate `codex exec` process
(rule-48 author/auditor separation).

Changed files: `ReadiumEPUBHost+Navigation.swift` (new — `ReadiumNavCommander` +
coordinator nav methods), `ReadiumEPUBReaderViewModel+Navigation.swift` (new —
pure `readiumLocator(fromVReader:spineHrefs:)`), `ReadiumEPUBHost.swift` (nav
observers + commander wiring), + the round-2 file split.

## Round 1 — 0 Critical / 0 High / 2 Medium

| File | Severity | Issue | Resolution |
|---|---|---|---|
| ReadiumEPUBHost+Navigation.swift | **Medium** | Nav `Task` captured the concrete `navigator` before the async hop; a `detach()`/dismantle racing between the intent firing and the task executing could drive a torn-down navigator (`clear()` only protected intents posted *after* detach). | FIXED — the 3 coordinator nav methods now `Task { [weak self] in guard let navigator = self?.boundNavigator else { return }; await navigator.go*() }`, re-reading the weak `boundNavigator` INSIDE the Task. Both detach (nils the ref) and the guard run on the `@MainActor`, so they serialize — a post-detach task no-ops. |
| ReadiumEPUBHost.swift | **Medium** | 495 lines (> ~300 convention), accreting host View + representable + coordinator + delegate + DEBUG eval + lifecycle; would keep growing through WI-10+. | FIXED — split into 3 files: `ReadiumEPUBHost.swift` (host View, 227), `ReadiumReaderCoordinator.swift` (class + `EPUBNavigatorDelegate` + DEBUG `ReadiumNavigatorEvaluating` extensions, 176), `ReadiumNavigatorRepresentable.swift` (representable, dropped `private` → internal, 123). All under the convention, same module. |

Round-1 also confirmed (no bug): commander instance identity correct (host `@State` → representable → coordinator, same object — no WI-8-class divergent-default footgun); `spineHrefs` threaded via `publication.readingOrder.map(\.href)` (not `[]`, so legacy-href jumps resolve — the WI-8 lesson applied); rapid next-next safe (Readium's state machine rejects overlapping moves); Readium `goForward`/`goBackward`/`go(to:,options:)` + `NavigatorGoOptions(animated:)` are the correct surface; no new UI.

## Round 2 — clean

**No new Critical/High/Medium.** Both round-1 Mediums resolved: the split is sound
(no duplicate/missing decls, balanced `#if`/`#endif` per file, imports sufficient,
new files in the Xcode source phase, DEBUG extension moved intact, `internal`
representable sound); the Task fix is race-safe (`[weak self]`, MainActor-serialized
re-read of `boundNavigator`, no retain cycle).

## Verdict

**ship-as-is.** Two audit rounds, zero open Critical/High/Medium. Test gate green:
104 tests / 7 suites (the pure `readiumLocator(fromVReader:spineHrefs:)` mapping —
href resolution exact/legacy/empty + progression + CJK text-quote + nil href; the
`ReadiumNavCommander` bind/fire/clear/rebind lifecycle; + all WI-5/6/7/8 suites
unchanged).

## Gate-5 device finding → round-3 audit (page-turn trigger was missing)

Device verification (mini-epub3, Readium ON) found page-turn-by-tap was DEAD:
WI-9a wired the host to OBSERVE `.readerNextPage`/`.readerPreviousPage` →
`goForward`/`goBackward`, but nothing POSTED them for the Readium host. Readium
reports taps via `VisualNavigatorDelegate.navigator(_:didTapAt:)` and does NOT
auto-navigate (the host decides — confirmed against the Readium sample's
`DirectionalNavigationAdapter`); the legacy tap-zone trigger lives in the
WKWebView bridge, which the Readium navigator doesn't have. So the observers had
no trigger.

**Fix (HEAD):** `ReadiumReaderCoordinator` implements `navigator(_:didTapAt:)` →
`ReaderTapZoneRouter.dispatch(x: point.x, totalWidth: navigator.view.bounds.width,
layout: currentLayout)` — the same dispatcher the legacy bridges use. Paged-mode
left/right zones post `.readerPreviousPage`/`.readerNextPage` (→ WI-9a observers
→ `goBackward`/`goForward`); center + all scroll-mode taps post
`.readerContentTapped` (chrome toggle, observed by the shared
`ReaderContainerView:284`). `currentLayout` is set by the representable from
`preferences.scroll` in make + update.

**Round-3 audit of the fix:** No new Critical/High/Medium. Confirmed: `didTapAt`
point is navigator-view-relative (zone fraction correct); no double-turn (Readium
doesn't auto-navigate); mixed delegate isolation valid (`didTapAt` @MainActor,
`presentError` nonisolated); center/scroll chrome-toggle wired via the shared
container observer; stale-layout-during-flip is at most a transient tap race
(not Medium+).

**Device-verified:** right-tap Chapter One → Chapter Two (`goForward`), left-tap
→ Chapter One (`goBackward`), bidirectional. This is the navigation that was dead
since WI-6's device finding — now working. Artifact
`dev-docs/verification/artifacts/feature-42-wi9a-readium-pageturn-chapter2-20260529.png`.

## Scope notes carried forward

- The async nav DISPATCH against the live `EPUBNavigatorViewController` (concrete,
  no cheap protocol seam) is device-verified, not unit-tested.
- Transient search-highlight (a separate `"search"` decoration group) is scoped
  OUT of WI-9a (the mapping carries the text-quote into `Locator.Text` so Readium
  re-anchors the jump; a distinct emphasis decoration is a later refinement).
- WI-9b (footnotes #138) is a separate slice.
