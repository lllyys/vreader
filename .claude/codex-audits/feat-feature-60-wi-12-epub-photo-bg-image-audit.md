---
branch: feat/feature-60-wi-12-epub-photo-bg-image
threadId: 019e312a-3749-72c2-a1fb-62a173f7aeb9
rounds: 2
final_verdict: ship-as-is
date: 2026-05-16
---

## Gate 4 — Codex implementation audit, feature #60 WI-12

WI-12 is the final work item of feature #60 (visual identity v2). It
closes acceptance criterion (c) — "all 5 themes render correctly
including Photo" — for the EPUB reader, resolving GH #795: the Photo
theme's user-picked background image now renders inside the EPUB
WKWebView via a base64 `data:` URL (no `file://` URL, so no dependency
on the bridge's `allowingReadAccessTo` scope).

Codex MCP, read-only sandbox. Thread `019e312a-3749-72c2-a1fb-62a173f7aeb9`.

## Round 1

Findings:

- **Medium** — `EPUBReaderContainerView` recomputed
  `photoBackgroundDataURL` only on `.onAppear` / theme change /
  `useCustomBackground` change. Picking a NEW image while already on
  the Photo theme with custom-background on overwrites the JPEG on disk
  but flips none of those watched values — so EPUB kept injecting the
  stale `data:` URL until reopen. `ThemeBackgroundView` (TXT/MD) shared
  the same staleness on first-pick and re-pick.

Confirmed correct in round 1: the `data:`-URL approach fixes the
original `file://`-scope problem; the `.onChange` caching keeps file
I/O off the body hot path; missing/empty files collapse to `nil`;
corrupt-but-nonempty files degrade to the fallback `background-color`;
concurrent save/remove is safe (atomic writes, `try?` read). No
CSS/`<style>` injection hole — base64 payloads carry no `"`/`\`,
`cssEscapeURL` covers those anyway, and the bridge injects via
`createElement('style')` + `textContent`. No duplicate/dead code, no
Swift 6 / actor-isolation issues.

## Round 1 → fix applied

- **Medium (fixed)** — added `ReaderSettingsStore.customBackgroundRevision`,
  a session-scoped (non-persisted) invalidation counter bumped by
  `ReaderSettingsPanel` after a successful `saveBackground`. Both
  cached readers observe it: `EPUBReaderContainerView` (`.onChange` →
  `refreshPhotoBackgroundImage()`) and `ThemeBackgroundView`
  (`.onChange` → `loadBackground()`). A first-pick or re-pick now
  refreshes every reader format immediately. The remove path already
  flips `useCustomBackground`, so it stays covered by the existing
  `.onChange`.

## Round 2

Verdict: **Clean — no remaining Critical/High/Medium findings.**

Codex confirmed the fix fully resolves the stale-cache issue for both
EPUB and TXT/MD on first-pick and re-pick; `@Observable` tracking is
correct (`.onChange(of:)` fires for `customBackgroundRevision`);
`@MainActor` correctness holds (picker save + view consumption are
both main-actor); the non-persisted counter is the right choice;
integer overflow is not realistic.

- **Low (addressed)** — round 2 noted there is no test covering the
  revision-driven invalidation path. The SwiftUI `.onChange` wiring is
  view plumbing best verified end-to-end (Gate 5a, below). The
  store-level guarantee it depends on — `backgroundImageDataURL`
  always reading the current file, never caching internally — is now
  pinned by `ThemeBackgroundTests.backgroundImageDataURL_reflectsLatestFileAfterOverwrite`.

## Resolution summary

Round 1 Medium fixed; round 2 clean. The round-2 Low is addressed
(store-level regression test + Gate 5a device verification of the
`.onChange` wiring). Zero open Critical/High/Medium findings.

## Gate 5a verification

Slice-verified on iPhone 17 Pro Simulator (iOS 26.4), build v3.27.0
(413): seeded the `mini-epub3` EPUB fixture, placed a 1024×1024 JPEG
at `ThemeBackgrounds/photo.jpg`, opened the EPUB, selected the Photo
theme, and enabled "Custom Background". The photo renders behind the
EPUB text — legible through the Photo theme's translucent paper
overlay. Artifact: `dev-docs/verification/artifacts/feature-60-wi12-epub-photo-bg-20260516.png`.

**Verdict: ship-as-is.**
