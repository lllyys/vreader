---
branch: feat/feature-42-wi10b-tts-follow
feature: 42
work_item: WI-10b
title: TTS speaking-position follow for the Readium EPUB host
auditor: codex (codex-cli 0.130.0, --sandbox read-only)
rounds: 2
final_verdict: ship-as-is
date: 2026-05-29
---

# Gate-4 Codex audit — Feature #42 WI-10b (Readium TTS-follow)

## Scope
New: `ReadiumTTSFollowMapper.swift` (pure offset→href+fraction mapper + throttle),
`ReadiumEPUBHost+TTSFollow.swift` (host wiring: off-main table build, follow
handler, observers wrap). Modified: `ReadiumEPUBHost.swift` (ttsService param, 2
@State fields, `.ready` navigator wrapped with `ttsFollowObservers`; extracted
`openHostTask`/`onHostDisappear`/`readyNavigator`), `ReaderContainerView.swift`
(threads `ttsService` into both `ReadiumEPUBHost` call sites). Tests:
`ReadiumTTSFollowMapperTests.swift` (19 tests). Docs: `architecture.md` WI-10b line.

## Round 1 — 2 Medium findings (both FIXED)

**M1 — mapper inert if TTS already speaking at host mount.**
`ttsFollowObservers` only built the mapper off `.onChange(of: ttsService?.state)`;
if TTS was already `.speaking` when the `.ready` navigator mounted (host re-mount
mid-playback), the state change was missed and `handleTTSOffsetChange` no-op'd
(`ttsFollowMapper == nil`). Follow stayed inert for that session.
Fix: added a `.task { }` to `ttsFollowObservers` that, when `ttsService?.state ==
.speaking` at mount, resets the cursor, builds the mapper, and follows the current
offset. `.task` runs once at appear, cancelled on disappear (no leak); the build is
idempotent (`buildTTSFollowMapperIfNeeded` guards `ttsFollowMapper == nil`,
re-checked after the off-main await) so it cannot double-build with the `.onChange`
path.

**M2 — per-spine `stripHTML` walk ran on `@MainActor`, blocking UI.**
`buildTTSFollowMapperIfNeeded` is a `@MainActor` host method; the `EPUBTextExtractor
.stripHTML(xhtml)` after each `await parser.contentForSpineItem` resumed on main,
so a large CJK book's full-spine strip blocked the UI shortly after TTS started.
The doc comment also wrongly claimed it stayed off-main.
Fix: added `nonisolated static func buildEntries(spineHrefs:parser:) async ->
[Entry]` to the mapper — the parser walk + strip runs off the main actor (the
`nonisolated` continuation after `await` is not pinned to main); the host now just
awaits it and assigns `@State` on main, with a re-check-after-await guard against a
concurrent assign. New test `buildEntries_offMainParserWalk_matchesDirectFeed`
confirms the parser-walk builder produces the same table as the direct feed +
skips a failed spine.

## Round 2 — clean

Verdict: **ship-as-is — no Critical/High/Medium findings.** Confirmed: (1) the M1
`.task` is race-free vs `.onChange` (idempotent build + re-check) and leak-free
(SwiftUI cancels `.task` on disappear); (2) the M2 strip genuinely runs off-main
via the `nonisolated static async` builder, Sendable-safe (pure value type +
`Entry: Sendable`); (3) the `openHostTask`/`onHostDisappear`/`readyNavigator`
extraction preserves the WI-5/6/8/11b open/close lifecycle behavior exactly.

## Clean areas (round 1)
- Offset mapping correct: boundary starts, separator-gap clamp (preceding spine
  f=1.0), negative→first f=0, past-end→last f=1.0, fraction always in 0...1 —
  covered by focused parameterized tests.
- Extraction-alignment EXACT: `buildEntries` uses `EPUBTextExtractor.stripHTML`
  (not the block-preserving variant), trims, skips empties, joins with the
  2-UTF-16 `"\n\n"` separator — matching `ReaderAICoordinator.loadBookTextContent`'s
  EPUB recipe; same parser + spine order (`bilingualSpineHrefs`).
- Href spaces handled: OPF-relative mapper entries resolve through the WI-9a
  `readiumLocator(fromVReader:spineHrefs:)` against `publication.readingOrder`.
- Throttle (`shouldFollow`): spine-change always follows; intra-spine drift > 0.08
  follows (forward or backward); no thrash on every word.
- Follow only when `tts.state == .speaking`; cursor resets on play start + on
  stop/idle (so the offset→0 reset on stop does not navigate-to-top).

## Notes
- `ReadiumEPUBHost.swift` is 323 lines (~300 budget; was 300). The +23 is the
  genuine cost of a new concern whose 2 `@State` fields + param + wrap must touch
  the struct; the logic is fully extracted to `+TTSFollow`. Further reduction would
  require touching unrelated WI-9a nav observers (drive-by) — accepted as Low.
- Codex's local `swift -e` compiler probe failed under the read-only sandbox
  (no /tmp cache write); the `nonisolated static async` validity was instead
  confirmed by the worktree's full `xcodebuild build` (BUILD SUCCEEDED).
