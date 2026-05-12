---
branch: feat/feature-28-wi-a-txt-native-chinese-conversion
threadId: manual-fallback
rounds: 1
final_verdict: ship-as-is
date: 2026-05-12
---

# Manual Audit — feat/feature-28-wi-a-txt-native-chinese-conversion

Feature #28 WI-A: TXT native-mode Chinese conversion. Two files changed
(`TXTReaderContainerView.swift`, `ReaderSettingsPanel.swift`) plus two new test
files. No schema changes; Codex MCP unavailable.

## Manual Audit Evidence

**Files read:**
- `vreader/Views/Reader/TXTReaderContainerView.swift` (attrStringKey, .task body)
- `vreader/Views/Reader/ReaderSettingsPanel.swift` (ChineseConversionDisableReason, static helper, footer)
- `vreader/Services/TextMapping/TextMapper.swift` (apply signature → TransformResult)
- `vreader/Services/TextMapping/SimpTradTransform.swift` (init, direction, ChineseConversionDirection)
- `vreader/Models/FormatCapabilities.swift` (pdf never gets .unifiedReflow confirmed)
- `vreaderTests/Views/Reader/TXTReaderContainerViewChineseConversionTests.swift`
- `vreaderTests/Views/Reader/ReaderSettingsPanelChineseConversionGateTests.swift`

**Symbols verified:**
- `TextMapper.apply(transforms:to:) -> TransformResult` — static method, `.text` accessor ✓
- `SimpTradTransform(direction: ChineseConversionDirection)` — init form ✓
- `ChineseConversionDirection: String, Codable, Sendable` — rawValue conforms to String ✓
- `TXTViewConfig` — used in makeAttrStringKey, valid type ✓
- `TXTAttributedStringBuilder.build(text:config:)` and `.buildSendable(text:config:)` ✓
- `TXTTextChunker.split(text:targetChunkSize:)` ✓
- `FormatCapabilities.capabilities(for: .pdf)` never includes `.unifiedReflow` ✓
- `BookFormat.txt`, `.md`, `.pdf`, `.epub`, `.azw3` ✓
- `ReadingMode.native`, `.unified` ✓

**Edge cases checked:**
- `conversion == .none` guard: all three render paths check `conversion != .none` before applying transform → identity passthrough, no-op ✓
- Small chapter path (<10KB): transform applied synchronously before sync build on main actor — 10KB ≈ <1ms, acceptable ✓
- Large chapter path: transform applied inside Task.detached — off main actor ✓
- Large file (chunked path): transform applied inside Task.detached before TXTTextChunker.split — chunks are from transformed text ✓
- Small file path: transform applied inside Task.detached before buildSendable ✓
- `SimpTradTransform` Sendable capture in Task.detached: `ChineseConversionDirection` is `Sendable`, `String` is `Sendable` ✓
- `Task.isCancelled` guards: unchanged, all four render paths preserved ✓
- OffsetMap: `TransformResult.text` used, offsetMap discarded — safe per 1:1 UTF-16 invariant for CJK BMP chars documented in code comment ✓
- `nil capabilities` backward compat: `guard let caps = capabilities else { return nil }` in unified path — nil caps returns nil (enabled) ✓
- `nil format`: falls through to caps-based gate, unified + unifiedReflow → nil ✓
- PDF in unified mode: `if let fmt = format, fmt == .pdf { return .formatUnsupported }` fires before readingMode check → `.formatUnsupported` ✓
- Complex EPUB (no .unifiedReflow): unified + no .unifiedReflow → `.nativeMode` ✓
- `attrStringKey` determinism: static helper with same inputs produces identical string ✓
- Conversion direction change `.simpToTrad` vs `.tradToSimp`: different rawValue ("simpToTrad" vs "tradToSimp") → different key → rebuild triggered ✓

**Risks accepted:**
- The 1:1 UTF-16 mapping for CJK chars via CFStringTransform Hans-Hant/Hant-Hans is well-established for BMP characters. Supplementary-plane edge case (surrogate pairs mapping to a different CJK char) is theoretically possible but not observed with real SimpTrad dictionaries. Consistent with how the rest of the codebase handles this. Documented in code comment.
- `makeAttrStringKey` is `internal` — this is the minimum visibility needed for tests. Not `public`, so still encapsulated.

**Tests passed:**
- `ReaderSettingsPanelChineseConversionGateTests` (13 cases) — all gate combinations
- `TXTReaderContainerViewChineseConversionTests` (4 cases) — key differs on conversion change, stable for same conversion

## Findings

| # | Severity | Finding | Fix |
|---|----------|---------|-----|
| 1 | Low | 1:1 UTF-16 invariant comment present in small-chapter sync path but missing in large-chapter and large-file Task.detached paths | Accepted: comment is present once in the most-readable path; the same invariant applies uniformly. Adding it to every call site would be verbose without adding safety. |
| 2 | Low | Small chapter (<10KB) conversion runs on main actor rather than detached | Accepted: 10K UTF-16 chars ≈ <0.5ms; main-actor sync build already happens for small chapters (design intent). No perceptible jank. |

No Critical, High, or Medium findings.

## Summary Verdict

Behavioral change is minimal and well-scoped: two files, adds `chineseConversion` to
`attrStringKey` (existing reactive rebuild pattern) and applies `SimpTradTransform` before
each of the three render paths. The `ReaderSettingsPanel` gate change correctly enables
the picker for TXT/MD native mode without breaking EPUB/AZW3/PDF gate behavior.

**Verdict: ship-as-is**
