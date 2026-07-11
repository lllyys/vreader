---
title: Module — text mapping
updated: 2026-07-10
status: verified
---

# Module — text mapping

## Purpose

Offset-tracked text transformation: when display text differs from source text (content replacement rules, Simplified↔Traditional Chinese conversion), this layer produces both the transformed text and a bidirectional `OffsetMap` capable of converting highlights, saved positions, and search ranges between source and display UTF-16 coordinates. In practice this is a set of mapping **primitives, not an end-to-end wired seam**: `OffsetMap.sourceToDisplay`/`displayToSource`/`sourceRangeToDisplay`/`displayRangeToSource` have essentially no production call sites outside `OffsetMap`'s own `compose(with:)` logic. The live TXT paths call `TextMapper.apply` and keep only `.text`, discarding the returned `offsetMap`; the MD pipeline does the same and persists positions in rendered (display) coordinates with no mapping back to source; `ReaderUnifiedCoordinator` stores an `offsetMap` that no production consumer reads. Highlights/positions/search anchored in source coordinates are not actually round-tripped through this layer today.

## Key files and types

- `vreader/Services/TextMapping/TextTransform.swift` — `protocol TextTransform: Sendable { func transform(input: String) -> TransformResult }` and `struct TransformResult { let text: String; let offsetMap: OffsetMap }`.
- `vreader/Services/TextMapping/TextMapper.swift` — `TextMapper.apply(transforms:to:)`: applies transforms left-to-right, composing each step's `OffsetMap` via `compose(with:)`; an empty transform list returns `OffsetMap.identity(lengthUTF16:)`.
- `vreader/Services/TextMapping/OffsetMap.swift` — `struct OffsetMap: Sendable, Equatable` holding sorted `OffsetEntry` values (`sourceOffset`, `displayOffset`, `sourceLength`, `displayLength` — one entry per divergence point). `sourceToDisplay(_:)` / `displayToSource(_:)` binary-search the last entry at or before the offset; offsets inside a replaced region map proportionally (`offsetInSource * displayLength / sourceLength`); offsets after an entry shift by the accumulated delta. `sourceRangeToDisplay` / `displayRangeToSource` convert ranges; `compose(with:)` chains two maps (source→intermediate→display), remapping self's entries through the other map and importing the other's entries that fall in untouched regions.
- `vreader/Services/TextMapping/ReplacementTransform.swift` — `struct ReplacementTransform: TextTransform` over `[ReplacementRuleDescriptor]` (`pattern`, `replacement`, `isRegex`, `enabled`, `order` — a value type decoupled from the SwiftData `ContentReplacementRule` so the transform is testable without persistence). Rules are filtered to enabled and sorted by `order`; each rule's result composes into the running map. String rules walk `range(of:)` matches; regex rules use `NSRegularExpression` with `regex.replacementString(for:in:offset:template:)` for capture-group templates. Bug #217: regex matching now runs synchronously on the calling thread — the prior `DispatchQueue.global()` + 1-second `DispatchSemaphore` timeout misfired under dispatch-pool saturation and silently dropped the rule.
- `vreader/Services/TextMapping/SimpTradTransform.swift` — `struct SimpTradTransform: TextTransform` with `enum ChineseConversionDirection { case simpToTrad, tradToSimp, none }`. Uses ICU via `CFStringTransform` with transform ID `"Hans-Hant"` (`reverse = true` for trad→simp; an inline comment notes `kCFStringTransformMandarinLatin` is NOT correct for this). `buildOffsetMap(source:display:)` compares character-by-character, emitting an `OffsetEntry` only where the character or its UTF-16 length differs — CJK simp↔trad is 1:1 in UTF-16 for most cases.
- `vreader/Services/TextMapping/SimpTradDictionary.swift` — 30 verification pairs (国/國, 学/學, …) used as test/verification reference; ICU is the actual conversion engine.

## Consumers and data flow

- **MD open pipeline**: `vreader/Services/MD/MDFileLoader.swift` builds `[ReplacementTransform, SimpTradTransform]` (in that fixed order — replacement rules must see the pre-conversion text) and runs `TextMapper.apply` on the decoded source BEFORE Markdown parsing (feature #54 WI-7, bug #178 / GH #606).
- **TXT chapter/raw display**: `vreader/Views/Reader/TXTReaderContainerView.swift` (lines 622, 637, 682, 708) and `vreader/Views/Reader/TXTChunkedReaderBridge.swift:133` apply `TextMapper.apply(transforms: [SimpTradTransform(direction:)], to:)` to chapter or raw text when Chinese conversion is on.
- **Unified reflow engine**: `vreader/Views/Reader/ReaderUnifiedCoordinator.swift` holds `activeTransforms: [any TextTransform]` with a `didSet` that re-applies transforms to the stored `sourceText` (bug #98) and stores the resulting `offsetMap` for highlight/search mapping — though no production code currently reads that stored `offsetMap` back out (see Purpose). Edge case/bug: `applyTransforms` early-returns the source text unchanged when `activeTransforms` becomes empty, but does NOT reset `offsetMap` to identity — a map left over from the previous nonempty transform chain goes stale in place.

Related but distinct offset layers: `TXTOffsetTranslator` / `TXTChapterOffsetIndex` (global↔chapter-local, no text rewriting — see [[Module — TXT reader]]) and `BilingualDisplaySegmentMap` (feature #56 WI-12b interleaved-translation display offsets — see [[Module — bilingual translation]]).

## Concurrency

Everything in `vreader/Services/TextMapping/` is a `Sendable` value type or pure function — no actors, no `@MainActor`, callable from `Task.detached` (as `MDFileLoader` does) or from the main actor (as the TXT container does).

## Edge cases and invariants

- Empty transform list, empty input, empty pattern, `direction == .none`, invalid regex, or a failed `CFStringTransform` all degrade to identity — text unchanged, `OffsetMap.identity`, never a crash or a throw.
- Replacements are non-recursive: a replacement's output is not re-scanned by the same rule (string rules continue from `range.upperBound`).
- All lengths/offsets are UTF-16 code units (`utf16.count` / `NSString.length`), matching the reader stack's coordinate convention.
- Offsets inside a replaced region are proportionally interpolated, so a display offset mid-replacement maps to a plausible source position rather than clamping to the region edge (unless either side has zero length, where it clamps to the region start).
- `OffsetMap.init` re-sorts entries by `sourceOffset`, so callers need not pre-sort.
- `ReplacementTransform` sorts by `order` defensively even though `MDReplacementRuleFetcher` already sorts at fetch time.

## ChunkTextMapper (Android counterpart — not an iOS type)

`ChunkTextMapper` does not exist in the iOS codebase. It is the Android port's format-aware rendered↔source mapper from feature #125 (GH #1847, VERIFIED 2026-06-29 in `android/v0.13.0`): `android/app/src/main/kotlin/com/vreader/app/reader/ChunkTextMapper.kt` and `MarkdownOffsetMap.kt` (tests under `android/app/src/test/kotlin/com/vreader/app/reader/`), with `IdentityChunkTextMapper` for TXT and `MarkdownChunkTextMapper` for MD, threaded through the Android selection engine. It solves for Android MD the same class of problem `OffsetMap` solves on iOS (rendered-vs-source coordinates), but per-chunk with dual-affinity per-character source spans; the designs are independent implementations bound by the shared locator contracts. See [[Module — Android port]] and [[Module — cross-platform contracts]].

## History

Bug #98 (transform changes after load must re-apply to stored source text — `ReaderUnifiedCoordinator.reapplyTransforms`); bug #217 (semaphore-timeout regex path silently no-op'd under load — replaced with synchronous matching); bug #178 / GH #606 (Chinese conversion for MD via this chain); feature #54 WI-7 (replacement rules wired into the native MD pipeline); feature #125 (Android `ChunkTextMapper`/`MarkdownOffsetMap` analog). See [[Timeline — bug history and recurring classes]].

**Sources.** [[session 014jggU2u3f3t6YRoPLS457u · 2026-07-10]] · [[session 014jggU2u3f3t6YRoPLS457u-audit · 2026-07-11]]

**Verified.** 2026-07-11 — checked against: vreader/Services/TextMapping/TextTransform.swift, vreader/Services/TextMapping/TextMapper.swift, vreader/Services/TextMapping/OffsetMap.swift, vreader/Services/TextMapping/ReplacementTransform.swift, vreader/Services/TextMapping/SimpTradTransform.swift, vreader/Services/TextMapping/SimpTradDictionary.swift, vreader/Services/MD/MDFileLoader.swift, vreader/Services/MD/MDReplacementRuleFetcher.swift, vreader/Views/Reader/TXTReaderContainerView.swift, vreader/Views/Reader/TXTChunkedReaderBridge.swift, vreader/Views/Reader/ReaderUnifiedCoordinator.swift, vreader/Services/TXT/TXTOffsetTranslator.swift, vreader/Services/TXT/TXTChapterOffsetIndex.swift, vreader/Services/Reader/BilingualDisplaySegmentMap.swift, vreader/Models/ContentReplacementRule.swift, android/app/src/main/kotlin/com/vreader/app/reader/ChunkTextMapper.kt, android/app/src/main/kotlin/com/vreader/app/reader/MarkdownOffsetMap.kt, android/app/src/test/kotlin/com/vreader/app/reader/ChunkTextMapperTest.kt, android/app/src/test/kotlin/com/vreader/app/reader/MarkdownOffsetMapTest.kt, docs/bugs.md, docs/features.md, archive/bugs-history.md, canon/modules/txt-reader.md, canon/modules/bilingual-translation.md, canon/modules/android-port.md, canon/modules/contracts.md, canon/timeline/bug-history.md, dev-docs/plans/20260519-feature-56-bilingual-reading.md.
