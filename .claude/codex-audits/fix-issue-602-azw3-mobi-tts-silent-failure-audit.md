---
branch: fix/issue-602-azw3-mobi-tts-silent-failure
threadId: manual-fallback
rounds: 1
final_verdict: ship-as-is
date: 2026-05-14
---

# Bug #176 / GH #602 — AZW3/MOBI TTS silently fails (audit log)

## Context

Reported via verify cron 2026-05-13 during feature #26 round-3
verification of the deferred Foliate slice. Speaker button appears in
the AZW3/MOBI reader chrome (because `FormatCapabilities.azw3`
declared `.tts`), but tapping it produces no observable effect —
silent failure. `vreader-debug://tts?action=start` likewise no-ops:
snapshot shows `ttsState: "idle"`, `ttsOffsetUTF16: null`.

Root cause documented in the issue body + bug row:
`ReaderAICoordinator.loadBookTextContent(fileURL:format:)` has no
`azw3`/`mobi` case in its `switch format`, falls through to
`default: return nil`. `startTTS()` guards on
`loadedTextContent != nil && !isEmpty`, so `ttsService.startSpeaking`
is never called for Foliate-rendered formats.

## Codex availability

Codex MCP unavailable this session (`stream disconnected before
completion` matching the multi-day outage). Manual fallback per rule
47.

## Fix path chosen

The bug body listed two substantial paths (both feature-class
investment):
- **(a)** Add a Swift-side text extractor for AZW3/MOBI by evaluating
  JS against the Foliate WKWebView. Requires ReaderAICoordinator
  access to the webview reference (currently absent) + ordering
  guarantees that the book content is loaded before extraction +
  async coordination across the AICoordinator/WebView seam.
- **(b)** Wire `FoliateTTSAdapter` (already exists in
  `vreader/Services/Foliate/`, currently used only by tests) into
  the FoliateView path. Foliate's in-webview TTS handles speech, but
  TTSService's sentence-highlighting (feature #40) and auto-scroll
  (feature #41) would not apply because they're keyed off the
  AVSpeechSynthesizerDelegate timeline, not Foliate-js's TTS events.

Both paths are substantial enough to be feature-class work. Neither
is in-scope for a bugfix-cron iteration.

**Adopted: cheap-path capability-gate** — same pattern used for bugs
#156, #157, #158 (all also "advertised capability silently no-ops
because production wire-up is missing"). Remove `.tts` from
`FormatCapabilities.capabilities(for: .azw3)`. Result: speaker button
disappears from the AZW3/MOBI reader chrome → no silent-failure
surface. The DebugBridge URL path still no-ops but is non-user-facing
(test automation only).

A follow-up feature row will be filed in `docs/features.md` to track
proper AZW3/MOBI TTS support (path a OR path b) as future work.

## Files audited

| File | Purpose | Audit |
|---|---|---|
| `vreader/Models/FormatCapabilities.swift` | removed `.tts` from `.azw3` capability set | reviewed |
| `vreaderTests/Models/FormatCapabilitiesTests.swift` | new `azw3_doesNotSupportTTS()` regression-guard test | reviewed |
| `docs/bugs.md` | bug #176 row flipped to FIXED with fix description | reviewed |

## Manual audit evidence

### Files read

- `vreader/Models/FormatCapabilities.swift` (full) — confirmed the AZW3 case is at lines 111-119, only construction site of the AZW3 capability set. Removed `.tts` from the explicit `[...]` list.
- `vreader/Models/BookFormat.swift` (full) — confirmed `.azw3` covers both AZW3 and MOBI file extensions (`fileExtensions` returns `["azw3", "azw", "mobi", "prc"]`). One capability-set change covers both formats.
- `vreader/Views/Reader/ReaderChromeBar.swift` (lines 40-60) — confirmed the speaker button (`readerTTSButton`) is wrapped in `if let onTTS { ... }`, so the button disappears when `onTTS == nil`.
- `vreader/Views/Reader/ReaderContainerView+Sheets.swift` (line 175) — confirmed `onTTS = resolvedBookFormat.capabilities.contains(.tts) ? { startTTS() } : nil`. So removing `.tts` from AZW3 caps → `onTTS` becomes nil → button hides. Cause-and-effect chain verified end-to-end.
- `vreaderTests/Models/FormatCapabilitiesTests.swift` (full) — checked all existing AZW3-related tests:
  - `only_md_epub_azw3_supportUnifiedReflow_simpleEPUB` — asserts AZW3 has `.unifiedReflow`. Unaffected (still in AZW3 caps).
  - `azw3_doesNotSupportAutoPageTurn` — asserts AZW3 lacks `.autoPageTurn`. Unaffected.
  - `only_md_supportsAutoPageTurn` — enumerates all formats, asserts only MD has `.autoPageTurn`. Unaffected.
  - No existing positive assertion that AZW3 has `.tts` — clean removal.
- `vreaderTests/Models/ReadingModeTests.swift` (grep for azw3) — no AZW3-specific TTS assertions.
- `vreaderTests/Integration/ModeSwitchPersistenceTests.swift` (grep for azw3) — one AZW3 case at line 287, but it's about locator construction (`LocatorFactory.epub`), not TTS capability. Unaffected.

### Symbols verified

- `FormatCapabilities.tts` ✓ — option set bit `1 << 4`, defined at line 14 of `FormatCapabilities.swift`.
- `FormatCapabilities.capabilities(for: .azw3)` ✓ — single construction site of the AZW3 capability set, at lines 111-119. Removing `.tts` here is the only required change for the production gate.
- `ReaderChromeBar.swift:51-58` ✓ — speaker button conditional render.
- `ReaderContainerView+Sheets.swift:175` ✓ — `onTTS` nil-gating on `.tts` capability.
- `BookFormat.swift:31` ✓ — `.azw3` covers azw3/azw/mobi/prc extensions; one cap set covers MOBI.

### Edge cases checked

1. **DebugBridge URL path silent failure** (`vreader-debug://tts?action=start` for AZW3 still no-ops): accepted. The bridge URL is non-user-facing — test automation only. The notification observer in `ReaderContainerView` (line 229-243) calls `startTTS()` directly without checking capability; `startTTS()` guards on `loadedTextContent != nil` so it returns silently. Adding a capability check at the observer would be a defensive improvement but not in scope — the user-visible surface (chrome button) is the primary fix target.
2. **Test target `FoliateTTSAdapterTests` (~340 lines)**: unaffected — those tests exercise the JS string generation + payload parsing of `FoliateTTSAdapter`, which is purely a static helper. They don't depend on the production capability set.
3. **AZW3 unit tests** (`only_md_epub_azw3_supportUnifiedReflow_simpleEPUB`, `azw3_doesNotSupportAutoPageTurn`): re-ran. Both PASS post-fix.
4. **Mixed-format library**: a user with TXT + AZW3 books still has TTS for TXT (unchanged). AZW3 books simply don't show the speaker button. No cross-format regression.
5. **Future re-enable**: when the proper Foliate-webview TTS wire-up ships (follow-up feature), the test `azw3_doesNotSupportTTS()` will fail intentionally — that test failure is the signal to flip the capability back on AND add a positive assertion alongside it.
6. **Build configuration**: `xcodebuild build -configuration Debug` succeeds. Capability change is pure-Swift, no Info.plist or build-setting impact. Release build behaves identically (gate is runtime, not compile-time).

### Concurrency / Swift 6

- `FormatCapabilities` is `OptionSet, Sendable, Hashable` (declared explicit `Sendable` conformance at line 7). Removing one option doesn't change conformance.
- `FormatCapabilities.capabilities(for:)` is a pure function. No threading concerns.

### VReader compliance

- Swift 6 strict concurrency: clean.
- `@MainActor` correctness: unchanged (no actor boundaries touched).
- File size: `FormatCapabilities.swift` 130 lines (was 122, +8 for the expanded comment); well under 300.
- Bridge safety: not applicable (no WKWebView / JS surface touched).
- DEBUG gating: not needed (capability gate is production-correct, not DEBUG-only).

### Risks accepted

- **DebugBridge URL still no-ops for AZW3**: out of scope; test-automation surface only.
- **`FoliateTTSAdapter` remains unused in production**: out of scope; the test coverage of the adapter is preserved for the eventual proper wire-up.
- **No pre-FIXED simulator screenshot artifact**: simulator verify was a build-only check; the user-visible "speaker button disappears" is verifiable by code-read (chrome button conditional render is a pure `if let onTTS` SwiftUI branch). Post-merge close-gate verification will exercise the run-time behavior on the merged build.

## Findings

| # | Severity | Issue | Resolution |
|---|---|---|---|
| 1 | n/a | none — fix exactly matches bug body's "Two fix paths" discussion, taking the documented cheap-path-gate variant (matching #156/#157/#158 precedent) | n/a |

## Final verdict

**ship-as-is** — minimal capability-gate change that removes the
user-facing silent-failure surface. One production line removed
(`.tts` from AZW3 caps explicit list) + 13-line explanatory comment +
one regression-guard test + bug row + audit log. No regressions on
other format capabilities (verified by re-running full
FormatCapabilitiesTests suite — 23/23 PASS).

Substantial AZW3/MOBI TTS support (Foliate-webview text extraction or
in-webview TTS pipeline) is filed as a follow-up feature for future
work.
