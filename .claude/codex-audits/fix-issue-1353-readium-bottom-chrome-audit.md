---
branch: fix/issue-1353-readium-bottom-chrome
threadId: codex-exec-gpt-5.4
rounds: 2
final_verdict: ship-as-is
date: 2026-06-02
---

# Codex audit — Bug #299 (mount bottom chrome on the Readium EPUB host)

Runner: cc-suite via `scripts/run-codex.sh` (watchdog — SUCCEEDED, no ghost),
gpt-5.4, high, read-only. Codex confirmed no concurrency / off-by-one issue.

## Round 1: NEEDS ATTENTION (2 Medium + 2 Low) → all fixed in round 2

| file | sev | issue | resolution |
|---|---|---|---|
| +BottomChrome.swift | Medium | Display used Readium's exact `totalProgression` but seek used equal-weight slices → not inverses, so a drag to "50%" could snap on uneven-chapter books. | **FIXED.** Display now uses the SAME equal-weight model: the relocate locator is resolved to its spine index via the host's proven `currentVReaderLocator` normalization, then `ReadiumBottomChromeSeek.progress(index:intra:)` — the exact inverse of the seek's `target(fraction:)`. Round-trip proven by `displaySeekRoundTrip` (every fraction × spine count). Falls back to `totalProgression` only if the spine match is unavailable. |
| ReadiumEPUBHost.swift | Medium | Bottom chrome showed whenever `isChromeVisible`, unlike other hosts (suppressed while loading/error + while TTS active) → empty chrome over ProgressView, overlap with the parent TTSControlBar. | **FIXED.** New `isBottomChromeVisible` gate = ready + chrome-visible + TTS-idle (`(ttsService?.state ?? .idle) == .idle`), matching the legacy `EPUBReaderContainerView.bottomOverlay` gate. Tested via `shouldShow`. |
| ReaderContainerView.swift:1016 | Low | The `.epubReadium` fallback call site relied on the default `isChromeVisible = true`. | **FIXED.** Now forwards `isChromeVisible` (both call sites). |
| ReadiumBottomChromeSeekTests | Low | Tests covered only the pure fraction→(index,intra) math. | **FIXED.** Added `displaySeekRoundTrip` (M1 consistency) + `visibilityGate` (M2). 8 tests total. |

## Verification

Build SUCCEEDED; 8 seek/gate tests green; device-verified twice on iPhone 17 Pro
Sim — the Readium EPUB shows the scrubber (Chapter Two | 50%, equal-weight) +
the Contents/Notes/Display/AI toolbar (artifact bug-299-...png).

ship-as-is.
