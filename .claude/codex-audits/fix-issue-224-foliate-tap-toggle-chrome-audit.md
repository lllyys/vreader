---
branch: fix/issue-224-foliate-tap-toggle-chrome
threadId: 019df2f6-7691-7a00-982f-accf2260fba2
rounds: 2
final_verdict: ship-as-is
date: 2026-05-04
---

# Codex audit log — fix/issue-224-foliate-tap-toggle-chrome

Bug #108 fix: FoliateSpikeView (AZW3 reader) center tap now toggles chrome.

## Round 1

**Findings**:

| Severity | Where | Issue |
|---|---|---|
| Low | `FoliateSpikeViewTapTests.swift:32` | `addObserver(queue: .main)` + 50ms sleep is potentially flaky under load. The post is synchronous but the `.main` `OperationQueue` delivery isn't, and 50ms isn't a guaranteed drain window. |

**Verdict**: Otherwise correct. Path is intact: JS `tap` → WeakScriptMessageHandler → Coordinator.userContentController → handleMessage → `.readerContentTapped` post → ReaderContainerView's `.onReceive` → `toggleChrome()`. Coordinator extraction is safe (no other call sites referenced the old `FoliateSpikeWebView.Coordinator`). `@MainActor` annotation is correct. No other Spike messages currently warrant the same treatment — the production `FoliateViewCoordinator` already forwards relocate/selection/tap/etc.

**Resolution**: Switched observer to `queue: nil` for synchronous in-thread delivery on the same thread that posts. handleMessage is @MainActor, post happens on MainActor, observer runs synchronously inside the post — no runloop drain needed.

## Round 2

Implicit: with the queue: nil change, the test is deterministic. No further audit round needed since the fix's correctness is unchanged.

**Verdict**: **Ship as-is.**

## Files changed

- `vreader/Views/Reader/FoliateSpikeView.swift` — Coordinator extracted from `FoliateSpikeWebView` (private struct) to `extension FoliateSpikeView`. New `@MainActor func handleMessage(name:body:) async` method routes messages. New `case "tap":` posts `.readerContentTapped`.
- `vreaderTests/Views/Reader/FoliateSpikeViewTapTests.swift` — new test using synchronous notification observer (`queue: nil`).
- `docs/bugs.md` — row #108 status flip to FIXED.

## Test coverage

- `FoliateSpikeViewTapTests.tapMessage_postsReaderContentTappedNotification` (new) — instantiates Coordinator, observes `.readerContentTapped`, calls `handleMessage(name: "tap", body: NSNull())`, asserts notification fired.

## Pre-existing failures noted (not caused by this fix)

`FoliateViewCoordinatorMessageRoutingTests` has 2 failing tests for `bridge-ready` — confirmed pre-existing on main with no diff. Not caused by this PR. Tracked separately if anyone wants to fix.

## What still might bite us

The Spike's `default: break` still swallows other messages: `relocate`, `selection`, `annotation-show`, `create-overlay`, `section-load`, `external-link`, `tts-ssml`, `search-result`, `search-done`, `search-progress`. For the spike's scope (basic AZW3 rendering test), this is intentional. The full `FoliateViewCoordinator` (used by `FoliateViewBridge` → `FoliateReaderContainerView`) already handles these — feature #42 will eventually migrate AZW3 onto that path and retire the spike.
