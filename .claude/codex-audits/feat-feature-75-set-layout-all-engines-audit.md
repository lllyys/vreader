---
branch: feat/feature-75-set-layout-all-engines
threadId: codex-exec-gpt-5.5-20260601
rounds: 1
final_verdict: ship-as-is
date: 2026-06-01
---

# Codex Audit — Feature #75 set-layout generalization (dispatcher-level observer)

## Scope

Move the DEBUG-only `set-layout` observer (`.debugBridgeSetLayoutCommand`) from
the EPUB-specific host (`EPUBReaderContainerView`) UP to the dispatcher
(`ReaderContainerView`), so it reaches EVERY EPUB engine — legacy
`EPUBWebViewBridge` AND the now-default Readium `ReadiumEPUBHost` — via the
shared `settingsStore.epubLayout` (both hosts read it reactively). The old
host-scoped observer only mounted under the legacy engine, so `set-layout` never
reached the Readium host. Verified CU-free that the dispatcher observer fires.

Files:
- `vreader/Views/Reader/ReaderContainerView.swift` (+ `.modifier(ReaderDebugBridgeSetLayoutObserver…)`)
- `vreader/Views/Reader/ReaderContainerView+DebugBridgeSetLayout.swift` (NEW engine-agnostic ViewModifier)
- `vreader/Views/Reader/EPUBReaderContainerView.swift` (− the now-redundant host-scoped observer)
- `EPUBReaderContainerView+DebugBridgeSetLayout.swift` (deleted)

## Round 1 — findings

Codex (gpt-5.5, read-only). **1 Medium (fixed); rest clean.**

| # | file:line | sev | issue | resolution |
|---|---|---|---|---|
| 1 | ReaderContainerView.swift:~600 | Medium | The observer now mounts for EVERY format; a `set-layout` fired while TXT/MD/PDF/AZW3 is open would mutate `settingsStore.epubLayout` (which those formats also read) — broadening the prior EPUB-only behavior. | FIXED — guard the callback on `DocumentFingerprint(canonicalKey: book.fingerprintKey)?.format == .epub`. Both EPUB engines are `.epub`, so the goal (reaching the Readium host) is unaffected; non-EPUB readers no longer mutate `epubLayout`. |

Clean otherwise: removing the legacy host observer is safe (both EPUB paths get
the SAME `ReaderSettingsStore` instance from the dispatcher); DEBUG gating
preserved; no double-fire after deleting the old modifier; @MainActor correctness
OK (DebugBridge/RealDebugBridgeContext dispatch on `@MainActor`, matching
`ReaderSettingsStore`'s isolation).

## Test evidence

- `DebugCommandTests` + `RealDebugBridgeContextTests` + `DebugBridgeTests` +
  `ReaderContainerViewEngineDispatchTests` green.
- CU-free confirmation: the dispatcher observer fires on `set-layout?mode=paged`
  (log `WI75DISP set-layout observer fired`).

## Field note (#75 navigation)

This change makes `set-layout` reach the Readium host (verified), but vertical-rl
PAGE navigation still does not advance on Readium: `goForward` returns false for
the single-chapter vertical-rl fixture regardless of paged/scroll mode or the
OPF `page-progression-direction`. Combined with the legacy bridge's native
UIScrollView negative-`contentOffset` snap-back, vertical-rl page nav is a genuine
gap on BOTH engines (render works on both). Recorded in `docs/features.md` #75 +
task #302 as the next investigation (needs Readium-internals work or a real
multi-page vertical EPUB).

## Summary verdict

ship-as-is (1 Medium fixed).
