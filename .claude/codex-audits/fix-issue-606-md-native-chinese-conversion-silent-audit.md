---
branch: fix/issue-606-md-native-chinese-conversion-silent
threadId: manual-fallback
rounds: 1
final_verdict: ship-as-is
date: 2026-05-14
---

# Bug #178 / GH #606 — MD native mode Chinese conversion silent no-op (audit log)

## Context

`ReaderSettingsPanel.swift:513` enables the Chinese Conversion picker
for TXT or MD format, but only TXT actually wires
`SimpTradTransform` into its render pipeline (Feature #28 WI-A).
`MDReaderContainerView` + `MDReaderViewModel` + `MDFileLoader` never
read `settingsStore.chineseConversion` and never call
`TextMapper.apply`, so toggling the picker for an MD book changes a
UserDefaults value but renders nothing differently — silent no-op.

## Codex availability

Codex MCP unavailable this session. Manual fallback per rule 47.

## Fix

Applied `SimpTradTransform` at the source-text seam in
`MDFileLoader.load`, BEFORE Markdown parsing — the same architectural
location TXT applies it at (TXTReaderContainerView's
`.task(id: attrStringKey)` body). Threaded through as a default-`.none`
parameter so call sites that don't care compile unchanged.

Live re-apply on toggle: DEFERRED. TXT supports live re-apply because
its attributed-string rebuild is fast against in-memory text. MD's
re-apply would require a close+reopen cycle (re-read file, re-decode,
re-transform, re-parse, re-render — typical 50-500ms). The bug as
filed is "silently no-ops" — the user-visible silent-noop is closed
by open-time application; full live re-apply is a separate
enhancement.

## Files audited

| File | Purpose | Audit |
|---|---|---|
| `vreader/Services/MD/MDFileLoader.swift` | `chineseConversion` param + transform application | reviewed |
| `vreader/ViewModels/MDReaderViewModel.swift` | `chineseConversion` param forwarded to MDFileLoader.load | reviewed |
| `vreader/Views/Reader/MDReaderContainerView.swift` | `.task` call site passes `settingsStore?.chineseConversion ?? .none` | reviewed |
| `vreaderTests/Services/MD/MDFileLoaderTests.swift` | 3 new regression-guard tests | reviewed |

## Manual audit evidence

### Files read

- `vreader/Services/MD/MDFileLoader.swift` (full) — confirmed `load(url:parser:positionStore:bookFingerprintKey:)` signature; the `Task.detached` inside reads `Data(contentsOf:)`, runs `EncodingDetector.detect`, then `parser.parse(text:config:)`. The transform fits cleanly between encoding-detect and parser-call.
- `vreader/ViewModels/MDReaderViewModel.swift` (full) — confirmed `open(url:)` signature; only one call site (`MDReaderContainerView.task`); adding a defaulted `chineseConversion: ChineseConversionDirection = .none` parameter doesn't break existing callers.
- `vreader/Views/Reader/MDReaderContainerView.swift` (lines 99-104, 181-200) — confirmed `.task` is the only place `viewModel.open` is called; `settingsStore?.chineseConversion ?? .none` is the right value to pass. `.onChange` modifiers for layout/fontSize/autoPageTurn exist but no equivalent for chineseConversion — explicitly NOT adding one (live re-apply deferred).
- `vreader/Views/Reader/ReaderFormatHosts.swift` (line 86-119) — confirmed `MDReaderHost` constructs the viewmodel but does NOT call `open()`; no change needed there.
- `vreader/Views/Reader/TXTReaderContainerView.swift` (lines 261-336) — confirmed TXT's pattern: reads `settingsStore?.chineseConversion ?? .none` inside `.task(id: attrStringKey)`, applies `TextMapper.apply(transforms: [SimpTradTransform(direction: conversion)], to: text).text`. The MD fix mirrors this at the equivalent source-text seam (`MDFileLoader.load` before parse, vs TXT's in-memory text-to-attributed-string rebuild).
- `vreader/Services/TextMapping/SimpTradTransform.swift` (lines 15-49) — confirmed `ChineseConversionDirection` enum cases (`simpToTrad`, `tradToSimp`, `none`); confirmed transform is a no-op when `.none` or input empty; confirmed ICU `Hans-Hant` transform name for both directions (reverse flag flips it).
- `vreader/Services/MD/MDParser.swift` (head, grep for `parse`) — confirmed `parse(text:config:)` is the parser entry point that accepts a String; the transform happens BEFORE this call, so parser sees the converted text and renders it normally.
- `vreaderTests/Services/MD/MockMDParser.swift` (full) — confirmed `lastParsedText` tracking enables the new tests to assert the transformed text reaches the parser.

### Symbols verified

- `MDFileLoader.load(...)` ✓ — backward-compatible signature extension with default-`.none` parameter.
- `MDReaderViewModel.open(url:chineseConversion:)` ✓ — defaulted param; existing `viewModel.open(url:)` calls in test code continue to work.
- `MDReaderContainerView.task` ✓ — only production caller of `viewModel.open`; passes `settingsStore?.chineseConversion ?? .none`.
- `TextMapper.apply(transforms:to:)` returns `(text: String, offsetMap: OffsetMap)` ✓ — same signature TXT uses.
- `SimpTradTransform(direction:)` ✓ — value type, Sendable.
- `Task.detached` body remains Sendable-clean: `chineseConversion` is `Sendable` (enum), `parser` is `any MDParserProtocol`-existential captured by the closure (existing behavior).

### Edge cases checked

1. **`.none` default**: no behavior change for existing callers. `MDFileLoader.load(...)` without the new parameter behaves identically to pre-fix. Verified by `loadWithoutConversionPreservesText` test.
2. **`.simpToTrad` with non-CJK text**: SimpTradTransform's ICU `Hans-Hant` mapping is identity for non-CJK chars. Markdown structure characters (`#`, `*`, `-`, `[`, `]`, etc.) all pass through unchanged. Test asserts `"# "` heading marker preservation.
3. **`.simpToTrad` with empty file**: SimpTradTransform's `guard !input.isEmpty` early-return preserves empty input. `MDFileLoader.load` with empty file then parses empty text. Existing `load handles empty document` test still passes.
4. **Live toggle while reader open**: NOT supported this iteration. User must close and reopen the book. Documented limitation in plan section.
5. **UTF-16 offset alignment**: SimpTradTransform's Hans-Hant mapping is 1:1 UTF-16 for BMP CJK chars (per TXTReaderContainerView's existing comment). Saved positions in source-text coordinates remain valid across a conversion change — opening a Simp book that was previously read as Trad lands at the same UTF-16 offset.
6. **MD parser robustness on transformed text**: ICU Hans-Hant produces valid UTF-8 / String values. MDParser sees a valid String, parses normally. No structural breakage.
7. **EncodingDetector ordering**: transform runs AFTER `EncodingDetector.detect(data:)` returns `result.text`. Detection works against raw bytes; transform works against decoded String. Correct ordering.
8. **`chineseConversion` propagation from settingsStore**: `MDReaderContainerView` declares `var settingsStore: ReaderSettingsStore?` (optional). `settingsStore?.chineseConversion ?? .none` is the safe fallback when settings haven't loaded. Matches TXT pattern.

### Concurrency / Swift 6

- `ChineseConversionDirection` is `Sendable` (per the enum declaration in `SimpTradTransform.swift`).
- The new parameter is captured by the `Task.detached` closure in `MDFileLoader.load` — Sendable-clean (value-type enum).
- `TextMapper.apply` is a pure function (no actor). Safe to call from any context.
- No new `@unchecked Sendable` or `nonisolated(unsafe)` markers needed.

### VReader compliance

- Swift 6 strict concurrency: clean (`SWIFT_STRICT_CONCURRENCY: complete`).
- `@MainActor` correctness: SwiftUI views and TTSService stay MainActor; the transform runs inside `Task.detached` so it's off MainActor. UI thread unaffected by the additional work.
- File size: `MDFileLoader.swift` grew from 80 → 98 lines (+18 for the conditional transform branch + docstring). `MDReaderViewModel.swift` grew by ~5 lines (parameter forwarding + docstring). `MDReaderContainerView.swift` grew by ~6 lines (call-site update + docstring). All under 300.
- Bridge safety: not applicable (no WKWebView / JS).
- DEBUG gating: not applicable (production-correct).

### Risks accepted

- **Live re-apply deferred**: TXT supports it; MD requires close+reopen this iteration. User-visible "silent noop" symptom is closed; live re-apply is a separate enhancement that requires viewmodel state restructuring (cache raw source, observe settingsStore.chineseConversion, trigger re-parse). Filed as a documented limitation.
- **Position alignment under transform**: SimpTradTransform is 1:1 UTF-16 for BMP CJK chars (the dominant case). Edge case: supplementary-plane CJK chars (CJK Extension B+, encoded as surrogate pairs) may have non-1:1 mappings. Same caveat applies to TXT; accepted.
- **Performance**: SimpTradTransform on a 100KB MD file adds maybe 5-20ms (ICU is fast). Inside `Task.detached`, doesn't affect UI thread. Acceptable.

### Tests added or intentionally deferred

- 3 new tests in `MDFileLoaderTests`: `loadWithoutConversionPreservesText`, `loadAppliesSimpToTradConversion`, `loadAppliesTradToSimpConversion`. All PASS.
- No XCUITest UI test added — the conversion is observable via the existing settings panel; manual device-verification will exercise the UI path during close-gate (`awaiting-device-verification` label).

## Findings

| # | Severity | Issue | Resolution |
|---|---|---|---|
| 1 | n/a | none — implementation matches bug body's "Fix: mirror TXT's SimpTradTransform pattern in MD render paths" exactly, with the explicit deferral of live re-apply (TXT's `.task(id:)` re-trigger) documented as a known limitation | n/a |

## Final verdict

**ship-as-is** — small, focused fix at the source-text seam. 10/10
MDFileLoader tests pass (7 existing + 3 new). Build clean. Live
re-apply is a documented deferral, not a bug — the user-visible
silent-noop symptom is closed.
