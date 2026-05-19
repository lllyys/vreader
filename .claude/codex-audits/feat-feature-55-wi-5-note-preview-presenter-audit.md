---
branch: feat/feature-55-wi-5-note-preview-presenter
threadId: 019e3ee1-b4e4-77b3-af2b-714cce7d984c
rounds: 3
final_verdict: ship-as-is
date: 2026-05-19
---

# Codex Audit — feature #55 WI-5 (NotePreview presentation wiring)

## Scope

Files changed:
- `vreader/Views/Reader/NotePreviewSheetView.swift` (new) — the bottom-sheet fallback view
- `vreader/Views/Reader/UIKitNotePreviewPresenter.swift` (new) — `NotePreviewPresenting` + `UIPopoverPresentationController`-based presenter
- `vreader/Views/Reader/NotePreviewModifier.swift` (new) — `NotePreviewRequest` + the SwiftUI `ViewModifier`
- `vreader/Views/Reader/NotePreviewPresenter.swift` (modified) — added `resolvedForm(...)`
- `vreader/Views/Reader/NoteCalloutView.swift` (modified) — adopt the shared hex helper
- `vreader/Views/Reader/Color+ReaderHex.swift` (new) — shared `Color(readerHexString:)`
- `vreaderTests/Views/Reader/NotePreviewModifierTests.swift` (new) — Swift Testing tests
- `vreader.xcodeproj/project.pbxproj` — xcodegen regen

## Round 1

Codex thread `019e3ee1-b4e4-77b3-af2b-714cce7d984c`, sandbox `read-only`.

| severity | issue | resolution |
|---|---|---|
| High | Superseding `presentCallout` dismissed then immediately presented — `dismiss(animated:)` is async → modal collision. | Round-1 attempt: present from the dismiss completion. (Incomplete — see round 2.) |
| High | Handoff actions (`openInPanel`/`share`) presented a follow-up surface while the preview was mid-dismiss. | Round-1 attempt: `dismissPreview(then:)` defers the side-effect. (Sheet path incomplete — see round 2.) |
| Medium | The host-nil callout fallback did not dismiss a live callout first. | **Fixed** — `NotePreviewPresenter.resolvedForm(...)` folds host-availability into the form decision (unit-tested); `route(to:)` dismisses the callout before the sheet fallback. |
| Low | `PopoverDelegate` should hop to `MainActor` explicitly (per #53 precedent). | **Fixed** — `presentationControllerDidDismiss` copies the `@MainActor` closure to a local + `MainActor.assumeIsolated`. |
| Low | `Color(hexString:)` was now a 3rd reader call site. | **Fixed** — lifted to `Color+ReaderHex.swift` (`Color(readerHexString:)`); `NoteCalloutView` + `NotePreviewSheetView` adopt it. |

## Round 2

The round-1 transition-sequencing fixes were incomplete — 2 High remained:

| severity | issue | resolution |
|---|---|---|
| High | Superseding-tap reentrancy: `presentedHost` was cleared early, so a 3rd tap mid-dismiss saw `nil`, presented immediately, while the 1st callout's completion still presented the 2nd. | **Fixed** — `UIKitNotePreviewPresenter` rewritten as a pipeline state machine: `phase ∈ {idle, presenting, dismissing}`, a single `pendingRequest` slot (replaced, not appended — only the latest survives), a `pendingDismissCompletions` queue. One present/dismiss at a time; `drainPipeline` presents only the newest pending request from the dismiss completion. |
| High | The sheet-form handoff used `DispatchQueue.main.async` — a one-runloop guess, not the real SwiftUI sheet-dismiss completion. | **Fixed** — a `pendingPostDismissAction` closure stashed by a sheet-form handoff; clearing `sheetContent` triggers `.sheet`'s `onDismiss` → runs the stashed action. The follow-up surface is presented only after the sheet fully dismisses. |

`resolvedForm`, the host-nil fallback, and the `MainActor.assumeIsolated` hop confirmed correct in round 2.

## Round 3

Final round — verification of the round-2 state-machine + sheet-hook fixes.

| severity | issue |
|---|---|
| — | No findings — Critical / High / Medium all clear |

Auditor walked a 3-tap sequence and confirmed: tap A presents (`.idle`→`.presenting`), tap B stashes + `beginDismiss` (`.presenting`→`.dismissing`), tap C replaces the pending slot; on the dismiss completion only **C** presents — B never reappears, two callouts never stack, no older-tap-overwrites-newer path. The `nearestViewController`-guard failure path resets to `.idle` cleanly; the `PopoverDelegate` interactive-dismiss path does not fight `beginDismiss`. The sheet handoff now uses `.sheet`'s real `onDismiss` completion; `runPendingPostDismissAction`'s no-action branch correctly clears VM state on a plain dismissal.

Verdict: "clean. No remaining Critical / High / Medium findings."

## Verdict

**ship-as-is** — 3 rounds (the maximum). Round 1: 2 High + 1 Medium + 2 Low; the
Medium + both Low fixed, the 2 High partially fixed. Round 2: the 2 High found
still incomplete, fixed properly (pipeline state machine + real `.sheet`
`onDismiss` hook). Round 3: zero findings — clean. All transition-sequencing
hazards resolved within the 3-round budget.
